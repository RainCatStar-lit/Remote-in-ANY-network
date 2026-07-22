#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/SmartInstaller.cmd"

bash -n "$SCRIPT"
grep -q 'LINUX_BRANCH="TEST-IN-22.04"' "$SCRIPT"
grep -q '\$WindowsBranch = "TEST-IN-WINDOWS"' "$SCRIPT"
grep -q '#__POWERSHELL_BEGIN__' "$SCRIPT"
grep -q '#__POWERSHELL_END__' "$SCRIPT"
grep -q 'Type INSTALL to start' "$SCRIPT"

if grep -Il $'\r' "$SCRIPT" >/dev/null; then
  echo "CRLF detected in SmartInstaller.cmd" >&2
  exit 1
fi

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
lines = text.splitlines()
assert lines.count("#__POWERSHELL_BEGIN__") == 1
assert lines.count("#__POWERSHELL_END__") == 1
assert lines.index("#__POWERSHELL_BEGIN__") < lines.index("#__POWERSHELL_END__")
print("Static checks passed")
PY
