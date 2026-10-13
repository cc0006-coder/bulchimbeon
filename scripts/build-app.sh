#!/usr/bin/env bash
# SwiftPM 릴리스 빌드 → dist/Bulchimbeon.app 조립 → ad-hoc 서명 → zip
# Xcode 없이 Command Line Tools 만으로 동작한다.
#   UNIVERSAL=1 ./scripts/build-app.sh   # arm64 + x86_64
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
APP="dist/Bulchimbeon.app"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --product Bulchimbeon --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/Bulchimbeon"
else
  swift build -c release --product Bulchimbeon
  BIN="$(swift build -c release --show-bin-path)/Bulchimbeon"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bulchimbeon"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

# hardened runtime: 런타임 코드 주입(DYLD_*)·디버거 attach 차단
codesign --force --options runtime --timestamp=none --sign - "$APP"
codesign --verify --strict "$APP"

ZIP="Bulchimbeon-$VERSION.zip"
(cd dist && rm -f "$ZIP" "$ZIP.sha256" && ditto -c -k --keepParent Bulchimbeon.app "$ZIP" && shasum -a 256 "$ZIP" > "$ZIP.sha256")

echo "✅ $APP (v$VERSION)"
echo "   실행: open $APP"
echo "   체크섬: dist/$ZIP.sha256"
