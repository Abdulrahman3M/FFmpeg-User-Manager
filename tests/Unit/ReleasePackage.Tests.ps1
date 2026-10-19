# Unit tests: deterministic Full/Lite release packages and runtime validation.
Set-TestGroup 'Full and Lite release packages'
$releasePackageModule = Join-Path (Get-TestRoot) 'tools/ReleasePackage.psm1'
$releaseModuleLoaded = $false
try { Import-Module -Name $releasePackageModule -Force -ErrorAction Stop; $releaseModuleLoaded = $true } catch { }
Assert-True 'release builder module exposes the edition package API' $releaseModuleLoaded
if (-not $releaseModuleLoaded) { return }

function New-ReleasePackagePeFixture {
    param([ValidateSet('x64', 'x86')][string]$Architecture = 'x64')
    $bytes = New-Object byte[] 256
    $bytes[0] = 0x4D; $bytes[1] = 0x5A; $bytes[60] = 0x80
    $bytes[128] = 0x50; $bytes[129] = 0x45
    if ($Architecture -eq 'x64') { $bytes[132] = 0x64; $bytes[133] = 0x86 }
    else { $bytes[132] = 0x4C; $bytes[133] = 0x01 }
    return ,$bytes
}

function Set-ReleasePackageFixtureFile {
    param([string]$Root, [string]$RelativePath, [byte[]]$Bytes)
    $path = Join-Path $Root ($RelativePath -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
    $parent = [System.IO.Path]::GetDirectoryName($path)
    if (-not [System.IO.Directory]::Exists($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [System.IO.File]::WriteAllBytes($path, $Bytes)
    return $path
}

function Read-ReleasePackageEntryText {
    param([System.IO.Compression.ZipArchive]$Archive, [string]$Name)
    $entry = @($Archive.Entries | Where-Object { $_.FullName -eq $Name }) | Select-Object -First 1
    if (-not $entry) { return '' }
    $stream = $entry.Open(); $reader = New-Object System.IO.StreamReader($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
}

function New-ReleasePackageFixture {
    $root = Join-Path (Get-TestWork) ('release fixture ' + [char]0x03A9)
    $templateRoot = Get-TestRoot
    foreach ($file in @('FFmpeg-User-Manager.bat', 'Start-FFmpegTUI.ps1', 'VERSION', 'README.md', 'CHANGELOG.md', 'LICENSE', 'NOTICE')) {
        $source = Join-Path $templateRoot $file
        $destination = Join-Path $root $file
        [void](New-Item -ItemType Directory -Path $root -Force)
        [System.IO.File]::Copy($source, $destination, $true)
    }
    [System.IO.File]::Copy((Join-Path $templateRoot 'THIRD-PARTY-NOTICES.md'), (Join-Path $root 'THIRD-PARTY-NOTICES.md'))
    foreach ($directory in @('config', 'src', 'src/Core', 'docs')) { [void](New-Item -ItemType Directory -Path (Join-Path $root $directory) -Force) }
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $root 'config') 'defaults.json'), '{}')
    [System.IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $root 'src') 'Core') 'App.psm1'), '# test entry')
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $root 'docs') 'User.md'), '# User docs')
    [void](New-Item -ItemType Directory -Path (Join-Path (Join-Path $root 'External-Libraries') 'Assimp') -Force)
    [System.IO.File]::Copy((Join-Path (Join-Path $templateRoot 'External-Libraries') 'README.md'), (Join-Path (Join-Path $root 'External-Libraries') 'README.md'))
    $manifest = Get-Content -LiteralPath (Join-Path (Join-Path $templateRoot 'External-Libraries') 'manifest.json') -Raw | ConvertFrom-Json
    $ffmpeg = @($manifest.Libraries | Where-Object { $_.Id -eq 'ffmpeg' }) | Select-Object -First 1
    $assimp = @($manifest.Libraries | Where-Object { $_.Id -eq 'assimp' }) | Select-Object -First 1
    $ffmpegRoot = Join-Path (Get-TestWork) ('release FFmpeg source ' + [char]0x03A9)
    $ffmpegBin = Join-Path $ffmpegRoot 'bin'
    [void](New-Item -ItemType Directory -Path $ffmpegBin -Force)
    $ffmpegFiles = @()
    foreach ($record in @($ffmpeg.Files)) {
        $relative = ([string]$record.Path -replace '^FFmpeg/', '')
        $path = Set-ReleasePackageFixtureFile -Root $ffmpegRoot -RelativePath $relative -Bytes (New-ReleasePackagePeFixture)
        $ffmpegFiles += , ([pscustomobject]@{ Path = [string]$record.Path; Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant(); Bytes = (Get-Item -LiteralPath $path).Length })
    }
    $ffmpeg.Files = $ffmpegFiles
    [System.IO.File]::WriteAllText((Join-Path $ffmpegRoot 'LICENSE'), "GNU GENERAL PUBLIC LICENSE`r`nVersion 3, 29 June 2007`r`n")
    [System.IO.File]::WriteAllText((Join-Path $ffmpegRoot 'README.txt'), "FFmpeg shared x64 test build`r`nVersion: $($ffmpeg.CurrentVersion)-full_build-www.gyan.dev`r`nLicense: GPL v3`r`n")
    $assimpFiles = @()
    foreach ($record in @($assimp.Files)) {
        $path = Set-ReleasePackageFixtureFile -Root (Join-Path $root 'External-Libraries') -RelativePath ([string]$record.Path) -Bytes (New-ReleasePackagePeFixture)
        $assimpFiles += , ([pscustomobject]@{ Path = [string]$record.Path; Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() })
    }
    $assimp.Files = $assimpFiles
    foreach ($runtimePackage in @($assimp.RuntimePackages)) {
        $null = Set-ReleasePackageFixtureFile -Root (Join-Path $root 'External-Libraries') -RelativePath ([string]$runtimePackage.LicenseFile) -Bytes ([System.Text.Encoding]::ASCII.GetBytes(('Fixture license: ' + [string]$runtimePackage.License)))
    }
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $root 'External-Libraries') 'manifest.json'), ($manifest | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))
    return [pscustomobject]@{ Root = $root; FFmpegSource = $ffmpegRoot; Version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1).Trim(); SourceRevision = ('a' * 40) }
}

