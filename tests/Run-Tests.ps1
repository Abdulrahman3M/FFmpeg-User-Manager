<#
.SYNOPSIS
    Runs the focused FFmpeg TUI test suite. Works on Windows PowerShell 5.1 and PowerShell 7.x.
.PARAMETER Suite
    Unit, Smoke or All (default).
.PARAMETER Filter
    Only run test files whose name contains this text.
#>
param([ValidateSet('All', 'Unit', 'Smoke')][string]$Suite = 'All', [string]$Filter = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
Write-Host ("PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $(if ($PSVersionTable.ContainsKey('PSEdition')) { $PSVersionTable.PSEdition } else { 'Desktop' }))
Initialize-TestEnvironment
$files = @()
if ($Suite -in @('All', 'Unit')) { $files += Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Unit') -Filter '*.Tests.ps1' | Sort-Object Name }
if ($Suite -in @('All', 'Smoke')) { $files += Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Smoke') -Filter '*.Tests.ps1' | Sort-Object Name }
if ($Filter) { $files = @($files | Where-Object { $_.Name -like "*$Filter*" }) }
try {
    foreach ($testFile in $files) {
        Write-Host ("`n##### " + $testFile.Name) -ForegroundColor White
        $currentTestFile = $testFile.FullName; $currentTestName = $testFile.Name
        try { . $currentTestFile } catch { Set-TestGroup $currentTestName; Add-TestResult "test file crashed: $currentTestName" 'FAIL' ($_.Exception.Message + "`n" + $_.ScriptStackTrace) }
    }
} finally { Remove-TestEnvironment }
$all = Get-TestResults
$pass = @($all | Where-Object { $_.Status -eq 'PASS' }).Count
$fail = @($all | Where-Object { $_.Status -eq 'FAIL' }).Count
$unv = @($all | Where-Object { $_.Status -eq 'UNVERIFIED' }).Count
Write-Host ("`n==== SUMMARY: {0} PASS, {1} FAIL, {2} UNVERIFIED ====" -f $pass, $fail, $unv) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail) { $all | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { Write-Host ("FAIL: [{0}] {1} - {2}" -f $_.Group, $_.Name, $_.Detail) -ForegroundColor Red } }
exit $(if ($fail) { 1 } else { 0 })
