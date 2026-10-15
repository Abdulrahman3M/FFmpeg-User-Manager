# ConvertVideo.psm1 - workflow 1: Convert Video Format.
Set-StrictMode -Version 2.0

function Get-ConvertVideoSteps {
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $hasAudio = { param($W) $m = Get-Media $W 'input'; [bool]($m -and $m.HasAudio) }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += Get-ContainerStep -Id 'format' -InputId 'input' -Prompt 'Output format'
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript $cont -OfferCopy -Level Full
    $steps += Get-ResolutionStep -Id 'resolution'
    $steps += Get-FrameRateStep -Id 'fps'
    $steps += Get-AudioEncodeSteps -Prefix 'a' -ContainerScript $cont -OfferCopy -OfferRemove -When $hasAudio -Full
    $steps += Get-SubtitleBehaviorStep -Id 'subs'
    $steps += Get-MetadataStep -Id 'metadata'
    $steps += Get-AdvancedGateStep
    $adv = { param($W) [bool](Get-Answer $W 'advanced' $false) }
    $steps += @{ Id = 'pixfmt'; Type = 'Choice'; Prompt = 'Pixel format'; Help = 'yuv420p is the most compatible. 10-bit formats need player support.'; When = $adv
        Choices = { param($W) @( (New-Choice '' 'Encoder default (Recommended)' 'Let the encoder choose the best pixel format for the codec.'), (New-Choice 'yuv420p' 'yuv420p (8-bit, most compatible)' 'Plays on nearly every device, TV and browser.'), (New-Choice 'yuv420p10le' 'yuv420p10le (10-bit)' 'Less banding in gradients and HDR; needs newer players.'), (New-Choice 'yuv444p' 'yuv444p (full chroma)' 'Full color detail (screen recordings, graphics); limited player support.') ) }; Default = '' }
    $steps += @{ Id = 'gop'; Type = 'Integer'; Prompt = 'Keyframe interval (frames)'; Help = 'Distance between keyframes. Leave empty for the encoder default.'; Example = '250'; Optional = $true; Min = 1; Max = 10000; Label = 'Keyframe interval'; When = $adv }
    $steps += @{ Id = 'faststart'; Type = 'YesNo'; Prompt = 'Optimize MP4/MOV for web streaming (faststart)?'; Help = 'Moves index data to the start so playback can begin before the download finishes.'; YesDesc = 'Recommended for videos you will upload or stream: playback starts immediately.'; NoDesc = 'Leave the file as FFmpeg writes it; fine for local playback.'; Default = $true
        When = { param($W) (Get-Answer $W 'advanced' $false) -and ((Get-Answer $W 'format') -in @('mp4', 'mov')) } }
    $steps += @{ Id = 'hwaccel'; Type = 'Choice'; Prompt = 'Hardware-accelerated decoding'; Help = 'Speeds up decoding on supported hardware. Automatic falls back to software if unavailable.'; When = $adv
        Choices = { param($W) @( (New-Choice 'off' 'Off' 'Decode in software. Works everywhere and is the safest choice.'), (New-Choice 'auto' 'Automatic' 'Use the graphics card for decoding when possible, otherwise fall back to software.') ) + @(Get-FFHwAccels | ForEach-Object { New-Choice $_ $_ "Decode with the '$_' method of your graphics hardware; falls back to software if it cannot." }) }; Default = 'off' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'converted' -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext }
    return $steps
}

function Build-ConvertVideoJob {
    param($W)
    $info = Get-Media $W 'input'
    $container = [string](Get-Answer $W 'format' 'mp4')
    $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $vcodec = [string](Get-Answer $W 'vcodec' 'auto')
    $res = [string](Get-Answer $W 'resolution' 'keep')
    $fps = [double](Get-Answer $W 'fps' 0)
    $notes = @()
    $vf = @()
    $rf = Get-ResolutionFilter $res
    if ($rf) { $vf += $rf }
    if ($fps -gt 0) { $vf += ('fps=' + (Format-FFNumber $fps 4)) }
    if ($vcodec -eq 'copy') {
        if ($vf.Count -gt 0) { throw 'Changing resolution or frame rate requires re-encoding. Choose a video codec other than "Copy original codec", or set resolution and frame rate to Keep original.' }
        $msg = Test-CopyAllowed $info $container -Video $true -Audio $false
        if ($msg) { throw $msg }
    }
    $adv = [bool](Get-Answer $W 'advanced' $false)
    $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart ([bool](Get-Answer $W 'faststart' $false)) -PixFmt ([string](Get-Answer $W 'pixfmt' '')) -Gop (Get-Answer $W 'gop')
    $ae = Resolve-AudioEncode $W -Prefix 'a' -Container $container -HasAudio $info.HasAudio
    if ($ae.Copy) { $msg = Test-CopyAllowed $info $container -Video $false -Audio $true; if ($msg) { throw $msg } }

    $cmd = New-FFCommand
    $hw = [string](Get-Answer $W 'hwaccel' 'off')
    $inOpts = @(); if ($adv -and $hw -ne 'off') { $inOpts = @('-hwaccel', $hw) }
    [void](Add-FFInput $cmd $info.Path $inOpts)
    $vi = $info.Video[0].Index
    Add-FFOutOpt $cmd @('-map', "0:$vi")
    if ($info.HasAudio -and -not $ae.None) { Add-FFOutOpt $cmd @('-map', '0:a') }
    $sm = Get-SubtitleMapping $info $container ([string](Get-Answer $W 'subs' 'remove'))
    if ($sm.Tokens.Count -gt 0) { Add-FFOutOpt $cmd $sm.Tokens }
    if ($sm.Dropped -gt 0) { $notes += "$($sm.Dropped) subtitle stream(s) cannot be stored in this format and will be left out." }
    Add-FFOutOpt $cmd $ve.Tokens
    if ($vf.Count -gt 0) { Add-FFOutOpt $cmd @('-vf', (Join-FFFilters $vf)) }
    Add-FFOutOpt $cmd $ae.Tokens
    Add-FFOutOpt $cmd (Get-MetadataTokens ([string](Get-Answer $W 'metadata' 'keep')))
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $tokens = Get-FFTokens $cmd

    $vtext = if ($ve.Copy) { 'Copy original' } else { $ve.Encoder }
    $atext = if ($ae.None) { 'Removed' } elseif ($ae.Copy) { 'Copy original' } else { $ae.Encoder }
    $rows = @(
        @('Input', $info.FileName), @('Format', $c.Label), @('Video codec', $vtext),
        @('Resolution', $(if ($res -eq 'keep') { 'Keep original' } else { $res })),
        @('Frame rate', $(if ($fps -gt 0) { "$fps FPS" } else { 'Keep original' })),
        @('Audio', $atext), @('Output', $out.Path)
    )
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title 'Converting video' -Summary $rows -Stages @(@{ Name = 'Encoding video'; Arguments = $tokens; DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $true -Notes $notes
}

function Start-ConvertVideoWorkflow {
    Start-StandardWorkflow -Title 'Convert Video Format' -Description 'Convert a video to another container or video format.' -Icon 'Video' -StepsFactory { Get-ConvertVideoSteps } -Build { param($W) Build-ConvertVideoJob $W }
}

Export-ModuleMember -Function Get-ConvertVideoSteps, Build-ConvertVideoJob, Start-ConvertVideoWorkflow
