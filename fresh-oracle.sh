#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/check-env.sh"

echo "Fresh Germany Oracle setup:"
echo "  1. Install/join Tailscale"
echo "  2. Run latest yonggekkk/sing-box-yg"
echo "  3. Stop and let you review/tune sing-box-yg before patching"
echo
echo "Important: run fresh-gcp.sh on the GCP VPS first."
echo

"$SCRIPT_DIR/install-oracle-upstream-only.sh"
