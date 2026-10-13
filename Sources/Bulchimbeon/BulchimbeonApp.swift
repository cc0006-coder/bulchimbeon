import AppKit
import BulchimbeonCore
import SwiftUI

@main
struct BulchimbeonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var duty = DutyController.shared
    @StateObject private var animator = SpriteAnimator()

    var body: some Scene {
        MenuBarExtra {
            DutyMenu(duty: duty)
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 번들 밖(swift run)에서도 Dock 아이콘 없이 메뉴바 전용으로
        NSApp.setActivationPolicy(.accessory)

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

    var body: some View {
        Text("불침번 — \(duty.statusLine)")
        Text("“\(duty.quote)”")

        Divider()

        Menu("🪖 근무 서기") {
            ForEach(DutyController.durations, id: \.title) { option in
                Button(option.title) { Task { await duty.startTimed(option.seconds) } }
            }
        }
        Toggle("🤖 에이전트 근무 (자동 교대)", isOn: Binding(
            get: { duty.order == .agentWatch },
            set: { on in Task { on ? await duty.startAgentWatch() : await duty.stop() } }
        ))
        if duty.order != .off {
            Button("💤 근무 종료") { Task { await duty.stop() } }
        }

        Divider()

        Picker("근무 형태", selection: Binding(
            get: { duty.mode },
            set: { mode in Task { await duty.setMode(mode) } }
        )) {
            ForEach(DutyMode.allCases) { Text($0.title).tag($0) }
        }
        Picker("배터리 철수 기준", selection: $duty.batteryFloor) {
            ForEach(DutyController.batteryFloors, id: \.self) { floor in
                Text(floor == 0 ? "끄기" : "\(floor)% 이하").tag(floor)
            }
        }

        Divider()

        Text(duty.agentLine)
        if let batteryLine = duty.batteryLine { Text(batteryLine) }
        Menu("📒 근무일지") {
            if duty.recentLog.isEmpty {
                Text("기록 없음")
            }
            ForEach(Array(duty.recentLog.enumerated()), id: \.offset) { _, entry in
                Text(entry.line)
            }
            Divider()
            Button("전체 일지 열기…") {
                if let url = duty.logFileURL { NSWorkspace.shared.open(url) }
            }
        }
        if duty.showsLidRecovery {
            Button("⚠️ 덮개 잠자기 복구") { Task { await duty.restoreLid() } }
        }

        Divider()

        Toggle("로그인 시 자동 실행", isOn: Binding(
            get: { duty.launchAtLogin },
            set: { duty.setLaunchAtLogin($0) }
        ))
        Button("불침번 퇴근 (종료)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
