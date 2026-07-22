[CmdletBinding()]
param(
    [string]$Proxy = "",
    [string]$WindowsBranch = "TEST-IN-WINDOWS",
    [switch]$SkipOpenSSH,
    [switch]$SkipRustDesk,
    [switch]$SkipTailscaleLogin,
    [switch]$DisableSleep,
    [switch]$ForceDownload,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$QuickVersion = "1.0.0"
$RepoOwner = "RainCatStar-lit"
$RepoName = "Ubuntu-tailscale-remote-access"
$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$WindowsBranch"
$CacheRoot = Join-Path $env:ProgramData "Ubuntu-tailscale-remote-access\quick-installer\$WindowsBranch"
$WindowsRoot = Join-Path $CacheRoot "windows"
$PackageDir = Join-Path $WindowsRoot "packages"
$InstallerPath = Join-Path $WindowsRoot "install.ps1"
$ManifestPath = Join-Path $PackageDir "SHA256SUMS.txt"
$LogDir = Join-Path $env:ProgramData "Ubuntu-tailscale-remote-access\logs"
$LogFile = Join-Path $LogDir ("quick-installer-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Argument {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Request-Elevation {
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Argument $PSCommandPath),
        "-WindowsBranch", (Quote-Argument $WindowsBranch),
        "-Elevated"
    )
    if ($Proxy) { $arguments += @("-Proxy", (Quote-Argument $Proxy)) }
    if ($SkipOpenSSH) { $arguments += "-SkipOpenSSH" }
    if ($SkipRustDesk) { $arguments += "-SkipRustDesk" }
    if ($SkipTailscaleLogin) { $arguments += "-SkipTailscaleLogin" }
    if ($DisableSleep) { $arguments += "-DisableSleep" }
    if ($ForceDownload) { $arguments += "-ForceDownload" }

    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

if (-not (Test-Administrator)) {
    Request-Elevation
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Only 64-bit Windows is supported."
}

$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10) {
    throw "Windows 10 or Windows 11 is required."
}

New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("[quick-installer] {0}" -f $Message) -ForegroundColor Cyan
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
    if ($Proxy) {
        return $Proxy
    }

    foreach ($port in @(10808, 10809, 7890, 7897)) {
        if (Test-LocalPort -Port $port) {
            return "http://127.0.0.1:$port"
        }
    }
    return ""
}

