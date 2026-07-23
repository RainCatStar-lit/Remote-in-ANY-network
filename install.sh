#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.6.0"
REPO_OWNER="RainCatStar-lit"
REPO_NAME="Ubuntu-tailscale-remote-access"
REPO_BRANCH="${REPO_BRANCH:-STABLE-IN-22.04}"
REPO_RAW_BASE="${REPO_RAW_BASE:-}"

INSTALL_PROXY="${INSTALL_PROXY:-}"
RUSTDESK_DEB="${RUSTDESK_DEB:-}"
NO_RUSTDESK=0
KEEP_WAYLAND=0
KEEP_SLEEP=0
SKIP_TAILSCALE_LOGIN=0

usage() {
  cat <<'USAGE'
Usage:
  Ubuntu: sudo bash install.sh [options]
  Windows: bash install.sh [options]   # Git Bash, not WSL

Options:
  --proxy URL          HTTP/Mixed proxy, for example http://127.0.0.1:10808
  --branch NAME        GitHub branch used to download modules
  --repo-base URL      Raw module base URL; overrides --branch
  --rustdesk-deb PATH  Use a local RustDesk .deb on Ubuntu
  --no-rustdesk        Skip RustDesk installation
  --keep-wayland       Keep Wayland on Ubuntu
  --keep-sleep         Keep the current sleep/hibernate settings
  --skip-login         Install Tailscale without opening the login step
  -h, --help           Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxy)
      [[ $# -ge 2 ]] || { echo "--proxy requires a URL" >&2; exit 2; }
      INSTALL_PROXY="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "--branch requires a name" >&2; exit 2; }
      REPO_BRANCH="$2"
      shift 2
      ;;
    --repo-base)
      [[ $# -ge 2 ]] || { echo "--repo-base requires a URL" >&2; exit 2; }
      REPO_RAW_BASE="${2%/}"
      shift 2
      ;;
    --rustdesk-deb)
      [[ $# -ge 2 ]] || { echo "--rustdesk-deb requires a path" >&2; exit 2; }
      RUSTDESK_DEB="$2"
      shift 2
      ;;
    --no-rustdesk)
      NO_RUSTDESK=1
      shift
      ;;
    --keep-wayland)
      KEEP_WAYLAND=1
      shift
      ;;
    --keep-sleep)
      KEEP_SLEEP=1
      shift
      ;;
    --skip-login)
      SKIP_TAILSCALE_LOGIN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${REPO_RAW_BASE}" ]]; then
  REPO_RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOCAL_SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
TEMP_ROOT=""
LOG_FILE=""
APT_PROXY_FILE="/etc/apt/apt.conf.d/99ubuntu-tailscale-remote-access-proxy"
INSTALL_FINISHED=0

cleanup() {
  local rc=$?
  if [[ -n "${TEMP_ROOT}" && -d "${TEMP_ROOT}" ]]; then
    rm -rf "${TEMP_ROOT}"
  fi
  if [[ -f "${APT_PROXY_FILE}" ]]; then
    rm -f "${APT_PROXY_FILE}"
  fi
  if [[ -n "${LOG_FILE}" ]]; then
    if [[ ${rc} -eq 0 && ${INSTALL_FINISHED} -eq 1 ]]; then
      printf '\n[installer] Result: SUCCESS\n' || true
    else
      printf '\n[installer] Result: FAILED\n' || true
    fi
    printf '[installer] Exit code: %s\n' "${rc}" || true
    printf '[installer] End: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)" || true
    printf '[installer] Log: %s\n' "${LOG_FILE}" || true
  fi
  trap - EXIT
  exit "${rc}"
}
trap cleanup EXIT

bootstrap_curl_args() {
  printf '%s\n' \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 1 \
    --retry-delay 1 \
    --connect-timeout 6 \
    --max-time 25
}

bootstrap_curl() {
  local url="$1"
  local dest="$2"
  local candidate
  local -a args
  mapfile -t args < <(bootstrap_curl_args)

  if [[ -n "${INSTALL_PROXY}" ]]; then
    echo "[installer] Downloading through configured proxy: ${INSTALL_PROXY}" >&2
    if curl "${args[@]}" --proxy "${INSTALL_PROXY}" "${url}" -o "${dest}"; then
      return 0
    fi
    echo "[installer] Configured proxy failed; trying direct download once" >&2
  fi

  if env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    curl "${args[@]}" "${url}" -o "${dest}"; then
    return 0
  fi

  if [[ -z "${INSTALL_PROXY}" ]]; then
    for candidate in 10808 10809 7890 7897; do
      if curl "${args[@]}" --proxy "http://127.0.0.1:${candidate}" \
        "${url}" -o "${dest}"; then
        INSTALL_PROXY="http://127.0.0.1:${candidate}"
        echo "[installer] Detected local proxy: ${INSTALL_PROXY}" >&2
        return 0
      fi
    done
  fi

  echo "[installer] Failed to download: ${url}" >&2
  echo "[installer] Check the branch, file path and proxy. Current base: ${REPO_RAW_BASE}" >&2
  return 1
}

