#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARS_FILE="${VARS_FILE:-$KIT_DIR/00-vars.env}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo
  echo "==> $*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root, or run with sudo."
  fi
}

load_vars() {
  [[ -f "$VARS_FILE" ]] || die "Missing $VARS_FILE. Copy 00-vars.env.example to 00-vars.env and edit it."
  # shellcheck disable=SC1090
  source "$VARS_FILE"
}

require_var() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" ]] || die "Missing required variable: $name"
}

detect_os() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*) OS_FAMILY="debian" ;;
    *) die "Only Ubuntu/Debian is implemented. Detected ID=$ID ID_LIKE=${ID_LIKE:-}" ;;
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
    *) die "Unsupported architecture: $(uname -m)" ;;
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
  info "Installing sing-box v${version}"
  curl -fL "$url" -o "$tmp/sing-box.tar.gz"
  tar -xzf "$tmp/sing-box.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/sing-box-${version}-linux-${arch}/sing-box" /usr/local/bin/sing-box
  rm -rf "$tmp"
}

ensure_sing_box() {
  if ! command -v sing-box >/dev/null 2>&1; then
    download_sing_box
  else
    info "sing-box already installed: $(sing-box version | head -n 1)"
  fi
}

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    info "Tailscale already installed"
    return
  fi
  info "Installing Tailscale"
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
