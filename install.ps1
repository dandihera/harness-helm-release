# install.ps1 — Invoke-WebRequest 기반 harness-helm full suite 설치 스크립트.
# 프로젝트 루트에서 실행하면 h2-install-vX.Y.Z.zip을 내려받아
# 내부 h2-install.ps1에 위임해 full suite를 설치한다.
#
# 사용법:
#   pwsh -File install.ps1 [-Target <dir>] [-AllowNonGit] [-Version <ver>]
#
# 환경변수:
#   H2_VERSION              설치할 버전 tag (예: v0.23.0). 미설정 시 latest 자동 조회.
#   H2_INSTALL_PACKAGE_BASE zip 다운로드 base URL override (로컬 smoke 용).
param(
    [string]$Target = "",
    [switch]$AllowNonGit,
    [string]$Version = ""
)

$ErrorActionPreference = 'Stop'
$ReleaseRepo = "dandihera/harness-helm-release"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    # ----------------------------------------------------------------------
    # 버전 결정
    # ----------------------------------------------------------------------
    if (-not $Version -and $env:H2_VERSION) { $Version = $env:H2_VERSION }

    if (-not $Version) {
        Write-Host "harness-helm 최신 버전을 확인하는 중..." -ForegroundColor Cyan
        $ApiUrl = "https://api.github.com/repos/$ReleaseRepo/releases/latest"
        try {
            $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
            $Version = $Release.tag_name
        } catch {
            Write-Error "오류: GitHub API 응답을 받지 못했습니다.`n  H2_VERSION=vX.Y.Z 환경변수를 설정하거나 -Version 파라미터를 사용하세요."
            exit 1
        }
        if (-not $Version) {
            Write-Error "오류: 버전 tag를 파싱하지 못했습니다."
            exit 1
        }
    }

    Write-Host "harness-helm $Version 설치를 시작합니다..." -ForegroundColor Cyan

    # ----------------------------------------------------------------------
    # zip 다운로드
    # ----------------------------------------------------------------------
    $ZipName = "h2-install-$Version.zip"
    $BaseUrl = if ($env:H2_INSTALL_PACKAGE_BASE) {
        $env:H2_INSTALL_PACKAGE_BASE.TrimEnd('/')
    } else {
        "https://github.com/$ReleaseRepo/releases/download/$Version"
    }
    $ZipUrl = "$BaseUrl/$ZipName"
    $ZipPath = Join-Path $Tmp $ZipName

    Write-Host "  $ZipUrl" -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
    } catch {
        Write-Error "오류: zip 다운로드 실패: $ZipUrl`n  수동 복구: Invoke-WebRequest $ZipUrl -OutFile $ZipPath"
        exit 1
    }

    # ----------------------------------------------------------------------
    # 압축 해제
    # ----------------------------------------------------------------------
    $ExtractDir = Join-Path $Tmp "extracted"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $Bootstrap = Join-Path $ExtractDir "h2-install.ps1"
    if (-not (Test-Path $Bootstrap)) {
        Write-Error "오류: zip 내부에 h2-install.ps1이 없습니다.`n  예상 경로: $Bootstrap"
        exit 1
    }

    # ----------------------------------------------------------------------
    # h2-install.ps1 위임
    # ----------------------------------------------------------------------
    $ForwardArgs = @{}
    if ($Target)      { $ForwardArgs['Target']      = $Target }
    if ($AllowNonGit) { $ForwardArgs['AllowNonGit'] = $true }

    & $Bootstrap @ForwardArgs

} finally {
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
