#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

need_root
load_vars

SB_PATH="${SB_PATH:-/usr/bin/sb}"
REAL_SB_PATH="${REAL_SB_PATH:-/usr/bin/sb.yg-original}"
HOOK_LIB_DIR="${HOOK_LIB_DIR:-/usr/local/lib/vps-tunnel}"
DEFAULT_HOOK_LIB_DIR="/usr/local/lib/vps-tunnel"
HOOK_MARKER="VPS-Tunnel auto repatch hook"

install_hook_files() {
  install -d -m 0700 "$HOOK_LIB_DIR"
  install -d -m 0700 "$HOOK_LIB_DIR/lib"
  install -m 0600 "$SCRIPT_DIR/00-vars.env" "$HOOK_LIB_DIR/00-vars.env"
  install -m 0600 "$SCRIPT_DIR/lib/common.sh" "$HOOK_LIB_DIR/lib/common.sh"
  install -m 0700 "$SCRIPT_DIR/check-oracle-patch-status.sh" "$HOOK_LIB_DIR/check-oracle-patch-status.sh"
  install -m 0700 "$SCRIPT_DIR/patch-sing-box-yg-oracle.sh" "$HOOK_LIB_DIR/patch-sing-box-yg-oracle.sh"
  install -m 0700 "$SCRIPT_DIR/oneclick-oracle-after-sing-box-yg.sh" "$HOOK_LIB_DIR/oneclick-oracle-after-sing-box-yg.sh"
  install -m 0700 "$SCRIPT_DIR/verify-vps-links.sh" "$HOOK_LIB_DIR/verify-vps-links.sh"
  install -m 0700 "$SCRIPT_DIR/test-socks5-udp.py" "$HOOK_LIB_DIR/test-socks5-udp.py"
  printf '%s\n' "$HOOK_MARKER" > "$HOOK_LIB_DIR/.vps-tunnel-hook"
  chown -R root:root "$HOOK_LIB_DIR"
  chmod 0600 "$HOOK_LIB_DIR/.vps-tunnel-hook"
}

install_hook() {
  [[ -x "$SB_PATH" ]] || die "找不到可执行文件 $SB_PATH。请先安装 yonggekkk/sing-box-yg。"
  [[ ! -L "$SB_PATH" ]] || die "$SB_PATH 是软链接。为避免覆盖软链接目标，本脚本不会包装它。请先换成真实文件后再运行。"

  if grep -q "$HOOK_MARKER" "$SB_PATH" 2>/dev/null; then
    install_hook_files
    echo "$SB_PATH 已经安装 VPS-Tunnel 自动重新打补丁钩子，已刷新 $HOOK_LIB_DIR。"
    return
  fi

  if [[ -e "$REAL_SB_PATH" ]]; then
    die "$REAL_SB_PATH 已存在。为避免覆盖已有备份，本次停止。"
  fi

  install_hook_files
  cp -a "$SB_PATH" "$REAL_SB_PATH"

  cat > "$SB_PATH" <<EOF
#!/usr/bin/env bash
# $HOOK_MARKER
set -euo pipefail

REAL_SB="$REAL_SB_PATH"
KIT_DIR="$HOOK_LIB_DIR"
export VARS_FILE="\$KIT_DIR/00-vars.env"

set +e
"\$REAL_SB" "\$@"
rc=\$?
set -e

if [[ "\$rc" -eq 0 && -x "\$KIT_DIR/check-oracle-patch-status.sh" && -x "\$KIT_DIR/patch-sing-box-yg-oracle.sh" ]]; then
  check_log="\$(mktemp /tmp/vps-tunnel-yg-patch-check.XXXXXX.log)"
  chmod 0600 "\$check_log"
  if ! CHECK_NETWORK=0 "\$KIT_DIR/check-oracle-patch-status.sh" >"\$check_log" 2>&1; then
    echo
    echo "VPS-Tunnel：检测到 sing-box-yg 配置发生变化，正在重新应用 GCP 出口补丁..."
    if SKIP_BASE_PACKAGES=1 "\$KIT_DIR/patch-sing-box-yg-oracle.sh"; then
      echo "VPS-Tunnel：GCP 出口补丁已重新应用。"
      echo "VPS-Tunnel：可运行 'sudo bash \$KIT_DIR/check-oracle-patch-status.sh' 验证网络出口。"
    else
      echo "VPS-Tunnel：自动重新打补丁失败。请查看 \$check_log，并重新运行：" >&2
      echo "  sudo bash \$KIT_DIR/oneclick-oracle-after-sing-box-yg.sh" >&2
    fi
  else
    rm -f "\$check_log"
  fi
fi

exit "\$rc"
EOF
  chmod 0755 "$SB_PATH"
  chown root:root "$SB_PATH"

  echo "已安装 VPS-Tunnel 自动重新打补丁钩子："
  echo "  包装后的 sb 命令：$SB_PATH"
  echo "  原始 sb 备份：$REAL_SB_PATH"
  echo "  root 权限辅助脚本副本：$HOOK_LIB_DIR"
}

remove_hook() {
  if ! grep -q "$HOOK_MARKER" "$SB_PATH" 2>/dev/null; then
    echo "$SB_PATH 当前不由 VPS-Tunnel 自动重新打补丁钩子管理。"
    return
  fi

  [[ -e "$REAL_SB_PATH" ]] || die "缺少原始脚本备份：$REAL_SB_PATH"
  cp -a "$REAL_SB_PATH" "$SB_PATH"
  rm -f "$REAL_SB_PATH"
  if [[ "$(cd "$HOOK_LIB_DIR" 2>/dev/null && pwd -P)" == "$DEFAULT_HOOK_LIB_DIR" && -f "$HOOK_LIB_DIR/.vps-tunnel-hook" ]] &&
    grep -q "$HOOK_MARKER" "$HOOK_LIB_DIR/.vps-tunnel-hook"; then
    rm -rf "$HOOK_LIB_DIR"
  else
    echo "警告：拒绝删除非预期的钩子目录：$HOOK_LIB_DIR" >&2
  fi
  echo "已移除 VPS-Tunnel 自动重新打补丁钩子，并恢复 $SB_PATH。"
}

case "${1:-install}" in
  install)
    install_hook
    ;;
  remove|uninstall)
    remove_hook
    ;;
  *)
    echo "用法：sudo bash install-yg-auto-repatch-hook.sh [install|remove]" >&2
    exit 1
    ;;
esac
