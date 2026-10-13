import Foundation
import Testing
@testable import BulchimbeonCore

@Suite struct AgentCatalogTests {
    @Test func nativeClaudeCode() {
        #expect(AgentCatalog.match(commandLine: "claude -c --dangerously-skip-permissions")?.id == "claude-code")
        #expect(AgentCatalog.match(commandLine: "/Users/me/.local/bin/claude")?.id == "claude-code")
    }

    @Test func npmInstalledAgents() {
        #expect(AgentCatalog.match(commandLine:
            "node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js --resume")?.id == "claude-code")
        #expect(AgentCatalog.match(commandLine:
            "node /usr/local/lib/node_modules/@openai/codex/bin/codex.js")?.id == "codex")
        #expect(AgentCatalog.match(commandLine: "/opt/homebrew/bin/codex exec fix")?.id == "codex")
        #expect(AgentCatalog.match(commandLine: "gemini")?.id == "gemini-cli")
    }

    @Test func hookScriptsAreNotAgents() {
        // 실측: Claude Code hook 은 node -e 로 .claude 경로를 참조한다
        let hook = "node -e const f=require('fs'),p=require('path');const C=p.join(h,'.claude')"
        #expect(AgentCatalog.match(commandLine: hook) == nil)
        #expect(AgentCatalog.match(commandLine: "/bin/zsh -c source /Users/me/.claude/shell-snapshots/x.sh") == nil)
    }

    @Test func desktopAppIsNotAnAgent() {
        #expect(AgentCatalog.match(commandLine: "/Applications/Claude.app/Contents/MacOS/Claude") == nil)
        #expect(AgentCatalog.match(commandLine:
            "/Applications/Claude.app/Contents/Helpers/chrome-native-host chrome-extension://x/") == nil)
    }

    @Test func countAndSummary() {
        let ps = """
        claude -c
        claude --resume
        node -e require('.claude')
        /opt/homebrew/bin/codex
        /bin/zsh
        """
        let counts = AgentCatalog.count(psOutput: ps)
        #expect(counts.values.reduce(0, +) == 3)
        #expect(AgentCatalog.summary(counts) == "Claude Code ×2, Codex")
        #expect(AgentCatalog.summary([:]) == "")
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
