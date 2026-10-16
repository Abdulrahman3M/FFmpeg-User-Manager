# Unit tests: canonical external runtime manifest and metadata validation.
Set-TestGroup 'External library manifest'
$appRoot = Get-TestRoot
Set-AppRoot $appRoot
$manifest = Get-ExternalLibraryManifest
$libraries = @($manifest.Libraries)
$ffmpeg = @($libraries | Where-Object { $_.Id -eq 'ffmpeg' }) | Select-Object -First 1
$assimp = @($libraries | Where-Object { $_.Id -eq 'assimp' }) | Select-Object -First 1
Assert-Equal 'manifest schema is the current dependency-aware schema' 2 $manifest.SchemaVersion
Assert-True 'manifest includes both FFmpeg and Assimp as canonical dependencies' ($libraries.Count -eq 2 -and $ffmpeg -and $assimp)
if ($ffmpeg) {
    Assert-True 'manifest identifies pinned FFmpeg package and x64 architecture' ($ffmpeg.CurrentVersion -eq '9.0.2' -and $ffmpeg.Architecture -eq 'x64' -and $ffmpeg.PackageManagerId -eq 'Gyan.FFmpeg.Shared' -and $ffmpeg.PackageVersion -eq '9.0.2')
    Assert-True 'manifest records Full/Lite policy, official source, GPL license and official package hash' ([bool]$ffmpeg.BundledInFull -and -not [bool]$ffmpeg.BundledInLite -and $ffmpeg.SourceUri -like 'https://github.com/GyanD/*' -and $ffmpeg.License -eq 'GPL-3.0' -and $ffmpeg.PackageArchiveSha256 -match '^[A-Fa-f0-9]{64}$')
    Assert-True 'manifest records verified FFmpeg runtime files and license/source paths' (@($ffmpeg.Files).Count -ge 9 -and $ffmpeg.LicenseFiles -contains 'FFmpeg/LICENSES/COPYING.GPLv3' -and $ffmpeg.SourceFile -eq 'FFmpeg/SOURCE.txt')
    Assert-True 'manifest records the accepted runtime encoders, filters and executables for live verification' (@($ffmpeg.RequiredExecutables).Count -eq 2 -and @($ffmpeg.RequiredEncoders).Count -ge 8 -and @($ffmpeg.RequiredFilters).Count -ge 13)
    Assert-True 'manifest records Windows architecture and does not claim unverified Linux support' ($ffmpeg.WindowsSupport.Status -in @('PASS', 'UNVERIFIED') -and $ffmpeg.LinuxSupport.Status -in @('UNVERIFIED', 'N/A'))
}
if ($assimp) {
    Assert-True 'Assimp remains in the same manifest and stays Full-only' ($assimp.CurrentVersion -eq '6.0.5' -and $assimp.Architecture -eq 'x64' -and [bool]$assimp.BundledInFull -and -not [bool]$assimp.BundledInLite)
}
$packageVersions = @([pscustomobject]@{ name = '8.0.1' }, [pscustomobject]@{ name = '9.0.2' }, [pscustomobject]@{ name = '10.0.0' }, [pscustomobject]@{ name = '11.0.0-rc.1' })
Assert-Equal 'FFmpeg package metadata uses SemVer ordering across major versions' '10.0.0' (Get-ExternalPackageMetadataVersion -Metadata $packageVersions -Id 'ffmpeg')
$ffmpegUpdate = Get-ExternalLibraryUpdateStatus -Id 'ffmpeg' -LatestVersion '10.0.0' -LatestPackageVersion '10.0.0'
Assert-True 'FFmpeg upstream and winget package metadata detect a newer stable runtime without changing files' ($ffmpegUpdate.State -eq 'UpdateAvailable' -and $ffmpegUpdate.CurrentVersion -eq '9.0.2' -and $ffmpegUpdate.LatestPackageVersion -eq '10.0.0' -and $ffmpegUpdate.Message -like '*No library files were changed*')

$invalidRoot = Join-Path (Get-TestWork) 'invalid runtime manifest'
$invalidLibraryDir = Join-Path $invalidRoot 'External-Libraries'
[void](New-Item -ItemType Directory -Path $invalidLibraryDir -Force)
$invalidManifest = Get-ExternalLibraryManifest
$invalidManifest.Libraries[0].Architecture = 'mips'
[System.IO.File]::WriteAllText((Join-Path $invalidLibraryDir 'manifest.json'), ($invalidManifest | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
Set-AppRoot $invalidRoot
$rejected = $false
try { $null = Get-ExternalLibraryManifest } catch { $rejected = $true }
Assert-True 'manifest rejects an unsupported dependency architecture' $rejected

$invalidManifest.SchemaVersion = 99
[System.IO.File]::WriteAllText((Join-Path $invalidLibraryDir 'manifest.json'), ($invalidManifest | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
$rejected = $false
try { $null = Get-ExternalLibraryManifest } catch { $rejected = $true }
Assert-True 'manifest rejects an unsupported schema version' $rejected

Set-AppRoot $appRoot
