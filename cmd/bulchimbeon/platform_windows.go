//go:build windows

package main

import (
	"github.com/s3onghyun/bulchimbeon/internal/platform"
	"github.com/s3onghyun/bulchimbeon/internal/platform/windows"
)

// newPlatform refuses until the Windows backend exists (see internal/platform/windows).
func newPlatform() (platform.Platform, error) {
	return windows.New(), platform.ErrNotImplemented
}

func alive(pid int) bool { return false }
