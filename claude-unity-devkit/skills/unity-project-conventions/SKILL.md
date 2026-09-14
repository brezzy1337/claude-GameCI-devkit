---
name: unity-project-conventions
description: >-
  Author the Unity section of a project's CLAUDE.md and its repo hygiene files — the folder layout
  under Assets/, assembly definitions as the domain boundaries for sub-agent routing, ScriptableObject
  vs MonoBehaviour guidance, Input System usage, .gitignore and Git LFS rules, an .editorconfig for C#,
  and ProjectSettings hygiene (Force Text serialization, Visible Meta Files). Use this skill whenever
  the user wants to set up, document, audit, or fix the conventions of a Unity repo, onboard Claude
  Code to a Unity project, or asks why scene and prefab merges keep breaking, why references go
  missing after a pull, or how to lay out Assets/ and asmdefs. Pairs with subagent-orchestration,
  which turns the asmdef map produced here into routing rules.
---

# Unity project conventions

## The idea

CLAUDE.md is where the central thread and every custom sub-agent learn how *this* repo works.
Unity has failure modes that generic code conventions never mention: assets are serialized YAML
that merges badly, every asset's identity is a GUID in a `.meta` file, several folders are owned by
the Editor, and assembly definitions are hard compile boundaries. An agent that doesn't know these
rules will hand-edit a `.meta`, drop a script into `Assembly-CSharp`, or rename a serialized field
and silently wipe data in fifty prefabs.

This skill writes those rules down concretely for the repo in front of you, and ships the hygiene
files (`.gitignore`, `.gitattributes`, `.editorconfig`) that enforce what can be enforced. The
plugin's `PreToolUse` hook (`scripts/guard-unity-paths.sh`) is the deterministic backstop for the
two worst mistakes — writes under `Library/`/`Temp/`/`Logs/`, and `.meta` edits without their
asset — so CLAUDE.md can focus on judgment calls.

## What you produce

1. **A CLAUDE.md "Unity project conventions" section** — start from
   `assets/unity-conventions-claude-md.md` and replace every `TAILOR` marker.
2. **Hygiene files at the Unity project root** (the folder holding `Assets/`) — `assets/.gitignore`,
   `assets/.gitattributes`, `assets/.editorconfig`. Merge into existing files; never replace a
   team's file wholesale.
3. **Optionally, asmdef proposals** — when code lives outside any assembly definition, propose the
   split (see `references/asmdef-routing.md`). Proposals only: adding asmdefs changes the compile
   graph and is a deliberate change to make through `/claude-unity-devkit:code-todo`, not a side
   effect of documenting conventions. `assets/Runtime.asmdef` is the runtime template the scaffolder
   uses.

## Step 1 — Inspect first (do not skip)

Never document a layout you haven't seen. Gather:

- **Editor version** — `ProjectSettings/ProjectVersion.txt` (`m_EditorVersion`).
- **Assemblies** — `find . -name '*.asmdef' -not -path '*/Library/*'` plus any `.asmref` files; read
  each one's `name`, `references`, `includePlatforms`, `defineConstraints`.
- **Layout** — the top two levels under `Assets/`, embedded packages in `Packages/`, third-party and
  Asset Store folders, where scenes/prefabs/settings assets live.
- **Stack** — `Packages/manifest.json`: render pipeline (URP/HDRP/Built-in), Input System, netcode
  (Netcode for GameObjects, Mirror, Fish-Net, …), UI (uGUI/UI Toolkit), Addressables, test framework.
- **Serialization and meta settings** — `ProjectSettings/EditorSettings.asset` should contain
  `m_SerializationMode: 2` (Force Text); `ProjectSettings/VersionControlSettings.asset` should contain
  `m_Mode: Visible Meta Files`. Both are the defaults for new projects.
