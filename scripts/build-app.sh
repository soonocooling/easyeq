#!/bin/bash
# EasyEq.app을 만들고 고정 인증서로 서명한다.
# 서명이 바뀌면 접근성 권한이 초기화되므로 항상 같은 인증서를 쓴다.
# 인증서가 없으면 임시 서명으로 빌드한다.
# 사용법: scripts/build-app.sh             build/EasyEq.app 생성
#         scripts/build-app.sh --install   빌드 후 /Applications에 설치하고 실행
#         SIGN_IDENTITY="이름" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.2.1"
APP="build/EasyEq.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    # 인증서가 없으면 임시(ad-hoc) 서명. 빌드할 때마다 서명이 바뀌어 접근성 권한을 다시 허용해야 한다.
    echo "Apple Development 인증서가 없어 임시 서명(ad-hoc)으로 빌드합니다." >&2
    echo "새로 빌드할 때마다 접근성 권한을 다시 허용해야 할 수 있습니다." >&2
    IDENTITY="-"
fi

swift build -c release --product EasyEq --arch arm64 --arch x86_64
BIN="$(swift build -c release --product EasyEq --arch arm64 --arch x86_64 --show-bin-path)/EasyEq"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EasyEq"
cp docs/manual.html docs/manual.en.html "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>EasyEq</string>
    <key>CFBundleIdentifier</key><string>com.soonocooling.easyeq</string>
    <key>CFBundleName</key><string>EasyEq</string>
    <key>CFBundleDisplayName</key><string>EasyEq</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 1)</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Personal use</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
echo "빌드 완료: $APP (서명: $IDENTITY)"

if [ "${1:-}" = "--install" ]; then
    pkill -x EasyEq 2>/dev/null || true
    rm -rf /Applications/EasyEq.app
    cp -R "$APP" /Applications/
    open /Applications/EasyEq.app
    echo "설치 완료: /Applications/EasyEq.app"
fi
