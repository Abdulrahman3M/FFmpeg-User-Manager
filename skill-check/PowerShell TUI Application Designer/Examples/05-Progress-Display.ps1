<# 05 - Progress display: a bar that redraws on ONE line with a carriage return, and a plain-text fallback when output is redirected
   (no escape codes, no carriage returns in logs). Percent, elapsed time and a cancel check belong in every long task.
   Run:  pwsh -File 05-Progress-Display.ps1 [-Demo] #>
param([switch]$Demo)
. (Join-Path $PSScriptRoot 'Shared/TinyTui.ps1')
function Format-Bar {
    param([int]$Percent, [int]$Width = 30)
    $filled = [int][math]::Floor($Width * $Percent / 100)
    return ('[' + ('#' * $filled) + ('-' * ($Width - $filled)) + '] ' + ([string]$Percent).PadLeft(3) + '%')
}
$redirected = $false; try { $redirected = [Console]::IsOutputRedirected } catch { $redirected = $true }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($p = 0; $p -le 100; $p += 25) {
    $line = (Format-Bar $p) + '  ' + $sw.Elapsed.ToString('mm\:ss')
    if ($redirected) { Write-Output $line } else { Write-Host ("`r" + $line) -NoNewline }
    if (-not $Demo) { Start-Sleep -Milliseconds 300 }
}
if (-not $redirected) { Write-Host '' }
Write-Line 'Done.' 'Green'
