<#
.SYNOPSIS
    Builds dist\FFmpeg-User-Manager-v<VERSION>.zip with only the files end users need.
.DESCRIPTION
    Works on Windows PowerShell 5.1 and PowerShell 7.x. The version comes from the VERSION file.
    Nothing is published; this only creates the local archive.
#>
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = ((Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)).Trim()
$semver = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if ($version -notmatch $semver) { throw "VERSION does not contain a valid Semantic Version: '$version'" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$name = "FFmpeg-User-Manager-v$version"
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ($name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkg = Join-Path $stage 'FFmpeg-User-Manager'
[void](New-Item -ItemType Directory -Path $pkg -Force)
try {
    foreach ($f in 'FFmpeg-User-Manager.bat', 'Start-FFmpegTUI.ps1', 'VERSION', 'README.md', 'CHANGELOG.md') { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $pkg }
    foreach ($d in 'config', 'src', 'docs') { Copy-Item -LiteralPath (Join-Path $root $d) -Destination $pkg -Recurse }
    $zip = Join-Path $OutputDirectory ($name + '.zip')
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path $pkg -DestinationPath $zip -CompressionLevel Optimal
    Write-Output $zip
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
