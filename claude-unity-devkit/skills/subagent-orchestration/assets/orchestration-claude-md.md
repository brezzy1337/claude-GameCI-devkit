<!--
  Template: the "Sub-Agent Orchestration" section for a Unity project's CLAUDE.md.
  Replace every `TAILOR:` marker with this repo's specifics, then delete the marker comments.
  Append to an existing CLAUDE.md rather than overwriting it; match its tone. It relies on the
  "Unity project conventions" section (assembly table) from the unity-project-conventions skill.
-->

## Sub-Agent Orchestration

This project treats the main Claude Code session as an orchestrator. It does little work
directly — it routes tasks to sub-agents and assembles their results. Output quality depends on
routing the work correctly and briefing each sub-agent completely. The rules below are how this
session decides.

### Routing: parallel, sequential, or background

Default to the safest pattern that fits. When unsure, run sequentially — a wrong parallel split
causes merge conflicts (and scene/prefab YAML that can't be merged), while a wrong sequential
choice only costs time.

**Dispatch in parallel** only when ALL of these hold:
- The work splits into 3+ tasks in independent domains (assemblies that don't reference each other)
- No task needs another task's output
- File boundaries are clean — no two agents touch the same file, scene, prefab, or settings asset

**Dispatch sequentially** when ANY of these holds:
- One task depends on another's output (B needs A), including an assembly that references another
- Tasks share files or state — `ProjectSettings/**`, `Packages/manifest.json`, a shared scene or prefab
- Scope is unclear and must be understood before acting

**Dispatch in the background** when:
- The task is research or analysis, not file edits
- The result isn't blocking the current work
(Monitor background work from the agent view; press Ctrl+B to background a running task.)

### Domain boundaries (parallel splits)

When a change spans these domains, give each its own agent and keep their files from
overlapping. A parallel split is only safe when the globs below do not intersect; if two
domains share a file, that work is sequential. Each domain is one assembly definition's folder
(see the assembly table in "Unity project conventions").

<!-- TAILOR: replace with THIS repo's real assemblies and globs. Delete examples that don't apply. -->
- **Core** — `Assets/Scripts/Core/**` (`Game.Core`: data types, ScriptableObject definitions, services)
- **Gameplay** — `Assets/Scripts/Gameplay/**` (`Game.Gameplay`: player, AI, combat, physics)
- **UI** — `Assets/Scripts/UI/**` (`Game.UI`: HUD, menus)
- **Editor tooling** — `Assets/Editor/**` (`Game.Editor`: inspectors, build scripts)
- **Tests** — `Assets/Tests/EditMode/**`, `Assets/Tests/PlayMode/**` (usually routed with the code they cover)

**Single-owner, never parallel:** `ProjectSettings/**`, `Packages/manifest.json`,
`Packages/packages-lock.json`, `Assets/Scenes/**`, shared prefabs. Third-party folders
(`Assets/ThirdParty/**`) are not a domain — don't edit them.

### Dependency chains (sequential order)

Some work must be serialized because each step consumes the previous step's output. This session
owns the chain — specialists have no `Agent` tool — so it runs each step, then hands the relevant
output to the next.

<!-- TAILOR: replace with THIS repo's real chains, led by the asmdef reference graph. -->
- Core → Gameplay → UI (the asmdef reference direction: a referenced assembly changes first)
- Data definition (ScriptableObject / Input Actions) → systems that read it → Editor wiring of scenes/prefabs
- Research → Plan → Implement (understand before building)
- Implement → Test (EditMode / PlayMode, then GameCI) → Review

### Background by default

Run these in the background so the main work continues uninterrupted:
- Web research and documentation lookups (Unity manual, package docs)
- Codebase exploration and analysis
- Security audits, dependency audits, and performance profiling

### Invocation protocol (every dispatch)

A sub-agent starts with a fresh context window and cannot ask follow-up questions. A thin brief
— not the agent's ability — is the most common cause of a bad result. Every dispatch carries all
four of these:

1. **Context** — what's going on and why, plus any constraint that must survive the handoff
   (e.g. "don't touch `Assets/ThirdParty/`", "no scene edits — report Editor follow-ups").
2. **Instructions** — the specific change or output, scoped narrowly.
3. **File references** — exact paths to read or modify (e.g. `Assets/Scripts/Gameplay/Player/PlayerMotor.cs`).
4. **Success criteria** — what "done" looks like, concretely, including the test that proves it.

Weak: "Fix the jump."

Strong: "Fix the double jump that happens when Space is held at high frame rates. Jump input is
read inside `FixedUpdate` via `WasPressedThisFrame` in
`Assets/Scripts/Gameplay/Player/PlayerMotor.cs`. Done = exactly one jump per press at 30, 60, and
144 fps, covered by a new parameterized test in `Assets/Tests/PlayMode/PlayerMotorTests.cs`, and the
format + meta checks pass."

### Guardrails

- **Don't over-parallelize.** Splitting eight micro-tasks across eight agents costs more in
  coordination and tokens than it saves. Group related small tasks into one agent.
- **Don't under-parallelize.** Four genuinely independent analyses run one-by-one waste
  wall-clock time. Look for assembly independence.
- **Match the model to the task.** Set `CLAUDE_CODE_SUBAGENT_MODEL` (for example, `sonnet`) so
  focused sub-agent work runs on a lighter, cheaper model while this session reasons on a
  stronger one. A per-agent `model` field in `.claude/agents/` takes precedence over it.

### Dependency safety

Before adding or upgrading any package — UPM (Unity registry, scoped registry, git URL), NuGet DLL,
Asset Store import, or GitHub Action — and before delegating that work to a sub-agent, follow these
rules. Unity's Package Manager has no built-in release-age gate, so review is the enforcement.

**Verify before you add.** Never add a package just because the name sounds right. An agent can
hallucinate a plausible name that an attacker has already registered (slopsquatting). For any new
dependency, confirm it actually exists, that it's the canonical package (repo link resolves,
adoption/history look real, name isn't a near-miss of a popular package), and that a scoped registry
can't shadow Unity's own packages (keep `scopes` narrow).

**Respect the cooldown — adopt versions that are at least 7 days old.** Most malicious releases are
caught and pulled within hours to a couple of days. Every add or bump goes through the
`dependency-auditor` sub-agent, which checks the publish date against this rule; GitHub Actions bumps
are gated by Dependabot's `cooldown`. The one exception is a genuine security fix — evaluate it
explicitly rather than auto-waiting.

**Other guards (set these up; honor them in agent work):**
- Commit `Packages/packages-lock.json`; review every change to it with the manifest.
- Git-URL packages pin a tag or commit (`…git#v1.2.3`), never a branch.
- Asset Store content never goes into a public repository (the Asset Store EULA forbids redistribution).
- NuGet/native DLLs are reviewed like source, go through Git LFS, and have explicit platform settings.
- Editor scripts inside packages run with your privileges as soon as the Editor loads them — treat a
  new package like running its install script.

<!-- TAILOR: list the scoped registries this repo trusts, e.g. OpenUPM (package.openupm.com) with scopes [...] -->

**Escalate, don't bypass.** If shipping seems to require a sub-7-day version or disabling a guard,
surface it to a human with the reason — don't quietly weaken the policy to move faster.
