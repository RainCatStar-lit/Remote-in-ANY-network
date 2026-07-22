# Compatibility wrapper.
$target = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "windows\install.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @args
exit $LASTEXITCODE
