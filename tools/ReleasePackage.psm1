# ReleasePackage.psm1 - deterministic Full/Lite Windows package builder.
Set-StrictMode -Version 2.0

$script:ReleasePackageHooks = @{ FFmpegRuntimeCheck = $null; AssimpRuntimeCheck = $null }

function Set-ReleasePackageHooks {
    param([scriptblock]$FFmpegRuntimeCheck, [scriptblock]$AssimpRuntimeCheck, [switch]$Reset)
    if ($Reset) { $script:ReleasePackageHooks = @{ FFmpegRuntimeCheck = $null; AssimpRuntimeCheck = $null }; return }
    if ($FFmpegRuntimeCheck) { $script:ReleasePackageHooks.FFmpegRuntimeCheck = $FFmpegRuntimeCheck }
    if ($AssimpRuntimeCheck) { $script:ReleasePackageHooks.AssimpRuntimeCheck = $AssimpRuntimeCheck }
}

function Get-ReleasePackageVersion {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $versionPath = Join-Path $ProjectRoot 'VERSION'
    if (-not [System.IO.File]::Exists($versionPath)) { throw 'The canonical VERSION file is missing.' }
    $version = ([System.IO.File]::ReadAllLines($versionPath)[0]).Trim()
    if (-not (Test-SemVer $version)) { throw "VERSION does not contain a valid Semantic Version: '$version'" }
    return $version
}

function Get-ReleaseProjectRevision {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $result = Invoke-ExternalCapture -FilePath 'git' -Arguments @('-C', $ProjectRoot, 'rev-parse', '--verify', 'HEAD') -TimeoutSec 15
    $revision = ([string]$result.StdOut).Trim()
    if (-not $result.Started -or $result.ExitCode -ne 0 -or $revision -notmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64})$') { throw 'The project source revision could not be resolved to a full Git commit.' }
    return $revision.ToLowerInvariant()
}

function Sort-ReleaseItemsByPath {
    param([Parameter(Mandatory)][object[]]$Items, [Parameter(Mandatory)][string]$PropertyName)
    $lookup = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $Items) {
        $itemPath = [string]$item.$PropertyName
        if ($lookup.ContainsKey($itemPath)) { throw ('Duplicate release package path: ' + $itemPath) }
        $lookup.Add($itemPath, $item)
        $paths.Add($itemPath)
    }
    $orderedPaths = [string[]]$paths.ToArray()
    [System.Array]::Sort($orderedPaths, [StringComparer]::Ordinal)
    $orderedItems = New-Object System.Collections.Generic.List[object]
    foreach ($itemPath in $orderedPaths) { $orderedItems.Add($lookup[$itemPath]) }
    return $orderedItems.ToArray()
}

