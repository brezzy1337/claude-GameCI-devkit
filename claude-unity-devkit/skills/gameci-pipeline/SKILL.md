---
name: gameci-pipeline
description: >-
  Author GitHub Actions CI for a Unity project with GameCI — game-ci/unity-test-runner for EditMode
  and PlayMode tests, game-ci/unity-builder for a build-target matrix (WebGL, StandaloneLinux64
  including the dedicated-server subtarget, StandaloneWindows64, Android), license activation through
  UNITY_LICENSE or UNITY_SERIAL plus UNITY_EMAIL and UNITY_PASSWORD secrets, Library caching keyed on
  Packages/manifest.json and ProjectSettings, and GitHub-hosted or self-hosted runner labels. Use this
  skill whenever the user wants to set up, fix, speed up, or review CI for a Unity game, add build
  targets, activate a Unity license in GitHub Actions, or debug a failing GameCI job (activation
  errors, out of memory, no space left on device).
---

# GameCI pipeline

## The idea

CI for Unity means running the Editor headless, in Docker, with a license. GameCI packages that
into two actions: `game-ci/unity-test-runner` and `game-ci/unity-builder`. The devkit splits the work
into two workflows with different jobs:

- **Test** (`assets/test.yml`) runs EditMode + PlayMode on every pull request. It is the test gate
  `/claude-unity-devkit:ship` waits on, because most developers can't run the Editor in the loop.
- **Build** (`assets/build.yml`) builds the target matrix on the default branch and on `v*` tags and
  uploads each target as an artifact. Deploy workflows (the `unity-deploy` skill) build the same way.

The templates encode the decisions below; this skill explains them so you can tailor a workflow to a
repo or review one. `/claude-unity-devkit:setup-ci` drives this skill; `ci-reviewer` enforces it.

## What you produce

1. `.github/workflows/test.yml` from `assets/test.yml`.
2. `.github/workflows/build.yml` from `assets/build.yml`.
3. A short **CI** subsection in CLAUDE.md: targets, runner type and labels, license type,
   `projectPath`, and the secret names — so reviews judge against the team's actual choices.
4. The secrets and license-activation checklist, printed for the human. Never set secrets yourself
   and never write them into files.

## Action versions

Verified 2026-09-13 against each action's releases and `action.yml`. Check again before bumping —
never write an input you haven't seen in the pinned tag's `action.yml`.

| Action | Pin | Notes |
| --- | --- | --- |
| `game-ci/unity-test-runner` | `@v4` | `v4` → v4.4.0 (2026-09-09), now a thin wrapper around `game-ci/cli`. v4.3.2 is the last release on the old architecture — pin it exactly if the wrapper misbehaves. v5 is in beta. |
| `game-ci/unity-builder` | `@v5` | v5.0.1 (2026-09-01). v6.0.0 (2026-09-10) is a drop-in thin-wrapper upgrade ("inputs, secrets, and project layout are unchanged from `@v5`"); move to `@v6` once it clears the 7-day cooldown. |
| `game-ci/unity-activate` | not used | Last release v2.0.0 (2022, `node12` runtime). The builder and test runner activate from the env secrets and return the license themselves, so these workflows don't need it. |
| `actions/checkout` | `@v7` | `lfs: true`; `fetch-depth: 0` for Semantic versioning |
| `actions/cache` | `@v6` | Library cache (v1–v3 are retired) |
| `actions/upload-artifact` | `@v7` | test results, coverage, build archives |
| `actions/download-artifact` | `@v8` | deploy jobs |

Both GameCI actions install `game-ci/cli` at `cliVersion: latest` on every run. Pin `cliVersion`
(latest was v0.1.63 on 2026-09-11) when reproducibility matters more than fixes. For the strictest
supply-chain posture, pin every action to a full commit SHA and let Dependabot bump them
(`package-ecosystem: github-actions` with a `cooldown`).

## Step 1 — Inspect first

- **`projectPath`** — the folder holding `Assets/` relative to the repo root (`.` or a subfolder).
- **Editor version** — `ProjectSettings/ProjectVersion.txt`. Then confirm GameCI publishes images for
  it: `https://hub.docker.com/v2/repositories/unityci/editor/tags?page_size=100&name=ubuntu-<version>-`
  must list a `-3` tag for each module the targets need (`base`, `webgl`, `linux-il2cpp`,
  `windows-mono`, `android`). Images appear a few days after a Unity release.
- **Git LFS** — does `.gitattributes` use `filter=lfs`? Then checkout needs `lfs: true`.
- **Targets, runners, license type, default branch** — ask; don't guess.
- **Existing workflows** — read them; extend or replace deliberately, never duplicate a job.

## Step 2 — License activation

Secrets go on the GameCI **steps** as `env:` — not at workflow or job level, never echoed, never
interpolated into `run:` scripts.

- **Personal** (the devkit default): `UNITY_LICENSE` = the full contents of the `.ulf` file, plus
  `UNITY_EMAIL` and `UNITY_PASSWORD`. To get the file: Unity Hub → Preferences → Licenses → Add →
  *Get a free personal license*. It lands at `C:\ProgramData\Unity\Unity_lic.ulf` (Windows),
  `/Library/Application Support/Unity/Unity_lic.ulf` (macOS), or
  `~/.local/share/unity3d/Unity/Unity_lic.ulf` (Linux). A license shown in Hub doesn't guarantee the
  file exists — check. Upload with `gh secret set UNITY_LICENSE < Unity_lic.ulf`.
- **Pro / Plus**: `UNITY_SERIAL` (from the Unity ID subscriptions page) instead of `UNITY_LICENSE`,
  plus email and password. GameCI returns the seat after each job; every concurrently running matrix
  job activates its own machine, so cap `max-parallel` if activations run out.
