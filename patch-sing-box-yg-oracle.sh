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

YG_DIR="${SING_BOX_YG_DIR:-/etc/s-box}"
BACKUP_DIR="$YG_DIR/backup-before-gcp-exit-$(date +%Y%m%d-%H%M%S)"
tmp_files=()

cleanup_tmp_files() {
  local tmp
  for tmp in "${tmp_files[@]:-}"; do
    [[ -n "$tmp" ]] && rm -f "$tmp"
  done
}
trap cleanup_tmp_files EXIT

if [[ "${SKIP_BASE_PACKAGES:-0}" != "1" ]]; then
  install_base_packages
fi

case "$INNER_LINK_MODE" in
  tailscale)
    require_var TAILSCALE_AUTH_KEY_ORACLE
    require_var TAILSCALE_ORACLE_HOSTNAME
    install_tailscale
    info "正在确认德国 Oracle 上的 Tailscale 已启动"
    if ! tailscale status >/dev/null 2>&1; then
      tailscale up --auth-key "$TAILSCALE_AUTH_KEY_ORACLE" --hostname "$TAILSCALE_ORACLE_HOSTNAME" --ssh=false
    fi
    if [[ -z "${TAILSCALE_GCP_IP:-}" ]]; then
      require_var TAILSCALE_GCP_HOSTNAME
      info "TAILSCALE_GCP_IP 为空，正在根据 Tailscale 主机名自动发现：$TAILSCALE_GCP_HOSTNAME"
      TAILSCALE_GCP_IP="$(tailscale status --json | jq -r --arg host "$TAILSCALE_GCP_HOSTNAME" '
        (.Peer // {}) |
        to_entries[] |
        select(
          (.value.HostName == $host) or
          (.value.DNSName // "" | startswith($host + "."))
        ) |
        .value.TailscaleIPs[0]
      ' | head -n 1)"
      [[ -n "$TAILSCALE_GCP_IP" && "$TAILSCALE_GCP_IP" != "null" ]] || die "无法自动发现 GCP 的 Tailscale IP。请先在 GCP 运行脚本，或在 00-vars.env 里填写 TAILSCALE_GCP_IP。"
      echo "已发现 GCP Tailscale IP：$TAILSCALE_GCP_IP"
    fi
    GCP_SOCKS_HOST="$TAILSCALE_GCP_IP"
    ;;
  wireguard)
    require_var WG_ORACLE_PRIVATE_KEY
    require_var WG_GCP_PUBLIC_KEY
    require_var GCP_US_PUBLIC_IP
    apt-get install -y wireguard
    info "正在确认德国 Oracle 上的 WireGuard 已配置"
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
    info "正在确认到 GCP SOCKS 的 SSH 隧道已配置"
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
    GCP_SOCKS_NETWORK="tcp"
    ;;
  *)
    die "INNER_LINK_MODE 配置无效：$INNER_LINK_MODE"
    ;;
esac

[[ -d "$YG_DIR" ]] || die "找不到 sing-box-yg 目录：$YG_DIR。请先在德国 Oracle 上运行 yonggekkk/sing-box-yg。"

config_files=()
for name in sb10.json sb11.json sb.json; do
  [[ -f "$YG_DIR/$name" ]] && config_files+=("$YG_DIR/$name")
done
[[ "${#config_files[@]}" -gt 0 ]] || die "在 $YG_DIR 里没有找到 sing-box-yg 服务端 JSON 配置。预期文件包括 sb10.json、sb11.json 或 sb.json。"
active_config="$YG_DIR/sb.json"
has_active_config=0
[[ -f "$active_config" ]] && has_active_config=1

binary=""
if [[ -x "$YG_DIR/sing-box" ]]; then
  binary="$YG_DIR/sing-box"
elif command -v sing-box >/dev/null 2>&1; then
  binary="$(command -v sing-box)"
else
  echo "警告：找不到 sing-box 可执行文件，将跳过配置语法校验。" >&2
