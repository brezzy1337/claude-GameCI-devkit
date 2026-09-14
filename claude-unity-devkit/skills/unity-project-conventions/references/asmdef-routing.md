# Assembly definitions as routing domains

How to turn a Unity repo's `.asmdef` files into the domain boundaries and dependency chains that
the `subagent-orchestration` CLAUDE.md section needs. Read this before writing the assembly table.

## Contents
- Why asmdefs make good domains
- Extracting the map
- Resolving GUID references
- Turning the graph into routing rules
- Code outside any asmdef
- Example

## Why asmdefs make good domains

An assembly definition owns every script in its folder and below it, except subfolders that have
their own `.asmdef` (and plus any folder that contains an `.asmref` pointing at it). That gives three
properties routing needs:

- **Non-overlapping file sets.** Two agents in two assemblies' folders can't edit the same `.cs` file.
- **A compiler-checked dependency graph.** `references` says which assembly may use which. A cycle is
  a compile error, so the graph is always a DAG — a ready-made sequential order.
- **Fast feedback.** Changing a leaf assembly only recompiles it and its dependents.

What asmdefs don't isolate: scenes, prefabs, ScriptableObject assets, `ProjectSettings/`, and
`Packages/manifest.json`. Those are shared serialized files — single-owner, never parallel.

## Extracting the map

```bash
# Every assembly definition and reference outside generated folders
find . \( -name '*.asmdef' -o -name '*.asmref' \) -not -path '*/Library/*' -not -path './.git/*'

# name, references, and platforms for each asmdef (needs jq)
for f in $(find . -name '*.asmdef' -not -path '*/Library/*'); do
  jq -r --arg f "$f" '[$f, .name, (.references // [] | join(",")), (.includePlatforms // [] | join(","))] | @tsv' "$f"
done
```

For each asmdef record:

| Field | Where from | Use |
| --- | --- | --- |
| Name | `name` | the domain's label and what others reference |
| Owns | folder of the `.asmdef` → `<folder>/**`, minus nested asmdef folders, plus `.asmref` folders | the domain glob |
| References | `references` | dependency edges (this assembly depends on those) |
| Editor-only | `includePlatforms` is `["Editor"]` | never referenced by runtime code |
| Tests | `defineConstraints` contains `UNITY_INCLUDE_TESTS` | test domain for the assembly it references |

Write nested exclusions explicitly in the glob column (e.g. `Assets/Scripts/**` except
`Assets/Scripts/Editor/**`) so a reader never assumes overlap.

## Resolving GUID references

With "Use GUIDs" enabled in the asmdef inspector, `references` entries look like
`"GUID:4307f53044263cf4b835bd812fc161a4"`. Map each GUID to its asmdef via the `.meta` file:

```bash
grep -rl --include='*.asmdef.meta' 'guid: 4307f53044263cf4b835bd812fc161a4' .
```

Unity package assemblies (e.g. `Unity.InputSystem`) resolve to `Library/PackageCache/…`; record them
as external references, not domains.

## Turning the graph into routing rules

- **Domain boundaries** — one domain per project assembly (merge tiny sibling assemblies of one
  feature into a single domain if they always change together). Third-party and Asset Store
  assemblies are excluded.
- **Dependency chains** — topologically sort the project assemblies: a change that touches a
  referenced assembly lands before the assemblies that reference it (Core → Gameplay → UI). A new
  public API in Core is a sequential step even when the consumers are in parallel-safe domains.
- **Tests** — the test assembly for a domain runs after (or with) that domain's change; route test
  edits to the same implementer as the code they cover unless the change is test-only.
- **Editor tooling** — a separate domain; it may reference runtime assemblies, never the reverse.
- **Parallel-safe** — two domains are parallel-safe only if neither references the other (directly
  or transitively) *and* the change doesn't touch shared serialized assets.

## Code outside any asmdef

Scripts not covered by an asmdef compile into `Assembly-CSharp` (and `Assembly-CSharp-Editor` for
`Editor` folders). Treat all of it as **one shared domain**: anything in it can reference anything
else in it, so there are no safe parallel splits inside it. Say so in CLAUDE.md, and — if the user
wants faster iteration and parallel work — propose an asmdef split as a separate, reviewed change.

## Example

```markdown
| Assembly | Owns | References | Notes |
| --- | --- | --- | --- |
| `Studio.Core` | `Assets/Scripts/Core/**` | — | data types, SO definitions, services; `noEngineReferences: false` |
| `Studio.Gameplay` | `Assets/Scripts/Gameplay/**` | `Studio.Core`, `Unity.InputSystem` | player, AI, combat |
| `Studio.UI` | `Assets/Scripts/UI/**` | `Studio.Core`, `Studio.Gameplay` | HUD, menus |
| `Studio.Editor` | `Assets/Editor/**` | `Studio.Core`, `Studio.Gameplay` | Editor-only |
| `Studio.Tests.EditMode` | `Assets/Tests/EditMode/**` | `Studio.Core`, `Studio.Gameplay` | Editor-only tests |
| `Studio.Tests.PlayMode` | `Assets/Tests/PlayMode/**` | `Studio.Gameplay` | player-loop tests |

Chains: Core → Gameplay → UI; Core/Gameplay → Tests.
Parallel-safe pairs: Editor tooling ∥ UI (neither references the other) when no shared assets change.
Single-owner: `ProjectSettings/**`, `Packages/manifest.json`, `Assets/Scenes/**`, `Assets/Prefabs/Shared/**`.
```
