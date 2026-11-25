#!/usr/bin/env bash
# Railway-friendly TVM Panel launcher; also usable on ordinary Linux hosts.
set -uo pipefail
cd "$(dirname "$(realpath "$0")")"

mkdir -p data backups static/uploads/profiles static/uploads/settings static/uploads/os_icons static/img
if [[ -d /data && -w /data ]]; then
  export DATABASE_PATH="${DATABASE_PATH:-/data/tvm-panel.db}"
else
  export DATABASE_PATH="${DATABASE_PATH:-$PWD/data/tvm-panel.db}"
  echo "[TVM] WARNING: no writable Railway volume detected at /data; data may be lost on redeploy." >&2
fi
mkdir -p "$(dirname "$DATABASE_PATH")"
export HOST="0.0.0.0"
export PORT="${PORT:-5000}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
if [[ -x "$PWD/venv/bin/python" ]]; then PYTHON_BIN="$PWD/venv/bin/python"; fi

if ! "$PYTHON_BIN" -c 'import flask, flask_socketio, requests, psutil, paramiko, dotenv' >/dev/null 2>&1; then
  echo "[TVM] Required Python modules are missing. Install requirements.txt during build." >&2
  echo "[TVM] Railway build command: pip install -r requirements.txt" >&2
  exit 1
fi
failures=0
while :; do
  echo "[TVM] Launching panel at ${HOST}:${PORT}; DB=${DATABASE_PATH}"
  if "$PYTHON_BIN" -u Tvm.py; then
    echo "[TVM] Panel exited normally."
    exit 0
  else
    rc=$?
  fi
  failures=$((failures + 1))
  echo "[TVM] Panel crashed (exit ${rc}); retry ${failures}/5." >&2
  if (( failures >= 5 )); then
    echo "[TVM] Repeated startup failures. Check Railway logs and environment variables." >&2
    exit "$rc"
  fi
  sleep $((failures * 5))
done
