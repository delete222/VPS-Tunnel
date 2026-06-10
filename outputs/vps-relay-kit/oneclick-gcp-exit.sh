#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

if [[ "${INNER_LINK_MODE:-tailscale}" != "tailscale" ]]; then
  die "oneclick-gcp-exit.sh is the simple Tailscale path. Set INNER_LINK_MODE=\"tailscale\" or use install-gcp-exit.sh for advanced modes."
fi

require_var TAILSCALE_AUTH_KEY_GCP
require_var TAILSCALE_GCP_HOSTNAME
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD

if [[ "$GCP_SOCKS_PASSWORD" == "change-this-to-a-long-random-password" ]]; then
  die "Please edit GCP_SOCKS_PASSWORD in 00-vars.env. Use a long random password."
fi

"$SCRIPT_DIR/install-gcp-exit.sh"

echo
echo "GCP side is ready."
echo "Copy this Tailscale IP into 00-vars.env as TAILSCALE_GCP_IP if the Germany script cannot auto-detect it:"
tailscale ip -4 | head -n 1
