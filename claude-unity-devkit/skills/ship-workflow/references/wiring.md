# Wiring reference

Detail for assembling the ship workflow. Read this when generating the slash command, the hook,
or the Slack/Discord glue. Verify command syntax against current `gh`, Claude Code, Slack, and
Discord docs.

## Contents
- gh CLI patterns (default driver)
- Making the gates real
- Choosing the notification channel
- Slack: agent path (default) vs webhook hook (backstop)
- Discord: webhook script
- Where state lives
- Slash-command frontmatter recap
- GitHub plugin / MCP alternative

## gh CLI patterns

The default driver is the `gh` CLI inside Claude Code — no extra setup beyond `gh auth login`.

- Open: `gh pr create --base <base> --title "<title>" --body "<body>"`
- Post a review: `gh pr comment <number|url> --body "<consolidated review>"` (or `gh pr review`)
- Inspect: `gh pr view --json number,title,url,state,body`
- CI status: `gh pr checks <number|url>` (add `--watch` to block until done); failing job detail:
  `gh run view <run-id> --log-failed`
- Merge: `gh pr merge <number|url> --squash` (style per repo)

Scope these in agent/command `allowed-tools` with patterns, e.g. `Bash(gh pr view *)`,
`Bash(gh pr checks *)`. `gh pr create`, `gh pr comment`, and `gh pr merge` are deliberately left
unscoped so they prompt — see gates below. A blanket `Bash(gh *)` would pre-authorize them and
silently remove both gates; never use it in these commands.

## Making the gates real

Two gates: open and merge. Enforce them with permissions, not just instructions.

- **Interactive use:** leave `git push`, `gh pr create`, and `gh pr merge` OUT of the command's
  `allowed-tools`. Claude Code then asks for permission when it reaches them — that prompt is the
  human gate. Everything read-only (status, diff, `gh pr view`, `gh pr checks`) is pre-authorized so
  the pipeline flows up to each gate without nagging.
- **Auto mode:** commands outside `allowed-tools` may run without a prompt, so add explicit `ask`
  rules in `.claude/settings.json`. Rules match command prefixes, so cover the flag-first forms and
  the other routes to the same effect (`gh api` can merge or comment; `gh pr close/review/ready`):
  ```json
  { "permissions": {
      "ask": ["Bash(git push)", "Bash(git push *)", "Bash(git * push *)",
              "Bash(gh pr create *)", "Bash(gh pr comment *)", "Bash(gh pr edit *)",
              "Bash(gh pr merge *)", "Bash(gh pr close *)", "Bash(gh pr review *)",
              "Bash(gh pr ready *)", "Bash(gh * pr merge *)", "Bash(gh api *)", "Bash(gh * api *)"],
      "deny": ["Bash(git push --force*)", "Bash(git push -f*)", "Bash(git push * --force*)",
               "Bash(git push * -f*)", "Bash(git push * +*)",
               "Bash(env)", "Bash(printenv)", "Bash(printenv *)"] } }
  ```
  `deny` on `env`/`printenv` keeps a prompt-injected run from dumping `DISCORD_WEBHOOK_URL` or other
  secrets from the environment.
- **Bypass mode** (`--dangerously-skip-permissions`): `ask` rules don't prompt there. Don't run
  `/ship` that way, or `deny` the push/create/merge commands so a human finishes those steps by
  hand. Say this plainly in the CLAUDE.md section rather than claiming the gates always hold.
- **Branch protection** on the base branch (required GameCI checks, required review) is the
  server-side backstop: even a mistaken merge attempt fails while checks are red.

## Choosing the notification channel

`/ship` resolves the channel once per run, first match wins:
1. `--notify=slack|discord|none` in the command arguments (a one-off override);
2. the `Notifications: slack | discord | none` line in CLAUDE.md's Ship workflow section (the team
   setting);
3. auto-detect: Discord if `notify-discord.sh --check` exits 0 (`DISCORD_WEBHOOK_URL` is set), Slack
   if Slack MCP tools are available in the session, otherwise none.

It states the choice before opening the PR. An unconfigured channel or a failed post is reported in
one line and never blocks shipping.

## Slack: agent path vs webhook hook

**Default — agent path (MCP).** The command invokes `slack-notifier` at each transition; the agent
posts through a Slack MCP server. Reliable because it's a defined command step, and it can thread:
the first post returns a thread timestamp, stored in the PR body, that later posts reply to.
Plugin agents can't declare `mcpServers`, so the plugin's `slack-notifier` uses whatever Slack tools
the session has (the plugin's `.mcp.json` `slack` slot or a connector); a project-local copy may pin
`mcpServers: [slack]`.

**Backstop — webhook hook.** A `SubagentStop` hook can fire even if the chain is abandoned, but a
command hook runs a shell command and doesn't talk to the Slack MCP server. So it posts via a Slack
incoming webhook. The plugin ships `scripts/notify-slack.sh`:
```bash
#!/usr/bin/env bash
set -e
MSG="${1:-update}"
if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "SLACK_WEBHOOK_URL not set; skipping notification"; exit 0
fi
curl -fsS -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"${MSG}\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
```
For a project-local setup, copy it to `.claude/scripts/`, `chmod +x` it, and reference it from
`assets/subagentstop-slack-hook.json`. The hook's matcher matches the agent type: `security-reviewer`
for a project agent, `claude-unity-devkit:security-reviewer` for the plugin's (the asset's regex
covers both). Use the backstop only when guaranteed firing matters; otherwise the agent path alone
is enough.

