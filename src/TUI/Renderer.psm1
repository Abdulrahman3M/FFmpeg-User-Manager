# Renderer.psm1 - all terminal output goes through here (ANSI or legacy colors, or a capture buffer for tests).
Set-StrictMode -Version 2.0

$script:Sink = 'Console'           # Console | Buffer
$script:Buffer = New-Object System.Text.StringBuilder
$script:Ansi = $false
$script:AltScreen = $false
$script:FixedWidth = 0
$script:FixedHeight = 0
$script:ESC = [string][char]27
$script:HeaderInfo = ''

function Initialize-Renderer {
    param([bool]$Ansi, [bool]$Unicode, [ValidateSet('Console', 'Buffer')][string]$Sink = 'Console', [int]$Width = 0, [int]$Height = 0)
    $script:Ansi = $Ansi
    $script:Sink = $Sink
    $script:FixedWidth = $Width
    $script:FixedHeight = $Height
    Initialize-Theme -Ansi $Ansi -Unicode $Unicode
}

function Test-AnsiMode { return $script:Ansi }
function Set-HeaderInfo { param([string]$Text) $script:HeaderInfo = $Text }
function Get-CapturedOutput { return $script:Buffer.ToString() }
function Clear-CapturedOutput { [void]$script:Buffer.Clear() }

function Get-UiSize {
    if ($script:FixedWidth -gt 0) { return [pscustomobject]@{ Width = $script:FixedWidth; Height = $(if ($script:FixedHeight -gt 0) { $script:FixedHeight } else { 30 }) } }
    $ts = Get-TerminalSize
    return [pscustomobject]@{ Width = $ts.Width; Height = $ts.Height }
}

function Get-UiWidth {
    $cfg = Get-AppConfig
    $max = 100; try { $max = [int]$cfg.ui.maxWidth } catch { }
    $w = (Get-UiSize).Width - 1
    if ($w -gt $max) { $w = $max }
    if ($w -lt 30) { $w = 30 }
    return $w
}

function Test-CompactLayout {
    $cfg = Get-AppConfig
    $c = 72; try { $c = [int]$cfg.ui.compactBelow } catch { }
    return ((Get-UiWidth) -lt $c)
}

function Get-TextWidth {
    # Approximate display width: emoji/CJK/wide characters count as two columns.
    param([string]$Text)
    if (-not $Text) { return 0 }
    $w = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = [int]$Text[$i]
        if ($c -ge 0xD800 -and $c -le 0xDBFF) { $w += 2; $i++; continue }
        if ($c -eq 0xFE0F -or $c -eq 0x200D) { continue }
        if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE6F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or $c -eq 0x2702 -or $c -eq 0x26A1 -or $c -eq 0x2B06 -or $c -eq 0x274C) { $w += 2; continue }
        $w += 1
    }
    return $w
}

function Limit-Text {
    param([string]$Text, [int]$Max)
    if (-not $Text) { return '' }
    if ($Max -lt 4) { $Max = 4 }
    if ((Get-TextWidth $Text) -le $Max) { return $Text }
    $ell = (Get-BoxChars).Ellipsis
    $budget = $Max - (Get-TextWidth $ell)
    $sb = New-Object System.Text.StringBuilder
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $cw = Get-TextWidth ([string]$ch)
        if ($w + $cw -gt $budget) { break }
        [void]$sb.Append($ch); $w += $cw
    }
    return $sb.ToString() + $ell
}

function Limit-PathText {
    # Keeps the tail of a long path visible.
    param([string]$Text, [int]$Max)
    if ((Get-TextWidth $Text) -le $Max) { return $Text }
    $ell = (Get-BoxChars).Ellipsis
    return $ell + $Text.Substring($Text.Length - ($Max - (Get-TextWidth $ell)))
}

function Split-TextLines {
    # Word-wraps to a width; returns string[].
    param([string]$Text, [int]$Width)
    $out = New-Object System.Collections.Generic.List[string]
    if ($Width -lt 10) { $Width = 10 }
    foreach ($para in ([string]$Text -split "`r?`n")) {
        $line = ''
        foreach ($word in ($para -split ' ')) {
            if ($line.Length -eq 0) { $line = $word }
            elseif ((Get-TextWidth $line) + 1 + (Get-TextWidth $word) -le $Width) { $line += ' ' + $word }
            else { $out.Add($line); $line = $word }
        }
        $out.Add($line)
    }
    return $out.ToArray()
}

function Write-Raw {
    param([string]$Text)
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append($Text); return }
    [Console]::Out.Write($Text)
}

