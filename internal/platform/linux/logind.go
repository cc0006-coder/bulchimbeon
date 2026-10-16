//go:build linux

package linux

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/s3onghyun/bulchimbeon/internal/platform"
)

// Commands run with absolute paths and a minimal environment only, never through $PATH
// or a shell, so a planted binary or variable cannot change what runs.
var toolDirs = []string{"/usr/bin", "/bin", "/usr/sbin", "/sbin"}

var minimalEnv = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"}

// findTool returns the absolute path of a system tool, or "".
func findTool(name string) string {
	for _, dir := range toolDirs {
		p := filepath.Join(dir, name)
		if info, err := os.Stat(p); err == nil && info.Mode().IsRegular() && info.Mode()&0o111 != 0 {
			return p
		}
	}
	return ""
}

// run executes a tool and returns its stdout. A non-zero exit is an error carrying stderr.
func run(timeout time.Duration, path string, args ...string) ([]byte, error) {
	return runEnv(timeout, minimalEnv, path, args...)
}

func runEnv(timeout time.Duration, env []string, path string, args ...string) ([]byte, error) {
	if path == "" {
		return nil, errors.New("tool not found")
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, args...)
	cmd.Env = env
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return stdout.Bytes(), fmt.Errorf("%w: %s", err, firstLine(msg))
		}
		return stdout.Bytes(), err
	}
	return stdout.Bytes(), nil
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// Logind lists inhibitors through `busctl`, which ships with systemd. It is the D-Bus call
// org.freedesktop.login1.Manager.ListInhibitors, so no D-Bus library is needed.
type Logind struct {
	Busctl string
}

// NewLogind finds busctl.
func NewLogind() *Logind { return &Logind{Busctl: findTool("busctl")} }

// Holders implements platform.HolderSource.
func (l *Logind) Holders() ([]platform.Holder, error) {
	out, err := run(3*time.Second, l.Busctl, "--json=short", "call", "org.freedesktop.login1",
		"/org/freedesktop/login1", "org.freedesktop.login1.Manager", "ListInhibitors")
	if err != nil {
		return nil, fmt.Errorf("busctl ListInhibitors: %w", err)
	}
	return ParseListInhibitors(out)
}

// ParseListInhibitors reads `busctl --json=short` output for ListInhibitors, whose reply
// is a(ssssuu): what, who, why, mode, uid, pid.
func ParseListInhibitors(data []byte) ([]platform.Holder, error) {
	var reply struct {
		Type string              `json:"type"`
		Data [][]json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(data, &reply); err != nil {
		return nil, err
	}
	if reply.Type != "a(ssssuu)" || len(reply.Data) != 1 {
		return nil, fmt.Errorf("unexpected ListInhibitors reply type %q", reply.Type)
	}
	var holders []platform.Holder
	for _, raw := range reply.Data[0] {
		var row []any
		if err := json.Unmarshal(raw, &row); err != nil || len(row) != 6 {
			return nil, fmt.Errorf("bad inhibitor entry %s", raw)
		}
		what, _ := row[0].(string)
		who, _ := row[1].(string)
		mode, _ := row[3].(string)
		pid, _ := row[5].(float64)
		holders = append(holders, platform.Holder{Who: who, What: what, Mode: mode, PID: int(pid)})
	}
	return holders, nil
}
