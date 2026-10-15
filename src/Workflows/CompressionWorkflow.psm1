# CompressionWorkflow.psm1 - Simple/Advanced compression and image compression jobs.
Set-StrictMode -Version 2.0

function Get-CompressionMediaKind {
    param($Info)
    if (-not $Info) { return '' }
    if ($Info.IsImageOnly) { return 'Image' }
    if ($Info.HasVideo) { return 'Video' }
    if ($Info.HasAudio) { return 'Audio' }
    return ''
}

function Get-CompressionDefaultVideoContainer {
    param($Info)
    $id = Get-ContainerIdFromPath ([string]$Info.Path)
    if ($id -and (Get-VideoContainer $id) -and (Test-FFMuxer (Get-VideoContainer $id).Muxer)) { return $id }
    $available = @(Get-AvailableVideoContainers)
    if ($available.Count -gt 0) { return [string]$available[0].Id }
    return 'mp4'
}

function Get-CompressionDefaultAudioFormat {
    param($Info)
    $extension = [System.IO.Path]::GetExtension([string]$Info.Path).ToLowerInvariant()
    $formats = @(Get-AvailableAudioFormats)
    foreach ($format in $formats) {
        if ($format.Ext -eq $extension -and $format.Id -notin @('flac', 'wav')) { return [string]$format.Id }
    }
    foreach ($format in $formats) { if ($format.Id -eq 'mp3') { return 'mp3' } }
    if ($formats.Count -gt 0) { return [string]$formats[0].Id }
    throw 'No usable audio format is available in this FFmpeg build.'
}

function Get-CompressionImageFormat {
    param($Info)
    $extension = [System.IO.Path]::GetExtension([string]$Info.Path).ToLowerInvariant()
    $format = switch ($extension) { '.jpg' { 'jpeg' } '.jpeg' { 'jpeg' } '.png' { 'png' } '.webp' { 'webp' } default { '' } }
    if (-not $format) { throw 'Only JPEG, PNG, or WebP still images can be compressed here.' }
    $available = @(Get-AvailableImageCompressionFormats | Where-Object { $_.Format -eq $format })
    if ($available.Count -eq 0) { throw "The installed FFmpeg build cannot encode $format images." }
    return $format
}

function Get-CompressionSourceBytes {
    param($Info)
    if ($Info -and $Info.Size -gt 0) { return [long]$Info.Size }
    if ($Info -and $Info.Path -and (Test-Path -LiteralPath ([string]$Info.Path) -PathType Leaf)) {
        $fileSize = [long](Get-Item -LiteralPath ([string]$Info.Path)).Length
        if ($fileSize -gt 0) { return $fileSize }
    }
    throw 'The source file size could not be read.'
}

function New-CompressionTargetSizeStep {
    param([scriptblock]$When, [string]$Id = 'targetSize')
    return @{
        Id = $Id; Type = 'Text'; Prompt = 'Target size'; Label = 'Size'; Example = '25 MB'
        Help = 'Enter an approximate output size using B, KB, MB, or GB. The result is not guaranteed byte-exact.'
        When = $When
        Validate = {
            param($value, $W)
            $mediaInfo = Get-Media $W 'input'
            try {
                $targetBytes = ConvertFrom-CompressionSizeText ([string]$value)
                $null = Get-CompressionTargetBytes -SourceBytes (Get-CompressionSourceBytes $mediaInfo) -Mode TargetSize -Value $targetBytes
            } catch { return $_.Exception.Message }
            return $null
        }.GetNewClosure()
    }
}

function New-CompressionTargetReductionStep {
    param([scriptblock]$When, [string]$Id = 'targetReduction')
    return @{
        Id = $Id; Type = 'Decimal'; Prompt = 'Target reduction (%)'; Label = 'Reduction'; Example = '20'
        Help = 'This is a desired decrease in file size, not a quality percentage. Enter a value greater than 0 and less than 100.'
        Min = 0; Max = 99.9; When = $When
        Validate = {
            param($value, $W)
            $mediaInfo = Get-Media $W 'input'
            try { $null = Get-CompressionTargetBytes -SourceBytes (Get-CompressionSourceBytes $mediaInfo) -Mode TargetReduction -Value ([double]$value) }
            catch { return $_.Exception.Message }
            return $null
        }.GetNewClosure()
    }
}

