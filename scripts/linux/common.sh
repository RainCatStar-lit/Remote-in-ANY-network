#!/usr/bin/env bash
set -Eeuo pipefail

[[ -n "${INSTALL_CONTEXT_FILE:-}" && -f "${INSTALL_CONTEXT_FILE}" ]] || {
  echo "INSTALL_CONTEXT_FILE is missing" >&2
  exit 1
}
# shellcheck disable=SC1090
source "${INSTALL_CONTEXT_FILE}"

log() {
  printf '[remote-setup] %s\n' "$*"
}

warn() {
  printf '[remote-setup] WARNING: %s\n' "$*" >&2
}

fail() {
  printf '[remote-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

state_set() {
  local key="$1"
  local value="$2"
  mkdir -p "${STATE_DIR}"
  printf '%s=%q\n' "${key}" "${value}" > "${STATE_DIR}/${key}.env"
}

state_get() {
  local key="$1"
  local file="${STATE_DIR}/${key}.env"
  [[ -f "${file}" ]] || return 1
  # shellcheck disable=SC1090
  source "${file}"
  printf '%s\n' "${!key}"
}

curl_args() {
  printf '%s\n' \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --connect-timeout 10
}

proxy_probe() {
  local proxy="$1"
  local url="${2:-https://login.tailscale.com}"
  curl --silent --show-error --location \
    --connect-timeout 6 --max-time 12 \
    --proxy "${proxy}" \
    --output /dev/null "${url}" >/dev/null 2>&1
}

direct_probe() {
  local url="${1:-https://controlplane.tailscale.com/key?v=131}"
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    curl --silent --show-error --location \
      --connect-timeout 6 --max-time 12 \
      --output /dev/null "${url}" >/dev/null 2>&1
}

detect_proxy() {
  local candidate gateway

  if [[ -n "${INSTALL_PROXY}" ]]; then
    if proxy_probe "${INSTALL_PROXY}"; then
      log "Using configured proxy: ${INSTALL_PROXY}"
      return
    fi
    warn "Configured proxy is not reachable: ${INSTALL_PROXY}"
  fi

  for candidate in "${HTTPS_PROXY:-}" "${https_proxy:-}" "${HTTP_PROXY:-}" "${http_proxy:-}"; do
    if [[ -n "${candidate}" ]] && proxy_probe "${candidate}"; then
      INSTALL_PROXY="${candidate}"
      log "Using proxy from environment: ${INSTALL_PROXY}"
      return
    fi
  done

  for candidate in 10808 10809 7890 7897; do
    if proxy_probe "http://127.0.0.1:${candidate}"; then
      INSTALL_PROXY="http://127.0.0.1:${candidate}"
      log "Detected local HTTP/Mixed proxy: ${INSTALL_PROXY}"
      return
    fi
  done

  # Useful for Multipass or another VM only when the host proxy permits LAN access.
  gateway="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  if [[ -n "${gateway}" && "${gateway}" != "127.0.0.1" ]]; then
    for candidate in 10808 10809 7890 7897; do
      if proxy_probe "http://${gateway}:${candidate}"; then
        INSTALL_PROXY="http://${gateway}:${candidate}"
        log "Detected gateway HTTP/Mixed proxy: ${INSTALL_PROXY}"
        return
      fi
    done
  fi

  INSTALL_PROXY=""
  log "No working proxy detected; using direct network"
}

curl_fetch() {
  local url="$1"
  local dest="$2"
  local -a base
  mapfile -t base < <(curl_args)

  if curl "${base[@]}" "${url}" -o "${dest}"; then
    return 0
  fi

  if [[ -n "${INSTALL_PROXY}" ]]; then
    warn "Direct download failed; retrying through ${INSTALL_PROXY}"
    curl "${base[@]}" --proxy "${INSTALL_PROXY}" "${url}" -o "${dest}"
    return
  fi

  return 1
}

setup_apt_proxy() {
  [[ -n "${INSTALL_PROXY}" ]] || return 0
  case "${INSTALL_PROXY}" in
    http://*|https://*)
      cat > "${APT_PROXY_FILE}" <<APTCONF
Acquire::http::Proxy "${INSTALL_PROXY}";
Acquire::https::Proxy "${INSTALL_PROXY}";
APTCONF
      chmod 600 "${APT_PROXY_FILE}"
      log "Configured temporary APT proxy: ${INSTALL_PROXY}"
      ;;
    *)
      warn "APT proxy supports HTTP/Mixed URLs only: ${INSTALL_PROXY}"
      ;;
  esac
}

