#!/usr/bin/env bash
set -Eeuo pipefail

FULL=0
PURGE_LOGS=0
for arg in "$@"; do
  case "$arg" in
    --full) FULL=1 ;;
    --purge-logs) PURGE_LOGS=1 ;;
    -h|--help)
      cat <<'HELP'
Usage: sudo bash reset-ubuntu.sh [--full] [--purge-logs]

Default: remove Tailscale APT/Snap packages, state, sources and proxy drop-ins.
--full: also remove RustDesk and restore sleep/Xorg settings created by this project.
OpenSSH is preserved to avoid locking out the machine.
HELP
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }

if [[ -n "${SSH_CONNECTION:-}" ]]; then
  client_ip="${SSH_CONNECTION%% *}"
  if [[ "$client_ip" =~ ^100\. ]] || [[ "$client_ip" =~ ^fd7a:115c:a1e0: ]]; then
    echo "Refusing to remove Tailscale from a Tailscale SSH session." >&2
    echo "Run this from the local console or another network path." >&2
    exit 1
  fi
fi

for cli in /usr/bin/tailscale /snap/bin/tailscale; do
  if [[ -x "$cli" ]]; then
    "$cli" down >/dev/null 2>&1 || true
    "$cli" logout >/dev/null 2>&1 || true
  fi
done

systemctl disable --now tailscaled.service 2>/dev/null || true
systemctl disable --now snap.tailscale.tailscaled.service 2>/dev/null || true

rm -rf /etc/systemd/system/tailscaled.service.d
rm -rf /etc/systemd/system/snap.tailscale.tailscaled.service.d
systemctl daemon-reload

if snap list tailscale >/dev/null 2>&1; then
  snap remove --purge tailscale || true
fi

apt-get remove -y tailscale 2>/dev/null || true
rm -f /etc/apt/sources.list.d/tailscale.list
rm -f /etc/apt/sources.list.d/tailscale.list.disabled-by-remote-access
rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
rm -f /etc/apt/apt.conf.d/99ubuntu-tailscale-remote-access-proxy
rm -rf /var/lib/tailscale /var/cache/tailscale
rm -rf /var/snap/tailscale

if [[ $FULL -eq 1 ]]; then
  apt-get remove -y rustdesk 2>/dev/null || true
  rm -f /etc/xdg/autostart/rustdesk.desktop
  systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target || true
  if [[ -f /etc/gdm3/custom.conf.remote-access.bak ]]; then
    cp -a /etc/gdm3/custom.conf.remote-access.bak /etc/gdm3/custom.conf
  fi
fi

if [[ $PURGE_LOGS -eq 1 ]]; then
  rm -rf /var/log/ubuntu-tailscale-remote-access
fi

apt-get update || true

echo "Reset complete. OpenSSH was preserved."
