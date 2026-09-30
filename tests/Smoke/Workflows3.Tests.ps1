# Workflow smoke tests (part 3): audio tools, subtitle tools, frame rate, filters.
$W = Get-TestWork
$vid = New-Fixture 'a video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$aud = New-Fixture 'a audio.mp3' @('-f', 'lavfi', '-i', 'sine=frequency=880:duration=4', '-af', 'volume=0.3', '-c:a', 'libmp3lame')
$DONE = New-ScreenRule 'Completed successfully' '{#Main menu}'
$FAIL = New-ScreenRule 'Processing failed\.' '{#Back}'
function Assert-JobOk {
    param([string]$Name, $Ui, [string]$Output, [string]$Type = 'video')
    $ok = ($Ui.Error -eq '') -and $Ui.Output.Contains('Completed successfully')
    $why = ''; if (-not $ok) { $why = "error=[$($Ui.Error)]`n" + (Get-LastFrame $Ui.Output) }
    Assert-True "$Name : job completes" $ok $why
    if ($Output) { Assert-True "$Name : output is valid ($([System.IO.Path]::GetFileName($Output)))" (Test-ValidMediaFile $Output $(if ($Type -eq 'any') { '' } else { $Type })) }
}
function Invoke-Sub {
    # Runs a submenu workflow: presses the menu key once, then Esc to leave the submenu after the job.
    param([scriptblock]$Menu, [string]$MenuMarker, [string]$Key, [object[]]$Rules, [int]$MaxCalls = 500)
    if ($Key -match '^\d$') { $Key = '0' + $Key }
    $all = @((New-ScreenRule $MenuMarker $Key 1), (New-ScreenRule $MenuMarker '{Esc}')) + $Rules
    return (Invoke-Flow $Menu $all -MaxCalls $MaxCalls)
}
$AT = 'Adjust volume, sample rate, channels'
$ST = 'Extract, add, remove, copy or burn subtitle'
$FM = 'Apply common filters, or explore every filter'

Set-TestGroup 'Workflow 10: Audio Tools'
$srcMean = Get-MeanVolume $aud
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '1' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'a audio_volume.mp3'
Assert-JobOk 'volume: preset 125%' $ui $o 'audio'
$diff = (Get-MeanVolume $o) - $srcMean
Assert-True ("volume +25% raises the level by about 1.9 dB (measured {0:0.00} dB)" -f $diff) ($diff -gt 1.4 -and $diff -lt 2.5)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '1' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), (New-Rule 'How do you want to change the volume?' '03'), (New-Rule 'Volume change (dB)' '{Clear}-6{Enter}'), $DONE, $FAIL)
Assert-JobOk 'volume: -6 dB' $ui $o 'audio'
$diff = (Get-MeanVolume $o) - $srcMean
Assert-True ("-6 dB lowers the level by about 6 dB (measured {0:0.00} dB)" -f $diff) ($diff -lt -5.3 -and $diff -gt -6.7)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '1' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), (New-Rule 'How do you want to change the volume?' '02'), (New-Rule 'Volume (%)' '{Clear}50{Enter}'), $DONE, $FAIL)
Assert-JobOk 'volume: 50 percent' $ui $o 'audio'
Assert-True 'volume 50% lowers the level by about 6 dB' ((Get-MeanVolume $o) - $srcMean -lt -5.3)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '1' @((New-Rule 'Input file (audio or video with audio)' "$vid{Enter}"), $DONE, $FAIL)
$ov = Join-Path $W 'a video_volume.mp4'
Assert-JobOk 'volume on a video keeps the picture (video stream copied)' $ui $ov
Assert-True 'video track kept as H.264 (copy) and audio re-encoded' ((Get-StreamOf (Get-ProbeJson $ov) 'video')[0].codec_name -eq 'h264' -and (Get-StreamOf (Get-ProbeJson $ov) 'audio').Count -eq 1)
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '1' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), (New-Rule 'How do you want to change the volume?' '02'), (New-Rule 'Volume (%)' '{Clear}0{Enter}' 1), (New-Rule 'Volume (%)' '{Esc}' 3), (New-Rule 'How do you want to change the volume?' '{Esc}{Esc}{Esc}' 3)) -MaxCalls 30
Assert-Contains 'volume: invalid percentage is rejected' $ui.Output 'at least 1'

