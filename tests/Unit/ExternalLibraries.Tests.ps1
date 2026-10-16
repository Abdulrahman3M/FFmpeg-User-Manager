# Unit tests: canonical external runtime manifest and metadata validation.
Set-TestGroup 'External library manifest'
$appRoot = Get-TestRoot
Set-AppRoot $appRoot

Set-TestGroup 'External library update transaction'

function New-ExternalSwapFixture {
    param([string]$Name)
    $base = Join-Path (Join-Path (Get-TestRoot) 'tests\output') ('external-swap-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
    $externalRoot = Join-Path $base 'External-Libraries'
    $active = Join-Path $externalRoot 'FFmpeg'
    $candidateRoot = Join-Path $externalRoot ('.stage-' + [guid]::NewGuid().ToString('N'))
    $candidate = Join-Path $candidateRoot 'FFmpeg'
    [void](New-Item -ItemType Directory -Path (Join-Path $active 'bin') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $candidate 'bin') -Force)
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $active 'bin') 'runtime.txt'), 'known-good')
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $candidate 'bin') 'runtime.txt'), 'candidate')
    $manifestPath = Join-Path $externalRoot 'manifest.json'
    $candidateManifestPath = Join-Path $candidateRoot 'manifest.json'
    [System.IO.File]::WriteAllText($manifestPath, 'old-manifest')
    [System.IO.File]::WriteAllText($candidateManifestPath, 'candidate-manifest')
    return [pscustomobject]@{ Base = $base; Active = $active; Candidate = $candidate; Manifest = $manifestPath; CandidateManifest = $candidateManifestPath }
}

function New-ExternalUpdateFixture {
    param([string]$Name)
    $base = Join-Path (Join-Path (Get-TestRoot) 'tests\output') ('external-update-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
    $externalRoot = Join-Path $base 'External-Libraries'
    $active = Join-Path $externalRoot 'FFmpeg'
    [void](New-Item -ItemType Directory -Path (Join-Path $active 'bin') -Force)
    [System.IO.File]::Copy((Join-Path (Join-Path (Get-TestRoot) 'External-Libraries') 'manifest.json'), (Join-Path $externalRoot 'manifest.json'), $true)
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $active 'bin') 'ffmpeg.exe'), 'old-runtime')
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $active 'bin') 'ffprobe.exe'), 'old-probe')
    return [pscustomobject]@{ Base = $base; ExternalRoot = $externalRoot; Active = $active }
}

function New-FFmpegUpdateArchive {
    param([string]$Base, [string]$Version, [switch]$InvalidLicense)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $packageRoot = Join-Path $Base 'package-source'
    $buildRoot = Join-Path $packageRoot ('ffmpeg-' + $Version + '-full_build-shared')
    $binRoot = Join-Path $buildRoot 'bin'
    [void](New-Item -ItemType Directory -Path $binRoot -Force)
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe', 'avcodec-99.dll')) { [System.IO.File]::WriteAllText((Join-Path $binRoot $name), ('candidate-' + $Version + '-' + $name)) }
    $licenseText = "                    GNU GENERAL PUBLIC LICENSE`r`n                       Version 3, 29 June 2007`r`n"
    if ($InvalidLicense) { $licenseText = 'MIT License' }
    $readmeText = "FFmpeg 64-bit shared Windows build from www.gyan.dev`r`n`r`nVersion: ${Version}-full_build-www.gyan.dev`r`n`r`nLicense: GPL v3`r`n"
    [System.IO.File]::WriteAllText((Join-Path $buildRoot 'LICENSE'), $licenseText)
    [System.IO.File]::WriteAllText((Join-Path $buildRoot 'README.txt'), $readmeText)
    $archivePath = Join-Path $Base ('ffmpeg-' + $Version + '-shared.zip')
    [System.IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $archivePath)
    return $archivePath
}

Set-ExternalLibraryHooks -Reset
$declinedDownloads = 0
Set-ExternalLibraryHooks -Download { $declinedDownloads++; throw 'A declined update must not download.' }
$declined = Update-BundledFFmpeg -PackageVersion '10.0.0' -Confirmed:$false
Assert-True 'declined FFmpeg update performs no download or file changes' ($declined.State -eq 'Declined' -and $declinedDownloads -eq 0)
Set-ExternalLibraryHooks -Reset