$fixture = New-ReleasePackageFixture
Set-AppRoot $fixture.Root
Set-ReleasePackageHooks -Reset
Set-ReleasePackageHooks -FFmpegRuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = $true; Detail = 'fixture runtime validated'; Version = $version; Architecture = 'x64'; BuildConfiguration = '--enable-gpl --enable-version3 --enable-shared --enable-libssh' } } -AssimpRuntimeCheck { param($assimpPath) return [pscustomobject]@{ Available = $true; Reason = ''; Path = $assimpPath } }
$testPackageOutputBase = Join-Path (Join-Path (Get-TestRoot) 'tests/output') ('release-package-tests-' + [guid]::NewGuid().ToString('N'))
$outputOne = Join-Path $testPackageOutputBase 'packages one'
$build = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory $outputOne -Edition Both -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision
$expectedFullName = 'FFmpeg-User-Manager-v' + $fixture.Version + '-Full-Windows-x64.zip'
$expectedLiteName = 'FFmpeg-User-Manager-v' + $fixture.Version + '-Lite-Windows-x64.zip'
Assert-True 'Both mode builds exact Full and Lite package names plus a versioned SHA-256 manifest' (@($build.Packages).Count -eq 2 -and [System.IO.Path]::GetFileName($build.Packages[0]) -eq $expectedFullName -and [System.IO.Path]::GetFileName($build.Packages[1]) -eq $expectedLiteName -and (Test-Path -LiteralPath $build.ChecksumPath -PathType Leaf) -and [System.IO.Path]::GetFileName($build.ChecksumPath) -eq ('SHA256SUMS-v' + $fixture.Version + '.txt')) ($build | ConvertTo-Json -Compress)

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
$fullArchive = [System.IO.Compression.ZipFile]::OpenRead($build.Packages[0])
$liteArchive = [System.IO.Compression.ZipFile]::OpenRead($build.Packages[1])
try {
    $fullNames = @($fullArchive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    $liteNames = @($liteArchive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    Assert-True 'Full contains both runtimes and their licenses while Lite excludes runtime binaries' (($fullNames -contains 'FFmpeg-User-Manager/External-Libraries/FFmpeg/bin/ffmpeg.exe') -and ($fullNames -contains 'FFmpeg-User-Manager/External-Libraries/FFmpeg/bin/ffprobe.exe') -and ($fullNames -contains 'FFmpeg-User-Manager/External-Libraries/FFmpeg/LICENSES/COPYING.GPLv3') -and ($fullNames -contains 'FFmpeg-User-Manager/External-Libraries/Assimp/bin/assimp.exe') -and @($liteNames | Where-Object { $_ -match 'External-Libraries/(FFmpeg|Assimp)/.*\.(exe|dll)$' }).Count -eq 0)
    $ffmpegSourceInfo = Read-ReleasePackageEntryText -Archive $fullArchive -Name 'FFmpeg-User-Manager/External-Libraries/FFmpeg/SOURCE.txt'
    Assert-True 'Full records the exact upstream FFmpeg source revision and runtime-reported required build flags' (($ffmpegSourceInfo -match '(?m)^UpstreamSourceRevision: 946fcce07b\r?$') -and ($ffmpegSourceInfo -match '(?m)^BuildConfiguration: .*--enable-gpl.*--enable-version3.*--enable-shared.*--enable-libssh')) ('FFmpeg SOURCE.txt: ' + ($ffmpegSourceInfo -replace "`r?`n", '|'))
    Assert-True 'both editions include the third-party inventory and Lite has no runtime source/license payloads' (($fullNames -contains 'FFmpeg-User-Manager/THIRD-PARTY-NOTICES.md') -and ($liteNames -contains 'FFmpeg-User-Manager/THIRD-PARTY-NOTICES.md') -and @($liteNames | Where-Object { $_ -match 'External-Libraries/(FFmpeg|Assimp)/' }).Count -eq 0)
    Assert-True 'packages omit Git, tests, tools, development plans, caches, and staging paths' ((@($fullNames + $liteNames | Where-Object { $_ -match '(^|/)(\.git|tests|tools|dist|\.superpowers|\.cache|\.stage[^/]*)(/|$)' }).Count -eq 0) -and (@($fullNames | Where-Object { $_ -match 'ffplay\.exe$' }).Count -eq 0))
    $fullBuildInfo = Read-ReleasePackageEntryText -Archive $fullArchive -Name 'FFmpeg-User-Manager/BUILD-INFO.txt'
    $liteBuildInfo = Read-ReleasePackageEntryText -Archive $liteArchive -Name 'FFmpeg-User-Manager/BUILD-INFO.txt'
    $fullSourceHash = (((@($fullBuildInfo -split "`r?`n" | Where-Object { $_ -match '^SourceTreeSha256:' })[0]) -replace '^SourceTreeSha256: ', '')).Trim()
    $liteSourceHash = (((@($liteBuildInfo -split "`r?`n" | Where-Object { $_ -match '^SourceTreeSha256:' })[0]) -replace '^SourceTreeSha256: ', '')).Trim()
    Assert-True 'Full and Lite record the same canonical version, source revision, and source-tree fingerprint' (($fullBuildInfo -match ('(?m)^Version: ' + [regex]::Escape($fixture.Version) + '\r?$')) -and ($liteBuildInfo -match ('(?m)^Version: ' + [regex]::Escape($fixture.Version) + '\r?$')) -and ($fullBuildInfo -match ('(?m)^SourceRevision: ' + [regex]::Escape($fixture.SourceRevision) + '\r?$')) -and ($liteBuildInfo -match ('(?m)^SourceRevision: ' + [regex]::Escape($fixture.SourceRevision) + '\r?$')) -and ($fullBuildInfo -match '(?m)^Edition: Full\r?$') -and ($liteBuildInfo -match '(?m)^Edition: Lite\r?$') -and ($fullSourceHash -match '^[0-9a-f]{64}$') -and ($liteSourceHash -ceq $fullSourceHash)) ('Full: ' + ($fullBuildInfo -replace "`r?`n", '|') + ' Lite: ' + ($liteBuildInfo -replace "`r?`n", '|'))
    $orderedPaths = [string[]]@($fullArchive.Entries | ForEach-Object { $_.FullName })
    $sortedPaths = [string[]]$orderedPaths.Clone(); [System.Array]::Sort($sortedPaths, [StringComparer]::Ordinal)
    $entryOrderMatches = ([string]::Join('|', $orderedPaths) -ceq [string]::Join('|', $sortedPaths))
    $incorrectTimestamps = @($fullArchive.Entries | Where-Object { $_.LastWriteTime.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') -ne '1980-01-01T00:00:00' })
    Assert-True 'ZIP entries use stable ordinal path order and fixed timestamps' ($entryOrderMatches -and $incorrectTimestamps.Count -eq 0) ('ordered=' + $entryOrderMatches + '; bad timestamps=' + $incorrectTimestamps.Count + '; first=' + $(if ($incorrectTimestamps.Count -gt 0) { $incorrectTimestamps[0].LastWriteTime.ToString('o') } else { 'none' }))
} finally { $fullArchive.Dispose(); $liteArchive.Dispose() }

$checksums = Get-Content -LiteralPath $build.ChecksumPath
Assert-True 'checksum file contains the exact SHA-256 of each package' ($checksums.Count -eq 2 -and $checksums[0] -match ('^[0-9a-f]{64}  ' + [regex]::Escape($expectedFullName) + '$') -and $checksums[1] -match ('^[0-9a-f]{64}  ' + [regex]::Escape($expectedLiteName) + '$') -and $checksums[0].Substring(0, 64) -eq (Get-FileHash -LiteralPath $build.Packages[0] -Algorithm SHA256).Hash.ToLowerInvariant() -and $checksums[1].Substring(0, 64) -eq (Get-FileHash -LiteralPath $build.Packages[1] -Algorithm SHA256).Hash.ToLowerInvariant())

$outputTwo = Join-Path $testPackageOutputBase 'packages two'
$buildAgain = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory $outputTwo -Edition Both -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision
Assert-True 'repeated builds from the same source produce byte-identical Full and Lite archives' ((Get-FileHash -LiteralPath $build.Packages[0] -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $buildAgain.Packages[0] -Algorithm SHA256).Hash -and (Get-FileHash -LiteralPath $build.Packages[1] -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $buildAgain.Packages[1] -Algorithm SHA256).Hash)

$collisionSentinel = 'preserve existing output'
[System.IO.File]::WriteAllText($build.Packages[0], $collisionSentinel)
$collisionRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory $outputOne -Edition Both -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $collisionRejected = $true }
Assert-True 'existing package files are never overwritten' ($collisionRejected -and [System.IO.File]::ReadAllText($build.Packages[0]) -eq $collisionSentinel)

$wrongHashPath = Join-Path $fixture.FFmpegSource 'bin/ffprobe.exe'
[System.IO.File]::WriteAllBytes($wrongHashPath, (New-ReleasePackagePeFixture -Architecture x86))
$hashMismatchRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'bad runtime hash') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $hashMismatchRejected = $true }
Assert-True 'Full build rejects runtime files whose hashes or architecture do not match the manifest' $hashMismatchRejected

$fixtureManifestPath = Join-Path (Join-Path $fixture.Root 'External-Libraries') 'manifest.json'
$fixtureManifest = Get-Content -LiteralPath $fixtureManifestPath -Raw | ConvertFrom-Json
$fixtureFFmpeg = @($fixtureManifest.Libraries | Where-Object { $_.Id -eq 'ffmpeg' }) | Select-Object -First 1
$sizeRecord = @($fixtureFFmpeg.Files | Where-Object { $_.Path -eq 'FFmpeg/bin/ffmpeg.exe' }) | Select-Object -First 1
$actualRuntimeBytes = (Get-Item -LiteralPath (Join-Path $fixture.FFmpegSource 'bin/ffmpeg.exe')).Length
$sizeRecord.Bytes = $actualRuntimeBytes + 1
[System.IO.File]::WriteAllText($fixtureManifestPath, ($fixtureManifest | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))
$sizeMismatchRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'bad runtime size') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $sizeMismatchRejected = $_.Exception.Message -match 'size does not match' }
Assert-True 'Full build rejects a runtime file whose manifest byte count is stale even when its hash matches' $sizeMismatchRejected
$sizeRecord.Bytes = $actualRuntimeBytes
[System.IO.File]::WriteAllText($fixtureManifestPath, ($fixtureManifest | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))