- **License server** (floating licenses): the `unityLicensingServer` input on both actions.
- **Fork PRs and Dependabot PRs** don't receive Actions secrets; the test job's `if:` skips fork PRs
  instead of failing them. Dependabot PRs need the license added under Dependabot secrets, or they fail.

Activation failures and their fixes are in `references/troubleshooting.md`.

## Step 3 — Library caching

Unity's `Library/` is the import cache. Without it every job re-imports every asset — often the
longest part of the run. The templates cache it with `actions/cache`:

- **Key** = target (build) or test mode (test) + `hashFiles('Packages/manifest.json',
  'Packages/packages-lock.json', 'ProjectSettings/**')`. Package and settings changes invalidate most of
  `Library/`; ordinary asset edits only need an incremental re-import, which a restored cache handles.
- **One cache per target and per test mode.** Switching build target re-imports assets for the new
  platform, so two targets sharing an entry thrash it.
- **`restore-keys`** fall back to the newest entry of the same target/mode, so a package bump still
  starts from a warm Library.
- **Trade-off.** Because the key ignores `Assets/`, an entry is written once per key and slowly goes
  stale; import time creeps up over weeks. When that bites, add `hashFiles('Assets/**/*.meta')` to the
  key (it changes when assets are added, removed, or re-configured) or change a key prefix to reset.
- **Limits.** GitHub evicts least-recently-used entries past the repository's cache limit (10 GB by
  default); a wide matrix of large Libraries can churn through it.
- **Prefix the globs** with the project folder when `projectPath` isn't the repo root — `hashFiles`
  paths are relative to the workspace, not to `projectPath`.

## Step 4 — The test workflow

- Matrix over `testMode: [editmode, playmode]`, `fail-fast: false`, so both results always report.
- `githubToken` + `permissions: checks: write` makes the test runner publish a check run per mode
  (`checkName`). `/ship` reads these with `gh pr checks`.
- Results and coverage upload with `if: always()` so failures keep their evidence.
- Code coverage is on by default (`coverageEnabled: true`). The action documents that some Unity
  versions crash with it on; if a run crashes during coverage, set `coverageEnabled: false`. Rich
  reports need the Code Coverage package (`com.unity.testtools.codecoverage`) — add it through
  `dependency-auditor`.
- Test conventions (EditMode vs PlayMode, test asmdefs) are in the `unity-testing` skill.

## Step 5 — The build workflow

- **Matrix with `include:` entries** — each has `targetPlatform`, a unique `artifactName`,
  `buildName`, and `customParameters`. `targetPlatform` must be a Unity `BuildTarget` name:
  `WebGL`, `StandaloneLinux64`, `StandaloneWindows64`, `StandaloneOSX`, `Android`, `iOS`, …
- **Dedicated server** — `targetPlatform: StandaloneLinux64` with
  `customParameters: -standaloneBuildSubtarget Server`. With the default `providerStrategy: local`, the
  builder uses the `linux-il2cpp` editor image for StandaloneLinux64, and GameCI installs the
  `linux-server` module into its Linux images, so no custom image is needed. The binary is
  `<buildName>.x86_64` (v5+ keep the extension unless `linux64RemoveExecutableExtension: true`). Unity
  6 Build Profiles are an alternative via the `buildProfile` input.
- **Output** lands in `build/<targetPlatform>/`. The template tars it before upload because
  `upload-artifact` drops the executable bit.
- **Versioning** — `versioning: Semantic` derives the version from git tags, so checkout uses
  `fetch-depth: 0`.
- **Android** — the signing inputs (`androidKeystoreBase64`, passes, alias) come from secrets;
  `androidExportType: androidAppBundle` for Play Store uploads. Free disk space first on hosted runners.
- **Platform limits** — Linux runners build WebGL, Linux, Android, Windows (Mono), and an Xcode
  project for iOS. Windows IL2CPP needs a Windows runner; macOS and signed iOS builds need macOS.
- Every job sets `timeout-minutes`; a hung Editor otherwise burns six hours.

## Step 6 — Runners

- **GitHub-hosted** (the devkit default): `runs-on: ubuntu-latest`. Standard Linux runners have
  4 vCPU / 16 GB RAM for public repositories and 2 vCPU / 8 GB for private ones, both with a 14 GB SSD.
  Editor images are 5–9 GB compressed (see the troubleshooting table), which is why the build
  template frees disk space for Android and WebGL, and why IL2CPP/WebGL builds on private-repo runners
  are memory-tight.
- **Self-hosted** — `runs-on: [self-hosted, linux, x64, unity]`-style label arrays, Docker on the
  host, and a few input changes. See `references/self-hosted-runners.md`.

## Step 7 — Review

Dispatch the `ci-reviewer` sub-agent on every workflow you write or change. Fix Critical and
Warning findings before handing the workflow over.

## Step 8 — Hand over

Print the secrets that still need adding (`gh secret list` shows the existing ones), the activation
steps for the chosen license, and what happens next: open a PR to see Test run; merge to see Build.

## Grounding notes

- GameCI is a community project, not affiliated with Unity. Its images trail Unity releases by days.
- Floating major tags move — `unity-test-runner@v4` changed architecture inside the major (v4.4.0).
  Pin exact tags or SHAs when stability matters more than fixes.
- Don't invent inputs. Read the pinned tag's `action.yml`
  (`gh api repos/game-ci/<action>/contents/action.yml?ref=<tag>`) before adding one.
- CI doesn't replace local judgment: a green PlayMode run proves the tests pass, not that the game
  plays well. The review lenses and the human gates still matter.
