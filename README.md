# 🪖 불침번 (Bulchimbeon)

> **Your Mac's night-watch soldier.**
> 내가 자는 동안 AI 에이전트 곁에서 맥을 깨워두고, 일이 끝나면 "근무 교대합니다!" 하고 재워주는 메뉴바 이등병.

```
💤  취침 중            → 아무것도 안 함
👀  에이전트 근무 대기   → Claude Code / Codex 출근을 감시
🪖  근무 중            → 맥이 잠들지 않음
🫡  근무 교대합니다!     → 에이전트 작업 끝, 다시 잠잘 수 있음
```

## 왜 만들었나

AI 에이전트를 돌려놓고 자려면 이렇게 했다.

```bash
caffeinate -d                 # 끄는 걸 잊는다
sudo pmset disablesleep 1     # 되돌리는 걸 잊으면 배터리 0%
```

불침번은 **에이전트가 떠 있는 동안만** 깨어 있고, 끝나면 알아서 근무를 교대한다.

## 기능

| 기능 | 설명 |
|------|------|
| 🤖 에이전트 근무 (자동 교대) | Claude Code · Codex · Gemini CLI · Aider · OpenCode 감지 → 있으면 근무 투입, 모두 끝나면 교대 알림 |
| 🪖 근무 서기 | 30분 / 1시간 / 2시간 / 4시간 / 무기한 |
| 근무 형태 | 화면까지 켜두기 · 시스템만 깨우기 · **덮개 닫아도 근무** (관리자 권한) |
| 🔋 배터리 철수 | 배터리 사용 중 잔량이 기준(기본 20%) 이하면 강제 철수 |
| ⚠️ 덮개 안전장치 | 근무 종료·앱 종료 시 `disablesleep` 원복, 비정상 종료 후 재실행하면 복구 버튼 |
| 📒 근무일지 | `~/Library/Application Support/Bulchimbeon/duty-log.txt` |

## 설치 & 실행

Xcode 없이 Command Line Tools 만 있으면 된다. (macOS 13+)

```bash
make app        # dist/Bulchimbeon.app 생성 (ad-hoc 서명)
make run        # 빌드 후 실행
make test       # 단위 테스트

# 실행과 동시에 에이전트 근무 시작
open dist/Bulchimbeon.app --args --agent-watch
```

> ad-hoc 서명이라 다른 맥으로 옮기면 Gatekeeper 경고가 뜬다. 우클릭 → 열기.

## 동작 원리

| 근무 형태 | 내부 동작 |
|-----------|----------|
| 화면까지 켜두기 | `IOPMAssertion` `PreventUserIdleDisplaySleep` |
| 시스템만 깨우기 | `IOPMAssertion` `PreventUserIdleSystemSleep` |
| 덮개 닫아도 근무 | 위 + `pmset -a disablesleep 1` (덮개 닫힘은 하드웨어 트리거라 assertion 으로 못 막음) |

에이전트 감지는 `ps` 의 실행 파일 basename 으로 한다. 부분 문자열 매칭은 Claude Code hook(`node -e "...'.claude'..."`)을 오탐하기 때문.

```bash
pmset -g assertions | grep Bulchimbeon   # 근무 중인지 확인
```

설계 상세: [docs/design.md](docs/design.md)

## 로드맵

- [ ] 치비 이등병 픽셀아트 아이콘·애니메이션
- [ ] 에이전트 **유휴 감지** (프로세스 생존이 아니라 실제 작업 중인지)
- [ ] Privileged helper 로 덮개 모드 암호 프롬프트 제거
- [ ] 해금 스킨: 순라꾼(조선시대 불침번), 선비(현량자고)
- [ ] Homebrew cask, 공증

## 주의

덮개를 닫은 채 무거운 작업을 오래 돌리면 발열이 생긴다. 가능하면 전원을 연결하고 쓰자.

## License

MIT
