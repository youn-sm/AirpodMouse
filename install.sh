#!/bin/zsh
# PodMouse 터미널 설치 스크립트
# 사용법: ./install.sh              빌드해서 /Applications 에 설치하고 실행
#         ./install.sh uninstall    앱 삭제
# 저장소 밖에서 실행하면 ~/PodMouse (또는 $PODMOUSE_DIR) 에 받아서 설치해요.
set -euo pipefail

REPO_URL="https://github.com/tony1010-dev/PodMouse.git"

if [[ "${1:-}" == "uninstall" ]]; then
  pkill -x PodMouse 2>/dev/null || true
  rm -rf /Applications/PodMouse.app
  echo "PodMouse 삭제 완료"
  echo "손쉬운 사용 권한 목록에 남은 항목은 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서 지워주세요."
  exit 0
fi

# macOS 14 이상인지 확인
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 14 )); then
  echo "PodMouse는 macOS 14 (Sonoma) 이상이 필요해요. 현재: $(sw_vers -productVersion)"
  exit 1
fi

# Swift 컴파일러 확인
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift 컴파일러가 없어요. 아래 명령으로 Command Line Tools를 설치한 뒤 다시 실행하세요:"
  echo "  xcode-select --install"
  exit 1
fi

# 저장소 위치 찾기 (스크립트 옆에 Sources 가 없으면 받아오기)
dir="${0:A:h}"
if [[ ! -d "$dir/Sources" ]]; then
  dir="${PODMOUSE_DIR:-$HOME/PodMouse}"
  if [[ -d "$dir/.git" ]]; then
    echo "업데이트: $dir"
    git -C "$dir" pull --ff-only
  else
    echo "다운로드: $dir"
    git clone "$REPO_URL" "$dir"
  fi
fi
cd "$dir"

# 빌드 + 설치. 기본 SDK가 설치된 컴파일러와 버전이 안 맞으면 다른 SDK로 다시 시도
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

try_build() {  # $1: SDK 경로 (비우면 기본 SDK)
  if [[ -n "${1:-}" ]]; then
    SDKROOT="$1" ./build.sh install >"$log" 2>&1
  else
    ./build.sh install >"$log" 2>&1
  fi
}

echo "빌드 중... (1분 정도 걸려요)"
if try_build; then
  cat "$log"
  exit 0
fi
if ! grep -qE "SDK is not supported by the compiler|malformed file" "$log"; then
  cat "$log"
  echo "빌드 실패. 위 오류를 확인해주세요."
  exit 1
fi

echo "기본 SDK가 컴파일러와 맞지 않아요. 설치된 다른 SDK로 다시 시도할게요."
sdks=()
for base in /Library/Developer/CommandLineTools/SDKs "$(xcode-select -p 2>/dev/null)/Platforms/MacOSX.platform/Developer/SDKs"; do
  [[ -d "$base" ]] && sdks+=("$base"/MacOSX[0-9]*.sdk(N))
done
# 높은 버전부터 시도
for sdk in ${(On)sdks}; do
  echo "→ ${sdk:t}"
  if try_build "$sdk"; then
    cat "$log"
    exit 0
  fi
done
echo "맞는 SDK를 찾지 못했어요. Xcode / Command Line Tools를 최신으로 업데이트한 뒤 다시 시도하세요."
exit 1
