<#
.SYNOPSIS
    {{AppName}} - entry point. Works on Windows PowerShell 5.1 and PowerShell 7.x, on Windows and Linux.
.PARAMETER Version
    Print the version and exit.
.PARAMETER ScriptedInput
    Drive the UI with a key string such as '01{Enter}' (tests, CI, demos). Tokens: {Enter} {Esc} {Up} {Down} {Backspace} {CtrlC}.
#>
[CmdletBinding()]
param([switch]$Version, [string]$ScriptedInput)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = $PSScriptRoot
. (Join-Path (Join-Path $root 'src') 'Import-Modules.ps1')
Import-AppModules -Root $root

if ($Version) { Write-Output ('{{AppName}} v' + (Get-AppVersion $root)); exit 0 }

$scripted = $PSBoundParameters.ContainsKey('ScriptedInput')
$interactive = $true
try { $interactive = (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected) } catch { $interactive = $false }
if (-not $interactive -and -not $scripted) {
    Write-Output '{{AppName}} needs an interactive console (a real terminal window). Start it from a terminal, not from a pipe or redirect.'
    exit 2
}

$sink = 'Console'
Initialize-Renderer -Ansi (Test-AnsiSupport) -Sink $sink
if ($scripted) { Set-ScriptedInput $ScriptedInput }
$code = 0
$oldCtrl = $false
try { $oldCtrl = [Console]::TreatControlCAsInput; if (-not $scripted) { [Console]::TreatControlCAsInput = $true } } catch { }
Enter-Screen
try {
    Start-TuiApp -Root $root
} catch [System.OperationCanceledException] {
    $code = 0   # Ctrl+C: leave quietly
} catch {
    $code = 1
    Write-AppLog ('unhandled: ' + $_.Exception.Message) 'ERROR'
    $failure = $_.Exception.Message
} finally {
    Exit-Screen
    try { [Console]::TreatControlCAsInput = $oldCtrl } catch { }
}
if ($code -ne 0) { [Console]::Error.WriteLine('Unexpected error: ' + $failure) }   # printed AFTER leaving the alternate screen so it stays visible
exit $code
