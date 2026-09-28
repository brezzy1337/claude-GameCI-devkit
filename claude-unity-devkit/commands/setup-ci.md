---
description: Add GameCI GitHub Actions to a Unity repo (EditMode + PlayMode tests and a build-target matrix) from the devkit templates, then print the exact secrets and license-activation steps
argument-hint: "[optional build targets, e.g. StandaloneLinux64 WebGL]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(ls *), Bash(find *), Bash(mkdir *), Bash(git rev-parse *), Bash(git branch *), Bash(gh secret list *), WebFetch
disable-model-invocation: true
---

# Setup CI

Add GameCI test and build workflows to this Unity repo using the `gameci-pipeline` skill — read its
SKILL.md first; it is the rulebook for everything below. Treat $ARGUMENTS as an optional list of
build targets.

Context (gathered for you):
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Unity project(s): !`find . -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print`
- Existing workflows: !`find . -maxdepth 3 -path './.github/workflows/*' -name '*.y*ml'`

1. **Locate the project.** Pick the Unity project folder (ask if there are several) — its path
   relative to the repo root is `projectPath` (`.` when it is the root). Read
   `ProjectSettings/ProjectVersion.txt` for the editor version.

2. **Check GameCI images exist for that version.** WebFetch
   `https://hub.docker.com/v2/repositories/unityci/editor/tags?page_size=100&name=ubuntu-<version>-`
   and confirm a `-3` tag exists for each module the targets need (`base`, `webgl`, `linux-il2cpp`
   for StandaloneLinux64 and the dedicated server, `windows-mono`, `android`). GameCI publishes
   images a few days after a Unity release; if one is missing, stop and tell me.

3. **Ask before guessing** (one AskUserQuestion round, defaults first):
   - **Build targets** (multi-select): Linux dedicated server (`StandaloneLinux64` +
     `-standaloneBuildSubtarget Server`), `WebGL`, Linux client (`StandaloneLinux64`),
     `StandaloneWindows64`, `Android`. Pre-select anything named in $ARGUMENTS.
   - **Runners**: GitHub-hosted `ubuntu-latest` (default) or self-hosted — if self-hosted, ask for the
     exact labels (e.g. `[self-hosted, linux, x64, unity]`).
   - **License**: Pro/Plus (`UNITY_SERIAL` + `UNITY_EMAIL` + `UNITY_PASSWORD`), license server, or
     Personal. For Personal, first ask whether they already have a portable `Unity_lic.ulf`; new
     Personal activations don't produce one and offline activation is Enterprise/Industry only. No
     `.ulf` → stop and offer the alternatives in the skill's "Personal licenses without a `.ulf`"
     table (Unity Build Automation via `/claude-unity-devkit:setup-cloud-build`, or the Unity CLI on a
     self-hosted runner via `/claude-unity-devkit:unity-init`)
     instead of writing GameCI workflows that can't activate.
   - **Default branch** (for push triggers) and whether every PR should also be built (default: PRs
     run tests only).

4. **Write the workflows** from `${CLAUDE_PLUGIN_ROOT}/templates/ci/test.yml` and `build.yml` into
   `.github/workflows/`. Resolve every `TAILOR` marker: `UNITY_PROJECT_PATH` and the `hashFiles`
   prefixes (projectPath), `runs-on` (runners), branch triggers, the build matrix (keep only the
   chosen targets), and the license env lines (Pro: swap `UNITY_LICENSE` for `UNITY_SERIAL`). For
   self-hosted runners apply `references/self-hosted-runners.md` from the skill. Keep the pinned
   action versions from the templates — don't "upgrade" them from memory. If a workflow file already
   exists, show me the diff and ask before overwriting.

5. **Review.** Dispatch the `ci-reviewer` sub-agent on the new workflow files and fix every Critical
   and Warning finding before you continue.

6. **Record the decisions** (targets, runner type/labels, license type, projectPath) in a short
   "CI" subsection of CLAUDE.md so later reviews and `ci-reviewer` judge against them.

7. **Print the secrets and activation steps.** Show which secrets already exist
   (`gh secret list`), then print exactly what I still need to do — I run these myself:
   - **Personal license (existing portable `.ulf` only):**
     `gh secret set UNITY_LICENSE < <path-to>/Unity_lic.ulf`. Never suggest manual activation,
     `unity-license-activate`, or page-editing workarounds.
   - **Pro/Plus:** `gh secret set UNITY_SERIAL` (serial from the Unity ID subscriptions page). GameCI
     returns the seat after every job.
   - Both: `gh secret set UNITY_EMAIL` and `gh secret set UNITY_PASSWORD`. Accounts created with
     Google/Apple sign-in need a Unity password set first (Unity ID → Security).
   - Point at the skill's `references/troubleshooting.md` for activation failures.

8. **Next steps.** Push a branch and open a PR to see the Test workflow run; builds run on the default
   branch and on `v*` tags. For deploys, run `/claude-unity-devkit:setup-deploy`.

Never write secrets into files, and never run `gh secret set` for me. Stop and ask rather than
guessing targets, runner labels, or the license type.
