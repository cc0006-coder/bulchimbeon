package engine

import "time"

// Whether an agent is merely open or actually working (Swift `AgentActivity`).
//
// Measured on macOS (2026-10): of 7 open Claude Code sessions only the one at work
// spawned `caffeinate -i -t 300` and used about 10% CPU; the others sat at 0-0.1%.
// So an agent is working when it has a caffeinate child (Claude Code's own signal, which
// never fires on Linux), or when it and its descendants use at least CPUThreshold.
const (
	CPUThreshold = 2.0 // percent
	// BusyGrace mirrors Swift `AgentActivity.busyGrace`; the engine uses its own GraceMinutes.
	BusyGrace = 5 * time.Minute
	// maxTreeVisit bounds the descendant walk (cyclic parent links must not hang it).
	maxTreeVisit = 512
)

// Status counts open and working processes of one agent.
type Status struct {
	Present int
	Busy    int
}

// Evaluate returns the open and working counts per agent.
func Evaluate(processes []ProcessSnapshot, cpu map[int32]float64, kinds []AgentKind) map[Kind]Status {
	children := Children(processes)
	result := map[Kind]Status{}
	for _, p := range processes {
		k, _, ok := Match(p, kinds)
		if !ok {
			continue
		}
		s := result[k.Kind]
		s.Present++
		if IsBusy(p, children, cpu) {
			s.Busy++
		}
		result[k.Kind] = s
	}
	return result
}

// Children indexes processes by parent PID, keeping input order.
func Children(processes []ProcessSnapshot) map[int32][]ProcessSnapshot {
	children := map[int32][]ProcessSnapshot{}
	for _, p := range processes {
		children[p.PPID] = append(children[p.PPID], p)
	}
	return children
}

// IsBusy reports whether one agent process is working.
func IsBusy(agent ProcessSnapshot, children map[int32][]ProcessSnapshot, cpu map[int32]float64) bool {
	total, caffeinate := TreeCPU(agent, children, cpu)
	return caffeinate || total >= CPUThreshold
}

// TreeCPU sums the CPU percentage of the agent and its descendants, and reports whether
// it has a caffeinate child (in which case the sum is not computed, as in Swift).
func TreeCPU(agent ProcessSnapshot, children map[int32][]ProcessSnapshot, cpu map[int32]float64) (total float64, caffeinate bool) {
	for _, c := range children[agent.PID] {
		if Basename(c.ExecutablePath) == "caffeinate" {
			return 0, true
		}
	}
	total = cpu[agent.PID]
	queue := append([]ProcessSnapshot(nil), children[agent.PID]...)
	visited := map[int32]bool{agent.PID: true}
	for len(queue) > 0 {
		next := queue[len(queue)-1]
		queue = queue[:len(queue)-1]
		if len(visited) >= maxTreeVisit {
			break
		}
		if visited[next.PID] {
			continue
		}
		visited[next.PID] = true
		total += cpu[next.PID]
		queue = append(queue, children[next.PID]...)
	}
	return total, false
}
