#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${ROOT}/install.sh"
bash -n "${ROOT}/reset-ubuntu.sh"
for script in "${ROOT}"/scripts/linux/*.sh; do
  bash -n "${script}"
done

grep -q 'Official APT installation failed; switching to the Snap fallback' "${ROOT}/scripts/linux/03-tailscale.sh"
grep -q 'configure_tailscale_service_proxy' "${ROOT}/scripts/linux/06-login-summary.sh"
grep -q 'collect_tailscale_diagnostics' "${ROOT}/scripts/linux/06-login-summary.sh"
grep -q '/var/log/ubuntu-tailscale-remote-access' "${ROOT}/install.sh"
grep -q 'Start-Transcript' "${ROOT}/scripts/windows/install.ps1"
grep -q 'curl -x http://127.0.0.1:10808' "${ROOT}/README.md"

echo "Static checks passed"
