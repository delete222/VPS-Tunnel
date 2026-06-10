#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars
detect_os

require_var INNER_LINK_MODE
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD

install_base_packages
ensure_sing_box

case "$INNER_LINK_MODE" in
  tailscale)
    require_var TAILSCALE_AUTH_KEY_GCP
    require_var TAILSCALE_GCP_HOSTNAME
    install_tailscale
    info "Bringing up Tailscale on GCP"
    if ! tailscale status >/dev/null 2>&1; then
      tailscale up --auth-key "$TAILSCALE_AUTH_KEY_GCP" --hostname "$TAILSCALE_GCP_HOSTNAME" --ssh=false
    else
      echo "Tailscale is already up; keeping existing login."
    fi
    ;;
  wireguard)
    require_var WG_GCP_PRIVATE_KEY
    require_var WG_ORACLE_PUBLIC_KEY
    require_var ORACLE_DE_PUBLIC_IP
    apt-get install -y wireguard
    info "Configuring WireGuard on GCP"
    write_file /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${WG_GCP_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${WG_GCP_PRIVATE_KEY}

[Peer]
PublicKey = ${WG_ORACLE_PUBLIC_KEY}
AllowedIPs = ${WG_ORACLE_IP}/32
EOF
    chmod 600 /etc/wireguard/wg0.conf
    enable_service wg-quick@wg0
    ;;
  ssh-socks)
    info "SSH + SOCKS mode selected; GCP SOCKS will stay on 127.0.0.1 only."
    ;;
  *)
    die "Invalid INNER_LINK_MODE=$INNER_LINK_MODE"
    ;;
esac

info "Writing GCP sing-box SOCKS exit service"
install -d -m 0755 /etc/sing-box
cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": ${GCP_INTERNAL_SOCKS_PORT},
      "users": [
        {
          "username": "${GCP_SOCKS_USER}",
          "password": "${GCP_SOCKS_PASSWORD}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF

if [[ "$INNER_LINK_MODE" == "tailscale" ]]; then
  ts_ip="$(tailscale ip -4 | head -n 1)"
  jq --arg ip "$ts_ip" '.inbounds += [{
    "type": "socks",
    "tag": "socks-tailscale",
    "listen": $ip,
    "listen_port": '"${GCP_INTERNAL_SOCKS_PORT}"',
    "users": [{"username": "'"${GCP_SOCKS_USER}"'", "password": "'"${GCP_SOCKS_PASSWORD}"'"}]
  }]' /etc/sing-box/config.json > /etc/sing-box/config.json.tmp
  mv /etc/sing-box/config.json.tmp /etc/sing-box/config.json
  echo "Tailscale GCP IP: $ts_ip"
elif [[ "$INNER_LINK_MODE" == "wireguard" ]]; then
  jq '.inbounds += [{
    "type": "socks",
    "tag": "socks-wireguard",
    "listen": "'"${WG_GCP_IP}"'",
    "listen_port": '"${GCP_INTERNAL_SOCKS_PORT}"',
    "users": [{"username": "'"${GCP_SOCKS_USER}"'", "password": "'"${GCP_SOCKS_PASSWORD}"'"}]
  }]' /etc/sing-box/config.json > /etc/sing-box/config.json.tmp
  mv /etc/sing-box/config.json.tmp /etc/sing-box/config.json
fi

cat > /etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

sing-box check -c /etc/sing-box/config.json
enable_service sing-box

info "GCP exit installed"
echo "Verify locally on GCP:"
echo "  curl --socks5 ${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@127.0.0.1:${GCP_INTERNAL_SOCKS_PORT} https://ipinfo.io/ip"