function Get-CompressionSteps {
    $inputExtra = {
        param($mediaInfo, $W)
        $kind = Get-CompressionMediaKind $mediaInfo
        if ($kind -eq 'Image') {
            try { $null = Get-CompressionImageFormat $mediaInfo } catch { return $_.Exception.Message }
            return $null
        }
        if ($kind -notin @('Video', 'Audio')) { return 'Choose a supported video, audio, or still-image file.' }
        return $null
    }.GetNewClosure()
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media (video, audio, or image)' -Require Any -Extra $inputExtra
    $steps += @{
        Id = 'mode'; Type = 'Choice'; Prompt = 'Compression mode'; Help = 'Simple offers four presets and two size goals. Advanced exposes supported codec and quality controls.'
        Choices = { param($W) @( (New-Choice 'Simple' 'Simple' 'Choose a compression strategy without codec settings.'), (New-Choice 'Advanced' 'Advanced' 'Configure supported format, codec, quality, bitrate, resolution, and frame rate options.') ) }
        Default = 'Simple'
    }
    $isSimple = { param($W) (Get-Answer $W 'mode' 'Simple') -eq 'Simple' }.GetNewClosure()
    $isAdvanced = { param($W) (Get-Answer $W 'mode' 'Simple') -eq 'Advanced' }.GetNewClosure()
    $isVideo = { param($W) (Get-CompressionMediaKind (Get-Media $W 'input')) -eq 'Video' }.GetNewClosure()
    $isAudio = { param($W) (Get-CompressionMediaKind (Get-Media $W 'input')) -eq 'Audio' }.GetNewClosure()
    $isImage = { param($W) (Get-CompressionMediaKind (Get-Media $W 'input')) -eq 'Image' }.GetNewClosure()
    $advancedVideo = { param($W) (& $isAdvanced $W) -and (& $isVideo $W) }.GetNewClosure()
    $advancedAudio = { param($W) (& $isAdvanced $W) -and (& $isAudio $W) }.GetNewClosure()
    $advancedImage = { param($W) (& $isAdvanced $W) -and (& $isImage $W) }.GetNewClosure()
    $steps += @{
        Id = 'strategy'; Type = 'Choice'; Prompt = 'Compression strategy'; Help = 'Light preserves more quality; Maximum may produce visible degradation. Size goals are approximate.'; When = $isSimple
        Choices = {
            param($W)
            $targetSizeEnabled = $true; $targetReason = ''
            if ($W) {
                $mediaInfo = Get-Media $W 'input'
                if ((Get-CompressionMediaKind $mediaInfo) -ne 'Image' -and ($null -eq $mediaInfo.Duration -or [double]$mediaInfo.Duration -le 0)) {
                    $targetSizeEnabled = $false
                    $targetReason = 'Media duration is unknown, so a target bitrate cannot be calculated.'
                }
            }
            @(
                (New-Choice 'Light' 'Light Compression' 'Prioritize quality; size reduction may be modest.'),
                (New-Choice 'Balanced' 'Balanced' 'Balance size and quality for ordinary use.'),
                (New-Choice 'Strong' 'Strong Compression' 'Make a smaller result with a higher quality risk.'),
                (New-Choice 'Maximum' 'Maximum Compression' 'Seek the smallest practical output; visible quality loss is likely.'),
                (New-Choice 'TargetSize' 'Target Size' 'Aim for an approximate output size and review the quality risk.' $targetSizeEnabled $targetReason),
                (New-Choice 'TargetReduction' 'Target Reduction' 'Aim for a decrease in file size, never a quality percentage.' $targetSizeEnabled $targetReason)
            )
        }.GetNewClosure()
        Default = 'Balanced'
    }
    $simpleTargetSize = { param($W) (& $isSimple $W) -and ((Get-Answer $W 'strategy') -eq 'TargetSize') }.GetNewClosure()
    $simpleTargetReduction = { param($W) (& $isSimple $W) -and ((Get-Answer $W 'strategy') -eq 'TargetReduction') }.GetNewClosure()
    $steps += New-CompressionTargetSizeStep -When $simpleTargetSize
    $steps += New-CompressionTargetReductionStep -When $simpleTargetReduction

    $steps += @{
        Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'Simple mode keeps the source container. Advanced mode can choose another available container.'; When = $advancedVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) Get-CompressionDefaultVideoContainer (Get-Media $W 'input') }.GetNewClosure()
    }
    $steps += @{
        Id = 'vcodec'; Type = 'Choice'; Prompt = 'Video codec'; Help = 'Available encoders are detected from FFmpeg. Hardware encoders appear only when usable.'; When = $advancedVideo
        Choices = {
            param($W)
            $containerId = [string](Get-Answer $W 'format' (Get-CompressionDefaultVideoContainer (Get-Media $W 'input')))
            $containerInfo = Get-VideoContainer $containerId
            if (-not $containerInfo) { return @() }
            $list = @( (New-Choice 'auto' 'Automatic / Recommended' 'Use the first compatible available video encoder.') )
            foreach ($encoderChoice in (Get-VideoEncoderChoices -AllowedFamilies @($containerInfo.Video) -IncludeHardware)) {
                $label = $encoderChoice.Label
                if (-not $encoderChoice.Hardware) { $label += '  [' + $encoderChoice.Encoder + ']' }
                $list += , (New-Choice $encoderChoice.Encoder $label $encoderChoice.Desc)
            }
            return $list
        }.GetNewClosure()
        Default = 'auto'
    }
    $steps += @{
        Id = 'goal'; Type = 'Choice'; Prompt = 'Compression goal'; Help = 'Quality controls are specific to the selected encoder. Size and reduction estimates use the media duration.'; When = $advancedVideo
        Choices = {
            param($W)
            $encoder = Get-CompressionAutoVideoEncoder $W
            $qualityAvailable = ((Get-EncoderProfile $encoder).Quality -ne 'none')
            $info = Get-Media $W 'input'
            $durationAvailable = ($null -ne $info.Duration -and [double]$info.Duration -gt 0)
            @(
                (New-Choice 'quality' 'Quality target' 'Choose the encoder quality setting; final size cannot be predicted reliably.' $qualityAvailable 'This encoder does not expose a quality control; choose bitrate or a size target.'),
                (New-Choice 'bitrate' 'Target bitrate' 'Set an average video bitrate.'),
                (New-Choice 'size' 'Target Size' 'Calculate an approximate video bitrate from the target size.' $durationAvailable 'The media duration is unknown, so a target bitrate cannot be calculated.'),
                (New-Choice 'reduction' 'Target Reduction' 'Calculate a bitrate from the desired file-size decrease, not quality.' $durationAvailable 'The media duration is unknown, so a target bitrate cannot be calculated.')
            )
        }.GetNewClosure()
        Default = {
            param($W)
            $encoder = Get-CompressionAutoVideoEncoder $W
            if ((Get-EncoderProfile $encoder).Quality -ne 'none') { return 'quality' }
            return 'bitrate'
        }.GetNewClosure()
    }
    $videoTargetSize = { param($W) (& $advancedVideo $W) -and ((Get-Answer $W 'goal') -eq 'size') }.GetNewClosure()
    $videoTargetReduction = { param($W) (& $advancedVideo $W) -and ((Get-Answer $W 'goal') -eq 'reduction') }.GetNewClosure()
    $steps += New-CompressionTargetSizeStep -When $videoTargetSize -Id 'videoTargetSize'
    $steps += New-CompressionTargetReductionStep -When $videoTargetReduction -Id 'videoTargetReduction'
    $steps += @{
        Id = 'quality'; Type = 'Choice'; Prompt = 'Quality level'; Help = 'The available range and direction depend on the selected encoder.'; When = { param($W) (& $advancedVideo $W) -and ((Get-Answer $W 'goal') -eq 'quality') }.GetNewClosure()
        Choices = { param($W) $encoder = Get-CompressionAutoVideoEncoder $W; @(Get-QualityChoices $encoder) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom value...'; Type = 'Integer'; Prompt = 'Custom quality value'; Help = 'Enter a whole number in this encoder range.'; Example = '26'; ValueLabel = 'Quality' }
        Default = { param($W) $encoder = Get-CompressionAutoVideoEncoder $W; (Get-EncoderProfile $encoder).Balanced }.GetNewClosure()
    }
    $steps += @{
        Id = 'vbitrate'; Type = 'Choice'; Prompt = 'Target video bitrate'; Help = 'The video bitrate is separate from audio bitrate and container overhead.'; When = { param($W) (& $advancedVideo $W) -and ((Get-Answer $W 'goal') -eq 'bitrate') }.GetNewClosure()
        Choices = { param($W) @( (New-Choice 500000 '500 kbps' 'Very small; low detail.'), (New-Choice 1000000 '1 Mbps' 'Small.'), (New-Choice 2500000 '2.5 Mbps' 'Often suitable for 720p.'), (New-Choice 5000000 '5 Mbps' 'Often suitable for 1080p.') ) }
        AllowCustom = @{ Label = 'Custom bitrate...'; Type = 'Bitrate'; Prompt = 'Custom video bitrate'; Help = 'Use k or M suffix.'; Example = '1800k'; Desc = 'For example 1800k.' }
        Default = 2500000
    }
    $steps += @{ Id = 'preset'; Type = 'Choice'; Prompt = 'Encoding speed / preset'; Help = 'Slower presets may create smaller files at similar quality but take longer.'; When = { param($W) if (-not (& $advancedVideo $W)) { return $false }; $encoder = Get-CompressionAutoVideoEncoder $W; (Get-EncoderProfile $encoder).ContainsKey('Presets') }.GetNewClosure()
        Choices = { param($W) $profile = Get-EncoderProfile (Get-CompressionAutoVideoEncoder $W); @($profile.Presets | ForEach-Object { New-Choice $_ $_ (Get-EncoderPresetDescription $_) }) }.GetNewClosure()
        Default = { param($W) (Get-EncoderProfile (Get-CompressionAutoVideoEncoder $W)).DefaultPreset }.GetNewClosure()
    }
    $resolutionStep = Get-ResolutionStep -Id 'resolution' -Prompt 'Resolution'
    $resolutionStep.When = $advancedVideo
    $steps += $resolutionStep
    $fpsStep = Get-FrameRateStep -Id 'fps' -Prompt 'Frame rate' -Help 'Keep the original frame rate unless you explicitly choose a change.'
    $fpsStep.When = $advancedVideo
    $steps += $fpsStep
    $audioForVideo = { param($W) (& $advancedVideo $W) -and (Get-Media $W 'input').HasAudio }.GetNewClosure()
    $steps += Get-AudioEncodeSteps -Prefix 'a' -ContainerScript { param($W) [string](Get-Answer $W 'format' (Get-CompressionDefaultVideoContainer (Get-Media $W 'input'))) }.GetNewClosure() -OfferCopy -OfferRemove -When $audioForVideo

    $steps += @{
        Id = 'afmt'; Type = 'Choice'; Prompt = 'Output audio format'; Help = 'Choose a format and codec available in the installed FFmpeg build.'; When = $advancedAudio
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) Get-CompressionDefaultAudioFormat (Get-Media $W 'input') }.GetNewClosure()
    }
    $steps += @{
        Id = 'audioGoal'; Type = 'Choice'; Prompt = 'Audio compression goal'; Help = 'Use codec controls, or request an approximate target size/reduction.'; When = $advancedAudio
        Choices = {
            param($W)
            $formatInfo = Get-AudioFormat ([string](Get-Answer $W 'afmt'))
            $info = Get-Media $W 'input'
            $durationAvailable = ($null -ne $info.Duration -and [double]$info.Duration -gt 0)
            $lossyAvailable = $false
            if ($formatInfo) { $lossyAvailable = (@(Get-AudioEncoderChoices -AllowedFamilies @($formatInfo.Codecs) | Where-Object { -not $_.Lossless }).Count -gt 0) }
            $targetsAvailable = $durationAvailable -and $lossyAvailable
            $reason = if (-not $durationAvailable) { 'The media duration is unknown, so a target bitrate cannot be calculated.' } else { 'This output format has no available lossy encoder for target sizing.' }
            @(
                (New-Choice 'controls' 'Quality / bitrate controls' 'Choose codec, quality mode, bitrate, sample rate, and channels.'),
                (New-Choice 'size' 'Target Size' 'Calculate an approximate audio bitrate for this size.' $targetsAvailable $reason),
                (New-Choice 'reduction' 'Target Reduction' 'Aim for a file-size decrease, not a quality percentage.' $targetsAvailable $reason)
            )
        }.GetNewClosure()
        Default = 'controls'
    }
    $audioTarget = { param($W) (& $advancedAudio $W) -and ((Get-Answer $W 'audioGoal') -in @('size', 'reduction')) }.GetNewClosure()
    $steps += @{
        Id = 'targetAudioCodec'; Type = 'Choice'; Prompt = 'Audio codec for target sizing'; Help = 'A lossy codec is needed to target a smaller size.'; When = $audioTarget
        Choices = { param($W) $formatInfo = Get-AudioFormat ([string](Get-Answer $W 'afmt')); if ($formatInfo) { @(Get-AudioEncoderChoices -AllowedFamilies @($formatInfo.Codecs) | Where-Object { -not $_.Lossless } | ForEach-Object { New-Choice $_.Encoder $_.Label $_.Desc }) } else { @() } }.GetNewClosure()
        Default = { param($W) $formatInfo = Get-AudioFormat ([string](Get-Answer $W 'afmt')); $choices = @(); if ($formatInfo) { $choices = @(Get-AudioEncoderChoices -AllowedFamilies @($formatInfo.Codecs) | Where-Object { -not $_.Lossless }) }; if ($choices.Count -gt 0) { return [string]$choices[0].Encoder }; return '' }.GetNewClosure()
    }
    $audioTargetSize = { param($W) (& $audioTarget $W) -and ((Get-Answer $W 'audioGoal') -eq 'size') -and ((Get-Answer $W 'targetAudioCodec') -notin @('flac', 'alac', 'pcm_s16le', 'pcm_s24le')) }.GetNewClosure()
    $audioTargetReduction = { param($W) (& $audioTarget $W) -and ((Get-Answer $W 'audioGoal') -eq 'reduction') -and ((Get-Answer $W 'targetAudioCodec') -notin @('flac', 'alac', 'pcm_s16le', 'pcm_s24le')) }.GetNewClosure()
    $steps += New-CompressionTargetSizeStep -When $audioTargetSize -Id 'audioTargetSize'
    $steps += New-CompressionTargetReductionStep -When $audioTargetReduction -Id 'audioTargetReduction'
    $audioControls = { param($W) (& $advancedAudio $W) -and ((Get-Answer $W 'audioGoal' 'controls') -eq 'controls') }.GetNewClosure()
    $audioFamilies = { param($W) $formatInfo = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($formatInfo) { @($formatInfo.Codecs) } else { @() } }.GetNewClosure()
    $steps += Get-AudioEncodeSteps -Prefix 'ac' -FormatAudioFamilies $audioFamilies -When $audioControls -Full -OfferVbr

    $steps += @{
        Id = 'imageGoal'; Type = 'Choice'; Prompt = 'Image compression goal'; Help = 'Quality-based size estimates are unavailable; target search is bounded and lossless images stay lossless.'; When = $advancedImage
        Choices = { param($W) @( (New-Choice 'quality' 'Quality preset / custom quality' 'Set image quality while preserving the source format.'), (New-Choice 'size' 'Target Size' 'Try a bounded quality search when this image format is lossy.'), (New-Choice 'reduction' 'Target Reduction' 'Try a bounded quality search; lossless images remain lossless.') ) }
        Default = 'quality'
    }
    $webpImage = { param($W) (& $advancedImage $W) -and ((Get-Answer $W 'imageGoal' 'quality') -eq 'quality') -and ((Get-CompressionImageFormat (Get-Media $W 'input')) -eq 'webp') -and -not (Test-CompressionPixelHasAlpha (Get-Media $W 'input')) }.GetNewClosure()
    $steps += @{ Id = 'imageLossless'; Type = 'YesNo'; Prompt = 'Use lossless WebP encoding?'; Help = 'Lossless WebP preserves decoded pixels, but the output may be larger. A lossless source defaults to lossless output.'; YesLabel = 'Lossless'; NoLabel = 'Lossy'; YesDesc = 'Preserve decoded pixels; file size may be larger.'; NoDesc = 'Explicitly re-encode lossily; detail may change.'; Default = { param($W) (Get-CompressionImageLosslessState (Get-Media $W 'input')) -ne 'Lossy' }.GetNewClosure(); When = $webpImage }
    $steps += @{ Id = 'imageQuality'; Type = 'Integer'; Prompt = 'Image quality'; Label = 'Quality'; Help = 'JPEG quality uses qscale 2-31 (lower is better); WebP quality uses 0-100 (higher is better).'; Example = '85'; Min = 0; Max = 100
        When = { param($W) (& $advancedImage $W) -and ((Get-Answer $W 'imageGoal') -eq 'quality') -and ((Get-CompressionImageFormat (Get-Media $W 'input')) -ne 'png') -and -not (Test-CompressionPixelHasAlpha (Get-Media $W 'input')) -and -not (Get-Answer $W 'imageLossless' $false) }.GetNewClosure()
        Default = { param($W) $format = Get-CompressionImageFormat (Get-Media $W 'input'); if ($format -eq 'jpeg') { return 4 }; return 85 }.GetNewClosure()
        Validate = { param($value, $W) $format = Get-CompressionImageFormat (Get-Media $W 'input'); if ($format -eq 'jpeg' -and ($value -lt 2 -or $value -gt 31)) { return 'JPEG qscale must be between 2 and 31.' }; if ($format -eq 'webp' -and ($value -lt 0 -or $value -gt 100)) { return 'WebP quality must be between 0 and 100.' }; $null }.GetNewClosure()
    }
    $imageTargetSize = { param($W) (& $advancedImage $W) -and ((Get-Answer $W 'imageGoal') -eq 'size') }.GetNewClosure()
    $imageTargetReduction = { param($W) (& $advancedImage $W) -and ((Get-Answer $W 'imageGoal') -eq 'reduction') }.GetNewClosure()
    $steps += New-CompressionTargetSizeStep -When $imageTargetSize -Id 'imageTargetSize'
    $steps += New-CompressionTargetReductionStep -When $imageTargetReduction -Id 'imageTargetReduction'
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'compressed' -Extension {
        param($W)
        $mediaInfo = Get-Media $W 'input'
        switch (Get-CompressionMediaKind $mediaInfo) {
            'Video' { $containerId = [string](Get-Answer $W 'format' (Get-CompressionDefaultVideoContainer $mediaInfo)); return (Get-VideoContainer $containerId).Ext }
            'Audio' { $formatId = [string](Get-Answer $W 'afmt' (Get-CompressionDefaultAudioFormat $mediaInfo)); return (Get-AudioFormat $formatId).Ext }
            'Image' { $formatId = Get-CompressionImageFormat $mediaInfo; return (Get-ImageCompressionProfile -Format $formatId -Preset 'Balanced').Extension }
        }
    }.GetNewClosure()
    return $steps
}

