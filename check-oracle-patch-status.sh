#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_vars

CHECK_NETWORK="${CHECK_NETWORK:-1}"
YG_DIR="${SING_BOX_YG_DIR:-/etc/s-box}"
ok=1

[[ -d "$YG_DIR" ]] || die "找不到 sing-box-yg 目录：$YG_DIR"
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
    [[ -n "${TAILSCALE_GCP_IP:-}" && "$TAILSCALE_GCP_IP" != "null" ]] || die "找不到 GCP 的 Tailscale IP。"
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
    die "INNER_LINK_MODE 配置无效：$INNER_LINK_MODE"
    ;;
esac

config_files=()
for name in sb10.json sb11.json sb.json; do
  if [[ -f "$YG_DIR/$name" ]]; then
    config_files+=("$YG_DIR/$name")
  else
    echo "提示：可选配置文件不存在：$YG_DIR/$name"
  fi
done

[[ "${#config_files[@]}" -gt 0 ]] || die "在 $YG_DIR 里没有找到 sing-box-yg 的服务端 JSON 配置。"

for file in "${config_files[@]}"; do
  echo
  echo "正在检查：$file"
  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "失败：JSON 格式无效"
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
    echo "正常：已存在 gcp-us-exit 出站"
  else
    echo "失败：应该只有 1 个 gcp-us-exit 出站，但实际找到 $outbound_count 个"
    ok=0
  fi

  if [[ "$outbound_matches" -eq 1 ]]; then
    echo "正常：gcp-us-exit 出站参数与 00-vars.env 一致"
  else
    echo "失败：gcp-us-exit 出站参数与 00-vars.env 不一致"
    ok=0
  fi

  if [[ "$route_final" == "gcp-us-exit" ]]; then
    echo "正常：route.final 已指向 gcp-us-exit"
  else
    echo "失败：route.final 当前是 '${route_final:-未设置}'，期望是 gcp-us-exit"
    ok=0
  fi

  if [[ -z "$bad_route_outbounds" ]]; then
    echo "正常：没有发现绕过 gcp-us-exit 的路由规则"
  else
    echo "失败：仍有路由规则指向非 GCP 出站：$bad_route_outbounds"
    ok=0
  fi
done

if [[ "$CHECK_NETWORK" == "1" ]]; then
  echo
  echo "正在测试 SOCKS 出口：$expected_host:$expected_port"
  if curl --max-time 20 --socks5 "${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${expected_host}:${expected_port}" https://ipinfo.io/ip; then
    echo
    echo "正常：德国 Oracle 可以连通 GCP SOCKS 出口。"
  else
    echo
    echo "失败：德国 Oracle 无法连通 GCP SOCKS 出口。"
    ok=0
  fi
else
  echo
  echo "已跳过 SOCKS 网络测试，因为 CHECK_NETWORK=$CHECK_NETWORK。"
fi

if [[ "$ok" -eq 1 ]]; then
  echo
  echo "Oracle 补丁状态正常。"
else
  echo
  echo "Oracle 补丁状态有问题。请重新运行：sudo bash oneclick-oracle-after-sing-box-yg.sh"
  exit 1
fi
