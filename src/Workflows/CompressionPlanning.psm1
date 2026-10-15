# CompressionPlanning.psm1 - shared size, quality preset, and result planning.
Set-StrictMode -Version 2.0

$script:CompressionOverheadFactor = 0.97
$script:CompressionTargetTolerance = 0.05
$script:MinimumPracticalVideoBitrate = 50000
$script:MinimumPracticalAudioBitrate = 8000

function Get-CompressionPreset {
    param(
        [Parameter(Mandatory)][string]$Encoder,
        [Parameter(Mandatory)][ValidateSet('Light', 'Balanced', 'Strong', 'Maximum')][string]$Preset
    )
    $profile = Get-EncoderProfile $Encoder
    $risk = switch ($Preset) {
        'Light' { 'Low' }
        'Balanced' { 'Moderate' }
        'Strong' { 'High' }
        'Maximum' { 'Very high' }
    }
    if ($profile.Quality -eq 'none') {
        $baseRate = [int64]$profile.DefaultBitrate
        if ($baseRate -le 0) { $baseRate = 5000000 }
        $factor = switch ($Preset) { 'Light' { 1.25 } 'Balanced' { 1.0 } 'Strong' { 0.75 } 'Maximum' { 0.5 } }
        return [pscustomobject]@{ Mode = 'Bitrate'; Quality = $null; BitrateBps = [int64][math]::Max(1, [math]::Round($baseRate * $factor)); QualityFlag = 'none'; QualityRisk = $risk }
    }
    $quality = switch ($Preset) {
        'Light' { $profile.High }
        'Balanced' { $profile.Balanced }
        'Strong' { $profile.Small }
        'Maximum' { if ($profile.Quality -eq 'vtq') { $profile.Min } else { $profile.Max } }
    }
    return [pscustomobject]@{ Mode = 'Quality'; Quality = [int]$quality; BitrateBps = $null; QualityFlag = [string]$profile.Quality; QualityRisk = $risk }
}

function Get-AudioCompressionPreset {
    param(
        [Parameter(Mandatory)][string]$Encoder,
        [Parameter(Mandatory)][ValidateSet('Light', 'Balanced', 'Strong', 'Maximum')][string]$Preset
    )
    $codec = $Encoder.ToLowerInvariant()
    if ($codec -eq 'libmp3lame') {
        $quality = switch ($Preset) {
            'Light' { 0 }
            'Balanced' { 2 }
            'Strong' { 5 }
            'Maximum' { 8 }
        }
        return [pscustomobject]@{ Mode = 'Quality'; Quality = $quality; BitrateBps = $null; Lossless = $false }
    }
    if ($codec -eq 'libvorbis') {
        $quality = switch ($Preset) {
            'Light' { 8 }
            'Balanced' { 6 }
            'Strong' { 4 }
            'Maximum' { 2 }
        }
        return [pscustomobject]@{ Mode = 'Quality'; Quality = $quality; BitrateBps = $null; Lossless = $false }
    }
    if ($codec -in @('flac', 'alac', 'pcm_s16le', 'pcm_s24le')) {
        return [pscustomobject]@{ Mode = 'Lossless'; Quality = $null; BitrateBps = $null; Lossless = $true }
    }
    $rate = switch ($Preset) { 'Light' { 192000 } 'Balanced' { 128000 } 'Strong' { 96000 } 'Maximum' { 64000 } }
    return [pscustomobject]@{ Mode = 'Bitrate'; Quality = $null; BitrateBps = [int64]$rate; Lossless = $false }
}

