# Dialog.psm1 - confirmations, notices and error screens.
Set-StrictMode -Version 2.0

function Show-Notice {
    # Full-screen message with an optional set of key actions. Returns the pressed action key (upper case).
    param(
        [string]$Title,
        [string[]]$Lines = @(),
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Kind = 'Info',
        [object[]]$Actions = @(@('Enter', 'Continue')),   # @(key, label[, role])
        [switch]$ShowHeader,
        [string[]]$DimLines = @(),
        [string]$Icon = ''
    )
    if ($Actions.Count -gt 0 -and $Actions[0] -is [string]) { $Actions = @(, $Actions) }
    $iconName = @{ Info = 'Info'; Success = 'Ok'; Warning = 'Warn'; Error = 'Fail' }[$Kind]
    if ($Icon) { $iconName = $Icon }
    $role = @{ Info = 'PrimaryAccent'; Success = 'Success'; Warning = 'Warning'; Error = 'Error' }[$Kind]
    $w = Get-UiWidth
    Hide-Cursor
    try {
        Start-Frame
        if ($ShowHeader) { Write-Header; Write-UiBlank }
        Write-UiSegments @(@(((Get-Icon $iconName) + ' '), $role), @($Title, $role))
        Write-UiBlank
        foreach ($l in $Lines) { foreach ($wl in (Split-TextLines $l ($w - 2))) { Write-Ui -Text ('  ' + $wl) -Role NormalText } }
        if ($DimLines.Count -gt 0) { Write-UiBlank; foreach ($l in $DimLines) { foreach ($wl in (Split-TextLines $l ($w - 2))) { Write-Ui -Text ('  ' + $wl) -Role DimText } } }
        Write-UiBlank
        foreach ($a in $Actions) {
            $r = 'PrimaryAccent'; if ($a.Count -gt 2) { $r = [string]$a[2] }
            Write-UiSegments @(@(('  [' + $a[0] + '] '), $r), @([string]$a[1], 'NormalText'))
        }
        Stop-Frame
        while ($true) {
            $k = Read-TuiKey
            $name = $k.Name
            if ($name -eq 'Char') { $name = $k.Char.ToUpperInvariant() }
            elseif ($name -eq 'Esc') { $name = 'ESC' } elseif ($name -eq 'Enter') { $name = 'ENTER' } elseif ($name -eq 'CtrlC') { $name = 'CTRLC' }
            foreach ($a in $Actions) { if (([string]$a[0]).ToUpperInvariant() -eq $name) { return $name } }
            if ($name -eq 'CTRLC') { return 'CTRLC' }
        }
    } finally { Show-Cursor }
}

function Show-Confirm {
    # Yes/No question. Enter accepts the default. Returns $true / $false ($false on Esc).
    param([string]$Title, [string[]]$Lines = @(), [bool]$Default = $false, [string]$YesLabel = 'Yes', [string]$NoLabel = 'No', [ValidateSet('Info', 'Warning', 'Error')][string]$Kind = 'Warning')
    $defKey = if ($Default) { 'Y' } else { 'N' }
    $actions = @(@('Y', $YesLabel), @('N', $NoLabel))
    $iconName = @{ Info = 'Info'; Warning = 'Warn'; Error = 'Fail' }[$Kind]
    $role = @{ Info = 'PrimaryAccent'; Warning = 'Warning'; Error = 'Error' }[$Kind]
    $w = Get-UiWidth
    Hide-Cursor
    try {
        Start-Frame
        Write-UiSegments @(@(((Get-Icon $iconName) + ' '), $role), @($Title, $role))
        Write-UiBlank
        foreach ($l in $Lines) { foreach ($wl in (Split-TextLines $l ($w - 2))) { Write-Ui -Text ('  ' + $wl) -Role NormalText } }
        Write-UiBlank
        Write-UiSegments @(@('  [Y] ', 'PrimaryAccent'), @($YesLabel, 'NormalText'))
        Write-UiSegments @(@('  [N] ', 'PrimaryAccent'), @($NoLabel, 'NormalText'))
        Write-KeyHints @(@('Enter', ("Default: " + $(if ($Default) { $YesLabel } else { $NoLabel }))), @('Esc', 'No'))
        Stop-Frame
        while ($true) {
            $k = Read-TuiKey
            if ($k.Name -eq 'Enter') { return $Default }
            if ($k.Name -eq 'Esc' -or $k.Name -eq 'CtrlC') { return $false }
            if ($k.Name -eq 'Char') {
                $c = $k.Char.ToUpperInvariant()
                if ($c -eq 'Y') { return $true }
                if ($c -eq 'N') { return $false }
            }
        }
    } finally { Show-Cursor }
}

function Show-ErrorScreen {
    param([string]$Title, [string]$Reason, [string]$Details = '', [object[]]$Actions = @(@('B', 'Back')))
    $lines = @('Reason:', $Reason)
    return (Show-Notice -Title $Title -Lines $lines -Kind Error -Actions $Actions)
}

function Show-TextViewer {
    # Scrollable read-only text (technical details, generated command, filter browser). Esc/B/Enter closes.
    param([string]$Title, [string[]]$Lines)
    $size = Get-UiSize
    $w = Get-UiWidth
    $wrapped = New-Object System.Collections.Generic.List[string]
    foreach ($l in $Lines) { foreach ($x in (Split-TextLines ([string]$l) ($w - 2))) { $wrapped.Add($x) } }
    $page = [math]::Max(5, $size.Height - 7)
    $top = 0
    Hide-Cursor
    try {
        while ($true) {
            Start-Frame
            Write-Rule -Title $Title
            $end = [math]::Min($wrapped.Count, $top + $page)
            for ($i = $top; $i -lt $end; $i++) { Write-Ui -Text ('  ' + $wrapped[$i]) -Role NormalText }
            Write-Rule
            $pos = if ($wrapped.Count -gt $page) { "Lines $($top + 1)-$end of $($wrapped.Count)" } else { '' }
            Write-KeyHints @(@('Up/Down', 'Scroll'), @('PgUp/PgDn', 'Page'), @('Esc', 'Close'))
            if ($pos) { Write-Ui -Text ('  ' + $pos) -Role DimText }
            Stop-Frame
            $k = Read-TuiKey
            switch ($k.Name) {
                'Up' { if ($top -gt 0) { $top-- } }
                'Down' { if ($top + $page -lt $wrapped.Count) { $top++ } }
                'PageUp' { $top = [math]::Max(0, $top - $page) }
                'PageDown' { $top = [math]::Max(0, [math]::Min($wrapped.Count - $page, $top + $page)) }
                'Home' { $top = 0 }
                'End' { $top = [math]::Max(0, $wrapped.Count - $page) }
                'Esc' { return }
                'Enter' { return }
                'CtrlC' { return }
                'Char' { if ($k.Char.ToUpperInvariant() -eq 'B' -or $k.Char.ToUpperInvariant() -eq 'Q') { return } }
            }
        }
    } finally { Show-Cursor }
}

Export-ModuleMember -Function Show-Notice, Show-Confirm, Show-ErrorScreen, Show-TextViewer
