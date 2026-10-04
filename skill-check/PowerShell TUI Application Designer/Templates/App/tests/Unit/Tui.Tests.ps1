Set-TestGroup 'Icon tiers'
$wt = @{ WT_SESSION = 'x' }
Assert-Equal 'Windows Terminal -> Emoji' 'Emoji' (Resolve-IconTier -Env $wt -IsWin $true -Redirected $false)
Assert-Equal 'classic Windows console -> Symbol' 'Symbol' (Resolve-IconTier -Env @{} -IsWin $true -Redirected $false)
Assert-Equal 'redirected output -> Ascii' 'Ascii' (Resolve-IconTier -Env $wt -IsWin $true -Redirected $true)
Assert-Equal 'UTF-8 Linux -> Emoji' 'Emoji' (Resolve-IconTier -Env @{ LANG = 'en_US.UTF-8' } -IsWin $false -Redirected $false)
Assert-Equal 'non-UTF-8 Linux -> Ascii' 'Ascii' (Resolve-IconTier -Env @{ LANG = 'C' } -IsWin $false -Redirected $false)
Assert-Equal 'override symbol wins' 'Symbol' (Resolve-IconTier -Env @{ {{ENVPREFIX}}_ICONS = 'symbol'; WT_SESSION = 'x' } -IsWin $true -Redirected $true)
foreach ($tier in 'Emoji', 'Symbol', 'Ascii') {
    $table = Get-IconTable; $missing = @($table.Keys | Where-Object { -not $table[$_][$tier] })
    Assert-Equal "every icon has a $tier form" 0 $missing.Count
}
Assert-True 'ASCII icons are really ASCII' (@((Get-IconTable).Values | Where-Object { $_.Ascii -notmatch '^[\x20-\x7E]$' }).Count -eq 0)

Set-TestGroup 'Numbered menu'
Assert-Equal 'number 1 is 01' '01' (Format-MenuNumber 1)
Assert-Equal 'number 100 is not truncated' '100' (Format-MenuNumber 100)
Assert-Equal 'two-digit number selects at once' 'Select' (Resolve-NumberInput '05' 12).State
Assert-Equal 'a prefix of a longer number waits' 'Wait' (Resolve-NumberInput '1' 12).State
Assert-Equal 'a number outside the list is invalid' 'Invalid' (Resolve-NumberInput '99' 12).State
$items = @((New-MenuItem -Label 'First' -Desc 'd1' -Value 'a'), (New-MenuItem -Label 'Second' -Desc 'd2' -Value 'b'), (New-MenuItem -Label 'Third' -Desc 'd3' -Value 'c'))
$ui = Invoke-Ui { Show-Menu -Title 'T' -Items $items } '02'
Assert-Equal 'typing 02 chooses the second item' 'b' $ui.Value
Assert-True 'every option is shown as NN with its description' ($ui.Output.Contains('01') -and $ui.Output.Contains('02') -and $ui.Output.Contains('03') -and $ui.Output.Contains('d2'))
$ui = Invoke-Ui { Show-Menu -Title 'T' -Items $items } '{Down}{Down}{Enter}'
Assert-Equal 'arrows and Enter choose the third item' 'c' $ui.Value
$ui = Invoke-Ui { Show-Menu -Title 'T' -Items $items } '{Esc}'
Assert-True 'Esc returns $null (Back)' ($null -eq $ui.Value -and $ui.Error -eq '')
$dis = @((New-MenuItem -Label 'Off' -Desc 'x' -Value 'off' -Enabled $false -Reason 'Needs something that is missing.'), (New-MenuItem -Label 'On' -Desc 'y' -Value 'on'))
$ui = Invoke-Ui { Show-Menu -Title 'T' -Items $dis } '01{Enter}02'
Assert-Equal 'a disabled option cannot be chosen' 'on' $ui.Value
Assert-Contains 'a disabled option shows its reason' $ui.Output 'Needs something that is missing.'
$ui = Invoke-Ui { Show-Menu -Title 'T' -Items $items } ''
Assert-Contains 'running out of scripted keys fails loudly' $ui.Error 'Scripted input exhausted'

Set-TestGroup 'Dialogs and prompts'
Assert-Equal 'Show-Confirm 01 is Yes' $true (Invoke-Ui { Show-Confirm -Title 'Q' } '01').Value
Assert-Equal 'Show-Confirm 02 is No' $false (Invoke-Ui { Show-Confirm -Title 'Q' } '02').Value
Assert-Equal 'Esc counts as No' $false (Invoke-Ui { Show-Confirm -Title 'Q' } '{Esc}').Value
$ui = Invoke-Ui { Read-ValidatedInput -Prompt 'P' -Help 'h' -Example 'e' -Validate { param($t) Test-PersonName $t } } '{Enter}Bob{Enter}'
Assert-Equal 'invalid input is rejected, then the valid value is accepted' 'Bob' $ui.Value
Assert-Contains 'the validation message is shown' $ui.Output 'Please type a name.'
Assert-True 'Esc cancels a prompt' ($null -eq (Invoke-Ui { Read-ValidatedInput -Prompt 'P' -Help 'h' -Example 'e' } '{Esc}').Value)

Set-TestGroup 'Whole application (scripted)'
$ui = Invoke-Ui { Start-TuiApp -Root (Get-TestRoot) } '04{Enter}05'
Assert-True 'About then Exit runs without errors' ($ui.Error -eq '' -and $ui.Output.Contains('About'))
$ui = Invoke-Ui { Start-TuiApp -Root (Get-TestRoot) } '01Ada{Enter}01{Enter}05'
Assert-True 'the demo form saves a name' ($ui.Error -eq '' -and (Get-UserSetting 'name') -eq 'Ada')
