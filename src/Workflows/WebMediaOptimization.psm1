# WebMediaOptimization.psm1 - web-oriented video size estimates and media workflows.
Set-StrictMode -Version 2.0

function Get-WebBitrateEstimate {
    param(
        [double]$DurationSec,
        [double]$VideoBitrateKbps,
        [double]$AudioBitrateKbps = 0
    )
    if ([double]::IsNaN($DurationSec) -or [double]::IsInfinity($DurationSec) -or $DurationSec -le 0) { throw 'Duration must be a positive finite number.' }
    if ([double]::IsNaN($VideoBitrateKbps) -or [double]::IsInfinity($VideoBitrateKbps) -or $VideoBitrateKbps -le 0) { throw 'Video bitrate must be a positive finite number.' }
    if ([double]::IsNaN($AudioBitrateKbps) -or [double]::IsInfinity($AudioBitrateKbps) -or $AudioBitrateKbps -lt 0) { throw 'Audio bitrate must be zero or a positive finite number.' }
    $expected = ($VideoBitrateKbps + $AudioBitrateKbps) * 1000 * $DurationSec / 8
    if ([double]::IsNaN($expected) -or [double]::IsInfinity($expected) -or $expected -gt [long]::MaxValue) { throw 'The requested estimate is outside the supported numeric range.' }
    $expectedBytes = [long][math]::Round($expected, 0, [MidpointRounding]::AwayFromZero)
    return [pscustomobject]@{
        Method = 'Target bitrate'
        SampleCount = 0
        LowBytes = [long][math]::Floor($expectedBytes * 0.95)
        ExpectedBytes = $expectedBytes
        HighBytes = [long][math]::Ceiling($expectedBytes * 1.05)
    }
}

function Get-WebSampleEstimate {
    param(
        [long[]]$SampleBytes,
        [double[]]$SampleDurations,
        [double]$DurationSec
    )
    if ([double]::IsNaN($DurationSec) -or [double]::IsInfinity($DurationSec) -or $DurationSec -le 0) { throw 'Duration must be a positive finite number.' }
    $bytes = @($SampleBytes)
    $durations = @($SampleDurations)
    if ($bytes.Count -ne 3 -or $durations.Count -ne 3) { throw 'Exactly three sample files and durations are required.' }
    $rates = @()
    for ($i = 0; $i -lt 3; $i++) {
        if ($bytes[$i] -le 0) { throw 'Every sample must produce a non-empty output file.' }
        if ([double]::IsNaN($durations[$i]) -or [double]::IsInfinity($durations[$i]) -or $durations[$i] -le 0) { throw 'Every sample duration must be a positive finite number.' }
        $rates += , ([double]$bytes[$i] / [double]$durations[$i])
    }
    $expected = (($rates[0] + $rates[1] + $rates[2]) / 3) * $DurationSec
    $low = [math]::Min($rates[0], [math]::Min($rates[1], $rates[2])) * $DurationSec * 0.95
    $high = [math]::Max($rates[0], [math]::Max($rates[1], $rates[2])) * $DurationSec * 1.05
    if ($high -gt [long]::MaxValue) { throw 'The requested estimate is outside the supported numeric range.' }
    return [pscustomobject]@{
        Method = '3-sample analysis'
        SampleCount = 3
        LowBytes = [long][math]::Floor($low)
        ExpectedBytes = [long][math]::Round($expected, 0, [MidpointRounding]::AwayFromZero)
        HighBytes = [long][math]::Ceiling($high)
    }
}

function Get-WebMCodecChoices {
    if (-not (Test-FFMuxer 'webm')) { return @() }
    $choices = @()
    if (Test-FFEncoder 'libvpx-vp9') {
        $choices += , @{ Id = 'vp9'; Label = 'VP9'; Encoder = 'libvpx-vp9'; Desc = 'Efficient WebM video supported by this FFmpeg build.' }
    }
    if (Test-FFEncoder 'libsvtav1') {
        $choices += , @{ Id = 'av1'; Label = 'AV1 (SVT-AV1)'; Encoder = 'libsvtav1'; Desc = 'Modern, efficient AV1 video supported by this FFmpeg build.' }
    } elseif (Test-FFEncoder 'libaom-av1') {
        $choices += , @{ Id = 'av1'; Label = 'AV1 (libaom)'; Encoder = 'libaom-av1'; Desc = 'Modern, efficient AV1 video supported by this FFmpeg build.' }
    }
    return $choices
}

function Get-WebMQualityTokens {
    param([ValidateSet('vp9', 'av1')][string]$Codec, [ValidateSet('high', 'balanced', 'small', 'custom')][string]$Quality, [int]$CustomValue = -1)
    $codecInfo = @(Get-WebMCodecChoices | Where-Object { $_.Id -eq $Codec }) | Select-Object -First 1
    if (-not $codecInfo) { throw "The selected WebM codec is not available in this FFmpeg build: $Codec" }
    switch ($Quality) {
        'high' { $crf = 30; $speed = 2 }
        'balanced' { $crf = 34; $speed = 3 }
        'small' { $crf = 40; $speed = 4 }
        'custom' {
            if ($CustomValue -lt 0 -or $CustomValue -gt 63) { throw 'Custom WebM quality must be an integer from 0 to 63.' }
            $crf = $CustomValue; $speed = 3
        }
    }
    if ($codecInfo.Encoder -eq 'libvpx-vp9') {
        return @('-c:v', $codecInfo.Encoder, '-crf', [string]$crf, '-b:v', '0', '-deadline', 'good', '-cpu-used', [string]$speed)
    }
    if ($codecInfo.Encoder -eq 'libsvtav1') {
        return @('-c:v', $codecInfo.Encoder, '-crf', [string]$crf, '-preset', '8')
    }
    return @('-c:v', $codecInfo.Encoder, '-crf', [string]$crf, '-b:v', '0', '-cpu-used', '4')
}

function Get-WebMAudioUnavailableReason {
    if (-not (Test-FFEncoder 'libopus') -and -not (Test-FFEncoder 'libvorbis')) { return 'No compatible WebM audio encoder (Opus or Vorbis) is installed; choose No audio or add a supported encoder to FFmpeg.' }
    return ''
}

function Get-WebMAudioTokens {
    param([ValidateSet('auto', 'copy', 'opus', 'vorbis', 'none')][string]$Mode, [string]$InputCodec = '')
    $codec = ([string]$InputCodec).ToLowerInvariant()
    if ($Mode -eq 'none') { return @('-an') }
    if ($Mode -eq 'auto' -and $codec -in @('opus', 'vorbis')) { return @('-c:a', 'copy') }
    if ($Mode -eq 'copy') {
        if ($codec -notin @('opus', 'vorbis')) { throw 'WebM can copy only Opus or Vorbis audio. Choose automatic encoding or no audio.' }
        return @('-c:a', 'copy')
    }
    if ($Mode -eq 'auto') {
        if (Test-FFEncoder 'libopus') { return @('-c:a', 'libopus', '-b:a', '128k') }
        if (Test-FFEncoder 'libvorbis') { return @('-c:a', 'libvorbis', '-b:a', '128k') }
        return @()
    }
    if ($Mode -eq 'opus') {
        if (-not (Test-FFEncoder 'libopus')) { throw 'The selected Opus encoder is not available in this FFmpeg build.' }
        return @('-c:a', 'libopus', '-b:a', '128k')
    }
    if (-not (Test-FFEncoder 'libvorbis')) { throw 'The selected Vorbis encoder is not available in this FFmpeg build.' }
    return @('-c:a', 'libvorbis', '-b:a', '128k')
}

