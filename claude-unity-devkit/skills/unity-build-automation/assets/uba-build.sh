#!/usr/bin/env bash
# Start a Unity Build Automation (UBA) build, wait for it, and report the result.
#
# Unity's build machines hold the Editor license, so this runs on any plain runner (no Unity install,
# no license secret). Uses the UBA v2 REST API with a service account (role: Automation User):
# https://docs.unity.com/en-us/oas-build-automation-client/2.0.0
#
# Required env:
#   UNITY_SERVICE_ACCOUNT_ID / UNITY_SERVICE_ACCOUNT_SECRET   service-account key ID and secret
#   UBA_ORG_ID, UBA_PROJECT_ID, UBA_TARGET                    where to build (repo variables)
# Optional env:
#   BUILD_BRANCH, BUILD_COMMIT    override the target's branch / commit (e.g. a PR head)
#   CAUSED_BY                     free text shown in the Unity Dashboard
#   POLL_SECONDS (30), MAX_WAIT_MINUTES (150), BUSY_RETRIES (10), BUSY_WAIT_SECONDS (60)
#   DOWNLOAD_DIR                  if set, download the primary artifact there
#   UBA_API                       API base (default https://build-automation.services.api.unity.com/v2)
#   UBA_STATE_FILE                if set, the build number is written there as soon as it starts
#                                 (a canceled step may never publish its GITHUB_OUTPUT)
#
# Outputs (GITHUB_OUTPUT): number, status. Exit 0 only when the build succeeds.
set -euo pipefail

: "${UNITY_SERVICE_ACCOUNT_ID:?}" "${UNITY_SERVICE_ACCOUNT_SECRET:?}"
: "${UBA_ORG_ID:?set the UBA_ORG_ID repository variable}"
: "${UBA_PROJECT_ID:?set the UBA_PROJECT_ID repository variable}"
: "${UBA_TARGET:?set the UBA_TARGET repository variable}"
API="${UBA_API:-https://build-automation.services.api.unity.com/v2}"
POLL_SECONDS="${POLL_SECONDS:-30}"
MAX_WAIT_MINUTES="${MAX_WAIT_MINUTES:-150}"
BUSY_RETRIES="${BUSY_RETRIES:-10}"
BUSY_WAIT_SECONDS="${BUSY_WAIT_SECONDS:-60}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
ORG_PATH="/orgs/$UBA_ORG_ID"
TARGET_PATH="$ORG_PATH/projects/$UBA_PROJECT_ID/buildtargets/$UBA_TARGET"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BODY="$WORK/body"

# api METHOD PATH [JSON] -> sets CODE, response body in $BODY. Never prints credentials.
api() {
  local args=(-sS -o "$BODY" -w '%{http_code}' -X "$1" -u "$UNITY_SERVICE_ACCOUNT_ID:$UNITY_SERVICE_ACCOUNT_SECRET"
              -H 'Accept: application/json')
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data "$3")
  CODE="$(curl "${args[@]}" "$API$2")" || CODE=000
}

err() { echo "::error::$*"; echo "**Error:** $*" >> "$SUMMARY"; }
detail() { jq -r '.detail // .title // .error // empty' "$BODY" 2>/dev/null | head -c 500; }

# Explain the common setup failures instead of just printing a status code.
fail_http() {
  local what="$1"
  case "$CODE" in
    401) err "$what: 401 — the service-account key ID or secret is wrong." ;;
    403) err "$what: 403 — give the service account the **Automation User** role on this project." ;;
    404) err "$what: 404 — check UBA_ORG_ID / UBA_PROJECT_ID / UBA_TARGET (org ID format: see CLAUDE.md → CI)." ;;
    *)   err "$what: HTTP $CODE $(detail)" ;;
  esac
  exit 1
}

# 1. Don't start a build Unity would cancel immediately.
api GET "$ORG_PATH/free-tier-status"
if [ "$CODE" = 200 ]; then
  if [ "$(jq -r '.freeTierLimitReached' "$BODY")" = true ]; then
    err "Unity DevOps free-tier limit reached — builds would be canceled on start. Add a payment method or wait for next month's minutes."
    exit 1
  fi
elif [ "$CODE" = 401 ] || [ "$CODE" = 403 ] || [ "$CODE" = 404 ]; then
  fail_http "Free-tier check"
else
  echo "::warning::Free-tier check returned HTTP $CODE; continuing."
fi

# 2. Start the build. 409 = the target already has a build pending; wait for it rather than fail.
payload="$(jq -nc --arg b "${BUILD_BRANCH:-}" --arg c "${BUILD_COMMIT:-}" --arg by "${CAUSED_BY:-GitHub Actions}" \
  '{clean: false, causedBy: $by} + (if $b != "" then {branch: $b} else {} end) + (if $c != "" then {commit: $c} else {} end)')"
for attempt in $(seq 0 "$BUSY_RETRIES"); do
  api POST "$TARGET_PATH/builds" "$payload"
  [ "$CODE" != 409 ] && break
  [ "$attempt" = "$BUSY_RETRIES" ] && { err "Target '$UBA_TARGET' stayed busy (409) — another build is pending."; exit 1; }
  echo "Target busy (409); retrying in ${BUSY_WAIT_SECONDS}s ($((attempt + 1))/$BUSY_RETRIES)."
  sleep "$BUSY_WAIT_SECONDS"
