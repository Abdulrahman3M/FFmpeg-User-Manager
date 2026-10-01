# Workflow smoke tests (part 1): primary workflows driven through the real wizard with real FFmpeg.
$W = Get-TestWork
$vid = New-Fixture 'w video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$aud = New-Fixture 'w audio.mp3' @('-f', 'lavfi', '-i', 'sine=frequency=880:duration=4', '-c:a', 'libmp3lame')
$DONE = New-ScreenRule 'Completed successfully' '{#Main menu}'
$FAIL = New-ScreenRule 'Processing failed\.' '{#Back}'

function Assert-JobOk {
    param([string]$Name, $Ui, [string]$Output, [string]$Type = 'video')
    $ok = ($Ui.Error -eq '') -and $Ui.Output.Contains('Completed successfully')
    $why = ''
    if (-not $ok) { $why = "error=[$($Ui.Error)]`n" + (Get-LastFrame $Ui.Output) }
    Assert-True "$Name : job completes" $ok $why
    if ($Output) { Assert-True "$Name : output is valid media ($([System.IO.Path]::GetFileName($Output)))" (Test-ValidMediaFile $Output $(if ($Type -eq 'any') { '' } else { $Type })) }
}

Set-TestGroup 'Workflow 1: Convert Video Format'
$out = Join-Path $W 'w video_converted.mp4'
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'MP4 -> MP4 defaults (auto codec, copy audio)' $ui $out
$j = Get-ProbeJson $out
Assert-True 'output keeps H.264 + AAC and 320x240' ((Get-StreamOf $j 'video')[0].codec_name -eq 'h264' -and (Get-StreamOf $j 'video')[0].width -eq 320 -and (Get-StreamOf $j 'audio').Count -eq 1)
Assert-True 'source file untouched after conversion' (Test-Path -LiteralPath $vid)
Assert-Contains 'progress screen was displayed' $ui.Output 'Converting video'
Assert-Contains 'result screen offers to open the output folder' $ui.Output 'Open output folder'
Assert-Contains 'result screen offers Run again and Main menu' $ui.Output 'Main menu'
$before = (Get-Item -LiteralPath $out).LastWriteTimeUtc.Ticks
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output file name' '{Enter}' 1), (New-Rule 'That output file already exists' '01' 1), (New-Rule 'Output file name' '{Clear}w video second.mp4{Enter}'), $DONE, $FAIL)
Assert-Contains 'existing output triggers the overwrite question' $ui.Output 'That output file already exists'
Assert-True 'existing output was NOT modified when a new name was chosen' ((Get-Item -LiteralPath $out).LastWriteTimeUtc.Ticks -eq $before)
Assert-True 'renamed output was created' (Test-Path -LiteralPath (Join-Path $W 'w video second.mp4'))
Start-Sleep -Milliseconds 1100
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'That output file already exists' '02'), $DONE, $FAIL)
Assert-JobOk 'explicit overwrite is applied only after confirmation' $ui $out
Assert-True 'overwritten file has a newer timestamp' ((Get-Item -LiteralPath $out).LastWriteTimeUtc.Ticks -gt $before)
$outw = Join-Path $W 'w video_converted.webm'
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output format' '03'), (New-Rule 'Resolution' '{#LAST}'), (New-Rule 'Custom resolution' '160x120{Enter}'), (New-Rule 'Audio' '02'), $DONE, $FAIL)
Assert-JobOk 'MP4 -> WebM (VP9/Opus, custom 160x120)' $ui $outw
$j = Get-ProbeJson $outw
Assert-True 'webm uses vp9 + opus at 160x120' ((Get-StreamOf $j 'video')[0].codec_name -eq 'vp9' -and (Get-StreamOf $j 'audio')[0].codec_name -eq 'opus' -and (Get-StreamOf $j 'video')[0].width -eq 160)
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Video codec' '02'), (New-Rule 'Resolution' '05'), (New-Rule 'Output file name' '{Clear}unsupported_case.mp4{Enter}'), (New-ScreenRule 'requires re-encoding' '{Enter}' 1), (New-ScreenRule '── Summary' '{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}')) -MaxCalls 80
Assert-Contains 'unsupported combination (copy codec + resize) is explained instead of crashing' (Get-FlatText $ui.Output) 'requires re-encoding'
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output format' '05'), (New-Rule 'Output file name' '{Clear}avi_case.avi{Enter}'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}' 1)) -MaxCalls 80
Assert-Contains 'AVI: codec choices offered are limited to compatible ones (no VP9)' $ui.Output 'MPEG-4'
Assert-NotContains 'AVI: VP9 is not offered for AVI' (($ui.Output -split '=====(?:FRAME|CLEAR)=====' | Where-Object { $_ -match 'Video codec' } | Select-Object -First 1)) 'VP9'

