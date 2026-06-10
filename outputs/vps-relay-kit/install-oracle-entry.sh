#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars
detect_os

require_var CDN_DOMAIN
require_var UUID
require_var VLESS_WS_PATH
require_var VMESS_WS_PATH
require_var HY2_PASSWORD
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD

install_base_packages
ensure_sing_box

case "$INNER_LINK_MODE" in
  tailscale)
    require_var TAILSCALE_AUTH_KEY_ORACLE
    require_var TAILSCALE_ORACLE_HOSTNAME
    require_var TAILSCALE_GCP_IP
    install_tailscale
    info "Bringing up Tailscale on Germany Oracle"
    tailscale up --auth-key "$TAILSCALE_AUTH_KEY_ORACLE" --hostname "$TAILSCALE_ORACLE_HOSTNAME" --ssh=false
    GCP_SOCKS_HOST="$TAILSCALE_GCP_IP"
    ;;
  wireguard)
    require_var WG_ORACLE_PRIVATE_KEY
    require_var WG_GCP_PUBLIC_KEY
    require_var GCP_US_PUBLIC_IP
    apt-get install -y wireguard
    info "Configuring WireGuard on Germany Oracle"
    write_file /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${WG_ORACLE_IP}/24
PrivateKey = ${WG_ORACLE_PRIVATE_KEY}

[Peer]
PublicKey = ${WG_GCP_PUBLIC_KEY}
AllowedIPs = ${WG_GCP_IP}/32
Endpoint = ${GCP_US_PUBLIC_IP}:${WG_PORT}
PersistentKeepalive = 25
EOF
    chmod 600 /etc/wireguard/wg0.conf
    enable_service wg-quick@wg0
    GCP_SOCKS_HOST="$WG_GCP_IP"
    ;;
  ssh-socks)
    require_var GCP_SSH_USER
    require_var GCP_SSH_HOST
    require_var GCP_SSH_KEY_PATH
    info "Configuring SSH SOCKS tunnel service"
    cat > /etc/systemd/system/gcp-socks-tunnel.service <<EOF
[Unit]
Description=Local tunnel to GCP SOCKS exit
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/bin/ssh -NT -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -i ${GCP_SSH_KEY_PATH} -p ${GCP_SSH_PORT} -L 127.0.0.1:${ORACLE_LOCAL_SOCKS_PORT}:127.0.0.1:${GCP_INTERNAL_SOCKS_PORT} ${GCP_SSH_USER}@${GCP_SSH_HOST}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    enable_service gcp-socks-tunnel
    GCP_SOCKS_HOST="127.0.0.1"
    GCP_INTERNAL_SOCKS_PORT="$ORACLE_LOCAL_SOCKS_PORT"
    ;;
  *)
    die "Invalid INNER_LINK_MODE=$INNER_LINK_MODE"
    ;;
esac

if [[ -z "${REALITY_PRIVATE_KEY:-}" ]]; then
  info "REALITY_PRIVATE_KEY is empty. Generating a key pair suggestion."
  sing-box generate reality-keypair || true
  echo "Put the private/public keys into 00-vars.env, then rerun this script for Reality."
fi

info "Installing Caddy"
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

info "Writing Caddy reverse proxy for Cloudflare WebSocket entry"
cat > /etc/caddy/Caddyfile <<EOF
{
  servers {
    protocols h1 h2
  }
}

${CDN_DOMAIN}:${HTTPS_PORT} {
  encode zstd gzip

  @vless_ws path ${VLESS_WS_PATH}
  reverse_proxy @vless_ws 127.0.0.1:${VLESS_WS_INTERNAL_PORT}

  @vmess_ws path ${VMESS_WS_PATH}
  reverse_proxy @vmess_ws 127.0.0.1:${VMESS_WS_INTERNAL_PORT}

  respond "ok" 200
}
EOF

info "Writing Germany Oracle sing-box entry service"
install -d -m 0755 /etc/sing-box
cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "listen_port": ${VLESS_WS_INTERNAL_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "name": "${CLIENT_NAME}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${VLESS_WS_PATH}"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-in",
      "listen": "127.0.0.1",
      "listen_port": ${VMESS_WS_INTERNAL_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0,
          "name": "${CLIENT_NAME}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${VMESS_WS_PATH}"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "password": "${HY2_PASSWORD}",
          "name": "${CLIENT_NAME}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DIRECT_DOMAIN:-$CDN_DOMAIN}",
        "acme": {
          "domain": "${DIRECT_DOMAIN:-$CDN_DOMAIN}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "gcp-exit",
      "server": "${GCP_SOCKS_HOST}",
      "server_port": ${GCP_INTERNAL_SOCKS_PORT},
      "version": "5",
      "username": "${GCP_SOCKS_USER}",
      "password": "${GCP_SOCKS_PASSWORD}"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "gcp-exit"
  }
}
EOF

if [[ "$INNER_LINK_MODE" == "ssh-socks" ]]; then
  jq '(.outbounds[] | select(.tag == "gcp-exit")) += {"network": "tcp"}' /etc/sing-box/config.json > /etc/sing-box/config.json.tmp
  mv /etc/sing-box/config.json.tmp /etc/sing-box/config.json
fi

if [[ -n "${REALITY_PRIVATE_KEY:-}" ]]; then
  jq '.inbounds += [{
    "type": "vless",
    "tag": "reality-in",
    "listen": "::",
    "listen_port": '"${REALITY_PORT}"',
    "users": [{"uuid": "'"${UUID}"'", "flow": "xtls-rprx-vision", "name": "'"${CLIENT_NAME}"'"}],
    "tls": {
      "enabled": true,
      "server_name": "'"${REALITY_SERVER_NAME}"'",
      "reality": {
        "enabled": true,
        "handshake": {"server": "'"${REALITY_SERVER_NAME}"'", "server_port": 443},
        "private_key": "'"${REALITY_PRIVATE_KEY}"'",
        "short_id": ["'"${REALITY_SHORT_ID}"'"]
      }
    }
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
systemctl reload caddy || systemctl restart caddy

info "Germany Oracle entry installed"
echo "Verify internal exit from Germany:"
echo "  curl --socks5 ${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${GCP_SOCKS_HOST}:${GCP_INTERNAL_SOCKS_PORT} https://ipinfo.io/ip"
