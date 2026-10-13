import AppKit
import BulchimbeonCore
import SwiftUI

@main
struct BulchimbeonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var duty = DutyController.shared
    @StateObject private var animator = SpriteAnimator()
    @StateObject private var patrol = PatrolController.shared

    init() {
        // Bulchimbeon.app/Contents/MacOS/Bulchimbeon --diagnose → 진단 출력 후 종료 (UI 없음)
        if CommandLine.arguments.contains("--diagnose") {
            let custom = UserDefaults.standard.stringArray(forKey: "customAgents") ?? []
            print(ProcessScanner.diagnose(custom: custom))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DutyMenu(duty: duty, patrol: patrol)
        } label: {
            MenuBarLabel(duty: duty, animator: animator)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var duty: DutyController
    @ObservedObject var animator: SpriteAnimator

    var body: some View {
        let frames = SpriteImages.frames(duty.pose)
        HStack(spacing: 3) {
            Image(nsImage: frames[animator.tick % frames.count])
            if let remaining = duty.remainingText {
                Text(remaining).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("불침번: ", "Bulchimbeon: ") + duty.statusLine)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 번들 밖(swift run)에서도 Dock 아이콘 없이 메뉴바 전용으로
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated { PatrolController.shared.start() }

        // --demo → 녹화용 연출 후 종료
        if CommandLine.arguments.contains("--demo") {
            MainActor.assumeIsolated { DemoDirector.run() }
            return
        }

        // open -a Bulchimbeon --args --agent-watch  → 실행과 동시에 에이전트 근무
        if CommandLine.arguments.contains("--agent-watch") {
            Task { @MainActor in await DutyController.shared.startAgentWatch() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { DutyController.shared.shutdown() }
    }
}

struct DutyMenu: View {
    @ObservedObject var duty: DutyController
    @ObservedObject var patrol: PatrolController

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    private static let repoURL = URL(string: "https://github.com/s3onghyun/bulchimbeon")!

    var body: some View {
        Text(L10n.t("불침번 — ", "Bulchimbeon — ") + duty.statusLine)
        Text("“\(duty.quote)”")

        Divider()

        Menu(L10n.t("🪖 근무 서기", "🪖 Stand watch")) {
            ForEach(DutyController.durations, id: \.title) { option in
                Button(option.title) { Task { await duty.startTimed(option.seconds) } }
            }
        }
        Toggle(L10n.t("🤖 에이전트 근무 (자동 교대)", "🤖 Agent watch (auto shift)"), isOn: Binding(
            get: { duty.order == .agentWatch },
            set: { on in Task { on ? await duty.startAgentWatch() : await duty.stop() } }
        ))
        Toggle(L10n.t("열려만 있는 세션도 근무로 인정", "Count idle sessions as working"), isOn: $duty.countIdleSessions)
        if duty.order != .off {
            Button(L10n.t("💤 근무 종료", "💤 Stand down")) { Task { await duty.stop() } }
        }

        Divider()

        Picker(L10n.t("근무 형태", "Watch mode"), selection: Binding(
            get: { duty.mode },
            set: { mode in Task { await duty.setMode(mode) } }
        )) {
            ForEach(DutyMode.allCases) { Text($0.title).tag($0) }
        }
        Toggle(L10n.t("🚶 순찰 모드 (화면 위 이등병)", "🚶 Patrol mode (soldier on screen)"), isOn: $patrol.enabled)
        if patrol.enabled {
            Picker(L10n.t("이등병 크기", "Soldier size"), selection: $patrol.scale) {
                ForEach(PatrolController.scales, id: \.self) { Text("\($0)×").tag($0) }
            }
        }
        Picker(L10n.t("배터리 철수 기준", "Stand down on battery"), selection: $duty.batteryFloor) {
            ForEach(DutyController.batteryFloors, id: \.self) { floor in
                Text(floor == 0 ? L10n.t("끄기", "Never") : L10n.t("\(floor)% 이하", "At \(floor)% or below")).tag(floor)
            }
        }

        Divider()

        Text(duty.agentLine)
        if let batteryLine = duty.batteryLine { Text(batteryLine) }
        if let heatLine = duty.heatLine { Text(heatLine) }
        Menu(L10n.t("📒 근무일지", "📒 Duty log")) {
            if duty.recentLog.isEmpty {
                Text(L10n.t("기록 없음", "No entries"))
            }
            ForEach(Array(duty.recentLog.enumerated()), id: \.offset) { _, entry in
                Text(entry.line)
            }
            Divider()
            Button(L10n.t("전체 일지 열기…", "Open full log…")) {
                if let url = duty.logFileURL { NSWorkspace.shared.open(url) }
            }
        }
        if duty.showsLidRecovery {
            Button(L10n.t("⚠️ 덮개 잠자기 복구", "⚠️ Restore lid sleep")) { Task { await duty.restoreLid() } }
        }

        Divider()

        Toggle(L10n.t("로그인 시 자동 실행", "Launch at login"), isOn: Binding(
            get: { duty.launchAtLogin },
            set: { duty.setLaunchAtLogin($0) }
        ))
        Button(L10n.t("불침번 v\(Self.version) · GitHub", "Bulchimbeon v\(Self.version) · GitHub")) {
            NSWorkspace.shared.open(Self.repoURL)
        }
        Button(L10n.t("불침번 퇴근 (종료)", "Quit Bulchimbeon")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