function Get-CompressionTargetBytes {
    param(
        [Parameter(Mandatory)][long]$SourceBytes,
        [Parameter(Mandatory)][ValidateSet('TargetSize', 'TargetReduction')][string]$Mode,
        [Parameter(Mandatory)][double]$Value
    )
    if ($SourceBytes -le 0) { throw 'The source file size must be greater than zero.' }
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { throw 'Enter a finite target value.' }
    if ($Mode -eq 'TargetSize') {
        if ($Value -le 0 -or $Value -gt [long]::MaxValue) { throw 'Target size must be a positive number of bytes.' }
        $targetBytes = [long][math]::Round($Value, 0, [MidpointRounding]::AwayFromZero)
        if ($targetBytes -ge $SourceBytes) { throw 'Target size must be smaller than the source file to request compression.' }
        return $targetBytes
    }
    if ($Value -le 0 -or $Value -ge 100) { throw 'Target reduction must be greater than 0% and less than 100%.' }
    $target = [double]$SourceBytes * (1.0 - ($Value / 100.0))
    if ($target -lt 1 -or $target -gt [long]::MaxValue) { throw 'The requested reduction is outside the supported size range.' }
    $roundedTarget = [math]::Round($target, 0, [MidpointRounding]::AwayFromZero)
    if ($roundedTarget -lt 1 -or $roundedTarget -ge $SourceBytes) { throw 'The requested reduction must produce a positive target smaller than the source.' }
    return [long]$roundedTarget
}

function ConvertFrom-CompressionSizeText {
    param([Parameter(Mandatory)][string]$Text)
    $normalized = $Text.Trim().ToUpperInvariant().Replace(',', '.')
    $match = [regex]::Match($normalized, '^([0-9]+(?:\.[0-9]+)?)\s*(B|KB|KIB|MB|MIB|GB|GIB)$')
    if (-not $match.Success) { throw 'Enter a size with a unit, for example 25 MB, 512 KB, or 1.5 GB.' }
    $number = [double]::Parse($match.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    $factor = switch ($match.Groups[2].Value) {
        'B' { 1.0 }
        { $_ -in @('KB', 'KIB') } { 1KB }
        { $_ -in @('MB', 'MIB') } { 1MB }
        { $_ -in @('GB', 'GIB') } { 1GB }
    }
    $bytes = $number * $factor
    if ($number -le 0 -or [double]::IsNaN($bytes) -or [double]::IsInfinity($bytes) -or $bytes -gt [long]::MaxValue) { throw 'Target size must be a positive value within the supported range.' }
    return [long][math]::Round($bytes, 0, [MidpointRounding]::AwayFromZero)
}

function Get-ImageCompressionProfile {
    param(
        [Parameter(Mandatory)][string]$Format,
        [ValidateSet('Light', 'Balanced', 'Strong', 'Maximum')][string]$Preset = 'Balanced',
        [switch]$Lossless
    )
    $imageFormat = $Format.TrimStart('.').ToLowerInvariant()
    if ($imageFormat -eq 'jpg') { $imageFormat = 'jpeg' }
    switch ($imageFormat) {
        'jpeg' {
            $quality = switch ($Preset) { 'Light' { 2 } 'Balanced' { 4 } 'Strong' { 9 } 'Maximum' { 18 } }
            return [pscustomobject]@{ Format = 'jpeg'; Extension = '.jpg'; Encoder = 'mjpeg'; Muxer = 'image2'; QualityFlag = 'qscale'; Quality = $quality; CompressionLevel = $null; Lossless = $false; SupportsAlpha = $false }
        }
        'png' {
            $prediction = switch ($Preset) { 'Light' { 0 } 'Balanced' { 1 } 'Strong' { 4 } 'Maximum' { 5 } }
            return [pscustomobject]@{ Format = 'png'; Extension = '.png'; Encoder = 'png'; Muxer = 'image2'; QualityFlag = ''; Quality = $null; Prediction = $prediction; Lossless = $true; SupportsAlpha = $true }
        }
        'webp' {
            if ($Lossless) { $quality = 100 } else { $quality = switch ($Preset) { 'Light' { 95 } 'Balanced' { 85 } 'Strong' { 70 } 'Maximum' { 50 } } }
            return [pscustomobject]@{ Format = 'webp'; Extension = '.webp'; Encoder = 'libwebp'; Muxer = 'webp'; QualityFlag = 'quality'; Quality = $quality; Prediction = $null; Lossless = [bool]$Lossless; SupportsAlpha = $true }
        }
        default { throw 'Only JPEG, PNG, or WebP input can be compressed by this workflow.' }
    }
}

function Get-AvailableImageCompressionFormats {
    $formats = @(
        @{ Format = 'jpeg'; Label = 'JPEG'; Extension = '.jpg'; Encoder = 'mjpeg'; Muxer = 'image2'; Lossless = $false },
        @{ Format = 'png'; Label = 'PNG'; Extension = '.png'; Encoder = 'png'; Muxer = 'image2'; Lossless = $true },
        @{ Format = 'webp'; Label = 'WebP'; Extension = '.webp'; Encoder = 'libwebp'; Muxer = 'webp'; Lossless = $false }
    )
    $available = @()
    foreach ($format in $formats) {
        if ((Test-FFEncoder $format.Encoder) -and (Test-FFMuxer $format.Muxer)) { $available += , $format }
    }
    return $available
}

function Get-ImageCompressionCandidates {
    param([Parameter(Mandatory)][ValidateSet('jpeg', 'jpg', 'png', 'webp')][string]$Format)
    switch ($Format.ToLowerInvariant()) {
        { $_ -in @('jpeg', 'jpg') } { return @(2, 4, 6, 9, 13, 18, 24, 31) }
        'png' { return @() }
        'webp' { return @(100, 90, 80, 70, 55, 40, 25, 10) }
    }
}

function Get-BestImageCandidateIndex {
    param([long[]]$CandidateSizes, [Parameter(Mandatory)][long]$TargetBytes, [double]$Tolerance = $script:CompressionTargetTolerance)
    $sizes = @($CandidateSizes)
    if ($sizes.Count -eq 0) { throw 'At least one encoded image candidate is required.' }
    if ($TargetBytes -le 0) { throw 'Target size must be greater than zero.' }
    if ([double]::IsNaN($Tolerance) -or [double]::IsInfinity($Tolerance) -or $Tolerance -lt 0 -or $Tolerance -ge 1) { throw 'Target tolerance must be at least zero and less than one.' }
    $maximumBytes = [double]$TargetBytes * (1.0 + $Tolerance)
    $smallestIndex = 0
    $smallestBytes = [long]::MaxValue
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        if ($sizes[$i] -le 0) { continue }
        if ($sizes[$i] -lt $smallestBytes) { $smallestBytes = $sizes[$i]; $smallestIndex = $i }
        if ($sizes[$i] -le $maximumBytes) { return $i }
    }
    if ($smallestBytes -eq [long]::MaxValue) { throw 'No image candidate produced a non-empty output.' }
    return $smallestIndex
}

