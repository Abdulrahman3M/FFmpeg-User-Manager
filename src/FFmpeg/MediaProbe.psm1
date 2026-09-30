# MediaProbe.psm1 - ffprobe integration: structured JSON -> a normalized media model + friendly summaries.
Set-StrictMode -Version 2.0

function Get-PropOrNull {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-DoubleOrNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}

function ConvertTo-Int64OrNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    $n = 0L
    if ([int64]::TryParse([string]$Value, [ref]$n)) { return $n }
    return $null
}

function ConvertFrom-RateFraction {
    param([string]$Text)
    if (-not $Text) { return $null }
    if ($Text -match '^(\d+)/(\d+)$') {
        $d = [double]$Matches[2]
        if ($d -le 0) { return $null }
        $v = [double]$Matches[1] / $d
        if ($v -le 0) { return $null }
        return $v
    }
    return (ConvertTo-DoubleOrNull $Text)
}

function Get-FriendlyCodecName {
    param([string]$Codec)
    $map = @{
        h264 = 'H.264'; hevc = 'H.265 / HEVC'; av1 = 'AV1'; vp9 = 'VP9'; vp8 = 'VP8'; mpeg4 = 'MPEG-4'; mpeg2video = 'MPEG-2'; mpeg1video = 'MPEG-1'
        prores = 'ProRes'; mjpeg = 'MJPEG'; png = 'PNG'; gif = 'GIF'; wmv3 = 'WMV'; theora = 'Theora'; dnxhd = 'DNxHD'
        aac = 'AAC'; mp3 = 'MP3'; opus = 'Opus'; vorbis = 'Vorbis'; flac = 'FLAC'; alac = 'ALAC'; ac3 = 'AC-3'; eac3 = 'E-AC-3'; dts = 'DTS'
        pcm_s16le = 'PCM 16-bit'; pcm_s24le = 'PCM 24-bit'; pcm_s32le = 'PCM 32-bit'; wmav2 = 'WMA'; truehd = 'TrueHD'; mp2 = 'MP2'
        subrip = 'SubRip (SRT)'; ass = 'ASS/SSA'; ssa = 'ASS/SSA'; mov_text = 'MP4 text'; webvtt = 'WebVTT'; dvd_subtitle = 'DVD bitmap'; hdmv_pgs_subtitle = 'PGS bitmap'; dvb_subtitle = 'DVB bitmap'; text = 'Text'
    }
    if ($map.ContainsKey($Codec)) { return $map[$Codec] }
    if (-not $Codec) { return 'Unknown' }
    return $Codec.ToUpperInvariant()
}

function Get-ChannelText {
    param($Channels, [string]$Layout = '')
    if ($null -eq $Channels) { return 'Unknown' }
    switch ([int]$Channels) {
        1 { return 'Mono' }
        2 { return 'Stereo' }
        6 { return '5.1' }
        8 { return '7.1' }
        default { return "$Channels channels" }
    }
}

function Test-TextSubtitleCodec {
    param([string]$Codec)
    return ($Codec -in @('subrip', 'srt', 'ass', 'ssa', 'mov_text', 'webvtt', 'text', 'ttml', 'sami', 'microdvd', 'subviewer'))
}

