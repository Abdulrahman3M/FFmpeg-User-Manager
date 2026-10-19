# Input.psm1 - keyboard reader (real console or scripted queue) and the shared single-line editor.
Set-StrictMode -Version 2.0

$script:Queue = New-Object System.Collections.Generic.Queue[object]
$script:Scripted = $false
$script:Provider = $null
$script:ProviderCalls = 0
$script:ProviderMax = 600

function New-KeyEvent {
    param([string]$Name, [string]$Char = '')
    return [pscustomobject]@{ Name = $Name; Char = $Char }
}

function Add-TuiScriptedKeys {
    param([string]$Script)
    $i = 0
    while ($i -lt $Script.Length) {
        $c = $Script[$i]
        if ($c -eq '{') {
            $j = $Script.IndexOf('}', $i)
            if ($j -gt $i) {
                $tok = $Script.Substring($i + 1, $j - $i - 1)
                $map = @{ Enter = 'Enter'; Esc = 'Esc'; Up = 'Up'; Down = 'Down'; Left = 'Left'; Right = 'Right'; Home = 'Home'; End = 'End'; Del = 'Delete'; BS = 'Backspace'; Tab = 'Tab'; PgUp = 'PageUp'; PgDn = 'PageDown'; CtrlC = 'CtrlC'; Clear = 'ClearLine' }
                if ($map.ContainsKey($tok)) { $script:Queue.Enqueue((New-KeyEvent $map[$tok])); $i = $j + 1; continue }
            }
        }
        if ([char]::IsHighSurrogate($c) -and ($i + 1) -lt $Script.Length) {
            $script:Queue.Enqueue((New-KeyEvent 'Char' ($Script.Substring($i, 2)))); $i += 2; continue
        }
        $script:Queue.Enqueue((New-KeyEvent 'Char' ([string]$c)))
        $i++
    }
}

function Set-TuiScriptedInput {
    # Test/automation hook. Tokens: {Enter} {Esc} {Up} {Down} {Left} {Right} {Home} {End} {Del} {BS} {Tab}
    # {PgUp} {PgDn} {CtrlC} {Clear} (Ctrl+U: clear the line). Any other character is a literal key press.
    param([string]$Script)
    $script:Queue.Clear()
    $script:Provider = $null
    $script:Scripted = $true
    Add-TuiScriptedKeys $Script
}

function Set-TuiScriptedProvider {
    # Test hook: keys are requested on demand from a scriptblock that receives the text of the current screen.
    # Returning $null ends the script (the next key read fails with 'Scripted input exhausted.').
    param([scriptblock]$Provider, [int]$MaxCalls = 600)
    $script:Queue.Clear()
    $script:Scripted = $true
    $script:Provider = $Provider
    $script:ProviderCalls = 0
    $script:ProviderMax = $MaxCalls
}

function Clear-TuiScriptedInput { $script:Queue.Clear(); $script:Scripted = $false; $script:Provider = $null }
function Test-TuiScripted { return $script:Scripted }
function Get-TuiScriptedRemaining { return $script:Queue.Count }

function Convert-ConsoleKey {
    param([System.ConsoleKeyInfo]$Info)
    switch ($Info.Key) {
        'Enter' { return (New-KeyEvent 'Enter') }
        'Escape' { return (New-KeyEvent 'Esc') }
        'UpArrow' { return (New-KeyEvent 'Up') }
        'DownArrow' { return (New-KeyEvent 'Down') }
        'LeftArrow' { return (New-KeyEvent 'Left') }
        'RightArrow' { return (New-KeyEvent 'Right') }
        'Home' { return (New-KeyEvent 'Home') }
        'End' { return (New-KeyEvent 'End') }
        'Delete' { return (New-KeyEvent 'Delete') }
        'Backspace' { return (New-KeyEvent 'Backspace') }
        'Tab' { return (New-KeyEvent 'Tab') }
        'PageUp' { return (New-KeyEvent 'PageUp') }
        'PageDown' { return (New-KeyEvent 'PageDown') }
    }
    if (($Info.Modifiers -band [System.ConsoleModifiers]::Control) -and $Info.Key -eq 'C') { return (New-KeyEvent 'CtrlC') }
    if (($Info.Modifiers -band [System.ConsoleModifiers]::Control) -and $Info.Key -eq 'U') { return (New-KeyEvent 'ClearLine') }
    $ch = $Info.KeyChar
    if ([int]$ch -ge 32 -and [int]$ch -ne 127) { return (New-KeyEvent 'Char' ([string]$ch)) }
    return (New-KeyEvent 'Other')
}

function Test-TuiKeyAvailable {
    if ($script:Scripted) { return ($script:Queue.Count -gt 0) }
    try { return [Console]::KeyAvailable } catch { return $false }
}

