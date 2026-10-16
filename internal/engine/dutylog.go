package engine

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

// LogEntry is one duty-log entry.
type LogEntry struct {
	At   time.Time
	Text string
	Kind LogKind
}

// Line is the entry as written to the file (without the newline).
func (e LogEntry) Line() string { return strings.TrimSuffix(FormatLogLine(e.At, e.Text), "\n") }

// FormatLogLine is the frozen duty-log line format (docs/compatibility.md §3):
// ISO 8601 UTC time, two spaces, the text folded onto one line, and a newline.
func FormatLogLine(at time.Time, text string) string {
	return at.UTC().Format("2006-01-02T15:04:05Z") + "  " + SingleLine(text) + "\n"
}

// SingleLine replaces every line break with a space so one entry can never pose as
// several (log injection). It covers the same characters as Foundation's
// `CharacterSet.newlines`: U+000A-U+000D, U+0085, U+2028 and U+2029.
func SingleLine(text string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case '\n', '\v', '\f', '\r', '\u0085', ' ', ' ':
			return ' '
		}
		return r
	}, text)
}

// DutyLog keeps the latest entries in memory and appends every entry to a file.
//
// Security (same as the Swift DutyLog):
//   - the file is opened without following symlinks, so it cannot overwrite another file
//   - file 0600, directory 0700
//   - past MaxFileBytes it rotates to "<file>.1", so it never fills the disk
//   - callers log only app constants and catalog names, never process arguments
type DutyLog struct {
	Path         string // empty: memory only
	MaxFileBytes int64
	Capacity     int
	recent       []LogEntry
}

// NewDutyLog uses the macOS app's limits: 50 entries in memory, 1 MB per file.
func NewDutyLog(path string) *DutyLog {
	return &DutyLog{Path: path, MaxFileBytes: 1_000_000, Capacity: 50}
}

// Recent returns the in-memory entries, newest first.
func (l *DutyLog) Recent() []LogEntry { return l.recent }

// Write records one entry. A file error leaves the in-memory entry in place.
func (l *DutyLog) Write(text string, kind LogKind, at time.Time) error {
	entry := LogEntry{At: at, Text: text, Kind: kind}
	l.recent = append([]LogEntry{entry}, l.recent...)
	if l.Capacity > 0 && len(l.recent) > l.Capacity {
		l.recent = l.recent[:l.Capacity]
	}
	if l.Path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(l.Path), 0o700); err != nil {
		return err
	}
	l.rotateIfNeeded()
	f, err := openAppendNoFollow(l.Path)
	if err != nil {
		return err // a symlink fails with ELOOP and nothing is written
	}
	defer f.Close()
	_, err = f.WriteString(FormatLogLine(at, text))
	return err
}

func (l *DutyLog) rotateIfNeeded() {
	info, err := os.Lstat(l.Path)
	if err != nil || !info.Mode().IsRegular() || info.Size() < l.MaxFileBytes {
		return
	}
	rotated := l.Path + ".1"
	os.Remove(rotated)
	os.Rename(l.Path, rotated)
}
