import Foundation

/// 이등병 대사집. 톤: 성실하고 귀엽게. 갈굼·부조리 개그는 넣지 않는다.
public enum Lines {
    public static let onDuty = [
        "근무 중 이상 무!",
        "편히 주무십시오. 제가 지키겠습니다!",
        "졸지 않겠습니다! …아마도요.",
        "에이전트 곁을 지키는 중입니다!",
        "별 보며 근무 서는 중 ✨",
    ]

    public static let standby = [
        "근무 대기 중. 에이전트 출근하면 바로 투입합니다!",
        "총 닦으며 대기 중…",
        "에이전트 기다리는 중 👀",
    ]

    public static let off = [
        "생활관 취침 중… zzz",
        "근무 없음. 꿀잠 중 💤",
    ]

    public static let reportForDuty = (
        title: "불침번 근무 투입! 🪖",
        body: "근무 서겠습니다! 이상 무!"
    )

    public static func agentArrived(_ summary: String) -> (title: String, body: String) {
        ("근무 투입! 🪖", "\(summary) 출근 확인. 곁을 지키겠습니다!")
    }

    public static func handover(_ summary: String) -> (title: String, body: String) {
        ("근무 교대합니다! 🫡", "\(summary) 작업 종료 확인. 이제 푹 주무십시오.")
    }

    public static let timeUp = (
        title: "근무 시간 종료! ⏰",
        body: "다음 근무자 깨우겠습니다. 수고하셨습니다!"
    )

    public static func batteryRetreat(_ percent: Int) -> (title: String, body: String) {
        ("당직사관님께 보고드립니다 🔋", "배터리 \(percent)%… 기력이 다해 근무 철수합니다.")
    }

    public static let lidFallback = (
        title: "덮개 근무 불가 🙅",
        body: "관리자 승인이 없어 시스템 근무로 대체합니다. 덮개는 열어두십시오!"
    )

    public static let lidResumeFallback = (
        title: "근무 복귀! 🪖",
        body: "덮개 근무는 관리자 승인이 다시 필요해 시스템 근무로 복귀했습니다. 필요하면 메뉴에서 다시 켜주십시오."
    )

    public static let lidLeftOn = (
        title: "덮개 잠자기가 꺼진 채 남아 있습니다 ⚠️",
        body: "지난 근무가 비정상 종료됐습니다. 메뉴에서 '덮개 잠자기 복구'를 눌러주십시오."
    )

    public static func pick(_ lines: [String]) -> String {
        lines.randomElement() ?? ""
    }
}
