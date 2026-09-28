---
description: Add Unity Build Automation CI (the free path for Unity Personal) — a GitHub Actions workflow that starts UBA builds with tests, waits, and reports — then print the Dashboard checklist, org-ID check, variables, and label
argument-hint: "[optional integration branch, e.g. stable]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(unity cloud *), Bash(unity pipeline cloud-build *), Bash(git rev-parse *), Bash(git branch *), Bash(gh repo view *), Bash(gh variable list *), Bash(gh label list *), Bash(ls *), Bash(find *), Bash(mkdir *), Bash(chmod *), Bash(sed -n *), Bash(actionlint *), Bash(shellcheck *), Bash(bash */scripts/test-uba-build.sh*)
disable-model-invocation: true
---

# Setup cloud build

Add Unity Build Automation CI to this repo using the `unity-build-automation` skill — read its
SKILL.md and `references/` first. Treat $ARGUMENTS as the integration branch if given.

Context (gathered for you):
- Repo root: !`git rev-parse --show-toplevel`
- Branches: !`git branch -a --format='%(refname:short)'`
- Unity project(s): !`find . -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print`
- Existing workflows: !`find . -maxdepth 3 -path './.github/workflows/*' -name '*.y*ml'`
- Unity CLI sign-in: !`unity cloud status 2>/dev/null | head -3 || echo "unity CLI not installed or not signed in"`

1. **Confirm fit.** Read the Editor version from `ProjectSettings/ProjectVersion.txt` and CLAUDE.md
   (branch model, license). If the team has Pro/Plus and wants builds in GitHub, say that GameCI or
   the Unity CLI on hosted runners (`/claude-unity-devkit:setup-ci`, `unity-init`) is an option too,
   and ask which they want.

2. **Ask before guessing** (one AskUserQuestion round, defaults first): integration branch
   (`stable`), production branch that tags come from (`main`), UBA target name
   (`windows-playtest`), and whether labeled PRs should build (default yes, label `cloud-ci`).

3. **Look up IDs** if the Unity CLI is signed in: `unity cloud org list` (note both `id` and
   `genesisId`), `UNITY_CLOUD_ORG=<id> unity cloud project list`, and — if a target already exists —
   `unity pipeline cloud-build targets list`. Otherwise leave them for the human.

4. **Write the files** from `${CLAUDE_PLUGIN_ROOT}/templates/ci/cloud-build.yml` →
   `.github/workflows/cloud-build.yml` and `${CLAUDE_PLUGIN_ROOT}/templates/ci/uba-build.sh` →
   `.github/scripts/uba-build.sh` (`chmod +x`). Resolve every `TAILOR`. If a file exists, show the
   diff and ask before overwriting. If an older Editor-running workflow (GameCI or Unity CLI on hosted
   runners) exists that can't activate a Personal license, offer to remove it.

5. **Verify.** `actionlint` on the workflow, `shellcheck` on the script, and
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/test-uba-build.sh .github/scripts/uba-build.sh`.

6. **CLAUDE.md.** Write or replace the **CI** section: triggers, target, budget (200 Windows
   minutes/month, project locks when exceeded), secrets, variables with the IDs found, the
   `cloud-ci` label, and that PRs otherwise rely on local `unity test --affected`.

7. **Hand over.** Print the skill's `references/dashboard-setup.md` steps, filled in with this
   repo's names and IDs — including the org-ID curl check, `gh variable set` for `UBA_ORG_ID`,
   `UBA_PROJECT_ID`, `UBA_TARGET`, and `gh label create cloud-ci`. Then: open a PR into the
   integration branch and add the label for the first real run.

Never set secrets or variables, create labels, or push — print the commands for me.
