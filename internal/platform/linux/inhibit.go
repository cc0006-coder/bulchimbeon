//go:build linux

package linux

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/s3onghyun/bulchimbeon/internal/platform"
)

// Who and Why are what `systemd-inhibit --list` shows. Why is a constant: never agent
// names or process arguments.
const (
	InhibitWho = "Bulchimbeon"
	InhibitWhy = "Bulchimbeon on duty: keeping AI agents awake"
)

// InhibitWhats are held as separate inhibitors. Measured on Ubuntu 24.04 (systemd 255):
// one combined `--what=sleep:idle` request is checked against the lid-switch polkit action,
// so it is denied even where `sleep` and `idle` alone are allowed.
var InhibitWhats = []string{"sleep", "idle"}

// SystemdInhibitor holds logind block inhibitors through `systemd-inhibit`.
//
// Each inhibitor is a child `systemd-inhibit --what=<what> --mode=block … cat` whose stdin is
// a pipe only this process holds open. If the daemon dies, even by SIGKILL, the kernel closes
// the pipe, cat sees EOF and exits, and systemd-inhibit releases the inhibitor at once. A
// plain `sleep infinity` child would leak the lock (measured in the design report).
type SystemdInhibitor struct {
	Tool, Cat string
	Logind    *Logind
	// ConfirmTimeout bounds how long Acquire waits to see the inhibitor in logind, and
	// UnconfirmedWait how long a helper must survive when logind cannot be asked.
	ConfirmTimeout, UnconfirmedWait time.Duration

	mu       sync.Mutex
	wanted   bool
	children map[string]*inhibitChild
	blocks   map[string]platform.Block
}

type inhibitChild struct {
	cmd    *exec.Cmd
	stdin  *os.File // our write end; closing it releases the inhibitor
	done   chan struct{}
	stderr *tail
}

// NewSystemdInhibitor finds the tools it needs.
func NewSystemdInhibitor(l *Logind) *SystemdInhibitor {
	return &SystemdInhibitor{Tool: findTool("systemd-inhibit"), Cat: findTool("cat"), Logind: l,
		ConfirmTimeout: 3 * time.Second, UnconfirmedWait: time.Second}
}

// Acquire implements platform.Inhibitor: it starts every inhibitor that is not held yet.
func (s *SystemdInhibitor) Acquire() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.wanted = true
	if s.children == nil {
		s.children, s.blocks = map[string]*inhibitChild{}, map[string]platform.Block{}
	}
	for _, what := range InhibitWhats {
		if s.children[what] != nil {
			continue
		}
		c, block := s.start(what)
		if c != nil {
			s.children[what] = c
		}
		s.blocks[what] = block
	}
}

