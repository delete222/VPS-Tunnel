#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

ASSUME_YES=0
REMOVE_TAILSCALE=0
REMOVE_KIT=0
BACKUP_ROOT="/root/vps-tunnel-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
YG_DIR="${SING_BOX_YG_DIR:-/etc/s-box}"
SB_PATH="${SB_PATH:-/usr/bin/sb}"
REAL_SB_PATH="${REAL_SB_PATH:-/usr/bin/sb.yg-original}"
HOOK_LIB_DIR="${HOOK_LIB_DIR:-/usr/local/lib/vps-tunnel}"
HOOK_MARKER="VPS-Tunnel auto repatch hook"

usage() {
  cat <<'EOF'
用法：
  sudo bash uninstall-vps-tunnel.sh [选项]

默认会执行：
  - 恢复被 VPS-Tunnel 包装过的 /usr/bin/sb
  - 停止并删除 vps-tunnel-gcp-exit.service
  - 停止并删除 gcp-socks-tunnel.service
  - 删除 GCP SOCKS 出口配置和等待 Tailscale 的辅助脚本
  - 如果 /etc/wireguard/wg0.conf 看起来由本项目生成，则停用并移走它
  - 恢复 sing-box-yg 打补丁前的 sb10/sb11/sb.json 备份
  - 如果没有备份，则从 sb*.json 中移除 gcp-us-exit 出站和强制路由

选项：
  --yes              不再二次确认
  --remove-tailscale 执行 tailscale down，并尝试卸载 tailscale 软件包
  --remove-kit       删除 /usr/local/bin/vpswall 和当前 VPS-Tunnel 脚本目录
  --help             显示帮助

说明：
  这个脚本不会卸载 yonggekkk/sing-box-yg 本体。
  删除/覆盖前的文件会备份到 /root/vps-tunnel-uninstall-backup-*。
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --remove-tailscale) REMOVE_TAILSCALE=1 ;;
    --remove-kit) REMOVE_KIT=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "未知参数：$1。可运行 --help 查看用法。" ;;
  esac
  shift
done

need_root

confirm() {
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  echo
  echo "将开始卸载 VPS-Tunnel 相关服务和补丁。"
  echo "备份目录：$BACKUP_ROOT"
  echo
  echo "不会卸载 sing-box-yg 本体；Tailscale 默认也不会卸载。"
  echo "如确认继续，请输入 YES："
  read -r answer
  [[ "$answer" == "YES" ]] || die "已取消。"
}

backup_path() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  local dest="$BACKUP_ROOT${path}"
  install -d -m 0700 "$(dirname "$dest")"
  cp -a "$path" "$dest"
}

remove_file_with_backup() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    backup_path "$path"
    rm -rf "$path"
    echo "已删除：$path"
  fi
}

disable_service() {
  local service="$1"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl cat "$service" >/dev/null 2>&1 || systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
      systemctl disable --now "$service" >/dev/null 2>&1 || true
      echo "已停用服务：$service"
    fi
  fi
}

remove_systemd_service() {
  local service="$1"
  disable_service "$service"
  remove_file_with_backup "/etc/systemd/system/${service}.service"
  remove_file_with_backup "/lib/systemd/system/${service}.service"
  remove_file_with_backup "/usr/lib/systemd/system/${service}.service"
}

restore_sb_script() {
  echo
  info "恢复 sb 脚本"
  if [[ -e "$REAL_SB_PATH" ]]; then
    if [[ -e "$SB_PATH" || -L "$SB_PATH" ]]; then
      backup_path "$SB_PATH"
    fi
    cp -a "$REAL_SB_PATH" "$SB_PATH"
    rm -f "$REAL_SB_PATH"
    echo "已恢复：$SB_PATH"
  elif [[ -e "$SB_PATH" ]] && grep -q "$HOOK_MARKER" "$SB_PATH" 2>/dev/null; then
    echo "警告：发现 $SB_PATH 是 VPS-Tunnel 包装器，但找不到原始备份 $REAL_SB_PATH。"
    echo "      可以重新运行 yonggekkk/sing-box-yg 安装脚本来恢复 sb 菜单。"
  else
    echo "未发现 VPS-Tunnel sb 包装器，跳过。"
  fi
  remove_file_with_backup "$HOOK_LIB_DIR"
}

