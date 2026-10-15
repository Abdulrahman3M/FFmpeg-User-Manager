# Menu.psm1 - the reusable menu component (main menu, submenus and every multiple-choice question).
Set-StrictMode -Version 2.0

# ---- numbering ---------------------------------------------------------------------------------------------
# Every option in every list is numbered 01, 02, 03 ... (at least two digits, growing to 100, 101 ... when a list
# has more than 99 entries). There are no letter keys. Order on screen: Number, Icon, Option name.

function Get-NumberWidth {
    # Display width of the number column: at least two digits, more when a list has 100 or more options.
    param([int]$Count)
    return [math]::Max(2, ([string][math]::Max($Count, 1)).Length)
}

function Format-MenuNumber {
    # 1 -> '01', 9 -> '09', 10 -> '10', 100 -> '100'. -Width pads with trailing spaces for column alignment.
    param([int]$Number, [int]$Width = 0)
    $t = ([string]$Number).PadLeft(2, '0')
    if ($Width -gt $t.Length) { $t = $t.PadRight($Width) }
    return $t
}

function Resolve-NumberInput {
    <#
      Quick-select by typing digits. Returns @{ State = 'Select'|'Wait'|'Invalid'; Index }.
      "05" selects option 5 at once. A single digit that cannot start any longer number (for example "5" in a list of
      12) also selects at once. A prefix of a longer number (for example "1" in a list of 12, or "10" in a list of 120)
      waits for more digits; Enter then accepts what was typed.
    #>
    param([string]$Buffer, [int]$Count)
    if ([string]::IsNullOrEmpty($Buffer) -or $Buffer -notmatch '^\d+$') { return @{ State = 'Invalid'; Index = -1 } }
    $cands = @()
    for ($n = 1; $n -le $Count; $n++) { if ((Format-MenuNumber $n).StartsWith($Buffer)) { $cands += $n } }
    if ($cands.Count -eq 0) {
        if ($Buffer.Length -le 9) { $v = [int]$Buffer; if ($v -ge 1 -and $v -le $Count) { return @{ State = 'Select'; Index = $v - 1 } } }
        return @{ State = 'Invalid'; Index = -1 }
    }
    $exact = @($cands | Where-Object { (Format-MenuNumber $_) -eq $Buffer })
    if ($exact.Count -eq 1 -and $cands.Count -eq 1) { return @{ State = 'Select'; Index = $exact[0] - 1 } }
    return @{ State = 'Wait'; Index = -1 }
}

