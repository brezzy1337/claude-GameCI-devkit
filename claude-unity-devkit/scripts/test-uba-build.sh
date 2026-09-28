#!/usr/bin/env bash
# test-uba-build.sh — run templates/ci/uba-build.sh against a local mock of the Unity Build Automation
# v2 API (scripts/testdata/mock_uba.py) in four scenarios. Part of claude-unity-devkit.
# Needs bash, curl, jq, python3. Exits 1 if any scenario misbehaves.
#
# Usage: scripts/test-uba-build.sh [path-to-uba-build.sh]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${1:-$ROOT/templates/ci/uba-build.sh}"
MOCK="$ROOT/scripts/testdata/mock_uba.py"
WORK="$(mktemp -d)"
trap 'kill "${pid:-}" 2>/dev/null; rm -rf "$WORK"' EXIT
fails=0

# scenario, expected exit code, text the summary must contain
run() {
  local scenario="$1" want_rc="$2" want_text="$3" port rc out="$WORK/$1"
  port=$(( 20000 + RANDOM % 20000 ))
  mkdir -p "$out"
  python3 "$MOCK" "$port" "$scenario" & pid=$!
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.1; done
  env -i PATH="$PATH" HOME="$HOME" \
    UNITY_SERVICE_ACCOUNT_ID=KEY UNITY_SERVICE_ACCOUNT_SECRET=SECRET \
    UBA_ORG_ID=ORG UBA_PROJECT_ID=PROJ UBA_TARGET=win BUILD_BRANCH=feature/x BUILD_COMMIT=c0ffee \
    UBA_API="http://127.0.0.1:$port/v2" POLL_SECONDS=0 BUSY_WAIT_SECONDS=0 \
    GITHUB_STEP_SUMMARY="$out/summary.md" GITHUB_OUTPUT="$out/output" UBA_STATE_FILE="$out/state" \
    DOWNLOAD_DIR="$out/dl" bash "$SCRIPT" > "$out/log" 2>&1
  rc=$?
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  if [ "$rc" = "$want_rc" ] && grep -qF -- "$want_text" "$out/summary.md" 2>/dev/null; then
    echo "ok   $scenario (exit $rc)"
  else
    echo "FAIL $scenario: exit $rc (want $want_rc), summary missing '$want_text'"; sed 's/^/     /' "$out/log"
    fails=$((fails + 1))
  fi
}

run ok    0 '| PlayMode | 3 | 0 |'
[ -f "$WORK/ok/dl/Game build.zip" ] && [ "$(cat "$WORK/ok/state" 2>/dev/null)" = 7 ] \
  || { echo "FAIL ok: artifact not downloaded or state file not written"; fails=$((fails + 1)); }
run fail  1 'error CS0103: boom'
run limit 1 'free-tier limit reached'
run auth  1 'Automation User'

if [ "$fails" != 0 ]; then echo "$fails scenario(s) failed"; exit 1; fi
echo "all scenarios passed"
