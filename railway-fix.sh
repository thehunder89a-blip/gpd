#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
# Railway does not provide systemd. Run the app directly using the Railway port.
mkdir -p data backups static/uploads/profiles static/uploads/settings static/uploads/os_icons static/img
export HOST=0.0.0.0
export PORT="${PORT:-5000}"
if [[ -d /data && -w /data ]]; then export DATABASE_PATH="${DATABASE_PATH:-/data/tvm-panel.db}"; else export DATABASE_PATH="${DATABASE_PATH:-$PWD/data/tvm-panel.db}"; fi
exec python -u Tvm.py