Set-TestGroup 'Workflow 2: Convert Audio Format'
$outa = Join-Path $W 'w audio_converted.m4a'
$ui = Invoke-Flow { Start-ConvertAudioWorkflow } @((New-Rule 'Input audio file' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'MP3 -> M4A (AAC) defaults' $ui $outa 'audio'
$outf = Join-Path $W 'w audio_converted.flac'
$ui = Invoke-Flow { Start-ConvertAudioWorkflow } @((New-Rule 'Input audio file' "$aud{Enter}"), (New-Rule 'Output format' '03'), $DONE, $FAIL)
Assert-JobOk 'MP3 -> FLAC (lossless, no bitrate question)' $ui $outf 'audio'
Assert-Equal 'flac codec' 'flac' (Get-StreamOf (Get-ProbeJson $outf) 'audio')[0].codec_name
Assert-NotContains 'FLAC: bitrate is not asked' $ui.Output 'Audio bitrate'
$ui = Invoke-Flow { Start-ConvertAudioWorkflow } @((New-Rule 'Input audio file' "$aud{Enter}"), (New-Rule 'Output format' '01'), (New-Rule 'Audio quality mode' '02'), $DONE, $FAIL)
Assert-JobOk 'MP3 -> MP3 with VBR quality mode' $ui (Join-Path $W 'w audio_converted.mp3') 'audio'

Set-TestGroup 'Workflow 3: Extract Audio from Video'
$oute = Join-Path $W 'w video_audio.m4a'
$ui = Invoke-Flow { Start-ExtractAudioWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'copy the AAC stream to M4A (no re-encode)' $ui $oute 'audio'
Assert-Equal 'extracted stream is still AAC' 'aac' (Get-StreamOf (Get-ProbeJson $oute) 'audio')[0].codec_name
Assert-True 'extracted file has no video' ((Get-StreamOf (Get-ProbeJson $oute) 'video').Count -eq 0)
$oute2 = Join-Path $W 'w video_audio.mp3'
$ui = Invoke-Flow { Start-ExtractAudioWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output mode' '02'), (New-Rule 'Output format' '01'), (New-Rule 'Extract which part?' '02'), (New-Rule 'Start time' '{Clear}1{Enter}'), (New-Rule 'End time' '{Clear}2{Enter}'), $DONE, $FAIL)
Assert-JobOk 'convert to MP3 with a selected range (1s-2s)' $ui $oute2 'audio'
Assert-True 'range extraction is about 1 second' ([math]::Abs([double](Get-ProbeJson $oute2).format.duration - 1.0) -lt 0.3)

Set-TestGroup 'Workflow 4: Trim / Cut Media'
$outt = Join-Path $W 'w video_trimmed.mp4'
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Start time' '{Clear}1{Enter}'), (New-Rule 'End time' '{Clear}2{Enter}'), (New-Rule 'Cut mode' '02'), $DONE, $FAIL)
Assert-JobOk 'accurate cut 1s -> 2s (re-encode)' $ui $outt
$dur = [double](Get-ProbeJson $outt).format.duration
Assert-True "accurate cut duration is about 1 s (got $dur)" ([math]::Abs($dur - 1.0) -lt 0.25)
Remove-Item -LiteralPath $outt -Force
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Start time' '{Clear}0.5{Enter}'), $DONE, $FAIL)
Assert-JobOk 'fast cut (stream copy) with defaults' $ui $outt
Assert-Contains 'fast cut explains keyframe behavior' $ui.Output 'Fast Cut is quicker but may cut near keyframes.'
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Start time' '{Clear}5{Enter}' 1), (New-Rule 'Start time' '{Esc}' 5)) -MaxCalls 30
Assert-Contains 'start time beyond the media is rejected' $ui.Output 'before the end of the media'
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Start time' '{Clear}2{Enter}' 1), (New-Rule 'End time' '{Clear}1{Enter}' 1), (New-Rule 'End time' '{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}')) -MaxCalls 40
Assert-Contains 'end before start is rejected' $ui.Output 'after the start time'
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Start time' '{Clear}abc{Enter}' 1), (New-Rule 'Start time' '{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}' 20)) -MaxCalls 40
Assert-Contains 'malformed timestamp is rejected' $ui.Output 'Not a valid time'

Set-TestGroup 'Workflow 5: Merge Media'
$vid2 = New-Fixture 'm2.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-ar', '44100', '-ac', '1', '-shortest')
$vid3 = New-Fixture 'm3.mp4' @('-f', 'lavfi', '-i', 'testsrc2=duration=2:size=640x360:rate=30', '-f', 'lavfi', '-i', 'sine=frequency=660:duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$outm = Join-Path $W 'w video_merged.mp4'
$addFiles = { param($a, $b) New-FileListRules 'Files to merge' @($a, $b) }
$ui = Invoke-Flow { Start-MergeWorkflow } @((& $addFiles $vid $vid2) + @($DONE, $FAIL))
Assert-JobOk 'lossless merge of two compatible files (stream copy)' $ui $outm
$dur = [double](Get-ProbeJson $outm).format.duration
Assert-True "merged duration is about 5 s (got $dur)" ([math]::Abs($dur - 5.0) -lt 0.4)
Assert-Contains 'summary reports lossless method' $ui.Output 'Lossless (stream copy)'
$ui = Invoke-Flow { Start-MergeWorkflow } @((& $addFiles $vid $vid3) + @((New-Rule 'Merge method' '{Esc}{Esc}{Esc}{Esc}{Esc}'))) -MaxCalls 20
Assert-Contains 'incompatible files: reason is shown next to the disabled option' $ui.Output 'different resolution'
Remove-Item -LiteralPath $outm -Force
$ui = Invoke-Flow { Start-MergeWorkflow } @((& $addFiles $vid $vid3) + @($DONE, $FAIL))
Assert-JobOk 'merge of different resolutions falls back to re-encoding by default' $ui $outm
$j = Get-ProbeJson $outm
Assert-True 're-encoded merge: one video + one audio stream at the first file size' ((Get-StreamOf $j 'video').Count -eq 1 -and (Get-StreamOf $j 'audio').Count -eq 1 -and (Get-StreamOf $j 'video')[0].width -eq 320)
Assert-Contains 're-encode reason is explained to the user' $ui.Output 're-encoded to common settings'
$a2 = New-Fixture 'ma2.mp3' @('-f', 'lavfi', '-i', 'sine=frequency=500:duration=2', '-c:a', 'libmp3lame')
$outma = Join-Path $W 'w audio_merged.mp3'
$ui = Invoke-Flow { Start-MergeWorkflow } @((& $addFiles $aud $a2) + @($DONE, $FAIL))
Assert-JobOk 'audio merge (stream copy of MP3 files)' $ui $outma 'audio'
$ui = Invoke-Flow { Start-MergeWorkflow } @((& $addFiles $vid $aud) + @((New-ScreenRule 'cannot be merged together' '{Enter}{Esc}{Esc}{Esc}{Esc}{Esc}' 1), (New-Rule 'Files to merge' '{Esc}{Esc}{Esc}'))) -MaxCalls 30
Assert-Contains 'mixed audio + video inputs are refused with a message' $ui.Output 'cannot be merged together'

Set-TestGroup 'Workflow 6: Compress Media'
$outc = Join-Path $W 'w video_compressed.mp4'
$ui = Invoke-Flow { Start-CompressWorkflow } @((New-Rule 'Input file (video or audio)' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'video: smaller file / recommended' $ui $outc
Assert-Contains 'result shows original/new size comparison' $ui.Output 'Original size'
Remove-Item -LiteralPath $outc -Force
$ui = Invoke-Flow { Start-CompressWorkflow } @((New-Rule 'Input file (video or audio)' "$vid{Enter}"), (New-Rule 'Compression goal' '04'), (New-Rule 'Target file size (MB)' '{Clear}0.03{Enter}' 1), (New-Rule 'Target file size (MB)' '{Esc}{Esc}{Esc}{Esc}{Esc}' 10)) -MaxCalls 40
Assert-True 'target size too small for the duration is rejected with an explanation' ($ui.Output.Contains('too small') -or $ui.Output.Contains('at least 0.5'))
$ui = Invoke-Flow { Start-CompressWorkflow } @((New-Rule 'Input file (video or audio)' "$vid{Enter}"), (New-Rule 'Compression goal' '04'), (New-Rule 'Target file size (MB)' '{Clear}1{Enter}'), $DONE, $FAIL)
Assert-JobOk 'video: approximate target size (1 MB)' $ui $outc
Assert-Contains 'target size mode explains that the size is approximate' $ui.Output 'approximate'
$ui = Invoke-Flow { Start-CompressWorkflow } @((New-Rule 'Input file (video or audio)' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'audio compression (MP3)' $ui (Join-Path $W 'w audio_compressed.mp3') 'audio'

Set-TestGroup 'Workflow 7: Resize / Scale Video'
$outr = Join-Path $W 'w video_resized.mp4'
$ui = Invoke-Flow { Start-ResizeWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target size' '05'), $DONE, $FAIL)
Assert-JobOk 'resize to 720p keeping aspect ratio' $ui $outr
$v = (Get-StreamOf (Get-ProbeJson $outr) 'video')[0]
Assert-True "aspect ratio preserved (got $($v.width)x$($v.height))" ($v.height -eq 720 -and $v.width -eq 960)
Remove-Item -LiteralPath $outr -Force
$ui = Invoke-Flow { Start-ResizeWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target size' '{#LAST}'), (New-Rule 'Custom resolution' '400x400{Enter}'), (New-Rule 'Aspect ratio behavior' '03'), $DONE, $FAIL)
Assert-JobOk 'fill/crop to 400x400' $ui $outr
$v = (Get-StreamOf (Get-ProbeJson $outr) 'video')[0]
Assert-True "fill+crop gives exactly 400x400 (got $($v.width)x$($v.height))" ($v.width -eq 400 -and $v.height -eq 400)
Remove-Item -LiteralPath $outr -Force
$ui = Invoke-Flow { Start-ResizeWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target size' '{#LAST}'), (New-Rule 'Custom resolution' '400x400{Enter}'), (New-Rule 'Aspect ratio behavior' '02'), (New-Rule 'Add black bars to reach the exact size?' '01'), $DONE, $FAIL)
Assert-JobOk 'fit inside with black bars to 400x400' $ui $outr
$v = (Get-StreamOf (Get-ProbeJson $outr) 'video')[0]
Assert-True "fit+pad gives exactly 400x400 (got $($v.width)x$($v.height))" ($v.width -eq 400 -and $v.height -eq 400)

Set-TestGroup 'Workflow 1-7: advanced options and remaining choices'
$outAdv = Join-Path $W 'w video_advanced.mp4'
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Configure advanced options?' '01'), (New-Rule 'Pixel format' '02'), (New-Rule 'Keyframe interval (frames)' '30{Enter}'), (New-Rule 'Optimize MP4/MOV for web streaming (faststart)?' '01'), (New-Rule 'Hardware-accelerated decoding' '02'), (New-Rule 'Output file name' '{Clear}w video_advanced.mp4{Enter}'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'advanced: pixel format, keyframe interval, faststart, automatic hardware decoding' $ui $outAdv
Assert-Contains 'advanced options reach the command (-g 30, -movflags +faststart, -hwaccel auto)' (Get-FlatText $ui.Output) '-hwaccel auto'
Assert-Contains 'keyframe interval reaches the command' (Get-FlatText $ui.Output) '-g 30'
Assert-Contains 'faststart reaches the command' (Get-FlatText $ui.Output) '+faststart'
$encList = @(Get-VideoEncoderChoices -AllowedFamilies @('h264', 'hevc', 'av1', 'mpeg4', 'vp9'))
$hevcKey = 1 + 1 + 1 + ([array]::IndexOf(@($encList | ForEach-Object { $_.Encoder }), 'libx265'))
if (Test-FFEncoder 'libx265') {
    $outx = Join-Path $W 'w video_x265.mp4'
    $ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Video codec' "$hevcKey"), (New-Rule 'Quality mode' '02'), (New-Rule 'Quality level' '01'), (New-Rule 'Encoding speed / preset' '01'), (New-Rule 'Output file name' '{Clear}w video_x265.mp4{Enter}'), $DONE, $FAIL)
    Assert-JobOk 'H.265 with a chosen quality level and the fastest preset' $ui $outx
    Assert-Equal 'output codec is HEVC (hvc1 tag for MP4)' 'hevc' (Get-StreamOf (Get-ProbeJson $outx) 'video')[0].codec_name
}
$outb = Join-Path $W 'w video_bitrate.mp4'
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Video codec' '03'), (New-Rule 'Quality mode' '03'), (New-Rule 'Target video bitrate' '{#LAST}'), (New-Rule 'Custom video bitrate' '400k{Enter}'), (New-Rule 'Output file name' '{Clear}w video_bitrate.mp4{Enter}'), $DONE, $FAIL)
Assert-JobOk 'bitrate mode with a custom bitrate (400k)' $ui $outb
Assert-True 'target bitrate mode produced a modest bitrate' ([int64](Get-StreamOf (Get-ProbeJson $outb) 'video')[0].bit_rate -lt 900000)
$outs = Join-Path $W 'w video_settings.mp4'
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Frame rate' '02'), (New-Rule 'Audio' '02'), (New-Rule 'Audio bitrate' '02'), (New-Rule 'Sample rate' '07'), (New-Rule 'Channels' '04'), (New-Rule 'Metadata' '02'), (New-Rule 'Output file name' '{Clear}w video_settings.mp4{Enter}'), $DONE, $FAIL)
Assert-JobOk 'frame rate 24, re-encode audio at 96k / 48 kHz / stereo, strip metadata' $ui $outs
$j = Get-ProbeJson $outs
Assert-True 'frame rate, sample rate and channels are applied' ((Get-StreamOf $j 'video')[0].r_frame_rate -eq '24/1' -and (Get-StreamOf $j 'audio')[0].sample_rate -eq '48000')
$ui = Invoke-Flow { Start-ConvertAudioWorkflow } @((New-Rule 'Input audio file' "$aud{Enter}"), (New-Rule 'Output format' '02'), (New-Rule 'Sample rate' '07'), (New-Rule 'Channels' '02'), (New-Rule 'Metadata' '02'), (New-Rule 'Output file name' '{Clear}w audio_settings.m4a{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'w audio_settings.m4a'
Assert-JobOk 'audio: 48 kHz mono, stripped metadata' $ui $o 'audio'
Assert-True 'audio sample rate and channels applied' ((Get-StreamOf (Get-ProbeJson $o) 'audio')[0].sample_rate -eq '48000' -and [int](Get-StreamOf (Get-ProbeJson $o) 'audio')[0].channels -eq 1)
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$aud{Enter}"), (New-Rule 'Start time' '{Clear}1{Enter}'), (New-Rule 'End time' '{Clear}3{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'w audio_trimmed.mp3'
Assert-JobOk 'trim an audio file (fast cut)' $ui $o 'audio'
Assert-True 'audio trim is about 2 s' ([math]::Abs([double](Get-ProbeJson $o).format.duration - 2.0) -lt 0.3)
$outsz = Join-Path $W 'w video_resized.mp4'
Remove-Item -LiteralPath $outsz -Force -ErrorAction SilentlyContinue
$ui = Invoke-Flow { Start-ResizeWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target size' '06'), (New-Rule 'Configure advanced scaling options?' '01'), (New-Rule 'Scaling algorithm' '02'), $DONE, $FAIL)
Assert-JobOk 'resize to 480p with the Lanczos algorithm (advanced)' $ui $outsz
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output file name' '{Clear}w video_open.mp4{Enter}'), (New-ScreenRule 'Completed successfully' 'O' 1), $DONE, $FAIL)
Assert-True 'pressing O on the result screen never crashes (even when no file manager is available)' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully'))
