#!/usr/bin/env bash
# 릴리스 zip 의 sha256 으로 homebrew-tap 의 Cask 를 갱신한다.
#   ./scripts/bump-cask.sh 0.3.1
set -euo pipefail

VERSION="${1:?usage: bump-cask.sh <version>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "버전 형식 오류: $VERSION" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 릴리스 자산을 받아 체크섬·출처 증명을 검증한 뒤에만 Cask 에 반영
gh release download "v$VERSION" -R s3onghyun/bulchimbeon -D "$WORK"
(cd "$WORK" && shasum -a 256 -c "Bulchimbeon-$VERSION.zip.sha256")
gh attestation verify "$WORK/Bulchimbeon-$VERSION.zip" --repo s3onghyun/bulchimbeon >/dev/null
SHA="$(cut -d' ' -f1 "$WORK/Bulchimbeon-$VERSION.zip.sha256")"

gh repo clone s3onghyun/homebrew-tap "$WORK/tap" -- -q
CASK="$WORK/tap/Casks/bulchimbeon.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$WORK/tap" commit -qam "bulchimbeon $VERSION"
git -C "$WORK/tap" push -q
echo "✅ Cask → $VERSION ($SHA)"
