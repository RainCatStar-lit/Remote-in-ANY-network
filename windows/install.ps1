[CmdletBinding()]
param(
    [switch]$SkipOpenSSH,
    [switch]$SkipRustDesk,
    [switch]$SkipTailscaleLogin,
    [switch]$DisableSleep,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectVersion = "0.7.0-windows"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PackageDir = Join-Path $PSScriptRoot "packages"
$LogDir = Join-Path $env:ProgramData "Ubuntu-tailscale-remote-access\logs"
$LogFile = Join-Path $LogDir ("windows-install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    $forward = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Elevated"
    )
    if ($SkipOpenSSH) { $forward += "-SkipOpenSSH" }
    if ($SkipRustDesk) { $forward += "-SkipRustDesk" }
    if ($SkipTailscaleLogin) { $forward += "-SkipTailscaleLogin" }
    if ($DisableSleep) { $forward += "-DisableSleep" }

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $forward
}

if (-not (Test-Administrator)) {
    Request-Elevation
    exit 0
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("[windows-setup] {0}" -f $Message) -ForegroundColor Cyan
}

function Write-WarningLine {
    param([string]$Message)
    Write-Host ("[windows-setup] WARNING: {0}" -f $Message) -ForegroundColor Yellow
}

function Get-OnePackage {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $items = @(Get-ChildItem -Path $PackageDir -Filter $Pattern -File -ErrorAction SilentlyContinue)
    if ($items.Count -ne 1) {
        throw "$DisplayName package not found or ambiguous. Expected one file matching: $Pattern"
    }
    return $items[0].FullName
}

function Test-PackageHashes {
    $manifest = Join-Path $PackageDir "SHA256SUMS.txt"
    if (-not (Test-Path $manifest)) {
        Write-WarningLine "SHA256SUMS.txt was not found; package hash verification skipped."
        return
    }

    foreach ($line in Get-Content $manifest) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -notmatch "^([0-9a-fA-F]{64})\s+\*?(.+)$") {
            throw "Invalid SHA-256 manifest line: $line"
        }

        $expected = $Matches[1].ToLowerInvariant()
        $fileName = $Matches[2].Trim()
        $filePath = Join-Path $PackageDir $fileName
        if (-not (Test-Path $filePath)) {
            throw "Package listed in SHA256SUMS.txt is missing: $fileName"
        }

        $actual = (Get-FileHash -Algorithm SHA256 -Path $filePath).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "SHA-256 mismatch: $fileName"
        }
        Write-Host "SHA-256 verified: $fileName"
    }
}

function Disable-BroadInboundRules {
    param([Parameter(Mandatory)][string]$NamePattern)

    Get-NetFirewallRule -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ne "RCS-OpenSSH-Tailscale" -and
            $_.Name -ne "RCS-RustDesk-Tailscale" -and
            ($_.Name -like $NamePattern -or $_.DisplayName -like $NamePattern)
        } |
        Disable-NetFirewallRule -ErrorAction SilentlyContinue
}

function Install-Msi {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Properties = @()
    )

    $msiLog = Join-Path $LogDir ("msi-{0}-{1}.log" -f $Name, (Get-Date -Format "yyyyMMdd-HHmmss"))
    $arguments = @(
        "/i",
        "`"$Path`"",
        "/qn",
        "/norestart",
        "/L*v",
        "`"$msiLog`""
    ) + $Properties

    Write-Host "Installing $Name from $Path"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "$Name installation failed. MSI exit code: $($process.ExitCode). Log: $msiLog"
    }
    if ($process.ExitCode -in @(3010, 1641)) {
        Write-WarningLine "$Name requested a restart."
    }
}

function Ensure-ServiceRunning {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSeconds = 30
    )

    $service = Get-Service -Name $Name -ErrorAction Stop
    Set-Service -Name $Name -StartupType Automatic
    if ($service.Status -ne "Running") {
        Start-Service -Name $Name
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $service = Get-Service -Name $Name
        if ($service.Status -eq "Running") { return }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    throw "Service did not reach Running state: $Name"
}

function Set-RestrictedFirewallRule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][int]$Port
    )

    Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -Name $Name `
        -DisplayName $DisplayName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -RemoteAddress "100.64.0.0/10" `
        -Profile Any | Out-Null
}

function Find-TailscaleExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Tailscale\tailscale.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    throw "tailscale.exe was not found after installation."
}

function Find-RustDeskExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "RustDesk\rustdesk.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Get-ListeningPortState {
    param([int]$Port)
    $connections = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    if ($connections.Count -gt 0) { return "LISTENING" }
    return "not listening"
}

