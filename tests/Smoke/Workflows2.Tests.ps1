# Workflow smoke tests (part 2): GIF and frame extraction, including paths with spaces / Unicode.
$W = Get-TestWork
$vid = New-Fixture 'g video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$DONE = New-ScreenRule 'Completed successfully' '{#Main menu}'
$FAIL = New-ScreenRule 'Processing failed\.' '{#Back}'
function Assert-JobOk {
    param([string]$Name, $Ui, [string]$Output, [string]$Type = 'video')
    $ok = ($Ui.Error -eq '') -and $Ui.Output.Contains('Completed successfully')
    $why = ''; if (-not $ok) { $why = "error=[$($Ui.Error)]`n" + (Get-LastFrame $Ui.Output) }
    Assert-True "$Name : job completes" $ok $why
    if ($Output) { Assert-True "$Name : output is valid ($([System.IO.Path]::GetFileName($Output)))" (Test-ValidMediaFile $Output $(if ($Type -eq 'any') { '' } else { $Type })) }
}
function Get-GifInfo { param($Path) $j = Get-ProbeJson $Path; $v = (Get-StreamOf $j 'video')[0]; return [pscustomobject]@{ Codec = $v.codec_name; W = [int]$v.width; H = [int]$v.height; Fps = $v.r_frame_rate; Dur = [double]$j.format.duration } }
function Get-FrameCount { param($Path) $r = Invoke-ExternalCapture -FilePath (Get-FFprobePath) -Arguments @('-v', 'error', '-count_frames', '-select_streams', 'v:0', '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', $Path) -TimeoutSec 60; return [int]($r.StdOut.Trim()) }
$SUMMARY_VIEW = { param($times) New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}' 1 }

Set-TestGroup 'Workflow 8: Video to GIF'
$g1 = Join-Path $W 'g video_gif.gif'
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'entire video, all defaults' $ui $g1
$i = Get-GifInfo $g1
Assert-True "GIF codec/size/fps defaults (gif, 480x360, 15 fps; got $($i.Codec) $($i.W)x$($i.H) $($i.Fps))" ($i.Codec -eq 'gif' -and $i.W -eq 480 -and $i.H -eq 360 -and $i.Fps -eq '15/1')
Assert-True "entire video kept (duration $($i.Dur))" ([math]::Abs($i.Dur - 3.0) -lt 0.3)
Assert-Contains 'high-quality path uses palettegen (command view)' $ui.Output 'palettegen'
Assert-Contains 'high-quality path uses paletteuse (command view)' $ui.Output 'paletteuse'
Assert-Contains 'explanation: frame rate' $ui.Output 'Higher FPS looks smoother but increases GIF size.'
Assert-Contains 'explanation: width' $ui.Output 'Smaller dimensions reduce file size significantly.'
Assert-Contains 'explanation: palette quality' $ui.Output 'High Quality creates a better color palette before generating the GIF.'
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Clip range' '02'), (New-Rule 'Start time' '{Clear}1{Enter}'), (New-Rule 'End time' '{Clear}2{Enter}'), $DONE, $FAIL)
Assert-JobOk 'selected clip 1s-2s (start + end)' $ui $g1
Assert-True 'clip duration is about 1 s' ([math]::Abs((Get-GifInfo $g1).Dur - 1.0) -lt 0.25)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Clip range' '03'), (New-Rule 'Start time' '{Clear}0.5{Enter}'), (New-Rule 'Duration' '{Clear}1.5{Enter}'), $DONE, $FAIL)
Assert-JobOk 'selected clip (start + duration)' $ui $g1
Assert-True 'start + duration clip is about 1.5 s' ([math]::Abs((Get-GifInfo $g1).Dur - 1.5) -lt 0.25)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Frame rate' '{#LAST}'), (New-Rule 'Custom GIF frame rate' '10{Enter}'), (New-Rule 'Width' '{#LAST}'), (New-Rule 'Custom width' '200{Enter}'), $DONE, $FAIL)
Assert-JobOk 'custom FPS (10) and custom width (200)' $ui $g1
Assert-Contains 'custom width shows guidance with an example' (Get-FlatText $ui.Output) 'Enter a positive pixel value, e.g. 1280.'
$i = Get-GifInfo $g1
Assert-True "custom fps + width honored (got $($i.Fps) $($i.W)x$($i.H))" ($i.Fps -eq '10/1' -and $i.W -eq 200 -and $i.H -eq 150)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'GIF speed' '07'), $DONE, $FAIL)
Assert-JobOk 'speed 2.0x' $ui $g1
Assert-True "2x speed halves the duration (got $((Get-GifInfo $g1).Dur))" ([math]::Abs((Get-GifInfo $g1).Dur - 1.5) -lt 0.3)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'GIF speed' '01'), $DONE, $FAIL)
Assert-JobOk 'speed 0.25x' $ui $g1
Assert-True "0.25x speed makes the GIF 4x longer (got $((Get-GifInfo $g1).Dur))" ([math]::Abs((Get-GifInfo $g1).Dur - 12.0) -lt 1.0)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'GIF speed' '{#LAST}'), (New-Rule 'Custom speed' '1.5{Enter}'), $DONE, $FAIL)
Assert-JobOk 'custom speed 1.5x' $ui $g1
Assert-True "1.5x custom speed shortens the GIF (got $((Get-GifInfo $g1).Dur))" ([math]::Abs((Get-GifInfo $g1).Dur - 2.0) -lt 0.3)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Maximum number of frames' '10{Enter}'), $DONE, $FAIL)
Assert-JobOk 'frame limit of 10' $ui $g1
Assert-Equal 'GIF has exactly 10 frames' 10 (Get-FrameCount $g1)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Preserve the aspect ratio?' '02'), (New-Rule 'Height' '100{Enter}'), $DONE, $FAIL)
Assert-JobOk 'aspect ratio not preserved (explicit height)' $ui $g1
$i = Get-GifInfo $g1
Assert-True "explicit height honored (got $($i.W)x$($i.H))" ($i.W -eq 480 -and $i.H -eq 100)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Width' '01'), $DONE, $FAIL)
Assert-JobOk 'keep original size' $ui $g1
Assert-True 'original size kept (320x240)' ((Get-GifInfo $g1).W -eq 320 -and (Get-GifInfo $g1).H -eq 240)
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Palette quality' '02'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'fast palette mode' $ui $g1
Assert-NotContains 'fast mode does not generate a palette' (($ui.Output -split '=====(?:FRAME|CLEAR)=====' | Where-Object { $_ -match 'Generated FFmpeg command' } | Select-Object -First 1)) 'palettegen'
Remove-Item -LiteralPath $g1 -Force
foreach ($d in @(@('2', 'floyd_steinberg'), @('3', 'bayer'), @('4', 'none'))) {
    $ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Number of colors' '04'), (New-Rule 'Dithering method' $d[0]), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
    Assert-JobOk "dither $($d[1]) with 32 colors" $ui $g1
    Assert-Contains "dither $($d[1]) reaches the command" $ui.Output ('dither=' + $d[1])
    Assert-Contains "32 colors reaches the command" $ui.Output 'max_colors=32'
    Remove-Item -LiteralPath $g1 -Force
}
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Loop behavior' '02'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'play once (no loop)' $ui $g1
Assert-Contains 'no-loop maps to -loop -1' (Get-FlatText $ui.Output) '-loop -1'
Remove-Item -LiteralPath $g1 -Force
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Loop behavior' '{#LAST}'), (New-Rule 'Number of repeats' '3{Enter}'), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL)
Assert-JobOk 'custom loop count' $ui $g1
Assert-Contains 'custom loop count reaches the command' (Get-FlatText $ui.Output) '-loop 3'
Remove-Item -LiteralPath $g1 -Force
# invalid custom values
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Frame rate' '{#LAST}'), (New-Rule 'Custom GIF frame rate' '-5{Enter}' 1), (New-Rule 'Custom GIF frame rate' '{Esc}' 5), (New-Rule 'Frame rate' '{Esc}{Esc}{Esc}' 3)) -MaxCalls 40
Assert-True 'invalid custom FPS is rejected with a message' ($ui.Output.Contains('at least') -or $ui.Output.Contains('must be a number') -or $ui.Output.Contains('between 0.1 and 240'))
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Width' '{#LAST}'), (New-Rule 'Custom width' '12.5{Enter}' 1), (New-Rule 'Custom width' '{Esc}' 5), (New-Rule 'Width' '{Esc}{Esc}{Esc}' 3)) -MaxCalls 40
Assert-Contains 'invalid custom width is rejected' $ui.Output 'must be a whole number'
# output path with spaces in a new folder
$newDir = Join-Path $W 'out dir with spaces (gif)'
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$newDir{Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), $DONE, $FAIL)
Assert-JobOk 'output folder with spaces is created after confirmation' $ui (Join-Path $newDir 'g video_gif.gif')
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$(Join-Path $W 'never created dir'){Enter}"), (New-Rule 'The output folder does not exist. Create it?' '02'), (New-Rule 'Output folder' '{Esc}{Esc}{Esc}{Esc}' 3)) -MaxCalls 40
Assert-True 'declining folder creation does not create the folder' (-not (Test-Path -LiteralPath (Join-Path $W 'never created dir')))

Set-TestGroup 'Workflow 9: Extract Frames / Images'
$fd = Join-Path $W 'frames out'
$fr = { param([string]$prefix) $null }
$ui = Invoke-Flow { Start-ExtractFramesWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Timestamp' '{Clear}1{Enter}'), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$fd{Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), $DONE, $FAIL)
Assert-True 'single frame: completes' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
Assert-True 'single frame: exactly one PNG with the default naming pattern' ((Test-Path -LiteralPath (Join-Path $fd 'g video_frame_0001.png')) -and @(Get-ChildItem -LiteralPath $fd).Count -eq 1)
Assert-Contains 'naming pattern example is shown before execution' $ui.Output 'e.g. g video_frame_0001.png'
$ui = Invoke-Flow { Start-ExtractFramesWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Extraction mode' '02'), (New-Rule 'Seconds between frames' '{Clear}1{Enter}'), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$(Join-Path $W 'frames interval'){Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), $DONE, $FAIL)
Assert-Equal 'every 1 s over 3 s -> 3 images' 3 @(Get-ChildItem -LiteralPath (Join-Path $W 'frames interval') -Filter '*.png').Count
$ui = Invoke-Flow { Start-ExtractFramesWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Extraction mode' '03'), (New-Rule 'Frames per second' '{Clear}2{Enter}'), (New-Rule 'Image format' '02'), (New-Rule 'Image quality' '01'), (New-Rule 'Image size' '{#LAST}'), (New-Rule 'Custom resolution' '160{Enter}'), (New-Rule 'Maximum number of images' '4{Enter}'), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$(Join-Path $W 'frames fps'){Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), (New-Rule 'File name prefix' '{Clear}pic{Enter}'), (New-Rule 'Number width (zero padding)' '{Clear}3{Enter}'), $DONE, $FAIL)
$jpgs = @(Get-ChildItem -LiteralPath (Join-Path $W 'frames fps') -Filter '*.jpg')
Assert-True "2 fps, JPEG, width 160, max 4 images -> 4 files named pic_001.jpg.. (got $($jpgs.Count): $(($jpgs | ForEach-Object Name) -join ','))" ($jpgs.Count -eq 4 -and (Test-Path -LiteralPath (Join-Path $W 'frames fps/pic_001.jpg')))
Assert-Equal 'JPEG width' 160 ((Get-StreamOf (Get-ProbeJson (Join-Path $W 'frames fps/pic_001.jpg')) 'video')[0].width)
$ui = Invoke-Flow { Start-ExtractFramesWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Extraction mode' '04'), (New-Rule 'Which part of the video?' '01'), (New-Rule 'Start time' '{Clear}1{Enter}'), (New-Rule 'End time' '{Clear}2{Enter}'), (New-Rule 'Seconds between frames' '{Clear}0.5{Enter}'), (New-Rule 'Image format' '03'), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$(Join-Path $W 'frames range'){Enter}"), (New-Rule 'The output folder does not exist. Create it?' '01'), $DONE, $FAIL)
$webps = @(Get-ChildItem -LiteralPath (Join-Path $W 'frames range') -Filter '*.webp')
Assert-True "time range 1-2 s every 0.5 s as WebP (got $($webps.Count))" ($webps.Count -eq 2)
# collision handling: same prefix in the same folder
$ui = Invoke-Flow { Start-ExtractFramesWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Timestamp' '{Clear}1{Enter}'), (New-Rule 'Output folder' '{#LAST}'), (New-Rule 'Output folder path' "$fd{Enter}"), (New-Rule 'File name prefix' '{Enter}' 1), (New-Rule 'Images with these names already exist' '01'), (New-Rule 'File name prefix' '{Clear}other{Enter}'), $DONE, $FAIL)
Assert-True 'existing images are not overwritten silently (rename path)' ((Test-Path -LiteralPath (Join-Path $fd 'other_0001.png')) -and $ui.Output.Contains('Images with these names already exist'))
# Unicode / awkward names end-to-end
$uniDir = Join-Path $W 'Папка тест (1) & "العربية"'
$uni = New-Fixture "Видео тест & 'q' (1) اختبار.mp4" @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=160x120:rate=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p') $uniDir
$ui = Invoke-Flow { Start-GifWorkflow } @((New-Rule 'Input video' "$uni{Enter}"), $DONE, $FAIL)
Assert-JobOk 'Unicode/Arabic/Cyrillic + quotes/ampersand/parentheses path -> GIF' $ui (Join-Path $uniDir "Видео тест & 'q' (1) اختبار_gif.gif")
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "`"$uni`"{Enter}"), (New-Rule 'Output format' '02'), $DONE, $FAIL)
Assert-JobOk 'quoted Unicode path -> MKV conversion' $ui (Join-Path $uniDir "Видео тест & 'q' (1) اختبار_converted.mkv")