function ConvertFrom-ProbeJson {
    # Normalizes ffprobe JSON. Tolerates missing/malformed fields (no exceptions for odd metadata).
    param([string]$Json, [string]$Path)
    $j = $Json | ConvertFrom-Json
    $fmt = Get-PropOrNull $j 'format'
    $streams = @(Get-PropOrNull $j 'streams')
    $info = [ordered]@{
        Path = $Path; FileName = [System.IO.Path]::GetFileName($Path)
        Container = ''; ContainerNames = ''; Duration = $null; Bitrate = $null; Size = $null; StreamCount = $streams.Count
        Video = @(); Audio = @(); Subtitles = @(); Other = @(); Tags = @{}
        HasVideo = $false; HasAudio = $false; HasSubtitles = $false; IsImageOnly = $false
    }
    if ($fmt) {
        $info.ContainerNames = [string](Get-PropOrNull $fmt 'format_name')
        $info.Container = [string](Get-PropOrNull $fmt 'format_long_name')
        $info.Duration = ConvertTo-DoubleOrNull (Get-PropOrNull $fmt 'duration')
        $info.Bitrate = ConvertTo-Int64OrNull (Get-PropOrNull $fmt 'bit_rate')
        $info.Size = ConvertTo-Int64OrNull (Get-PropOrNull $fmt 'size')
        $tags = Get-PropOrNull $fmt 'tags'
        if ($tags) { foreach ($p in $tags.PSObject.Properties) { $info.Tags[[string]$p.Name] = [string]$p.Value } }
    }
    foreach ($s in $streams) {
        $type = [string](Get-PropOrNull $s 'codec_type')
        $tags = Get-PropOrNull $s 'tags'
        $lang = ''; $title = ''
        if ($tags) { $lang = [string](Get-PropOrNull $tags 'language'); $title = [string](Get-PropOrNull $tags 'title') }
        $disp = Get-PropOrNull $s 'disposition'
        $codec = [string](Get-PropOrNull $s 'codec_name')
        $common = [ordered]@{
            Index = [int](Get-PropOrNull $s 'index'); Codec = $codec; CodecLong = [string](Get-PropOrNull $s 'codec_long_name')
            Language = $lang; Title = $title; Bitrate = (ConvertTo-Int64OrNull (Get-PropOrNull $s 'bit_rate'))
            Default = ([string](Get-PropOrNull $disp 'default') -eq '1'); Profile = [string](Get-PropOrNull $s 'profile')
        }
        switch ($type) {
            'video' {
                $attached = ([string](Get-PropOrNull $disp 'attached_pic') -eq '1')
                $rfr = ConvertFrom-RateFraction ([string](Get-PropOrNull $s 'r_frame_rate'))
                $afr = ConvertFrom-RateFraction ([string](Get-PropOrNull $s 'avg_frame_rate'))
                $fps = $afr; if (-not $fps) { $fps = $rfr }
                $vfr = $false
                if ($rfr -and $afr -and ([math]::Abs($rfr - $afr) / $rfr) -gt 0.02) { $vfr = $true }
                $rot = 0
                $tr = Get-PropOrNull $tags 'rotate'
                if ($tr) { $rv = ConvertTo-DoubleOrNull $tr; if ($null -ne $rv) { $rot = [int]$rv } }
                foreach ($sd in @(Get-PropOrNull $s 'side_data_list')) { $rv = ConvertTo-DoubleOrNull (Get-PropOrNull $sd 'rotation'); if ($null -ne $rv) { $rot = [int](-$rv) } }
                $rot = (($rot % 360) + 360) % 360
                $w = ConvertTo-Int64OrNull (Get-PropOrNull $s 'width'); $h = ConvertTo-Int64OrNull (Get-PropOrNull $s 'height')
                $v = $common + [ordered]@{
                    Width = $w; Height = $h; PixFmt = [string](Get-PropOrNull $s 'pix_fmt'); Fps = $fps; IsVfr = $vfr
                    Aspect = [string](Get-PropOrNull $s 'display_aspect_ratio'); Rotation = $rot; AttachedPic = $attached
                    Duration = (ConvertTo-DoubleOrNull (Get-PropOrNull $s 'duration')); FieldOrder = [string](Get-PropOrNull $s 'field_order')
                }
                if ($attached) { $info.Other += , ([pscustomobject]$v) } else { $info.Video += , ([pscustomobject]$v) }
            }
            'audio' {
                $a = $common + [ordered]@{
                    SampleRate = (ConvertTo-Int64OrNull (Get-PropOrNull $s 'sample_rate')); Channels = (ConvertTo-Int64OrNull (Get-PropOrNull $s 'channels'))
                    ChannelLayout = [string](Get-PropOrNull $s 'channel_layout'); SampleFmt = [string](Get-PropOrNull $s 'sample_fmt')
                    Duration = (ConvertTo-DoubleOrNull (Get-PropOrNull $s 'duration'))
                }
                $info.Audio += , ([pscustomobject]$a)
            }
            'subtitle' {
                $sb = $common + [ordered]@{ IsText = (Test-TextSubtitleCodec $codec) }
                $info.Subtitles += , ([pscustomobject]$sb)
            }
            default { $info.Other += , ([pscustomobject]$common) }
        }
    }
    if ($null -eq $info.Duration) {
        foreach ($v in $info.Video) { if ($v.Duration) { $info.Duration = $v.Duration; break } }
        if ($null -eq $info.Duration) { foreach ($a in $info.Audio) { if ($a.Duration) { $info.Duration = $a.Duration; break } } }
    }
    $info.HasVideo = ($info.Video.Count -gt 0); $info.HasAudio = ($info.Audio.Count -gt 0); $info.HasSubtitles = ($info.Subtitles.Count -gt 0)
    if ($info.HasVideo -and $info.Duration -ne $null -and $info.Duration -le 0.05) { $info.IsImageOnly = $true }
    if ($info.HasVideo -and $info.Video[0].Codec -in @('png', 'mjpeg', 'bmp', 'webp', 'tiff') -and $info.Video.Count -eq 1 -and -not $info.HasAudio -and ($info.ContainerNames -match 'image2|png_pipe|jpeg_pipe|webp_pipe|bmp_pipe|tiff_pipe')) { $info.IsImageOnly = $true }
    return [pscustomobject]$info
}

