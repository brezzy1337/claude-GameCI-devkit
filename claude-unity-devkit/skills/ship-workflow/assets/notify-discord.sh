#!/usr/bin/env bash
# notify-discord.sh — post one "PR opened" message to the team Discord channel.
# Part of claude-unity-devkit. Used by /ship when the notification channel is Discord.
#
# A webhook can't start a thread in a normal text channel (only in forum channels), so /ship posts
# once, when the PR opens; the message links to GitHub, where the PR is reviewed and merged.
#
# Usage:
#   notify-discord.sh --check                               exit 0 if DISCORD_WEBHOOK_URL is set, 3 if not
#   notify-discord.sh <pr-url> <pr-title> [summary] [base]  post the message (base defaults to the PR's base)
#
# Reads the webhook from DISCORD_WEBHOOK_URL (a Codespaces secret or a local env var). Never commit
# the URL or print it: anyone holding it can post to the channel.
# Exit codes: 0 posted (or --check ok), 1 post failed, 3 webhook not set, 64 usage.
set -euo pipefail

if [ "${1:-}" = "--check" ]; then
  [ -n "${DISCORD_WEBHOOK_URL:-}" ] && { echo "DISCORD_WEBHOOK_URL is set."; exit 0; }
  echo "DISCORD_WEBHOOK_URL is not set." >&2
  exit 3
fi
if [ $# -lt 2 ]; then
  echo "usage: $0 --check | <pr-url> <pr-title> [summary] [base]" >&2
  exit 64
fi
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "DISCORD_WEBHOOK_URL is not set; skipped the Discord post." >&2
  exit 3
fi
command -v jq >/dev/null || { echo "notify-discord: jq is required." >&2; exit 1; }

url="$1" title="$2" summary="${3:-}" base="${4:-}"
branch="$(git branch --show-current 2>/dev/null || true)"
author="$(git config user.name 2>/dev/null || true)"
if [ -z "$base" ] && command -v gh >/dev/null; then
  base="$(gh pr view "$url" --json baseRefName --jq .baseRefName 2>/dev/null || true)"
fi

payload="$(jq -n --arg url "$url" --arg title "$title" --arg summary "$summary" \
  --arg branch "$branch" --arg base "$base" --arg author "$author" '{
    username: "ship",
    allowed_mentions: { parse: [] },
    embeds: [{
      title: ("PR opened: " + $title)[0:256],
      url: $url,
      description: ([$summary, "Review and merge on GitHub: " + $url] | map(select(. != "")) | join("\n\n"))[0:4096],
      color: 2600544,
      fields: ([
        (if $branch != "" then { name: "Branch",
          value: ("`" + $branch + "`" + (if $base != "" then " → `" + $base + "`" else "" end)), inline: true }
         else empty end),
        (if $author != "" then { name: "Author", value: $author, inline: true } else empty end)
      ])
    }]
  }')"

# ?wait=true makes Discord return the created message, so a failure is an HTTP error, not silence.
if ! out="$(curl -sS --fail-with-body -X POST -H 'Content-Type: application/json' \
  --data "$payload" "${DISCORD_WEBHOOK_URL}?wait=true" 2>&1)"; then
  # Print Discord's error body only, with any webhook URL masked.
  echo "Discord post failed: $(printf '%s' "$out" | sed 's#https://[^ ]*discord[^ ]*#<webhook>#g' | head -c 300)" >&2
  exit 1
fi
echo "Posted to Discord."
