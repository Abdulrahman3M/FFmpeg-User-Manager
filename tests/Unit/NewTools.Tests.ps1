# Unit tests: icon-tier decision, argument parsing for the custom command, dshow device parsing, analysis log parsers,
# chapter parsing and metadata escaping (all pure logic; the workflows themselves are covered by the smoke tests).
Set-TestGroup 'Icon tier decision (why icons always appear)'
$none = @{}
Assert-Equal 'Windows Terminal gets emoji icons' 'Emoji' (Resolve-IconTier -Env @{ WT_SESSION = 'x' } -IsWin $true -Redirected $false)
Assert-Equal 'VS Code terminal gets emoji icons' 'Emoji' (Resolve-IconTier -Env @{ TERM_PROGRAM = 'vscode' } -IsWin $true -Redirected $false)
Assert-Equal 'ConEmu gets emoji icons' 'Emoji' (Resolve-IconTier -Env @{ ConEmuANSI = 'ON' } -IsWin $true -Redirected $false)
Assert-Equal 'classic Windows console (conhost / PowerShell 5.1 window) gets console-safe SYMBOL icons, never plain text tags' 'Symbol' (Resolve-IconTier -Env $none -IsWin $true -Redirected $false)
Assert-Equal 'Windows console whose output encoding cannot be set falls back to ASCII tags' 'Ascii' (Resolve-IconTier -Env $none -IsWin $true -Redirected $false -Utf8Ok $false)
Assert-Equal 'redirected output uses ASCII tags' 'Ascii' (Resolve-IconTier -Env $none -IsWin $true -Redirected $true)
Assert-Equal 'UTF-8 Linux/macOS terminal gets emoji icons' 'Emoji' (Resolve-IconTier -Env @{ LANG = 'en_US.UTF-8' } -IsWin $false -Redirected $false)
Assert-Equal 'non-UTF-8 Linux/macOS terminal uses ASCII tags' 'Ascii' (Resolve-IconTier -Env @{ LANG = 'C' } -IsWin $false -Redirected $false)
Assert-Equal 'FFTUI_ASCII=1 forces ASCII' 'Ascii' (Resolve-IconTier -Env @{ FFTUI_ASCII = '1'; WT_SESSION = 'x' } -IsWin $true -Redirected $false)
Assert-Equal 'FFTUI_UNICODE=1 forces emoji' 'Emoji' (Resolve-IconTier -Env @{ FFTUI_UNICODE = '1' } -IsWin $true -Redirected $false)
Assert-Equal 'FFTUI_ICONS=symbol overrides detection' 'Symbol' (Resolve-IconTier -Env @{ FFTUI_ICONS = 'Symbol'; WT_SESSION = 'x' } -IsWin $true -Redirected $false)
Assert-Equal 'FFTUI_ICONS=emoji overrides redirection' 'Emoji' (Resolve-IconTier -Env @{ FFTUI_ICONS = 'emoji' } -IsWin $true -Redirected $true)
Assert-Equal 'FFTUI_ICONS=ascii overrides detection' 'Ascii' (Resolve-IconTier -Env @{ FFTUI_ICONS = 'ascii'; WT_SESSION = 'x' } -IsWin $true -Redirected $false)
$old = $env:FFTUI_ICONS
$env:FFTUI_ICONS = 'symbol'
Assert-Equal 'Get-IconTier reads the environment' 'Symbol' (Get-IconTier)
$env:FFTUI_ICONS = $old

