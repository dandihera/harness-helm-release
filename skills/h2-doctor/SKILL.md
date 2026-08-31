---
name: h2-doctor
description: Bootstrap skill for harness-helm h2-doctor. Provides /h2-doctor:doctor for first-time project setup. For the full h2 workflow, run /h2-doctor:doctor to install the complete runtime.
---

# h2-doctor (bootstrap)

Bootstrap skill. Provides only `/h2-doctor:doctor` for first-time harness-helm setup.

`/h2:plan`, `/h2:design`, and other workflow commands are available after running `/h2-doctor:doctor` to install the complete runtime.

## /h2-doctor:doctor

`install.sh` 기반 curl 설치 후 프로젝트에 등록된 doctor skill의 진입점.

전체 Execution Sequence는 `.codex/skills/h2-doctor/doctor.md` (Codex) 또는 `.claude/skills/h2-doctor/doctor.md` (Claude Code)에 정의되어 있다.

지원 인자: `--dry-run`, `--target`, `--backup`, `--allow-non-git`, `--version <vX.Y.Z>` (지정 시 latest 무관 명시 버전 설치·downgrade/rollback)

### 부트스트랩 설치

runtime binary가 없는 기기에서 최초 설치할 때 실행한다. `<target>`은 프로젝트 루트 절대경로다.

```sh
curl -fsSL https://raw.githubusercontent.com/dandihera/harness-helm-release/main/install.sh | sh -s -- --target '<target>' [--allow-non-git] [--version <vX.Y.Z>]
```

```powershell
& ([ScriptBlock]::Create((irm https://raw.githubusercontent.com/dandihera/harness-helm-release/main/install.ps1))) -Target '<target>' [-AllowNonGit] [-Version <vX.Y.Z>]
```

설치 asset은 source repo `dandihera/harness-helm`가 아니라 release repo `dandihera/harness-helm-release`에 있다. 지정하지 않은 선택 인자는 대괄호째 생략한다.

