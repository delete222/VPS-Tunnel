#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

YG_DIR="${SING_BOX_YG_DIR:-/etc/s-box}"
[[ -d "$YG_DIR" ]] || die "Cannot find sing-box-yg directory: $YG_DIR"
tmp_files=()

cleanup_tmp_files() {
  local tmp
  for tmp in "${tmp_files[@]:-}"; do
    [[ -n "$tmp" ]] && rm -f "$tmp"
  done
}
trap cleanup_tmp_files EXIT

latest_backup="$(find "$YG_DIR" -maxdepth 1 -type d -name 'backup-before-gcp-exit-*' | sort | tail -n 1)"
[[ -n "$latest_backup" ]] || die "No backup-before-gcp-exit-* directory found in $YG_DIR"

binary=""
if [[ -x "$YG_DIR/sing-box" ]]; then
  binary="$YG_DIR/sing-box"
elif command -v sing-box >/dev/null 2>&1; then
  binary="$(command -v sing-box)"
fi

echo "Restoring latest backup: $latest_backup"
restore_files=()
restore_tmps=()
for name in sb10.json sb11.json sb.json; do
  if [[ -f "$latest_backup/$name" ]]; then
    jq empty "$latest_backup/$name" >/dev/null 2>&1 || die "Backup JSON is invalid: $latest_backup/$name"
    tmp="$(mktemp "$YG_DIR/.vps-tunnel-restore-$name.XXXXXX")"
    tmp_files+=("$tmp")
    cp -a "$latest_backup/$name" "$tmp"
    if [[ -n "$binary" ]]; then
      "$binary" check -c "$tmp" || die "sing-box check failed for backup: $latest_backup/$name"
    fi
    restore_files+=("$name")
    restore_tmps+=("$tmp")
  fi
done

[[ "${#restore_files[@]}" -gt 0 ]] || die "Latest backup has no sb10.json, sb11.json, or sb.json files: $latest_backup"

for i in "${!restore_files[@]}"; do
  name="${restore_files[$i]}"
  tmp="${restore_tmps[$i]}"
  cp -a "$latest_backup/$name" "$YG_DIR/$name"
  rm -f "$tmp"
  restore_tmps[$i]=""
  echo "Restored: $YG_DIR/$name"
done

restarted=0
if command -v systemctl >/dev/null 2>&1; then
  for svc in ${SING_BOX_YG_SERVICE_CANDIDATES:-sing-box s-box sb}; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 && systemctl cat "$svc" >/dev/null 2>&1; then
      systemctl restart "$svc" && restarted=1 && echo "Restarted: $svc"
    fi
  done
elif command -v rc-service >/dev/null 2>&1; then
  rc-service sing-box restart
  restarted=1
  echo "Restarted: sing-box via rc-service"
fi

if [[ "$restarted" -eq 0 ]]; then
  echo "WARN: Could not restart sing-box automatically. Restart it manually."
fi