Set-TestGroup 'Custom command: argument text -> tokens'
$t = ConvertFrom-ArgumentText '-c:v libx264 -crf 20 -vf "scale=1280:-2" -an'
Assert-True 'whitespace separates tokens and quotes group words' ($t.Ok -and ($t.Tokens -join '|') -eq '-c:v|libx264|-crf|20|-vf|scale=1280:-2|-an')
$t = ConvertFrom-ArgumentText '-metadata title="My movie 2025" -y'
Assert-Equal 'a quoted value keeps its spaces' '-metadata|title=My movie 2025|-y' ($t.Tokens -join '|')
$t = ConvertFrom-ArgumentText '-vf "unclosed'
Assert-True 'an unclosed quotation mark is reported' ((-not $t.Ok) -and $t.Error -like '*quotation*')
$t = ConvertFrom-ArgumentText '   '
Assert-True 'blank text gives no tokens' ($t.Ok -and $t.Tokens.Count -eq 0)
$t = ConvertFrom-ArgumentText '-i "C:\My Files\a b.mp4"'
Assert-Equal 'Windows paths with spaces survive intact (no backslash escaping)' '-i|C:\My Files\a b.mp4' ($t.Tokens -join '|')
$t = ConvertFrom-ArgumentText '-x ; calc & dir | more `whoami` $(evil)'
Assert-True 'shell metacharacters are just ordinary tokens (nothing is ever run through a shell)' ($t.Ok -and $t.Tokens -contains ';' -and $t.Tokens -contains '&' -and $t.Tokens -contains '$(evil)')
Assert-Equal '-i is refused' 'Inputs are chosen in the file list, so -i is not needed.' (Test-CustomOptionTokens @('-i', 'x.mp4') 'Output')
Assert-True '-y is refused' ((Test-CustomOptionTokens @('-y') 'Output') -like '*Overwriting*')
Assert-True '-n is refused' ((Test-CustomOptionTokens @('-n') 'Output') -like '*Overwrite handling*')
Assert-True '-progress is refused' ((Test-CustomOptionTokens @('-progress', 'x') 'Output') -like '*Progress*')
Assert-True 'an encoder missing from the installed build is refused' ((Test-CustomOptionTokens @('-c:v', 'definitely_not_an_encoder') 'Output') -like '*not available in your FFmpeg build*')
Assert-Equal 'copy is always accepted as a codec' $null (Test-CustomOptionTokens @('-c', 'copy') 'Output')
Assert-Equal 'an available encoder is accepted' $null (Test-CustomOptionTokens @('-c:a', 'aac') 'Output')
Assert-True 'an unknown output format is refused' ((Test-CustomOptionTokens @('-f', 'no_such_format') 'Output') -like '*not available*')
Assert-Equal 'a known output format is accepted' $null (Test-CustomOptionTokens @('-f', 'matroska') 'Output')
Assert-Equal 'plain filter options are accepted' $null (Test-CustomOptionTokens @('-vf', 'scale=320:-2', '-an') 'Output')

