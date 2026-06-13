#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/00-vars.env"

pause() {
  echo
  read -r -p "按回车键返回菜单..." _
}

run_script() {
  local script="$1"
  shift || true
  if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
    chmod +x "$SCRIPT_DIR/$script" 2>/dev/null || true
  fi
  echo
  echo "正在运行：$script $*"
  echo
  bash "$SCRIPT_DIR/$script" "$@"
}

run_action() {
  set +e
  (set -e; "$@")
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo
    echo "操作失败，退出码：$rc"
  fi
  return 0
}

confirm_overwrite() {
  if [[ -e "$VARS_FILE" ]]; then
    echo "当前已经存在：$VARS_FILE"
    read -r -p "确定要覆盖它吗？输入 YES 继续： " answer
    [[ "$answer" == "YES" ]] || {
      echo "已取消。"
      return 1
    }
  fi
}

env_new() {
  local tmpdir
  confirm_overwrite || return 0
  tmpdir="$(mktemp -d)"
  cp "$SCRIPT_DIR/init-quickstart-env.sh" "$tmpdir/init-quickstart-env.sh"
  chmod +x "$tmpdir/init-quickstart-env.sh"
  (
    cd "$tmpdir"
    bash ./init-quickstart-env.sh
  )
  install -m 0600 "$tmpdir/00-vars.env" "$VARS_FILE"
  rm -rf "$tmpdir"
  echo
  echo "请编辑 $VARS_FILE，至少填入："
  echo "  TAILSCALE_AUTH_KEY_GCP"
  echo "  TAILSCALE_AUTH_KEY_ORACLE"
  echo
  echo "重要：两台 VPS 必须使用同一份 00-vars.env。"
}

env_show() {
  if [[ ! -f "$VARS_FILE" ]]; then
    echo "还没有配置文件：$VARS_FILE"
    return 0
  fi
  echo "当前配置文件：$VARS_FILE"
  echo
  cat "$VARS_FILE"
}

env_paste() {
  confirm_overwrite || return 0

  tmp="$(mktemp)"
  echo "请粘贴完整的 00-vars.env 内容。"
  echo "粘贴完成后，单独输入一行 EOF 然后回车。"
  echo
  while IFS= read -r line; do
    [[ "$line" == "EOF" ]] && break
    printf '%s\n' "$line" >> "$tmp"
  done

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    echo "没有读取到内容，已取消。"
    return 0
  fi

  if ! bash -n "$tmp"; then
    rm -f "$tmp"
    echo "粘贴内容不是合法的 shell env 文件，已取消。"
    return 1
  fi

  if ! awk '
    /^[[:space:]]*($|#)/ { next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/ {
      value=$0
      sub(/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value ~ /[$`\\;&|<>!]/) {
        bad=1
        print "配置值包含不允许的 shell 元字符：" NR ": " $0 > "/dev/stderr"
        next
      }
      if (value ~ /^"[^"]*"$/ || value ~ /^'\''[^'\'']*'\''$/ || value !~ /[^-A-Za-z0-9_.\/:@%+=,]/) {
        next
      }
    }
    { bad=1; print "不支持的配置行：" NR ": " $0 > "/dev/stderr" }
    END { exit bad }
  ' "$tmp"; then
    rm -f "$tmp"
    echo "粘贴内容只能包含注释、空行和简单 KEY=VALUE 配置，已取消。"
    return 1
  fi

  install -m 0600 "$tmp" "$VARS_FILE"
  rm -f "$tmp"
  echo "已写入：$VARS_FILE"
  echo "可以继续选择“检查配置”确认必填项。"
}

env_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<EOF
VPS-Tunnel 环境配置

1. 新建配置
2. 查看当前配置
3. 粘入已有配置
4. 检查配置
0. 返回主菜单

EOF
    read -r -p "请选择： " choice
    case "$choice" in
      1) run_action env_new; pause ;;
      2) run_action env_show; pause ;;
      3) run_action env_paste; pause ;;
      4) run_action run_script check-env.sh; pause ;;
      0) return 0 ;;
      *) echo "无效选项：$choice"; pause ;;
    esac
  done
}

run_yg_menu() {
  if command -v sb >/dev/null 2>&1; then
    sb
  elif [[ -x /usr/bin/sb ]]; then
    /usr/bin/sb
  else
    echo "没有找到 sb 命令。请先在 Oracle 上运行 fresh-oracle.sh 安装 sing-box-yg。"
    return 1
  fi
}

test_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<EOF
VPS-Tunnel 测试菜单

1. GCP 本机出口测试
2. Oracle 到 GCP 出口测试
3. Oracle 补丁状态检查
0. 返回主菜单

EOF
    read -r -p "请选择： " choice
    case "$choice" in
      1) run_action run_script verify-vps-links.sh gcp; pause ;;
      2) run_action run_script verify-vps-links.sh oracle; pause ;;
      3) run_action run_script check-oracle-patch-status.sh; pause ;;
      0) return 0 ;;
      *) echo "无效选项：$choice"; pause ;;
    esac
  done
}

other_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<EOF
VPS-Tunnel 其他脚本

1. 只运行上游 sing-box-yg 安装脚本
2. 安装 sb 自动重新打补丁钩子
3. 移除 sb 自动重新打补丁钩子
4. 恢复最近一次 sing-box-yg 备份
5. 生成客户端配置
6. 高级备用：自建 Oracle 入口
0. 返回主菜单

EOF
    read -r -p "请选择： " choice
    case "$choice" in
      1) run_action run_script install-oracle-upstream-only.sh; pause ;;
      2) run_action run_script install-yg-auto-repatch-hook.sh install; pause ;;
      3) run_action run_script install-yg-auto-repatch-hook.sh remove; pause ;;
      4) run_action run_script restore-sing-box-yg-backup.sh; pause ;;
      5) run_action run_script generate-client-config.sh; pause ;;
      6) run_action run_script install-oracle-entry.sh; pause ;;
      0) return 0 ;;
      *) echo "无效选项：$choice"; pause ;;
    esac
  done
}

update_self() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "更新需要 root 权限。请使用 sudo vpswall，或重新运行安装命令。"
    return 1
  fi
  echo "正在更新 VPS-Tunnel..."
  cd /
  curl -fsSL https://raw.githubusercontent.com/delete222/VPS-Tunnel/main/install-vpswall.sh | VPSWALL_DIR="$SCRIPT_DIR" VPSWALL_NO_MENU=1 bash
  cd "$SCRIPT_DIR"
}

main_menu() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "提示：多数安装/更新操作需要 root 权限。建议使用：sudo vpswall"
    pause
  fi

  while true; do
    clear 2>/dev/null || true
    cat <<EOF
VPS-Tunnel 主菜单

脚本目录：$SCRIPT_DIR

1. 环境配置
2. 运行 GCP 出口脚本
3. 运行 Oracle 入口脚本
4. Oracle 打 GCP 出口补丁
5. 打开 sing-box-yg 菜单
6. 测试/检查
7. 更新 VPS-Tunnel 脚本
8. 其他脚本
0. 退出

EOF
    read -r -p "请选择： " choice
    case "$choice" in
      1) env_menu ;;
      2) run_action run_script fresh-gcp.sh; pause ;;
      3) run_action run_script fresh-oracle.sh; pause ;;
      4) run_action run_script oneclick-oracle-after-sing-box-yg.sh; pause ;;
      5) run_action run_yg_menu; pause ;;
      6) test_menu ;;
      7) run_action update_self; pause ;;
      8) other_menu ;;
      0) exit 0 ;;
      *) echo "无效选项：$choice"; pause ;;
    esac
  done
}

main_menu