function Get-CompressionAutoVideoEncoder {
    param($W)
    $selected = [string](Get-Answer $W 'vcodec' 'auto')
    if ($selected -ne 'auto') {
        if (-not (Test-FFEncoder $selected)) { throw 'The selected video encoder is no longer available in this FFmpeg build.' }
        return $selected
    }
    $formatId = [string](Get-Answer $W 'format' (Get-CompressionDefaultVideoContainer (Get-Media $W 'input')))
    $container = Get-VideoContainer $formatId
    if (-not $container) { throw 'The selected output container is not supported.' }
    $choices = @(Get-VideoEncoderChoices -AllowedFamilies @($container.Video))
    if ($choices.Count -eq 0) { throw "No usable video encoder is available in this FFmpeg build for $formatId." }
    return [string]$choices[0].Encoder
}

function Get-CompressionTargetForAnswers {
    param($W, [string]$Mode, [string]$SizeId = 'targetSize', [string]$ReductionId = 'targetReduction')
    $info = Get-Media $W 'input'
    if ($Mode -eq 'size') {
        return [long](Get-CompressionTargetBytes -SourceBytes (Get-CompressionSourceBytes $info) -Mode TargetSize -Value (ConvertFrom-CompressionSizeText ([string](Get-Answer $W $SizeId))))
    }
    if ($Mode -eq 'reduction') {
        return [long](Get-CompressionTargetBytes -SourceBytes (Get-CompressionSourceBytes $info) -Mode TargetReduction -Value ([double](Get-Answer $W $ReductionId)))
    }
    return $null
}