get_module() {
  local relative="$1"
  local local_path="${LOCAL_SCRIPTS_DIR}/${relative}"
  local target="${TEMP_ROOT}/scripts/${relative}"

  mkdir -p "$(dirname -- "${target}")"
  if [[ -f "${local_path}" ]]; then
    cp "${local_path}" "${target}"
  else
    bootstrap_curl "${REPO_RAW_BASE}/scripts/${relative}" "${target}"
  fi

  [[ -s "${target}" ]] || {
    echo "[installer] Downloaded module is empty: ${relative}" >&2
    return 1
  }
  case "${target}" in
    *.sh) bash -n "${target}" ;;
  esac
  chmod +x "${target}" 2>/dev/null || true
  printf '%s\n' "${target}"
}

UNAME_S="$(uname -s 2>/dev/null || true)"
case "${UNAME_S}" in
  MINGW*|MSYS*|CYGWIN*)
    TEMP_ROOT="$(mktemp -d)"
    WINDOWS_SCRIPT="$(get_module windows/install.ps1)"
    PS_ARGS=(
      -NoProfile
      -ExecutionPolicy Bypass
      -File "$(cygpath -w "${WINDOWS_SCRIPT}")"
    )
    [[ -n "${INSTALL_PROXY}" ]] && PS_ARGS+=( -Proxy "${INSTALL_PROXY}" )
    [[ ${NO_RUSTDESK} -eq 1 ]] && PS_ARGS+=( -NoRustDesk )
    [[ ${KEEP_SLEEP} -eq 1 ]] && PS_ARGS+=( -KeepSleep )
    [[ ${SKIP_TAILSCALE_LOGIN} -eq 1 ]] && PS_ARGS+=( -SkipTailscaleLogin )
    powershell.exe "${PS_ARGS[@]}"
    exit $?
    ;;
  Linux)
    ;;
  *)
    echo "Unsupported operating system: ${UNAME_S}" >&2
    exit 1
    ;;
esac

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo: sudo bash install.sh" >&2; exit 1; }

mkdir -p /var/log/ubuntu-tailscale-remote-access
LOG_FILE="/var/log/ubuntu-tailscale-remote-access/install-$(date +%Y%m%d-%H%M%S).log"
touch "${LOG_FILE}"
chmod 600 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

printf '[installer] Version: %s\n' "${VERSION}"
printf '[installer] Start: %s\n' "$(date --iso-8601=seconds)"
printf '[installer] Host: %s\n' "$(hostname)"
printf '[installer] Module base: %s\n' "${REPO_RAW_BASE}"
printf '[installer] Requested proxy: %s\n' "${INSTALL_PROXY:-automatic/direct}"
printf '[installer] Log: %s\n' "${LOG_FILE}"

TEMP_ROOT="$(mktemp -d)"
mkdir -p "${TEMP_ROOT}/scripts/linux" "${TEMP_ROOT}/state"

for module in \
  linux/common.sh \
  linux/01-base.sh \
  linux/02-ssh.sh \
  linux/03-tailscale.sh \
  linux/04-rustdesk.sh \
  linux/05-system.sh \
  linux/06-login-summary.sh \
  linux/07-verify.sh; do
  get_module "${module}" >/dev/null
done

CONTEXT_FILE="${TEMP_ROOT}/context.env"
{
  printf 'INSTALL_PROXY=%q\n' "${INSTALL_PROXY}"
  printf 'RUSTDESK_DEB=%q\n' "${RUSTDESK_DEB}"
  printf 'NO_RUSTDESK=%q\n' "${NO_RUSTDESK}"
  printf 'KEEP_WAYLAND=%q\n' "${KEEP_WAYLAND}"
  printf 'KEEP_SLEEP=%q\n' "${KEEP_SLEEP}"
  printf 'SKIP_TAILSCALE_LOGIN=%q\n' "${SKIP_TAILSCALE_LOGIN}"
  printf 'LOG_FILE=%q\n' "${LOG_FILE}"
  printf 'STATE_DIR=%q\n' "${TEMP_ROOT}/state"
  printf 'APT_PROXY_FILE=%q\n' "${APT_PROXY_FILE}"
  printf 'ORIGINAL_USER=%q\n' "${SUDO_USER:-root}"
  printf 'REPO_RAW_BASE=%q\n' "${REPO_RAW_BASE}"
} > "${CONTEXT_FILE}"
chmod 600 "${CONTEXT_FILE}"

export INSTALL_CONTEXT_FILE="${CONTEXT_FILE}"

run_step() {
  local number="$1"
  local name="$2"
  local script="$3"
  printf '\n[installer] Step %s: %s\n' "${number}" "${name}"
  bash "${script}"
  printf '[installer] Step %s completed\n' "${number}"
}

run_step 1 "System check, source cleanup and base packages" "${TEMP_ROOT}/scripts/linux/01-base.sh"
run_step 2 "OpenSSH Server" "${TEMP_ROOT}/scripts/linux/02-ssh.sh"
run_step 3 "Tailscale repository installation, then Snap fallback" "${TEMP_ROOT}/scripts/linux/03-tailscale.sh"
run_step 4 "RustDesk" "${TEMP_ROOT}/scripts/linux/04-rustdesk.sh"
run_step 5 "Autostart, sleep, Xorg and firewall" "${TEMP_ROOT}/scripts/linux/05-system.sh"
run_step 6 "Tailscale login, IP and port summary" "${TEMP_ROOT}/scripts/linux/06-login-summary.sh"
run_step 7 "Final verification" "${TEMP_ROOT}/scripts/linux/07-verify.sh"

INSTALL_FINISHED=1
printf '\n[installer] All steps completed.\n'
