import Foundation

public struct BatteryStatus: Equatable, Sendable {
    public let percent: Int
    public let onBattery: Bool
    public init(percent: Int, onBattery: Bool) {
        self.percent = percent
        self.onBattery = onBattery
    }
}

public enum BatteryPolicy {
    /// 배터리 사용 중이고 잔량이 기준 이하이면 철수. floor 가 nil 이면 철수하지 않는다.
    public static func shouldRetreat(_ status: BatteryStatus?, floor: Int?) -> Bool {
        guard let status, let floor, status.onBattery else { return false }
        return status.percent <= floor
    }
}

/// 에이전트 근무 모드의 교대 판단.
public enum AgentWatchPolicy {
    public enum Action: Equatable { case engage, handover, none }

    public static func decide(agentsPresent: Bool, onDuty: Bool, lowBattery: Bool) -> Action {
        switch (agentsPresent, onDuty) {
        case (true, false): lowBattery ? .none : .engage
        case (false, true): .handover
        default: .none
        }
    }
}

public enum PmsetParser {
    /// `pmset -g` 출력의 `SleepDisabled` 값. 항목이 없으면 false.
    public static func sleepDisabled(_ output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1"
            }
        }
        return false
    }
}

public enum DutyClock {
    /// 경과/남은 시간 표시: 59초 → "0:59", 1시간 5분 3초 → "1:05:03"
    public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// 앱 재시작 시 저장된 근무 명령을 이어갈지 판단한다.
public enum DutyResume {
    public enum Action: Equatable {
        case none
        case agentWatch
        case timed(until: Date?) // nil = 무기한
        case expired             // 앱이 꺼져 있는 동안 근무 시간이 끝남
    }

    /// 근무 명령으로 허용하는 최대 남은 시간. 이보다 길면 저장값 조작으로 보고 무시한다.
    static let maxRemaining: TimeInterval = 24 * 3600

    public static func decide(stored: String?, until: Double?, now: Date) -> Action {
        switch stored {
        case "agentWatch":
            return .agentWatch
        case "timed":
            guard let until else { return .timed(until: nil) }
            guard until.isFinite else { return .none }
            let end = Date(timeIntervalSince1970: until)
            if end <= now { return .expired }
            return end.timeIntervalSince(now) <= maxRemaining ? .timed(until: end) : .none
        default:
            return .none
        }
    }
}