Set-TestGroup 'Capture devices: DirectShow list parsing'
$new = "[dshow @ 000001] DirectShow video devices (some may be both video and audio devices)`n[dshow @ 000001]  `"Integrated Camera`" (video)`n[dshow @ 000001]     Alternative name `"@device_pnp_\\?\usb#vid`"`n[dshow @ 000001] DirectShow audio devices`n[dshow @ 000001]  `"Microphone Array (Realtek)`" (audio)`n[dshow @ 000001]     Alternative name `"@device_cm_{33D9}`"`n[dshow @ 000001]  `"Stereo Mix`" (audio)"
$d = ConvertFrom-DshowDeviceList $new
Assert-True 'new layout: one camera and two audio inputs, alternative names ignored' ($d.Video.Count -eq 1 -and $d.Video[0] -eq 'Integrated Camera' -and $d.Audio.Count -eq 2 -and $d.Audio[1] -eq 'Stereo Mix')
$old = "[dshow @ 0000] DirectShow video devices`n[dshow @ 0000]  `"USB Webcam`"`n[dshow @ 0000] DirectShow audio devices`n[dshow @ 0000]  `"Line In`""
$d = ConvertFrom-DshowDeviceList $old
Assert-True 'older layout (sections without (video)/(audio) suffix) is parsed too' ($d.Video[0] -eq 'USB Webcam' -and $d.Audio[0] -eq 'Line In')
$d = ConvertFrom-DshowDeviceList 'Could not enumerate devices'
Assert-True 'garbage yields empty lists, not errors' ($d.Video.Count -eq 0 -and $d.Audio.Count -eq 0)
if (-not (Test-IsWindows)) {
    Assert-True 'screen and device capture are disabled (with a reason) on a non-Windows host' ((-not (Test-ScreenCaptureAvailable)) -and (-not (Test-DeviceCaptureAvailable)))
    Skip-Test 'screen / webcam / microphone recording on Windows (gdigrab, dshow)' 'needs Windows capture devices; parsing and command building are unit tested, recording itself is UNVERIFIED here'
}

Set-TestGroup 'Analysis log parsers'
$v = ConvertFrom-VolumeDetect "[Parsed_volumedetect_0 @ 0x1] mean_volume: -23.4 dB`n[Parsed_volumedetect_0 @ 0x1] max_volume: -3.1 dB"
Assert-True 'volumedetect: mean and max' ($v.Mean -eq -23.4 -and $v.Max -eq -3.1)
$s = @(ConvertFrom-SilenceDetect "[silencedetect @ 0x1] silence_start: 1.5`n[silencedetect @ 0x1] silence_end: 4.5 | silence_duration: 3`n[silencedetect @ 0x1] silence_start: 9")
Assert-True 'silencedetect: a closed gap and one that lasts to the end' ($s.Count -eq 2 -and $s[0].Start -eq 1.5 -and $s[0].End -eq 4.5 -and $s[0].Duration -eq 3 -and $null -eq $s[1].End)
$b = @(ConvertFrom-BlackDetect "[blackdetect @ 0x1] black_start:0 black_end:2 black_duration:2`n[blackdetect @ 0x1] black_start:5.5 black_end:6 black_duration:0.5")
Assert-True 'blackdetect: two moments' ($b.Count -eq 2 -and $b[1].Start -eq 5.5 -and $b[1].Duration -eq 0.5)
$sc = @(ConvertFrom-SceneLog "[Parsed_showinfo_1 @ 0x1] n:   0 pts:  20 pts_time:2 pos: 1`n[other] pts_time:9`n[Parsed_showinfo_1 @ 0x1] n:   1 pts:  70 pts_time:7.5 pos: 2")
Assert-True 'scene log: only showinfo lines count' ($sc.Count -eq 2 -and $sc[0] -eq 2 -and $sc[1] -eq 7.5)
$c = ConvertFrom-CropDetect "[Parsed_cropdetect_0 @ 0x1] x1:0 x2:159 crop=160:90:0:35`n[Parsed_cropdetect_0 @ 0x1] x1:0 x2:159 crop=160:88:0:36"
Assert-True 'cropdetect: the last (converged) suggestion is used' ($c.W -eq 160 -and $c.H -eq 88 -and $c.Y -eq 36)
Assert-Equal 'psnr average' 38.5 (ConvertFrom-PsnrLog '[Parsed_psnr_2 @ 0x1] PSNR y:40 u:41 v:42 average:38.5 min:30 max:99')
Assert-Equal 'psnr infinity becomes 100' 100 (ConvertFrom-PsnrLog '[Parsed_psnr_2 @ 0x1] PSNR y:inf u:inf v:inf average:inf min:inf max:inf')
Assert-Equal 'ssim all' 0.9731 (ConvertFrom-SsimLog '[Parsed_ssim_2 @ 0x1] SSIM Y:0.97 U:0.98 V:0.98 All:0.9731 (15.7)')
$ln = ConvertFrom-LoudnormLog ('[Parsed_loudnorm_0 @ 0x1]' + "`n{`n`t`"input_i`" : `"-18.50`",`n`t`"input_tp`" : `"-2.10`",`n`t`"input_lra`" : `"6.00`",`n`t`"input_thresh`" : `"-28.80`"`n}")
Assert-True 'loudnorm JSON: integrated loudness, true peak, range' ($ln.I -eq -18.5 -and $ln.TP -eq -2.1 -and $ln.LRA -eq 6)
Assert-True 'an unreadable analysis log yields $null, not an exception' ($null -eq (ConvertFrom-LoudnormLog 'nothing useful') -and $null -eq (ConvertFrom-CropDetect 'nothing') -and $null -eq (ConvertFrom-PsnrLog 'x'))

Set-TestGroup 'Chapters and metadata escaping'
$c = ConvertFrom-ChapterList '00:00:00 Intro; 00:01:30 Main part; 0:05:00 End' 600
Assert-True 'chapter list parses times and titles' ($c.Ok -and $c.Chapters.Count -eq 3 -and $c.Chapters[1].Start -eq 90 -and $c.Chapters[2].Title -eq 'End')
Assert-True 'chapters must be in increasing order' (-not (ConvertFrom-ChapterList '00:02:00 B; 00:01:00 A' 600).Ok)
Assert-True 'a chapter beyond the end of the media is rejected' ((ConvertFrom-ChapterList '00:00:00 A; 00:20:00 B' 600).Error -like '*beyond the end*')
Assert-True 'a chapter without a title is rejected' (-not (ConvertFrom-ChapterList '00:00:10' 600).Ok)
Assert-True 'a bad time is rejected' ((ConvertFrom-ChapterList 'abc Title' 600).Error -like '*not a valid time*')
$txt = New-FFMetadataChapterText @(@{ Start = 0; Title = 'A=1; B#2' }, @{ Start = 10; Title = 'Second' }) 30
Assert-True 'ffmetadata chapter file: header, millisecond timebase, contiguous ranges, escaped title' (($txt -like ';FFMETADATA1*') -and $txt.Contains('START=0') -and $txt.Contains('END=10000') -and $txt.Contains('END=30000') -and $txt.Contains('title=A\=1\; B\#2'))
Assert-Equal 'metadata values escape = ; # and backslash' 'a\=b\;c\#d\\e' (ConvertTo-FFMetadataValue 'a=b;c#d\e')

Set-TestGroup 'Stream push destinations'
Assert-True 'rtmp destination is accepted when the build supports it' ($null -eq (Test-PushUrl 'rtmp://live.example.com/app/key') -or (Test-PushUrl 'rtmp://live.example.com/app/key') -like '*cannot send*')
Assert-True 'udp destination is accepted' ($null -eq (Test-PushUrl 'udp://127.0.0.1:1234'))
Assert-True 'http destination is refused with the supported list' ((Test-PushUrl 'http://x/y') -like '*not supported for sending*')
Assert-True 'not a URL is refused' ((Test-PushUrl 'C:\file.mp4') -like '*full address*')

Set-TestGroup 'Slideshow / sequence helpers'
Assert-True 'size text parses and rounds to even numbers' ((ConvertFrom-SizeText '1281 x 721').W -eq 1282 -and (ConvertFrom-SizeText '1281 x 721').H -eq 722)
Assert-True 'bad size text is refused' ($null -eq (ConvertFrom-SizeText 'big'))
$si = Get-SequenceInfo '/tmp/x/frame_%04d.png'
Assert-True 'sequence pattern is analyzed (prefix, suffix, digits)' ($si.Prefix -eq 'frame_' -and $si.Suffix -eq '.png' -and $si.Digits -eq 4)
Assert-True 'a pattern without a counter is refused' ($null -eq (Get-SequenceInfo '/tmp/x/frame.png'))

Set-TestGroup 'Capability gating: nothing depends on a filter, encoder or protocol the build lacks'
# Install a synthetic build that has almost nothing; every tool that needs a missing piece must be disabled WITH its reason.
Set-FFCapabilityData -Encoders @('libx264', 'aac', 'libmp3lame') -Muxers @('mp4', 'matroska', 'mp3') -Filters @('scale') -Protocols @('file') -HwAccels @()
$ui = Invoke-Ui { Start-VideoEnhanceWorkflow } '{Esc}' -Height 70
foreach ($need in 'yadif or bwdif', 'hqdn3d', 'vidstab', 'reverse filter') { Assert-Contains "Video Enhancement shows why a tool is disabled: $need" (Get-FlatText $ui.Output) $need }
$ui = Invoke-Ui { Start-AudioToolsWorkflow } '{Esc}' -Height 90
foreach ($need in 'loudnorm', 'afftdn', 'silenceremove') { Assert-Contains "Audio Tools shows why a tool is disabled: $need" (Get-FlatText $ui.Output) $need }
$ui = Invoke-Ui { Start-AnalyzeWorkflow } '{Esc}' -Height 70
foreach ($need in 'loudnorm', 'silencedetect', 'blackdetect', 'cropdetect', 'psnr and ssim') { Assert-Contains "Analyze & Detect shows why a tool is disabled: $need" (Get-FlatText $ui.Output) $need }
$ui = Invoke-Ui { Start-StreamingWorkflow } '{Esc}' -Height 70
Assert-Contains 'Streaming: HLS and stream-out are disabled when the build lacks the muxer/protocols' (Get-FlatText $ui.Output) 'This FFmpeg build cannot write HLS.'
Assert-Contains 'Streaming: stream-out reason is shown' (Get-FlatText $ui.Output) 'no network output protocols'
$ui = Invoke-Ui { Start-CaptureWorkflow } '{Esc}' -Height 70
Assert-True 'Record / Capture: every option is disabled with a reason when capture devices are unavailable' ((Get-FlatText $ui.Output) -match 'needs Windows')
$null = Initialize-FFCapabilities -Force
Assert-True 'the real capability set is restored after the synthetic one' ((Test-FFEncoder 'libx264') -or (Test-FFEncoder 'libopenh264') -or (Test-FFEncoder 'h264_nvenc'))
