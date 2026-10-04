<# 02 - Nested menu: a submenu returns to its parent with Esc; the parent loops until Exit.
   Run:  pwsh -File 02-Nested-Menu.ps1 [-Demo] #>
param([switch]$Demo)
. (Join-Path $PSScriptRoot 'Shared/TinyTui.ps1')
if ($Demo) { Set-DemoKeys '02{Esc}03' }   # Tools -> Esc back to main -> Exit
function Show-ToolsMenu {
    $items = @(@{ Label = 'Clean temporary files'; Desc = 'Remove files the program created.'; Value = 'clean' }, @{ Label = 'Rebuild index'; Desc = 'Scan again and rebuild the list.'; Value = 'index' })
    $r = Show-NumberedMenu -Title 'Tools' -Items $items
    if ($r) { Write-Line ('Tool chosen: ' + $r) 'Green' }
}
$main = @(@{ Label = 'Reports'; Desc = 'Open the reports.'; Value = 'reports' }, @{ Label = 'Tools'; Desc = 'Maintenance tools (opens a submenu).'; Value = 'tools' }, @{ Label = 'Exit'; Desc = 'Close the program.'; Value = 'exit' })
$done = $false
while (-not $done) {
    switch (Show-NumberedMenu -Title 'Main menu' -Items $main) {
        'reports' { Write-Line 'Reports screen' 'Green' }
        'tools' { Show-ToolsMenu }
        'exit' { $done = $true }
        default { $done = $true }   # Esc on the top level leaves
    }
}
Write-Line 'Bye.' 'Gray'
