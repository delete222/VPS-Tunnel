#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${VPSWALL_DIR:-/root/VPS-Tunnel}"
ARCHIVE_URL="${VPSWALL_ARCHIVE_URL:-https://github.com/delete222/VPS-Tunnel/releases/latest/download/VPS-Tunnel.tar.gz}"
FALLBACK_ARCHIVE_URL="${VPSWALL_FALLBACK_ARCHIVE_URL:-https://github.com/delete222/VPS-Tunnel/archive/refs/heads/main.tar.gz}"
BIN_PATH="${VPSWALL_BIN_PATH:-/usr/local/bin/vpswall}"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "错误：请使用 root 用户运行，或者在命令前加 sudo。" >&2
    exit 1
  fi
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "错误：缺少命令：$cmd" >&2
    echo "请先安装它，例如：apt-get update && apt-get install -y curl tar gzip" >&2
    exit 1
  fi
}

need_root
need_cmd curl
need_cmd tar
need_cmd gzip

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if [[ -f "$INSTALL_DIR/00-vars.env" ]]; then
  cp -a "$INSTALL_DIR/00-vars.env" "$tmpdir/00-vars.env.keep"
fi
if [[ -f "$INSTALL_DIR/client-sing-box.json" ]]; then
  cp -a "$INSTALL_DIR/client-sing-box.json" "$tmpdir/client-sing-box.json.keep"
fi

download_and_extract() {
  local url="$1"
  local archive="$tmpdir/VPS-Tunnel.tar.gz"

  rm -rf "$tmpdir/extract"
  mkdir -p "$tmpdir/extract"
  echo "正在下载 VPS-Tunnel：$url"
  curl -fL "$url" -o "$archive"
  tar --no-same-owner -xzf "$archive" -C "$tmpdir/extract"
}

find_extracted_dir() {
  local dir
  if [[ -f "$tmpdir/extract/VPS-Tunnel/vpswall-menu.sh" ]]; then
    echo "$tmpdir/extract/VPS-Tunnel"
    return 0
  fi

  while IFS= read -r dir; do
    if [[ -f "$dir/vpswall-menu.sh" ]]; then
      echo "$dir"
      return 0
    fi
  done < <(find "$tmpdir/extract" -mindepth 1 -maxdepth 1 -type d | sort)

  return 1
}

if download_and_extract "$ARCHIVE_URL"; then
  extracted_dir="$(find_extracted_dir || true)"
else
  extracted_dir=""
fi

if [[ -z "$extracted_dir" && -n "$FALLBACK_ARCHIVE_URL" && "$FALLBACK_ARCHIVE_URL" != "$ARCHIVE_URL" ]]; then
  echo "latest release 包不可用或没有找到菜单脚本，改为下载 main 分支源码包。"
  if download_and_extract "$FALLBACK_ARCHIVE_URL"; then
    extracted_dir="$(find_extracted_dir || true)"
  else
    extracted_dir=""
  fi
fi

if [[ -z "$extracted_dir" ]]; then
  echo "错误：压缩包里没有找到可安装的 VPS-Tunnel 目录。" >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
mv "$extracted_dir" "$INSTALL_DIR"

if [[ -f "$tmpdir/00-vars.env.keep" ]]; then
  cp -a "$tmpdir/00-vars.env.keep" "$INSTALL_DIR/00-vars.env"
  echo "已保留原有配置：$INSTALL_DIR/00-vars.env"
fi
if [[ -f "$tmpdir/client-sing-box.json.keep" ]]; then
  cp -a "$tmpdir/client-sing-box.json.keep" "$INSTALL_DIR/client-sing-box.json"
  echo "已保留本地客户端配置：$INSTALL_DIR/client-sing-box.json"
fi

chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR"/*.sh

cat > "$BIN_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$INSTALL_DIR"
exec bash "$INSTALL_DIR/vpswall-menu.sh" "\$@"
EOF
chmod 0755 "$BIN_PATH"

echo
echo "安装完成。"
echo "脚本目录：$INSTALL_DIR"
echo "快捷命令：$BIN_PATH"
echo
echo "以后输入下面这个命令即可打开菜单："
echo "  sudo vpswall"
echo
if [[ "${VPSWALL_NO_MENU:-0}" != "1" ]]; then
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    "$BIN_PATH" </dev/tty >/dev/tty
  else
    echo "当前不是交互式终端，已跳过自动打开菜单。请稍后运行：sudo vpswall"
  fi
fi
