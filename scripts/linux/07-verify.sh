#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

METHOD="$(state_get TAILSCALE_METHOD)"
CLI="$(state_get TAILSCALE_CLI)"
RUSTDESK_AUTOSTART="$(state_get RUSTDESK_AUTOSTART 2>/dev/null || echo unknown)"

[[ "$(systemctl is-active ssh 2>/dev/null || true)" == "active" ]] || \
  fail "SSH verification failed"
systemctl is-enabled ssh >/dev/null 2>&1 || fail "SSH is not enabled at boot"

if [[ "${METHOD}" == "apt" ]]; then
  [[ "$(systemctl is-active tailscaled 2>/dev/null || true)" == "active" ]] || \
    fail "tailscaled.service is not active"
  systemctl is-enabled tailscaled >/dev/null 2>&1 || fail "tailscaled.service is not enabled at boot"
else
  snap services tailscale | grep -Eq 'tailscale\.tailscaled[[:space:]]+enabled[[:space:]]+active' || \
    fail "Tailscale Snap service is not active and enabled"
fi

[[ -x "${CLI}" ]] || fail "Tailscale CLI verification failed"
[[ -s "${LOG_FILE}" ]] || fail "Installation log was not created correctly"

if [[ ${NO_RUSTDESK} -eq 0 ]]; then
  dpkg-query -W -f='${Status}' rustdesk 2>/dev/null | grep -q 'install ok installed' || \
    fail "RustDesk package verification failed"
  [[ "${RUSTDESK_AUTOSTART}" != "unknown" ]] || fail "RustDesk autostart was not configured"
fi

log "Verification passed"
log "RustDesk autostart mode: ${RUSTDESK_AUTOSTART}"
log "Installation log is active: ${LOG_FILE}"
