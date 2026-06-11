#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

if [[ "${INNER_LINK_MODE:-tailscale}" != "tailscale" ]]; then
  die "oneclick-oracle-after-sing-box-yg.sh 只用于简单 Tailscale 路线。请设置 INNER_LINK_MODE=\"tailscale\"；高级模式请直接使用 patch-sing-box-yg-oracle.sh。"
fi

if [[ ! -d "${SING_BOX_YG_DIR:-/etc/s-box}" ]]; then
  die "找不到 ${SING_BOX_YG_DIR:-/etc/s-box}。请先在德国 VPS 上安装 yonggekkk/sing-box-yg，然后再运行本脚本。"
fi

require_var TAILSCALE_AUTH_KEY_ORACLE
require_var TAILSCALE_ORACLE_HOSTNAME
require_var TAILSCALE_GCP_HOSTNAME
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD

if [[ "$GCP_SOCKS_PASSWORD" == "change-this-to-a-long-random-password" ]]; then
  die "请先修改 00-vars.env 里的 GCP_SOCKS_PASSWORD，并确保它和 GCP 那边一致。"
fi

"$SCRIPT_DIR/patch-sing-box-yg-oracle.sh"
CHECK_NETWORK=0 "$SCRIPT_DIR/check-oracle-patch-status.sh"
"$SCRIPT_DIR/verify-vps-links.sh" oracle

echo
echo "德国侧已打补丁。sing-box-yg 的入站节点现在应该都会从美国 GCP SOCKS 服务出站。"
echo
echo "重要提示："
echo "  如果你之后用 sing-box-yg 菜单重装、切换 sing-box 内核、"
echo "  重置配置、修改主要出站/WARP 设置，或导致 /etc/s-box/sb*.json 被重写，"
echo "  请重新运行："
echo "    sudo bash oneclick-oracle-after-sing-box-yg.sh"
echo
echo "如果只想检查补丁是否仍然生效，不修改配置，可以运行："
echo "  sudo bash check-oracle-patch-status.sh"
