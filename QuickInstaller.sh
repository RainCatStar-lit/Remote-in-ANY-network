#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
REPO_OWNER="RainCatStar-lit"
REPO_NAME="Ubuntu-tailscale-remote-access"
LINUX_BRANCH="${RCS_LINUX_BRANCH:-TEST-IN-22.04}"
WINDOWS_BRANCH="${RCS_WINDOWS_BRANCH:-TEST-IN-WINDOWS}"
MAIN_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"
INSTALL_PROXY="${INSTALL_PROXY:-}"

usage() {
  cat <<'USAGE'
QuickInstaller

Ubuntu 22.04:
  sudo bash QuickInstaller.sh [installer options]

Useful options passed to the Ubuntu installer:
  --proxy URL
  --no-rustdesk
  --keep-wayland
  --keep-sleep
  --skip-login
  -h, --help

Environment overrides:
  RCS_LINUX_BRANCH=TEST-IN-22.04
  RCS_WINDOWS_BRANCH=TEST-IN-WINDOWS
USAGE
}

for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--proxy" ]]; then
    next=$((i + 1))
    if (( next > $# )); then
      echo "QuickInstaller: --proxy requires a URL" >&2
      exit 2
    fi
    INSTALL_PROXY="${!next}"
    break
  fi
done

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

curl_args=(
  --fail
  --silent
  --show-error
  --location
  --retry 1
  --retry-delay 1
  --connect-timeout 6
  --max-time 30
)

fetch() {
  local url="$1"
  local output="$2"
  local candidate

  if [[ -n "${INSTALL_PROXY}" ]]; then
    echo "[quick-installer] Downloading through ${INSTALL_PROXY}"
    if curl "${curl_args[@]}" --proxy "${INSTALL_PROXY}" "${url}" -o "${output}"; then
      return 0
    fi
    echo "[quick-installer] Proxy failed; trying direct connection once" >&2
  fi

  if env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    curl "${curl_args[@]}" "${url}" -o "${output}"; then
    return 0
  fi

  if [[ -z "${INSTALL_PROXY}" ]]; then
    for candidate in 10808 10809 7890 7897; do
      if curl "${curl_args[@]}" \
        --proxy "http://127.0.0.1:${candidate}" \
        "${url}" -o "${output}"; then
        INSTALL_PROXY="http://127.0.0.1:${candidate}"
        echo "[quick-installer] Detected local proxy: ${INSTALL_PROXY}"
        return 0
      fi
    done
  fi

  echo "[quick-installer] Download failed: ${url}" >&2
  return 1
}

UNAME_S="$(uname -s 2>/dev/null || true)"

case "${UNAME_S}" in
  Linux)
    [[ -r /etc/os-release ]] || {
      echo "[quick-installer] /etc/os-release not found" >&2
      exit 1
    }
    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
      echo "[quick-installer] Unsupported Linux system: ${PRETTY_NAME:-unknown}" >&2
      echo "[quick-installer] Supported Linux target: Ubuntu 22.04" >&2
      exit 1
    fi

    [[ ${EUID} -eq 0 ]] || {
      echo "[quick-installer] Run with sudo:" >&2
      echo "  sudo bash QuickInstaller.sh $*" >&2
      exit 1
    }

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT
    installer="${tmp_dir}/install.sh"
    linux_base="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${LINUX_BRANCH}"

    echo "[quick-installer] Version: ${VERSION}"
    echo "[quick-installer] System: ${PRETTY_NAME}"
    echo "[quick-installer] Selected branch: ${LINUX_BRANCH}"

    fetch "${linux_base}/install.sh?ts=$(date +%s)" "${installer}"
    [[ -s "${installer}" ]] || {
      echo "[quick-installer] Downloaded installer is empty" >&2
      exit 1
    }
    bash -n "${installer}"

    export REPO_BRANCH="${LINUX_BRANCH}"
    export REPO_RAW_BASE="${linux_base}"
    export INSTALL_PROXY
    exec bash "${installer}" --branch "${LINUX_BRANCH}" "$@"
    ;;

  MINGW*|MSYS*|CYGWIN*)
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT
    ps_script="${tmp_dir}/QuickInstaller.ps1"

    echo "[quick-installer] Windows shell detected"
    echo "[quick-installer] Selected branch: ${WINDOWS_BRANCH}"
    fetch "${MAIN_RAW}/QuickInstaller.ps1?ts=$(date +%s)" "${ps_script}"

    ps_args=(
      -NoProfile
      -ExecutionPolicy Bypass
      -File "$(cygpath -w "${ps_script}")"
      -WindowsBranch "${WINDOWS_BRANCH}"
    )
    [[ -n "${INSTALL_PROXY}" ]] && ps_args+=( -Proxy "${INSTALL_PROXY}" )
    powershell.exe "${ps_args[@]}"
    ;;

  *)
    echo "[quick-installer] Unsupported operating system: ${UNAME_S}" >&2
    exit 1
    ;;
esac