function Get-WebMScaleFilter {
    param([string]$Resolution)
    if (-not $Resolution -or $Resolution -eq 'keep') { return '' }
    return Get-ResolutionFilter -Value $Resolution
}

function New-WebMArguments {
    param([string]$InputPath, [string]$OutputPath, [string[]]$VideoTokens, [string[]]$AudioTokens = @(), [string]$Resolution = 'keep', [double]$StartSec = 0, [double]$ClipDuration = 0, [bool]$Overwrite = $false)
    $cmd = New-FFCommand
    $inputOptions = @()
    if ($StartSec -gt 0) { $inputOptions = @('-ss', (Format-FFNumber $StartSec 3)) }
    [void](Add-FFInput $cmd $InputPath $inputOptions)
    Add-FFOutOpt $cmd @('-map', '0:v:0')
    Add-FFOutOpt $cmd $VideoTokens
    Add-FFOutOpt $cmd @('-pix_fmt', 'yuv420p')
    $scale = Get-WebMScaleFilter $Resolution
    if ($scale) { Add-FFOutOpt $cmd @('-vf', $scale) }
    if ($AudioTokens.Count -gt 0 -and $AudioTokens[0] -ne '-an') {
        Add-FFOutOpt $cmd @('-map', '0:a:0?')
        Add-FFOutOpt $cmd $AudioTokens
    } elseif ($AudioTokens.Count -gt 0) {
        Add-FFOutOpt $cmd @('-an')
    }
    if ($ClipDuration -gt 0) { Add-FFOutOpt $cmd @('-t', (Format-FFNumber $ClipDuration 3)) }
    Add-FFOutOpt $cmd @('-map_metadata', '0', '-f', 'webm')
    Set-FFOutput $cmd $OutputPath -Overwrite:$Overwrite
    return @(Get-FFTokens $cmd)
}

