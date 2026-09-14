<!--
  Template: the "Feature implementation (/code-todo)" section for a Unity project's CLAUDE.md.
  Append it BELOW the "Sub-Agent Orchestration" section — it relies on that section's Domain
  boundaries and invocation protocol. Replace every `TAILOR:` marker, then delete the markers.
  Match the file's existing tone. If the claude-unity-devkit plugin provides the commands, write
  them as /claude-unity-devkit:code-todo and /claude-unity-devkit:ship.
-->

## Feature implementation (/code-todo)

`/code-todo` is the implement-and-review front end to shipping. It reuses this file's **Domain
boundaries** (to route a change to the right assembly's agent) and **invocation protocol** (to brief
each agent), and it ends by handing an approved branch to `/ship`. It does **not** open PRs, push, or
merge — that's `/ship`'s job.

The central thread owns the chain (specialists have no `Agent` tool):

1. **Read** the change request.
2. **Route** to domain(s) per Domain boundaries — one `implementer` per non-overlapping assembly in
   parallel; dependent assemblies in sequence, each step's output handed to the next. Changes to
   `ProjectSettings/`, `Packages/manifest.json`, or shared scenes/prefabs are single-owner.
3. **Implement** via `implementer` sub-agent(s) with the full four-part brief. Route any new or
   bumped package through `dependency-auditor` first; stop on a NO-GO.
4. **Iterate** on runtime gameplay slices with `gameplay-reviewer` + `performance-reviewer` in
   parallel; re-brief on Critical/Warning findings, at most two cycles.
5. **Gate.** Run the format and `.meta` checks, commit to a feature branch, then post the diff
   summary (code vs asset changes, plus Editor follow-ups) to Slack via `slack-notifier` and wait for
   human approval **in the terminal**. Slack gives visibility into the diff; approval comes back in
   the session — the run does not poll Slack.
6. **Hand off.** On approval, invoke `/ship` on the branch.

**Boundaries that keep the two halves clean:**
- The gate is not optional. Do not open a PR, push, or hand off before approval.
- Implementers edit only their domain's globs. A slice that needs to cross a boundary is a routing
  decision for the central thread, not a widening the implementer does on its own.
- Only the central thread commits; implementers edit and verify.
- Scene and prefab wiring is Editor work — listed as follow-ups, never hand-edited YAML.
- For a single-domain change, dispatch one implementer — don't over-spawn.

**State** lives on the branch (the work + commit message) and the Slack thread, not in the
session, so an interrupted run resumes from the branch.

<!-- TAILOR: name the repo's feature-branch convention (e.g. `feat/<slug>`), the exact verify commands (format, meta check, Unity test command or "GameCI Test workflow"), and the gameplay domain globs that trigger step 4. -->
