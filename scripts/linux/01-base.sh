#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

[[ -r /etc/os-release ]] || fail "/etc/os-release not found"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]] || \
  fail "Only Ubuntu 22.04 is supported. Detected: ${PRETTY_NAME:-unknown}"

log "Detected ${PRETTY_NAME}"
detect_proxy
setup_apt_proxy

# Known stale sources that previously blocked installation on the target machine.
disable_sources_matching 'apt.v2raya.org'
# Remove stale or half-configured Tailscale sources before a clean attempt.
disable_sources_matching 'pkgs.tailscale.com'

export DEBIAN_FRONTEND=noninteractive
apt_update_checked
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  openssh-server \
  python3

state_set INSTALL_PROXY "${INSTALL_PROXY}"
log "Base packages installed"
