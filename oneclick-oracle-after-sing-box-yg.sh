#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

if [[ "${INNER_LINK_MODE:-tailscale}" != "tailscale" ]]; then
  die "oneclick-oracle-after-sing-box-yg.sh is the simple Tailscale path. Set INNER_LINK_MODE=\"tailscale\" or use patch-sing-box-yg-oracle.sh for advanced modes."
fi

if [[ ! -d "${SING_BOX_YG_DIR:-/etc/s-box}" ]]; then
  die "Cannot find ${SING_BOX_YG_DIR:-/etc/s-box}. Install yonggekkk/sing-box-yg on this Germany VPS first, then rerun this script."
fi

require_var TAILSCALE_AUTH_KEY_ORACLE
require_var TAILSCALE_ORACLE_HOSTNAME
require_var TAILSCALE_GCP_HOSTNAME
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD

if [[ "$GCP_SOCKS_PASSWORD" == "change-this-to-a-long-random-password" ]]; then
  die "Please edit GCP_SOCKS_PASSWORD in 00-vars.env. It must match the GCP side."
fi

"$SCRIPT_DIR/patch-sing-box-yg-oracle.sh"
CHECK_NETWORK=0 "$SCRIPT_DIR/check-oracle-patch-status.sh"
"$SCRIPT_DIR/verify-vps-links.sh" oracle

echo
echo "Germany side is patched. Your sing-box-yg inbound nodes should now exit through the US GCP SOCKS service."
echo
echo "Important:"
echo "  If you later use the sing-box-yg menu to reinstall, switch sing-box core,"
echo "  reset configs, change major outbound/WARP settings, or otherwise rewrite"
echo "  /etc/s-box/sb*.json, run this again:"
echo "    sudo bash oneclick-oracle-after-sing-box-yg.sh"
echo
echo "To check whether the patch is still active without changing configs:"
echo "  sudo bash check-oracle-patch-status.sh"
