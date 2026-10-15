# AudioTools.psm1 - workflow 10: Audio Tools submenu (volume, loudness, sample rate, channels, tempo, remove/replace audio).
Set-StrictMode -Version 2.0

function Get-AudioInputStep {
    param([string]$Prompt = 'Input file (audio or video with audio)', [switch]$AudioOnly)
    $extra = $null
    if ($AudioOnly) { $extra = { param($info, $W) if ($info.HasVideo) { return 'This tool changes audio only. For a video with sound, use "Change Playback Speed" instead.' }; $null } }
    return (Get-InputFileStep -Id 'input' -Prompt $Prompt -Require Audio -Extra $extra)
}

# ---- 1. Adjust Volume -----------------------------------------------------------------

function Get-VolumeSteps {
    $steps = @(); $steps += Get-AudioInputStep
    $steps += @{ Id = 'voltype'; Type = 'Choice'; Prompt = 'How do you want to change the volume?'; Help = '100% means unchanged. +6 dB is roughly twice as loud.'
        Choices = { param($W) @( (New-Choice 'preset' 'Choose a preset' 'Common adjustments.'), (New-Choice 'percent' 'Percentage' 'For example 150% is louder, 50% is quieter.'), (New-Choice 'db' 'Decibels (dB)' 'Precise adjustment; negative values are quieter.') ) }; Default = 'preset' }
    $steps += @{ Id = 'volpreset'; Type = 'Choice'; Prompt = 'Volume preset'; Help = 'Louder presets may cause clipping (distortion) on loud audio.'; When = { param($W) (Get-Answer $W 'voltype') -eq 'preset' }
        Choices = { param($W) @( (New-Choice 'p:0.5' '50% (much quieter)' 'Halves the loudness; good for audio that is far too loud.'), (New-Choice 'p:0.75' '75% (quieter)' 'A gentle reduction in loudness.'), (New-Choice 'p:1.25' '125% (louder)' 'A small boost; safe for most audio.'), (New-Choice 'p:1.5' '150% (much louder)' 'A strong boost; may distort if the audio is already loud.'), (New-Choice 'p:2' '200% (double)' 'Doubles the amplitude; likely to distort loud audio.'), (New-Choice 'd:-6' '-6 dB' 'Half the amplitude; clearly quieter without losing quality.'), (New-Choice 'd:6' '+6 dB' 'Twice the amplitude; clearly louder, watch for distortion.') ) }; Default = 'p:1.25' }
    $steps += @{ Id = 'volpct'; Type = 'Decimal'; Prompt = 'Volume (%)'; Help = '100 = unchanged. Range 1 to 1000.'; Example = '150'; Min = 1; Max = 1000; Label = 'Volume'; Unit = '%'; Default = 100; When = { param($W) (Get-Answer $W 'voltype') -eq 'percent' } }
    $steps += @{ Id = 'voldb'; Type = 'Decimal'; Prompt = 'Volume change (dB)'; Help = 'Positive = louder, negative = quieter. Range -60 to +40.'; Example = '-3  or  +6'; Min = -60; Max = 40; Label = 'Volume change'; Unit = 'dB'; Default = 3; When = { param($W) (Get-Answer $W 'voltype') -eq 'db' } }
    $steps += Get-AudioToolTailSteps -Suffix 'volume'
    return $steps
}

function Build-VolumeJob {
    param($W)
    $t = [string](Get-Answer $W 'voltype' 'preset')
    switch ($t) {
        'percent' { $f = 'volume=' + (Format-FFNumber (([double](Get-Answer $W 'volpct' 100)) / 100) 4); $label = ("{0:0.##}%" -f (Get-Answer $W 'volpct')) }
        'db' { $f = 'volume=' + (Format-FFNumber ([double](Get-Answer $W 'voldb' 0)) 3) + 'dB'; $label = ("{0:+0.##;-0.##;0} dB" -f (Get-Answer $W 'voldb')) }
        default {
            $p = [string](Get-Answer $W 'volpreset' 'p:1.25')
            if ($p.StartsWith('d:')) { $f = 'volume=' + $p.Substring(2) + 'dB'; $label = ($p.Substring(2) + ' dB') } else { $f = 'volume=' + $p.Substring(2); $label = ("{0:0.##}%" -f ([double]$p.Substring(2) * 100)) }
        }
    }
    $info = Get-Media $W 'input'
    return New-AudioProcessJob -W $W -Title 'Adjusting volume' -AudioFilters @($f) -Rows @(@('Input', $info.FileName), @('Volume', $label)) -StageName 'Adjusting volume'
}

