package utils

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
)

// PortalSSOPayload is the JSON plaintext encrypted by the enterprise portal.
// The portal and WeKnora share PORTAL_SSO_AES_KEY (32 bytes).
type PortalSSOPayload struct {
	Email string `json:"email"`
	Name  string `json:"name"`
	Exp   int64  `json:"exp"`
}

// ParsePortalSSOKey accepts a raw 32-byte string or base64/base64url of 32 bytes.
func ParsePortalSSOKey(raw string) ([]byte, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, errors.New("portal SSO AES key is empty")
	}
	if len(raw) == 32 {
		return []byte(raw), nil
	}
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding, base64.RawURLEncoding, base64.URLEncoding} {
		if decoded, err := enc.DecodeString(raw); err == nil && len(decoded) == 32 {
			return decoded, nil
		}
	}
	return nil, errors.New("PORTAL_SSO_AES_KEY must be 32 bytes or base64 encoding of 32 bytes")
}

// DecryptPortalSSOToken decrypts AES-256-GCM ciphertext encoded as base64url(nonce||ciphertext).
func DecryptPortalSSOToken(token string, key []byte) ([]byte, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil, errors.New("portal SSO token is empty")
	}
	if len(key) != 32 {
		return nil, errors.New("portal SSO AES key must be 32 bytes")
	}

	data, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil {
		data, err = base64.URLEncoding.DecodeString(token)
		if err != nil {
			data, err = base64.StdEncoding.DecodeString(token)
			if err != nil {
				return nil, fmt.Errorf("invalid portal SSO token encoding: %w", err)
			}
		}
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(data) < aesgcm.NonceSize()+1 {
		return nil, errors.New("invalid portal SSO token: too short")
	}
	nonce, ciphertext := data[:aesgcm.NonceSize()], data[aesgcm.NonceSize():]
	plaintext, err := aesgcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("portal SSO token decrypt failed: %w", err)
	}
	return plaintext, nil
}

// ParsePortalSSOPayload decrypts and validates the portal token.
func ParsePortalSSOPayload(token string, key []byte, maxAge time.Duration) (*PortalSSOPayload, error) {
	plaintext, err := DecryptPortalSSOToken(token, key)
	if err != nil {
		return nil, err
	}

	var payload PortalSSOPayload
	if err := json.Unmarshal(plaintext, &payload); err != nil {
		return nil, fmt.Errorf("invalid portal SSO payload JSON: %w", err)
	}

	email := NormalizeEmail(payload.Email)
	if email == "" {
		return nil, errors.New("portal SSO payload missing email")
	}
	payload.Email = email
	payload.Name = strings.TrimSpace(payload.Name)

	if payload.Exp <= 0 {
		return nil, errors.New("portal SSO payload missing exp")
	}
	now := time.Now().Unix()
	if payload.Exp < now {
		return nil, errors.New("portal SSO token expired")
	}
	if maxAge > 0 {
		issuedAt := payload.Exp - int64(maxAge.Seconds())
		if issuedAt > now+30 {
			return nil, errors.New("portal SSO token exp is too far in the future")
		}
	}

	return &payload, nil
}

// EncryptPortalSSOToken encrypts payload JSON for portal-side token generation (tests / tooling).
func EncryptPortalSSOToken(payload []byte, key []byte) (string, error) {
	if len(key) != 32 {
		return "", errors.New("portal SSO AES key must be 32 bytes")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, aesgcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ciphertext := aesgcm.Seal(nil, nonce, payload, nil)
	combined := append(nonce, ciphertext...)
	return base64.RawURLEncoding.EncodeToString(combined), nil
}
