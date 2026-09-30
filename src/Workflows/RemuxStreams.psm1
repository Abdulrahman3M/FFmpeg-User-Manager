# RemuxStreams.psm1 - Remux & Streams: change a container without re-encoding, keep selected streams, set track language/default.
Set-StrictMode -Version 2.0

function Get-CopyMapTokens {
    # Maps every stream type that normal containers can carry. Matroska also carries attachments and data streams.
    param([string]$Extension)
    $e = $Extension.ToLowerInvariant().TrimStart('.')
    if ($e -in @('mkv', 'mka', 'webm')) { return @('-map', '0') }
    return @('-map', '0:v?', '-map', '0:a?', '-map', '0:s?')
}

function Get-StreamChoiceLabel {
    param($Kind, $S)
    switch ($Kind) {
        'video' { $t = ('Video #{0}  {1}' -f $S.Index, (Get-FriendlyCodecName $S.Codec)); if ($S.Width) { $t += ('  {0}x{1}' -f $S.Width, $S.Height) } }
        'audio' { $t = ('Audio #{0}  {1}  {2}' -f $S.Index, (Get-FriendlyCodecName $S.Codec), (Get-ChannelText $S.Channels)) }
        default { $t = ('Subtitle #{0}  {1}' -f $S.Index, (Get-FriendlyCodecName $S.Codec)) }
    }
    if ($S.Language) { $t += ('  [' + $S.Language + ']') }
    if ($S.Title) { $t += ('  "' + $S.Title + '"') }
    return $t
}

# ---- 1. Remux ----------------------------------------------------------------------------------

function Get-RemuxSteps {
    $isVideo = { param($W) $m = Get-Media $W 'input'; [bool]($m -and $m.HasVideo) }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'The file whose container (wrapper) you want to change. Audio and video are copied, not re-encoded.'
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'New container'; Help = 'Only the wrapper changes; picture and sound stay bit-for-bit identical. Not every codec fits every container.'; When = $isVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $c = Get-ContainerIdFromPath (Get-Media $W 'input').Path; if ($c -eq 'mkv') { 'mp4' } else { 'mkv' } } }
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'New audio file type'; Help = 'Audio stays untouched; only the file type changes.'; When = { param($W) -not (& $isVideo $W) }.GetNewClosure()
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mka' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'remux' -Extension {
        param($W) $m = Get-Media $W 'input'
        if ($m.HasVideo) { return (Get-VideoContainer ([string](Get-Answer $W 'format' 'mkv'))).Ext }
        return (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mka'))).Ext }
    return $steps
}