function New-CompressionTargetPreview {
    param($Info, [long]$TargetBytes, [string]$MediaType, [long]$PlannedBitrateBps = 0, [bool]$Lossless = $false)
    $sourceBytes = Get-CompressionSourceBytes $Info
    $assessment = Get-CompressionTargetAssessment -SourceBytes $sourceBytes -TargetBytes $TargetBytes
    $estimatedOutput = 'Unavailable (content-dependent estimate)'
    $qualityRisk = [string]$assessment.QualityRisk
    $notes = @()
    if ($MediaType -eq 'Image') {
        $estimatedOutput = 'Unavailable (bounded image quality search)'
        if ($Lossless) { $qualityRisk = 'Target may not be reached; lossless output retained' }
        elseif ($assessment.Warn) { $notes += ('Aggressive image target: requests {0}% size reduction; visible quality loss is likely.' -f $assessment.ReductionPercent) }
        else { $notes += 'Image target uses bounded quality search; actual size and visible quality depend on the source.' }
    } else {
        $estimatedOutput = ('About {0}; estimate only, actual size varies.' -f (Format-FileSize $TargetBytes))
        if ($assessment.Warn) { $notes += ('Aggressive target: requests {0}% size reduction; visible quality loss is likely.' -f $assessment.ReductionPercent) }
        else { $notes += 'Target bitrate is an estimate; quality depends on the source and the actual output is measured after encoding.' }
    }
    $rows = @(
        , @('Requested target', (Format-FileSize $TargetBytes)),
        , @('Estimated output', $estimatedOutput),
        , @('Requested reduction', ('{0:0.#}%' -f $assessment.ReductionPercent)),
        , @('Quality risk', $qualityRisk)
    )
    if ($PlannedBitrateBps -gt 0) { $rows += , @('Planned average bitrate', ('{0} kbps (estimated)' -f [math]::Round($PlannedBitrateBps / 1000.0, 0))) }
    return @{ SummaryRows = $rows; Notes = $notes }
}

function Get-CompressionAudioBudget {
    param($W, $AudioPlan, [string]$Prefix = 'a')
    if (-not $AudioPlan -or $AudioPlan.None) { return [int64]0 }
    if ($AudioPlan.Copy) {
        $info = Get-Media $W 'input'
        if ($info.HasAudio -and $info.Audio[0].Bitrate -gt 0) { return [int64]$info.Audio[0].Bitrate }
        return [int64]128000
    }
    $selectedRate = Get-Answer $W ($Prefix + 'bitrate')
    if ($selectedRate -and [string](Get-Answer $W ($Prefix + 'qm') 'Bitrate') -ne 'Quality') { return [int64]$selectedRate }
    return [int64](Get-DefaultAudioBitrate ([string]$AudioPlan.Encoder))
}

