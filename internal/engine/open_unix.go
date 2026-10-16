//go:build unix

package engine

import (
	"os"
	"syscall"
)

func openAppendNoFollow(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE|syscall.O_NOFOLLOW, 0o600)
}