function Read-TuiKey {
    if ($script:Scripted) {
        if ($script:Queue.Count -eq 0 -and $script:Provider) {
            $script:ProviderCalls++
            if ($script:ProviderCalls -gt $script:ProviderMax) { $lastFrame = ((Get-CapturedOutput) -split '=====(?:FRAME|CLEAR)=====' | Select-Object -Last 1)
            $flat = ((($lastFrame -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 30) -join ' | ')
            throw ('Scripted provider exceeded the call limit. Last screen: ' + $flat.Substring(0, [Math]::Min(1500, $flat.Length))) }
            $parts = (Get-CapturedOutput) -split '=====(?:FRAME|CLEAR)====='
            $keys = & $script:Provider $parts[$parts.Count - 1]
            if ($null -ne $keys) { Add-TuiScriptedKeys ([string]$keys) }
        }
        if ($script:Queue.Count -eq 0) { throw 'Scripted input exhausted.' }
        return $script:Queue.Dequeue()
    }
    # Console.ReadKey blocks indefinitely, so a resize would otherwise remain invisible until the
    # next key press. Polling KeyAvailable lets every screen receive a Resize event and redraw.
    $viewport = Get-UiSize
    while ($true) {
        try {
            if ([Console]::KeyAvailable) {
                $info = [Console]::ReadKey($true)
                $k = Convert-ConsoleKey $info
                if ($k.Name -ne 'Other') { return $k }
                continue
            }
        } catch { }
        Start-Sleep -Milliseconds 50
        $currentViewport = Get-UiSize
        if (Test-UiViewportChanged -Before $viewport -After $currentViewport) { return (New-KeyEvent 'Resize') }
    }
}

function Read-TuiLine {
    <#
      Single-line editor. Returns @{ Status = 'Ok'|'Back'|'Browse'|'Quit'; Text }.
      Esc = Back. Tab = Browse (only when -AllowBrowse). Supports Left/Right/Home/End/Backspace/Delete and paste.
    #>
    param([string]$Prompt = '> ', [string]$Initial = '', [switch]$AllowBrowse)
    $buf = New-Object System.Text.StringBuilder($Initial)
    $pos = $buf.Length
    $width = (Get-UiWidth) - (Get-TextWidth $Prompt) - 1
    $scriptedOrBuffer = (Test-TuiScripted)
    $render = {
        $text = $buf.ToString()
        $shown = $text
        $off = 0
        if ((Get-TextWidth $text) -gt $width) { $off = [math]::Max(0, $pos - $width + 1); $shown = $text.Substring($off, [math]::Min($text.Length - $off, $width)) }
        Write-Raw "`r"
        Write-Ui -Text $Prompt -Role PrimaryAccent -NoNewline
        Write-Ui -Text $shown -Role NormalText -NoNewline
        Clear-LineRemainder -Used ((Get-TextWidth $Prompt) + (Get-TextWidth $shown))
        if (-not $scriptedOrBuffer) {
            Set-LastFrameRow -Text ($Prompt + $shown)
            Set-CursorColumn ((Get-TextWidth $Prompt) + $pos - $off)
        }
    }
    Show-Cursor
    & $render
    while ($true) {
        $k = Read-TuiKey
        switch ($k.Name) {
            'Resize' { return [pscustomobject]@{ Status = 'Resize'; Text = $buf.ToString() } }
            # The wizard owns this row as part of its frame. Do not emit a newline here; the next
            # frame redraw replaces the prompt and input without leaving a stale line below it.
            'Enter' { return [pscustomobject]@{ Status = 'Ok'; Text = $buf.ToString() } }
            'Esc' { return [pscustomobject]@{ Status = 'Back'; Text = $buf.ToString() } }
            'CtrlC' { return [pscustomobject]@{ Status = 'Quit'; Text = $buf.ToString() } }
            'Tab' { if ($AllowBrowse) { return [pscustomobject]@{ Status = 'Browse'; Text = $buf.ToString() } } }
            'ClearLine' { [void]$buf.Clear(); $pos = 0 }
            'Backspace' { if ($pos -gt 0) { [void]$buf.Remove($pos - 1, 1); $pos-- } }
            'Delete' { if ($pos -lt $buf.Length) { [void]$buf.Remove($pos, 1) } }
            'Left' { if ($pos -gt 0) { $pos-- } }
            'Right' { if ($pos -lt $buf.Length) { $pos++ } }
            'Home' { $pos = 0 }
            'End' { $pos = $buf.Length }
            'Char' { [void]$buf.Insert($pos, $k.Char); $pos += $k.Char.Length }
        }
        & $render
    }
}

Export-ModuleMember -Function Add-TuiScriptedKeys, Set-TuiScriptedProvider, Set-TuiScriptedInput, Clear-TuiScriptedInput, Test-TuiScripted, Get-TuiScriptedRemaining, Test-TuiKeyAvailable, Read-TuiKey, Read-TuiLine