disable_sources_matching() {
  local pattern="$1"
  local file

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    [[ "${file}" == *.disabled-by-remote-access ]] && continue
    mv "${file}" "${file}.disabled-by-remote-access"
    warn "Disabled APT source: ${file}"
  done < <(grep -RIl --include='*.list' --include='*.sources' "${pattern}" \
    /etc/apt/sources.list.d 2>/dev/null || true)

  if [[ -f /etc/apt/sources.list ]] && grep -q "${pattern}" /etc/apt/sources.list; then
    local backup="/etc/apt/sources.list.remote-access.bak"
    [[ -f "${backup}" ]] || cp -a /etc/apt/sources.list "${backup}"
    sed -i "\\|${pattern}| s|^[[:space:]]*|# disabled-by-remote-access |" /etc/apt/sources.list
    warn "Disabled matching lines in /etc/apt/sources.list"
  fi
}

apt_update_ok() {
  local output_file
  output_file="$(mktemp)"
  if ! apt-get update 2>&1 | tee "${output_file}"; then
    rm -f "${output_file}"
    return 1
  fi
  if grep -Eq \
    'Temporary failure resolving|Failed to fetch|Some index files failed|EXPKEYSIG|is not signed' \
    "${output_file}"; then
    grep -E \
      'Temporary failure resolving|Failed to fetch|Some index files failed|EXPKEYSIG|is not signed' \
      "${output_file}" >&2 || true
    rm -f "${output_file}"
    return 1
  fi
  rm -f "${output_file}"
}

apt_update_checked() {
  apt_update_ok || fail "APT update failed or a configured repository is unusable"
}

run_unlogged_timeout() {
  local seconds="$1"
  shift
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    timeout --foreground "${seconds}" "$@" </dev/tty >/dev/tty 2>/dev/tty
  else
    return 125
  fi
}

find_tailscale_cli() {
  local candidate
  for candidate in /usr/bin/tailscale /usr/local/bin/tailscale /snap/bin/tailscale; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  command -v tailscale 2>/dev/null || return 1
}

tailscale_service_for_method() {
  local method="$1"
  case "${method}" in
    apt) printf '%s\n' 'tailscaled.service' ;;
    snap) printf '%s\n' 'snap.tailscale.tailscaled.service' ;;
    *) return 1 ;;
  esac
}

configure_tailscale_service_proxy() {
  local service="$1"
  local proxy="$2"
  local dir="/etc/systemd/system/${service}.d"

  [[ -n "${service}" && -n "${proxy}" ]] || return 1
  mkdir -p "${dir}"
  cat > "${dir}/10-remote-access-proxy.conf" <<EOF_PROXY
[Service]
Environment="HTTP_PROXY=${proxy}"
Environment="HTTPS_PROXY=${proxy}"
Environment="http_proxy=${proxy}"
Environment="https_proxy=${proxy}"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
Environment="no_proxy=localhost,127.0.0.1,::1"
EOF_PROXY

  systemctl daemon-reload
  systemctl restart "${service}"
  sleep 3
  systemctl is-active --quiet "${service}" || return 1
  systemctl show "${service}" --property=Environment --no-pager | grep -Fq "HTTPS_PROXY=${proxy}"
  log "Configured runtime proxy for ${service}: ${proxy}"
}

remove_tailscale_service_proxy() {
  local service="$1"
  rm -rf "/etc/systemd/system/${service}.d"
  systemctl daemon-reload
}

collect_tailscale_diagnostics() {
  local service="$1"
  warn "Tailscale diagnostics follow"
  systemctl status "${service}" --no-pager || true
  journalctl -u "${service}" -n 120 --no-pager || true
  if [[ "${service}" == snap.* ]]; then
    snap services tailscale || true
    snap logs tailscale -n=100 || true
  fi
}

rustdesk_service_name() {
  local candidate
  for candidate in rustdesk.service rustdesk; do
    if systemctl list-unit-files "${candidate}" 2>/dev/null | grep -q '^rustdesk'; then
      printf '%s\n' "${candidate%.service}"
      return 0
    fi
  done
  return 1
}
