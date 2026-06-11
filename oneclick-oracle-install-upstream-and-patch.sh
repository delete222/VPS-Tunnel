#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "NOTE: This compatibility script no longer patches sing-box-yg automatically."
echo "It will install/run upstream sing-box-yg only."
echo "After you finish tuning sing-box-yg, run:"
echo "  sudo bash $SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh"
echo

"$SCRIPT_DIR/install-oracle-upstream-only.sh"
