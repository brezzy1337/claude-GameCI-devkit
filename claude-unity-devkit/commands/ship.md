---
description: Open a PR for a Unity branch, run a multi-lens review, wait for GameCI checks, and notify Slack — with approval gates before opening and merging
argument-hint: [short summary of the change]
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git branch *), Bash(git merge-base *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr checks *), Bash(gh run list *), Bash(gh run view *), Bash(dotnet format *), Bash(*/scripts/format-csharp.sh*), Bash(*/scripts/check-meta-files.sh*), Read, Grep, Glob
---

# Ship

Context (gathered for you):
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Diff stat vs base: !`git diff --stat $(git merge-base HEAD origin/HEAD)..HEAD`

Run the ship pipeline for the current branch. Treat $ARGUMENTS as an optional one-line summary of
the change. The chain is sequential and you (the central thread) own it — the specialists have no
`Agent` tool, so every stage runs from here.

1. **Preflight.** Run the project's verify commands (from CLAUDE.md):
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/format-csharp.sh" --check` — C# formatting;
   - `"${CLAUDE_PLUGIN_ROOT}/scripts/check-meta-files.sh" --tracked --strict` — every committed asset
     has its `.meta`, no orphans;
   - the Unity test command if CLAUDE.md configures a local Editor; otherwise note that the GameCI Test
     workflow on the PR is the test gate (step 4).
   If the diff touches `Packages/manifest.json`, `Packages/packages-lock.json`, DLLs under
   `Assets/Plugins/`, imported Asset Store content, or `uses:` lines in `.github/workflows/`, delegate
   to the `dependency-auditor` sub-agent and stop on a NO-GO. Do not continue on a red preflight —
   report what failed and stop.

2. **Draft the PR.** Delegate to the `pr-author` sub-agent to produce a title and body from the diff.
   **GATE 1 — do not open the PR.** Show me the draft and the target base branch and wait for my
   explicit "yes". Pushing and `gh pr create` are not pre-authorized, so they will prompt for
   permission — that prompt is the gate. Only proceed once I approve.

3. **Review (fan-out, then consolidate).** Scale the panel to the diff: for a trivial change run one
   or two lenses or skip; for a substantive change dispatch these read-only lenses in parallel —
   `factual-reviewer`, `architecture-reviewer`, `security-reviewer`, `consistency-reviewer`,
   `redundancy-checker`. Add the Unity lenses by what the diff touches:
   - **Runtime gameplay code** (the gameplay domain globs in CLAUDE.md) → `gameplay-reviewer` and
     `performance-reviewer`.
   - **Physics, quality, or graphics settings** in `ProjectSettings/` → `performance-reviewer`.
   - **`.github/workflows/**` or `deploy/**`** → `ci-reviewer`.
   Then consolidate yourself: merge findings, resolve conflicts between lenses, de-duplicate, rank by
   impact, and post ONE prioritized review to the PR with a single overall verdict. Summarize
   blocking issues for me.

4. **CI checks.** Run `gh pr checks` for the PR. The GameCI Test workflow (EditMode + PlayMode) is the
   authoritative test run for a Unity project; if checks are still running, report their status and
   check again before the merge gate. A failing check is a blocking issue — use `gh run view` to pull
   the failing job's summary and include it in your report.

5. **GATE 2 — do not merge.** Show me the consolidated review, the CI check status, and your merge
   recommendation, and wait for my explicit "yes". `gh pr merge` is not pre-authorized and will
   prompt — only proceed once I approve.

6. **Notify.** After each transition (PR opened, review posted, merged), delegate to the
   `slack-notifier` sub-agent to post to the team thread. Keep every update in the same thread.

Never work around a gate, a red preflight, a failing CI check, or a blocking review to ship faster.
If something blocks, stop and tell me with the reason.
