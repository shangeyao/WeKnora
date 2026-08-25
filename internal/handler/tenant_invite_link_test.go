package handler

import (
	"os"
	"testing"

	"github.com/Tencent/WeKnora/internal/config"
)

func TestBuildInviteRegisterURL(t *testing.T) {
	t.Setenv("FRONTEND_BASE_URL", "")
	t.Setenv("FRONTEND_BASE_PATH", "")

	if got := buildInviteRegisterURL(nil, ""); got != "" {
		t.Fatalf("empty token: got %q", got)
	}
	if got := buildInviteRegisterURL(nil, "abc123"); got != "/register?token=abc123" {
		t.Fatalf("root deploy: got %q", got)
	}

	t.Setenv("FRONTEND_BASE_PATH", "/weknora")
	if got := buildInviteRegisterURL(nil, "abc123"); got != "/weknora/register?token=abc123" {
		t.Fatalf("subpath deploy: got %q", got)
	}

	t.Setenv("FRONTEND_BASE_URL", "http://10.121.1.155:8081")
	if got := buildInviteRegisterURL(nil, "abc123"); got != "http://10.121.1.155:8081/weknora/register?token=abc123" {
		t.Fatalf("absolute subpath deploy: got %q", got)
	}

	cfg := &config.Config{
		FrontendBaseURL:  "https://example.com",
		FrontendBasePath: "/weknora",
	}
	if got := buildInviteRegisterURL(cfg, "xyz"); got != "https://example.com/weknora/register?token=xyz" {
		t.Fatalf("config struct: got %q", got)
	}

	// env overrides at request time when config fields are empty.
	cfg = &config.Config{}
	t.Setenv("FRONTEND_BASE_URL", "")
	t.Setenv("FRONTEND_BASE_PATH", "weknora")
	if got := buildInviteRegisterURL(cfg, "tok"); got != "/weknora/register?token=tok" {
		t.Fatalf("env path without leading slash: got %q", got)
	}

	os.Unsetenv("FRONTEND_BASE_URL")
	os.Unsetenv("FRONTEND_BASE_PATH")
}
