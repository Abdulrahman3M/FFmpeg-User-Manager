# Unit tests: validation, paths, command builder, capability parsing, probe.
Set-TestGroup 'Validation'
$r = ConvertFrom-TimestampText '90'; Assert-Equal 'timestamp seconds' 90 $r.Value
$r = ConvertFrom-TimestampText '1:30'; Assert-Equal 'timestamp MM:SS' 90 $r.Value
$r = ConvertFrom-TimestampText '01:02:03.5'; Assert-Equal 'timestamp HH:MM:SS.f' 3723.5 $r.Value
$r = ConvertFrom-TimestampText '1h2m3s'; Assert-Equal 'timestamp 1h2m3s' 3723 $r.Value
$r = ConvertFrom-TimestampText '1:75'; Assert-True 'timestamp rejects seconds >= 60' (-not $r.Ok)
$r = ConvertFrom-TimestampText 'abc'; Assert-True 'timestamp rejects text' (-not $r.Ok)
$r = ConvertFrom-TimestampText ''; Assert-True 'timestamp rejects blank' (-not $r.Ok)
$r = ConvertFrom-IntegerText '1280' 1 10000 'Width'; Assert-Equal 'integer ok' 1280 $r.Value
$r = ConvertFrom-IntegerText '-5' 1 $null 'Width'; Assert-True 'integer rejects below min' (-not $r.Ok)
$r = ConvertFrom-IntegerText '12.5'; Assert-True 'integer rejects decimals' (-not $r.Ok)
$r = ConvertFrom-DecimalText '1,5' 0.1 8; Assert-Equal 'decimal accepts comma' 1.5 $r.Value
$r = ConvertFrom-DecimalText '1.75x' 0.1 8; Assert-Equal 'decimal accepts x suffix' 1.75 $r.Value
$r = ConvertFrom-DecimalText '-2' 0.1 8; Assert-True 'decimal rejects negative below min' (-not $r.Ok)
$r = ConvertFrom-BitrateText '2500k'; Assert-Equal 'bitrate 2500k' 2500000 $r.Value
$r = ConvertFrom-BitrateText '4M'; Assert-Equal 'bitrate 4M' 4000000 $r.Value
$r = ConvertFrom-BitrateText 'fast'; Assert-True 'bitrate rejects text' (-not $r.Ok)
$r = ConvertFrom-FrameRateText '29.97'; Assert-Equal 'fps decimal' 29.97 $r.Value
$r = ConvertFrom-FrameRateText '30000/1001'; Assert-True 'fps fraction' ([math]::Abs($r.Value - 29.97003) -lt 0.001)
$r = ConvertFrom-FrameRateText '0'; Assert-True 'fps rejects zero' (-not $r.Ok)
$r = ConvertFrom-FrameRateText '999'; Assert-True 'fps rejects > 240' (-not $r.Ok)
$r = ConvertFrom-ColorText '#ffcc00'; Assert-Equal 'color hex' '0xFFCC00' $r.Value
$r = ConvertFrom-ColorText 'red;rm'; Assert-True 'color rejects junk' (-not $r.Ok)
Assert-Equal 'timestamp formatting' '00:01:30.500' (ConvertTo-TimestampText 90.5)

Set-TestGroup 'Paths'
Assert-Equal 'clean path: double quotes' 'C:\Videos\my file.mp4' (ConvertTo-CleanPath '"C:\Videos\my file.mp4"')
Assert-Equal 'clean path: single quotes' 'C:\Videos\my file.mp4' (ConvertTo-CleanPath "'C:\Videos\my file.mp4'")
Assert-Equal 'clean path: console drag-drop prefix' 'C:\x y\a.mp4' (ConvertTo-CleanPath "& 'C:\x y\a.mp4'")
Assert-Equal 'clean path: outer spaces' '/tmp/a.mp4' (ConvertTo-CleanPath '   /tmp/a.mp4  ')
$rel = Resolve-UserPath 'relative.mp4'; Assert-True 'relative path is normalized to absolute' ([System.IO.Path]::IsPathRooted($rel))
Assert-True 'invalid name: illegal char' ((Test-ValidFileName 'a<b.mp4') -ne $null)
Assert-True 'invalid name: reserved' ((Test-ValidFileName 'CON.mp4') -ne $null)
Assert-True 'invalid name: trailing dot' ((Test-ValidFileName 'a.') -ne $null)
Assert-True 'invalid name: empty' ((Test-ValidFileName '') -ne $null)
Assert-True 'valid name: unicode + spaces' ((Test-ValidFileName 'Видео тест العربية (1).mp4') -eq $null)
Assert-True 'missing file is rejected' ((Test-InputFile (Join-Path (Get-TestWork) 'nope.mp4')) -ne $null)
$empty = Join-Path (Get-TestWork) 'zero.mp4'; [System.IO.File]::WriteAllBytes($empty, [byte[]]@())
Assert-True 'zero-length file is rejected' ((Test-InputFile $empty) -ne $null)
Assert-True 'folder is rejected as input file' ((Test-InputFile (Get-TestWork)) -ne $null)
Assert-Equal 'file size format' '1.5 MB' (Format-FileSize (1.5MB))
Assert-Equal 'duration format' '01:01:05' (Format-Duration 3665.4)

