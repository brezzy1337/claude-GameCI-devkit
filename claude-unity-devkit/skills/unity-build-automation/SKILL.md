---
name: unity-build-automation
description: >-
  Set up cloud CI for a Unity project on a Unity Personal (free) license with Unity Build Automation
  (UBA, part of Unity DevOps). Unity's build machines hold the Editor license and run EditMode/PlayMode
  tests and the build, while a lightweight GitHub Actions workflow starts each build through the UBA v2
  REST API with a service account, waits, and reports tests and status. Covers the Unity Dashboard
  setup (DevOps free plan, GitHub token, Automation User role, build target with auto-build off and
  tests on), the free-tier budget (200 Windows minutes/month), and the API. Use this skill whenever a
  team on Unity Personal wants CI or cloud builds, hits "offline activation is available only for
  Enterprise and Industry seats", can't find a Unity_lic.ulf, wants to avoid Unity Pro or a build
  server, or asks about Unity Build Automation / Cloud Build.
---

# Unity Build Automation

## The idea

Any machine that runs the Unity Editor — even headless for a build or test — needs a license
activated on it. Unity Personal is activated by a *person* signing in on that machine; Unity closed
offline activation to everything but Enterprise and Industry seats, and new activations write a
machine-bound `UnityEntitlementLicense.xml`, not a portable `.ulf`. So hosted CI (GitHub Actions,
CircleCI, GitLab — with GameCI or the Unity CLI) can't run the Editor on a Personal license.

UBA sidesteps that: **Unity's build machines activate the license themselves.** GitHub stays the
place the team looks — a workflow on a plain `ubuntu-latest` runner (no Unity, no license secret)
starts the UBA build, polls it, and writes the result into the run summary.

Alternatives, when UBA doesn't fit: a self-hosted runner with a signed-in Personal license
(`unity-init` skill, `machine` mode), or Pro/Plus with GameCI or the Unity CLI on hosted runners.

## What you produce

1. `.github/workflows/cloud-build.yml` from `assets/cloud-build.yml` (canonical:
   `templates/ci/cloud-build.yml`), every `TAILOR` resolved.
2. `.github/scripts/uba-build.sh` from `assets/uba-build.sh` (canonical: `templates/ci/uba-build.sh`),
   executable. It starts the build, retries while the target is busy, polls, summarizes tests,
   prints the log tail on failure, and can download the primary artifact (`DOWNLOAD_DIR`).
3. A CLAUDE.md **CI** section: triggers, target, budget, secrets, variables, and the PR label.
4. Printed for the human: the Dashboard checklist, the org-ID check, variables, and the label.

## Step 1 — Decide and budget

- UBA free tier (from 2026-03-01): **200 Windows, 100 Linux, 100 Mac minutes per month**, 25 GB storage,
  2 concurrent builds. **Exceeding it blocks the DevOps project immediately** (builds cancel on
  start) until a payment method is added; cloud data is deleted after 30 days without an upgrade.
- A Windows build with tests is roughly 15–30 minutes → ~7–13 runs a month. Spend them on pushes to
  the integration branch and release tags; PRs build only when labeled (`cloud-ci`), and developers
  run `unity test --affected` locally.
- Polling also consumes GitHub Actions minutes for the build's duration (private repos on GitHub
  Free: 2,000 minutes/month).

## Step 2 — Dashboard setup (the human does it)

Hand over `references/dashboard-setup.md` — DevOps free plan, GitHub fine-grained token (Contents
read-only; deploy keys and Git LFS are unverified), service account with **Automation User**, build
target with **auto-build off**, all four test options on, max concurrent builds 1.

Check the **Unity version**: UBA's published support list tops out at 6000.3 LTS (2026-09) and new
versions usually arrive within five business days of release. If the project's version isn't
offered, wait or move the project to a supported LTS — don't let UBA silently build another version.

## Step 3 — Workflow and script

Copy both assets. Resolve `TAILOR`: the integration branch in `on.push.branches`, and the production
branch that tags come from in `BUILD_BRANCH`. Keep:

- `concurrency` per ref with `cancel-in-progress: false` — a target answers 409 while a build is
  pending, and canceling mid-build wastes the minutes already spent.
- The PR `if:` — only when the `cloud-ci` label is added or a labeled PR gets a push; never forks.
- The cancel step — canceling the Actions run cancels the UBA build (build number via
  `UBA_STATE_FILE`, because a canceled step may never publish its outputs).

Secrets `UNITY_SERVICE_ACCOUNT_ID` / `UNITY_SERVICE_ACCOUNT_SECRET`; variables `UBA_ORG_ID`,
`UBA_PROJECT_ID`, `UBA_TARGET`. Find IDs with the Unity CLI (signed in):
`unity cloud org list`, `UNITY_CLOUD_ORG=<id> unity cloud project list`, and after the target exists
`unity pipeline cloud-build targets list` (read-only — the CLI can't start builds).

**Org ID format is undocumented**: an org has a UUID `id` and a numeric `genesisId`. Have the human
try both against `GET /v2/orgs/<org>/projects/<project>/buildtargets` with the service account
(`references/dashboard-setup.md` → "Find the org ID") and use the one that returns 200.

## Step 4 — Verify

- `actionlint` on the workflow; `shellcheck` on the script.
- `scripts/test-uba-build.sh .github/scripts/uba-build.sh` (from the devkit) — four mock scenarios.
- First real run: a PR into the integration branch with the `cloud-ci` label. Confirm the branch /
  commit override builds the PR head, note the duration, and where test results appear.

## Step 5 — Hand over

Print what the human still does: the Dashboard checklist, the org-ID check, `gh variable set` for
the three variables, `gh label create cloud-ci`, and the service-account secrets if missing. Never
set secrets, push, or add labels yourself.

## Grounding notes

- API facts are in `references/uba-api.md`, taken from the v2 OpenAPI spec (2026-09-28). The v1 API
  (`build-api.cloud.unity3d.com`, API-key auth) is removed on **2026-12-21** — never write v1 calls.
- Undocumented, verify on first use: the org-ID format; whether `commit` must be on the target's
  branch and whether PR branches build; the Micro machine's `machineTypeLabel`; Git LFS over deploy
  keys; a public share-link URL (the share API returns only an ID, so summaries point at the
  Dashboard instead).
- Builds download from Unity Dashboard → Build Automation → Build History. Copying them into GitHub
  artifacts (`DOWNLOAD_DIR` + `upload-artifact`) is optional: GitHub Free gives private repos 500 MB
  of artifact storage.
- Don't point Personal-license users at `game-ci/unity-license-activate`, manual activation, or
  page-editing workarounds — they don't work and sidestep Unity's licensing.
