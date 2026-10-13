import AppKit
import BulchimbeonCore
import Foundation
import ServiceManagement
import UserNotifications

enum DutyMode: String, CaseIterable, Identifiable {
    case display, system, lid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .display: "화면까지 켜두기"
        case .system: "시스템만 깨우기"
        case .lid: "덮개 닫아도 근무 (관리자 권한)"
        }
    }
}

enum DutyOrder: Equatable {
    case off
    case timed(until: Date?) // nil = 무기한
    case agentWatch
}

/// 불침번 상태 머신. 5초마다 에이전트·배터리·타이머를 점검한다.
@MainActor
final class DutyController: ObservableObject {
    static let shared = DutyController()

    static let durations: [(title: String, seconds: TimeInterval?)] = [
        ("30분", 1800), ("1시간", 3600), ("2시간", 7200), ("4시간", 14400), ("무기한", nil),
    ]
    static let batteryFloors = [10, 20, 30, 0] // 0 = 끄기

    @Published private(set) var order: DutyOrder = .off
    @Published private(set) var isOnDuty = false
    @Published private(set) var agents: [AgentKind: Int] = [:]
    @Published private(set) var battery: BatteryStatus?
    @Published private(set) var lidSleepDisabled = false
    @Published private(set) var now = Date()
    @Published private(set) var quote = Lines.pick(Lines.off)
    @Published private(set) var mode: DutyMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }
    @Published var batteryFloor: Int {
        didSet { defaults.set(batteryFloor, forKey: Keys.batteryFloor) }
    }

    private enum Keys {
        static let mode = "dutyMode"
        static let batteryFloor = "batteryFloor"
        static let lidEngagedByUs = "lidEngagedByUs"
        static let customAgents = "customAgents"
    }

    private let defaults = UserDefaults.standard
    private let log = DutyLog(fileURL: DutyLog.defaultFileURL)
    private let assertion = PowerAssertion()
    private let notifier = Notifier()
    private var dutyStartedAt: Date?
    /// 근무 교대·종료 직후 잠깐 경례 포즈
    private var saluteUntil: Date?
    /// 순찰 이등병 말풍선
    private var speech: (text: String, until: Date)?
    /// --demo 연출 중이면 실제 상태 대신 이 포즈
    @Published private var demoPose: Sprites.Pose?
    private var lastAgentSummary = ""
    private var ticking = false
    private var timer: Timer?

    /// 덮개 플래그를 이 앱이 켰는지. 비정상 종료 후 복구 판단용으로 영속화한다.
    private var lidEngagedByUs: Bool {
        get { defaults.bool(forKey: Keys.lidEngagedByUs) }
        set { defaults.set(newValue, forKey: Keys.lidEngagedByUs) }
    }

    private init() {
        mode = DutyMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .system
        // defaults 는 사용자가 `defaults write` 로 바꿀 수 있으므로 허용된 값만 받는다
        let storedFloor = defaults.object(forKey: Keys.batteryFloor) as? Int ?? 20
        batteryFloor = Self.batteryFloors.contains(storedFloor) ? storedFloor : 20
        lidSleepDisabled = SystemProbes.lidSleepDisabled()

        if lidSleepDisabled && lidEngagedByUs {
            writeLog("⚠️ 지난 근무 비정상 종료 — 덮개 잠자기가 꺼진 채 남아 있음")
            notifier.send(Lines.lidLeftOn)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { await tick() }
    }

    // MARK: - 메뉴 표시

    var pose: Sprites.Pose {
        if let demoPose { return demoPose }
        if let saluteUntil, Date() < saluteUntil { return .salute }
        if isOnDuty { return .duty }
        return order == .agentWatch ? .standby : .sleeping
    }

    var currentSpeech: String? {
        guard let speech, Date() < speech.until else { return nil }
        return speech.text
    }

    private func say(_ text: String, seconds: TimeInterval = 4) {
        speech = (text, Date().addingTimeInterval(seconds))
    }

    /// 시간제 근무의 남은 시간 (메뉴바 표시용)
    var remainingText: String? {
        guard case .timed(let until?) = order else { return nil }
        return DutyClock.format(until.timeIntervalSinceNow)
    }

    var statusLine: String {
        if isOnDuty, let dutyStartedAt {
            return "근무 중 · \(DutyClock.format(now.timeIntervalSince(dutyStartedAt))) 경과"
        }
        return order == .agentWatch ? "에이전트 근무 대기 중" : "취침 중"
    }

    var agentLine: String {
        let summary = AgentCatalog.summary(agents)
        return summary.isEmpty ? "감지된 에이전트 없음" : "감지된 에이전트: \(summary)"
    }

    var batteryLine: String? {
        battery.map { "🔋 \($0.percent)%" + ($0.onBattery ? "" : " (전원 연결)") }
    }

    var recentLog: [DutyLogEntry] { Array(log.recent.prefix(10)) }
    var logFileURL: URL? { DutyLog.defaultFileURL }

    /// 근무 중이 아닌데 덮개 플래그가 켜져 있으면 복구 버튼을 보여준다.
    var showsLidRecovery: Bool { lidSleepDisabled && !(isOnDuty && mode == .lid) }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    // MARK: - 명령

    func startTimed(_ duration: TimeInterval?) async {
        order = .timed(until: duration.map { Date().addingTimeInterval($0) })
        await engage()
        notifier.send(Lines.reportForDuty)
        say("근무 서겠습니다! 🫡")
        let length = Self.durations.first { $0.seconds == duration }?.title ?? "무기한"
        writeLog("근무 투입 — \(length), \(mode.title)")
    }

    func startAgentWatch() async {
        order = .agentWatch
        quote = Lines.pick(Lines.standby)
        writeLog("에이전트 근무 대기 시작")
        await tick()
    }

    func stop() async {
        await standDown(notice: nil, logText: "근무 종료 (수동)")
    }

    func setMode(_ newMode: DutyMode) async {
        guard newMode != mode else { return }
        let leavingLid = mode == .lid
        mode = newMode
        guard isOnDuty else { return }
        if leavingLid && lidEngagedByUs { await restoreLid() }
        await engage()
    }

    func restoreLid() async {
        let ok = await Task.detached { SystemProbes.setLidSleepDisabled(false) }.value
        if ok {
            lidEngagedByUs = false
            lidSleepDisabled = false
            writeLog("덮개 잠자기 복구 완료")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            writeLog("로그인 자동 실행 설정 실패: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    /// 앱 종료 시 동기 정리. 덮개 플래그는 반드시 되돌린다.
    func shutdown() {
        assertion.release()
        if lidEngagedByUs && SystemProbes.setLidSleepDisabled(false) {
            lidEngagedByUs = false
        }
    }

    /// 녹화용 연출: 대기 → 출근 → 순찰 → 교대 경례 → 취침
    func playDemo() async {
        let steps: [(pose: Sprites.Pose, line: String?, seconds: Double)] = [
            (.standby, "에이전트 출근 기다리는 중 👀", 3.5),
            (.duty, "근무 투입! 이상 무!", 3),
            (.duty, nil, 6),
            (.salute, "근무 교대합니다! 🫡", 4),
            (.sleeping, nil, 1.5),
        ]
        for step in steps {
            demoPose = step.pose
            if let line = step.line { say(line, seconds: step.seconds) }
            try? await Task.sleep(for: .seconds(step.seconds))
        }
    }

    // MARK: - 근무 사이클

    private func tick() async {
        guard !ticking, demoPose == nil else { return }
        ticking = true
        defer { ticking = false }

        let customAgents = defaults.stringArray(forKey: Keys.customAgents) ?? []
        let (agents, battery) = await Task.detached {
            (SystemProbes.agents(custom: customAgents), SystemProbes.battery())
        }.value
        now = Date()
        self.agents = agents
        self.battery = battery
        let floor = batteryFloor > 0 ? batteryFloor : nil

        if isOnDuty, BatteryPolicy.shouldRetreat(battery, floor: floor), let battery {
            await standDown(notice: Lines.batteryRetreat(battery.percent), logText: "배터리 \(battery.percent)% — 근무 철수")
            return
        }

        switch order {
        case .off:
            break
        case .timed(let until):
            if let until, now >= until {
                saluteUntil = Date().addingTimeInterval(10)
                say("근무 끝! 충성! 🫡", seconds: 8)
                await standDown(notice: Lines.timeUp, logText: "근무 시간 종료")
            }
        case .agentWatch:
            let present = !agents.isEmpty
            if present { lastAgentSummary = AgentCatalog.summary(agents) }

            switch AgentWatchPolicy.decide(agentsPresent: present, onDuty: isOnDuty,
                                           lowBattery: BatteryPolicy.shouldRetreat(battery, floor: floor)) {
            case .engage:
                await engage()
                notifier.send(Lines.agentArrived(lastAgentSummary))
                say("근무 투입! 이상 무!")
                writeLog("근무 투입 — \(lastAgentSummary) 출근")
            case .handover:
                await disengage()
                quote = Lines.pick(Lines.standby)
                saluteUntil = Date().addingTimeInterval(10)
                notifier.send(Lines.handover(lastAgentSummary))
                say("근무 교대합니다! 🫡", seconds: 8)
                writeLog("근무 교대 — \(lastAgentSummary) 작업 종료, 이상 무")
            case .none:
                break
            }
        }
    }

    private func engage() async {
        if mode == .lid && !lidSleepDisabled {
            let ok = await Task.detached { SystemProbes.setLidSleepDisabled(true) }.value
            if ok {
                lidEngagedByUs = true
                lidSleepDisabled = true
            } else {
                mode = .system
                notifier.send(Lines.lidFallback)
                writeLog("덮개 근무 승인 거부 — 시스템 근무로 대체")
            }
        }
        assertion.acquire(mode == .display ? .display : .system,
                          reason: "Bulchimbeon on duty: keeping AI agents awake") // pmset 은 비ASCII 를 빈 문자열로 표시
        if !isOnDuty { dutyStartedAt = Date() }
        isOnDuty = assertion.isHeld
        quote = Lines.pick(Lines.onDuty)
    }

    private func disengage() async {
        assertion.release()
        isOnDuty = false
        dutyStartedAt = nil
        if lidEngagedByUs { await restoreLid() }
    }

    private func standDown(notice: (title: String, body: String)?, logText: String) async {
        await disengage()
        order = .off
        quote = Lines.pick(Lines.off)
        if let notice { notifier.send(notice) }
        writeLog(logText)
    }

    private func writeLog(_ text: String) {
        log.write(text)
        objectWillChange.send()
    }
}

/// 알림 전송. `swift run` 처럼 번들 밖에서 실행되면 UNUserNotificationCenter 가 크래시하므로 stdout 으로 대체한다.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier != nil ? .current() : nil

    override init() {
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(_ notice: (title: String, body: String)) {
        guard let center else {
            print("[불침번] \(notice.title) — \(notice.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // 메뉴가 열려 있어 앱이 활성 상태여도 배너를 보여준다
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
