# Dialog.psm1 - confirmations, notices and error screens.
Set-StrictMode -Version 2.0

function Get-ActionIcon {
    # Default icon for a dialog action, chosen from its label.
    param([string]$Label)
    switch -Regex ($Label) {
        '^(Yes|Install now|Update now|Open)' { if ($Label -match '^Open') { return 'Folder' }; if ($Label -match '^(Install|Update)') { return 'Update' }; return 'Yes' }
        '^(No|Cancel)' { return 'No' }
        'Retry|again|Re-' { return 'Retry' }
        'details|command' { return 'Details' }
        '^Exit' { return 'Quit' }
        '^Back|^Go back' { return 'Back' }
        'Main menu' { return 'Home' }
        'Install|Update' { return 'Update' }
        '^Continue|^Start' { return 'Continue' }
        default { return 'Option' }
    }
}

function Show-Notice {
    # Full-screen message with numbered actions (01, 02, ...). Returns the action id (upper case): the id of the action
    # whose number was typed, 'ENTER' / 'ESC' for those keys when they are listed, or 'CTRLC'.
    # Actions: @(id, label[, role]). The ids 'Enter' and 'Esc' are shown as key hints instead of numbered rows.
    param(
        [string]$Title,
        [string[]]$Lines = @(),
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Kind = 'Info',
        [object[]]$Actions = @(@('Enter', 'Continue')),
        [switch]$ShowHeader,
        [string[]]$DimLines = @(),
        [string]$Icon = ''
    )
    if ($Actions.Count -gt 0 -and $Actions[0] -is [string]) { $Actions = @(, $Actions) }
    $iconName = @{ Info = 'Info'; Success = 'Ok'; Warning = 'Warn'; Error = 'Fail' }[$Kind]
    if ($Icon) { $iconName = $Icon }
    $role = @{ Info = 'PrimaryAccent'; Success = 'Success'; Warning = 'Warning'; Error = 'Error' }[$Kind]
    $keyed = @($Actions | Where-Object { @('ENTER', 'ESC') -notcontains ([string]$_[0]).ToUpperInvariant() })
    $special = @($Actions | Where-Object { @('ENTER', 'ESC') -contains ([string]$_[0]).ToUpperInvariant() })
    $numWidth = Get-NumberWidth $keyed.Count
    $w = Get-UiWidth
    $typed = ''
    Hide-Cursor
    try {
        while ($true) {
            Start-Frame
            if ($ShowHeader) { Write-Header; Write-UiBlank }
            Write-UiSegments @(@(((Get-Icon $iconName) + ' '), $role), @($Title, $role))
            Write-UiBlank
            foreach ($l in $Lines) { foreach ($wl in (Split-TextLines $l ($w - 2))) { Write-Ui -Text ('  ' + $wl) -Role NormalText } }
            if ($DimLines.Count -gt 0) { Write-UiBlank; foreach ($l in $DimLines) { foreach ($wl in (Split-TextLines $l ($w - 2))) { Write-Ui -Text ('  ' + $wl) -Role DimText } } }
            Write-UiBlank
            $iconCol = 1
            foreach ($a in $keyed) { $ic = Get-Icon (Get-ActionIcon ([string]$a[1])); if ((Get-TextWidth $ic) -gt $iconCol) { $iconCol = Get-TextWidth $ic } }
            for ($i = 0; $i -lt $keyed.Count; $i++) {
                $a = $keyed[$i]
                $r = 'NormalText'; if ($a.Count -gt 2) { $r = [string]$a[2] }
                $ic = Get-Icon (Get-ActionIcon ([string]$a[1]))
                $ic = $ic + (' ' * [math]::Max(0, $iconCol - (Get-TextWidth $ic)))
                Write-UiSegments @(@(('  ' + (Format-MenuNumber ($i + 1) $numWidth) + ' '), 'PrimaryAccent'), @(($ic + ' '), $r), @([string]$a[1], $r))
            }
            $hints = @()
            foreach ($a in $special) { $hints += , @([string]$a[0], [string]$a[1]) }
            if ($keyed.Count -gt 0) { $hints += , @(((Format-MenuNumber 1) + '-' + (Format-MenuNumber $keyed.Count)), 'Type a number') }
            if ($typed) { $hints += , @('Typed', $typed) }
            if ($hints.Count -gt 0) { Write-KeyHints $hints }
            Stop-Frame
            $k = Read-TuiKey
            $name = ''
            switch ($k.Name) {
                'Enter' { $name = 'ENTER' }
                'Esc' { $name = 'ESC' }
                'CtrlC' { $name = 'CTRLC' }
                'Backspace' { if ($typed.Length -gt 0) { $typed = $typed.Substring(0, $typed.Length - 1) } }
                'Char' {
                    if ($k.Char -match '^\d$') {
                        $typed += $k.Char
                        $res = Resolve-NumberInput $typed $keyed.Count
                        if ($res.State -eq 'Select') { return ([string]$keyed[$res.Index][0]).ToUpperInvariant() }
                        if ($res.State -eq 'Invalid') { $typed = '' }
                    } else { $typed = '' }
                }
            }
            if ($name -eq 'ENTER' -and $typed -and $keyed.Count -gt 0) {
                if ($typed -match '^\d+$' -and [int]$typed -ge 1 -and [int]$typed -le $keyed.Count) { return ([string]$keyed[[int]$typed - 1][0]).ToUpperInvariant() }
                $typed = ''
                continue
            }
            if ($name) {
                if ($name -eq 'CTRLC') { return 'CTRLC' }
                foreach ($a in $special) { if (([string]$a[0]).ToUpperInvariant() -eq $name) { return $name } }
                $typed = ''
            }
        }
    } finally { Show-Cursor }
}

