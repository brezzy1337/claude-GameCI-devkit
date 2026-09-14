---
description: Add a deploy pipeline for Unity builds to a DigitalOcean Droplet (Linux dedicated server as a systemd service by default, or WebGL behind nginx) with versioned releases, an atomic symlink swap, and rollback
argument-hint: [server or webgl]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(ls *), Bash(find *), Bash(mkdir *), Bash(git rev-parse *), Bash(gh secret list *)
disable-model-invocation: true
---

# Setup deploy

Add a deploy pipeline using the `unity-deploy` skill — read its SKILL.md and
`references/droplet-setup.md` first. Treat $ARGUMENTS as the target (`server` or `webgl`).

Context (gathered for you):
- Repo root: !`git rev-parse --show-toplevel`
- Unity project(s): !`find . -maxdepth 3 -path '*/Library' -prune -o -name ProjectVersion.txt -path '*/ProjectSettings/*' -print`
- Existing workflows: !`find . -maxdepth 3 -path './.github/workflows/*' -name '*.y*ml'`
- Existing deploy files: !`find . -maxdepth 2 -path './deploy/*'`

1. **Preconditions.** The deploy workflow builds with GameCI, so it needs the same license secrets as
   CI. If there is no GameCI setup yet, tell me and suggest `/claude-unity-devkit:setup-ci` first (you
   may continue — the deploy workflow is self-contained).

2. **Ask before guessing** (one AskUserQuestion round, defaults first):
   - **Target**: Linux dedicated server via systemd (default) or WebGL via nginx — unless $ARGUMENTS
     already says.
   - **Droplet layout**: `DEPLOY_ROOT` (default `/srv/unity-server` for the server,
     `/var/www/unity-webgl` for WebGL), systemd service name (default `unity-server`), service user
     (default `unity`), releases to keep (default 5).
   - **Server**: build name (default `Server` → binary `Server.x86_64`), game port and protocol
     (default `7777/udp`), and any launch arguments the server bootstrap reads.
   - **WebGL**: domain name (for nginx `server_name` and certbot), and whether the build uses Brotli
     or Gzip compression (Brotli requires HTTPS).
   - **Trigger**: `v*` tags + manual dispatch (default), or also pushes to the default branch.

3. **Write the files** from `${CLAUDE_PLUGIN_ROOT}/templates/deploy/`, resolving every `TAILOR`
   marker consistently — the same `DEPLOY_ROOT`, service name, and binary name must appear in every
   file:
   - Server: `.github/workflows/deploy-server.yml`, `deploy/deploy.sh`, `deploy/unity-server.service`
     (rename to `<service>.service` if the name changed).
   - WebGL: `.github/workflows/deploy-webgl.yml`, `deploy/deploy.sh`, `deploy/nginx-unity-webgl.conf`.
   Keep the workflow's `environment: production`, pinned host keys, and `cancel-in-progress: false`.
   If a file already exists, show me the diff and ask before overwriting.

4. **Review.** Dispatch the `ci-reviewer` sub-agent on the workflow and `deploy/` files; fix every
   Critical and Warning finding.

5. **Print what I must do** (I run these; never run them for me):
   - **Deploy key:** `ssh-keygen -t ed25519 -N "" -C github-deploy -f ./deploy_key`, add
     `deploy_key.pub` to the deploy user's `~/.ssh/authorized_keys` on the Droplet, then
     `gh secret set DEPLOY_SSH_KEY < deploy_key` and delete the local private key.
   - **Host key pin:** `ssh-keyscan -t ed25519 <droplet-ip> | gh secret set DEPLOY_KNOWN_HOSTS` —
     compare the fingerprint with the one in the DigitalOcean console first.
   - `gh secret set DEPLOY_HOST`, `gh secret set DEPLOY_USER`; optionally
     `gh variable set DEPLOY_PORT` for a non-22 SSH port. Show which already exist (`gh secret list`).
   - **GitHub environment:** Settings → Environments → `production` → add required reviewers, so
     every deploy waits for a human.
   - **One-time Droplet setup** from `references/droplet-setup.md`, filled in with the chosen names:
     users and directories, the single sudoers rule for `systemctl restart <service>`, installing the
     unit (or nginx site + certbot), and the firewall rule for the game port (or 80/443).

6. **Next steps.** Tag a release (`git tag v0.1.0 && git push origin v0.1.0`) or run the workflow
   manually; approve it in the `production` environment. Roll back with
   `DEPLOY_HOST=… DEPLOY_USER=… DEPLOY_ROOT=… bash deploy/deploy.sh rollback <server|webgl>`.

Never put keys, hosts, or passwords in committed files. Stop and ask rather than guessing hosts,
paths, or ports.
