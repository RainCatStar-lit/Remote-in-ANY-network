#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${ROOT}/install.sh"
bash -n "${ROOT}/reset-ubuntu.sh"
for script in "${ROOT}"/scripts/linux/*.sh; do
  bash -n "${script}"
done

grep -q 'VERSION="0.6.0"' "${ROOT}/install.sh"
grep -q 'Official APT installation failed; switching to the Snap fallback' "${ROOT}/scripts/linux/03-tailscale.sh"
grep -q 'Downloading through configured proxy' "${ROOT}/scripts/linux/common.sh"
grep -q 'configure_tailscale_service_proxy' "${ROOT}/scripts/linux/06-login-summary.sh"
grep -q 'Tailscale IPv4:' "${ROOT}/scripts/linux/06-login-summary.sh"
grep -q 'print_port_status "Local proxy"' "${ROOT}/scripts/linux/06-login-summary.sh"
grep -q 'sudo ss -lntup' "${ROOT}/README.md"
grep -q '/var/log/ubuntu-tailscale-remote-access' "${ROOT}/install.sh"
grep -q 'Start-Transcript' "${ROOT}/scripts/windows/install.ps1"

echo "Static checks passed"