function Get-CompressionTargetAssessment {
    param([Parameter(Mandatory)][long]$SourceBytes, [Parameter(Mandatory)][long]$TargetBytes)
    if ($SourceBytes -le 0) { throw 'The source file size must be greater than zero.' }
    if ($TargetBytes -le 0 -or $TargetBytes -ge $SourceBytes) { throw 'The target must be greater than zero and smaller than the source.' }
    $reduction = 100.0 * (1.0 - ([double]$TargetBytes / [double]$SourceBytes))
    $risk = 'Context-dependent'
    if ($reduction -ge 70.0) { $risk = 'High' }
    elseif ($reduction -ge 40.0) { $risk = 'Elevated' }
    return [pscustomobject]@{ ReductionPercent = [math]::Round($reduction, 1); QualityRisk = $risk; Warn = ($reduction -ge 50.0) }
}

function Test-CompressionTargetMet {
    param([Parameter(Mandatory)][long]$OutputBytes, [Parameter(Mandatory)][long]$TargetBytes, [double]$Tolerance = $script:CompressionTargetTolerance)
    if ($OutputBytes -le 0 -or $TargetBytes -le 0) { return $false }
    if ([double]::IsNaN($Tolerance) -or [double]::IsInfinity($Tolerance) -or $Tolerance -lt 0 -or $Tolerance -ge 1) { throw 'Target tolerance must be at least zero and less than one.' }
    return ([double]$OutputBytes -le ([double]$TargetBytes * (1.0 + $Tolerance)))
}

