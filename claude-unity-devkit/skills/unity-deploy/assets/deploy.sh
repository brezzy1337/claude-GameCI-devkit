#!/usr/bin/env bash
#
# deploy.sh — ship a Unity build to a Droplet as a versioned release, then atomically swap the
# `current` symlink. From claude-unity-devkit templates/deploy/deploy.sh; copy to deploy/deploy.sh.
#
# Usage:
#   deploy.sh server   <local-build-dir> [release-label]   # Linux dedicated server (systemd)
#   deploy.sh webgl    <local-build-dir> [release-label]   # WebGL player served by nginx
#   deploy.sh rollback <server|webgl>                      # point `current` at the previous release
#
# Remote layout under DEPLOY_ROOT:
#   releases/<UTC-timestamp>[-label]/  one directory per deploy; names sort chronologically, and
#                                      files unchanged since the live release are hard-linked to it
#   current -> releases/<name>         what systemd / nginx actually run or serve
#   shared/                            state that must survive releases (config, saves)
#
# Environment:
#   DEPLOY_HOST            required  Droplet IP or hostname
#   DEPLOY_USER            required  SSH user that owns DEPLOY_ROOT
#   DEPLOY_ROOT            required  e.g. /srv/unity-server or /var/www/unity-webgl
#   DEPLOY_PORT            optional  SSH port (default 22)
#   SSH_KEY_PATH           optional  private key file (default: ssh-agent / ~/.ssh config)
#   SSH_KNOWN_HOSTS_PATH   optional  known_hosts file; enables strict host key checking
#   KEEP_RELEASES          optional  releases to keep (default 5, minimum 2)
#   SERVICE_NAME           server    systemd unit (default unity-server)
#   SERVER_BINARY          server    executable inside the build (default Server.x86_64)
#   HEALTH_WAIT_SECONDS    server    seconds to wait before the is-active check (default 10)
#
# Server deploys need one sudoers rule on the Droplet (see the unity-deploy skill):
#   <deploy-user> ALL=(root) NOPASSWD: /usr/bin/systemctl restart <service>
set -euo pipefail

usage() {
  sed -n '6,9p' "$0" >&2
  exit 1
}

die() {
  echo "deploy.sh: $*" >&2
  exit 1
}

