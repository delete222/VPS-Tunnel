#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_vars
require_var CDN_DOMAIN
require_var UUID
require_var VLESS_WS_PATH
require_var HY2_PASSWORD

out="$SCRIPT_DIR/client-sing-box.json"

cat > "$out" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query"
      }
    ],
    "final": "cloudflare"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": [
        "vless-cdn",
        "reality-direct",
        "hy2-direct"
      ],
      "default": "vless-cdn"
    },
    {
      "type": "vless",
      "tag": "vless-cdn",
      "server": "${CDN_DOMAIN}",
      "server_port": 443,
      "uuid": "${UUID}",
      "tls": {
        "enabled": true,
        "server_name": "${CDN_DOMAIN}"
      },
      "transport": {
        "type": "ws",
        "path": "${VLESS_WS_PATH}",
        "headers": {
          "Host": "${CDN_DOMAIN}"
        }
      }
    },
    {
      "type": "vless",
      "tag": "reality-direct",
      "server": "${DIRECT_DOMAIN:-$ORACLE_DE_PUBLIC_IP}",
      "server_port": ${REALITY_PORT},
      "uuid": "${UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SERVER_NAME}",
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUBLIC_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-direct",
      "server": "${DIRECT_DOMAIN:-$ORACLE_DE_PUBLIC_IP}",
      "server_port": ${HY2_PORT},
      "password": "${HY2_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${DIRECT_DOMAIN:-$CDN_DOMAIN}"
      }
    },
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
    "final": "proxy",
    "auto_detect_interface": true
  }
}
EOF

echo "Wrote $out"
echo "Important: test this only on a real China network path, not while your existing VPN is active."

