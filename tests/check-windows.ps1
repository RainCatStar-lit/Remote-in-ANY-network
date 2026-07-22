$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$required = @(
    "README.md",
    "install-windows.cmd",
    "windows\install.ps1",
    "windows\reset-windows.ps1",
    "windows\download-packages.ps1",
    "windows\packages\README.md"
)

foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path $path)) {
        throw "Missing required file: $relative"
    }
}

$installerText = Get-Content (Join-Path $root "windows\install.ps1") -Raw
foreach ($needle in @(
    "0.7.0-windows",
    "tailscale.exe",
    "RCS-OpenSSH-Tailscale",
    "RCS-RustDesk-Tailscale",
    "100.64.0.0/10",
    "21118"
)) {
    if ($installerText -notmatch [regex]::Escape($needle)) {
        throw "Installer is missing required text: $needle"
    }
}

Write-Host "Windows static checks passed."
