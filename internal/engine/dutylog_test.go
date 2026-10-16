package engine

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDutyLogNewestFirstAndCapped(t *testing.T) {
	l := &DutyLog{Capacity: 2}
	for _, s := range []string{"a", "b", "c"} {
		l.Write(s, LogOther, time.Unix(0, 0))
	}
	if got := l.Recent(); len(got) != 2 || got[0].Text != "c" || got[1].Text != "b" {
		t.Fatalf("recent = %+v", got)
	}
}

func TestDutyLogFileIsOwnerOnly(t *testing.T) {
	path := filepath.Join(t.TempDir(), "new", "duty-log.txt")
	if err := NewDutyLog(path).Write("근무 투입", LogOnDuty, time.Now()); err != nil {
		t.Fatal(err)
	}
	for p, want := range map[string]os.FileMode{path: 0o600, filepath.Dir(path): 0o700} {
		info, err := os.Stat(p)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != want {
			t.Errorf("%s: mode %v, want %v", p, info.Mode().Perm(), want)
		}
	}
}

func TestDutyLogRefusesToFollowSymlink(t *testing.T) {
	dir := t.TempDir()
	victim := filepath.Join(dir, "victim.txt")
	os.WriteFile(victim, []byte("중요한 파일"), 0o600)
	path := filepath.Join(dir, "duty-log.txt")
	if err := os.Symlink(victim, path); err != nil {
		t.Fatal(err)
	}
	if err := NewDutyLog(path).Write("덮어쓰기 시도", LogOther, time.Now()); err == nil {
		t.Error("writing through a symlink succeeded")
	}
	if data, _ := os.ReadFile(victim); string(data) != "중요한 파일" {
		t.Errorf("victim changed: %q", data)
	}
}

func TestDutyLogRotatesWhenTooLarge(t *testing.T) {
	path := filepath.Join(t.TempDir(), "duty-log.txt")
	l := NewDutyLog(path)
	l.MaxFileBytes = 64
	for i := 0; i < 10; i++ {
		l.Write("근무 기록 "+itoa(i), LogOther, time.Now())
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() >= 64*2 {
		t.Errorf("size %d after rotation", info.Size())
	}
	if _, err := os.Stat(path + ".1"); err != nil {
		t.Errorf("no rotated file: %v", err)
	}
}

func TestLogEntryLine(t *testing.T) {
	e := LogEntry{At: time.Unix(1_000_000, 0), Text: "a\nb"}
	if got := e.Line(); got != "1970-01-12T13:46:40Z  a b" || strings.Contains(got, "\n") {
		t.Errorf("line = %q", got)
	}
}
