@echo off
setlocal
cd /d "%~dp0"
title Ubuntu Tailscale Remote Access - Windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo Installation failed. Exit code: %RC%
) else (
  echo Installation finished.
)
echo.
pause
exit /b %RC%
