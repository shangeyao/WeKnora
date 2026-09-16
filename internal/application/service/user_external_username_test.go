package service

import (
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestSanitizeUsernameCandidate_TruncatesByRunesNotBytes(t *testing.T) {
	// Regression: byte truncation at 50 split a CJK rune; appending "-1788828679"
	// produced invalid UTF-8 (0xe6 0x2d 0x31) and PostgreSQL rejected the insert.
	long := "guowenqiang郭文强-车载电源产品中心-集" + strings.Repeat("测试", 30)
	got := sanitizeUsernameCandidate(long)
	if !utf8.ValidString(got) {
		t.Fatalf("invalid UTF-8: %q (% x)", got, []byte(got))
	}
	if n := utf8.RuneCountInString(got); n > 50 {
		t.Fatalf("rune count = %d, want <= 50", n)
	}

	withSuffix := fmt.Sprintf("%s-%d", got, 1788828679)
	if !utf8.ValidString(withSuffix) {
		t.Fatalf("invalid UTF-8 after suffix: %q (% x)", withSuffix, []byte(withSuffix))
	}
}

func TestSanitizeUsernameCandidate_PreservesReadableLDAPName(t *testing.T) {
	got := sanitizeUsernameCandidate("GuoWenQiang郭文强-车载电源产品中心")
	if got == "" {
		t.Fatal("expected non-empty username")
	}
	if !utf8.ValidString(got) {
		t.Fatalf("invalid UTF-8: %q", got)
	}
	if !strings.Contains(got, "guowenqiang") {
		t.Fatalf("expected ascii portion preserved, got %q", got)
	}
}
