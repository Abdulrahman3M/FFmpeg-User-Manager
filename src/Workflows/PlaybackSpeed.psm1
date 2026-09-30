# PlaybackSpeed.psm1 - workflow 16: Change Playback Speed.
Set-StrictMode -Version 2.0

function Get-SpeedSteps {
    $speedList = Get-PresetList 'speeds' @(0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0)
    $isVideo = { param($W) $m = Get-Media $W 'input'; [bool]($m -and $m.HasVideo) }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media (video or audio)' -Require Media
    $steps += @{ Id = 'speed'; Type = 'Choice'; Prompt = 'Playback speed'; Help = '1.0x is the original speed. Below 1 = slow motion, above 1 = fast forward.'
        Choices = { param($W) @($speedList | ForEach-Object { New-Choice ([double]$_) (("{0:0.0#}x" -f $_) + $(if ($_ -eq 1.0) { '  (unchanged)' } else { '' })) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.1; Max = 10; Prompt = 'Custom speed'; Help = 'A multiplier between 0.1 and 10.'; Example = '1.35'; ValueLabel = 'Speed'; Desc = 'For example 1.35.' }
        Default = 1.5
        Validate = { param($v, $W) if ([math]::Abs($v - 1.0) -lt 1e-9) { return 'A speed of 1.0x changes nothing. Choose another speed.' }; $null } }
    $steps += @{ Id = 'vmode'; Type = 'Choice'; Prompt = 'Video behavior for slow motion'; Help = 'Duplicating frames is fast. Interpolation creates smoother slow motion but is slow.'
        When = { param($W) (& $isVideo $W) -and ([double](Get-Answer $W 'speed' 1)) -lt 1 }.GetNewClosure()
        Choices = { param($W) @( (New-Choice 'standard' 'Standard (duplicate frames)' 'Fast; recommended.'), (New-Choice 'interpolate' 'Smooth (motion interpolation)' 'Slow to process.' (Test-FFFilter 'minterpolate') 'Requires the minterpolate filter (not in this FFmpeg build).') ) }; Default = 'standard' }
    $steps += @{ Id = 'audio'; Type = 'Choice'; Prompt = 'Audio behavior'; Help = 'Keeping audio synchronized changes its tempo (pitch stays natural).'
        When = { param($W) $m = Get-Media $W 'input'; [bool]($m.HasVideo -and $m.HasAudio) }
        Choices = { param($W) @( (New-Choice 'sync' 'Keep audio synchronized'), (New-Choice 'remove' 'Remove audio') ) }; Default = 'sync' }
    # video output
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The file type of the result.'; When = $isVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $c = Get-ContainerIdFromPath (Get-Media $W 'input').Path; if ($c) { $c } else { 'mp4' } } }
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript { param($W) [string](Get-Answer $W 'format' 'mp4') } -Level Simple -GateWhen $isVideo
    # audio-only output
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The audio file type of the result.'; When = { param($W) -not (& $isVideo $W) }.GetNewClosure()
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $e = [System.IO.Path]::GetExtension((Get-Media $W 'input').Path).ToLowerInvariant().TrimStart('.'); foreach ($f in Get-AvailableAudioFormats) { if ($f.Id -eq $e) { return $f.Id } }; 'mp3' } }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { @($f.Codecs) } else { @() } } -When { param($W) $m = Get-Media $W 'input'; [bool](-not $m.HasVideo) }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'speed' -Extension {
        param($W) $m = Get-Media $W 'input'
        if ($m.HasVideo) { return (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext }
        return (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
    return $steps
}

function Build-SpeedJob {
    param($W)
    $info = Get-Media $W 'input'
    $speed = [double](Get-Answer $W 'speed' 1.5)
    if ($speed -le 0) { throw 'Speed must be greater than zero.' }
    $atempo = Get-AtempoChain $speed
    if ($info.HasVideo) {
        $vf = @('setpts=PTS/' + (Format-FFNumber $speed 6))
        if ((Get-Answer $W 'vmode' 'standard') -eq 'interpolate' -and $info.Video[0].Fps) { $vf += ('minterpolate=fps=' + (Format-FFNumber $info.Video[0].Fps 4)) }
        $audio = [string](Get-Answer $W 'audio' 'sync')
        $mode = if ($info.HasAudio -and $audio -eq 'sync') { 'auto' } else { 'none' }
        $af = @(); if ($mode -eq 'auto') { $af = @($atempo) }
        $rows = @(@('Input', $info.FileName), @('Speed', ("{0:0.0#}x" -f $speed)), @('Audio', $(if ($mode -eq 'auto') { 'Synchronized (tempo chain: ' + $atempo + ')' } elseif ($info.HasAudio) { 'Removed' } else { 'None' })))
        return New-VideoProcessJob -W $W -Title 'Changing playback speed' -VideoFilters $vf -AudioFilters $af -AudioMode $mode -SubMode remove -Speed $speed -Rows $rows -StageName 'Changing speed'
    }
    return New-AudioProcessJob -W $W -Title 'Changing playback speed' -AudioFilters @($atempo) -Speed $speed -Rows @(@('Input', $info.FileName), @('Speed', ("{0:0.0#}x" -f $speed)), @('Tempo chain', $atempo)) -StageName 'Changing speed'
}

function Start-SpeedWorkflow {
    Start-StandardWorkflow -Title 'Change Playback Speed' -Description 'Make video or audio slower or faster while controlling synchronization.' -Icon 'Speed' -StepsFactory { Get-SpeedSteps } -Build { param($W) Build-SpeedJob $W }
}

Export-ModuleMember -Function Get-SpeedSteps, Build-SpeedJob, Start-SpeedWorkflow
