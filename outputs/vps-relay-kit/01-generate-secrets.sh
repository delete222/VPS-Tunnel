#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_EXAMPLE="$SCRIPT_DIR/00-vars.env.example"
VARS_FILE="$SCRIPT_DIR/00-vars.env"

if [[ -e "$VARS_FILE" ]]; then
  echo "$VARS_FILE already exists; refusing to overwrite secrets." >&2
  exit 1
fi

cp "$VARS_EXAMPLE" "$VARS_FILE"

uuid="$(command -v uuidgen >/dev/null 2>&1 && uuidgen | tr '[:upper:]' '[:lower:]' || cat /proc/sys/kernel/random/uuid)"
vless_path="/vless-$(openssl rand -hex 12)"
vmess_path="/vmess-$(openssl rand -hex 12)"
hy2_password="$(openssl rand -base64 32 | tr -d '\n')"
socks_password="$(openssl rand -base64 32 | tr -d '\n')"
reality_short_id="$(openssl rand -hex 8)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if command -v wg >/dev/null 2>&1; then
  wg genkey > "$tmp/gcp.key"
  wg pubkey < "$tmp/gcp.key" > "$tmp/gcp.pub"
  wg genkey > "$tmp/oracle.key"
  wg pubkey < "$tmp/oracle.key" > "$tmp/oracle.pub"
  wg_gcp_private="$(cat "$tmp/gcp.key")"
  wg_gcp_public="$(cat "$tmp/gcp.pub")"
  wg_oracle_private="$(cat "$tmp/oracle.key")"
  wg_oracle_public="$(cat "$tmp/oracle.pub")"
else
  wg_gcp_private=""
  wg_gcp_public=""
  wg_oracle_private=""
  wg_oracle_public=""
  echo "wg not found locally; WireGuard keys left blank. Generate them on a VPS with: wg genkey | tee private | wg pubkey" >&2
fi

perl -0pi -e "s|^UUID=.*|UUID=\"$uuid\"|m;
  s|^VLESS_WS_PATH=.*|VLESS_WS_PATH=\"$vless_path\"|m;
  s|^VMESS_WS_PATH=.*|VMESS_WS_PATH=\"$vmess_path\"|m;
  s|^HY2_PASSWORD=.*|HY2_PASSWORD=\"$hy2_password\"|m;
  s|^GCP_SOCKS_PASSWORD=.*|GCP_SOCKS_PASSWORD=\"$socks_password\"|m;
  s|^REALITY_SHORT_ID=.*|REALITY_SHORT_ID=\"$reality_short_id\"|m;
  s|^WG_GCP_PRIVATE_KEY=.*|WG_GCP_PRIVATE_KEY=\"$wg_gcp_private\"|m;
  s|^WG_GCP_PUBLIC_KEY=.*|WG_GCP_PUBLIC_KEY=\"$wg_gcp_public\"|m;
  s|^WG_ORACLE_PRIVATE_KEY=.*|WG_ORACLE_PRIVATE_KEY=\"$wg_oracle_private\"|m;
  s|^WG_ORACLE_PUBLIC_KEY=.*|WG_ORACLE_PUBLIC_KEY=\"$wg_oracle_public\"|m;" "$VARS_FILE"

cat <<EOF
Created: $VARS_FILE

Next:
1. Edit CDN_DOMAIN, DIRECT_DOMAIN, ORACLE_DE_PUBLIC_IP, GCP_US_PUBLIC_IP.
2. If using Tailscale, fill TAILSCALE_AUTH_KEY_GCP and TAILSCALE_AUTH_KEY_ORACLE.
3. Generate Reality keys on a VPS after sing-box is installed:
   sing-box generate reality-keypair
EOF

