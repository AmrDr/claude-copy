<#
  copy-last-answer.ps1  -  part of "Claude Copy"
  --------------------------------------------------------------
  Extracts the most recent response of a Claude Code session and
  copies it to the Windows clipboard.

  Normally invoked by claude-copy.ahk, which passes:
    1. $StatusFile - this script writes "OK ..." / "ERR ..." there
    2. $TitleFile  - a file containing the active terminal window title

  Picking the right session:
    Claude Code writes {"type":"ai-title", ...} entries into its
    transcript, and the terminal window title mirrors that ai-title.
    This script matches the active window title against every
    session's ai-title and reads that session's transcript. If no
    match is found, the most recently updated transcript is used.

  See README.md for details and limitations.
#>
param([string]$StatusFile, [string]$TitleFile)

# ============================ CONFIGURATION ============================
# What to copy from Claude's most recent response:
#   'text'        Only Claude's answer text (including ``` code blocks
#                 that are part of the answer itself).
#   'text+code'   Answer text + commands Claude ran + files it wrote/edited.
#   'everything'  All of the above + the output of every tool call.
$CopyMode = 'text'

# In 'everything' mode, truncate each tool output to this many
# characters (0 = no limit).
$MaxToolOutputChars = 0
# =======================================================================

if ($CopyMode -notin @('text', 'text+code', 'everything')) { $CopyMode = 'text' }

function Write-Status([string]$msg) {
    Write-Output $msg
    if ($StatusFile) {
        try {
            $enc = New-Object System.Text.UTF8Encoding $false   # no BOM
            [System.IO.File]::WriteAllText($StatusFile, $msg, $enc)
        } catch { }
    }
}

# Latest ai-title (= terminal window title) of a transcript.
function Get-AiTitle([string]$path) {
    try { $tail = Get-Content -LiteralPath $path -Tail 800 -Encoding UTF8 } catch { return '' }
    for ($i = $tail.Count - 1; $i -ge 0; $i--) {
        if ($tail[$i] -like '*"type":"ai-title"*') {
            try {
                $o = $tail[$i] | ConvertFrom-Json
                if ($o.aiTitle) { return [string]$o.aiTitle }
            } catch { }
        }
    }
    return ''
}

# Is this entry a real user prompt (= the start of a turn)?
# Tool results, system reminders and meta entries do NOT count.
function Test-RealPrompt($obj) {
    if ($obj.type -ne 'user' -or $obj.message.role -ne 'user') { return $false }
    if ($obj.isMeta -eq $true) { return $false }
    $c = $obj.message.content
    if ($c -is [string]) { return -not [string]::IsNullOrWhiteSpace($c) }
    if (-not $c) { return $false }
    $isToolResult = $false
    $hasText = $false
    foreach ($b in $c) {
        if ($b.type -eq 'tool_result') { $isToolResult = $true }
        if ($b.type -eq 'text' -and -not [string]::IsNullOrWhiteSpace($b.text)) { $hasText = $true }
    }
    return ($hasText -and -not $isToolResult)
}

# Render a tool_use block (command run / file written / etc.).
function Format-ToolUse($b) {
    $name = [string]$b.name
    $inp  = $b.input
    if ($null -ne $inp.command) {
        return ">>> Command ($name):`n" + [string]$inp.command
    }
    if (($null -ne $inp.content) -and ($null -ne $inp.file_path)) {
        return ">>> Wrote file: $($inp.file_path)`n" + [string]$inp.content
    }
    if (($null -ne $inp.file_path) -and (($null -ne $inp.old_string) -or ($null -ne $inp.new_string))) {
        return ">>> Edited file: $($inp.file_path)`n--- before ---`n" + [string]$inp.old_string +
               "`n--- after ---`n" + [string]$inp.new_string
    }
    $j = ''
    try { $j = ($inp | ConvertTo-Json -Depth 8 -Compress) } catch { $j = [string]$inp }
    return ">>> Tool ($name): $j"
}

# Render a tool_result block (the output of a tool call).
function Format-ToolResult($b) {
    $c = $b.content
    $txt = ''
    if ($c -is [string]) {
        $txt = $c
    }
    elseif ($c) {
        $parts = @()
        foreach ($p in $c) {
            if ($p -is [string]) { $parts += $p }
            elseif ($null -ne $p.text) { $parts += [string]$p.text }
        }
        $txt = $parts -join "`n"
    }
    if ($MaxToolOutputChars -gt 0 -and $txt.Length -gt $MaxToolOutputChars) {
        $txt = $txt.Substring(0, $MaxToolOutputChars) + "`n... [truncated]"
    }
    $label = if ($b.is_error -eq $true) { '<<< Output (error):' } else { '<<< Output:' }
    return $label + "`n" + $txt
}

