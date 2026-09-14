## Ship workflow

The `/ship` command runs a sequential pipeline on the current branch: preflight -> open PR ->
review -> CI checks -> merge -> notify. The central thread owns the chain (specialists have no
`Agent` tool); it runs each stage and passes output to the next.

Stages and ownership:
- **Preflight** — C# format check, `.meta` check on tracked files, and local Unity tests if an Editor
  is configured; if packages, DLLs, or workflow actions changed, delegate to `dependency-auditor`. A
  red preflight stops the pipeline.
- **Open PR** — `pr-author` drafts the title/body; **opening requires human approval** (push and
  `gh pr create` are not pre-authorized, so they prompt).
- **Review** — fan out to the read-only panel (`factual-reviewer`, `architecture-reviewer`,
  `security-reviewer`, `consistency-reviewer`, `redundancy-checker`) in parallel, scaled to the
  diff size. Diffs touching gameplay code add `gameplay-reviewer` + `performance-reviewer`; physics or
  quality settings add `performance-reviewer`; workflow or deploy files add `ci-reviewer`. The central
  thread consolidates the reports into one prioritized review and posts it to the PR.
- **CI checks** — the GameCI Test workflow (EditMode + PlayMode) is the authoritative test run; a
  failing check is a blocking finding.
- **Merge** — **merging requires human approval** (`gh pr merge` is not pre-authorized).
- **Notify** — `slack-notifier` posts each transition to one Slack thread via the Slack MCP server.

Keep the review lenses distinct — one dimension each, no overlapping roles. Each reviewer returns
findings in the same shape (severity, file, issue, fix, verdict) so consolidation is mechanical.

State lives outside this session: the PR body holds the change summary and the consolidated
review; the Slack thread holds running status (store the thread timestamp in the PR body so a
later run resumes the same thread). If the pipeline is interrupted, re-run `/ship` — it reads the
PR, its checks, and the thread rather than starting over.

Gates are not optional. Never work around a red preflight, a failing check, a blocking review, or a
merge gate to ship faster — surface it to a human with the reason.
