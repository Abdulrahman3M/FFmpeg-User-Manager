<#
.SYNOPSIS
    Validation gate for a PowerShell TUI project: structure, encoding, syntax, forbidden constructs, launchers, version, tests present.
.DESCRIPTION
    Exit code 0 = every rule passed, 1 = at least one rule failed. Read-only. Works on Windows PowerShell 5.1 and PowerShell 7.x.
.PARAMETER Path   Project root (the folder with the entry script and src/).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = (Resolve-Path -LiteralPath $Path).Path
$results = New-Object System.Collections.Generic.List[object]
function Add-Rule { param([string]$Id, [string]$Name, [bool]$Ok, [string]$Detail = '') $results.Add([pscustomobject]@{ Id = $Id; Name = $Name; Ok = $Ok; Detail = $Detail }) }

$entry = @(Get-ChildItem -LiteralPath $root -Filter 'Start-*.ps1' -File)
Add-Rule 'S1' 'one entry script Start-<Name>.ps1 in the root' ($entry.Count -eq 1) ("found: " + (($entry | ForEach-Object { $_.Name }) -join ', '))
Add-Rule 'S2' 'src/Import-Modules.ps1 exists (single place that orders the modules)' (Test-Path -LiteralPath (Join-Path $root 'src/Import-Modules.ps1'))
foreach ($dir in 'src/Core', 'src/TUI', 'tests') { Add-Rule 'S3' "folder $dir exists" (Test-Path -LiteralPath (Join-Path $root $dir) -PathType Container) }
foreach ($m in 'Platform', 'Theme', 'Renderer', 'Input', 'Menu') { Add-Rule 'S4' "module $m.psm1 exists" (@(Get-ChildItem -LiteralPath $root -Recurse -Filter "$m.psm1" -File).Count -ge 1) }
Add-Rule 'S5' 'tests/Run-Tests.ps1 exists' (Test-Path -LiteralPath (Join-Path $root 'tests/Run-Tests.ps1'))
$vf = Join-Path $root 'VERSION'
$ver = ''; if (Test-Path -LiteralPath $vf) { $ver = (Get-Content -LiteralPath $vf -TotalCount 1).Trim() }
Add-Rule 'V1' 'VERSION holds a Semantic Version' ($ver -match '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$') $ver

$src = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' -and $_.FullName -notmatch '[\\/](dist|\.git)[\\/]' })
$bad = @{ Ascii = @(); Parse = @(); Iex = @(); Ternary = @(); Coalesce = @(); Parallel = @(); WinVar = @(); LetterKey = @() }
foreach ($f in $src) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    if ($text -match '[^\x00-\x7F]') { $bad.Ascii += $f.Name }
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { $bad.Parse += $f.Name; continue }
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $n = $c.GetCommandName()
        if ($n -in @('Invoke-Expression', 'iex')) { $bad.Iex += ($f.Name + ':' + $c.Extent.StartLineNumber) }
        if ($n -eq 'ForEach-Object' -and ($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Parallel' })) { $bad.Parallel += $f.Name }
    }
    if ($ast.FindAll({ param($n) $n.GetType().Name -eq 'TernaryExpressionAst' }, $true).Count -gt 0) { $bad.Ternary += $f.Name }
    if ($ast.FindAll({ param($n) $n.GetType().Name -eq 'PipelineChainAst' }, $true).Count -gt 0) { $bad.Ternary += ($f.Name + ' (&& / ||)') }
    if ($f.FullName -notmatch '[\\/]tests[\\/]' -and $text -match '\$\w+\s*\?\?\s') { $bad.Coalesce += $f.Name }
    if ($f.Name -ne 'Platform.psm1' -and $f.FullName -notmatch '[\\/]tests[\\/]' -and $text -match '\$Is(Windows|Linux|MacOS)\b') { $bad.WinVar += $f.Name }
    if ($f.Extension -eq '.psm1' -and $text -match "Read-Host" ) { $bad.LetterKey += ($f.Name + ' uses Read-Host (use the Input module)') }
}
Add-Rule 'C1' 'all .ps1/.psm1 files are ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI)' ($bad.Ascii.Count -eq 0) ($bad.Ascii -join ', ')
Add-Rule 'C2' 'all .ps1/.psm1 files parse without errors' ($bad.Parse.Count -eq 0) ($bad.Parse -join ', ')
Add-Rule 'C3' 'no Invoke-Expression / iex' ($bad.Iex.Count -eq 0) ($bad.Iex -join ', ')
Add-Rule 'C4' 'no PowerShell-7-only syntax (ternary, pipeline chains, ForEach-Object -Parallel, ??)' (($bad.Ternary.Count + $bad.Parallel.Count + $bad.Coalesce.Count) -eq 0) ((@($bad.Ternary) + @($bad.Parallel) + @($bad.Coalesce)) -join ', ')
Add-Rule 'C5' '$IsWindows/$IsLinux/$IsMacOS are read only in the platform module' ($bad.WinVar.Count -eq 0) ($bad.WinVar -join ', ')
Add-Rule 'C6' 'no Read-Host in modules (all keyboard input goes through the Input module)' ($bad.LetterKey.Count -eq 0) ($bad.LetterKey -join ', ')
$strict = @($src | Where-Object { $_.Extension -eq '.psm1' -and ([System.IO.File]::ReadAllText($_.FullName) -notmatch 'Set-StrictMode') })
Add-Rule 'C7' 'every module sets Set-StrictMode' ($strict.Count -eq 0) (($strict | ForEach-Object { $_.Name }) -join ', ')

foreach ($bat in Get-ChildItem -LiteralPath $root -Filter '*.bat' -File) {
    $b = [System.IO.File]::ReadAllBytes($bat.FullName); $lf = 0
    for ($i = 1; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10 -and $b[$i - 1] -ne 13) { $lf++ } }
    Add-Rule 'L1' ("$($bat.Name) has CRLF line endings") ($lf -eq 0)
}
foreach ($sh in Get-ChildItem -LiteralPath $root -Filter '*.sh' -File) {
    $text = [System.IO.File]::ReadAllText($sh.FullName)
    Add-Rule 'L2' ("$($sh.Name) has LF line endings and a shebang") (($text -notmatch "`r") -and $text.StartsWith('#!'))
}
Add-Rule 'L3' 'a Windows launcher (.bat) exists' (@(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File).Count -ge 1)
$fail = @($results | Where-Object { -not $_.Ok })
foreach ($r in $results) { Write-Output ('[{0}] {1} {2}{3}' -f $(if ($r.Ok) { 'PASS' } else { 'FAIL' }), $r.Id, $r.Name, $(if (-not $r.Ok -and $r.Detail) { ' -> ' + $r.Detail } else { '' })) }
Write-Output ('==== {0} rules, {1} failed ====' -f $results.Count, $fail.Count)
if ($fail.Count -gt 0) { exit 1 }
exit 0