# Extract the whole last response turn from a transcript.
function Get-LastAnswer([string]$path) {
    $includeTools  = ($CopyMode -eq 'text+code' -or $CopyMode -eq 'everything')
    $includeOutput = ($CopyMode -eq 'everything')

    $lines = Get-Content -LiteralPath $path -Encoding UTF8

    # Phase A: find the last 'assistant' line. Anything after it
    # (shell commands, a new prompt without an answer, ...) is ignored.
    $lastAsst = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
        if ($o.type -eq 'assistant' -and $o.message.role -eq 'assistant') { $lastAsst = $i; break }
    }
    if ($lastAsst -lt 0) { return '' }

    # Phase B: walk back to the start of the turn (line after the prompt).
    $turnStart = 0
    for ($i = $lastAsst; $i -ge 0; $i--) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
        if (Test-RealPrompt $o) { $turnStart = $i + 1; break }
    }

    # Phase C: walk the turn forward, emitting blocks in order.
    $parts = [System.Collections.Generic.List[string]]::new()
    for ($i = $turnStart; $i -le $lastAsst; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }

        if ($o.type -eq 'assistant' -and $o.message.role -eq 'assistant') {
            $c = $o.message.content
            if ($c -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($c)) { $parts.Add($c) }
            }
            elseif ($c) {
                foreach ($b in $c) {
                    if ($b.type -eq 'text') {
                        if (-not [string]::IsNullOrWhiteSpace($b.text)) { $parts.Add([string]$b.text) }
                    }
                    elseif ($b.type -eq 'tool_use' -and $includeTools) {
                        $parts.Add((Format-ToolUse $b))
                    }
                    # 'thinking' blocks are always skipped
                }
            }
        }
        elseif ($includeOutput -and $o.type -eq 'user' -and $o.message.role -eq 'user') {
            $c = $o.message.content
            if (($c -isnot [string]) -and $c) {
                foreach ($b in $c) {
                    if ($b.type -eq 'tool_result') { $parts.Add((Format-ToolResult $b)) }
                }
            }
        }
    }

    if ($parts.Count -eq 0) { return '' }
    $a = ($parts -join "`n`n") -replace "`r`n", "`n" -replace "`r", "`n"
    $a = $a.Trim()
    return ($a -replace "`n", "`r`n")   # normalise to CRLF
}

try {
    $projectsDir = Join-Path $env:USERPROFILE '.claude\projects'
    if (-not (Test-Path $projectsDir)) { Write-Status 'ERR .claude\projects folder not found'; exit 1 }

    # Newest transcript per project folder.
    $candidates = @()
    foreach ($folder in (Get-ChildItem -LiteralPath $projectsDir -Directory -ErrorAction SilentlyContinue)) {
        $j = Get-ChildItem -LiteralPath $folder.FullName -Filter *.jsonl -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($j) { $candidates += $j }
    }
    if ($candidates.Count -eq 0) { Write-Status 'ERR No transcript found'; exit 1 }

    # Active terminal window title.
    $winTitle = ''
    if ($TitleFile -and (Test-Path -LiteralPath $TitleFile)) {
        try { $winTitle = ([string](Get-Content -LiteralPath $TitleFile -Raw -Encoding UTF8)).Trim() } catch { }
    }

    # Match the window title to a session via its ai-title.
    $target = $null
    $how = 'newest transcript'
    if ($winTitle.Length -ge 3) {
        $hits = @()
        foreach ($c in $candidates) {
            $ai = Get-AiTitle $c.FullName
            if ($ai.Length -ge 3 -and
                $winTitle.IndexOf($ai, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += [pscustomobject]@{ File = $c; Len = $ai.Length }
            }
        }
        if ($hits.Count -gt 0) {
            $best = $hits |
                Sort-Object @{Expression={$_.Len}}, @{Expression={$_.File.LastWriteTime}} -Descending |
                Select-Object -First 1
            $target = $best.File
            $how = 'active window'
        }
    }
    if (-not $target) {
        $target = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    $answer = Get-LastAnswer $target.FullName
    if ([string]::IsNullOrWhiteSpace($answer)) { Write-Status 'ERR No answer found in transcript'; exit 1 }

    Set-Clipboard -Value $answer
    Write-Status ('OK ' + $answer.Length + ' chars - ' + $how)
    exit 0
}
catch {
    Write-Status ('ERR ' + $_.Exception.Message)
    exit 1
}