fi

patched_files=()
patched_tmps=()

for file in "${config_files[@]}"; do
  if ! jq empty "$file" >/dev/null 2>&1; then
    die "JSON 格式无效：$file。为避免改坏配置，本次不会打补丁。"
  fi

  tmp="$(mktemp "$(dirname "$file")/.vps-tunnel-$(basename "$file").XXXXXX")"
  tmp_files+=("$tmp")
  jq \
    --arg host "$GCP_SOCKS_HOST" \
    --arg user "$GCP_SOCKS_USER" \
    --arg pass "$GCP_SOCKS_PASSWORD" \
    --arg network "${GCP_SOCKS_NETWORK:-}" \
    --argjson port "$GCP_INTERNAL_SOCKS_PORT" '
      def keep_outbound:
        (. == "block") or (. == "dns") or (. == "dns-out") or (. == "gcp-us-exit");
      def force_route_outbound:
        walk(
          if type == "object" and has("outbound") and (.outbound | type == "string") and ((.outbound | keep_outbound) | not)
          then .outbound = "gcp-us-exit"
          else .
          end
        );
      .outbounds = ((.outbounds // []) | map(select(.tag != "gcp-us-exit"))) +
        [{
          "type": "socks",
          "tag": "gcp-us-exit",
          "server": $host,
          "server_port": $port,
          "version": "5",
          "username": $user,
          "password": $pass
        } + (if $network != "" then {"network": $network} else {} end)] |
      .route = (.route // {}) |
      .route.final = "gcp-us-exit" |
      .route = (.route | force_route_outbound)
    ' "$file" > "$tmp"

  jq empty "$tmp" >/dev/null 2>&1 || die "为 $file 生成的 JSON 无效，原文件未修改。"
  if [[ -n "$binary" ]]; then
    if ! "$binary" check -c "$tmp"; then
      if [[ "$has_active_config" -eq 0 || "$(basename "$file")" == "sb.json" ]]; then
        die "sing-box 校验配置失败：$file。原文件未修改。"
      fi
      echo "警告：可选模板 $file 的 sing-box 校验失败；这通常是旧模板不兼容新版 sing-box。因为当前运行配置 sb.json 可校验，所以仍会给这个可选模板打补丁。" >&2
    fi
  fi

  patched_files+=("$file")
  patched_tmps+=("$tmp")
done

info "正在备份 sing-box-yg 配置到 $BACKUP_DIR"
install -d -m 0700 "$BACKUP_DIR"

for i in "${!patched_files[@]}"; do
  file="${patched_files[$i]}"
  tmp="${patched_tmps[$i]}"
  cp -a "$file" "$BACKUP_DIR/$(basename "$file")"
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  chown --reference="$file" "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
  patched_tmps[$i]=""
  echo "已打补丁：$file"
done

info "正在重启可能的 sing-box-yg 服务"
restarted=0
for svc in ${SING_BOX_YG_SERVICE_CANDIDATES:-sing-box s-box sb}; do
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 && systemctl cat "$svc" >/dev/null 2>&1; then
    systemctl restart "$svc" && restarted=1 && echo "已重启：$svc"
  fi
done

if [[ "$restarted" -eq 0 ]]; then
  echo "警告：无法自动识别 sing-box-yg 的 systemd 服务。"
  echo "请运行：systemctl list-units --type=service | grep -Ei 'sing|s-box|sb'"
  echo "然后手动重启对应服务。"
fi

info "补丁完成"
echo "所有已处理的 sing-box-yg 配置现在都会使用出站标签：gcp-us-exit"
echo "可在德国 Oracle 上这样验证："
echo "  curl --socks5 ${GCP_SOCKS_USER}:${GCP_SOCKS_PASSWORD}@${GCP_SOCKS_HOST}:${GCP_INTERNAL_SOCKS_PORT} https://ipinfo.io/ip"
echo "预期结果：输出美国 GCP 的公网 IP。"
