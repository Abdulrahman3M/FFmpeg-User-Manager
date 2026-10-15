# Workflow smoke tests (part 5): the tools added for full FFmpeg category coverage, driven through the real wizard
# with real FFmpeg: remux & streams, metadata & chapters, images & slideshows, audio effects, video enhancement,
# analysis, batch conversion, advanced tools and stream output.
$W = Get-TestWork
$vid = New-Fixture 'n video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$aud = New-Fixture 'n audio.mp3' @('-f', 'lavfi', '-i', 'sine=frequency=880:duration=4', '-af', 'volume=0.3', '-c:a', 'libmp3lame')
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
    # Opens a submenu option (number or {#label} macro), runs the wizard rules, then leaves the submenu with Esc.
    param([scriptblock]$Menu, [string]$MenuMarker, [string]$Key, [object[]]$Rules, [int]$MaxCalls = 500)
    if ($Key -match '^\d$') { $Key = '0' + $Key }
    $all = @((New-ScreenRule $MenuMarker $Key 1), (New-ScreenRule $MenuMarker '{Esc}')) + $Rules
    return (Invoke-Flow $Menu $all -MaxCalls $MaxCalls -Height 70)
}
function Get-Tag { param($Json, [string]$Name) $t = $Json.format.tags; if ($t -and $t.PSObject.Properties[$Name]) { return [string]$t.$Name }; return '' }

# ---- Remux & Streams --------------------------------------------------------------------------------------------------
Set-TestGroup 'Remux & Streams'
$RM = 'Change containers and choose tracks without re-encoding'
$ui = Invoke-Sub { Start-RemuxStreamsWorkflow } $RM '{#Remux (Change}' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'New container' '{#MKV}'), $DONE, $FAIL)
$o = Join-Path $W 'n video_remux.mkv'
Assert-JobOk 'MP4 -> MKV remux' $ui $o
$j = Get-ProbeJson $o
Assert-True 'remux copies the streams (H.264 + AAC, 320x240) into Matroska' (($j.format.format_name -match 'matroska') -and (Get-StreamOf $j 'video')[0].codec_name -eq 'h264' -and (Get-StreamOf $j 'audio')[0].codec_name -eq 'aac' -and (Get-StreamOf $j 'video')[0].width -eq 320)
Assert-Contains 'remux summary states that nothing is re-encoded' $ui.Output 'None (streams are copied)'
Assert-Contains 'remux options have descriptions' $ui.Output 'Put the same picture and sound into another file type'
$multi = New-Fixture 'n multi.mkv' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=160x120:rate=10', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', '-f', 'lavfi', '-i', 'sine=frequency=880:duration=2', '-map', '0', '-map', '1', '-map', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=fra')
$ui = Invoke-Sub { Start-RemuxStreamsWorkflow } $RM '{#Keep Selected}' @((New-Rule 'Input media file' "$multi{Enter}"), (New-Rule 'Which streams do you want to keep?' '02{#Continue}'), $DONE, $FAIL)
$o = Join-Path $W 'n multi_streams.mkv'
Assert-JobOk 'keep video + second audio only' $ui $o
$j = Get-ProbeJson $o
Assert-True 'only one audio stream remains and it is the French one' ((Get-StreamOf $j 'audio').Count -eq 1 -and (Get-StreamOf $j 'audio')[0].tags.language -eq 'fra')
$ui = Invoke-Sub { Start-RemuxStreamsWorkflow } $RM '{#Set Track Language}' @((New-Rule 'Input media file' "$multi{Enter}"), (New-Rule 'Which track do you want to label?' '{#Audio #2}'), (New-Rule 'Language code (3 letters)' 'deu{Enter}'), (New-Rule 'Make this the default track of its kind?' '01'), $DONE, $FAIL)
$o = Join-Path $W 'n multi_tagged.mkv'
Assert-JobOk 'label track 2 as German and make it default' $ui $o
$j = Get-ProbeJson $o
$a = Get-StreamOf $j 'audio'
Assert-True 'language tag written and default flag moved' ($a[1].tags.language -eq 'deu' -and $a[1].disposition.default -eq 1 -and $a[0].disposition.default -eq 0)

