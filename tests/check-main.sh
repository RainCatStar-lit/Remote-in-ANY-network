#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${ROOT}/QuickInstaller.sh"

grep -q 'TEST-IN-22.04' "${ROOT}/QuickInstaller.sh"
grep -q 'TEST-IN-WINDOWS' "${ROOT}/QuickInstaller.ps1"
grep -q 'QuickInstaller.cmd' "${ROOT}/README.md"
grep -q 'QuickInstaller.sh' "${ROOT}/README.md"

if grep -Il $'\r' "${ROOT}/QuickInstaller.sh" "${ROOT}/tests/check-main.sh" >/dev/null; then
  echo "CRLF detected in a Bash file" >&2
  exit 1
fi

echo "Main QuickInstaller checks passed"
