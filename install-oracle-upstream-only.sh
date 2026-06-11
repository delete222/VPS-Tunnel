#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

UPSTREAM_SB_URL="${UPSTREAM_SB_URL:-https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh}"

if [[ "${INNER_LINK_MODE:-tailscale}" != "tailscale" ]]; then
  die "这个 Oracle 上游安装脚本只用于简单 Tailscale 路线。高级模式请手动安装入口后再使用 patch-sing-box-yg-oracle.sh。"
fi

require_var TAILSCALE_AUTH_KEY_ORACLE
require_var TAILSCALE_ORACLE_HOSTNAME

detect_os
install_base_packages
install_tailscale

echo "正在确认德国 Oracle 上的 Tailscale 已启动..."
if ! tailscale status >/dev/null 2>&1; then
  tailscale up --auth-key "$TAILSCALE_AUTH_KEY_ORACLE" --hostname "$TAILSCALE_ORACLE_HOSTNAME" --ssh=false
else
  echo "Tailscale 已经在线，保留当前登录状态。"
fi

echo
echo "接下来会运行最新的 yonggekkk/sing-box-yg 上游安装脚本。"
echo "请正常完成它的交互菜单。本脚本不会自动修改 yg 配置。"
echo "等你完成 sing-box-yg 的端口、证书、订阅和协议设置后，再运行："
echo "  sudo bash $SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh"
echo
echo "上游脚本地址：$UPSTREAM_SB_URL"
echo

bash <(curl -Ls "$UPSTREAM_SB_URL")

if [[ ! -d "${SING_BOX_YG_DIR:-/etc/s-box}" ]]; then
  die "上游安装脚本已结束，但没有找到 ${SING_BOX_YG_DIR:-/etc/s-box}。请先安装/配置 sing-box-yg，再运行补丁脚本。"
fi

echo
echo "sing-box-yg 已结束。此时还没有应用 GCP 出口补丁。"
echo "如果需要，请先调整 sing-box-yg 配置，然后运行："
echo "  sudo bash $SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh"
echo
echo "可选：打补丁后，可以安装 sb 自动重新打补丁钩子："
echo "  sudo bash $SCRIPT_DIR/install-yg-auto-repatch-hook.sh install"
