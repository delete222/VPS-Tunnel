#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_vars

CHECK_NETWORK="${CHECK_NETWORK:-1}"
YG_DIR="${SING_BOX_YG_DIR:-/etc/s-box}"
ok=1

[[ -d "$YG_DIR" ]] || die "Cannot find sing-box-yg directory: $YG_DIR"
require_var INNER_LINK_MODE
require_var GCP_SOCKS_USER
require_var GCP_SOCKS_PASSWORD
require_var GCP_INTERNAL_SOCKS_PORT

case "$INNER_LINK_MODE" in
  tailscale)
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
    fi
    [[ -n "${TAILSCALE_GCP_IP:-}" && "$TAILSCALE_GCP_IP" != "null" ]] || die "Cannot find GCP Tailscale IP."
    expected_host="$TAILSCALE_GCP_IP"
    expected_port="$GCP_INTERNAL_SOCKS_PORT"
    expected_network=""
    ;;
  wireguard)
    require_var WG_GCP_IP
    expected_host="$WG_GCP_IP"
    expected_port="$GCP_INTERNAL_SOCKS_PORT"
    expected_network=""
    ;;
  ssh-socks)
    require_var ORACLE_LOCAL_SOCKS_PORT
    expected_host="127.0.0.1"
    expected_port="$ORACLE_LOCAL_SOCKS_PORT"
    expected_network="tcp"
    ;;
  *)
    die "Invalid INNER_LINK_MODE=$INNER_LINK_MODE"
    ;;
esac

config_files=()
for name in sb10.json sb11.json sb.json; do
  if [[ -f "$YG_DIR/$name" ]]; then
    config_files+=("$YG_DIR/$name")
  else
    echo "INFO: optional config not found: $YG_DIR/$name"
  fi
done

[[ "${#config_files[@]}" -gt 0 ]] || die "No sing-box-yg server JSON configs found in $YG_DIR."

for file in "${config_files[@]}"; do
  echo
  echo "Checking: $file"
  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "FAIL: invalid JSON"
    ok=0
    continue
  fi

  outbound_count="$(jq '[.outbounds[]? | select(.tag == "gcp-us-exit")] | length' "$file")"
  route_final="$(jq -r '.route.final // ""' "$file")"
  outbound_matches="$(jq \
    --arg host "$expected_host" \
    --arg user "$GCP_SOCKS_USER" \
    --arg pass "$GCP_SOCKS_PASSWORD" \
    --arg network "$expected_network" \
    --argjson port "$expected_port" '
      [
        .outbounds[]? |
        select(
          .tag == "gcp-us-exit" and
          .type == "socks" and
          .server == $host and
          .server_port == $port and
          .username == $user and
          .password == $pass and
          (if $network == "" then ((.network // "") == "") else .network == $network end)
        )
      ] |
      length
    ' "$file")"
  bad_route_outbounds="$(jq -r '
    def allowed:
      . == "block" or . == "dns" or . == "dns-out" or . == "gcp-us-exit";
    [
      .. |
      objects |
      select(has("outbound") and (.outbound | type == "string")) |
      .outbound |
      select((allowed | not))
    ] |
    unique |
    join(",")
  ' "$file")"

  if [[ "$outbound_count" -eq 1 ]]; then
    echo "OK: gcp-us-exit outbound exists"
  else
    echo "FAIL: expected exactly one gcp-us-exit outbound, found $outbound_count"
    ok=0
  fi

  if [[ "$outbound_matches" -eq 1 ]]; then
    echo "OK: gcp-us-exit outbound fields match 00-vars.env"
  else
    echo "FAIL: gcp-us-exit outbound fields do not match 00-vars.env"
    ok=0
  fi

  if [[ "$route_final" == "gcp-us-exit" ]]; then
    echo "OK: route.final points to gcp-us-exit"
  else
    echo "FAIL: route.final is '${route_final:-unset}', expected gcp-us-exit"
    ok=0
  fi

  if [[ -z "$bad_route_outbounds" ]]; then
    echo "OK: no route rules bypass gcp-us-exit"
  else
    echo "FAIL: route rules still reference non-GCP outbounds: $bad_route_outbounds"
    ok=0
  fi
done

if [[ "$CHECK_NETWORK" == "1" ]]; then
  echo
  echo "Testing SOCKS exit: $expected_host:$expected_port"
  if curl --max-time 20 --socks5 "${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${expected_host}:${expected_port}" https://ipinfo.io/ip; then
    echo
    echo "OK: Germany can reach the GCP SOCKS exit."
  else
    echo
    echo "FAIL: Germany cannot reach the GCP SOCKS exit."
    ok=0
  fi
else
  echo
  echo "Skipped SOCKS network test because CHECK_NETWORK=$CHECK_NETWORK."
fi

if [[ "$ok" -eq 1 ]]; then
  echo
  echo "Oracle patch status looks OK."
else
  echo
  echo "Oracle patch status has problems. Re-run: sudo bash oneclick-oracle-after-sing-box-yg.sh"
  exit 1
fi
