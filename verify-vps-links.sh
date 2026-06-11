#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_vars

usage() {
  cat <<'EOF'
用法：
  ./verify-vps-links.sh gcp
  ./verify-vps-links.sh oracle

在美国 GCP VPS 上运行 gcp。
在德国 Oracle VPS 上运行 oracle。
不要用你本机或本机 VPN 的测速结果来判断线路质量。
EOF
}

role="${1:-}"
[[ -n "$role" ]] || { usage; exit 1; }

case "$role" in
  gcp)
    echo "GCP 本机 SOCKS 出口测试："
    curl --max-time 15 --socks5 "${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@127.0.0.1:${GCP_INTERNAL_SOCKS_PORT}" https://ipinfo.io/ip || true
    echo
    systemctl --no-pager --full status vps-tunnel-gcp-exit || true
    ;;
  oracle)
    echo "德国 Oracle -> 美国 GCP 内链基础测试："
    if [[ "$INNER_LINK_MODE" == "tailscale" ]]; then
      if [[ -z "${TAILSCALE_GCP_IP:-}" ]]; then
        require_var TAILSCALE_GCP_HOSTNAME
        TAILSCALE_GCP_IP="$(tailscale status --json | jq -r --arg host "$TAILSCALE_GCP_HOSTNAME" '
          (.Peer // {}) |
          to_entries[] |
          select(
            (.value.HostName == $host) or
            (.value.DNSName // "" | startswith($host + "."))
          ) |
          .value.TailscaleIPs[0]
        ' | head -n 1)"
        [[ -n "$TAILSCALE_GCP_IP" && "$TAILSCALE_GCP_IP" != "null" ]] || die "无法自动发现 GCP 的 Tailscale IP。请在 00-vars.env 里填写 TAILSCALE_GCP_IP。"
      fi
      tailscale status || true
      tailscale ping "$TAILSCALE_GCP_IP" || true
      target="$TAILSCALE_GCP_IP"
    elif [[ "$INNER_LINK_MODE" == "wireguard" ]]; then
      wg show || true
      target="$WG_GCP_IP"
    else
      target="127.0.0.1"
    fi

    echo
    echo "到内链目标的 mtr 测试：$target"
    mtr -rwzc 20 "$target" || true

    echo
    echo "德国经 GCP SOCKS 出口访问 ipinfo 的出口 IP："
    if [[ "$INNER_LINK_MODE" == "ssh-socks" ]]; then
      port="$ORACLE_LOCAL_SOCKS_PORT"
    else
      port="$GCP_INTERNAL_SOCKS_PORT"
    fi
    curl --max-time 20 --socks5 "${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${target}:${port}" https://ipinfo.io/ip || true

    echo
    echo "德国经 GCP SOCKS 的 UDP 测试："
    if [[ "$INNER_LINK_MODE" == "ssh-socks" ]]; then
      echo "跳过：ssh-socks 模式使用 SSH TCP 转发，通常不支持通过 GCP SOCKS 出口转发 UDP。"
    elif ! command -v python3 >/dev/null 2>&1; then
      echo "跳过：系统没有 python3，无法运行 SOCKS5 UDP 测试。"
    else
      python3 "$SCRIPT_DIR/test-socks5-udp.py" \
        --proxy-host "$target" \
        --proxy-port "$port" \
        --username "$GCP_SOCKS_USER" \
        --password "$GCP_SOCKS_PASSWORD" || true
    fi
    echo
    systemctl --no-pager --full status sing-box || true
    echo
    "$SCRIPT_DIR/check-oracle-patch-status.sh" || true
    ;;
  *)
    usage
    exit 1
    ;;
esac
