# Self-hosted runner for the Unity CLI workflow

A self-hosted runner keeps the Editor installed and `Library/` warm between runs, so after the first
import a PR's tests start in seconds instead of re-downloading ~4–5 GB and re-importing every asset.
The cost: someone owns the machine. The human does every step below; Claude prints them.

## Only for private repositories

A self-hosted runner executes whatever a workflow tells it to. On a public repo a fork PR could run
code on your machine. The workflow skips fork PRs, but keep self-hosted runners on **private** repos
and restrict them to this repo (or a runner group).

## Machine

- Linux x64 with glibc 2.34+ (Ubuntu 22.04 / 24.04). Windows/macOS work too, but the template's
  steps are bash; on Windows, install the CLI with `winget install Unity.CLI` and run steps in Git Bash.
- Disk: ~10 GB per Editor version with modules, plus `Library/` (often 2–20 GB) per workspace, plus
  builds. 100 GB+ free is comfortable. RAM: 16 GB+.
- One Editor per project folder at a time — one runner per machine per project, or separate runner
  directories (each gets its own workspace and `Library/`).

## One-time setup (as the user the runner service will run as)

1. Editor runtime libraries (Ubuntu 24.04 names; drop the `t64` suffix on 22.04):
   ```bash
   sudo apt-get install -y --no-install-recommends libgl1 libglu1-mesa libgtk-3-0t64 libnss3 \
     libasound2t64 libgbm1 libdrm2 libxtst6 libxrandr2 libxcursor1 libxcomposite1 libxdamage1 \
     libxfixes3 libxi6 libxrender1 libxext6 libsm6 libice6 libxkbcommon0 libpango-1.0-0 \
     libpangocairo-1.0-0 libcairo2 libgdk-pixbuf-2.0-0 libatk1.0-0t64 libatk-bridge2.0-0t64 \
     libcups2t64 libdbus-1-3 libnotify4 libsecret-1-0 git git-lfs jq curl
   ```
2. Unity CLI at the workflow's pinned version:
   `curl -fsSL https://unity.com/install.sh | UNITY_CLI_CHANNEL=beta UNITY_CLI_VERSION=<pin> bash`
3. Editor + modules: `unity install <editor> -m <modules> --accept-eula --yes`
4. License (`UNITY_LICENSE_MODE: machine`) — sign in as a **person**, not the service account:
   `unity auth login` (opens a browser; do it from a desktop session or over a forwarded display),
   then `unity license activate --personal --accept-eula` (Personal) or
   `unity license activate --serial <serial>` (Pro/Plus). Check with `unity license status`.
   The license stays on the machine; the workflow never returns it in `machine` mode.
5. `unity doctor --ci` should pass.
6. Register the runner: repo → Settings → Actions → Runners → New self-hosted runner. Follow the
   download/config commands shown there, adding the labels the workflow uses, e.g.
   `./config.sh --url https://github.com/<owner>/<repo> --token <token> --labels unity`
   (`self-hosted`, `linux`, `x64` are added automatically).
7. Run it as a service under the same user: `sudo ./svc.sh install <user> && sudo ./svc.sh start`.
   A different user wouldn't see the CLI, Editor, or license.

## Runners on teammates' machines (Windows)

A small team can start with a runner on each Editor user's own PC instead of a dedicated box. Jobs go
to whichever registered machine with the labels is online and idle.

- **Trade-offs.** Jobs queue while every runner PC is off or asleep (GitHub cancels a job queued for
  24 hours). A build runs a second batch-mode Editor next to the owner's — CPU, RAM, and disk heavy,
  so owners may want to pause the runner while they work. Each machine keeps its own warm `Library/`.
- **Trust.** Any teammate who can push a branch can run code on every runner PC. Fine for a small
  trusted team on a private repo; move to a dedicated machine as the team grows.
- **Which machines.** Only people who already have the project's Editor installed (programmers,
  designers). Artists' machines don't need to be runners.
- **Same account.** The runner must run as the machine owner's Windows account, so it sees their
  Unity CLI, Editor, and Personal license (`UNITY_LICENSE_MODE: machine`). The service installer
  defaults to `NETWORK SERVICE`, which sees none of them.

Setup on each PC:

1. Git for Windows (includes Git Bash and Git LFS — the workflow's steps run in bash).
2. Unity CLI at the pinned version: `winget install Unity.CLI`, then
   `unity self-update --target <pin> --yes` if winget installed a different version.
3. The project's Editor (Unity Hub or `unity install <editor> --accept-eula --yes`). Building
   Windows on Windows needs no extra module.
4. The owner's Unity Personal license, already active if Unity Hub is signed in — check with
   `unity license status`. Then `unity doctor --ci`.
5. Register the runner (repo → Settings → Actions → Runners → New self-hosted runner → Windows),
   using a folder with space for Library + builds, e.g. `C:\actions-runner`:
   `.\config.cmd --url https://github.com/<owner>/<repo> --token <token> --labels unity --runasservice --windowslogonaccount <DOMAIN\user> --windowslogonpassword <password>`
   — or skip `--runasservice` and start it with `.\run.cmd` only while the PC should take jobs
   (simplest way to "pause" it: close that window).

## Maintenance

- Bumping the CLI pin in the workflow reinstalls it on the next run; bumping the Editor
  (`ProjectVersion.txt`) installs the new Editor on the next run — prune old ones with
  `unity editors prune`.
- Personal licenses need periodic re-activation; when `doctor --ci` starts failing on license,
  repeat step 4.
- A corrupt `Library/` shows up as odd import errors: delete `_work/<repo>/<repo>/Library` once.