function Get-ReleasePackageSourceFiles {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($relative in @('FFmpeg-User-Manager.bat', 'Start-FFmpegTUI.ps1', 'VERSION', 'README.md', 'CHANGELOG.md', 'LICENSE', 'NOTICE')) {
        $path = Join-Path $ProjectRoot $relative
        if (-not [System.IO.File]::Exists($path)) { throw ('Required distribution file is missing: ' + $relative) }
        $files.Add([pscustomobject]@{ Path = $relative.Replace('\', '/'); FullName = $path })
    }
    $thirdPartyNotices = Join-Path $ProjectRoot 'THIRD-PARTY-NOTICES.md'
    if ([System.IO.File]::Exists($thirdPartyNotices)) { $files.Add([pscustomobject]@{ Path = 'THIRD-PARTY-NOTICES.md'; FullName = $thirdPartyNotices }) }
    foreach ($directory in @('config', 'src', 'docs')) {
        $source = Join-Path $ProjectRoot $directory
        if (-not [System.IO.Directory]::Exists($source)) { throw ('Required distribution directory is missing: ' + $directory) }
        foreach ($file in @(Get-ChildItem -LiteralPath $source -File -Recurse | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($source.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
            if ($directory -eq 'docs' -and $relative -match '^(?:superpowers|_drafts)/') { continue }
            $files.Add([pscustomobject]@{ Path = ($directory + '/' + $relative); FullName = $file.FullName })
        }
    }
    foreach ($relative in @('External-Libraries/README.md', 'External-Libraries/manifest.json')) {
        $path = Join-Path $ProjectRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
        if (-not [System.IO.File]::Exists($path)) { throw ('Required dependency metadata is missing: ' + $relative) }
        $files.Add([pscustomobject]@{ Path = $relative; FullName = $path })
    }
    return @(Sort-ReleaseItemsByPath -Items $files.ToArray() -PropertyName 'Path')
}

function Get-ReleaseSourceTreeSha256 {
    param([Parameter(Mandatory)][object[]]$Files)
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        foreach ($file in $Files) {
            $pathBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$file.Path)
            $contentHash = [System.Security.Cryptography.SHA256]::Create()
            $fileStream = $null
            try { $fileStream = [System.IO.File]::OpenRead([string]$file.FullName); $hashBytes = $contentHash.ComputeHash($fileStream) }
            finally { if ($fileStream) { $fileStream.Dispose() }; $contentHash.Dispose() }
            $writer.Write([int]$pathBytes.Length); $writer.Write($pathBytes); $writer.Write([int]$hashBytes.Length); $writer.Write($hashBytes)
        }
        $writer.Flush(); $stream.Position = 0
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } finally { $writer.Dispose(); $stream.Dispose() }
}

function Copy-ReleaseFile {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not [System.IO.File]::Exists($Source)) { throw ('Required source file is missing: ' + $Source) }
    $parent = [System.IO.Path]::GetDirectoryName($Destination)
    if (-not [System.IO.Directory]::Exists($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [System.IO.File]::Copy($Source, $Destination, $false)
}

function Get-ManifestRuntimePath {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Prefix)
    $relative = $Path.Replace('\', '/')
    if (-not $relative.StartsWith($Prefix, [StringComparison]::Ordinal) -or $relative -match '(^|/)\.\.(/|$)' -or $relative.StartsWith('/') -or $relative.Contains(':')) { throw ('The dependency manifest contains an unsafe runtime path: ' + $Path) }
    return $relative.Substring($Prefix.Length)
}

function Test-ReleaseFFmpegRuntime {
    param([string]$FfmpegPath, [string]$FfprobePath, [string]$ExpectedVersion, $Definition)
    if ($script:ReleasePackageHooks.FFmpegRuntimeCheck) { return (& $script:ReleasePackageHooks.FFmpegRuntimeCheck $FfmpegPath $FfprobePath $ExpectedVersion) }
    $check = Test-FFmpegRuntimeRequirements -FfmpegPath $FfmpegPath -FfprobePath $FfprobePath -Source Candidate -ExpectedVersion $ExpectedVersion
    if (-not $check.Ready) { return $check }
    $probe = Invoke-ExternalCapture -FilePath $FfprobePath -Arguments @('-version') -TimeoutSec 20
    if (-not $probe.Started -or $probe.ExitCode -ne 0 -or $probe.TimedOut -or [string]$probe.StdOut -notmatch ('(?m)^ffprobe version ' + [regex]::Escape($ExpectedVersion) + '(?:\D|$)')) { return [pscustomobject]@{ Ready = $false; Detail = 'ffprobe did not report the exact manifest version.' } }
    $build = Invoke-ExternalCapture -FilePath $FfmpegPath -Arguments @('-buildconf') -TimeoutSec 20
    $buildText = ([string]$build.StdOut) + "`n" + ([string]$build.StdErr)
    if (-not $build.Started -or $build.ExitCode -ne 0 -or $build.TimedOut) { return [pscustomobject]@{ Ready = $false; Detail = 'ffmpeg -buildconf could not verify the selected build configuration.' } }
    $buildFlags = @($buildText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^--[A-Za-z0-9-]+$' })
    if ($buildFlags.Count -eq 0) { return [pscustomobject]@{ Ready = $false; Detail = 'ffmpeg -buildconf did not return parseable configure flags.' } }
    $buildConfiguration = [string]::Join(' ', [string[]]$buildFlags)
    foreach ($requiredFlag in @($Definition.RequiredBuildFlags)) {
        if ($buildFlags -notcontains [string]$requiredFlag) { return [pscustomobject]@{ Ready = $false; Detail = ('ffmpeg build is missing required configure flag ' + [string]$requiredFlag + '.') } }
    }
    return [pscustomobject]@{ Ready = $true; Version = $ExpectedVersion; Architecture = 'x64'; Detail = $check.Detail; BuildConfiguration = $buildConfiguration }
}

function Copy-VerifiedFFmpegRuntime {
    param([string]$ProjectRoot, [string]$SourceRoot, [string]$PackageRoot, $Definition)
    if (-not $SourceRoot -or -not [System.IO.Directory]::Exists($SourceRoot)) { throw 'Full Edition requires an explicit or acquired verified FFmpeg runtime source directory.' }
    $sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
    $sourceBin = Join-Path $sourceRoot 'bin'
    $sourceLicense = Join-Path $sourceRoot 'LICENSE'
    $sourceReadme = Join-Path $sourceRoot 'README.txt'
    $sourceLicenseDirectory = Join-Path $sourceRoot 'LICENSES'
    if (-not [System.IO.Directory]::Exists($sourceBin)) { throw 'The FFmpeg source must be the verified Gyan build root or a staged FFmpeg runtime with a bin directory.' }
    if (-not [System.IO.File]::Exists($sourceLicense)) { $sourceLicense = Join-Path $sourceLicenseDirectory 'COPYING.GPLv3' }
    if (-not [System.IO.File]::Exists($sourceReadme)) { $sourceReadme = Join-Path $sourceLicenseDirectory 'Gyan-README.txt' }
    if (-not [System.IO.File]::Exists($sourceLicense) -or -not [System.IO.File]::Exists($sourceReadme)) { throw 'The FFmpeg source is missing its upstream GPL license or build README.' }
    $licenseText = [System.IO.File]::ReadAllText($sourceLicense)
    $readmeText = [System.IO.File]::ReadAllText($sourceReadme)
    $versionPattern = '(?mi)^Version:\s*' + [regex]::Escape([string]$Definition.CurrentVersion) + '(?:-[^\r\n]*)?\s*$'
    if ($licenseText -notmatch '(?im)^\s*GNU GENERAL PUBLIC LICENSE\s*$' -or $licenseText -notmatch '(?im)^\s*Version 3, 29 June 2007\s*$' -or $readmeText -notmatch $versionPattern -or $readmeText -notmatch '(?mi)^License:\s*GPL v3\s*$') { throw 'The FFmpeg runtime README/license does not match the manifest version and GPL-3.0 build.' }
    $expectedNames = @($Definition.Files | ForEach-Object { [System.IO.Path]::GetFileName([string]$_.Path) })
    $actualBinFiles = @(Get-ChildItem -LiteralPath $sourceBin -File | Sort-Object Name)
    foreach ($file in $actualBinFiles) {
        if ($file.Name -ne 'ffplay.exe' -and $expectedNames -notcontains $file.Name) { throw ('FFmpeg source contains an unapproved runtime file: ' + $file.Name) }
    }
    $outputRoot = Join-Path $PackageRoot 'External-Libraries/FFmpeg'
    $outputBin = Join-Path $outputRoot 'bin'
    [void](New-Item -ItemType Directory -Path $outputBin -Force)
    foreach ($record in @($Definition.Files)) {
        $relative = Get-ManifestRuntimePath -Path ([string]$record.Path) -Prefix 'FFmpeg/'
        if (-not $relative.StartsWith('bin/', [StringComparison]::Ordinal)) { throw ('FFmpeg release manifests may ship runtime files only from the bin directory: ' + [string]$record.Path) }
        $source = Join-Path $sourceRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
        if (-not [System.IO.File]::Exists($source)) { throw ('FFmpeg runtime file is missing: ' + [string]$record.Path) }
        if ($record.PSObject.Properties['Bytes'] -and [long]$record.Bytes -ne (Get-Item -LiteralPath $source).Length) { throw ('FFmpeg runtime size does not match the manifest: ' + [string]$record.Path) }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if (-not [string]::Equals($hash, [string]$record.Sha256, [StringComparison]::OrdinalIgnoreCase)) { throw ('FFmpeg runtime hash mismatch: ' + [string]$record.Path) }
        $architecture = Get-ExecutableArchitecture -Path $source
        if (-not [string]::Equals($architecture, [string]$Definition.Architecture, [StringComparison]::OrdinalIgnoreCase)) { throw ('FFmpeg runtime architecture mismatch: ' + [string]$record.Path + ' (' + $architecture + ').') }
        Copy-ReleaseFile -Source $source -Destination (Join-Path $outputRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar))
    }
    foreach ($requiredName in @('ffmpeg.exe', 'ffprobe.exe')) {
        if (-not [System.IO.File]::Exists((Join-Path $outputBin $requiredName))) { throw ('Full Edition is missing ' + $requiredName + '.') }
    }
    $ffmpegCheck = Test-ReleaseFFmpegRuntime -FfmpegPath (Join-Path $outputBin 'ffmpeg.exe') -FfprobePath (Join-Path $outputBin 'ffprobe.exe') -ExpectedVersion ([string]$Definition.CurrentVersion) -Definition $Definition
    if (-not $ffmpegCheck.Ready) { throw ('FFmpeg did not pass the manifest self-check. ' + [string]$ffmpegCheck.Detail) }
    if (-not $ffmpegCheck.PSObject.Properties['BuildConfiguration'] -or [string]::IsNullOrWhiteSpace([string]$ffmpegCheck.BuildConfiguration)) { throw 'FFmpeg package metadata requires the runtime-verified -buildconf configuration.' }
    foreach ($licensePath in @($Definition.LicenseFiles)) {
        $licenseName = [System.IO.Path]::GetFileName([string]$licensePath)
        if ($licenseName -eq 'COPYING.GPLv3') { $source = $sourceLicense }
        elseif ($licenseName -eq 'Gyan-README.txt') { $source = $sourceReadme }
        else { throw ('Unsupported FFmpeg license path in the manifest: ' + [string]$licensePath) }
        $relative = Get-ManifestRuntimePath -Path ([string]$licensePath) -Prefix 'FFmpeg/'
        Copy-ReleaseFile -Source $source -Destination (Join-Path $outputRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar))
    }
    [System.IO.File]::WriteAllText((Join-Path $outputRoot 'VERSION'), ([string]$Definition.CurrentVersion + "`r`n"), (New-Object System.Text.ASCIIEncoding))
    $sourceLines = @(
        'Dependency: FFmpeg',
        ('Version: ' + [string]$Definition.CurrentVersion),
        ('Architecture: ' + [string]$Definition.Architecture),
        ('Package: ' + [string]$Definition.PackageManagerId),
        ('PackageVersion: ' + [string]$Definition.PackageVersion),
        ('Source: ' + [string]$Definition.SourceUri),
        ('UpstreamSourceRevision: ' + [string]$Definition.UpstreamSourceRevision),
        ('UpstreamSource: ' + [string]$Definition.UpstreamSourceUri),
        ('CorrespondingSourceArchive: https://github.com/FFmpeg/FFmpeg/archive/' + [string]$Definition.UpstreamSourceRevision + '.zip'),
        ('BuildConfiguration: ' + [string]$ffmpegCheck.BuildConfiguration),
        ('PackageMetadata: ' + [string]$Definition.PackageMetadataUri),
        ('PackageArchiveSha256 (manifest pin): ' + [string]$Definition.PackageArchiveSha256),
        'RuntimeIntegrity: every shipped executable/library was checked against External-Libraries/manifest.json',
        'Runtime acquisition date: see External-Libraries/manifest.json'
    )
    [System.IO.File]::WriteAllText((Join-Path $outputRoot 'SOURCE.txt'), (($sourceLines -join "`r`n") + "`r`n"), (New-Object System.Text.ASCIIEncoding))
}

function Copy-VerifiedAssimpRuntime {
    param([string]$ProjectRoot, [string]$PackageRoot, $Definition)
    $externalRoot = Join-Path $ProjectRoot 'External-Libraries'
    $sourceRoot = Join-Path $externalRoot 'Assimp'
    if (-not [System.IO.Directory]::Exists($sourceRoot)) { throw 'Full Edition requires the bundled Assimp runtime directory.' }
    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($Definition.Files)) { [void]$expected.Add((Get-ManifestRuntimePath -Path ([string]$record.Path) -Prefix 'Assimp/').Replace('/', [string][System.IO.Path]::DirectorySeparatorChar)) }
    foreach ($runtimePackage in @($Definition.RuntimePackages)) { [void]$expected.Add(([string]$runtimePackage.LicenseFile -replace '^Assimp/', '').Replace('/', [string][System.IO.Path]::DirectorySeparatorChar)) }
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse)) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ($relative -in @('VERSION', 'SOURCE.txt')) { continue }
        if (-not $expected.Contains($relative)) { throw ('Assimp source contains an unapproved runtime or development file: ' + $relative) }
    }
    $outputRoot = Join-Path $PackageRoot 'External-Libraries/Assimp'
    foreach ($record in @($Definition.Files)) {
        $relative = Get-ManifestRuntimePath -Path ([string]$record.Path) -Prefix 'Assimp/'
        if (-not $relative.StartsWith('bin/', [StringComparison]::Ordinal)) { throw ('Assimp release manifests may ship runtime files only from the bin directory: ' + [string]$record.Path) }
        $source = Join-Path $sourceRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
        if (-not [System.IO.File]::Exists($source)) { throw ('Assimp runtime file is missing: ' + [string]$record.Path) }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if (-not [string]::Equals($hash, [string]$record.Sha256, [StringComparison]::OrdinalIgnoreCase)) { throw ('Assimp runtime hash mismatch: ' + [string]$record.Path) }
        $architecture = Get-ExecutableArchitecture -Path $source
        if (-not [string]::Equals($architecture, [string]$Definition.Architecture, [StringComparison]::OrdinalIgnoreCase)) { throw ('Assimp runtime architecture mismatch: ' + [string]$record.Path + ' (' + $architecture + ').') }
        Copy-ReleaseFile -Source $source -Destination (Join-Path $PackageRoot ('External-Libraries/' + [string]$record.Path -replace '/', [string][System.IO.Path]::DirectorySeparatorChar))
    }
    foreach ($runtimePackage in @($Definition.RuntimePackages)) {
        $licensePath = [string]$runtimePackage.LicenseFile
        $relative = Get-ManifestRuntimePath -Path $licensePath -Prefix 'Assimp/'
        $source = Join-Path $sourceRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
        if (-not [System.IO.File]::Exists($source) -or (Get-Item -LiteralPath $source).Length -eq 0) { throw ('Required Assimp third-party license is missing or empty: ' + $licensePath) }
        Copy-ReleaseFile -Source $source -Destination (Join-Path $outputRoot ($relative -replace '/', [string][System.IO.Path]::DirectorySeparatorChar))
    }
    $assimpPath = Join-Path (Join-Path $outputRoot 'bin') 'assimp.exe'
    if (-not [System.IO.File]::Exists($assimpPath)) { throw 'Full Edition is missing the Assimp CLI required by the OBJ-to-GLB workflow.' }
    if ($script:ReleasePackageHooks.AssimpRuntimeCheck) { $check = & $script:ReleasePackageHooks.AssimpRuntimeCheck $assimpPath }
    else { $check = Get-ThreeDToolStatus -Executable $assimpPath }
    if (-not $check.Available) { throw ('Bundled Assimp did not pass its glb2 exporter self-check. ' + [string]$check.Reason) }
    [System.IO.File]::WriteAllText((Join-Path $outputRoot 'VERSION'), ([string]$Definition.CurrentVersion + "`r`n"), (New-Object System.Text.ASCIIEncoding))
    $sourceLines = @('Dependency: Assimp', ('Version: ' + [string]$Definition.CurrentVersion), ('Architecture: ' + [string]$Definition.Architecture), ('Source: ' + [string]$Definition.SourceUri), ('PackageSource: ' + [string]$Definition.PackageSource), ('Package: ' + [string]$Definition.PackageName), ('PackageVersion: ' + [string]$Definition.PackageVersion), ('PackageArchiveSha256: ' + [string]$Definition.PackageArchiveSha256), 'RuntimeIntegrity: every shipped executable/library was checked against External-Libraries/manifest.json')
    [System.IO.File]::WriteAllText((Join-Path $outputRoot 'SOURCE.txt'), (($sourceLines -join "`r`n") + "`r`n"), (New-Object System.Text.ASCIIEncoding))
}

