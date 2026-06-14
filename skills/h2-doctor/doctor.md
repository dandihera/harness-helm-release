---
name: doctor
description: harness-helm h2 상태 점검 command. target runtime의 harness doctor binary를 호출해 최신 상태, 업데이트 가능, 오류 상태를 확인하고 업데이트 가능이면 사용자 확인 후 update script를 실행한다.
user-invocable: true
argument: optional
allowed-tools: [Bash]
---

# h2:doctor

`/h2:doctor`는 이미 설치된 harness-helm h2 runtime의 상태를 점검하고 업데이트를 처리하는 단일 진입점 command입니다.

## Inputs (optional)

```text
/h2:doctor
/h2:doctor --dry-run
/h2:doctor --target <path>
/h2:doctor --backup
/h2:doctor --allow-non-git
```

기본값:

- `--target`: 지정하지 않으면 현재 위치에서 `git rev-parse --show-toplevel`로 repository root를 자동 감지. 실패하고 `--allow-non-git`도 없으면 안내 후 중단.
- `--dry-run`: false (false면 사용자 승인 후 실제 적용)
- `--backup`: false (기존 파일 backup 여부)
- `--allow-non-git`: false (`.git` 없으면 중단)

## Execution Sequence

1. **harness doctor 상태 조회** — 단일 Bash tool 호출
   - 다음 중 해당하는 snippet을 **하나의 Bash tool 호출**로 실행한다.

   `--target <path>` 명시 시:
   ```bash
   target='<path>'
   [ -x "$target/.harness-helm/bin/harness" ] || {
     echo "h2 runtime binary가 없습니다. curl bootstrap으로 runtime을 먼저 준비한 뒤 /h2:doctor를 다시 실행하세요."
     exit 1
   }
   "$target/.harness-helm/bin/harness" doctor --target "$target"
   ```

   기본값 (`--target` 없음, `--allow-non-git` 없음):
   ```bash
   target=$(git rev-parse --show-toplevel 2>/dev/null) || {
     echo "git repository root를 찾을 수 없습니다. git repository 안에서 실행하거나 --allow-non-git을 사용하세요."
     exit 1
   }
   [ -x "$target/.harness-helm/bin/harness" ] || {
     echo "h2 runtime binary가 없습니다. curl bootstrap으로 runtime을 먼저 준비한 뒤 /h2:doctor를 다시 실행하세요."
     exit 1
   }
   "$target/.harness-helm/bin/harness" doctor --target "$target"
   ```

   `--allow-non-git` 있는 경우:
   ```bash
   target=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
   [ -x "$target/.harness-helm/bin/harness" ] || {
     echo "h2 runtime binary가 없습니다. curl bootstrap으로 runtime을 먼저 준비한 뒤 /h2:doctor를 다시 실행하세요."
     exit 1
   }
   "$target/.harness-helm/bin/harness" doctor --target "$target"
   ```

   - 출력 결과를 사용자에게 그대로 표시한다.
   - 종료 코드(`$?`)에 따라 분기:
     - `0` → 최신 상태. 추가 액션 없이 종료.
     - `2` → Step 2 [업데이트 가능] 흐름으로 진입.
     - `3` → "상태 확인 중 오류가 발생했습니다." 출력 후 중단.
     - 그 외 → "알 수 없는 종료 코드입니다." 출력 후 중단.
   - **IMPORTANT**: h2 runtime은 Go binary(`harness`)다. `python3`, `harness.py`, `harness_lib/`는 v0.20.0에서 완전히 제거됐다. Python 버전 체크를 실행하거나 `harness.py`를 호출하지 말 것.

