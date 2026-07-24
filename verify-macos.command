#!/bin/bash
set -u

[ "$(uname -s)" = "Darwin" ] || {
    printf '[ERROR] This checker must run on macOS.\n' >&2
    exit 1
}

printf 'Remote in ANY network - macOS verification\n'
printf '===========================================\n'
printf 'macOS: %s\n' "$(sw_vers -productVersion)"
printf 'Architecture: %s\n' "$(uname -m)"
printf 'User: %s\n' "$(id -un)"
printf '\n'

printf '[SSH]\n'
if sudo systemsetup -getremotelogin 2>/dev/null | grep -qi 'On'; then
    printf 'Remote Login: enabled\n'
else
    printf 'Remote Login: not confirmed\n'
    printf 'Open System Settings > General > Sharing > Remote Login.\n'
fi
printf '\n'

printf '[Tailscale]\n'
if [ -d "/Applications/Tailscale.app" ]; then
    printf 'Application: installed\n'
else
    printf 'Application: missing\n'
fi

TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
if [ -x "$TS_BIN" ]; then
    TS_IP="$("$TS_BIN" ip -4 2>/dev/null | head -n 1 || true)"
    if [ -n "$TS_IP" ]; then
        printf 'Tailscale IP: %s\n' "$TS_IP"
        printf 'SSH: ssh %s@%s\n' "$(id -un)" "$TS_IP"
        printf 'RustDesk: %s:21118\n' "$TS_IP"
    else
        printf 'Tailscale IP: unavailable; complete login and VPN approval.\n'
    fi
else
    printf 'CLI: unavailable\n'
fi
printf '\n'

printf '[RustDesk]\n'
if [ -d "/Applications/RustDesk.app" ]; then
    printf 'Application: installed\n'
    if codesign --verify --deep --strict "/Applications/RustDesk.app" >/dev/null 2>&1; then
        printf 'Code signature: valid\n'
    else
        printf 'Code signature: verification failed\n'
    fi
else
    printf 'Application: missing\n'
fi

if pgrep -x RustDesk >/dev/null 2>&1; then
    printf 'Process: running\n'
else
    printf 'Process: not running\n'
fi

if lsof -nP -iTCP:21118 -sTCP:LISTEN >/dev/null 2>&1; then
    printf 'Direct IP port 21118: listening\n'
else
    printf 'Direct IP port 21118: not listening\n'
    printf 'Enable Direct IP Access in RustDesk security settings.\n'
fi

printf '\n'
printf 'RustDesk permissions must be checked manually in:\n'
printf 'System Settings > Privacy & Security\n'
printf '  - Accessibility\n'
printf '  - Screen & System Audio Recording\n'
printf '  - Input Monitoring, when needed\n'