function Write-Ui {
    param([AllowEmptyString()][string]$Text, [string]$Role = 'NormalText', [switch]$NoNewline, [switch]$Bold)
    if ($script:Sink -eq 'Buffer') {
        [void]$script:Buffer.Append($Text)
        if (-not $NoNewline) { [void]$script:Buffer.Append("`n") }
        return
    }
    if ($script:Ansi) {
        $code = Get-ThemeAnsi $Role
        $s = $script:ESC + '[' + $code + 'm' + $Text + $script:ESC + '[0m'
        if (-not $NoNewline) { $s += $script:ESC + '[K' + "`n" }
        [Console]::Out.Write($s)
    } else {
        $color = Get-ThemeConsoleColor $Role
        if ($NoNewline) { Write-Host -NoNewline $Text -ForegroundColor $color } else { Write-Host $Text -ForegroundColor $color }
    }
}

function Write-PlainError {
    # For messages printed after the TUI has been torn down (fatal errors, non-interactive notices).
    param([string]$Text)
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append($Text + "`n"); return }
    Write-Host $Text -ForegroundColor (Get-ThemeConsoleColor 'Error')
}

function Write-UiSegments {
    # Segments: array of @(text, role) pairs written on one line.
    param([object[]]$Segments, [switch]$NoNewline)
    foreach ($seg in $Segments) { Write-Ui -Text ([string]$seg[0]) -Role ([string]$seg[1]) -NoNewline }
    if (-not $NoNewline) {
        if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append("`n") }
        elseif ($script:Ansi) { [Console]::Out.Write($script:ESC + '[K' + "`n") }
        else { Write-Host '' }
    }
}

function Write-UiBlank { Write-Ui -Text '' -Role NormalText }

