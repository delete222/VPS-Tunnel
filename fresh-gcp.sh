#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/check-env.sh"

echo "GCP 全新机器初始化："
echo "  1. 安装并加入 Tailscale"
echo "  2. 安装 sing-box"
echo "  3. 启动美国 GCP SOCKS 出口服务，并监听本机/Tailscale 地址"
echo

"$SCRIPT_DIR/oneclick-gcp-exit.sh"