function Get-WebMSteps {
    if (@(Get-WebMCodecChoices).Count -eq 0) { throw 'WebM video is unavailable because this FFmpeg build lacks a WebM muxer and a supported VP9 or AV1 encoder.' }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'webmCodec'; Type = 'Choice'; Prompt = 'WebM video codec'; Help = 'Pick a VP9 or AV1 encoder installed in this FFmpeg build. Availability is detected from FFmpeg, not assumed.'
        Choices = { param($W) @(Get-WebMCodecChoices | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'vp9' }
    $steps += @{ Id = 'webmQuality'; Type = 'Choice'; Prompt = 'Video quality'; Help = 'Higher quality may create a larger file. WebM is not guaranteed to be smaller than the source.'
        Choices = { param($W) @((New-Choice 'high' 'High quality' 'Use a lower CRF value for more detail; encoding may take longer.'), (New-Choice 'balanced' 'Balanced (Recommended)' 'A practical balance of quality and file size; actual output size varies.'), (New-Choice 'small' 'Smaller output' 'Use a higher CRF value; more detail is discarded and the size is still not guaranteed.'), (New-Choice 'custom' 'Custom quality value' 'Set the encoder CRF value from 0 to 63; lower values mean higher quality.') ) }; Default = 'balanced' }
    $steps += @{ Id = 'webmCustomCrf'; Type = 'Integer'; Prompt = 'Custom WebM quality value'; Help = 'CRF is the encoder quality target from 0 (highest quality and often largest) to 63 (lowest quality and often smallest).'; Example = '34'; Min = 0; Max = 63; Label = 'CRF value'; Default = 34; When = { param($W) (Get-Answer $W 'webmQuality') -eq 'custom' } }
    $steps += Get-ResolutionStep -Id 'webmResolution' -Prompt 'Output resolution'
    $hasAudio = { param($W) $m = Get-Media $W 'input'; [bool]($m -and $m.HasAudio) }
    $steps += @{ Id = 'webmAudio'; Type = 'Choice'; Prompt = 'Audio'; Help = 'WebM supports Opus and Vorbis. Automatic copies a compatible source track or encodes it with an installed encoder.'; When = $hasAudio
        Choices = {
            param($W)
            $m = Get-Media $W 'input'; $codec = [string]$m.Audio[0].Codec
            $list = @((New-Choice 'auto' 'Automatic (Recommended)' 'Copy Opus/Vorbis, otherwise encode with the best installed WebM audio encoder.'), (New-Choice 'none' 'No audio' 'Leave all audio tracks out of the WebM output.'))
            if ($codec -in @('opus', 'vorbis')) { $list += , (New-Choice 'copy' 'Copy compatible audio' 'Keep the source Opus/Vorbis audio without re-encoding.') }
            if (Test-FFEncoder 'libopus') { $list += , (New-Choice 'opus' 'Encode Opus' 'Convert the source audio to Opus at 128 kbps.') }
            if (Test-FFEncoder 'libvorbis') { $list += , (New-Choice 'vorbis' 'Encode Vorbis' 'Convert the source audio to Vorbis at 128 kbps.') }
            if (-not (Test-FFEncoder 'libopus') -and -not (Test-FFEncoder 'libvorbis') -and $codec -notin @('opus', 'vorbis')) { $list[0].Enabled = $false; $list[0].Reason = Get-WebMAudioUnavailableReason }
            return $list
        }.GetNewClosure(); Default = 'auto' }
    $steps += @{ Id = 'estimateFirst'; Type = 'YesNo'; Prompt = 'Estimate size before converting?'; Help = 'Yes runs exactly three short WebM sample encodes (start, middle, end), then lets you continue, change settings or cancel. No full-length encode is hidden in the estimate.'; Default = $true
        YesLabel = 'Estimate with 3 short samples'; NoLabel = 'Skip the estimate'; YesDesc = 'Encode three representative short sections, then show an approximate size range.'; NoDesc = 'Start the full conversion after the final review.' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'web' -Extension { param($W) '.webm' } -NamePrompt 'Output WebM file name' -ProtectIds @('input')
    return $steps
}

function Build-WebMJob {
    param($W)
    $info = Get-Media $W 'input'
    $codecId = [string](Get-Answer $W 'webmCodec' 'vp9')
    $quality = [string](Get-Answer $W 'webmQuality' 'balanced')
    $crf = [int](Get-Answer $W 'webmCustomCrf' 34)
    $resolution = [string](Get-Answer $W 'webmResolution' 'keep')
    $audioMode = [string](Get-Answer $W 'webmAudio' 'auto')
    $sourceAudioCodec = ''
    if ($info.HasAudio) { $sourceAudioCodec = [string]$info.Audio[0].Codec }
    $audioTokens = @()
    if ($info.HasAudio) {
        $audioTokens = @(Get-WebMAudioTokens -Mode $audioMode -InputCodec $sourceAudioCodec)
        if ($audioTokens.Count -eq 0) { throw (Get-WebMAudioUnavailableReason) }
    }
    $out = Get-OutputFile $W
    $vTokens = @(Get-WebMQualityTokens -Codec $codecId -Quality $quality -CustomValue $crf)
    $tokens = @(New-WebMArguments -InputPath $info.Path -OutputPath $out.Path -VideoTokens $vTokens -AudioTokens $audioTokens -Resolution $resolution -Overwrite:$out.Overwrite)
    $codecInfo = @(Get-WebMCodecChoices | Where-Object { $_.Id -eq $codecId }) | Select-Object -First 1
    $audioLabel = if (-not $info.HasAudio -or $audioMode -eq 'none') { 'None' } elseif ($audioTokens -contains 'copy') { 'Copy ' + $sourceAudioCodec } elseif ($audioTokens -contains 'libopus') { 'Opus 128 kbps' } else { 'Vorbis 128 kbps' }
    $notes = @('WebM may be larger or smaller than the source; compare the actual before/after sizes after conversion.')
    if ($info.Audio.Count -gt 1 -and $info.HasAudio -and $audioMode -ne 'none') { $notes += 'Only the first source audio track is selected; additional audio tracks are not included.' }
    if ($info.HasSubtitles) { $notes += 'Subtitle streams are not included in this WebM conversion.' }
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten only because you confirmed it.' }
    $rows = @(@('Input', $info.FileName), @('Video codec', $codecInfo.Encoder), @('Quality', $quality + $(if ($quality -eq 'custom') { ' (CRF ' + $crf + ')' } else { '' })), @('Resolution', $resolution), @('Audio', $audioLabel), @('Output', $out.Path))
    $job = New-JobObject -Title 'Converting to WebM' -Summary $rows -Stages @(@{ Name = 'Encoding WebM video'; Arguments = $tokens; DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $true -Notes $notes
    $job.WebMSettings = @{ InputPath = $info.Path; Duration = [double]$info.Duration; VideoTokens = $vTokens; AudioTokens = $audioTokens; Resolution = $resolution; Codec = $codecId; Quality = $quality; CustomCrf = $crf; SourceAudioCodec = $sourceAudioCodec; SourceSize = $info.Size }
    $job.EstimateFirst = [bool](Get-Answer $W 'estimateFirst' $true)
    return $job
}

function New-WebMSampleEstimateJob {
    param($ConversionJob)
    $settings = $ConversionJob.WebMSettings
    $duration = [double]$settings.Duration
    if ($duration -le 0) { throw 'A valid video duration is required for a three-sample size estimate.' }
    $sampleDuration = [math]::Min(8.0, ($duration / 3.0))
    if ($sampleDuration -lt 0.15) { $sampleDuration = [math]::Max(0.1, ($duration * 0.8)) }
    $starts = @(0.0, [math]::Max(0.0, (($duration - $sampleDuration) / 2.0)), [math]::Max(0.0, ($duration - $sampleDuration)))
    $stages = @(); $tempFiles = @(); $index = 0
    foreach ($start in $starts) {
        $index++
        $samplePath = Join-Path ([System.IO.Path]::GetTempPath()) ('fftui_webm_sample_' + [guid]::NewGuid().ToString('N') + '.webm')
        $tempFiles += $samplePath
        $sampleArgs = @(New-WebMArguments -InputPath $settings.InputPath -OutputPath $samplePath -VideoTokens $settings.VideoTokens -AudioTokens $settings.AudioTokens -Resolution $settings.Resolution -StartSec ([double]$start) -ClipDuration $sampleDuration)
        $stages += , @{ Name = ('Encoding sample {0} of 3' -f $index); Arguments = $sampleArgs; DurationSec = $sampleDuration }
    }
    $job = New-JobObject -Title 'Estimating WebM output size' -Summary @(@('Method', 'Exactly three short sample encodes'), @('Sections', 'Start, middle and end of the source'), @('Full conversion', 'Not performed during estimation')) -Stages $stages -OutputPath '' -OutputKind 'Estimate' -TempFiles $tempFiles -Notes @('This is an estimate, not a guarantee. It samples the beginning, middle and end using your selected settings.', 'No full-length encode is performed. The source media remains unchanged.')
    $paths = $tempFiles; $fullDuration = $duration
    $job.FinalizeOutput = {
        param($EstimateJob, $StageResults)
        $sizes = @(); $times = @()
        foreach ($path in $paths) {
            $size = Get-FileSizeSafe $path
            if (-not $size -or $size -le 0) { throw 'A WebM sample did not produce a non-empty temporary output.' }
            $probe = Get-MediaInfo -Path $path
            if (-not $probe.Ok -or $probe.Info.Duration -le 0) { throw 'A WebM sample could not be measured.' }
            $sizes += , ([long]$size); $times += , ([double]$probe.Info.Duration)
        }
        $EstimateJob.EstimateResult = Get-WebSampleEstimate -SampleBytes $sizes -SampleDurations $times -DurationSec $fullDuration
        $EstimateJob.ResultNotes = @('Method: three actual short encodes at the start, middle and end.', 'The range reflects observed sample variation plus a modest container/measurement margin; the full result may differ.', 'No full-length output was created. Your original video was not modified.')
    }.GetNewClosure()
    return $job
}

function Start-WebMWorkflow {
    $initialAnswers = @{}
    while ($true) {
        if (@(Get-WebMCodecChoices).Count -eq 0) { $null = Show-Notice -Title 'WebM conversion unavailable' -Lines @('This FFmpeg build needs a WebM muxer and a VP9 or AV1 video encoder.', 'Install or configure an FFmpeg build with the required capabilities, then try again.') -Kind Warning; return }
        $result = Invoke-Wizard -Title 'Convert to WebM' -Description 'Create a browser-oriented WebM video using an installed VP9 or AV1 encoder.' -Icon 'Video' -Steps (Get-WebMSteps) -Build { param($W) Build-WebMJob $W } -InitialAnswers $initialAnswers
        if ($result.Status -ne 'Completed') { return }
        $job = $result.Job
        if ($job.EstimateFirst) {
            $estimateJob = New-WebMSampleEstimateJob $job
            $next = Invoke-FFJob -Job $estimateJob
            if ($next -eq 'Change') {
                $initialAnswers = @{}
                foreach ($key in $result.Answers.Keys) { $initialAnswers[$key] = $result.Answers[$key] }
                continue
            }
            if ($next -ne 'Continue') { return }
        }
        $next = Invoke-FFJob -Job $job
        if ($next -eq 'Again') { $initialAnswers = @{}; continue }
        return
    }
}

function Get-WebSizeEstimateSteps {
    $hasAudio = { param($W) $m = Get-Media $W 'webEstimateInput'; [bool]($m -and $m.HasAudio) }
    return @(
        (Get-InputFileStep -Id 'webEstimateInput' -Prompt 'Input video' -Require Video),
        @{ Id = 'webVideoKbps'; Type = 'Integer'; Prompt = 'Target video bitrate'; Help = 'Enter the planned average video bitrate in kbps. The estimate uses this value, audio bitrate, and the probed duration.'; Example = '2500'; Min = 1; Max = 100000; Label = 'Video bitrate'; Default = 2500 },
        @{ Id = 'webIncludeAudio'; Type = 'YesNo'; Prompt = 'Include audio in the estimate?'; Help = 'If the conversion will include audio, include its target bitrate in the size estimate.'; Default = $true; When = $hasAudio; YesLabel = 'Yes, include audio'; NoLabel = 'No audio'; YesDesc = 'Include the audio bitrate in the calculation.'; NoDesc = 'Estimate a video-only output.' },
        @{ Id = 'webAudioKbps'; Type = 'Integer'; Prompt = 'Target audio bitrate'; Help = 'Enter the planned audio bitrate in kbps. The estimate uses this target, not a guessed input bitrate.'; Example = '128'; Min = 1; Max = 512; Label = 'Audio bitrate'; Default = 128; When = { param($W) (Get-Answer $W 'webIncludeAudio' $false) } }
    )
}

function Build-WebSizeEstimateJob {
    param($W)
    $info = Get-Media $W 'webEstimateInput'
    $videoKbps = [double](Get-Answer $W 'webVideoKbps')
    $audioKbps = 0.0
    if ($info.HasAudio -and (Get-Answer $W 'webIncludeAudio' $true)) { $audioKbps = [double](Get-Answer $W 'webAudioKbps' 128) }
    $estimate = Get-WebBitrateEstimate -DurationSec ([double]$info.Duration) -VideoBitrateKbps $videoKbps -AudioBitrateKbps $audioKbps
    $audioLabel = if ($audioKbps -gt 0) { "$audioKbps kbps" } else { 'No audio' }
    $rows = @(@('Input duration', (Format-Duration $info.Duration)), @('Target video bitrate', "$videoKbps kbps"), @('Target audio bitrate', $audioLabel), @('Estimated output', (Format-FileSize $estimate.ExpectedBytes)), @('Likely range', ('{0} to {1}' -f (Format-FileSize $estimate.LowBytes), (Format-FileSize $estimate.HighBytes))))
    $job = New-JobObject -Title 'Video size estimate' -Summary $rows -Stages @() -OutputPath '' -OutputKind 'Estimate' -Notes @('Estimate only; no media was encoded or created.', 'Calculation: (video kbps + audio kbps) x duration seconds / 8, with a modest range for container overhead and measurement variation.', 'This estimate assumes the selected target bitrates are achieved and is not a guarantee.')
    $job.EstimateResult = $estimate
    return $job
}

function Start-WebSizeEstimateWorkflow {
    while ($true) {
        $result = Invoke-Wizard -Title 'Estimate Video Size' -Description 'Estimate a video output size from planned average video/audio bitrates and the source duration.' -Icon 'Chart' -Steps (Get-WebSizeEstimateSteps) -Build { param($W) Build-WebSizeEstimateJob $W }
        if ($result.Status -ne 'Completed') { return }
        $estimate = $result.Job.EstimateResult
        $lines = @('Method: target bitrate times the source duration.', ('Video target: ' + [string]$result.Answers['webVideoKbps'] + ' kbps'), ('Estimated size: ' + (Format-FileSize $estimate.ExpectedBytes)), ('Likely range: {0} to {1}' -f (Format-FileSize $estimate.LowBytes), (Format-FileSize $estimate.HighBytes)), '', 'This is an estimate only; no media was encoded or created.', 'Actual size may differ because of container overhead and bitrate variation.')
        if ($result.Answers.ContainsKey('webIncludeAudio') -and $result.Answers['webIncludeAudio']) { $lines += ('Audio target: ' + [string]$result.Answers['webAudioKbps'] + ' kbps') }
        $action = Show-Notice -Title 'Approximate video size' -Lines $lines -Kind Info -Actions @(@('A', 'Estimate another video'), @('M', 'Main menu'))
        if ($action -ne 'A') { return }
    }
}

function Test-WebPAvailable {
    return ((Test-FFEncoder 'libwebp') -and (Test-FFMuxer 'webp'))
}

function Get-WebPTokens {
    param([ValidateSet('maximum', 'high', 'balanced', 'small', 'custom')][string]$Quality, [switch]$Lossless, [int]$CustomValue = -1)
    if (-not (Test-WebPAvailable)) { throw 'WebP encoding is not available in this FFmpeg build.' }
    switch ($Quality) {
        'maximum' { $qualityValue = 100 }
        'high' { $qualityValue = 90 }
        'balanced' { $qualityValue = 80 }
        'small' { $qualityValue = 60 }
        'custom' {
            if ($CustomValue -lt 0 -or $CustomValue -gt 100) { throw 'Custom WebP quality must be an integer from 0 to 100.' }
            $qualityValue = $CustomValue
        }
    }
    $losslessValue = '0'
    if ($Lossless) { $losslessValue = '1'; $qualityValue = 100 }
    return @('-c:v', 'libwebp', '-lossless', $losslessValue, '-quality', [string]$qualityValue)
}

function New-WebPArguments {
    param([string]$InputPath, [string]$OutputPath, [string[]]$WebPTokens, [bool]$Overwrite = $false)
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $InputPath)
    Add-FFOutOpt $cmd @('-frames:v', '1')
    Add-FFOutOpt $cmd $WebPTokens
    Add-FFOutOpt $cmd @('-f', 'webp')
    Set-FFOutput $cmd $OutputPath -Overwrite:$Overwrite
    return @(Get-FFTokens $cmd)
}

function Get-WebPSteps {
    if (-not (Test-WebPAvailable)) { throw 'WebP encoding is unavailable because this FFmpeg build lacks the libwebp encoder or WebP muxer.' }
    $steps = @()
    $steps += @{ Id = 'webpInputMode'; Type = 'Choice'; Prompt = 'Select images'; Help = 'Choose one or more files, or scan a folder. Only PNG, JPG and JPEG images are included.'
        Choices = { param($W) @((New-Choice 'multiple' 'Select one or more images' 'Add individual PNG, JPG or JPEG images to a conversion queue.'), (New-Choice 'folder' 'Scan a folder' 'Convert supported images found in one folder; originals are not changed.')) }; Default = 'multiple' }
    $steps += @{ Id = 'webpFiles'; Type = 'Files'; Prompt = 'Images to convert'; Min = 1; Help = 'Add one or more PNG, JPG or JPEG files. Unsupported extensions are ignored and reported in the review.'; When = { param($W) (Get-Answer $W 'webpInputMode') -eq 'multiple' } }
    $steps += @{ Id = 'webpFolder'; Type = 'Directory'; Prompt = 'Folder containing images'; Label = 'Folder'; MustExist = $true; Example = 'C:\Pictures\Album'; Help = 'The folder is scanned for PNG, JPG and JPEG images. Subfolders are not included.'; When = { param($W) (Get-Answer $W 'webpInputMode') -eq 'folder' }
        Validate = {
            param($v, $W)
            $inventory = Get-BatchFolderInventory -Folder $v -Extensions @('.png', '.jpg', '.jpeg')
            if ($inventory.Compatible -eq 0) { return 'No PNG, JPG or JPEG images were found in that folder.' }
            Set-WizardPanel $W 'webp.folder' 'Folder scan' @(@('Files scanned', [string]$inventory.Total), @('Supported images', [string]$inventory.Compatible), @('Unsupported', [string]$inventory.Unsupported)) 18
            $null
        } }
    $steps += @{ Id = 'webpLossless'; Type = 'Choice'; Prompt = 'WebP encoding mode'; Help = 'Lossy mode trades some image detail for smaller files. Lossless preserves pixels but may be larger than the source.'
        Choices = { param($W) @((New-Choice 'lossy' 'Lossy WebP' 'Choose an image quality target; the actual file may be larger or smaller than the input.'), (New-Choice 'lossless' 'Lossless WebP' 'Preserve pixel values; output size depends on the image and can increase.')) }; Default = 'lossy' }
    $steps += @{ Id = 'webpQuality'; Type = 'Choice'; Prompt = 'Lossy image quality'; Help = 'Higher quality retains more detail and usually needs more space. The output is not guaranteed to be smaller.'; When = { param($W) (Get-Answer $W 'webpLossless') -eq 'lossy' }
        Choices = { param($W) @((New-Choice 'maximum' 'Maximum quality' 'Highest quality target (100); typically the largest lossy WebP.'), (New-Choice 'high' 'High quality' 'High visual quality (90) with a moderate size target.'), (New-Choice 'balanced' 'Balanced (Recommended)' 'A practical default quality target (80); inspect results for important images.'), (New-Choice 'small' 'Smaller output' 'Lower quality target (60); fine detail may be lost.'), (New-Choice 'custom' 'Custom quality' 'Enter a quality value from 0 to 100; higher means better image quality.')) }; Default = 'balanced' }
    $steps += @{ Id = 'webpCustomQuality'; Type = 'Integer'; Prompt = 'Custom WebP quality'; Help = 'The libwebp quality value from 0 (lowest) to 100 (highest).'; Example = '82'; Min = 0; Max = 100; Label = 'Quality'; Default = 80; When = { param($W) (Get-Answer $W 'webpLossless') -eq 'lossy' -and (Get-Answer $W 'webpQuality') -eq 'custom' } }
    $steps += @{ Id = 'webpOutDir'; Type = 'Choice'; Prompt = 'Output folder'; Help = 'All WebP outputs are written here. Originals remain untouched.'
        Choices = { param($W) $base = [string](Get-Answer $W 'webpFolder'); if (-not $base) { $files = @(Get-Answer $W 'webpFiles' @()); if ($files.Count -gt 0) { $base = [System.IO.Path]::GetDirectoryName([string]$files[0]) } }; if (-not $base) { $base = (Get-Location).ProviderPath }; $suggested = Join-Path $base 'WebP'; @( (New-Choice $suggested 'A "WebP" folder beside the source' $suggested) ) }
        AllowCustom = @{ Label = 'Choose another folder...'; Type = 'Directory'; Prompt = 'Output folder path'; Help = 'Type or paste a folder path. A missing folder is created when conversion starts.'; Example = 'C:\Pictures\WebP'; Desc = 'Type or paste an output folder path.' }
        Default = { param($W) $base = [string](Get-Answer $W 'webpFolder'); if (-not $base) { $files = @(Get-Answer $W 'webpFiles' @()); if ($files.Count -gt 0) { $base = [System.IO.Path]::GetDirectoryName([string]$files[0]) } }; if (-not $base) { $base = (Get-Location).ProviderPath }; Join-Path $base 'WebP' } }
    $steps += @{ Id = 'webpExists'; Type = 'Choice'; Prompt = 'If a WebP output already exists'; Help = 'Existing files are never replaced unless you choose to. The choice applies to each matching name in this batch.'
        Choices = { param($W) @((New-Choice 'skip' 'Skip existing results (Recommended)' 'Leave existing files untouched and continue with other images.'), (New-Choice 'rename' 'Give new files numbered names' 'Keep existing results and write a new name such as image_2.webp.'), (New-Choice 'overwrite' 'Overwrite existing results' 'Replace matching output files after this explicit batch-wide choice.')) }; Default = 'skip' }
    return $steps
}

function Get-WebPSelectedFiles {
    param($W)
    if ((Get-Answer $W 'webpInputMode' 'multiple') -eq 'folder') {
        $files = @(Get-BatchFilesFromFolder -Folder ([string](Get-Answer $W 'webpFolder')) -Extensions @('.png', '.jpg', '.jpeg'))
        return @($files | ForEach-Object { [string]$_.FullName })
    }
    return @(@(Get-Answer $W 'webpFiles' @()) | Where-Object { $_ -and @('.png', '.jpg', '.jpeg') -contains [System.IO.Path]::GetExtension([string]$_).ToLowerInvariant() })
}

function Build-WebPJob {
    param($W)
    if (-not (Test-WebPAvailable)) { throw 'WebP encoding is unavailable in this FFmpeg build.' }
    $files = @(Get-WebPSelectedFiles $W)
    if ($files.Count -eq 0) { throw 'No supported PNG, JPG or JPEG input files were selected.' }
    if ($files.Count -gt 500) { throw 'A WebP batch is limited to 500 images. Narrow the selection and try again.' }
    $lossless = (Get-Answer $W 'webpLossless' 'lossy') -eq 'lossless'
    $quality = [string](Get-Answer $W 'webpQuality' 'balanced')
    $custom = [int](Get-Answer $W 'webpCustomQuality' 80)
    $tokens = @(Get-WebPTokens -Quality $(if ($lossless) { 'maximum' } else { $quality }) -Lossless:$lossless -CustomValue $custom)
    $outDir = [string](Get-Answer $W 'webpOutDir')
    $policy = [string](Get-Answer $W 'webpExists' 'skip')
    if ((Test-Path -LiteralPath $outDir -PathType Container) -and -not (Test-DirectoryWritable $outDir)) { throw 'You do not have permission to write to the selected WebP output folder.' }
    if (Test-Path -LiteralPath $outDir -PathType Leaf) { throw 'The WebP output path is a file, not a folder.' }
    $queue = New-BatchQueue -Paths $files
    $reserved = @{}
    $stages = @(); $expected = @(); $skipped = @(); $dupes = @{}
    foreach ($item in $queue) {
        $sourceKey = [System.IO.Path]::GetFullPath($item.InputPath).ToLowerInvariant()
        if ($dupes.ContainsKey($sourceKey)) { $item.Status = 'Skipped'; $item.Error = 'The same source image was selected more than once.'; $skipped += $item.InputPath; continue }
        $dupes[$sourceKey] = $true
        try { $target = Resolve-BatchOutputPath -InputPath $item.InputPath -OutputFolder $outDir -Extension '.webp' -Policy $policy -ReservedNames $reserved }
        catch { $item.Status = 'Failed'; $item.Error = $_.Exception.Message; continue }
        if ($target.Action -eq 'Skip') { $item.Status = 'Skipped'; $item.Error = 'The WebP result already exists.'; $skipped += [System.IO.Path]::GetFileName($target.ActionPath); continue }
        if ([string]::Equals([System.IO.Path]::GetFullPath($target.ActionPath), [System.IO.Path]::GetFullPath($item.InputPath), [StringComparison]::OrdinalIgnoreCase)) { $item.Status = 'Skipped'; $item.Error = 'The output path would replace the source image.'; continue }
        $reserved[[System.IO.Path]::GetFileName($target.ActionPath).ToLowerInvariant()] = $true
        $item.OutputPath = $target.ActionPath
        $webpArguments = @(New-WebPArguments -InputPath $item.InputPath -OutputPath $target.ActionPath -WebPTokens $tokens -Overwrite:$target.Overwrite)
        $stages += , @{ Name = 'Image {0}: {1}' -f $item.Index, [System.IO.Path]::GetFileName($item.InputPath); Arguments = $webpArguments; BatchItem = $item; DurationSec = 1 }
        $expected += $target.ActionPath
    }
    if ($stages.Count -eq 0) { throw 'No images are ready to convert. Check the supported file types and existing outputs.' }
    $notes = @('The original PNG/JPG/JPEG files are never modified.', 'WebP is not guaranteed to be smaller; compare each result with its source image.')
    if ($skipped.Count -gt 0) { $notes += ('Skipped existing or duplicate inputs: ' + (($skipped | Select-Object -First 8) -join ', ')) }
    if ($policy -eq 'overwrite') { $notes += 'Matching existing WebP files will be replaced according to your batch-wide choice.' }
    $label = if ((Get-Answer $W 'webpInputMode' 'multiple') -eq 'folder') { [string](Get-Answer $W 'webpFolder') } else { 'Selected image list' }
    $modeLabel = if ($lossless) { 'Lossless' } else { $quality + $(if ($quality -eq 'custom') { ' (' + $custom + ')' } else { '' }) }
    $rows = @(@('Input', $label), @('Images', [string]$stages.Count), @('Mode', $modeLabel), @('Output folder', $outDir), @('Existing results', $policy))
    $exp = $expected
    $count = { @($exp | Where-Object { Test-Path -LiteralPath $_ }).Count }.GetNewClosure()
    $job = New-JobObject -Title 'Converting images to WebP' -Summary $rows -Stages $stages -OutputPath $outDir -OutputKind 'Folder' -EnsureDirs @($outDir) -Notes $notes -CountOutputs $count
    $job.BatchQueue = $queue; $job.ContinueOnFailure = $true
    return $job
}

function Start-WebPWorkflow {
    if (-not (Test-WebPAvailable)) { $null = Show-Notice -Title 'WebP conversion unavailable' -Lines @('This FFmpeg build needs the libwebp encoder and WebP muxer.', 'Install or configure an FFmpeg build with WebP support, then try again.') -Kind Warning; return }
    Start-StandardWorkflow -Title 'Convert Images to WebP' -Description 'Convert PNG, JPG and JPEG images to WebP, one file or a batch.' -Icon 'Image' -StepsFactory { Get-WebPSteps } -Build { param($W) Build-WebPJob $W }
}

function Get-ThreeDToolStatus {
    param([string]$Executable = '')
    $candidate = $Executable
    if (-not $candidate) { $candidate = [string](Get-UserSetting 'assimpPath') }
    if ($candidate -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { $candidate = '' }
    if (-not $candidate) {
        foreach ($name in @('assimp.exe', 'assimp')) {
            $found = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $candidate = $found.Source; break }
        }
    }
    if (-not $candidate) { return [pscustomobject]@{ Available = $false; Path = ''; Reason = 'Assimp CLI was not found. Choose an existing Assimp executable in Manage 3D Converter; this app does not download or install it.'; ExportList = '' } }
    $probe = Invoke-ExternalCapture -FilePath $candidate -Arguments @('listexport') -TimeoutSec 30
    if (-not $probe.Started -or $probe.ExitCode -ne 0) { return [pscustomobject]@{ Available = $false; Path = $candidate; Reason = 'The selected Assimp executable could not list its exporters. Check that it is a working command-line build.'; ExportList = ($probe.StdOut + "`n" + $probe.StdErr) } }
    $exportList = [string]($probe.StdOut + "`n" + $probe.StdErr)
    if ($exportList -notmatch '(?im)^\s*glb2\b|\bglb2\b') { return [pscustomobject]@{ Available = $false; Path = $candidate; Reason = 'This Assimp build does not advertise the glb2 (binary glTF 2) exporter.'; ExportList = $exportList } }
    return [pscustomobject]@{ Available = $true; Path = $candidate; Reason = ''; ExportList = $exportList }
}

function Get-ObjDependencyReport {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'The OBJ input file does not exist.' }
    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -ne '.obj') { throw 'The input must be a Wavefront .obj file.' }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $baseDir = [System.IO.Path]::GetDirectoryName($fullPath)
    $objLines = @(Get-Content -LiteralPath $fullPath -ErrorAction Stop)
    $hasUv = [bool](@($objLines | Where-Object { $_ -match '^\s*vt\s+' }).Count -gt 0)
    $hasNormals = [bool](@($objLines | Where-Object { $_ -match '^\s*vn\s+' }).Count -gt 0)
    $mtlRefs = @(); $textureRefs = @(); $missing = @()
    foreach ($line in $objLines) {
        if ($line -match '^\s*mtllib\s+(.+?)\s*$') {
            $raw = $Matches[1].Trim()
            $rawCandidate = if ([System.IO.Path]::IsPathRooted($raw)) { $raw } else { Join-Path $baseDir $raw }
            if ($raw -match '^"([^"]+)"$') { $refs = @($Matches[1]) }
            elseif (Test-Path -LiteralPath $rawCandidate -PathType Leaf) { $refs = @($raw) }
            else { $refs = @($raw -split '\s+') }
            foreach ($ref in $refs) {
                if (-not $ref) { continue }
                $mtlCandidate = if ([System.IO.Path]::IsPathRooted($ref)) { $ref } else { Join-Path $baseDir $ref }
                $mtlFull = [System.IO.Path]::GetFullPath($mtlCandidate)
                $mtlRefs += $mtlFull
                if (-not (Test-Path -LiteralPath $mtlFull -PathType Leaf)) { $missing += $mtlFull; continue }
                $mtlDir = [System.IO.Path]::GetDirectoryName($mtlFull)
                foreach ($mtlLine in @(Get-Content -LiteralPath $mtlFull -ErrorAction SilentlyContinue)) {
                    if ($mtlLine -match '^\s*(?:map_[A-Za-z0-9_]+|bump|disp|decal|norm)\s+(.+?)\s*$') {
                        $value = $Matches[1].Trim()
                        if ($value -match '"([^"]+)"') { $texture = $Matches[1] }
                        else {
                            $candidateValue = $value
                            if (-not (Test-Path -LiteralPath (Join-Path $mtlDir $candidateValue) -PathType Leaf)) { $candidateValue = (($value -split '\s+')[-1]) }
                            $texture = $candidateValue
                        }
                        if ($texture -match '^\*\d+$') { continue }
                        $textureCandidate = if ([System.IO.Path]::IsPathRooted($texture)) { $texture } else { Join-Path $mtlDir $texture }
                        $textureFull = [System.IO.Path]::GetFullPath($textureCandidate)
                        $textureRefs += $textureFull
                        if (-not (Test-Path -LiteralPath $textureFull -PathType Leaf)) { $missing += $textureFull }
                    }
                }
            }
        }
    }
    $uniqueMissing = @($missing | Select-Object -Unique)
    return [pscustomobject]@{ Path = $fullPath; HasUv = $hasUv; HasNormals = $hasNormals; MaterialFiles = @($mtlRefs | Select-Object -Unique); TextureReferences = @($textureRefs | Select-Object -Unique); MissingDependencies = $uniqueMissing }
}

function New-AssimpExportArguments {
    param([string]$InputPath, [string]$OutputPath)
    if ([System.IO.Path]::GetExtension($InputPath) -ne '.obj') { throw 'Assimp input must be a Wavefront .obj file.' }
    if ([System.IO.Path]::GetExtension($OutputPath) -ne '.glb') { throw 'Assimp output must use the .glb extension.' }
    return @('export', $InputPath, $OutputPath, '-fglb2')
}

function Read-GlbJsonChunk {
    param([string]$Path)
    $stream = $null; $reader = $null
    try {
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($stream.Length -lt 20) { throw 'The GLB file is too small to contain a glTF 2 header.' }
        $magic = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        $version = $reader.ReadUInt32(); $declaredLength = $reader.ReadUInt32()
        if ($magic -ne 'glTF' -or $version -ne 2 -or $declaredLength -gt $stream.Length) { throw 'The output is not a valid glTF 2 binary container.' }
        $jsonLength = [long]$reader.ReadUInt32(); $jsonType = $reader.ReadUInt32()
        if ($jsonType -ne 0x4E4F534A -or $jsonLength -gt 16777216 -or ($stream.Position + $jsonLength) -gt $stream.Length) { throw 'The GLB JSON chunk could not be validated safely.' }
        $jsonText = [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes([int]$jsonLength)).Trim([char[]]@(' ', "`t", "`r", "`n", [char]0))
        return ($jsonText | ConvertFrom-Json -ErrorAction Stop)
    } finally {
        if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
}

function Get-WebJsonProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-ObjGlbWarnings {
    param([string]$ObjPath, [string]$GlbPath, $DependencyReport)
    $warnings = @(); $json = $null
    try { $json = Read-GlbJsonChunk $GlbPath } catch { $warnings += ('GLB validation warning: ' + $_.Exception.Message); return $warnings }
    if ($DependencyReport.HasUv) {
        $hasUvOut = $false
        foreach ($mesh in @(Get-WebJsonProperty $json 'meshes')) { foreach ($primitive in @(Get-WebJsonProperty $mesh 'primitives')) { $attributes = Get-WebJsonProperty $primitive 'attributes'; if ($null -ne (Get-WebJsonProperty $attributes 'TEXCOORD_0')) { $hasUvOut = $true } } }
        if (-not $hasUvOut) { $warnings += 'The source contains UV coordinates, but no TEXCOORD_0 attribute was detected in the GLB; inspect texture mapping before relying on it.' }
    }
    if ($DependencyReport.HasNormals) {
        $hasNormalsOut = $false
        foreach ($mesh in @(Get-WebJsonProperty $json 'meshes')) { foreach ($primitive in @(Get-WebJsonProperty $mesh 'primitives')) { $attributes = Get-WebJsonProperty $primitive 'attributes'; if ($null -ne (Get-WebJsonProperty $attributes 'NORMAL')) { $hasNormalsOut = $true } } }
        if (-not $hasNormalsOut) { $warnings += 'The source contains normals, but no NORMAL attribute was detected in the GLB; verify shading in your target application.' }
    }
    $images = @(Get-WebJsonProperty $json 'images')
    if ($DependencyReport.TextureReferences.Count -gt 0) {
        if ($images.Count -eq 0) { $warnings += 'The OBJ references external textures but the GLB contains no image records; the textures were not retained.' }
        else {
            $externalImages = @($images | Where-Object { $uri = Get-WebJsonProperty $_ 'uri'; $uri -and -not $uri.StartsWith('data:', [StringComparison]::OrdinalIgnoreCase) })
            if ($externalImages.Count -gt 0) { $warnings += 'One or more GLB images still reference external files instead of being embedded; keep the referenced texture files with the output.' }
            $embeddedImages = @($images | Where-Object { $uri = Get-WebJsonProperty $_ 'uri'; $bufferView = Get-WebJsonProperty $_ 'bufferView'; ($null -ne $bufferView) -or ($uri -and $uri.StartsWith('data:', [StringComparison]::OrdinalIgnoreCase)) })
            if ($embeddedImages.Count -eq 0) { $warnings += 'No embedded GLB texture image was detected; inspect the result before distributing it as a self-contained model.' }
        }
    }
    if ($DependencyReport.MaterialFiles.Count -gt 0 -and @(Get-WebJsonProperty $json 'materials').Count -eq 0) { $warnings += 'An MTL file was present, but no glTF material was detected in the GLB.' }
    if ($DependencyReport.MissingDependencies.Count -gt 0) { $warnings += ('Missing source dependency: ' + (($DependencyReport.MissingDependencies | Select-Object -First 5 | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', ')) }
    return $warnings
}

function Get-ObjToGlbSteps {
    $status = Get-ThreeDToolStatus
    if (-not $status.Available) { throw $status.Reason }
    $steps = @()
    $steps += @{ Id = 'objInput'; Type = 'File'; Prompt = 'Input Wavefront OBJ file'; Help = 'Choose an existing .obj file. The referenced MTL and texture paths are inspected, but your files are never edited.'; Example = 'C:\Models\character.obj'; Label = 'OBJ file'
        Validate = {
            param($v, $W)
            if (-not (Test-Path -LiteralPath $v -PathType Leaf)) { return 'File not found. Choose an existing OBJ file.' }
            if ([System.IO.Path]::GetExtension($v) -ne '.obj') { return 'Choose a Wavefront .obj file.' }
            try { $dependencyReport = Get-ObjDependencyReport -Path $v } catch { return $_.Exception.Message }
            $W.Data['obj.dependencies'] = $dependencyReport
            $rows = @(@('MTL files', [string]$dependencyReport.MaterialFiles.Count), @('Texture references', [string]$dependencyReport.TextureReferences.Count), @('UV coordinates', [string]$dependencyReport.HasUv), @('Normals', [string]$dependencyReport.HasNormals), @('Missing files', [string]$dependencyReport.MissingDependencies.Count))
            Set-WizardPanel $W 'obj.dependencies' 'OBJ dependencies' $rows 18
            return $null
        } }
    $steps += Get-OutputSteps -Prefix 'glb' -InputId 'objInput' -Suffix 'converted' -Extension { param($W) '.glb' } -NamePrompt 'Output GLB file name' -ProtectIds @('objInput')
    return $steps
}

function Build-ObjToGlbJob {
    param($W)
    $status = Get-ThreeDToolStatus
    if (-not $status.Available) { throw $status.Reason }
    $sourcePath = [string](Get-Answer $W 'objInput')
    $dependencies = $W.Data['obj.dependencies']
    $out = Get-OutputFile $W -Prefix 'glb'
    $tempPath = Join-Path $out.Dir ('fftui_assimp_' + [guid]::NewGuid().ToString('N') + '.glb')
    $toolArgs = @(New-AssimpExportArguments -InputPath $sourcePath -OutputPath $tempPath)
    $notes = @('The OBJ, MTL and texture source files are read-only to this workflow.', 'Material properties are converted into glTF materials; the original .mtl text is not copied into the GLB container.')
    if ($dependencies.MaterialFiles.Count -gt 0) { $notes += ('Referenced MTL files found: ' + $dependencies.MaterialFiles.Count + '.') }
    if ($dependencies.TextureReferences.Count -gt 0) { $notes += ('Referenced textures found: ' + $dependencies.TextureReferences.Count + '. The output is checked for embedded GLB images.') }
    if ($dependencies.MissingDependencies.Count -gt 0) { $notes += ('Some MTL/texture files are already missing: ' + (($dependencies.MissingDependencies | Select-Object -First 5 | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', ') + '.') }
    if ($out.Overwrite) { $notes += 'The existing GLB is replaced only after a successful conversion and because you explicitly confirmed overwrite.' }
    $rows = @(@('Input', [System.IO.Path]::GetFileName($sourcePath)), @('Converter', [System.IO.Path]::GetFileName($status.Path)), @('Format', 'Binary glTF 2.0 (GLB)'), @('MTL files found', [string]$dependencies.MaterialFiles.Count), @('Texture references', [string]$dependencies.TextureReferences.Count), @('Output', $out.Path))
    $job = New-JobObject -Title 'Converting OBJ to GLB' -Summary $rows -Stages @(@{ Name = 'Exporting GLB 2.0'; Executable = $status.Path; Arguments = $toolArgs; DurationSec = $null }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -TempFiles @($tempPath) -Notes $notes
    $outputPath = $out.Path; $replaceAllowed = [bool]$out.Overwrite; $inputObjPath = $sourcePath; $dependencySnapshot = $dependencies
    $job.FinalizeOutput = {
        param($GlbJob, $StageResults)
        if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf) -or (Get-FileSizeSafe $tempPath) -le 0) { throw 'Assimp did not create a non-empty GLB output.' }
        $warnings = @(Get-ObjGlbWarnings -ObjPath $inputObjPath -GlbPath $tempPath -DependencyReport $dependencySnapshot)
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            if (-not $replaceAllowed) { throw 'A file appeared at the output path after review. It was left untouched; choose a new name or explicitly approve overwrite.' }
            [System.IO.File]::Replace($tempPath, $outputPath, $null)
        } else {
            [System.IO.File]::Move($tempPath, $outputPath)
        }
        $GlbJob.ResultNotes = @('The GLB JSON chunk was inspected for UVs, normals, materials and embedded textures where the source contained them.') + $warnings
    }.GetNewClosure()
    return $job
}

function Get-ThreeDToolManagerSteps {
    return @(@{ Id = 'assimpExecutable'; Type = 'Text'; Prompt = 'Path to an existing Assimp CLI executable'; Help = 'Type or paste the full path to the Assimp command-line executable. The path is tested for the glb2 exporter and saved only in your per-user settings.'; Example = 'C:\Tools\Assimp\assimp.exe'; Label = 'Executable path'
        Validate = { param($v, $W) if (-not (Test-Path -LiteralPath $v -PathType Leaf)) { return 'That executable file was not found.' }; $check = Get-ThreeDToolStatus -Executable $v; if (-not $check.Available) { return $check.Reason }; $null } })
}

function Show-ThreeDToolManager {
    while ($true) {
        $status = Get-ThreeDToolStatus
        $lines = @()
        if ($status.Available) { $lines += 'Status: Ready'; $lines += ('Path: ' + $status.Path); $lines += 'Exporter: glb2 (binary glTF 2.0)' }
        else { $lines += 'Status: Not ready'; $lines += $status.Reason; if ($status.Path) { $lines += ('Selected path: ' + $status.Path) } }
        $action = Show-Notice -Title 'Manage 3D Converter' -Lines $lines -Kind $(if ($status.Available) { 'Info' } else { 'Warning' }) -Actions @(@('C', 'Choose an existing Assimp CLI'), @('R', 'Requirements and limitations'), @('B', 'Back'))
        if ($action -eq 'C') {
            $selected = Invoke-Wizard -Title 'Select Assimp CLI' -Description 'The existing executable is checked for its glb2 exporter; nothing is installed or downloaded.' -Icon 'Settings' -Steps (Get-ThreeDToolManagerSteps)
            if ($selected.Status -eq 'Completed') {
                $candidate = [string]$selected.Answers['assimpExecutable']
                $verified = Get-ThreeDToolStatus -Executable $candidate
                if ($verified.Available -and (Set-UserSetting 'assimpPath' $verified.Path)) { $null = Show-Notice -Title '3D converter saved' -Lines @('The verified Assimp path is stored in your per-user settings.', $verified.Path) -Kind Success }
                else { $null = Show-Notice -Title '3D converter could not be saved' -Lines @('The executable was not verified, or the settings file could not be written.') -Kind Error }
            }
            continue
        }
        if ($action -eq 'R') {
            $null = Show-Notice -Title 'Assimp requirements and limitations' -Lines @('An existing Assimp command-line executable with the glb2 exporter is required.', 'This app does not install or download Assimp. Install it through a route approved by your organization, then select its executable here.', 'OBJ material values are translated into glTF materials. UVs and normals are checked in the resulting GLB when they exist in the source.', 'External MTL/texture paths are inspected. The result is checked for embedded GLB images; any detected loss or external dependency is reported.', 'OBJ and companion files are never modified.') -Kind Info -Actions @(, @('Enter', 'Back to tool manager'))
            continue
        }
        return
    }
}

function Get-WebMediaOptimizationMenuItems {
    $webmReady = @(Get-WebMCodecChoices).Count -gt 0
    $webpReady = Test-WebPAvailable
    $assimpStatus = Get-ThreeDToolStatus
    return @(
        @{ Icon = 'Video'; Label = 'Convert Video to WebM'; Desc = 'Encode one video with an installed VP9 or AV1 encoder and optionally sample an estimated output size.'; Value = 'WebM'; Enabled = $webmReady; Reason = $(if ($webmReady) { '' } else { 'Needs a WebM muxer and installed VP9 or AV1 encoder.' }) },
        @{ Icon = 'Chart'; Label = 'Estimate Video Size'; Desc = 'Estimate output size from target video/audio bitrates and the source duration; no file is encoded.'; Value = 'Estimate' },
        @{ Icon = 'Image'; Label = 'Convert Images to WebP'; Desc = 'Convert one or many PNG, JPG or JPEG images using lossy or lossless WebP.'; Value = 'WebP'; Enabled = $webpReady; Reason = $(if ($webpReady) { '' } else { 'Needs the libwebp encoder and WebP muxer in FFmpeg.' }) },
        @{ Icon = 'Info'; Label = 'Convert OBJ to GLB'; Desc = 'Convert Wavefront OBJ with glTF 2 binary export, MTL dependency checks and GLB validation.'; Value = 'ObjGlb'; Enabled = [bool]$assimpStatus.Available; Reason = $assimpStatus.Reason },
        @{ Icon = 'Settings'; Label = 'Manage 3D Converter'; Desc = 'Inspect requirements or select an existing Assimp CLI; this app does not download or install it.'; Value = 'Manage3D' }
    )
}

function Start-WebMediaOptimizationWorkflow {
    while ($true) {
        $menu = Show-Menu -Title 'Web Media Optimization' -Subtitle 'Choose a web-oriented media workflow or manage the optional 3D converter.' -Items (Get-WebMediaOptimizationMenuItems) -ShowHeader -AllowBack
        if ($menu.Action -eq 'Back' -or $menu.Action -eq 'Quit') { return }
        if ($menu.Action -ne 'Select') { continue }
        switch ([string]$menu.Item.Value) {
            'WebM' { Start-WebMWorkflow }
            'Estimate' { Start-WebSizeEstimateWorkflow }
            'WebP' { Start-WebPWorkflow }
            'ObjGlb' { Start-ObjToGlbWorkflow }
            'Manage3D' { Show-ThreeDToolManager }
        }
    }
}

function Start-ObjToGlbWorkflow {
    $status = Get-ThreeDToolStatus
    if (-not $status.Available) { $null = Show-Notice -Title '3D converter unavailable' -Lines @($status.Reason, 'Choose an existing executable under Manage 3D Converter, then try again.') -Kind Warning; return }
    Start-StandardWorkflow -Title 'Convert OBJ to GLB' -Description 'Convert a Wavefront OBJ and inspect how its materials and external dependencies transfer to a GLB 2.0 file.' -Icon 'Info' -StepsFactory { Get-ObjToGlbSteps } -Build { param($W) Build-ObjToGlbJob $W }
}

Export-ModuleMember -Function Get-WebBitrateEstimate, Get-WebSampleEstimate, Get-WebMCodecChoices, Get-WebMQualityTokens, Get-WebMAudioUnavailableReason, Get-WebMAudioTokens, Get-WebMScaleFilter, New-WebMArguments, Get-WebMSteps, Build-WebMJob, New-WebMSampleEstimateJob, Start-WebMWorkflow, Get-WebSizeEstimateSteps, Build-WebSizeEstimateJob, Start-WebSizeEstimateWorkflow, Test-WebPAvailable, Get-WebPTokens, New-WebPArguments, Get-WebPSteps, Get-WebPSelectedFiles, Build-WebPJob, Start-WebPWorkflow, Get-ThreeDToolStatus, Get-ObjDependencyReport, New-AssimpExportArguments, Read-GlbJsonChunk, Get-WebJsonProperty, Get-ObjGlbWarnings, Get-ObjToGlbSteps, Build-ObjToGlbJob, Get-ThreeDToolManagerSteps, Show-ThreeDToolManager, Get-WebMediaOptimizationMenuItems, Start-WebMediaOptimizationWorkflow, Start-ObjToGlbWorkflow
