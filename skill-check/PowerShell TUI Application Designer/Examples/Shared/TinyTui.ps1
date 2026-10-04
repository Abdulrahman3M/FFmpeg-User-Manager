# TinyTui.ps1 - a deliberately small helper used ONLY by the examples (dot-source it). It shows the minimum of the pattern;
# real applications use the modular template in Templates/App (separate Renderer, Input, Menu, Theme modules).
# Works on Windows PowerShell 5.1 and PowerShell 7.x on Windows and Linux. ASCII-only source.
Set-StrictMode -Version 2.0
$script:TinyKeys = New-Object System.Collections.Generic.Queue[string]
$script:TinyDemo = $false

function Set-DemoKeys {
    # Tokens: {Enter} {Esc}; everything else is typed one character at a time.
    param([string]$Text)
    $script:TinyDemo = $true; $script:TinyKeys = New-Object System.Collections.Generic.Queue[string]
    $i = 0
    while ($i -lt $Text.Length) {
        if ($Text[$i] -eq '{') { $c = $Text.IndexOf('}', $i); $script:TinyKeys.Enqueue($Text.Substring($i + 1, $c - $i - 1)); $i = $c + 1 } else { $script:TinyKeys.Enqueue([string]$Text[$i]); $i++ }
    }
}
function Read-TinyKey {
    if ($script:TinyDemo) { if ($script:TinyKeys.Count -eq 0) { throw 'Demo keys exhausted.' }; return $script:TinyKeys.Dequeue() }
    $k = [Console]::ReadKey($true)
    switch ($k.Key) { 'Enter' { return 'Enter' } 'Escape' { return 'Esc' } 'Backspace' { return 'Backspace' } default { return [string]$k.KeyChar } }
}
function Write-Line { param([string]$Text = '', [string]$Color = 'Gray') Write-Host $Text -ForegroundColor $Color }
function Get-TinyIcon {
    # Three tiers in one line: emoji only when the terminal is known to draw it, else a single-column symbol, else ASCII.
    param([string]$Emoji, [string]$Symbol, [string]$Ascii)
    $redir = $false; try { $redir = [Console]::IsOutputRedirected } catch { $redir = $true }
    if ($env:EXAMPLE_ICONS -eq 'ascii' -or ($redir -and -not $script:TinyDemo)) { return $Ascii }
    if ($env:EXAMPLE_ICONS -eq 'emoji' -or $env:WT_SESSION -or $env:TERM_PROGRAM) { return $Emoji }
    return $Symbol
}
function Show-NumberedMenu {
    # Returns the chosen item's Value or $null on Esc. Items: hashtables with Label, Desc, Value.
    param([string]$Title, [hashtable[]]$Items)
    $buf = ''
    while ($true) {
        Write-Line ''
        Write-Line $Title 'Cyan'
        for ($i = 0; $i -lt $Items.Count; $i++) { Write-Line ('  {0}  {1}' -f ([string]($i + 1)).PadLeft(2, '0'), $Items[$i].Label) 'White'; Write-Line ('      ' + $Items[$i].Desc) 'DarkGray' }
        Write-Line ('  Type 01-{0} (two digits) or Esc to go back' -f ([string]$Items.Count).PadLeft(2, '0')) 'DarkGray'
        $k = Read-TinyKey
        if ($k -eq 'Esc') { return $null }
        if ($k -match '^\d$') {
            $buf += $k
            if ($buf.Length -ge 2) { $n = [int]$buf; $buf = ''; if ($n -ge 1 -and $n -le $Items.Count) { return $Items[$n - 1].Value } }
        } else { $buf = '' }
    }
}
