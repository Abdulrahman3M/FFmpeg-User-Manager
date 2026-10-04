<#
.SYNOPSIS
    Runs a TUI project's tests (tests/Run-Tests.ps1) under every PowerShell edition installed on this machine and summarizes.
.DESCRIPTION
    Exit code 0 only when every edition that ran had 0 failures. An edition that is not installed is reported as NOT RUN
    (never as passed). Works on Windows PowerShell 5.1 and PowerShell 7.x.
.PARAMETER Path   Project root.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Path).Path
$runner = Join-Path (Join-Path $root 'tests') 'Run-Tests.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw "tests/Run-Tests.ps1 not found in $root" }
$editions = @('pwsh', 'powershell')
$failed = $false; $ran = 0
foreach ($e in $editions) {
    $cmd = Get-Command $e -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { Write-Output ("[NOT RUN] {0} is not installed on this machine" -f $e); continue }
    $log = Join-Path ([System.IO.Path]::GetTempPath()) ('tui-tests-' + $e + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.log')
    & $cmd.Source -NoProfile -ExecutionPolicy Bypass -File $runner *> $log
    $code = $LASTEXITCODE; $ran++
    $sum = (Select-String -Path $log -Pattern '==== SUMMARY' | Select-Object -Last 1)
    Write-Output ("[{0}] {1} - {2} (log: {3})" -f $(if ($code -eq 0) { 'PASS' } else { 'FAIL' }), $e, $(if ($sum) { $sum.Line.Trim('= ') } else { 'no summary' }), $log)
    if ($code -ne 0) { $failed = $true }
}
if ($ran -eq 0) { Write-Output 'No PowerShell edition could be started.'; exit 1 }
if ($failed) { exit 1 }
exit 0
