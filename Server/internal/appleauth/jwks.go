package appleauth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"sync"
	"time"
)

// AppleKeysEndpoint is Apple's published JWKS location.
const AppleKeysEndpoint = "https://appleid.apple.com/auth/keys"

const (
	defaultKeyTTL      = time.Hour
	maxKeySetBodyBytes = 1 << 20
)

// KeyProvider resolves a signing key ID to the public key that must have
// signed the token.
type KeyProvider interface {
	Key(context.Context, string) (*rsa.PublicKey, error)
}

// KeyCache fetches and caches Apple's JWKS. An unseen key ID triggers at most
// one refetch, so key rotation is picked up without letting a bogus kid drive
// unbounded outbound requests.
type KeyCache struct {
	endpoint string
	client   *http.Client
	now      func() time.Time
	ttl      time.Duration

	mutex     sync.Mutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

func NewKeyCache(endpoint string, client *http.Client, now func() time.Time) *KeyCache {
	if endpoint == "" {
		endpoint = AppleKeysEndpoint
	}
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	if now == nil {
		now = time.Now
	}
	return &KeyCache{
		endpoint: endpoint,
		client:   client,
		now:      now,
		ttl:      defaultKeyTTL,
	}
}

func (c *KeyCache) Key(ctx context.Context, keyID string) (*rsa.PublicKey, error) {
	if keyID == "" {
		return nil, &Error{Reason: "unknownKey"}
	}

	c.mutex.Lock()
	defer c.mutex.Unlock()

	if key, fresh := c.cachedKey(keyID); fresh {
		return key, nil
	}
	if err := c.refresh(ctx); err != nil {
		return nil, err
	}
	if key, ok := c.keys[keyID]; ok {
		return key, nil
	}
	return nil, &Error{Reason: "unknownKey"}
}

// cachedKey reports a cached key only while the whole key set is still fresh.
func (c *KeyCache) cachedKey(keyID string) (*rsa.PublicKey, bool) {
	if c.keys == nil || c.now().Sub(c.fetchedAt) >= c.ttl {
		return nil, false
	}
	key, ok := c.keys[keyID]
	return key, ok
}

func (c *KeyCache) refresh(ctx context.Context) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, c.endpoint, nil)
	if err != nil {
		return &Error{Reason: "keyFetch", Err: err}
	}
	response, err := c.client.Do(request)
	if err != nil {
		return &Error{Reason: "keyFetch", Err: err}
	}
	defer func() { _ = response.Body.Close() }()

	if response.StatusCode != http.StatusOK {
		return &Error{Reason: "keyFetch", Err: fmt.Errorf("status %d", response.StatusCode)}
	}

	body, err := io.ReadAll(io.LimitReader(response.Body, maxKeySetBodyBytes))
	if err != nil {
		return &Error{Reason: "keyFetch", Err: err}
	}

	var keySet struct {
		Keys []struct {
			Kty string `json:"kty"`
			Kid string `json:"kid"`
			Alg string `json:"alg"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.Unmarshal(body, &keySet); err != nil {
		return &Error{Reason: "keyFetch", Err: err}
	}

	keys := make(map[string]*rsa.PublicKey, len(keySet.Keys))
	for _, key := range keySet.Keys {
		if key.Kty != "RSA" || key.Kid == "" {
			continue
		}
		if key.Alg != "" && key.Alg != "RS256" {
			continue
		}
		publicKey, err := decodeRSAPublicKey(key.N, key.E)
		if err != nil {
			continue
		}
		keys[key.Kid] = publicKey
	}
	if len(keys) == 0 {
		return &Error{Reason: "keyFetch", Err: fmt.Errorf("key set holds no usable RSA key")}
	}

	c.keys = keys
	c.fetchedAt = c.now()
	return nil
}

func decodeRSAPublicKey(modulus string, exponent string) (*rsa.PublicKey, error) {
	modulusBytes, err := base64.RawURLEncoding.DecodeString(modulus)
	if err != nil {
		return nil, fmt.Errorf("decode modulus: %w", err)
	}
	exponentBytes, err := base64.RawURLEncoding.DecodeString(exponent)
	if err != nil {
		return nil, fmt.Errorf("decode exponent: %w", err)
	}
	if len(modulusBytes) == 0 || len(exponentBytes) == 0 || len(exponentBytes) > 8 {
		return nil, fmt.Errorf("malformed RSA key material")
	}

	publicExponent := new(big.Int).SetBytes(exponentBytes)
	if !publicExponent.IsInt64() || publicExponent.Int64() > int64(^uint32(0)) {
		return nil, fmt.Errorf("unsupported RSA exponent")
	}
	return &rsa.PublicKey{
		N: new(big.Int).SetBytes(modulusBytes),
		E: int(publicExponent.Int64()),
	}, nil
}