$wrongArchitecturePath = Join-Path $fixture.FFmpegSource 'bin/ffprobe.exe'
[System.IO.File]::WriteAllBytes($wrongArchitecturePath, (New-ReleasePackagePeFixture -Architecture x86))
$wrongArchitectureHash = (Get-FileHash -LiteralPath $wrongArchitecturePath -Algorithm SHA256).Hash
foreach ($record in @($fixtureFFmpeg.Files)) { if ($record.Path -eq 'FFmpeg/bin/ffprobe.exe') { $record.Sha256 = $wrongArchitectureHash; $record.Bytes = (Get-Item -LiteralPath $wrongArchitecturePath).Length } }
[System.IO.File]::WriteAllText($fixtureManifestPath, ($fixtureManifest | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))
$architectureMismatchRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'wrong runtime architecture') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $architectureMismatchRejected = $_.Exception.Message -match 'architecture mismatch' }
Assert-True 'Full build rejects a manifest-consistent runtime file with the wrong PE architecture' $architectureMismatchRejected
[System.IO.File]::WriteAllBytes($wrongArchitecturePath, (New-ReleasePackagePeFixture))
$fixtureFFmpeg.Files = @($fixtureFFmpeg.Files | ForEach-Object { if ($_.Path -eq 'FFmpeg/bin/ffprobe.exe') { $p = Join-Path $fixture.FFmpegSource 'bin/ffprobe.exe'; [pscustomobject]@{ Path = $_.Path; Sha256 = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant(); Bytes = (Get-Item -LiteralPath $p).Length } } else { $_ } })
[System.IO.File]::WriteAllText($fixtureManifestPath, ($fixtureManifest | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))

