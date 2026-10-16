# 호환성 약속 (Compatibility)

1.0부터 아래 항목은 **메이저 버전(2.0)이 바뀌기 전까지 이름·값·형식을 바꾸지 않는다.**
스크립트나 `defaults write` 로 불침번을 다루는 사람이 업데이트 때문에 깨지지 않게 하기 위해서다.

약속은 `Tests/BulchimbeonCoreTests/CompatibilityTests.swift` 로 고정돼 있다.
이 테스트가 실패하는 변경은 실수이거나, 의도했다면 CHANGELOG 에 **호환성 깨짐**으로 적고 메이저 버전을 올려야 한다.

> 1.0 전(0.x)에도 이 문서의 항목은 가능한 한 지킨다. 바꿔야 하면 CHANGELOG 에 먼저 적는다.

## 1. 설정 (UserDefaults)

도메인: `io.github.s3onghyun.bulchimbeon`

| 키 | 형식 | 허용 값 (밖이면 기본값) | 기본값 | 메뉴 |
|----|------|------------------------|--------|------|
| `dutyMode` | 문자열 | `display` · `system` · `lid` | `system` | 근무 형태 |
| `batteryFloor` | 정수 | `0`(끄기) · `10` · `20` · `30` | `20` | 배터리 철수 기준 |
| `agentGraceMinutes` | 정수 | `1` · `3` · `5` · `10` | `5` | 에이전트 근무 설정 ▸ 조용해진 뒤 교대까지 |
| `agentWatchCountsIdle` | 불리언 | `true` · `false` | `false` | 에이전트 근무 설정 ▸ 열려만 있는 세션도 근무로 인정 |
| `customAgents` | 문자열 배열 | 실행 파일 이름 | 없음 | (메뉴 없음) |
| `patrolEnabled` | 불리언 | `true` · `false` | `true` | 🚶 순찰 모드 |
| `patrolScale` | 정수 | `2` · `3` | `2` | 이등병 크기 |
| `uniformTheme` | 문자열 | `default` · `navy` · `arctic` (테마 id) | `default` | 🎽 군복 |

```bash
defaults write io.github.s3onghyun.bulchimbeon customAgents -array goose amp
defaults write io.github.s3onghyun.bulchimbeon agentGraceMinutes -int 10
```

앱 언어는 macOS 표준인 앱 도메인 `AppleLanguages` 를 쓴다 (메뉴 **언어 / Language**).

`uniformTheme` 의 테마 id 는 한 번 출시되면 이름을 바꾸거나 없애지 않는다. 테마는 늘어날 수 있다.
군복은 사용자가 메뉴에서 고른 것만 입는다 (언어·지역으로 자동 선택하지 않는다). 테마의 색·모양은 약속하지 않는다.

### 약속하지 않는 키

재시작 후 근무를 이어가기 위한 내부 상태다. 직접 바꾸지 말 것. 언제든 바뀔 수 있다.

| 키 | 용도 |
|----|------|
| `dutyOrder`, `dutyOrderUntil` | 진행 중인 근무 명령 |
| `lidEngagedByUs` | 덮개 잠자기를 이 앱이 껐는지 (원복용) |
| `simulateHeat` | 시험용 발열 흉내 (`advisory` · `alert` · `normal`) |

## 2. 실행 인자

| 인자 | 동작 |
|------|------|
| `--agent-watch` | 실행하자마자 에이전트 근무 시작 |
| `--diagnose` | 감지되는 에이전트를 표준 출력으로 보여주고 종료. **출력 내용은 사람이 읽는 용도이며 형식은 약속하지 않는다** |

`--demo`, `--demo-scale` 은 홍보 영상 녹화용이라 약속하지 않는다.
환경 변수 `BULCHIMBEON_DEBUG=1` 의 출력도 디버깅용이라 형식을 약속하지 않는다.

## 3. 근무일지

| 항목 | 약속 |
|------|------|
| 위치 | `~/Library/Application Support/Bulchimbeon/duty-log.txt` |
| 회전 | 1MB를 넘으면 `duty-log.txt.1` 로 옮기고 새로 쓴다 (한 세대만 보관) |
| 줄 형식 | `<ISO 8601 UTC 시각>` + 공백 두 칸 + `<내용>` + 줄바꿈. 한 항목은 항상 한 줄 |
| 권한 | 파일 `0600`, 디렉토리 `0700` |

```text
2026-10-14T05:41:00Z  근무 투입 — 4시간, 화면은 꺼져도 맥은 깨어 있음 (caffeinate -i)
```

**내용 문구는 약속하지 않는다.** 언어 설정을 따르고, 더 알기 쉽게 바뀔 수 있다.
줄 단위로 시각을 잘라 쓰는 것(`cut -c1-20`, `awk '{print $1}'`)은 안전하다.

## 4. 그 밖에 약속하지 않는 것

- 감지 기준의 세부 값 (CPU 문턱, 평균 구간, 확인 주기). 실측으로 더 나아지면 바꾼다
- 메뉴 구성과 문구, 이등병 대사·스프라이트
- 번들 ID 외의 내부 구조, Core 모듈의 Swift API
