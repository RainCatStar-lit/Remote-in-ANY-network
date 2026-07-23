#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

if [[ ${KEEP_SLEEP} -eq 0 ]]; then
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  log "Suspend and hibernate are disabled"
fi

XORG_CHANGED=0
if [[ ${KEEP_WAYLAND} -eq 0 && -f /etc/gdm3/custom.conf ]]; then
  backup="/etc/gdm3/custom.conf.remote-access.bak"
  [[ -f "${backup}" ]] || cp -a /etc/gdm3/custom.conf "${backup}"
  if grep -Eq '^[#[:space:]]*WaylandEnable=' /etc/gdm3/custom.conf; then
    sed -i 's/^[#[:space:]]*WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
  elif grep -q '^\[daemon\]' /etc/gdm3/custom.conf; then
    sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
  else
    printf '\n[daemon]\nWaylandEnable=false\n' >> /etc/gdm3/custom.conf
  fi
  XORG_CHANGED=1
  log "GDM is configured for Xorg"
fi
state_set XORG_CHANGED "${XORG_CHANGED}"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  ufw allow in on tailscale0 to any port 22 proto tcp
  if [[ ${NO_RUSTDESK} -eq 0 ]]; then
    ufw allow in on tailscale0 to any port 21118 proto tcp
  fi
  log "UFW permits SSH and RustDesk direct access through tailscale0"
fi
