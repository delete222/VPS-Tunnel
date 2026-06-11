#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

UPSTREAM_SB_URL="${UPSTREAM_SB_URL:-https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh}"

if [[ "${INNER_LINK_MODE:-tailscale}" != "tailscale" ]]; then
  die "This Oracle upstream installer is for the simple Tailscale path. Use patch-sing-box-yg-oracle.sh for advanced modes after installing your entry manually."
fi

require_var TAILSCALE_AUTH_KEY_ORACLE
require_var TAILSCALE_ORACLE_HOSTNAME

detect_os
install_base_packages
install_tailscale

echo "Ensuring Tailscale is up on Germany Oracle first..."
if ! tailscale status >/dev/null 2>&1; then
  tailscale up --auth-key "$TAILSCALE_AUTH_KEY_ORACLE" --hostname "$TAILSCALE_ORACLE_HOSTNAME" --ssh=false
else
  echo "Tailscale is already up; keeping existing login."
fi

echo
echo "This script will now run the latest upstream yonggekkk/sing-box-yg installer."
echo "Finish its interactive menu normally. This script will NOT patch configs automatically."
echo "After you finish all sing-box-yg ports, certificates, subscriptions, and protocol settings, run:"
echo "  sudo bash $SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh"
echo
echo "Upstream URL: $UPSTREAM_SB_URL"
echo

bash <(curl -Ls "$UPSTREAM_SB_URL")

if [[ ! -d "${SING_BOX_YG_DIR:-/etc/s-box}" ]]; then
  die "Upstream installer finished, but ${SING_BOX_YG_DIR:-/etc/s-box} was not found. Install/configure sing-box-yg before patching."
fi

echo
echo "sing-box-yg finished. No GCP exit patch was applied yet."
echo "Tune sing-box-yg first if needed, then run:"
echo "  sudo bash $SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh"
echo
echo "Optional after patching: install the sb auto re-patch hook:"
echo "  sudo bash $SCRIPT_DIR/install-yg-auto-repatch-hook.sh install"