$unapprovedPath = Join-Path (Join-Path $fixture.FFmpegSource 'bin') 'unapproved.exe'
[System.IO.File]::WriteAllBytes($unapprovedPath, (New-ReleasePackagePeFixture))
$unapprovedRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'unapproved runtime file') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $unapprovedRejected = $_.Exception.Message -match 'unapproved runtime file' }
Assert-True 'Full build rejects an unapproved runtime executable rather than silently including it' $unapprovedRejected
[System.IO.File]::Delete($unapprovedPath)

$runtimeCheckReady = $false
Set-ReleasePackageHooks -FFmpegRuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = $false; Detail = 'injected capability failure' } }
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'runtime self-check failure') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $runtimeCheckReady = $_.Exception.Message -match 'self-check' }
Assert-True 'Full build stops when the canonical FFmpeg runtime self-check fails' $runtimeCheckReady
Set-ReleasePackageHooks -FFmpegRuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = $true; Detail = 'fixture runtime validated'; Version = $version; Architecture = 'x64'; BuildConfiguration = '--enable-gpl --enable-version3 --enable-shared --enable-libssh' } }

Set-ReleasePackageHooks -FFmpegRuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = $true; Detail = 'fixture runtime validated'; Version = $version; Architecture = 'x64'; BuildConfiguration = '' } }
$missingBuildConfigurationRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'missing build configuration') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $missingBuildConfigurationRejected = $_.Exception.Message -match 'buildconf' }
Assert-True 'Full build rejects missing runtime-reported build configuration metadata' $missingBuildConfigurationRejected
Set-ReleasePackageHooks -FFmpegRuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = $true; Detail = 'fixture runtime validated'; Version = $version; Architecture = 'x64'; BuildConfiguration = '--enable-gpl --enable-version3 --enable-shared --enable-libssh' } }

