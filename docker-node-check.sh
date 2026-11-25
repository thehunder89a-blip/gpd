#!/usr/bin/env bash
# Non-destructive Docker node diagnostic for TVM Panel deployments.
set -u
report(){ printf '\n[%s] %s\n' "$1" "$2"; }
report INFO 'Checking Docker CLI...'
if ! command -v docker >/dev/null 2>&1; then
  report ERROR 'Docker CLI not found. Install Docker Engine on this node, then rerun this check.'
  exit 2
fi
report OK "Docker CLI: $(docker --version 2>&1)"
report INFO 'Checking daemon connectivity...'
if ! docker info >/dev/null 2>&1; then
  report ERROR 'Docker daemon unavailable or current user lacks permission. Check daemon status and socket permissions.'
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --no-pager --full status docker 2>&1 | head -25
  fi
  exit 3
fi
report OK 'Docker daemon responds.'
report INFO 'Checking storage...'
docker system df 2>&1 || true
report INFO 'Checking containers...'
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1 || true
report OK 'Diagnostic completed. No containers, images, volumes, or system settings were changed.'