function Get-MediaInfo {
    <# Returns @{ Ok; Info; Error }. Never throws. #>
    param([Parameter(Mandatory)][string]$Path)
    $res = [pscustomobject]@{ Ok = $false; Info = $null; Error = '' }
    $probe = Get-FFprobePath
    if (-not $probe) { $res.Error = 'ffprobe is not available.'; return $res }
    $r = Invoke-ExternalCapture -FilePath $probe -Arguments @('-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', '-i', $Path) -TimeoutSec 60
    if (-not $r.Started) { $res.Error = 'ffprobe could not be started: ' + $r.Error; return $res }
    if ($r.TimedOut) { $res.Error = 'ffprobe timed out while reading the file.'; return $res }
    if ($r.ExitCode -ne 0 -or -not $r.StdOut.Trim()) {
        $msg = ($r.StdErr -split "`r?`n" | Where-Object { $_ } | Select-Object -First 2) -join ' '
        if (-not $msg) { $msg = 'unknown error' }
        $res.Error = "The file could not be read as media ($msg)"
        return $res
    }
    try {
        $info = ConvertFrom-ProbeJson $r.StdOut $Path
    } catch { $res.Error = 'ffprobe returned data that could not be understood.'; return $res }
    if ($info.StreamCount -eq 0) { $res.Error = 'The file contains no recognizable audio or video streams.'; return $res }
    $res.Ok = $true; $res.Info = $info
    return $res
}

function Get-AudioLine {
    param($A)
    $parts = @((Get-FriendlyCodecName $A.Codec), (Get-ChannelText $A.Channels))
    if ($A.SampleRate) { $parts += ('{0:0.#} kHz' -f ($A.SampleRate / 1000)) }
    return ($parts -join (' ' + [string][char]0x00B7 + ' '))
}

function Get-MediaSummaryRows {
    # Rows for the "Source" panel shown at the top of workflow screens.
    param($Info)
    $dot = ' ' + [string][char]0x00B7 + ' '
    $rows = @()
    $rows += , @('File', $Info.FileName)
    $rows += , @('Duration', $(if ($null -ne $Info.Duration) { Format-Duration $Info.Duration } else { 'unknown' }))
    if ($Info.HasVideo) {
        $v = $Info.Video[0]
        $vp = @((Get-FriendlyCodecName $v.Codec))
        if ($v.Width -and $v.Height) { $vp += ('{0}{1}{2}' -f $v.Width, [char]0x00D7, $v.Height) }
        if ($v.Fps) { $vp += ('{0:0.##} FPS' -f $v.Fps) }
        $line = $vp -join $dot
        if ($Info.Video.Count -gt 1) { $line += "  (+$($Info.Video.Count - 1) more)" }
        $rows += , @('Video', $line)
    }
    if ($Info.HasAudio) {
        $line = Get-AudioLine $Info.Audio[0]
        if ($Info.Audio.Count -gt 1) { $line += "  (+$($Info.Audio.Count - 1) more track(s))" }
        $rows += , @('Audio', $line)
    }
    if ($Info.HasSubtitles) { $rows += , @('Subtitles', "$($Info.Subtitles.Count) stream(s)") }
    $size = $Info.Size; if ($null -eq $size -and (Test-Path -LiteralPath $Info.Path -PathType Leaf)) { $size = (New-Object System.IO.FileInfo($Info.Path)).Length }
    $rows += , @('Size', (Format-FileSize $size))
    return $rows
}

function Get-DisplayVideoSize {
    # Effective displayed size accounting for 90/270 degree rotation metadata.
    param($V)
    $w = [int]$V.Width; $h = [int]$V.Height
    if ($V.Rotation -eq 90 -or $V.Rotation -eq 270) { return @($h, $w) }
    return @($w, $h)
}

