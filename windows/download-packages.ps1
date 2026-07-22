[CmdletBinding()]
param(
    [string]$Proxy = "http://127.0.0.1:10808"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PackageDir = Join-Path $PSScriptRoot "packages"
New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null

$downloads = @(
    @{
        Name = "Tailscale 1.98.9 x64"
        Url = "https://pkgs.tailscale.com/stable/tailscale-setup-1.98.9-amd64.msi"
        File = "tailscale-setup-1.98.9-amd64.msi"
    },
    @{
        Name = "RustDesk 1.4.9 x64"
        Url = "https://github.com/rustdesk/rustdesk/releases/download/1.4.9/rustdesk-1.4.9-x86_64.msi"
        File = "rustdesk-1.4.9-x86_64.msi"
    },
    @{
        Name = "Win32-OpenSSH 9.8.3.0 x64"
        Url = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.8.3.0p2-Preview/OpenSSH-Win64-v9.8.3.0.msi"
        File = "OpenSSH-Win64-v9.8.3.0.msi"
    }
)

foreach ($item in $downloads) {
    $destination = Join-Path $PackageDir $item.File
    Write-Host "Downloading $($item.Name)"
    Write-Host $item.Url

    $parameters = @{
        Uri = $item.Url
        OutFile = $destination
        UseBasicParsing = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        $parameters.Proxy = $Proxy
    }

    Invoke-WebRequest @parameters

    $length = (Get-Item $destination).Length
    if ($length -lt 1MB) {
        throw "Downloaded file is unexpectedly small: $destination ($length bytes)"
    }
}

$sumFile = Join-Path $PackageDir "SHA256SUMS.txt"
$lines = foreach ($item in $downloads) {
    $path = Join-Path $PackageDir $item.File
    $hash = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLowerInvariant()
    "$hash  $($item.File)"
}

$lines | Set-Content -Path $sumFile -Encoding ASCII

Write-Host ""
Write-Host "Packages downloaded:"
Get-ChildItem $PackageDir -File |
    Select-Object Name,Length |
    Format-Table -AutoSize
Write-Host "SHA-256 manifest: $sumFile"
