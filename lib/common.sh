#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARS_FILE="${VARS_FILE:-$KIT_DIR/00-vars.env}"

die() {
  echo "错误：$*" >&2
  exit 1
}

info() {
  echo
  echo "==> $*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 用户运行，或者在命令前加 sudo。"
  fi
}

load_vars() {
  [[ -f "$VARS_FILE" ]] || die "找不到 $VARS_FILE。请把 00-vars.env.example 复制成 00-vars.env 后再填写。"
  # shellcheck disable=SC1090
  source "$VARS_FILE"
}

require_var() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" ]] || die "缺少必填变量：$name"
}

detect_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release"
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*) OS_FAMILY="debian" ;;
    *) die "目前只支持 Ubuntu/Debian。检测到 ID=$ID ID_LIKE=${ID_LIKE:-}" ;;
  esac
}

install_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl jq tar gzip unzip openssl iproute2 iptables mtr-tiny iperf3 gnupg python3
}

system_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "暂不支持这个 CPU 架构：$(uname -m)" ;;
  esac
}

download_sing_box() {
  local arch version url tmp
  arch="$(system_arch)"
  tmp="$(mktemp -d)"
  if [[ -n "${SING_BOX_VERSION:-}" ]]; then
    version="$SING_BOX_VERSION"
  else
    version="$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  fi
  url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
  info "正在安装 sing-box v${version}"
  curl -fL "$url" -o "$tmp/sing-box.tar.gz"
  tar -xzf "$tmp/sing-box.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/sing-box-${version}-linux-${arch}/sing-box" /usr/local/bin/sing-box
  rm -rf "$tmp"
}

ensure_sing_box() {
  if ! command -v sing-box >/dev/null 2>&1; then
    download_sing_box
  else
    info "sing-box 已安装：$(sing-box version | head -n 1)"
  fi
}

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    info "Tailscale 已安装"
    return
  fi
  info "正在安装 Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
}

enable_service() {
  local service="$1"
  systemctl daemon-reload
  systemctl enable --now "$service"
}

write_file() {
  local path="$1"
  install -d -m 0755 "$(dirname "$path")"
  cat > "$path"
}
