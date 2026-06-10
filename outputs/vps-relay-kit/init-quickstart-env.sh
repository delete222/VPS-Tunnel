#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/00-vars.env"

if [[ -e "$VARS_FILE" ]]; then
  echo "$VARS_FILE already exists; refusing to overwrite it." >&2
  exit 1
fi

socks_password="$(openssl rand -base64 32 | tr -d '\n')"

cat > "$VARS_FILE" <<EOF
# Simple recommended path:
# Germany Oracle runs yonggekkk/sing-box-yg.
# GCP provides the US exit.
# Germany and GCP connect through Tailscale.

INNER_LINK_MODE="tailscale"

# Fill these two values from the Tailscale admin console.
TAILSCALE_AUTH_KEY_GCP=""
TAILSCALE_AUTH_KEY_ORACLE=""

TAILSCALE_GCP_HOSTNAME="gcp-us-exit"
TAILSCALE_ORACLE_HOSTNAME="oracle-de-entry"

# Usually leave empty. The Germany script can auto-detect it.
TAILSCALE_GCP_IP=""

GCP_SOCKS_USER="relay"
GCP_SOCKS_PASSWORD="$socks_password"
GCP_INTERNAL_SOCKS_PORT="1080"

SING_BOX_VERSION=""
SING_BOX_YG_DIR="/etc/s-box"
SING_BOX_YG_SERVICE_CANDIDATES="sing-box s-box sb"
UPSTREAM_SB_URL="https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
EOF

cat <<EOF
Created: $VARS_FILE

Edit only these two required values before uploading this same folder to both VPS:
  TAILSCALE_AUTH_KEY_GCP
  TAILSCALE_AUTH_KEY_ORACLE

Keep this exact same 00-vars.env on both GCP and Germany Oracle.
EOF
