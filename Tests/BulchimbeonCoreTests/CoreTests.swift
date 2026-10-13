import Foundation
import Testing
@testable import BulchimbeonCore

@Suite struct AgentCatalogTests {
    private func proc(_ path: String, _ args: [String]) -> ProcessSnapshot {
        ProcessSnapshot(executablePath: path, arguments: args)
    }

    // 실측 (2026-10, macOS 26): 네이티브 설치본은 실행 파일 이름이 버전 번호, argv[0] 만 "claude"
    @Test func nativeInstallerViaShellCommand() {
        let p = proc("/Users/me/.local/share/claude/versions/2.1.296", ["claude"])
        #expect(AgentCatalog.match(p)?.kind.id == "claude-code")
    }

    @Test func nativeInstallerLaunchedByFullPath() {
        // IDE 확장·스크립트가 전체 경로로 띄우면 argv[0] 도 버전 경로 → 설치 경로로 판별
        let path = "/Users/me/.local/share/claude/versions/2.1.296"
        let match = AgentCatalog.match(proc(path, [path, "--resume"]))
        #expect(match?.kind.id == "claude-code")
        #expect(match?.reason == .installPath)
    }

    @Test func homebrewAndIdeBinaries() {
        #expect(AgentCatalog.match(proc("/opt/homebrew/Caskroom/claude-code/2.1.0/claude", ["claude"]))?.reason == .executableName)
        #expect(AgentCatalog.match(proc("/Users/me/.vscode/extensions/anthropic.claude-code-2.1.0/resources/native-binary/claude",
                                        ["claude"]))?.kind.id == "claude-code")
        #expect(AgentCatalog.match(proc("/opt/homebrew/bin/codex", ["codex", "exec"]))?.kind.id == "codex")
        #expect(AgentCatalog.match(proc("/Users/me/.local/bin/cursor-agent", ["cursor-agent"]))?.kind.id == "cursor-agent")
    }

    @Test func npmGlobalInstallRunsBinLink() {
        // npm 전역 설치: shebang 으로 `node /opt/homebrew/bin/claude` — 스크립트 basename 으로 판별
        let match = AgentCatalog.match(proc("/opt/homebrew/Cellar/node/24.1.0/bin/node",
                                            ["node", "/opt/homebrew/bin/claude", "-c"]))
        #expect(match?.kind.id == "claude-code")
        #expect(match?.reason == .script)
    }

    @Test func npmPackagePathAndOtherRunners() {
        #expect(AgentCatalog.match(proc("/Users/me/.volta/tools/image/node/22.0.0/bin/node",
            ["node", "--max-old-space-size=4096", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]))?.kind.id == "claude-code")
        #expect(AgentCatalog.match(proc("/Users/me/.bun/bin/bun",
            ["bun", "/Users/me/.bun/install/global/node_modules/@google/gemini-cli/dist/index.js"]))?.kind.id == "gemini-cli")
        #expect(AgentCatalog.match(proc("/usr/local/bin/node",
            ["node", "/usr/local/lib/node_modules/@openai/codex/bin/codex.js"]))?.kind.id == "codex")
    }

    @Test func hookScriptsAreNotAgents() {
        // 실측: Claude Code hook 은 node -e 로 .claude 경로를 참조한다
        #expect(AgentCatalog.match(proc("/opt/homebrew/bin/node",
            ["node", "-e", "require(require('path').join(process.env.CLAUDE_PLUGIN_ROOT,'hooks/x.js'))"])) == nil)
        #expect(AgentCatalog.match(proc("/bin/zsh", ["/bin/zsh", "-c", "source /Users/me/.claude/shell-snapshots/x.sh"])) == nil)
        // 실행 파일 경로에 .claude 가 있어도 설치 마커가 아니면 무시
        #expect(AgentCatalog.match(proc("/Users/me/.claude/plugins/foo/bin/helper", ["helper"])) == nil)
    }

    @Test func desktopAppIsNotAnAgent() {
        #expect(AgentCatalog.match(proc("/Applications/Claude.app/Contents/MacOS/Claude", ["/Applications/Claude.app/Contents/MacOS/Claude"])) == nil)
        #expect(AgentCatalog.match(proc("/Applications/Claude.app/Contents/Helpers/chrome-native-host",
                                        ["chrome-native-host", "chrome-extension://x/"])) == nil)
    }

    @Test func onlyRunnersNeedFullArguments() {
        #expect(AgentCatalog.needsFullArguments(executablePath: "/opt/homebrew/bin/node"))
        #expect(AgentCatalog.needsFullArguments(executablePath: "/Users/me/.bun/bin/bun"))
        #expect(AgentCatalog.needsFullArguments(executablePath: "/usr/bin/ssh") == false)
    }

    @Test func customAgentsAreValidated() {
        let kinds = AgentCatalog.customKinds(["my-agent", "my-agent", "../../etc", "a b", "", String(repeating: "x", count: 40), "goose"])
        #expect(kinds.map(\.displayName) == ["my-agent", "goose"])
        #expect(AgentCatalog.customKinds((0..<30).map { "agent\($0)" }).count == 16)
        let match = AgentCatalog.match(proc("/usr/local/bin/goose", ["goose"]), kinds: AgentCatalog.builtIn + kinds)
        #expect(match?.kind.displayName == "goose")
    }

    @Test func countAndSummary() {
        let processes = [
            proc("/Users/me/.local/share/claude/versions/2.1.296", ["claude"]),
            proc("/Users/me/.local/share/claude/versions/2.1.296", ["claude"]),
            proc("/opt/homebrew/bin/node", ["node", "-e", "require('.claude')"]),
            proc("/opt/homebrew/bin/codex", ["codex"]),
            proc("/bin/zsh", ["-zsh"]),
        ]
        let counts = AgentCatalog.count(processes)
        #expect(counts.values.reduce(0, +) == 3)
        #expect(AgentCatalog.summary(counts) == "Claude Code ×2, Codex")
        #expect(AgentCatalog.summary([:]) == "")
    }
}

