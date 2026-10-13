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
            ? ("근무 교대합니다! 🫡", "\(summary) 조용해졌습니다 (작업 끝 또는 입력 대기). 이제 푹 주무십시오.")
            : ("Shift over! 🫡", "\(summary) went quiet (done, or waiting for input). Your Mac can sleep now.")
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

    public static func heatAdvisory(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("폭염 주의보 🌡️", "맥이 뜨거워지고 있습니다. 그늘에서 물 마시며 근무 중입니다!")
            : ("Heat advisory 🌡️", "Your Mac is heating up. Staying hydrated on watch!")
    }

    public static func heatRest(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("폭염 경보 🔥 전투휴식 실시!", "맥을 식히는 동안 근무를 잠시 중단합니다. 열이 내리면 자동으로 복귀합니다.")
            : ("Heat warning 🔥 Combat rest!", "Pausing the watch so your Mac can cool down. I'll resume automatically.")
    }

    public static func heatResume(lidDowngraded: Bool, _ lang: Language = L10n.language) -> Notice {
        let extra = lidDowngraded
            ? L10n.t(" 과열 직후라 덮개 근무 대신 시스템 근무로 복귀합니다.", " Resuming as system watch instead of lid-closed, to be safe.", lang)
            : ""
        return lang == .ko
            ? ("전투휴식 종료 🫡", "열이 내렸습니다. 근무 복귀합니다!" + extra)
            : ("Combat rest over 🫡", "Cooled down. Back on watch!" + extra)
    }

    public static func postAbandoned(_ lang: Language = L10n.language) -> Notice {
        lang == .ko
            ? ("근무지 이탈 감지 ⚠️", "잠자기 방지가 풀려 있어 즉시 재투입했습니다.")
            : ("Post abandoned? ⚠️", "The sleep block was released, so I re-engaged immediately.")
    }

    /// 순찰 이등병 말풍선
    public enum Speech {
        public static func reporting(_ lang: Language = L10n.language) -> String { L10n.t("근무 서겠습니다! 🫡", "Reporting for duty! 🫡", lang) }
        public static func arrived(_ lang: Language = L10n.language) -> String { L10n.t("근무 투입! 이상 무!", "On duty. All clear!", lang) }
        public static func handover(_ lang: Language = L10n.language) -> String { L10n.t("근무 교대합니다! 🫡", "Shift over! 🫡", lang) }
        public static func timeUp(_ lang: Language = L10n.language) -> String { L10n.t("근무 끝! 충성! 🫡", "Watch over! Salute! 🫡", lang) }
        public static func resumed(_ lang: Language = L10n.language) -> String { L10n.t("근무 복귀했습니다! 🫡", "Back on watch! 🫡", lang) }
        public static func heat(_ lang: Language = L10n.language) -> String { L10n.t("폭염 주의보! 물 마시는 중 🥵", "Heat advisory! Hydrating 🥵", lang) }
        public static func rest(_ lang: Language = L10n.language) -> String { L10n.t("전투휴식! 열 식히는 중 🧊", "Combat rest! Cooling down 🧊", lang) }
        public static func backFromRest(_ lang: Language = L10n.language) -> String { L10n.t("전투휴식 끝! 근무 복귀 🫡", "Rest over! Back on post 🫡", lang) }
        public static func notAWOL(_ lang: Language = L10n.language) -> String { L10n.t("근무지 이탈 아닙니다! 복귀! 🫡", "Not AWOL! Back on post! 🫡", lang) }
        public static func handoverReport(_ lang: Language = L10n.language) -> String { L10n.t("인수인계 드리겠습니다! 📋", "Handover report! 📋", lang) }
        public static func waiting(_ lang: Language = L10n.language) -> String { L10n.t("에이전트 출근 기다리는 중 👀", "Waiting for agents 👀", lang) }
    }

    public static func pick(_ lines: [String]) -> String {
        lines.randomElement() ?? ""
    }
}