function Copy-ReleaseProjectFiles {
    param([string]$ProjectRoot, [string]$PackageRoot, [object[]]$Files)
    foreach ($file in $Files) { Copy-ReleaseFile -Source ([string]$file.FullName) -Destination (Join-Path $PackageRoot ($file.Path -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)) }
}

function Write-ReleaseBuildInfo {
    param([string]$PackageRoot, [string]$Edition, [string]$Version, [string]$Revision, [string]$SourceTreeHash, $FFmpegDefinition, $AssimpDefinition)
    $lines = @('Product: FFmpeg User Manager', ('Version: ' + $Version), ('Edition: ' + $Edition), 'Target: Windows x64', ('SourceRevision: ' + $Revision), ('SourceTreeSha256: ' + $SourceTreeHash), ('FFmpeg: ' + $(if ($Edition -eq 'Full') { [string]$FFmpegDefinition.CurrentVersion } else { 'not bundled' })), ('Assimp: ' + $(if ($Edition -eq 'Full') { [string]$AssimpDefinition.CurrentVersion } else { 'not bundled' })))
    [System.IO.File]::WriteAllText((Join-Path $PackageRoot 'BUILD-INFO.txt'), (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.ASCIIEncoding))
}

function Add-DeterministicReleaseZip {
    param([string]$PackageRoot, [string]$ZipPath)
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    $fileStream = $null; $archive = $null
    try {
        $fileStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $archive = New-Object System.IO.Compression.ZipArchive($fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        $prefix = [System.IO.Path]::GetFullPath($PackageRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $releaseFiles = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $PackageRoot -File -Recurse)) {
            $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
            $releaseFiles += , ([pscustomobject]@{ Path = $relative; FullName = $file.FullName })
        }
        $caseInsensitivePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $releaseFiles) { if (-not $caseInsensitivePaths.Add([string]$file.Path)) { throw ('Release package contains duplicate paths for Windows: ' + [string]$file.Path) } }
        foreach ($file in @(Sort-ReleaseItemsByPath -Items $releaseFiles -PropertyName 'Path')) {
            $entry = $archive.CreateEntry(('FFmpeg-User-Manager/' + [string]$file.Path), [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = New-Object System.DateTimeOffset(1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
            $source = $null; $target = $null
            try { $source = [System.IO.File]::OpenRead([string]$file.FullName); $target = $entry.Open(); $source.CopyTo($target) }
            finally { if ($target) { $target.Dispose() }; if ($source) { $source.Dispose() } }
        }
    } finally { if ($archive) { $archive.Dispose() }; if ($fileStream) { $fileStream.Dispose() } }
}

function New-ReleasePackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [ValidateSet('Full', 'Lite', 'Both')][string]$Edition = 'Both',
        [string]$FFmpegRuntimeSource = '',
        [switch]$AcquireFFmpeg,
        [string]$SourceRevision = ''
    )
    $projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
    if (-not [System.IO.Directory]::Exists($projectPath)) { throw 'ProjectRoot must be an existing directory.' }
    if ($FFmpegRuntimeSource -and $AcquireFFmpeg) { throw 'Choose either an explicit FFmpeg runtime source or -AcquireFFmpeg, not both.' }
    $previousRoot = Get-AppRoot
    Set-AppRoot -Path $projectPath
    $stage = ''
    $movedFiles = New-Object System.Collections.Generic.List[string]
    try {
        $version = Get-ReleasePackageVersion -ProjectRoot $projectPath
        if (-not $SourceRevision) { $SourceRevision = Get-ReleaseProjectRevision -ProjectRoot $projectPath }
        if ($SourceRevision -notmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64})$') { throw 'SourceRevision must be a full Git commit hash.' }
        $sourceFiles = @(Get-ReleasePackageSourceFiles -ProjectRoot $projectPath)
        $sourceTreeHash = Get-ReleaseSourceTreeSha256 -Files $sourceFiles
        $manifest = Get-ExternalLibraryManifest
        $ffmpegDefinition = @($manifest.Libraries | Where-Object { [string]$_.Id -eq 'ffmpeg' }) | Select-Object -First 1
        $assimpDefinition = @($manifest.Libraries | Where-Object { [string]$_.Id -eq 'assimp' }) | Select-Object -First 1
        if (-not $ffmpegDefinition -or -not $assimpDefinition) { throw 'Both FFmpeg and Assimp must be present in the canonical external-library manifest.' }
        if (-not $ffmpegDefinition.BundledInFull -or $ffmpegDefinition.BundledInLite -or -not $assimpDefinition.BundledInFull -or $assimpDefinition.BundledInLite) { throw 'The dependency manifest does not define the required Full/Lite runtime policy.' }
        if (-not [System.IO.Directory]::Exists($OutputDirectory)) { [void](New-Item -ItemType Directory -Path $OutputDirectory -Force) }
        $outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
        $editions = if ($Edition -eq 'Both') { @('Full', 'Lite') } else { @($Edition) }
        $targets = @(); $packageNames = @()
        foreach ($editionName in $editions) {
            $packageName = 'FFmpeg-User-Manager-v' + $version + '-' + $editionName + '-Windows-x64.zip'
            $packageNames += $packageName
            $targets += (Join-Path $outputPath $packageName)
        }
        $checksumName = 'SHA256SUMS-v' + $version + '.txt'
        $checksumTarget = Join-Path $outputPath $checksumName
        $targets += $checksumTarget
        foreach ($target in $targets) { if ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target)) { throw ('Refusing to overwrite an existing release artifact: ' + $target) } }

        $stage = Join-Path $outputPath ('.release-stage-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $stage)
        $ffmpegSource = $FFmpegRuntimeSource
        if ($AcquireFFmpeg) {
            $acquired = Get-VerifiedFFmpegRuntimeForPackaging -Destination (Join-Path $stage 'acquired-ffmpeg') -Confirmed:$true
            if (-not $acquired.Ready) { throw ('FFmpeg package acquisition for release failed. ' + [string]$acquired.Message) }
            $ffmpegSource = [string]$acquired.Path
        } elseif (-not $ffmpegSource) {
            $localRuntime = Join-Path $projectPath 'External-Libraries/FFmpeg'
            if ([System.IO.Directory]::Exists($localRuntime)) { $ffmpegSource = $localRuntime }
        }
        $tempZips = @(); $index = 0
        foreach ($editionName in $editions) {
            $index++
            $packageRoot = Join-Path (Join-Path $stage ('edition-' + $editionName)) 'FFmpeg-User-Manager'
            [void](New-Item -ItemType Directory -Path $packageRoot -Force)
            Copy-ReleaseProjectFiles -ProjectRoot $projectPath -PackageRoot $packageRoot -Files $sourceFiles
            if ($editionName -eq 'Full') {
                Copy-VerifiedFFmpegRuntime -ProjectRoot $projectPath -SourceRoot $ffmpegSource -PackageRoot $packageRoot -Definition $ffmpegDefinition
                Copy-VerifiedAssimpRuntime -ProjectRoot $projectPath -PackageRoot $packageRoot -Definition $assimpDefinition
            }
            Write-ReleaseBuildInfo -PackageRoot $packageRoot -Edition $editionName -Version $version -Revision $SourceRevision.ToLowerInvariant() -SourceTreeHash $sourceTreeHash -FFmpegDefinition $ffmpegDefinition -AssimpDefinition $assimpDefinition
            $tempZip = Join-Path $stage $packageNames[$index - 1]
            Add-DeterministicReleaseZip -PackageRoot $packageRoot -ZipPath $tempZip
            $tempZips += $tempZip
        }
        $checksumLines = @()
        for ($zipIndex = 0; $zipIndex -lt $tempZips.Count; $zipIndex++) {
            $hash = (Get-FileHash -LiteralPath $tempZips[$zipIndex] -Algorithm SHA256).Hash.ToLowerInvariant()
            $checksumLines += ($hash + '  ' + $packageNames[$zipIndex])
        }
        $tempChecksum = Join-Path $stage $checksumName
        [System.IO.File]::WriteAllText($tempChecksum, (($checksumLines -join "`r`n") + "`r`n"), (New-Object System.Text.ASCIIEncoding))
        for ($zipIndex = 0; $zipIndex -lt $tempZips.Count; $zipIndex++) {
            $target = Join-Path $outputPath $packageNames[$zipIndex]
            [System.IO.File]::Move($tempZips[$zipIndex], $target)
            $movedFiles.Add($target)
        }
        [System.IO.File]::Move($tempChecksum, $checksumTarget)
        $movedFiles.Add($checksumTarget)
        $packagePaths = @(); foreach ($packageName in $packageNames) { $packagePaths += (Join-Path $outputPath $packageName) }
        return [pscustomobject]@{ Version = $version; SourceRevision = $SourceRevision.ToLowerInvariant(); SourceTreeSha256 = $sourceTreeHash; Edition = $Edition; Packages = @($packagePaths); ChecksumPath = $checksumTarget }
    } catch {
        foreach ($moved in $movedFiles) { if ([System.IO.File]::Exists($moved)) { [System.IO.File]::Delete($moved) } }
        throw
    } finally {
        if ($stage -and [System.IO.Directory]::Exists($stage)) { [System.IO.Directory]::Delete($stage, $true) }
        if ($previousRoot) { Set-AppRoot -Path $previousRoot }
    }
}

Export-ModuleMember -Function Set-ReleasePackageHooks, New-ReleasePackages