@Suite struct ProcArgsTests {
    /// KERN_PROCARGS2 형식 버퍼 생성
    private func buffer(execPath: String, argv: [String], env: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int32(argv.count)) { Array($0) }
        bytes += Array(execPath.utf8) + [0, 0, 0, 0] // 경로 + 패딩
        for s in argv + env { bytes += Array(s.utf8) + [0] }
        return bytes
    }

    @Test func parsesArgvOnlyNeverEnvironment() {
        let b = buffer(execPath: "/opt/homebrew/bin/node", argv: ["node", "/opt/homebrew/bin/claude"],
                       env: ["ANTHROPIC_API_KEY=sk-secret"])
        let args = ProcArgs.parse(b, limit: 8)
        #expect(args == ["node", "/opt/homebrew/bin/claude"])
        #expect(!args.joined().contains("sk-secret"))
    }

    @Test func respectsLimit() {
        let b = buffer(execPath: "/bin/x", argv: ["x", "--token=secret"], env: [])
        #expect(ProcArgs.parse(b, limit: 1) == ["x"])
    }

    @Test func malformedBuffersAreSafe() {
        #expect(ProcArgs.parse([], limit: 8) == [])
        #expect(ProcArgs.parse([1, 0], limit: 8) == [])
        #expect(ProcArgs.parse([255, 255, 255, 127] + Array("/x".utf8), limit: 8) == []) // argc 거짓, 데이터 없음
        #expect(ProcArgs.parse(withUnsafeBytes(of: Int32(-3)) { Array($0) } + [0], limit: 8) == [])
    }
}

@Suite struct PolicyTests {
    @Test func batteryRetreat() {
        #expect(BatteryPolicy.shouldRetreat(.init(percent: 20, onBattery: true), floor: 20))
        #expect(BatteryPolicy.shouldRetreat(.init(percent: 21, onBattery: true), floor: 20) == false)
        #expect(BatteryPolicy.shouldRetreat(.init(percent: 5, onBattery: false), floor: 20) == false, "충전 중에는 철수하지 않음")
        #expect(BatteryPolicy.shouldRetreat(.init(percent: 5, onBattery: true), floor: nil) == false, "기준 끔")
        #expect(BatteryPolicy.shouldRetreat(nil, floor: 20) == false, "배터리 없는 데스크톱")
    }

