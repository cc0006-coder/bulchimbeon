#!/usr/bin/env bash
# 릴리스 파일의 sha256 으로 homebrew-tap 의 Cask(맥)와 Formula(리눅스, 있으면)를 갱신한다.
# macOS·Linux 모두에서 돈다.
#   ./scripts/bump-cask.sh 0.3.1
set -euo pipefail

VERSION="${1:?usage: bump-cask.sh <version>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "버전 형식 오류: $VERSION" >&2; exit 1; }
REPO=s3onghyun/bulchimbeon

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sha256_check() { # 체크섬 파일을 WORK 에서 검증
  if command -v sha256sum >/dev/null; then (cd "$WORK" && sha256sum -c "$1")
  else (cd "$WORK" && shasum -a 256 -c "$1"); fi
}
sha_of() { # 체크섬 파일에서 해당 파일의 sha256
  awk -v f="$2" '$2 == f || $2 == "./" f { print $1 }' "$WORK/$1"
}
edit() { # sed -i 는 BSD 와 GNU 의 문법이 달라 임시 파일로 바꾼다
  local file="$1"; shift
  sed -E "$@" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# 릴리스 파일을 받아 체크섬·출처 증명을 검증한 뒤에만 tap 에 반영
ZIP="Bulchimbeon-$VERSION.zip"
AMD64="bulchimbeon_${VERSION}_linux_amd64.tar.gz"
ARM64="bulchimbeon_${VERSION}_linux_arm64.tar.gz"
gh release download "v$VERSION" -R "$REPO" -D "$WORK" \
  -p "$ZIP" -p "$ZIP.sha256" -p "$AMD64" -p "$ARM64" -p SHA256SUMS
sha256_check "$ZIP.sha256"
awk -v a="$AMD64" -v b="$ARM64" '{ f = $2; sub(/^\.\//, "", f) } f == a || f == b' \
  "$WORK/SHA256SUMS" > "$WORK/linux.sha256"
[[ "$(wc -l < "$WORK/linux.sha256")" -eq 2 ]] || { echo "SHA256SUMS 에 리눅스 tarball 이 없음" >&2; exit 1; }
sha256_check linux.sha256
for f in "$ZIP" "$AMD64" "$ARM64"; do
  gh attestation verify "$WORK/$f" --repo "$REPO" >/dev/null
done
SHA="$(cut -d' ' -f1 "$WORK/$ZIP.sha256")"
SHA_AMD64="$(sha_of linux.sha256 "$AMD64")"
SHA_ARM64="$(sha_of linux.sha256 "$ARM64")"

gh repo clone s3onghyun/homebrew-tap "$WORK/tap" -- -q
edit "$WORK/tap/Casks/bulchimbeon.rb" \
  "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/"

# Formula: url 줄의 v<버전>·파일 이름을 바꾸고, 아키텍처 블록 안의 sha256 을 각각 갱신
FORMULA="$WORK/tap/Formula/bulchimbeon-linux.rb"
if [[ -f "$FORMULA" ]]; then
  edit "$FORMULA" \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "/^ +url /s/[0-9]+\.[0-9]+\.[0-9]+/$VERSION/g" \
    -e "/on_intel do/,/^ *end$/s/sha256 \".*\"/sha256 \"$SHA_AMD64\"/" \
    -e "/on_arm do/,/^ *end$/s/sha256 \".*\"/sha256 \"$SHA_ARM64\"/"
  grep -q "sha256 \"$SHA_AMD64\"" "$FORMULA" && grep -q "sha256 \"$SHA_ARM64\"" "$FORMULA" \
    || { echo "Formula 의 sha256 갱신 실패" >&2; exit 1; }
fi

MSG="bulchimbeon $VERSION"; [[ -f "$FORMULA" ]] && MSG="$MSG, bulchimbeon-linux $VERSION"
git -C "$WORK/tap" commit -qam "$MSG"
git -C "$WORK/tap" push -q
echo "✅ Cask → $VERSION ($SHA)"
[[ -f "$FORMULA" ]] && echo "✅ Formula bulchimbeon-linux → $VERSION (amd64 $SHA_AMD64, arm64 $SHA_ARM64)"
exit 0
