<#
.SYNOPSIS
    FFmpeg PowerShell TUI - a beginner-friendly terminal interface for FFmpeg on Windows.

.DESCRIPTION
    Launches the FFmpeg User Manager, an interactive, keyboard-driven text UI that guides you through common FFmpeg
    operations (convert, trim, merge, compress, GIF, frames, filters, subtitles, HLS, ...)
    without typing FFmpeg commands. Supports Windows PowerShell 5.1 and PowerShell 7.x.

.PARAMETER Version
    Print the application version (from the VERSION file) and exit.

.PARAMETER SkipUpdateCheck
    Do not check for FFmpeg updates at startup.

.PARAMETER ScriptedInput
    Automation/testing hook: feed key presses (for example "1{Enter}") instead of reading the keyboard.

.PARAMETER BufferOutput
    Automation/testing hook: render into a memory buffer instead of the console.

.EXAMPLE
    .\Start-FFmpegTUI.ps1
#>
[CmdletBinding()]
param(
    [switch]$Version,
    [switch]$SkipUpdateCheck,
    [string]$ScriptedInput,
    [switch]$BufferOutput
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
try {
    . (Join-Path (Join-Path $root 'src') 'Import-Modules.ps1')
    Import-FFTuiModules -Root $root
} catch {
    Write-Host ('FFmpeg TUI could not load its modules: ' + $_.Exception.Message) -ForegroundColor Red
    exit 3
}
if ($Version) {
    Set-AppRoot $root
    Write-Output ((Get-AppName) + ' v' + (Get-AppVersion))
    exit 0
}
$code = Start-FFmpegTuiApp -Root $root -ScriptedInput $ScriptedInput -SkipUpdateCheck:$SkipUpdateCheck -BufferOutput:$BufferOutput
exit $code
