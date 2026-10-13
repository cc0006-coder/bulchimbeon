#!/usr/bin/env bash
# SwiftPM 릴리스 빌드 → dist/Bulchimbeon.app 조립 → ad-hoc 서명 → zip
# Xcode 없이 Command Line Tools 만으로 동작한다.
#   UNIVERSAL=1 ./scripts/build-app.sh   # arm64 + x86_64
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
APP="dist/Bulchimbeon.app"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/Bulchimbeon"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Bulchimbeon"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bulchimbeon"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
(cd dist && rm -f "Bulchimbeon-$VERSION.zip" && ditto -c -k --keepParent Bulchimbeon.app "Bulchimbeon-$VERSION.zip")

echo "✅ $APP (v$VERSION)"
echo "   실행: open $APP"
