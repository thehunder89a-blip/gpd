# tvm-panel

Web-based LXC VPS management panel. **Dev by tyrkrox_tech**

## One-line install (Ubuntu 20.04+ / Debian 11+, run as root)

```bash
curl -fsSL https://YOUR_HOST/install.sh | sudo bash -s -- --url https://YOUR_HOST/avm_panel.zip --with-lxd
```

That single command installs the system packages, downloads the panel, creates the virtualenv,
generates a secure `.env` (random `SECRET_KEY` + admin password), sets up the `avm-panel` systemd
service, opens the port in ufw and starts the panel. The URL and admin login are printed at the end.

> Replace `YOUR_HOST` with the place where you upload `install.sh` and the panel archive (`.zip` or `.tar.gz`).
> Drop `--with-lxd` if LXD is already installed (LXD is required to create VPS).

Same thing with process substitution:

```bash
sudo bash <(curl -fsSL https://YOUR_HOST/install.sh) --url https://YOUR_HOST/avm_panel.zip --with-lxd
```

### Make it even shorter
Put your archive URL inside `install.sh` once (before you upload it):

```bash
sed -i 's|^DEFAULT_ARCHIVE_URL=.*|DEFAULT_ARCHIVE_URL="https://YOUR_HOST/avm_panel.zip"|' install.sh
```

Then users only need:

```bash
curl -fsSL https://YOUR_HOST/install.sh | sudo bash
```

### GitHub example
Upload the panel files (with `install.sh` in the repo root) to a **public** repo, then:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install.sh | sudo bash -s -- \
  --url https://github.com/YOUR_USER/YOUR_REPO/archive/refs/heads/main.tar.gz --with-lxd
```

Anyone who knows the URLs can download the panel, so host it only where you want that. Private repos do
not work with plain `curl`.

### Verify the download (optional)
```bash
sha256sum astralhvm.zip      # run this where you built the archive
curl -fsSL https://YOUR_HOST/install.sh | sudo bash -s -- --url https://YOUR_HOST/avm_panel.zip --sha256 <hash>
```
The installer aborts if the hash does not match.

## Options

| Option | Default | Meaning |
|---|---|---|
| `--url URL` | – | Panel archive (`.zip` / `.tar.gz`) to download (curl mode) |
| `--sha256 HASH` | – | Verify the archive before installing |
| `--dir PATH` | `/opt/avm-panel` | Install location |
| `--port N` | `5000` | Panel port |
| `--name "TEXT"` | `tvm-panel` | Panel name |
| `--admin-user NAME` | `admin` | First admin username |
| `--admin-email MAIL` | `admin@localhost` | First admin email |
| `--with-lxd` | off | Install and initialise LXD (snap) |

Environment variables `AVM_ARCHIVE_URL` and `AVM_ARCHIVE_SHA256` work like `--url` / `--sha256`.

## Manual install (from the zip)

```bash
unzip astralhvm.zip && cd astral
sudo bash install.sh --with-lxd
```

## After install

- Open `http://SERVER_IP:5000` and log in with the admin user/password printed by the installer
  (they are also in `/opt/avm-panel/.env`, readable by root only).
- Manage the service:

```bash
systemctl status avm-panel
journalctl -u avm-panel -f
systemctl restart avm-panel
```

## Configuration

Edit `/opt/avm-panel/.env`, then `systemctl restart avm-panel`.

| Variable | Meaning |
|---|---|
| `PANEL_NAME` | Name shown in the panel |
| `PORT` / `HOST` | Listen port / address |
| `SECRET_KEY` | Session + encryption key (do not change after install) |
| `YOUR_SERVER_IP` | Public IP shown in the panel |
| `MAIN_ADMIN_USERNAME` / `MAIN_ADMIN_PASSWORD` / `MAIN_ADMIN_EMAIL` | First admin; used only when the database is created |

## Discord bot (deploy VPS from Discord)

Open **Admin -> Discord Bot** in the panel, paste the bot token, your Discord user ID (main admin) and press
**Save & (re)start bot**. Optional: change the bot name, add extra admins, set member limits and the target node.

| Command | Who | What it does |
|---|---|---|
| `/register` `/deploy` `/myvps` `/vpsinfo` `/start` `/stop` `/restart` `/password` `/ostemplates` | members | create an account, deploy and manage their own VPS |
| `/allvps` `/deploy_for` `/delete` `/suspend` `/unsuspend` `/link` `/nodes` `/stats` | bot admins | manage every VPS and user |
| `/addadmin` `/removeadmin` `/botadmins` `/setname` | main admin | manage bot admins and the bot name |

Two engines are included, pick one in **Admin -> Discord Bot -> Bot engine**:

- **Custom bot (`bot.py`)** - prefix commands (`!help`), manages LXC containers directly and keeps its own `vps.db`. Token, bot name, main admin, prefix and server IP come from the panel page. It needs the *Message Content* and *Server Members* intents enabled in the Discord developer portal.
- **Panel bot (`discord_bot.py`)** - slash commands, talks to the panel's REST API so VPS appear in the panel.

The bot runs as a child process of the panel (console log: `bot_console.log`).
It needs `discord.py`, which the installer adds to the venv automatically.

## Video background

A looping animated background (`static/video/avm-arctic.mp4`) is enabled by default. Change or disable it in
**Admin -> Settings -> Video background** (any direct `.mp4` URL works).

## Update

Run the same install command again. Panel files are updated; `.env`, the database, backups and uploads are kept.

## Uninstall

```bash
sudo bash /opt/avm-panel/install.sh uninstall     # removes the service, keeps your data
sudo rm -rf /opt/avm-panel                        # optional: delete everything
```

## Notes

- The installer must run as root and supports Ubuntu/Debian (apt + systemd).
- Without LXD the panel runs, but VPS cannot be created. Add it later with `sudo bash install.sh --with-lxd`.
- `node.py` is the agent for remote nodes and is installed separately on those machines.
- Logs: `avm.log` in the install folder and `journalctl -u avm-panel`.

## Railway deployment

This repository includes `railway.json`, `Procfile`, and `start.sh` for Railway.
Deploy the repository, set a persistent Railway Volume mounted at `/data`, and use
`./start.sh` as the start command (already configured). The panel uses
`/data/tvm-panel.db` for SQLite when `/data` is mounted and writable. Without a
volume, Railway redeploys/restarts may lose local database data.

**VPS provisioning note:** Railway is a hosted application container and is not a
reliable privileged virtualization host. For VPS creation, add a separate Linux
node with supported LXD/LXC and configure that node in the panel. The launcher
can restart the web process after crashes, but it cannot safely auto-repair every
system, networking, database, or virtualization failure; check logs and node
health for those.

## Docker node diagnostic (non-destructive)

This build includes `docker-node-check.sh` for a Docker-enabled node. Run it on the node:

```bash
bash docker-node-check.sh
```
It checks CLI/daemon access, storage usage, and container status. It does not automatically change host settings or delete Docker resources. **The current TVM node agent is LXC/LXD-based; this diagnostic does not convert its VPS provisioning backend to Docker.**