$fixture = New-ExternalSwapFixture -Name 'invalid-candidate'
$unchangedManifest = [System.IO.File]::ReadAllText($fixture.Manifest)
$invalidResult = Invoke-ExternalRuntimeSwap -ActivePath $fixture.Active -CandidatePath $fixture.Candidate -ActiveManifestPath $fixture.Manifest -CandidateManifestPath $fixture.CandidateManifest -ValidateCandidate { param($path) return $false } -ValidateActive { param($path) return $true }
Assert-True 'candidate verification failure leaves active runtime and manifest untouched' ($invalidResult.State -eq 'Rejected' -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'runtime.txt')) -eq 'known-good' -and [System.IO.File]::ReadAllText($fixture.Manifest) -eq $unchangedManifest -and (Test-Path -LiteralPath $fixture.Candidate))
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalSwapFixture -Name 'success'
$successResult = Invoke-ExternalRuntimeSwap -ActivePath $fixture.Active -CandidatePath $fixture.Candidate -ActiveManifestPath $fixture.Manifest -CandidateManifestPath $fixture.CandidateManifest -ValidateCandidate { param($path) return ([System.IO.File]::ReadAllText((Join-Path (Join-Path $path 'bin') 'runtime.txt')) -eq 'candidate') } -ValidateActive { param($path) return ([System.IO.File]::ReadAllText((Join-Path (Join-Path $path 'bin') 'runtime.txt')) -eq 'candidate') }
Assert-True 'successful runtime replacement activates candidate and retires old runtime only after validation' ($successResult.State -eq 'Updated' -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'runtime.txt')) -eq 'candidate' -and [System.IO.File]::ReadAllText($fixture.Manifest) -eq 'candidate-manifest' -and (-not $successResult.BackupPath -or -not (Test-Path -LiteralPath $successResult.BackupPath))) ($successResult | ConvertTo-Json -Compress)
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalSwapFixture -Name 'first-rename-failure'
$moveCalls = 0
Set-ExternalLibraryHooks -MoveDirectory { param($from, $to) $script:moveCalls++; if ($script:moveCalls -eq 1) { throw 'injected first rename failure' }; [System.IO.Directory]::Move($from, $to) }
$firstRenameResult = Invoke-ExternalRuntimeSwap -ActivePath $fixture.Active -CandidatePath $fixture.Candidate -ActiveManifestPath $fixture.Manifest -CandidateManifestPath $fixture.CandidateManifest -ValidateCandidate { param($path) return $true } -ValidateActive { param($path) return $true }
Assert-True 'first activation rename failure preserves current runtime and metadata' ($firstRenameResult.State -eq 'Failed' -and (Test-Path -LiteralPath $fixture.Active) -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'runtime.txt')) -eq 'known-good' -and [System.IO.File]::ReadAllText($fixture.Manifest) -eq 'old-manifest')
Set-ExternalLibraryHooks -Reset
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalSwapFixture -Name 'second-rename-failure'
$moveCalls = 0
Set-ExternalLibraryHooks -MoveDirectory { param($from, $to) $script:moveCalls++; if ($script:moveCalls -eq 2) { throw 'injected candidate activation failure' }; [System.IO.Directory]::Move($from, $to) }
$secondRenameResult = Invoke-ExternalRuntimeSwap -ActivePath $fixture.Active -CandidatePath $fixture.Candidate -ActiveManifestPath $fixture.Manifest -CandidateManifestPath $fixture.CandidateManifest -ValidateCandidate { param($path) return $true } -ValidateActive { param($path) return $true }
Assert-True 'second activation rename failure rolls back the known-good runtime and manifest' ($secondRenameResult.State -eq 'Failed' -and (Test-Path -LiteralPath $fixture.Active) -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'runtime.txt')) -eq 'known-good' -and [System.IO.File]::ReadAllText($fixture.Manifest) -eq 'old-manifest')
Set-ExternalLibraryHooks -Reset
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalSwapFixture -Name 'post-activation-failure'
$activeChecks = 0
$postActivationResult = Invoke-ExternalRuntimeSwap -ActivePath $fixture.Active -CandidatePath $fixture.Candidate -ActiveManifestPath $fixture.Manifest -CandidateManifestPath $fixture.CandidateManifest -ValidateCandidate { param($path) return $true } -ValidateActive { param($path) $script:activeChecks++; return ($script:activeChecks -eq 2) }
Assert-True 'post-activation verification failure restores the previous runtime and manifest' ($postActivationResult.State -eq 'Failed' -and (Test-Path -LiteralPath $fixture.Active) -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'runtime.txt')) -eq 'known-good' -and [System.IO.File]::ReadAllText($fixture.Manifest) -eq 'old-manifest')
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalSwapFixture -Name 'cleanup-failure'
Set-ExternalLibraryHooks -RemoveDirectory { param($path) throw 'injected backup cleanup failure' }
$cleanupResult = Invoke-ExternalRuntimeSwap -ActivePath $fixture.Active -CandidatePath $fixture.Candidate -ActiveManifestPath $fixture.Manifest -CandidateManifestPath $fixture.CandidateManifest -ValidateCandidate { param($path) return $true } -ValidateActive { param($path) return $true }
Assert-True 'backup cleanup failure never deletes or deactivates the validated active runtime' ($cleanupResult.State -eq 'UpdatedWithBackup' -and (Test-Path -LiteralPath $fixture.Active) -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'runtime.txt')) -eq 'candidate' -and (Test-Path -LiteralPath $cleanupResult.BackupPath)) ($cleanupResult | ConvertTo-Json -Compress)
Set-ExternalLibraryHooks -Reset
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalUpdateFixture -Name 'end-to-end-success'
$preparedArchive = New-FFmpegUpdateArchive -Base $fixture.Base -Version '10.0.0'
$archiveHash = (Get-FileHash -LiteralPath $preparedArchive -Algorithm SHA256).Hash
$script:updateMetadataFixture = [pscustomobject]@{ PackageId = 'Gyan.FFmpeg.Shared'; PackageVersion = '10.0.0'; Architecture = 'x64'; InstallerType = 'zip'; InstallerSha256 = $archiveHash; InstallerUrl = 'https://github.com/GyanD/codexffmpeg/releases/download/10.0.0/ffmpeg-10.0.0-shared.zip'; InstallerFileName = 'ffmpeg-10.0.0-shared.zip' }
$script:preparedArchiveFixture = $preparedArchive
$script:runtimeCheckFixture = $true
Set-AppRoot $fixture.Base
Set-ExternalLibraryHooks -PackageMetadata { param($version) return $script:updateMetadataFixture } -Download { param($version, $destination, $metadata) $targetArchive = Join-Path $destination $metadata.InstallerFileName; [System.IO.File]::Copy($script:preparedArchiveFixture, $targetArchive); return [pscustomobject]@{ Path = $targetArchive; ExitCode = 0; Started = $true; TimedOut = $false } } -RuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = [bool]$script:runtimeCheckFixture; Detail = 'mocked complete runtime verification' } }
$updateResult = Update-BundledFFmpeg -PackageVersion '10.0.0' -Confirmed:$true
$updatedManifest = Get-Content -LiteralPath (Join-Path $fixture.ExternalRoot 'manifest.json') -Raw | ConvertFrom-Json
$updatedFFmpeg = @($updatedManifest.Libraries | Where-Object { $_.Id -eq 'ffmpeg' }) | Select-Object -First 1
Assert-True 'WinGet package hash, runtime checks and manifest commit succeed as one FFmpeg update' ($updateResult.State -eq 'Updated' -and $updatedFFmpeg.CurrentVersion -eq '10.0.0' -and $updatedFFmpeg.PackageArchiveSha256 -eq $archiveHash.ToUpperInvariant() -and @($updatedFFmpeg.Files).Count -eq 3 -and (Test-Path -LiteralPath (Join-Path (Join-Path $fixture.Active 'LICENSES') 'COPYING.GPLv3')) -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'ffmpeg.exe')) -eq 'candidate-10.0.0-ffmpeg.exe') ($updateResult | ConvertTo-Json -Compress)
Set-ExternalLibraryHooks -Reset
Set-AppRoot $appRoot
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalUpdateFixture -Name 'candidate-runtime-failure'
$preparedArchive = New-FFmpegUpdateArchive -Base $fixture.Base -Version '10.0.0'
$archiveHash = (Get-FileHash -LiteralPath $preparedArchive -Algorithm SHA256).Hash
$script:updateMetadataFixture = [pscustomobject]@{ PackageId = 'Gyan.FFmpeg.Shared'; PackageVersion = '10.0.0'; Architecture = 'x64'; InstallerType = 'zip'; InstallerSha256 = $archiveHash; InstallerUrl = 'https://github.com/GyanD/codexffmpeg/releases/download/10.0.0/ffmpeg-10.0.0-shared.zip'; InstallerFileName = 'ffmpeg-10.0.0-shared.zip' }
$script:preparedArchiveFixture = $preparedArchive
$script:runtimeCheckFixture = $false
Set-AppRoot $fixture.Base
Set-ExternalLibraryHooks -PackageMetadata { param($version) return $script:updateMetadataFixture } -Download { param($version, $destination, $metadata) $targetArchive = Join-Path $destination $metadata.InstallerFileName; [System.IO.File]::Copy($script:preparedArchiveFixture, $targetArchive); return [pscustomobject]@{ Path = $targetArchive; ExitCode = 0; Started = $true; TimedOut = $false } } -RuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = [bool]$script:runtimeCheckFixture; Detail = 'injected capability failure' } }
$updateFailure = Update-BundledFFmpeg -PackageVersion '10.0.0' -Confirmed:$true
$unchangedUpdateManifest = Get-Content -LiteralPath (Join-Path $fixture.ExternalRoot 'manifest.json') -Raw | ConvertFrom-Json
Assert-True 'candidate runtime verification failure leaves the installed version and manifest unchanged' ($updateFailure.State -eq 'Failed' -and $unchangedUpdateManifest.Libraries[0].CurrentVersion -eq '9.0.2' -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'ffmpeg.exe')) -eq 'old-runtime') ($updateFailure | ConvertTo-Json -Compress)
Set-ExternalLibraryHooks -Reset
Set-AppRoot $appRoot
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalUpdateFixture -Name 'unapproved-license'
$preparedArchive = New-FFmpegUpdateArchive -Base $fixture.Base -Version '10.0.0' -InvalidLicense
$archiveHash = (Get-FileHash -LiteralPath $preparedArchive -Algorithm SHA256).Hash
$script:updateMetadataFixture = [pscustomobject]@{ PackageId = 'Gyan.FFmpeg.Shared'; PackageVersion = '10.0.0'; Architecture = 'x64'; InstallerType = 'zip'; InstallerSha256 = $archiveHash; InstallerUrl = 'https://github.com/GyanD/codexffmpeg/releases/download/10.0.0/ffmpeg-10.0.0-shared.zip'; InstallerFileName = 'ffmpeg-10.0.0-shared.zip' }
$script:preparedArchiveFixture = $preparedArchive
$script:runtimeCheckFixture = $true
Set-AppRoot $fixture.Base
Set-ExternalLibraryHooks -PackageMetadata { param($version) return $script:updateMetadataFixture } -Download { param($version, $destination, $metadata) $targetArchive = Join-Path $destination $metadata.InstallerFileName; [System.IO.File]::Copy($script:preparedArchiveFixture, $targetArchive); return [pscustomobject]@{ Path = $targetArchive; ExitCode = 0; Started = $true; TimedOut = $false } } -RuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = [bool]$script:runtimeCheckFixture; Detail = 'mocked runtime verification' } }
$licenseFailure = Update-BundledFFmpeg -PackageVersion '10.0.0' -Confirmed:$true
$licenseFailureManifest = Get-Content -LiteralPath (Join-Path $fixture.ExternalRoot 'manifest.json') -Raw | ConvertFrom-Json
Assert-True 'candidate package with a non-GPL or mismatched license is rejected before activation' ($licenseFailure.State -eq 'Failed' -and $licenseFailureManifest.Libraries[0].CurrentVersion -eq '9.0.2' -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'ffmpeg.exe')) -eq 'old-runtime') ($licenseFailure | ConvertTo-Json -Compress)
Set-ExternalLibraryHooks -Reset
Set-AppRoot $appRoot
[System.IO.Directory]::Delete($fixture.Base, $true)

