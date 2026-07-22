[CmdletBinding()]
param(
    [switch]$RemovePrograms,
    [switch]$PurgeLogs,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Elevated")
    if ($RemovePrograms) { $args += "-RemovePrograms" }
    if ($PurgeLogs) { $args += "-PurgeLogs" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    exit 0
}

foreach ($ruleName in @("RCS-OpenSSH-Tailscale", "RCS-RustDesk-Tailscale")) {
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

if ($RemovePrograms) {
    $patterns = @(
        "*Tailscale*",
        "*RustDesk*",
        "*OpenSSH*"
    )

    $products = @(
        Get-ItemProperty `
            HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
            -ErrorAction SilentlyContinue
    )

    foreach ($pattern in $patterns) {
        foreach ($product in ($products | Where-Object DisplayName -Like $pattern)) {
            if ($product.PSChildName -match "^\{[0-9A-Fa-f-]+\}$") {
                Write-Host "Uninstalling $($product.DisplayName)"
                Start-Process msiexec.exe `
                    -ArgumentList @("/x", $product.PSChildName, "/qn", "/norestart") `
                    -Wait
            }
        }
    }
}

if ($PurgeLogs) {
    Remove-Item `
        (Join-Path $env:ProgramData "Ubuntu-tailscale-remote-access") `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}

Write-Host "Windows reset complete."
