#!/bin/sh
# install.sh — curl 기반 harness-helm full suite 설치 스크립트.
# 프로젝트 루트에서 실행하면 h2-install-vX.Y.Z.zip을 내려받아
# 내부 h2-install.sh에 위임해 full suite를 설치한다.
#
# 사용법:
#   sh install.sh [--target <dir>] [--allow-non-git] [--version <ver>]
#   curl -fsSL <url>/install.sh | sh -s -- [--target <dir>] [--allow-non-git]
#
# 환경변수:
#   H2_VERSION              설치할 버전 tag (예: v0.23.0). 미설정 시 latest 자동 조회.
#   H2_INSTALL_PACKAGE_BASE zip 다운로드 base URL override (로컬 smoke 용).
#   H2_HARNESS_RELEASE_BASE harness binary 다운로드 override (h2-install.sh에 전달).

set -eu

RELEASE_REPO="dandihera/harness-helm-release"
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# --------------------------------------------------------------------------
# 인수 파싱
# --version / --version=* 만 소비하고 나머지는 $@로 재구성해 h2-install.sh에 전달.
# POSIX sh에 배열이 없으므로 eval 기반 누적 후 set -- 로 재조립한다.
# --------------------------------------------------------------------------
VERSION="${H2_VERSION:-}"
_i=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --version=*)
            VERSION="${1#--version=}"
            shift
            ;;
        *)
            _i=$((_i + 1))
            eval "_fw${_i}=\$1"
            shift
            ;;
    esac
done

_j=1
set --
while [ $_j -le $_i ]; do
    eval "set -- \"\$@\" \"\$_fw$_j\""
    _j=$((_j + 1))
done
unset _i _j

# --------------------------------------------------------------------------
# 필수 도구 확인
# --------------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "오류: curl 또는 wget이 필요합니다." >&2
    exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
    echo "오류: unzip이 필요합니다." >&2
    echo "  macOS:  brew install unzip" >&2
    echo "  Ubuntu: apt-get install -y unzip" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# 다운로드 헬퍼
# --------------------------------------------------------------------------
fetch() {
    src="$1"
    dst="$2"
    case "$src" in
        file://*)
            cp "${src#file://}" "$dst"
            ;;
        http://*|https://*)
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL "$src" -o "$dst"
            else
                wget -qO "$dst" "$src"
            fi
            ;;
        *)
            cp "$src" "$dst"
            ;;
    esac
}

# --------------------------------------------------------------------------
# 버전 결정
# --------------------------------------------------------------------------
if [ -z "$VERSION" ]; then
    echo "harness-helm 최신 버전을 확인하는 중..." >&2
    API_URL="https://api.github.com/repos/$RELEASE_REPO/releases/latest"
    API_RESP="$TMPDIR_WORK/latest.json"

    if ! fetch "$API_URL" "$API_RESP" 2>/dev/null; then
        echo "오류: GitHub API 응답을 받지 못했습니다." >&2
        echo "  H2_VERSION=vX.Y.Z sh install.sh 형태로 버전을 직접 지정하세요." >&2
        exit 1
    fi

    VERSION=$(sed -n 's/.*"tag_name":[ ]*"\([^"]*\)".*/\1/p' "$API_RESP" | head -1)

    if [ -z "$VERSION" ]; then
        echo "오류: 버전 tag를 파싱하지 못했습니다." >&2
        echo "  H2_VERSION=vX.Y.Z sh install.sh 형태로 버전을 직접 지정하세요." >&2
        exit 1
    fi
fi

echo "harness-helm $VERSION 설치를 시작합니다..." >&2

# --------------------------------------------------------------------------
# zip 다운로드
# --------------------------------------------------------------------------
ZIP_NAME="h2-install-${VERSION}.zip"
BASE_URL="${H2_INSTALL_PACKAGE_BASE:-"https://github.com/$RELEASE_REPO/releases/download/$VERSION"}"
ZIP_URL="${BASE_URL%/}/$ZIP_NAME"
ZIP_PATH="$TMPDIR_WORK/$ZIP_NAME"

echo "  $ZIP_URL" >&2
if ! fetch "$ZIP_URL" "$ZIP_PATH" 2>/dev/null; then
    echo "오류: zip 다운로드 실패: $ZIP_URL" >&2
    echo "  수동 복구: curl -fsSL $ZIP_URL -o /tmp/$ZIP_NAME && unzip /tmp/$ZIP_NAME && sh h2-install.sh" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# 압축 해제
# --------------------------------------------------------------------------
EXTRACT_DIR="$TMPDIR_WORK/extracted"
mkdir -p "$EXTRACT_DIR"
unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR"

BOOTSTRAP="$EXTRACT_DIR/h2-install.sh"
if [ ! -f "$BOOTSTRAP" ]; then
    echo "오류: zip 내부에 h2-install.sh가 없습니다." >&2
    echo "  예상 경로: $BOOTSTRAP" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# h2-install.sh 위임 — "$@"로 공백 포함 경로를 안전하게 전달
# --------------------------------------------------------------------------
exec sh "$BOOTSTRAP" "$@"