- **Git hygiene** — is there a `.gitignore` covering `Library/`, `Temp/`, `Logs/`, `obj/`,
  `UserSettings/`? Does `.gitattributes` route binaries through LFS (`git check-attr filter -- <some
  .png>` prints `lfs`)? Are large binaries already committed outside LFS
  (`git ls-files -- '*.png' '*.fbx' '*.wav' | head` then `git lfs ls-files`)? Run
  `"${CLAUDE_PLUGIN_ROOT}/scripts/check-meta-files.sh" --tracked`.
- **Existing CLAUDE.md, `.editorconfig`, CONTRIBUTING** — match their tone; append, don't duplicate.
- **How tests run** — is there a local Editor path the team uses for batchmode, or is GameCI the
  only test runner?

If you can't read the repo, ask for the layout, the asmdef list, and the Unity version — and mark
every placeholder you couldn't verify.

## Step 2 — Folder layout

Document the layout the repo actually uses. For a new project, recommend this (it is what
`/claude-unity-devkit:new-project` scaffolds):

```
Assets/
  Scripts/            runtime code; one asmdef per domain folder (Scripts/Core, Scripts/Gameplay, …)
  Editor/             editor-only code (an asmdef with includePlatforms ["Editor"])
  Tests/EditMode/     EditMode test asmdef
  Tests/PlayMode/     PlayMode test asmdef
  Scenes/  Prefabs/  Materials/  Art/{Models,Textures,Audio}/  Settings/ (pipeline assets, input actions)
  ThirdParty/         vendored + Asset Store content — never a routing domain, never refactored
```

Rules worth stating: no code in the `Assets/` root; avoid `Resources/` for new content (everything in
it ships in every build and is indexed at startup — prefer serialized references or Addressables);
know Unity's special folder names (`Editor`, `Plugins`, `StreamingAssets`, `Gizmos`,
`Editor Default Resources`) and that names starting with `.` or ending with `~` are not imported.

## Step 3 — Assembly definitions are the domain map

In a Unity repo the asmdef graph *is* the architecture, and it gives routing clean, compiler-enforced
boundaries: two agents working in two assemblies' folders can't collide on files, and the reference
direction tells you which change must land first. Build the map with
`references/asmdef-routing.md` and put it in CLAUDE.md as a table (assembly, glob it owns,
references, notes). State the allowed dependency direction explicitly (e.g. Core ← Gameplay ← UI;
Runtime ← Editor; Runtime ← Tests) and the rules:

- New runtime code goes into an existing assembly's folder; a new assembly is an architecture change.
- Runtime assemblies never reference Editor assemblies or use `UnityEditor` outside `#if UNITY_EDITOR`.
- Test assemblies use `defineConstraints: ["UNITY_INCLUDE_TESTS"]`, `overrideReferences: true` with
  `nunit.framework.dll`, and are never referenced by runtime code (see the `unity-testing` skill).
- Code with no asmdef compiles into `Assembly-CSharp`: treat it as one shared, sequential domain.
- `ProjectSettings/**`, `Packages/manifest.json`, and shared scenes/prefabs are **single-owner**:
  never split across parallel agents.

## Step 4 — ScriptableObject vs MonoBehaviour (and plain C#)

Write the repo's version of this guidance into CLAUDE.md:

- **Plain C# classes** hold game rules and calculations — they are testable in EditMode and have no
  lifecycle surprises. Prefer them for logic.
- **MonoBehaviours** live on GameObjects in scenes and prefabs; they own lifecycle, transforms,
  physics callbacks, and presentation. Keep them thin: gather input and references, call plain C#
  logic, present the result. One responsibility per component.
- **ScriptableObjects** are assets for shared data and configuration (weapon stats, level
  definitions, tuning), event channels, and stateless strategies/services that designers wire in the
  inspector. **Don't store mutable runtime state on ScriptableObject assets**: changes made in Play
  Mode persist in the Editor, and every user of the asset shares them. Copy to a runtime object
  (`Instantiate` the SO or map to a plain class) when state must change.
