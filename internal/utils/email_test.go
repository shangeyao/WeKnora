package utils

import "testing"

func TestNormalizeEmail(t *testing.T) {
	if got := NormalizeEmail("  User@Corp.COM  "); got != "user@corp.com" {
		t.Fatalf("got %q", got)
	}
}
