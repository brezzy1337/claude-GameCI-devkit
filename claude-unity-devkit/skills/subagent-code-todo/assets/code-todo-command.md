---
description: Implement a Unity feature/change via domain-routed sub-agents, review the diff on Slack, then hand the approved branch to /ship
argument-hint: [feature or change to implement]
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git branch *), Bash(git switch *), Bash(git checkout *), Bash(git add *), Bash(git commit *), Bash(git merge-base *), Bash(dotnet format *), Bash(gh pr view *), Bash(gh run list *), Bash(gh run view *), Read, Grep, Glob
---

# Code-todo

Context (gathered for you):
- Branch: !`git branch --show-current`
- Status: !`git status --short`

Implement the change described in $ARGUMENTS. You (the central thread) own the chain — the
specialists have no `Agent` tool, so they never delegate further — so you route the work, brief each
agent fully, manage all git state, and do the handoff yourself.

1. **Read the request.** Treat $ARGUMENTS (and any linked issue or `@file`) as the change to make.
   If the scope is unclear, ask me before routing — an implementer starts with a fresh context and
   can't ask follow-ups.

2. **Determine the domain(s).** Match the change against the **Domain boundaries** in CLAUDE.md
   (the subagent-orchestration baseline — the `.asmdef` folders). One domain → one implementer.
   Multiple domains with non-overlapping globs → implementers in parallel. Dependent domains (a
   referenced assembly before the assemblies that use it) → a sequential chain you drive, handing each
   step's output to the next. Changes to `ProjectSettings/`, `Packages/manifest.json`, or shared
   scenes/prefabs are single-owner and sequential. When unsure, go sequential. If CLAUDE.md has no
   Domain boundaries, ask me which paths the change touches — do not guess globs.

3. **Prepare the branch.** Create or switch to a feature branch for this change (match the repo's
   branch convention). Implementers edit on it; only you commit.

4. **Dispatch implementer(s).** For each slice, invoke the `implementer` sub-agent with the
   baseline's four-part brief — context, instructions, exact file references, and success criteria
   — and name the domain's globs plus the verify commands from CLAUDE.md. If a slice needs a new or
   bumped package, route it through the `dependency-auditor` sub-agent first and stop on a NO-GO.
   Stop on red: if implementation or checks fail and can't be fixed, halt and report.

5. **Gameplay iteration (runtime gameplay slices only).** If the slice touched the gameplay domain
   globs in CLAUDE.md, dispatch `gameplay-reviewer` and `performance-reviewer` in parallel on the
   diff. Re-brief the implementer on every Critical and Warning finding and re-run the lenses until
   both verdicts are clean (cap at two fix cycles — if still red, surface the remaining findings at the
   gate instead of looping forever).

6. **Verify, commit, then review on Slack — GATE.** Run the format and `.meta` checks from CLAUDE.md;
   every new asset must have its `.meta`. Commit the work to the branch. Run `git diff` against the
   base, summarize what changed (code vs asset changes, plus every implementer's Editor follow-ups),
   and delegate to `slack-notifier` to post the summary + branch name to the team thread. Then STOP and
   wait for my explicit "yes" here in the terminal. Slack is where I read the diff; I approve back in
   this session — do not poll Slack for a reply. If I request changes, re-brief the implementer,
   update the branch, and re-post.

7. **Hand off to /ship.** Only after I approve: run `/ship` on this branch. `/ship` owns PR
   creation, the multi-lens review panel, CI checks, the merge gate, and PR notifications — do NOT open
   a PR, push, or merge here (those tools are intentionally not available to this command). If `/ship`
   isn't installed, stop and tell me the branch is ready to open a PR by hand.

Never work around the review gate, a red step, or a dependency NO-GO to move faster. If something
blocks, stop and tell me with the reason.
