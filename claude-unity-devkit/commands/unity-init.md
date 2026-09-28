---
description: Set a Unity repo up around the Unity CLI — install the CLI, Editor, and modules; Unity-aware git (merge setup, hooks, LFS locking); the stable/main branch model; and a unity test / unity build GitHub Actions workflow — then print the secrets, runner, and teammate steps
argument-hint: "[optional build targets, e.g. StandaloneWindows64 WebGL]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(unity *), Bash(curl -fsSL https://unity.com/install.sh*), Bash(git status *), Bash(git diff *), Bash(git branch *), Bash(git switch *), Bash(git rev-parse *), Bash(git lfs install *), Bash(git ls-files *), Bash(gh repo view *), Bash(gh secret list *), Bash(ls *), Bash(find *), Bash(mkdir *), Bash(sed -n *)
disable-model-invocation: true
---

# Unity init

Set this Unity repo up around the Unity CLI using the `unity-init` skill — read its SKILL.md and
`references/cli-reference.md` first; they are the rulebook. Treat $ARGUMENTS as optional build targets.

Context (gathered for you):
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Branches: !`git branch -a --format='%(refname:short)'`
- Unity project(s): !`find . -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print`
- Existing workflows: !`find . -maxdepth 3 -path './.github/workflows/*' -name '*.y*ml'`
- Unity CLI: !`unity version 2>/dev/null | head -2 || echo "not installed"`

1. **Locate the project** and read `ProjectSettings/ProjectVersion.txt`. Check repo visibility with
   `gh repo view --json visibility,defaultBranchRef`. **Detect the environment** (`$CODESPACES`,
   `$REMOTE_CONTAINERS`, `/.dockerenv`): in a cloud/container dev environment the Editor is never
   installed — say so, and skip every Editor-dependent step below (list them in the hand-over).

2. **Ask before guessing** (one AskUserQuestion round, defaults first; skip what CLAUDE.md or
   $ARGUMENTS already answers):
   - **Build targets** (multi-select): `StandaloneWindows64` (default), `WebGL`, Linux dedicated
     server, `Android`.
   - **Runners**: self-hosted (ask for labels, e.g. `[self-hosted, linux, x64, unity]`) or
     GitHub-hosted `ubuntu-latest`. Refuse self-hosted on a public repo and say why.
   - **License**: Personal or Pro/Plus or floating. Derive the mode from the skill's table
     (Personal → `machine` on a self-hosted runner; Pro/Plus → `serial`; license server → floating).
     Personal can't run the Editor on hosted runners (see the skill). If they want Personal *and* no
     machine to maintain, recommend Unity Build Automation instead of this workflow: stop the CI part
     here and point them at `/claude-unity-devkit:setup-cloud-build` (the rest of unity-init — machine,
     git, branch model — still applies).
   - **Branch names**: production (`main`) and integration (`stable`).

3. **Machine.** If `unity` is missing or not the skill's pinned version, install it (show the
   command first). Only on a person's own machine: install the Editor and modules — show
   `unity install … --dry-run --json` sizes and ask before a multi-GB download. Run `unity doctor`. If `com.unity.pipeline` is absent, ask
   whether the team wants it before adding it.

4. **Version control.** `unity vcs doctor`, then `--fix` after I agree; `unity vcs merge-setup`;
   `unity vcs hooks install`; `git lfs install --local`. Add `lockable` to `*.unity` (and binary art
   patterns I choose) in `.gitattributes`. Show `git diff` of every file changed and ask before
   keeping changes you didn't expect. Never commit.

5. **Branch model.** Create the integration branch locally from the production branch
   (`git branch stable main`). Don't push, change the default branch, or set protection — print
   those commands from `unity-project-conventions/references/branching.md`.

6. **Workflow.** Write `.github/workflows/unity.yml` from `${CLAUDE_PLUGIN_ROOT}/templates/ci/unity-cli.yml`,
   resolving every `TAILOR` marker. Keep the pinned action and CLI versions. If the file exists,
   show the diff and ask before overwriting. Run `actionlint` if available.

7. **Review.** Dispatch `ci-reviewer` on the workflow (tell it this is a Unity CLI workflow, not
   GameCI) and fix Critical and Warning findings.

8. **CLAUDE.md.** Write or append **Branching**, **Unity CLI** (team commands table), and **CI**
   (targets, runner labels, license mode, projectPath, secret names) sections.

9. **Hand over.** Print what I still need to do — I run these myself:
   - Secrets (`gh secret list` shows what exists): `UNITY_SERVICE_ACCOUNT_ID`,
     `UNITY_SERVICE_ACCOUNT_SECRET`, plus `UNITY_LICENSE_FILE_BASE64` or `UNITY_LICENSE_SERIAL` per mode.
   - Self-hosted: the steps in the skill's `references/runner-setup.md` (the teammates'-machines
     section when runners are personal PCs), with this repo's labels.
   - Editor-dependent steps skipped in a cloud/container environment, to run on each Editor
     machine: `unity vcs merge-setup`, `unity test`.
   - `git push -u origin stable`, optional default-branch change, branch protection.
   - Teammate onboarding (the CLAUDE.md "Unity CLI" table).
   - First run: a PR into `stable` shows Test; merging it produces the playtest build artifact.

Never write secrets into files, never run `gh secret set`, never push. Stop and ask rather than
guessing targets, runner labels, or the license type.
