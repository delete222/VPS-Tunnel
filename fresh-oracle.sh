#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/check-env.sh"

echo "德国 Oracle 全新机器初始化："
echo "  1. 安装并加入 Tailscale"
echo "  2. 运行最新的 yonggekkk/sing-box-yg"
echo "  3. 等你在 sing-box-yg 菜单里配置好协议/证书/订阅后，再手动运行补丁脚本"
echo
echo "重要：请先在 GCP VPS 上运行 fresh-gcp.sh。"
echo

"$SCRIPT_DIR/install-oracle-upstream-only.sh"
