# ExternalLibraries.psm1 - canonical dependency inventory, checks and transactional bundled updates.
Set-StrictMode -Version 2.0

$script:ExternalLibraryHooks = @{ WingetPath = $null; PackageMetadata = $null; Download = $null; RuntimeCheck = $null; MoveDirectory = $null; MoveFile = $null; RemoveDirectory = $null; RemoveFile = $null }

function Set-ExternalLibraryHooks {
    <# Test seams for package acquisition, verification and same-volume activation. #>
    param([scriptblock]$WingetPath, [scriptblock]$PackageMetadata, [scriptblock]$Download, [scriptblock]$RuntimeCheck, [scriptblock]$MoveDirectory, [scriptblock]$MoveFile, [scriptblock]$RemoveDirectory, [scriptblock]$RemoveFile, [switch]$Reset)
    if ($Reset) { $script:ExternalLibraryHooks = @{ WingetPath = $null; PackageMetadata = $null; Download = $null; RuntimeCheck = $null; MoveDirectory = $null; MoveFile = $null; RemoveDirectory = $null; RemoveFile = $null }; return }
    foreach ($name in @('WingetPath', 'PackageMetadata', 'Download', 'RuntimeCheck', 'MoveDirectory', 'MoveFile', 'RemoveDirectory', 'RemoveFile')) {
        $value = Get-Variable -Name $name -ValueOnly
        if ($value) { $script:ExternalLibraryHooks[$name] = $value }
    }
}

function Invoke-ExternalDirectoryMove {
    param([string]$Source, [string]$Destination)
    if ($script:ExternalLibraryHooks.MoveDirectory) { & $script:ExternalLibraryHooks.MoveDirectory $Source $Destination; return }
    [System.IO.Directory]::Move($Source, $Destination)
}

function Invoke-ExternalFileMove {
    param([string]$Source, [string]$Destination)
    if ($script:ExternalLibraryHooks.MoveFile) { & $script:ExternalLibraryHooks.MoveFile $Source $Destination; return }
    [System.IO.File]::Move($Source, $Destination)
}

function Remove-ExternalRuntimeDirectory {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $leaf = [System.IO.Path]::GetFileName($full)
    if (([System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($full)) -ne 'External-Libraries') -or ($leaf -notmatch '^\.FFmpeg-backup-[A-Fa-f0-9]{32}$' -and $leaf -notmatch '^\.stage-[A-Fa-f0-9]{32}$')) { throw 'Refusing to remove a directory outside the generated FFmpeg backup/staging naming policy.' }
    if ($script:ExternalLibraryHooks.RemoveDirectory) { & $script:ExternalLibraryHooks.RemoveDirectory $full; return }
    if ([System.IO.Directory]::Exists($full)) { [System.IO.Directory]::Delete($full, $true) }
}

function Remove-ExternalRuntimeFile {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (([System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($full)) -ne 'External-Libraries') -or [System.IO.Path]::GetFileName($full) -notmatch '^manifest\.json\.backup-[A-Fa-f0-9]{32}$') { throw 'Refusing to remove a file outside the generated manifest-backup naming policy.' }
    if ($script:ExternalLibraryHooks.RemoveFile) { & $script:ExternalLibraryHooks.RemoveFile $full; return }
    if ([System.IO.File]::Exists($full)) { [System.IO.File]::Delete($full) }
}