$ResolvedProxy = Resolve-Proxy
if ($ResolvedProxy) {
    Write-Host ("[quick-installer] Proxy: {0}" -f $ResolvedProxy)
}
else {
    Write-Host "[quick-installer] Proxy: direct connection"
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

    $common = @{
        Uri = $Uri
        OutFile = $temporary
        UseBasicParsing = $true
        TimeoutSec = 120
        Headers = @{ "Cache-Control" = "no-cache" }
    }

    if ($ResolvedProxy) {
        try {
            Write-Host ("Downloading through proxy: {0}" -f $Uri)
            Invoke-WebRequest @common -Proxy $ResolvedProxy
            Move-Item $temporary $OutFile -Force
            return
        }
        catch {
            Remove-Item $temporary -Force -ErrorAction SilentlyContinue
            Write-Host "Proxy download failed; trying direct connection once." -ForegroundColor Yellow
        }
    }

    try {
        Write-Host ("Downloading directly: {0}" -f $Uri)
        Invoke-WebRequest @common
        Move-Item $temporary $OutFile -Force
        return
    }
    catch {
        Remove-Item $temporary -Force -ErrorAction SilentlyContinue
        throw "Download failed: $Uri. $($_.Exception.Message)"
    }
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

function Ensure-ExistingComponentsConfigured {
    param(
        [bool]$OpenSSHAlreadyInstalled,
        [bool]$RustDeskAlreadyInstalled
    )

    if ($OpenSSHAlreadyInstalled) {
        $service = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name "sshd" -StartupType Automatic
            if ($service.Status -ne "Running") {
                Start-Service -Name "sshd"
            }
            Disable-BroadInboundRules -NamePattern "*OpenSSH*"
            Disable-BroadInboundRules -NamePattern "*sshd*"
            Set-RestrictedFirewallRule `
                -Name "RCS-OpenSSH-Tailscale" `
                -DisplayName "OpenSSH via Tailscale only" `
                -Port 22
        }
    }

    if ($RustDeskAlreadyInstalled) {
        $service = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name "RustDesk" -StartupType Automatic
            if ($service.Status -ne "Running") {
                Start-Service -Name "RustDesk"
            }
        }
        Disable-BroadInboundRules -NamePattern "*RustDesk*"
        Set-RestrictedFirewallRule `
            -Name "RCS-RustDesk-Tailscale" `
            -DisplayName "RustDesk direct IP via Tailscale only" `
            -Port 21118
    }
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

try {
    Write-Host "Ubuntu Tailscale Remote Access - QuickInstaller"
    Write-Host ("Version: {0}" -f $QuickVersion)
    Write-Host ("System: Windows {0}, x64" -f $osVersion)
    Write-Host ("Selected branch: {0}" -f $WindowsBranch)
    Write-Host ("Cache: {0}" -f $CacheRoot)
    Write-Host ("Log: {0}" -f $LogFile)

    $openSSHAlreadyInstalled = Test-OpenSSHInstalled
    $rustDeskAlreadyInstalled = Test-RustDeskInstalled
    $effectiveSkipOpenSSH = $SkipOpenSSH -or $openSSHAlreadyInstalled
    $effectiveSkipRustDesk = $SkipRustDesk -or $rustDeskAlreadyInstalled

    if (-not $SkipOpenSSH -and $effectiveSkipOpenSSH) {
        Write-Host "OpenSSH is already installed; its package will not be downloaded."
    }
    if (-not $SkipRustDesk -and $effectiveSkipRustDesk) {
        Write-Host "RustDesk is already installed; its package will not be downloaded."
    }

    Write-Step "Download the Windows branch installer"
    Invoke-Download -Uri "$RawBase/windows/install.ps1?ts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" -OutFile $InstallerPath

    Write-Step "Read the package manifest"
    $manifestTemp = Join-Path $PackageDir "SHA256SUMS.full.txt"
    Invoke-Download -Uri "$RawBase/windows/packages/SHA256SUMS.txt?ts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" -OutFile $manifestTemp
    $manifestText = Get-Content $manifestTemp -Raw

    $entries = @()
    foreach ($match in [regex]::Matches($manifestText, "(?i)([0-9a-f]{64})\s+([^\s]+\.msi)")) {
        $entries += [pscustomobject]@{
            Hash = $match.Groups[1].Value.ToLowerInvariant()
            Name = $match.Groups[2].Value
        }
    }
    if ($entries.Count -lt 3) {
        throw "The package manifest is incomplete or invalid."
    }

    $selected = @()
    $selected += @($entries | Where-Object Name -Like "tailscale-setup-*-amd64.msi")
    if (-not $effectiveSkipOpenSSH) {
        $selected += @($entries | Where-Object Name -Like "OpenSSH-Win64-*.msi")
    }
    if (-not $effectiveSkipRustDesk) {
        $selected += @($entries | Where-Object Name -Like "rustdesk-*-x86_64.msi")
    }

    if ($selected.Count -lt 1) {
        throw "No required packages were selected from the manifest."
    }

    Set-Content -Path $ManifestPath -Encoding ASCII -Value @(
        $selected | ForEach-Object { "{0} {1}" -f $_.Hash, $_.Name }
    )

    Write-Step "Download only the required MSI packages"
    foreach ($entry in $selected) {
        $packagePath = Join-Path $PackageDir $entry.Name
        if (-not $ForceDownload -and (Test-FileHashValue -Path $packagePath -Expected $entry.Hash)) {
            Write-Host ("Using cached package: {0}" -f $entry.Name)
            continue
        }

        $encodedName = [Uri]::EscapeDataString($entry.Name)
        Invoke-Download -Uri "$RawBase/windows/packages/$encodedName" -OutFile $packagePath
        if (-not (Test-FileHashValue -Path $packagePath -Expected $entry.Hash)) {
            Remove-Item $packagePath -Force -ErrorAction SilentlyContinue
            throw "SHA-256 verification failed: $($entry.Name)"
        }
        Write-Host ("SHA-256 verified: {0}" -f $entry.Name)
    }

    Write-Step "Start the branch installer"
    $installerArguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $InstallerPath,
        "-Elevated"
    )
    if ($effectiveSkipOpenSSH) { $installerArguments += "-SkipOpenSSH" }
    if ($effectiveSkipRustDesk) { $installerArguments += "-SkipRustDesk" }
    if ($SkipTailscaleLogin) { $installerArguments += "-SkipTailscaleLogin" }
    if ($DisableSleep) { $installerArguments += "-DisableSleep" }

    & powershell.exe @installerArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "The Windows branch installer failed with exit code $exitCode."
    }

    Ensure-ExistingComponentsConfigured `
        -OpenSSHAlreadyInstalled ($openSSHAlreadyInstalled -and -not $SkipOpenSSH) `
        -RustDeskAlreadyInstalled ($rustDeskAlreadyInstalled -and -not $SkipRustDesk)

    Write-Host ""
    Write-Host "Quick installation completed." -ForegroundColor Green
    Write-Host ("QuickInstaller log: {0}" -f $LogFile)
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("[quick-installer] ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Log: {0}" -f $LogFile) -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