function Build-RemuxJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    $notes = @()
    if ($info.HasVideo) {
        $container = [string](Get-Answer $W 'format' 'mkv')
        $c = Get-VideoContainer $container
        $msg = Test-CopyAllowed $info $container -Video $true -Audio $true
        if ($msg) { throw ($msg + ' Use Convert Video Format to re-encode instead.') }
        Add-FFOutOpt $cmd @('-map', '0:v', '-map', '0:a?')
        $sm = Get-SubtitleMapping $info $container 'copy'
        if ($sm.Tokens.Count -gt 0) { Add-FFOutOpt $cmd $sm.Tokens }
        if ($sm.Dropped -gt 0) { $notes += "$($sm.Dropped) subtitle stream(s) cannot be stored in $($c.Label) and will be left out." }
        Add-FFOutOpt $cmd @('-c:v', 'copy', '-c:a', 'copy')
        if ($container -in @('mp4', 'mov')) { Add-FFOutOpt $cmd @('-movflags', '+faststart') }
        Add-FFOutOpt $cmd @('-map_metadata', '0', '-f', $c.Muxer)
        $label = $c.Label
    } else {
        $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mka'))
        $fam = Get-AudioFamily $info.Audio[0].Codec
        if (@($f.Codecs) -notcontains $fam -and $f.Id -ne 'mka') { throw ("The audio codec ({0}) cannot be stored in {1} without re-encoding. Use Convert Audio Format instead." -f (Get-FriendlyCodecName $info.Audio[0].Codec), $f.Label) }
        Add-FFOutOpt $cmd @('-map', '0:a:0', '-vn', '-c:a', 'copy', '-map_metadata', '0', '-f', $f.Muxer)
        $label = $f.Label
    }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('New container', $label), @('Re-encoding', 'None (streams are copied)'), @('Output', $out.Path))
    return New-JobObject -Title 'Remuxing' -Summary $rows -Stages @(@{ Name = 'Copying streams'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

# ---- 2. Keep selected streams -------------------------------------------------------------------

function Get-SelectStreamsSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'A file with several audio, subtitle or video tracks. You will choose which ones to keep.' -Extra { param($info, $W) if ($info.StreamCount -lt 2) { return 'This file has only one stream, so there is nothing to select.' }; $null }
    $steps += @{ Id = 'keep'; Type = 'MultiChoice'; Prompt = 'Which streams do you want to keep?'; Min = 1
        Help = 'Type a number to tick or untick a stream, then choose Continue. Unticked streams are dropped. Nothing is re-encoded.'
        Choices = { param($W)
            $m = Get-Media $W 'input'
            $l = @()
            foreach ($s in $m.Video) { $l += , (New-Choice $s.Index (Get-StreamChoiceLabel 'video' $s) 'Picture track.') }
            foreach ($s in $m.Audio) { $l += , (New-Choice $s.Index (Get-StreamChoiceLabel 'audio' $s) 'Sound track (for example a language version).') }
            foreach ($s in $m.Subtitles) { $l += , (New-Choice $s.Index (Get-StreamChoiceLabel 'sub' $s) 'Subtitle track.') }
            return $l }
        Default = { param($W) $m = Get-Media $W 'input'; @(@($m.Video) + @($m.Audio) + @($m.Subtitles) | ForEach-Object { $_.Index }) } }
    $steps += Get-ContainerStep -Id 'format' -InputId 'input' -Prompt 'Output container'
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'streams' -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mkv'))).Ext }
    return $steps
}

function Build-SelectStreamsJob {
    param($W)
    $info = Get-Media $W 'input'
    $keep = @(Get-Answer $W 'keep' @() | ForEach-Object { [int]$_ })
    if ($keep.Count -eq 0) { throw 'Select at least one stream to keep.' }
    $container = [string](Get-Answer $W 'format' 'mkv')
    $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    $notes = @()
    foreach ($i in $keep) {
        $v = @($info.Video | Where-Object { $_.Index -eq $i }); $a = @($info.Audio | Where-Object { $_.Index -eq $i }); $s = @($info.Subtitles | Where-Object { $_.Index -eq $i })
        if ($v.Count -gt 0 -and $c.Video -notcontains (Get-VideoFamily $v[0].Codec)) { throw ("Video stream #{0} ({1}) cannot be stored in {2} without re-encoding." -f $i, (Get-FriendlyCodecName $v[0].Codec), $c.Label) }
        if ($a.Count -gt 0 -and $c.Audio -notcontains (Get-AudioFamily $a[0].Codec)) { throw ("Audio stream #{0} ({1}) cannot be stored in {2} without re-encoding." -f $i, (Get-FriendlyCodecName $a[0].Codec), $c.Label) }
        if ($s.Count -gt 0 -and $c.Sub -eq 'none') { $notes += "Subtitle stream #$i cannot be stored in $($c.Label) and was left out."; continue }
        if ($s.Count -gt 0 -and $c.Sub -ne 'copy' -and -not $s[0].IsText) { $notes += "Subtitle stream #$i is a picture-based subtitle that $($c.Label) cannot hold; it was left out."; continue }
        Add-FFOutOpt $cmd @('-map', "0:$i")
    }
    Add-FFOutOpt $cmd @('-c', 'copy')
    $hasSub = @($keep | Where-Object { $i = $_; @($info.Subtitles | Where-Object { $_.Index -eq $i }).Count -gt 0 })
    if ($hasSub.Count -gt 0 -and $c.Sub -notin @('none', 'copy')) { Add-FFOutOpt $cmd @('-c:s', $c.Sub) }
    Add-FFOutOpt $cmd @('-map_metadata', '0', '-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Keeping', ((@($keep) | ForEach-Object { '#' + $_ }) -join ', ')), @('Container', $c.Label), @('Output', $out.Path))
    return New-JobObject -Title 'Keeping selected streams' -Summary $rows -Stages @(@{ Name = 'Copying selected streams'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

# ---- 3. Track language / default flag -----------------------------------------------------------

function Get-TrackTagSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'A file with at least one audio or subtitle track whose label you want to fix.' -Extra { param($info, $W) if (($info.Audio.Count + $info.Subtitles.Count) -lt 1) { return 'This file has no audio or subtitle tracks.' }; $null }
    $steps += @{ Id = 'track'; Type = 'Choice'; Prompt = 'Which track do you want to label?'; Help = 'Players show the language and pick the default track from these labels.'
        Choices = { param($W) $m = Get-Media $W 'input'; $l = @(); foreach ($s in $m.Audio) { $l += , (New-Choice $s.Index (Get-StreamChoiceLabel 'audio' $s) 'Audio track.') }; foreach ($s in $m.Subtitles) { $l += , (New-Choice $s.Index (Get-StreamChoiceLabel 'sub' $s) 'Subtitle track.') }; $l }
        Default = { param($W) $m = Get-Media $W 'input'; @(@($m.Audio) + @($m.Subtitles))[0].Index } }
    $steps += @{ Id = 'lang'; Type = 'Text'; Prompt = 'Language code (3 letters)'; Label = 'Language code'; Optional = $true; Example = 'eng, ara, fra, deu, spa, jpn'
        Help = 'ISO 639-2 three-letter code shown by players. Leave empty to keep the current language.'
        Validate = { param($v, $W) if ($v -and $v -notmatch '^[a-zA-Z]{3}$') { return 'Use exactly three letters, for example eng.' }; $null } }
    $steps += @{ Id = 'default'; Type = 'YesNo'; Prompt = 'Make this the default track of its kind?'; Help = 'The default audio or subtitle track is the one a player selects automatically. Other tracks of the same kind lose the flag.'
        YesLabel = 'Yes, make it the default'; NoLabel = 'No, leave the default flags as they are'; YesDesc = 'The player will pick this track first.'; NoDesc = 'Only the language label changes.'; Default = $false }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'tagged' -Extension { param($W) $m = Get-Media $W 'input'; $e = [System.IO.Path]::GetExtension($m.Path); if ($e) { $e } else { '.mkv' } }
    return $steps
}

function Build-TrackTagJob {
    param($W)
    $info = Get-Media $W 'input'
    $idx = [int](Get-Answer $W 'track')
    $lang = ([string](Get-Answer $W 'lang' '')).ToLowerInvariant()
    $makeDefault = [bool](Get-Answer $W 'default' $false)
    if (-not $lang -and -not $makeDefault) { throw 'Nothing to change: enter a language code or choose to make the track the default.' }
    $out = Get-OutputFile $W
    $ext = [System.IO.Path]::GetExtension($info.Path)
    $kind = 'a'; $list = @($info.Audio)
    if (@($info.Audio | Where-Object { $_.Index -eq $idx }).Count -eq 0) { $kind = 's'; $list = @($info.Subtitles) }
    $pos = 0; for ($k = 0; $k -lt $list.Count; $k++) { if ($list[$k].Index -eq $idx) { $pos = $k } }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd (Get-CopyMapTokens $ext)
    Add-FFOutOpt $cmd @('-c', 'copy', '-map_metadata', '0')
    if ($lang) { Add-FFOutOpt $cmd @("-metadata:s:${kind}:$pos", "language=$lang") }
    if ($makeDefault) {
        for ($k = 0; $k -lt $list.Count; $k++) { Add-FFOutOpt $cmd @("-disposition:${kind}:$k", $(if ($k -eq $pos) { 'default' } else { '0' })) }
    }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Track', ('#' + $idx)), @('Language', $(if ($lang) { $lang } else { 'unchanged' })), @('Default track', $(if ($makeDefault) { 'Yes' } else { 'unchanged' })), @('Output', $out.Path))
    return New-JobObject -Title 'Labeling track' -Summary $rows -Stages @(@{ Name = 'Writing labels'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

function Start-RemuxStreamsWorkflow {
    $items = @(
        @{ Label = 'Remux (Change Container, No Re-encoding)'; Icon = 'Merge'; Desc = 'Put the same picture and sound into another file type (MKV to MP4). Fast, lossless.'; Value = { Start-StandardWorkflow -Title 'Remux' -Description 'Change the container without re-encoding.' -Icon 'Merge' -StepsFactory { Get-RemuxSteps } -Build { param($W) Build-RemuxJob $W } } },
        @{ Label = 'Keep Selected Streams'; Icon = 'Map'; Desc = 'Drop unwanted audio languages, subtitles or extra video tracks without re-encoding.'; Value = { Start-StandardWorkflow -Title 'Keep Selected Streams' -Description 'Choose which tracks stay in the file.' -Icon 'Map' -StepsFactory { Get-SelectStreamsSteps } -Build { param($W) Build-SelectStreamsJob $W } } },
        @{ Label = 'Set Track Language / Default Track'; Icon = 'Tag'; Desc = 'Fix the language of an audio or subtitle track, or choose which track plays first.'; Value = { Start-StandardWorkflow -Title 'Track Language / Default' -Description 'Label a track and choose the default.' -Icon 'Tag' -StepsFactory { Get-TrackTagSteps } -Build { param($W) Build-TrackTagJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Remux') + '  Remux & Streams') -Subtitle 'Change containers and choose tracks without re-encoding (fast, lossless).' -Items $items
}

Export-ModuleMember -Function Get-CopyMapTokens, Get-RemuxSteps, Build-RemuxJob, Get-SelectStreamsSteps, Build-SelectStreamsJob, Get-TrackTagSteps, Build-TrackTagJob, Start-RemuxStreamsWorkflow
