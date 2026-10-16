// Package engine is the Go port of Sources/BulchimbeonCore: agent detection, the duty
// policies, the duty state machine (Engine), the private's lines and the duty-log format.
//
// It makes no system calls apart from the duty-log writer, so the daemon and every
// platform backend share one engine. The Swift core is the behavior reference: the
// fixtures in testdata/engine are run by both the Swift tests and the Go tests, so the
// two engines cannot drift apart without CI failing.
package engine

import "strings"

// Lang is the UI language. Like the macOS app, only Korean and English exist.
type Lang int

const (
	EN Lang = iota
	KO
)

func (l Lang) String() string {
	if l == KO {
		return "ko"
	}
	return "en"
}

// ParseLang accepts "ko" or "en".
func ParseLang(s string) (Lang, bool) {
	switch s {
	case "ko":
		return KO, true
	case "en":
		return EN, true
	}
	return EN, false
}

// T picks the Korean or English text (Swift `L10n.t`).
func T(lang Lang, ko, en string) string {
	if lang == KO {
		return ko
	}
	return en
}

// DetectLanguage mirrors Swift `L10n.detect`: Korean if the first preferred language is
// Korean, English otherwise.
func DetectLanguage(preferred []string) Lang {
	if len(preferred) > 0 && strings.HasPrefix(preferred[0], "ko") {
		return KO
	}
	return EN
}

// PreferredLanguages turns the POSIX locale environment into a preference list, the way
// gettext reads it: LC_ALL, then LC_MESSAGES, then LANG pick the locale. LANGUAGE (a
// colon-separated list) wins over them unless the locale is C/POSIX or unset.
func PreferredLanguages(getenv func(string) string) []string {
	locale := ""
	for _, key := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := getenv(key); v != "" {
			locale = v
			break
		}
	}
	if locale == "" || locale == "C" || locale == "POSIX" || strings.HasPrefix(locale, "C.") {
		return []string{locale}
	}
	var list []string
	for _, l := range strings.Split(getenv("LANGUAGE"), ":") {
		if l != "" {
			list = append(list, l)
		}
	}
	return append(list, locale)
}