$missingLicense = Join-Path $fixture.FFmpegSource 'LICENSE'
$savedLicense = [System.IO.File]::ReadAllText($missingLicense)
[System.IO.File]::Delete($missingLicense)
$missingLicenseRejected = $false
try { $null = New-ReleasePackages -ProjectRoot $fixture.Root -OutputDirectory (Join-Path $testPackageOutputBase 'missing license') -Edition Full -FFmpegRuntimeSource $fixture.FFmpegSource -SourceRevision $fixture.SourceRevision } catch { $missingLicenseRejected = $true }
Assert-True 'Full build rejects a missing upstream license rather than producing an incomplete package' $missingLicenseRejected
[System.IO.File]::WriteAllText($missingLicense, $savedLicense)

$acquireRoot = Join-Path (Get-TestWork) 'winget release archive fixture'
$acquireBuildRoot = Join-Path $acquireRoot 'ffmpeg-9.0.2-full_build-shared'
[void](New-Item -ItemType Directory -Path $acquireBuildRoot -Force)
Copy-Item -LiteralPath (Join-Path $fixture.FFmpegSource 'bin') -Destination $acquireBuildRoot -Recurse
Copy-Item -LiteralPath (Join-Path $fixture.FFmpegSource 'LICENSE') -Destination $acquireBuildRoot
Copy-Item -LiteralPath (Join-Path $fixture.FFmpegSource 'README.txt') -Destination $acquireBuildRoot
$archivePath = Join-Path (Get-TestWork) 'ffmpeg-9.0.2-full_build-shared.zip'
[System.IO.Compression.ZipFile]::CreateFromDirectory($acquireRoot, $archivePath)
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
$fixtureManifest = Get-Content -LiteralPath $fixtureManifestPath -Raw | ConvertFrom-Json
$fixtureFFmpeg = @($fixtureManifest.Libraries | Where-Object { $_.Id -eq 'ffmpeg' }) | Select-Object -First 1
$fixtureFFmpeg.PackageArchiveSha256 = $archiveHash
[System.IO.File]::WriteAllText($fixtureManifestPath, ($fixtureManifest | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))
$script:releaseArchiveFixture = $archivePath
$script:releaseInstallerMetadataFixture = [pscustomobject]@{ PackageId = 'Gyan.FFmpeg.Shared'; PackageVersion = [string]$fixtureFFmpeg.PackageVersion; Architecture = 'x64'; InstallerType = 'zip'; InstallerSha256 = $archiveHash; InstallerUrl = 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-full_build-shared.zip'; InstallerFileName = 'ffmpeg-9.0.2-full_build-shared.zip' }
$script:releaseArchiveDownloadCount = 0
Set-ExternalLibraryHooks -Reset
Set-ExternalLibraryHooks -PackageMetadata { param($version) return $script:releaseInstallerMetadataFixture } -Download { param($version, $destination, $metadata) $script:releaseArchiveDownloadCount++; $downloadPath = Join-Path (Join-Path $destination 'Gyan.FFmpeg.Shared_9.0.2') 'FFmpeg (Shared)_9.0.2_X64_portable_en-US.zip'; [void](New-Item -ItemType Directory -Path (Split-Path -Parent $downloadPath) -Force); [System.IO.File]::Copy($script:releaseArchiveFixture, $downloadPath); return [pscustomobject]@{ Path = $downloadPath; ExitCode = 0; Started = $true; TimedOut = $false } } -RuntimeCheck { param($ffmpegPath, $ffprobePath, $version) return [pscustomobject]@{ Ready = $true; Detail = 'fixture runtime validated'; Version = $version; Architecture = 'x64' } }
$declinedAcquire = Get-VerifiedFFmpegRuntimeForPackaging -Destination (Join-Path $testPackageOutputBase 'declined acquisition')
Assert-True 'release package acquisition requires explicit opt-in before any WinGet download' ($declinedAcquire.State -eq 'Declined' -and $script:releaseArchiveDownloadCount -eq 0)
$acquiredDestination = Join-Path $testPackageOutputBase 'verified acquisition'
$acquiredRuntime = Get-VerifiedFFmpegRuntimeForPackaging -Destination $acquiredDestination -Confirmed
Assert-True 'explicit package acquisition verifies pinned archive, licenses, file inventory, version and capabilities without replacing the active runtime' ($acquiredRuntime.Ready -and $acquiredRuntime.State -eq 'Ready' -and $acquiredRuntime.Version -eq '9.0.2' -and $script:releaseArchiveDownloadCount -eq 1 -and (Test-Path -LiteralPath (Join-Path (Join-Path $acquiredRuntime.Path 'bin') 'ffprobe.exe'))) (($acquiredRuntime | ConvertTo-Json -Compress) + ' downloads=' + $script:releaseArchiveDownloadCount)
if ([System.IO.Directory]::Exists($acquiredDestination)) { [System.IO.Directory]::Delete($acquiredDestination, $true) }
Set-ExternalLibraryHooks -Reset

Set-ReleasePackageHooks -Reset
Set-AppRoot (Get-TestRoot)
$restoredRuntime = Find-FFmpegInstallation
Assert-True 'release-package tests restore the detected FFmpeg runtime for later suites' ($restoredRuntime.Status -eq 'Ready' -and (Get-FFmpegPath) -eq $restoredRuntime.Ffmpeg)
if ([System.IO.Directory]::Exists($testPackageOutputBase)) { [System.IO.Directory]::Delete($testPackageOutputBase, $true) }
