#!/usr/bin/env bash
# notify-discord.sh — post one "PR opened" message to the team Discord channel.
# Part of claude-unity-devkit. Used by /ship when the notification channel is Discord.
#
# A webhook can't start a thread in a normal text channel (only in forum channels), so /ship posts
# once, when the PR opens; the message links to GitHub, where the PR is reviewed and merged.
#
# Usage:
#   notify-discord.sh --check                 exit 0 if DISCORD_WEBHOOK_URL is set, 3 if not
#   notify-discord.sh <pr-url> [<<'EOF' ...]  post; an optional one-line summary comes on stdin
#
# The only argument is the PR URL, which must look like https://github.com/<owner>/<repo>/pull/<n>.
# Title, branch, and base are read from GitHub (gh pr view), never passed on the command line, so
# PR text can't reach the shell. Pass the summary through a quoted heredoc (<<'EOF'), never inside
# double quotes.
#
# Reads the webhook from DISCORD_WEBHOOK_URL (a Codespaces secret or a local env var). Never commit
# the URL or print it: anyone holding it can post to the channel. It is handed to curl through a
# config on a file descriptor, so it doesn't appear in the process list.
# Exit codes: 0 posted (or --check ok), 1 failed, 3 webhook not set, 64 usage.
set -euo pipefail

if [ "${1:-}" = "--check" ]; then
  [ -n "${DISCORD_WEBHOOK_URL:-}" ] && { echo "DISCORD_WEBHOOK_URL is set."; exit 0; }
  echo "DISCORD_WEBHOOK_URL is not set." >&2
  exit 3
fi
if [ $# -ne 1 ] || ! [[ "$1" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$ ]]; then
  echo "usage: $0 --check | <https://github.com/<owner>/<repo>/pull/<n>> [summary on stdin]" >&2
  exit 64
fi
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "DISCORD_WEBHOOK_URL is not set; skipped the Discord post." >&2
  exit 3
fi

pr_url="$1"
summary=""
[ -t 0 ] || summary="$(head -c 2000 || true)"
if ! pr="$(gh pr view "$pr_url" --json title,headRefName,baseRefName,author 2>/dev/null)"; then
  echo "Couldn't read $pr_url with gh; skipped the Discord post." >&2
  exit 1
fi

payload="$(jq -n --arg url "$pr_url" --arg summary "$summary" --argjson pr "$pr" '{
    username: "ship",
    allowed_mentions: { parse: [] },
    embeds: [{
      title: ("PR opened: " + $pr.title)[0:256],
      url: $url,
      description: ([$summary, "Review and merge on GitHub: " + $url] | map(select(. != "")) | join("\n\n"))[0:4096],
      color: 2600544,
      fields: [
        { name: "Branch", value: ("`" + $pr.headRefName + "` → `" + $pr.baseRefName + "`"), inline: true },
        { name: "Author", value: ($pr.author.name // $pr.author.login // "unknown"), inline: true }
      ]
    }]
  }')"

# ?wait=true makes Discord return the created message, so a failure is an HTTP error, not silence.
sep='?'; [[ "$DISCORD_WEBHOOK_URL" == *\?* ]] && sep='&'
if ! out="$(printf '%s' "$payload" | curl -sS --fail-with-body --connect-timeout 10 --max-time 30 \
  -X POST -H 'Content-Type: application/json' --data-binary @- \
  -K <(printf 'url = "%s"\n' "${DISCORD_WEBHOOK_URL}${sep}wait=true") 2>&1)"; then
  # Print Discord's error body only, with the webhook value and any Discord webhook URL masked.
  out="${out//"$DISCORD_WEBHOOK_URL"/<webhook>}"
  echo "Discord post failed: $(printf '%s' "$out" | sed -E 's#https?://[^ "]*discord[^ "]*/webhooks/[^ "]*#<webhook>#g' | head -c 300)" >&2
  exit 1
fi
echo "Posted to Discord."
