#!/bin/bash
set -u

PROJECT_NAME="Remote in ANY network"
TAILSCALE_PKG_URL="https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg"
RUSTDESK_API_URL="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

PROXY=""
NO_OPEN=0
DRY_RUN=0
SKIP_SSH=0
SKIP_TAILSCALE=0
SKIP_RUSTDESK=0
TMP_DIR=""
MOUNT_DIR=""
MOUNTED=0

usage() {
    cat <<'EOF'
Usage:
  ./install-macos.command [options]

Options:
  --proxy URL        Use an HTTP or Mixed proxy, for example:
                     http://127.0.0.1:10808
  --no-open          Do not launch Tailscale or RustDesk.
  --skip-ssh         Do not enable macOS Remote Login.
  --skip-tailscale   Do not install Tailscale.
  --skip-rustdesk    Do not install RustDesk.
  --dry-run          Print planned operations without changing the system.
  -h, --help         Show this help.
EOF
}

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

cleanup() {
    if [ "$MOUNTED" -eq 1 ] && [ -n "$MOUNT_DIR" ]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --proxy)
            [ "$#" -ge 2 ] || die "--proxy requires a URL"
            PROXY="$2"
            shift 2
            ;;
        --no-open)
            NO_OPEN=1
            shift
            ;;
        --skip-ssh)
            SKIP_SSH=1
            shift
            ;;
        --skip-tailscale)
            SKIP_TAILSCALE=1
            shift
            ;;
        --skip-rustdesk)
            SKIP_RUSTDESK=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || die "This installer must run on macOS."

if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this script with sudo. Run it as the signed-in user."
fi

OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VERSION%%.*}"
case "$OS_MAJOR" in
    ''|*[!0-9]*) die "Cannot determine the macOS version." ;;
esac
[ "$OS_MAJOR" -ge 12 ] || die "macOS 12 or later is required."

ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        RUSTDESK_ARCH="aarch64"
        ;;
    x86_64)
        RUSTDESK_ARCH="x86_64"
        ;;
    *)
        die "Unsupported CPU architecture: $ARCH"
        ;;
esac

LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/remote-in-any-network-macos-install.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log "$PROJECT_NAME macOS installer"
log "macOS: $OS_VERSION"
log "Architecture: $ARCH"
log "Log: $LOG_FILE"

if [ -n "$PROXY" ]; then
    log "Proxy: $PROXY"
fi

if [ "$DRY_RUN" -eq 0 ]; then
    log "Administrator permission is required for system installation."
    sudo -v || die "Administrator authorization failed."
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remote-any-network.XXXXXX")" || die "Cannot create a temporary directory."
MOUNT_DIR="$TMP_DIR/rustdesk-volume"

curl_download() {
    url="$1"
    output="$2"

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -n "$PROXY" ]; then
            printf '+ curl -fL --retry 3 --connect-timeout 20 -x %q %q -o %q\n' "$PROXY" "$url" "$output"
        else
            printf '+ curl -fL --retry 3 --connect-timeout 20 %q -o %q\n' "$url" "$output"
        fi
        return 0
    fi

    if [ -n "$PROXY" ]; then
        curl -fL --retry 3 --connect-timeout 20 -x "$PROXY" "$url" -o "$output"
    else
        curl -fL --retry 3 --connect-timeout 20 "$url" -o "$output"
    fi
}

enable_ssh() {
    log "Enabling macOS Remote Login (SSH)..."

    if [ "$DRY_RUN" -eq 1 ]; then
        run sudo systemsetup -setremotelogin on
        return 0
    fi

    if sudo systemsetup -setremotelogin on; then
        log "Remote Login is enabled."
    else
        warn "Remote Login could not be enabled automatically."
        warn "Open System Settings > General > Sharing and enable Remote Login manually."
    fi
}

install_tailscale() {
    pkg="$TMP_DIR/Tailscale.pkg"

    log "Downloading Tailscale from the official package server..."
    curl_download "$TAILSCALE_PKG_URL" "$pkg"

    if [ "$DRY_RUN" -eq 1 ]; then
        run pkgutil --check-signature "$pkg"
        run sudo installer -pkg "$pkg" -target /
        return 0
    fi

    pkgutil --check-signature "$pkg" || die "Tailscale package signature verification failed."
    sudo installer -pkg "$pkg" -target / || die "Tailscale installation failed."

    [ -d "/Applications/Tailscale.app" ] || die "Tailscale.app was not found after installation."
    log "Tailscale installed."
}

latest_rustdesk_url() {
    json="$TMP_DIR/rustdesk-release.json"

    curl_download "$RUSTDESK_API_URL" "$json"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'https://github.com/rustdesk/rustdesk/releases/latest\n'
        return 0
    fi

    sed -n \
        's/.*"browser_download_url":[[:space:]]*"\([^"]*rustdesk-[^"]*-'"$RUSTDESK_ARCH"'\.dmg\)".*/\1/p' \
        "$json" | head -n 1
}

