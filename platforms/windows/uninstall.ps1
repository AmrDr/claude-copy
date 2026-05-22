<#
  uninstall.ps1  -  remove Claude Copy from Windows
  Run:  pwsh -ExecutionPolicy Bypass -File uninstall.ps1
#>
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Claude Copy - Windows uninstaller" -ForegroundColor Cyan

# Stop the running hotkey
Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe'" |
    Where-Object { $_.CommandLine -like '*claude-copy.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# Remove the autostart shortcut
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Copy Hotkey.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "Removed autostart shortcut" }

# Remove the install folder (incl. config.ini)
$installDir = Join-Path $env:LOCALAPPDATA 'ClaudeCopy'
if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force; Write-Host "Removed $installDir" }

Write-Host "Done. Claude Copy has been removed." -ForegroundColor Green
