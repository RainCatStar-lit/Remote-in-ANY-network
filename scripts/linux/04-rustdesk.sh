#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

if [[ ${NO_RUSTDESK} -eq 1 ]]; then
  state_set RUSTDESK_AUTOSTART "skipped"
  log "RustDesk installation skipped"
  exit 0
fi

INSTALL_PROXY="$(state_get INSTALL_PROXY 2>/dev/null || printf '%s' "${INSTALL_PROXY}")"
setup_apt_proxy

if dpkg-query -W -f='${Status}' rustdesk 2>/dev/null | grep -q 'install ok installed'; then
  log "RustDesk is already installed"
else
  if [[ -n "${RUSTDESK_DEB}" ]]; then
    [[ -f "${RUSTDESK_DEB}" ]] || fail "RustDesk package not found: ${RUSTDESK_DEB}"
    package="${RUSTDESK_DEB}"
  else
    arch="$(dpkg --print-architecture)"
    case "${arch}" in
      amd64) release_arch="x86_64" ;;
      arm64) release_arch="aarch64" ;;
      armhf) release_arch="armv7" ;;
      *) fail "Unsupported RustDesk architecture: ${arch}" ;;
    esac

    metadata="$(mktemp)"
    package="$(mktemp --suffix=.deb)"
    curl_fetch https://api.github.com/repos/rustdesk/rustdesk/releases/latest "${metadata}" || \
      fail "Cannot query RustDesk releases. Use --rustdesk-deb PATH."

    asset_url="$(python3 - "${metadata}" "${release_arch}" <<'PY'
import json
import sys
path, arch = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
for asset in data.get('assets', []):
    name = asset.get('name', '')
    if name.endswith('.deb') and arch in name:
        print(asset.get('browser_download_url', ''))
        break
PY
)"
    rm -f "${metadata}"
    [[ -n "${asset_url}" ]] || fail "No RustDesk .deb was found for ${release_arch}"
    curl_fetch "${asset_url}" "${package}"
  fi

  apt-get install -y "${package}"
  if [[ -z "${RUSTDESK_DEB}" ]]; then
    rm -f "${package}"
  fi
fi

service_name="$(rustdesk_service_name 2>/dev/null || true)"
if [[ -n "${service_name}" ]]; then
  systemctl enable --now "${service_name}"
  state_set RUSTDESK_AUTOSTART "system-service"
  log "RustDesk service is active and enabled at boot"
else
  binary="$(command -v rustdesk 2>/dev/null || true)"
  if [[ -n "${binary}" ]]; then
    timeout 30 "${binary}" --install-service >/dev/null 2>&1 || true
  fi
  service_name="$(rustdesk_service_name 2>/dev/null || true)"
  if [[ -n "${service_name}" ]]; then
    systemctl enable --now "${service_name}"
    state_set RUSTDESK_AUTOSTART "system-service"
    log "RustDesk service installed and enabled at boot"
  else
    install -d -m 0755 /etc/xdg/autostart
    cat > /etc/xdg/autostart/rustdesk.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=RustDesk
Exec=${binary:-/usr/bin/rustdesk}
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP
    chmod 0644 /etc/xdg/autostart/rustdesk.desktop
    state_set RUSTDESK_AUTOSTART "desktop-login"
    warn "RustDesk has no system service; desktop-login autostart was configured instead"
  fi
fi
