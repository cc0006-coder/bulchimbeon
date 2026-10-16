// Package platform declares what the daemon needs from the operating system. Each OS has
// a backend package (internal/platform/linux now, internal/platform/windows later); the
// engine itself never calls the system.
package platform

import (
	"errors"
	"io"
	"sort"
	"strings"

	"github.com/s3onghyun/bulchimbeon/internal/engine"
)

// Who is the name our locks carry in the OS's lock listings.
const Who = "Bulchimbeon"

// ErrNotImplemented is returned by backends that do not exist yet.
var ErrNotImplemented = errors.New("not implemented on this platform yet")

// ProcessScan is one snapshot of the current user's processes.
type ProcessScan struct {
	Snapshots []engine.ProcessSnapshot
	// CPUTimes is cumulative user+system CPU time per PID, in nanoseconds.
	CPUTimes map[int32]uint64
}

// ProcessSource lists the current user's processes. It reads argv[0] only, unless the
// process is a script runner or already an agent candidate for kinds (see engine.Args*).
type ProcessSource interface {
	Scan(kinds []engine.AgentKind) (ProcessScan, error)
}

// Block is one part of the sleep lock, such as logind's "sleep" or "idle" inhibitor.
type Block struct {
	What string `json:"what"`
	Held bool   `json:"held"`
	// Confirmed means the OS itself lists the block (logind), not just a live helper.
	Confirmed bool `json:"confirmed"`
	// PID is the helper process holding the block, if any.
	PID int `json:"pid,omitempty"`
	// Denied means a policy refused it (polkit); Error says why it is not held.
	Denied bool   `json:"denied,omitempty"`
	Error  string `json:"error,omitempty"`
}

// LockStatus is what the inhibitor holds.
type LockStatus struct {
	Wanted bool    `json:"wanted"`
	Method string  `json:"method"`
	Blocks []Block `json:"blocks"`
}

// Block returns the named block.
func (s LockStatus) Block(what string) (Block, bool) {
	for _, b := range s.Blocks {
		if b.What == what {
			return b, true
		}
	}
	return Block{}, false
}

// Complete reports whether every wanted block is held.
func (s LockStatus) Complete() bool {
	if !s.Wanted {
		return true
	}
	for _, b := range s.Blocks {
		if !b.Held {
			return false
		}
	}
	return len(s.Blocks) > 0
}

// Inhibitor keeps the machine awake while the engine is on duty.
type Inhibitor interface {
	// Acquire takes every block that is not held yet. Failures show up in Status.
	Acquire()
	// Release drops everything.
	Release()
	// Refresh re-checks held blocks against the system and reports whether one that was
	// held has disappeared (the engine's "abandoned post").
	Refresh() (lost bool)
	Status() LockStatus
}

// BatterySource reads the internal battery; nil means there is none (a desktop).
type BatterySource interface {
	Battery() (*engine.BatteryStatus, error)
}

// ThermalReading is the heat level and the sensor it came from.
type ThermalReading struct {
	Level       engine.HeatLevel `json:"-"`
	LevelName   string           `json:"level"`
	Sensor      string           `json:"sensor,omitempty"`
	Celsius     float64          `json:"celsius,omitempty"`
	CritCelsius float64          `json:"critCelsius,omitempty"`
	// Available is false when there is no sensor; the level is then normal.
	Available bool `json:"available"`
}

// ThermalSource reads the heat level.
type ThermalSource interface {
	Thermal() ThermalReading
}

// Holder is another program's sleep or idle lock.
type Holder struct {
	Who  string `json:"who"`
	What string `json:"what"`
	Mode string `json:"mode"`
	PID  int    `json:"pid"`
}

// HolderSource lists every sleep and idle lock on the system, including ours.
type HolderSource interface {
	Holders() ([]Holder, error)
}

// Platform bundles one OS backend.
type Platform struct {
	Name      string
	Processes ProcessSource
	Inhibitor Inhibitor
	Battery   BatterySource
	Thermal   ThermalSource
	Holders   HolderSource
	// Doctor checks the setup, prints the findings and returns false if something needs fixing.
	Doctor func(w io.Writer, lang engine.Lang) bool
}

// HolderSummary groups other programs' locks for display.
type HolderSummary struct {
	BlockSleep, DelaySleep, BlockIdle []string
}

// SummarizeHolders lists other programs that block or delay sleep, or block idle, by name.
// Our own helpers (ownPIDs) and entries named ownWho are left out.
func SummarizeHolders(holders []Holder, ownPIDs []int, ownWho string) HolderSummary {
	own := map[int]bool{}
	for _, p := range ownPIDs {
		own[p] = true
	}
	sets := [3]map[string]bool{{}, {}, {}}
	for _, h := range holders {
		if own[h.PID] || h.Who == ownWho {
			continue
		}
		for _, what := range strings.Split(h.What, ":") {
			switch {
			case what == "sleep" && h.Mode == "block":
				sets[0][h.Who] = true
			case what == "sleep" && h.Mode == "delay":
				sets[1][h.Who] = true
			case what == "idle" && h.Mode == "block":
				sets[2][h.Who] = true
			}
		}
	}
	list := func(m map[string]bool) []string {
		out := make([]string, 0, len(m))
		for k := range m {
			out = append(out, k)
		}
		sort.Strings(out)
		return out
	}
	return HolderSummary{BlockSleep: list(sets[0]), DelaySleep: list(sets[1]), BlockIdle: list(sets[2])}
}
