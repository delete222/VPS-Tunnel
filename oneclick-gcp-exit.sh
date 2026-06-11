#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

if [[ "${INNER_LINK_MODE:-tailscale}" != "tailscale" ]]; then
  die "oneclick-gcp-exit.sh 只用于简单 Tailscale 路线。请设置 INNER_LINK_MODE=\"tailscale\"；高级模式请直接使用 install-gcp-exit.sh。"
fi

require_var TAILSCALE_AUTH_KEY_GCP
require_var TAILSCALE_GCP_HOSTNAME
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD

if [[ "$GCP_SOCKS_PASSWORD" == "change-this-to-a-long-random-password" ]]; then
  die "请先修改 00-vars.env 里的 GCP_SOCKS_PASSWORD，并使用一个足够长的随机密码。"
fi

"$SCRIPT_DIR/install-gcp-exit.sh"

echo
echo "GCP 侧已准备好。"
echo "如果德国脚本无法自动发现 GCP，请把下面这个 Tailscale IP 填到 00-vars.env 的 TAILSCALE_GCP_IP："
tailscale ip -4 | head -n 1