function Invoke-ExternalRuntimeSwap {
    <# Activates a verified candidate and matching dependency manifest, retaining recoverable backups until active verification passes. #>
    param([Parameter(Mandatory)][string]$ActivePath, [Parameter(Mandatory)][string]$CandidatePath, [Parameter(Mandatory)][string]$ActiveManifestPath, [Parameter(Mandatory)][string]$CandidateManifestPath, [Parameter(Mandatory)][scriptblock]$ValidateCandidate, [Parameter(Mandatory)][scriptblock]$ValidateActive)
    $activeFull = [System.IO.Path]::GetFullPath($ActivePath); $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
    $manifestFull = [System.IO.Path]::GetFullPath($ActiveManifestPath); $candidateManifestFull = [System.IO.Path]::GetFullPath($CandidateManifestPath)
    if (-not [System.IO.Directory]::Exists($activeFull) -or -not [System.IO.Directory]::Exists($candidateFull) -or -not [System.IO.File]::Exists($manifestFull) -or -not [System.IO.File]::Exists($candidateManifestFull)) { return [pscustomobject]@{ State = 'Rejected'; Message = 'The current runtime, candidate runtime or matching manifest is missing.'; BackupPath = ''; BackupManifestPath = '' } }
    $activeParent = [System.IO.Path]::GetDirectoryName($activeFull); $candidateParent = [System.IO.Path]::GetDirectoryName($candidateFull); $manifestParent = [System.IO.Path]::GetDirectoryName($manifestFull); $candidateManifestParent = [System.IO.Path]::GetDirectoryName($candidateManifestFull)
    $sameVolume = [string]::Equals([System.IO.Path]::GetPathRoot($activeFull), [System.IO.Path]::GetPathRoot($candidateFull), [StringComparison]::OrdinalIgnoreCase)
    $validStageName = [System.IO.Path]::GetFileName($candidateParent) -match '^\.stage-[A-Fa-f0-9]{32}$'
    $validLayout = ([System.IO.Path]::GetFileName($activeFull) -eq 'FFmpeg' -and [System.IO.Path]::GetFileName($candidateFull) -eq 'FFmpeg' -and [System.IO.Path]::GetFileName($manifestFull) -eq 'manifest.json' -and [System.IO.Path]::GetFileName($candidateManifestFull) -eq 'manifest.json' -and [string]::Equals($activeParent, $manifestParent, [StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($candidateParent, $candidateManifestParent, [StringComparison]::OrdinalIgnoreCase) -and [System.IO.Path]::GetFileName($activeParent) -eq 'External-Libraries' -and $validStageName)
    if (-not $sameVolume -or -not $validLayout) { return [pscustomobject]@{ State = 'Rejected'; Message = 'The runtime activation paths do not match the same-volume FFmpeg staging layout.'; BackupPath = ''; BackupManifestPath = '' } }
    try { if (-not [bool](& $ValidateCandidate $candidateFull)) { return [pscustomobject]@{ State = 'Rejected'; Message = 'The staged FFmpeg candidate did not pass its verification.'; BackupPath = ''; BackupManifestPath = '' } } }
    catch { return [pscustomobject]@{ State = 'Rejected'; Message = ('The staged FFmpeg candidate could not be verified: ' + $_.Exception.Message); BackupPath = ''; BackupManifestPath = '' } }

    $transactionId = [guid]::NewGuid().ToString('N')
    $backupPath = Join-Path $activeParent ('.FFmpeg-backup-' + $transactionId)
    $backupManifestPath = $manifestFull + '.backup-' + $transactionId
    $oldRuntimeMoved = $false; $oldManifestMoved = $false; $newManifestMoved = $false; $newRuntimeMoved = $false
    $activationError = ''
    try {
        Invoke-ExternalDirectoryMove -Source $activeFull -Destination $backupPath
        $oldRuntimeMoved = $true
        Invoke-ExternalFileMove -Source $manifestFull -Destination $backupManifestPath
        $oldManifestMoved = $true
        Invoke-ExternalFileMove -Source $candidateManifestFull -Destination $manifestFull
        $newManifestMoved = $true
        Invoke-ExternalDirectoryMove -Source $candidateFull -Destination $activeFull
        $newRuntimeMoved = $true
        if (-not [bool](& $ValidateActive $activeFull)) { throw 'The activated FFmpeg runtime failed its final verification.' }
    } catch { $activationError = $_.Exception.Message }

    if ($activationError) {
        $rollbackErrors = @()
        try { if ($newRuntimeMoved -and [System.IO.Directory]::Exists($activeFull)) { Invoke-ExternalDirectoryMove -Source $activeFull -Destination $candidateFull } } catch { $rollbackErrors += ('Could not quarantine the failed active runtime: ' + $_.Exception.Message) }
        try { if ($newManifestMoved -and [System.IO.File]::Exists($manifestFull) -and -not [System.IO.File]::Exists($candidateManifestFull)) { Invoke-ExternalFileMove -Source $manifestFull -Destination $candidateManifestFull } } catch { $rollbackErrors += ('Could not quarantine the candidate manifest: ' + $_.Exception.Message) }
        try { if ($oldManifestMoved -and [System.IO.File]::Exists($backupManifestPath) -and -not [System.IO.File]::Exists($manifestFull)) { Invoke-ExternalFileMove -Source $backupManifestPath -Destination $manifestFull } } catch { $rollbackErrors += ('Could not restore the previous dependency manifest: ' + $_.Exception.Message) }
        try { if ($oldRuntimeMoved -and [System.IO.Directory]::Exists($backupPath) -and -not [System.IO.Directory]::Exists($activeFull)) { Invoke-ExternalDirectoryMove -Source $backupPath -Destination $activeFull } } catch { $rollbackErrors += ('Could not restore the previous FFmpeg runtime: ' + $_.Exception.Message) }
        if ($rollbackErrors.Count -gt 0) { return [pscustomobject]@{ State = 'RollbackFailed'; Message = ($activationError + ' ' + ($rollbackErrors -join ' ')); BackupPath = $backupPath; BackupManifestPath = $backupManifestPath } }
        return [pscustomobject]@{ State = 'Failed'; Message = ($activationError + ' The previous runtime and manifest were restored.'); BackupPath = ''; BackupManifestPath = '' }
    }

    $cleanupErrors = @()
    try { Remove-ExternalRuntimeDirectory -Path $backupPath } catch { $cleanupErrors += ('The superseded runtime backup remains at ' + $backupPath + ': ' + $_.Exception.Message) }
    try { Remove-ExternalRuntimeFile -Path $backupManifestPath } catch { $cleanupErrors += ('The previous manifest backup remains at ' + $backupManifestPath + ': ' + $_.Exception.Message) }
    if ($cleanupErrors.Count -gt 0) { return [pscustomobject]@{ State = 'UpdatedWithBackup'; Message = ('The new runtime passed active verification. ' + ($cleanupErrors -join ' ')); BackupPath = $backupPath; BackupManifestPath = $backupManifestPath } }
    return [pscustomobject]@{ State = 'Updated'; Message = 'The new runtime passed candidate and active verification; the superseded runtime was removed.'; BackupPath = ''; BackupManifestPath = '' }
}

function Get-ExternalLibraryManifest {
    $root = Get-AppRoot
    if (-not $root) { throw 'The application root has not been initialized.' }
    $path = Join-Path (Join-Path $root 'External-Libraries') 'manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'The external library manifest is missing.' }
    $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.SchemaVersion -ne 2 -or @($manifest.Libraries).Count -eq 0) { throw 'The external library manifest has an unsupported or empty schema.' }
    $seenIds = @{}
    foreach ($library in @($manifest.Libraries)) {
        $libraryId = [string]$library.Id
        if (-not $libraryId -or $seenIds.ContainsKey($libraryId) -or -not (Test-SemVer ([string]$library.CurrentVersion))) { throw 'The external library manifest contains a duplicate/invalid library id or version.' }
        $seenIds[$libraryId] = $true
        if (@('x86', 'x64', 'arm64') -notcontains [string]$library.Architecture) { throw 'The external library manifest contains an unsupported architecture.' }
        if ($library.BundledInFull -isnot [bool] -or $library.BundledInLite -isnot [bool] -or (-not $library.BundledInFull -and -not $library.BundledInLite)) { throw 'The external library manifest omits a valid edition policy.' }
        if (-not $library.Source -or -not $library.License -or -not $library.AcquisitionDate -or -not $library.LastVerified -or -not $library.WindowsSupport.Status -or -not $library.WindowsSupport.Verified -or -not $library.LinuxSupport.Status -or -not $library.LinuxSupport.Verified) { throw 'The external library manifest omits required provenance, license, acquisition date, verification date or platform status.' }
        $sourceEndpoint = $null
        if (-not [System.Uri]::TryCreate([string]$library.SourceUri, [System.UriKind]::Absolute, [ref]$sourceEndpoint) -or $sourceEndpoint.Scheme -ne 'https' -or $sourceEndpoint.Host -notin @('github.com', 'gitlab.com', 'www.ffmpeg.org', 'ffmpeg.org')) { throw 'The external library manifest contains an untrusted source endpoint.' }
        $verifiedDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$library.LastVerified, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$verifiedDate)) { throw 'The external library manifest contains an invalid verification date.' }
        if (@($library.Files).Count -eq 0) { throw 'The external library manifest omits the runtime file inventory.' }
        foreach ($file in @($library.Files)) {
            if (-not $file.Path -or [string]$file.Path -match '(^|[\\/])\.\.([\\/]|$)' -or [string]$file.Path -match '^([\\/]|[A-Za-z]:)' -or [string]$file.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'The external library manifest contains an unsafe path or invalid runtime file hash.' }
        }
        $endpoint = $null; $packageEndpoint = $null
        if (-not [System.Uri]::TryCreate([string]$library.MetadataUri, [System.UriKind]::Absolute, [ref]$endpoint) -or $endpoint.Scheme -ne 'https' -or $endpoint.Host -ne 'api.github.com') { throw 'The external library manifest contains an untrusted upstream metadata endpoint.' }
        if (-not [System.Uri]::TryCreate([string]$library.PackageMetadataUri, [System.UriKind]::Absolute, [ref]$packageEndpoint) -or $packageEndpoint.Scheme -ne 'https' -or $packageEndpoint.Host -notin @('api.github.com', 'packages.msys2.org')) { throw 'The external library manifest contains an untrusted package metadata endpoint.' }
        if ($libraryId -eq 'assimp') {
            if ($packageEndpoint.AbsolutePath -ne '/api/search' -or $packageEndpoint.Host -ne 'packages.msys2.org' -or $packageEndpoint.Query -notmatch ('(^|[?&])query=' + [regex]::Escape([string]$library.PackageName) + '(&|$)') -or $packageEndpoint.Query -notmatch '(^|[?&])qtype=binpkg(&|$)') { throw 'The Assimp manifest contains an untrusted package metadata endpoint.' }
            if (-not $library.PackageBaseName -or -not $library.PackageRealName -or -not $library.PackageRepository -or @($library.RuntimePackages).Count -eq 0) { throw 'The Assimp manifest omits its exact package-manager identity or runtime package inventory.' }
        } elseif ($libraryId -eq 'ffmpeg') {
            if ($packageEndpoint.AbsolutePath -ne '/repos/microsoft/winget-pkgs/contents/manifests/g/Gyan/FFmpeg/Shared' -or $library.PackageManagerId -ne 'Gyan.FFmpeg.Shared' -or $library.PackageVersion -ne $library.CurrentVersion -or [string]$library.License -ne 'GPL-3.0' -or [string]$library.PackageArchiveSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not $library.SourceFile -or @($library.LicenseFiles).Count -eq 0) { throw 'The FFmpeg manifest omits the pinned package identity, license/source paths or integrity metadata.' }
            if (@($library.RequiredExecutables).Count -ne 2 -or @($library.RequiredEncoders).Count -eq 0 -or @($library.RequiredFilters).Count -eq 0) { throw 'The FFmpeg manifest omits required executable or capability acceptance criteria.' }
            if (@($library.Files | Where-Object { $_.Path -eq 'FFmpeg/bin/ffmpeg.exe' }).Count -ne 1 -or @($library.Files | Where-Object { $_.Path -eq 'FFmpeg/bin/ffprobe.exe' }).Count -ne 1) { throw 'The FFmpeg manifest must inventory both required executables.' }
        }
    }
    return $manifest
}

