# 기여 가이드 (Contributing)

입대를 환영합니다 🫡 버그 신고, 에이전트 추가, 대사·스프라이트 아이디어 모두 환영입니다.

> 🇺🇸 English speakers: issues and PRs in English are welcome. The quick version is in [English summary](#english-summary) below.

## 어디서부터?

| 하고 싶은 것 | 방법 |
|-------------|------|
| 이등병이 이상하게 굴었다 | [🚨 근무 태도 불량 신고](https://github.com/s3onghyun/bulchimbeon/issues/new?template=bug-report.yml) |
| 내 에이전트가 감지 안 된다 | [🤖 새 에이전트 감지 요청](https://github.com/s3onghyun/bulchimbeon/issues/new?template=agent-request.yml) — 또는 직접 PR (아래) |
| 보안 문제 | 공개 이슈 말고 [비공개 제보](https://github.com/s3onghyun/bulchimbeon/security/advisories/new) |
| 대사·스프라이트·스킨 아이디어 | 이슈로 자유롭게 |

## 개발 환경

Xcode 없이 Command Line Tools 만 있으면 됩니다. (macOS 13+)

```bash
make test       # 단위 테스트
make app        # dist/Bulchimbeon.app
make run        # 빌드 후 실행
make icons      # 스프라이트 수정 후 아이콘·미리보기 재생성

dist/Bulchimbeon.app/Contents/MacOS/Bulchimbeon --diagnose   # 에이전트 감지 진단
dist/Bulchimbeon.app/Contents/MacOS/Bulchimbeon --demo       # 홍보 영상용 연출
```

## 구조

| 위치 | 내용 | 테스트 |
|------|------|--------|
| `Sources/BulchimbeonCore/` | 순수 로직 — 에이전트 판별, 근무 판단, 대사, 스프라이트, 근무일지 | **필수** |
| `Sources/Bulchimbeon/` | 시스템 호출(IOKit·libproc·pmset)과 UI | 실제 실행으로 확인 |
| `Sources/IconGen/` | 스프라이트 → 앱 아이콘·미리보기 PNG | — |

판단 로직은 Core 에 두고 테스트를 붙여주세요. 앱 타깃은 시스템을 호출하는 얇은 껍데기로 유지합니다.

## 지켜주세요

| 원칙 | 이유 |
|------|------|
| **네트워크 통신 금지** | 텔레메트리·업데이트 확인 포함. "통신 없음"이 이 앱의 약속입니다 |
| **서드파티 의존성 추가 금지** | 공급망 리스크 0 유지 |
| 프로세스 명령줄·환경변수를 저장·출력하지 않기 | 다른 프로세스의 API 키가 들어 있을 수 있음 |
| 관리자 권한 명령에 외부 문자열을 넣지 않기 | 셸 인젝션 방지 |
| 보안 동작을 바꾸면 `SECURITY.md` 위협 모델도 갱신 | |
| 사용자 문구는 한국어·영어 모두 (`L10n.t("한국어", "English")`) | |
| 대사 톤: 성실하고 귀엽게. **갈굼·부조리 개그는 넣지 않습니다** | 모두가 웃을 수 있게 |

## 에이전트 추가하기

1. 에이전트를 실행해 두고 실제 프로세스 모습을 확인합니다. **추측 말고 실측으로.**
   ```bash
   ps -Axo comm=,args= | grep -i <name>
   ```
   네이티브 설치본은 실행 파일 이름이 버전 번호인 경우도 있습니다 (Claude Code 가 그렇습니다).
2. `Sources/BulchimbeonCore/AgentCatalog.swift` 의 `builtIn` 에 추가합니다.
   - `binaryNames`: 실행 파일·argv[0] basename (대소문자 구분)
   - `pathMarkers`: 실행 파일 이름이 특이할 때 설치 경로 조각
   - `packageMarkers`: node/bun/deno 로 실행될 때 스크립트 경로 조각
   - 부분 문자열로 넓게 잡지 마세요. hook 스크립트 같은 오탐이 생깁니다.
3. `Tests/BulchimbeonCoreTests/CoreTests.swift` 에 **실측한 프로세스 모습 그대로** 테스트를 추가합니다. 오탐 케이스도 하나 넣어주세요.
4. `--diagnose` 로 실제로 잡히는지 확인하고, 그 출력을 PR 에 붙여주세요.

## 스프라이트

`Sources/BulchimbeonCore/Sprites.swift` 의 ASCII 그리드가 원본입니다. 문자 하나 = 픽셀 하나, 16×16.
수정 후 `make icons` 를 돌리고 `docs/sprites-preview.png` 를 함께 커밋해주세요. 팔레트에 없는 문자는 테스트에서 걸립니다.

## 릴리스 (메인테이너)

```bash
git tag vX.Y.Z && git push origin vX.Y.Z   # CI 가 universal 빌드·서명·출처 증명·Release
./scripts/bump-cask.sh X.Y.Z               # 체크섬·출처 증명 검증 후 Homebrew tap 갱신
```

---

## English summary

- **Bugs:** use the "🚨 Bug report" issue form. **Security issues:** report privately via Security → Report a vulnerability.
- **Setup:** Command Line Tools only. `make test`, `make app`, `make run`. Use `--diagnose` to see what gets detected.
- **Rules:** no network calls, no third-party dependencies, never store or print other processes' arguments/env,
  keep logic in `BulchimbeonCore` with tests, and write user-facing text in both Korean and English via `L10n.t`.
- **Adding an agent:** check the real process with `ps`, add it to `AgentCatalog.builtIn`, add a test using the
  exact observed process shape (plus a false-positive case), and paste `--diagnose` output in the PR.
- **Tone:** the soldier is earnest and cute. No hazing or bullying jokes.
