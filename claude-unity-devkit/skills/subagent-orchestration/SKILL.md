---
name: subagent-orchestration
description: >-
  Author Claude Code orchestration configuration for a Unity / C# game repo — the CLAUDE.md sub-agent
  routing rules and .claude/agents/ specialist definitions that teach a project's main session how to
  delegate. Use this skill whenever the user wants to set up, configure, audit, or improve how their
  Claude Code project uses sub-agents, such as writing or fixing CLAUDE.md routing rules keyed to
  assembly definitions, deciding when work should run in parallel vs sequentially vs in the
  background, defining persistent specialist agents, restricting agent tools or permissions, cutting
  token cost by routing sub-agents to lighter models, or fixing over- or under-parallelization and
  vague sub-agent invocations. Trigger it even when the user only describes the symptom ("my Claude
  Code spawns agents that step on each other's prefabs", "how do I make my main session delegate
  better", "set up agents for my Unity repo") without naming CLAUDE.md or .claude/agents explicitly.
---

# Sub-Agent Orchestration

## The idea

Claude Code isn't one AI — it's an orchestration system. The main session is a *central
thread* that mostly coordinates: it routes work to specialist sub-agents and stitches their
results back together. The quality of the output is bounded by two things the central thread
controls — **how it routes work** (parallel, sequential, or background) and **how completely it
briefs each sub-agent**. This skill produces the configuration that teaches a specific repo's
central thread to do both well.

You are authoring config, not running agents. The deliverables are static files the user
commits to their repo. Make them concrete and tailored — generic boilerplate barely moves the
needle, because the whole point of routing rules is that they encode *this* repo's real domain
boundaries and dependencies. In a Unity repo those boundaries are unusually crisp: assembly
definitions (`.asmdef`) are compiler-enforced domains, and their `references` are the dependency
chains. Use them.

## What you produce

1. **A CLAUDE.md orchestration section** — routing rules, this repo's domain splits and
   dependency chains, background defaults, an invocation protocol, guardrails, and a dependency-
   safety policy (release-age cooldown + verify-before-add). This is the spine; produce it in
   almost every case. Start from `assets/orchestration-claude-md.md`.
2. **`.claude/agents/` specialist definitions** (optional) — persistent, focused agents with
   least-privilege tools, when the repo has clear recurring specialist roles (reviewer, test
   writer, shader or tooling specialist) or the user asks. Schema lives in
   `references/agent-frontmatter.md` — read it before writing any agent file so the frontmatter is
   valid and current. If the claude-unity-devkit plugin is installed, its live agents
   (`implementer`, the review lenses, `dependency-auditor` — a copy is in
   `assets/dependency-auditor.md`) already exist as `claude-unity-devkit:<name>`; don't duplicate
   them — a project agent with the same name overrides the plugin's.

Decide between them from context: if the user just wants smarter delegation, the CLAUDE.md
section alone is often enough. Add agent files when there are repeatable roles worth naming.

## Step 1 — Inspect before you generate (do not skip)

Routing rules are only as good as the boundaries they name. A rule that says "gameplay agent
owns gameplay" is useless unless it points at the actual folders, and a parallel split is *unsafe*
if two named domains secretly share a file. So learn the repo first:

- **Find the real domains.** List the assembly definitions
  (`find . -name '*.asmdef' -not -path '*/Library/*'`, plus `.asmref` files) and map each to the
  folder glob it owns (e.g. `Assets/Scripts/Core/**`, `Assets/Scripts/Gameplay/**`,
  `Assets/Editor/**`, `Packages/com.studio.netcode/**`). These become the parallel-split boundaries.
  Confirm the globs don't intersect — overlapping globs mean that work is sequential, not
  parallel. Code outside any asmdef compiles into `Assembly-CSharp` and is one shared domain. The
  `unity-project-conventions` skill's `references/asmdef-routing.md` has the full procedure.
- **Find the shared serialized files.** `ProjectSettings/**`, `Packages/manifest.json`, and shared
  scenes and prefabs are YAML that merges badly; any change touching them is single-owner and
  sequential, no matter which domains it spans.
- **Find the real dependency chains.** What must exist before what? The asmdef `references` graph
  gives most of it: a referenced assembly changes before the assemblies that use it (Core →
  Gameplay → UI). Others: a ScriptableObject definition before the systems and assets that use it;
  a new Input Action map before the gameplay code that reads it; runtime code before its tests;
  code before the Editor work (scene/prefab wiring) that hooks it up.
- **Read the stack and existing CLAUDE.md.** Unity version (`ProjectSettings/ProjectVersion.txt`),
  render pipeline, input system, netcode, and test setup (`Packages/manifest.json`). Match the
  language and tone of any existing CLAUDE.md and append to it rather than duplicating. Note the
  verify commands (C# format check, meta-file check, Unity test command or "GameCI runs tests") so
  agent definitions can reference them.
- **Scan the dependency surface.** Supply-chain attacks make this part of inspection, not an
  afterthought. Read `Packages/manifest.json` and `Packages/packages-lock.json` and record the
  posture: Is the lock file committed? Which `scopedRegistries` are trusted, and how narrow are their
  scopes? Are git-URL packages pinned to a tag or commit, or floating on a branch? Are there Asset
  Store imports or NuGet DLLs under `Assets/`? Are GitHub Actions pinned? UPM has no built-in
  release-age cooldown, so this posture is what the dependency-safety rules in Step 2 codify. See
  `references/dependency-safety.md` for the per-source settings and what each check defends against.

If you have no repo access (e.g. on Claude.ai with nothing uploaded), ask the user for the asmdef
list, folder layout, stack, and the one or two ordering constraints that bite them most — or work
from what they describe and clearly mark every placeholder you couldn't verify. Never invent file
paths; a confidently wrong glob is worse than a labelled placeholder.

## Step 2 — Write the CLAUDE.md orchestration section

Copy the structure from `assets/orchestration-claude-md.md` and replace every `TAILOR` marker
with this repo's specifics. Keep these blocks:

- **Routing rules** — the parallel / sequential / background decision. Keep the conservative
  default (when unsure, sequential): a wrong parallel split causes merge conflicts in code and
  unmergeable scene/prefab YAML, while a wrong sequential choice only costs some time.
- **Domain boundaries** — the repo's real assemblies, each with non-overlapping file globs, plus
  the single-owner shared files.
- **Dependency chains** — the repo's real "X before Y" orderings, led by the asmdef graph. The
  central thread owns the chain: specialists are given no `Agent` tool, so each step runs from the
  main session, which hands the relevant output to the next.
- **Background defaults** — research/analysis/audits that shouldn't block.
- **Invocation protocol** — the four parts every dispatch must carry (context, instructions,
  file references, success criteria). This is where most setups stop, and it's the highest-
  leverage block: a sub-agent has a fresh context window and can't ask clarifying questions, so
  a thin brief is the single most common cause of a bad result. Include the weak-vs-strong
  example so the central thread has a pattern to imitate.
- **Guardrails** — against over-parallelizing (coordination + token overhead) and
  under-parallelizing (wasted wall-clock time), plus a pointer to model routing
  (`CLAUDE_CODE_SUBAGENT_MODEL`) so focused sub-agent work runs on a lighter, cheaper model
  while the central thread reasons on a stronger one.
- **Dependency safety** — the policy the central thread follows before it pulls or bumps any
  package. This matters doubly for an AI orchestrator, because the agent is often the one
  *proposing* the package — and an agent can confidently name a package that doesn't exist, which
  is exactly what slopsquatting attackers register. The block tells the central thread to
  verify-before-add, respect a release-age cooldown (the "at least a week old" rule), and route
  every add or bump through `dependency-auditor`. Use the ready-made block in the asset; the
  per-source detail and rationale live in `references/dependency-safety.md`.

## Step 3 — Define specialist agents (when warranted)

Read `references/agent-frontmatter.md` first. Then, for each recurring role:

- Give it a **sharp `description`** — Claude decides when to auto-delegate primarily from this
  field, so it matters more than it looks. Say what the agent is *for* and, where appropriate,
  add "use proactively" to encourage delegation.
- Grant **least-privilege tools.** A reviewer or auditor gets read-only tools (`Read, Grep,
  Glob`, plus narrow patterns like `Bash(git diff *)`) and no `Edit`/`Write`; a fixer needs `Edit`;
  a researcher gets `WebFetch, WebSearch`. Leave `Agent` out so the agent can't delegate further.
  Narrow tools keep the agent focused and cheaper.
- Pick a **model** to fit: lighter (`haiku`/`sonnet`) for scoped or read-only work, `inherit`
  when it should match the main session.
- Write a **focused system prompt** in the body: when invoked, what to do, what to check, how to
  format the result. One job per agent. For Unity agents, point at the CLAUDE.md conventions and the
  Editor-owned files they must not touch.

A `dependency-auditor` is a strong default specialist when dependency safety matters: a read-only
agent the central thread delegates "should we add or bump X?" to, which checks existence, release
age, Unity compatibility, advisories, and licensing, then returns a go/no-go. A ready-to-use
definition is in `assets/dependency-auditor.md` (the plugin's live version).

## Step 4 — Verify

- **Valid YAML frontmatter**, with `name` (lowercase + hyphens) and `description` present.
- **Current naming.** Use `Agent(name)` for permission/spawn rules (the old `Task(name)` still
  works as an alias, but write the current form). Don't reproduce a blog's stale `Task(...)`
  syntax verbatim.
- **Unique agent names** across the tree — a duplicate name in one scope is silently discarded,
  and a project agent silently overrides a plugin agent of the same name.
- **No glob overlap** between any two domains marked parallel-safe, and shared serialized files
  marked single-owner.
- **Least privilege** held throughout — no agent carries `Write`/`Edit` (or `Agent`) it doesn't use.
- **Dependency settings are real and current.** Don't emit npm or pnpm cooldown settings into a
  Unity repo — UPM has none; the cooldown lives in the auditor and in Dependabot for Actions.

## Grounding notes (keep the config honest)

- CLAUDE.md routing rules are **guidance the central thread reads**, not a hard scheduler. They
  steer delegation; they don't enforce it. Pair them with sharp agent `description` fields,
  which are the strongest lever for *automatic* delegation.
- Custom sub-agents **do** inherit CLAUDE.md (only the built-in Explore and Plan agents skip
  it), so routing rules and Unity conventions placed there reach both the orchestrator and custom
  agents. A rule that must reach Explore/Plan has to be restated in the delegation prompt.
- **Nesting exists; this design doesn't use it.** Claude Code lets a sub-agent spawn its own
  sub-agents (up to three layers below the main conversation by default;
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` turns it off). Keeping the chain one level deep — no
  `Agent` tool on specialists — keeps routing, git state, and human gates in one place. Say so
  rather than claiming sub-agents *can't* nest.
- Recent Claude Code models tend to **over-spawn** sub-agents. The guardrails earned their place
  — don't drop them.
- **Dependency rules in CLAUDE.md are a behavioral backstop, not the enforcement layer.** The
  durable protection is tooling and review: a committed `packages-lock.json`, pinned git refs,
  narrow scoped registries, Dependabot cooldowns for Actions, and a human gate on manifest changes.
  The agent should escalate to the human rather than silently weaken a guard to ship faster.
- Don't oversell. Frame this as "rules that make delegation more deliberate," not "automatic
  perfect orchestration."