function Get-MediaDetailSections {
    # Structured sections for the Media Information screen: File, Video, Audio, Subtitles, Metadata, Streams.
    param($Info, [switch]$Technical)
    $dot = ' ' + [string][char]0x00B7 + ' '
    $sections = [ordered]@{}
    $file = @(
        , @('Name', $Info.FileName), @('Folder', [System.IO.Path]::GetDirectoryName($Info.Path)),
        @('Container', ($Info.Container + $(if ($Info.ContainerNames) { ' (' + $Info.ContainerNames + ')' } else { '' }))),
        @('Duration', $(if ($null -ne $Info.Duration) { (Format-Duration $Info.Duration) + ('  ({0:0.###} s)' -f $Info.Duration) } else { 'unknown' })),
        @('Size', (Format-FileSize $Info.Size)),
        @('Bitrate', $(if ($Info.Bitrate) { ('{0:N0} kbps' -f ($Info.Bitrate / 1000)) } else { 'unknown' })),
        @('Streams', [string]$Info.StreamCount)
    )
    $sections['File'] = $file
    $vrows = @()
    foreach ($v in $Info.Video) {
        $n = "#$($v.Index)"
        $vrows += , @($n, (Get-FriendlyCodecName $v.Codec) + $(if ($v.Profile) { " ($($v.Profile))" } else { '' }))
        if ($v.Width) { $vrows += , @('  Size', ('{0}{1}{2}' -f $v.Width, [char]0x00D7, $v.Height) + $(if ($v.Aspect) { "  (aspect $($v.Aspect))" } else { '' })) }
        if ($v.Fps) { $vrows += , @('  Frame rate', ('{0:0.###} FPS' -f $v.Fps) + $(if ($v.IsVfr) { '  (variable frame rate)' } else { '' })) }
        if ($v.PixFmt) { $vrows += , @('  Pixel fmt', $v.PixFmt) }
        if ($v.Rotation) { $vrows += , @('  Rotation', "$($v.Rotation) degrees") }
        if ($v.Bitrate) { $vrows += , @('  Bitrate', ('{0:N0} kbps' -f ($v.Bitrate / 1000))) }
    }
    if ($vrows.Count -eq 0) { $vrows = @(, @('', 'No video stream')) }
    $sections['Video'] = $vrows
    $arows = @()
    foreach ($a in $Info.Audio) {
        $arows += , @("#$($a.Index)", (Get-AudioLine $a) + $(if ($a.Language) { "  [$($a.Language)]" } else { '' }) + $(if ($a.Title) { "  $($a.Title)" } else { '' }))
        if ($Technical) {
            if ($a.SampleFmt) { $arows += , @('  Sample fmt', $a.SampleFmt) }
            if ($a.ChannelLayout) { $arows += , @('  Layout', $a.ChannelLayout) }
        }
        if ($a.Bitrate) { $arows += , @('  Bitrate', ('{0:N0} kbps' -f ($a.Bitrate / 1000))) }
    }
    if ($arows.Count -eq 0) { $arows = @(, @('', 'No audio stream')) }
    $sections['Audio'] = $arows
    $srows = @()
    foreach ($s in $Info.Subtitles) { $srows += , @("#$($s.Index)", (Get-FriendlyCodecName $s.Codec) + $(if ($s.Language) { "  [$($s.Language)]" } else { '' }) + $(if ($s.Title) { "  $($s.Title)" } else { '' }) + $(if (-not $s.IsText) { '  (bitmap)' } else { '' })) }
    if ($srows.Count -eq 0) { $srows = @(, @('', 'No subtitle streams')) }
    $sections['Subtitles'] = $srows
    $mrows = @()
    foreach ($k in ($Info.Tags.Keys | Sort-Object)) { $mrows += , @($k, [string]$Info.Tags[$k]) }
    if ($mrows.Count -eq 0) { $mrows = @(, @('', 'No container metadata')) }
    $sections['Metadata'] = $mrows
    $strows = @()
    foreach ($v in $Info.Video) { $strows += , @("#$($v.Index)", 'video' + $dot + $v.Codec) }
    foreach ($a in $Info.Audio) { $strows += , @("#$($a.Index)", 'audio' + $dot + $a.Codec) }
    foreach ($s in $Info.Subtitles) { $strows += , @("#$($s.Index)", 'subtitle' + $dot + $s.Codec) }
    foreach ($o in $Info.Other) { $strows += , @("#$($o.Index)", 'other' + $dot + $o.Codec) }
    $sections['Streams'] = $strows
    return $sections
}

Export-ModuleMember -Function Get-AudioLine, ConvertFrom-ProbeJson, Get-MediaInfo, Get-FriendlyCodecName, Get-ChannelText, Get-MediaSummaryRows, Get-MediaDetailSections, Get-DisplayVideoSize, ConvertFrom-RateFraction, Test-TextSubtitleCodec