function Get-CompressionBitratePlan {
    param(
        [Parameter(Mandatory)][long]$TargetBytes,
        [Parameter(Mandatory)][double]$DurationSec,
        [double]$AudioBps = 0,
        [ValidateSet('Video', 'Audio')][string]$MediaType = 'Video'
    )
    if ($TargetBytes -le 0) { throw 'Target size must be greater than zero.' }
    if ([double]::IsNaN($DurationSec) -or [double]::IsInfinity($DurationSec) -or $DurationSec -le 0) { throw 'The media duration is unknown, so a target bitrate cannot be calculated.' }
    if ([double]::IsNaN($AudioBps) -or [double]::IsInfinity($AudioBps) -or $AudioBps -lt 0) { throw 'Audio bitrate must be zero or a positive finite number.' }
    $totalRate = ([double]$TargetBytes * 8.0 * $script:CompressionOverheadFactor) / $DurationSec
    if ([double]::IsNaN($totalRate) -or [double]::IsInfinity($totalRate) -or $totalRate -gt [long]::MaxValue) { throw 'The requested bitrate is outside the supported numeric range.' }
    $totalBps = [int64][math]::Floor($totalRate)
    if ($MediaType -eq 'Audio') {
        if ($totalBps -lt $script:MinimumPracticalAudioBitrate) { throw 'The target leaves too little bitrate for usable audio. Choose a larger target size.' }
        return [pscustomobject]@{ TargetTotalBitrateBps = $totalBps; VideoBitrateBps = [int64]0; AudioBitrateBps = $totalBps; OverheadFactor = $script:CompressionOverheadFactor }
    }
    $videoBps = $totalBps - [int64][math]::Floor($AudioBps)
    if ($videoBps -lt $script:MinimumPracticalVideoBitrate) { throw 'The target size or audio bitrate leaves too little bitrate for usable video. Choose a larger target or reduce the audio bitrate.' }
    return [pscustomobject]@{ TargetTotalBitrateBps = $totalBps; VideoBitrateBps = $videoBps; AudioBitrateBps = [int64][math]::Floor($AudioBps); OverheadFactor = $script:CompressionOverheadFactor }
}

function Get-CompressionResultMetrics {
    param([long]$SourceBytes, [long]$OutputBytes, $TargetBytes = $null)
    if ($SourceBytes -le 0) { throw 'The source file size must be greater than zero.' }
    if ($OutputBytes -lt 0) { throw 'The output file size cannot be negative.' }
    $saved = $SourceBytes - $OutputBytes
    $reduction = 100.0 * [double]$saved / [double]$SourceBytes
    $difference = $null
    if ($null -ne $TargetBytes) { $difference = [int64]$OutputBytes - [int64]$TargetBytes }
    return [pscustomobject]@{ SourceBytes = $SourceBytes; OutputBytes = $OutputBytes; BytesSaved = [int64]$saved; ReductionPercent = [math]::Round($reduction, 2); TargetBytes = $TargetBytes; TargetDifferenceBytes = $difference; TargetTolerance = $script:CompressionTargetTolerance }
}

function Get-CompressionTargetTolerance { return $script:CompressionTargetTolerance }

Export-ModuleMember -Function Get-CompressionPreset, Get-AudioCompressionPreset, Get-CompressionTargetBytes, ConvertFrom-CompressionSizeText, Get-ImageCompressionProfile, Get-AvailableImageCompressionFormats, Get-ImageCompressionCandidates, Get-BestImageCandidateIndex, Get-CompressionTargetAssessment, Test-CompressionTargetMet, Get-CompressionBitratePlan, Get-CompressionResultMetrics, Get-CompressionTargetTolerance
