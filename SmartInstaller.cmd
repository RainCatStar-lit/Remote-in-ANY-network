: <<'__RCS_WINDOWS_BATCH__'
@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
set "RCS_SELF=%~f0"
set "RCS_PS1=%TEMP%\RCS-SmartInstaller-%RANDOM%-%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$lines = Get-Content -LiteralPath $env:RCS_SELF; $begin = [Array]::IndexOf($lines, '#__POWERSHELL_BEGIN__'); $end = [Array]::IndexOf($lines, '#__POWERSHELL_END__'); if ($begin -lt 0 -or $end -le $begin) { Write-Error 'Embedded PowerShell section not found.'; exit 3 }; $lines[($begin + 1)..($end - 1)] | Set-Content -LiteralPath $env:RCS_PS1 -Encoding UTF8"
if errorlevel 1 (
  echo [smart-installer] Failed to extract the Windows installer.
  pause
  exit /b 3
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RCS_PS1%"
set "RCS_EXIT=%ERRORLEVEL%"
del /f /q "%RCS_PS1%" >nul 2>&1
if not "%RCS_EXIT%"=="0" pause
exit /b %RCS_EXIT%
__RCS_WINDOWS_BATCH__
#!/usr/bin/env bash
set -Eeuo pipefail

SMART_VERSION="1.0.0"
REPO_OWNER="RainCatStar-lit"
REPO_NAME="Ubuntu-tailscale-remote-access"
LINUX_BRANCH="TEST-IN-22.04"
LINUX_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${LINUX_BRANCH}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ubuntu-tailscale-remote-access/smart-installer"
INSTALLER_PATH="${CACHE_DIR}/install-linux.sh"
PROXY_URL="${PROXY_URL:-}"

say() { printf '[smart-installer] %s\n' "$*"; }
fail() { printf '[smart-installer] ERROR: %s\n' "$*" >&2; exit 1; }

confirm_yes_no() {
  local answer
  read -r -p "$1 [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

confirm_install_word() {
  local answer
  read -r -p 'Type INSTALL to start: ' answer
  [[ "$answer" == "INSTALL" ]]
}

port_open() {
  local port="$1"
  timeout 1 bash -c "</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
}

detect_proxy() {
  local port
  [[ -n "$PROXY_URL" ]] && return 0
  for port in 10808 10809 7890 7897; do
    if port_open "$port"; then
      PROXY_URL="http://127.0.0.1:${port}"
      return 0
    fi
  done
}

download_file() {
  local url="$1"
  local output="$2"
  local timestamp
  timestamp="$(date +%s)"
  mkdir -p "$(dirname "$output")"

  if command -v curl >/dev/null 2>&1; then
    if [[ -n "$PROXY_URL" ]]; then
      say "Downloading through proxy: ${PROXY_URL}"
      if curl --fail --silent --show-error --location \
        --connect-timeout 8 --max-time 60 \
        --proxy "$PROXY_URL" "${url}?ts=${timestamp}" -o "$output"; then
        return 0
      fi
      say 'Proxy download failed; trying direct connection once.'
    fi
    curl --fail --silent --show-error --location \
      --connect-timeout 8 --max-time 60 \
      "${url}?ts=${timestamp}" -o "$output"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    if [[ -n "$PROXY_URL" ]]; then
      say "Downloading through proxy: ${PROXY_URL}"
      if https_proxy="$PROXY_URL" http_proxy="$PROXY_URL" \
        wget -q --timeout=60 -O "$output" "${url}?ts=${timestamp}"; then
        return 0
      fi
      say 'Proxy download failed; trying direct connection once.'
    fi
    wget -q --timeout=60 -O "$output" "${url}?ts=${timestamp}"
    return
  fi

  fail 'curl or wget is required.'
}

[[ "$(uname -s)" == "Linux" ]] || fail 'This Bash section supports Linux only.'
[[ -r /etc/os-release ]] || fail '/etc/os-release was not found.'
# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
  fail "Unsupported system: ${PRETTY_NAME:-unknown}. Required: Ubuntu 22.04."
fi

printf '\nRCS Smart Installer %s\n' "$SMART_VERSION"
printf 'Detected system : %s\n' "$PRETTY_NAME"
printf 'Selected branch : %s\n' "$LINUX_BRANCH"
printf 'Installation    : Tailscale + OpenSSH + RustDesk\n\n'

confirm_yes_no 'Is the detected system correct and do you want to continue?' \
  || fail 'Cancelled by user.'

printf '\nThe installer will download and execute the Ubuntu installer from:\n%s\n\n' "$LINUX_RAW"
confirm_install_word || fail 'Second confirmation failed; installation cancelled.'

detect_proxy
if [[ -n "$PROXY_URL" ]]; then
  say "Detected proxy: $PROXY_URL"
else
  say 'No common local proxy port detected; using direct connection.'
fi

download_file "${LINUX_RAW}/install.sh" "$INSTALLER_PATH"
bash -n "$INSTALLER_PATH" || fail 'Downloaded Linux installer failed syntax validation.'

args=(
  --branch "$LINUX_BRANCH"
)
if [[ -n "$PROXY_URL" ]]; then
  args+=(--proxy "$PROXY_URL")
fi

say "Starting Ubuntu installer from branch ${LINUX_BRANCH}."
exec sudo bash "$INSTALLER_PATH" "${args[@]}"

: <<'__RCS_POWERSHELL_SECTION__'
#__POWERSHELL_BEGIN__
[CmdletBinding()]
param(
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$SmartVersion = "1.0.0"
$RepoOwner = "RainCatStar-lit"
$RepoName = "Ubuntu-tailscale-remote-access"
$WindowsBranch = "TEST-IN-WINDOWS"
$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$WindowsBranch"
$CacheRoot = Join-Path $env:ProgramData "Ubuntu-tailscale-remote-access\smart-installer"
$WindowsRoot = Join-Path $CacheRoot "windows"
$PackageDir = Join-Path $WindowsRoot "packages"
$InstallerPath = Join-Path $WindowsRoot "install.ps1"
$ManifestPath = Join-Path $PackageDir "SHA256SUMS.txt"
$LogDir = Join-Path $env:ProgramData "Ubuntu-tailscale-remote-access\logs"
$LogFile = Join-Path $LogDir ("smart-installer-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$ResolvedProxy = ""

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $PSCommandPath),
        "-Elevated"
    )
    exit $process.ExitCode
}

if (-not (Test-Administrator)) {
    Request-Elevation
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Only 64-bit Windows is supported."
}

$os = Get-CimInstance Win32_OperatingSystem
$osVersion = [Version]$os.Version
if ($osVersion.Major -lt 10) {
    throw "Windows 10 or Windows 11 is required."
}

function Read-YesNo {
    param([string]$Prompt)
    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match '^[Yy]$'
}

function Test-LocalPort {
    param([int]$Port)
    try {
        return Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
    }
    catch {
        return $false
    }
}

function Resolve-Proxy {
    foreach ($port in @(10808, 10809, 7890, 7897)) {
        if (Test-LocalPort -Port $port) {
            return "http://127.0.0.1:$port"
        }
    }
    return ""
}

function Invoke-Download {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    $parent = Split-Path -Parent $OutFile
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = "$OutFile.download"
    Remove-Item $temporary -Force -ErrorAction SilentlyContinue

    $request = @{
        Uri = "$Uri?ts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        OutFile = $temporary
        UseBasicParsing = $true
        TimeoutSec = 120
        Headers = @{ "Cache-Control" = "no-cache" }
    }

    if ($ResolvedProxy) {
        try {
            Write-Host "Downloading through proxy: $Uri"
            Invoke-WebRequest @request -Proxy $ResolvedProxy
            Move-Item $temporary $OutFile -Force
            return
        }
        catch {
            Remove-Item $temporary -Force -ErrorAction SilentlyContinue
            Write-Host "Proxy download failed; trying direct connection once." -ForegroundColor Yellow
        }
    }

    Write-Host "Downloading directly: $Uri"
    Invoke-WebRequest @request
    Move-Item $temporary $OutFile -Force
}

function Test-FileHashValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected
    )
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
    return $actual -eq $Expected.ToLowerInvariant()
}

