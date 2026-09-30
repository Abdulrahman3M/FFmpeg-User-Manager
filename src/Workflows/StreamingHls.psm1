# StreamingHls.psm1 - workflow 17: Streaming / HLS (generic; no platform-specific logic).
Set-StrictMode -Version 2.0

$script:NetworkSchemes = @('http', 'https', 'rtmp', 'rtmps', 'rtmpt', 'rtsp', 'rtp', 'srtp', 'udp', 'tcp', 'tls', 'srt', 'mmsh', 'mmst')

function Test-NetworkUrl {
    # Returns $null when acceptable. Only network schemes that the installed FFmpeg reports as input protocols.
    param([string]$Url)
    $u = $Url.Trim()
    if ($u -notmatch '^([a-zA-Z][a-zA-Z0-9+.-]*)://\S+$') { return 'Enter a full address such as https://example.com/stream.m3u8' }
    $scheme = $Matches[1].ToLowerInvariant()
    if ($script:NetworkSchemes -notcontains $scheme) { return "'$scheme' is not a supported network address type. Supported: $($script:NetworkSchemes -join ', ')." }
    if (-not (Test-FFProtocol $scheme)) { return "Your FFmpeg build does not support the '$scheme' protocol." }
    return $null
}

function Hide-UrlCredentials {
    param([string]$Url)
    return ($Url -replace '(?<=://)[^/@\s]*@', '***@')
}

# ---- 1. HLS from a media file ----------------------------------------------------------------------

function Get-HlsSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -FolderOnly
    $steps += @{ Id = 'playlist'; Type = 'Text'; Prompt = 'Playlist name'; Help = 'The .m3u8 extension is added automatically.'; Example = 'playlist'; Default = 'playlist'; Label = 'Playlist name'
        Validate = { param($v, $W) $n = $v; if ($n.EndsWith('.m3u8')) { $n = $n.Substring(0, $n.Length - 5) }; $e = Test-ValidFileName ($n + '.m3u8'); if ($e) { return $e }; $null } }
    $steps += @{ Id = 'segdur'; Type = 'Choice'; Prompt = 'Segment duration'; Help = 'Length of each video chunk. 6 seconds is common.'
        Choices = { param($W) @( (New-Choice 2 '2 seconds'), (New-Choice 4 '4 seconds'), (New-Choice 6 '6 seconds (Recommended)'), (New-Choice 10 '10 seconds') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 1; Max = 60; Prompt = 'Custom segment duration (seconds)'; Help = 'Between 1 and 60.'; Example = '8'; ValueLabel = 'Segment duration'; Desc = 'For example 8.' }; Default = 6 }
    $steps += @{ Id = 'mode'; Type = 'Choice'; Prompt = 'Encoding mode'; Help = 'Copy is instant when the streams are already HLS-friendly (H.264/H.265 + AAC/MP3/AC-3).'
        Choices = { param($W) $ok = ((Test-FFEncoder 'libx264') -and (Test-FFEncoder 'aac')); @( (New-Choice 'copy' 'Copy streams (fast)' 'No re-encoding; only works with compatible codecs.'), (New-Choice 'encode' 'Re-encode to H.264 + AAC' 'Most compatible with players; slower.' $ok 'Requires libx264 and the AAC encoder.') ) }
        Default = 'copy' }
    $steps += @{ Id = 'vlevel'; Type = 'Choice'; Prompt = 'Video quality'; Help = 'Higher quality creates larger segments.'; When = { param($W) (Get-Answer $W 'mode') -eq 'encode' }
        Choices = { param($W) @( (New-Choice 'Recommended' 'Recommended'), (New-Choice 'high' 'High quality'), (New-Choice 'small' 'Smaller') ) }; Default = 'Recommended' }
    $steps += @{ Id = 'ptype'; Type = 'Choice'; Prompt = 'Playlist type'; Help = 'VOD lists every segment and ends. Event keeps appending segments.'
        Choices = { param($W) @( (New-Choice 'vod' 'VOD (complete recording)  (Recommended)'), (New-Choice 'event' 'Event (append-only)') ) }; Default = 'vod' }
    $steps += @{ Id = 'segname'; Type = 'Text'; Prompt = 'Segment file name pattern'; Help = 'Must contain a number placeholder such as %03d.'; Example = 'segment_%03d.ts'; Default = 'segment_%03d.ts'; Label = 'Pattern'
        Validate = { param($v, $W) if ($v -notmatch '%0?\d*d') { return 'The pattern must contain a number placeholder such as %03d.' }; $e = Test-ValidFileName (($v -replace '%0?\d*d', '000')); if ($e) { return $e }; if ($v -notmatch '\.ts$|\.m4s$|\.mp4$') { return 'The pattern should end with .ts, .m4s or .mp4.' }; $null } }
    $steps += @{ Id = 'overwrite'; Type = 'Choice'; Prompt = 'HLS files already exist in that folder'; Help = 'Existing files are never replaced without your confirmation.'
        When = { param($W) $d = Get-Answer $W 'outdir'; $p = [string](Get-Answer $W 'playlist' 'playlist'); $p = $p -replace '\.m3u8$', ''; (Test-Path -LiteralPath (Join-Path $d ($p + '.m3u8'))) }
        Choices = { param($W) @( (New-Choice 'rename' 'Choose a different playlist name'), (New-Choice 'overwrite' 'Overwrite the existing playlist and segments') ) }; Default = 'rename'
        OnAnswer = { param($v, $W) if ($v -eq 'rename') { $W.Goto = 'playlist' } } }
    return $steps
}

