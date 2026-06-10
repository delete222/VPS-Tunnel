#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./upload-to-vps.sh <gcp-ssh-target> <oracle-ssh-target>

Examples:
  ./upload-to-vps.sh ubuntu@1.2.3.4 ubuntu@5.6.7.8
  ./upload-to-vps.sh root@gcp.example.com root@oracle.example.com

This script runs locally. It uploads the same configured VPS-Tunnel folder to:
  ~/VPS-Tunnel
on both servers.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -ne 2 ]]; then
  usage >&2
  exit 1
fi

GCP_TARGET="$1"
ORACLE_TARGET="$2"
REMOTE_DIR="VPS-Tunnel"

"$SCRIPT_DIR/check-env.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/VPS-Tunnel.tar.gz"
tar -czf "$archive" \
  --exclude '.git' \
  --exclude 'work' \
  --exclude 'release' \
  --exclude 'client-sing-box.json' \
  -C "$SCRIPT_DIR" .

upload_one() {
  local target="$1"
  echo
  echo "Uploading to $target:~/$REMOTE_DIR"
  scp "$archive" "$target:/tmp/VPS-Tunnel.tar.gz"
  ssh "$target" "rm -rf ~/$REMOTE_DIR && mkdir -p ~/$REMOTE_DIR && tar -xzf /tmp/VPS-Tunnel.tar.gz -C ~/$REMOTE_DIR && rm -f /tmp/VPS-Tunnel.tar.gz"
}

upload_one "$GCP_TARGET"
upload_one "$ORACLE_TARGET"

cat <<EOF

Upload complete.

Next:
  On GCP:
    cd ~/$REMOTE_DIR && sudo bash fresh-gcp.sh

  On Germany Oracle:
    cd ~/$REMOTE_DIR && sudo bash fresh-oracle.sh
EOF
