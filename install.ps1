<#
  install.ps1  -  Claude Copy installer
  --------------------------------------------------------------
  Installs the Ctrl+Alt+C hotkey that copies Claude Code's last
  answer to the clipboard.

  Run from the repository folder:
      pwsh -ExecutionPolicy Bypass -File install.ps1

  Options:
      -Mode <text|text+code|everything>
            What the hotkey copies. Default: text
      -NoAutostart   Do not start automatically at login.
      -NoLaunch      Do not start the hotkey right now.
#>
param(
    [ValidateSet('text', 'text+code', 'everything')]
    [string]$Mode = 'text',
    [switch]$NoAutostart,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$repoDir = $PSScriptRoot
$srcAhk  = Join-Path $repoDir 'claude-copy.ahk'
$srcPs   = Join-Path $repoDir 'copy-last-answer.ps1'
if (-not (Test-Path $srcAhk) -or -not (Test-Path $srcPs)) {
    Write-Host "ERROR: claude-copy.ahk / copy-last-answer.ps1 must sit next to install.ps1." -ForegroundColor Red
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

Write-Host "Claude Copy - installer" -ForegroundColor Cyan
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
$dstAhk = Join-Path $installDir 'claude-copy.ahk'
$dstPs  = Join-Path $installDir 'copy-last-answer.ps1'

# 3. Stop any running instance before overwriting
Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*claude-copy.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 400

# 4. Copy the scripts into the install folder
Copy-Item $srcAhk $dstAhk -Force
Copy-Item $srcPs  $dstPs  -Force
Write-Host "Installed to  : $installDir"

# 5. Apply the copy mode to the installed copy
$lines = Get-Content -LiteralPath $dstPs
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\$CopyMode\s*=') { $lines[$i] = "`$CopyMode = '$Mode'" }
}
Set-Content -LiteralPath $dstPs -Value $lines -Encoding UTF8
Write-Host "Copy mode     : $Mode"

# 6. Clean up installs from older versions of this tool
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
    $sc.Description      = 'Claude Copy - copy Claude Code last answer (Ctrl+Alt+C)'
    $sc.Save()
    Write-Host "Autostart     : on  ($lnk)"
}

# 8. Launch now
if (-not $NoLaunch) {
    Start-Process -FilePath $ahkExe -ArgumentList ('"' + $dstAhk + '"')
    Write-Host "Status        : running"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
if (-not $NoLaunch) {
    Write-Host "Try it: in a Claude Code terminal, press Ctrl+Alt+C."
}
