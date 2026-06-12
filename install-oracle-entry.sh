#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars
detect_os

if [[ "${I_UNDERSTAND_INSTALL_ORACLE_ENTRY_REPLACES_SERVICES:-}" != "yes" ]]; then
  cat >&2 <<'EOF'
错误：install-oracle-entry.sh 是高级备用入口，不使用 yonggekkk/sing-box-yg。
它会写入 /etc/sing-box/config.json、/etc/systemd/system/sing-box.service
以及 /etc/caddy/Caddyfile。

推荐路线：
  1. sudo bash fresh-oracle.sh
  2. 在 sing-box-yg 菜单里完成端口、证书、协议和订阅配置
  3. sudo bash oneclick-oracle-after-sing-box-yg.sh

如果你确实要使用这个备用入口安装器，请这样重新运行：
  I_UNDERSTAND_INSTALL_ORACLE_ENTRY_REPLACES_SERVICES=yes sudo -E bash install-oracle-entry.sh
EOF
  exit 1
fi

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
    info "正在启动德国 Oracle 上的 Tailscale"
    tailscale up --auth-key "$TAILSCALE_AUTH_KEY_ORACLE" --hostname "$TAILSCALE_ORACLE_HOSTNAME" --ssh=false
    GCP_SOCKS_HOST="$TAILSCALE_GCP_IP"
    ;;
  wireguard)
    require_var WG_ORACLE_PRIVATE_KEY
    require_var WG_GCP_PUBLIC_KEY
    require_var GCP_US_PUBLIC_IP
    apt-get install -y wireguard
    info "正在配置德国 Oracle 上的 WireGuard"
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
    info "正在配置 SSH SOCKS 隧道服务"
    cat > /etc/systemd/system/gcp-socks-tunnel.service <<EOF
[Unit]
Description=到 GCP SOCKS 出口的本地隧道
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
    die "INNER_LINK_MODE 配置无效：$INNER_LINK_MODE"
    ;;
esac

if [[ -z "${REALITY_PRIVATE_KEY:-}" ]]; then
  info "REALITY_PRIVATE_KEY 为空，正在生成一组 Reality 密钥建议。"
  sing-box generate reality-keypair || true
  echo "请把生成的 private/public key 填入 00-vars.env，然后重新运行本脚本启用 Reality。"
fi

info "正在安装 Caddy"
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

info "正在写入 Cloudflare WebSocket 入口的 Caddy 反向代理配置"
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

info "正在写入德国 Oracle 的 sing-box 入口服务"
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
Description=sing-box 服务
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

info "德国 Oracle 入口已安装完成"
echo "可在德国 Oracle 上这样验证内链出口："
echo "  curl --socks5 ${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${GCP_SOCKS_HOST}:${GCP_INTERNAL_SOCKS_PORT} https://ipinfo.io/ip"
