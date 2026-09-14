#!/usr/bin/env bash
# scaffold-unity-project.sh — create a Unity project skeleton WITHOUT launching the Unity Editor.
# Part of claude-unity-devkit; used by /claude-unity-devkit:new-project and bootstrap.sh.
#
# Usage:
#   scaffold-unity-project.sh <target-dir> [options]
#
# Options:
#   --unity-version <v>     editor version for ProjectVersion.txt   (default 6000.3.24f1)
#   --revision <hash>       editor changeset for that version        (default 4e7b9b5b6244;
#                           pass "" to omit the m_EditorVersionWithRevision line)
#   --namespace <Name>      C# root namespace / asmdef prefix        (default: PascalCase dir name)
#   --cinemachine           add com.unity.cinemachine to Packages/manifest.json
#   --marketplace <o/r>     write .claude/settings.json enabling the devkit from GitHub repo o/r
#   --no-git                skip `git init` and `git lfs install --local`
#
# Creates Assets/{Scripts,Scenes,Prefabs,Materials,Tests/{EditMode,PlayMode}}, Packages/manifest.json,
# ProjectSettings/ProjectVersion.txt, asmdefs + smoke tests, .gitignore, .gitattributes (LFS),
# .editorconfig. Unity generates the rest of ProjectSettings/ and every .meta on first open.
set -euo pipefail

DEFAULT_UNITY_VERSION="6000.3.24f1"
DEFAULT_UNITY_REVISION="4e7b9b5b6244"
CINEMACHINE_VERSION="3.1.7"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates/project"

usage() {
  sed -n '5,17p' "$0" >&2
  exit 1
}

die() {
  echo "scaffold: $*" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
TARGET="$1"
shift

UNITY_VERSION="$DEFAULT_UNITY_VERSION"
UNITY_REVISION="$DEFAULT_UNITY_REVISION"
REVISION_SET=0
NAMESPACE=""
CINEMACHINE=0
MARKETPLACE=""
GIT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unity-version) UNITY_VERSION="${2:?--unity-version needs a value}"; shift 2 ;;
    --revision) UNITY_REVISION="${2-}"; REVISION_SET=1; shift 2 ;;
    --namespace) NAMESPACE="${2:?--namespace needs a value}"; shift 2 ;;
    --cinemachine) CINEMACHINE=1; shift ;;
    --marketplace) MARKETPLACE="${2:?--marketplace needs owner/repo}"; shift 2 ;;
    --no-git) GIT=0; shift ;;
    -h | --help) usage ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -d "$TEMPLATES" ]] || die "templates not found at $TEMPLATES — run this from a clone of the claude-unity-devkit repo"
[[ -e "$TARGET" ]] && die "'$TARGET' already exists; refusing to overwrite (use /claude-unity-devkit:add-to-project for existing repos)"
[[ "$UNITY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[abfp][0-9]+$ ]] || die "'$UNITY_VERSION' does not look like a Unity version (e.g. 6000.3.24f1)"
if [[ -n "$MARKETPLACE" && ! "$MARKETPLACE" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  die "marketplace '$MARKETPLACE' is not of the form owner/repo"
fi
# A revision only makes sense for the version it belongs to.
if [[ "$UNITY_VERSION" != "$DEFAULT_UNITY_VERSION" && $REVISION_SET -eq 0 ]]; then
  UNITY_REVISION=""
fi

if [[ -z "$NAMESPACE" ]]; then
  NAMESPACE="$(basename "$TARGET" | awk -F '[^A-Za-z0-9]+' '{
    out = ""
    for (i = 1; i <= NF; i++) if ($i != "") out = out toupper(substr($i, 1, 1)) substr($i, 2)
    print out
  }')"
  [[ "$NAMESPACE" =~ ^[0-9] ]] && NAMESPACE="Game$NAMESPACE"
  [[ -n "$NAMESPACE" ]] || NAMESPACE="Game"
fi
[[ "$NAMESPACE" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] || die "namespace '$NAMESPACE' is not a valid C# namespace"

echo "==> Scaffolding Unity project in $TARGET"
echo "    unity     : $UNITY_VERSION${UNITY_REVISION:+ ($UNITY_REVISION)}"
echo "    namespace : $NAMESPACE"

mkdir -p "$TARGET"
cd "$TARGET"

mkdir -p Assets/Scripts Assets/Scenes Assets/Prefabs Assets/Materials \
  Assets/Tests/EditMode Assets/Tests/PlayMode Packages ProjectSettings
# Unity skips dot-files, so .gitkeep keeps empty folders in git without generating a .meta.
for keep in Assets/Scenes Assets/Prefabs Assets/Materials; do
  : >"$keep/.gitkeep"
done

cp "$TEMPLATES/.gitignore" .gitignore
cp "$TEMPLATES/.gitattributes" .gitattributes
cp "$TEMPLATES/.editorconfig" .editorconfig

if [[ $CINEMACHINE -eq 1 ]]; then
  awk -v line="    \"com.unity.cinemachine\": \"$CINEMACHINE_VERSION\"," '
    { print }
    /"com.unity.inputsystem"/ { print line }
  ' "$TEMPLATES/manifest.json" >Packages/manifest.json
else
  cp "$TEMPLATES/manifest.json" Packages/manifest.json
fi

{
  echo "m_EditorVersion: $UNITY_VERSION"
  [[ -n "$UNITY_REVISION" ]] && echo "m_EditorVersionWithRevision: $UNITY_VERSION ($UNITY_REVISION)"
} >ProjectSettings/ProjectVersion.txt

render() { # render <template> <dest>
  sed "s/__NAMESPACE__/$NAMESPACE/g" "$1" >"$2"
}
render "$TEMPLATES/asmdef/Runtime.asmdef" "Assets/Scripts/$NAMESPACE.Runtime.asmdef"
render "$TEMPLATES/asmdef/Tests.EditMode.asmdef" "Assets/Tests/EditMode/$NAMESPACE.Tests.EditMode.asmdef"
render "$TEMPLATES/asmdef/Tests.PlayMode.asmdef" "Assets/Tests/PlayMode/$NAMESPACE.Tests.PlayMode.asmdef"
render "$TEMPLATES/tests/EditModeSmokeTests.cs" "Assets/Tests/EditMode/SmokeTests.cs"
render "$TEMPLATES/tests/PlayModeSmokeTests.cs" "Assets/Tests/PlayMode/SmokeTests.cs"

if [[ -n "$MARKETPLACE" ]]; then
  mkdir -p .claude
  sed "s#__MARKETPLACE_REPO__#$MARKETPLACE#g" "$TEMPLATES/claude-settings.json" >.claude/settings.json
  echo "    settings  : .claude/settings.json -> marketplace $MARKETPLACE"
fi

if [[ $GIT -eq 1 ]]; then
  if command -v git >/dev/null 2>&1; then
    git init -q -b main 2>/dev/null || git init -q
    if git lfs version >/dev/null 2>&1; then
      git lfs install --local >/dev/null
      echo "    git       : initialized, Git LFS hooks installed (local)"
    else
      echo "    git       : initialized — WARNING: git-lfs not found; install it before committing binary assets" >&2
    fi
  else
    echo "    git       : not found, skipped" >&2
  fi
fi

echo "==> Scaffold complete: $(pwd)"
