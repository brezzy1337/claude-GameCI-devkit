#!/usr/bin/env bash
# check-meta-files.sh — warn about Unity assets missing a .meta file, and orphaned .meta files.
# Part of claude-unity-devkit.
#
# Usage:
#   check-meta-files.sh [--tracked] [--strict] [unity-project-dir]
#
#   --tracked  check what git tracks (what CI and teammates will get) instead of the working tree
#   --strict   exit 1 when problems are found (for CI); by default it only warns and exits 0
#
# Scans Assets/ and embedded packages (Packages/<name>/). Follows Unity's import rules: names that
# start with "." or end with "~", folders named "cvs", and *.tmp files are ignored (no .meta).
# The project dir defaults to the current directory, or the first ProjectSettings/ProjectVersion.txt
# found within three levels below it.
set -euo pipefail

usage() {
  sed -n '5,14p' "$0" >&2
  exit 2
}

tracked=0
strict=0
dir=""
for arg in "$@"; do
  case "$arg" in
    --tracked) tracked=1 ;;
    --strict) strict=1 ;;
    -h | --help) usage ;;
    -*) echo "check-meta-files: unknown option $arg" >&2; usage ;;
    *) dir="$arg" ;;
  esac
done

find_root() {
  local start="${1:-.}"
  if [[ -d "$start/Assets" && -d "$start/ProjectSettings" ]]; then
    (cd "$start" && pwd)
    return
  fi
  local version_file
  version_file="$(find "$start" -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print 2>/dev/null | head -n 1)"
  [[ -n "$version_file" ]] || return 1
  (cd "$(dirname "$version_file")/.." && pwd)
}

root="$(find_root "${dir:-.}")" || {
  echo "check-meta-files: no Unity project (Assets/ + ProjectSettings/) found under '${dir:-.}'" >&2
  exit 2
}
cd "$root"

scan_roots=(Assets)
[[ -d Packages ]] && scan_roots+=(Packages)

list_entries() {
  if [[ $tracked -eq 1 ]]; then
    git -c core.quotePath=false ls-files -- "${scan_roots[@]}" | awk '{ print "F\t" $0 }'
  else
    find "${scan_roots[@]}" -mindepth 1 \
      \( -name '.*' -o -name '*~' -o -iname cvs -o -name '*.tmp' \) -prune \
      -o -type f -print | awk '{ print "F\t" $0 }'
    find "${scan_roots[@]}" -mindepth 1 \
      \( -name '.*' -o -name '*~' -o -iname cvs -o -name '*.tmp' \) -prune \
      -o -type d -print | awk '{ print "D\t" $0 }'
  fi
}

report="$(list_entries | awk -F '\t' '
  function ignored(p,   n, parts, i, c) {
    n = split(p, parts, "/")
    for (i = 1; i <= n; i++) {
      c = parts[i]
      if (c ~ /^\./ || c ~ /~$/ || tolower(c) == "cvs" || c ~ /\.tmp$/) return 1
    }
    return 0
  }
  {
    kind = $1; p = $2
    # Only Assets/** and Packages/<pkg>/** need metas; Assets/ and the package roots do not.
    if (p !~ /^Assets\// && p !~ /^Packages\/[^\/]+\//) next
    if (kind == "D") { if (!ignored(p)) dirs[p] = 1; next }
    # git lists files only, so derive their folders — including the folder of an ignored file such
    # as .gitkeep, which still needs its own .meta — stopping at the first ignored folder.
    n = split(p, parts, "/")
    depth = (p ~ /^Packages\//) ? 2 : 1
    path = parts[1]
    for (i = 2; i <= depth; i++) path = path "/" parts[i]
    for (i = depth + 1; i < n; i++) {
      c = parts[i]
      if (c ~ /^\./ || c ~ /~$/ || tolower(c) == "cvs") break
      path = path "/" c
      dirs[path] = 1
    }
    if (ignored(p)) next
    files[p] = 1
  }
  END {
    for (p in files) {
      if (p ~ /\.meta$/) {
        a = substr(p, 1, length(p) - 5)
        if (!(a in files) && !(a in dirs)) print "ORPHAN\t" p
      } else if (!((p ".meta") in files)) {
        print "MISSING\t" p
      }
    }
    for (d in dirs) if (!((d ".meta") in files)) print "MISSING\t" d "/"
  }
' | sort)"

missing="$(printf '%s\n' "$report" | awk -F '\t' '$1 == "MISSING" { print "  " $2 }')"
orphans="$(printf '%s\n' "$report" | awk -F '\t' '$1 == "ORPHAN" { print "  " $2 }')"
mode_label="working tree"
[[ $tracked -eq 1 ]] && mode_label="git-tracked files"

if [[ -z "$missing" && -z "$orphans" ]]; then
  echo "check-meta-files: OK — every asset has a .meta and no .meta is orphaned ($mode_label, $root)"
  exit 0
fi

if [[ -n "$missing" ]]; then
  echo "check-meta-files: WARNING — $(printf '%s\n' "$missing" | wc -l | tr -d ' ') asset(s) without a .meta ($mode_label):"
  printf '%s\n' "$missing"
  echo "  Fix: open the project in the Unity Editor so it generates them, then commit the .meta files."
fi
if [[ -n "$orphans" ]]; then
  echo "check-meta-files: WARNING — $(printf '%s\n' "$orphans" | wc -l | tr -d ' ') orphaned .meta file(s) ($mode_label):"
  printf '%s\n' "$orphans"
  echo "  Fix: delete the orphan if its asset was removed, or restore/commit the missing asset."
fi

[[ $strict -eq 1 ]] && exit 1
exit 0
