# claude-unity-devkit

A Claude Code plugin for Unity / C# game development. It bundles workflow skills (subagent
orchestration, code-todo handoffs, a ship workflow, Unity conventions, GameCI pipelines, Droplet
deploys, Unity testing) plus the live agents, slash commands, hooks, scripts, and templates they use.

It is modeled on [claude-t3-devkit](https://github.com/brezzy1337/claude-t3-devkit): same shape
(skills as authoring guides, live agents/commands that work out of the box, an
implement → review → ship chain, an optional Slack backstop hook), retargeted from TypeScript/T3 to
Unity + C# + GameCI.

## What's inside

```
claude-unity-devkit/
├── .claude-plugin/plugin.json      # plugin manifest
├── skills/                         # authoring guides (SKILL.md + assets + references)
│   ├── subagent-orchestration/     # CLAUDE.md routing keyed to asmdefs, agent schema, dependency safety
│   ├── subagent-code-todo/         # /code-todo: route → implement → gameplay/perf loop → Slack gate
│   ├── ship-workflow/              # /ship: preflight → PR → review panel → CI checks → merge → notify
│   ├── unity-project-conventions/  # CLAUDE.md Unity section, .gitignore/.gitattributes (LFS)/.editorconfig
│   ├── gameci-pipeline/            # GameCI test + build workflows, license activation, troubleshooting
│   ├── unity-init/                 # Unity CLI: editors, Unity-aware git, branch model, unity test/build CI
│   ├── unity-build-automation/     # Unity Build Automation CI — the Personal-license path (no build machine)
│   ├── unity-deploy/               # dedicated server (systemd) or WebGL (nginx) on a DigitalOcean Droplet
│   └── unity-testing/              # UTF EditMode/PlayMode, test asmdefs, NSubstitute, coverage rubric
├── agents/                         # live specialists (invoked as claude-unity-devkit:<name>)
│   ├── implementer.md  pr-author.md  slack-notifier.md  dependency-auditor.md  injection-scanner.md
│   ├── factual-reviewer.md  architecture-reviewer.md  security-reviewer.md
│   ├── consistency-reviewer.md  redundancy-checker.md
│   └── performance-reviewer.md  gameplay-reviewer.md  ci-reviewer.md   # Unity lenses
├── commands/                       # /claude-unity-devkit:<name>
│   ├── new-project.md   add-to-project.md   setup-ci.md   setup-deploy.md   unity-init.md   setup-cloud-build.md
│   └── code-todo.md     ship.md
├── hooks/hooks.json                # PreToolUse Unity path guard + OPTIONAL Slack backstop
├── scripts/
│   ├── guard-unity-paths.sh        # the PreToolUse hook: blocks Library/Temp/Logs + lone .meta edits
│   ├── check-meta-files.sh         # assets missing a .meta, orphaned .meta (working tree or --tracked)
│   ├── format-csharp.sh            # dotnet format (whitespace, .editorconfig) or a no-op with a message
│   ├── scaffold-unity-project.sh   # the Editor-free project scaffold (new-project + bootstrap.sh)
│   ├── sync-templates.sh           # copies templates/ + agents/ into skills/*/assets (--check for drift)
│   ├── test-uba-build.sh           # runs uba-build.sh against a mock UBA API (testdata/mock_uba.py)
│   └── notify-slack.sh             # used by the optional Slack hook (needs SLACK_WEBHOOK_URL)
├── templates/                      # canonical files the commands copy into a project
│   ├── project/  .gitignore .gitattributes .editorconfig manifest.json claude-settings.json asmdef/ tests/
│   ├── ci/       test.yml build.yml
│   └── deploy/   deploy-server.yml deploy-webgl.yml deploy.sh unity-server.service nginx-unity-webgl.conf
├── bootstrap.sh                    # one-shot terminal scaffolder (same scaffold as new-project)
└── .mcp.json                       # Slack / Notion / GitHub MCP server slots (fill in or delete)
```

Skills are the authoring guides (they teach Claude how to generate CLAUDE.md sections, agents,
workflows, and deploy files for a target repo). The files in `agents/` and `commands/` are the live,
ready-to-run versions. Both are intentionally included: the skills let you regenerate/customize, the
agents/commands work out of the box. `templates/` and `agents/` are the source of truth; each skill's
`assets/` holds byte-identical copies (run `scripts/sync-templates.sh` after editing).

## Install

**Prerequisites:** [Claude Code](https://code.claude.com/docs) installed and authenticated (`claude`
runs from your terminal). All `/…` commands below are typed inside an interactive `claude` session.
For CI and deploys you also want `gh` (authenticated) and `git-lfs`.

### Try it locally first (no marketplace needed)

```
git clone https://github.com/brezzy1337/claude-GameCI-devkit.git
claude --plugin-dir ./claude-GameCI-devkit/claude-unity-devkit
/reload-plugins
```

### Install from the marketplace (team)

```
# 1. add this marketplace (once per machine)
/plugin marketplace add brezzy1337/claude-GameCI-devkit

# 2. install the plugin
/plugin install claude-unity-devkit@claude-unity-devkit

# 3. companion plugins from the built-in official marketplace
/plugin install csharp-lsp@claude-plugins-official
/plugin install github@claude-plugins-official
```

Run `/reload-plugins` after installing. Commands are namespaced:
`/claude-unity-devkit:new-project`, `/claude-unity-devkit:add-to-project`,
`/claude-unity-devkit:setup-ci`, `/claude-unity-devkit:setup-deploy`,
`/claude-unity-devkit:code-todo`, `/claude-unity-devkit:ship`. Skills are also invocable directly,
e.g. `/claude-unity-devkit:gameci-pipeline`.

For zero-touch onboarding, install at **project scope** so it auto-loads for everyone on the repo
(`new-project`, `add-to-project`, and `bootstrap.sh` write this `.claude/settings.json` for you):

```json
{
  "extraKnownMarketplaces": {
    "claude-unity-devkit": { "source": { "source": "github", "repo": "brezzy1337/claude-GameCI-devkit" } }
  },
  "enabledPlugins": { "claude-unity-devkit@claude-unity-devkit": true }
}
```

## Project setup commands

Six commands bootstrap a repo onto the devkit — pick the ones that match your starting point:

| Command | Use it for | What it does |
|---------|-----------|--------------|
| `/claude-unity-devkit:new-project <name>` | a brand-new game | Asks for the Unity version (default **6000.3.24f1**, Unity 6.3 LTS), namespace, and Cinemachine; scaffolds `Assets/{Scripts,Scenes,Prefabs,Materials,Tests}`, `Packages/manifest.json` (Input System, uGUI + TextMeshPro, Test Framework, IDE packages, built-in modules), `ProjectVersion.txt`, runtime + EditMode/PlayMode asmdefs with smoke tests, `.gitignore`, `.gitattributes` (LFS), `.editorconfig`, and `.claude/settings.json` — **without** launching the Editor. Then generates the CLAUDE.md Unity conventions + orchestration sections and `.claude/agents/`. Unity Hub → *Add project from disk* finishes initialization. |
| `/claude-unity-devkit:add-to-project` | a Unity repo you already have | No scaffolding — detects the Unity version, inspects the real `Assets/` and `.asmdef` layout, reports hygiene gaps (serialization mode, meta files, LFS), enables the plugin, and generates CLAUDE.md sections + agents that fit the existing code. Never invents paths. |
| `/claude-unity-devkit:unity-init` | standardizing on the Unity CLI | Installs the pinned Unity CLI, the project's Editor and build modules; runs `unity vcs doctor`, `merge-setup`, and `hooks install` and marks scenes `lockable`; creates the `stable` integration branch (`main` = production); writes `.github/workflows/unity.yml` (`unity test` on PRs into `stable`, `unity build` on `stable` and `v*` tags, self-hosted or hosted, Personal/Pro/floating licensing); adds Branching, Unity CLI, and CI sections to CLAUDE.md; prints secrets, runner, and teammate steps. |
| `/claude-unity-devkit:setup-cloud-build` | CI on a Unity **Personal** license | Writes a GitHub Actions workflow + `uba-build.sh` that start Unity Build Automation builds (EditMode + PlayMode tests, then the build), wait, and report in the run summary — Unity's machines hold the license, so nothing runs the Editor in Actions. Looks up org/project IDs with the Unity CLI, and prints the Dashboard checklist, org-ID check, variables, and `cloud-ci` label. Free tier: 200 Windows minutes/month. |
| `/claude-unity-devkit:setup-ci` | adding CI with GameCI (Pro/Plus or license server) | Checks GameCI images exist for your Unity version, asks for build targets, runner type, and license type, writes `.github/workflows/test.yml` + `build.yml`, runs `ci-reviewer`, and prints the exact secrets and license-activation steps. |
| `/claude-unity-devkit:setup-deploy` | shipping builds | Asks for dedicated server (default) or WebGL, writes the deploy workflow, `deploy/deploy.sh`, and the systemd unit or nginx site, and prints the SSH key, host-key pin, secrets, and one-time Droplet setup. |

Day-to-day workflow: `/claude-unity-devkit:code-todo <change>` → (approve in terminal) →
`/claude-unity-devkit:ship`. Code-todo routes the change by assembly, dispatches `implementer`s,
loops `gameplay-reviewer` + `performance-reviewer` on gameplay slices, and gates on your approval.
Ship runs preflight (format, `.meta`, dependency audit), opens the PR after GATE 1, runs the review
panel, waits on the GameCI checks, and merges after GATE 2.

To scaffold from a plain terminal *before* the plugin is installed, `bootstrap.sh` runs the same
scaffold + settings step (run it from a clone of this repo — it copies from `templates/`):

```
./bootstrap.sh <project-name> <marketplace-repo>   # e.g. ./bootstrap.sh my-game brezzy1337/claude-GameCI-devkit
# optional: UNITY_VERSION=6000.0.83f1 UNITY_NAMESPACE=MyGame CINEMACHINE=1 ./bootstrap.sh …
```

## Agents

| Agent | Model | Role |
|-------|-------|------|
| `implementer` | inherit | writes one scoped slice inside one assembly's folder; verifies; never commits |
| `pr-author` | sonnet | drafts the PR; flags secrets, LFS misses, `.meta`/settings risks |
| `slack-notifier` | haiku | posts pipeline status via a Slack MCP server; no code, no Bash, no Agent |
| `dependency-auditor` | sonnet | GO/NO-GO on UPM / scoped registry / git URL / NuGet / Asset Store / Actions changes |
| `injection-scanner` | sonnet | repo-wide prompt-injection sweep (agent files, game text, LLM call sites) |
| `factual-reviewer` | sonnet | does the diff do what the PR claims (incl. platform claims) |
| `architecture-reviewer` | sonnet | asmdef direction, per-frame structure, singletons, SO vs MonoBehaviour |
| `security-reviewer` | sonnet | secrets in settings/builds, unsafe deserialization, netcode trust, PlayerPrefs |
| `consistency-reviewer` | haiku | naming, namespaces vs asmdef, placement, `.editorconfig` |
| `redundancy-checker` | sonnet | duplicates, and hand-rolled versions of engine/package features |
| `performance-reviewer` | sonnet | GC in hot paths, GetComponent/Find per frame, physics matrix, batching |
| `gameplay-reviewer` | sonnet | deltaTime, Fixed vs Update, input, state machines, null-safety, test coverage |
| `ci-reviewer` | haiku | workflow changes vs the gameci-pipeline rulebook |

Reviewers and auditors carry read-only tools and no `Agent` tool, so the chain stays one level deep
and every gate lives in the central thread.

## Companion plugins (not bundled — and intentionally so)

- **`csharp-lsp`** (`claude-plugins-official`) — C# code intelligence and diagnostics through
  `csharp-ls`. Install the server once: `dotnet tool install --global csharp-ls` (needs the .NET SDK
  6.0+; `brew install csharp-ls` on macOS). Unity generates the `.sln`/`.csproj` files the language
  server reads — enable project generation in Unity (External Tools) and open the project once.
- **`github`** (`claude-plugins-official`) — GitHub's MCP server for PR/issue work outside the `gh`
  CLI. The devkit's commands default to `gh`.

The docs recommend the official LSP plugins for common languages rather than custom ones; this plugin
only bundles its own skills/agents/commands/hooks plus MCP server slots.

## MCP servers (.mcp.json)

`.mcp.json` ships with three **placeholder** server slots. Plugin MCP servers start automatically when
the plugin is enabled, so until you fill them in they show up as failed in `/plugin` → Errors:

- Replace `REPLACE_WITH_SLACK_MCP_PACKAGE`, `REPLACE_WITH_NOTION_MCP_PACKAGE`, and
  `REPLACE_WITH_GITHUB_MCP_COMMAND` with the servers you've chosen, or delete the slots you don't want.
  If you install the `github` companion plugin, delete the `github` slot to avoid a duplicate server.
- Provide credentials via environment variables — each teammate supplies their own:
  - `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` (so `slack-notifier` can post to the team channel)
  - `NOTION_TOKEN` (so workflows can read design / architecture pages)
  - `GITHUB_PERSONAL_ACCESS_TOKEN` (for the GitHub slot, if you keep it)

## Hooks

`hooks/hooks.json` registers two hooks:

- **PreToolUse `Write|Edit` — Unity path guard (on by default).** `scripts/guard-unity-paths.sh`
  blocks writes under a Unity project's `Library/`, `Temp/`, or `Logs/`, and blocks edits to a `.meta`
  file unless its asset is also in the change set (`git status` shows it added, modified, deleted, or
  untracked). Outside a Unity project (no `Assets/` + `ProjectSettings/` ancestor) it does nothing; in
  a Unity folder that isn't a git repo it asks instead of blocking. Needs `git`, plus `jq` or `python3`
  (falls back to `sed`). Remove the entry to disable it.
- **SubagentStop on `security-reviewer` — OPTIONAL Slack backstop.** Fires a webhook after the security
  lens finishes, as a backstop for when the agent chain is interrupted. It needs `SLACK_WEBHOOK_URL`
  (it exits quietly without it). The `slack-notifier` agent is the primary notifier; delete the hook +
  script if you don't want the backstop.

## Pinned versions

Verified on 2026-09-13; re-check before bumping (see the `gameci-pipeline` skill).

| What | Version | Note |
|------|---------|------|
| Unity default | 6000.3.24f1 (changeset 4e7b9b5b6244) | Unity 6.3 LTS; GameCI images published |
| `game-ci/unity-test-runner` | `@v4` | → v4.4.0 (thin wrapper over game-ci/cli) |
| `game-ci/unity-builder` | `@v5` | v6.0.0 (2026-09-10) is a drop-in upgrade; adopt after the 7-day cooldown |
| `actions/checkout` / `cache` / `upload-artifact` / `download-artifact` | `@v7` / `@v6` / `@v7` / `@v8` | |
| Default packages | inputsystem 1.20.0, test-framework 1.6.0, ugui 2.0.0, ide.rider 3.0.40, ide.visualstudio 2.0.26, cinemachine 3.1.7 (optional) | from real Unity 6.3 projects |

## Publish

```
git add -A && git commit -m "claude-unity-devkit: initial plugin"
git branch -M main
git remote add origin https://github.com/brezzy1337/claude-GameCI-devkit.git
git push -u origin main
```

If you fork the devkit, change the owner/author in `.claude-plugin/marketplace.json` and
`plugin.json`, `homepage`/`repository`, and the marketplace repo (`brezzy1337/claude-GameCI-devkit`)
in `commands/new-project.md`, `commands/add-to-project.md`, and the READMEs. The `.mcp.json` server
slots stay placeholders until you pick servers.

## Validate before publishing

```
claude plugin validate .                         # from the repo root: the marketplace
claude plugin validate ./claude-unity-devkit     # the plugin
claude plugin validate --strict ./claude-unity-devkit
bash claude-unity-devkit/scripts/sync-templates.sh --check   # skill assets match templates/ + agents/
bash claude-unity-devkit/scripts/test-uba-build.sh            # uba-build.sh against the mock UBA API
```

- `plugin.json` has `name` (lowercase-kebab), `version`, `description`; the version matches the
  marketplace entry.
- Only `plugin.json` lives in `.claude-plugin/`; `commands/`, `agents/`, `skills/`, `hooks/` are at root.
- Agent frontmatter is valid and names are unique; reviewers/auditors carry read-only tools only and
  no plugin agent declares `hooks`, `mcpServers`, or `permissionMode` (ignored for plugin agents).
- Skill/command descriptions contain no `: ` sequences or `<…>` placeholders.
- Load locally first: `claude --plugin-dir ./claude-unity-devkit`, then `/reload-plugins`.
- Live-editing an installed copy: Claude Code caches installs per version, so a local clone can be
  symlinked over `~/.claude/plugins/cache/claude-unity-devkit/claude-unity-devkit/<version>` and
  picked up by `/reload-plugins`. Bumping `version` makes the next install copy a fresh cache
  directory — re-create the symlink after a bump.
