<#
.SYNOPSIS
    Builds <Name>-v<VERSION>.zip from a TUI project: only what end users need (no tests, .git, dist, logs).
.DESCRIPTION
    The version comes from the project's VERSION file; nothing is published. Works on Windows PowerShell 5.1 and PowerShell 7.x.
.PARAMETER Path             Project root.
.PARAMETER OutputDirectory  Where to write the zip (default: <Path>/dist).
.PARAMETER Exclude          Top-level names to leave out (default: tests, dist, .git, .github).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path, [string]$OutputDirectory, [string[]]$Exclude = @('tests', 'dist', '.git', '.github'))
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Path).Path
$ver = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1).Trim()
if ($ver -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$') { throw "VERSION is not a Semantic Version: '$ver'" }
$entry = @(Get-ChildItem -LiteralPath $root -Filter 'Start-*.ps1' -File | Select-Object -First 1)
if ($entry.Count -eq 0) { throw 'No Start-<Name>.ps1 entry script found.' }
$name = $entry[0].BaseName.Substring('Start-'.Length)
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('pkg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $stage $name
[void](New-Item -ItemType Directory -Path $pkg -Force)
try {
    foreach ($item in Get-ChildItem -LiteralPath $root -Force) {
        if ($Exclude -contains $item.Name -or $item.Name -like '*.log' -or $item.Name -like '*.zip') { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $pkg -Recurse
    }
    $zip = Join-Path $OutputDirectory ("$name-v$ver.zip")
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path $pkg -DestinationPath $zip -CompressionLevel Optimal
    Write-Output $zip
} finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
