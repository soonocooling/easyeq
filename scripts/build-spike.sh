#!/bin/bash
# Phase 0 스파이크를 .app으로 묶고 고정 인증서로 서명한다.
# 서명이 바뀌면 접근성 권한이 초기화되므로 항상 같은 인증서를 쓴다.
# 사용법: scripts/build-spike.sh            (첫 번째 Apple Development 인증서)
#         SIGN_IDENTITY="이름" scripts/build-spike.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/EasyEqSpike.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "서명 인증서를 찾지 못했습니다. SIGN_IDENTITY를 지정하세요." >&2
    exit 1
fi

swift build -c release --product EasyEqSpike

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/EasyEqSpike "$APP/Contents/MacOS/EasyEqSpike"
cp docs/manual.html docs/manual.en.html "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>EasyEqSpike</string>
    <key>CFBundleIdentifier</key><string>com.soonocooling.easyeq.spike</string>
    <key>CFBundleName</key><string>EasyEqSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign "$IDENTITY" "$APP"
echo "빌드 완료: $APP (서명: $IDENTITY)"
echo "실행: open $APP   /   로그: ~/Library/Logs/EasyEqSpike.log"
