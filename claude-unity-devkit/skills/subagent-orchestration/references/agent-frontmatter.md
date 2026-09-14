# `.claude/agents/` frontmatter reference

Read this before writing any agent file. It reflects the Claude Code sub-agent and plugin docs as
of September 2026 (code.claude.com/docs/en/sub-agents, /plugins-reference). Use it to keep generated
agent files valid — don't rely on memory or copy stale syntax from blog posts.

## Contents
- File format and location
- Required and optional frontmatter fields
- The `model` field
- Tool access (`tools` / `disallowedTools`)
- Naming: `Agent(...)` vs the legacy `Task(...)`
- Behavior facts that affect config
- Example agents

## File format and location

A sub-agent is a Markdown file: YAML frontmatter on top, then a body that becomes the agent's
**system prompt**. The agent receives only that system prompt plus basic environment details (and
the CLAUDE.md hierarchy) — not the full Claude Code system prompt.

| Location | Scope | Notes |
| --- | --- | --- |
| `.claude/agents/` | This project | Commit these; they're shared with the team. Overrides user and plugin agents of the same name |
| `~/.claude/agents/` | All your projects | Personal, cross-project |
| `<plugin>/agents/` | Wherever the plugin is enabled | Invoked as `<plugin>:<name>` (e.g. `claude-unity-devkit:implementer`) |

Directories are scanned recursively, so subfolders (`agents/review/`) are fine. Identity comes from
the `name` field. Names must be unique within a scope — a duplicate name is kept-one-discarded-other
**without warning**. Edits to files on disk load at session start; restart the session (or use
`/agents`, or `/reload-plugins` for plugin agents) to pick up changes.

## Frontmatter fields

Only `name` and `description` are required.

| Field | Required | Purpose |
| --- | --- | --- |
| `name` | Yes | Unique id, lowercase letters and hyphens |
| `description` | Yes | When Claude should delegate here — the primary auto-delegation signal |
| `tools` | No | Allowlist of tools (comma-separated or YAML list). Inherits all if omitted |
| `disallowedTools` | No | Denylist, removed from the inherited/allowed set |
| `model` | No | `sonnet` / `opus` / `haiku` / `fable` / a full id (e.g. `claude-opus-5`) / `inherit` |
| `effort` | No | `low` / `medium` / `high` / `xhigh` / `max`; overrides session effort |
| `maxTurns` | No | Max agentic turns before the agent stops |
| `skills` | No | Skills to preload into the agent's context at startup |
| `memory` | No | `user`, `project`, or `local` — persistent cross-session memory dir |
| `background` | No | `true` to keep it in the background |
| `isolation` | No | `worktree` to run in an isolated git worktree copy |
| `color` | No | UI color |
| `permissionMode` | No | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, or `plan` — **project/user agents only** |
| `mcpServers` | No | MCP servers scoped to this agent — **project/user agents only** |
| `hooks` | No | Lifecycle hooks scoped to this agent — **project/user agents only** |

**Plugin agents ignore `permissionMode`, `mcpServers`, and `hooks`** (a security restriction). A
plugin agent that needs an MCP server gets it from the session (the plugin's `.mcp.json` or the
user's connectors) — so don't restrict it with a `tools` allowlist that omits those MCP tools; use
`disallowedTools` instead, as the devkit's `slack-notifier` does.

For most config-authoring work you only need `name`, `description`, `tools`, and `model`. Reach
for the rest when the user has a specific need (e.g. `memory` for an agent that should accumulate
codebase knowledge, `isolation: worktree` for risky edits).

## The `model` field

- Aliases: `sonnet`, `opus`, `haiku`, `fable`. Aliases age better than pinned ids — prefer them
  unless the user wants a specific version.
- Full ids are also accepted (e.g. `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5-20251001`).
- `inherit` uses the main session's model.
- Resolution order at invocation: the per-invocation `model` parameter → the agent's `model`
  frontmatter → the `CLAUDE_CODE_SUBAGENT_MODEL` environment variable → the main conversation's model.

A common cost pattern: main session on the strongest model, read-only reviewers on `sonnet` or
`haiku`, and `inherit` for code writers that need the full model.

## Tool access

Restrict with either an allowlist or a denylist:

```yaml
# Allowlist — agent gets ONLY these (no Edit/Write, no MCP, no Agent)
tools: Read, Grep, Glob, Bash(git diff *)
```

```yaml
# Denylist — inherit everything EXCEPT these
disallowedTools: Write, Edit, Bash, Agent
```

If both are set, `disallowedTools` applies first, then `tools` resolves against what remains; a
tool in both is removed. `Bash(pattern)` entries use permission-rule syntax: `Bash(git diff *)`
allows `git diff` with any arguments. Least-privilege defaults by role:

- Reviewers / auditors (read-only): `Read, Grep, Glob, Bash(git diff *)`
- Researchers: `Read, Grep, Glob, WebFetch, WebSearch`
- Code writers / fixers: `Read, Write, Edit, Bash, Glob, Grep`

`AskUserQuestion` is never available to sub-agents — they can't ask the user questions, which is why
the brief must be complete.

## Naming: `Agent(...)` vs legacy `Task(...)`

The Task tool was renamed **Agent**. `Task(...)` still works as an alias, but write the current form
in new config:

```json
{ "permissions": { "deny": ["Agent(Explore)", "Agent(my-custom-agent)"] } }
```

To restrict which agents an agent may spawn, list `Agent(name, …)` in its `tools` field (e.g.
`tools: Agent(worker, researcher), Read, Bash`).

## Behavior facts that affect config

- **Sub-agents can nest.** By default a sub-agent can spawn sub-agents of its own, up to three
  layers below the main conversation (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; `1` turns nesting off).
  To keep a specialist from delegating, omit `Agent` from its `tools` or add it to `disallowedTools`.
  The devkit's chains are deliberately one level deep: the central thread owns routing, git, and gates.
- **Custom sub-agents inherit CLAUDE.md** (every level of the hierarchy the main conversation loads);
  only the built-in Explore and Plan agents skip it. So routing rules and Unity conventions in
  CLAUDE.md reach custom agents too.
- **Built-ins:** Explore (read-only search), Plan (read-only planning), general-purpose (all tools).
  You don't redefine these — you route around or restrict them.
- **`description` drives auto-delegation.** Make it specific; add "use proactively" to encourage
  delegation where that's wanted.

## Example agents

Read-only reviewer:

```markdown
---
name: shader-reviewer
description: Reviews shader and material changes for SRP Batcher compatibility and mobile cost. Use proactively after edits under Assets/Shaders/.
tools: Read, Grep, Glob, Bash(git diff *)
model: sonnet
---

You review shader changes. When invoked:
1. Run `git diff` on Assets/Shaders/ and the materials that use the changed shaders.
2. Check SRP Batcher compatibility (CBUFFER layout), keyword count, and per-fragment cost.
3. Report findings as Critical / Warning / Note, each with a concrete fix.
```

Scoped researcher on a lighter model:

```markdown
---
name: unity-docs-researcher
description: Researches Unity manual pages, package docs, and version constraints. Use for docs lookups so results stay out of the main context.
tools: Read, Grep, Glob, WebFetch, WebSearch
model: haiku
---

You research and summarize. Do not edit files. Return a short answer with sources, the Unity and
package versions it applies to, and a recommendation tied to this repo's editor version.
```