function Show-Confirm {
    # Yes/No question as a numbered list (01 Yes, 02 No). Enter accepts the default. Returns $true / $false ($false on Esc).
    param([string]$Title, [string[]]$Lines = @(), [bool]$Default = $false, [string]$YesLabel = 'Yes', [string]$NoLabel = 'No', [ValidateSet('Info', 'Warning', 'Error')][string]$Kind = 'Warning')
    $iconName = @{ Info = 'Info'; Warning = 'Warn'; Error = 'Fail' }[$Kind]
    $role = @{ Info = 'PrimaryAccent'; Warning = 'Warning'; Error = 'Error' }[$Kind]
    $w = Get-UiWidth
    $ic = Get-Icon 'Yes'; $icn = Get-Icon 'No'
    $col = [math]::Max((Get-TextWidth $ic), (Get-TextWidth $icn))
    $ic = $ic + (' ' * ($col - (Get-TextWidth $ic))); $icn = $icn + (' ' * ($col - (Get-TextWidth $icn)))
    Hide-Cursor
    try {
        Start-Frame
        Write-UiSegments @(@(((Get-Icon $iconName) + ' '), $role), @($Title, $role))
        Write-UiBlank
        foreach ($l in $Lines) { foreach ($wl in (Split-TextLines $l ($w - 2))) { Write-Ui -Text ('  ' + $wl) -Role NormalText } }
        Write-UiBlank
        Write-UiSegments @(@('  01 ', 'PrimaryAccent'), @(($ic + ' '), 'NormalText'), @($YesLabel, 'NormalText'))
        Write-UiSegments @(@('  02 ', 'PrimaryAccent'), @(($icn + ' '), 'NormalText'), @($NoLabel, 'NormalText'))
        Write-KeyHints @(@('01-02', 'Type a number'), @('Enter', ("Default: " + $(if ($Default) { $YesLabel } else { $NoLabel }))), @('Esc', 'No'))
        Stop-Frame
        $typed = ''
        while ($true) {
            $k = Read-TuiKey
            if ($k.Name -eq 'Enter') { return $Default }
            if ($k.Name -eq 'Esc' -or $k.Name -eq 'CtrlC') { return $false }
            if ($k.Name -eq 'Char' -and $k.Char -match '^\d$') {
                $typed += $k.Char
                if ($typed -eq '01' -or $typed -eq '1') { return $true }
                if ($typed -eq '02' -or $typed -eq '2') { return $false }
                if ($typed -ne '0') { $typed = '' }
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
    # Scrollable read-only text (technical details, generated command, filter browser). Esc/Enter closes.
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
            }
        }
    } finally { Show-Cursor }
}

Export-ModuleMember -Function Show-Notice, Show-Confirm, Show-ErrorScreen, Show-TextViewer
