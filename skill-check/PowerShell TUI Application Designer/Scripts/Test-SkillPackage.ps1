<#
.SYNOPSIS
    Validates this skill package itself: structure, front matter, version, links, privacy, script syntax, and that the template
    generates a project whose tests and validator pass and that every example runs.
.DESCRIPTION
    Exit code 0 = every check passed. Works on Windows PowerShell 5.1 and PowerShell 7.x. Creates and removes a temporary folder only.
.PARAMETER SkipGenerate  Skip generating/running a project from the template (faster, less complete).
#>
[CmdletBinding()]
param([switch]$SkipGenerate)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
$res = New-Object System.Collections.Generic.List[object]
function Add-Check { param([string]$Name, [bool]$Ok, [string]$Detail = '') $res.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }) }
$hostExe = (Get-Process -Id $PID).Path

# structure
foreach ($p in 'SKILL.md', 'README.md', 'VERSION', 'References', 'Scripts', 'Examples', 'Images', 'Templates/App') { Add-Check "exists: $p" (Test-Path -LiteralPath (Join-Path $root $p)) }
foreach ($r in 'Architecture', 'TUI-Design-Rules', 'Cross-Platform-Compatibility', 'Unicode-and-Emoji-Handling', 'Error-Handling', 'Testing-Strategy', 'Packaging-and-Release', 'Coding-Conventions') { Add-Check "reference: $r.md" (Test-Path -LiteralPath (Join-Path $root "References/$r.md")) }

# front matter + version
$skill = [System.IO.File]::ReadAllText((Join-Path $root 'SKILL.md'))
$fm = [regex]::Match($skill, '(?s)\A---\r?\nname:\s*([a-z0-9-]+)\r?\ndescription:\s*(.+?)\r?\n---')
Add-Check 'SKILL.md front matter has name (lowercase-hyphen) and description' ($fm.Success) ''
if ($fm.Success) { Add-Check 'description is 1-1024 characters' (($fm.Groups[2].Value.Length -ge 20) -and ($fm.Groups[2].Value.Length -le 1024)) ([string]$fm.Groups[2].Value.Length) }
$ver = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1).Trim()
Add-Check 'VERSION is a Semantic Version' ($ver -match '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') $ver
Add-Check 'SKILL.md and README.md mention the VERSION' (($skill.Contains($ver)) -and ([System.IO.File]::ReadAllText((Join-Path $root 'README.md'))).Contains($ver))

# links
$bad = @()
foreach ($md in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.md' -File) {
    $t = [System.IO.File]::ReadAllText($md.FullName)
    foreach ($m in [regex]::Matches($t, '\]\(([^)#\s]+)(#[^)]*)?\)')) {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?:|mailto:)') { continue }
        $full = Join-Path $md.DirectoryName ($target -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { $bad += ($md.Name + ' -> ' + $target) }
    }
}
Add-Check 'all relative markdown links resolve' ($bad.Count -eq 0) ($bad -join '; ')
$refs = @(); foreach ($m in [regex]::Matches($skill, '`(References/[A-Za-z0-9-]+\.md|Scripts/[A-Za-z0-9-]+\.ps1|Examples/[A-Za-z0-9-]+\.ps1)`')) { if (-not (Test-Path -LiteralPath (Join-Path $root $m.Groups[1].Value))) { $refs += $m.Groups[1].Value } }
Add-Check 'files named in SKILL.md exist' ($refs.Count -eq 0) ($refs -join ', ')

# privacy / independence
$leaks = @()
foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in '.md', '.ps1', '.psm1', '.bat', '.sh', '.json', '.txt' -or $_.Name -eq 'VERSION' }) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    if ($f.Name -eq 'Test-SkillPackage.ps1') { continue }
    if ($t -match '(/home/[a-z]|/root/|C:\\Users\\|runneradmin|/Users/[A-Za-z])') { $leaks += ($f.Name + ': local path') }
    if ($t -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}') { $leaks += ($f.Name + ': e-mail address') }
    if ($t -match 'FFmpeg-User-Manager|Abdulrahman') { $leaks += ($f.Name + ': names the source project') }
}
Add-Check 'no local paths, e-mail addresses or source-project names in any file' ($leaks.Count -eq 0) ($leaks -join '; ')

