---
name: unity-init
description: >-
  Initialize a Unity repo around the Unity CLI (`unity`) — install the CLI and the project's Editor
  plus build modules, wire version control for Unity (`unity vcs doctor`, UnityYAMLMerge merge
  setup, integrity hooks, LFS locking for scenes), set up the stable/main branch model, and write a
  GitHub Actions workflow that tests every PR into stable and builds stable and v* tags with
  `unity test` and `unity build` on self-hosted or GitHub-hosted runners, with a pre-activated
  runner (any license, including Personal), Pro serial, or floating license activation. Use this skill whenever the user
  wants to adopt, install, or standardize on the Unity CLI, set up CI without GameCI, onboard
  teammates' machines, fix scene/prefab merge problems with Unity's tooling, set up a self-hosted
  Unity build runner, or asks about `unity build`, `unity test`, `unity ci init`, `unity vcs`, or
  `unity license activate`. GameCI (the gameci-pipeline skill) is the fallback when the CLI can't do
  the job.
---

# Unity init

## The idea

The Unity CLI is one binary that installs Editors and modules, runs builds and tests in batch mode,
activates licenses, and understands Unity assets under git. Using it for **both** a teammate's
machine and CI means "it passed on my machine" and "it passed in CI" run the same commands against
the same pinned Editor. This skill sets a repo up that way:

1. **Machine** — the CLI, the project's Editor, and the modules the build targets need.
2. **Version control** — Unity-aware git: merge driver, hooks, LFS patterns, locking.
3. **Branch model** — `main` ships, `stable` integrates, short-lived `feature/*` and `level/*`.
4. **CI** — one workflow: test PRs into `stable`, build pushes to `stable` and `v*` tags.
5. **CLAUDE.md** — the team's commands and decisions, so agents and reviewers use them.

The CLI (1.0.0-beta.11) and `com.unity.pipeline` (0.8.0-exp.1) are **experimental**. Pin versions,
read `unity <command> --help` before using a flag you haven't seen in `references/cli-reference.md`,
and keep GameCI (`gameci-pipeline` skill) as the fallback.

## Where things run

The Editor is installed **only on people's own machines** (and dedicated runners). Cloud and
container dev environments — GitHub Codespaces (`$CODESPACES`), dev containers
(`$REMOTE_CONTAINERS`, `/.dockerenv`), Gitpod, SSH sandboxes — get the **CLI only**: a multi-GB
Editor there burns disk and can't be opened anyway.

| Environment | CLI | Editor + modules | Editor-dependent steps |
| --- | --- | --- | --- |
| Cloud / container dev env | yes | **never** | skip `vcs merge-setup`, local `unity test`/`build`; list them in the hand-over for each person's machine |
| A teammate's own machine | yes | yes | all |
| Self-hosted runner | yes (pre-installed) | yes (pre-installed) | CI verifies; never installs |
| GitHub-hosted runner | installed per job | installed per job | all |

Detect the environment in Step 1 and say which column applies before doing anything.

## What you produce

