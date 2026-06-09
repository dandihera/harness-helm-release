---
name: doctor
description: harness-helm h2 상태 점검 command. install-manifest.json 유무를 확인하고 GitHub Releases API로 최신 버전과 비교해 설치·업데이트·최신 상태를 출력한다. 설치 필요 또는 업데이트 가능이면 사용자 확인 후 install package zip을 내려받아 h2-install.sh 또는 h2-update.sh를 실행한다.
user-invocable: true
argument: optional
allowed-tools: [Bash, Read]
---

# h2:doctor

`/h2:doctor`는 harness-helm h2 상태를 점검하고 설치·업데이트를 처리하는 단일 진입점 command입니다.

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

이 command는 prompt template이며, 모델이 다음 순서로 `Bash`·`Read` tool을 호출해 진행한다.

1. **Target resolution**
   - `--target`이 있으면 그 경로를 target으로 결정.
   - `--target`이 없으면 `Bash`로 `git rev-parse --show-toplevel`을 실행해 repository root를 target으로 결정.
   - `git rev-parse --show-toplevel`이 실패하고 `--allow-non-git`도 없으면 안내 후 중단.
   - `--allow-non-git`이 있으면 `pwd`를 target으로 결정.
   - `Bash`로 `test -d <target>/.git` 확인. `.git`이 없고 `--allow-non-git`도 없으면 안내 후 중단.

2. **install-manifest.json 존재 확인**
   - `Bash`로 `test -f <target>/.harness-helm/install-manifest.json`를 실행.
     - 없으면 → `current_version = null` (최초 설치 필요 상태).
     - 있으면 → `Read`로 내용을 읽어 `package_version` field 추출 → `current_version = package_version`.

3. **GitHub Releases API 조회**
   - `Bash`로 아래를 실행해 `latest_version`을 취득한다:
     ```
     curl -fsSL https://api.github.com/repos/dandihera/harness-helm-release/releases/latest
     ```
   - 응답 JSON에서 `tag_name` 추출 → `latest_version`.
   - 실패(HTTP 오류·JSON 파싱 실패·`tag_name` 없음)이면: "GitHub Releases API 응답을 확인할 수 없습니다. 네트워크 연결을 확인하거나 H2_HARNESS_RELEASE_BASE로 직접 지정하세요." 출력 후 중단.

4. **버전 정보 + 상태 + 카트리지 plugin 표시**

   아래 정보를 **항상** 출력한다.

   **상태 결정 규칙:**

   | 조건 | 상태 |
   |------|------|
   | `current_version = null` | 설치 필요 |
   | `latest_version > current_version` (SemVer) | 업데이트 가능 |
   | `latest_version == current_version` | 최신 상태 |
   | `latest_version < current_version` | 최신 상태 (+ 다운그레이드 경고 WARN) |

   **카트리지 plugin 감지 순서:**
   - 1순위: `Read`로 `~/.claude/plugins/installed_plugins.json` 읽어 `gstack`·`superpowers`·`compound-engineering` 항목 존재 확인.
   - 2순위: `Bash`로 `test -d ~/.claude/skills/{plugin-name}` 확인.
   - 감지 불가 → `? 미확인` 표시 (✗ 미설치와 구분).

   **출력 형식 예시:**

   ```
   harness-helm (h2) 상태
   ─────────────────────────────────────
   설치된 버전:  (없음)
   최신 버전:    v0.20.0
   상태:         설치 필요

   카트리지 플러그인
     gstack               ✗ 미설치
     superpowers          ✓ 설치됨
     compound-engineering ✗ 미설치
   ─────────────────────────────────────
   ```

   미설치 카트리지 plugin이 있으면 아래 안내를 추가한다:

   ```
   ⚠ 미설치 카트리지 플러그인이 있습니다. h2 workflow의 일부 surface를 사용하려면 해당 플러그인이 필요합니다.
   ```

   미설치 plugin이 있어도 설치·업데이트 흐름을 차단하지 않는다.

5. **Preflight (플랫폼 체크)**
   - **IMPORTANT**: h2 runtime은 Go binary(`harness`)다. `python3`, `harness.py`, `harness_lib/`는 v0.20.0에서 완전히 제거됐다. Python 버전 체크를 실행하거나 `harness.py`를 호출하지 말 것.
   - `Bash`로 `uname -s`와 `uname -m`을 실행해 host OS·architecture 확인.
   - `darwin/arm64`, `darwin/amd64`, `linux/amd64`, `linux/arm64`, `windows/amd64` 중 하나인지 확인. unsupported이면 remediation과 함께 FAIL.
   - 상태가 `최신 상태`이면 Step 6을 건너뛰고 종료.

