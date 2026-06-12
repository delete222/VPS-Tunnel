#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
用法：
  ./upload-to-vps.sh <gcp-ssh-target> <oracle-ssh-target>

示例：
  ./upload-to-vps.sh ubuntu@1.2.3.4 ubuntu@5.6.7.8
  ./upload-to-vps.sh root@gcp.example.com root@oracle.example.com

这个脚本在你的本地电脑上运行。它会把同一份配置好的 VPS-Tunnel 目录上传到两台服务器的：
  ~/VPS-Tunnel
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
  echo "正在上传到 $target:~/$REMOTE_DIR"
  scp "$archive" "$target:/tmp/VPS-Tunnel.tar.gz"
  ssh "$target" "rm -rf ~/$REMOTE_DIR && mkdir -p ~/$REMOTE_DIR && tar -xzf /tmp/VPS-Tunnel.tar.gz -C ~/$REMOTE_DIR && rm -f /tmp/VPS-Tunnel.tar.gz"
}

upload_one "$GCP_TARGET"
upload_one "$ORACLE_TARGET"

cat <<EOF

上传完成。

下一步：
  在 GCP 上：
    cd ~/$REMOTE_DIR && sudo bash fresh-gcp.sh

  在德国 Oracle 上：
    cd ~/$REMOTE_DIR && sudo bash fresh-oracle.sh
    # 先在 sing-box-yg 菜单里完成端口、证书、协议和订阅配置，然后再运行：
    sudo bash oneclick-oracle-after-sing-box-yg.sh
EOF
