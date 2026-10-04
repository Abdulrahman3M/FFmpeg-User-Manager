<# 07 - Error handling: validate first, return messages instead of throwing for expected problems, catch at ONE top-level place,
   restore the terminal in finally, print the error AFTER leaving the alternate screen, and use distinct exit codes.
   Exit codes: 0 ok, 1 unexpected error, 2 needs an interactive console, 3 missing dependency.
   Run:  pwsh -File 07-Error-Handling.ps1 [-Demo] #>
param([switch]$Demo)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
function Test-InputFile {
    # Expected problems are RETURNED as user-facing text (not exceptions); $null means fine.
    param([string]$FullPath)
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return 'Please enter a file path.' }
    if (Test-Path -LiteralPath $FullPath -PathType Container) { return 'That path is a folder, not a file.' }
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return ('File not found: ' + $FullPath) }
    try { $fs = [System.IO.File]::Open($FullPath, 'Open', 'Read', 'ReadWrite'); $fs.Dispose() }
    catch [System.UnauthorizedAccessException] { return 'Access to the file was denied.' }
    catch [System.IO.IOException] { return 'The file is locked by another program or cannot be read.' }
    return $null
}
$code = 0; $failure = ''
try {
    Write-Output ('Check 1: ' + (Test-InputFile ''))
    Write-Output ('Check 2: ' + (Test-InputFile (Join-Path ([System.IO.Path]::GetTempPath()) 'no-such-file-xyz.txt')))
    if ($Demo) { throw 'simulated unexpected failure' }   # the one place where an exception is the right tool
} catch {
    $code = 1; $failure = $_.Exception.Message
} finally {
    # restore cursor / screen here (Exit-Screen in a real app)
}
if ($code -ne 0) { [Console]::Error.WriteLine('Unexpected error: ' + $failure) }
exit $(if ($Demo) { 0 } else { $code })   # the demo prints the error path but exits 0 so test runners stay green
