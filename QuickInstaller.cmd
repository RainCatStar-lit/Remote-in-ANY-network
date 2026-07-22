@echo off
setlocal EnableExtensions
set "SCRIPT_URL=https://raw.githubusercontent.com/RainCatStar-lit/Ubuntu-tailscale-remote-access/main/QuickInstaller.ps1"
set "SCRIPT_FILE=%TEMP%\RCS-QuickInstaller.ps1"
title RCS Remote Access QuickInstaller

echo [quick-installer] Downloading the small Windows bootstrap script...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$u='%SCRIPT_URL%?ts=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds();" ^
  "$d='%SCRIPT_FILE%';" ^
  "$ports=@(10808,10809,7890,7897);" ^
  "$done=$false;" ^
  "foreach($port in $ports){try{if(Test-NetConnection 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue){Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Proxy ('http://127.0.0.1:'+$port) -Uri $u -OutFile $d;$done=$true;break}}catch{}};" ^
  "if(-not $done){Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $u -OutFile $d}"

if errorlevel 1 (
  echo [quick-installer] Failed to download QuickInstaller.ps1.
  echo Check GitHub access or start the local proxy on 10808.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_FILE%" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo Quick installation failed. Exit code: %RC%
) else (
  echo Quick installation finished.
)
echo.
pause
exit /b %RC%