function Build-HlsJob {
    param($W)
    $info = Get-Media $W 'input'
    if (-not (Test-FFMuxer 'hls')) { throw 'Your FFmpeg build cannot write HLS output.' }
    $dir = Get-Answer $W 'outdir'
    $pl = ([string](Get-Answer $W 'playlist' 'playlist')) -replace '\.m3u8$', ''
    $playlist = Join-Path $dir ($pl + '.m3u8')
    $segPattern = Join-Path $dir ([string](Get-Answer $W 'segname' 'segment_%03d.ts'))
    $ov = ((Get-Answer $W 'overwrite') -eq 'overwrite')
    $mode = [string](Get-Answer $W 'mode' 'copy')
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    $notes = @()
    if ($mode -eq 'copy') {
        if ($info.HasVideo -and $info.Video[0].Codec -notin @('h264', 'hevc')) { throw "The video codec ($(Get-FriendlyCodecName $info.Video[0].Codec)) cannot be copied into HLS. Choose 'Re-encode to H.264 + AAC'." }
        if ($info.HasAudio -and $info.Audio[0].Codec -notin @('aac', 'mp3', 'ac3', 'eac3')) { throw "The audio codec ($(Get-FriendlyCodecName $info.Audio[0].Codec)) cannot be copied into HLS. Choose 'Re-encode to H.264 + AAC'." }
        if ($info.HasVideo) { Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index)) }
        if ($info.HasAudio) { Add-FFOutOpt $cmd @('-map', ('0:' + $info.Audio[0].Index)) }
        Add-FFOutOpt $cmd @('-c', 'copy')
        $notes += 'Copy mode can only start a new segment at a keyframe, so segments may be longer than requested. Use re-encode for exact segment lengths.'
    } else {
        if ($info.HasVideo) {
            $lvl = [string](Get-Answer $W 'vlevel' 'Recommended')
            $prof = Get-EncoderProfile 'libx264'
            $q = $prof.Balanced; if ($lvl -eq 'high') { $q = $prof.High } elseif ($lvl -eq 'small') { $q = $prof.Small }
            Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index))
            Add-FFOutOpt $cmd (Get-VideoEncodeArgs -Encoder 'libx264' -Mode Quality -Quality $q -Container 'ts')
            $segdur = [int](Get-Answer $W 'segdur' 6)
            $fps = $(if ($info.Video[0].Fps) { $info.Video[0].Fps } else { 30 })
            Add-FFOutOpt $cmd @('-g', [string][int]([math]::Round($fps * $segdur)), '-sc_threshold', '0')
        }
        if ($info.HasAudio) { Add-FFOutOpt $cmd @('-map', ('0:' + $info.Audio[0].Index)); Add-FFOutOpt $cmd (Get-AudioEncodeArgs -Encoder 'aac' -BitrateBps 128000) }
    }
    Add-FFOutOpt $cmd @('-f', 'hls', '-hls_time', [string][int](Get-Answer $W 'segdur' 6), '-hls_playlist_type', [string](Get-Answer $W 'ptype' 'vod'), '-hls_segment_filename', $segPattern)
    Set-FFOutput $cmd $playlist -Overwrite:$ov
    if ($ov) { $notes += 'Existing HLS files with the same names will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Mode', $(if ($mode -eq 'copy') { 'Copy streams' } else { 'Re-encode (H.264 + AAC)' })), @('Segments', ("{0} s, {1}" -f (Get-Answer $W 'segdur' 6), (Get-Answer $W 'ptype' 'vod'))), @('Playlist', $playlist))
    $dirLocal = $dir; $cnt = { @(Get-ChildItem -LiteralPath $dirLocal -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.ts', '.m4s', '.m3u8', '.mp4') }).Count }.GetNewClosure()
    return New-JobObject -Title 'Creating HLS output' -Summary $rows -Stages @(@{ Name = 'Creating HLS'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $dir -OutputKind 'Folder' -EnsureDirs @($dir) -Notes $notes -CountOutputs $cnt -ResultNotes @("Playlist: $playlist")
}

# ---- 2. Read / save a network stream ------------------------------------------------------------------

function Get-StreamSaveSteps {
    $steps = @()
    $steps += @{ Id = 'url'; Type = 'Text'; Prompt = 'Stream address (URL)'; Help = 'A stream or file address using a network protocol supported by your FFmpeg build. No sign-in or platform-specific features are provided.'; Example = 'https://example.com/live/stream.m3u8'; Label = 'Address'
        Validate = { param($v, $W)
            $e = Test-NetworkUrl $v; if ($e) { return $e }
            $m = Get-MediaInfo -Path $v.Trim()
            if (-not $m.Ok) { return ('The stream could not be opened: ' + $m.Error) }
            $W.Data['probe.input'] = $m.Info; $W.Data['probe.input'].FileName = 'stream'
            Set-WizardPanel $W 'source.input' 'Stream' (Get-MediaSummaryRows $m.Info) 9
            $null } }
    $steps += @{ Id = 'limit'; Type = 'Timestamp'; Prompt = 'Stop after (optional)'; Help = 'Recording length limit. Leave empty to record until the stream ends.'; Example = '00:05:00  or  300'; Optional = $true; Validate = { param($v, $W) if ($null -ne $v -and $v -le 0) { return 'The limit must be greater than zero.' }; $null } }
    $steps += @{ Id = 'container'; Type = 'Choice'; Prompt = 'Save as'; Help = 'MKV can hold nearly any stream. MP4 needs compatible codecs.'
        Choices = { param($W) @( (New-Choice 'mkv' 'MKV (Recommended)' '' (Test-FFMuxer 'matroska')), (New-Choice 'mp4' 'MP4' '' (Test-FFMuxer 'mp4')), (New-Choice 'ts' 'MPEG-TS' '' (Test-FFMuxer 'mpegts')) ) }; Default = 'mkv' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'stream' -ProtectIds @() -Extension { param($W) '.' + [string](Get-Answer $W 'container' 'mkv') }
    $steps = @($steps)
    # Suggest a sensible default name / folder because there is no local source file.
    for ($i = 0; $i -lt $steps.Count; $i++) {
        if ($steps[$i].Id -eq 'outdir') { $steps[$i].Choices = { param($W) @( (New-Choice ((Get-Location).ProviderPath) 'Current folder' ((Get-Location).ProviderPath)) ) }; $steps[$i].Default = { param($W) (Get-Location).ProviderPath } }
        if ($steps[$i].Id -eq 'outname') { $steps[$i].Default = { param($W) 'stream_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.' + [string](Get-Answer $W 'container' 'mkv') } }
    }
    return $steps
}

function Build-StreamSaveJob {
    param($W)
    $url = ([string](Get-Answer $W 'url')).Trim()
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $cont = [string](Get-Answer $W 'container' 'mkv')
    $c = Get-VideoContainer $cont
    if ($cont -eq 'mp4') { $msg = Test-CopyAllowed $info 'mp4' -Video $true -Audio $true; if ($msg) { throw ($msg + ' Choose MKV instead.') } }
    $scheme = ([regex]::Match($url, '^([a-zA-Z][a-zA-Z0-9+.-]*)://')).Groups[1].Value.ToLowerInvariant()
    $inOpts = @(); if ($scheme -in @('http', 'https')) { $inOpts = @('-reconnect', '1', '-reconnect_streamed', '1', '-reconnect_delay_max', '5') }
    $limit = Get-Answer $W 'limit'
    if ($limit) { $inOpts += @('-t', (Format-FFNumber ([double]$limit) 3)) }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $url $inOpts)
    Add-FFOutOpt $cmd @('-map', '0:v?', '-map', '0:a?', '-c', 'copy', '-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @('Streams are saved without re-encoding.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $dur = $null; if ($limit) { $dur = [double]$limit } elseif ($info.Duration) { $dur = $info.Duration }
    return New-JobObject -Title 'Saving stream' -Summary @(@('Stream', (Hide-UrlCredentials $url)), @('Limit', $(if ($limit) { Format-Duration $limit } else { 'Until the stream ends' })), @('Output', $out.Path)) -Stages @(@{ Name = 'Saving stream'; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

# ---- 3. Inspect ---------------------------------------------------------------------------------------------

function Start-InspectStreamWorkflow {
    $step = @{ Id = 'url'; Type = 'Text'; Prompt = 'Stream address (URL) or file path'; Help = 'The stream is opened read-only and inspected with ffprobe.'; Example = 'https://example.com/live/stream.m3u8'; Label = 'Address'
        Validate = { param($v, $W)
            $t = $v.Trim()
            if ($t -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $e = Test-NetworkUrl $t; if ($e) { return $e }; $target = $t }
            else { $p = Resolve-UserPath $t; if (-not $p) { return 'That is not a valid address or path.' }; $e = Test-InputFile $p; if ($e) { return $e }; $target = $p }
            $m = Get-MediaInfo -Path $target
            if (-not $m.Ok) { return $m.Error }
            $W.Data['info'] = $m.Info; $null } }
    while ($true) {
        $r = Invoke-Wizard -Title 'Inspect Stream Information' -Description 'Read details about a stream or file without downloading it.' -Icon 'Stream' -Steps @($step)
        if ($r.Status -ne 'Completed') { return }
        $act = Show-MediaInfoScreen -Info $r.State.Data['info'] -Title 'Stream Information'
        if ($act -ne 'Another') { return }
    }
}

function Start-StreamingWorkflow {
    $items = @(
        @{ Label = 'Create HLS Output from Media File'; Desc = 'Split a video or audio file into an .m3u8 playlist with segments.'; Key = '1'; Enabled = (Test-FFMuxer 'hls'); Reason = 'This FFmpeg build cannot write HLS.'; Value = { Start-StandardWorkflow -Title 'Create HLS Output' -Description 'Create a playlist and segments for streaming.' -Icon 'Stream' -StepsFactory { Get-HlsSteps } -Build { param($W) Build-HlsJob $W } } },
        @{ Label = 'Read / Save Supported Network Stream'; Desc = 'Record a stream from a supported network address to a file.'; Key = '2'; Value = { Start-StandardWorkflow -Title 'Save Network Stream' -Description 'Save a stream to a local file.' -Icon 'Stream' -StepsFactory { Get-StreamSaveSteps } -Build { param($W) Build-StreamSaveJob $W } } },
        @{ Label = 'Inspect Stream Information'; Desc = 'Show codecs, resolution and other details of a stream or file.'; Key = '3'; Value = { Start-InspectStreamWorkflow } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Stream') + '  Streaming / HLS') -Subtitle 'Work with supported streams and create common HLS outputs.' -Items $items
}

Export-ModuleMember -Function Test-NetworkUrl, Hide-UrlCredentials, Get-HlsSteps, Build-HlsJob, Get-StreamSaveSteps, Build-StreamSaveJob, Start-InspectStreamWorkflow, Start-StreamingWorkflow
