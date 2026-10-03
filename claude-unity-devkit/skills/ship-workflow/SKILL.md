---
name: ship-workflow
description: >-
  Author a Claude Code "ship" pipeline for a Unity / C# repo that opens a pull request, runs a
  multi-lens code review via sub-agents, waits on the GameCI checks, and notifies the team on Slack or
  Discord — built on top of the subagent-orchestration baseline. Use this skill whenever the user
  wants to set up, configure, or improve an automated PR, review, and notify workflow for a Claude
  Code project, such as a /ship (or /open-pr) slash command, specialist agents like pr-author, a
  review panel (factual, architecture, security, consistency, redundancy, plus Unity performance,
  gameplay, and CI lenses), slack-notifier, approval gates before opening or merging, Slack or Discord
  updates on PR events (including choosing between them), or wiring these together with hooks and the
  gh CLI. Trigger it even when the user only describes the goal ("get my changes reviewed and tell the
  team on Slack/Discord", "automate opening PRs with a review step", "set up a ship command") without
  naming the pieces. For the routing rules, invocation protocol, and dependency safety this depends
  on, see the subagent-orchestration skill.
---

# Ship workflow

## The idea

This is the `subagent-orchestration` chain applied to shipping a change. The pipeline —
preflight → open PR → review → CI checks → merge → notify — is just that skill's "Implement → Test →
Review" chain extended with PR creation at the front and a team notification (Slack or Discord)
at the back. The
central thread owns it (specialists get no `Agent` tool): it runs each stage and hands output to the
next. So author this on top of the baseline, don't restate the baseline's routing or invocation
rules here.

Design for two audiences. **Intuitive for the user:** one handle (`/ship`) starts the chain, and
two human gates (open, merge) keep them in control while Slack or Discord gives visibility. **Effective for
the model:** each stage is a focused agent with least-privilege tools and a clear input/output
contract, the glue is deterministic (permission gates and hooks, not remembered prose), and state
lives in durable places (the PR body, plus one Slack thread when Slack is the channel) so an
interrupted run can resume.

The Unity twist: most developers can't run the Editor's tests in the loop, so the **GameCI Test
workflow on the PR is the authoritative test run** (see `gameci-pipeline`), and `/ship` treats a red
check as a blocking finding at the merge gate.

If the claude-unity-devkit plugin is installed, the live pipeline already exists as
`/claude-unity-devkit:ship` with its agents; author project-local copies only when the user wants to
customize them.

## What you produce

1. **An entry point** — `.claude/commands/ship.md`, a slash command that runs the pipeline.
2. **Specialist agents** in `.claude/agents/` — a five-lens review panel (`factual-reviewer`,
   `architecture-reviewer`, `security-reviewer`, `consistency-reviewer`, `redundancy-checker`),
   three Unity lenses dispatched by what the diff touches (`performance-reviewer`,
   `gameplay-reviewer`, `ci-reviewer`), plus the pipeline mechanics `pr-author` and
   `slack-notifier` (Slack teams). Reuse the baseline's `dependency-auditor` in preflight rather
   than duplicating it.
3. **A CLAUDE.md "Ship workflow" section** describing the chain, the gates, and where state lives.
4. **For Discord teams** — `.claude/scripts/notify-discord.sh` (`assets/notify-discord.sh`), the
   webhook poster `/ship` runs when the PR opens.
5. **Optional** — a `SubagentStop` Slack hook as a notification backstop (see Step 5).

Templates for all of these are in `assets/`. The agent templates are byte-identical copies of the
plugin's live agents (kept in sync by `scripts/sync-templates.sh`); in a project-local copy, replace
`${CLAUDE_PLUGIN_ROOT}/...` references with paths that exist in the repo. The wiring detail (gh CLI,
gates, Slack and Discord paths, state) is in `references/wiring.md`.

## Step 1 — Inspect first

Same rule as the baseline: tailor to the real repo. Before generating, learn:

- **Git host & CLI.** Is `gh` available and authenticated? That's the default driver for PR
  create/review/checks/merge. (The GitHub plugin/MCP is the alternative — see the reference — worth
  it only if PR actions are needed from outside Claude Code.)
- **Verify commands.** The preflight stage runs these: the C# format check, the `.meta` check
  (`--tracked --strict`), and the Unity test command if a local Editor is configured. Put the real
  commands in the command body, not a guess.
- **CI checks.** Which GameCI workflows run on PRs, and what are the check names (`editmode test
  results`, `playmode test results` in the devkit templates)? The merge gate waits on them.
- **Base branch.** What do PRs target (`main`, `develop`)? The command needs it for the diff and
  for `gh pr create --base`.
- **Notification channel.** Slack, Discord, or none? Ask if it isn't obvious. For Slack: which
  channel, and is a Slack MCP server connected? For Discord: is a channel webhook available as
  `DISCORD_WEBHOOK_URL` (a Codespaces secret or local env var)? Record the answer as the
  `Notifications:` line in the CLAUDE.md section (Step 4); if it isn't set up yet, say what's
  missing.
- **Existing agents.** If the baseline is already installed, reuse `dependency-auditor` in
  preflight; the review panel is defined here. Don't duplicate a `name` that already exists in
  the same scope — duplicates are silently dropped, and a project agent overrides a plugin agent.

If you can't read the repo, ask for these (or mark them as placeholders) — don't invent a test
command, check name, or base branch.

## Step 2 — Author the entry point (`/ship`)

Start from `assets/ship-command.md`. The key design choices to preserve:

- **Make the gates real via permissions, not prose.** List only read-only/inspection commands in
  `allowed-tools` (e.g. `Bash(git status *)`, `Bash(git diff *)`, `Bash(gh pr view *)`,
  `Bash(gh pr checks *)`). Deliberately leave `git push`, `gh pr create`, `gh pr comment`, and
  `gh pr merge` *out* of `allowed-tools` so Claude Code prompts for permission at exactly those
  points — that prompt is the human gate. Never grant a blanket `Bash(gh *)`: it pre-authorizes both
  gates away.
- **Spell out the stages in order** with the gate language ("show me the draft and wait for my
  explicit yes before opening"). The command body is the chain definition the central thread
  follows.
- **Stop on red.** A failed preflight, a failing CI check, or a blocking review halts the pipeline
  and reports; it never works around the failure.

## Step 3 — Author the specialist agents

Read the baseline's `references/agent-frontmatter.md` for the schema first. Then design the
agents deliberately — a specialist earns its place by getting its *own* context. When one
session has to review correctness, security, and frame-time cost at once, those concerns
compete for attention and you get shallow, generic feedback on all three; an isolated agent that
thinks about one dimension goes deep on it. That depth is the entire reason to split, so design
each agent as a single expert lens, not a second pair of hands.

Four design rules make the split pay off:

- **One non-overlapping dimension per agent.** The common failure is stacking near-duplicate
  roles ("security expert" + "pen tester" + "vuln scanner") that all surface the same findings
  and inflate cost. Give each agent a dimension no other agent owns, and make the boundaries
  explicit in its prompt so it stays in lane. (The architecture lens judges *how per-frame work is
  structured*; the performance lens judges *what each hot-path line costs* — the prompts say so.)
- **Match tools to the dimension's natural instruments — then trim to least privilege.** A
  security reviewer reaches for the diff and history; a code reviewer reaches for the diff and the
  test command; a notifier reaches for Slack. Grant exactly those and nothing that lets it edit
  code it's only meant to inspect.
- **Define an output contract.** Each reviewer returns findings in a fixed shape — severity
  (Critical / Warning / Note), file, the risk, and a concrete fix, plus a one-line
  blocking/non-blocking verdict. A consistent shape is what makes consolidation mechanical
  instead of a re-read.
- **Reserve the fan-out for substantive diffs.** A typo or one-line change doesn't need eight
  reviewers; the coordination overhead outweighs the benefit. Gate the review fan-out on the
  change being non-trivial.

The core panel — five complementary, non-overlapping code-quality lenses, each persisted as its own
agent (templates in `assets/`):

- **`factual-reviewer`** — technical accuracy: does the change do what the PR, linked issue, and
  docs claim (including platform claims like "works on WebGL"), and does it contradict any documented
  contract?
- **`architecture-reviewer`** (the senior-engineer lens) — asmdef boundaries and dependency
  direction, coupling, per-frame structure, singleton and global-state abuse, ScriptableObject vs
  MonoBehaviour responsibilities, testability.
- **`security-reviewer`** — secrets in settings and builds, unsafe deserialization, netcode trust
  boundaries, PlayerPrefs misuse, TLS bypasses, prompt injection, new dependencies.
- **`consistency-reviewer`** — standards compliance: naming, namespaces vs asmdef `rootNamespace`,
  folder placement, serialized-field style, drawn from the repo's `.editorconfig` and CLAUDE.md.
- **`redundancy-checker`** — duplicate logic: copy-paste within the diff, existing utilities, and
  hand-rolled versions of engine/package features (pooling, tweening, input).

The three Unity lenses, dispatched only when the diff touches their area — keep them off the default
path:

- **`performance-reviewer`** — runtime gameplay code or physics/quality/graphics settings: GC
  allocations and lookups in hot paths, per-frame strings, physics layer matrix, batching and
  draw-call costs.
- **`gameplay-reviewer`** — runtime gameplay code: frame-rate independence, `FixedUpdate` vs
  `Update`, input handling, state transitions, null-safety on scene references; it also judges test
  coverage with the `unity-testing` rubric.
- **`ci-reviewer`** — `.github/workflows/**` or `deploy/**`: GameCI versions, license secrets,
  Library cache keys, matrix, runners, fork safety, deploy gating, checked against `gameci-pipeline`.

Keep **`dependency-auditor`** in *preflight* rather than the review panel: supply-chain age,
compatibility, and licensing checks belong before the PR opens, not at review time.

The two non-review agents are pipeline mechanics, not review lenses, so the panel doesn't replace
them — keep them just as focused: **`pr-author`** drafts the PR title/body from the diff
(read-only git, no push/merge; it separates code from serialized-asset churn and flags LFS, `.meta`,
and settings risks), and **`slack-notifier`** posts status to Slack through a Slack MCP server
(denied `Write`/`Edit`/`Bash`/`Agent` so it can't touch code, run commands, or delegate). In a
project-local copy you may scope it with `mcpServers: [slack]`; plugin agents can't declare
`mcpServers`, so the plugin's version inherits the session's Slack tools instead.

Because these review lenses are independent and read-only, they're the textbook *safe parallel*
case from the baseline — run them concurrently, not in sequence, with edits disabled (least-
privilege tools already enforce this; plan mode is a belt-and-suspenders option) so a reviewer
can never "helpfully" rewrite the code it's judging.

### Consolidation is the central thread's job

A pile of separate reports isn't a review — it's homework for the human. After the fan-out,
the central thread consolidates before anything reaches the PR: merge the findings, resolve
conflicts where two lenses disagree (e.g. a caching pattern the performance lens wants that the
architecture lens thinks couples two assemblies), de-duplicate overlapping notes, rank everything by
impact, and post one prioritized action list with a single overall verdict. The reviewers produce
signal; the central thread turns it into a decision. Make this an explicit step of the Review stage,
not an afterthought — it's what makes the gate worth stopping at.

## Step 4 — Author the CLAUDE.md "Ship workflow" section

Use `assets/ship-workflow-claude-md.md`. It records the chain, marks both gates as
approval-required, names the review fan-out as parallel-then-consolidated, makes the GameCI checks
part of the merge gate, records the notification channel (`Notifications: slack | discord | none`),
and states where state lives (PR body, plus the Slack thread for Slack) so a re-run resumes instead of
restarting. It also reminds the central thread that gates are not optional.

## Step 5 — Wire the notifications

`/ship` picks the channel from a `--notify=slack|discord|none` flag, else the CLAUDE.md
`Notifications:` line, else auto-detects (Discord if `DISCORD_WEBHOOK_URL` is set, Slack if Slack MCP
tools are connected). Wire the one the team uses.

**Discord** — copy `assets/notify-discord.sh` to `.claude/scripts/` and `chmod +x` it. `/ship` runs it
once, right after the PR opens; the embed links to GitHub, where people review and merge. One post,
not one per transition: a webhook can't start a thread in a normal text channel (only in forum channels), so per-stage
posts would scatter across the channel. The webhook URL is a secret (anyone holding it can post):
keep it in `DISCORD_WEBHOOK_URL`, never in the repo, and never print it. A missing webhook (exit 3)
only skips the post.

**Slack** — default to the **agent path**: the command's last step in each transition invokes `slack-notifier`,
which posts via a Slack MCP server and keeps everything in one thread (it returns the thread
timestamp; store it in the PR body so later updates reply in-thread). This is reliable because it's
a defined command step, not an ad-hoc afterthought.

Offer the **hook backstop** only if the user wants a notification to fire even when the chain is
interrupted: a `SubagentStop` hook (`assets/subagentstop-slack-hook.json`) running a small script.
Be honest about the constraint — **a command hook runs a shell command and doesn't talk to the Slack
MCP server** — so the backstop posts through a Slack incoming webhook (`SLACK_WEBHOOK_URL`). The
`SubagentStop` matcher matches the agent's type name: a project agent is `security-reviewer`, the
plugin's is `claude-unity-devkit:security-reviewer`; the asset's regex matcher covers both.

## Step 6 — Verify

- **Gates are enforced, not just described** — `git push`, `gh pr create`, `gh pr comment`, and
  `gh pr merge` are absent from the command's `allowed-tools`, and there is no blanket `Bash(gh *)`.
- **Least privilege** — `slack-notifier` can't edit code or delegate; every reviewer is read-only with
  no `Write`/`Edit`/`Agent`.
- **One notification channel** — the CLAUDE.md `Notifications:` line names it; for Discord the
  webhook comes from `DISCORD_WEBHOOK_URL` only, never a committed file.
- **Review lenses stay distinct** — no two panel agents cover the same dimension (the "overlapping
  roles" mistake); each has a dimension the others don't, stated in its prompt.
- **Valid frontmatter** — command fields (`description`, `argument-hint`, `allowed-tools`) and
  agent fields (`name`, `description`) are present and correct.
- **Real values** — the verify commands, CI check names, base branch, and Slack channel (or Discord
  webhook variable) are the repo's actual ones, not placeholders left in.
- **One level of delegation** — the chain runs from the central thread; agents don't call agents.

## Grounding notes

- The gates rely on the permission prompt, so they only hold in interactive use (or with a
  matching `permissions` policy). In headless/auto modes, add explicit `permissions.ask` /
  `deny` rules for the push/create/merge commands, or the gate won't prompt.
- Notifications via the agent are model-driven; the webhook+hook backstop is the deterministic
  layer. Pick based on how much the user needs guaranteed firing.
- A green GameCI run proves the tests pass, not that the change plays well — the gameplay lens and
  a human playtest still matter for gameplay changes.
- Reuse the baseline agents rather than redefining them — duplicate `name`s in one scope are
  silently dropped.
- Don't oversell. This makes shipping a deliberate, visible pipeline with human control — not a
  hands-off auto-merge bot.