function Get-ExternalLibraryDefinition {
    param([Parameter(Mandatory)][string]$Id)
    $manifest = Get-ExternalLibraryManifest
    foreach ($library in @($manifest.Libraries)) { if ([string]::Equals([string]$library.Id, $Id, [StringComparison]::OrdinalIgnoreCase)) { return $library } }
    throw "External library '$Id' is not in the manifest."
}

function Compare-SemVerPrecedence {
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    $pattern = '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
    $leftMatch = [regex]::Match($Left, $pattern)
    $rightMatch = [regex]::Match($Right, $pattern)
    if (-not $leftMatch.Success -or -not $rightMatch.Success) { throw 'Both versions must be valid Semantic Versions.' }
    foreach ($part in @('major', 'minor', 'patch')) {
        $leftNumber = $leftMatch.Groups[$part].Value; $rightNumber = $rightMatch.Groups[$part].Value
        if ($leftNumber.Length -ne $rightNumber.Length) { if ($leftNumber.Length -gt $rightNumber.Length) { return 1 } else { return -1 } }
        $numericOrder = [string]::CompareOrdinal($leftNumber, $rightNumber)
        if ($numericOrder -ne 0) { if ($numericOrder -gt 0) { return 1 } else { return -1 } }
    }
    $leftPre = $leftMatch.Groups['pre'].Value; $rightPre = $rightMatch.Groups['pre'].Value
    if (-not $leftPre -and -not $rightPre) { return 0 }
    if (-not $leftPre) { return 1 }
    if (-not $rightPre) { return -1 }
    $leftIds = @($leftPre -split '\.'); $rightIds = @($rightPre -split '\.')
    $common = [math]::Min($leftIds.Count, $rightIds.Count)
    for ($idIndex = 0; $idIndex -lt $common; $idIndex++) {
        $leftNumeric = $leftIds[$idIndex] -match '^\d+$'; $rightNumeric = $rightIds[$idIndex] -match '^\d+$'
        if ($leftNumeric -and $rightNumeric) {
            if ($leftIds[$idIndex].Length -ne $rightIds[$idIndex].Length) { if ($leftIds[$idIndex].Length -gt $rightIds[$idIndex].Length) { return 1 } else { return -1 } }
            $numericOrder = [string]::CompareOrdinal($leftIds[$idIndex], $rightIds[$idIndex])
        } elseif ($leftNumeric) { return -1 }
        elseif ($rightNumeric) { return 1 }
        else { $numericOrder = [string]::CompareOrdinal($leftIds[$idIndex], $rightIds[$idIndex]) }
        if ($numericOrder -ne 0) { if ($numericOrder -gt 0) { return 1 } else { return -1 } }
    }
    if ($leftIds.Count -eq $rightIds.Count) { return 0 }
    if ($leftIds.Count -gt $rightIds.Count) { return 1 }
    return -1
}

function Compare-ExternalPackageVersion {
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    $packagePattern = '^(?<upstream>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))(?:-(?<release>0|[1-9]\d*))$'
    $leftMatch = [regex]::Match($Left, $packagePattern); $rightMatch = [regex]::Match($Right, $packagePattern)
    if (-not $leftMatch.Success -or -not $rightMatch.Success) { throw 'Both package versions must use upstream Semantic Version plus a numeric package release.' }
    $upstreamOrder = Compare-SemVerPrecedence -Left $leftMatch.Groups['upstream'].Value -Right $rightMatch.Groups['upstream'].Value
    if ($upstreamOrder -ne 0) { return $upstreamOrder }
    $leftRelease = $leftMatch.Groups['release'].Value; $rightRelease = $rightMatch.Groups['release'].Value
    if ($leftRelease.Length -ne $rightRelease.Length) { if ($leftRelease.Length -gt $rightRelease.Length) { return 1 } else { return -1 } }
    return [string]::CompareOrdinal($leftRelease, $rightRelease)
}

