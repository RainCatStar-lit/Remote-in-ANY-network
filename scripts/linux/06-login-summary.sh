#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

CLI="$(state_get TAILSCALE_CLI)"
METHOD="$(state_get TAILSCALE_METHOD)"
SERVICE="$(state_get TAILSCALE_SERVICE)"
INSTALL_PROXY="$(state_get INSTALL_PROXY 2>/dev/null || printf '%s' "${INSTALL_PROXY}")"
XORG_CHANGED="$(state_get XORG_CHANGED 2>/dev/null || echo 0)"

systemctl is-active --quiet "${SERVICE}" || fail "Tailscale service is not active: ${SERVICE}"

if [[ ${SKIP_TAILSCALE_LOGIN} -eq 0 ]] && ! "${CLI}" ip -4 >/dev/null 2>&1; then
  log "Checking access to the Tailscale control plane"

  if direct_probe; then
    log "Tailscale control plane is reachable directly"
  else
    warn "Direct access to the Tailscale control plane failed"

    if [[ -z "${INSTALL_PROXY}" ]]; then
      detect_proxy
    fi

    if [[ -n "${INSTALL_PROXY}" ]] && proxy_probe "${INSTALL_PROXY}" \
      'https://controlplane.tailscale.com/key?v=131'; then
      configure_tailscale_service_proxy "${SERVICE}" "${INSTALL_PROXY}" || {
        collect_tailscale_diagnostics "${SERVICE}"
        fail "Could not apply the proxy to ${SERVICE}"
      }
      state_set TAILSCALE_RUNTIME_PROXY "${INSTALL_PROXY}"
    else
      collect_tailscale_diagnostics "${SERVICE}"
      fail "Tailscale control plane is unreachable. Start the local proxy or use --proxy http://127.0.0.1:PORT"
    fi
  fi

  cat >/dev/tty <<'LOGIN'

Tailscale login is required.
A browser authorization URL should appear below.
Open it, sign in, and approve this device.
The URL is not written to the installation log.
LOGIN

  if ! run_unlogged_timeout 300s "${CLI}" up --accept-dns=false; then
    warn "Tailscale login did not complete within 300 seconds"
    collect_tailscale_diagnostics "${SERVICE}"
    fail "Tailscale login failed or timed out"
  fi
elif [[ ${SKIP_TAILSCALE_LOGIN} -eq 1 ]]; then
  warn "Tailscale login was skipped"
fi

TAILSCALE_IP="$("${CLI}" ip -4 2>/dev/null | head -n 1 || true)"
SSH_STATUS="$(systemctl is-active ssh 2>/dev/null || true)"
if [[ "${METHOD}" == "snap" ]]; then
  TS_STATUS="$(snap services tailscale 2>/dev/null | awk '/tailscale\.tailscaled/ {print $3}' | head -n 1)"
else
  TS_STATUS="$(systemctl is-active tailscaled 2>/dev/null || true)"
fi

printf '\n===== Deployment result =====\n'
printf 'SSH service:       %s\n' "${SSH_STATUS:-unknown}"
printf 'Tailscale method:  %s\n' "${METHOD}"
printf 'Tailscale service: %s\n' "${TS_STATUS:-unknown}"
printf 'Tailscale IP:      %s\n' "${TAILSCALE_IP:-login not completed}"
printf 'Installation log: %s\n' "${LOG_FILE}"

if [[ -n "${TAILSCALE_IP}" ]]; then
  printf '\nUse the Tailscale IP for every remote connection:\n'
  printf '  SSH:      ssh %s@%s\n' "${ORIGINAL_USER}" "${TAILSCALE_IP}"
  if [[ ${NO_RUSTDESK} -eq 0 ]]; then
    printf '  RustDesk: %s:21118\n' "${TAILSCALE_IP}"
  fi
fi

if [[ "${METHOD}" == "snap" ]]; then
  printf '\nThe Snap package does not provide Tailscale SSH. This project uses normal OpenSSH over the Tailscale network.\n'
fi

if [[ ${NO_RUSTDESK} -eq 0 ]]; then
  cat <<'RUSTDESK'

RustDesk manual setup:
  1. Open RustDesk once as the desktop user.
  2. Settings -> Security -> enable Direct IP access.
  3. Set an unattended-access password yourself.
The installer does not create or store any password.
RUSTDESK
fi

if [[ "${XORG_CHANGED}" == "1" ]]; then
  printf '\nReboot once to activate Xorg: sudo reboot\n'
fi
