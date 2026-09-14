#!/usr/bin/env bash
# sync-templates.sh — keep skill assets identical to the canonical files in templates/ and agents/.
# Part of claude-unity-devkit.
#
# templates/ and agents/ are the single source of truth: commands and scripts copy from templates/,
# and agents/ holds the live agents. Each skill's assets/ holds byte-identical duplicates so the skill
# stays self-contained when read on its own. Edit the canonical file, then run this script.
#
# Usage:
#   sync-templates.sh          copy templates/ -> skills/*/assets
#   sync-templates.sh --check  report drift and exit 1 if any copy differs (pre-publish / CI)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-sync}"

MAP=(
  "templates/project/.gitignore:skills/unity-project-conventions/assets/.gitignore"
  "templates/project/.gitattributes:skills/unity-project-conventions/assets/.gitattributes"
  "templates/project/.editorconfig:skills/unity-project-conventions/assets/.editorconfig"
  "templates/project/asmdef/Runtime.asmdef:skills/unity-project-conventions/assets/Runtime.asmdef"
  "templates/ci/test.yml:skills/gameci-pipeline/assets/test.yml"
  "templates/ci/build.yml:skills/gameci-pipeline/assets/build.yml"
  "templates/deploy/deploy-server.yml:skills/unity-deploy/assets/deploy-server.yml"
  "templates/deploy/deploy-webgl.yml:skills/unity-deploy/assets/deploy-webgl.yml"
  "templates/deploy/deploy.sh:skills/unity-deploy/assets/deploy.sh"
  "templates/deploy/unity-server.service:skills/unity-deploy/assets/unity-server.service"
  "templates/deploy/nginx-unity-webgl.conf:skills/unity-deploy/assets/nginx-unity-webgl.conf"
  "templates/project/asmdef/Tests.EditMode.asmdef:skills/unity-testing/assets/Tests.EditMode.asmdef"
  "templates/project/asmdef/Tests.PlayMode.asmdef:skills/unity-testing/assets/Tests.PlayMode.asmdef"
  "templates/project/tests/EditModeSmokeTests.cs:skills/unity-testing/assets/EditModeSmokeTests.cs"
  "templates/project/tests/PlayModeSmokeTests.cs:skills/unity-testing/assets/PlayModeSmokeTests.cs"
  "agents/dependency-auditor.md:skills/subagent-orchestration/assets/dependency-auditor.md"
  "agents/implementer.md:skills/subagent-code-todo/assets/implementer.md"
  "agents/pr-author.md:skills/ship-workflow/assets/pr-author.md"
  "agents/slack-notifier.md:skills/ship-workflow/assets/slack-notifier.md"
  "agents/factual-reviewer.md:skills/ship-workflow/assets/factual-reviewer.md"
  "agents/architecture-reviewer.md:skills/ship-workflow/assets/architecture-reviewer.md"
  "agents/security-reviewer.md:skills/ship-workflow/assets/security-reviewer.md"
  "agents/consistency-reviewer.md:skills/ship-workflow/assets/consistency-reviewer.md"
  "agents/redundancy-checker.md:skills/ship-workflow/assets/redundancy-checker.md"
  "agents/performance-reviewer.md:skills/ship-workflow/assets/performance-reviewer.md"
  "agents/gameplay-reviewer.md:skills/ship-workflow/assets/gameplay-reviewer.md"
  "agents/ci-reviewer.md:skills/ship-workflow/assets/ci-reviewer.md"
)

drift=0
for pair in "${MAP[@]}"; do
  src="$ROOT/${pair%%:*}"
  dst="$ROOT/${pair#*:}"
  [[ -f "$src" ]] || { echo "sync-templates: missing template ${pair%%:*}" >&2; exit 1; }
  case "$MODE" in
    --check)
      if ! cmp -s "$src" "$dst"; then
        echo "DRIFT: ${pair#*:} differs from ${pair%%:*}"
        drift=1
      fi
      ;;
    sync)
      mkdir -p "$(dirname "$dst")"
      cp -p "$src" "$dst"
      ;;
    *)
      sed -n '10,12p' "$0" >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" == --check ]]; then
  [[ $drift -eq 0 ]] && echo "sync-templates: all skill assets match templates/"
  exit "$drift"
fi
echo "sync-templates: copied ${#MAP[@]} templates into skills/*/assets"
