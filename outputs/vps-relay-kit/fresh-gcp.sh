#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/check-env.sh"

echo "Fresh GCP setup:"
echo "  1. Install/join Tailscale"
echo "  2. Install sing-box"
echo "  3. Start the US SOCKS exit bound to loopback/Tailscale"
echo

"$SCRIPT_DIR/oneclick-gcp-exit.sh"
