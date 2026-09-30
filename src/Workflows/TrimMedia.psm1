# TrimMedia.psm1 - workflow 4: Trim / Cut Media.
Set-StrictMode -Version 2.0

function Get-TrimSteps {
    $isVideo = { param($W) $m = Get-Media $W 'input'; [bool]($m -and $m.HasVideo) }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media (video or audio)' -Require Media
    $steps += Get-TimeRangeSteps -Prefix 't' -InputId 'input' -Prompt 'What part do you want to keep?' -RequireRange
    $steps += @{ Id = 'mode'; Type = 'Choice'; Prompt = 'Cut mode'; Help = "Fast Cut is quicker but may cut near keyframes.`nAccurate Cut re-encodes and can cut at the requested point more precisely."
        Choices = { param($W) @( (New-Choice 'fast' 'Fast cut (stream copy)' 'No re-encoding; may start at the nearest keyframe.'), (New-Choice 'accurate' 'Accurate cut (re-encode)' 'Cuts exactly at the requested time; slower.') ) }
        Default = 'fast' }
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'Fast cut needs a format that can hold the original streams.'; When = $isVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $c = Get-ContainerIdFromPath (Get-Media $W 'input').Path; if ($c) { $c } else { 'mkv' } } }
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The audio file type of the result.'; When = { param($W) -not (& $isVideo $W) }.GetNewClosure()
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $e = [System.IO.Path]::GetExtension((Get-Media $W 'input').Path).ToLowerInvariant().TrimStart('.'); foreach ($f in Get-AvailableAudioFormats) { if ($f.Id -eq $e) { return $f.Id } }; 'flac' } }
    $accVideo = { param($W) (& $isVideo $W) -and ((Get-Answer $W 'mode') -eq 'accurate') }.GetNewClosure()
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript { param($W) [string](Get-Answer $W 'format' 'mp4') } -Level Simple -GateWhen $accVideo
    $fam = { param($W) if (& $isVideo $W) { $c = Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4')); if ($c) { return @($c.Audio) } } else { $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { return @($f.Codecs) } }; @() }.GetNewClosure()
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies $fam -When { param($W) (Get-Answer $W 'mode') -eq 'accurate' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'trimmed' -Extension ({ param($W) if (& $isVideo $W) { (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext } else { (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext } }.GetNewClosure())
    return $steps
}

function Build-TrimJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $range = Resolve-TimeRange $W 't' 'input'
    $fast = ((Get-Answer $W 'mode') -eq 'fast')
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path (Get-RangeInputOptions $range))
    $notes = @()
    if ($info.HasVideo) {
        $container = [string](Get-Answer $W 'format' 'mp4'); $c = Get-VideoContainer $container
        $muxer = $c.Muxer
        if ($fast) {
            $msg = Test-CopyAllowed $info $container -Video $true -Audio $true
            if ($msg) { throw ($msg + ' Use Accurate cut, or pick a format that supports the original streams.') }
            Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index))
            if ($info.HasAudio) { Add-FFOutOpt $cmd @('-map', '0:a') }
            Add-FFOutOpt $cmd @('-c', 'copy', '-avoid_negative_ts', 'make_zero')
            $notes += 'Fast cut copies streams without re-encoding, so the cut may start at the nearest keyframe.'
        } else {
            $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true
            $ae = Resolve-AudioEncode $W -Prefix 'a' -Container $container -HasAudio $info.HasAudio
            Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index))
            if ($info.HasAudio -and -not $ae.None) { Add-FFOutOpt $cmd @('-map', '0:a') }
            Add-FFOutOpt $cmd $ve.Tokens; Add-FFOutOpt $cmd $ae.Tokens
        }
    } else {
        $fmt = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); $muxer = $fmt.Muxer
        Add-FFOutOpt $cmd @('-vn', '-map', ('0:' + $info.Audio[0].Index))
        if ($fast) {
            $srcFam = Get-AudioFamily $info.Audio[0].Codec
            if ($fmt.Codecs -notcontains $srcFam) { throw "The original audio ($(Get-FriendlyCodecName $info.Audio[0].Codec)) cannot be stored in $($fmt.Label) without re-encoding. Use Accurate cut or another format." }
            Add-FFOutOpt $cmd @('-c:a', 'copy')
        } else {
            $ae = Resolve-AudioEncode $W -Prefix 'a' -Container '' -AllowedFamilies @($fmt.Codecs) -HasAudio $true
            Add-FFOutOpt $cmd $ae.Tokens
        }
    }
    Add-FFOutOpt $cmd @('-f', $muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Keep', ('{0} ({1} s)' -f (Format-Duration $range.Start), (Format-FFNumber $range.Duration 2))), @('Mode', $(if ($fast) { 'Fast cut (stream copy)' } else { 'Accurate cut (re-encode)' })), @('Output', $out.Path))
    return New-JobObject -Title 'Trimming media' -Summary $rows -Stages @(@{ Name = 'Cutting'; Arguments = (Get-FFTokens $cmd); DurationSec = $range.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -Notes $notes
}

function Start-TrimWorkflow {
    Start-StandardWorkflow -Title 'Trim / Cut Media' -Description 'Keep only a selected time range from a video or audio file.' -Icon 'Cut' -StepsFactory { Get-TrimSteps } -Build { param($W) Build-TrimJob $W }
}

Export-ModuleMember -Function Get-TrimSteps, Build-TrimJob, Start-TrimWorkflow
