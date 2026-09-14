#!/usr/bin/env bash
# format-csharp.sh — format a Unity project's C# with `dotnet format`, if the .NET SDK is present.
# Part of claude-unity-devkit.
#
# Usage:
#   format-csharp.sh [--check] [unity-project-dir]
#
#   --check  verify only; exit non-zero if any file would change (use in preflight / CI)
#
# Runs `dotnet format whitespace --folder`, which needs no .csproj/.sln (Unity generates those and
# they are gitignored) and applies the project's .editorconfig to Assets/ and embedded packages.
# Style and analyzer fixes need a real project file, so they are left to the IDE.
# Without the .NET SDK this is a no-op that says so and exits 0.
set -euo pipefail

usage() {
  sed -n '5,9p' "$0" >&2
  exit 2
}

check=0
dir=""
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    -h | --help) usage ;;
    -*) echo "format-csharp: unknown option $arg" >&2; usage ;;
    *) dir="$arg" ;;
  esac
done

if ! command -v dotnet >/dev/null 2>&1; then
  echo "format-csharp: dotnet not found — skipping C# formatting (install the .NET 8+ SDK to enable it)."
  exit 0
fi
if ! dotnet format --version >/dev/null 2>&1; then
  echo "format-csharp: 'dotnet format' is unavailable in this SDK — skipping (needs .NET 6+ SDK)."
  exit 0
fi

start="${dir:-.}"
if [[ -d "$start/Assets" && -d "$start/ProjectSettings" ]]; then
  root="$(cd "$start" && pwd)"
else
  version_file="$(find "$start" -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print 2>/dev/null | head -n 1)"
  if [[ -z "$version_file" ]]; then
    echo "format-csharp: no Unity project (Assets/ + ProjectSettings/) found under '$start'" >&2
    exit 2
  fi
  root="$(cd "$(dirname "$version_file")/.." && pwd)"
fi

# Folder includes need the trailing slash: `--include Assets` silently matches nothing.
includes=(Assets/)
for pkg in "$root"/Packages/*/; do
  [[ -d "$pkg" ]] && includes+=("Packages/$(basename "$pkg")/")
done

args=(format whitespace "$root" --folder --include "${includes[@]}")
[[ $check -eq 1 ]] && args+=(--verify-no-changes)

echo "format-csharp: dotnet ${args[*]}"
dotnet "${args[@]}"
