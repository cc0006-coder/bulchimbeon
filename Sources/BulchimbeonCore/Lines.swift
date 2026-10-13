import Foundation

/// 이등병 대사집. 톤: 성실하고 귀엽게. 갈굼·부조리 개그는 넣지 않는다.
/// 모든 대사는 언어를 인자로 받는다 (기본값: 시스템 언어).
public enum Lines {
    public typealias Notice = (title: String, body: String)
    public typealias Language = L10n.Language

    public static func onDuty(_ lang: Language = L10n.language) -> [String] {
        lang == .ko
            ? ["근무 중 이상 무!", "편히 주무십시오. 제가 지키겠습니다!", "졸지 않겠습니다! …아마도요.",
               "에이전트 곁을 지키는 중입니다!", "별 보며 근무 서는 중 ✨"]
            : ["On watch. All clear!", "Sleep tight. I've got this!", "Won't doze off! …probably.",
               "Guarding your agents!", "Night watch under the stars ✨"]
    }

    public static func standby(_ lang: Language = L10n.language) -> [String] {
        lang == .ko
            ? ["근무 대기 중. 에이전트 출근하면 바로 투입합니다!", "총 닦으며 대기 중…", "에이전트 기다리는 중 👀"]
            : ["Standing by. Ready when an agent clocks in!", "Polishing my rifle… standing by.", "Waiting for agents 👀"]
    }

    public static func off(_ lang: Language = L10n.language) -> [String] {
        lang == .ko
            ? ["생활관 취침 중… zzz", "근무 없음. 꿀잠 중 💤"]
            : ["Asleep in the barracks… zzz", "Off duty. Sweet dreams 💤"]
    }

    public static func reportForDuty(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("불침번 근무 투입! 🪖", "근무 서겠습니다! 이상 무!")
            : ("Reporting for night watch! 🪖", "On duty. All clear!")
    }

    public static func agentArrived(_ summary: String, _ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("근무 투입! 🪖", "\(summary) 출근 확인. 곁을 지키겠습니다!")
            : ("On duty! 🪖", "\(summary) clocked in. I'll keep watch!")
    }

    public static func handover(_ summary: String, _ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("근무 교대합니다! 🫡", "\(summary) 작업 종료 확인. 이제 푹 주무십시오.")
            : ("Shift over! 🫡", "\(summary) finished. Your Mac can sleep now.")
    }

    public static func timeUp(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("근무 시간 종료! ⏰", "다음 근무자 깨우겠습니다. 수고하셨습니다!")
            : ("Watch is over! ⏰", "Waking the next guard. Good work!")
    }

    public static func batteryRetreat(_ percent: Int, _ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("당직사관님께 보고드립니다 🔋", "배터리 \(percent)%… 기력이 다해 근무 철수합니다.")
            : ("Reporting to the duty officer 🔋", "Battery at \(percent)%… out of strength, standing down.")
    }

    public static func lidFallback(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("덮개 근무 불가 🙅", "관리자 승인이 없어 시스템 근무로 대체합니다. 덮개는 열어두십시오!")
            : ("Can't guard with the lid closed 🙅", "No admin approval, so I switched to system watch. Keep the lid open!")
    }

    public static func lidResumeFallback(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("근무 복귀! 🪖", "덮개 근무는 관리자 승인이 다시 필요해 시스템 근무로 복귀했습니다. 필요하면 메뉴에서 다시 켜주십시오.")
            : ("Back on watch! 🪖", "Lid-closed watch needs admin approval again, so I resumed as system watch. Turn it back on from the menu if needed.")
    }

    public static func lidLeftOn(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("덮개 잠자기가 꺼진 채 남아 있습니다 ⚠️", "지난 근무가 비정상 종료됐습니다. 메뉴에서 '덮개 잠자기 복구'를 눌러주십시오.")
            : ("Lid sleep is still disabled ⚠️", "The last watch ended abnormally. Choose 'Restore lid sleep' from the menu.")
    }

    /// 순찰 이등병 말풍선
    public enum Speech {
        public static func reporting(_ lang: Language = L10n.language) -> String { L10n.t("근무 서겠습니다! 🫡", "Reporting for duty! 🫡", lang) }
        public static func arrived(_ lang: Language = L10n.language) -> String { L10n.t("근무 투입! 이상 무!", "On duty. All clear!", lang) }
        public static func handover(_ lang: Language = L10n.language) -> String { L10n.t("근무 교대합니다! 🫡", "Shift over! 🫡", lang) }
        public static func timeUp(_ lang: Language = L10n.language) -> String { L10n.t("근무 끝! 충성! 🫡", "Watch over! Salute! 🫡", lang) }
        public static func resumed(_ lang: Language = L10n.language) -> String { L10n.t("근무 복귀했습니다! 🫡", "Back on watch! 🫡", lang) }
        public static func waiting(_ lang: Language = L10n.language) -> String { L10n.t("에이전트 출근 기다리는 중 👀", "Waiting for agents 👀", lang) }
    }

    public static func pick(_ lines: [String]) -> String {
        lines.randomElement() ?? ""
    }
}
