#!/usr/bin/env bash
set -Eeuo pipefail

# Ubuntu 22.04 remote workstation installer
# Installs: OpenSSH Server, Tailscale, RustDesk
# Configures: service autostart, no suspend, Xorg, minimal UFW rules

NO_RUSTDESK=0
KEEP_WAYLAND=0
KEEP_SLEEP=0
FORCE_OS=0
RUSTDESK_DEB="${RUSTDESK_DEB:-}"

usage() {
  cat <<'USAGE'
Usage: sudo bash install.sh [options]

Options:
  --rustdesk-deb PATH  Install RustDesk from a local .deb file
  --no-rustdesk        Skip RustDesk installation
  --keep-wayland       Do not switch GDM to Xorg
  --keep-sleep         Do not disable suspend/hibernate
  --force-os           Run even if the system is not Ubuntu 22.04
  -h, --help           Show this help

Optional environment variable:
  TS_AUTHKEY           Tailscale auth key for unattended login
                       Do not commit auth keys to Git.
USAGE
}

log() {
  printf '\n[remote-setup] %s\n' "$*"
}

warn() {
  printf '\n[remote-setup] WARNING: %s\n' "$*" >&2
}

fail() {
  printf '\n[remote-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rustdesk-deb)
      [[ $# -ge 2 ]] || fail "--rustdesk-deb requires a file path"
      RUSTDESK_DEB="$2"
      shift 2
      ;;
    --no-rustdesk)
      NO_RUSTDESK=1
      shift
      ;;
    --keep-wayland)
      KEEP_WAYLAND=1
      shift
      ;;
    --keep-sleep)
      KEEP_SLEEP=1
      shift
      ;;
    --force-os)
      FORCE_OS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ ${EUID} -eq 0 ]] || fail "Run with sudo: sudo bash install.sh"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
else
  fail "/etc/os-release not found"
fi

if [[ ${FORCE_OS} -ne 1 ]]; then
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]] || \
    fail "This script targets Ubuntu 22.04. Use --force-os to override."
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing minimal base packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  openssh-server \
  python3

log "Enabling SSH"
systemctl enable --now ssh

log "Installing Tailscale"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL --retry 3 https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled

if [[ -n "${TS_AUTHKEY:-}" ]]; then
  log "Joining Tailscale with TS_AUTHKEY"
  tailscale up --auth-key="${TS_AUTHKEY}"
elif ! tailscale ip -4 >/dev/null 2>&1; then
  log "Tailscale login is required"
  warn "Complete the browser login shown by the next command."
  tailscale up || true
fi

install_rustdesk_latest() {
  local dpkg_arch rustdesk_arch api_json asset_url temp_deb

  dpkg_arch="$(dpkg --print-architecture)"
  case "${dpkg_arch}" in
    amd64) rustdesk_arch="x86_64" ;;
    arm64) rustdesk_arch="aarch64" ;;
    armhf) rustdesk_arch="armv7" ;;
    *) fail "Unsupported RustDesk architecture: ${dpkg_arch}" ;;
  esac

  log "Finding the latest official RustDesk .deb for ${rustdesk_arch}"
  api_json="$(curl -fsSL --retry 3 \
    https://api.github.com/repos/rustdesk/rustdesk/releases/latest)"

  asset_url="$(python3 -c '
import json
import sys
arch = sys.argv[1]
data = json.load(sys.stdin)
suffix = f"-{arch}.deb"
urls = [a["browser_download_url"] for a in data.get("assets", [])
        if a.get("name", "").endswith(suffix)]
print(urls[0] if urls else "")
' "${rustdesk_arch}" <<<"${api_json}")"

  [[ -n "${asset_url}" ]] || fail "No matching RustDesk .deb was found"

  temp_deb="$(mktemp --suffix=.deb)"
  curl -fL --retry 3 --output "${temp_deb}" "${asset_url}"
  apt-get install -y "${temp_deb}"
  rm -f "${temp_deb}"
}

if [[ ${NO_RUSTDESK} -ne 1 ]]; then
  if [[ -n "${RUSTDESK_DEB}" ]]; then
    [[ -f "${RUSTDESK_DEB}" ]] || fail "RustDesk package not found: ${RUSTDESK_DEB}"
    log "Installing RustDesk from ${RUSTDESK_DEB}"
    apt-get install -y "${RUSTDESK_DEB}"
  elif dpkg-query -W -f='${Status}' rustdesk 2>/dev/null | grep -q 'install ok installed'; then
    log "RustDesk is already installed"
  else
    install_rustdesk_latest
  fi

  if systemctl list-unit-files rustdesk.service 2>/dev/null | grep -q '^rustdesk.service'; then
    systemctl enable --now rustdesk.service || true
  fi
fi

if [[ ${KEEP_SLEEP} -ne 1 ]]; then
  log "Disabling suspend and hibernate"
  systemctl mask \
    sleep.target \
    suspend.target \
    hibernate.target \
    hybrid-sleep.target
fi

XORG_CHANGED=0
if [[ ${KEEP_WAYLAND} -ne 1 && -f /etc/gdm3/custom.conf ]]; then
  log "Configuring GDM to use Xorg for reliable unattended desktop access"
  cp -a /etc/gdm3/custom.conf /etc/gdm3/custom.conf.remote-setup.bak

  if grep -Eq '^[#[:space:]]*WaylandEnable=' /etc/gdm3/custom.conf; then
    sed -i 's/^[#[:space:]]*WaylandEnable=.*/WaylandEnable=false/' \
      /etc/gdm3/custom.conf
  elif grep -q '^\[daemon\]' /etc/gdm3/custom.conf; then
    sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
  else
    printf '\n[daemon]\nWaylandEnable=false\n' >> /etc/gdm3/custom.conf
  fi
  XORG_CHANGED=1
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  log "Adding minimal UFW rules on tailscale0"
  ufw allow in on tailscale0 to any port 22 proto tcp
  if [[ ${NO_RUSTDESK} -ne 1 ]]; then
    ufw allow in on tailscale0 to any port 21118 proto tcp
  fi
fi

log "Deployment summary"
printf 'SSH:       %s\n' "$(systemctl is-active ssh 2>/dev/null || true)"
printf 'Tailscale: %s\n' "$(systemctl is-active tailscaled 2>/dev/null || true)"
printf 'Tailnet IP: %s\n' "$(tailscale ip -4 2>/dev/null || echo 'login not completed')"
if [[ ${NO_RUSTDESK} -ne 1 ]]; then
  if dpkg-query -W -f='${Version}' rustdesk >/dev/null 2>&1; then
    printf 'RustDesk:   %s\n' "$(dpkg-query -W -f='${Version}' rustdesk)"
  else
    printf 'RustDesk:   not installed\n'
  fi
fi

cat <<'NEXT'

Manual steps still required:
1. If Tailscale is not logged in, run: sudo tailscale up
2. Open RustDesk as the desktop user.
3. Set a permanent password.
4. Enable Direct IP access and keep port 21118.
5. Connect from the other device using:
     ssh USER@TAILSCALE_IP
     RustDesk: TAILSCALE_IP:21118
NEXT

if [[ ${XORG_CHANGED} -eq 1 ]]; then
  warn "Reboot once to activate Xorg: sudo reboot"
fi