function Show-Menu {
    <#
      Items: hashtables/objects with Label, and optionally Desc, Icon, Value, Enabled, Reason.
      Every item is numbered automatically (01, 02, ...); callers never assign keys. Row layout is
      Number, Icon, Option name, with the description on the line below.
      Returns @{ Action = 'Select'|'Back'|'Quit'; Item; Index }. Esc = back, Ctrl+C = quit.
    #>
    param(
        [string]$Title = '',
        [string]$Subtitle = '',
        [object[]]$Items,
        [switch]$ShowHeader,
        [switch]$AllowBack,
        [switch]$AllowQuit,
        [string]$BackLabel = 'Back',
        [int]$InitialIndex = 0,
        [scriptblock]$InfoRenderer,
        [int]$InfoLines = 0,
        [string]$FooterNote = '',
        [object[]]$ExtraHints = @()
    )
    $list = @()
    $hasDesc = $false
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $it = $Items[$i]
        $h = @{ Label = ''; Desc = ''; Icon = ''; Value = $null; Enabled = $true; Reason = '' }
        foreach ($name in 'Label', 'Desc', 'Icon', 'Value', 'Enabled', 'Reason') {
            if ($it -is [System.Collections.IDictionary]) { if ($it.Contains($name)) { $h[$name] = $it[$name] } }
            elseif ($it.PSObject.Properties[$name]) { $h[$name] = $it.$name }
        }
        if (-not $h.Icon) { $h.Icon = 'Option' }
        if ($h.Desc -or $h.Reason) { $hasDesc = $true }
        $list += , $h
    }
    if ($list.Count -eq 0) { return [pscustomobject]@{ Action = 'Back'; Item = $null; Index = -1 } }
    $numWidth = Get-NumberWidth $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) { $list[$i].Key = Format-MenuNumber ($i + 1) }
    $selected = [math]::Min([math]::Max($InitialIndex, 0), $list.Count - 1)
    if (-not $list[$selected].Enabled) { for ($j = 0; $j -lt $list.Count; $j++) { if ($list[$j].Enabled) { $selected = $j; break } } }
    $top = 0
    $typed = ''
    Hide-Cursor
    try {
        while ($true) {
            $size = Get-UiSize
            $compact = Test-CompactLayout
            $w = Get-UiWidth
            # --- layout budget
            $overhead = 3 + $(if ($ShowHeader) { 5 } else { 0 }) + $(if ($Title) { 2 } else { 0 }) + $(if ($Subtitle) { 2 } else { 0 }) + 4
            $avail = $size.Height - $overhead - $InfoLines
            # a description under every option whenever at least four options fit with theirs
            $inline = $hasDesc -and (-not $compact) -and ($avail -ge 8)
            $rowsPer = $(if ($inline) { 2 } else { 1 })
            $detail = (-not $inline) -and $hasDesc
            $visible = $list.Count
            if ($detail) { $avail -= 2 }
            if ($list.Count * $rowsPer -gt $avail) { $visible = [math]::Max(3, [math]::Floor($avail / $rowsPer)) }
            if ($selected -lt $top) { $top = $selected }
            if ($selected -ge $top + $visible) { $top = $selected - $visible + 1 }
            if ($top -lt 0) { $top = 0 }
            $iconCol = 1
            foreach ($x in $list) { $iw = Get-TextWidth (Get-Icon $x.Icon); if ($iw -gt $iconCol) { $iconCol = $iw } }

            Start-Frame
            if ($ShowHeader) { Write-Header; Write-UiBlank }
            if ($InfoRenderer) { & $InfoRenderer }
            if ($Title) { Write-UiSegments @(, @($Title, 'Title')); Write-UiBlank }
            if ($Subtitle) { foreach ($sl in (Split-TextLines $Subtitle ($w - 2))) { Write-UiSegments @(, @(('  ' + $sl), 'DimText')) }; Write-UiBlank }
            $b = Get-BoxChars
            if ($top -gt 0) { Write-UiSegments @(, @(('  ' + $b.Up + ' more'), 'DimText')) }
            $end = [math]::Min($list.Count, $top + $visible)
            for ($i = $top; $i -lt $end; $i++) {
                $it = $list[$i]
                $isSel = ($i -eq $selected)
                $marker = if ($isSel) { (Get-Icon 'Arrow') } else { ' ' }
                $ic = Get-Icon $it.Icon
                if (-not $ic) { $ic = [string]$it.Icon }
                $iconText = $ic + (' ' * [math]::Max(0, $iconCol - (Get-TextWidth $ic))) + ' '
                $labelMax = $w - 6 - $numWidth - (Get-TextWidth $iconText)
                $label = Limit-Text ([string]$it.Label) $labelMax
                $role = 'NormalText'
                if ($isSel) { $role = 'Selected' }
                if (-not $it.Enabled) { $role = 'DimText' }
                Write-UiSegments @(@((' ' + $marker + ' '), 'PrimaryAccent'), @(($it.Key.PadRight($numWidth) + ' '), $(if ($isSel) { 'PrimaryAccent' } else { 'SecondaryAccent' })), @($iconText, $role), @($label, $role))
                if ($inline) {
                    $d = [string]$it.Desc
                    if (-not $it.Enabled -and $it.Reason) { $d = [string]$it.Reason }
                    $indent = 4 + $numWidth
                    if ($d) { Write-UiSegments @(, @(((' ' * $indent) + (Limit-Text $d ($w - $indent - 2))), 'DimText')) } else { Write-UiBlank }
                }
            }
            if ($end -lt $list.Count) { Write-UiSegments @(, @(('  ' + $b.Down + ' more'), 'DimText')) }
            if ($detail) {
                $cur = $list[$selected]
                $d = [string]$cur.Desc
                if (-not $cur.Enabled -and $cur.Reason) { $d = [string]$cur.Reason }
                Write-UiBlank
                Write-UiSegments @(, @(('  ' + (Limit-Text $d ($w - 4))), 'DimText'))
            }
            if ($FooterNote) { Write-UiBlank; Write-UiSegments @(, @(('  ' + (Limit-Text $FooterNote ($w - 4))), 'Warning')) }
            $hints = @(@("$([char]0x2191)/$([char]0x2193)", 'Navigate'), @('Enter', 'Select'))
            if (-not (Test-UnicodeArrows)) { $hints = @(@('Up/Down', 'Navigate'), @('Enter', 'Select')) }
            $first = Format-MenuNumber 1; $last = Format-MenuNumber $list.Count
            $hints += , @(($first + '-' + $last), 'Type a number')
            if ($typed) { $hints += , @('Typed', $typed) }
            if ($AllowBack) { $hints += , @('Esc', $BackLabel) }
            if ($AllowQuit) { $hints += , @('Ctrl+C', 'Quit') }
            $hints += $ExtraHints
            Write-KeyHints $hints
            Stop-Frame

            $k = Read-TuiKey
            if (@('Char', 'Backspace', 'Enter') -notcontains $k.Name) { $typed = '' }
            switch ($k.Name) {
                'Up' { $n = $selected; do { $n = ($n - 1 + $list.Count) % $list.Count } while (-not $list[$n].Enabled -and $n -ne $selected); $selected = $n }
                'Down' { $n = $selected; do { $n = ($n + 1) % $list.Count } while (-not $list[$n].Enabled -and $n -ne $selected); $selected = $n }
                'Home' { $selected = 0 }
                'End' { $selected = $list.Count - 1 }
                'PageUp' { $selected = [math]::Max(0, $selected - $visible) }
                'PageDown' { $selected = [math]::Min($list.Count - 1, $selected + $visible) }
                'Enter' {
                    if ($typed) {
                        $hitIdx = -1
                        if ($typed -match '^\d+$' -and [int]$typed -ge 1 -and [int]$typed -le $list.Count) { $hitIdx = [int]$typed - 1 }
                        $typed = ''
                        if ($hitIdx -ge 0 -and $list[$hitIdx].Enabled) { return [pscustomobject]@{ Action = 'Select'; Item = $list[$hitIdx]; Index = $hitIdx } }
                    } elseif ($list[$selected].Enabled) { return [pscustomobject]@{ Action = 'Select'; Item = $list[$selected]; Index = $selected } }
                }
                'Esc' { if ($AllowBack) { return [pscustomobject]@{ Action = 'Back'; Item = $null; Index = -1 } } }
                'CtrlC' { return [pscustomobject]@{ Action = 'Quit'; Item = $null; Index = -1 } }
                'Backspace' { if ($typed.Length -gt 0) { $typed = $typed.Substring(0, $typed.Length - 1) } }
                'Char' {
                    if ($k.Char -match '^\d$') {
                        $typed += $k.Char
                        $res = Resolve-NumberInput $typed $list.Count
                        if ($res.State -eq 'Select') {
                            $typed = ''
                            if ($list[$res.Index].Enabled) { return [pscustomobject]@{ Action = 'Select'; Item = $list[$res.Index]; Index = $res.Index } }
                        } elseif ($res.State -eq 'Invalid') { $typed = '' }
                    } else { $typed = '' }
                }
            }
        }
    } finally { Show-Cursor }
}

function Test-UnicodeArrows { return ((Get-BoxChars).H -ne '-') }

Export-ModuleMember -Function Get-NumberWidth, Format-MenuNumber, Resolve-NumberInput, Show-Menu