Set-TestGroup 'Command builder: argument quoting'
# Round-trip through a real child process: ffmpeg writes files whose names contain awkward characters.
$names = @('plain.png', 'with space.png', 'paren (1).png', 'amp & and.png', "apos ' quote.png", 'Unicode-ünï-日本.png', 'Arabic-اختبار-ملف.png', 'Cyrillic-Тест-видео.png', 'semi;colon,comma.png', 'dollar $(Get-Date) `tick.png', 'bracket [x] {y}.png')
$dir = Join-Path (Get-TestWork) 'quoting dir (test) & more'
[void](New-Item -ItemType Directory -Path $dir -Force)
foreach ($n in $names) {
    $p = Join-Path $dir $n
    $res = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=16x16:d=0.1', '-frames:v', '1', $p) -TimeoutSec 30
    Assert-True "file name survives intact: $n" ((Test-Path -LiteralPath $p -PathType Leaf) -and $res.ExitCode -eq 0) $res.StdErr
}
$created = @((Get-ChildItem -LiteralPath $dir -File).Name)
Assert-Equal 'no injected extra files were created' $names.Count $created.Count
Assert-Equal 'quoting: trailing backslash arg' '"C:\dir with space\\"' (ConvertTo-ProcessArgument 'C:\dir with space\')
Assert-Equal 'quoting: embedded quote' '"a \"b\" c"' (ConvertTo-ProcessArgument 'a "b" c')
Assert-Equal 'quoting: empty arg' '""' (ConvertTo-ProcessArgument '')
Assert-Equal 'quoting: plain arg untouched' 'abc' (ConvertTo-ProcessArgument 'abc')

Set-TestGroup 'Command builder: injection safety'
$marker = Join-Path (Get-TestWork) 'INJECTED.txt'
$evil = "x'; New-Item -ItemType File -Path '$marker' -Force; '"
$cmd = New-FFCommand
[void](Add-FFInput $cmd '/tmp/a.mp4')
Set-FFOutput $cmd (Join-Path (Get-TestWork) $evil.Replace('/', '_').Replace('\', '_'))
$tokens = Get-FFTokens $cmd
Assert-True 'evil text stays a single token' (@($tokens | Where-Object { $_ -like '*New-Item*' }).Count -eq 1)
Assert-True 'evil text was never executed' (-not (Test-Path -LiteralPath $marker))
Assert-Equal 'default is -n (never overwrite)' '-n' $tokens[0]
Set-FFOutput $cmd '/tmp/o.mp4' -Overwrite
Assert-Equal 'confirmed overwrite uses -y' '-y' (Get-FFTokens $cmd)[0]

Set-TestGroup 'Command builder: filters and encoders'
Assert-Equal 'atempo 3x' 'atempo=2.0,atempo=1.5' (Get-AtempoChain 3.0)
Assert-Equal 'atempo 0.25x' 'atempo=0.5,atempo=0.5' (Get-AtempoChain 0.25)
Assert-Equal 'atempo 0.75x' 'atempo=0.75' (Get-AtempoChain 0.75)
Assert-Equal 'atempo 8x' 'atempo=2.0,atempo=2.0,atempo=2.0' (Get-AtempoChain 8.0)
Assert-Equal 'atempo 1x' 'atempo=1.0' (Get-AtempoChain 1.0)
Assert-Equal 'scale preserve width' 'scale=1280:-2' (New-ScaleFilter -Width 1280 -Mode Preserve)
Assert-Equal 'scale preserve height' 'scale=-2:720' (New-ScaleFilter -Height 720 -Mode Preserve)
Assert-True 'scale fit+pad pads' ((New-ScaleFilter 1920 1080 Fit -Pad) -like '*pad=1920:1080*')
Assert-True 'scale fill crops' ((New-ScaleFilter 1280 720 Fill) -like '*crop=1280:720')
Assert-Equal 'x264 default args' '-c:v libx264 -crf 23 -preset medium -pix_fmt yuv420p -movflags +faststart' ((Get-VideoEncodeArgs -Encoder libx264 -Container mp4 -Faststart $true) -join ' ')
Assert-Equal 'x265 mp4 gets hvc1 tag' '-c:v libx265 -crf 28 -preset medium -pix_fmt yuv420p -tag:v hvc1' ((Get-VideoEncodeArgs -Encoder libx265 -Container mp4) -join ' ')
Assert-True 'bitrate mode sets -b:v' (((Get-VideoEncodeArgs -Encoder libx264 -Mode Bitrate -BitrateBps 2500000) -join ' ') -like '*-b:v 2500000*')
Assert-Equal 'audio args (aac 192k stereo 48k)' '-c:a aac -b:a 192000 -ar 48000 -ac 2' ((Get-AudioEncodeArgs -Encoder aac -BitrateBps 192000 -SampleRate 48000 -Channels 2) -join ' ')
Assert-Equal 'lossless audio ignores bitrate' '-c:a flac' ((Get-AudioEncodeArgs -Encoder flac -BitrateBps 192000) -join ' ')
Assert-Equal 'target size bitrate (10 MB, 60 s, 128k audio)' 1228158 (Get-TargetBitrateForSize (10MB) 60 128000)
$threw = $false; try { $null = Get-TargetBitrateForSize 1000 3600 } catch { $threw = $true }
Assert-True 'impossible target size is rejected' $threw
# Escaping proven against the real FFmpeg filter parser: a path with every special character.
$weird = Join-Path $dir "f:i[l]t,er;'x=1 y.png"
$null = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=16x16:d=0.1', '-frames:v', '1', $weird) -TimeoutSec 30
$res = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', ('movie=' + (ConvertTo-FFFilterPath $weird)), '-frames:v', '1', (Join-Path $dir 'movie_out.png')) -TimeoutSec 30
Assert-True 'filter path escaping accepted by FFmpeg (: [ ] , ; quote =)' ($res.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $dir 'movie_out.png'))) $res.StdErr

Set-TestGroup 'Progress parsing'
$st = [pscustomobject]@{ OutTime = 0.0; Frame = 0L; Fps = 0.0; Speed = 0.0; Size = 0L; Ended = $false }
foreach ($l in @('frame=120', 'fps=25.0', 'out_time_us=2500000', 'speed=1.8x', 'total_size=1234', 'progress=continue')) { Update-ProgressState $st $l }
Assert-Equal 'progress out_time' 2.5 $st.OutTime
Assert-Equal 'progress speed' 1.8 $st.Speed
Assert-Equal 'progress percent' 50 (Get-ProgressPercent $st 5.0)
Assert-True 'unknown duration gives no fake percent' ($null -eq (Get-ProgressPercent $st $null))
Update-ProgressState $st 'out_time_us=N/A'; Assert-Equal 'N/A time ignored' 2.5 $st.OutTime
Update-ProgressState $st 'progress=end'; Assert-True 'progress end flag' $st.Ended

Set-TestGroup 'Capability parsing (sample FFmpeg output)'
$enc = "Encoders:`n V..... = Video`n ------`n V....D libx264              libx264 H.264 / AVC`n A....D aac                   AAC (Advanced Audio Coding)`n V.S... h264_nvenc          NVIDIA NVENC H.264"
$e = ConvertFrom-FFCodecList $enc
Assert-True 'encoder list parses names' ($e.ContainsKey('libx264') -and $e.ContainsKey('aac') -and $e.ContainsKey('h264_nvenc'))
$mux = "File formats:`n D. = Demuxing supported`n .E = Muxing supported`n --`n  E mp4             MP4 (MPEG-4 Part 14)`n D  mov,mp4,m4a  QuickTime`n DE matroska       Matroska"
$m = ConvertFrom-FFFormatList $mux
Assert-True 'muxer list parses (2-dash separator)' ($m.ContainsKey('mp4') -and $m.ContainsKey('matroska') -and $m.ContainsKey('m4a'))
Assert-True 'header lines are not parsed as formats' (-not $m.ContainsKey('='))
$flt = "Filters:`n T.. = Timeline support`n ... = Slice threading`n ---`n T.C acrossfade       AA->A      Cross fade`n ... palettegen        V->V       Generate a palette"
$f = ConvertFrom-FFFilterList $flt
Assert-True 'filter list parses' ($f.ContainsKey('palettegen') -and $f.ContainsKey('acrossfade'))
$prot = "Supported file protocols:`nInput:`n  file`n  https`nOutput:`n  file`n  rtmp"
$pr = ConvertFrom-FFProtocolList $prot
Assert-True 'protocol list parses input and output' ($pr.In.ContainsKey('https') -and $pr.Out.ContainsKey('rtmp') -and -not $pr.Out.ContainsKey('https'))
$hw = ConvertFrom-FFHwAccelList "Hardware acceleration methods:`ncuda`nvaapi`nqsv"
Assert-Equal 'hwaccel list parses' 'cuda,vaapi,qsv' ($hw -join ',')

Set-TestGroup 'Capability discovery (installed FFmpeg)'
$cs = Get-FFCapabilityStatus
Assert-True 'capabilities loaded from the installed build' ($cs.Loaded -and $cs.Encoders -gt 20 -and $cs.Muxers -gt 10 -and $cs.Filters -gt 50)
Assert-True 'mp4 muxer is detected' (Test-FFMuxer 'mp4')
Assert-True 'a bogus encoder is not detected' (-not (Test-FFEncoder 'definitely_not_an_encoder'))
Set-FFCapabilityData -Encoders @('libx264', 'aac') -Muxers @('mp4')
$vc = @(Get-VideoEncoderChoices)
Assert-Equal 'only installed encoders are offered (synthetic build)' 'libx264' (($vc | ForEach-Object { $_.Encoder }) -join ',')
Assert-True 'H.265 is not offered when libx265 is missing' (-not (@($vc | Where-Object { $_.Family -eq 'hevc' }).Count))
Assert-Equal 'containers limited to available muxers' 'mp4' ((Get-AvailableVideoContainers | ForEach-Object { $_.Id }) -join ',')
$null = Initialize-FFCapabilities -Force

Set-TestGroup 'ffprobe media probe'
$av = New-Fixture 'probe_av.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$mi = Get-MediaInfo $av
Assert-True 'probe ok for A/V file' $mi.Ok
Assert-True 'video stream parsed (codec, size, fps)' ($mi.Info.Video[0].Codec -eq 'h264' -and $mi.Info.Video[0].Width -eq 320 -and [math]::Abs($mi.Info.Video[0].Fps - 25) -lt 0.01)
Assert-True 'audio stream parsed' ($mi.Info.HasAudio -and $mi.Info.Audio[0].Codec -eq 'aac' -and $mi.Info.Audio[0].SampleRate -gt 0)
Assert-True 'duration parsed' ([math]::Abs($mi.Info.Duration - 2) -lt 0.2)
$rows = Get-MediaSummaryRows $mi.Info
Assert-True 'summary has File/Duration/Video/Audio/Size rows' ((($rows | ForEach-Object { $_[0] }) -join ',') -eq 'File,Duration,Video,Audio,Size')
$aud = New-Fixture 'probe_audio.mp3' @('-f', 'lavfi', '-i', 'sine=duration=1', '-c:a', 'libmp3lame')
$ma = Get-MediaInfo $aud
Assert-True 'audio-only file has no video stream' ($ma.Ok -and -not $ma.Info.HasVideo -and $ma.Info.HasAudio)
$nov = New-Fixture 'probe_video_only.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=1:size=64x64:rate=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$mn = Get-MediaInfo $nov
Assert-True 'video-only file has no audio stream' ($mn.Ok -and $mn.Info.HasVideo -and -not $mn.Info.HasAudio)
$corrupt = Join-Path (Get-TestWork) 'corrupt.mp4'; [System.IO.File]::WriteAllText($corrupt, 'this is not media at all')
$mc = Get-MediaInfo $corrupt
Assert-True 'corrupt file is rejected with a message' ((-not $mc.Ok) -and $mc.Error.Length -gt 5)
$srt = Join-Path (Get-TestWork) 'sub.srt'; [System.IO.File]::WriteAllText($srt, "1`n00:00:00,000 --> 00:00:01,000`nHello`n")
$ms = Get-MediaInfo $srt
Assert-True 'subtitle file probes as subtitle stream' ($ms.Ok -and $ms.Info.HasSubtitles -and $ms.Info.Subtitles[0].IsText)
$withsub = New-Fixture 'probe_sub.mkv' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=64x64:rate=10', '-i', $srt, '-map', '0:v', '-map', '1:s', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:s', 'srt', '-metadata:s:s:0', 'language=eng')
$mw = Get-MediaInfo $withsub
Assert-True 'embedded subtitle stream with language is parsed' ($mw.Ok -and $mw.Info.Subtitles.Count -eq 1 -and $mw.Info.Subtitles[0].Language -eq 'eng')
$raw = New-Fixture 'probe_unknown_duration.h264' @('-f', 'lavfi', '-i', 'testsrc=duration=1:size=64x64:rate=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-f', 'h264')
$mr = Get-MediaInfo $raw
Assert-True 'unknown/absent duration does not crash the probe' ($mr.Ok)
$sections = Get-MediaDetailSections $mi.Info
Assert-Equal 'info sections' 'File,Video,Audio,Subtitles,Metadata,Streams' ($sections.Keys -join ',')