2. **업데이트 가능 상태 처리**
   - Step 1 출력에서 `설치된 버전:` 줄의 마지막 SemVer token을 `current_version`으로 사용한다.
   - Step 1 출력에서 `최신 버전:` 줄의 마지막 SemVer token을 `latest_version`으로 사용한다.
   - 둘 중 하나라도 추출하지 못하면 업데이트를 진행하지 않고 중단한다.
   - "`{current_version} → {latest_version}`로 업데이트하시겠습니까? (yes/no)" 확인 요청. no → 변경 없이 종료.
   - release asset base 결정:
     - `H2_HARNESS_RELEASE_BASE`가 있으면 해당 base 사용.
     - 없으면 release 레포(`dandihera/harness-helm-release`) 기본 URL (`https://github.com/dandihera/harness-helm-release/releases/download/{latest_version}`).
   - install package zip(`h2-install-{latest_version}.zip`)을 임시 디렉터리에 다운로드 · 압축 해제한다. base가 http(s)가 아니면(`file://` 또는 로컬 경로) `h2-update.sh`의 `fetch()`와 동일하게 `cp`로 처리한다.
     ```bash
     TMP_PKG=$(mktemp -d)
     release_base="${H2_HARNESS_RELEASE_BASE:-https://github.com/dandihera/harness-helm-release/releases/download/${latest_version}}"
     release_base="${release_base%/}"
     package_zip="h2-install-${latest_version}.zip"
     case "$release_base" in
       http://*|https://*) curl -fsSL "$release_base/$package_zip" -o "$TMP_PKG/pkg.zip" ;;
       file://*)           cp "${release_base#file://}/$package_zip" "$TMP_PKG/pkg.zip" ;;
       *)                  cp "$release_base/$package_zip" "$TMP_PKG/pkg.zip" ;;
     esac
     unzip -q "$TMP_PKG/pkg.zip" -d "$TMP_PKG/pkg"
     ```
     실패 시: "install package를 내려받지 못했습니다." + 수동 복구 URL 출력 후 중단.
   - dry-run 실행 및 결과 출력:
     ```text
     sh $TMP_PKG/pkg/h2-update.sh --target <target> --dry-run [--backup]
     ```
     `--dry-run` flag가 있으면 결과 출력 후 종료.
   - "Apply / Cancel" 요청. Cancel → 변경 없이 종료.
   - Apply:
     ```text
     sh $TMP_PKG/pkg/h2-update.sh --target <target> [--backup]
     ```

3. **Post-apply result**
   - `<target>/.harness-helm/install-manifest.json` 경로를 출력.
   - `<target>/.harness-helm/bin/harness(.exe)` 경로와 `install-manifest.json.runtime_binary` evidence를 출력.
   - 다음 권장 명령(`/h2:plan` 또는 `/h2:context`)을 한 줄 안내.

## Failure Handling

- Step 1 binary 호출 실패 시 (binary 없음 또는 git 실패): 해당 오류 메시지 출력 후 중단.
- Step 1 상태 조회 실패(exit 3) 시 즉시 중단. 오류 메시지와 `H2_GITHUB_API_BASE` 직접 지정 방법 안내.
- Step 2 zip 다운로드 실패 시: "install package를 내려받지 못했습니다." + 수동 복구 URL 출력 후 중단.
- Step 2 apply 실패 시:
  - `install-manifest.json`은 성공한 install command만 갱신한다.
  - `--backup`이 사용됐으면 backup으로 자동 rollback 시도.
  - partial 상태 감지 시 `<target>/.harness-helm/install-partial.json`에 상태 기록 후 `/h2:doctor` 재실행 안내.

## Re-run / Idempotency

- 최신 버전이면 "최신 상태" 출력 후 추가 액션 없이 종료.
- 같은 version으로 재실행 시 `unchanged` 상태 유지.

## Notes

- `/h2:doctor`는 `h2` 진입점의 유일한 doctor command다. 다른 `/h2:*` 명령은 target install 단계에서 target 측 `.claude/commands/h2/*.md`에 위치한다.
- guard 판정 기준은 `<target>/.harness-helm/install-manifest.json` 단독이다.
- release asset 레포는 `dandihera/harness-helm-release`다 (source 레포 `dandihera/harness-helm`와 별개). 기본 base: `https://github.com/dandihera/harness-helm-release/releases/download/{latest_version}`.
- `H2_HARNESS_RELEASE_BASE` 환경변수는 release asset base override용이다 (CI 환경, 로컬 테스트용). override 디렉터리에는 다음 파일이 **모두** 있어야 한다:
  - `h2-install-<VER>.zip` — doctor.md 공통 절차가 받아 압축 해제하는 install package.
  - `harness-<VER>-<os>-<arch>` — zip 내부 `h2-update.sh`가 받는 runtime binary (예: `harness-v0.35.1-darwin-arm64`).
  - `harness-<VER>-<os>-<arch>.sha256` — 위 binary의 checksum sidecar.
  - Windows에서는 binary가 `harness-<VER>-windows-<arch>.exe` + `.sha256`이며 `h2-update.ps1` 경로를 사용한다.
- curl/wget 차단 환경(context-mode 플러그인 등)에서는 위 파일을 로컬에 두고 `H2_HARNESS_RELEASE_BASE=file:///abs/local/dir`(권장) 또는 절대/상대 로컬 경로로 실행한다. http(s)가 아닌 base는 doctor.md zip 단계와 `h2-update.sh` `fetch()` 모두 `cp`로 처리하므로 curl/wget 없이 zip·binary 다운로드가 완료된다.