function Get-CompressionVideoAudioPlan {
    param($W, $Info, [string]$Container, [bool]$Advanced)
    if (-not $Info.HasAudio) { return @{ None = $true; Copy = $false; Encoder = ''; Tokens = @('-an') } }
    if ($Advanced) {
        $audioPlan = Resolve-AudioEncode $W -Prefix 'a' -Container $Container -HasAudio $true
        if ($audioPlan.Copy) {
            $message = Test-CopyAllowed $Info $Container -Video $false -Audio $true
            if ($message) { throw $message }
        }
        return $audioPlan
    }
    $message = Test-CopyAllowed $Info $Container -Video $false -Audio $true
    if (-not $message) { return @{ None = $false; Copy = $true; Encoder = 'copy'; Tokens = @('-c:a', 'copy') } }
    $containerInfo = Get-VideoContainer $Container
    $choices = @(Get-AudioEncoderChoices -AllowedFamilies @($containerInfo.Audio))
    if ($choices.Count -eq 0) { throw 'No usable audio encoder is available for the selected output container.' }
    $encoder = [string]$choices[0].Encoder
    return @{ None = $false; Copy = $false; Encoder = $encoder; Tokens = (Get-AudioEncodeArgs -Encoder $encoder -BitrateBps (Get-DefaultAudioBitrate $encoder)) }
}

function Build-CompressionVideoJob {
    param($W, $Info, $Output)
    $advanced = ([string](Get-Answer $W 'mode' 'Simple') -eq 'Advanced')
    $containerId = if ($advanced) { [string](Get-Answer $W 'format' (Get-CompressionDefaultVideoContainer $Info)) } else { Get-CompressionDefaultVideoContainer $Info }
    $container = Get-VideoContainer $containerId
    if (-not $container -or -not (Test-FFMuxer $container.Muxer)) { throw 'The selected output container is not available in this FFmpeg build.' }
    $encoder = if ($advanced) { Get-CompressionAutoVideoEncoder $W } else { [string]((Get-VideoEncoderChoices -AllowedFamilies @($container.Video) | Select-Object -First 1).Encoder) }
    if (-not $encoder) { throw 'No usable video encoder is available for this output container.' }
    $profile = Get-EncoderProfile $encoder
    $goal = if ($advanced) { [string](Get-Answer $W 'goal' 'quality') } else { [string](Get-Answer $W 'strategy' 'Balanced') }
    $presetName = if ($advanced) { '' } else { $goal }
    $mode = 'Quality'; $quality = $null; $bitrate = $null; $targetBytes = $null; $notes = @(); $previewRows = @()
    $audio = Get-CompressionVideoAudioPlan $W $Info $containerId $advanced
    if (-not $advanced -and $presetName -in @('Light', 'Balanced', 'Strong', 'Maximum')) {
        $preset = Get-CompressionPreset -Encoder $encoder -Preset $presetName
        $mode = $preset.Mode; $quality = $preset.Quality; $bitrate = $preset.BitrateBps
        $notes += ($preset.QualityRisk + ' quality-loss risk; actual output size is measured after encoding.')
    } elseif (-not $advanced -and $goal -in @('TargetSize', 'TargetReduction')) {
        $targetMode = if ($goal -eq 'TargetSize') { 'size' } else { 'reduction' }
        $targetBytes = Get-CompressionTargetForAnswers $W $targetMode
        $audioBps = Get-CompressionAudioBudget $W $audio 'a'
        $ratePlan = Get-CompressionBitratePlan -TargetBytes $targetBytes -DurationSec ([double]$Info.Duration) -AudioBps $audioBps -MediaType Video
        $mode = 'Bitrate'; $bitrate = $ratePlan.VideoBitrateBps
        $targetPreview = New-CompressionTargetPreview -Info $Info -TargetBytes $targetBytes -MediaType 'Video' -PlannedBitrateBps $ratePlan.TargetTotalBitrateBps
        $previewRows = @($targetPreview.SummaryRows); $notes += @($targetPreview.Notes)
    } elseif ($advanced -and $goal -eq 'quality') {
        if ($profile.Quality -eq 'none') {
            $preset = Get-CompressionPreset -Encoder $encoder -Preset 'Balanced'
            $mode = $preset.Mode; $quality = $preset.Quality; $bitrate = $preset.BitrateBps
            $notes += 'This encoder has no quality control, so a balanced bitrate fallback was used.'
        } else {
            $quality = Get-Answer $W 'quality' $profile.Balanced
            $mode = 'Quality'
        }
    } elseif ($advanced -and $goal -eq 'bitrate') {
        $mode = 'Bitrate'; $bitrate = [int64](Get-Answer $W 'vbitrate' 2500000)
    } elseif ($advanced -and $goal -in @('size', 'reduction')) {
        $targetMode = $goal
        $targetBytes = Get-CompressionTargetForAnswers $W $targetMode 'videoTargetSize' 'videoTargetReduction'
        $audioBps = Get-CompressionAudioBudget $W $audio 'a'
        $ratePlan = Get-CompressionBitratePlan -TargetBytes $targetBytes -DurationSec ([double]$Info.Duration) -AudioBps $audioBps -MediaType Video
        $mode = 'Bitrate'; $bitrate = $ratePlan.VideoBitrateBps
        $targetPreview = New-CompressionTargetPreview -Info $Info -TargetBytes $targetBytes -MediaType 'Video' -PlannedBitrateBps $ratePlan.TargetTotalBitrateBps
        $previewRows = @($targetPreview.SummaryRows); $notes += @($targetPreview.Notes)
    }
    $encoding = Get-VideoEncodeArgs -Encoder $encoder -Mode $mode -Quality $quality -Preset ([string](Get-Answer $W 'preset' '')) -BitrateBps $bitrate -Container $containerId -Faststart $true
    $videoFilters = @()
    if ($advanced) {
        $resolution = [string](Get-Answer $W 'resolution' 'keep')
        $resolutionFilter = Get-ResolutionFilter $resolution
        if ($resolutionFilter) { $videoFilters += $resolutionFilter }
        $frameRate = [double](Get-Answer $W 'fps' 0)
        if ($frameRate -gt 0) { $videoFilters += ('fps=' + (Format-FFNumber $frameRate 4)) }
    }
    $command = New-FFCommand
    [void](Add-FFInput $command $Info.Path)
    Add-FFOutOpt $command @('-map', ('0:' + $Info.Video[0].Index))
    if ($Info.HasAudio -and -not $audio.None) { Add-FFOutOpt $command @('-map', '0:a') }
    $subtitles = Get-SubtitleMapping $Info $containerId 'copy'
    if ($subtitles.Tokens.Count -gt 0) { Add-FFOutOpt $command $subtitles.Tokens }
    if ($subtitles.Dropped -gt 0) { $notes += "$($subtitles.Dropped) subtitle stream(s) cannot be stored in this format and will be left out." }
    Add-FFOutOpt $command $encoding
    if ($videoFilters.Count -gt 0) { Add-FFOutOpt $command @('-vf', (Join-FFFilters $videoFilters)) }
    Add-FFOutOpt $command $audio.Tokens
    Add-FFOutOpt $command (Get-MetadataTokens 'keep')
    Add-FFOutOpt $command @('-f', $container.Muxer)
    Set-FFOutput $command $Output.Path -Overwrite:$Output.Overwrite
    if ($Output.Overwrite) { $notes += 'The existing output file will be overwritten because you chose that option.' }
    $summary = @(@('Input', $Info.FileName), @('Mode', $(if ($advanced) { 'Advanced' } else { 'Simple' })), @('Video encoder', $encoder), @('Goal', $goal)) + @($previewRows) + @(, @('Audio', $(if ($audio.None) { 'No audio' } elseif ($audio.Copy) { 'Copied without re-encoding' } else { $audio.Encoder })), , @('Output', $Output.Path))
    return New-JobObject -Title 'Compressing media' -Summary $summary -Stages @(@{ Name = 'Compressing video'; Arguments = (Get-FFTokens $command); DurationSec = $Info.Duration }) -OutputPath $Output.Path -EnsureDirs @($Output.Dir) -SourceSize (Get-CompressionSourceBytes $Info) -CompareSize $true -Notes $notes -DetailedSizeMetrics $true -TargetSizeBytes $targetBytes
}

