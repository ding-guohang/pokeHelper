package password

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"io"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/text/unicode/norm"
)

const (
	defaultMemoryKiB   uint32 = 19_456
	defaultIterations  uint32 = 2
	defaultParallelism uint8  = 1
	saltLength                = 16
	keyLength          uint32 = 32
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
	var parameters phcParameters
	if count, err := fmt.Sscanf(
		parts[3],
		"m=%d,t=%d,p=%d",
		&parameters.memoryKiB,
		&parameters.iterations,
		&parameters.parallelism,
	); err != nil || count != 3 ||
		parameters.memoryKiB == 0 || parameters.iterations == 0 || parameters.parallelism == 0 {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	salt, err := base64.RawStdEncoding.Strict().DecodeString(parts[4])
	if err != nil || len(salt) == 0 {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	key, err := base64.RawStdEncoding.Strict().DecodeString(parts[5])
	if err != nil || len(key) == 0 {
		return phcParameters{}, nil, nil, &Error{Code: Invalid}
	}
	return parameters, salt, key, nil
}