# ---- Metadata & Chapters ---------------------------------------------------------------------------------------------
Set-TestGroup 'Metadata & Chapters'
$MM = 'Edit the labels stored inside media files'
$ui = Invoke-Sub { Start-MetadataChaptersWorkflow } $MM '{#Edit Metadata}' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'Title' 'My Holiday{Enter}'), (New-Rule 'Artist / Author' 'Jane Doe{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'n video_tagged.mp4'
Assert-JobOk 'edit title and artist' $ui $o
$j = Get-ProbeJson $o
Assert-True 'title and artist are stored, streams untouched' ((Get-Tag $j 'title') -eq 'My Holiday' -and (Get-Tag $j 'artist') -eq 'Jane Doe' -and (Get-StreamOf $j 'video')[0].codec_name -eq 'h264')
$ui = Invoke-Sub { Start-MetadataChaptersWorkflow } $MM '{#Edit Metadata}' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'Output file name' '{Clear}n video_empty.mp4{Enter}'), (New-ScreenRule 'Nothing to change' '{Enter}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}')) -MaxCalls 80
Assert-Contains 'editing with every field empty is refused with an explanation' (Get-FlatText $ui.Output) 'Nothing to change'
$ui = Invoke-Sub { Start-MetadataChaptersWorkflow } $MM '{#Remove Metadata}' @((New-Rule 'Input media file' "$o{Enter}"), (New-Rule 'Output file name' '{Clear}n video_clean.mp4{Enter}'), $DONE, $FAIL)
$o2 = Join-Path $W 'n video_clean.mp4'
Assert-JobOk 'strip all metadata' $ui $o2
Assert-Equal 'title is gone after stripping' '' (Get-Tag (Get-ProbeJson $o2) 'title')
$ui = Invoke-Sub { Start-MetadataChaptersWorkflow } $MM '{#Add Chapters}' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'Chapter list' '00:00:00 Intro; 00:00:01 Middle; 00:00:02 End{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'n video_chapters.mp4'
Assert-JobOk 'three chapters' $ui $o
$chap = (Invoke-ExternalCapture -FilePath (Get-FFprobePath) -Arguments @('-v', 'error', '-print_format', 'json', '-show_chapters', $o) -TimeoutSec 30).StdOut | ConvertFrom-Json
Assert-True 'three chapters with the given titles are in the file' (@($chap.chapters).Count -eq 3 -and $chap.chapters[1].tags.title -eq 'Middle')
$ui = Invoke-Sub { Start-MetadataChaptersWorkflow } $MM '{#Add Chapters}' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'Chapter list' '00:00:02 B; 00:00:01 A{Enter}' 1), (New-Rule 'Chapter list' '{Esc}{Esc}{Esc}' 10)) -MaxCalls 40
Assert-Contains 'chapters out of order are rejected' $ui.Output 'increasing order'
$png = New-Fixture 'n cover.png' @('-f', 'lavfi', '-i', 'color=c=red:s=200x200:d=1', '-frames:v', '1')
$ui = Invoke-Sub { Start-MetadataChaptersWorkflow } $MM '{#Attach Cover}' @((New-Rule 'Audio file' "$aud{Enter}"), (New-Rule 'Cover picture' "$png{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'n audio_cover.mp3'
Assert-JobOk 'cover art attached to an MP3' $ui $o 'any'
$j = Get-ProbeJson $o
Assert-True 'the MP3 now has an audio stream and an attached picture' ((Get-StreamOf $j 'audio').Count -eq 1 -and (Get-StreamOf $j 'video').Count -eq 1 -and (Get-StreamOf $j 'video')[0].disposition.attached_pic -eq 1)

# ---- Images & Slideshows ---------------------------------------------------------------------------------------------
Set-TestGroup 'Images & Slideshows'
$IM = 'Create videos from pictures or audio'
$p1 = New-Fixture 'p1.png' @('-f', 'lavfi', '-i', 'color=c=red:s=320x200:d=1', '-frames:v', '1')
$p2 = New-Fixture 'p2.png' @('-f', 'lavfi', '-i', 'color=c=green:s=200x320:d=1', '-frames:v', '1')
$p3 = New-Fixture 'p3.png' @('-f', 'lavfi', '-i', 'color=c=blue:s=320x320:d=1', '-frames:v', '1')
$ui = Invoke-Sub { Start-ImagesAndVisualsWorkflow } $IM '{#Pictures to Slideshow}' ((New-FileListRules 'Pictures for the slideshow' @($p1, $p2, $p3)) + @((New-Rule 'How long should each picture stay on screen?' '{#LAST}'), (New-Rule 'Seconds per picture' '1{Enter}'), (New-Rule 'Video size' '{#1280x720}'), $DONE, $FAIL))
$o = Join-Path $W 'p1_slideshow.mp4'
Assert-JobOk 'three pictures, 1 second each, 1280x720' $ui $o
$j = Get-ProbeJson $o
$dur = [double]$j.format.duration
Assert-True "slideshow is about 3 s long (got $dur) at 1280x720" ([math]::Abs($dur - 3.0) -lt 0.4 -and (Get-StreamOf $j 'video')[0].width -eq 1280 -and (Get-StreamOf $j 'video')[0].height -eq 720)
$seq = Join-Path $W 'seq'; [void](New-Item -ItemType Directory -Path $seq -Force)
$null = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=10:duration=1', (Join-Path $seq 'frame_%04d.png')) -TimeoutSec 60
$pat = Join-Path $seq 'frame_%04d.png'
$ui = Invoke-Sub { Start-ImagesAndVisualsWorkflow } $IM '{#Numbered Image Sequence}' @((New-Rule 'Image sequence pattern' "$pat{Enter}"), (New-Rule 'Frame rate of the video' '{#12 FPS}'), $DONE, $FAIL)
$o = Join-Path $seq 'sequence_video.mp4'
Assert-JobOk 'image sequence to video' $ui $o
Assert-True 'sequence video has 10 frames at 12 FPS (about 0.83 s)' ([math]::Abs([double](Get-ProbeJson $o).format.duration - 0.833) -lt 0.2)
$ui = Invoke-Sub { Start-ImagesAndVisualsWorkflow } $IM '{#Numbered Image Sequence}' @((New-Rule 'Image sequence pattern' "$(Join-Path $seq 'nothing_%04d.png'){Enter}"), (New-Rule 'Number of the first picture' '{Enter}'), (New-Rule 'Number of the first picture' '{Esc}{Esc}{Esc}{Esc}' 10)) -MaxCalls 40
Assert-Contains 'a sequence that does not exist is rejected' $ui.Output 'No picture with that number was found'
$ui = Invoke-Sub { Start-ImagesAndVisualsWorkflow } $IM '{#Audio to Video}' @((New-Rule 'Audio file' "$aud{Enter}"), (New-Rule 'What should the picture show?' '{#Plain black}'), (New-Rule 'Video size' '{#1280x720}'), (New-ScreenRule 'Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
$o = Join-Path $W 'n audio_visual.mp4'
Assert-JobOk 'audio to a black-screen video' $ui $o
$j = Get-ProbeJson $o
Assert-True 'result has one video and one audio stream of about 4 s' ((Get-StreamOf $j 'video').Count -eq 1 -and (Get-StreamOf $j 'audio').Count -eq 1 -and [math]::Abs([double]$j.format.duration - 4.0) -lt 0.6) ('video streams={0} audio streams={1} duration={2}' -f @(Get-StreamOf $j 'video').Count, @(Get-StreamOf $j 'audio').Count, $j.format.duration)
$ui = Invoke-Sub { Start-ImagesAndVisualsWorkflow } $IM '{#Audio to Video}' @((New-Rule 'Audio file' "$aud{Enter}"), (New-Rule 'What should the picture show?' '{#Animated sound waves}'), (New-Rule 'Video size' '{#1280x720}'), (New-Rule 'Output file name' '{Clear}n audio_waves.mp4{Enter}'), $DONE, $FAIL)
Assert-JobOk 'audio to a waveform video' $ui (Join-Path $W 'n audio_waves.mp4')
$ui = Invoke-Sub { Start-ImagesAndVisualsWorkflow } $IM '{#Contact Sheet}' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'n video_sheet.jpg'
Assert-JobOk 'contact sheet of a video' $ui $o 'video'
$v = (Get-StreamOf (Get-ProbeJson $o) 'video')[0]
Assert-True "the sheet is one picture about 4 thumbnails wide (got $($v.width)x$($v.height))" ($v.width -ge 1200 -and $v.height -ge 700)

# ---- Audio effects ---------------------------------------------------------------------------------------------------
Set-TestGroup 'Audio effects'
$AT = 'Adjust volume, sample rate, channels'
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Fade In}' @((New-Rule 'Input file (audio, or video with audio)' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'fade in and out (2 s each)' $ui (Join-Path $W 'n audio_fade.mp3') 'audio'
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Bass / Treble}' @((New-Rule 'Input file (audio, or video with audio)' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'more bass' $ui (Join-Path $W 'n audio_eq.mp3') 'audio'
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Reduce Background}' @((New-Rule 'Input file (audio, or video with audio)' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'noise reduction (medium)' $ui (Join-Path $W 'n audio_denoised.mp3') 'audio'
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Remove Rumble}' @((New-Rule 'Input file (audio, or video with audio)' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'frequency filter (low rumble)' $ui (Join-Path $W 'n audio_filtered.mp3') 'audio'
$sil = New-Fixture 'n silence.wav' @('-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono:d=3', '-f', 'lavfi', '-i', 'sine=frequency=660:duration=1', '-filter_complex', '[0:a][1:a][2:a]concat=n=3:v=0:a=1')
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Remove Silence}' @((New-Rule 'Input audio file' "$sil{Enter}"), (New-Rule 'Audio file type' '{#WAV}'), $DONE, $FAIL)
$o = Join-Path $W 'n silence_nosilence.wav'
Assert-JobOk 'silence removal' $ui $o 'audio'
Assert-True 'the 3 s pause was removed (result clearly shorter than 5 s)' ([double](Get-ProbeJson $o).format.duration -lt 3.6)
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Fix Audio}' @((New-Rule 'Video (or audio) whose sound is out of sync' "$aud{Enter}"), (New-Rule 'Shift the audio by (seconds)' '0.5{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'n audio_synced.mp3'
Assert-JobOk 'delay audio by 0.5 s' $ui $o 'audio'
Assert-True 'the delayed file is about 0.5 s longer' ([double](Get-ProbeJson $o).format.duration -gt 4.3)
$ui = Invoke-Sub { Start-AudioToolsWorkflow } $AT '{#Reverse Audio}' @((New-Rule 'Input audio file' "$aud{Enter}"), $DONE, $FAIL)
Assert-JobOk 'reverse audio' $ui (Join-Path $W 'n audio_reversed.mp3') 'audio'

# ---- Video enhancement -------------------------------------------------------------------------------------------------
Set-TestGroup 'Video enhancement'
$EN = 'Clean up, steady, reshape or repeat video'
$ui = Invoke-Sub { Start-VideoEnhanceWorkflow } $EN '{#Deinterlace}' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'deinterlace (yadif)' $ui (Join-Path $W 'n video_deinterlaced.mp4')
$ui = Invoke-Sub { Start-VideoEnhanceWorkflow } $EN '{#Reduce Video Noise}' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'denoise (medium)' $ui (Join-Path $W 'n video_denoised.mp4')
$ui = Invoke-Sub { Start-VideoEnhanceWorkflow } $EN '{#Stabilize}' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'stabilize (two passes)' $ui (Join-Path $W 'n video_stabilized.mp4')
Assert-Contains 'stabilization shows both passes' $ui.Output 'Analyzing motion'
Assert-True 'stabilization leaves no temporary .trf file behind' (@(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'fftui_*.trf' -ErrorAction SilentlyContinue).Count -eq 0)
$ui = Invoke-Sub { Start-VideoEnhanceWorkflow } $EN '{#Reverse Video}' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
Assert-JobOk 'reverse video and audio' $ui (Join-Path $W 'n video_reversed.mp4')
$ui = Invoke-Sub { Start-VideoEnhanceWorkflow } $EN '{#Add Bars}' @((New-Rule 'Input video' "$vid{Enter}"), $DONE, $FAIL)
$o = Join-Path $W 'n video_padded.mp4'
Assert-JobOk 'pad a 4:3 video to 16:9' $ui $o
$v = (Get-StreamOf (Get-ProbeJson $o) 'video')[0]
Assert-True "padded picture is 16:9 (got $($v.width)x$($v.height))" ([math]::Abs($v.width / $v.height - 16 / 9) -lt 0.03)
$ui = Invoke-Sub { Start-VideoEnhanceWorkflow } $EN '{#Loop}' @((New-Rule 'Input media file' "$vid{Enter}"), (New-Rule 'How many times in total?' '2{Enter}'), $DONE, $FAIL)
$o = Join-Path $W 'n video_looped.mp4'
Assert-JobOk 'loop twice without re-encoding' $ui $o
Assert-True 'looped file is about twice as long' ([math]::Abs([double](Get-ProbeJson $o).format.duration - 6.0) -lt 0.6)

# ---- Analyze & Detect --------------------------------------------------------------------------------------------------
Set-TestGroup 'Analyze & Detect'
$AN = 'Read-only checks'
function Invoke-Analysis {
    param([string]$Key, [object[]]$Rules, [string]$Report)
    $all = @((New-ScreenRule $AN $Key 1), (New-ScreenRule $AN '{Esc}')) + $Rules + @((New-ScreenRule $Report '{Esc}' 1), (New-ScreenRule 'Analyze another file\?' '02'))
    return (Invoke-Flow { Start-AnalyzeWorkflow } $all -MaxCalls 200 -Height 70)
}
$ui = Invoke-Analysis '{#Measure Volume}' @((New-Rule 'Audio or video file' "$aud{Enter}")) '(?m)^\s+Volume report'
Assert-Contains 'volume analysis reports mean and peak' $ui.Output 'Average (mean) volume'
Assert-True 'volume analysis made no files' (-not (Test-Path -LiteralPath (Join-Path $W 'n audio_volume.mp3')))
$ui = Invoke-Analysis '{#Measure Loudness}' @((New-Rule 'Audio or video file' "$aud{Enter}")) '(?m)^\s+Loudness report'
Assert-Contains 'loudness analysis reports LUFS' $ui.Output 'Integrated loudness'
$ui = Invoke-Analysis '{#Detect Silence}' @((New-Rule 'Audio or video file' "$sil{Enter}")) '(?m)^\s+Silence report'
Assert-Contains 'silence analysis finds the 3 s gap' (Get-FlatText $ui.Output) 'Silence report (1 gap(s) found)'
$blk = New-Fixture 'n black.mp4' @('-f', 'lavfi', '-i', 'color=c=black:s=160x120:d=2:r=10', '-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=10:duration=2', '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0', '-pix_fmt', 'yuv420p')
$ui = Invoke-Analysis '{#Detect Black Frames}' @((New-Rule 'Input video' "$blk{Enter}")) '(?m)^\s+Black moments'
Assert-Contains 'black-frame analysis finds the black opening' (Get-FlatText $ui.Output) 'Black moments (1 found)'
$cuts = New-Fixture 'n cuts.mp4' @('-f', 'lavfi', '-i', 'color=c=red:s=160x120:d=2:r=10', '-f', 'lavfi', '-i', 'color=c=blue:s=160x120:d=2:r=10', '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0', '-pix_fmt', 'yuv420p')
$ui = Invoke-Analysis '{#Detect Scene}' @((New-Rule 'Input video' "$cuts{Enter}")) '(?m)^\s+Scene changes \('
Assert-Contains 'scene analysis finds the cut at 2 s' (Get-FlatText $ui.Output) 'Scene changes (1 found)'
$bars = New-Fixture 'n bars.mp4' @('-f', 'lavfi', '-i', 'color=c=orange:size=160x90:rate=10:duration=2', '-vf', 'pad=160:160:0:35:black', '-pix_fmt', 'yuv420p')
$ui = Invoke-Analysis '{#Detect Black Bars}' @((New-Rule 'Input video' "$bars{Enter}")) '(?m)^\s+Black bar report'
Assert-Contains 'crop analysis suggests removing the bars (160x90)' (Get-FlatText $ui.Output) 'Suggested crop : 160x90'
$ui = Invoke-Analysis '{#Compare Video}' @((New-Rule 'Original video (the reference)' "$vid{Enter}"), (New-Rule 'Converted or compressed video' "$vid{Enter}")) '(?m)^\s+Quality comparison'
Assert-Contains 'comparing a video with itself reports excellent quality' (Get-FlatText $ui.Output) 'Excellent'

# ---- Batch convert -----------------------------------------------------------------------------------------------------
Set-TestGroup 'Batch Convert'
$bd = Join-Path $W 'batch'; [void](New-Item -ItemType Directory -Path $bd -Force)
Copy-Item -LiteralPath $vid -Destination (Join-Path $bd 'one clip.mp4'); Copy-Item -LiteralPath $blk -Destination (Join-Path $bd 'two clip.mp4'); Copy-Item -LiteralPath $aud -Destination (Join-Path $bd 'song.mp3')
$ui = Invoke-Flow { Start-BatchWorkflow } @((New-Rule 'Folder with the files to convert' "$bd{Enter}"), (New-Rule 'What do you want to convert?' '{#Video files}'), (New-Rule 'Convert videos to' '{#MKV}'), (New-Rule 'The output folder does not exist. Create it?' '01'), $DONE, $FAIL)
Assert-True 'batch job completes' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) "error=[$($ui.Error)]"
$bo = Join-Path $bd 'Converted'
Assert-True 'both videos were converted into the Converted folder (MKV) and the MP3 was left alone' ((Test-ValidMediaFile (Join-Path $bo 'one clip.mkv') 'video') -and (Test-ValidMediaFile (Join-Path $bo 'two clip.mkv') 'video') -and -not (Test-Path -LiteralPath (Join-Path $bo 'song.mkv')))
Assert-True 'originals were not touched' ((Test-Path -LiteralPath (Join-Path $bd 'one clip.mp4')) -and (Test-Path -LiteralPath (Join-Path $bd 'two clip.mp4')))
Assert-Contains 'batch shows per-file progress stages' $ui.Output 'File 2 of 2'
Assert-Contains 'folder scan reports compatible media and unsupported files' (Get-FlatText $ui.Output) 'Unsupported'
$multiDir = Join-Path $W 'multi input folder'; [void](New-Item -ItemType Directory -Path $multiDir -Force)
$multiOneName = ([string][char]0x0645) + ([string][char]0x0644) + ([string][char]0x0641) + ' one.mp4'
$multiOne = Join-Path $multiDir $multiOneName; $multiTwo = Join-Path $multiDir 'second clip.mp4'
Copy-Item -LiteralPath $vid -Destination $multiOne; Copy-Item -LiteralPath $blk -Destination $multiTwo
$multiRules = @((New-Rule 'Select input' '{#Multiple files}')) + (New-FileListRules 'Files to convert' @($multiOne, $multiTwo)) + @((New-Rule 'What do you want to convert?' '{#Video files}'), (New-Rule 'Convert videos to' '{#MKV}'), $DONE, $FAIL)
$ui = Invoke-Flow { Start-BatchWorkflow } $multiRules -MaxCalls 180
$multiOut = Join-Path $multiDir 'Converted'
$multiOutOne = Join-Path $multiOut ($multiOneName -replace '\.mp4$', '.mkv')
Assert-True 'multiple selected files with Unicode names, spaces and a spaced folder use one shared settings wizard' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully') -and (Test-ValidMediaFile $multiOutOne 'video') -and (Test-ValidMediaFile (Join-Path $multiOut 'second clip.mkv') 'video')) "error=[$($ui.Error)]"
$existingSize = (New-Object System.IO.FileInfo($multiOutOne)).Length
$namePlan = Resolve-BatchOutputPath -InputPath $multiOne -OutputFolder $multiOut -Extension '.mkv' -Policy 'rename' -ReservedNames @{}
Assert-True 'auto-rename preserves an existing output and plans a numbered result' ((Get-FileSizeSafe $multiOutOne) -eq $existingSize -and $namePlan.Action -eq 'Process' -and $namePlan.ActionPath -like '*_2.mkv')
$ui = Invoke-Flow { Start-BatchWorkflow } @((New-Rule 'Folder with the files to convert' "$bd{Enter}"), (New-Rule 'What do you want to convert?' '{#Video files}'), (New-Rule 'Convert videos to' '{#MKV}'), (New-ScreenRule 'Nothing to convert' '{Enter}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}' 1), (New-ScreenRule 'Summary' '{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}')) -MaxCalls 120
Assert-Contains 'running the batch again skips files that already exist (never overwrites silently)' (Get-FlatText $ui.Output) 'output already exists'
$ui = Invoke-Flow { Start-BatchWorkflow } @((New-Rule 'Folder with the files to convert' "$(Join-Path $W 'no such folder'){Enter}" 1), (New-Rule 'Folder with the files to convert' '{Esc}{Esc}' 10)) -MaxCalls 20
Assert-Contains 'a missing folder is rejected' (Get-FlatText $ui.Output) 'Folder not found'
$emptyBatchFolder = Join-Path $W 'empty batch folder'; [void](New-Item -ItemType Directory -Path $emptyBatchFolder -Force)
$ui = Invoke-Flow { Start-BatchWorkflow } @((New-Rule 'Folder with the files to convert' "$emptyBatchFolder{Enter}"), (New-Rule 'Folder with the files to convert' '{Esc}' 1)) -MaxCalls 20
Assert-Contains 'an empty folder is rejected during the scan' (Get-FlatText $ui.Output) 'No compatible video or audio files were found'

