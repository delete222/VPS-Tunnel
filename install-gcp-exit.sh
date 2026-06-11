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
require_var GCP_INTERNAL_SOCKS_PORT

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
GCP_EXIT_CONFIG="/etc/sing-box/vps-tunnel-gcp-exit.json"
GCP_EXIT_SERVICE="vps-tunnel-gcp-exit"

cat > "$GCP_EXIT_CONFIG" <<EOF
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
  ts_ip=""
  for _ in $(seq 1 60); do
    ts_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
    [[ -n "$ts_ip" ]] && break
    sleep 2
  done
  [[ -n "$ts_ip" ]] || die "Tailscale is up, but no IPv4 address was available. Check: tailscale status"
  jq --arg ip "$ts_ip" '.inbounds += [{
    "type": "socks",
    "tag": "socks-tailscale",
    "listen": $ip,
    "listen_port": '"${GCP_INTERNAL_SOCKS_PORT}"',
    "users": [{"username": "'"${GCP_SOCKS_USER}"'", "password": "'"${GCP_SOCKS_PASSWORD}"'"}]
  }]' "$GCP_EXIT_CONFIG" > "$GCP_EXIT_CONFIG.tmp"
  mv "$GCP_EXIT_CONFIG.tmp" "$GCP_EXIT_CONFIG"
  echo "Tailscale GCP IP: $ts_ip"
elif [[ "$INNER_LINK_MODE" == "wireguard" ]]; then
  jq '.inbounds += [{
    "type": "socks",
    "tag": "socks-wireguard",
    "listen": "'"${WG_GCP_IP}"'",
    "listen_port": '"${GCP_INTERNAL_SOCKS_PORT}"',
    "users": [{"username": "'"${GCP_SOCKS_USER}"'", "password": "'"${GCP_SOCKS_PASSWORD}"'"}]
  }]' "$GCP_EXIT_CONFIG" > "$GCP_EXIT_CONFIG.tmp"
  mv "$GCP_EXIT_CONFIG.tmp" "$GCP_EXIT_CONFIG"
fi

if [[ "$INNER_LINK_MODE" == "tailscale" ]]; then
  cat > /usr/local/bin/vps-tunnel-wait-gcp-exit-tailscale <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

config="${1:?missing sing-box config path}"

for _ in $(seq 1 60); do
  ts_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  if [[ -n "$ts_ip" ]]; then
    tmp="$(mktemp)"
    jq --arg ip "$ts_ip" '(.inbounds[]? | select(.tag == "socks-tailscale") | .listen) = $ip' "$config" > "$tmp"
    /usr/local/bin/sing-box check -c "$tmp" >/dev/null
    cat "$tmp" > "$config"
    rm -f "$tmp"
    exit 0
  fi
  sleep 2
done

echo "Timed out waiting for a Tailscale IPv4 address" >&2
exit 1
EOF
  chmod 0755 /usr/local/bin/vps-tunnel-wait-gcp-exit-tailscale

  cat > /etc/systemd/system/${GCP_EXIT_SERVICE}.service <<EOF
[Unit]
Description=VPS-Tunnel GCP sing-box SOCKS exit
Documentation=https://sing-box.sagernet.org/
Wants=network-online.target tailscaled.service
After=network-online.target tailscaled.service nss-lookup.target
StartLimitIntervalSec=0

[Service]
User=root
ExecStartPre=/usr/local/bin/vps-tunnel-wait-gcp-exit-tailscale $GCP_EXIT_CONFIG
ExecStart=/usr/local/bin/sing-box run -c $GCP_EXIT_CONFIG
Restart=always
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
else
  cat > /etc/systemd/system/${GCP_EXIT_SERVICE}.service <<EOF
[Unit]
Description=VPS-Tunnel GCP sing-box SOCKS exit
Documentation=https://sing-box.sagernet.org/
Wants=network-online.target
After=network-online.target nss-lookup.target
StartLimitIntervalSec=0

[Service]
User=root
ExecStart=/usr/local/bin/sing-box run -c $GCP_EXIT_CONFIG
Restart=always
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
fi

sing-box check -c "$GCP_EXIT_CONFIG"

if systemctl cat sing-box >/dev/null 2>&1 && [[ -f /etc/sing-box/config.json ]] &&
  jq -e --argjson port "$GCP_INTERNAL_SOCKS_PORT" '
    (
      [.inbounds[]? | select(.tag == "socks-tailscale" or .tag == "socks-wireguard")] | length > 0
    ) or (
      [.inbounds[]?] as $inbounds |
      ($inbounds | length == 1) and
      ($inbounds[0].type == "socks") and
      ($inbounds[0].tag == "socks-in") and
      ($inbounds[0].listen == "127.0.0.1") and
      ($inbounds[0].listen_port == $port) and
      (.route.final == "direct")
    )
  ' /etc/sing-box/config.json >/dev/null 2>&1 &&
  systemctl cat sing-box | grep -q '/etc/sing-box/config.json'; then
  info "Disabling old VPS-Tunnel GCP exit service name: sing-box"
  systemctl disable --now sing-box >/dev/null 2>&1 || true
fi

enable_service "$GCP_EXIT_SERVICE"

info "GCP exit installed"
echo "Verify locally on GCP:"
echo "  curl --socks5 ${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@127.0.0.1:${GCP_INTERNAL_SOCKS_PORT} https://ipinfo.io/ip"
echo "Service:"
echo "  systemctl status ${GCP_EXIT_SERVICE}"
