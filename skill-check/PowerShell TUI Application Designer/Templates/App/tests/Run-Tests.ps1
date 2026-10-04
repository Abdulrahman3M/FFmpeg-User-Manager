<#
.SYNOPSIS  Runs the unit tests. Works on Windows PowerShell 5.1 and PowerShell 7.x.
.PARAMETER Filter  Only run test files whose name contains this text.
Exit code 1 when anything failed. UNVERIFIED = could not be executed here (reason printed), never counted as PASS.
#>
param([string]$Filter = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
Write-Host ('PowerShell {0}' -f $PSVersionTable.PSVersion)
Initialize-TestEnvironment
try {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Unit') -Filter '*.Tests.ps1' -File | Sort-Object Name)
    if ($Filter) { $files = @($files | Where-Object { $_.Name -like "*$Filter*" }) }
    foreach ($f in $files) {
        Write-Host ("`n##### " + $f.Name) -ForegroundColor White
        try { . $f.FullName } catch { Set-TestGroup $f.Name; Add-TestResult ('test file crashed: ' + $f.Name) 'FAIL' ($_.Exception.Message + ' @ ' + $_.ScriptStackTrace) }
    }
} finally { Remove-TestEnvironment }
$all = Get-TestResults
$p = @($all | Where-Object { $_.Status -eq 'PASS' }).Count; $f = @($all | Where-Object { $_.Status -eq 'FAIL' }).Count; $u = @($all | Where-Object { $_.Status -eq 'UNVERIFIED' }).Count
Write-Host ("`n==== SUMMARY: {0} PASS, {1} FAIL, {2} UNVERIFIED ====" -f $p, $f, $u)
if ($f) { $all | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { Write-Host ('FAIL: [{0}] {1} - {2}' -f $_.Group, $_.Name, $_.Detail) }; exit 1 }
exit 0