$fixture = New-ExternalUpdateFixture -Name 'cancelled-download'
$script:updateMetadataFixture = [pscustomobject]@{ PackageId = 'Gyan.FFmpeg.Shared'; PackageVersion = '10.0.0'; Architecture = 'x64'; InstallerType = 'zip'; InstallerSha256 = ('A' * 64); InstallerUrl = 'https://github.com/GyanD/codexffmpeg/releases/download/10.0.0/ffmpeg-10.0.0-full_build-shared.zip'; InstallerFileName = 'ffmpeg-10.0.0-full_build-shared.zip' }
Set-AppRoot $fixture.Base
Set-ExternalLibraryHooks -PackageMetadata { param($version) return $script:updateMetadataFixture } -Download { param($version, $destination, $metadata) return [pscustomobject]@{ Path = ''; ExitCode = -1; Started = $true; TimedOut = $false; Cancelled = $true } }
$cancelledUpdate = Update-BundledFFmpeg -PackageVersion '10.0.0' -Confirmed:$true
$cancelledStage = @(Get-ChildItem -LiteralPath $fixture.ExternalRoot -Directory -Force | Where-Object { $_.Name -like '.stage-*' })
Assert-True 'cancelling WinGet during staging leaves the current runtime and manifest intact and cleans temporary files' ($cancelledUpdate.State -eq 'Cancelled' -and [System.IO.File]::ReadAllText((Join-Path (Join-Path $fixture.Active 'bin') 'ffmpeg.exe')) -eq 'old-runtime' -and (Get-Content (Join-Path $fixture.ExternalRoot 'manifest.json') -Raw | ConvertFrom-Json).Libraries[0].CurrentVersion -eq '9.0.2' -and $cancelledStage.Count -eq 0)
Set-ExternalLibraryHooks -Reset
Set-AppRoot $appRoot
[System.IO.Directory]::Delete($fixture.Base, $true)