6. **상태별 액션**

   ### [설치 필요] → 설치 흐름 (`h2-install.sh`)

   1. "설치를 진행하시겠습니까? (yes/no)" 확인 요청. no → 변경 없이 종료.
   2. install package zip asset URL 결정:
      - `H2_HARNESS_RELEASE_BASE`가 있으면 해당 base 사용. 없으면 GitHub Releases 기본 URL (`https://github.com/dandihera/harness-helm-release/releases/download/{latest_version}`).
      - 다운로드 대상: `h2-install-{latest_version}.zip`
   3. `Bash`로 install package zip을 임시 디렉터리에 다운로드 · 압축 해제:
      ```
      TMP_PKG=$(mktemp -d)
      curl -fsSL <release_base>/h2-install-{latest_version}.zip -o $TMP_PKG/pkg.zip
      unzip -q $TMP_PKG/pkg.zip -d $TMP_PKG/pkg
      ```
      실패 시: "install package를 내려받지 못했습니다." + 수동 복구 URL 출력 후 중단.
   4. dry-run 실행 및 결과 출력:
      ```
      sh $TMP_PKG/pkg/h2-install.sh --target <target> --dry-run [--backup] [--allow-non-git]
      ```
      `--dry-run` flag가 있으면 결과 출력 후 종료.
   5. "Apply / Cancel" 요청. Cancel → 변경 없이 종료.
   6. Apply:
      ```
      sh $TMP_PKG/pkg/h2-install.sh --target <target> [--backup] [--allow-non-git]
      ```

   ### [업데이트 가능] → 업데이트 흐름 (`h2-update.sh`)

   1. "`v{current_version} → v{latest_version}`로 업데이트하시겠습니까? (yes/no)" 확인 요청. no → 변경 없이 종료.
   2. install package zip asset URL 결정 (설치 흐름과 동일).
   3. install package zip 다운로드 · 압축 해제 (설치 흐름과 동일).
   4. dry-run 실행 및 결과 출력:
      ```
      sh $TMP_PKG/pkg/h2-update.sh --target <target> --from v{current_version} --to v{latest_version} --dry-run [--backup]
      ```
      `--dry-run` flag가 있으면 결과 출력 후 종료.
   5. "Apply / Cancel" 요청. Cancel → 변경 없이 종료.
   6. Apply:
      ```
      sh $TMP_PKG/pkg/h2-update.sh --target <target> --from v{current_version} --to v{latest_version} [--backup]
      ```

   ### [최신 상태]

   추가 액션 없이 종료. 다운그레이드 경고가 있으면 WARN 한 줄 추가.

7. **Post-apply result**
   - `<target>/.harness-helm/install-manifest.json` 경로를 출력.
   - `<target>/.harness-helm/bin/harness(.exe)` 경로와 `install-manifest.json.runtime_binary` evidence를 출력.
   - 다음 권장 명령(`/h2:plan` 또는 `/h2:context`)을 한 줄 안내.
   - 진단 결과는 `<target>/.harness-helm/doctor/latest.json`에 log 용도로 남긴다 (guard 판정에는 사용하지 않음).

## Failure Handling

- Step 3 API 조회 실패 시 즉시 중단. 오류 메시지와 `H2_HARNESS_RELEASE_BASE` 직접 지정 방법 안내.
- Step 6 zip 다운로드 실패 시: "install package를 내려받지 못했습니다." + 수동 복구 URL 출력 후 중단.
- Step 6 apply 실패 시:
  - `install-manifest.json`은 작성되지 않은 상태로 둔다.
  - `--backup`이 사용됐으면 backup으로 자동 rollback 시도.
  - partial 상태 감지 시 `<target>/.harness-helm/install-partial.json`에 상태 기록 후 `/h2:doctor` 재실행 안내.

## Re-run / Idempotency

- `install-manifest.json`이 있고 최신 버전이면 "최신 상태" 출력 후 추가 액션 없이 종료.
- 같은 version으로 재실행 시 `unchanged` 상태 유지.

## Notes

- `/h2:doctor`는 `h2` 진입점의 유일한 doctor command다. 다른 `/h2:*` 명령은 target install 단계에서 target 측 `.claude/commands/h2/*.md`에 위치한다.
- guard 판정 기준은 `<target>/.harness-helm/install-manifest.json` 단독이다.
- `H2_HARNESS_RELEASE_BASE` 환경변수는 release asset base override용이다 (CI 환경, 로컬 테스트용).
- 설치(`h2-install.sh`)와 업데이트(`h2-update.sh`)는 별개 스크립트다. doctor가 install package zip을 내려받아 임시 디렉터리에 풀고 상태에 맞는 스크립트를 실행한다.