install_rustdesk() {
    dmg="$TMP_DIR/RustDesk.dmg"

    log "Resolving the latest RustDesk release for $RUSTDESK_ARCH..."
    rustdesk_url="$(latest_rustdesk_url)"

    if [ "$DRY_RUN" -eq 0 ] && [ -z "$rustdesk_url" ]; then
        die "No matching RustDesk macOS DMG was found for $RUSTDESK_ARCH."
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        rustdesk_url="https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-latest-$RUSTDESK_ARCH.dmg"
    fi

    log "Downloading RustDesk..."
    curl_download "$rustdesk_url" "$dmg"

    if [ "$DRY_RUN" -eq 1 ]; then
        run hdiutil verify "$dmg"
        run mkdir -p "$MOUNT_DIR"
        run hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$MOUNT_DIR"
        run codesign --verify --deep --strict "$MOUNT_DIR/RustDesk.app"
        run sudo rm -rf /Applications/RustDesk.app
        run sudo ditto "$MOUNT_DIR/RustDesk.app" /Applications/RustDesk.app
        return 0
    fi

    hdiutil verify "$dmg" || die "RustDesk DMG verification failed."

    mkdir -p "$MOUNT_DIR"
    hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null \
        || die "RustDesk DMG could not be mounted."
    MOUNTED=1

    app_path="$(find "$MOUNT_DIR" -type d -name 'RustDesk.app' -prune -print | head -n 1)"
    [ -n "$app_path" ] || die "RustDesk.app was not found in the DMG."

    codesign --verify --deep --strict --verbose=2 "$app_path" \
        || die "RustDesk code-signature verification failed."

    if ! spctl --assess --type execute --verbose=2 "$app_path"; then
        warn "Gatekeeper assessment did not pass. macOS may request manual approval when RustDesk starts."
    fi

    pkill -x RustDesk >/dev/null 2>&1 || true
    sudo rm -rf "/Applications/RustDesk.app"
    sudo ditto "$app_path" "/Applications/RustDesk.app" \
        || die "RustDesk installation failed."

    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    MOUNTED=0

    [ -d "/Applications/RustDesk.app" ] || die "RustDesk.app was not found after installation."
    log "RustDesk installed."
}

if [ "$SKIP_SSH" -eq 0 ]; then
    enable_ssh
else
    log "Skipping SSH configuration."
fi

if [ "$SKIP_TAILSCALE" -eq 0 ]; then
    install_tailscale
else
    log "Skipping Tailscale installation."
fi

if [ "$SKIP_RUSTDESK" -eq 0 ]; then
    install_rustdesk
else
    log "Skipping RustDesk installation."
fi

if [ "$NO_OPEN" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    if [ -d "/Applications/Tailscale.app" ]; then
        open -a Tailscale || warn "Tailscale could not be opened automatically."
    fi
    if [ -d "/Applications/RustDesk.app" ]; then
        open -a RustDesk || warn "RustDesk could not be opened automatically."
    fi
fi

printf '\n'
printf 'Installation phase completed.\n'
printf '\n'
printf 'Next steps:\n'
printf '  1. In Tailscale, approve the VPN/system-extension prompts and sign in.\n'
printf '  2. Use the same Tailscale account as the other devices.\n'
printf '  3. In System Settings > Privacy & Security, grant RustDesk:\n'
printf '       - Accessibility\n'
printf '       - Screen & System Audio Recording\n'
printf '       - Input Monitoring, if keyboard or mouse control is unavailable\n'
printf '  4. Restart RustDesk after changing permissions.\n'
printf '  5. In RustDesk security settings, enable Direct IP Access and set a permanent password.\n'
printf '\n'
printf 'Run ./verify-macos.command to check the installation.\n'
printf 'Log file: %s\n' "$LOG_FILE"

TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
if [ "$DRY_RUN" -eq 0 ] && [ -x "$TS_BIN" ]; then
    TS_IP="$("$TS_BIN" ip -4 2>/dev/null | head -n 1 || true)"
    if [ -n "$TS_IP" ]; then
        printf 'Tailscale IP: %s\n' "$TS_IP"
        printf 'SSH example: ssh %s@%s\n' "$(id -un)" "$TS_IP"
        printf 'RustDesk direct IP: %s:21118\n' "$TS_IP"
    else
        printf 'Tailscale IP is not available yet. Complete the Tailscale login first.\n'
    fi
fi

printf '\n'
if [ -t 0 ]; then
    read -r -p "Press Return to close..." _unused
fi
exit 0