    @Test func agentWatchTransitions() {
        #expect(AgentWatchPolicy.decide(agentsPresent: true, onDuty: false, lowBattery: false) == .engage)
        #expect(AgentWatchPolicy.decide(agentsPresent: true, onDuty: false, lowBattery: true) == .none, "배터리 부족이면 투입 안 함")
        #expect(AgentWatchPolicy.decide(agentsPresent: false, onDuty: true, lowBattery: false) == .handover)
        #expect(AgentWatchPolicy.decide(agentsPresent: true, onDuty: true, lowBattery: false) == .none)
        #expect(AgentWatchPolicy.decide(agentsPresent: false, onDuty: false, lowBattery: false) == .none)
    }

    @Test func pmsetParsing() {
        #expect(!PmsetParser.sleepDisabled(" SleepDisabled\t\t0\n sleep 1"))
        #expect(PmsetParser.sleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\n"))
        #expect(!PmsetParser.sleepDisabled(""))
    }

    @Test func clockFormat() {
        #expect(DutyClock.format(59) == "0:59")
        #expect(DutyClock.format(3903) == "1:05:03")
        #expect(DutyClock.format(-5) == "0:00")
    }
}

@Suite struct DutyLogTests {
    @Test func newestFirstAndCapped() {
        let log = DutyLog(fileURL: nil, capacity: 2)
        log.write("a"); log.write("b"); log.write("c")
        #expect(log.recent.map(\.text) == ["c", "b"])
    }

    @Test func appendsToFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("log.txt")
        let log = DutyLog(fileURL: url)
        log.write("근무 투입")
        log.write("근무 교대")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("근무 투입") && text.contains("근무 교대"))
        #expect(text.split(separator: "\n").count == 2)
    }

    private func tempLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("log.txt")
    }

    @Test func fileIsOwnerOnly() throws {
        let url = tempLogURL()
        DutyLog(fileURL: url).write("근무 투입")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        let dirPerms = try FileManager.default
            .attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(dirPerms == 0o700)
    }

    @Test func refusesToFollowSymlink() throws {
        let url = tempLogURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let victim = dir.appendingPathComponent("victim.txt")
        try "중요한 파일".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: victim)

        DutyLog(fileURL: url).write("덮어쓰기 시도")
        #expect(try String(contentsOf: victim, encoding: .utf8) == "중요한 파일")
    }

    @Test func rotatesWhenTooLarge() throws {
        let url = tempLogURL()
        let log = DutyLog(fileURL: url, maxFileBytes: 64)
        for i in 0..<10 { log.write("근무 기록 \(i)") }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size < 64 * 2)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("1").path))
    }

    @Test func newlinesCannotForgeEntries() throws {
        let url = tempLogURL()
        DutyLog(fileURL: url).write("정상\n2026-01-01T00:00:00Z  위조된 항목")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 1)
    }
}

@Suite struct SpriteTests {
    @Test(arguments: Sprites.Pose.allCases)
    func framesAre16x16WithKnownColors(pose: Sprites.Pose) {
        for frame in Sprites.frames(pose) {
            #expect(frame.height == 16)
            for row in frame.rows {
                #expect(row.count == 16, "행 길이 불일치: \(row)")
                for ch in row where ch != "." {
                    #expect(Palette.cgColor(ch) != nil, "팔레트에 없는 문자 '\(ch)'")
                }
            }
        }
    }

    @Test func appIconSceneIsSquare() {
        let scene = Sprites.appIconScene
        #expect(scene.height == 24)
        #expect(scene.rows.allSatisfy { $0.count == 24 })
    }

    @Test func mirroredFlipsRows() {
        let sprite = PixelSprite(["KY.", ".BU"])
        #expect(sprite.mirrored().rows == [".YK", "UB."])
        #expect(sprite.mirrored().mirrored() == sprite)
    }

    @Test func placingOverlaysOnlyOpaquePixels() {
        let base = PixelSprite(["...", "..."])
        let result = base.placing(PixelSprite(["K.", "YK"]), x: 1, y: 0)
        #expect(result.rows == [".K.", ".YK"])
    }
}
