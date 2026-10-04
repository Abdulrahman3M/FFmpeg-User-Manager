<#
.SYNOPSIS
    Creates a new, working PowerShell TUI application from the skill's template (Templates/App).
.DESCRIPTION
    Copies the template, replaces the placeholders and fixes line endings (.bat = CRLF, .sh = LF).
    Works on Windows PowerShell 5.1 and PowerShell 7.x, on Windows and Linux. Never overwrites an existing non-empty folder
    unless -Force is given.
.PARAMETER Name        Display name, e.g. 'Disk Helper'.
.PARAMETER Path        Folder to create (default: .\<AppId>).
.PARAMETER AppId       Identifier used in file names: letters, digits and hyphens (default: Name without spaces).
.PARAMETER RunTests    Run the generated project's tests afterwards.
.PARAMETER Force       Allow a non-empty destination folder (existing files with the same name are overwritten).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Path,
    [string]$AppId,
    [switch]$RunTests,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
function Test-IsWindowsHost { if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }; $v = Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue; return [bool]$v }
$skillRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path (Join-Path $skillRoot 'Templates') 'App'
if (-not (Test-Path -LiteralPath $template)) { throw "Template folder not found: $template" }
if (-not $AppId) { $AppId = ($Name -replace '[^A-Za-z0-9-]', '') }
if ($AppId -notmatch '^[A-Za-z][A-Za-z0-9-]*$') { throw "AppId '$AppId' must start with a letter and contain only letters, digits and hyphens." }
$envPrefix = ($AppId.ToUpperInvariant() -replace '[^A-Z0-9]', '_')
if (-not $Path) { $Path = Join-Path (Get-Location).Path $AppId }
$Path = [System.IO.Path]::GetFullPath($Path)
if ((Test-Path -LiteralPath $Path) -and @(Get-ChildItem -LiteralPath $Path -Force).Count -gt 0 -and -not $Force) { throw "Destination is not empty: $Path (use -Force to continue)." }
$map = @{ '{{AppName}}' = $Name; '{{AppId}}' = $AppId; '{{ENVPREFIX}}' = $envPrefix; '{{Year}}' = [string](Get-Date).Year }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$count = 0
foreach ($src in Get-ChildItem -LiteralPath $template -Recurse -File) {
    $rel = $src.FullName.Substring($template.Length).TrimStart([char[]]@('\', '/'))
    foreach ($k in $map.Keys) { $rel = $rel.Replace($k, $map[$k]) }
    $dest = Join-Path $Path $rel
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $text = [System.IO.File]::ReadAllText($src.FullName)
    foreach ($k in $map.Keys) { $text = $text.Replace($k, $map[$k]) }
    $text = $text -replace "`r`n", "`n"
    if ($dest.EndsWith('.bat')) { $text = $text -replace "`n", "`r`n" }
    [System.IO.File]::WriteAllText($dest, $text, $utf8)
    $count++
}
if (-not (Test-IsWindowsHost)) {
    foreach ($sh in Get-ChildItem -LiteralPath $Path -Filter '*.sh' -File) { try { & chmod +x $sh.FullName } catch { } }
}
Write-Output ("Created '{0}' ({1} files) in {2}" -f $Name, $count, $Path)
if ($RunTests) {
    $hostExe = (Get-Process -Id $PID).Path
    & $hostExe -NoProfile -File (Join-Path (Join-Path $Path 'tests') 'Run-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw "The generated project's tests failed (exit code $LASTEXITCODE)." }
}