function Start-Frame {
    # ANSI: home the cursor and overwrite (no flicker). Legacy: clear the screen.
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append("`n=====FRAME=====`n"); return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[H') }
    else { try { Clear-Host } catch { } }
}

function Stop-Frame {
    if ($script:Sink -eq 'Buffer') { return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[J') }
}

function Clear-Ui {
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append("`n=====CLEAR=====`n"); return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[2J' + $script:ESC + '[H') } else { try { Clear-Host } catch { } }
}

function Show-Cursor {
    if ($script:Sink -eq 'Buffer') { return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[?25h') }
    try { [Console]::CursorVisible = $true } catch { }
}

function Set-CursorColumn {
    # Moves the cursor to a 0-based column of the current line. ANSI: absolute-column escape (no terminal query);
    # legacy console: [Console]::CursorLeft.
    param([int]$Column)
    if ($script:Sink -eq 'Buffer') { return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[' + ($Column + 1) + 'G'); return }
    try { [Console]::CursorLeft = [math]::Min([math]::Max($Column, 0), [Console]::BufferWidth - 1) } catch { [Console]::Out.Write("`r") }
}

function Clear-LineRemainder {
    # Erases what is left of the current line after $Used columns of text (ANSI: erase-to-end; legacy: pad with spaces).
    param([int]$Used)
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append('  '); return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[K'); return }
    $pad = (Get-UiWidth) - $Used
    if ($pad -gt 0) { [Console]::Out.Write(' ' * $pad) }
}

function Hide-Cursor {
    if ($script:Sink -eq 'Buffer') { return }
    if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[?25l') }
    else { try { [Console]::CursorVisible = $false } catch { } }
}

function Enter-AltScreen {
    if ($script:Sink -eq 'Buffer' -or -not $script:Ansi) { return }
    [Console]::Out.Write($script:ESC + '[?1049h' + $script:ESC + '[2J' + $script:ESC + '[H')
    $script:AltScreen = $true
}

function Restore-TerminalState {
    # Safe to call repeatedly, including from finally blocks after an exception.
    if ($script:Sink -eq 'Buffer') { return }
    try {
        if ($script:Ansi) { [Console]::Out.Write($script:ESC + '[0m') }
        if ($script:AltScreen) { [Console]::Out.Write($script:ESC + '[?1049l'); $script:AltScreen = $false }
        Show-Cursor
        [Console]::ResetColor()
    } catch { }
    try { [Console]::TreatControlCAsInput = $false } catch { }
}

# ---- reusable visual pieces -------------------------------------------------

function Write-Rule {
    param([string]$Title = '', [string]$Role = 'Border')
    $b = Get-BoxChars
    $w = Get-UiWidth
    if ($Title) {
        $left = $b.H * 2
        $t = ' ' + $Title + ' '
        $rest = $w - 2 - (Get-TextWidth $t)
        if ($rest -lt 2) { $rest = 2 }
        Write-UiSegments @(, @($left, $Role)) -NoNewline
        Write-UiSegments @(, @($t, 'Title')) -NoNewline
        Write-UiSegments @(, @(($b.H * $rest), $Role))
    } else {
        Write-Ui -Text ($b.H * $w) -Role $Role
    }
}

function Write-Header {
    # Compact bordered header (plain ASCII text inside so the right border always aligns).
    param([string]$Title = 'FFmpeg TUI', [string]$Subtitle = 'Media tools powered by FFmpeg')
    $b = Get-BoxChars
    $w = Get-UiWidth
    $inner = $w - 2
    $mark = if ((Get-BoxChars).H -eq '-') { '>>' } else { [string][char]0x25C6 }
    $l1 = '  ' + $mark + ' ' + $Title
    $l2 = '  ' + $Subtitle + $(if ($script:HeaderInfo) { ' ' + $script:HeaderInfo } else { '' })
    $l1 = Limit-Text $l1 $inner; $l2 = Limit-Text $l2 $inner
    Write-UiSegments @(, @(($b.TL + ($b.H * $inner) + $b.TR), 'Border'))
    Write-UiSegments @(@($b.V, 'Border'), @($l1.PadRight($inner), 'Title'), @($b.V, 'Border'))
    Write-UiSegments @(@($b.V, 'Border'), @($l2.PadRight($inner), 'DimText'), @($b.V, 'Border'))
    Write-UiSegments @(, @(($b.BL + ($b.H * $inner) + $b.BR), 'Border'))
}

function Write-KeyHints {
    # $Hints: array of @(key, label). Only keys valid on the current screen should be passed.
    param([object[]]$Hints)
    if ($Hints.Count -gt 0 -and $Hints[0] -is [string]) { $Hints = @(, $Hints) }
    $w = Get-UiWidth
    Write-UiBlank
    $segs = New-Object System.Collections.Generic.List[object]
    $used = 0
    foreach ($h in $Hints) {
        $len = (Get-TextWidth ([string]$h[0])) + 1 + (Get-TextWidth ([string]$h[1])) + 3
        if ($used + $len -gt $w -and $segs.Count -gt 0) {
            Write-UiSegments $segs.ToArray(); $segs.Clear(); $used = 0
        }
        $segs.Add(@([string]$h[0], 'PrimaryAccent')); $segs.Add(@((' ' + $h[1] + '   '), 'DimText')); $used += $len
    }
    if ($segs.Count -gt 0) { Write-UiSegments $segs.ToArray() }
}

function Write-KeyValueTable {
    # Label/value rows: $Rows = array of @(label, value[, role]). Long values wrap onto indented lines.
    param([object[]]$Rows, [int]$LabelWidth = 10, [int]$Indent = 0)
    if ($Rows.Count -gt 0 -and $Rows[0] -is [string]) { $Rows = @(, $Rows) }
    $w = Get-UiWidth
    $avail = $w - $Indent - $LabelWidth - 1
    if ($avail -lt 10) { $avail = 10 }
    foreach ($r in $Rows) {
        $role = 'NormalText'; if ($r.Count -gt 2) { $role = [string]$r[2] }
        $text = [string]$r[1]
        $chunks = New-Object System.Collections.Generic.List[string]
        while ((Get-TextWidth $text) -gt $avail) {
            $cut = $avail
            $sp = $text.LastIndexOf(' ', [math]::Min($text.Length - 1, $avail))
            if ($sp -gt ($avail / 2)) { $cut = $sp + 1 }
            $chunks.Add($text.Substring(0, $cut)); $text = $text.Substring($cut)
            if ($chunks.Count -ge 6) { break }
        }
        $chunks.Add($text)
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            $label = $(if ($i -eq 0) { ([string]$r[0]).PadRight($LabelWidth) } else { ''.PadRight($LabelWidth) })
            Write-UiSegments @(@(((' ' * $Indent) + $label + ' '), 'DimText'), @($chunks[$i], $role))
        }
    }
}

function Write-Panel {
    # Titled section with key/value rows, e.g. the "Source" summary.
    param([string]$Title, [object[]]$Rows, [int]$LabelWidth = 10)
    Write-Rule -Title $Title
    Write-KeyValueTable -Rows $Rows -LabelWidth $LabelWidth
    Write-Rule
}

function Format-ProgressBar {
    param([int]$Percent, [int]$Width)
    $b = Get-BoxChars
    if ($Width -lt 10) { $Width = 10 }
    $filled = [int][math]::Floor($Width * $Percent / 100)
    $ch = $b.Bar; if ($script:Sink -ne 'Buffer' -and -not (Test-AnsiMode) -and $b.H -ne '-') { $ch = $b.Bar }
    return @(($ch * $filled), (($b.H) * ($Width - $filled)))
}

Export-ModuleMember -Function Clear-LineRemainder, Set-CursorColumn, Set-HeaderInfo, Write-PlainError, Initialize-Renderer, Test-AnsiMode, Get-CapturedOutput, Clear-CapturedOutput, Get-UiSize, Get-UiWidth, Test-CompactLayout, Get-TextWidth, Limit-Text, Limit-PathText, Split-TextLines, Write-Raw, Write-Ui, Write-UiSegments, Write-UiBlank, Start-Frame, Stop-Frame, Clear-Ui, Show-Cursor, Hide-Cursor, Enter-AltScreen, Restore-TerminalState, Write-Rule, Write-Header, Write-KeyHints, Write-KeyValueTable, Write-Panel, Format-ProgressBar
