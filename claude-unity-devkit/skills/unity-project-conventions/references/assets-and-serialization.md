# Assets, serialization, and version control

The reasons behind the Unity hygiene rules in CLAUDE.md, plus the procedures (minimal `.meta` files,
LFS migration, smart merge) an agent needs when the Editor isn't available.

## Contents
- Force Text and Visible Meta Files
- What a .meta file is, and the rules that follow
- Minimal .meta templates (when no Editor is available)
- Git LFS
- Smart merge for scenes and prefabs
- ProjectSettings, Packages, and UserSettings

## Force Text and Visible Meta Files

- **Asset Serialization Mode = Force Text** stores scenes, prefabs, materials, and other assets as
  YAML. Text assets diff, merge (with UnityYAMLMerge), and review; binary ones don't. Check:
  `grep m_SerializationMode ProjectSettings/EditorSettings.asset` → `m_SerializationMode: 2`.
- **Version Control Mode = Visible Meta Files** writes a `.meta` next to every asset so git can track
  it. Check: `grep m_Mode ProjectSettings/VersionControlSettings.asset` → `m_Mode: Visible Meta Files`.
- Both are defaults for new projects and are changed only in the Editor (Project Settings → Editor).
  Switching serialization mode re-serializes every asset — a huge one-off diff that deserves its own PR.
- Some assets stay binary even under Force Text (e.g. `LightingData.asset`, terrain heightmaps); the
  devkit `.gitattributes` routes the known ones through LFS.

## What a .meta file is, and the rules that follow

A `.meta` holds the asset's **GUID** and its **importer settings**. Scenes, prefabs, and materials
reference other assets by GUID (`{fileID: 11500000, guid: 28055e20…, type: 3}` for a script). So:

- **Commit every `.meta` with its asset.** An asset pushed without its `.meta` gets a new random GUID
  on every other machine, and every reference to it breaks ("Missing (Mono Script)", pink materials).
- **Never hand-edit a GUID; never copy a `.meta` to make a new asset.** Two assets with one GUID make
  Unity reassign one of them and break whatever pointed at it.
- **Move, rename, and delete the asset and its `.meta` together** — in the Editor, or `git mv` both
  files. A `.meta` left behind is an orphan; Unity deletes it and the GUID is gone for good.
- **Folders have `.meta` files too.** Git can't track empty folders, so an empty folder's `.meta`
  becomes an orphan on other machines — put a `.gitkeep` in folders that must exist (Unity ignores
  dot-files, so it gets no `.meta`).
- **Importer settings live in the `.meta`.** Changing a texture's compression or a model's import
  scale changes the `.meta`, not the asset — that's the one legitimate `.meta`-only change, and it's
  Editor work.
- `scripts/check-meta-files.sh` (plugin) finds assets without a `.meta` and orphaned `.meta` files;
  `--tracked` checks what git will actually deliver. The plugin's `PreToolUse` hook blocks `.meta`
  edits whose asset isn't part of the change.

## Minimal .meta templates (when no Editor is available)

Prefer letting the Editor generate `.meta` files. When an agent must create new assets without an
Editor (so the change is complete and GUIDs are stable from the first commit), write a `.meta` with a
**fresh** GUID — 32 lowercase hex characters:

```bash
python3 -c "import uuid; print(uuid.uuid4().hex)"
```

These are the formats Unity 6.3 writes. Unity re-imports and may rewrite the importer block on first
open; commit that rewrite.

**C# script** (`Foo.cs.meta`):
```yaml
fileFormatVersion: 2
guid: <fresh-guid>
MonoImporter:
  externalObjects: {}
  serializedVersion: 2
  defaultReferences: []
  executionOrder: 0
  icon: {instanceID: 0}
  userData: 
  assetBundleName: 
  assetBundleVariant: 
```

**Assembly definition** (`Game.Runtime.asmdef.meta`):
```yaml
fileFormatVersion: 2
guid: <fresh-guid>
AssemblyDefinitionImporter:
  externalObjects: {}
  userData: 
  assetBundleName: 
  assetBundleVariant: 
```

**Folder** (`Scripts.meta`, next to the `Scripts/` folder):
```yaml
fileFormatVersion: 2
guid: <fresh-guid>
folderAsset: yes
DefaultImporter:
  externalObjects: {}
  userData: 
  assetBundleName: 
  assetBundleVariant: 
```

Note the trailing space after `userData:`, `assetBundleName:`, and `assetBundleVariant:` — Unity
writes it; keeping it avoids a spurious diff when the Editor re-saves the file. For other asset types
(textures, models, audio), don't hand-write importer settings — report the `.meta` as an Editor
follow-up.

## Git LFS

- **What goes in LFS:** binary assets that don't diff — textures, PSD/PSB, models, audio, video,
  fonts, native plugins and DLLs, archives (the devkit `.gitattributes` lists them). YAML assets,
  code, and `.meta` files stay in git.
- **Per clone:** `git lfs install --local` (installs the hooks for this repo only).
- **Verify a path is routed:** `git check-attr filter -- Assets/Art/hero.png` → `filter: lfs`.
  `git lfs ls-files` lists what is actually stored in LFS.
- **Binaries already committed outside LFS** stay in history even after `.gitattributes` changes.
  Moving them needs `git lfs migrate import --include="*.png,*.fbx,…" --everything`, which **rewrites
  history** — every clone must re-clone, open PRs need rebasing. Coordinate with the team; never run it
  unasked. Going forward-only (`git lfs migrate import --no-rewrite`) is the non-disruptive alternative.
- **CI:** `actions/checkout` with `lfs: true`; otherwise builds import pointer text files. GitHub
  meters LFS storage and bandwidth, so large teams often cache `.git/lfs` in CI.
- **Locking** (`git lfs lock`) helps for large binary art that can't be merged; mark those patterns
  `lockable` in `.gitattributes` if the team wants it.

## Smart merge for scenes and prefabs

Even as text, scene and prefab YAML merges badly with a line-based merge. Unity ships
**UnityYAMLMerge** (in the Editor's `Data/Tools/`), which merges by object. The devkit
`.gitattributes` marks Unity YAML with `merge=unityyamlmerge`; each developer registers the driver
once (commands in the file's header). Even with it, avoid two people (or two agents) editing the same
scene or prefab at once — that's why shared scenes and prefabs are single-owner in the domain map.
Prefer prefabs and nested prefabs over large monolithic scenes to shrink the conflict surface.

## ProjectSettings, Packages, and UserSettings

- **`ProjectSettings/`** is committed. It affects every build and every teammate (physics layers,
  quality, player settings, input handling, tags and layers). Changes happen in the Editor, get their
  own review, and never ride along in a feature PR by accident.
- **`ProjectSettings/ProjectVersion.txt`** changes only through an Editor upgrade — done in a
  dedicated PR, because the upgrade also re-serializes assets and bumps packages.
- **`Packages/manifest.json`** is the dependency list; **`Packages/packages-lock.json`** records the
  resolved versions and git hashes — commit both. Changes go through `dependency-auditor`.
- **`UserSettings/`** holds per-user Editor state — gitignored, never committed.
- **No secrets in any of these** — settings assets, ScriptableObjects, and `StreamingAssets` all ship
  inside the player build.