function Get-ExternalPackageMetadataVersion {
    param([Parameter(Mandatory)]$Metadata, [Parameter(Mandatory)][string]$Id)
    $library = Get-ExternalLibraryDefinition -Id $Id
    if ([string]::Equals([string]$library.Id, 'ffmpeg', [StringComparison]::OrdinalIgnoreCase)) {
        $versions = @()
        foreach ($entry in @($Metadata)) {
            $entryName = [string]$entry.name
            if ($entryName -match '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') { $versions += $entryName }
        }
        if ($versions.Count -eq 0) { throw 'The official winget manifest metadata did not return any valid FFmpeg package versions.' }
        $newest = $versions[0]
        foreach ($candidate in $versions | Select-Object -Skip 1) { if ((Compare-SemVerPrecedence -Left $candidate -Right $newest) -gt 0) { $newest = $candidate } }
        return $newest
    }
    $packageResult = $Metadata.results.exact
    if (-not $packageResult -or -not [string]::Equals([string]$packageResult.name, [string]$library.PackageBaseName, [StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$packageResult.realname, [string]$library.PackageRealName, [StringComparison]::OrdinalIgnoreCase)) { throw 'The official package metadata did not return the expected package.' }
    $hasRepository = $false
    foreach ($repository in @($packageResult.repos)) { if ([string]::Equals([string]$repository, [string]$library.PackageRepository, [StringComparison]::OrdinalIgnoreCase)) { $hasRepository = $true } }
    if (-not $hasRepository) { throw 'The official package metadata did not include the expected repository.' }
    $packageVersion = [string]$packageResult.version
    if (-not [regex]::IsMatch($packageVersion, '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)-(?:0|[1-9]\d*)$')) { throw 'The official package metadata did not contain a valid package version.' }
    return $packageVersion
}

function Get-ExternalLibraryUpdateStatus {
    param([Parameter(Mandatory)][string]$Id, [string]$LatestVersion = '', [string]$LatestPackageVersion = '')
    $library = Get-ExternalLibraryDefinition -Id $Id
    $upstreamError = ''; $packageError = ''
    if (-not $LatestVersion) {
        try {
            $release = Invoke-RestMethod -Uri ([string]$library.MetadataUri) -Method Get -TimeoutSec 8 -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'FFmpeg-User-Manager' } -ErrorAction Stop
            if ($release.draft -or $release.prerelease) { throw 'The upstream endpoint did not return a stable release.' }
            $LatestVersion = [string]$release.tag_name
        } catch {
            $upstreamError = 'The official upstream metadata check failed or is unavailable.'
        }
    }
    if (-not $LatestPackageVersion) {
        try {
            $packageMetadata = Invoke-RestMethod -Uri ([string]$library.PackageMetadataUri) -Method Get -TimeoutSec 8 -Headers @{ Accept = 'application/json'; 'User-Agent' = 'FFmpeg-User-Manager' } -ErrorAction Stop
            $LatestPackageVersion = Get-ExternalPackageMetadataVersion -Metadata $packageMetadata -Id $Id
        } catch {
            $packageError = 'The official package-manager metadata check failed or is unavailable.'
        }
    }
    $LatestVersion = $LatestVersion.Trim()
    if ($LatestVersion.StartsWith('v', [StringComparison]::OrdinalIgnoreCase)) { $LatestVersion = $LatestVersion.Substring(1) }
    $upstreamState = 'Unknown'; $packageState = 'Unknown'
    if ($upstreamError) { $upstreamMessage = $upstreamError }
    elseif (-not (Test-SemVer $LatestVersion)) { $upstreamMessage = 'The official upstream metadata did not contain a valid Semantic Version.' }
    else {
        $latestMatch = [regex]::Match($LatestVersion, '^[^+-]+(?<pre>-[^+]+)?')
        if ($latestMatch.Groups['pre'].Success) { $upstreamState = 'UpToDate'; $upstreamMessage = 'No newer stable upstream release was reported; prereleases are ignored.' }
        elseif ((Compare-SemVerPrecedence -Left $LatestVersion -Right ([string]$library.CurrentVersion)) -gt 0) { $upstreamState = 'UpdateAvailable'; $upstreamMessage = 'A newer stable upstream release is available.' }
        else { $upstreamState = 'UpToDate'; $upstreamMessage = 'The bundled upstream version matches the latest stable release.' }
    }
    if ($packageError) { $packageMessage = $packageError }
    elseif (($library.Id -eq 'ffmpeg' -and -not (Test-SemVer $LatestPackageVersion)) -or ($library.Id -ne 'ffmpeg' -and -not [regex]::IsMatch($LatestPackageVersion, '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)-(?:0|[1-9]\d*)$'))) { $packageMessage = 'The official package metadata did not contain a valid package version.' }
    else {
        try {
            $packageOrder = if ($library.Id -eq 'ffmpeg') { Compare-SemVerPrecedence -Left $LatestPackageVersion -Right ([string]$library.PackageVersion) } else { Compare-ExternalPackageVersion -Left $LatestPackageVersion -Right ([string]$library.PackageVersion) }
            if ($packageOrder -gt 0) { $packageState = 'UpdateAvailable'; $packageMessage = 'A newer stable package-manager build is available.' }
            else { $packageState = 'UpToDate'; $packageMessage = 'The bundled package-manager build matches the latest stable package.' }
        } catch { $packageMessage = 'The official package metadata did not contain a comparable package version.' }
    }
    $state = if ($upstreamState -eq 'UpdateAvailable' -or $packageState -eq 'UpdateAvailable') { 'UpdateAvailable' } elseif ($upstreamState -eq 'Unknown' -or $packageState -eq 'Unknown') { 'Unknown' } else { 'UpToDate' }
    $message = $upstreamMessage + ' ' + $packageMessage + ' No library files were changed.'
    return [pscustomobject]@{ Id = [string]$library.Id; Name = [string]$library.Name; CurrentVersion = [string]$library.CurrentVersion; LatestVersion = $LatestVersion; PackageVersion = [string]$library.PackageVersion; LatestPackageVersion = $LatestPackageVersion; State = $state; Source = ([string]$library.MetadataSource + '; ' + [string]$library.PackageMetadataSource); Message = $message }
}

function Get-ExternalLibraryUpdateStatuses {
    param([scriptblock]$OnTick)
    $manifest = Get-ExternalLibraryManifest
    $results = @(); $index = 0
    foreach ($library in @($manifest.Libraries)) {
        $index++
        if ($OnTick) { if (& $OnTick $index ('Checking ' + [string]$library.Name)) { break } }
        $results += , (Get-ExternalLibraryUpdateStatus -Id ([string]$library.Id))
    }
    return , @($results)
}

function ConvertFrom-FFmpegWingetInstallerManifest {
    param([Parameter(Mandatory)][string]$Yaml, [Parameter(Mandatory)][string]$PackageVersion, [string]$MetadataSource = '')
    $library = Get-ExternalLibraryDefinition -Id 'ffmpeg'
    if (-not (Test-SemVer $PackageVersion) -or $PackageVersion -match '-') { throw 'Only an exact stable FFmpeg package version can be staged.' }
    $metadataUri = $null
    if (-not [System.Uri]::TryCreate($MetadataSource, [System.UriKind]::Absolute, [ref]$metadataUri) -or $metadataUri.Scheme -ne 'https' -or $metadataUri.Host -ne 'raw.githubusercontent.com' -or $metadataUri.AbsolutePath -notmatch ('^/microsoft/winget-pkgs/(?:master|main)/manifests/g/Gyan/FFmpeg/Shared/' + [regex]::Escape($PackageVersion) + '/Gyan\.FFmpeg\.Shared\.installer\.yaml$')) { throw 'The winget installer manifest link is outside the pinned official metadata path.' }
    $packageIdMatch = [regex]::Match($yaml, '(?m)^PackageIdentifier:\s*(?<value>[^\s#]+)\s*$')
    $packageVersionMatch = [regex]::Match($yaml, '(?m)^PackageVersion:\s*(?<value>[^\s#]+)\s*$')
    if (-not $packageIdMatch.Success -or $packageIdMatch.Groups['value'].Value -ne [string]$library.PackageManagerId -or -not $packageVersionMatch.Success -or $packageVersionMatch.Groups['value'].Value -ne $PackageVersion) { throw 'The official installer manifest package identity/version did not match the requested FFmpeg package.' }
    $blocks = [regex]::Split($yaml, '(?m)(?=^-\s*Architecture:)')
    $x64Blocks = @($blocks | Where-Object { $_ -match '(?m)^-\s*Architecture:\s*x64\s*$' })
    if ($x64Blocks.Count -ne 1) { throw 'The official installer manifest did not contain exactly one x64 installer record.' }
    $block = [string]$x64Blocks[0]
    $typeMatch = [regex]::Match($Yaml, '(?m)^InstallerType:\s*(?<value>[^\s#]+)\s*$')
    $urlMatch = [regex]::Match($block, '(?m)^\s+InstallerUrl:\s*["'']?(?<value>https://[^"''\s]+)["'']?\s*$')
    $hashMatch = [regex]::Match($block, '(?m)^\s+InstallerSha256:\s*(?<value>[A-Fa-f0-9]{64})\s*$')
    $installerUri = $null
    if (-not $typeMatch.Success -or $typeMatch.Groups['value'].Value -ne 'zip' -or -not $urlMatch.Success -or -not [System.Uri]::TryCreate($urlMatch.Groups['value'].Value, [System.UriKind]::Absolute, [ref]$installerUri) -or $installerUri.Scheme -ne 'https' -or $installerUri.Host -ne 'github.com' -or $installerUri.AbsolutePath -notmatch '^/GyanD/codexffmpeg/releases/download/' -or -not $hashMatch.Success) { throw 'The official FFmpeg package must provide a trusted x64 ZIP installer and SHA-256.' }
    return [pscustomobject]@{ PackageId = [string]$library.PackageManagerId; PackageVersion = $PackageVersion; Architecture = 'x64'; InstallerType = 'zip'; InstallerUrl = $installerUri.AbsoluteUri; InstallerFileName = [System.IO.Path]::GetFileName($installerUri.LocalPath); InstallerSha256 = $hashMatch.Groups['value'].Value.ToUpperInvariant(); MetadataSource = $metadataUri.AbsoluteUri }
}

