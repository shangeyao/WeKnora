package utils

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/url"
	"strings"
)

// DongjianSSOPayload is the JSON inside RSA-encrypted ssoToken from 洞鉴 portal.
type DongjianSSOPayload struct {
	ClientID string `json:"clientID"`
	Username string `json:"username"`
	Email    string `json:"email"`
	Name     string `json:"name"`
	Exp      int64  `json:"exp,omitempty"`
}

// ParseRSAPrivateKeyPEM loads an RSA private key from PEM text (env-friendly \n escapes supported).
func ParseRSAPrivateKeyPEM(pemText string) (*rsa.PrivateKey, error) {
	pemText = strings.TrimSpace(pemText)
	if pemText == "" {
		return nil, errors.New("RSA private key PEM is empty")
	}
	pemText = strings.ReplaceAll(pemText, `\n`, "\n")
	block, _ := pem.Decode([]byte(pemText))
	if block == nil {
		return nil, errors.New("invalid RSA private key PEM")
	}
	if key, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		if rsaKey, ok := key.(*rsa.PrivateKey); ok {
			return rsaKey, nil
		}
		return nil, errors.New("PEM is not an RSA private key")
	}
	if rsaKey, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return rsaKey, nil
	}
	return nil, errors.New("failed to parse RSA private key PEM")
}

// decodeURLSSOToken reverses URL encoding on ssoToken query values. Portal links
// often percent-encode base64 (+, /, =); some gateways also turn '+' into space.
func decodeURLSSOToken(token string) string {
	token = strings.TrimSpace(token)
	for i := 0; i < 3; i++ {
		decoded, err := url.PathUnescape(token)
		if err != nil || decoded == token {
			if decoded, err = url.QueryUnescape(token); err != nil || decoded == token {
				break
			}
		}
		token = decoded
	}
	if strings.Contains(token, " ") && !strings.Contains(token, "+") {
		token = strings.ReplaceAll(token, " ", "+")
	}
	return token
}

// DecryptRSACipherBase64 decrypts base64/base64url RSA ciphertext (PKCS#1 v1.5, OAEP-SHA256 fallback).
func DecryptRSACipherBase64(token string, privateKey *rsa.PrivateKey) ([]byte, error) {
	token = decodeURLSSOToken(token)
	if token == "" {
		return nil, errors.New("sso token is empty")
	}
	ciphertext, err := decodeFlexibleBase64(token)
	if err != nil {
		return nil, err
	}
	if plain, err := rsa.DecryptPKCS1v15(rand.Reader, privateKey, ciphertext); err == nil {
		return plain, nil
	}
	plain, err := rsa.DecryptOAEP(sha256.New(), rand.Reader, privateKey, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("RSA decrypt failed: %w", err)
	}
	return plain, nil
}

func decodeFlexibleBase64(s string) ([]byte, error) {
	for _, dec := range []func(string) ([]byte, error){
		base64.RawURLEncoding.DecodeString,
		base64.URLEncoding.DecodeString,
		base64.StdEncoding.DecodeString,
		base64.RawStdEncoding.DecodeString,
	} {
		if b, err := dec(s); err == nil {
			return b, nil
		}
	}
	return nil, errors.New("invalid base64 sso token")
}

// ParseDongjianSSOToken decrypts ssoToken and validates required fields.
func ParseDongjianSSOToken(token string, privateKey *rsa.PrivateKey, expectedClientID string) (*DongjianSSOPayload, error) {
	plaintext, err := DecryptRSACipherBase64(token, privateKey)
	if err != nil {
		return nil, err
	}
	var payload DongjianSSOPayload
	if err := json.Unmarshal(plaintext, &payload); err != nil {
		return nil, fmt.Errorf("invalid SSO JSON: %w", err)
	}
	payload.ClientID = strings.TrimSpace(payload.ClientID)
	payload.Username = strings.TrimSpace(payload.Username)
	payload.Email = NormalizeEmail(payload.Email)
	payload.Name = strings.TrimSpace(payload.Name)
	if payload.Email == "" {
		return nil, errors.New("SSO payload missing email")
	}
	if expectedClientID != "" && payload.ClientID != expectedClientID {
		return nil, errors.New("SSO clientID mismatch")
	}
	return &payload, nil
}
