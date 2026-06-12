#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/release"
OUT_FILE="$OUT_DIR/VPS-Tunnel.tar.gz"

install -d -m 0755 "$OUT_DIR"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pkg="$tmpdir/VPS-Tunnel"
mkdir -p "$pkg"

tar -cf - \
  --exclude '.git' \
  --exclude 'work' \
  --exclude 'release' \
  --exclude 'client-sing-box.json' \
  --exclude '00-vars.env' \
  -C "$SCRIPT_DIR" . | tar -xf - -C "$pkg"

tar -czf "$OUT_FILE" -C "$tmpdir" VPS-Tunnel
echo "已写入：$OUT_FILE"
