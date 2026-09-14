---
name: unity-deploy
description: >-
  Author the deployment of Unity build artifacts to a DigitalOcean Droplet — a Linux headless
  dedicated server run as a systemd service (the default), or a WebGL build served by nginx with the
  right wasm, data, Brotli, and gzip headers — using rsync over SSH into versioned release
  directories, an atomic current-symlink swap, a health check, and rollback, wired into GitHub
  Actions. Use this skill whenever the user wants to deploy, host, or ship a Unity game server or web
  build to a VPS or Droplet, write a systemd unit for a Unity server, configure nginx for Unity WebGL,
  add a deploy job to CI, or fix a WebGL build that won't load because of compression or MIME headers.
---

# Unity deploy

## The idea

A deploy should be boring: the same artifact CI built, copied to a new directory on the server,
switched on with one atomic operation, checked, and reversible with one command. The devkit's
pattern is the classic release-directory layout:

```
DEPLOY_ROOT/
  releases/20260913T210500Z-v0.3.0-abc1234/   one directory per deploy (timestamp-named)
  releases/20260912T181200Z-v0.2.9-9f8e7d6/
  current -> releases/20260913T210500Z-v0.3.0-abc1234
  shared/                                     state that survives releases
```

systemd runs (or nginx serves) whatever `current` points at. Swapping the symlink is atomic, so there
is never a half-copied release live; rolling back is pointing it at the previous directory.

Two targets, one mechanism (`assets/deploy.sh`):

- **Linux dedicated server** (first-class) — built with GameCI as `StandaloneLinux64` with the
  Dedicated Server subtarget, run headless by `assets/unity-server.service`, restarted and
  health-checked on every deploy, rolled back automatically if it doesn't come up.
- **WebGL** — served by nginx (`assets/nginx-unity-webgl.conf`) with the compression headers Unity
  requires; no restart needed.

## What you produce

1. A deploy workflow — `assets/deploy-server.yml` or `assets/deploy-webgl.yml` →
   `.github/workflows/`.
2. `deploy/deploy.sh` (from `assets/deploy.sh`) — used by CI and by humans for rollback.
3. `deploy/unity-server.service` or `deploy/nginx-unity-webgl.conf`.
4. A **Deploy** subsection in CLAUDE.md: target, host alias (never the IP if the repo is public),
   `DEPLOY_ROOT`, service name, how to roll back.
5. The one-time Droplet setup, filled in — `references/droplet-setup.md`.

`/claude-unity-devkit:setup-deploy` drives this skill; `ci-reviewer` reviews the result.

## Step 1 — Inspect and ask

- Does the project build for the target? For the server: a Dedicated Server build of the game must
  make sense (a server bootstrap scene/code path; netcode transport). For WebGL: Player Settings →
  Web → Publishing Settings → Compression Format (Brotli, Gzip, or Disabled) — it decides the nginx
  and TLS requirements.
- Which port and protocol does the server listen on (most game transports use UDP, e.g. `7777/udp`)?
  How does it read its port and config (command-line args, environment, a file in `shared/`)?
- Is there persistent state (saves, databases)? It belongs in `shared/` or outside `DEPLOY_ROOT`,
  never inside a release.
- Existing infra: domain names, a reverse proxy, a firewall, other services on the Droplet.

Ask for anything not in the repo — hosts, paths, and ports are never guessed.

## Step 2 — The dedicated server

- **Build.** GameCI `unity-builder` with `targetPlatform: StandaloneLinux64`,
  `customParameters: -standaloneBuildSubtarget Server`, `buildName: Server` → `Server.x86_64` plus
  `Server_Data/` and `UnityPlayer.so`. (See the `gameci-pipeline` skill for why this works on the
  stock image.) The server subtarget strips rendering and audio; code must not assume a camera or GPU.
- **Run.** `assets/unity-server.service` starts `current/Server.x86_64 -batchmode -nographics -logFile -`
  so the Unity log goes to journald (`journalctl -u unity-server -f`). Extra arguments (the template's
  `-port 7777`) are only meaningful if your bootstrap reads them via
  `System.Environment.GetCommandLineArgs()` — say so in CLAUDE.md or remove them.
- **State and config.** `HOME=/var/lib/unity-server` + `StateDirectory=` gives
  `Application.persistentDataPath` a writable home under hardening; `EnvironmentFile=-/etc/unity-server.env`
  holds secrets and per-host settings outside the repo; `ReadWritePaths=` opens `shared/`.