cleanup_gcp_exit() {
  echo
  info "移除 GCP SOCKS 出口服务"
  remove_systemd_service "vps-tunnel-gcp-exit"
  remove_file_with_backup "/etc/sing-box/vps-tunnel-gcp-exit.json"
  remove_file_with_backup "/usr/local/bin/vps-tunnel-wait-gcp-exit-tailscale"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

cleanup_ssh_tunnel() {
  echo
  info "移除 SSH SOCKS 隧道服务"
  remove_systemd_service "gcp-socks-tunnel"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

cleanup_wireguard() {
  echo
  info "检查 WireGuard wg0"
  local wg_conf="/etc/wireguard/wg0.conf"
  if [[ ! -f "$wg_conf" ]]; then
    echo "没有发现 $wg_conf，跳过。"
    return 0
  fi

  if grep -Eq 'Address = 10\.66\.0\.(1|2)/24|AllowedIPs = 10\.66\.0\.(1|2)/32' "$wg_conf"; then
    disable_service "wg-quick@wg0"
    remove_file_with_backup "$wg_conf"
    echo "已移除疑似 VPS-Tunnel 创建的 WireGuard 配置：$wg_conf"
  else
    echo "发现 $wg_conf，但不像本项目生成的配置，为避免误删已跳过。"
  fi
}

cleanup_legacy_sing_box_service() {
  echo
  info "检查本项目自建的 /etc/sing-box/config.json"
  local config="/etc/sing-box/config.json"
  if [[ ! -f "$config" ]]; then
    echo "没有发现 $config，跳过。"
    return 0
  fi

  if command -v jq >/dev/null 2>&1 &&
    jq -e '
      ([.outbounds[]? | select(.tag == "gcp-exit" or .tag == "gcp-us-exit")] | length > 0) or
      ([.inbounds[]? | select(.tag == "vless-ws" or .tag == "vmess-ws" or .tag == "hy2" or .tag == "reality")] | length > 0)
    ' "$config" >/dev/null 2>&1; then
    if systemctl cat sing-box >/dev/null 2>&1 && systemctl cat sing-box | grep -q '/etc/sing-box/config.json'; then
      systemctl disable --now sing-box >/dev/null 2>&1 || true
      remove_file_with_backup "/etc/systemd/system/sing-box.service"
      systemctl daemon-reload >/dev/null 2>&1 || true
      echo "已停用本项目自建 sing-box.service。"
    fi
    remove_file_with_backup "$config"
  else
    echo "$config 不像本项目自建入口配置，为避免误删已跳过。"
  fi
}

restart_yg_service() {
  local restarted=0 svc
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  for svc in ${SING_BOX_YG_SERVICE_CANDIDATES:-sing-box s-box sb}; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 && systemctl cat "$svc" >/dev/null 2>&1; then
      systemctl restart "$svc" >/dev/null 2>&1 && restarted=1 && echo "已重启：$svc"
    fi
  done
  [[ "$restarted" -eq 1 ]] || echo "没有自动识别到可重启的 sing-box-yg 服务。"
}

restore_yg_from_backup() {
  local latest_backup name
  [[ -d "$YG_DIR" ]] || return 1
  latest_backup="$(find "$YG_DIR" -maxdepth 1 -type d -name 'backup-before-gcp-exit-*' | sort | tail -n 1)"
  [[ -n "$latest_backup" ]] || return 1

  echo "发现补丁前备份：$latest_backup"
  backup_path "$YG_DIR"
  for name in sb10.json sb11.json sb.json; do
    if [[ -f "$latest_backup/$name" ]]; then
      cp -a "$latest_backup/$name" "$YG_DIR/$name"
      echo "已恢复：$YG_DIR/$name"
    fi
  done
  return 0
}

remove_gcp_exit_from_yg_json() {
  local file="$1" tmp
  command -v jq >/dev/null 2>&1 || return 1
  jq empty "$file" >/dev/null 2>&1 || return 1
  tmp="$(mktemp "$(dirname "$file")/.vps-tunnel-unpatch-$(basename "$file").XXXXXX")"
  jq '
    def fix_route_outbound:
      walk(
        if type == "object" and .outbound == "gcp-us-exit"
        then .outbound = "direct"
        else .
        end
      );
    .outbounds = ((.outbounds // []) | map(select(.tag != "gcp-us-exit"))) |
    if ([.outbounds[]? | select(.tag == "direct")] | length) == 0
      then .outbounds += [{"type": "direct", "tag": "direct"}]
      else .
    end |
    if (.route.final // "") == "gcp-us-exit"
      then .route.final = "direct"
      else .
    end |
    .route = ((.route // {}) | fix_route_outbound)
  ' "$file" > "$tmp"
  jq empty "$tmp" >/dev/null 2>&1
  backup_path "$file"
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  chown --reference="$file" "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
  echo "已移除 gcp-us-exit 补丁：$file"
}

restore_or_unpatch_yg() {
  echo
  info "恢复 sing-box-yg 配置"
  if [[ ! -d "$YG_DIR" ]]; then
    echo "没有发现 sing-box-yg 目录：$YG_DIR，跳过。"
    return 0
  fi

  if restore_yg_from_backup; then
    restart_yg_service
    return 0
  fi

  echo "没有找到 backup-before-gcp-exit-* 备份，将尝试从当前配置中移除 gcp-us-exit。"
  local changed=0 name
  for name in sb10.json sb11.json sb.json; do
    if [[ -f "$YG_DIR/$name" ]] && grep -q 'gcp-us-exit' "$YG_DIR/$name"; then
      remove_gcp_exit_from_yg_json "$YG_DIR/$name" && changed=1
    fi
  done
  if [[ "$changed" -eq 1 ]]; then
    restart_yg_service
  else
    echo "没有发现 gcp-us-exit 补丁痕迹，跳过。"
  fi
}

cleanup_caddy_if_owned() {
  echo
  info "检查 Caddy 配置"
  local caddyfile="/etc/caddy/Caddyfile"
  if [[ ! -f "$caddyfile" ]]; then
    echo "没有发现 $caddyfile，跳过。"
    return 0
  fi
  if grep -qE 'vless-ws|vmess-ws|reverse_proxy .*127\.0\.0\.1' "$caddyfile"; then
    backup_path "$caddyfile"
    : > "$caddyfile"
    systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
    echo "已清空疑似本项目写入的 Caddyfile。原文件已备份。"
  else
    echo "Caddyfile 不像本项目写入的配置，为避免误删已跳过。"
  fi
}

cleanup_tailscale() {
  echo
  info "处理 Tailscale"
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "未安装 tailscale，跳过。"
    return 0
  fi

  if [[ "$REMOVE_TAILSCALE" -eq 1 ]]; then
    tailscale down >/dev/null 2>&1 || true
    if command -v apt-get >/dev/null 2>&1; then
      apt-get remove -y tailscale >/dev/null 2>&1 || true
    fi
    remove_file_with_backup "/etc/apt/sources.list.d/tailscale.list"
    remove_file_with_backup "/usr/share/keyrings/tailscale-archive-keyring.gpg"
    echo "已尝试下线并卸载 Tailscale。"
  else
    tailscale down >/dev/null 2>&1 || true
    echo "已执行 tailscale down，但保留 Tailscale 软件包。若要卸载软件包，请加 --remove-tailscale。"
  fi
}

cleanup_firewall_notes() {
  echo
  info "检查防火墙"
  echo "本项目脚本没有写入持久化 iptables/ufw 规则；如你手动在云厂商控制台放行端口，需要在控制台单独删除。"
}

cleanup_kit() {
  [[ "$REMOVE_KIT" -eq 1 ]] || return 0
  echo
  info "删除 VPS-Tunnel 脚本目录和快捷命令"
  remove_file_with_backup "/usr/local/bin/vpswall"
  if [[ "$SCRIPT_DIR" == /root/VPS-Tunnel || "$SCRIPT_DIR" == /opt/VPS-Tunnel ]]; then
    backup_path "$SCRIPT_DIR"
    rm -rf "$SCRIPT_DIR"
    echo "已删除脚本目录：$SCRIPT_DIR"
  else
    echo "当前脚本目录不是常见安装位置，为避免误删已跳过：$SCRIPT_DIR"
  fi
}

main() {
  confirm
  install -d -m 0700 "$BACKUP_ROOT"

  restore_sb_script
  cleanup_gcp_exit
  cleanup_ssh_tunnel
  cleanup_wireguard
  cleanup_legacy_sing_box_service
  restore_or_unpatch_yg
  cleanup_caddy_if_owned
  cleanup_tailscale
  cleanup_firewall_notes
  cleanup_kit

  echo
  echo "卸载/恢复流程已完成。"
  echo "备份目录：$BACKUP_ROOT"
  echo
  echo "建议检查："
  echo "  systemctl status sing-box --no-pager -l"
  echo "  sb"
}

main
