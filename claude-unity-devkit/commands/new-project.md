---
description: Scaffold a fresh Unity project skeleton without the Unity Editor and wire it to the claude-unity-devkit (packages, Git LFS, asmdefs, settings, CLAUDE.md conventions + orchestration, agents)
argument-hint: [new project directory name]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(pwd), Bash(ls *), Bash(git status *), WebFetch
disable-model-invocation: true
---

# New project

Scaffold a brand-new Unity project skeleton and wire it to the claude-unity-devkit so the team's
orchestration, code-todo, ship, CI, and deploy workflows work from day one. The Unity Editor is NOT
launched — Unity Hub finishes initialization on first open. Treat $ARGUMENTS as the new project
directory name. You (the central thread) own the sequence end to end.

Context (gathered for you):
- Here: !`pwd`
- Contents: !`ls -1`

1. **Confirm the target.** $ARGUMENTS is the new directory name. If none was given, ask me for one
   before scaffolding. Refuse if `./<name>` already exists — this command creates a fresh project;
   use `/claude-unity-devkit:add-to-project` to wire an existing repo.

2. **Ask before guessing.** Ask me (one AskUserQuestion round):
   - **Unity version.** Default `6000.3.24f1` (Unity 6.3 LTS, changeset `4e7b9b5b6244`). If I pick a
     different version, look up its changeset with WebFetch
     `https://services.api.unity.com/unity/editor/release/v1/releases?version=<version>&limit=1`
     (field `shortRevision`), and confirm GameCI publishes editor images for it with
     `https://hub.docker.com/v2/repositories/unityci/editor/tags?page_size=100&name=ubuntu-<version>-`
     (CI can't build a version that has no image). If the changeset lookup fails, scaffold without it
     — Unity Hub fills it in on first open.
   - **C# root namespace** (default: PascalCase of the directory name) — it prefixes the asmdefs.
   - **Cinemachine** — include `com.unity.cinemachine` or not (default: not).

3. **Scaffold.** Run the bundled scaffolder (it asks for permission once — approve it):
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold-unity-project.sh" <name> \
     --unity-version <version> [--revision <changeset>] --namespace <Namespace> [--cinemachine] \
     --marketplace brezzy1337/claude-GameCI-devkit
   ```
   It creates `Assets/{Scripts,Scenes,Prefabs,Materials,Tests/EditMode,Tests/PlayMode}`,
   `Packages/manifest.json` (Input System, uGUI + TextMeshPro, Test Framework, IDE packages, the
   built-in modules; Cinemachine if asked), `ProjectSettings/ProjectVersion.txt`, a runtime asmdef plus
   EditMode/PlayMode test asmdefs with smoke tests, `.gitignore`, `.gitattributes` (Git LFS),
   `.editorconfig`, and `.claude/settings.json` enabling this marketplace + plugin so collaborators
   are prompted on folder-trust; then `git init` and `git lfs install --local`. (The plugin's
   `bootstrap.sh` runs the same scaffold from a plain terminal.) Stop and report if it fails.

4. **Generate conventions + orchestration.** Work inside the new project:
   - Use the `unity-project-conventions` skill to author the CLAUDE.md **Unity project conventions**
     section — folder layout, the asmdef map (`Assets/Scripts/**` → `<Namespace>.Runtime`,
     `Assets/Tests/EditMode/**`, `Assets/Tests/PlayMode/**`), ScriptableObject vs MonoBehaviour,
     Input System, Git LFS, serialization and `.meta` rules.
   - Use the `subagent-orchestration` skill to author the **Sub-Agent Orchestration** section and,
     where roles recur, `.claude/agents/` specialists. Domain boundaries are the asmdef folders that
     actually exist — inspect the scaffold; never invent paths.

5. **Confirm the workflows.** Make sure the generated CLAUDE.md references
   `/claude-unity-devkit:code-todo`, `/claude-unity-devkit:ship`, `/claude-unity-devkit:setup-ci`,
   and `/claude-unity-devkit:setup-deploy` so the implement → review → ship chain is ready to use.

6. **Next steps.** Print clear instructions:
   - **Unity Hub → Add → Add project from disk** → select `<name>`. The first open finishes
     initialization: it generates the rest of `ProjectSettings/`, every `.meta` file, and `Library/`.
     Accept the Input System prompt to enable the new input backend (the Editor restarts).
   - Confirm **Edit → Project Settings → Editor**: Asset Serialization = *Force Text*, Version Control
     mode = *Visible Meta Files* (the Unity 6 defaults).
   - Run `"${CLAUDE_PLUGIN_ROOT}/scripts/check-meta-files.sh" --strict`, then make the first commit —
     after the first open, so every asset is committed with its `.meta`.
   - `cd <name>`, run `/reload-plugins`, then `/claude-unity-devkit:setup-ci` for GameCI, and drive the
     first change with `/claude-unity-devkit:code-todo`. Teammates pick up the plugin on folder-trust.

Stop and ask if anything is ambiguous rather than guessing versions, structure, or paths.
