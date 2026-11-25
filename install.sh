#!/usr/bin/env bash
# =============================================================================
#  Tvm-panel installer  -  Ubuntu 20.04+ / Debian 11+   (Dev by Tyrkrox_gamer)
#
#  Usage:   sudo bash install.sh [options]
#           sudo bash install.sh uninstall
#
#  Options:
#    --dir PATH          install location            (default /opt/Tvm-panel)
#    --port N            panel port                  (default 5000)
#    --name "TEXT"       panel name                  (default "Tvm-panel")
#    --admin-user NAME   first admin username        (default admin)
#    --admin-email MAIL  first admin email           (default admin@localhost)
#    --with-lxd          also install + init LXD (needed to create VPS)
#    --url URL           download the panel (.tar.gz / .zip) from URL (curl mode)
#    --sha256 HASH       verify the downloaded archive against this SHA-256
#    -h, --help          show this help
#
#  Re-running the script updates the panel files and keeps your .env,
#  database, backups and uploads.
# =============================================================================
set -Eeuo pipefail
# Railway is a container platform and has no systemd. When this installer is run
# inside Railway, use the platform start script instead of installing a service.
if [[ -n "${RAILWAY_ENVIRONMENT:-}${RAILWAY_PROJECT_ID:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SCRIPT_DIR/start.sh" ]]; then
    echo "[TVM] Railway detected; systemd installation is skipped. Starting panel with start.sh..."
    exec "$SCRIPT_DIR/start.sh"
  fi
  echo "[TVM] Railway detected but start.sh is missing. Deploy the full panel repository." >&2
  exit 1
fi

APP_DIR="/opt/Tvm-panel"
SERVICE="Tvm-panel"
PORT="5000"
PANEL_NAME="Tvm-panel"
ADMIN_USER="admin"
ADMIN_EMAIL="admin@localhost"
WITH_LXD=0
ACTION="install"
# One-line install: put the public URL of your panel archive here (or pass --url /
# TVM_ARCHIVE_URL) so that  curl -fsSL <install.sh url> | sudo bash  is all you need.
DEFAULT_ARCHIVE_URL=""
ARCHIVE_URL="${TVM_ARCHIVE_URL:-$DEFAULT_ARCHIVE_URL}"
ARCHIVE_SHA256="${TVM_ARCHIVE_SHA256:-}"
FIRST_INSTALL=0
ADMIN_PASS="admin123"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"

c_grn=$'\033[1;32m'; c_ylw=$'\033[1;33m'; c_red=$'\033[1;31m'; c_cyn=$'\033[1;36m'; c_off=$'\033[0m'
log()  { echo "${c_grn}[+]${c_off} $*"; }
warn() { echo "${c_ylw}[!]${c_off} $*" >&2; }
die()  { echo "${c_red}[x]${c_off} $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Tvm-panel installer (Ubuntu 20.04+ / Debian 11+)

Usage:  sudo bash install.sh [options]
        sudo bash install.sh uninstall
        curl -fsSL <install.sh url> | sudo bash -s -- --url <archive url> [options]

Options:
  --dir PATH          install location            (default /opt/Tvm-panel)
  --port N            panel port                  (default 5000)
  --name "TEXT"       panel name                  (default "Tvm-panel")
  --admin-user NAME   first admin username        (default admin)
  --admin-email MAIL  first admin email           (default admin@localhost)
  --with-lxd          also install + init LXD (needed to create VPS)
  --url URL           download the panel (.tar.gz / .zip) from URL (curl mode)
  --sha256 HASH       verify the downloaded archive against this SHA-256
  -h, --help          show this help
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|update) ACTION="install" ;;
      uninstall)      ACTION="uninstall" ;;
      --dir)          APP_DIR="${2:?--dir needs a value}"; shift ;;
      --port)         PORT="${2:?--port needs a value}"; shift ;;
      --name)         PANEL_NAME="${2:?--name needs a value}"; shift ;;
      --admin-user)   ADMIN_USER="${2:?--admin-user needs a value}"; shift ;;
      --admin-email)  ADMIN_EMAIL="${2:?--admin-email needs a value}"; shift ;;
      --with-lxd)     WITH_LXD=1 ;;
      --url)          ARCHIVE_URL="${2:?--url needs a value}"; shift ;;
      --sha256)       ARCHIVE_SHA256="${2:?--sha256 needs a value}"; shift ;;
      -h|--help)      usage; exit 0 ;;
      *)              die "Unknown option: $1 (use --help)" ;;
    esac
    shift
  done
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die "Invalid port: $PORT"
}

need_root() {
  [[ $EUID -eq 0 ]] || die "Run as root:  sudo bash install.sh"
}

