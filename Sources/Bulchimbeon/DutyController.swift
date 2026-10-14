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
        case .display: L10n.t("화면 켜둠 (caffeinate -d)", "Keep display on (caffeinate -d)")
        case .system: L10n.t("화면은 꺼져도 맥은 깨어 있음 (caffeinate -i)", "Display may sleep, Mac stays awake (caffeinate -i)")
        case .lid: L10n.t("덮개 닫아도 깨어 있음 (관리자 권한)", "Stay awake with lid closed (admin)")
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
        (L10n.t("30분", "30 min"), 1800), (L10n.t("1시간", "1 hour"), 3600), (L10n.t("2시간", "2 hours"), 7200),
        (L10n.t("4시간", "4 hours"), 14400), (L10n.t("무기한", "Indefinitely"), nil),
    ]
    static let batteryFloors = [10, 20, 30, 0] // 0 = 끄기

    @Published private(set) var order: DutyOrder = .off {
        didSet { saveOrder() }
    }
    @Published private(set) var isOnDuty = false
    @Published private(set) var agents: [AgentKind: Int] = [:]
    @Published private(set) var agentStatus: [AgentKind: AgentActivity.Status] = [:]
    /// true 면 예전 방식: 에이전트가 열려 있기만 해도 근무 (기본 false = 일할 때만)
    @Published var countIdleSessions: Bool {
        didSet { defaults.set(countIdleSessions, forKey: Keys.countIdleSessions) }
    }
    /// 모든 에이전트가 조용해진 뒤 교대까지 기다리는 분
    @Published var graceMinutes: Int {
        didSet { defaults.set(graceMinutes, forKey: Keys.graceMinutes) }
    }
    static let graceOptions = [1, 3, 5, 10]
    /// 에이전트 근무 중 "왜 근무 중인지 / 언제 교대하는지" (메뉴 표시용)
    @Published private(set) var watchDetail: String?
    /// 이 앱 말고 화면 꺼짐 / 잠자기를 막고 있는 다른 앱
    @Published private(set) var otherHolders: (display: [String], system: [String]) = ([], [])
    @Published private(set) var battery: BatteryStatus?
    @Published private(set) var lidSleepDisabled = false
    @Published private(set) var heat: HeatLevel = .normal
    /// 폭염 경보로 근무를 잠시 멈춘 상태 (식으면 자동 복귀)
    @Published private(set) var resting = false
    @Published private(set) var now = Date()
    @Published private(set) var quote = Lines.pick(Lines.off())
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
        static let order = "dutyOrder"
        static let orderUntil = "dutyOrderUntil"
        static let simulateHeat = "simulateHeat"
        static let countIdleSessions = "agentWatchCountsIdle"
        static let graceMinutes = "agentGraceMinutes"
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
    private var lastScan = Date.distantPast
    private var lastBusyAt: Date?
    private var watchStartedAt = Date()
    private var cpuHistory = CPUHistory(window: 60)
    private var heatAdvised = false
    private var coolSince: Date?
    /// 화면이 잠긴 시각 (당직 근무 인수인계용)
    private var lockedAt: Date?
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
        countIdleSessions = defaults.bool(forKey: Keys.countIdleSessions)
        let storedGrace = defaults.object(forKey: Keys.graceMinutes) as? Int ?? 5
        graceMinutes = Self.graceOptions.contains(storedGrace) ? storedGrace : 5
        lidSleepDisabled = SystemProbes.lidSleepDisabled()

        if !lidSleepDisabled && lidEngagedByUs {
            lidEngagedByUs = false // 당직 감시병이 이미 원복함
        }
        if lidSleepDisabled && lidEngagedByUs {
            writeLog(L10n.t("⚠️ 지난 근무 비정상 종료 — 덮개 잠자기가 꺼진 채 남아 있음", "⚠️ Last watch ended abnormally — lid sleep still disabled"))
            notifier.send(Lines.lidLeftOn())
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DutyController.shared.screenLocked() }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DutyController.shared.screenUnlocked() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task {
            await resume()
            await tick()
        }
    }

    // MARK: - 메뉴 표시

    var pose: Sprites.Pose {
        if let demoPose { return demoPose }
        if resting { return .heat }
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
        if resting {
            return L10n.t("전투휴식 중 (폭염 경보) — 식으면 복귀", "Combat rest (heat warning) — resumes when cool")
        }
        if isOnDuty, let remainingText {
            return L10n.t("근무 중 · \(remainingText) 남음", "On duty · \(remainingText) left")
        }
        if isOnDuty, let dutyStartedAt {
            let elapsed = DutyClock.format(now.timeIntervalSince(dutyStartedAt))
            return L10n.t("근무 중 · \(elapsed) 경과", "On duty · \(elapsed)")
        }
        return order == .agentWatch ? L10n.t("에이전트 근무 대기 중", "Waiting for agents") : L10n.t("취침 중", "Off duty")
    }

    var agentLine: String {
        let summary = AgentCatalog.summary(agents)
        guard !summary.isEmpty else { return L10n.t("감지된 에이전트 없음", "No agents detected") }
        let busy = agentStatus.values.reduce(0) { $0 + $1.busy }
        return L10n.t("감지된 에이전트: \(summary) · 작업 중 \(busy)", "Agents: \(summary) · \(busy) working")
    }

    var batteryLine: String? {
        battery.map { "🔋 \($0.percent)%" + ($0.onBattery ? "" : L10n.t(" (전원 연결)", " (charging)")) }
    }

    var heatLine: String? {
        switch heat {
        case .advisory: L10n.t("🌡️ 폭염 주의보", "🌡️ Heat advisory")
        case .alert: L10n.t("🔥 폭염 경보", "🔥 Heat warning")
        case .normal, .caution: nil
        }
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
        notifier.send(Lines.reportForDuty())
        say(Lines.Speech.reporting())
        let length = Self.durations.first { $0.seconds == duration }?.title ?? L10n.t("무기한", "Indefinitely")
        writeLog(L10n.t("근무 투입 — \(length), \(mode.title)", "On duty — \(length), \(mode.title)"), kind: .onDuty)
    }

    func startAgentWatch() async {
        watchStartedAt = Date()
        order = .agentWatch
        quote = Lines.pick(Lines.standby())
        writeLog(L10n.t("에이전트 근무 대기 시작", "Started waiting for agents"))
        await tick()
    }

    func stop() async {
        await standDown(notice: nil, logText: L10n.t("근무 종료 (수동)", "Off duty (manual)"))
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
            writeLog(L10n.t("덮개 잠자기 복구 완료", "Lid sleep restored"))
        }
    }

    // MARK: - 언어

    var languagePreference: L10n.Preference {
        let appDomain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) }
        return L10n.Preference(appDomainLanguages: appDomain?["AppleLanguages"] as? [String])
    }

    /// 언어를 바꾸고 앱을 다시 띄운다. 근무 상태는 저장돼 있어 재시작 후 이어진다.
    func setLanguage(_ preference: L10n.Preference) {
        guard preference != languagePreference else { return }
        if let languages = preference.appleLanguages {
            defaults.set(languages, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.synchronize()
        writeLog(L10n.t("언어 변경 → ", "Language → ") + preference.title)
        relaunch()
    }

    /// 1초 뒤 같은 앱을 다시 연다. 앱 경로는 셸 문자열에 넣지 않고 인자($0)로 넘긴다.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        process.environment = ["PATH": "/usr/bin:/bin"]
        try? process.run()
        NSApp.terminate(nil)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            writeLog(L10n.t("로그인 자동 실행 설정 실패: ", "Launch at login failed: ") + error.localizedDescription)
        }
        objectWillChange.send()
    }

    /// 앱 종료 시 동기 정리. 덮개 플래그는 반드시 되돌린다.
    func shutdown() {
        assertion.release()
        guard lidEngagedByUs else { return }
        // 당직 감시병이 살아 있으면 종료 후 5초 안에 원복하므로 암호 창을 띄우지 않는다
        if SystemProbes.lidWatchdogAlive() { return }
        if SystemProbes.setLidSleepDisabled(false) { lidEngagedByUs = false }
    }

    // MARK: - 당직 근무 인수인계

    func screenLocked() {
        lockedAt = Date()
    }

    func screenUnlocked() {
        defer { lockedAt = nil }
        guard let lockedAt,
              let report = HandoverReport.make(entries: log.recent, awayFrom: lockedAt, until: Date())
        else { return }
        notifier.send(report)
        say(Lines.Speech.handoverReport(), seconds: 6)
    }

    /// 녹화용 연출: 대기 → 출근 → 순찰 → 폭염 주의보 → 전투휴식 → 복귀 → 교대 경례 → 취침
    func playDemo() async {
        let steps: [(pose: Sprites.Pose, line: String?, seconds: Double)] = [
            (.standby, Lines.Speech.waiting(), 3.5),
            (.duty, Lines.Speech.arrived(), 3),
            (.duty, nil, 2),
            (.duty, Lines.Speech.heat(), 3),
            (.heat, Lines.Speech.rest(), 4),
            (.duty, Lines.Speech.backFromRest(), 3),
            (.salute, Lines.Speech.handover(), 4),
            (.sleeping, nil, 1.5),
        ]
        for step in steps {
            demoPose = step.pose
            if let line = step.line { say(line, seconds: step.seconds) }
            try? await Task.sleep(for: .seconds(step.seconds))
        }
    }

    // MARK: - 재시작 복귀

    private func saveOrder() {
        switch order {
        case .off:
            defaults.removeObject(forKey: Keys.order)
            defaults.removeObject(forKey: Keys.orderUntil)
        case .agentWatch:
            defaults.set("agentWatch", forKey: Keys.order)
            defaults.removeObject(forKey: Keys.orderUntil)
        case .timed(let until):
            defaults.set("timed", forKey: Keys.order)
            if let until { defaults.set(until.timeIntervalSince1970, forKey: Keys.orderUntil) }
            else { defaults.removeObject(forKey: Keys.orderUntil) }
        }
    }

    /// 앱 재시작·업데이트·재부팅 후 저장된 근무를 이어간다.
    private func resume() async {
        guard !CommandLine.arguments.contains("--demo") else { return }
        let action = DutyResume.decide(stored: defaults.string(forKey: Keys.order),
                                       until: defaults.object(forKey: Keys.orderUntil) as? Double,
                                       now: Date())
        if action == .none { return }
        if action == .expired {
            order = .off
            writeLog(L10n.t("앱이 꺼져 있는 동안 근무 시간 종료", "Watch ended while the app was closed"))
            return
        }

        // 로그인 직후 예고 없는 관리자 암호 창은 피싱처럼 보인다 → 덮개 근무는 시스템 근무로 복귀
        if mode == .lid && !lidSleepDisabled {
            mode = .system
            notifier.send(Lines.lidResumeFallback())
            writeLog(L10n.t("덮개 근무 → 시스템 근무로 복귀 (관리자 재승인 필요)", "Lid-closed watch → resumed as system watch (admin approval needed)"))
        }

        switch action {
        case .agentWatch:
            watchStartedAt = Date()
            order = .agentWatch
            quote = Lines.pick(Lines.standby())
            writeLog(L10n.t("근무 복귀 — 에이전트 근무", "Back on watch — agent watch"))
        case .timed(let until):
            order = .timed(until: until)
            await engage()
            say(Lines.Speech.resumed())
            let left = until.map { DutyClock.format($0.timeIntervalSinceNow) }
            writeLog(L10n.t("근무 복귀 — ", "Back on watch — ")
                     + (left.map { L10n.t("남은 시간 \($0)", "\($0) left") } ?? L10n.t("무기한", "indefinitely")))
        case .none, .expired:
            break
        }
    }

    // MARK: - 근무 사이클

    private func tick() async {
        guard !ticking, demoPose == nil else { return }
        ticking = true
        defer { ticking = false }

        // 근무가 없으면 프로세스 스캔은 30초에 한 번 (메뉴 표시용), 근무 중엔 5초마다
        let scanAgents = order != .off || Date().timeIntervalSince(lastScan) >= 30
        let customAgents = defaults.stringArray(forKey: Keys.customAgents) ?? []
        let (scanned, battery, assertions) = await Task.detached {
            (scanAgents ? SystemProbes.processes() : nil, SystemProbes.battery(), PowerHolderProbe.assertions())
        }.value
        otherHolders = PowerHolders.summarize(assertions, ownPID: getpid())
        now = Date()
        if let scanned {
            let cpu = cpuHistory.add(scanned.cpuTimes, at: now)
            agentStatus = AgentActivity.evaluate(scanned.snapshots, cpu: cpu,
                                                 kinds: AgentCatalog.builtIn + AgentCatalog.customKinds(customAgents))
            agents = agentStatus.mapValues(\.present).filter { $0.value > 0 }
            lastScan = now
        }
        self.battery = battery
        let floor = batteryFloor > 0 ? batteryFloor : nil

        if isOnDuty, BatteryPolicy.shouldRetreat(battery, floor: floor), let battery {
            await standDown(notice: Lines.batteryRetreat(battery.percent),
                            logText: L10n.t("배터리 \(battery.percent)% — 근무 철수", "Battery \(battery.percent)% — stood down"))
            return
        }

        // 폭염 대응
        heat = currentHeat()
        if heat <= .caution {
            if coolSince == nil { coolSince = now }
            heatAdvised = false
        } else {
            coolSince = nil
        }
        switch HeatPolicy.decide(level: heat, onDuty: isOnDuty, resting: resting, advised: heatAdvised,
                                 coolSince: coolSince, now: now) {
        case .advisory:
            heatAdvised = true
            notifier.send(Lines.heatAdvisory())
            say(Lines.Speech.heat(), seconds: 6)
            writeLog(L10n.t("폭염 주의보 발령", "Heat advisory"), kind: .heat)
        case .rest:
            resting = true
            await disengage()
            notifier.send(Lines.heatRest())
            say(Lines.Speech.rest(), seconds: 8)
            writeLog(L10n.t("폭염 경보 — 전투휴식 실시", "Heat warning — combat rest"), kind: .heat)
        case .resume:
            resting = false
            let lidDowngraded = mode == .lid
            if lidDowngraded { mode = .system } // 과열 직후엔 덮개 근무로 돌아가지 않는다
            notifier.send(Lines.heatResume(lidDowngraded: lidDowngraded))
            say(Lines.Speech.backFromRest(), seconds: 6)
            writeLog(L10n.t("전투휴식 종료 — 근무 복귀", "Combat rest over — back on watch"), kind: .onDuty)
            if case .timed = order { await engage() } // 에이전트 근무는 아래에서 다시 판단
        case .none:
            break
        }
        if resting { return }

        // 근무지 이탈 감지: 들고 있어야 할 assertion 이 사라졌으면 즉시 재투입
        if isOnDuty && !assertion.isActuallyHeld() {
            assertion.reacquire()
            notifier.send(Lines.postAbandoned())
            say(Lines.Speech.notAWOL(), seconds: 6)
            writeLog(L10n.t("⚠️ 근무지 이탈 감지 — 즉시 재투입", "⚠️ Post abandoned — re-engaged"), kind: .awol)
        }

        switch order {
        case .off:
            break
        case .timed(let until):
            if let until, now >= until {
                saluteUntil = Date().addingTimeInterval(10)
                say(Lines.Speech.timeUp(), seconds: 8)
                await standDown(notice: Lines.timeUp(), logText: L10n.t("근무 시간 종료", "Watch time over"))
            }
        case .agentWatch:
            // 일할 때만 근무: 투입은 지금 일하는 에이전트가 있을 때, 교대는 유예 시간 넘게 조용할 때
            let busy = agentStatus.mapValues(\.busy).filter { $0.value > 0 }
            let busyNow: Bool
            if countIdleSessions {
                busyNow = !agents.isEmpty
                if busyNow { lastAgentSummary = AgentCatalog.summary(agents) }
            } else {
                busyNow = !busy.isEmpty
                if busyNow { lastAgentSummary = AgentCatalog.summary(busy) }
            }
            if busyNow { lastBusyAt = now }
            if lastAgentSummary.isEmpty { lastAgentSummary = L10n.t("에이전트", "Agents") }
            let quiet = AgentWatchPolicy.quietFor(now: now, lastBusyAt: lastBusyAt, watchStartedAt: watchStartedAt)
            let grace = TimeInterval(graceMinutes * 60)
            watchDetail = Self.watchDetail(busyNow: busyNow, countIdle: countIdleSessions, summary: lastAgentSummary,
                                           openCount: agents.values.reduce(0, +), onDuty: isOnDuty, quiet: quiet, grace: grace)

            switch AgentWatchPolicy.decide(busyNow: busyNow, quietFor: quiet, grace: grace, onDuty: isOnDuty,
                                           lowBattery: BatteryPolicy.shouldRetreat(battery, floor: floor) || heat >= .alert) {
            case .engage:
                await engage()
                notifier.send(Lines.agentArrived(lastAgentSummary))
                say(Lines.Speech.arrived())
                writeLog(L10n.t("근무 투입 — \(lastAgentSummary) 출근", "On duty — \(lastAgentSummary) clocked in"), kind: .onDuty)
            case .handover:
                await disengage()
                quote = Lines.pick(Lines.standby())
                saluteUntil = Date().addingTimeInterval(10)
                notifier.send(Lines.handover(lastAgentSummary))
                say(Lines.Speech.handover(), seconds: 8)
                writeLog(L10n.t("근무 교대 — \(lastAgentSummary) 작업 종료, 이상 무", "Shift over — \(lastAgentSummary) finished, all clear"), kind: .handover)
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
                notifier.send(Lines.lidFallback())
                writeLog(L10n.t("덮개 근무 승인 거부 — 시스템 근무로 대체", "Lid-closed watch denied — switched to system watch"))
            }
        }
        assertion.acquire(mode == .display ? .display : .system,
                          reason: "Bulchimbeon on duty: keeping AI agents awake") // pmset 은 비ASCII 를 빈 문자열로 표시
        if !isOnDuty { dutyStartedAt = Date() }
        isOnDuty = assertion.isHeld
        quote = Lines.pick(Lines.onDuty())
    }

    private func disengage() async {
        assertion.release()
        isOnDuty = false
        dutyStartedAt = nil
        if lidEngagedByUs { await restoreLid() }
    }

    private func standDown(notice: (title: String, body: String)?, logText: String) async {
        await disengage()
        resting = false
        order = .off
        quote = Lines.pick(Lines.off())
        if let notice { notifier.send(notice) }
        writeLog(logText, kind: .standDown)
    }

    static func watchDetail(busyNow: Bool, countIdle: Bool, summary: String, openCount: Int,
                            onDuty: Bool, quiet: TimeInterval, grace: TimeInterval) -> String? {
        if countIdle && busyNow {
            return L10n.t("열린 세션 \(openCount)개 (열린 세션 인정 모드)", "\(openCount) open session(s) (counting idle sessions)")
        }
        if busyNow { return L10n.t("\(summary) 작업 중", "\(summary) working") }
        guard onDuty else { return nil }
        return L10n.t("조용해진 지 \(DutyClock.format(quiet)) · 교대까지 \(DutyClock.format(grace - quiet))",
                      "Quiet for \(DutyClock.format(quiet)) · shift over in \(DutyClock.format(grace - quiet))")
    }

    /// 실제 발열 단계. `defaults write ... simulateHeat advisory|alert|normal` 로 시험할 수 있다 (지우면 실제 값).
    private func currentHeat() -> HeatLevel {
        if let name = defaults.string(forKey: Keys.simulateHeat), let simulated = HeatLevel(name: name) {
            return simulated
        }
        return HeatLevel(ProcessInfo.processInfo.thermalState)
    }

    private func writeLog(_ text: String, kind: DutyLogEntry.Kind = .other) {
        log.write(text, kind: kind)
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
