#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/00-vars.env"

if [[ -e "$VARS_FILE" ]]; then
  echo "$VARS_FILE 已存在，为避免覆盖配置，本次停止。" >&2
  exit 1
fi

socks_password="$(openssl rand -base64 32 | tr -d '\n')"

cat > "$VARS_FILE" <<EOF
# 推荐的简单路线：
# 德国 Oracle 运行 yonggekkk/sing-box-yg。
# GCP 提供美国出口。
# 德国和 GCP 之间通过 Tailscale 连接。

INNER_LINK_MODE="tailscale"

# 从 Tailscale 管理后台填写这两个值。
TAILSCALE_AUTH_KEY_GCP=""
TAILSCALE_AUTH_KEY_ORACLE=""

TAILSCALE_GCP_HOSTNAME="gcp-us-exit"
TAILSCALE_ORACLE_HOSTNAME="oracle-de-entry"

# 通常留空即可，德国脚本可以自动发现。
TAILSCALE_GCP_IP=""

GCP_SOCKS_USER="relay"
GCP_SOCKS_PASSWORD="$socks_password"
GCP_INTERNAL_SOCKS_PORT="1080"

SING_BOX_VERSION=""
SING_BOX_YG_DIR="/etc/s-box"
SING_BOX_YG_SERVICE_CANDIDATES="sing-box s-box sb"
UPSTREAM_SB_URL="https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
EOF

cat <<EOF
已创建：$VARS_FILE

上传同一个目录到两台 VPS 前，只需要先填写这两个必填值：
  TAILSCALE_AUTH_KEY_GCP
  TAILSCALE_AUTH_KEY_ORACLE

两台 VPS 请使用完全相同的 00-vars.env。
EOF
