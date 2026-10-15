# CaptureMedia.psm1 - Record / Capture: screen, webcam and microphone recording with Windows capture devices
# (gdigrab and DirectShow). Recordings always have a fixed length so the file is finished cleanly.
Set-StrictMode -Version 2.0

function ConvertFrom-DshowDeviceList {
    # Parses 'ffmpeg -list_devices true -f dshow -i dummy' output (both the older section layout and the newer
    # '"name" (video)' layout). Returns @{ Video = @(names); Audio = @(names) }.
    param([string]$Text)
    $video = @(); $audio = @(); $section = ''
    foreach ($l in ($Text -split "`r?`n")) {
        if ($l -match 'Alternative name') { continue }
        if ($l -match 'DirectShow video devices') { $section = 'video'; continue }
        if ($l -match 'DirectShow audio devices') { $section = 'audio'; continue }
        $m = [regex]::Match($l, '"([^"]+)"\s*\((video|audio|none)\)')
        if ($m.Success) {
            $kind = $m.Groups[2].Value
            if ($kind -eq 'video') { $video += $m.Groups[1].Value } elseif ($kind -eq 'audio') { $audio += $m.Groups[1].Value }
            continue
        }
        $m = [regex]::Match($l, '\]\s+"([^"]+)"\s*$')
        if ($m.Success) {
            if ($section -eq 'video') { $video += $m.Groups[1].Value } elseif ($section -eq 'audio') { $audio += $m.Groups[1].Value }
        }
    }
    return @{ Video = @($video | Select-Object -Unique); Audio = @($audio | Select-Object -Unique) }
}

function Get-CaptureDevices {
    # Device names are read from FFmpeg itself (DirectShow). Empty lists when unavailable.
    if (-not (Test-IsWindows) -or -not (Test-FFDemuxer 'dshow')) { return @{ Video = @(); Audio = @() } }
    $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy') -TimeoutSec 30
    return (ConvertFrom-DshowDeviceList ($r.StdErr + "`n" + $r.StdOut))
}

function Test-ScreenCaptureAvailable { return ((Test-IsWindows) -and (Test-FFDemuxer 'gdigrab')) }
function Test-DeviceCaptureAvailable { return ((Test-IsWindows) -and (Test-FFDemuxer 'dshow')) }

function Get-DeviceCache {
    param($W)
    if (-not $W.Data.ContainsKey('devices')) { $W.Data['devices'] = Get-CaptureDevices }
    return $W.Data['devices']
}

function Get-RecordingLengthStep {
    return @{ Id = 'length'; Type = 'Timestamp'; Prompt = 'Recording length'; Label = 'Length'; Example = '00:05:00  or  300  or  5:00'
        Help = 'How long to record. The recording stops by itself after this time so the file is always complete. You can cancel earlier with Esc, but a cancelled recording may be unfinished.'
        Validate = { param($v, $W) if ($v -le 0) { return 'The length must be greater than zero.' }; if ($v -gt 43200) { return 'The maximum recording length is 12 hours.' }; $null } }
}

function Set-RecordingOutputDefaults {
    # There is no source file, so name the recording after the date and save next to the current folder.
    param($Steps, [string]$Base)
    $b = $Base
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        if ($Steps[$i].Id -eq 'outdir') {
            $Steps[$i].Choices = { param($W) @( (New-Choice ((Get-Location).ProviderPath) 'Current folder' ((Get-Location).ProviderPath)) ) }
            $Steps[$i].Default = { param($W) (Get-Location).ProviderPath }
        }
        if ($Steps[$i].Id -eq 'outname') {
            $Steps[$i].Default = { param($W) $b + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }.GetNewClosure()
        }
    }
    return $Steps
}

function Get-MicChoices {
    param($W)
    $l = @( (New-Choice '' 'No sound' 'Record the picture only.') )
    foreach ($a in @((Get-DeviceCache $W).Audio)) { $l += , (New-Choice $a $a 'Record sound from this device too.') }
    return $l
}

# ---- screen ------------------------------------------------------------------------------------------

function Get-ScreenRecordSteps {
    $steps = @()
    $steps += Get-RecordingLengthStep
    $steps += @{ Id = 'fps'; Type = 'Choice'; Prompt = 'Frames per second'; Help = 'Higher rates look smoother but make bigger files and need a faster computer.'
        Choices = { param($W) @( (New-Choice 15 '15 FPS' 'Light; fine for tutorials.'), (New-Choice 30 '30 FPS  (Recommended)' 'Smooth for most screen recordings.'), (New-Choice 60 '60 FPS' 'For games and fast motion.') ) }; Default = 30 }
    $steps += @{ Id = 'mouse'; Type = 'YesNo'; Prompt = 'Show the mouse pointer?'; Help = 'Include the cursor in the recording.'; Default = $true; YesLabel = 'Yes, show the pointer'; NoLabel = 'No, hide the pointer'; YesDesc = 'Good for tutorials.'; NoDesc = 'Cleaner picture.' }
    $steps += @{ Id = 'mic'; Type = 'Choice'; Prompt = 'Record sound from a microphone?'; Help = 'Screen capture has no sound of its own. Pick a microphone (or another recording device) to add voice.'
        Choices = { param($W) @(Get-MicChoices $W) }; Default = '' }
    $steps += Get-EasyVideoEncoding -Suffix 'screen' -InputId 'none'
    return (Set-RecordingOutputDefaults $steps 'screen_recording')
}