$script:flowStatusFixture = @([pscustomobject]@{ Id = 'ffmpeg'; Name = 'FFmpeg'; CurrentVersion = '9.0.2'; LatestVersion = '10.0.0'; PackageVersion = '9.0.2'; LatestPackageVersion = '10.0.0'; State = 'UpdateAvailable'; Source = 'official FFmpeg and WinGet metadata'; Message = 'update available' })
$script:flowDownloadCalls = 0
Set-ExternalLibraryHooks -Download { $script:flowDownloadCalls++; throw 'The Keep option must not download.' }
$flowAction = { Invoke-ExternalLibraryUpdateFlow -Statuses $script:flowStatusFixture }.GetNewClosure()
$flowUi = Invoke-Ui -Action $flowAction -Keys '02'
Assert-True 'bundled FFmpeg update is a numbered, described, explicit opt-in and Keep performs no download' ($flowUi.Output.Contains('01') -and $flowUi.Output.Contains('02') -and $flowUi.Output.Contains('Download and update bundled FFmpeg') -and $flowUi.Output.Contains('Keep the current FFmpeg version') -and $flowUi.Output.Contains('Explicitly authorizes downloading package') -and $script:flowDownloadCalls -eq 0)
Set-ExternalLibraryHooks -Reset

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
$wingetInstallerYaml = @'
PackageIdentifier: Gyan.FFmpeg.Shared
PackageVersion: 9.0.2
InstallerType: zip
Installers:
- Architecture: x64
  InstallerUrl: https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-full_build-shared.zip
  InstallerSha256: 8D31E162F1616E37AAB3FA2DB991B97E1B8DBEB1C8465FD81A81BE16FF91B328
