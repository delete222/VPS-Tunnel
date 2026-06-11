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
  printf '%s\n' "$HOOK_MARKER" > "$HOOK_LIB_DIR/.vps-tunnel-hook"
  chown -R root:root "$HOOK_LIB_DIR"
  chmod 0600 "$HOOK_LIB_DIR/.vps-tunnel-hook"
}

install_hook() {
  [[ -x "$SB_PATH" ]] || die "Cannot find executable $SB_PATH. Install yonggekkk/sing-box-yg first."
  [[ ! -L "$SB_PATH" ]] || die "$SB_PATH is a symlink. Refusing to wrap it because that can overwrite the symlink target. Replace it with a real file first, then rerun this installer."

  if grep -q "$HOOK_MARKER" "$SB_PATH" 2>/dev/null; then
    install_hook_files
    echo "$SB_PATH already has the VPS-Tunnel auto repatch hook. Refreshed $HOOK_LIB_DIR."
    return
  fi

  if [[ -e "$REAL_SB_PATH" ]]; then
    die "$REAL_SB_PATH already exists. Refusing to overwrite an existing backup."
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
    echo "VPS-Tunnel: sing-box-yg configs changed; re-applying GCP exit patch..."
    if SKIP_BASE_PACKAGES=1 "\$KIT_DIR/patch-sing-box-yg-oracle.sh"; then
      echo "VPS-Tunnel: GCP exit patch re-applied."
      echo "VPS-Tunnel: run 'sudo bash \$KIT_DIR/check-oracle-patch-status.sh' to verify network exit."
    else
      echo "VPS-Tunnel: auto re-patch failed. See \$check_log and re-run:" >&2
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

  echo "Installed VPS-Tunnel auto repatch hook:"
  echo "  wrapper: $SB_PATH"
  echo "  original: $REAL_SB_PATH"
  echo "  root-owned helper copy: $HOOK_LIB_DIR"
}

remove_hook() {
  if ! grep -q "$HOOK_MARKER" "$SB_PATH" 2>/dev/null; then
    echo "$SB_PATH is not managed by the VPS-Tunnel auto repatch hook."
    return
  fi

  [[ -e "$REAL_SB_PATH" ]] || die "Missing original script backup: $REAL_SB_PATH"
  cp -a "$REAL_SB_PATH" "$SB_PATH"
  rm -f "$REAL_SB_PATH"
  if [[ "$(cd "$HOOK_LIB_DIR" 2>/dev/null && pwd -P)" == "$DEFAULT_HOOK_LIB_DIR" && -f "$HOOK_LIB_DIR/.vps-tunnel-hook" ]] &&
    grep -q "$HOOK_MARKER" "$HOOK_LIB_DIR/.vps-tunnel-hook"; then
    rm -rf "$HOOK_LIB_DIR"
  else
    echo "WARN: Refusing to remove unexpected hook directory: $HOOK_LIB_DIR" >&2
  fi
  echo "Removed VPS-Tunnel auto repatch hook and restored $SB_PATH."
}

case "${1:-install}" in
  install)
    install_hook
    ;;
  remove|uninstall)
    remove_hook
    ;;
  *)
    echo "Usage: sudo bash install-yg-auto-repatch-hook.sh [install|remove]" >&2
    exit 1
    ;;
esac