check_system() {
  command -v apt-get >/dev/null || die "This installer supports Ubuntu/Debian (apt) only."
  command -v systemctl >/dev/null || die "systemd is required."
  [[ -f "$SRC_DIR/Tvm.py" && -f "$SRC_DIR/requirements.txt" ]] \
    || die "Run install.sh from inside the extracted panel folder (Tvm.py not found next to it)."
}

fetch_source() {
  [[ -f "$SRC_DIR/Tvm.py" ]] && return 0
  [[ -n "$ARCHIVE_URL" ]] || die "Panel files not found next to install.sh. Pass --url <archive.tar.gz|zip> (or set TVM_ARCHIVE_URL)."
  command -v apt-get >/dev/null || die "This installer supports Ubuntu/Debian (apt) only."
  if ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
    log "Installing download tools..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get install -y --no-install-recommends curl unzip ca-certificates
  fi
  log "Downloading panel from $ARCHIVE_URL ..."
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  local pkg="$TMP_DIR/pkg"
  curl -fsSL --retry 3 --connect-timeout 15 -o "$pkg" "$ARCHIVE_URL" || die "Download failed: $ARCHIVE_URL"
  if [[ -n "$ARCHIVE_SHA256" ]]; then
    echo "${ARCHIVE_SHA256}  ${pkg}" | sha256sum -c - >/dev/null 2>&1 || die "SHA-256 mismatch - archive not trusted."
    log "SHA-256 verified."
  fi
  mkdir -p "$TMP_DIR/x"
  if unzip -tq "$pkg" >/dev/null 2>&1; then
    unzip -q "$pkg" -d "$TMP_DIR/x"
  else
    tar -xf "$pkg" -C "$TMP_DIR/x" || die "Archive is neither a valid .zip nor .tar.gz"
  fi
  local hv
  hv="$(find "$TMP_DIR/x" -maxdepth 4 -name Tvm.py -print -quit)"
  [[ -n "$hv" ]] || die "Tvm.py not found inside the downloaded archive."
  SRC_DIR="$(dirname "$hv")"
}

install_packages() {
  log "Installing system packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev build-essential \
    libffi-dev libssl-dev sqlite3 rsync curl ca-certificates
  python3 - <<'PY' || die "Python 3.10+ is required (found $(python3 -V 2>&1))."
import sys
sys.exit(0 if sys.version_info >= (3, 10) else 1)
PY
}

copy_files() {
  if [[ "$(realpath "$SRC_DIR")" == "$(realpath -m "$APP_DIR")" ]]; then
    log "Installing in place: $APP_DIR"
    return
  fi
  log "Copying panel to $APP_DIR ..."
  mkdir -p "$APP_DIR"
  rsync -a \
    --exclude 'venv/' --exclude '.env' --exclude '*.db' --exclude '*.db-*' \
    --exclude 'backups/' --exclude '*.log' --exclude '__pycache__/' \
    --exclude 'static/uploads/' --exclude 'install.sh' \
    "$SRC_DIR"/ "$APP_DIR"/
  rm -f "$APP_DIR/hvm.py"   # old file name from before the rename to Tvm.py
  # uploads: add new files (e.g. the hosting template) but never overwrite existing ones
  mkdir -p "$APP_DIR/static/uploads"
  rsync -a --ignore-existing "$SRC_DIR/static/uploads/" "$APP_DIR/static/uploads/"
  [[ -f "$SRC_DIR/install.sh" ]] && cp -f "$SRC_DIR/install.sh" "$APP_DIR/install.sh"
  mkdir -p "$APP_DIR/backups"
}

setup_venv() {
  log "Creating Python virtualenv and installing requirements (this can take a few minutes)..."
  [[ -d "$APP_DIR/venv" ]] || python3 -m venv "$APP_DIR/venv"
  "$APP_DIR/venv/bin/python" -m pip install --upgrade pip wheel setuptools
  "$APP_DIR/venv/bin/python" -m pip install -r "$APP_DIR/requirements.txt"
}

rand_alnum() {  # rand_alnum LENGTH
  python3 -c "import secrets,string,sys; a=string.ascii_letters+string.digits; print(''.join(secrets.choice(a) for _ in range(int(sys.argv[1]))))" "$1"
}

detect_ip() {
  local ip
  ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "${ip:-127.0.0.1}"
}

write_env() {
  local envf="$APP_DIR/.env"
  if [[ -f "$envf" ]]; then
    log "Keeping existing $envf"
    local p; p="$(grep -E '^PORT=' "$envf" | tail -n1 | cut -d= -f2- | tr -d '"' || true)"
    [[ -n "$p" ]] && PORT="$p"
    return
  fi
  FIRST_INSTALL=1
  log "Generating $envf ..."
  umask 077
  cat > "$envf" <<EOF
# Tvm-panel configuration (read by systemd via EnvironmentFile)
PANEL_NAME="${PANEL_NAME}"
PANEL_DEVELOPER="Tyrkrox_gamer"
SECRET_KEY="$(rand_alnum 64)"
HOST="0.0.0.0"
PORT="${PORT}"
YOUR_SERVER_IP="$(detect_ip)"

# First admin account (only used when the database is created)
MAIN_ADMIN_USERNAME="${ADMIN_USER}"
MAIN_ADMIN_PASSWORD="${ADMIN_PASS}"
MAIN_ADMIN_EMAIL="${ADMIN_EMAIL}"

DEFAULT_STORAGE_POOL="default"
DEBUG_MODE="False"
EOF
  chmod 600 "$envf"
}

