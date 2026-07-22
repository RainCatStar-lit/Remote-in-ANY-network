#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$(dirname -- "$0")/common.sh"

systemctl enable --now ssh
[[ "$(systemctl is-active ssh)" == "active" ]] || fail "ssh.service is not active"
log "OpenSSH Server is active and enabled at boot"
