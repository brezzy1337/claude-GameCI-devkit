# One-time Droplet setup

Run once per Droplet, as root (or with `sudo`), on Ubuntu 24.04 LTS. Replace the defaults below with
the names chosen in `/claude-unity-devkit:setup-deploy` — they must match the workflow, `deploy.sh`
environment, the unit file, and nginx `root`.

| Placeholder | Default | Used by |
| --- | --- | --- |
| deploy user | `deploy` | SSH from CI, owns `DEPLOY_ROOT` |
| service user | `unity` | runs the dedicated server |
| server root | `/srv/unity-server` | `DEPLOY_ROOT`, unit `WorkingDirectory`/`ExecStart` |
| web root | `/var/www/unity-webgl` | `DEPLOY_ROOT`, nginx `root …/current` |
| service | `unity-server` | `SERVICE_NAME`, unit file name, sudoers rule |
| game port | `7777/udp` | firewall, server launch args |

## 1. Deploy user and SSH key (both targets)

```bash
adduser --disabled-password --gecos "" deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
# Paste the contents of deploy_key.pub (generated locally by setup-deploy's instructions):
nano /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys && chmod 600 /home/deploy/.ssh/authorized_keys
```

Then, from your machine, pin the host key for CI and compare the fingerprint with the one shown in
the DigitalOcean console:

```bash
ssh-keyscan -t ed25519 <droplet-ip> | tee /dev/stderr | gh secret set DEPLOY_KNOWN_HOSTS
ssh-keygen -lf <(ssh-keyscan -t ed25519 <droplet-ip> 2>/dev/null)
```

## 2a. Dedicated server

```bash
# Service account with no login shell; its HOME is the systemd StateDirectory
useradd --system --home-dir /var/lib/unity-server --shell /usr/sbin/nologin unity

# Release tree: owned by the deploy user, readable by the service; shared/ writable by the service
install -d -o deploy -g deploy -m 755 /srv/unity-server /srv/unity-server/releases
install -d -o unity  -g unity  -m 750 /srv/unity-server/shared

# Optional runtime config / secrets for the server (never commit these)
install -m 640 -o root -g unity /dev/null /etc/unity-server.env

# Install the unit (copied from the repo's deploy/unity-server.service)
cp unity-server.service /etc/systemd/system/unity-server.service
systemctl daemon-reload
systemctl enable unity-server        # don't start it yet — `current` appears on the first deploy

# Let the deploy user restart this one service, nothing else
echo 'deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart unity-server' > /etc/sudoers.d/deploy-unity-server
chmod 440 /etc/sudoers.d/deploy-unity-server
visudo -cf /etc/sudoers.d/deploy-unity-server

# Let the deploy user read the service journal (deploy.sh prints it when a health check fails)
usermod -aG systemd-journal deploy

# Firewall: SSH + the game port
ufw allow OpenSSH
ufw allow 7777/udp
ufw enable
```

If the Droplet sits behind a DigitalOcean Cloud Firewall, open the same ports there too.

## 2b. WebGL

```bash
apt-get update && apt-get install -y nginx certbot python3-certbot-nginx

install -d -o deploy -g deploy -m 755 /var/www/unity-webgl /var/www/unity-webgl/releases

# Install the site (copied from the repo's deploy/nginx-unity-webgl.conf, server_name/root edited)
cp nginx-unity-webgl.conf /etc/nginx/sites-available/unity-webgl.conf
ln -s /etc/nginx/sites-available/unity-webgl.conf /etc/nginx/sites-enabled/unity-webgl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw enable

# TLS — required for Brotli-compressed builds. Point DNS at the Droplet first.
certbot --nginx -d game.example.com
```

## 3. After the first deploy

```bash
# Dedicated server
systemctl status unity-server
journalctl -u unity-server -n 50 --no-pager
readlink /srv/unity-server/current

# WebGL
readlink /var/www/unity-webgl/current
curl -sI https://game.example.com/Build/WebGL.wasm.br | grep -iE 'content-(type|encoding)'
```

## Rolling back by hand

From any machine with the deploy key:

```bash
DEPLOY_HOST=<ip> DEPLOY_USER=deploy DEPLOY_ROOT=/srv/unity-server \
  SSH_KEY_PATH=./deploy_key bash deploy/deploy.sh rollback server
```

Or directly on the Droplet: `ln -sfn releases/<previous> /srv/unity-server/current.tmp &&
mv -Tf /srv/unity-server/current.tmp /srv/unity-server/current && sudo systemctl restart unity-server`.
