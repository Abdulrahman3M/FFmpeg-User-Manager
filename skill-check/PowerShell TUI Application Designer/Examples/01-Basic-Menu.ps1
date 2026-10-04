<# 01 - Basic numbered menu: Number + Icon + Label + one-line description, two-digit numbers, Esc = back.
   Run:  pwsh -File 01-Basic-Menu.ps1        (interactive)      pwsh -File 01-Basic-Menu.ps1 -Demo   (scripted, for tests) #>
param([switch]$Demo)
. (Join-Path $PSScriptRoot 'Shared/TinyTui.ps1')
if ($Demo) { Set-DemoKeys '02' }
$items = @(
    @{ Label = ((Get-TinyIcon ([char]::ConvertFromUtf32(0x1F4C4)) ([string][char]0x2666) '*') + '  Open a file'); Desc = 'Choose a file to work with.'; Value = 'open' },
    @{ Label = ((Get-TinyIcon ([char]::ConvertFromUtf32(0x1F527)) ([string][char]0x263C) '#') + '  Settings'); Desc = 'Change how the program behaves.'; Value = 'settings' },
    @{ Label = ((Get-TinyIcon ([char]::ConvertFromUtf32(0x1F6AA)) ([string][char]0x25C4) '<') + '  Exit'); Desc = 'Close the program.'; Value = 'exit' }
)
$choice = Show-NumberedMenu -Title 'Main menu' -Items $items
Write-Line ('You chose: ' + $choice) 'Green'
