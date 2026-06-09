# install.ps1 — Invoke-WebRequest 기반 h2 doctor skill 설치 스크립트.
# 프로젝트 루트에서 실행하면 .claude/skills/h2/{SKILL.md,doctor.md}(Claude Code)와
# .codex/skills/h2/{SKILL.md,doctor.md}(Codex)를 git repository root에 배치한다.
param([switch]$AllowNonGit)

$ErrorActionPreference = 'Stop'
$BASE_URL = "https://raw.githubusercontent.com/dandihera/harness-helm-release/main"
$TMP = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

if ($AllowNonGit) {
    $TARGET_ROOT = (Get-Location).Path
} else {
    $TARGET_ROOT = git rev-parse --show-toplevel 2>$null
    if (-not $TARGET_ROOT) {
        Write-Error "오류: git repository root를 찾을 수 없습니다.`n프로젝트 루트에서 다시 실행하거나 -AllowNonGit을 사용하세요."
        exit 1
    }
}

Write-Host "harness-helm h2 doctor를 내려받는 중..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $TMP | Out-Null
try {
    Invoke-WebRequest -Uri "$BASE_URL/skills/h2/SKILL.md" -OutFile "$TMP/SKILL.md" -UseBasicParsing
    Invoke-WebRequest -Uri "$BASE_URL/skills/h2/doctor.md" -OutFile "$TMP/doctor.md" -UseBasicParsing
} catch {
    Write-Error "오류: 다운로드 실패 — $_`n수동 복구: Invoke-WebRequest $BASE_URL/skills/h2/SKILL.md -OutFile .claude/skills/h2/SKILL.md"
    Remove-Item $TMP -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

New-Item -ItemType Directory -Force -Path "$TARGET_ROOT/.claude/skills/h2" | Out-Null
New-Item -ItemType Directory -Force -Path "$TARGET_ROOT/.codex/skills/h2" | Out-Null
Copy-Item "$TMP/SKILL.md"  "$TARGET_ROOT/.claude/skills/h2/SKILL.md"  -Force
Copy-Item "$TMP/doctor.md" "$TARGET_ROOT/.claude/skills/h2/doctor.md" -Force
Copy-Item "$TMP/SKILL.md"  "$TARGET_ROOT/.codex/skills/h2/SKILL.md"   -Force
Copy-Item "$TMP/doctor.md" "$TARGET_ROOT/.codex/skills/h2/doctor.md"  -Force
Remove-Item $TMP -Recurse -Force

Write-Host "✓ harness-helm h2 doctor가 설치됐습니다."
Write-Host "  Claude Code: .claude/skills/h2/  (SKILL.md + doctor.md)"
Write-Host "  Codex:       `$h2 doctor  (.codex/skills/h2/doctor.md)"
