# SubtitleTools.psm1 - workflow 11: Subtitle Tools submenu.
Set-StrictMode -Version 2.0

function Get-SubtitleStreamLabel {
    param($S, [int]$Ordinal)
    $t = "Subtitle $($Ordinal + 1): " + (Get-FriendlyCodecName $S.Codec)
    if ($S.Language) { $t += "  [$($S.Language)]" }
    if ($S.Title) { $t += "  $($S.Title)" }
    if (-not $S.IsText) { $t += '  (bitmap)' }
    return $t
}

function Get-SubtitleVideoInputStep {
    param([string]$Prompt = 'Input video')
    return (Get-InputFileStep -Id 'input' -Prompt $Prompt -Require Video -Extra { param($info, $W) $null })
}

function Get-SubtitleStreamInputStep {
    return (Get-InputFileStep -Id 'input' -Prompt 'Input file with subtitles' -Require Media -Extra { param($info, $W) if (-not $info.HasSubtitles) { return 'This file contains no subtitle streams.' }; $null })
}

# ---- 1. Extract -------------------------------------------------------------------------------

$script:SubExtractFormats = @(
    @{ Id = 'srt'; Label = 'SubRip (.srt)'; Ext = '.srt'; Muxer = 'srt'; Codec = 'subrip'; Text = $true },
    @{ Id = 'ass'; Label = 'Advanced SubStation (.ass)'; Ext = '.ass'; Muxer = 'ass'; Codec = 'ass'; Text = $true },
    @{ Id = 'vtt'; Label = 'WebVTT (.vtt)'; Ext = '.vtt'; Muxer = 'webvtt'; Codec = 'webvtt'; Text = $true },
    @{ Id = 'mks'; Label = 'Matroska subtitles (.mks, keeps bitmap subtitles)'; Ext = '.mks'; Muxer = 'matroska'; Codec = 'copy'; Text = $false }
)

function Get-SelectedSubtitle {
    param($W)
    $m = Get-Media $W 'input'
    $idx = Get-Answer $W 'stream'
    if ($null -eq $idx) { return $m.Subtitles[0] }
    foreach ($s in $m.Subtitles) { if ($s.Index -eq $idx) { return $s } }
    return $m.Subtitles[0]
}

