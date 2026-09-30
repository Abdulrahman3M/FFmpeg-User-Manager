# CompressMedia.psm1 - workflow 6: Compress Media (video and audio).
Set-StrictMode -Version 2.0

function Get-CompressSteps {
    $isVideo = { param($W) $m = Get-Media $W 'input'; [bool]($m -and $m.HasVideo) }
    $isAudioOnly = { param($W) -not (& $isVideo $W) }.GetNewClosure()
    $vGoal = { param($W) (& $isVideo $W) }.GetNewClosure()
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input file (video or audio)' -Require Media
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'Keeping the original format is usually best.'; When = $isVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $c = Get-ContainerIdFromPath (Get-Media $W 'input').Path; if ($c) { $c } else { 'mp4' } } }
    $steps += @{ Id = 'goal'; Type = 'Choice'; Prompt = 'Compression goal'; Help = 'How should the size be decided?'; When = $isVideo
        Choices = { param($W) @( (New-Choice 'recommended' 'Smaller file / Recommended' 'Good quality at a noticeably smaller size.'), (New-Choice 'quality' 'Quality target' 'Choose a quality level.'), (New-Choice 'bitrate' 'Target bitrate' 'Set an average video bitrate.'), (New-Choice 'size' 'Approximate target file size' 'Aim for a size in MB (result is approximate).') ) }
        Default = 'recommended' }
    $steps += @{ Id = 'vcodec'; Type = 'Choice'; Prompt = 'Video codec'; Help = 'H.265/AV1 compress better but encode slower. Hardware encoders are listed when detected.'; When = $isVideo
        Choices = { param($W) $c = Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4')); $l = @( (New-Choice 'auto' 'Automatic / Recommended' 'H.264 or the best available encoder.') ); foreach ($e in (Get-VideoEncoderChoices -AllowedFamilies @($c.Video) -IncludeHardware)) { $l += , (New-Choice $e.Encoder ($e.Label + $(if (-not $e.Hardware) { '  [' + $e.Encoder + ']' } else { '' })) $e.Desc) }; $l }
        Default = 'auto' }
    $isEnc = { param($W) (& $vGoal $W) -and ((Get-Answer $W 'vcodec' 'auto') -ne 'auto') }.GetNewClosure()
    $steps += @{ Id = 'quality'; Type = 'Choice'; Prompt = 'Quality level'; Help = 'Lower numbers mean higher quality and larger files (except where noted).'
        When = { param($W) (& $vGoal $W) -and ((Get-Answer $W 'goal') -eq 'quality') }.GetNewClosure()
        Choices = { param($W) $enc = [string](Get-Answer $W 'vcodec' 'auto'); if ($enc -eq 'auto') { $enc = Get-AutoVideoEncoder $W }; @(Get-QualityChoices $enc) }
        AllowCustom = @{ Label = 'Custom value...'; Type = 'Integer'; Prompt = 'Custom quality value'; Help = 'Enter a whole number in the encoder range.'; Example = '26'; ValueLabel = 'Quality' }
        Default = { param($W) $enc = [string](Get-Answer $W 'vcodec' 'auto'); if ($enc -eq 'auto') { $enc = Get-AutoVideoEncoder $W }; (Get-EncoderProfile $enc).Small } }
    $steps += @{ Id = 'vbitrate'; Type = 'Choice'; Prompt = 'Target video bitrate'; Help = 'Lower bitrate means a smaller file.'; When = { param($W) (& $vGoal $W) -and ((Get-Answer $W 'goal') -eq 'bitrate') }.GetNewClosure()
        Choices = { param($W) @( (New-Choice 500000 '500 kbps' 'Very small.'), (New-Choice 1000000 '1 Mbps' 'Small.'), (New-Choice 2500000 '2.5 Mbps' '720p.'), (New-Choice 5000000 '5 Mbps' '1080p.') ) }
        AllowCustom = @{ Label = 'Custom bitrate...'; Type = 'Bitrate'; Prompt = 'Custom video bitrate'; Help = 'Use k or M suffix.'; Example = '1800k'; Desc = 'For example 1800k.' }
        Default = 1000000 }
    $steps += @{ Id = 'sizeMB'; Type = 'Decimal'; Prompt = 'Target file size (MB)'; Help = 'The result will be close to this size but not exact.'; Example = '25'; Min = 0.5; Max = 100000; Label = 'Size'; Unit = 'MB'
        When = { param($W) (& $vGoal $W) -and ((Get-Answer $W 'goal') -eq 'size') }.GetNewClosure()
        Validate = { param($v, $W) $m = Get-Media $W 'input'; if (-not $m.Duration) { return 'The media duration is unknown, so a target size cannot be calculated.' }; $ab = 128000; try { $null = Get-TargetBitrateForSize ($v * 1MB) $m.Duration $ab } catch { return $_.Exception.Message }; $null } }
    $steps += @{ Id = 'preset'; Type = 'Choice'; Prompt = 'Encoding speed / preset'; Help = 'Slower presets compress better but take longer.'
        When = { param($W) (& $vGoal $W) -and ((Get-EncoderProfile (Get-AutoVideoEncoder $W)).ContainsKey('Presets')) }.GetNewClosure()
        Choices = { param($W) $pr = Get-EncoderProfile (Get-AutoVideoEncoder $W); @($pr.Presets | ForEach-Object { New-Choice $_ ($_ + $(if ($_ -eq $pr.DefaultPreset) { '  (Recommended)' } else { '' })) }) }
        Default = { param($W) (Get-EncoderProfile (Get-AutoVideoEncoder $W)).DefaultPreset } }
    $steps += Get-ResolutionStep -Id 'resolution' -Prompt 'Reduce resolution?'
    $steps[-1].When = $isVideo
    $fr = Get-FrameRateStep -Id 'fps' -Prompt 'Reduce frame rate?' -Help 'Lower frame rates give smaller files. Keep original unless needed.'
    $fr.When = $isVideo
    $steps += $fr
    $steps += Get-AudioEncodeSteps -Prefix 'a' -ContainerScript { param($W) [string](Get-Answer $W 'format' 'mp4') } -OfferCopy -OfferRemove -When $isVideo
    # ---- audio-only
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'Lossy formats create much smaller files.'; When = $isAudioOnly
        Choices = { param($W) @(Get-AvailableAudioFormats | Where-Object { $_.Id -notin @('flac', 'wav') } | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp3' }
    $afam = { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { @($f.Codecs) } else { @() } }
    $steps += Get-AudioEncodeSteps -Prefix 'ac' -FormatAudioFamilies $afam -When $isAudioOnly -Full -OfferVbr
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'compressed' -Extension {
        param($W) $m = Get-Media $W 'input'
        if ($m.HasVideo) { return (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext }
        return (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
    return $steps
}

function Get-AutoVideoEncoder {
    param($W)
    $enc = [string](Get-Answer $W 'vcodec' 'auto')
    if ($enc -ne 'auto') { return $enc }
    $c = Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))
    $l = @(Get-VideoEncoderChoices -AllowedFamilies @($c.Video))
    if ($l.Count) { return [string]$l[0].Encoder }
    return ''
}

function Build-CompressJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $notes = @()
    $cmd = New-FFCommand
    $srcSize = $info.Size
    if ($info.HasVideo) {
        $container = [string](Get-Answer $W 'format' 'mp4'); $c = Get-VideoContainer $container
        $enc = Get-AutoVideoEncoder $W
        if (-not $enc) { throw 'No usable video encoder is available in your FFmpeg build for this format.' }
        $goal = [string](Get-Answer $W 'goal' 'recommended')
        $prof = Get-EncoderProfile $enc
        $mode = 'Recommended'; $quality = $null; $bitrate = $null
        $ae = Resolve-AudioEncode $W -Prefix 'a' -Container $container -HasAudio $info.HasAudio
        if ($ae.Copy) { $msg = Test-CopyAllowed $info $container -Video $false -Audio $true; if ($msg) { throw $msg } }
        switch ($goal) {
            'recommended' { if ($prof.Quality -ne 'none') { $mode = 'Quality'; $quality = $prof.Small } else { $mode = 'Bitrate'; $bitrate = 1500000 } }
            'quality' { if ($prof.Quality -eq 'none') { throw 'This encoder does not support quality-based compression. Choose Target bitrate instead.' }; $mode = 'Quality'; $quality = Get-Answer $W 'quality' }
            'bitrate' { $mode = 'Bitrate'; $bitrate = Get-Answer $W 'vbitrate' }
            'size' {
                $audioBps = 0
                if ($ae.None -or -not $info.HasAudio) { $audioBps = 0 } elseif ($ae.Copy) { $audioBps = $(if ($info.Audio[0].Bitrate) { $info.Audio[0].Bitrate } else { 128000 }) } else { $audioBps = $(if (Get-Answer $W 'abitrate') { Get-Answer $W 'abitrate' } else { Get-DefaultAudioBitrate $ae.Encoder }) }
                $bitrate = Get-TargetBitrateForSize (([double](Get-Answer $W 'sizeMB')) * 1MB) $info.Duration $audioBps
                $mode = 'Bitrate'
                $notes += 'The final size is approximate. Encoders rarely hit an exact size.'
            }
        }
        $ve = Get-VideoEncodeArgs -Encoder $enc -Mode $mode -Quality $quality -Preset ([string](Get-Answer $W 'preset' '')) -BitrateBps $bitrate -Container $container -Faststart $true
        $vf = @()
        $rf = Get-ResolutionFilter ([string](Get-Answer $W 'resolution' 'keep')); if ($rf) { $vf += $rf }
        $fps = [double](Get-Answer $W 'fps' 0); if ($fps -gt 0) { $vf += ('fps=' + (Format-FFNumber $fps 4)) }
        [void](Add-FFInput $cmd $info.Path)
        Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index))
        if ($info.HasAudio -and -not $ae.None) { Add-FFOutOpt $cmd @('-map', '0:a') }
        $sm = Get-SubtitleMapping $info $container 'copy'
        if ($sm.Tokens.Count -gt 0) { Add-FFOutOpt $cmd $sm.Tokens }
        Add-FFOutOpt $cmd $ve
        if ($vf.Count -gt 0) { Add-FFOutOpt $cmd @('-vf', (Join-FFFilters $vf)) }
        Add-FFOutOpt $cmd $ae.Tokens
        Add-FFOutOpt $cmd (Get-MetadataTokens 'keep')
        Add-FFOutOpt $cmd @('-f', $c.Muxer)
        $goalText = @{ recommended = 'Smaller file (recommended)'; quality = "Quality level $quality"; bitrate = ('Bitrate ' + (Format-Bitrate ([int64]$bitrate))); size = ('About ' + (Get-Answer $W 'sizeMB') + ' MB (bitrate ' + (Format-Bitrate ([int64]$bitrate)) + ')') }[$goal]
        $rows = @(@('Input', $info.FileName), @('Goal', $goalText), @('Video codec', $enc), @('Audio', $(if ($ae.None) { 'Removed' } elseif ($ae.Copy) { 'Copy original' } else { $ae.Encoder })), @('Output', $out.Path))
    } else {
        $fmt = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))
        $ae = Resolve-AudioEncode $W -Prefix 'ac' -Container '' -AllowedFamilies @($fmt.Codecs) -HasAudio $true
        [void](Add-FFInput $cmd $info.Path)
        Add-FFOutOpt $cmd @('-vn', '-map', ('0:' + $info.Audio[0].Index))
        Add-FFOutOpt $cmd $ae.Tokens
        Add-FFOutOpt $cmd (Get-MetadataTokens 'keep')
        Add-FFOutOpt $cmd @('-f', $fmt.Muxer)
        $rows = @(@('Input', $info.FileName), @('Format', $fmt.Label), @('Audio codec', $ae.Encoder), @('Output', $out.Path))
    }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title 'Compressing media' -Summary $rows -Stages @(@{ Name = 'Compressing'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $srcSize -CompareSize $true -Notes $notes
}

function Start-CompressWorkflow {
    Start-StandardWorkflow -Title 'Compress Media' -Description 'Reduce video or audio file size with guided quality controls.' -Icon 'Compress' -StepsFactory { Get-CompressSteps } -Build { param($W) Build-CompressJob $W }
}

Export-ModuleMember -Function Get-CompressSteps, Get-AutoVideoEncoder, Build-CompressJob, Start-CompressWorkflow
