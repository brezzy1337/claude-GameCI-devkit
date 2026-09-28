# Unity CLI reference (verified subset)

Checked against `unity --help` of **1.0.0-beta.11** on Linux, 2026-09-27. The CLI is experimental;
`unity <command> --help` is authoritative, and `unity commands --json` dumps every command and flag
as a machine-readable manifest. Docs: https://docs.unity.com/en-us/unity-cli

## Global

- `--format human|json|tsv|ndjson|github` (env `UNITY_FORMAT`), `--json`. JSON envelope:
  `{success, command, data, errors, warnings}`; branch on `errors[0].code`.
- `--non-interactive` (`UNITY_NON_INTERACTIVE=1`), `--quiet`, `--verbose`, `--no-banner`.
- `UNITY_NO_UPDATE_CHECK=1` in CI. Errors go to stderr, results to stdout.
- Exit codes: 0 ok · 1 error · 2 usage · 3 auth · 4 configuration required · 6 operation failed /
  run didn't finish · 7 service or Editor unreachable (retryable) · 8 tests failed · 130/143 signals.

## Install and machine

| Command | Notes |
| --- | --- |
| `unity install <ver> -m <ids…> --accept-eula --yes` | `--dry-run` (sizes, with `--json`), `--resume`, `-a x86_64\|arm64` |
| `unity install-modules -e <ver> -m <ids…> --accept-eula --yes` | add modules to an installed Editor; `-l` lists; `--retries <n>` |
| `unity editors -i` / `editors path <ver>` / `editors verify <ver>` | installed Editors, install dir, structural check |
| `unity doctor` / `unity doctor --ci` | diagnostics; `--ci` exits non-zero when the machine can't build/test |
| `unity auth login` / `status` / `logout` | browser sign-in; `--client-id` + `--secret-from-stdin` for a service account |
| `unity license list\|status\|activate\|return` | activate: `--serial`, `--personal --accept-eula`, `--floating`, `--file <.ulf>`, `--generate-request <.alf>` |
| `unity self-update --target <ver> --yes` | also `--channel stable\|beta`, `--rollback`, `--check` |
| `unity skill install claude-code` | Unity's own agent skill into `~/.claude/skills/unity-cli/` |

Service-account env vars: `UNITY_SERVICE_ACCOUNT_ID`, `UNITY_SERVICE_ACCOUNT_SECRET`. They cover
Unity services only; `license activate --personal` rejects service-account tokens.

## Build and test (batch mode — no running Editor, no Pipeline package needed)

- `unity test [project]` — `--mode EditMode|PlayMode` (omit = the Editor's default platform only, so
  run both modes explicitly), `--filter`, `--output` (default `test-results.xml`),
  `--report-format nunit|junit|nunit,junit`, `--retries <0-10>` (reports flaky), `--rerun-failed`,
  `--affected [--since <ref>]` (impact-graph selection; full suite when unsure), `--shard N/M`,
  `--coverage` (needs `com.unity.testtools.codecoverage`), `--timeout <s>`, `--allow-install`.
- `unity build [project]` — `--target <BuildTarget>` or `--profile <name|.asset>` (Unity 6+),
  `-o/--output-path`, `--execute-method`, `--versioning-strategy semantic|tag|custom|none`,
  `--build-version`, `--timeout <s>`, `--no-tail`, `--allow-dirty-build`, provenance manifest beside
  the output (`--no-provenance`), Android signing flags (prefer env/secrets over argv).
  `--list-targets`, `--list-profiles`, `--create-profile <target>`. `unity build run` launches the
  last build (WebGL served locally).
- `unity run [project]` — generic batch-mode run; `run --command <name>` runs a `[CliCommand]`.
- `unity cache key --target <T>` — deterministic Library cache key (Editor + packages + target).
- `unity ci init --target <T> [--shards N] --dry-run` — Unity's own generated workflow.

## Version control (`unity vcs`)

| Command | Use |
| --- | --- |
| `vcs doctor [--fix]` | audit repo settings, ignore rules, LFS patterns, package pinning |
| `vcs merge-setup [--check]` | UnityYAMLMerge for scenes/prefabs (local git config; needs the Editor) |
| `vcs hooks install` / `status` | managed pre-commit, post-checkout, post-merge hooks (per clone) |
| `vcs sync [--rebase]` | pull commits + LFS objects; refuses while an Editor holds the project |
| `vcs switch <branch> [--dry-run]` | safe branch switch; reports the reimport it causes |
| `vcs status` | changes grouped by Unity meaning, with `.meta` pairing problems |
| `vcs conflicts` / `explain <path>` / `resolve [--all]` | classify, explain, auto-merge conflicts |
| `vcs diff <path>` / `blame <path>` | scene/prefab diff and blame by GameObject/component name |
| `vcs summarize --since <ref>` | PR-ready summary of a branch |
| `vcs affected --since <ref>` | assets, assemblies, and tests a change reaches |
| `vcs git worktree add <dir>` | second branch without a cold reimport |

## Running Editor (needs `com.unity.pipeline`)

`unity status`, `unity list`, `unity command <name> [args]`, `unity command eval '<C#>'`,
`unity recompile [--strict]`, `unity mcp`. The package serves on `127.0.0.1` (Editor ports
7800–7849) with a per-session bearer token in `Library/Pipeline/.unity-pipeline-port`. Commands are
static methods with `[CliCommand("name","desc")]` and `[CliArg]` parameters; the assembly must
reference `Unity.Pipeline.Attributes`. Player support is dev-builds only and off by default.

## Team commands (CLAUDE.md template)

Adapt names to the repo; keep it short — this is what teammates and agents copy.

```markdown
## Unity CLI

Pinned CLI: `<version>` · Editor: `<version>` (modules: `<ids>`)

| When | Run |
| --- | --- |
| New machine | `curl -fsSL https://unity.com/install.sh \| UNITY_CLI_CHANNEL=beta UNITY_CLI_VERSION=<pin> bash`, then `unity install <editor> -m <modules> --accept-eula --yes` |
| New clone | `git lfs install --local && unity vcs merge-setup && unity vcs hooks install` |
| Get latest | `unity vcs sync` (close the Editor first) |
| Change branch | `unity vcs switch <branch>` |
| Before pushing | `unity test --affected --since origin/stable --mode EditMode` |
| Opening a PR | `unity vcs summarize --since origin/stable` → paste into the PR |
| Merge conflict in a scene/prefab | `unity vcs conflicts`, `unity vcs explain <path>`, `unity vcs resolve --all` |
| Try the build CI made | `unity build run` after `unity build --target <T> -o <path>` locally |
| Something's off | `unity doctor` |
```
