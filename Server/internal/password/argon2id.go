package password

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"io"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/text/unicode/norm"
)

const (
	defaultMemoryKiB     uint32 = 19_456
	defaultIterations    uint32 = 2
	defaultParallelism   uint8  = 1
	saltLength                  = 16
	keyLength            uint32 = 32
	minStoredSaltLength         = 16
	maxStoredSaltLength         = 32
	minStoredKeyLength          = 16
	maxStoredKeyLength          = 64
	maxStoredMemoryKiB   uint32 = 65_536
	maxStoredIterations  uint32 = 4
	maxStoredParallelism uint8  = 4
)

type Hasher struct {
	Random      io.Reader
	MemoryKiB   uint32
	Iterations  uint32
	Parallelism uint8
}

func NewHasher(random io.Reader) Hasher {
	return Hasher{Random: random}
}

func (h Hasher) parameters() (io.Reader, uint32, uint32, uint8) {
	random := h.Random
	if random == nil {
		random = rand.Reader
	}
	memory := h.MemoryKiB
	if memory == 0 {
		memory = defaultMemoryKiB
	}
	iterations := h.Iterations
	if iterations == 0 {
		iterations = defaultIterations
	}
	parallelism := h.Parallelism
	if parallelism == 0 {
		parallelism = defaultParallelism
	}
	return random, memory, iterations, parallelism
}

func (h Hasher) Hash(normalized string) (string, error) {
	random, memory, iterations, parallelism := h.parameters()
	salt := make([]byte, saltLength)
	if _, err := io.ReadFull(random, salt); err != nil {
		return "", fmt.Errorf("password: generate salt: %w", err)
	}
	key := argon2.IDKey([]byte(normalized), salt, iterations, memory, parallelism, keyLength)
	return fmt.Sprintf(
		"$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version,
		memory,
		iterations,
		parallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

func (h Hasher) Verify(phc, candidate string) (bool, bool, error) {
	parameters, salt, expected, err := parsePHC(phc)
	if err != nil {
		return false, false, err
	}
	actual := argon2.IDKey(
		[]byte(norm.NFC.String(candidate)),
		salt,
		parameters.iterations,
		parameters.memoryKiB,
		parameters.parallelism,
		uint32(len(expected)),
	)
	valid := subtle.ConstantTimeCompare(actual, expected) == 1
	if !valid {
		return false, false, nil
	}
	needsUpgrade := parameters.memoryKiB != defaultMemoryKiB ||
		parameters.iterations != defaultIterations ||
		parameters.parallelism != defaultParallelism ||
		len(salt) != saltLength ||
		len(expected) != int(keyLength)
	return true, needsUpgrade, nil
}

type phcParameters struct {
	memoryKiB   uint32
	iterations  uint32
	parallelism uint8
}

func parsePHC(phc string) (phcParameters, []byte, []byte, error) {
	parts := strings.Split(phc, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" || parts[2] != "v=19" {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	parameters, err := parseParameters(parts[3])
	if err != nil {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	if len(parts[4]) > base64.RawStdEncoding.EncodedLen(maxStoredSaltLength) ||
		len(parts[5]) > base64.RawStdEncoding.EncodedLen(maxStoredKeyLength) {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	salt, err := base64.RawStdEncoding.Strict().DecodeString(parts[4])
	if err != nil || len(salt) < minStoredSaltLength || len(salt) > maxStoredSaltLength {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	key, err := base64.RawStdEncoding.Strict().DecodeString(parts[5])
	if err != nil || len(key) < minStoredKeyLength || len(key) > maxStoredKeyLength {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	return parameters, salt, key, nil
}

func parseParameters(value string) (phcParameters, error) {
	fields := strings.Split(value, ",")
	if len(fields) != 3 {
		return phcParameters{}, &Error{Code: Invalid}
	}
	memory, err := parseParameter(fields[0], "m=", 32)
	if err != nil {
		return phcParameters{}, err
	}
	iterations, err := parseParameter(fields[1], "t=", 32)
	if err != nil {
		return phcParameters{}, err
	}
	parallelism, err := parseParameter(fields[2], "p=", 8)
	if err != nil {
		return phcParameters{}, err
	}
	parameters := phcParameters{
		memoryKiB:   uint32(memory),
		iterations:  uint32(iterations),
		parallelism: uint8(parallelism),
	}
	if parameters.parallelism < 1 || parameters.parallelism > maxStoredParallelism ||
		parameters.iterations < 1 || parameters.iterations > maxStoredIterations ||
		parameters.memoryKiB < 8*uint32(parameters.parallelism) ||
		parameters.memoryKiB > maxStoredMemoryKiB {
		return phcParameters{}, &Error{Code: Invalid}
	}
	return parameters, nil
}

func parseParameter(value, prefix string, bitSize int) (uint64, error) {
	number, found := strings.CutPrefix(value, prefix)
	if !found || number == "" {
		return 0, &Error{Code: Invalid}
	}
	parsed, err := strconv.ParseUint(number, 10, bitSize)
	if err != nil {
		return 0, &Error{Code: Invalid}
	}
	return parsed, nil
}