## Discord: webhook script

Discord needs no MCP server: a channel webhook (Channel → Edit → Integrations → Webhooks → New
Webhook → Copy URL) is enough. The plugin ships `scripts/notify-discord.sh` (copy in
`assets/notify-discord.sh`):

- `notify-discord.sh --check` — exit 0 if `DISCORD_WEBHOOK_URL` is set, 3 if not. Prints no URL.
- `notify-discord.sh <pr-url> <<'EOF'` … `EOF` — posts one embed ("PR opened: …", the summary,
  branch → base, author) linking to the PR. The **only argument is the PR URL**, validated against
  `https://github.com/<owner>/<repo>/pull/<n>`; the title, branches, and author come from
  `gh pr view`, and the optional one-line summary comes on **stdin**. This keeps PR text, which
  `pr-author` drafts from a diff anyone can influence, away from the shell: a title containing
  `$(…)` pasted into a double-quoted, pre-authorized command would otherwise execute. Tell the
  model to use a quoted heredoc (`<<'EOF'`) for the summary, never double quotes.
- The webhook reaches curl through `-K` on a file descriptor, not argv, so it doesn't show in `ps`.
  `?wait=true` turns a rejected post into an HTTP error; the error output masks the exact webhook
  value and any Discord webhook URL. `allowed_mentions` is empty, so a PR title can't ping
  `@everyone`. Connect and total timeouts keep a hung request from stalling `/ship`. Needs `gh` and
  `jq`.

`/ship` posts **once**, when the PR opens, and not again on a re-run for an existing PR. A webhook
can't start a thread in a normal text channel — it can post into an existing thread (`thread_id`)
or create one only in a forum channel (`thread_name`) — so per-stage posts would scatter; reviews
and merges are followed on GitHub. A resumed run on an existing PR offers to send a post the first
run skipped. Pre-authorize only the two script forms in the command's `allowed-tools` — it isn't a
gate: `Bash(*/scripts/notify-discord.sh --check)` and
`Bash(*/scripts/notify-discord.sh https://github.com/*)` for the plugin, or the same with
`.claude/scripts/` for a project copy.

The URL is the credential: anyone holding it can post as the webhook. Keep it in
`DISCORD_WEBHOOK_URL` (a Codespaces secret, or a local env var each teammate sets), never in a
committed file, and never echo it. If it leaks, delete the webhook in Discord and create a new one.

## Where state lives

Don't keep pipeline state in the session — it dies with the context.
- **PR body** — the change summary, Editor follow-ups, and the consolidated review. Re-runnable:
  read it back with `gh pr view --json body`.
- **PR checks** — the GameCI results, read back with `gh pr checks`.
- **Slack thread** (Slack teams) — running status. Store the thread `ts` in the PR body (a trailing
  `<!-- slack-thread: <ts> -->` line works) so a later run replies in the same thread instead of
  opening a new one.

This is what lets an interrupted `/ship` resume: it reconstructs state from the PR, its checks, and
the thread.

## Slash-command frontmatter recap

`.claude/commands/<name>.md` (or `<plugin>/commands/<name>.md`, invoked as `/<plugin>:<name>`);
filename is the command name. Optional frontmatter: `description`, `argument-hint`, `allowed-tools`,
`model`, `disable-model-invocation` (set it on commands with side effects that Claude shouldn't run
on its own — but not on `/ship` if `/code-todo` must invoke it). Body is the prompt; `$ARGUMENTS`
(or `$0`, `$1`) inject input, `@path` references a file, and `` !`cmd` `` runs a command before the
prompt is sent (it must succeed, and needs a matching `Bash(...)` rule in `allowed-tools`).
`allowed-tools` patterns use the `Bash(git diff *)` form.

## GitHub plugin / MCP alternative

The `github` plugin from `claude-plugins-official` (GitHub's MCP server) can replace `gh` if PR
actions are needed from outside Claude Code or for richer GitHub queries. If used, swap the
`Bash(gh ...)` tools in `pr-author` and the command for the MCP tools, and apply the same gate idea:
keep the create/merge tools un-pre-authorized so they prompt. For an in-terminal workflow, `gh` is
simpler and the default recommendation.
