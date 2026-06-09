#!/bin/sh
# install.sh — curl 기반 h2 doctor skill 설치 스크립트.
# 프로젝트 루트에서 실행하면 .claude/skills/h2/{SKILL.md,doctor.md}(Claude Code)와
# .codex/skills/h2/{SKILL.md,doctor.md}(Codex)를 git repository root에 배치한다.

set -eu

BASE_URL="https://raw.githubusercontent.com/dandihera/harness-helm-release/main"
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# --allow-non-git 플래그 파싱
ALLOW_NON_GIT=0
for arg in "$@"; do
    case "$arg" in
        --allow-non-git) ALLOW_NON_GIT=1 ;;
    esac
done

# git root 감지
if [ "$ALLOW_NON_GIT" = "1" ]; then
    TARGET_ROOT=$(pwd)
else
    TARGET_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -z "$TARGET_ROOT" ]; then
        echo "오류: git repository root를 찾을 수 없습니다." >&2
        echo "프로젝트 루트에서 다시 실행하거나 --allow-non-git을 사용하세요." >&2
        exit 1
    fi
fi

echo "harness-helm h2 doctor를 내려받는 중..." >&2

if ! curl -fsSL "$BASE_URL/skills/h2/SKILL.md" -o "$TMPDIR_WORK/SKILL.md" 2>/dev/null; then
    echo "오류: skills/h2/SKILL.md 다운로드 실패" >&2
    echo "수동 복구: curl -fsSL $BASE_URL/skills/h2/SKILL.md -o $TARGET_ROOT/.claude/skills/h2/SKILL.md" >&2
    exit 1
fi

if ! curl -fsSL "$BASE_URL/skills/h2/doctor.md" -o "$TMPDIR_WORK/doctor.md" 2>/dev/null; then
    echo "오류: skills/h2/doctor.md 다운로드 실패" >&2
    echo "수동 복구: curl -fsSL $BASE_URL/skills/h2/doctor.md -o $TARGET_ROOT/.claude/skills/h2/doctor.md" >&2
    exit 1
fi

# 모든 파일 성공 시 최종 위치로 이동 (atomic)
mkdir -p "$TARGET_ROOT/.claude/skills/h2" "$TARGET_ROOT/.codex/skills/h2"
cp "$TMPDIR_WORK/SKILL.md"   "$TARGET_ROOT/.claude/skills/h2/SKILL.md"
cp "$TMPDIR_WORK/doctor.md"  "$TARGET_ROOT/.claude/skills/h2/doctor.md"
mv "$TMPDIR_WORK/SKILL.md"   "$TARGET_ROOT/.codex/skills/h2/SKILL.md"
mv "$TMPDIR_WORK/doctor.md"  "$TARGET_ROOT/.codex/skills/h2/doctor.md"

echo "✓ harness-helm h2 doctor가 설치됐습니다."
echo "  Claude Code: .claude/skills/h2/  (SKILL.md + doctor.md)"
echo "  Codex:       \$h2 doctor  (.codex/skills/h2/doctor.md)"