- **Serialization rules** — `[SerializeField] private` over public fields; renaming a serialized
  field needs `[FormerlySerializedAs("old")]`; MonoBehaviour/ScriptableObject class name == file name;
  no constructors for Unity objects (use `Awake`/`OnEnable`/`Init`); `?.` and `??` bypass Unity's
  destroyed-object check — use `== null` on `UnityEngine.Object`.

## Step 5 — Input System

For projects on `com.unity.inputsystem`: Active Input Handling (Project Settings → Player) is
"Input System Package (New)" — or "Both" only during a migration; actions live in an
`.inputactions` asset (e.g. `Assets/Settings/Input/`) used through a generated C# class or
`PlayerInput`; action maps are enabled/disabled with their owner's `OnEnable`/`OnDisable`, and every
callback subscription is unsubscribed; continuous values are read in `Update` and consumed in
`FixedUpdate`; new code never calls the legacy `UnityEngine.Input` API (it throws when legacy input
is disabled).

## Step 6 — Version-control and ProjectSettings hygiene

Details and the reasons behind each rule are in `references/assets-and-serialization.md`. Cover:

- **`.gitignore`** — Editor-generated folders and IDE files (`assets/.gitignore` is GitHub's
  Unity.gitignore plus license/keystore/secret patterns).
- **Git LFS** — binaries (`*.png`, `*.psd`, `*.fbx`, `*.wav`, `*.mp4`, fonts, native plugins, …) via
  `assets/.gitattributes`; every clone runs `git lfs install --local`; CI checks out with
  `lfs: true`. Moving existing binaries into LFS (`git lfs migrate import`) rewrites history —
  coordinate with the team; never do it unasked.
- **Smart merge** — `.gitattributes` marks Unity YAML `merge=unityyamlmerge`; each developer
  registers UnityYAMLMerge once (the commands are in the file's header).
- **`.meta` files** — committed with their asset, never hand-edited, never with a reused GUID; empty
  folders get no `.meta` in git (use `.gitkeep`, which Unity ignores).
- **ProjectSettings** — Force Text and Visible Meta Files are set in the Editor (Project Settings →
  Editor), never by editing the YAML. `ProjectSettings/` changes affect every build and every
  teammate: single owner, reviewed on their own. Editor upgrades (`ProjectVersion.txt` changes) go
  in a dedicated PR. No secrets in any settings asset — they ship in the build.
- **`.editorconfig`** — `assets/.editorconfig` sets C# layout/naming and silences analyzers that
  misread Unity idioms (unused Unity messages, `[SerializeField]` fields, `?.` on Unity objects);
  it also tells editors never to reformat Unity YAML.

## Step 7 — Write the CLAUDE.md section

Copy `assets/unity-conventions-claude-md.md`, replace every `TAILOR` marker with verified values,
delete examples that don't apply, and append it to CLAUDE.md (above the orchestration section if that
already exists — the orchestration section's domain boundaries point back at the asmdef table).
Include the verify commands the implementer and `/ship` preflight will run.

## Step 8 — Verify

- Every glob and assembly in the table exists (`find` matches), and no two domain globs overlap.
- `check-meta-files.sh --tracked` is clean, or its findings are listed as a known follow-up.
- `git check-attr filter -- Assets/any.png` prints `filter: lfs` after the `.gitattributes` merge.
- The serialization and meta-file modes were read from the settings files, not assumed.
- No TAILOR markers remain; nothing invented.

## Grounding notes

- CLAUDE.md rules are guidance the central thread and custom sub-agents read, not enforcement. The
  hook, `.gitattributes`, and CI (`check-meta-files.sh --tracked --strict` in preflight) are the
  enforcement layer.
- Force Text and Visible Meta Files are the defaults for new projects, but old projects and some
  templates differ — read the settings, don't assume.
- Don't oversell asmdefs: they speed up iteration and give clean boundaries, but splitting an
  existing `Assembly-CSharp` project is real refactoring work with broken references to fix.
