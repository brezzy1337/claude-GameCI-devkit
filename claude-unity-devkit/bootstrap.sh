#!/usr/bin/env bash
#
# bootstrap.sh — one-shot scaffolder for a Unity project wired to the claude-unity-devkit
# Claude Code plugin marketplace. Runs the same scaffold as /claude-unity-devkit:new-project,
# from a plain terminal, without the Unity Editor.
#
# Usage:
#   ./bootstrap.sh <project-name> <marketplace-repo>
#   e.g.  ./bootstrap.sh my-game your-org/claude-unity-devkit
#
# Optional environment:
#   UNITY_VERSION    editor version for ProjectVersion.txt (default: 6000.3.24f1, Unity 6.3 LTS)
#   UNITY_REVISION   changeset for UNITY_VERSION (default matches the default version; leave unset
#                    for another version and Unity Hub fills it in on first open)
#   UNITY_NAMESPACE  C# root namespace (default: PascalCase of <project-name>)
#   CINEMACHINE=1    also add com.unity.cinemachine to Packages/manifest.json
#
# Run it from a clone of the devkit repo: it copies files from the sibling templates/ folder.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ./bootstrap.sh <project-name> <marketplace-repo>

  <project-name>      Name of the new Unity project directory to create (must not exist).
  <marketplace-repo>  GitHub marketplace repo in "owner/name" form.

Example:
  ./bootstrap.sh my-game your-org/claude-unity-devkit
EOF
  exit 1
}

# Phase 1: Argument validation
if [[ "$#" -ne 2 ]]; then
  echo "Error: expected exactly 2 arguments, got $#." >&2
  usage
fi

PROJECT_NAME="$1"
MARKETPLACE_REPO="$2"

if [[ -z "$PROJECT_NAME" ]]; then
  echo "Error: project name must not be empty." >&2
  usage
fi

if [[ ! "$MARKETPLACE_REPO" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  echo "Error: marketplace repo '$MARKETPLACE_REPO' is not of the form 'owner/name'." >&2
  usage
fi

TARGET_DIR="./$PROJECT_NAME"
if [[ -e "$TARGET_DIR" ]]; then
  echo "Error: target directory '$TARGET_DIR' already exists. Refusing to overwrite." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="$SCRIPT_DIR/scripts/scaffold-unity-project.sh"
if [[ ! -f "$SCAFFOLD" || ! -d "$SCRIPT_DIR/templates/project" ]]; then
  echo "Error: $SCAFFOLD or templates/ not found next to bootstrap.sh." >&2
  echo "       Run bootstrap.sh from a clone of the claude-unity-devkit repo." >&2
  exit 1
fi

echo "==> claude-unity-devkit bootstrap"
echo "    project          : $PROJECT_NAME"
echo "    marketplace repo : $MARKETPLACE_REPO"

# Phase 2: Scaffold the Unity project skeleton + wire the marketplace (.claude/settings.json)
SCAFFOLD_ARGS=("$TARGET_DIR" --marketplace "$MARKETPLACE_REPO")
[[ -n "${UNITY_VERSION:-}" ]] && SCAFFOLD_ARGS+=(--unity-version "$UNITY_VERSION")
[[ -n "${UNITY_REVISION+set}" && -n "${UNITY_VERSION:-}" ]] && SCAFFOLD_ARGS+=(--revision "$UNITY_REVISION")
[[ -n "${UNITY_NAMESPACE:-}" ]] && SCAFFOLD_ARGS+=(--namespace "$UNITY_NAMESPACE")
[[ "${CINEMACHINE:-0}" == 1 ]] && SCAFFOLD_ARGS+=(--cinemachine)

bash "$SCAFFOLD" "${SCAFFOLD_ARGS[@]}"

# Phase 3: Next steps
echo ""
echo "============================================================"
echo " Done. Your Unity project skeleton is ready."
echo "============================================================"
echo ""
echo " Next steps:"
echo "   1. Unity Hub -> Add -> Add project from disk -> select $PROJECT_NAME"
echo "      (first open generates ProjectSettings/ and every .meta file; accept the"
echo "       Input System prompt to enable the new input backend and restart)."
echo "   2. cd $PROJECT_NAME && git add -A && git commit -m 'Initial Unity project'"
echo "      (commit AFTER the first open so the .meta files go in with their assets)."
echo "   3. Open Claude Code in this directory and run:"
echo "        /claude-unity-devkit:add-to-project   # CLAUDE.md orchestration + agents"
echo "        /claude-unity-devkit:setup-ci         # GameCI test + build workflows"
echo ""
echo " Note: teammates who open this folder will be prompted to install"
echo "       the claude-unity-devkit marketplace + plugin on folder-trust"
echo "       (wired via .claude/settings.json)."
echo ""