func (s *SystemdInhibitor) start(what string) (*inhibitChild, platform.Block) {
	block := platform.Block{What: what}
	if s.Tool == "" || s.Cat == "" {
		block.Error = "systemd-inhibit not found"
		return nil, block
	}
	r, w, err := os.Pipe()
	if err != nil {
		block.Error = err.Error()
		return nil, block
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		r.Close()
		w.Close()
		block.Error = err.Error()
		return nil, block
	}
	cmd := exec.Command(s.Tool, "--what="+what, "--mode=block", "--who="+InhibitWho, "--why="+InhibitWhy, s.Cat)
	cmd.Env = minimalEnv
	cmd.Stdin = r
	// An *os.File, so Wait returns when systemd-inhibit exits even though cat shares it.
	cmd.Stderr = errW
	if err := cmd.Start(); err != nil {
		r.Close()
		w.Close()
		errR.Close()
		errW.Close()
		block.Error = err.Error()
		return nil, block
	}
	r.Close()
	errW.Close()
	c := &inhibitChild{cmd: cmd, stdin: w, done: make(chan struct{}), stderr: newTail(errR)}
	go func() {
		cmd.Wait()
		close(c.done)
	}()
	block.PID = cmd.Process.Pid

	// Wait until logind lists the inhibitor, or systemd-inhibit gives up (polkit says no).
	start := time.Now()
	for {
		select {
		case <-c.done:
			w.Close()
			msg := c.stderr.text(time.Second)
			block.PID = 0
			switch {
			case strings.Contains(msg, "Access denied"):
				block.Denied, block.Error = true, "polkit denied"
			case msg != "":
				block.Error = msg
			default:
				block.Error = "systemd-inhibit exited"
			}
			return nil, block
		default:
		}
		listed, known := s.listed(what, block.PID)
		waited := time.Since(start)
		switch {
		case listed:
			block.Held, block.Confirmed = true, true
			return c, block
		case !known && waited > s.UnconfirmedWait, waited > s.ConfirmTimeout:
			// Still alive, but logind cannot confirm it (no busctl) or has not listed it yet.
			// The child holds the inhibitor; Refresh checks again on the next tick.
			block.Held = true
			return c, block
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// listed reports whether logind lists our inhibitor; ok is false when it cannot tell.
func (s *SystemdInhibitor) listed(what string, pid int) (listed, ok bool) {
	if s.Logind == nil {
		return false, false
	}
	holders, err := s.Logind.Holders()
	if err != nil {
		return false, false
	}
	for _, h := range holders {
		if h.PID == pid && h.What == what && h.Mode == "block" {
			return true, true
		}
	}
	return false, true
}

// Release implements platform.Inhibitor.
func (s *SystemdInhibitor) Release() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.wanted = false
	for what, c := range s.children {
		c.stop()
		delete(s.children, what)
	}
	s.blocks = map[string]platform.Block{}
}

func (c *inhibitChild) stop() {
	c.stdin.Close()
	select {
	case <-c.done:
	case <-time.After(2 * time.Second):
		c.cmd.Process.Kill()
		<-c.done
	}
}

// Refresh implements platform.Inhibitor.
func (s *SystemdInhibitor) Refresh() (lost bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.wanted {
		return false
	}
	var holders []platform.Holder
	var listErr error = io.EOF
	if s.Logind != nil {
		holders, listErr = s.Logind.Holders()
	}
	for what, c := range s.children {
		block := s.blocks[what]
		alive := true
		select {
		case <-c.done:
			alive = false
		default:
		}
		if alive && listErr == nil {
			alive, block.Confirmed = false, false
			for _, h := range holders {
				if h.PID == block.PID && h.What == what && h.Mode == "block" {
					alive, block.Confirmed = true, true
				}
			}
		}
		if !alive {
			c.stop()
			delete(s.children, what)
			block = platform.Block{What: what, Error: "inhibitor disappeared"}
			lost = true
		}
		s.blocks[what] = block
	}
	return lost
}

// Status implements platform.Inhibitor.
func (s *SystemdInhibitor) Status() platform.LockStatus {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := platform.LockStatus{Wanted: s.wanted, Method: "systemd-inhibit"}
	if !s.wanted {
		return st
	}
	for _, what := range InhibitWhats {
		if b, ok := s.blocks[what]; ok {
			st.Blocks = append(st.Blocks, b)
		}
	}
	return st
}

// tail keeps the first bytes a child writes to stderr.
type tail struct {
	mu   sync.Mutex
	buf  bytes.Buffer
	eof  chan struct{}
	size int
}

func newTail(r io.ReadCloser) *tail {
	t := &tail{eof: make(chan struct{}), size: 512}
	go func() {
		defer close(t.eof)
		defer r.Close()
		chunk := make([]byte, 256)
		for {
			n, err := r.Read(chunk)
			t.mu.Lock()
			if room := t.size - t.buf.Len(); room > 0 {
				t.buf.Write(chunk[:min(n, room)])
			}
			t.mu.Unlock()
			if err != nil {
				return
			}
		}
	}()
	return t
}

// text waits up to wait for the writer to finish and returns the first line.
func (t *tail) text(wait time.Duration) string {
	select {
	case <-t.eof:
	case <-time.After(wait):
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	return firstLine(strings.TrimSpace(t.buf.String()))
}