$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '2' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'a audio_normalized.mp3'
Assert-JobOk 'normalize loudness (two-pass)' $ui $o 'audio'
Assert-Contains 'normalization shows an Analysis stage' $ui.Output 'Analysis'
Assert-Contains 'normalization shows a Processing stage' $ui.Output 'Processing'
$lufs = Get-IntegratedLoudness $o
Assert-True ("integrated loudness is close to the -16 LUFS target (measured $lufs)") ($null -ne $lufs -and $lufs -gt -17.5 -and $lufs -lt -14.5)
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '3' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), (New-Rule 'New sample rate' '06'), $DONE, $FAIL)
$o = Join-Path $W 'a audio_samplerate.mp3'
Assert-JobOk 'change sample rate to 48000 Hz' $ui $o 'audio'
Assert-Equal 'sample rate is 48000' '48000' (Get-StreamOf (Get-ProbeJson $o) 'audio')[0].sample_rate
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '4' @((New-Rule 'Input file (audio or video with audio)' "$aud{Enter}"), (New-Rule 'Channel layout' '02'), $DONE, $FAIL)
$o = Join-Path $W 'a audio_channels.mp3'
Assert-JobOk 'change channels mono -> stereo' $ui $o 'audio'
Assert-Equal 'output is stereo' 2 ([int](Get-StreamOf (Get-ProbeJson $o) 'audio')[0].channels)
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '5' @((New-Rule 'Input audio file' "$aud{Enter}"), (New-Rule 'Speed' '07'), $DONE, $FAIL)
$o = Join-Path $W 'a audio_speed.mp3'
Assert-JobOk 'audio tempo 2.0x (pitch kept)' $ui $o 'audio'
Assert-True 'tempo 2x halves the duration' ([math]::Abs([double](Get-ProbeJson $o).format.duration - 2.0) -lt 0.3)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '5' @((New-Rule 'Input audio file' "$aud{Enter}"), (New-Rule 'Speed method' '02'), (New-Rule 'Speed' '02'), $DONE, $FAIL)
Assert-JobOk 'audio speed + pitch 0.5x' $ui $o 'audio'
Assert-True 'speed+pitch 0.5x doubles the duration' ([math]::Abs([double](Get-ProbeJson $o).format.duration - 8.0) -lt 0.6)
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '5' @((New-Rule 'Input audio file' "$vid{Enter}" 1), (New-Rule 'Input audio file' '{Esc}{Esc}{Esc}' 5)) -MaxCalls 30
Assert-Contains 'audio-speed tool refuses a video file with guidance' (Get-FlatText $ui.Output) 'changes audio only'
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '6' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'a video_noaudio.mp4'
Assert-JobOk 'remove audio from video' $ui $o
Assert-True 'no audio stream and video untouched (h264)' ((Get-StreamOf (Get-ProbeJson $o) 'audio').Count -eq 0 -and (Get-StreamOf (Get-ProbeJson $o) 'video')[0].codec_name -eq 'h264')
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '7' @((New-Rule 'Video file' "$vid{Enter}"), (New-Rule 'Audio file to use' "$aud{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'a video_newaudio.mp4'
Assert-JobOk 'replace audio track' $ui $o
Assert-True 'replaced: exactly one audio stream, video copied' ((Get-StreamOf (Get-ProbeJson $o) 'audio').Count -eq 1 -and (Get-StreamOf (Get-ProbeJson $o) 'video')[0].codec_name -eq 'h264')
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '7' @((New-Rule 'Video file' "$vid{Enter}"), (New-Rule 'Audio file to use' "$aud{Enter}"), (New-Rule 'What should happen to the existing audio?' '02'), (New-Rule 'Audio start offset (seconds)' '{Clear}0.5{Enter}'), $DONE, $FAIL)
Assert-JobOk 'add an additional audio track (with 0.5 s offset)' $ui $o
Assert-Equal 'added: two audio streams' 2 (Get-StreamOf (Get-ProbeJson $o) 'audio').Count

Set-TestGroup 'Workflow 11: Subtitle Tools'
$srt = Join-Path $W 'sub one.srt'; [System.IO.File]::WriteAllText($srt, "1`n00:00:00,000 --> 00:00:01,500`nHello world`n`n2`n00:00:01,600 --> 00:00:02,900`nSecond line`n")
$srt2 = Join-Path $W 'sub two.srt'; [System.IO.File]::WriteAllText($srt2, "1`n00:00:00,000 --> 00:00:01,500`nBonjour`n")
$mkvSub = New-Fixture 'a sub.mkv' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-i', $srt, '-i', $srt2, '-map', '0:v', '-map', '1:a', '-map', '2:s', '-map', '3:s', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-c:s', 'srt', '-metadata:s:s:0', 'language=eng', '-metadata:s:s:1', 'language=fra', '-shortest')
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '1' @((New-Rule 'Input file with subtitles' "$mkvSub{Enter}"), (New-Rule 'Subtitle stream' '02'), $DONE, $FAIL)
$o = Join-Path $W 'a sub_subtitle.srt'
Assert-True 'extract subtitle: completes' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
Assert-True 'extract subtitle: file contains the second stream (French)' ((Test-Path -LiteralPath $o) -and ((Get-Content -LiteralPath $o -Raw) -match 'Bonjour'))
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '1' @((New-Rule 'Input file with subtitles' "$vid{Enter}" 1), (New-Rule 'Input file with subtitles' '{Esc}{Esc}{Esc}' 5)) -MaxCalls 30
Assert-Contains 'extract subtitle: file without subtitles is rejected clearly' $ui.Output 'contains no subtitle streams'
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '2' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Subtitle file' "$srt{Enter}"), (New-Rule 'Track title' 'English{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'a video_subbed.mp4'
Assert-JobOk 'mux subtitle into MP4 (mov_text)' $ui $o
$j = Get-ProbeJson $o
$subs = Get-StreamOf $j 'subtitle'
Assert-True 'muxed: one subtitle stream (mov_text, language eng), video/audio copied' ($subs.Count -eq 1 -and $subs[0].codec_name -eq 'mov_text' -and $subs[0].tags.language -eq 'eng' -and (Get-StreamOf $j 'video')[0].codec_name -eq 'h264')
Assert-Contains 'mux explains that streams are copied' $ui.Output 'copied without re-encoding'
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '3' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Subtitle file' "$srt{Enter}"), (New-Rule 'Subtitle text size' '03'), $DONE, $FAIL)
$o = Join-Path $W 'a video_subtitled.mp4'
Assert-JobOk 'burn subtitles from an external file' $ui $o
Assert-Contains 'burn explains that video is re-encoded' $ui.Output 'requires re-encoding the video'
Assert-True 'burned output has no subtitle stream (text is in the picture)' ((Get-StreamOf (Get-ProbeJson $o) 'subtitle').Count -eq 0)
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '3' @((New-Rule 'Input video' "$mkvSub{Enter}"), (New-Rule 'Subtitle source' '02'), (New-Rule 'Which subtitle stream?' '02'), (New-Rule 'Output format' '02'), $DONE, $FAIL)
Assert-JobOk 'burn an embedded subtitle stream' $ui (Join-Path $W 'a sub_subtitled.mkv')
$srtWeird = Join-Path $W "we'ird: [sub], name;x=1.srt"; [System.IO.File]::WriteAllText($srtWeird, "1`n00:00:00,000 --> 00:00:01,500`nHi`n")
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '3' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Subtitle file' "$srtWeird{Enter}"), (New-Rule 'Output file name' '{Clear}weird_burn.mp4{Enter}'), $DONE, $FAIL)
Assert-JobOk 'burn with a subtitle path containing apostrophe, colon, brackets, comma, semicolon, equals' $ui (Join-Path $W 'weird_burn.mp4')
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '4' @((New-Rule 'Input file with subtitles' "$mkvSub{Enter}"), (New-Rule 'Output file name' '{Clear}nosubs.mkv{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'nosubs.mkv'
Assert-JobOk 'remove subtitle streams' $ui $o
Assert-True 'no subtitle streams left, video + audio intact' ((Get-StreamOf (Get-ProbeJson $o) 'subtitle').Count -eq 0 -and (Get-StreamOf (Get-ProbeJson $o) 'video').Count -eq 1 -and (Get-StreamOf (Get-ProbeJson $o) 'audio').Count -eq 1)
$ui = Invoke-Sub { Start-SubtitleToolsWorkflow } $ST '5' @((New-Rule 'Input file with subtitles' "$mkvSub{Enter}"), (New-Rule 'Subtitle streams to keep' '0102{#LAST}' 1), (New-Rule 'Output file name' '{Clear}subset.mkv{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'subset.mkv'
Assert-JobOk 'copy selected subtitle streams (keep stream 2 only)' $ui $o
$subs = Get-StreamOf (Get-ProbeJson $o) 'subtitle'
Assert-True 'exactly the selected subtitle stream remains' ($subs.Count -eq 1)

Set-TestGroup 'Workflow 12: Change Frame Rate'
$ui = Invoke-Flow { Start-FrameRateWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target frame rate' '{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'a video_fps.mp4'
Assert-JobOk 'standard 25 -> 30 FPS' $ui $o
Assert-Equal 'output runs at 30 FPS' '30/1' (Get-StreamOf (Get-ProbeJson $o) 'video')[0].r_frame_rate
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Flow { Start-FrameRateWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target frame rate' '{#LAST}'), (New-Rule 'Custom frame rate' '12{Enter}'), (New-Rule 'Conversion method' '02'), $DONE, $FAIL)
Assert-JobOk 'motion interpolation 25 -> 12 FPS (explicitly selected)' $ui $o
Assert-Contains 'interpolation warns that it is slow' $ui.Output 'Motion interpolation is slow'
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Flow { Start-FrameRateWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Target frame rate' '02' 1), (New-Rule 'Target frame rate' '{Esc}{Esc}{Esc}' 5)) -MaxCalls 30
Assert-Contains 'choosing the current frame rate is rejected' (Get-FlatText $ui.Output) 'already runs at 25 FPS'

Set-TestGroup 'Workflow 13: Filters & Color'

$srcY = Get-VideoStat $vid 'YAVG'; $srcS = Get-VideoStat $vid 'SATAVG'
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Which effects do you want to apply?' '{#LAST}'), $DONE, $FAIL)
$o = Join-Path $W 'a video_filtered.mp4'
Assert-JobOk 'brightness +0.1 (default effect)' $ui $o
Assert-True 'output is brighter than the source' ((Get-VideoStat $o 'YAVG') -gt $srcY + 5)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Which effects do you want to apply?' '050607{#LAST}'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'combined: brightness + grayscale + sharpen + blur' $ui $o
Assert-True 'grayscale removes color (saturation near zero)' ((Get-VideoStat $o 'SATAVG') -lt 3 -and $srcS -gt 20)
Assert-Contains 'filter chain is summarized as readable labels' (Get-FlatText $ui.Output) 'Brightness +0.1, Grayscale, Sharpen, Blur'
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Which effects do you want to apply?' '010809{#LAST}'), (New-Rule 'Fade-in length (seconds)' '{Clear}1{Enter}'), (New-Rule 'Fade-out length (seconds)' '{Clear}1{Enter}'), $DONE, $FAIL)
Assert-JobOk 'fade in + fade out' $ui $o
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Which effects do you want to apply?' '02030104{#LAST}'), (New-Rule 'Contrast' '02'), $DONE, $FAIL)
Assert-JobOk 'contrast + saturation + gamma (multiple eq controls)' $ui $o
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Which effects do you want to apply?' '{#LAST}'), (New-Rule 'Add an expert filter expression?' '01'), (New-Rule 'Expert filter expression' 'hue=h=40,vignette{Enter}'), $DONE, $FAIL)
Assert-JobOk 'validated expert filter expression is accepted' $ui $o
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Which effects do you want to apply?' '{#LAST}'), (New-Rule 'Add an expert filter expression?' '01'), (New-Rule 'Expert filter expression' 'notafilter=1{Enter}' 1), (New-Rule 'Expert filter expression' '{Esc}' 3), (New-Rule 'Add an expert filter expression?' '{Esc}{Esc}{Esc}' 3)) -MaxCalls 40
Assert-Contains 'invalid expert filter is rejected with FFmpeg explanation (no crash)' $ui.Output 'FFmpeg rejected this filter'
$ui = Invoke-Sub { Start-FiltersWorkflow } $FM '2' @((New-ScreenRule 'Search>' 'palette{Enter}' 1), (New-ScreenRule 'palettegen' '{Esc}'), (New-ScreenRule 'Filter Browser' '{Esc}' )) -MaxCalls 40
Assert-Contains 'filter browser lists filters discovered from the installed build' $ui.Output 'palettegen'
