#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_vars

usage() {
  cat <<'EOF'
Usage:
  ./verify-vps-links.sh gcp
  ./verify-vps-links.sh oracle

Run "gcp" on the US GCP VPS.
Run "oracle" on the Germany Oracle VPS.
Do not run this on your local China laptop/VPN path for routing decisions.
EOF
}

role="${1:-}"
[[ -n "$role" ]] || { usage; exit 1; }

case "$role" in
  gcp)
    echo "GCP local SOCKS exit test:"
    curl --max-time 15 --socks5 "${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@127.0.0.1:${GCP_INTERNAL_SOCKS_PORT}" https://ipinfo.io/ip || true
    echo
    systemctl --no-pager --full status vps-tunnel-gcp-exit || true
    ;;
  oracle)
    echo "Germany -> GCP basic network tests:"
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
        [[ -n "$TAILSCALE_GCP_IP" && "$TAILSCALE_GCP_IP" != "null" ]] || die "Cannot auto-detect GCP Tailscale IP. Fill TAILSCALE_GCP_IP in 00-vars.env."
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
    echo "mtr to inner target: $target"
    mtr -rwzc 20 "$target" || true

    echo
    echo "Germany through GCP SOCKS exit IP:"
    if [[ "$INNER_LINK_MODE" == "ssh-socks" ]]; then
      port="$ORACLE_LOCAL_SOCKS_PORT"
    else
      port="$GCP_INTERNAL_SOCKS_PORT"
    fi
    curl --max-time 20 --socks5 "${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${target}:${port}" https://ipinfo.io/ip || true

    echo
    echo "Germany through GCP SOCKS UDP test:"
    if [[ "$INNER_LINK_MODE" == "ssh-socks" ]]; then
      echo "SKIP: ssh-socks mode uses SSH TCP forwarding, so UDP through the GCP SOCKS exit is not expected to work."
    elif ! command -v python3 >/dev/null 2>&1; then
      echo "SKIP: python3 is missing, so the SOCKS5 UDP test cannot run."
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