1. The Unity CLI installed and the project's Editor + modules present (`unity doctor` clean).
2. Repo hygiene from `unity vcs doctor --fix`, reviewed as a diff, plus merge setup and hooks.
3. A `stable` branch (created locally; pushing is the human's call) and the branch model recorded.
4. `.github/workflows/unity.yml` from `assets/unity-cli.yml`, every `TAILOR` marker resolved.
5. CLAUDE.md sections: **Branching**, **Unity CLI** (team commands), **CI** (targets, runner labels,
   license mode, projectPath, secret names).
6. Printed for the human: secrets to add, runner setup steps, branch protection commands.

## Step 1 — Inspect first

- `projectPath` (folder with `Assets/`), Editor version from `ProjectSettings/ProjectVersion.txt`.
- `Packages/manifest.json` — is `com.unity.pipeline` present? Is `packages-lock.json` committed?
- `.gitattributes` / `.gitignore`, existing `.github/workflows/`, existing CLAUDE.md sections.
- `gh repo view --json visibility,defaultBranchRef` — **never put a self-hosted runner on a public
  repo**: any fork PR could run code on it. The workflow also skips fork PRs, but that's a backstop.
- Ask (don't guess): build targets, runner type and labels, license type, branch names.

## Step 2 — Machine

In a cloud/container dev environment, do only the CLI install and `unity doctor` here, then go to
Step 3 and skip the Editor-dependent commands.

- Install: `curl -fsSL https://unity.com/install.sh | UNITY_CLI_CHANNEL=beta UNITY_CLI_VERSION=<pin> bash`
  (Linux → `~/.local/bin/unity`; `UNITY_CLI_HOME` relocates it). Linux needs glibc 2.34+ (Ubuntu
  22.04+). Windows: `winget install Unity.CLI`. The installer verifies a SHA-256 from the manifest.
- Editor: `unity install <version> -m <modules> --accept-eula --yes`; add modules to an installed
  Editor with `unity install-modules -e <version> -m <modules> --accept-eula --yes`. Preview with
  `--dry-run --json` (shows download sizes). Module IDs: `windows-mono`, `webgl`, `android`,
  `linux-il2cpp`, … — a target that isn't the host's own player needs its module.
- `unity auth login` (browser) for a person; CI uses the service-account env vars instead.
- `unity doctor` to confirm. `unity pipeline install` if `com.unity.pipeline` is missing and the team
  wants Editor automation (`unity command`, `[CliCommand]`); route the package add through
  `dependency-auditor` like any dependency.
- Optional: `unity skill install claude-code` installs Unity's own CLI skill to
  `~/.claude/skills/unity-cli/` — complementary; this skill owns the repo's decisions.

## Step 3 — Version control

Run from the project folder; show the diff of anything written and ask before committing.

- `unity vcs doctor` → review → `unity vcs doctor --fix` (idempotent). Merge its output with the
  devkit's `.gitignore`/`.gitattributes` templates (`unity-project-conventions`) instead of letting
  either overwrite the other.
- `unity vcs merge-setup` — configures UnityYAMLMerge for scenes and prefabs. It needs the Editor
  installed (Step 2). It writes **local git config**, so every teammate runs it once per clone.
- `unity vcs hooks install` — pre-commit / post-checkout / post-merge integrity checks. Also per clone.
- LFS locking: add `lockable` to `*.unity` and to unmergeable binary art (`*.psd`, `*.fbx`, …) in
  `.gitattributes`. See `unity-project-conventions/references/branching.md` for why and how.

## Step 4 — Branch model

Follow `unity-project-conventions/references/branching.md`: `main` = production (tags only),
`stable` = always-playable integration branch, `feature/*` and `level/*` short-lived off `stable`.
Create `stable` from `main` locally. Pushing it and protecting branches are outward-facing — print
the commands (in that reference) and let the human run them. Record the model in CLAUDE.md so
`/code-todo` and `/ship` target `stable`.

## Step 5 — CI workflow

Copy `assets/unity-cli.yml` (canonical: `templates/ci/unity-cli.yml`) to `.github/workflows/unity.yml`
and resolve every `TAILOR`:

- **Triggers** — integration branch name. Tags `v*` build releases; `workflow_dispatch` for manual.
- **`runs-on`** — self-hosted label array (both jobs) or `ubuntu-latest`. On hosted runners the
  workflow installs the CLI, Editor, and modules; on self-hosted ones it only verifies them and fails
  with the fix command, so one file works for both. Self-hosted runners on teammates' own PCs:
  see `references/runner-setup.md` → "Runners on teammates' machines".
- **`UNITY_MODULES`** — only modules for targets that aren't the runner's own platform: a Windows
  runner building `StandaloneWindows64` needs none (empty); a Linux runner needs `windows-mono`.
- **`BUILD_TARGET` / `BUILD_NAME`** — from the chosen targets. One target → keep
  the single build job; several → turn `build` into a matrix over `BUILD_TARGET`/modules.
- **`UNITY_LICENSE_MODE`** — see below.
- **`UNITY_CLI_VERSION`** — keep the pin; bump only after reading `unity changelog`.
- **Library cache globs** — prefix with `projectPath` when it isn't `.` (hosted only).

`unity ci init --dry-run --target <T>` prints Unity's own generated workflow for the installed CLI —
diff it against the template when bumping the CLI to catch new recommended steps.

### License modes

| Mode | When | How |
| --- | --- | --- |
| `machine` | Personal or any license, **self-hosted** | Activated once on the runner as the runner's user (`references/runner-setup.md`). CI never returns it. |
| `file` | Enterprise / Industry offline licenses only | base64'd into `UNITY_LICENSE_FILE_BASE64`; `unity license activate --file` (`.ulf` or `.xml`). Not for Personal or Pro — see below. |
| `serial` | Pro / Plus | `UNITY_LICENSE_SERIAL`; activated per job, **returned** after (`if: always()`). |
| floating | License server | Replace the activate step with `unity license activate --floating`. |

**Personal licenses can't run on GitHub-hosted runners.** Current Unity licensing (Hub and the CLI's
bundled licensing client) issues `UnityEntitlementLicense.xml`, bound to the activating machine
(`Legacy.MachineBinding1/2` identifiers) and refreshed every ~30 days — not the portable `.ulf`
older guides describe, which is why teammates can't find one. A hosted runner is a new machine every
job, so that file won't activate there. And a portable file can't be obtained any more: uploading a
`.alf` (`unity license activate --generate-request`) to license.unity3d.com/manual returns *"You are
not eligible to activate your license offline. Offline activation is available only for Enterprise
and Industry seats."* (verified 2026-09-28). For Personal, choose:

- **Unity Build Automation** — Unity's machines hold the license; GitHub Actions only starts builds.
  Free tier, nothing to maintain. The `unity-build-automation` skill /
  `/claude-unity-devkit:setup-cloud-build`. Recommended when the team wants no build machine.
- **`machine` mode on a self-hosted runner** — a teammate's PC or a build box, signed in once.
  Fastest (warm `Library/`), but CI runs only while that machine is on.

Hosted runners running the Editor need Pro/Plus (`serial`) or a floating license server.

`unity license activate --personal` **does not work in CI** either: Unity's licensing backend rejects
service-account tokens for activation. Service-account secrets (`UNITY_SERVICE_ACCOUNT_ID` /
`_SECRET`) authenticate Unity *services* only; the Editor still needs a license.

## Step 6 — Review

Dispatch `ci-reviewer` on the workflow. Its GameCI-specific checks don't apply; ask it to judge
triggers, fork safety, secret handling, runner labels, timeouts, and artifact retention. Run
`actionlint` if available (custom runner labels are expected warnings).
`runner.environment` (`github-hosted` / `self-hosted`) and the runner-set `RUNNER_ENVIRONMENT` env var
are standard GitHub Actions features; reviewers have flagged them as undefined — they aren't.

## Step 7 — CLAUDE.md and hand-over

Write or append **Branching**, **Unity CLI**, and **CI** sections (template in
`references/cli-reference.md` → "Team commands"). Then print, for the human to do:

- Secrets: `gh secret set UNITY_SERVICE_ACCOUNT_ID` / `UNITY_SERVICE_ACCOUNT_SECRET` (+ license
  secret for `file`/`serial`). Never run `gh secret set` yourself or write secrets to files.
- Runner setup (`references/runner-setup.md`) when self-hosted.
- `git push -u origin stable` and branch protection.
- Per-teammate onboarding: install CLI, `unity install`, `git lfs install`, `unity vcs merge-setup`,
  `unity vcs hooks install`.
- First run: open a PR into `stable` to see Test; merge it to see the playtest build.

## Grounding notes

- Everything above was checked against `unity --help` output of CLI 1.0.0-beta.11 (2026-09-27).
  Flags change between betas — re-verify with `--help`, never from memory.
- `unity build` / `unity test` refuse to run while the project is open in an Editor, and pass
  `-batchmode -quit -projectPath` themselves — don't add them.
- `unity build` has an uncommitted-changes guard (`--allow-dirty-build` skips it). CI starts clean.
- Exit codes: 0 ok, 3 auth, 4 config required, 6 operation failed / run didn't finish, 7 service or
  Editor unreachable (retryable), 8 tests failed (don't retry).
- The template's `install-modules` path on an Editor that already has the module is unverified
  until a hosted run — watch it and fix the skill if it misbehaves.