try {
    Write-Host "Ubuntu Tailscale Remote Access - Windows"
    Write-Host "Version: $ProjectVersion"
    Write-Host "Log: $LogFile"
    Write-Host "Package directory: $PackageDir"

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "This test branch currently supports 64-bit Windows only."
    }

    if (-not (Test-Path $PackageDir)) {
        throw "Package directory not found: $PackageDir"
    }

    Test-PackageHashes

    if (-not $SkipOpenSSH) {
        Write-Step "1/4 Install Win32-OpenSSH"
        $openSshMsi = Get-OnePackage -Pattern "OpenSSH-Win64-*.msi" -DisplayName "Win32-OpenSSH"
        Install-Msi -Path $openSshMsi -Name "openssh"

        Ensure-ServiceRunning -Name "sshd"
        Disable-BroadInboundRules -NamePattern "*OpenSSH*"
        Disable-BroadInboundRules -NamePattern "*sshd*"
        Set-RestrictedFirewallRule `
            -Name "RCS-OpenSSH-Tailscale" `
            -DisplayName "OpenSSH via Tailscale only" `
            -Port 22
    } else {
        Write-WarningLine "OpenSSH installation skipped."
    }

    Write-Step "2/4 Install Tailscale"
    $tailscaleMsi = Get-OnePackage -Pattern "tailscale-setup-*-amd64.msi" -DisplayName "Tailscale"
    Install-Msi `
        -Path $tailscaleMsi `
        -Name "tailscale" `
        -Properties @(
            "TS_UNATTENDEDMODE=always",
            "TS_ALLOWINCOMINGCONNECTIONS=always"
        )

    Ensure-ServiceRunning -Name "Tailscale"
    $tailscaleExe = Find-TailscaleExe

    if (-not $SkipRustDesk) {
        Write-Step "3/4 Install RustDesk"
        $rustDeskMsi = Get-OnePackage -Pattern "rustdesk-*-x86_64.msi" -DisplayName "RustDesk"
        Install-Msi `
            -Path $rustDeskMsi `
            -Name "rustdesk" `
            -Properties @(
                "CREATESTARTMENUSHORTCUTS=Y",
                "CREATEDESKTOPSHORTCUTS=Y",
                "INSTALLPRINTER=N"
            )

        $rustDeskService = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
        if ($rustDeskService) {
            Ensure-ServiceRunning -Name "RustDesk"
        } else {
            Write-WarningLine "RustDesk service was not found. Open RustDesk once and select Install Service."
        }

        Disable-BroadInboundRules -NamePattern "*RustDesk*"
        Set-RestrictedFirewallRule `
            -Name "RCS-RustDesk-Tailscale" `
            -DisplayName "RustDesk direct IP via Tailscale only" `
            -Port 21118

        $rustDeskExe = Find-RustDeskExe
        if ($rustDeskExe) {
            Start-Process -FilePath $rustDeskExe
        }
    } else {
        Write-WarningLine "RustDesk installation skipped."
    }

    if ($DisableSleep) {
        Write-Step "Apply optional sleep setting"
        powercfg.exe /change standby-timeout-ac 0 | Out-Null
    }

    Write-Step "4/4 Tailscale login"
    if (-not $SkipTailscaleLogin) {
        Write-Host ""
        Write-Host "The browser login page will open." -ForegroundColor Green
        Write-Host "Sign in with the SAME Tailscale account used by the Ubuntu device." -ForegroundColor Green
        Write-Host ""
        & $tailscaleExe login
        if ($LASTEXITCODE -ne 0) {
            throw "Tailscale login failed with exit code $LASTEXITCODE"
        }
    }

    $tailscaleIp = (& $tailscaleExe ip -4 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($tailscaleIp)) {
        $tailscaleIp = "(not logged in)"
    }

    $currentUser = [Environment]::UserName

    Write-Host ""
    Write-Host "================ Connection summary ================" -ForegroundColor Green
    Write-Host ("Windows user:        {0}" -f $currentUser)
    Write-Host ("Tailscale IPv4:      {0}" -f $tailscaleIp)
    Write-Host ("SSH command:         ssh {0}@{1}" -f $currentUser, $tailscaleIp)
    Write-Host ("RustDesk direct IP:  {0}:21118" -f $tailscaleIp)
    Write-Host ""
    Write-Host ("Port 22:             {0}" -f (Get-ListeningPortState -Port 22))
    Write-Host ("Port 10808:          {0}" -f (Get-ListeningPortState -Port 10808))
    Write-Host ("Port 21118:          {0}" -f (Get-ListeningPortState -Port 21118))
    Write-Host ""
    Write-Host "RustDesk final setup:"
    Write-Host "Settings -> Security -> Unlock security settings"
    Write-Host "Enable direct IP access and set a permanent password."
    Write-Host ""
    Write-Host ("Install log: {0}" -f $LogFile)
    Write-Host "====================================================" -ForegroundColor Green

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("[windows-setup] ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Log: {0}" -f $LogFile) -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
