#!/bin/zsh
# PodMouse.app 빌드 → ./build/PodMouse.app
# 사용법: ./build.sh            빌드만
#         ./build.sh install    /Applications 에 복사하고 실행
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PodMouse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/. "$APP/Contents/Resources/"   # 권한 요청 문구 (한국어/영어)

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/PodMouse" \
  Sources/*.swift

# 개발자 인증서가 있으면 그걸로 서명 (재빌드해도 손쉬운 사용 권한이 유지됨). 없으면 ad-hoc.
IDENTITY="${PODMOUSE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "서명: ${IDENTITY:-ad-hoc}"
echo "빌드 완료: $PWD/$APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x PodMouse 2>/dev/null || true
  # 완전히 종료될 때까지 기다려야 다시 열 때 실패하지 않음
  for _ in {1..30}; do pgrep -x PodMouse >/dev/null || break; sleep 0.1; done
  rm -rf /Applications/PodMouse.app
  cp -R "$APP" /Applications/
  open /Applications/PodMouse.app
  echo "설치 및 실행: /Applications/PodMouse.app"
fi
