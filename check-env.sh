#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_vars

errors=0

check_required() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "缺失：$name"
    errors=$((errors + 1))
  fi
}

check_not_placeholder() {
  local name="$1"
  local value="${!name:-}"
  if [[ "$value" == *"xxxxxxxx"* || "$value" == *"yyyyyyyy"* || "$value" == "change-this-to-a-long-random-password" ]]; then
    echo "仍是占位符：$name"
    errors=$((errors + 1))
  fi
}

echo "正在检查 $VARS_FILE"
echo

check_required INNER_LINK_MODE
if [[ "${INNER_LINK_MODE:-}" != "tailscale" ]]; then
  echo "警告：INNER_LINK_MODE 当前是 ${INNER_LINK_MODE:-未设置}。全新一键脚本默认按 tailscale 路线设计。"
fi

check_required TAILSCALE_AUTH_KEY_GCP
check_required TAILSCALE_AUTH_KEY_ORACLE
check_required TAILSCALE_GCP_HOSTNAME
check_required TAILSCALE_ORACLE_HOSTNAME
check_required GCP_SOCKS_USER
check_required GCP_SOCKS_PASSWORD
check_required GCP_INTERNAL_SOCKS_PORT

check_not_placeholder TAILSCALE_AUTH_KEY_GCP
check_not_placeholder TAILSCALE_AUTH_KEY_ORACLE
check_not_placeholder GCP_SOCKS_PASSWORD

if [[ -n "${GCP_INTERNAL_SOCKS_PORT:-}" && ! "${GCP_INTERNAL_SOCKS_PORT}" =~ ^[0-9]+$ ]]; then
  echo "无效：GCP_INTERNAL_SOCKS_PORT 必须是数字"
  errors=$((errors + 1))
fi

if [[ "${TAILSCALE_GCP_HOSTNAME:-}" == "${TAILSCALE_ORACLE_HOSTNAME:-}" && -n "${TAILSCALE_GCP_HOSTNAME:-}" ]]; then
  echo "无效：TAILSCALE_GCP_HOSTNAME 和 TAILSCALE_ORACLE_HOSTNAME 不能相同"
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  echo
  echo "环境变量检查失败，共 $errors 个问题。请修改 00-vars.env 后重新运行。"
  exit 1
fi

echo "环境变量看起来正常，适合推荐的 Tailscale 路线。"
echo "两台 VPS 请使用同一份 00-vars.env。"
