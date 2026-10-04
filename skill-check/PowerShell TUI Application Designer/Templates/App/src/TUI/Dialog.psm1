# Dialog.psm1 - confirmations and notices. They are menus too, so they follow the numbered-option rule (01 Yes / 02 No).
Set-StrictMode -Version 2.0

function Show-Confirm {
    # Returns $true / $false. Esc counts as No. Both answers are described so the user knows what each does.
    param([Parameter(Mandatory)][string]$Title, [string]$Message = '', [string]$YesLabel = 'Yes', [string]$YesDesc = 'Go ahead.', [string]$NoLabel = 'No', [string]$NoDesc = 'Do nothing and go back.', [bool]$Default = $true)
    $items = @(
        (New-MenuItem -Label $YesLabel -Desc $YesDesc -Value 'yes' -Icon 'Yes'),
        (New-MenuItem -Label $NoLabel -Desc $NoDesc -Value 'no' -Icon 'No')
    )
    $r = Show-Menu -Title $Title -Description $Message -Items $items -Default $(if ($Default) { 0 } else { 1 })
    return ($r -eq 'yes')
}

function Show-Notice {
    # Success / Warning / Error / Info message with one numbered action. Returns when the user continues.
    param([Parameter(Mandatory)][string]$Title, [string[]]$Lines = @(), [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Kind = 'Info', [string]$ContinueLabel = 'Continue')
    $msg = (($Lines | ForEach-Object { $_ }) -join ' ')
    $icon = Get-Icon $Kind
    [void](Show-Menu -Title ($icon + '  ' + $Title) -Description $msg -Items @((New-MenuItem -Label $ContinueLabel -Desc 'Close this message.' -Value 'ok' -Icon $Kind)))
}

Export-ModuleMember -Function Show-Confirm, Show-Notice