# scripts
$syn = @(); $nonAscii = @()
foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }) {
    $t = $null; $e = $null
    if (-not ([System.IO.File]::ReadAllText($f.FullName)).Contains('{{')) {   # template files with placeholders are parsed after generation instead
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
        if ($e.Count -gt 0) { $syn += $f.Name }
    }
    if ([System.IO.File]::ReadAllText($f.FullName) -match '[^\x00-\x7F]') { $nonAscii += $f.Name }
}
Add-Check 'every .ps1/.psm1 parses' ($syn.Count -eq 0) ($syn -join ', ')
Add-Check 'every .ps1/.psm1 is ASCII-only' ($nonAscii.Count -eq 0) ($nonAscii -join ', ')
$nohelp = @(Get-ChildItem -LiteralPath (Join-Path $root 'Scripts') -Filter '*.ps1' -File | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -notmatch '\.SYNOPSIS' })
Add-Check 'every script has comment-based help (.SYNOPSIS)' ($nohelp.Count -eq 0) (($nohelp | ForEach-Object { $_.Name }) -join ', ')
$png = @(Get-ChildItem -LiteralPath (Join-Path $root 'Images') -Filter '*.png' -File | Where-Object { [System.IO.File]::ReadAllBytes($_.FullName)[1] -ne 80 })
Add-Check 'every image is a real PNG' ($png.Count -eq 0)

if (-not $SkipGenerate) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('skillcheck-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $proj = Join-Path $tmp 'Sample App'
        $out = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-TuiProject.ps1') -Name 'Sample App' -Path $proj -RunTests 2>&1
        Add-Check 'template generates a project whose own tests pass (0 FAIL)' (($LASTEXITCODE -eq 0) -and ((($out | Out-String) -match ' 0 FAIL'))) (($out | Select-Object -Last 3) -join ' | ')
        $null = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-TuiProject.ps1') -Path $proj 2>&1
        Add-Check 'generated project passes Test-TuiProject' ($LASTEXITCODE -eq 0)
        $v = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $proj 'Start-SampleApp.ps1') -Version 2>&1
        Add-Check 'generated app prints its version' ((($v | Out-String).Trim()) -eq 'Sample App v0.1.0') (($v | Out-String).Trim())
        $null = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $proj 'Start-SampleApp.ps1') -ScriptedInput '04{Enter}05' 2>&1
        Add-Check 'generated app runs a scripted session and exits 0' ($LASTEXITCODE -eq 0)
        $noni = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $proj 'Start-SampleApp.ps1') 2>&1   # output is captured here, so the app sees a redirected console
        Add-Check 'generated app refuses non-interactive use with exit code 2' ($LASTEXITCODE -eq 2) ("exit " + $LASTEXITCODE)
        $pkg = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-TuiPackage.ps1') -Path $proj -OutputDirectory (Join-Path $tmp 'out') 2>&1
        Add-Check 'package script builds a zip' ((Test-Path -LiteralPath (($pkg | Select-Object -Last 1).ToString().Trim()))) ($pkg | Out-String)
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
    foreach ($ex in Get-ChildItem -LiteralPath (Join-Path $root 'Examples') -Filter '0*.ps1' -File) {
        $o = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $ex.FullName -Demo 2>&1
        Add-Check ("example runs with -Demo and exits 0: " + $ex.Name) ($LASTEXITCODE -eq 0) (($o | Select-Object -Last 2) -join ' | ')
    }
}
$fail = @($res | Where-Object { -not $_.Ok })
foreach ($r in $res) { Write-Output ('[{0}] {1}{2}' -f $(if ($r.Ok) { 'PASS' } else { 'FAIL' }), $r.Name, $(if (-not $r.Ok -and $r.Detail) { ' -> ' + $r.Detail } else { '' })) }
Write-Output ('==== {0} checks, {1} failed ====' -f $res.Count, $fail.Count)
if ($fail.Count -gt 0) { exit 1 }
exit 0