# ---- 2. Normalize Loudness ------------------------------------------------------------

function Get-NormalizeSteps {
    $steps = @(); $steps += Get-AudioInputStep
    $steps += @{ Id = 'target'; Type = 'Choice'; Prompt = 'Loudness target'; Help = 'Normalization makes quiet and loud files sound equally loud. It takes two passes (analysis, then processing).'
        Choices = { param($W) @( (New-Choice '-16' 'Streaming / podcast (-16 LUFS)  (Recommended)' 'Common target for online audio.'), (New-Choice '-14' 'Loud streaming (-14 LUFS)' 'Louder; used by some music platforms.'), (New-Choice '-23' 'Broadcast (-23 LUFS, EBU R128)' 'Quieter, TV/radio standard.') ) }; Default = '-16' }
    $steps += Get-AudioToolTailSteps -Suffix 'normalized'
    return $steps
}

function Build-NormalizeJob {
    param($W)
    if (-not (Test-FFFilter 'loudnorm')) { throw 'Your FFmpeg build does not include the loudnorm filter.' }
    $info = Get-Media $W 'input'
    $target = [string](Get-Answer $W 'target' '-16')
    $base = "I=$target" + ':TP=-1.5:LRA=11'
    $job = New-AudioProcessJob -W $W -Title 'Normalizing loudness' -AudioFilters @('loudnorm=' + $base) -Rows @(@('Input', $info.FileName), @('Target', "$target LUFS (two-pass)")) -StageName 'Processing'
    $final = $job.Stages[0].Arguments
    $analysis = @('-loglevel', 'info', '-nostdin', '-i', $info.Path, '-map', ('0:' + $info.Audio[0].Index), '-vn', '-af', ('loudnorm=' + $base + ':print_format=json'), '-f', 'null', '-')
    $dur = $info.Duration
    $baseLocal = $base
    $factory = {
        param($Job, $Results)
        $err = [string]$Results[0].StdErr
        $m = [regex]::Match($err, '\{[^{}]*"input_i"[^{}]*\}')
        if (-not $m.Success) { throw 'The loudness analysis did not return usable measurements.' }
        $j = $m.Value | ConvertFrom-Json
        foreach ($k in 'input_i', 'input_tp', 'input_lra', 'input_thresh', 'target_offset') { if ("$($j.$k)" -notmatch '^-?\d+(\.\d+)?$') { throw 'The audio is too quiet or silent to normalize.' } }
        $af = 'loudnorm=' + $baseLocal + ':measured_I=' + $j.input_i + ':measured_TP=' + $j.input_tp + ':measured_LRA=' + $j.input_lra + ':measured_thresh=' + $j.input_thresh + ':offset=' + $j.target_offset + ':linear=true'
        $out = @()
        for ($i = 0; $i -lt $Job.FinalArgs.Count; $i++) {
            if ($Job.FinalArgs[$i] -eq '-af') { $out += '-af'; $out += $af; $i++ } else { $out += $Job.FinalArgs[$i] }
        }
        return $out
    }.GetNewClosure()
    $job.FinalArgs = $final
    $job.Stages = @(@{ Name = 'Analysis'; Arguments = $analysis; DurationSec = $dur }, @{ Name = 'Processing'; Factory = $factory; Arguments = $final; DurationSec = $dur })
    return $job
}

# ---- 3. Sample rate / 4. Channels ------------------------------------------------------

