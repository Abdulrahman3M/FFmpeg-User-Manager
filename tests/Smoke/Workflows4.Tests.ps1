# Workflow smoke tests (part 4): crop/rotate/flip, text & watermark, speed, HLS, streaming, media info, status.
$W = Get-TestWork
$vid = New-Fixture 'c video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
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
    param([scriptblock]$Menu, [string]$MenuMarker, [string]$Key, [object[]]$Rules, [int]$MaxCalls = 500)
    if ($Key -match '^\d$') { $Key = '0' + $Key }
    $all = @((New-ScreenRule $MenuMarker $Key 1), (New-ScreenRule $MenuMarker '{Esc}')) + $Rules
    return (Invoke-Flow $Menu $all -MaxCalls $MaxCalls)
}
function Get-Dims { param($Path) $v = (Get-StreamOf (Get-ProbeJson $Path) 'video')[0]; return "$($v.width)x$($v.height)" }
$TM = 'Crop the frame or change video orientation'
$OM = 'Add text or an image/logo overlay to a video'
$HM = 'Work with supported streams and create common HLS outputs'

Set-TestGroup 'Workflow 14: Crop / Rotate / Flip'
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Aspect ratio' '03'), $DONE, $FAIL)
$o = Join-Path $W 'c video_cropped.mp4'
Assert-JobOk 'crop to 1:1 (centered aspect preset)' $ui $o
Assert-Equal 'square crop is 240x240' '240x240' (Get-Dims $o)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Crop method' '03'), (New-Rule 'Crop width (px)' '{Clear}100{Enter}'), (New-Rule 'Crop height (px)' '{Clear}80{Enter}'), (New-Rule 'X position (px from the left)' '{Clear}10{Enter}'), (New-Rule 'Y position (px from the top)' '{Clear}20{Enter}'), $DONE, $FAIL)
Assert-JobOk 'manual crop 100x80 at (10,20)' $ui $o
Assert-Equal 'manual crop size' '100x80' (Get-Dims $o)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Crop method' '02'), (New-Rule 'Crop width (px)' '{Clear}200{Enter}'), (New-Rule 'Crop height (px)' '{Clear}100{Enter}'), $DONE, $FAIL)
Assert-JobOk 'centered crop 200x100' $ui $o
Assert-Equal 'centered crop size' '200x100' (Get-Dims $o)
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Crop method' '03'), (New-Rule 'Crop width (px)' '{Clear}900{Enter}' 1), (New-Rule 'Crop width (px)' '{Esc}' 5), (New-Rule 'Crop method' '{Esc}{Esc}{Esc}' 3)) -MaxCalls 40
Assert-Contains 'crop larger than the source is rejected' $ui.Output 'Cannot be larger than the source width'
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Crop method' '03'), (New-Rule 'Crop width (px)' '{Clear}200{Enter}'), (New-Rule 'Crop height (px)' '{Clear}100{Enter}'), (New-Rule 'X position (px from the left)' '{Clear}200{Enter}' 1), (New-Rule 'X position (px from the left)' '{Esc}' 5), (New-Rule 'Crop height (px)' '{Esc}{Esc}{Esc}' 5)) -MaxCalls 50
Assert-Contains 'impossible crop position (X + width > source) is rejected' $ui.Output 'exceeds the source width'
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '2' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'c video_rotated.mp4'
Assert-JobOk 'rotate 90 degrees clockwise' $ui $o
Assert-Equal 'rotated 90 -> 240x320' '240x320' (Get-Dims $o)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '2' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Rotation' '03'), $DONE, $FAIL)
Assert-JobOk 'rotate 180 degrees' $ui $o
Assert-Equal '180 keeps 320x240' '320x240' (Get-Dims $o)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-TransformWorkflow } $TM '2' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Rotation' '{#LAST}'), (New-Rule 'Custom angle (degrees)' '15{Enter}'), $DONE, $FAIL)
Assert-JobOk 'rotate by a custom angle (15 degrees)' $ui $o
$d = (Get-Dims $o) -split 'x'
Assert-True "custom angle enlarges the frame (got $(Get-Dims $o))" ([int]$d[0] -gt 320 -and [int]$d[1] -gt 240)
Remove-Item -LiteralPath $o -Force
foreach ($f in @(@('1', 'hflip'), @('2', 'vflip'), @('3', 'both'))) {
    $ui = Invoke-Sub { Start-TransformWorkflow } $TM '3' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Flip direction' $f[0]), (New-Rule 'Output file name' "{Clear}flip_$($f[1]).mp4{Enter}"), $DONE, $FAIL)
    $o = Join-Path $W "flip_$($f[1]).mp4"
    Assert-JobOk "flip $($f[1])" $ui $o
}
$ref = Join-Path $W 'flip_ref.mp4'
$null = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-y', '-hide_banner', '-loglevel', 'error', '-i', $vid, '-vf', 'hflip', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-an', $ref) -TimeoutSec 60
$pHF = Get-Psnr (Join-Path $W 'flip_hflip.mp4') $ref; $pVF = Get-Psnr (Join-Path $W 'flip_vflip.mp4') $ref
Assert-True ("horizontal flip matches FFmpeg's own hflip (PSNR $pHF) and differs from vflip (PSNR $pVF)") ($pHF -gt 30 -and $pVF -lt $pHF - 5)