function Build-ScreenRecordJob {
    param($W)
    if (-not (Test-ScreenCaptureAvailable)) { throw 'Screen recording needs Windows and an FFmpeg build with gdigrab.' }
    $len = [double](Get-Answer $W 'length'); $fps = [int](Get-Answer $W 'fps' 30)
    $container = [string](Get-Answer $W 'format' 'mp4'); $c = Get-VideoContainer $container
    $mic = [string](Get-Answer $W 'mic' '')
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd 'desktop' @('-f', 'gdigrab', '-framerate', [string]$fps, '-draw_mouse', $(if ([bool](Get-Answer $W 'mouse' $true)) { '1' } else { '0' })))
    if ($mic) { [void](Add-FFInput $cmd ('audio=' + $mic) @('-f', 'dshow')) }
    Add-FFOutOpt $cmd @('-t', (Format-FFNumber $len 3), '-map', '0:v')
    Add-FFOutOpt $cmd @('-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p')
    Add-FFOutOpt $cmd (Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true).Tokens
    if ($mic) { Add-FFOutOpt $cmd (@('-map', '1:a') + (Get-AutoAudioTokens $container)) }
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @('Switch to the window you want to record after pressing Start; the recording begins immediately.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Source', 'Whole desktop'), @('Length', (Format-Duration $len)), @('Frame rate', "$fps FPS"), @('Sound', $(if ($mic) { $mic } else { 'None' })), @('Output', $out.Path))
    return New-JobObject -Title 'Recording screen' -Summary $rows -Stages @(@{ Name = 'Recording'; Arguments = (Get-FFTokens $cmd); DurationSec = $len }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

# ---- webcam -------------------------------------------------------------------------------------------

function Get-WebcamSteps {
    $steps = @()
    $steps += @{ Id = 'cam'; Type = 'Choice'; Prompt = 'Which camera?'; Help = 'Cameras found by Windows (DirectShow).'
        Choices = { param($W) $v = @((Get-DeviceCache $W).Video); if ($v.Count -eq 0) { return @(New-Choice '' 'No camera found' 'Connect a camera and try again.' $false 'No DirectShow camera was detected.') }; @($v | ForEach-Object { New-Choice $_ $_ 'Record from this camera.' }) }
        Validate = { param($v, $W) if (-not $v) { return 'No camera is available.' }; $null } }
    $steps += @{ Id = 'mic'; Type = 'Choice'; Prompt = 'Record sound too?'; Help = 'Pick a microphone to record voice together with the picture.'
        Choices = { param($W) @(Get-MicChoices $W) }; Default = '' }
    $steps += Get-RecordingLengthStep
    $steps += @{ Id = 'fps'; Type = 'Choice'; Prompt = 'Frames per second'; Help = 'Most webcams support 30. If FFmpeg reports an error, try 15 or 25.'
        Choices = { param($W) @( (New-Choice 15 '15 FPS' 'Light on the computer; fine for slow screen content.'), (New-Choice 25 '25 FPS' 'Standard video rate in many countries.'), (New-Choice 30 '30 FPS  (Recommended)' 'Smooth and widely supported.') ) }; Default = 30 }
    $steps += Get-EasyVideoEncoding -Suffix 'webcam' -InputId 'none'
    return (Set-RecordingOutputDefaults $steps 'webcam_recording')
}

function Build-WebcamJob {
    param($W)
    $len = [double](Get-Answer $W 'length'); $fps = [int](Get-Answer $W 'fps' 30)
    $cam = [string](Get-Answer $W 'cam'); $mic = [string](Get-Answer $W 'mic' '')
    if (-not $cam) { throw 'No camera selected.' }
    $container = [string](Get-Answer $W 'format' 'mp4'); $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $spec = 'video=' + $cam; if ($mic) { $spec += ':audio=' + $mic }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $spec @('-f', 'dshow', '-framerate', [string]$fps, '-t', (Format-FFNumber $len 3)))
    Add-FFOutOpt $cmd @('-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p')
    Add-FFOutOpt $cmd (Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true).Tokens
    if ($mic) { Add-FFOutOpt $cmd (Get-AutoAudioTokens $container) }
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Camera', $cam), @('Sound', $(if ($mic) { $mic } else { 'None' })), @('Length', (Format-Duration $len)), @('Output', $out.Path))
    return New-JobObject -Title 'Recording webcam' -Summary $rows -Stages @(@{ Name = 'Recording'; Arguments = (Get-FFTokens $cmd); DurationSec = $len }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

# ---- microphone -----------------------------------------------------------------------------------------

function Get-MicRecordSteps {
    $steps = @()
    $steps += @{ Id = 'mic'; Type = 'Choice'; Prompt = 'Which recording device?'; Help = 'Microphones and other audio inputs found by Windows (DirectShow).'
        Choices = { param($W) $a = @((Get-DeviceCache $W).Audio); if ($a.Count -eq 0) { return @(New-Choice '' 'No recording device found' 'Connect a microphone and try again.' $false 'No DirectShow audio device was detected.') }; @($a | ForEach-Object { New-Choice $_ $_ 'Record from this device.' }) }
        Validate = { param($v, $W) if (-not $v) { return 'No recording device is available.' }; $null } }
    $steps += Get-RecordingLengthStep
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Audio file type'; Help = 'WAV is uncompressed and safest for editing; MP3 and M4A are small.'
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'wav' }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'wav')); if ($f) { @($f.Codecs) } else { @() } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'none' -Suffix 'recording' -ProtectIds @() -Extension { param($W) (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'wav'))).Ext }
    return (Set-RecordingOutputDefaults $steps 'voice_recording')
}