function Get-SampleRateSteps {
    $sr = Get-PresetList 'sampleRates' @(8000, 16000, 22050, 32000, 44100, 48000, 96000)
    $steps = @(); $steps += Get-AudioInputStep
    $steps += @{ Id = 'sr'; Type = 'Choice'; Prompt = 'New sample rate'; Help = '44.1 kHz is CD quality, 48 kHz is standard for video.'
        Choices = { param($W) @($sr | ForEach-Object { New-Choice ([int]$_) ("{0:N0} Hz" -f $_) (Get-SampleRateDescription ([int]$_)) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 8000; Max = 192000; Prompt = 'Custom sample rate (Hz)'; Help = 'Between 8000 and 192000.'; Example = '44100'; ValueLabel = 'Sample rate'; Desc = 'For example 44100.' }
        Default = 44100 }
    $steps += Get-AudioToolTailSteps -Suffix 'samplerate'
    return $steps
}

function Build-SampleRateJob {
    param($W)
    $info = Get-Media $W 'input'
    $sr = [int](Get-Answer $W 'sr' 44100)
    return New-AudioProcessJob -W $W -Title 'Changing sample rate' -ExtraAudioOptions @('-ar', [string]$sr) -Rows @(@('Input', $info.FileName), @('Sample rate', ("{0:N0} Hz" -f $sr))) -StageName 'Resampling audio'
}

function Get-ChannelsSteps {
    $steps = @(); $steps += Get-AudioInputStep
    $steps += @{ Id = 'ch'; Type = 'Choice'; Prompt = 'Channel layout'; Help = 'Mono has one channel. Stereo has left and right. Downmixing is safe; upmixing duplicates channels.'
        Choices = { param($W) $m = Get-Media $W 'input'; $cur = $m.Audio[0].Channels; @( (New-Choice 1 'Mono (1 channel)' 'One channel for everything. Smallest size; good for speech.'), (New-Choice 2 'Stereo (2 channels)' 'Left and right channels. The normal choice for music and video.'), (New-Choice 6 '5.1 surround (6 channels)' 'Home-cinema layout with front, rear, center and bass channels.'), (New-Choice 8 '7.1 surround (8 channels)' 'Large cinema layout with eight channels.') ) }
        AllowCustom = @{ Label = 'Custom count...'; Type = 'Integer'; Min = 1; Max = 8; Prompt = 'Number of channels'; Help = 'Between 1 and 8.'; Example = '2'; ValueLabel = 'Channels'; Desc = 'For example 2.' }
        Default = 2 }
    $steps += Get-AudioToolTailSteps -Suffix 'channels'
    return $steps
}

function Build-ChannelsJob {
    param($W)
    $info = Get-Media $W 'input'
    $ch = [int](Get-Answer $W 'ch' 2)
    return New-AudioProcessJob -W $W -Title 'Changing channels' -ExtraAudioOptions @('-ac', [string]$ch) -Rows @(@('Input', $info.FileName), @('Channels', [string]$ch)) -StageName 'Remixing audio'
}

# ---- 5. Tempo / speed --------------------------------------------------------------------

function Get-AudioSpeedSteps {
    $speedList = Get-PresetList 'speeds' @(0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0)
    $steps = @(); $steps += Get-AudioInputStep -Prompt 'Input audio file' -AudioOnly
    $steps += @{ Id = 'method'; Type = 'Choice'; Prompt = 'Speed method'; Help = 'Tempo change keeps the pitch (voices sound natural). Speed and pitch changes both, like a tape or record.'
        Choices = { param($W) @( (New-Choice 'tempo' 'Tempo only (keep pitch)' 'Recommended for speech and music.'), (New-Choice 'pitch' 'Speed and pitch together' 'Faster = higher pitch, slower = lower pitch.') ) }; Default = 'tempo' }
    $steps += @{ Id = 'speed'; Type = 'Choice'; Prompt = 'Speed'; Help = '1.0x is the original speed.'
        Choices = { param($W) @($speedList | ForEach-Object { New-Choice ([double]$_) ("{0:0.0#}x" -f $_) (Get-SpeedDescription $_) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.1; Max = 8; Prompt = 'Custom speed'; Help = 'A multiplier between 0.1 and 8.'; Example = '1.35'; ValueLabel = 'Speed'; Desc = 'For example 1.35.' }
        Default = 1.5 }
    $steps += Get-AudioToolTailSteps -Suffix 'speed'
    return $steps
}

function Build-AudioSpeedJob {
    param($W)
    $info = Get-Media $W 'input'
    $speed = [double](Get-Answer $W 'speed' 1.0)
    if ($speed -le 0) { throw 'Speed must be greater than zero.' }
    $method = [string](Get-Answer $W 'method' 'tempo')
    if ($method -eq 'tempo') { $f = Get-AtempoChain $speed }
    else {
        $sr = [int]$info.Audio[0].SampleRate; if ($sr -le 0) { $sr = 44100 }
        $f = "asetrate=$([int][math]::Round($sr * $speed)),aresample=$sr"
    }
    return New-AudioProcessJob -W $W -Title 'Changing audio speed' -AudioFilters @($f) -Speed $speed -Rows @(@('Input', $info.FileName), @('Speed', ("{0:0.0#}x" -f $speed)), @('Method', $(if ($method -eq 'tempo') { 'Tempo (pitch kept)' } else { 'Speed + pitch' }))) -StageName 'Changing speed'
}

# ---- 6. Remove audio ---------------------------------------------------------------------

function Get-RemoveAudioSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'noaudio' -Extension { param($W) [System.IO.Path]::GetExtension((Get-Media $W 'input').Path) }
    return $steps
}

function Build-RemoveAudioJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd @('-map', '0', '-map', '-0:a', '-c', 'copy', '-an')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @('The video is copied without re-encoding; only the audio is removed.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    if (-not $info.HasAudio) { $notes += 'This file has no audio stream; the output will be an identical copy.' }
    return New-JobObject -Title 'Removing audio' -Summary @(@('Input', $info.FileName), @('Output', $out.Path)) -Stages @(@{ Name = 'Removing audio'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -Notes $notes
}

# ---- 7. Replace / add audio ------------------------------------------------------------------

function Get-ReplaceAudioSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Video file' -Require Video
    $steps += Get-InputFileStep -Id 'audio' -Prompt 'Audio file to use' -Require Audio -NoPanel -PanelTitle 'New audio' -Example 'C:\Music\track.mp3' -Help 'The audio that will replace or be added to the video.'
    $steps += @{ Id = 'mode'; Type = 'Choice'; Prompt = 'What should happen to the existing audio?'; Help = 'Replace removes the original audio tracks; Add keeps them and adds the new track.'
        When = { param($W) (Get-Media $W 'input').HasAudio }
        Choices = { param($W) @( (New-Choice 'replace' 'Replace the existing audio' 'The video keeps only the new sound; the old audio tracks are dropped.'), (New-Choice 'add' 'Add as an additional audio track' 'The video keeps its original sound and gets the new track as an extra choice.') ) }; Default = 'replace' }
    $steps += @{ Id = 'offset'; Type = 'Decimal'; Prompt = 'Audio start offset (seconds)'; Help = 'Delay the new audio by this many seconds to fix sync. Enter 0 for none.'; Example = '0.5'; Min = 0; Max = 3600; Default = 0; Label = 'Offset'; Unit = 'seconds' }
    $steps += @{ Id = 'length'; Type = 'Choice'; Prompt = 'Output length'; Help = 'What if the audio and video have different lengths?'
        Choices = { param($W) @( (New-Choice 'video' 'Keep the full video length' 'The video plays to its end; if the audio is shorter the rest is silent.'), (New-Choice 'shortest' 'Stop at the shorter of the two' 'The result ends when the shorter of the audio and video ends.') ) }; Default = 'video' }
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The file type of the result.'
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $c = Get-ContainerIdFromPath (Get-Media $W 'input').Path; if ($c) { $c } else { 'mkv' } } }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -ContainerScript { param($W) [string](Get-Answer $W 'format' 'mkv') } -OfferCopy
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'newaudio' -ProtectIds @('input', 'audio') -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mkv'))).Ext }
    return $steps
}

function Convert-AudioTokensForStream {
    # Rewrites global audio encoder options so they apply only to the Nth output audio stream.
    param([string[]]$Tokens, [int]$N)
    $map = @{ '-c:a' = "-c:a:$N"; '-b:a' = "-b:a:$N"; '-q:a' = "-q:a:$N"; '-ar' = "-ar:a:$N"; '-ac' = "-ac:a:$N" }
    return @($Tokens | ForEach-Object { if ($map.ContainsKey($_)) { $map[$_] } else { $_ } })
}

function Build-ReplaceAudioJob {
    param($W)
    $v = Get-Media $W 'input'; $a = Get-Media $W 'audio'
    $container = [string](Get-Answer $W 'format' 'mkv'); $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $mode = [string](Get-Answer $W 'mode' 'replace')
    $ae = Resolve-AudioEncode $W -Prefix 'a' -Container $container -HasAudio $true
    if ($ae.Copy) { $msg = Test-CopyAllowed $a $container -Video $false -Audio $true; if ($msg) { throw $msg } }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $v.Path)
    $off = [double](Get-Answer $W 'offset' 0)
    $inOpts = @(); if ($off -gt 0) { $inOpts = @('-itsoffset', (Format-FFNumber $off 3)) }
    [void](Add-FFInput $cmd $a.Path $inOpts)
    Add-FFOutOpt $cmd @('-map', ('0:' + $v.Video[0].Index))
    if ($mode -eq 'add' -and $v.HasAudio) { Add-FFOutOpt $cmd @('-map', '0:a') }
    Add-FFOutOpt $cmd @('-map', ('1:' + $a.Audio[0].Index), '-c:v', 'copy')
    if ($mode -eq 'add' -and $v.HasAudio) {
        # Keep the original tracks untouched; encode only the new (last) audio stream.
        Add-FFOutOpt $cmd @('-c:a', 'copy')
        if (-not $ae.Copy) { Add-FFOutOpt $cmd (Convert-AudioTokensForStream $ae.Tokens $v.Audio.Count) }
    } else { Add-FFOutOpt $cmd $ae.Tokens }
    if ((Get-Answer $W 'length' 'video') -eq 'shortest') { Add-FFOutOpt $cmd @('-shortest') }
    $sm = Get-SubtitleMapping $v $container 'copy'; if ($sm.Tokens.Count -gt 0) { Add-FFOutOpt $cmd $sm.Tokens }
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Video', $v.FileName), @('Audio', $a.FileName), @('Mode', $(if ($mode -eq 'add') { 'Add as additional track' } else { 'Replace existing audio' })), @('Offset', ("{0:0.###} s" -f $off)), @('Output', $out.Path))
    return New-JobObject -Title 'Replacing audio' -Summary $rows -Stages @(@{ Name = 'Muxing audio'; Arguments = (Get-FFTokens $cmd); DurationSec = $v.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $v.Size -Notes $notes
}

# ---- submenu -------------------------------------------------------------------------------------

function Start-AudioToolsWorkflow {
    $items = @(
        @{ Label = 'Adjust Volume'; Desc = 'Make audio louder or quieter using percent or dB.'; Value = { Start-StandardWorkflow -Title 'Adjust Volume' -Description 'Change how loud the audio is.' -Icon 'AudioTools' -StepsFactory { Get-VolumeSteps } -Build { param($W) Build-VolumeJob $W } } },
        @{ Label = 'Normalize Loudness'; Desc = 'Even out loudness with a two-pass analysis.'; Enabled = (Test-FFFilter 'loudnorm'); Reason = 'Requires the loudnorm filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Normalize Loudness' -Description 'Make loudness consistent (analysis pass + processing pass).' -Icon 'AudioTools' -StepsFactory { Get-NormalizeSteps } -Build { param($W) Build-NormalizeJob $W } } },
        @{ Label = 'Change Sample Rate'; Desc = 'Resample audio to another rate such as 44.1 or 48 kHz.'; Value = { Start-StandardWorkflow -Title 'Change Sample Rate' -Description 'Resample the audio.' -Icon 'AudioTools' -StepsFactory { Get-SampleRateSteps } -Build { param($W) Build-SampleRateJob $W } } },
        @{ Label = 'Change Channels'; Desc = 'Convert between mono, stereo and surround.'; Value = { Start-StandardWorkflow -Title 'Change Channels' -Description 'Change the channel layout.' -Icon 'AudioTools' -StepsFactory { Get-ChannelsSteps } -Build { param($W) Build-ChannelsJob $W } } },
        @{ Label = 'Change Audio Speed / Tempo'; Desc = 'Speed up or slow down audio, with or without changing pitch.'; Value = { Start-StandardWorkflow -Title 'Change Audio Speed / Tempo' -Description 'Make audio faster or slower.' -Icon 'Speed' -StepsFactory { Get-AudioSpeedSteps } -Build { param($W) Build-AudioSpeedJob $W } } },
        @{ Label = 'Remove Audio from Video'; Desc = 'Delete the sound track without re-encoding the video.'; Value = { Start-StandardWorkflow -Title 'Remove Audio from Video' -Description 'Save a silent copy of a video.' -Icon 'AudioTools' -StepsFactory { Get-RemoveAudioSteps } -Build { param($W) Build-RemoveAudioJob $W } } },
        @{ Label = 'Replace / Add Audio Track'; Desc = 'Put a different audio file on a video, or add another track.'; Value = { Start-StandardWorkflow -Title 'Replace / Add Audio Track' -Description 'Combine a video with another audio file.' -Icon 'AudioTools' -StepsFactory { Get-ReplaceAudioSteps } -Build { param($W) Build-ReplaceAudioJob $W } } }
    ) + @(Get-AudioEffectMenuItems)
    Show-WorkflowSubmenu -Title ((Get-Icon 'AudioTools') + '  Audio Tools') -Subtitle 'Adjust volume, sample rate, channels, speed and other common audio properties.' -Items $items
}

Export-ModuleMember -Function Get-VolumeSteps, Build-VolumeJob, Get-NormalizeSteps, Build-NormalizeJob, Get-SampleRateSteps, Build-SampleRateJob, Get-ChannelsSteps, Build-ChannelsJob, Get-AudioSpeedSteps, Build-AudioSpeedJob, Get-RemoveAudioSteps, Build-RemoveAudioJob, Get-ReplaceAudioSteps, Build-ReplaceAudioJob, Start-AudioToolsWorkflow
