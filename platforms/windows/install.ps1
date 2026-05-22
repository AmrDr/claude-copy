<#
  install.ps1  -  Claude Copy installer for Windows
  --------------------------------------------------------------
  Sets up the global hotkey that copies Claude Code's last
  answer to the clipboard.

  Run from this folder:
      pwsh -ExecutionPolicy Bypass -File install.ps1

  Options:
      -Hotkey <combo>     e.g. "ctrl+alt+c", "ctrl+shift+y", "super+c".
                          Sets [hotkey] combo in config.ini.
      -Mode <mode>        text | text+code | everything
                          Sets [copy] mode in config.ini.
      -NoAutostart        Do not start automatically at login.
      -NoLaunch           Do not start the hotkey right now.

  Re-running with no flags PRESERVES your existing config.ini.
#>
param(
    [string]$Hotkey = '',
    [ValidateSet('', 'text', 'text+code', 'everything')]
    [string]$Mode = '',
    [switch]$NoAutostart,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$repoDir   = $PSScriptRoot
$rootDir   = Split-Path -Parent (Split-Path -Parent $repoDir)
$srcAhk    = Join-Path $repoDir 'claude-copy.ahk'
$srcPs     = Join-Path $repoDir 'copy-last-answer.ps1'
$srcConfig = Join-Path $rootDir 'config.example.ini'
if (-not (Test-Path $srcAhk) -or -not (Test-Path $srcPs)) {
    Write-Host "ERROR: claude-copy.ahk / copy-last-answer.ps1 must sit next to install.ps1." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $srcConfig)) {
    Write-Host "ERROR: config.example.ini not found at repository root: $srcConfig" -ForegroundColor Red
    exit 1
}

function Find-AutoHotkey {
    $cands = @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($p in $cands) { if ($p -and (Test-Path $p)) { return $p } }
    $cmd = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($root in @("$env:ProgramFiles\AutoHotkey", "$env:LOCALAPPDATA\Programs\AutoHotkey")) {
        if (Test-Path $root) {
            $f = Get-ChildItem $root -Recurse -Filter 'AutoHotkey*.exe' -ErrorAction SilentlyContinue |
                 Where-Object { $_.VersionInfo.ProductVersion -like '2.*' } | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}

# Update a single key in an INI file, preserving everything else.
function Set-IniValue([string]$path, [string]$section, [string]$key, [string]$value) {
    if (-not (Test-Path -LiteralPath $path)) {
        Set-Content -LiteralPath $path -Value @("[$section]", "$key = $value") -Encoding UTF8
        return
    }
    $lines = Get-Content -LiteralPath $path
    $inSec = $false
    $secSeen = $false
    $keyMatch = "^\s*$([Regex]::Escape($key))\s*="
    $secMatch = "^\s*\[$([Regex]::Escape($section))\]\s*$"
    $newLines = New-Object System.Collections.Generic.List[string]
    $written = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match $secMatch) {
            $inSec = $true; $secSeen = $true
            $newLines.Add($line)
            continue
        }
        if ($line -match '^\s*\[.+\]\s*$') {
            # leaving previous section; if we still need to write, do it before
            if ($inSec -and -not $written) {
                $newLines.Add("$key = $value")
                $written = $true
            }
            $inSec = $false
            $newLines.Add($line)
            continue
        }
        if ($inSec -and ($line -match $keyMatch)) {
            $newLines.Add("$key = $value")
            $written = $true
            continue
        }
        $newLines.Add($line)
    }
    if (-not $written) {
        if (-not $secSeen) { $newLines.Add("[$section]") }
        $newLines.Add("$key = $value")
    }
    Set-Content -LiteralPath $path -Value $newLines.ToArray() -Encoding UTF8
}

Write-Host "Claude Copy - Windows installer" -ForegroundColor Cyan
Write-Host ""

# 1. AutoHotkey v2
$ahkExe = Find-AutoHotkey
if (-not $ahkExe) {
    Write-Host "ERROR: AutoHotkey v2 was not found." -ForegroundColor Red
    Write-Host "Install it from https://www.autohotkey.com/  (choose v2), then run install.ps1 again."
    exit 1
}
Write-Host "AutoHotkey v2 : $ahkExe"

# 2. Install folder
$installDir = Join-Path $env:LOCALAPPDATA 'ClaudeCopy'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$dstAhk    = Join-Path $installDir 'claude-copy.ahk'
$dstPs     = Join-Path $installDir 'copy-last-answer.ps1'
$dstConfig = Join-Path $installDir 'config.ini'

# 3. Stop any running instance (we are about to overwrite it)
Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*claude-copy.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 400

# 4. Copy scripts
Copy-Item $srcAhk $dstAhk -Force
Copy-Item $srcPs  $dstPs  -Force
Write-Host "Installed to  : $installDir"

# 5. Config file: create from example if missing, then patch with flags
if (-not (Test-Path -LiteralPath $dstConfig)) {
    Copy-Item $srcConfig $dstConfig -Force
    Write-Host "Config created: $dstConfig (from config.example.ini)"
}
if ($Hotkey -ne '') {
    Set-IniValue $dstConfig 'hotkey' 'combo' $Hotkey
    Write-Host "Hotkey        : $Hotkey"
}
if ($Mode -ne '') {
    Set-IniValue $dstConfig 'copy' 'mode' $Mode
    Write-Host "Copy mode     : $Mode"
}

# 6. Clean up older versions (pre-v2 lived in ~/.claude/scripts)
$legacyDir = Join-Path $env:USERPROFILE '.claude\scripts'
foreach ($n in 'claude-copy.ahk', 'copy-last-answer.ps1') {
    $lp = Join-Path $legacyDir $n
    if (Test-Path $lp) { Remove-Item $lp -Force -ErrorAction SilentlyContinue }
}

# 7. Autostart shortcut
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'Claude Copy Hotkey.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
if ($NoAutostart) {
    Write-Host "Autostart     : disabled"
} else {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath       = $ahkExe
    $sc.Arguments        = '"' + $dstAhk + '"'
    $sc.WorkingDirectory = $installDir
    $sc.Description      = 'Claude Copy - copy Claude Code last answer'
    $sc.Save()
    Write-Host "Autostart     : on  ($lnk)"
}

# 8. Launch
if (-not $NoLaunch) {
    Start-Process -FilePath $ahkExe -ArgumentList ('"' + $dstAhk + '"')
    Write-Host "Status        : running"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
if (-not $NoLaunch) {
    # Show the active hotkey
    $combo = 'ctrl+alt+c'
    if (Test-Path $dstConfig) {
        $hit = Select-String -LiteralPath $dstConfig -Pattern '^\s*combo\s*=\s*(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $combo = ($hit.Matches[0].Groups[1].Value).Trim() }
    }
    Write-Host "Press $combo in a Claude Code terminal."
}
