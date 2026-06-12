#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "注意：这个兼容入口现在不会自动给 sing-box-yg 打补丁。"
echo "它只会安装/运行上游 sing-box-yg。"
echo "等你在 sing-box-yg 菜单里调好配置后，再运行："
echo "  sudo bash $SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh"
echo

"$SCRIPT_DIR/install-oracle-upstream-only.sh"