function Get-FFmpegWingetInstallerMetadata {
    param([Parameter(Mandatory)][string]$PackageVersion)
    $library = Get-ExternalLibraryDefinition -Id 'ffmpeg'
    if (-not (Test-SemVer $PackageVersion) -or $PackageVersion -match '-') { throw 'Only an exact stable FFmpeg package version can be staged.' }
    $versionUri = ([string]$library.PackageMetadataUri).TrimEnd('/') + '/' + $PackageVersion
    $entries = Invoke-RestMethod -Uri $versionUri -Method Get -TimeoutSec 8 -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'FFmpeg-User-Manager' } -ErrorAction Stop
    $installerEntries = @($entries | Where-Object { [string]$_.name -eq 'Gyan.FFmpeg.Shared.installer.yaml' })
    if ($installerEntries.Count -ne 1) { throw 'The official winget release directory did not contain exactly one FFmpeg installer manifest.' }
    $metadataUri = [string]$installerEntries[0].download_url
    $metadataEndpoint = $null
    if (-not [System.Uri]::TryCreate($metadataUri, [System.UriKind]::Absolute, [ref]$metadataEndpoint) -or $metadataEndpoint.Scheme -ne 'https' -or $metadataEndpoint.Host -ne 'raw.githubusercontent.com' -or $metadataEndpoint.AbsolutePath -notmatch ('^/microsoft/winget-pkgs/(?:master|main)/manifests/g/Gyan/FFmpeg/Shared/' + [regex]::Escape($PackageVersion) + '/Gyan\.FFmpeg\.Shared\.installer\.yaml$')) { throw 'The winget installer manifest link is outside the pinned official metadata path.' }
    $yaml = [string](Invoke-RestMethod -Uri $metadataEndpoint.AbsoluteUri -Method Get -TimeoutSec 8 -Headers @{ 'User-Agent' = 'FFmpeg-User-Manager' } -ErrorAction Stop)
    return ConvertFrom-FFmpegWingetInstallerManifest -Yaml $yaml -PackageVersion $PackageVersion -MetadataSource $metadataUri
}