function Build-CompressionAudioJob {
    param($W, $Info, $Output)
    $advanced = ([string](Get-Answer $W 'mode' 'Simple') -eq 'Advanced')
    $formatId = if ($advanced) { [string](Get-Answer $W 'afmt' (Get-CompressionDefaultAudioFormat $Info)) } else { Get-CompressionDefaultAudioFormat $Info }
    $format = Get-AudioFormat $formatId
    if (-not $format -or -not (Test-FFMuxer $format.Muxer)) { throw 'The selected audio output format is not available in this FFmpeg build.' }
    $notes = @(); $targetBytes = $null; $targetMode = ''; $previewRows = @()
    if ($advanced -and (Get-Answer $W 'audioGoal' 'controls') -eq 'controls') {
        $encoding = Resolve-AudioEncode $W -Prefix 'ac' -AllowedFamilies @($format.Codecs) -HasAudio $true
        if ($encoding.None -or $encoding.Copy) { throw 'Audio compression requires re-encoding the audio stream.' }
        $encoder = [string]$encoding.Encoder
        $notes += 'Audio quality depends on the selected codec and rate control; output size is measured after encoding.'
    } elseif ($advanced) {
        $targetMode = [string](Get-Answer $W 'audioGoal')
        $encoder = [string](Get-Answer $W 'targetAudioCodec' '')
        if (-not $encoder -or -not (Test-FFEncoder $encoder)) { throw 'Choose an available lossy audio codec for target-size compression.' }
        $targetBytes = Get-CompressionTargetForAnswers $W $targetMode 'audioTargetSize' 'audioTargetReduction'
        $ratePlan = Get-CompressionBitratePlan -TargetBytes $targetBytes -DurationSec ([double]$Info.Duration) -MediaType Audio
        $encoding = @{ Encoder = $encoder; Tokens = (Get-AudioEncodeArgs -Encoder $encoder -BitrateBps $ratePlan.AudioBitrateBps) }
        $targetPreview = New-CompressionTargetPreview -Info $Info -TargetBytes $targetBytes -MediaType 'Audio' -PlannedBitrateBps $ratePlan.TargetTotalBitrateBps
        $previewRows = @($targetPreview.SummaryRows); $notes += @($targetPreview.Notes)
    } else {
        $choices = @(Get-AudioEncoderChoices -AllowedFamilies @($format.Codecs) | Where-Object { -not $_.Lossless })
        if ($choices.Count -eq 0) { throw 'No lossy audio encoder is available for the selected output format.' }
        $encoder = [string]$choices[0].Encoder
        $strategy = [string](Get-Answer $W 'strategy' 'Balanced')
        if ($strategy -in @('TargetSize', 'TargetReduction')) {
            $targetMode = if ($strategy -eq 'TargetSize') { 'size' } else { 'reduction' }
            $targetBytes = Get-CompressionTargetForAnswers $W $targetMode
            $ratePlan = Get-CompressionBitratePlan -TargetBytes $targetBytes -DurationSec ([double]$Info.Duration) -MediaType Audio
            $encoding = @{ Encoder = $encoder; Tokens = (Get-AudioEncodeArgs -Encoder $encoder -BitrateBps $ratePlan.AudioBitrateBps) }
            $targetPreview = New-CompressionTargetPreview -Info $Info -TargetBytes $targetBytes -MediaType 'Audio' -PlannedBitrateBps $ratePlan.TargetTotalBitrateBps
            $previewRows = @($targetPreview.SummaryRows); $notes += @($targetPreview.Notes)
        } else {
            $preset = Get-AudioCompressionPreset -Encoder $encoder -Preset $strategy
            $encoding = @{ Encoder = $encoder; Tokens = (Get-AudioEncodeArgs -Encoder $encoder -Mode $preset.Mode -VbrQuality $preset.Quality -BitrateBps $preset.BitrateBps) }
            if ($preset.Lossless) { $notes += 'The selected audio encoding is lossless; a smaller output is not guaranteed.' }
            else { $notes += 'Lossy audio encoding may reduce sound quality; output size is measured after encoding.' }
        }
    }
    $command = New-FFCommand
    [void](Add-FFInput $command $Info.Path)
    Add-FFOutOpt $command @('-vn', '-map', ('0:' + $Info.Audio[0].Index))
    Add-FFOutOpt $command $encoding.Tokens
    Add-FFOutOpt $command (Get-MetadataTokens 'keep')
    Add-FFOutOpt $command @('-f', $format.Muxer)
    Set-FFOutput $command $Output.Path -Overwrite:$Output.Overwrite
    if ($Output.Overwrite) { $notes += 'The existing output file will be overwritten because you chose that option.' }
    $summary = @(@('Input', $Info.FileName), @('Mode', $(if ($advanced) { 'Advanced' } else { 'Simple' })), @('Format', $format.Label), @('Audio encoder', $encoder), @('Goal', $(if ($targetMode) { $targetMode } else { Get-Answer $W 'strategy' 'Quality / bitrate controls' }))) + @($previewRows) + @(, @('Output', $Output.Path))
    return New-JobObject -Title 'Compressing audio' -Summary $summary -Stages @(@{ Name = 'Compressing audio'; Arguments = (Get-FFTokens $command); DurationSec = $Info.Duration }) -OutputPath $Output.Path -EnsureDirs @($Output.Dir) -SourceSize (Get-CompressionSourceBytes $Info) -CompareSize $true -Notes $notes -DetailedSizeMetrics $true -TargetSizeBytes $targetBytes
}

function Get-CompressionWebPProperties {
    param($Info)
    $properties = @{ LosslessState = 'Unknown'; HasAlpha = $null }
    if (-not $Info -or -not $Info.Path) { return [pscustomobject]$properties }
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open([string]$Info.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($stream.Length -lt 12) { return [pscustomobject]$properties }
        $riff = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        $null = $reader.ReadUInt32()
        $webp = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        if ($riff -ne 'RIFF' -or $webp -ne 'WEBP') { return [pscustomobject]$properties }
        while (($stream.Position + 8) -le $stream.Length) {
            $chunk = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $chunkSize = [long]$reader.ReadUInt32()
            $chunkStart = $stream.Position
            if ($chunk -eq 'ALPH') { $properties.HasAlpha = $true }
            if ($chunk -eq 'VP8L') {
                $properties.LosslessState = 'Lossless'
                if ($chunkSize -ge 5) {
                    $losslessHeader = $reader.ReadBytes(5)
                    # The VP8L alpha_is_used flag is bit 28 after the 0x2F signature byte.
                    if ($losslessHeader.Count -eq 5 -and $losslessHeader[0] -eq 0x2f) { $properties.HasAlpha = (($losslessHeader[4] -band 0x10) -ne 0) }
                }
                return [pscustomobject]$properties
            }
            if ($chunk -eq 'VP8 ') { $properties.LosslessState = 'Lossy'; return [pscustomobject]$properties }
            $nextPosition = $stream.Position + $chunkSize + ($chunkSize % 2)
            if ($chunk -eq 'VP8X') { $nextPosition = $chunkStart + $chunkSize + ($chunkSize % 2) }
            if ($nextPosition -gt $stream.Length) { return [pscustomobject]$properties }
            $stream.Position = $nextPosition
        }
    } catch { return [pscustomobject]$properties }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
    return [pscustomobject]$properties
}

