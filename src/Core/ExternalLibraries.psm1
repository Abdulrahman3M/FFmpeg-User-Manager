# ExternalLibraries.psm1 - read-only update checks for libraries bundled by this project.
Set-StrictMode -Version 2.0

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

function Get-BundledAssimpPath {
    $root = Get-AppRoot
    if (-not $root) { return '' }
    $path = Join-Path (Join-Path (Join-Path (Join-Path $root 'External-Libraries') 'Assimp') 'bin') 'assimp.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return ''
}

Export-ModuleMember -Function Get-ExternalLibraryManifest, Get-ExternalLibraryDefinition, Compare-SemVerPrecedence, Compare-ExternalPackageVersion, Get-ExternalPackageMetadataVersion, Get-ExternalLibraryUpdateStatus, Get-ExternalLibraryUpdateStatuses, Get-BundledAssimpPath
