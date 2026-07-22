#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/RainCatStar-lit/Ubuntu-tailscale-remote-access.git}"
BASE_BRANCH="${BASE_BRANCH:-TEST-IN-22.04}"
TARGET_BRANCH="${TARGET_BRANCH:-TEST-IN-WINDOWS}"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:10808}"
OVERLAY_DIR="${1:-}"
WORK_DIR="${2:-$HOME/Ubuntu-tailscale-remote-access-windows}"

if [[ -z "$OVERLAY_DIR" || ! -d "$OVERLAY_DIR" ]]; then
  echo "Usage: $0 /path/to/ubuntu-tailscale-remote-access-windows-v0.7.0 [work-dir]" >&2
  exit 2
fi

for command_name in git curl rsync sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing command: $command_name" >&2
    exit 1
  }
done

if [[ ! -d "$WORK_DIR/.git" ]]; then
  rm -rf "$WORK_DIR"
  git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

git fetch origin "$BASE_BRANCH" "$TARGET_BRANCH" 2>/dev/null || \
  git fetch origin "$BASE_BRANCH"

if git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
  git switch -C "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
else
  git switch -C "$TARGET_BRANCH" "origin/$BASE_BRANCH"
fi

rsync -av --delete --exclude='.git/' "$OVERLAY_DIR/" "$WORK_DIR/"

PACKAGE_DIR="$WORK_DIR/windows/packages"
mkdir -p "$PACKAGE_DIR"

download_file() {
  local url="$1"
  local output="$2"

  if [[ -s "$output" ]]; then
    echo "Using existing package: $(basename "$output")"
    return 0
  fi

  echo "Downloading: $url"
  if ! curl -fL --retry 2 --connect-timeout 10 --max-time 600 \
      --proxy "$PROXY_URL" "$url" -o "$output"; then
    echo "Proxy download failed; trying direct download." >&2
    curl -fL --retry 2 --connect-timeout 10 --max-time 600 \
      "$url" -o "$output"
  fi

  local size
  size="$(stat -c '%s' "$output")"
  if [[ "$size" -lt 1048576 ]]; then
    echo "Downloaded file is unexpectedly small: $output ($size bytes)" >&2
    exit 1
  fi
  if [[ "$size" -gt 99614720 ]]; then
    echo "Downloaded file exceeds the safe normal-Git size limit: $output ($size bytes)" >&2
    exit 1
  fi
}

download_file \
  "https://pkgs.tailscale.com/stable/tailscale-setup-1.98.9-amd64.msi" \
  "$PACKAGE_DIR/tailscale-setup-1.98.9-amd64.msi"

download_file \
  "https://github.com/rustdesk/rustdesk/releases/download/1.4.9/rustdesk-1.4.9-x86_64.msi" \
  "$PACKAGE_DIR/rustdesk-1.4.9-x86_64.msi"

download_file \
  "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.8.3.0p2-Preview/OpenSSH-Win64-v9.8.3.0.msi" \
  "$PACKAGE_DIR/OpenSSH-Win64-v9.8.3.0.msi"

(
  cd "$PACKAGE_DIR"
  sha256sum \
    tailscale-setup-1.98.9-amd64.msi \
    rustdesk-1.4.9-x86_64.msi \
    OpenSSH-Win64-v9.8.3.0.msi \
    > SHA256SUMS.txt
)

git config core.autocrlf false
git add --all

echo
echo "Staged files:"
git diff --cached --stat

if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "Add Windows offline one-click installer"
fi

git push -u origin "HEAD:$TARGET_BRANCH"

git fetch origin "$TARGET_BRANCH"
echo
echo "Published branch: $TARGET_BRANCH"
echo "Remote commit: $(git rev-parse "origin/$TARGET_BRANCH")"
git ls-tree -r --name-only "origin/$TARGET_BRANCH" |
  grep -E '^(install-windows\.cmd|windows/)' |
  sed -n '1,80p'