function Get-ExtractSubtitleSteps {
    $steps = @(); $steps += Get-SubtitleStreamInputStep
    $steps += @{ Id = 'stream'; Type = 'Choice'; Prompt = 'Subtitle stream'; Help = 'Choose the subtitle track to extract.'
        When = { param($W) (Get-Media $W 'input').Subtitles.Count -gt 1 }
        Choices = { param($W) $m = Get-Media $W 'input'; $l = @(); for ($i = 0; $i -lt $m.Subtitles.Count; $i++) { $l += , (New-Choice $m.Subtitles[$i].Index (Get-SubtitleStreamLabel $m.Subtitles[$i] $i)) }; $l }
        Default = { param($W) (Get-Media $W 'input').Subtitles[0].Index } }
    $steps += @{ Id = 'sfmt'; Type = 'Choice'; Prompt = 'Subtitle format'; Help = 'Text subtitles can be converted; bitmap subtitles can only be saved as Matroska subtitles.'
        Choices = { param($W) $s = Get-SelectedSubtitle $W; @($script:SubExtractFormats | ForEach-Object { $ok = ($_.Text -eq $s.IsText -or ($_.Id -eq 'mks')) -and (Test-FFMuxer $_.Muxer); New-Choice $_.Id $_.Label '' $ok $(if (-not $s.IsText) { 'This bitmap subtitle cannot be converted to a text format.' } else { 'Not supported by this FFmpeg build.' }) }) }
        Default = { param($W) if ((Get-SelectedSubtitle $W).IsText) { 'srt' } else { 'mks' } } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'subtitle' -Extension { param($W) ($script:SubExtractFormats | Where-Object { $_.Id -eq (Get-Answer $W 'sfmt' 'srt') } | Select-Object -First 1).Ext }
    return $steps
}

function Build-ExtractSubtitleJob {
    param($W)
    $info = Get-Media $W 'input'
    $s = Get-SelectedSubtitle $W
    $f = $script:SubExtractFormats | Where-Object { $_.Id -eq (Get-Answer $W 'sfmt' 'srt') } | Select-Object -First 1
    if ($f.Text -and -not $s.IsText) { throw 'Bitmap subtitles cannot be converted to a text format. Choose the Matroska option.' }
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd @('-map', "0:$($s.Index)", '-c:s', $f.Codec, '-f', $f.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title 'Extracting subtitle' -Summary @(@('Input', $info.FileName), @('Stream', (Get-SubtitleStreamLabel $s 0)), @('Format', $f.Label), @('Output', $out.Path)) -Stages @(@{ Name = 'Extracting subtitle'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

# ---- 2. Add / mux -------------------------------------------------------------------------------

function Get-MuxSubtitleSteps {
    $steps = @(); $steps += Get-SubtitleVideoInputStep
    $steps += Get-InputFileStep -Id 'subfile' -Prompt 'Subtitle file' -Require Any -NoPanel -Example 'C:\Videos\movie.srt' -Help 'A subtitle file such as .srt, .ass or .vtt.' -Extra { param($info, $W) if (-not $info.HasSubtitles) { return 'This file does not contain a readable subtitle stream.' }; $null }
    $steps += @{ Id = 'lang'; Type = 'Choice'; Prompt = 'Subtitle language'; Help = 'Stored as track metadata so players can show the right name.'
        Choices = { param($W) @( (New-Choice 'eng' 'English'), (New-Choice 'ara' 'Arabic'), (New-Choice 'fra' 'French'), (New-Choice 'deu' 'German'), (New-Choice 'spa' 'Spanish'), (New-Choice 'ita' 'Italian'), (New-Choice 'por' 'Portuguese'), (New-Choice 'rus' 'Russian'), (New-Choice 'jpn' 'Japanese'), (New-Choice 'kor' 'Korean'), (New-Choice 'zho' 'Chinese'), (New-Choice 'und' 'Undetermined') ) }
        AllowCustom = @{ Label = 'Other language code...'; Type = 'Text'; Prompt = 'Three-letter language code'; Help = 'ISO 639-2 code such as nld or tur.'; Example = 'nld'; Desc = 'For example nld.' }
        Validate = { param($v, $W) if ($v -notmatch '^[a-z]{3}$') { return 'Use a three-letter lowercase language code such as eng.' }; $null }
        Default = 'eng' }
    $steps += @{ Id = 'title'; Type = 'Text'; Prompt = 'Track title'; Help = 'Optional name shown in the player subtitle menu.'; Example = 'English (SDH)'; Optional = $true }
    $steps += @{ Id = 'default'; Type = 'YesNo'; Prompt = 'Show this subtitle by default?'; Help = 'Players usually turn on the default subtitle automatically.'; Default = $false }
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'MP4/MOV store subtitles as text (mov_text); MKV keeps them as they are.'
        Choices = { param($W) @(Get-AvailableVideoContainers | Where-Object { $_.Sub -ne 'none' } | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $c = Get-ContainerIdFromPath (Get-Media $W 'input').Path; if ($c -in @('mp4', 'mkv', 'mov', 'webm')) { $c } else { 'mkv' } } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'subbed' -ProtectIds @('input', 'subfile') -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mkv'))).Ext }
    return $steps
}

function Build-MuxSubtitleJob {
    param($W)
    $v = Get-Media $W 'input'; $sub = Get-Media $W 'subfile'
    $container = [string](Get-Answer $W 'format' 'mkv'); $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $msg = Test-CopyAllowed $v $container -Video $true -Audio $true
    if ($msg) { throw ($msg + ' Choose MKV to keep the original streams without re-encoding.') }
    $ns = $sub.Subtitles[0]
    if (-not $ns.IsText -and $c.Sub -ne 'copy') { throw 'A bitmap subtitle can only be added to MKV.' }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $v.Path)
    [void](Add-FFInput $cmd $sub.Path)
    Add-FFOutOpt $cmd @('-map', ('0:' + $v.Video[0].Index))
    if ($v.HasAudio) { Add-FFOutOpt $cmd @('-map', '0:a') }
    $sm = Get-SubtitleMapping $v $container 'copy'
    foreach ($i in $sm.Maps) { Add-FFOutOpt $cmd @('-map', "0:$i") }
    $n = $sm.Maps.Count
    Add-FFOutOpt $cmd @('-map', ('1:' + $ns.Index), '-c', 'copy')
    $subCodec = $c.Sub; if ($subCodec -eq 'copy') { $subCodec = 'copy' }
    Add-FFOutOpt $cmd @('-c:s', $subCodec)
    Add-FFOutOpt $cmd @("-metadata:s:s:$n", ('language=' + [string](Get-Answer $W 'lang' 'eng')))
    $title = [string](Get-Answer $W 'title' '')
    if ($title) { Add-FFOutOpt $cmd @("-metadata:s:s:$n", ('title=' + $title)) }
    if ((Get-Answer $W 'default' $false)) { Add-FFOutOpt $cmd @("-disposition:s:$n", 'default') }
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @('Video and audio are copied without re-encoding.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title 'Adding subtitle' -Summary @(@('Video', $v.FileName), @('Subtitle', $sub.FileName), @('Language', [string](Get-Answer $W 'lang' 'eng')), @('Output', $out.Path)) -Stages @(@{ Name = 'Adding subtitle'; Arguments = (Get-FFTokens $cmd); DurationSec = $v.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $v.Size -Notes $notes
}

# ---- 3. Burn ---------------------------------------------------------------------------------------

function Get-BurnSubtitleSteps {
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $steps = @(); $steps += Get-SubtitleVideoInputStep
    $steps += @{ Id = 'source'; Type = 'Choice'; Prompt = 'Subtitle source'; Help = 'Burning permanently draws the subtitles into the picture and requires re-encoding the video.'
        Choices = { param($W) $m = Get-Media $W 'input'; $hasText = [bool]($m.Subtitles | Where-Object { $_.IsText }); @( (New-Choice 'file' 'Subtitle file'), (New-Choice 'stream' 'Subtitle stream inside the video' '' $hasText 'The video has no text subtitle stream.') ) }
        Default = 'file' }
    $steps += Get-InputFileStep -Id 'subfile' -Prompt 'Subtitle file' -Require Any -NoPanel -Example 'C:\Videos\movie.srt' -Help 'A text subtitle file (.srt, .ass, .vtt).' -Extra { param($info, $W) if (-not $info.HasSubtitles -or -not $info.Subtitles[0].IsText) { return 'This file does not contain a readable text subtitle.' }; $null }
    $steps[-1].When = { param($W) (Get-Answer $W 'source') -eq 'file' }
    $steps += @{ Id = 'stream'; Type = 'Choice'; Prompt = 'Which subtitle stream?'; Help = 'Only text subtitle streams can be burned.'; When = { param($W) (Get-Answer $W 'source') -eq 'stream' }
        Choices = { param($W) $m = Get-Media $W 'input'; $l = @(); $ord = 0; foreach ($s in $m.Subtitles) { if ($s.IsText) { $l += , (New-Choice $ord (Get-SubtitleStreamLabel $s $ord)) }; $ord++ }; $l }
        Default = 0 }
    $steps += @{ Id = 'size'; Type = 'Choice'; Prompt = 'Subtitle text size'; Help = 'Applies to SRT/WebVTT subtitles. ASS files keep their own style.'
        Choices = { param($W) @( (New-Choice 0 'Default'), (New-Choice 18 'Small (18)'), (New-Choice 24 'Medium (24)'), (New-Choice 32 'Large (32)'), (New-Choice 44 'Extra large (44)') ) }; Default = 0 }
    $steps += @{ Id = 'pos'; Type = 'Choice'; Prompt = 'Subtitle position'; Help = 'Where the text appears on the screen.'
        Choices = { param($W) @( (New-Choice 2 'Bottom (default)'), (New-Choice 8 'Top'), (New-Choice 5 'Middle') ) }; Default = 2 }
    $steps += Get-ContainerStep -Id 'format' -InputId 'input'
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript $cont -Level Simple
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'subtitled' -ProtectIds @('input') -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext }
    return $steps
}

function Build-BurnSubtitleJob {
    param($W)
    if (-not (Test-FFFilter 'subtitles')) { throw 'Your FFmpeg build does not include the subtitles filter (libass), so subtitles cannot be burned in.' }
    $v = Get-Media $W 'input'
    $style = @()
    if ([int](Get-Answer $W 'size' 0) -gt 0) { $style += ('FontSize=' + [int](Get-Answer $W 'size')) }
    if ([int](Get-Answer $W 'pos' 2) -ne 2) { $style += ('Alignment=' + [int](Get-Answer $W 'pos')) }
    if ((Get-Answer $W 'source') -eq 'file') { $sub = Get-Media $W 'subfile'; $f = 'subtitles=filename=' + (ConvertTo-FFFilterPath $sub.Path); $srcTxt = $sub.FileName }
    else { $f = 'subtitles=filename=' + (ConvertTo-FFFilterPath $v.Path) + ':si=' + [int](Get-Answer $W 'stream' 0); $srcTxt = 'Embedded subtitle stream' }
    if ($style.Count -gt 0) { $f += ':force_style=' + (ConvertTo-FFFilterValue ($style -join ',')) }
    $rows = @(@('Video', $v.FileName), @('Subtitles', $srcTxt), @('Burn-in', 'Permanent (re-encodes the video)'))
    return New-VideoProcessJob -W $W -Title 'Burning subtitles' -VideoFilters @($f) -Rows $rows -AudioMode copy -SubMode remove -StageName 'Burning subtitles'
}

# ---- 4. Remove / 5. Keep selected ---------------------------------------------------------------------

function Get-RemoveSubtitleSteps {
    $steps = @(); $steps += Get-SubtitleStreamInputStep
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'nosubs' -Extension { param($W) [System.IO.Path]::GetExtension((Get-Media $W 'input').Path) }
    return $steps
}

function Build-RemoveSubtitleJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd @('-map', '0', '-map', '-0:s', '-c', 'copy')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @('Video and audio are copied without re-encoding.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title 'Removing subtitles' -Summary @(@('Input', $info.FileName), @('Removing', "$($info.Subtitles.Count) subtitle stream(s)"), @('Output', $out.Path)) -Stages @(@{ Name = 'Removing subtitles'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -Notes $notes
}

function Get-KeepSubtitleSteps {
    $steps = @(); $steps += Get-SubtitleStreamInputStep
    $steps += @{ Id = 'keep'; Type = 'MultiChoice'; Prompt = 'Subtitle streams to keep'; Help = 'All other subtitle streams are removed. Video and audio are untouched.'; Min = 1
        Choices = { param($W) $m = Get-Media $W 'input'; $l = @(); for ($i = 0; $i -lt $m.Subtitles.Count; $i++) { $l += , (New-Choice $m.Subtitles[$i].Index (Get-SubtitleStreamLabel $m.Subtitles[$i] $i)) }; $l }
        Default = { param($W) @((Get-Media $W 'input').Subtitles[0].Index) } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'subset' -Extension { param($W) [System.IO.Path]::GetExtension((Get-Media $W 'input').Path) }
    return $steps
}

function Build-KeepSubtitleJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $keep = @(Get-Answer $W 'keep')
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd @('-map', '0', '-map', '-0:s')
    foreach ($i in $keep) { Add-FFOutOpt $cmd @('-map', "0:$i") }
    Add-FFOutOpt $cmd @('-c', 'copy')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @('Video and audio are copied without re-encoding.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title 'Selecting subtitles' -Summary @(@('Input', $info.FileName), @('Keeping', "$($keep.Count) of $($info.Subtitles.Count) subtitle stream(s)"), @('Output', $out.Path)) -Stages @(@{ Name = 'Copying streams'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -Notes $notes
}

function Start-SubtitleToolsWorkflow {
    $items = @(
        @{ Label = 'Extract Subtitle'; Desc = 'Save a subtitle stream as an .srt, .ass or .vtt file.'; Key = '1'; Value = { Start-StandardWorkflow -Title 'Extract Subtitle' -Description 'Save a subtitle track as a separate file.' -Icon 'Subtitle' -StepsFactory { Get-ExtractSubtitleSteps } -Build { param($W) Build-ExtractSubtitleJob $W } } },
        @{ Label = 'Add / Mux Subtitle'; Desc = 'Add a subtitle file to a video without re-encoding.'; Key = '2'; Value = { Start-StandardWorkflow -Title 'Add / Mux Subtitle' -Description 'Attach a subtitle file to a video.' -Icon 'Subtitle' -StepsFactory { Get-MuxSubtitleSteps } -Build { param($W) Build-MuxSubtitleJob $W } } },
        @{ Label = 'Burn Subtitle into Video'; Desc = 'Draw subtitles permanently into the picture (re-encodes video).'; Key = '3'; Enabled = (Test-FFFilter 'subtitles'); Reason = 'Requires the subtitles filter (libass), which this FFmpeg build lacks.'; Value = { Start-StandardWorkflow -Title 'Burn Subtitle into Video' -Description 'Permanently render subtitles into the video.' -Icon 'Subtitle' -StepsFactory { Get-BurnSubtitleSteps } -Build { param($W) Build-BurnSubtitleJob $W } } },
        @{ Label = 'Remove Subtitle Streams'; Desc = 'Delete all subtitle tracks without re-encoding.'; Key = '4'; Value = { Start-StandardWorkflow -Title 'Remove Subtitle Streams' -Description 'Remove all subtitle tracks.' -Icon 'Subtitle' -StepsFactory { Get-RemoveSubtitleSteps } -Build { param($W) Build-RemoveSubtitleJob $W } } },
        @{ Label = 'Copy Selected Subtitle Streams'; Desc = 'Keep only the subtitle tracks you choose.'; Key = '5'; Value = { Start-StandardWorkflow -Title 'Copy Selected Subtitle Streams' -Description 'Keep only chosen subtitle tracks.' -Icon 'Subtitle' -StepsFactory { Get-KeepSubtitleSteps } -Build { param($W) Build-KeepSubtitleJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Subtitle') + '  Subtitle Tools') -Subtitle 'Extract, add, remove, copy or burn subtitle streams.' -Items $items
}

Export-ModuleMember -Function Get-ExtractSubtitleSteps, Build-ExtractSubtitleJob, Get-MuxSubtitleSteps, Build-MuxSubtitleJob, Get-BurnSubtitleSteps, Build-BurnSubtitleJob, Get-RemoveSubtitleSteps, Build-RemoveSubtitleJob, Get-KeepSubtitleSteps, Build-KeepSubtitleJob, Start-SubtitleToolsWorkflow
