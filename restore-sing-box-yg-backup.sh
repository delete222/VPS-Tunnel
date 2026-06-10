#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

YG_DIR="${SING_BOX_YG_DIR:-/etc/s-box}"
[[ -d "$YG_DIR" ]] || die "Cannot find sing-box-yg directory: $YG_DIR"

latest_backup="$(find "$YG_DIR" -maxdepth 1 -type d -name 'backup-before-gcp-exit-*' | sort | tail -n 1)"
[[ -n "$latest_backup" ]] || die "No backup-before-gcp-exit-* directory found in $YG_DIR"

echo "Restoring latest backup: $latest_backup"
for name in sb10.json sb11.json sb.json; do
  if [[ -f "$latest_backup/$name" ]]; then
    cp -a "$latest_backup/$name" "$YG_DIR/$name"
    echo "Restored: $YG_DIR/$name"
  fi
done

if command -v systemctl >/dev/null 2>&1 && systemctl cat sing-box >/dev/null 2>&1; then
  systemctl restart sing-box
  echo "Restarted: sing-box"
elif command -v rc-service >/dev/null 2>&1; then
  rc-service sing-box restart
  echo "Restarted: sing-box via rc-service"
else
  echo "WARN: Could not restart sing-box automatically. Restart it manually."
fi

