param(
    [string]$Proxy = "",
    [switch]$NoRustDesk,
    [switch]$KeepSleep,
    [switch]$SkipTailscaleLogin,
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Elevated'
    )
    if ($Proxy) { $arguments += @('-Proxy', ('"{0}"' -f $Proxy)) }
    if ($NoRustDesk) { $arguments += '-NoRustDesk' }
    if ($KeepSleep) { $arguments += '-KeepSleep' }
    if ($SkipTailscaleLogin) { $arguments += '-SkipTailscaleLogin' }

    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $arguments
    exit $process.ExitCode
}

$LogDir = Join-Path $env:ProgramData 'Ubuntu-tailscale-remote-access\logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $LogFile -Force | Out-Null
$Succeeded = $false

function Write-Step([string]$Text) {
    Write-Host "`n[remote-setup] $Text"
}

function Invoke-Download([string]$Uri, [string]$OutFile) {
    $parameters = @{
        Uri = $Uri
        OutFile = $OutFile
        UseBasicParsing = $true
    }
    if ($Proxy) { $parameters.Proxy = $Proxy }
    Invoke-WebRequest @parameters
}

try {
    Write-Host "[installer] Start: $(Get-Date -Format o)"
    Write-Host "[installer] Log: $LogFile"

    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($build -lt 17763) {
        throw "Windows 10 build 1809 or later is required. Detected build: $build"
    }
    Write-Step "Detected $($os.Caption), build $build"

    Write-Step "Installing OpenSSH Server"
    $ssh = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($ssh.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -Name 'OpenSSH-Server-In-TCP' `
            -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
    }

    Write-Step "Installing Tailscale"
    $tailscaleExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (-not (Test-Path $tailscaleExe)) {
        $jsonFile = Join-Path $env:TEMP 'tailscale-windows.json'
        Invoke-Download 'https://pkgs.tailscale.com/stable/?mode=json&os=windows' $jsonFile
        $metadata = Get-Content $jsonFile -Raw | ConvertFrom-Json
        $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { 'amd64' }
            'ARM64' { 'arm64' }
            default { 'x86' }
        }
        $msiName = $metadata.MSIs.$arch
        if (-not $msiName) { throw "No Tailscale MSI found for $arch" }
        $msiPath = Join-Path $env:TEMP $msiName
        Invoke-Download ("https://pkgs.tailscale.com/stable/{0}" -f $msiName) $msiPath
        $msiLog = Join-Path $LogDir 'tailscale-msi.log'
        $process = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
            '/i', $msiPath, '/qn', '/norestart', '/l*v', $msiLog
        )
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Tailscale MSI failed with exit code $($process.ExitCode)"
        }
    }
    if (-not (Test-Path $tailscaleExe)) { throw 'Tailscale executable was not found after installation' }
    Set-Service -Name Tailscale -StartupType Automatic
    Start-Service Tailscale

    if (-not $NoRustDesk) {
        Write-Step "Installing RustDesk"
        $rustdeskExe = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
        if (-not (Test-Path $rustdeskExe)) {
            $apiFile = Join-Path $env:TEMP 'rustdesk-release.json'
            Invoke-Download 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest' $apiFile
            $release = Get-Content $apiFile -Raw | ConvertFrom-Json
            $asset = $release.assets | Where-Object { $_.name -match 'x86_64\.msi$' } | Select-Object -First 1
            if (-not $asset) {
                $asset = $release.assets | Where-Object { $_.name -match 'x86_64\.exe$' } | Select-Object -First 1
            }
            if (-not $asset) { throw 'No RustDesk Windows installer was found' }
            $installer = Join-Path $env:TEMP $asset.name
            Invoke-Download $asset.browser_download_url $installer
            if ($installer.EndsWith('.msi')) {
                $msiLog = Join-Path $LogDir 'rustdesk-msi.log'
                $process = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
                    '/i', $installer, '/qn', '/norestart', 'INSTALLPRINTER=N', '/l*v', $msiLog
                )
                if ($process.ExitCode -notin @(0, 3010)) {
                    throw "RustDesk MSI failed with exit code $($process.ExitCode)"
                }
            }
            else {
                $process = Start-Process $installer -Wait -PassThru -ArgumentList '--silent-install'
                if ($process.ExitCode -ne 0) {
                    throw "RustDesk installer failed with exit code $($process.ExitCode)"
                }
            }
        }

        if (-not (Get-Service -Name RustDesk -ErrorAction SilentlyContinue)) {
            if (Test-Path $rustdeskExe) {
                Start-Process $rustdeskExe -Wait -ArgumentList '--install-service'
            }
        }
        $rustdeskService = Get-Service -Name RustDesk -ErrorAction SilentlyContinue
        if (-not $rustdeskService) { throw 'RustDesk service was not created' }
        Set-Service -Name RustDesk -StartupType Automatic
        Start-Service RustDesk

        if (-not (Get-NetFirewallRule -Name 'RustDesk-Tailscale-Direct' -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule `
                -Name 'RustDesk-Tailscale-Direct' `
                -DisplayName 'RustDesk direct access over Tailscale' `
                -Enabled True `
                -Direction Inbound `
                -Protocol TCP `
                -Action Allow `
                -LocalPort 21118 `
                -RemoteAddress '100.64.0.0/10' | Out-Null
        }
    }

    if (-not $KeepSleep) {
        Write-Step "Disabling automatic sleep on AC power"
        powercfg.exe /change standby-timeout-ac 0 | Out-Null
        powercfg.exe /hibernate off | Out-Null
    }

    if (-not $SkipTailscaleLogin) {
        $ip = & $tailscaleExe ip -4 2>$null
        if (-not $ip) {
            Write-Host "`nTailscale login is required. The next command displays a browser login URL."
            Write-Host "The login URL is intentionally excluded from the installation log."
            Stop-Transcript | Out-Null
            & $tailscaleExe up
            Start-Transcript -Path $LogFile -Append | Out-Null
        }
    }

    Write-Step "Final verification"
    if ((Get-Service sshd).Status -ne 'Running') { throw 'sshd is not running' }
    if ((Get-CimInstance Win32_Service -Filter "Name='sshd'").StartMode -ne 'Auto') {
        throw 'sshd is not configured for automatic startup'
    }
    if ((Get-Service Tailscale).Status -ne 'Running') { throw 'Tailscale service is not running' }
    if ((Get-CimInstance Win32_Service -Filter "Name='Tailscale'").StartMode -ne 'Auto') {
        throw 'Tailscale is not configured for automatic startup'
    }
    if (-not $NoRustDesk) {
        if ((Get-Service RustDesk).Status -ne 'Running') { throw 'RustDesk service is not running' }
        if ((Get-CimInstance Win32_Service -Filter "Name='RustDesk'").StartMode -ne 'Auto') {
            throw 'RustDesk is not configured for automatic startup'
        }
    }

    $ip = (& $tailscaleExe ip -4 2>$null | Select-Object -First 1)
    Write-Host "`n===== Deployment result ====="
    Write-Host "Installation log: $LogFile"
    $ipDisplay = if ($ip) { $ip } else { 'login not completed' }
    Write-Host "Tailscale IP:     $ipDisplay"
    if ($ip) {
        Write-Host "SSH:              ssh $env:USERNAME@$ip"
        if (-not $NoRustDesk) { Write-Host "RustDesk:         ${ip}:21118" }
    }
    if (-not $NoRustDesk) {
        Write-Host "`nOpen RustDesk -> Settings -> Security, enable Direct IP access, and set your own unattended-access password."
        Write-Host "No password is created or stored by this installer."
    }

    $Succeeded = $true
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($Succeeded) {
        Write-Host "[installer] Result: SUCCESS"
    }
    else {
        Write-Host "[installer] Result: FAILED"
    }
    Write-Host "[installer] End: $(Get-Date -Format o)"
    Write-Host "[installer] Log: $LogFile"
    try { Stop-Transcript | Out-Null } catch {}
}
