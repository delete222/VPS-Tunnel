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
    echo "MISSING: $name"
    errors=$((errors + 1))
  fi
}

check_not_placeholder() {
  local name="$1"
  local value="${!name:-}"
  if [[ "$value" == *"xxxxxxxx"* || "$value" == *"yyyyyyyy"* || "$value" == "change-this-to-a-long-random-password" ]]; then
    echo "PLACEHOLDER: $name"
    errors=$((errors + 1))
  fi
}

echo "Checking $VARS_FILE"
echo

check_required INNER_LINK_MODE
if [[ "${INNER_LINK_MODE:-}" != "tailscale" ]]; then
  echo "WARN: INNER_LINK_MODE is ${INNER_LINK_MODE:-unset}. The fresh one-click scripts are designed for tailscale."
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
  echo "INVALID: GCP_INTERNAL_SOCKS_PORT must be a number"
  errors=$((errors + 1))
fi

if [[ "${TAILSCALE_GCP_HOSTNAME:-}" == "${TAILSCALE_ORACLE_HOSTNAME:-}" && -n "${TAILSCALE_GCP_HOSTNAME:-}" ]]; then
  echo "INVALID: TAILSCALE_GCP_HOSTNAME and TAILSCALE_ORACLE_HOSTNAME must be different"
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  echo
  echo "Environment check failed with $errors issue(s). Edit 00-vars.env and run this again."
  exit 1
fi

echo "Environment looks OK for the recommended Tailscale path."
echo "Use this exact same 00-vars.env on both VPS."

