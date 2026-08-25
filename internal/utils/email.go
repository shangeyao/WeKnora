package utils

import "strings"

// NormalizeEmail trims whitespace and lowercases for case-insensitive identity matching.
func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}