# ---- Advanced tools ------------------------------------------------------------------------------------------------------
Set-TestGroup 'Advanced FFmpeg'
$AD = 'For everything the guided tools do not cover'
$ui = Invoke-Sub { Start-AdvancedWorkflow } $AD '{#Custom FFmpeg Command}' (((New-FileListRules 'Input files' @($vid)) + @((New-Rule 'Options for the first input (optional)' '{Enter}'), (New-Rule 'Options for the output (optional)' '-vf "scale=160:-2" -c:v libx264 -an{Enter}'), (New-Rule 'Output file name (with extension)' '{Clear}n custom out.mp4{Enter}'), $DONE, $FAIL)))
$o = Join-Path $W 'n custom out.mp4'
Assert-JobOk 'custom command (scale to 160, no audio)' $ui $o
$v = Get-ProbeJson $o
Assert-True 'custom options were applied exactly' ((Get-StreamOf $v 'video')[0].width -eq 160 -and (Get-StreamOf $v 'audio').Count -eq 0)
$ui = Invoke-Sub { Start-AdvancedWorkflow } $AD '{#Custom FFmpeg Command}' (((New-FileListRules 'Input files' @($vid)) + @((New-Rule 'Options for the first input (optional)' '{Enter}'), (New-Rule 'Options for the output (optional)' '-c:v not_a_real_encoder{Enter}' 1), (New-Rule 'Options for the output (optional)' '{Esc}{Esc}{Esc}{Esc}{Esc}' 10))) ) -MaxCalls 60
Assert-Contains 'an encoder that the installed FFmpeg lacks is rejected before running' (Get-FlatText $ui.Output) "not available in your FFmpeg build"
$ui = Invoke-Sub { Start-AdvancedWorkflow } $AD '{#Custom FFmpeg Command}' (((New-FileListRules 'Input files' @($vid)) + @((New-Rule 'Options for the first input (optional)' '{Enter}'), (New-Rule 'Options for the output (optional)' '-y{Enter}' 1), (New-Rule 'Options for the output (optional)' '{Esc}{Esc}{Esc}{Esc}{Esc}' 10))) ) -MaxCalls 60
Assert-Contains 'the -y option is refused (overwrite is decided by the application)' (Get-FlatText $ui.Output) 'Overwriting is decided by this application'
$ui = Invoke-Flow { Start-AdvancedWorkflow } @((New-ScreenRule $AD '{#Capability Browser}' 1), (New-ScreenRule $AD '{Esc}'), (New-ScreenRule 'Capability Browser' '{#Filters}' 1), (New-ScreenRule 'Capability Browser' '{Esc}'), (New-ScreenRule 'Search> ' 'scale{Enter}' 1), (New-ScreenRule 'Search> ' '{Esc}'), (New-ScreenRule 'match\(es\)' '{Esc}')) -MaxCalls 80
Assert-Contains 'capability browser lists filters of the installed build' $ui.Output 'scale2ref'
$ui = Invoke-Sub { Start-AdvancedWorkflow } $AD '{#Hardware Acceleration}' @((New-ScreenRule 'Hardware acceleration report' '{Esc}'))
Assert-Contains 'hardware check produces a report' $ui.Output 'Hardware acceleration report'
$ui = Invoke-Sub { Start-AdvancedWorkflow } $AD '{#FFmpeg Build Details}' @((New-ScreenRule 'FFmpeg build details' '{Esc}'))
Assert-Contains 'build details show the installed version' $ui.Output 'ffmpeg version'