install_lxd() {
  if command -v lxc >/dev/null 2>&1; then
    log "LXC/LXD already installed."
    return
  fi
  if [[ $WITH_LXD -eq 1 ]]; then
    log "Installing LXD (snap)..."
    command -v snap >/dev/null 2>&1 || apt-get install -y snapd
    snap install lxd
    export PATH="$PATH:/snap/bin"
    lxd init --auto || warn "'lxd init --auto' failed - run 'lxd init' manually."
  else
    warn "LXD (lxc) not found. The panel will run, but creating VPS needs LXD."
    warn "Install it later with:  sudo bash install.sh --with-lxd"
  fi
}

write_service() {
  log "Creating systemd service: $SERVICE"
  cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=Tvm-panel (Dev by Tyrkrox_gamer)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
ExecStart=${APP_DIR}/venv/bin/python ${APP_DIR}/Tvm.py
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    log "Opening port ${PORT}/tcp in ufw"
    ufw allow "${PORT}/tcp" >/dev/null
  fi
}

start_service() {
  if ss -ltn "sport = :${PORT}" 2>/dev/null | grep -q LISTEN && ! systemctl is-active --quiet "$SERVICE"; then
    warn "Port ${PORT} is already in use by another program. Change PORT in $APP_DIR/.env and restart."
  fi
  log "Starting panel..."
  systemctl enable "$SERVICE" >/dev/null 2>&1
  systemctl restart "$SERVICE"
  local i
  for i in $(seq 1 45); do
    if curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      log "Panel is up."
      return 0
    fi
    sleep 1
  done
  warn "Panel did not answer on port ${PORT} yet. Recent log:"
  journalctl -u "$SERVICE" -n 25 --no-pager || true
  return 1
}

summary() {
  local ip; ip="$(grep -E '^YOUR_SERVER_IP=' "$APP_DIR/.env" | cut -d= -f2- | tr -d '"')"
  echo
  echo "${c_cyn}================================================================${c_off}"
  echo "${c_cyn}  Tvm-panel installed${c_off}   (Dev by tyrkrox_tech)"
  echo "${c_cyn}================================================================${c_off}"
  echo "  URL:       http://${ip:-YOUR_SERVER_IP}:${PORT}"
  if [[ $FIRST_INSTALL -eq 1 ]]; then
    echo "  Username:  ${ADMIN_USER}"
    echo "  Password:  ${ADMIN_PASS}     <- save it now (also stored in ${APP_DIR}/.env)"
  else
    echo "  Login:     unchanged (see MAIN_ADMIN_* in ${APP_DIR}/.env; applies only to a new database)"
  fi
  echo
  echo "  Status:    systemctl status ${SERVICE}"
  echo "  Logs:      journalctl -u ${SERVICE} -f"
  echo "  Restart:   systemctl restart ${SERVICE}"
  echo "  Config:    nano ${APP_DIR}/.env && systemctl restart ${SERVICE}"
  echo "  Uninstall: sudo bash ${APP_DIR}/install.sh uninstall"
  echo "${c_cyn}================================================================${c_off}"
}

do_install() {
  need_root
  fetch_source
  check_system
  install_packages
  copy_files
  setup_venv
  write_env
  install_lxd
  write_service
  open_firewall
  start_service || true
  summary
}

do_uninstall() {
  need_root
  log "Stopping and removing service ${SERVICE} ..."
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  systemctl daemon-reload
  log "Service removed. Your data is still in ${APP_DIR}"
  log "To delete everything:  rm -rf ${APP_DIR}"
}

main() {
  parse_args "$@"
  # Railway is an ephemeral container, not a systemd-based VPS. If the installer
  # is accidentally run there, launch the app instead of failing at systemd check.
  if [[ "$ACTION" == "install" && ( -n "${RAILWAY_ENVIRONMENT:-}" || -n "${RAILWAY_PROJECT_ID:-}" || -n "${RAILWAY_SERVICE_ID:-}" ) ]]; then
    if [[ -x "$SRC_DIR/start.sh" ]]; then
      warn "Railway environment detected; systemd installer is skipped. Starting TVM with start.sh."
      exec "$SRC_DIR/start.sh"
    fi
    die "Railway detected but start.sh is missing. Use the complete panel archive."
  fi
  case "$ACTION" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
  esac
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
