#!/bin/bash
# EasyEq 최신 릴리스를 받아 /Applications에 설치하고 실행한다.
# 사용법: curl -fsSL https://raw.githubusercontent.com/soonocooling/easyeq/main/scripts/install.sh | bash
# 접근성 권한은 macOS가 사용자에게만 허용하므로, 설치 후 직접 켜야 한다.
set -euo pipefail

REPO="soonocooling/easyeq"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
URL="https://github.com/$REPO/releases/latest/download/EasyEq.zip"

if [ "$(uname)" != "Darwin" ]; then
    echo "EasyEq는 macOS 전용입니다." >&2
    exit 1
fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 13 ]; then
    echo "macOS 13 이상이 필요합니다 (현재 $(sw_vers -productVersion))." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "내려받는 중: $URL"
curl -fsSL "$URL" -o "$WORK/EasyEq.zip"
ditto -x -k "$WORK/EasyEq.zip" "$WORK"
if [ ! -d "$WORK/EasyEq.app" ]; then
    echo "압축 파일에 EasyEq.app이 없습니다." >&2
    exit 1
fi

pkill -x EasyEq 2>/dev/null || true
rm -rf "$INSTALL_DIR/EasyEq.app"
ditto "$WORK/EasyEq.app" "$INSTALL_DIR/EasyEq.app"
# 공증받지 않은 개인 빌드라서 Gatekeeper 격리 표시를 지운다 ("그래도 열기" 단계 생략).
xattr -dr com.apple.quarantine "$INSTALL_DIR/EasyEq.app" 2>/dev/null || true
echo "설치 완료: $INSTALL_DIR/EasyEq.app"

if [ -z "${NO_OPEN:-}" ]; then
    open "$INSTALL_DIR/EasyEq.app"
fi

cat <<'MSG'

남은 단계 (사용자가 직접 해야 합니다):
  1. 화면에 뜬 "EasyEq 시작하기" 창에서 [시스템 설정 열기]를 누릅니다.
  2. 손쉬운 사용(Accessibility) 목록에서 EasyEq를 켭니다.
  3. 메뉴 막대에 √ 아이콘이 보이면 완료입니다. 사용법은 메뉴의 "사용 설명서"에 있습니다.
MSG
