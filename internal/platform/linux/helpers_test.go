//go:build linux

package linux

import (
	"syscall"
	"time"
)

func syscallKill(pid int) error { return syscall.Kill(pid, 0) }

func sleepBriefly() { time.Sleep(20 * time.Millisecond) }
