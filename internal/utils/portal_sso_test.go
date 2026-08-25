package utils

import (
	"encoding/json"
	"testing"
	"time"
)

func TestPortalSSOTokenRoundTrip(t *testing.T) {
	key := []byte("0123456789abcdef0123456789abcdef")
	exp := time.Now().Add(5 * time.Minute).Unix()
	body, _ := json.Marshal(PortalSSOPayload{
		Email: "User@Corp.Com",
		Name:  "张三",
		Exp:   exp,
	})
	token, err := EncryptPortalSSOToken(body, key)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	got, err := ParsePortalSSOPayload(token, key, 10*time.Minute)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if got.Email != "user@corp.com" {
		t.Fatalf("email normalized: got %q", got.Email)
	}
	if got.Name != "张三" {
		t.Fatalf("name: got %q", got.Name)
	}
}

func TestPortalSSOTokenExpired(t *testing.T) {
	key := []byte("0123456789abcdef0123456789abcdef")
	body, _ := json.Marshal(PortalSSOPayload{
		Email: "a@b.com",
		Exp:   time.Now().Add(-time.Minute).Unix(),
	})
	token, err := EncryptPortalSSOToken(body, key)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if _, err := ParsePortalSSOPayload(token, key, 5*time.Minute); err == nil {
		t.Fatal("expected expired error")
	}
}