Set-TestGroup 'Workflow 15: Text & Watermark'
if (-not (Test-FFFilter 'drawtext')) { Skip-Test 'Add Text' 'drawtext filter not available in this FFmpeg build' }
else {
    $txt = "Hello: 'World' [50%] (a,b);c=d \ Тест اختبار"
    $ui = Invoke-Sub { Start-OverlayWorkflow } $OM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Text to show' "$txt{Enter}"), (New-Rule 'Text size' '05'), (New-Rule 'Text color' '02'), (New-Rule 'Position' '04'), $DONE, $FAIL)
    $o = Join-Path $W 'c video_text.mp4'
    Assert-JobOk 'text with quotes, brackets, %, semicolon, backslash and Unicode' $ui $o
    Assert-True 'text was actually drawn (output differs from the source)' ((Get-Psnr $o $vid) -lt 40)
    Assert-True 'temporary text file is cleaned up' (@(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'fftui_*.txt' -ErrorAction SilentlyContinue).Count -eq 0)
    Remove-Item -LiteralPath $o -Force
    $ui = Invoke-Sub { Start-OverlayWorkflow } $OM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Text to show' 'Timed{Enter}'), (New-Rule 'Show from (start time)' '1{Enter}'), (New-Rule 'Show until (end time)' '2{Enter}'), (New-Rule 'Set an exact pixel position?' '01'), (New-Rule 'X position (px from the left)' '{Clear}30{Enter}'), (New-Rule 'Y position (px from the top)' '{Clear}30{Enter}'), $DONE, $FAIL)
    Assert-JobOk 'timed text (1s-2s) with an exact pixel position' $ui $o
    $ui = Invoke-Sub { Start-OverlayWorkflow } $OM '1' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Text to show' 'x{Enter}'), (New-Rule 'Show from (start time)' '2{Enter}'), (New-Rule 'Show until (end time)' '1{Enter}' 1), (New-Rule 'Show until (end time)' '{Esc}' 5), (New-Rule 'Show from (start time)' '{Esc}{Esc}{Esc}' 5)) -MaxCalls 50
    Assert-Contains 'text: end before start is rejected' $ui.Output 'after the start time'
}
$logo = New-Fixture 'logo.png' @('-f', 'lavfi', '-i', 'color=c=red:s=64x64:d=1', '-frames:v', '1')
$ui = Invoke-Sub { Start-OverlayWorkflow } $OM '2' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Image / logo file' "$logo{Enter}"), (New-Rule 'Opacity' '02'), $DONE, $FAIL)
$o = Join-Path $W 'c video_watermark.mp4'
Assert-JobOk 'watermark: bottom-right, 10%, 75% opacity' $ui $o
Assert-Equal 'watermarked video keeps its size' '320x240' (Get-Dims $o)
Assert-True 'watermark changed the picture' ((Get-Psnr $o $vid) -lt 45)
Assert-True 'audio is preserved' ((Get-StreamOf (Get-ProbeJson $o) 'audio').Count -eq 1)
Assert-True 'duration is not extended by the logo input' ([math]::Abs([double](Get-ProbeJson $o).format.duration - 3.0) -lt 0.3)
Remove-Item -LiteralPath $o -Force
$ui = Invoke-Sub { Start-OverlayWorkflow } $OM '2' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Image / logo file' "$logo{Enter}"), (New-Rule 'Position' '05'), (New-Rule 'Show from (start time)' '1{Enter}'), (New-Rule 'Show until (end time)' '2{Enter}'), $DONE, $FAIL)
Assert-JobOk 'watermark: centered, timed 1s-2s' $ui $o
$ui = Invoke-Sub { Start-OverlayWorkflow } $OM '2' @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Image / logo file' "$(Join-Path $W 'nofile.png'){Enter}" 1), (New-Rule 'Image / logo file' '{Esc}{Esc}' 5)) -MaxCalls 30
Assert-Contains 'watermark: missing logo file is rejected' $ui.Output 'File not found'