function Test-OpenSSHInstalled {
    return $null -ne (Get-Service -Name "sshd" -ErrorAction SilentlyContinue)
}

function Test-RustDeskInstalled {
    $paths = @(
        (Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "RustDesk\rustdesk.exe")
    )
    return $null -ne ($paths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1)
}

New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    Write-Host ""
    Write-Host "RCS Smart Installer $SmartVersion" -ForegroundColor Cyan
    Write-Host ("Detected system : {0} {1} ({2})" -f $os.Caption, $os.Version, $os.OSArchitecture)
    Write-Host ("Selected branch : {0}" -f $WindowsBranch)
    Write-Host "Installation    : Tailscale + Win32-OpenSSH + RustDesk"
    Write-Host ""

    if (-not (Read-YesNo "Is the detected system correct and do you want to continue?")) {
        throw "Cancelled by user."
    }

    Write-Host ""
    Write-Host "The installer will download signed MSI packages and execute:" 
    Write-Host $RawBase
    Write-Host ""
    $second = Read-Host "Type INSTALL to start"
    if ($second -cne "INSTALL") {
        throw "Second confirmation failed; installation cancelled."
    }

    $ResolvedProxy = Resolve-Proxy
    if ($ResolvedProxy) {
        Write-Host "Detected proxy: $ResolvedProxy"
    }
    else {
        Write-Host "No common local proxy port detected; using direct connection."
    }

    $openSSHInstalled = Test-OpenSSHInstalled
    $rustDeskInstalled = Test-RustDeskInstalled

    Write-Host ""
    Write-Host "[smart-installer] Download Windows branch installer" -ForegroundColor Cyan
    Invoke-Download -Uri "$RawBase/windows/install.ps1" -OutFile $InstallerPath

    $fullManifest = Join-Path $PackageDir "SHA256SUMS.full.txt"
    Invoke-Download -Uri "$RawBase/windows/packages/SHA256SUMS.txt" -OutFile $fullManifest
    $manifestText = Get-Content $fullManifest -Raw

    $entries = @()
    foreach ($match in [regex]::Matches($manifestText, "(?i)([0-9a-f]{64})\s+\*?([^\r\n]+\.msi)")) {
        $entries += [pscustomobject]@{
            Hash = $match.Groups[1].Value.ToLowerInvariant()
            Name = $match.Groups[2].Value.Trim()
        }
    }
    if ($entries.Count -lt 3) {
        throw "The Windows package manifest is incomplete or invalid."
    }

    $selected = @($entries | Where-Object Name -Like "tailscale-setup-*-amd64.msi")
    if (-not $openSSHInstalled) {
        $selected += @($entries | Where-Object Name -Like "OpenSSH-Win64-*.msi")
    }
    if (-not $rustDeskInstalled) {
        $selected += @($entries | Where-Object Name -Like "rustdesk-*-x86_64.msi")
    }

    Set-Content -Path $ManifestPath -Encoding ASCII -Value @(
        $selected | ForEach-Object { "{0} {1}" -f $_.Hash, $_.Name }
    )

    Write-Host ""
    Write-Host "[smart-installer] Download required packages" -ForegroundColor Cyan
    foreach ($entry in $selected) {
        $packagePath = Join-Path $PackageDir $entry.Name
        if (Test-FileHashValue -Path $packagePath -Expected $entry.Hash) {
            Write-Host "Using cached package: $($entry.Name)"
            continue
        }

        $encodedName = [Uri]::EscapeDataString($entry.Name)
        Invoke-Download -Uri "$RawBase/windows/packages/$encodedName" -OutFile $packagePath
        if (-not (Test-FileHashValue -Path $packagePath -Expected $entry.Hash)) {
            Remove-Item $packagePath -Force -ErrorAction SilentlyContinue
            throw "SHA-256 verification failed: $($entry.Name)"
        }
        Write-Host "SHA-256 verified: $($entry.Name)"
    }

    Write-Host ""
    Write-Host "[smart-installer] Start Windows branch installer" -ForegroundColor Cyan
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $InstallerPath,
        "-Elevated"
    )
    if ($openSSHInstalled) { $arguments += "-SkipOpenSSH" }
    if ($rustDeskInstalled) { $arguments += "-SkipRustDesk" }

    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "The Windows branch installer failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Smart installation completed." -ForegroundColor Green
    Write-Host "Log: $LogFile"
    Stop-Transcript | Out-Null
    Read-Host "Press Enter to close"
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("[smart-installer] ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host "Log: $LogFile" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host "Press Enter to close"
    exit 1
}
#__POWERSHELL_END__
__RCS_POWERSHELL_SECTION__
