# Menu.psm1 - the reusable menu component (main menu, submenus and every multiple-choice question).
Set-StrictMode -Version 2.0

function Get-MenuHotkeys {
    # Auto-assigned hotkeys: 1-9 then letters (B and Q are reserved for Back/Quit).
    param([int]$Count, [string[]]$Exclude = @())
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($d in 1..9) { $keys.Add([string]$d) }
    foreach ($c in 'A', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') { if ($Exclude -notcontains $c) { $keys.Add($c) } }
    $out = @()
    for ($i = 0; $i -lt $Count; $i++) { if ($i -lt $keys.Count) { $out += $keys[$i] } else { $out += '' } }
    return $out
}

function Show-Menu {
    <#
      Items: hashtables/objects with Label, and optionally Key, Desc, Icon, Value, Enabled, Reason.
      Returns @{ Action = 'Select'|'Back'|'Quit'; Item; Index }.
      Item hotkeys take precedence over the Back (B) / Quit (Q) keys, so screens like the main menu
      (where B = Subtitle Tools) work as displayed.
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
        [switch]$AutoKeys,
        [object[]]$ExtraHints = @()
    )
    $list = @()
    $hotkeys = @()
    if ($AutoKeys) { $hotkeys = Get-MenuHotkeys $Items.Count }
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $it = $Items[$i]
        $h = @{ Label = ''; Key = ''; Desc = ''; Icon = ''; Value = $null; Enabled = $true; Reason = '' }
        foreach ($name in 'Label', 'Key', 'Desc', 'Icon', 'Value', 'Enabled', 'Reason') {
            if ($it -is [System.Collections.IDictionary]) { if ($it.Contains($name)) { $h[$name] = $it[$name] } }
            elseif ($it.PSObject.Properties[$name]) { $h[$name] = $it.$name }
        }
        if ($AutoKeys -and -not $h.Key) { $h.Key = $hotkeys[$i] }
        $h.Key = ([string]$h.Key).ToUpperInvariant()
        $list += , $h
    }
    if ($list.Count -eq 0) { return [pscustomobject]@{ Action = 'Back'; Item = $null; Index = -1 } }
    $selected = [math]::Min([math]::Max($InitialIndex, 0), $list.Count - 1)
    if (-not $list[$selected].Enabled) { for ($j = 0; $j -lt $list.Count; $j++) { if ($list[$j].Enabled) { $selected = $j; break } } }
    $top = 0
    Hide-Cursor
    try {
        while ($true) {
            $size = Get-UiSize
            $compact = Test-CompactLayout
            $w = Get-UiWidth
            # --- layout budget
            $overhead = 3 + $(if ($ShowHeader) { 5 } else { 0 }) + $(if ($Title) { 2 } else { 0 }) + $(if ($Subtitle) { 2 } else { 0 }) + 4
            $avail = $size.Height - $overhead - $InfoLines
            $inline = (-not $compact) -and (($list.Count * 2) -le $avail)
            $rowsPer = $(if ($inline) { 2 } else { 1 })
            $detail = (-not $inline)
            $visible = $list.Count
            if ($detail) { $avail -= 2 }
            if ($list.Count * $rowsPer -gt $avail) { $visible = [math]::Max(3, [math]::Floor($avail / $rowsPer)) }
            if ($selected -lt $top) { $top = $selected }
            if ($selected -ge $top + $visible) { $top = $selected - $visible + 1 }
            if ($top -lt 0) { $top = 0 }

            Start-Frame
            if ($ShowHeader) { Write-Header; Write-UiBlank }
            if ($InfoRenderer) { & $InfoRenderer }
            if ($Title) { Write-UiSegments @(, @($Title, 'Title')); Write-UiBlank }
            if ($Subtitle) { Write-UiSegments @(, @($Subtitle, 'DimText')); Write-UiBlank }
            $b = Get-BoxChars
            if ($top -gt 0) { Write-UiSegments @(, @(('  ' + $b.Up + ' more'), 'DimText')) }
            $end = [math]::Min($list.Count, $top + $visible)
            for ($i = $top; $i -lt $end; $i++) {
                $it = $list[$i]
                $isSel = ($i -eq $selected)
                $marker = if ($isSel) { (Get-Icon 'Arrow') } else { ' ' }
                $keyText = if ($it.Key) { ($it.Key + '.') } else { '' }
                $iconText = ''
                if ($it.Icon) { $ic = Get-Icon $it.Icon; if (-not $ic) { $ic = [string]$it.Icon }; $iconText = $ic + ' ' }
                $labelMax = $w - 8 - (Get-TextWidth $iconText) - $keyText.Length
                $label = Limit-Text ([string]$it.Label) $labelMax
                $role = 'NormalText'
                if ($isSel) { $role = 'Selected' }
                if (-not $it.Enabled) { $role = 'DimText' }
                Write-UiSegments @(@((' ' + $marker + ' '), 'PrimaryAccent'), @($iconText, $role), @($keyText.PadRight(3), $(if ($isSel) { 'PrimaryAccent' } else { 'SecondaryAccent' })), @($label, $role))
                if ($inline) {
                    $d = [string]$it.Desc
                    if (-not $it.Enabled -and $it.Reason) { $d = [string]$it.Reason }
                    if ($d) { Write-UiSegments @(, @(('        ' + (Limit-Text $d ($w - 10))), 'DimText')) } else { Write-UiBlank }
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
            $keyed = @($list | Where-Object { $_.Key })
            if ($keyed.Count -gt 0) { $hints += , @('Key', 'Quick select') }
            if ($AllowBack) { $hints += , @('Esc', $BackLabel) }
            if ($AllowQuit) { $hints += , @('Q', 'Quit') }
            $hints += $ExtraHints
            Write-KeyHints $hints
            Stop-Frame

            $k = Read-TuiKey
            switch ($k.Name) {
                'Up' { $n = $selected; do { $n = ($n - 1 + $list.Count) % $list.Count } while (-not $list[$n].Enabled -and $n -ne $selected); $selected = $n }
                'Down' { $n = $selected; do { $n = ($n + 1) % $list.Count } while (-not $list[$n].Enabled -and $n -ne $selected); $selected = $n }
                'Home' { $selected = 0 }
                'End' { $selected = $list.Count - 1 }
                'PageUp' { $selected = [math]::Max(0, $selected - $visible) }
                'PageDown' { $selected = [math]::Min($list.Count - 1, $selected + $visible) }
                'Enter' { if ($list[$selected].Enabled) { return [pscustomobject]@{ Action = 'Select'; Item = $list[$selected]; Index = $selected } } }
                'Esc' { if ($AllowBack) { return [pscustomobject]@{ Action = 'Back'; Item = $null; Index = -1 } } }
                'CtrlC' { return [pscustomobject]@{ Action = 'Quit'; Item = $null; Index = -1 } }
                'Char' {
                    $c = $k.Char.ToUpperInvariant()
                    $hit = -1
                    for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].Key -eq $c) { $hit = $i; break } }
                    if ($hit -ge 0) {
                        if ($list[$hit].Enabled) { return [pscustomobject]@{ Action = 'Select'; Item = $list[$hit]; Index = $hit } }
                    } elseif ($c -eq 'B' -and $AllowBack) { return [pscustomobject]@{ Action = 'Back'; Item = $null; Index = -1 } }
                    elseif ($c -eq 'Q' -and $AllowQuit) { return [pscustomobject]@{ Action = 'Quit'; Item = $null; Index = -1 } }
                }
            }
        }
    } finally { Show-Cursor }
}

function Test-UnicodeArrows { return ((Get-BoxChars).H -ne '-') }

Export-ModuleMember -Function Get-MenuHotkeys, Show-Menu