[[ $# -ge 2 ]] || usage
MODE="$1"

: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_USER:?DEPLOY_USER is required}"
: "${DEPLOY_ROOT:?DEPLOY_ROOT is required}"
DEPLOY_PORT="${DEPLOY_PORT:-22}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
SERVICE_NAME="${SERVICE_NAME:-unity-server}"
SERVER_BINARY="${SERVER_BINARY:-Server.x86_64}"
HEALTH_WAIT_SECONDS="${HEALTH_WAIT_SECONDS:-10}"

[[ "$DEPLOY_ROOT" == /* ]] || die "DEPLOY_ROOT must be an absolute path"
[[ "$KEEP_RELEASES" =~ ^[0-9]+$ && "$KEEP_RELEASES" -ge 2 ]] || die "KEEP_RELEASES must be an integer >= 2"

SSH_OPTS=(-p "$DEPLOY_PORT" -o BatchMode=yes -o ConnectTimeout=15)
if [[ -n "${SSH_KEY_PATH:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_PATH" -o IdentitiesOnly=yes)
fi
if [[ -n "${SSH_KNOWN_HOSTS_PATH:-}" ]]; then
  SSH_OPTS+=(-o UserKnownHostsFile="$SSH_KNOWN_HOSTS_PATH" -o StrictHostKeyChecking=yes)
fi
REMOTE="$DEPLOY_USER@$DEPLOY_HOST"

remote() {
  # Run a bash script (read from stdin) on the Droplet; arguments are its positional params.
  ssh "${SSH_OPTS[@]}" "$REMOTE" bash -s -- "$@"
}

# Remote helper shared by deploy and rollback: swap `current`, restart (server only), verify,
# roll back to the previous target when the service does not come up, then prune old releases.
read -r -d '' ACTIVATE_SCRIPT <<'REMOTE_SCRIPT' || true
set -euo pipefail
root="$1"; mode="$2"; target="$3"; service="$4"; binary="$5"; wait_s="$6"; keep="$7"
cd "$root"
previous="$(readlink current 2>/dev/null || true)"

swap_to() {
  ln -sfn "$1" current.tmp
  mv -Tf current.tmp current
}

[[ -d "$target" ]] || { echo "ERROR: $target does not exist" >&2; exit 1; }
if [[ "$mode" == server ]]; then
  chmod +x "$target/$binary"
fi
swap_to "$target"
echo "current -> $target (was: ${previous:-none})"

if [[ "$mode" == server ]]; then
  sudo -n systemctl restart "$service"
  sleep "$wait_s"
  if ! systemctl is-active --quiet "$service"; then
    echo "ERROR: $service is not active after restart" >&2
    journalctl -u "$service" -n 50 --no-pager >&2 || true
    if [[ -n "$previous" && -d "$previous" && "$previous" != "$target" ]]; then
      echo "Rolling back to $previous" >&2
      swap_to "$previous"
      sudo -n systemctl restart "$service" || true
    fi
    exit 1
  fi
  echo "$service is active"
fi

# Prune: keep the newest $keep releases by name (names start with a UTC timestamp), and never
# delete whatever `current` points at.
live="$(readlink current)"
all="$(ls -1d releases/*/ 2>/dev/null | sed 's:/$::' | sort)"
count="$(printf '%s\n' "$all" | grep -c . || true)"
if [[ "$count" -gt "$keep" ]]; then
  printf '%s\n' "$all" | head -n "$((count - keep))" | while read -r old; do
    [[ "$old" == "$live" ]] && continue
    rm -rf -- "$old"
    echo "pruned $old"
  done
fi
REMOTE_SCRIPT

case "$MODE" in
  server | webgl)
    LOCAL_DIR="${2%/}"
    [[ -d "$LOCAL_DIR" ]] || die "build directory '$LOCAL_DIR' not found"
    if [[ "$MODE" == server ]]; then
      [[ -f "$LOCAL_DIR/$SERVER_BINARY" ]] || die "'$SERVER_BINARY' not found in $LOCAL_DIR (check buildName / SERVER_BINARY)"
    else
      [[ -f "$LOCAL_DIR/index.html" ]] || die "index.html not found in $LOCAL_DIR (point at the WebGL build folder)"
    fi

    LABEL="$(printf '%s' "${3:-}" | tr -c 'A-Za-z0-9._-' '-')"
    RELEASE_NAME="$(date -u +%Y%m%dT%H%M%SZ)${LABEL:+-$LABEL}"
    RELEASE_DIR="releases/$RELEASE_NAME"

    echo "==> $MODE release $RELEASE_NAME -> $REMOTE:$DEPLOY_ROOT"

    # Create the release directory; report whether a live release exists to hard-link against.
    HAS_CURRENT="$(remote "$DEPLOY_ROOT" "$RELEASE_DIR" <<'REMOTE_SCRIPT'
set -euo pipefail
root="$1"; release="$2"
mkdir -p "$root/releases" "$root/shared"
if [[ -e "$root/$release" ]]; then
  echo "ERROR: $root/$release already exists; retry in a second or pass a different label" >&2
  exit 1
fi
mkdir -p "$root/$release"
if [[ -L "$root/current" && -d "$root/current/" ]]; then echo yes; else echo no; fi
REMOTE_SCRIPT
)"

    RSYNC_EXTRA=()
    # --link-dest hard-links files unchanged since the live release: faster uploads, less disk.
    [[ "$HAS_CURRENT" == yes ]] && RSYNC_EXTRA+=(--link-dest="$DEPLOY_ROOT/current/")

    rsync -az --delete "${RSYNC_EXTRA[@]}" \
      -e "ssh ${SSH_OPTS[*]}" \
      "$LOCAL_DIR/" "$REMOTE:$DEPLOY_ROOT/$RELEASE_DIR/"

    printf '%s\n' "$ACTIVATE_SCRIPT" | remote "$DEPLOY_ROOT" "$MODE" "$RELEASE_DIR" \
      "$SERVICE_NAME" "$SERVER_BINARY" "$HEALTH_WAIT_SECONDS" "$KEEP_RELEASES"
    echo "==> deployed $RELEASE_NAME"
    ;;

  rollback)
    TARGET_MODE="$2"
    [[ "$TARGET_MODE" == server || "$TARGET_MODE" == webgl ]] || usage
    # The release immediately older (by name) than the one `current` points at.
    PREVIOUS="$(remote "$DEPLOY_ROOT" <<'REMOTE_SCRIPT'
set -euo pipefail
cd "$1"
live="$(readlink current)"
ls -1d releases/*/ | sed 's:/$::' | sort | awk -v live="$live" '$0 == live { print prev; exit } { prev = $0 }'
REMOTE_SCRIPT
)"
    [[ -n "$PREVIOUS" ]] || die "no release older than the current one to roll back to"
    echo "==> rolling back $TARGET_MODE to $PREVIOUS"
    printf '%s\n' "$ACTIVATE_SCRIPT" | remote "$DEPLOY_ROOT" "$TARGET_MODE" "$PREVIOUS" \
      "$SERVICE_NAME" "$SERVER_BINARY" "$HEALTH_WAIT_SECONDS" "$KEEP_RELEASES"
    ;;

  *)
    usage
    ;;
esac
