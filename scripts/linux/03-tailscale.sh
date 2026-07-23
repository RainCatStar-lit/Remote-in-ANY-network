#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

INSTALL_PROXY="$(state_get INSTALL_PROXY 2>/dev/null || printf '%s' "${INSTALL_PROXY}")"
setup_apt_proxy

verify_apt_install() {
  [[ -x /usr/bin/tailscale ]] || return 1
  systemctl list-unit-files tailscaled.service >/dev/null 2>&1 || return 1
  systemctl enable --now tailscaled
  [[ "$(systemctl is-active tailscaled)" == "active" ]]
}

verify_snap_install() {
  [[ -x /snap/bin/tailscale ]] || return 1
  snap list tailscale >/dev/null 2>&1 || return 1
  snap start --enable tailscale >/dev/null
  snap services tailscale | grep -Eq 'tailscale\.tailscaled[[:space:]]+enabled[[:space:]]+active'
}

install_from_official_repository() {
  local key_tmp list_tmp
  key_tmp="$(mktemp)"
  list_tmp="$(mktemp)"

  log "Trying the official Tailscale APT repository"
  if ! curl_fetch \
    https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg \
    "${key_tmp}"; then
    rm -f "${key_tmp}" "${list_tmp}"
    return 1
  fi
  if ! curl_fetch \
    https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list \
    "${list_tmp}"; then
    rm -f "${key_tmp}" "${list_tmp}"
    return 1
  fi

  install -d -m 0755 /usr/share/keyrings
  install -m 0644 "${key_tmp}" /usr/share/keyrings/tailscale-archive-keyring.gpg
  install -m 0644 "${list_tmp}" /etc/apt/sources.list.d/tailscale.list
  rm -f "${key_tmp}" "${list_tmp}"

  if ! apt_update_ok; then
    warn "The official Tailscale repository could not be updated"
    return 1
  fi
  if ! apt-get install -y tailscale; then
    warn "The Tailscale APT package could not be installed"
    return 1
  fi
  verify_apt_install
}

install_from_snap() {
  warn "Official APT installation failed; switching to the Snap fallback"

  disable_sources_matching 'pkgs.tailscale.com'
  rm -f /etc/apt/sources.list.d/tailscale.list
  rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg

  if dpkg-query -W -f='${Status}' tailscale 2>/dev/null | grep -q 'install ok installed'; then
    apt-get remove -y tailscale || true
  fi

  apt_update_checked
  apt-get install -y --no-install-recommends snapd
  systemctl enable --now snapd.socket
  systemctl start snapd.service 2>/dev/null || true
  timeout 180 snap wait system seed.loaded >/dev/null 2>&1 || true

  if ! snap list tailscale >/dev/null 2>&1; then
    snap install tailscale
  fi
  snap start --enable tailscale
  verify_snap_install || fail "Tailscale Snap was installed but its service is not active"
}

METHOD=""
CLI=""
SERVICE=""

if verify_apt_install; then
  METHOD="apt"
  CLI="/usr/bin/tailscale"
  SERVICE="tailscaled.service"
  log "Using the existing Tailscale APT installation"
elif verify_snap_install; then
  METHOD="snap"
  CLI="/snap/bin/tailscale"
  SERVICE="snap.tailscale.tailscaled.service"
  log "Using the existing Tailscale Snap installation"
else
  if install_from_official_repository; then
    METHOD="apt"
    CLI="/usr/bin/tailscale"
    SERVICE="tailscaled.service"
    log "Tailscale installed from the official repository"
  else
    install_from_snap
    METHOD="snap"
    CLI="/snap/bin/tailscale"
    SERVICE="snap.tailscale.tailscaled.service"
    log "Tailscale installed through the Snap fallback"
  fi
fi

[[ -x "${CLI}" ]] || fail "Tailscale CLI was not found after installation"
systemctl is-active --quiet "${SERVICE}" || fail "Tailscale service is not active: ${SERVICE}"

state_set TAILSCALE_METHOD "${METHOD}"
state_set TAILSCALE_CLI "${CLI}"
state_set TAILSCALE_SERVICE "${SERVICE}"
