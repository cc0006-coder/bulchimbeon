//go:build linux

package main

import (
	"syscall"

	"github.com/s3onghyun/bulchimbeon/internal/platform"
	"github.com/s3onghyun/bulchimbeon/internal/platform/linux"
)

func newPlatform() (platform.Platform, error) { return linux.New(), nil }

// alive reports whether a process exists (EPERM still means it does).
func alive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}