function Invoke-FFmpegPackageDownload {
    param([string]$PackageVersion, [string]$Destination, $InstallerMetadata, [scriptblock]$OnTick)
    if ($script:ExternalLibraryHooks.Download) { return (& $script:ExternalLibraryHooks.Download $PackageVersion $Destination $InstallerMetadata) }
    $wingetPath = $null
    if ($script:ExternalLibraryHooks.WingetPath) { $wingetPath = [string](& $script:ExternalLibraryHooks.WingetPath) }
    else { $wingetCommand = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($wingetCommand) { $wingetPath = [string]$wingetCommand.Source } }
    if (-not $wingetPath) { throw 'WinGet is unavailable; no runtime package was downloaded.' }
    $library = Get-ExternalLibraryDefinition -Id 'ffmpeg'
    $tokens = @('download', '--id', [string]$library.PackageManagerId, '--exact', '--source', 'winget', '--version', $PackageVersion, '--architecture', 'x64', '--download-directory', $Destination, '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    $run = Invoke-ExternalStreaming -FilePath $wingetPath -Arguments $tokens -TimeoutSec 1800 -OnTick $OnTick
    if ($run.Cancelled) { return [pscustomobject]@{ Path = ''; ExitCode = [int]$run.ExitCode; Started = [bool]$run.Started; TimedOut = [bool]$run.TimedOut; Cancelled = $true } }
    if (-not $run.Started -or $run.TimedOut -or $run.ExitCode -ne 0) { throw ('WinGet did not complete the verified FFmpeg package download. ' + [string]$run.Error) }
    $installerPath = Join-Path $Destination ([string]$InstallerMetadata.InstallerFileName)
    if (-not [System.IO.File]::Exists($installerPath)) { throw 'WinGet reported success but the exact expected FFmpeg installer archive is missing.' }
    return [pscustomobject]@{ Path = $installerPath; ExitCode = [int]$run.ExitCode; Started = [bool]$run.Started; TimedOut = [bool]$run.TimedOut; Cancelled = $false }
}

function Expand-FFmpegArchiveSafely {
    param([Parameter(Mandatory)][string]$ArchivePath, [Parameter(Mandatory)][string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $root = [System.IO.Path]::GetFullPath($Destination)
    [void](New-Item -ItemType Directory -Path $root -Force)
    $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
        $expandedBytes = [long]0
        foreach ($entry in $archive.Entries) {
            $relative = ([string]$entry.FullName).Replace('\', '/')
            if (-not $relative -or $relative.StartsWith('/') -or $relative -match '(^|/)\.\.(/|$)' -or $relative -match '(^|/)\.(/|$)' -or $relative -match '^[A-Za-z]:' -or $relative.Contains(':')) { throw 'The FFmpeg archive contains an unsafe entry path.' }
            $entryType = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($entryType -eq 0xA000) { throw 'The FFmpeg archive contains a symbolic link, which is not accepted.' }
            $target = [System.IO.Path]::GetFullPath((Join-Path $root ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))))
            if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'The FFmpeg archive contains a path that escapes its extraction directory.' }
            if (-not $entry.Name) { [void](New-Item -ItemType Directory -Path $target -Force); continue }
            if (-not $seen.Add($relative)) { throw 'The FFmpeg archive contains duplicate paths.' }
            $expandedBytes += [long]$entry.Length
            if ($expandedBytes -gt 1073741824) { throw 'The FFmpeg archive expands beyond the 1 GiB safety limit.' }
            $parent = [System.IO.Path]::GetDirectoryName($target)
            if (-not [System.IO.Directory]::Exists($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
            $sourceStream = $entry.Open(); $targetStream = $null
            try { $targetStream = [System.IO.File]::Open($target, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None); $sourceStream.CopyTo($targetStream) }
            finally { if ($targetStream) { $targetStream.Dispose() }; if ($sourceStream) { $sourceStream.Dispose() } }
        }
    } finally { if ($archive) { $archive.Dispose() } }
}

function Get-ExternalPathUnder {
    param([string]$Root, [string]$Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'A package-manager result escaped its isolated staging directory.' }
    return $fullPath
}

function Invoke-FFmpegCandidateRuntimeCheck {
    param([string]$FfmpegPath, [string]$FfprobePath, [string]$ExpectedVersion)
    if ($script:ExternalLibraryHooks.RuntimeCheck) { return (& $script:ExternalLibraryHooks.RuntimeCheck $FfmpegPath $FfprobePath $ExpectedVersion) }
    if ((Get-ExecutableArchitecture -Path $FfmpegPath) -ne 'x64' -or (Get-ExecutableArchitecture -Path $FfprobePath) -ne 'x64') { return [pscustomobject]@{ Ready = $false; Detail = 'ffmpeg and ffprobe must both be x64 executables.' } }
    $runtime = Test-FFmpegRuntimeRequirements -FfmpegPath $FfmpegPath -FfprobePath $FfprobePath -Source Candidate -ExpectedVersion $ExpectedVersion
    if (-not $runtime.Ready) { return $runtime }
    $probe = Invoke-ExternalCapture -FilePath $FfprobePath -Arguments @('-version') -TimeoutSec 20
    if (-not $probe.Started -or $probe.ExitCode -ne 0 -or $probe.TimedOut -or $probe.StdOut -notmatch ('(?m)^ffprobe version ' + [regex]::Escape($ExpectedVersion) + '(?:\D|$)')) { return [pscustomobject]@{ Ready = $false; Detail = 'ffprobe did not report the exact requested stable version.' } }
    return [pscustomobject]@{ Ready = $true; Detail = $runtime.Detail; Version = $ExpectedVersion; Architecture = 'x64' }
}

function New-FFmpegCandidateRuntime {
    param([string]$ArchivePath, [string]$ExtractPath, [string]$CandidatePath, $InstallerMetadata)
    Expand-FFmpegArchiveSafely -ArchivePath $ArchivePath -Destination $ExtractPath
    $pairs = @()
    foreach ($ffmpegFile in @(Get-ChildItem -LiteralPath $ExtractPath -Filter 'ffmpeg.exe' -File -Recurse)) {
        $ffprobeFile = Join-Path $ffmpegFile.DirectoryName 'ffprobe.exe'
        if ([System.IO.File]::Exists($ffprobeFile)) { $pairs += , @{ Bin = $ffmpegFile.DirectoryName; Root = $ffmpegFile.Directory.Parent.FullName } }
    }
    if ($pairs.Count -ne 1) { throw 'The verified FFmpeg archive must contain exactly one matching ffmpeg/ffprobe x64 pair.' }
    $binRoot = [string]$pairs[0].Bin; $buildRoot = [string]$pairs[0].Root
    $sourceLicense = Join-Path $buildRoot 'LICENSE'; $sourceReadme = Join-Path $buildRoot 'README.txt'
    if (-not [System.IO.File]::Exists($sourceLicense) -or -not [System.IO.File]::Exists($sourceReadme)) { throw 'The FFmpeg package is missing its upstream license or build README.' }
    $licenseText = [System.IO.File]::ReadAllText($sourceLicense); $readmeText = [System.IO.File]::ReadAllText($sourceReadme)
    $readmeVersionPattern = '(?mi)^Version:\s*' + [regex]::Escape([string]$InstallerMetadata.PackageVersion) + '(?:-[^\r\n]*)?\s*$'
    if ($licenseText -notmatch '(?im)^\s*GNU GENERAL PUBLIC LICENSE\s*$' -or $licenseText -notmatch '(?im)^\s*Version 3, 29 June 2007\s*$' -or $readmeText -notmatch $readmeVersionPattern -or $readmeText -notmatch '(?mi)^License:\s*GPL v3\s*$') { throw 'The FFmpeg package license or Gyan build README did not verify as the expected GPL-3.0 runtime/version.' }
    $candidateBin = Join-Path $CandidatePath 'bin'; $licenseRoot = Join-Path $CandidatePath 'LICENSES'
    [void](New-Item -ItemType Directory -Path $candidateBin -Force); [void](New-Item -ItemType Directory -Path $licenseRoot -Force)
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) { [System.IO.File]::Copy((Join-Path $binRoot $name), (Join-Path $candidateBin $name), $false) }
    $dllFiles = @(Get-ChildItem -LiteralPath $binRoot -Filter '*.dll' -File | Sort-Object Name)
    if ($dllFiles.Count -eq 0) { throw 'The FFmpeg shared build contains no runtime DLLs.' }
    foreach ($dll in $dllFiles) { [System.IO.File]::Copy($dll.FullName, (Join-Path $candidateBin $dll.Name), $false) }
    [System.IO.File]::Copy($sourceLicense, (Join-Path $licenseRoot 'COPYING.GPLv3'), $false)
    [System.IO.File]::Copy($sourceReadme, (Join-Path $licenseRoot 'Gyan-README.txt'), $false)
    $versionText = $InstallerMetadata.PackageVersion + "`r`n"
    $sourceText = @('Package: ' + [string]$InstallerMetadata.PackageId, 'PackageVersion: ' + [string]$InstallerMetadata.PackageVersion, 'Architecture: x64', 'PackageSource: WinGet source winget', 'InstallerURL: ' + [string]$InstallerMetadata.InstallerUrl, 'InstallerSHA256: ' + [string]$InstallerMetadata.InstallerSha256, 'Acquired: ' + (Get-Date -Format 'yyyy-MM-dd')) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $CandidatePath 'VERSION'), $versionText, (New-Object System.Text.ASCIIEncoding))
    [System.IO.File]::WriteAllText((Join-Path $CandidatePath 'SOURCE.txt'), ($sourceText + "`r`n"), (New-Object System.Text.ASCIIEncoding))
    $records = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $candidateBin -File | Sort-Object Name)) {
        if ($file.Extension -notin @('.exe', '.dll') -or $file.Name -eq 'ffplay.exe') { throw 'The staged FFmpeg runtime contains an unsupported executable or library.' }
        $relative = 'FFmpeg/bin/' + $file.Name
        $records += , ([pscustomobject]@{ Path = $relative; Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant(); Bytes = [long]$file.Length })
    }
    foreach ($required in @('ffmpeg.exe', 'ffprobe.exe')) { if (@($records | Where-Object { $_.Path -eq ('FFmpeg/bin/' + $required) }).Count -ne 1) { throw ('The staged FFmpeg runtime is missing ' + $required + '.') } }
    return , $records
}