Set-TestGroup 'Workflow 16: Change Playback Speed'
$cases = @(@('1', 0.25, 12.0), @('2', 0.5, 6.0), @('3', 0.75, 4.0), @('5', 1.25, 2.4), @('6', 1.5, 2.0), @('7', 2.0, 1.5))
foreach ($c in $cases) {
    $o = Join-Path $W "c video_speed_$($c[1]).mp4"
    $ui = Invoke-Flow { Start-SpeedWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Playback speed' $c[0]), (New-Rule 'Output file name' "{Clear}c video_speed_$($c[1]).mp4{Enter}"), $DONE, $FAIL)
    Assert-JobOk ("speed {0}x" -f $c[1]) $ui $o
    $j = Get-ProbeJson $o
    $vd = [double](Get-StreamOf $j 'video')[0].duration; $ad = [double](Get-StreamOf $j 'audio')[0].duration
    Assert-True ("speed {0}x: video duration {1:0.00}s (expected {2}) and audio in sync ({3:0.00}s)" -f $c[1], $vd, $c[2], $ad) ([math]::Abs($vd - $c[2]) -lt ($c[2] * 0.12 + 0.15) -and [math]::Abs($vd - $ad) -lt 0.5)
}
$o = Join-Path $W 'c video_speed_4.mp4'
$ui = Invoke-Flow { Start-SpeedWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Playback speed' '{#LAST}'), (New-Rule 'Custom speed' '4{Enter}'), (New-Rule 'Output file name' '{Clear}c video_speed_4.mp4{Enter}'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'custom speed 4x (needs an atempo chain)' $ui $o
Assert-Contains '4x uses a chained atempo (2.0,2.0)' (Get-FlatText $ui.Output) 'atempo=2.0,atempo=2.0'
$j = Get-ProbeJson $o
Assert-True ("4x: audio and video stay in sync ({0:0.00}s vs {1:0.00}s)" -f [double](Get-StreamOf $j 'audio')[0].duration, [double](Get-StreamOf $j 'video')[0].duration) ([math]::Abs([double](Get-StreamOf $j 'audio')[0].duration - [double](Get-StreamOf $j 'video')[0].duration) -lt 0.4)
$o = Join-Path $W 'c video_speed_noaudio.mp4'
$ui = Invoke-Flow { Start-SpeedWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Playback speed' '07'), (New-Rule 'Audio behavior' '02'), (New-Rule 'Output file name' '{Clear}c video_speed_noaudio.mp4{Enter}'), $DONE, $FAIL)
Assert-JobOk 'speed with audio removed' $ui $o
Assert-True 'no audio stream when removal is chosen' ((Get-StreamOf (Get-ProbeJson $o) 'audio').Count -eq 0)
$audOnly = New-Fixture 'c tone.mp3' @('-f', 'lavfi', '-i', 'sine=frequency=500:duration=4', '-c:a', 'libmp3lame')
$ui = Invoke-Flow { Start-SpeedWorkflow } @((New-Rule 'Input media (video or audio)' "$audOnly{Enter}"), (New-Rule 'Playback speed' '07'), $DONE, $FAIL)
Assert-JobOk 'audio-only file at 2x' $ui (Join-Path $W 'c tone_speed.mp3') 'audio'
$ui = Invoke-Flow { Start-SpeedWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Playback speed' '{#LAST}'), (New-Rule 'Custom speed' '0{Enter}' 1), (New-Rule 'Custom speed' '{Esc}' 5), (New-Rule 'Playback speed' '{Esc}{Esc}{Esc}' 3)) -MaxCalls 40
Assert-Contains 'invalid speed (0) is rejected' $ui.Output 'at least 0.1'
$ui = Invoke-Flow { Start-SpeedWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Playback speed' '04' 1), (New-Rule 'Playback speed' '{Esc}{Esc}{Esc}' 5)) -MaxCalls 40
Assert-Contains 'speed 1.0x is refused as pointless' (Get-FlatText $ui.Output) 'changes nothing'

Set-TestGroup 'Workflow 17: Streaming / HLS'
$hd = Join-Path $W 'hls out dir'
$hlsSrc = New-Fixture 'c hls src.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '25', '-keyint_min', '25', '-sc_threshold', '0', '-c:a', 'aac', '-shortest')
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '1' @((New-Rule 'Input media file' "$hlsSrc{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$hd{Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), (New-Rule 'Segment duration' '01'), $DONE, $FAIL)
Assert-True 'HLS copy: completes' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
$segs = @(Get-ChildItem -LiteralPath $hd -Filter 'segment_*.ts' -ErrorAction SilentlyContinue)
Assert-True "HLS: playlist and $($segs.Count) segments are together in the chosen folder" ((Test-Path -LiteralPath (Join-Path $hd 'playlist.m3u8')) -and $segs.Count -ge 2)
$pl = Get-Content -LiteralPath (Join-Path $hd 'playlist.m3u8') -Raw
Assert-True 'HLS: playlist is a VOD playlist referencing the segments' ($pl -match '#EXT-X-PLAYLIST-TYPE:VOD' -and $pl -match 'segment_000\.ts' -and $pl -match '#EXT-X-ENDLIST')
Assert-True 'HLS: playlist is playable by FFmpeg' (Test-ValidMediaFile (Join-Path $hd 'playlist.m3u8') 'video')
$hd2 = Join-Path $W 'hls encode'
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '1' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$hd2{Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), (New-Rule 'Playlist name' 'stream{Enter}'), (New-Rule 'Segment duration' '01'), (New-Rule 'Encoding mode' '02'), (New-Rule 'Playlist type' '02'), $DONE, $FAIL)
Assert-True 'HLS re-encode + event playlist: completes' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
Assert-True 'HLS re-encode: custom playlist name is used' (Test-Path -LiteralPath (Join-Path $hd2 'stream.m3u8')) (Get-LastFrame $ui.Output)
Assert-True 'HLS event playlist type is written' ((Get-Content -LiteralPath (Join-Path $hd2 'stream.m3u8') -Raw) -match 'EXT-X-PLAYLIST-TYPE:EVENT')
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '1' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$hd{Enter}"), (New-Rule 'Playlist name' '{Enter}' 1), (New-Rule 'HLS files already exist in that folder' '01'), (New-Rule 'Playlist name' '{Clear}other{Enter}'), $DONE, $FAIL)
Assert-Contains 'HLS: existing playlist triggers the overwrite question' $ui.Output 'HLS files already exist in that folder'

# Network streams via a local HTTP server (MPEG-TS needs no seeking)
$tsDir = Join-Path $W 'www'; [void](New-Item -ItemType Directory -Path $tsDir -Force)
$null = New-Fixture 'live.ts' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=160x120:rate=25', '-f', 'lavfi', '-i', 'sine=duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', '-f', 'mpegts') $tsDir
$server = $null
try { $server = Start-TestHttpServer -Root $tsDir } catch { $server = $null }
if (-not $server) { Skip-Test 'network stream workflows' 'a local HTTP listener could not be started in this environment' }
else {
    $env:no_proxy = '127.0.0.1,localhost'; $env:NO_PROXY = '127.0.0.1,localhost'; $env:http_proxy = ''; $env:HTTP_PROXY = ''
    $url = $server.Url + '/live.ts'
    $ui = Invoke-Sub { Start-StreamingWorkflow } $HM '{#Inspect Stream}' @((New-Rule 'Stream address (URL) or file path' "$url{Enter}"), (New-ScreenRule 'Stream Information' '{Esc}'))
    Assert-Contains 'inspect stream: shows the stream information screen' $ui.Output 'Stream Information'
    Assert-True 'inspect stream: readable sections (Video/Audio) and no raw JSON' ($ui.Output.Contains('-- Video') -or $ui.Output.Contains('── Video')) 
    Assert-NotContains 'inspect stream: no raw ffprobe JSON is shown' $ui.Output '"codec_name"'
    $so = Join-Path $W 'saved stream.mkv'
    $ui = Invoke-Sub { Start-StreamingWorkflow } $HM '2' @((New-Rule 'Stream address (URL)' "$url{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$W{Enter}"), (New-Rule 'Output file name' '{Clear}saved stream.mkv{Enter}'), $DONE, $FAIL)
    Assert-JobOk 'save a network stream (HTTP MPEG-TS) to MKV' $ui $so
    $urlCred = $url.Replace('http://', 'http://someuser:secretpass@')
    $ui = Invoke-Sub { Start-StreamingWorkflow } $HM '2' @((New-Rule 'Stream address (URL)' "$urlCred{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$W{Enter}"), (New-Rule 'Output file name' '{Clear}saved cred.mkv{Enter}'), (New-ScreenRule '── Summary' '{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}'), $DONE, $FAIL) -MaxCalls 60
    $sumFrames = @($ui.Output -split '=====(?:FRAME|CLEAR)=====' | Where-Object { $_ -match '── Summary' })
Assert-True 'the stream summary was displayed' ($sumFrames.Count -gt 0)
Assert-True 'credentials in a stream URL are never echoed in the summary or job screens' (-not (@($sumFrames | Where-Object { $_.Contains('secretpass') }).Count)) 'password visible in summary'
    $server.Stop.Invoke()
}
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '2' @((New-Rule 'Stream address (URL)' 'file:///etc/hostname{Enter}' 1), (New-Rule 'Stream address (URL)' '{Esc}' 5)) -MaxCalls 30
Assert-Contains 'local file:// addresses are refused (network protocols only)' (Get-FlatText $ui.Output) 'not a supported network address'
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '2' @((New-Rule 'Stream address (URL)' 'just some text{Enter}' 1), (New-Rule 'Stream address (URL)' '{Esc}' 5)) -MaxCalls 30
Assert-Contains 'malformed address is rejected' (Get-FlatText $ui.Output) 'Enter a full address'
Assert-True 'protocol validation uses the installed FFmpeg build (http/https present)' ((Test-FFProtocol 'http') -or (Test-FFProtocol 'https'))
Assert-Equal 'credential masking helper' 'http://***@host/x' (Hide-UrlCredentials 'http://user:pw@host/x')

Set-TestGroup 'Workflow 18: Media Information'
$ui = Invoke-Flow { Start-MediaInfoWorkflow } @((New-Rule 'File to inspect' "$vid{Enter}"), (New-ScreenRule 'More actions' '{Enter}' 1), (New-ScreenRule 'what next' '{#Technical details}' 1), (New-ScreenRule 'Stream #0' '{Esc}' 1), (New-ScreenRule 'what next' '{#Back}'))
foreach ($sec in 'File', 'Video', 'Audio', 'Subtitles', 'Metadata', 'Streams') { Assert-Contains "info screen has a '$sec' section" $ui.Output ($sec + ' ') }
Assert-Contains 'info screen shows the codec in friendly form' $ui.Output 'H.264'
Assert-Contains 'technical details view is available' $ui.Output 'Stream #0 (video)'
Assert-Contains 'technical details list stream fields' $ui.Output 'codec_name'
Assert-NotContains 'no raw JSON braces/quotes dump' $ui.Output '"codec_name"'
$bad = Join-Path $W 'notmedia.txt'; [System.IO.File]::WriteAllText($bad, 'hello')
$ui = Invoke-Flow { Start-MediaInfoWorkflow } @((New-Rule 'File to inspect' "$bad{Enter}" 1), (New-Rule 'File to inspect' '{Esc}' 5)) -MaxCalls 30
Assert-Contains 'media info: unreadable file gives a clear error' $ui.Output 'could not be read as media'

Set-TestGroup 'Workflow 19: FFmpeg Status / Settings'
# winget is hidden so a real winget (present on Windows machines) cannot change what the update check shows
Set-FFManagerHooks -FindCommand { param($n) if ($n -eq 'winget') { return $null }; $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return [string]$c.Source } }
$ui = Invoke-Ui { Show-FFmpegStatus } '0102{Enter}0305'
Set-FFManagerHooks -Reset
foreach ($needle in @('FFmpeg Status / Settings', [System.IO.Path]::GetFileName((Get-FFmpegPath)), [System.IO.Path]::GetFileName((Get-FFprobePath)), (Get-FFmpegInfo).Version, 'PowerShell', 'Terminal', 'Accelerators', 'Capabilities', 'Updates', 'Re-scan capabilities', 'Check for updates', 'Re-detect FFmpeg paths')) { Assert-Contains "status shows: $needle" $ui.Output $needle }
Assert-True 'status actions (re-scan, update check, re-detect, back) run without errors' ($ui.Error -eq '') $ui.Error
Assert-Contains 'update check without winget is a non-fatal notice' $ui.Output 'Update status'
Assert-True 'capabilities are still loaded after a re-scan' ((Get-FFCapabilityStatus).Loaded)
