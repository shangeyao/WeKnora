package utils

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"net/url"
	"testing"
)

func TestDongjianSSOTokenRoundTrip(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(DongjianSSOPayload{
		ClientID: "dongjian",
		Username: "zhangsan",
		Email:    "ZhangSan@Example.com",
		Name:     "张三",
	})
	cipher, err := rsa.EncryptPKCS1v15(rand.Reader, &key.PublicKey, body)
	if err != nil {
		t.Fatal(err)
	}
	token := base64.StdEncoding.EncodeToString(cipher)

	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})
	priv, err := ParseRSAPrivateKeyPEM(string(privPEM))
	if err != nil {
		t.Fatal(err)
	}
	got, err := ParseDongjianSSOToken(token, priv, "dongjian")
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != "zhangsan@example.com" {
		t.Fatalf("email: %q", got.Email)
	}
	if got.Name != "张三" {
		t.Fatalf("name: %q", got.Name)
	}
}

func TestDongjianSSOTokenURLDecoded(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(DongjianSSOPayload{
		ClientID: "dongjian",
		Username: "lisi",
		Email:    "lisi@example.com",
		Name:     "李四",
	})
	cipher, err := rsa.EncryptPKCS1v15(rand.Reader, &key.PublicKey, body)
	if err != nil {
		t.Fatal(err)
	}
	token := url.QueryEscape(base64.StdEncoding.EncodeToString(cipher))

	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})
	priv, err := ParseRSAPrivateKeyPEM(string(privPEM))
	if err != nil {
		t.Fatal(err)
	}
	got, err := ParseDongjianSSOToken(token, priv, "dongjian")
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != "lisi@example.com" {
		t.Fatalf("email: %q", got.Email)
	}
}

func TestDecodeURLSSOTokenRestoresPlus(t *testing.T) {
	raw := "abc+def/ghi="
	got := decodeURLSSOToken("abc def/ghi%3D")
	if got != raw {
		t.Fatalf("got %q want %q", got, raw)
	}
}