function Get-VerifiedFFmpegRuntimeForPackaging {
    <# Downloads the manifest-pinned package only after explicit caller opt-in; it never changes the active runtime. #>
    param([Parameter(Mandatory)][string]$Destination, [switch]$Confirmed, [scriptblock]$OnTick)
    if (-not $Confirmed) { return [pscustomobject]@{ Ready = $false; State = 'Declined'; Message = 'No FFmpeg package was downloaded.'; Path = ''; Version = '' } }
    if (-not (Test-IsWindows)) { return [pscustomobject]@{ Ready = $false; State = 'Unavailable'; Message = 'The verified WinGet release-package acquisition is supported only on Windows.'; Path = ''; Version = '' } }
    $destinationFull = [System.IO.Path]::GetFullPath($Destination)
    if ([System.IO.File]::Exists($destinationFull) -or [System.IO.Directory]::Exists($destinationFull)) { return [pscustomobject]@{ Ready = $false; State = 'Rejected'; Message = 'The package staging destination already exists and will not be overwritten.'; Path = ''; Version = '' } }
    $createdDestination = $false; $state = 'Failed'; $message = ''; $candidatePath = ''; $version = ''
    try {
        $library = Get-ExternalLibraryDefinition -Id 'ffmpeg'
        $version = [string]$library.PackageVersion
        if (-not (Test-SemVer $version) -or $version -match '-' -or [string]$library.CurrentVersion -ne $version) { throw 'The FFmpeg package version is not a stable exact match for the canonical runtime manifest.' }
        $metadata = $null
        if ($script:ExternalLibraryHooks.PackageMetadata) { $metadata = & $script:ExternalLibraryHooks.PackageMetadata $version }
        else { $metadata = Get-FFmpegWingetInstallerMetadata -PackageVersion $version }
        if ([string]$metadata.PackageId -ne [string]$library.PackageManagerId -or [string]$metadata.PackageVersion -ne $version -or [string]$metadata.Architecture -ne 'x64' -or [string]$metadata.InstallerType -ne 'zip' -or [string]$metadata.InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not [string]::Equals([string]$metadata.InstallerSha256, [string]$library.PackageArchiveSha256, [StringComparison]::OrdinalIgnoreCase)) { throw 'Official WinGet metadata did not match the pinned package identity, version, architecture, format and manifest archive SHA-256.' }
        [void](New-Item -ItemType Directory -Path $destinationFull)
        $createdDestination = $true
        $downloadRoot = Join-Path $destinationFull 'download'
        $extractRoot = Join-Path $destinationFull 'extract'
        $candidatePath = Join-Path $destinationFull 'FFmpeg'
        [void](New-Item -ItemType Directory -Path $downloadRoot)
        $download = Invoke-FFmpegPackageDownload -PackageVersion $version -Destination $downloadRoot -InstallerMetadata $metadata -OnTick $OnTick
        if ($download -and $download.PSObject.Properties['Cancelled'] -and [bool]$download.Cancelled) { $state = 'Cancelled'; $message = 'The WinGet download was cancelled; no runtime files were changed.'; return [pscustomobject]@{ Ready = $false; State = $state; Message = $message; Path = ''; Version = $version } }
        $downloadedPath = if ($download -is [string]) { [string]$download } else { [string]$download.Path }
        if (-not $downloadedPath) { throw 'WinGet did not return the verified FFmpeg installer archive path.' }
        $downloadedPath = Get-ExternalPathUnder -Root $downloadRoot -Path $downloadedPath
        if (-not [System.IO.File]::Exists($downloadedPath) -or [System.IO.Path]::GetFileName($downloadedPath) -ne [string]$metadata.InstallerFileName) { throw 'WinGet returned an unexpected package file or path.' }
        $archiveHash = (Get-FileHash -LiteralPath $downloadedPath -Algorithm SHA256).Hash
        if (-not [string]::Equals($archiveHash, [string]$metadata.InstallerSha256, [StringComparison]::OrdinalIgnoreCase)) { throw 'The downloaded FFmpeg archive did not match the official SHA-256.' }
        $fileRecords = New-FFmpegCandidateRuntime -ArchivePath $downloadedPath -ExtractPath $extractRoot -CandidatePath $candidatePath -InstallerMetadata $metadata
        if ($fileRecords -isnot [array]) { $fileRecords = @($fileRecords) }
        if ($fileRecords.Count -ne @($library.Files).Count) { throw 'The downloaded FFmpeg runtime file inventory does not match the canonical manifest.' }
        foreach ($record in @($library.Files)) {
            $stagedRecord = @($fileRecords | Where-Object { [string]$_.Path -eq [string]$record.Path }) | Select-Object -First 1
            if (-not $stagedRecord -or -not [string]::Equals([string]$stagedRecord.Sha256, [string]$record.Sha256, [StringComparison]::OrdinalIgnoreCase)) { throw ('The downloaded runtime does not match the canonical file hash: ' + [string]$record.Path) }
        }
        $runtimeCheck = Invoke-FFmpegCandidateRuntimeCheck -FfmpegPath (Join-Path (Join-Path $candidatePath 'bin') 'ffmpeg.exe') -FfprobePath (Join-Path (Join-Path $candidatePath 'bin') 'ffprobe.exe') -ExpectedVersion $version
        if (-not $runtimeCheck.Ready) { throw ('The downloaded FFmpeg package failed the manifest capability/version/architecture self-check. ' + [string]$runtimeCheck.Detail) }
        $state = 'Ready'; $message = 'The manifest-pinned FFmpeg package passed archive, license, file-hash and runtime verification.'
        return [pscustomobject]@{ Ready = $true; State = $state; Message = $message; Path = $candidatePath; Version = $version; ArchiveSha256 = $archiveHash.ToUpperInvariant() }
    } catch { $message = 'FFmpeg package acquisition for release failed: ' + $_.Exception.Message; return [pscustomobject]@{ Ready = $false; State = $state; Message = $message; Path = ''; Version = $version } }
    finally { if ($createdDestination -and $state -ne 'Ready' -and [System.IO.Directory]::Exists($destinationFull)) { [System.IO.Directory]::Delete($destinationFull, $true) } }
}

