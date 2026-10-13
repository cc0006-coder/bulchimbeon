# 불침번 (Bulchimbeon) 설계서

| 항목 | 내용 |
|------|------|
| 제품명 | 불침번 (Bulchimbeon) — "Your Mac's night-watch soldier" |
| 형태 | macOS 메뉴바 앱 (SwiftUI `MenuBarExtra`) |
| 최소 OS | macOS 13 Ventura |
| 빌드 | SwiftPM + `.app` 번들 조립 스크립트 (Xcode 불필요) |
| 라이선스 | MIT |
| 한 줄 요약 | 내가 자는 동안 AI 에이전트 곁에서 맥을 깨워두고, 일이 끝나면 "근무 교대" 하고 재워주는 이등병 |

## 1. 문제 정의

| 현재 방식 | 불편 |
|-----------|------|
| `caffeinate -d` 터미널에 띄워두기 | 잊어버리면 영원히 깨어 있음. 에이전트 끝나도 모름 |
| `sudo pmset disablesleep 1` | 덮개 닫아도 깨어 있지만 **되돌리는 걸 잊으면 배터리 0%** |
| Amphetamine 등 | 기능은 충분하지만 "에이전트가 끝났는지" 모름. 재미 없음 |

## 2. 컨셉 — 불침번

| 앱 상태 | 이등병 상태 | 메뉴바 |
|---------|------------|--------|
| 꺼짐 | 생활관 취침 | 💤 |
| 에이전트 근무 대기 | 근무 대기 (에이전트 출근 감시) | 👀 |
| 근무 중 | 경계 근무, "이상 무!" | 🪖 (+ 남은 시간) |
| 에이전트 작업 끝 | "근무 교대합니다!" 알림 후 취침 | 👀 → 대기 복귀 |
| 배터리 부족 | 당직사관에게 보고 후 철수 | 💤 |

톤 가이드: 2등신 치비, **갈굼·부조리 개그 금지**. "나 대신 밤새주는 고생하는 귀여운 애" 포지션.

## 3. 기능 (MVP v0.1)

| # | 기능 | 구현 |
|---|------|------|
| F1 | 근무 서기 (30분/1/2/4시간/무기한) | `IOPMAssertionCreateWithName` |
| F2 | 근무 형태 선택 | 화면까지 / 시스템만 / 덮개 닫아도 |
| F3 | **에이전트 근무 (자동 교대)** | `ps` 폴링 → 에이전트 있으면 근무 투입, 모두 끝나면 교대 알림 후 해제 |
| F4 | 배터리 철수 | 배터리 사용 중 & 잔량 ≤ 기준(기본 20%) → 강제 해제 |
| F5 | 덮개 모드 안전장치 | 해제 시 `disablesleep 0` 복구, 비정상 종료 후 재실행 시 복구 버튼 노출 |
| F6 | 근무일지 | `~/Library/Application Support/Bulchimbeon/duty-log.txt` + 메뉴에 최근 10건 |
| F7 | 로그인 시 자동 실행 | `SMAppService.mainApp` |

### 근무 형태 ↔ 시스템 동작

| 근무 형태 | Power assertion | 덮개 | 권한 |
|-----------|-----------------|------|------|
| 화면까지 켜두기 | `PreventUserIdleDisplaySleep` | 닫으면 잠 | 없음 |
| 시스템만 깨우기 | `PreventUserIdleSystemSleep` | 닫으면 잠 | 없음 |
| 덮개 닫아도 근무 | `PreventUserIdleSystemSleep` + `pmset -a disablesleep 1` | 깨어 있음 | 관리자 암호 (osascript) |

> power assertion은 idle 타이머만 막는다. 덮개 닫힘은 하드웨어 트리거라 `disablesleep` 전역 플래그가 필요하고, 이 플래그는 프로세스가 죽어도 남는다 → F5 안전장치 필수.

## 4. 에이전트 감지 규칙

`ps -Axo args=` 의 각 줄에서 **첫 토큰(실행 파일)의 basename** 으로 매칭. 부분 문자열 매칭 금지
(실측: Claude Code hook 은 `node -e "...'.claude'..."` 형태라 오탐 발생).

| 에이전트 | 실행 파일 basename | node/bun 스크립트 경로 마커 |
|----------|-------------------|---------------------------|
| Claude Code | `claude` | `@anthropic-ai/claude-code` |
| Codex CLI | `codex` | `@openai/codex` |
| Gemini CLI | `gemini` | `@google/gemini-cli` |
| Aider | `aider` | — |
| OpenCode | `opencode` | `opencode-ai` |

- 대소문자 구분 → `/Applications/Claude.app/.../Claude` (데스크톱 앱) 은 제외
- `node -e` / `--eval` 인라인 스크립트는 검사하지 않음

### 에이전트 근무 상태 머신

```
        에이전트 감지 ≥1                    에이전트 0
 대기(👀) ───────────────▶ 근무(🪖) ───────────────▶ 교대 알림 → 대기(👀)
    ▲                         │ 배터리 ≤ 기준
    │                         ▼
    └──────── 수동 재개 ── 철수(💤)
```

## 5. 구조

| 모듈 | 파일 | 책임 |
|------|------|------|
| `BulchimbeonCore` (순수 로직, 테스트 대상) | `AgentCatalog.swift` | 에이전트 매칭·ps 출력 파싱 |
| | `Policies.swift` | 배터리 철수 판단, pmset 파싱, 시간 포맷 |
| | `Lines.swift` | 대사 |
| | `DutyLog.swift` | 근무일지 저장 |
| `Bulchimbeon` (앱) | `PowerAssertion.swift` | IOKit assertion 래퍼 |
| | `SystemProbes.swift` | 배터리·ps·pmset·osascript 호출 |
| | `DutyController.swift` | 상태 머신 (5초 tick) |
| | `BulchimbeonApp.swift` | 메뉴바 UI |

## 6. 로드맵

| 버전 | 내용 |
|------|------|
| v0.1 | MVP (위 F1–F7), 이모지 아이콘 |
| v0.2 ✅ | 치비 이등병 픽셀아트 아이콘·애니메이션 (취침/대기/근무/경례 4포즈), 앱 아이콘 |
| v0.3 | 에이전트 **유휴 감지** (프로세스 생존이 아니라 CPU·출력 활동 기준) |
| v0.4 | Privileged helper (`SMAppService.daemon`) 로 덮개 모드 암호 프롬프트 제거 |
| v0.5 | 해금 스킨: 순라꾼(조선시대 불침번), 선비(현량자고) / 당직사관 이스터에그 |
| v1.0 | Homebrew cask 배포, 공증(notarization) |
