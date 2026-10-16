//go:build !linux && !windows

package main

import (
	"errors"

	"github.com/s3onghyun/bulchimbeon/internal/platform"
)

// On macOS the menu-bar app is the product; this command has no backend there.
func newPlatform() (platform.Platform, error) {
	return platform.Platform{}, errors.New("this command runs on Linux; on macOS use the Bulchimbeon menu-bar app")
}

func alive(pid int) bool { return false }