function New-FFmpegUpdatedManifest {
    param([string]$CandidateManifestPath, [string]$PackageVersion, [string]$ArchiveHash, [object[]]$Files)
    $manifest = Get-ExternalLibraryManifest
    $definition = @($manifest.Libraries | Where-Object { [string]$_.Id -eq 'ffmpeg' }) | Select-Object -First 1
    if (-not $definition) { throw 'The canonical dependency manifest does not contain FFmpeg.' }
    $definition.CurrentVersion = $PackageVersion; $definition.PackageVersion = $PackageVersion; $definition.PackageArchiveSha256 = $ArchiveHash.ToUpperInvariant()
    $definition.AcquisitionDate = Get-Date -Format 'yyyy-MM-dd'; $definition.LastVerified = Get-Date -Format 'yyyy-MM-dd'; $definition.Files = @($Files)
    $json = $manifest | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($CandidateManifestPath, ($json + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Update-BundledFFmpeg {
    <# Downloads only after explicit UI consent, verifies WinGet's pinned package hash and runtime, then transactionally activates it. #>
    param([Parameter(Mandatory)][string]$PackageVersion, [bool]$Confirmed = $false, [scriptblock]$OnTick)
    if (-not $Confirmed) { return [pscustomobject]@{ State = 'Declined'; Message = 'No runtime files were downloaded or changed.'; Version = '' } }
    if (-not (Test-IsWindows)) { return [pscustomobject]@{ State = 'Unavailable'; Message = 'Bundled FFmpeg updates are supported only on Windows.'; Version = '' } }
    try {
        $library = Get-ExternalLibraryDefinition -Id 'ffmpeg'
        if (-not (Test-SemVer $PackageVersion) -or $PackageVersion -match '-') { throw 'The requested FFmpeg package version is not a stable Semantic Version.' }
        if ((Compare-SemVerPrecedence -Left $PackageVersion -Right ([string]$library.PackageVersion)) -le 0) { return [pscustomobject]@{ State = 'NotNewer'; Message = 'The requested WinGet package is not newer than the bundled runtime.'; Version = $PackageVersion } }
        $root = Get-AppRoot
        $externalRoot = Join-Path $root 'External-Libraries'; $activePath = Join-Path $externalRoot 'FFmpeg'; $manifestPath = Join-Path $externalRoot 'manifest.json'
        if (-not [System.IO.Directory]::Exists($activePath)) { return [pscustomobject]@{ State = 'Unavailable'; Message = 'This edition has no bundled FFmpeg directory to update; the system FFmpeg was not changed.'; Version = '' } }
        $installerMetadata = $null
        if ($script:ExternalLibraryHooks.PackageMetadata) { $installerMetadata = & $script:ExternalLibraryHooks.PackageMetadata $PackageVersion }
        else { $installerMetadata = Get-FFmpegWingetInstallerMetadata -PackageVersion $PackageVersion }
        if ([string]$installerMetadata.PackageId -ne [string]$library.PackageManagerId -or [string]$installerMetadata.PackageVersion -ne $PackageVersion -or [string]$installerMetadata.Architecture -ne 'x64' -or [string]$installerMetadata.InstallerType -ne 'zip' -or [string]$installerMetadata.InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'The official package metadata failed package id, version, architecture, format or checksum verification.' }
        $transactionId = [guid]::NewGuid().ToString('N')
        $stagePath = Join-Path $externalRoot ('.stage-' + $transactionId)
        [void](New-Item -ItemType Directory -Path $stagePath -Force)
        $preserveStage = $false; $result = $null
        try {
            $downloadPath = Join-Path $stagePath 'download'; $extractPath = Join-Path $stagePath 'extract'; $candidatePath = Join-Path $stagePath 'FFmpeg'; $candidateManifestPath = Join-Path $stagePath 'manifest.json'
            [void](New-Item -ItemType Directory -Path $downloadPath -Force)
            $download = Invoke-FFmpegPackageDownload -PackageVersion $PackageVersion -Destination $downloadPath -InstallerMetadata $installerMetadata -OnTick $OnTick
            if ($download -and $download.PSObject.Properties['Cancelled'] -and [bool]$download.Cancelled) { $result = [pscustomobject]@{ State = 'Cancelled'; Message = 'The WinGet download was cancelled; the installed runtime was not changed.'; Version = $PackageVersion; BackupPath = ''; BackupManifestPath = '' }; return $result }
            if ($download -is [string]) { $downloadPathResolved = [string]$download } else { $downloadPathResolved = [string]$download.Path }
            if (-not $downloadPathResolved) { throw 'WinGet did not return the staged FFmpeg installer path.' }
            $downloadPathResolved = Get-ExternalPathUnder -Root $downloadPath -Path $downloadPathResolved
            if (-not [System.IO.File]::Exists($downloadPathResolved) -or [System.IO.Path]::GetFileName($downloadPathResolved) -ne [string]$installerMetadata.InstallerFileName) { throw 'The staged package did not match the exact verified installer filename.' }
            $archiveHash = (Get-FileHash -LiteralPath $downloadPathResolved -Algorithm SHA256).Hash.ToUpperInvariant()
            if (-not [string]::Equals($archiveHash, [string]$installerMetadata.InstallerSha256, [StringComparison]::OrdinalIgnoreCase)) { throw 'The downloaded FFmpeg archive SHA-256 does not match the official WinGet package manifest.' }
            $fileRecords = New-FFmpegCandidateRuntime -ArchivePath $downloadPathResolved -ExtractPath $extractPath -CandidatePath $candidatePath -InstallerMetadata $installerMetadata
            $ffmpegPath = Join-Path (Join-Path $candidatePath 'bin') 'ffmpeg.exe'; $ffprobePath = Join-Path (Join-Path $candidatePath 'bin') 'ffprobe.exe'
            $runtimeCheck = Invoke-FFmpegCandidateRuntimeCheck -FfmpegPath $ffmpegPath -FfprobePath $ffprobePath -ExpectedVersion $PackageVersion
            if (-not $runtimeCheck.Ready) { throw ('The staged FFmpeg runtime did not pass version/architecture/capability checks. ' + [string]$runtimeCheck.Detail) }
            New-FFmpegUpdatedManifest -CandidateManifestPath $candidateManifestPath -PackageVersion $PackageVersion -ArchiveHash $archiveHash -Files $fileRecords
            $candidateValidator = { param($candidate) return ((Test-Path -LiteralPath (Join-Path (Join-Path $candidate 'bin') 'ffmpeg.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path (Join-Path $candidate 'bin') 'ffprobe.exe') -PathType Leaf)) }
            $activeValidator = { param($active) $check = Invoke-FFmpegCandidateRuntimeCheck -FfmpegPath (Join-Path (Join-Path $active 'bin') 'ffmpeg.exe') -FfprobePath (Join-Path (Join-Path $active 'bin') 'ffprobe.exe') -ExpectedVersion $PackageVersion; return [bool]$check.Ready }
            $swap = Invoke-ExternalRuntimeSwap -ActivePath $activePath -CandidatePath $candidatePath -ActiveManifestPath $manifestPath -CandidateManifestPath $candidateManifestPath -ValidateCandidate $candidateValidator -ValidateActive $activeValidator
            $result = [pscustomobject]@{ State = [string]$swap.State; Message = [string]$swap.Message; Version = $PackageVersion; BackupPath = [string]$swap.BackupPath; BackupManifestPath = [string]$swap.BackupManifestPath }
            if ($swap.State -eq 'RollbackFailed') { $preserveStage = $true }
        } finally {
            if (-not $preserveStage -and [System.IO.Directory]::Exists($stagePath)) {
                try { Remove-ExternalRuntimeDirectory -Path $stagePath }
                catch {
                    if ($result) { if ($result.State -eq 'Updated') { $result.State = 'UpdatedWithBackup' }; $result.Message += (' Staging cleanup was incomplete; staging remains at ' + $stagePath + '.') }
                    else { throw ('FFmpeg update staging could not be cleaned at ' + $stagePath + ': ' + $_.Exception.Message) }
                }
            }
        }
        return $result
    } catch { return [pscustomobject]@{ State = 'Failed'; Message = ('The bundled FFmpeg update was not applied: ' + $_.Exception.Message); Version = $PackageVersion } }
}

function Get-BundledAssimpPath {
    $root = Get-AppRoot
    if (-not $root) { return '' }
    $path = Join-Path (Join-Path (Join-Path (Join-Path $root 'External-Libraries') 'Assimp') 'bin') 'assimp.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return ''
}

Export-ModuleMember -Function Set-ExternalLibraryHooks, Invoke-ExternalRuntimeSwap, Update-BundledFFmpeg, Get-VerifiedFFmpegRuntimeForPackaging, ConvertFrom-FFmpegWingetInstallerManifest, Get-ExternalLibraryManifest, Get-ExternalLibraryDefinition, Compare-SemVerPrecedence, Compare-ExternalPackageVersion, Get-ExternalPackageMetadataVersion, Get-ExternalLibraryUpdateStatus, Get-ExternalLibraryUpdateStatuses, Get-BundledAssimpPath
