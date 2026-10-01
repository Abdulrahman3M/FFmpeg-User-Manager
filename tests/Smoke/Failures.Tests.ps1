# Failure-path and edge-case tests (never an unhandled exception for an expected user mistake).
$W = Get-TestWork
$vid = New-Fixture 'f video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$aud = New-Fixture 'f audio.mp3' @('-f', 'lavfi', '-i', 'sine=frequency=880:duration=2', '-c:a', 'libmp3lame')
$DONE = New-ScreenRule 'Completed successfully' '{#Main menu}'
$FAIL = New-ScreenRule 'Processing failed\.' '{#Back}'
function Test-Rejects {
    param([string]$Name, [scriptblock]$Flow, [string]$PromptRule, [string]$BadInput, [string]$Expect)
    $rules = @()
    if ($PromptRule -ne 'Input video') { $rules += (New-Rule 'Input video' "$vid{Enter}") }
    $ui = Invoke-Flow $Flow (@($rules) + @((New-Rule $PromptRule $BadInput 1), (New-Rule $PromptRule '{Esc}{Esc}{Esc}{Esc}' 10), (New-ScreenRule 'cannot be processed' '{Enter}{Esc}{Esc}{Esc}{Esc}'))) -MaxCalls 60
    Assert-True "$Name" ((Get-FlatText $ui.Output).Contains($Expect) -and -not ($ui.Error -match 'Exception|cannot be found|cannot be retrieved|null')) ("expected [$Expect]; error=[$($ui.Error -replace "`n.*",'')]")
}

Set-TestGroup 'Failure tests: input files'
Test-Rejects 'nonexistent input file is rejected before execution' { Start-ConvertVideoWorkflow } 'Input video' "$(Join-Path $W 'does not exist.mp4'){Enter}" 'File not found'
Test-Rejects 'a folder given as input is rejected' { Start-ConvertVideoWorkflow } 'Input video' "$W{Enter}" 'is a folder'
$zero = Join-Path $W 'zero.mp4'; [System.IO.File]::WriteAllBytes($zero, [byte[]]@())
Test-Rejects 'zero-length file is rejected' { Start-ConvertVideoWorkflow } 'Input video' "$zero{Enter}" 'empty'
$corrupt = Join-Path $W 'corrupt.mp4'; [System.IO.File]::WriteAllText($corrupt, 'not a real media file at all, just text')
Test-Rejects 'corrupt input is rejected with a readable reason' { Start-ConvertVideoWorkflow } 'Input video' "$corrupt{Enter}" 'could not be read as media'
Test-Rejects 'audio file given to a video workflow: no video stream' { Start-ConvertVideoWorkflow } 'Input video' "$aud{Enter}" 'no video stream'
$vonly = New-Fixture 'f video only.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=64x64:rate=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
Test-Rejects 'video without audio given to Extract Audio: no audio stream' { Start-ExtractAudioWorkflow } 'Input video' "$vonly{Enter}" 'no audio stream'
Test-Rejects 'blank path is rejected' { Start-ConvertVideoWorkflow } 'Input video' '{Enter}' 'required'
Test-Rejects 'a path with an illegal character is rejected safely' { Start-ConvertVideoWorkflow } 'Input video' "$(Join-Path $W ('bad' + [char]0 + 'name.mp4')){Enter}" 'not a valid path'
$long = Join-Path $W ('long_' + ('x' * 230) + '.mp4')
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output file name' "{Clear}$('y' * 210).mp4{Enter}" 1), (New-Rule 'Output file name' '{Esc}{Esc}{Esc}{Esc}' 10)) -MaxCalls 60
Assert-True 'over-long output name/path is rejected' ((Get-FlatText $ui.Output) -match 'too long')

Set-TestGroup 'Failure tests: output names and folders'
Test-Rejects 'output name identical to the source is rejected (never overwrite the source)' { Start-ConvertVideoWorkflow } 'Output file name' '{Clear}f video.mp4{Enter}' 'would overwrite the source file'
Test-Rejects 'illegal characters in the output name are rejected' { Start-ConvertVideoWorkflow } 'Output file name' '{Clear}a<b>c.mp4{Enter}' 'invalid character'
Test-Rejects 'reserved Windows device name is rejected' { Start-ConvertVideoWorkflow } 'Output file name' '{Clear}CON.mp4{Enter}' 'reserved'
$ui = Invoke-Flow { Invoke-Wizard -Title 'T' -Steps @(@{ Id = 't'; Type = 'Text'; Prompt = 'Required text' }) } @((New-Rule 'Required text' '{Enter}' 1), (New-Rule 'Required text' '{Esc}' 5)) -MaxCalls 20
Assert-Contains 'blank required answer is rejected with a message' $ui.Output 'This value is required.'
# Flow helper above always types the input path first; give it the fixture via the workflow prompts

Set-TestGroup 'Failure tests: media and combinations'
$ui = Invoke-Flow { Start-TrimWorkflow } @((New-Rule 'Input media (video or audio)' "$vid{Enter}"), (New-Rule 'Output format' '03'), (New-Rule 'Output file name' '{Clear}f_trim_webm.webm{Enter}'), (New-ScreenRule 'cannot be processed' '{Enter}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}'), $DONE, $FAIL) -MaxCalls 80
Assert-True 'fast cut into a container that cannot hold the streams is explained (WebM)' ((Get-FlatText $ui.Output) -match 'cannot be stored in WebM')
$ui = Invoke-Flow { Start-MergeWorkflow } @((New-ScreenRule '(?s)\A(?!.*Add another file).*Files to merge' "$vid{Enter}" 2), (New-ScreenRule 'Add another file' '{#Add another}' 1), (New-ScreenRule 'Add another file' '{#Done}' 1), (New-Rule 'Merge method' '01'), $DONE, $FAIL)
Assert-True 'merging a file with itself works (order/duplicates are allowed)' ($ui.Output.Contains('Completed successfully'))
$twoAudio = New-Fixture 'f two audio.mkv' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=64x64:rate=10', '-f', 'lavfi', '-i', 'sine=frequency=300:duration=2', '-f', 'lavfi', '-i', 'sine=frequency=900:duration=2', '-map', '0:v', '-map', '1:a', '-map', '2:a', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=fra')
$ui = Invoke-Flow { Start-ExtractAudioWorkflow } @((New-Rule 'Input video' "$twoAudio{Enter}"), (New-Rule 'Audio track' '02'), $DONE, $FAIL)
Assert-True 'multiple audio streams: the user is asked which one to extract' ($ui.Output.Contains('Audio track') -and $ui.Output.Contains('Track 2') -and $ui.Output.Contains('Completed successfully'))
Assert-Contains 'multiple audio streams: both tracks are listed with language' $ui.Output '[fra]'
$rotSrc = New-Fixture 'f rot src.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=1:size=320x240:rate=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$rot = Join-Path $W 'f rotated.mp4'
$null = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-y', '-hide_banner', '-loglevel', 'error', '-display_rotation:v:0', '90', '-i', $rotSrc, '-c', 'copy', $rot) -TimeoutSec 60
$mi = Get-MediaInfo $rot
$disp = Get-DisplayVideoSize $mi.Info.Video[0]
Assert-True "rotation metadata is detected (display size $($disp -join 'x') for a 320x240 stream rotated 90)" ($mi.Ok -and $mi.Info.Video[0].Rotation -in @(90, 270) -and $disp[0] -eq 240)
$vfr = New-Fixture 'f vfr.mkv' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=64x64:rate=30', '-vf', "select='not(mod(n,3))+not(mod(n,5))',setpts=N/(30*TB)", '-fps_mode', 'vfr', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$mv = Get-MediaInfo $vfr
Assert-True 'variable-frame-rate file is probed without errors' ($mv.Ok)

Set-TestGroup 'Failure tests: FFmpeg execution errors'
$badJob = @{ Title = 'Failing job'; Summary = @(, @('x', 'y')); Stages = @(@{ Name = 'Broken stage'; Arguments = @('-i', (Join-Path $W 'nonexistent input.mp4'), (Join-Path $W 'failed_out.mp4')) }); OutputPath = (Join-Path $W 'failed_out.mp4'); OutputKind = 'File'; EnsureDirs = @(); TempFiles = @() }
$ui = Invoke-Flow { Invoke-FFJob -Job $badJob } @((New-ScreenRule 'Processing failed' '{#Show technical}' 1), (New-ScreenRule 'Technical details' '{Esc}' 1), (New-ScreenRule 'Processing failed' '{#Retry}' 1), (New-ScreenRule 'Processing failed' '{#Back}'))
Assert-Contains 'non-zero FFmpeg exit shows a failure screen' $ui.Output 'Processing failed.'
Assert-Contains 'failure screen shows a short human reason' $ui.Output 'Reason:'
Assert-Contains 'failure screen offers technical details, retry and back' $ui.Output 'Show technical details'
Assert-Contains 'technical details contain the exit code and FFmpeg output' $ui.Output 'Exit code:'
Assert-True 'Retry re-runs the job (two progress screens)' (@($ui.Output -split '=====(?:FRAME|CLEAR)=====' | Where-Object { $_ -match 'Working\.\.\.|Failing job' -and $_ -match 'Broken stage' }).Count -ge 2)
Assert-True 'failed job leaves no zero-byte output file' (-not (Test-Path -LiteralPath (Join-Path $W 'failed_out.mp4')))
Assert-True 'the failure did not throw' ($ui.Error -eq '' -and $ui.Value -eq 'Menu')
$stderrNoise = ($ui.Output -split '=====(?:FRAME|CLEAR)=====' | Where-Object { $_ -match 'Processing failed' } | Select-Object -First 1)
Assert-NotContains 'raw FFmpeg stderr does not flood the normal failure screen' $stderrNoise 'in#0 @'

Set-TestGroup 'Failure tests: cancellation'
$before = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue).Count
$longOut = Join-Path $W 'long_job.mp4'
$longJob = @{ Title = 'Long job'; Summary = @(, @('x', 'y')); Stages = @(@{ Name = 'Encoding forever'; Arguments = @('-f', 'lavfi', '-i', 'testsrc=duration=900:size=1280x720:rate=30', '-c:v', 'libx264', '-preset', 'veryslow', '-pix_fmt', 'yuv420p', $longOut); DurationSec = 900 }); OutputPath = $longOut; OutputKind = 'File'; EnsureDirs = @(); TempFiles = @() }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ui = Invoke-Ui { Invoke-FFJob -Job $longJob } '{Esc}0101'
$sw.Stop()
Assert-Contains 'user cancellation asks for confirmation' $ui.Output 'Cancel this job?'
Assert-Contains 'cancelled job is reported' $ui.Output 'Job cancelled'
Assert-Contains 'partial output is flagged as potentially incomplete' $ui.Output 'potentially incomplete'
Assert-True ("cancelling stops promptly (took {0:0.0}s of a 900 s job)" -f $sw.Elapsed.TotalSeconds) ($sw.Elapsed.TotalSeconds -lt 30)
Start-Sleep -Milliseconds 500
Assert-True 'the child FFmpeg process is terminated after cancellation' (@(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue).Count -le $before)
$shortOut = Join-Path $W 'short_job.mp4'
$shortJob = @{ Title = 'Short job'; Summary = @(, @('x', 'y')); Stages = @(@{ Name = 'Encoding short'; Arguments = @('-f', 'lavfi', '-i', 'testsrc=duration=4:size=320x240:rate=25', '-c:v', 'libx264', '-preset', 'veryslow', '-pix_fmt', 'yuv420p', $shortOut); DurationSec = 4 }); OutputPath = $shortOut; OutputKind = 'File'; EnsureDirs = @(); TempFiles = @() }
$ui = Invoke-Ui { Invoke-FFJob -Job $shortJob } '{Esc}0203'
Assert-True 'answering No to the cancel prompt lets the job finish' ($ui.Output.Contains('Completed successfully') -and (Test-ValidMediaFile $shortOut 'video'))

Set-TestGroup 'Failure tests: source protection'
$src = New-Fixture 'protect me.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=1:size=64x64:rate=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$hashBefore = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
foreach ($wf in @(@{ F = { Start-ConvertVideoWorkflow }; N = 'convert' }, @{ F = { Start-TrimWorkflow }; N = 'trim' }, @{ F = { Start-GifWorkflow }; N = 'gif' }, @{ F = { Start-SpeedWorkflow }; N = 'speed' })) {
    $ui = Invoke-Flow $wf.F @((New-ScreenRule 'Input (video|media)' "$src{Enter}"), (New-ScreenRule 'Input media \(video or audio\)' "$src{Enter}"), $DONE, $FAIL)
}
Assert-True 'source files are never modified or deleted by any workflow' ((Test-Path -LiteralPath $src) -and (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -eq $hashBefore)

Set-TestGroup 'Failure tests: unwritable output folder (simulated)'
function global:Test-DirectoryWritable { param($Dir) return $false }
$ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Output folder' '{Enter}' 1), (New-ScreenRule 'That choice cannot be used' '{Enter}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}{Esc}'), (New-Rule 'Output folder' '{Esc}{Esc}{Esc}{Esc}' 3)) -MaxCalls 60
Assert-True 'a folder without write permission is rejected before execution' ((Get-FlatText $ui.Output) -match 'permission to write')
Import-Module -Name (Join-Path (Join-Path (Join-Path (Get-TestRoot) 'src') 'Core') 'Paths.psm1') -Force -DisableNameChecking -Global
Assert-True 'the write-permission override was removed again' ((Test-DirectoryWritable (Get-TestWork)) -eq $true)
Skip-Test 'read permission denied on an input file' 'the test machine runs as root/administrator, so permission errors cannot be provoked; Test-InputFile maps UnauthorizedAccessException to a message (code-reviewed only)'
Skip-Test 'input file locked by another program' 'sharing violations only occur on Windows; Test-InputFile maps IOException to a message (code-reviewed only)'
Skip-Test 'terminal closes unexpectedly while a job runs' 'cannot be automated; the child FFmpeg process is stopped in a finally block of Invoke-FFmpegStage'