function Test-CompressionPixelHasAlpha {
    param($Info)
    if (-not $Info.HasVideo -or $Info.Video.Count -eq 0) { return $false }
    $pathProperty = $Info.PSObject.Properties['Path']
    if ($pathProperty -and [System.IO.Path]::GetExtension([string]$pathProperty.Value).ToLowerInvariant() -eq '.webp') {
        $properties = Get-CompressionWebPProperties $Info
        if ($null -ne $properties.HasAlpha) { return [bool]$properties.HasAlpha }
    }
    return ([string]$Info.Video[0].PixFmt -match '(?i)(a|ya)([0-9]+)?(p|le|be)?$|^(rgba|bgra|argb|abgr)')
}

function Get-CompressionImageLosslessState {
    param($Info)
    if (-not $Info) { return 'Unknown' }
    $format = Get-CompressionImageFormat $Info
    if ($format -eq 'png') { return 'Lossless' }
    if ($format -eq 'jpeg') { return 'Lossy' }
    return [string](Get-CompressionWebPProperties $Info).LosslessState
}

function Get-CompressionImageArguments {
    param($Info, [string]$OutputPath, $Profile, $Quality = $null, [bool]$HasAlpha = $false, [string]$VideoFilter = '', [bool]$Overwrite = $false)
    $command = New-FFCommand
    [void](Add-FFInput $command $Info.Path)
    Add-FFOutOpt $command @('-map', '0:v:0', '-frames:v', '1', '-an', '-sn', '-dn', '-map_metadata', '0', '-c:v', $Profile.Encoder)
    if ($VideoFilter) { Add-FFOutOpt $command @('-vf', $VideoFilter) }
    if ($Profile.Format -eq 'jpeg') {
        $jpegQuality = $Profile.Quality
        if ($null -ne $Quality) { $jpegQuality = [int]$Quality }
        Add-FFOutOpt $command @('-q:v', [string]$jpegQuality)
    } elseif ($Profile.Format -eq 'png') {
        Add-FFOutOpt $command @('-pred', [string]$Profile.Prediction)
        if ($HasAlpha) { Add-FFOutOpt $command @('-pix_fmt', 'rgba') }
    } else {
        $webpQuality = $Profile.Quality
        if ($null -ne $Quality) { $webpQuality = [int]$Quality }
        Add-FFOutOpt $command @('-quality', [string]$webpQuality)
        if ($Profile.Lossless) { Add-FFOutOpt $command @('-lossless', '1') }
        if ($HasAlpha) {
            $pixelFormat = 'yuva420p'
            if ($Profile.Lossless) { $pixelFormat = 'bgra' }
            Add-FFOutOpt $command @('-pix_fmt', $pixelFormat)
        }
    }
    Add-FFOutOpt $command @('-f', $Profile.Muxer)
    if ($Profile.Muxer -eq 'image2') { Add-FFOutOpt $command @('-update', '1') }
    Set-FFOutput $command $OutputPath -Overwrite:$Overwrite
    return (Get-FFTokens $command)
}

