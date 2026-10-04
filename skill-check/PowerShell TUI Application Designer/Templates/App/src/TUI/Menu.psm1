# Menu.psm1 - numbered menus. Rule: every selectable option is "NN  Icon  Name" with a two-digit zero-padded number
# (01..09, 10, 11 ... 100 and beyond, never truncated) and a one-line description under it. No letter keys.
Set-StrictMode -Version 2.0

function Format-MenuNumber { param([int]$Number) return ([string]$Number).PadLeft(2, '0') }

function Resolve-NumberInput {
    # Quick select by typing digits. Returns @{ State = 'Select'|'Wait'|'Invalid'; Index }.
    # "05" selects option 5 at once; a prefix of a longer number (e.g. "1" in a list of 12) waits for more digits.
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

function New-MenuItem {
    # Label + Desc are mandatory (every option explains itself). Enabled = $false needs a Reason shown under the option.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Desc, [string]$Value = '', [string]$Icon = 'Item', [bool]$Enabled = $true, [string]$Reason = '')
    if (-not $Value) { $Value = $Label }
    return @{ Label = $Label; Desc = $Desc; Value = $Value; Icon = $Icon; Enabled = $Enabled; Reason = $Reason }
}

function Show-Menu {
    # Returns the chosen item's Value, or $null when the user presses Esc (Back).
    param([Parameter(Mandatory)][string]$Title, [string]$Description = '', [Parameter(Mandatory)][object[]]$Items, [int]$Default = 0)
    $items = @($Items)
    if ($items.Count -eq 0) { throw 'Show-Menu needs at least one item.' }
    $sel = [math]::Min([math]::Max($Default, 0), $items.Count - 1)
    $buffer = ''
    while ($true) {
        Clear-Ui
        Write-UiLine ((Get-Icon 'Run') + '  ' + $Title) 'Title'
        if ($Description) { Write-UiLine ''; Write-UiLine ('  ' + $Description) 'Dim' }
        Write-UiLine ''
        for ($i = 0; $i -lt $items.Count; $i++) {
            $it = $items[$i]
            $marker = ' '; $role = 'Normal'
            if ($i -eq $sel) { $marker = '>'; $role = 'Selected' }
            if (-not $it.Enabled) { $role = 'Dim' }
            Write-Ui (' ' + $marker + ' ') $role
            Write-Ui (Format-MenuNumber ($i + 1)) 'Number'
            Write-UiLine ('  ' + (Get-Icon $it.Icon) + '  ' + $it.Label) $role
            $d = $it.Desc; if (-not $it.Enabled -and $it.Reason) { $d = $it.Reason }
            Write-UiLine ('        ' + $d) 'Dim'
        }
        Write-UiLine ''
        Write-Ui ('Up/Down' + ' ') 'Key'; Write-Ui 'Navigate   ' 'Dim'
        Write-Ui 'Enter ' 'Key'; Write-Ui 'Select   ' 'Dim'
        Write-Ui ((Format-MenuNumber 1) + '-' + (Format-MenuNumber $items.Count) + ' ') 'Key'; Write-Ui 'Type a number   ' 'Dim'
        Write-Ui 'Esc ' 'Key'; Write-UiLine 'Back' 'Dim'
        $k = Read-AppKey
        switch ($k.Name) {
            'CtrlC' { throw (New-Object System.OperationCanceledException('Quit')) }
            'Esc' { return $null }
            'Up' { $sel = ($sel - 1 + $items.Count) % $items.Count; $buffer = '' }
            'Down' { $sel = ($sel + 1) % $items.Count; $buffer = '' }
            'Enter' {
                if ($buffer) { $r = Resolve-NumberInput $buffer $items.Count; if ($r.State -ne 'Invalid') { $sel = $(if ($r.State -eq 'Select') { $r.Index } else { [int]$buffer - 1 }) } ; $buffer = '' }
                if ($sel -ge 0 -and $sel -lt $items.Count -and $items[$sel].Enabled) { return $items[$sel].Value }
            }
            'Char' {
                if ($k.Char -match '^\d$') {
                    $buffer += $k.Char
                    $r = Resolve-NumberInput $buffer $items.Count
                    if ($r.State -eq 'Select') { $buffer = ''; if ($items[$r.Index].Enabled) { return $items[$r.Index].Value } }
                    elseif ($r.State -eq 'Invalid') { $buffer = '' }
                }
            }
            'Backspace' { if ($buffer.Length -gt 0) { $buffer = $buffer.Substring(0, $buffer.Length - 1) } }
        }
    }
}

Export-ModuleMember -Function Format-MenuNumber, Resolve-NumberInput, New-MenuItem, Show-Menu