function Build-MicRecordJob {
    param($W)
    $len = [double](Get-Answer $W 'length'); $mic = [string](Get-Answer $W 'mic')
    if (-not $mic) { throw 'No recording device selected.' }
    $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'wav'))
    $out = Get-OutputFile $W
    $ae = Resolve-AudioEncode $W -Prefix 'a' -Container '' -AllowedFamilies @($f.Codecs) -HasAudio $true
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd ('audio=' + $mic) @('-f', 'dshow', '-t', (Format-FFNumber $len 3)))
    Add-FFOutOpt $cmd $ae.Tokens
    Add-FFOutOpt $cmd @('-f', $f.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Device', $mic), @('Length', (Format-Duration $len)), @('Format', $f.Label), @('Output', $out.Path))
    return New-JobObject -Title 'Recording audio' -Summary $rows -Stages @(@{ Name = 'Recording'; Arguments = (Get-FFTokens $cmd); DurationSec = $len }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

function Show-CaptureDevices {
    $d = Get-CaptureDevices
    $lines = @('Capture devices reported by FFmpeg (DirectShow)', '', 'Cameras:')
    if ($d.Video.Count -eq 0) { $lines += '  (none found)' } else { foreach ($v in $d.Video) { $lines += ('  ' + $v) } }
    $lines += ''; $lines += 'Microphones and audio inputs:'
    if ($d.Audio.Count -eq 0) { $lines += '  (none found)' } else { foreach ($a in $d.Audio) { $lines += ('  ' + $a) } }
    $lines += ''; $lines += 'Screen capture (gdigrab): ' + $(if (Test-ScreenCaptureAvailable) { 'available' } else { 'not available' })
    Show-TextViewer -Title 'Capture devices' -Lines $lines
}

function Start-CaptureWorkflow {
    $items = @(
        @{ Label = 'Record the Screen'; Icon = 'Record'; Desc = 'Record the whole desktop for a set time, optionally with microphone sound.'; Enabled = (Test-ScreenCaptureAvailable); Reason = 'Screen recording needs Windows and an FFmpeg build with gdigrab.'; Value = { Start-StandardWorkflow -Title 'Record the Screen' -Description 'Record the desktop.' -Icon 'Record' -StepsFactory { Get-ScreenRecordSteps } -Build { param($W) Build-ScreenRecordJob $W } } },
        @{ Label = 'Record from a Webcam'; Icon = 'Video'; Desc = 'Record a camera (and optionally a microphone) for a set time.'; Enabled = (Test-DeviceCaptureAvailable); Reason = 'Device recording needs Windows and an FFmpeg build with DirectShow (dshow).'; Value = { Start-StandardWorkflow -Title 'Record from a Webcam' -Description 'Record a camera.' -Icon 'Video' -StepsFactory { Get-WebcamSteps } -Build { param($W) Build-WebcamJob $W } } },
        @{ Label = 'Record Audio from a Microphone'; Icon = 'Audio'; Desc = 'Record voice or any audio input to WAV, MP3, M4A or another audio file.'; Enabled = (Test-DeviceCaptureAvailable); Reason = 'Device recording needs Windows and an FFmpeg build with DirectShow (dshow).'; Value = { Start-StandardWorkflow -Title 'Record Audio' -Description 'Record from a microphone.' -Icon 'Audio' -StepsFactory { Get-MicRecordSteps } -Build { param($W) Build-MicRecordJob $W } } },
        @{ Label = 'List Capture Devices'; Icon = 'Search'; Desc = 'Show the cameras and microphones FFmpeg can see.'; Enabled = (Test-DeviceCaptureAvailable); Reason = 'Device listing needs Windows and an FFmpeg build with DirectShow (dshow).'; Value = { Show-CaptureDevices } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Record') + '  Record / Capture') -Subtitle 'Record the screen, a camera or a microphone for a chosen length of time.' -Items $items
}

Export-ModuleMember -Function ConvertFrom-DshowDeviceList, Get-CaptureDevices, Test-ScreenCaptureAvailable, Test-DeviceCaptureAvailable, Get-ScreenRecordSteps, Build-ScreenRecordJob, Get-WebcamSteps, Build-WebcamJob, Get-MicRecordSteps, Build-MicRecordJob, Show-CaptureDevices, Start-CaptureWorkflow