function Build-CompressionImageJob {
    param($W, $Info, $Output)
    $advanced = ([string](Get-Answer $W 'mode' 'Simple') -eq 'Advanced')
    $format = Get-CompressionImageFormat $Info
    $strategy = [string](Get-Answer $W 'strategy' 'Balanced')
    $goal = if ($advanced) { [string](Get-Answer $W 'imageGoal' 'quality') } else { $strategy }
    $hasAlpha = Test-CompressionPixelHasAlpha $Info
    $losslessState = Get-CompressionImageLosslessState $Info
    $targetBytes = $null
    if ($goal -in @('TargetSize', 'TargetReduction', 'size', 'reduction')) {
        $targetMode = if ($goal -in @('TargetSize', 'size')) { 'size' } else { 'reduction' }
        if ($advanced) { $targetBytes = Get-CompressionTargetForAnswers $W $targetMode 'imageTargetSize' 'imageTargetReduction' }
        else { $targetBytes = Get-CompressionTargetForAnswers $W $targetMode }
    }
    $requestedLossless = [bool](Get-Answer $W 'imageLossless' ($losslessState -ne 'Lossy'))
    $explicitLossyWebp = $advanced -and $format -eq 'webp' -and $goal -eq 'quality' -and -not $requestedLossless
    $lossless = ($format -eq 'png') -or ($format -eq 'webp' -and ($hasAlpha -or ($losslessState -ne 'Lossy' -and -not $explicitLossyWebp) -or $requestedLossless))
    $presetName = if ($strategy -in @('Light', 'Balanced', 'Strong', 'Maximum')) { $strategy } else { 'Maximum' }
    if ($advanced -and $goal -eq 'quality') { $presetName = 'Balanced' }
    $profile = Get-ImageCompressionProfile -Format $format -Preset $presetName -Lossless:$lossless
    if ($advanced -and $goal -eq 'quality' -and $format -in @('jpeg', 'webp') -and -not $lossless) {
        $customQuality = Get-Answer $W 'imageQuality'
        if ($null -ne $customQuality) {
            if ($format -eq 'jpeg' -and ($customQuality -lt 2 -or $customQuality -gt 31)) { throw 'JPEG qscale must be between 2 and 31.' }
            if ($format -eq 'webp' -and ($customQuality -lt 0 -or $customQuality -gt 100)) { throw 'WebP quality must be between 0 and 100.' }
            $profile.Quality = [int]$customQuality
        }
    }
    $notes = @(); $previewRows = @()
    if ($format -eq 'png') { $notes += 'PNG remains lossless. Target size or reduction is a best effort and may not be reached.' }
    elseif ($format -eq 'webp' -and $hasAlpha) { $notes += 'Transparent WebP stays lossless to preserve alpha; a requested size target may not be reached.' }
    elseif ($lossless) { $notes += 'The lossless WebP source stays lossless; the output may be larger than the source.' }
    else { $notes += 'Lossy image encoding can change visible detail. Quality and target-size previews are approximate.' }
    if ($null -ne $targetBytes) {
        $targetPreview = New-CompressionTargetPreview -Info $Info -TargetBytes $targetBytes -MediaType 'Image' -Lossless:$lossless
        $previewRows = @($targetPreview.SummaryRows); $notes += @($targetPreview.Notes)
    }
    if ($explicitLossyWebp -and $losslessState -eq 'Lossless') { $notes += 'You explicitly chose lossy encoding for a lossless WebP source; decoded detail may change.' }
    if ($format -eq 'jpeg' -and (Test-CompressionPixelHasAlpha $Info)) { $notes += 'JPEG cannot preserve transparency; transparent pixels are composited by FFmpeg.' }
    if ($Output.Overwrite) { $notes += 'The existing output file will be overwritten because you chose that option.' }
    $candidates = @()
    if ($targetBytes -and -not $lossless) { $candidates = @(Get-ImageCompressionCandidates -Format $format) }
    if ($candidates.Count -eq 0) {
        $quality = $profile.Quality
        $arguments = Get-CompressionImageArguments -Info $Info -OutputPath $Output.Path -Profile $profile -Quality $quality -HasAlpha:$hasAlpha -Overwrite:$Output.Overwrite
        $stages = @(@{ Name = 'Compressing image'; Arguments = $arguments; DurationSec = $null })
        $summary = @(@('Input', $Info.FileName), @('Format', $format.ToUpperInvariant()), @('Mode', $(if ($advanced) { 'Advanced' } else { 'Simple' })), @('Goal', $goal)) + @($previewRows) + @(, @('Encoder', $profile.Encoder), , @('Output', $Output.Path))
        $job = New-JobObject -Title 'Compressing image' -Summary $summary -Stages $stages -OutputPath $Output.Path -EnsureDirs @($Output.Dir) -SourceSize (Get-CompressionSourceBytes $Info) -CompareSize $true -Notes $notes -DetailedSizeMetrics $true -TargetSizeBytes $targetBytes
        return $job
    }
    $stageRows = @(); $tempFiles = @(); $candidatePaths = @(); $candidateProfiles = @()
    foreach ($candidateQuality in $candidates) {
        $candidatePath = Join-Path $Output.Dir ('.fftui-candidate-' + [guid]::NewGuid().ToString('N') + $profile.Extension)
        $candidateProfile = Get-ImageCompressionProfile -Format $format -Preset $presetName
        $candidateProfile.Quality = [int]$candidateQuality
        $arguments = Get-CompressionImageArguments -Info $Info -OutputPath $candidatePath -Profile $candidateProfile -Quality $candidateQuality -HasAlpha:$hasAlpha
        $stageRows += , @{ Name = ('Trying image quality ' + $candidateQuality); Arguments = $arguments; DurationSec = $null }
        $tempFiles += $candidatePath; $candidatePaths += $candidatePath; $candidateProfiles += $candidateQuality
    }
    $finalize = {
        param($Job, $StageResults)
        $sizes = @()
        foreach ($candidateFile in $candidatePaths) { $size = Get-FileSizeSafe $candidateFile; if ($null -eq $size) { $size = 0 }; $sizes += [long]$size }
        $bestIndex = Get-BestImageCandidateIndex -CandidateSizes $sizes -TargetBytes $targetBytes -Tolerance (Get-CompressionTargetTolerance)
        $chosenPath = [string]$candidatePaths[$bestIndex]
        if (Test-Path -LiteralPath $Output.Path) {
            if (-not $Output.Overwrite) { throw 'The output file appeared during compression. It was not replaced.' }
            $backupPath = $Output.Path + '.fftui-backup-' + [guid]::NewGuid().ToString('N')
            [System.IO.File]::Copy($Output.Path, $backupPath, $false)
            try { [System.IO.File]::Copy($chosenPath, $Output.Path, $true) }
            catch {
                try { [System.IO.File]::Copy($backupPath, $Output.Path, $true) }
                catch { throw ('The overwrite could not be completed or restored; the previous output is preserved at ' + $backupPath) }
                throw ('Could not replace the existing output with the selected image candidate. ' + $_.Exception.Message)
            }
            try { [System.IO.File]::Delete($backupPath) }
            catch { $Job.ResultNotes += ('The new output is complete, but its temporary safety copy could not be removed: ' + $backupPath) }
        } else {
            [System.IO.File]::Copy($chosenPath, $Output.Path, $false)
        }
        if (Test-CompressionTargetMet -OutputBytes $sizes[$bestIndex] -TargetBytes $targetBytes -Tolerance (Get-CompressionTargetTolerance)) {
            $Job.ResultNotes += ('Selected quality {0} from {1} bounded encodes; it is within the {2}% target tolerance.' -f $candidateProfiles[$bestIndex], $candidateProfiles.Count, [math]::Round((Get-CompressionTargetTolerance) * 100, 0))
        } else {
            $Job.ResultNotes += ('The requested target of {0} was not reached within tolerance. The smallest measured candidate was {1} at quality setting {2}; consider a larger target.' -f (Format-FileSize $targetBytes), (Format-FileSize $sizes[$bestIndex]), $candidateProfiles[$bestIndex])
        }
    }.GetNewClosure()
    $summary = @(@('Input', $Info.FileName), @('Format', $format.ToUpperInvariant()), @('Goal', $goal)) + @($previewRows) + @(, @('Search', ($candidates.Count.ToString() + ' bounded quality levels')), , @('Output', $Output.Path))
    $job = New-JobObject -Title 'Compressing image' -Summary $summary -Stages $stageRows -OutputPath $Output.Path -EnsureDirs @($Output.Dir) -TempFiles $tempFiles -SourceSize (Get-CompressionSourceBytes $Info) -CompareSize $true -Notes $notes -DetailedSizeMetrics $true -TargetSizeBytes $targetBytes
    $job.FinalizeOutput = $finalize
    return $job
}

function Build-CompressionJob {
    param($W)
    $Info = Get-Media $W 'input'
    if (-not $Info) { throw 'Choose a supported input file before building the compression job.' }
    $Output = Get-OutputFile $W
    switch (Get-CompressionMediaKind $Info) {
        'Video' { return (Build-CompressionVideoJob $W $Info $Output) }
        'Audio' { return (Build-CompressionAudioJob $W $Info $Output) }
        'Image' { return (Build-CompressionImageJob $W $Info $Output) }
        default { throw 'Choose a video, audio, JPEG, PNG, or WebP file.' }
    }
}

function Start-CompressionWorkflow {
    Start-StandardWorkflow -Title 'Compress Media' -Description 'Compress video, audio, JPEG, PNG, or WebP media with guided quality and file-size controls.' -Icon 'Compress' -StepsFactory { Get-CompressionSteps } -Build { param($W) Build-CompressionJob $W }
}

Export-ModuleMember -Function Get-CompressionMediaKind, Get-CompressionDefaultVideoContainer, Get-CompressionDefaultAudioFormat, Get-CompressionImageFormat, Get-CompressionSourceBytes, Get-CompressionImageLosslessState, Get-CompressionSteps, Get-CompressionAutoVideoEncoder, Build-CompressionJob, Start-CompressionWorkflow, Get-CompressionTargetForAnswers, Build-CompressionVideoJob, Build-CompressionAudioJob, Build-CompressionImageJob, Get-CompressionImageArguments, Test-CompressionPixelHasAlpha