- **Hardening.** `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `NoNewPrivileges`, and friends
  are on. `MemoryDenyWriteExecute` is deliberately off — the Mono backend JIT-compiles.
- **Shutdown.** `systemctl restart` sends SIGTERM and waits `TimeoutStopSec` (30 s). Check the journal
  for a clean shutdown when you first deploy; if matches must drain, handle it in the server and raise
  the timeout. A restart drops connected players — schedule deploys or add a drain step; this layout
  is not zero-downtime for stateful game servers.

## Step 3 — WebGL behind nginx

- **Headers.** Unity's pre-compressed files must be served with `Content-Encoding` and the right
  `Content-Type`: `.data.br`/`.data.gz` as `application/octet-stream`, `.js.br`/`.js.gz` as
  `application/javascript`, `.wasm.br`/`.wasm.gz` as `application/wasm`, each with `gzip off`. The
  template's blocks follow the Unity 6.3 manual's nginx sample; it adds an uncompressed `.wasm` MIME
  rule, dotfile denial, and cache headers.
- **HTTPS.** Browsers only decode `Content-Encoding: br` over HTTPS. A Brotli build needs TLS
  (`certbot --nginx`) or must be rebuilt with Gzip. When you can't control headers at all, Unity's
  *Decompression Fallback* option makes the loader decompress in JavaScript — slower startup, but it
  works anywhere.
- **Multithreading.** Builds with native C/C++ multithreading need the COOP/COEP headers (commented in
  the template).
- **Caching.** The template sends `Cache-Control: no-cache` everywhere (revalidate with ETags) so a
  deploy is visible immediately. With *Name Files As Hashes* enabled, the `Build/` files can be cached
  for a year instead — `index.html` must stay `no-cache` either way.

## Step 4 — Releases, swap, rollback (`deploy.sh`)

- **Upload** with `rsync -az --delete` into a fresh `releases/<UTC timestamp>-<label>/`. When a live
  release exists, `--link-dest` hard-links unchanged files to it, so a patch deploy uploads and stores
  only what changed.
- **Activate** by creating `current.tmp` and renaming it over `current` (`mv -T`): atomic on the same
  filesystem.
- **Server:** `sudo -n systemctl restart <service>` (one narrow sudoers rule), wait, check
  `systemctl is-active`. If it isn't active, print the last journal lines, swap back to the previous
  release, restart, and fail the job.
- **Prune** to the newest `KEEP_RELEASES` (default 5) by name; the live release is never deleted.
- **Rollback:** `deploy.sh rollback server|webgl` points `current` at the release just older than the
  live one (run it twice to go back two), restarting and health-checking the server.

## Step 5 — Wire it into GitHub Actions

The deploy workflows build the artifact themselves (same GameCI settings and Library cache as
`build.yml`), then deploy in a second job:

- `environment: production` — add required reviewers so every deploy waits for a human; this is the
  deploy equivalent of `/ship`'s merge gate.
- SSH material from secrets: `DEPLOY_SSH_KEY` (a dedicated ed25519 key), `DEPLOY_KNOWN_HOSTS` (the
  pinned host key — never `StrictHostKeyChecking=no`), `DEPLOY_HOST`, `DEPLOY_USER`; optional
  `DEPLOY_PORT` variable. The key is written with `umask 077` into `$RUNNER_TEMP` and removed afterwards.
- `concurrency` with `cancel-in-progress: false` — a deploy is never killed halfway.
- Triggers: `v*` tags and manual dispatch. The release label is `<tag or branch>-<short sha>`.

## Step 6 — Verify

- Run `ci-reviewer` on the workflow and `deploy/` files.
- Check that `DEPLOY_ROOT`, service name, and binary name agree across the workflow, the unit file,
  and nginx `root`.
- After the first deploy: `systemctl status <service>`, `journalctl -u <service> -n 50`, and a real
  client connecting. For WebGL:
  `curl -sI https://<domain>/Build/<name>.wasm.br | grep -iE 'content-(type|encoding)'` must show
  `application/wasm` and `br`.
- Try a rollback once before you need it.

## Grounding notes

- Dedicated Server build support is available on the Personal license; the build itself follows the
  `gameci-pipeline` license setup.
- This is single-host deployment. Multiple regions, autoscaling, or matchmaking are a different design
  (fleet managers, containers) — say so rather than stretching this one.
- Keep secrets out of the repo and out of the build: runtime secrets go in the EnvironmentFile on the
  Droplet, deploy credentials in GitHub secrets.
