//go:build !unix

package engine

import (
	"errors"
	"os"
)

// openAppendNoFollow has no O_NOFOLLOW here, so it refuses an existing symlink first.
func openAppendNoFollow(path string) (*os.File, error) {
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("duty log is a symlink")
	}
	return os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o600)
}
