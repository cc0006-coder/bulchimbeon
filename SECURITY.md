# 보안 정책 (Security)

불침번은 **관리자 권한으로 시스템 전원 설정을 바꾸고**, **다른 프로세스의 명령줄을 읽는** 앱이다.
그래서 일반 메뉴바 앱보다 공격 표면이 넓고, 아래 원칙으로 설계했다.

## 위협 모델

| 자산 / 행위 | 위협 | 대응 |
|-------------|------|------|
| 관리자 권한 `pmset` 실행 | 셸 인젝션으로 임의 명령 root 실행 | 스크립트의 가변 값은 Bool 에서 나온 `0`/`1` 뿐. 사용자 입력·외부 문자열이 들어가지 않음 |
| 관리자 암호 프롬프트 | 반복 프롬프트로 사용자가 무심코 암호를 입력하는 습관화 (피싱 표면) | 프롬프트에 실행할 명령 원문(`/usr/bin/pmset -a disablesleep 1`)을 표시. 거부하면 덮개 모드를 포기하고 시스템 근무로 대체 (재요청 루프 없음) |
| `disablesleep` 전역 플래그 | 앱 비정상 종료 시 잠자기 영구 해제 → 배터리 0%·발열 | 종료 시 원복, 재실행 시 감지·복구 버튼, 배터리 철수 기준 |
| 외부 명령 실행 | `PATH` 하이재킹, `DYLD_*` 주입 | 절대 경로(`/bin/ps`, `/usr/bin/pmset`, `/usr/bin/osascript`)만 사용. 자식 프로세스 환경을 최소화(`PATH`=시스템 경로, `LANG=C`) |
| 다른 프로세스 정보 | 명령줄·환경변수에 포함된 API 키·토큰 노출, 다른 사용자 프로세스 열람 | `ps` 대신 libproc API 로 **현재 사용자(UID) 프로세스만** 조회. 일반 프로세스는 실행 파일 경로 + `argv[0]` 만, node·bun·deno 만 argv 앞 8개. 환경변수 영역은 파싱하지 않고(argc 에서 정지) 버퍼는 `memset_s` 로 즉시 소거. 로그·알림엔 카탈로그 이름만, 진단 출력에도 인자는 미포함 |
| 사용자 지정 에이전트 (`customAgents`) | 비정상 이름 주입 | `^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$` 만 허용, 최대 16개, 정확히 일치하는 basename 만 비교 (정규식·경로 해석 없음) |
| 근무일지 파일 | 심볼릭 링크로 다른 파일 덮어쓰기, 로그 위조, 디스크 고갈 | `O_NOFOLLOW` 로 열기(TOCTOU 없음), 파일 0600·디렉토리 0700, 줄바꿈 제거, 1MB 회전 |
| UserDefaults | `defaults write` 로 비정상 값 주입 | 배터리 기준·크기는 허용 목록에 있는 값만 받음 |
| 순찰 오버레이 창 | 클릭 가로채기, 입력 탈취 | `ignoresMouseEvents` — 모든 입력 통과. 화면 내용·키 입력을 읽지 않음 (마우스 좌표만 사용, 별도 권한 불필요) |
| 바이너리 | 런타임 코드 주입, 디버거 attach | hardened runtime 서명 (`codesign --options runtime`) |
| 공급망 | 의존성 탈취, CI Action 변조 | 서드파티 의존성 0개. CI Action 은 커밋 SHA 고정, `permissions: contents: read`, Dependabot 으로 갱신 |
| 배포 | 변조된 zip | CI 에서만 릴리스 빌드, SHA-256 체크섬 + Sigstore 빌드 출처 증명 (`gh attestation verify`) |

## 하지 않는 것

| 항목 | 이유 |
|------|------|
| 네트워크 통신 | 없음. 텔레메트리·업데이트 확인·분석 SDK 없음 |
| App Sandbox | `ps`·`pmset` 실행이 필요해 샌드박스와 양립 불가. 대신 위 항목으로 권한 사용 범위를 좁힘 |
| 상주 root 데몬 | v0.1 은 필요할 때만 `osascript` 로 권한 상승. privileged helper(`SMAppService.daemon`)는 로드맵 v0.4 — 도입 시 XPC 호출자 코드서명 검증 필수 |

## 알려진 한계

- ad-hoc 서명이라 공증(notarization)되지 않았다. 다른 맥에서는 Gatekeeper 경고가 뜬다.
- 같은 사용자 권한으로 이름이 `claude` 인 프로세스를 띄우면 근무를 유지시킬 수 있다 (잠자기 방지 외 영향 없음).
- Docker 컨테이너·원격(SSH) 서버에서 도는 에이전트는 이 맥의 프로세스가 아니므로 감지하지 않는다.

## 취약점 제보

공개 이슈 대신 저장소의 **Security → Report a vulnerability** (GitHub private vulnerability reporting)로 제보해 주세요.
