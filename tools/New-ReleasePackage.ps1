<#
.SYNOPSIS
    Builds deterministic Full, Lite, or Both Windows x64 release packages from the canonical project VERSION.
.DESCRIPTION
    Works on Windows PowerShell 5.1 and PowerShell 7.x. By default it builds both editions into dist.
    Full requires a verified FFmpeg runtime source, or the explicit -AcquireFFmpeg consent switch.
    Nothing is published, tagged, pushed, or silently overwritten.
.PARAMETER FFmpegRuntimeSource
    Existing Gyan FFmpeg build root or staged runtime directory to verify against External-Libraries/manifest.json.
.PARAMETER AcquireFFmpeg
    Explicitly authorizes downloading the manifest-pinned Gyan.FFmpeg.Shared x64 package through WinGet.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [ValidateSet('Full', 'Lite', 'Both')][string]$Edition = 'Both',
    [string]$FFmpegRuntimeSource = '',
    [switch]$AcquireFFmpeg
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
. (Join-Path (Join-Path $root 'src') 'Import-Modules.ps1')
Import-FFTuiModules -Root $root
Import-Module -Name (Join-Path $PSScriptRoot 'ReleasePackage.psm1') -Force -Global -DisableNameChecking -ErrorAction Stop
$result = New-ReleasePackages -ProjectRoot $root -OutputDirectory $OutputDirectory -Edition $Edition -FFmpegRuntimeSource $FFmpegRuntimeSource -AcquireFFmpeg:$AcquireFFmpeg
foreach ($packagePath in @($result.Packages)) { Write-Output $packagePath }
Write-Output $result.ChecksumPath
