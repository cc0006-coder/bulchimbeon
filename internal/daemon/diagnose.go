package daemon

import (
	"fmt"
	"io"
	"slices"
	"strings"
	"time"

	"github.com/s3onghyun/bulchimbeon/internal/engine"
	"github.com/s3onghyun/bulchimbeon/internal/platform"
	"github.com/s3onghyun/bulchimbeon/internal/settings"
)

// Diagnose prints which agents are detected and why (`bulchimbeon diagnose`, the Linux
// counterpart of the macOS `--diagnose`). It samples CPU twice, sample apart. It shows
// executables and working directories of agent processes only, never their arguments.
func Diagnose(w io.Writer, p platform.Platform, s settings.Settings, lang engine.Lang, uid int,
	sample time.Duration, sleep func(time.Duration)) error {
	t := func(ko, en string) string { return engine.T(lang, ko, en) }
	kinds := append(slices.Clone(engine.BuiltIn), engine.CustomKinds(s.CustomAgents)...)
	history := &engine.CPUHistory{Window: sample}
	first, err := p.Processes.Scan(kinds)
	if err != nil {
		return err
	}
	start := time.Now()
	history.Add(first.CPUTimes, start)
	sleep(sample)
	scan, err := p.Processes.Scan(kinds)
	if err != nil {
		return err
	}
	cpu := history.Add(scan.CPUTimes, start.Add(sample))
	children := engine.Children(scan.Snapshots)

	fmt.Fprintf(w, t("불침번 에이전트 감지 진단 (UID %[2]d 프로세스 %[1]d개 검사, CPU %[3]s 측정)\n\n",
		"Bulchimbeon agent detection (checked %[1]d processes of UID %[2]d, CPU over %[3]s)\n\n"),
		len(scan.Snapshots), uid, sample)
	found := 0
	for _, proc := range scan.Snapshots {
		k, reason, ok := engine.Match(proc, kinds)
		if !ok {
			continue
		}
		found++
		total, caffeinate := engine.TreeCPU(proc, children, cpu)
		state := fmt.Sprintf(t("  · 대기 (트리 CPU %.1f%%)", "  · idle (tree CPU %.1f%%)"), total)
		if caffeinate || total >= engine.CPUThreshold {
			state = fmt.Sprintf(t("  · 작업 중 (트리 CPU %.1f%%)", "  · working (tree CPU %.1f%%)"), total)
		}
		fmt.Fprintf(w, "  ✔ %s  pid %d  %s%s%s\n", k.DisplayName, proc.PID, t("근거: ", "matched by: "), reason.Label(lang), state)
		if proc.CWD != "" {
			fmt.Fprintln(w, "      "+t("작업 폴더: ", "cwd: ")+proc.CWD)
		}
		fmt.Fprintln(w, "      "+t("실행 파일: ", "executable: ")+proc.ExecutablePath)
	}
	if found == 0 {
		fmt.Fprintln(w, "  "+t("감지된 에이전트 없음", "No agents detected"))
	}
	fmt.Fprintf(w, t("\n작업 중 판정: 자신과 자손 프로세스의 CPU 합이 %.1f%% 이상 (데몬은 60초 평균)\n",
		"\nWorking means the process and its descendants use at least %.1f%% CPU (the daemon averages over 60 s)\n"),
		engine.CPUThreshold)

	if holders, err := p.Holders.Holders(); err == nil {
		sum := platform.SummarizeHolders(holders, nil, platform.Who)
		list := func(names []string) string {
			if len(names) == 0 {
				return "-"
			}
			return strings.Join(names, ", ")
		}
		fmt.Fprintln(w, "\n"+t("잠자기를 막는 다른 앱: ", "Also blocking sleep: ")+list(sum.BlockSleep))
		fmt.Fprintln(w, t("잠자기를 늦추는 다른 앱: ", "Also delaying sleep: ")+list(sum.DelaySleep))
	}
	custom := t("없음", "none")
	if len(s.CustomAgents) > 0 {
		custom = strings.Join(s.CustomAgents, ", ")
	}
	fmt.Fprintln(w, "\n"+t("사용자 지정 에이전트: ", "Custom agents: ")+custom)
	fmt.Fprintln(w, t("추가: ", "Add: ")+"bulchimbeon config set customAgents <name>...")
	return nil
}
