---
description: Wire the claude-unity-devkit into an existing Unity repo — detect the Unity version and real asmdef layout, enable the plugin, then generate tailored CLAUDE.md conventions + orchestration and agents (no scaffolding)
argument-hint: [optional notes on domains or ordering constraints]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git rev-parse *), Bash(git branch *), Bash(git status *), Bash(git ls-files *), Bash(ls *), Bash(find *)
disable-model-invocation: true
---

# Add to project

Onboard the **current existing Unity repository** to the claude-unity-devkit so its orchestration,
code-todo, ship, CI, and deploy workflows are available here. Do NOT scaffold anything — adapt to
what already exists. Treat $ARGUMENTS as extra context about domains or ordering constraints.

Context (gathered for you):
- Repo root: !`git rev-parse --show-toplevel 2>/dev/null || echo "not a git repo"`
- Branch: !`git branch --show-current`
- Top-level layout: !`ls -1`
- Unity project(s): !`find . -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print`
- Assembly definitions: !`find . -name '*.asmdef' -not -path '*/Library/*' -not -path './.git/*'`

1. **Verify the repo.** Confirm this is the existing project you want wired. If it isn't a git repo,
   or no `ProjectSettings/ProjectVersion.txt` was found, stop and tell me — this command adds to
   existing Unity projects; use `/claude-unity-devkit:new-project` to scaffold a fresh one. If more
   than one Unity project was found, ask me which one (its folder becomes `projectPath` for CI).

2. **Detect the Unity version.** Read `ProjectSettings/ProjectVersion.txt` (`m_EditorVersion`) and
   record it — CI images, package compatibility, and the dependency auditor all key off it.

3. **Enable the plugin here.** Write or MERGE into `.claude/settings.json` so this repo (and
   collaborators on folder-trust) get the marketplace + plugin. Preserve any existing keys — merge,
   don't overwrite:
   ```json
   {
     "extraKnownMarketplaces": {
       "claude-unity-devkit": { "source": { "source": "github", "repo": "brezzy1337/claude-GameCI-devkit" } }
     },
     "enabledPlugins": { "claude-unity-devkit@claude-unity-devkit": true }
   }
   ```

4. **Inspect before generating.** Never invent paths; mark anything you can't verify as a placeholder.
   - **Assemblies = domains.** For each `.asmdef`: its `name`, folder (the glob it owns, minus nested
     asmdef folders), `references` (the dependency graph), and `includePlatforms` (Editor-only,
     test assemblies). Note code under `Assets/` that sits outside every asmdef (it compiles into
     `Assembly-CSharp` and can't be a clean domain — flag it).
   - **Layout.** Top-level folders under `Assets/`, third-party/vendor folders, embedded packages in
     `Packages/`, test folders, scenes.
   - **Dependencies.** `Packages/manifest.json` (packages, `scopedRegistries`, git URLs, `file:`
     packages), whether `Packages/packages-lock.json` is committed, DLLs under `Assets/Plugins/`.
   - **Hygiene.** `ProjectSettings/EditorSettings.asset` has `m_SerializationMode: 2` (Force Text);
     `ProjectSettings/VersionControlSettings.asset` has `m_Mode: Visible Meta Files`; `.gitignore`
     covers `Library/`, `Temp/`, `Logs/`, `UserSettings/`; `.gitattributes` routes binary assets
     through Git LFS (check `git ls-files` for large binaries committed outside LFS); run
     `"${CLAUDE_PLUGIN_ROOT}/scripts/check-meta-files.sh" --tracked` for missing/orphaned `.meta`.
   - **Existing CLAUDE.md, `.editorconfig`, `.github/workflows/`** — read them; you'll append, not
     duplicate.

5. **Report hygiene gaps and offer fixes.** List what's missing or risky. Offer the devkit templates
   (`${CLAUDE_PLUGIN_ROOT}/templates/project/.gitignore`, `.gitattributes`, `.editorconfig`) — ask
   before writing, and merge into existing files rather than replacing them. Never flip
   serialization mode or rewrite ProjectSettings yourself; tell me the Editor setting to change.

6. **Generate conventions + orchestration config.**
   - Use the `unity-project-conventions` skill to author or APPEND the CLAUDE.md **Unity project
     conventions** section from the real layout: folder rules, the asmdef map and allowed dependency
     direction, ScriptableObject vs MonoBehaviour guidance, Input System usage, LFS/serialization/
     `.meta` rules, and the verify commands.
   - Use the `subagent-orchestration` skill to author or APPEND the **Sub-Agent Orchestration**
     section: domain boundaries are the asmdef folders from step 4; dependency chains follow asmdef
     references (a referenced assembly changes before the assemblies that depend on it). Add
     `.claude/agents/` specialists only where roles recur, with least-privilege tools.

7. **Confirm the workflows.** Make sure the generated CLAUDE.md references
   `/claude-unity-devkit:code-todo` and `/claude-unity-devkit:ship` so the implement → review → ship
   chain works here. If there is no CI yet, point me at `/claude-unity-devkit:unity-init` (Unity CLI: machine,
   Unity-aware git, branch model, and CI) — or `/claude-unity-devkit:setup-ci` for GameCI;
   for deploys, `/claude-unity-devkit:setup-deploy`. Mention the optional MCP servers and Slack hook.

8. **Next steps.** Print: run `/reload-plugins`, then try `/claude-unity-devkit:code-todo` on a small
   change to confirm the chain. Note that teammates are prompted to install on folder-trust.

Stop and ask rather than guessing this repo's domain boundaries, project path, or conventions.
