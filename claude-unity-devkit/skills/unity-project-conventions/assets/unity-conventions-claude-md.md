<!--
  Template: the "Unity project conventions" section for a Unity project's CLAUDE.md.
  Replace every `TAILOR:` marker with this repo's verified specifics, then delete the markers.
  Append to an existing CLAUDE.md rather than overwriting it; match its tone. Place it above the
  "Sub-Agent Orchestration" section, whose Domain boundaries point back at the assembly table.
-->

## Unity project conventions

<!-- TAILOR: one line of stack facts, verified from ProjectVersion.txt and Packages/manifest.json. -->
Unity 6000.3.24f1 (Unity 6.3 LTS) · URP · Input System · uGUI · Unity Test Framework.
The Unity project root is `.` (the folder that holds `Assets/`, `Packages/`, `ProjectSettings/`).

### Folder layout

<!-- TAILOR: the layout this repo actually uses. Delete lines that don't exist. -->
- `Assets/Scripts/<Domain>/` — runtime code, one assembly definition per domain folder.
- `Assets/Editor/` — editor-only tooling (Editor-only asmdef).
- `Assets/Tests/EditMode/`, `Assets/Tests/PlayMode/` — test assemblies.
- `Assets/Scenes/`, `Assets/Prefabs/`, `Assets/Materials/`, `Assets/Art/`, `Assets/Settings/`
  (render pipeline assets, `.inputactions`).
- `Assets/ThirdParty/` — vendored and Asset Store content. Never refactor it; never a routing domain.
- No code in the `Assets/` root. No new content in `Resources/` — use serialized references or
  Addressables.

### Assemblies (domain map)

<!-- TAILOR: one row per real asmdef (and its .asmref folders). Globs must not overlap. -->
| Assembly | Owns | References | Notes |
| --- | --- | --- | --- |
| `Game.Runtime` | `Assets/Scripts/**` | `Unity.InputSystem` | runtime gameplay |
| `Game.Tests.EditMode` | `Assets/Tests/EditMode/**` | `Game.Runtime`, test runner | Editor-only |
| `Game.Tests.PlayMode` | `Assets/Tests/PlayMode/**` | `Game.Runtime`, test runner | |

<!-- TAILOR: the allowed dependency direction for THIS repo. -->
Dependency direction: Runtime ← Tests (and Core ← Gameplay ← UI once those assemblies exist).
Never add a reference that points the other way or sideways between features — add an interface in
the lower assembly instead. Runtime assemblies never use `UnityEditor` outside `#if UNITY_EDITOR`.
New runtime code goes into an existing assembly's folder; a new asmdef is an architecture change
that gets its own reviewed PR.

**Single-owner files** (never edited by two agents in parallel): `ProjectSettings/**`,
`Packages/manifest.json`, `Packages/packages-lock.json`, and shared scenes/prefabs.

### Code rules

- Game rules and calculations live in **plain C# classes** (EditMode-testable). **MonoBehaviours**
  stay thin: lifecycle, references, physics callbacks, presentation. **ScriptableObjects** hold shared
  data/config, event channels, and stateless services — never mutable runtime state.
- `[SerializeField] private` fields (`_camelCase`), not public fields. Renaming a serialized field
  requires `[FormerlySerializedAs("oldName")]`. MonoBehaviour/ScriptableObject class name == file name.
- Use `== null` / `if (obj)` on `UnityEngine.Object`; never `?.` or `??` (they skip the destroyed check).
- Input goes through the Input System actions in <!-- TAILOR: path to the .inputactions asset -->
  `Assets/Settings/Input/`; enable maps and subscribe callbacks in `OnEnable`, undo both in
  `OnDisable`. No legacy `UnityEngine.Input` calls.
- Movement, timers, and smoothing scale by `Time.deltaTime`; physics happens in `FixedUpdate`.

### Editor-owned files (never edit by hand)

- `Library/`, `Temp/`, `Logs/`, `obj/`, `UserSettings/` — generated; the devkit hook blocks writes.
- `.meta` files — change only together with their asset; every new asset is committed with its
  `.meta`; never reuse or invent a GUID by copying.
- Scene and prefab YAML (`.unity`, `.prefab`) — structural changes are Editor work; implementers
  report them as "Editor follow-ups" instead of hand-editing.
- `ProjectSettings/*.asset` — change through Project Settings in the Editor, in a dedicated PR.

### Version control

- Git LFS stores binary assets (`.gitattributes`). After cloning, run `git lfs install --local`.
- Asset Serialization Mode is **Force Text** and Version Control Mode is **Visible Meta Files**
  <!-- TAILOR: "(verified in ProjectSettings on YYYY-MM-DD)" -->.
- Scene/prefab merges use UnityYAMLMerge (setup commands in `.gitattributes`).
- No secrets in the repo or in any asset that ships: license files, keystores, API keys.

### Verify commands

<!-- TAILOR: the real commands. If no local Editor is available, say that GameCI is the test gate. -->
- Format: `dotnet format whitespace . --folder --include Assets --verify-no-changes`
  (or `scripts/format-csharp.sh --check` from the claude-unity-devkit plugin)
- Meta files: `scripts/check-meta-files.sh --tracked --strict` (claude-unity-devkit plugin)
- Tests (local Editor): `"$UNITY_EDITOR" -batchmode -nographics -projectPath . -runTests
  -testPlatform EditMode -testResults Logs/editmode-results.xml -logFile -` (then `PlayMode`).
  Don't add `-quit` — `-runTests` exits on its own. Close the Editor on this project first.
- Tests (CI): the GameCI **Test** workflow runs EditMode + PlayMode on every PR.