'@
$wingetInstallerSource = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/g/Gyan/FFmpeg/Shared/9.0.2/Gyan.FFmpeg.Shared.installer.yaml'
$parsedInstaller = ConvertFrom-FFmpegWingetInstallerManifest -Yaml $wingetInstallerYaml -PackageVersion '9.0.2' -MetadataSource $wingetInstallerSource
Assert-True 'WinGet installer metadata parser pins official source, package, x64 ZIP filename and SHA-256' ($parsedInstaller.PackageId -eq 'Gyan.FFmpeg.Shared' -and $parsedInstaller.InstallerFileName -eq 'ffmpeg-9.0.2-full_build-shared.zip' -and $parsedInstaller.InstallerSha256 -eq '8D31E162F1616E37AAB3FA2DB991B97E1B8DBEB1C8465FD81A81BE16FF91B328' -and $parsedInstaller.MetadataSource -eq $wingetInstallerSource)
$rejectedInstallerYaml = $wingetInstallerYaml.Replace('Gyan.FFmpeg.Shared', 'Other.Package')
$rejectedInstallerManifest = $false
try { $null = ConvertFrom-FFmpegWingetInstallerManifest -Yaml $rejectedInstallerYaml -PackageVersion '9.0.2' -MetadataSource $wingetInstallerSource } catch { $rejectedInstallerManifest = $true }
Assert-True 'WinGet installer metadata parser rejects a mismatched package identity' $rejectedInstallerManifest
$rejectedInstallerSource = $false
try { $null = ConvertFrom-FFmpegWingetInstallerManifest -Yaml $wingetInstallerYaml -PackageVersion '9.0.2' -MetadataSource 'https://example.invalid/installer.yaml' } catch { $rejectedInstallerSource = $true }
Assert-True 'WinGet installer metadata parser rejects an untrusted metadata source' $rejectedInstallerSource

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