# ---- Stream out ---------------------------------------------------------------------------------------------------------------
Set-TestGroup 'Streaming: send a file to a network address'
$HM = 'Work with supported streams and create common HLS outputs'
$short = New-Fixture 'n short.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=1:size=160x120:rate=10', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '{#Send a File}' @((New-Rule 'Media file to send' "$short{Enter}"), (New-Rule 'Destination address (URL)' 'udp://127.0.0.1:59871?pkt_size=1316{Enter}'), $DONE, $FAIL)
Assert-True 'streaming a short file to a UDP address completes' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) "error=[$($ui.Error)]"
Assert-Contains 'the destination is shown as "Sent to"' $ui.Output 'Sent to:'
Assert-NotContains 'no "Open output folder" action is offered for a network destination' (Get-LastFrame $ui.Output) 'Open output folder'
$ui = Invoke-Sub { Start-StreamingWorkflow } $HM '{#Send a File}' @((New-Rule 'Media file to send' "$short{Enter}"), (New-Rule 'Destination address (URL)' 'ftp://example.com/x{Enter}' 1), (New-Rule 'Destination address (URL)' '{Esc}{Esc}{Esc}{Esc}' 10)) -MaxCalls 50
Assert-Contains 'unsupported destination types are explained' (Get-FlatText $ui.Output) 'is not supported for sending'