done
[ "$CODE" = 202 ] || fail_http "Start build"
start_error="$(jq -r '.[0].error // empty' "$BODY")"
[ -n "$start_error" ] && { err "Build refused: $start_error"; exit 1; }
NUMBER="$(jq -r '.[0].build' "$BODY")"
echo "number=$NUMBER" >> "$OUTPUT"
[ -n "${UBA_STATE_FILE:-}" ] && echo "$NUMBER" > "$UBA_STATE_FILE"
echo "Started UBA build #$NUMBER on target '$UBA_TARGET' (branch ${BUILD_BRANCH:-target default}, commit ${BUILD_COMMIT:-latest})."

# 3. Poll until it finishes.
deadline=$(( $(date +%s) + MAX_WAIT_MINUTES * 60 ))
last=""
while :; do
  api GET "$TARGET_PATH/builds/$NUMBER"
  if [ "$CODE" = 200 ]; then
    status="$(jq -r '.buildStatus' "$BODY")"
    if [ "$status" != "$last" ]; then
      reason="$(jq -r '.queuedReason // empty' "$BODY")"
      echo "$(date -u +%H:%M:%S) build #$NUMBER: $status${reason:+ ($reason)}"
      last="$status"
    fi
    case "$status" in success|failure|canceled|unknown) break ;; esac
  else
    echo "::warning::Status poll returned HTTP $CODE; retrying."
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    err "Build #$NUMBER still '$last' after $MAX_WAIT_MINUTES minutes. It keeps running in UBA; check the Unity Dashboard."
    exit 1
  fi
  sleep "$POLL_SECONDS"
done
echo "status=$status" >> "$OUTPUT"

# 4. Report: status, tests, time, failures.
api GET "$TARGET_PATH/builds/$NUMBER?include=testResults,failureDetails"
[ "$CODE" = 200 ] || cp /dev/null "$BODY"
{
  echo "### Unity Build Automation — build #$NUMBER: \`$status\`"
  echo
  echo "Target \`$UBA_TARGET\` · branch \`$(jq -r '.scmBranch // "?"' "$BODY")\` · revision \`$(jq -r '.lastBuiltRevision // "?"' "$BODY" | cut -c1-12)\` · billable $(jq -r '((.billableTimeInSeconds // 0) / 60 | floor | tostring) + " min"' "$BODY")"
  echo
  jq -r '
    (.testResults // {}) as $t
    | if ($t | length) == 0 then "No test results reported."
      else "| Tests | Passed | Failed |\n| --- | --- | --- |\n"
        + ([["EditMode", $t.unit_test_editmode], ["PlayMode", $t.unit_test_playmode], ["All", $t.unit_test]]
           | map(select(.[1] != null) | "| \(.[0]) | \(.[1].passed // 0) | \(.[1].failed // 0) |") | join("\n"))
      end' "$BODY"
  echo
  jq -r '(.failureDetails // [])[] | "- **\(.label // "failure")**: \(.message // .reason // "" | tostring | .[0:300])"' "$BODY"
  echo
  echo "Download or share the build: Unity Dashboard → DevOps → Build Automation → Build History → #$NUMBER."
} >> "$SUMMARY"

if [ "$status" != success ]; then
  # The log endpoint redirects to a signed URL; fetch it following redirects.
  curl -sSL -u "$UNITY_SERVICE_ACCOUNT_ID:$UNITY_SERVICE_ACCOUNT_SECRET" \
    "$API$TARGET_PATH/builds/$NUMBER/log" -o "$WORK/log" 2>/dev/null || true
  if [ -s "$WORK/log" ]; then
    echo "----- last 80 log lines -----"; tail -n 80 "$WORK/log"
    { echo; echo '<details><summary>Last 80 log lines</summary>'; echo; echo '```'; tail -n 80 "$WORK/log"; echo '```'; echo '</details>'; } >> "$SUMMARY"
  fi
  err "UBA build #$NUMBER finished with status '$status'."
  exit 1
fi

# 5. Optionally pull the primary artifact into the workspace (e.g. to attach to a GitHub release).
if [ -n "${DOWNLOAD_DIR:-}" ]; then
  api GET "$TARGET_PATH/builds/$NUMBER/artifacts"
  [ "$CODE" = 200 ] || fail_http "List artifacts"
  file="$(jq -r '[.[] | select(.primary)][0].files[0].filename // empty' "$BODY")"
  [ -n "$file" ] || { err "Build #$NUMBER has no primary artifact."; exit 1; }
  # Returns 303 with the signed URL in the JSON body (no Location header), so read it and fetch.
  api GET "$TARGET_PATH/builds/$NUMBER/download/$(jq -rn --arg f "$file" '$f | @uri')"
  url="$(jq -r '.url // empty' "$BODY")"
  [ -n "$url" ] || fail_http "Download link"
  mkdir -p "$DOWNLOAD_DIR"
  curl -sSfL "$url" -o "$DOWNLOAD_DIR/$(basename "$file")"
  echo "Downloaded $(basename "$file") to $DOWNLOAD_DIR."
fi
echo "UBA build #$NUMBER succeeded."
