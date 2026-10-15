# AudioEffects.psm1 - more Audio Tools: fades, equalizer, noise reduction, silence removal, frequency filters,
# audio/video sync offset and reverse. Each is a short wizard that ends in New-AudioProcessJob.
Set-StrictMode -Version 2.0

function Get-FxInputStep {
    param([string]$Prompt = 'Input file (audio, or video with audio)')
    return (Get-InputFileStep -Id 'input' -Prompt $Prompt -Require Audio -Help 'Audio files and videos with sound both work. In a video, the picture is copied unchanged.')
}

# ---- fades -------------------------------------------------------------------------------------

function Get-FadeSteps {
    $secs = { param($W) @( (New-Choice 0.0 'None' 'No fade.'), (New-Choice 1.0 '1 second' 'A quick fade.'), (New-Choice 2.0 '2 seconds  (Recommended)' 'A natural-sounding fade.'), (New-Choice 3.0 '3 seconds' 'A slow fade.'), (New-Choice 5.0 '5 seconds' 'A very slow fade.') ) }
    $steps = @(); $steps += Get-FxInputStep
    $steps += @{ Id = 'fin'; Type = 'Choice'; Prompt = 'Fade in at the start'; Help = 'The sound rises smoothly from silence instead of starting abruptly.'; Choices = $secs; Default = 2.0
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.1; Max = 600; Prompt = 'Fade-in length (seconds)'; Help = 'Between 0.1 and 600 seconds.'; Example = '1.5'; ValueLabel = 'Length'; Desc = 'For example 1.5.' } }
    $steps += @{ Id = 'fout'; Type = 'Choice'; Prompt = 'Fade out at the end'; Help = 'The sound fades smoothly to silence at the end.'; Choices = $secs; Default = 2.0
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.1; Max = 600; Prompt = 'Fade-out length (seconds)'; Help = 'Between 0.1 and 600 seconds.'; Example = '1.5'; ValueLabel = 'Length'; Desc = 'For example 1.5.' } }
    $steps += Get-AudioToolTailSteps -Suffix 'fade'
    return $steps
}

function Build-FadeJob {
    param($W)
    $info = Get-Media $W 'input'
    $fin = [double](Get-Answer $W 'fin' 0); $fout = [double](Get-Answer $W 'fout' 0)
    if ($fin -le 0 -and $fout -le 0) { throw 'Choose a fade-in or a fade-out length.' }
    if (-not $info.Duration) { throw 'The length of this file is unknown, so the fade cannot be placed.' }
    if (($fin + $fout) -gt $info.Duration) { throw ('The fades ({0:0.##} s in total) are longer than the file ({1}).' -f ($fin + $fout), (Format-Duration $info.Duration)) }
    $f = @()
    if ($fin -gt 0) { $f += ('afade=t=in:st=0:d=' + (Format-FFNumber $fin 3)) }
    if ($fout -gt 0) { $f += ('afade=t=out:st=' + (Format-FFNumber ($info.Duration - $fout) 3) + ':d=' + (Format-FFNumber $fout 3)) }
    return New-AudioProcessJob -W $W -Title 'Adding fades' -AudioFilters $f -Rows @(@('Input', $info.FileName), @('Fade in', $(if ($fin -gt 0) { "$fin s" } else { 'None' })), @('Fade out', $(if ($fout -gt 0) { "$fout s" } else { 'None' }))) -StageName 'Applying fades'
}

# ---- equalizer -----------------------------------------------------------------------------------

function Get-EqualizerSteps {
    $steps = @(); $steps += Get-FxInputStep
    $steps += @{ Id = 'eq'; Type = 'Choice'; Prompt = 'Sound adjustment'; Help = 'Bass is the low rumble, treble the bright high end. Decibel (dB) changes of 3 to 6 are clearly audible.'
        Choices = { param($W) @(
            (New-Choice 'bass' 'More bass' 'Adds +6 dB of low frequencies: fuller, warmer sound.'),
            (New-Choice 'lessbass' 'Less bass' 'Removes 6 dB of low frequencies: clearer speech, less boom.'),
            (New-Choice 'treble' 'More treble' 'Adds +5 dB of high frequencies: brighter, crisper sound.'),
            (New-Choice 'lesstreble' 'Less treble' 'Removes 5 dB of high frequencies: softer sound, less hiss.'),
            (New-Choice 'voice' 'Clearer voice' 'Cuts low rumble and boosts the speech range.'),
            (New-Choice 'custom' 'Custom bass and treble' 'You choose the decibels for each.')) }
        Default = 'bass' }
    $steps += @{ Id = 'bassdb'; Type = 'Decimal'; Prompt = 'Bass change (dB)'; Help = 'Positive = more bass, negative = less. Range -20 to +20.'; Example = '4  or  -3'; Min = -20; Max = 20; Default = 0; Label = 'Bass'; Unit = 'dB'; When = { param($W) (Get-Answer $W 'eq') -eq 'custom' } }
    $steps += @{ Id = 'trebledb'; Type = 'Decimal'; Prompt = 'Treble change (dB)'; Help = 'Positive = brighter, negative = softer. Range -20 to +20.'; Example = '3  or  -2'; Min = -20; Max = 20; Default = 0; Label = 'Treble'; Unit = 'dB'; When = { param($W) (Get-Answer $W 'eq') -eq 'custom' } }
    $steps += Get-AudioToolTailSteps -Suffix 'eq'
    return $steps
}

function Build-EqualizerJob {
    param($W)
    $info = Get-Media $W 'input'
    $eq = [string](Get-Answer $W 'eq' 'bass')
    switch ($eq) {
        'bass' { $f = @('bass=g=6'); $label = 'More bass (+6 dB)' }
        'lessbass' { $f = @('bass=g=-6'); $label = 'Less bass (-6 dB)' }
        'treble' { $f = @('treble=g=5'); $label = 'More treble (+5 dB)' }
        'lesstreble' { $f = @('treble=g=-5'); $label = 'Less treble (-5 dB)' }
        'voice' { $f = @('highpass=f=90', 'equalizer=f=2800:t=q:w=1.2:g=4'); $label = 'Clearer voice' }
        default {
            $b = [double](Get-Answer $W 'bassdb' 0); $t = [double](Get-Answer $W 'trebledb' 0)
            if ($b -eq 0 -and $t -eq 0) { throw 'Both changes are 0 dB, so nothing would change.' }
            $f = @(); if ($b -ne 0) { $f += ('bass=g=' + (Format-FFNumber $b 2)) }; if ($t -ne 0) { $f += ('treble=g=' + (Format-FFNumber $t 2)) }
            $label = ("Bass {0:+0.##;-0.##;0} dB, treble {1:+0.##;-0.##;0} dB" -f $b, $t)
        }
    }
    return New-AudioProcessJob -W $W -Title 'Adjusting tone' -AudioFilters $f -Rows @(@('Input', $info.FileName), @('Adjustment', $label)) -StageName 'Adjusting tone'
}

# ---- noise reduction ---------------------------------------------------------------------------

function Get-DenoiseAudioSteps {
    $steps = @(); $steps += Get-FxInputStep
    $steps += @{ Id = 'nr'; Type = 'Choice'; Prompt = 'Noise reduction strength'; Help = 'Removes steady background noise such as hiss or fan hum. Stronger settings can make voices sound thin.'
        Choices = { param($W) @( (New-Choice 10 'Light' 'Gentle cleanup, keeps the sound natural.'), (New-Choice 20 'Medium  (Recommended)' 'Good balance for most recordings.'), (New-Choice 30 'Strong' 'Heavy cleanup; may affect the voice.') ) }; Default = 20 }
    $steps += Get-AudioToolTailSteps -Suffix 'denoised'
    return $steps
}

function Build-DenoiseAudioJob {
    param($W)
    if (-not (Test-FFFilter 'afftdn')) { throw 'Your FFmpeg build does not include the afftdn (noise reduction) filter.' }
    $info = Get-Media $W 'input'
    $nr = [int](Get-Answer $W 'nr' 20)
    return New-AudioProcessJob -W $W -Title 'Reducing noise' -AudioFilters @("afftdn=nr=${nr}:nf=-35") -Rows @(@('Input', $info.FileName), @('Reduction', "$nr dB")) -StageName 'Reducing noise'
}

# ---- silence removal ---------------------------------------------------------------------------

function Get-SilenceSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input audio file' -Require Audio -Help 'Best for speech recordings, podcasts and lectures.' -Extra { param($info, $W) if ($info.HasVideo) { return 'Removing pauses makes the file shorter, which would put a video picture out of sync. Use an audio file, or extract the audio first.' }; $null }
    $steps += @{ Id = 'thr'; Type = 'Choice'; Prompt = 'What counts as silence?'; Help = 'Sound quieter than this level is treated as silence. Noisy recordings need a higher (less negative) level.'
        Choices = { param($W) @( (New-Choice -40 '-40 dB (noisy room)' 'Treats even fairly audible background as silence.'), (New-Choice -50 '-50 dB  (Recommended)' 'Good for normal recordings.'), (New-Choice -60 '-60 dB (very quiet)' 'Only near-total silence is removed.') ) }; Default = -50 }
    $steps += @{ Id = 'minlen'; Type = 'Choice'; Prompt = 'Shortest pause to remove'; Help = 'Pauses shorter than this are kept so speech still sounds natural.'
        Choices = { param($W) @( (New-Choice 0.5 '0.5 seconds' 'Tightens speech a lot.'), (New-Choice 1.0 '1 second  (Recommended)' 'Removes long gaps only.'), (New-Choice 2.0 '2 seconds' 'Removes only very long gaps.') ) }; Default = 1.0 }
    $steps += Get-AudioToolTailSteps -Suffix 'nosilence'
    return $steps
}

function Build-SilenceJob {
    param($W)
    if (-not (Test-FFFilter 'silenceremove')) { throw 'Your FFmpeg build does not include the silenceremove filter.' }
    $info = Get-Media $W 'input'
    $thr = [int](Get-Answer $W 'thr' -50); $min = [double](Get-Answer $W 'minlen' 1.0)
    $f = ('silenceremove=start_periods=1:start_duration=0.1:start_threshold={0}dB:stop_periods=-1:stop_duration={1}:stop_threshold={0}dB' -f $thr, (Format-FFNumber $min 2))
    return New-AudioProcessJob -W $W -Title 'Removing silence' -AudioFilters @($f) -Rows @(@('Input', $info.FileName), @('Silence level', "$thr dB"), @('Shortest pause removed', "$min s")) -StageName 'Removing silence'
}

# ---- frequency filters -------------------------------------------------------------------------

function Get-FrequencyFilterSteps {
    $steps = @(); $steps += Get-FxInputStep
    $steps += @{ Id = 'kind'; Type = 'Choice'; Prompt = 'Which frequencies should be removed?'; Help = 'Low frequencies are rumble and hum; high frequencies are hiss and whistle.'
        Choices = { param($W) @(
            (New-Choice 'low' 'Low rumble and hum' 'Removes everything below about 100 Hz (wind, traffic, mains hum).'),
            (New-Choice 'high' 'High hiss' 'Removes everything above about 10 kHz.'),
            (New-Choice 'band' 'Keep only the voice range' 'Telephone-like: keeps 300 Hz to 3.4 kHz.'),
            (New-Choice 'custom' 'Custom cut-off frequency' 'You choose a low-cut and/or high-cut frequency.')) }
        Default = 'low' }
    $steps += @{ Id = 'lowcut'; Type = 'Integer'; Prompt = 'Remove everything BELOW (Hz)'; Help = 'Low-cut frequency. Enter 0 to skip. Typical values: 80 to 200.'; Example = '120'; Min = 0; Max = 20000; Default = 100; Label = 'Low cut'; Unit = 'Hz'; When = { param($W) (Get-Answer $W 'kind') -eq 'custom' } }
    $steps += @{ Id = 'highcut'; Type = 'Integer'; Prompt = 'Remove everything ABOVE (Hz)'; Help = 'High-cut frequency. Enter 0 to skip. Typical values: 8000 to 16000.'; Example = '12000'; Min = 0; Max = 48000; Default = 0; Label = 'High cut'; Unit = 'Hz'; When = { param($W) (Get-Answer $W 'kind') -eq 'custom' } }
    $steps += Get-AudioToolTailSteps -Suffix 'filtered'
    return $steps
}

function Build-FrequencyFilterJob {
    param($W)
    $info = Get-Media $W 'input'
    switch ([string](Get-Answer $W 'kind' 'low')) {
        'low' { $f = @('highpass=f=100'); $label = 'Below 100 Hz removed' }
        'high' { $f = @('lowpass=f=10000'); $label = 'Above 10 kHz removed' }
        'band' { $f = @('highpass=f=300', 'lowpass=f=3400'); $label = 'Voice range only (300 Hz - 3.4 kHz)' }
        default {
            $lo = [int](Get-Answer $W 'lowcut' 0); $hi = [int](Get-Answer $W 'highcut' 0)
            if ($lo -le 0 -and $hi -le 0) { throw 'Enter a low-cut or a high-cut frequency.' }
            if ($lo -gt 0 -and $hi -gt 0 -and $lo -ge $hi) { throw 'The low-cut frequency must be lower than the high-cut frequency.' }
            $f = @(); $parts = @()
            if ($lo -gt 0) { $f += "highpass=f=$lo"; $parts += "below $lo Hz" }
            if ($hi -gt 0) { $f += "lowpass=f=$hi"; $parts += "above $hi Hz" }
            $label = (($parts -join ' and ') + ' removed')
        }
    }
    return New-AudioProcessJob -W $W -Title 'Filtering frequencies' -AudioFilters $f -Rows @(@('Input', $info.FileName), @('Filter', $label)) -StageName 'Filtering audio'
}

# ---- sync offset ---------------------------------------------------------------------------------

function Get-SyncOffsetSteps {
    $steps = @(); $steps += Get-FxInputStep -Prompt 'Video (or audio) whose sound is out of sync'
    $steps += @{ Id = 'offset'; Type = 'Decimal'; Prompt = 'Shift the audio by (seconds)'; Label = 'Shift'; Unit = 'seconds'; Min = -60; Max = 60; Example = '0.4  or  -0.25'
        Help = 'Positive = the sound plays LATER (use when the sound comes too early). Negative = the sound plays EARLIER (use when the sound lags behind the picture).'
        Validate = { param($v, $W) if ($v -eq 0) { return 'A shift of 0 changes nothing.' }; $null } }
    $steps += Get-AudioToolTailSteps -Suffix 'synced'
    return $steps
}

function Build-SyncOffsetJob {
    param($W)
    $info = Get-Media $W 'input'
    $o = [double](Get-Answer $W 'offset' 0)
    if ($o -eq 0) { throw 'A shift of 0 changes nothing.' }
    if ($o -gt 0) { $ms = [int][math]::Round($o * 1000); $f = "adelay=${ms}:all=1" }
    else { $f = 'atrim=start=' + (Format-FFNumber (-$o) 3) + ',asetpts=PTS-STARTPTS' }
    return New-AudioProcessJob -W $W -Title 'Shifting audio' -AudioFilters @($f) -Rows @(@('Input', $info.FileName), @('Shift', ("{0:+0.###;-0.###} s ({1})" -f $o, $(if ($o -gt 0) { 'later' } else { 'earlier' })))) -StageName 'Shifting audio'
}

# ---- reverse ----------------------------------------------------------------------------------------

function Get-ReverseAudioSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input audio file' -Require Audio -Help 'The whole file is loaded into memory to be played backwards, so use short clips (up to 10 minutes).' -Extra {
        param($info, $W) if ($info.HasVideo) { return 'Reversing the sound of a video would break the sync with the picture. Use an audio file.' }
        if ($info.Duration -and $info.Duration -gt 600) { return 'This file is longer than 10 minutes. Trim it first (Trim / Cut Media).' }; $null }
    $steps += Get-AudioToolTailSteps -Suffix 'reversed'
    return $steps
}

function Build-ReverseAudioJob {
    param($W)
    $info = Get-Media $W 'input'
    return New-AudioProcessJob -W $W -Title 'Reversing audio' -AudioFilters @('areverse') -Rows @(@('Input', $info.FileName), @('Effect', 'Play backwards')) -StageName 'Reversing audio'
}

function Get-AudioEffectMenuItems {
    return @(
        @{ Label = 'Fade In / Fade Out'; Icon = 'Speed'; Desc = 'Start or end the sound smoothly instead of abruptly.'; Value = { Start-StandardWorkflow -Title 'Fade In / Fade Out' -Description 'Add smooth fades.' -Icon 'AudioTools' -StepsFactory { Get-FadeSteps } -Build { param($W) Build-FadeJob $W } } },
        @{ Label = 'Bass / Treble / Voice Clarity'; Icon = 'AudioTools'; Desc = 'Make sound fuller, brighter or clearer with simple tone controls.'; Value = { Start-StandardWorkflow -Title 'Bass / Treble' -Description 'Adjust the tone.' -Icon 'AudioTools' -StepsFactory { Get-EqualizerSteps } -Build { param($W) Build-EqualizerJob $W } } },
        @{ Label = 'Reduce Background Noise'; Icon = 'Filters'; Desc = 'Clean up steady hiss or hum in a recording.'; Enabled = (Test-FFFilter 'afftdn'); Reason = 'Requires the afftdn filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Reduce Background Noise' -Description 'Clean up a noisy recording.' -Icon 'Filters' -StepsFactory { Get-DenoiseAudioSteps } -Build { param($W) Build-DenoiseAudioJob $W } } },
        @{ Label = 'Remove Silence'; Icon = 'Cut'; Desc = 'Cut out long pauses in speech, podcasts or lectures.'; Enabled = (Test-FFFilter 'silenceremove'); Reason = 'Requires the silenceremove filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Remove Silence' -Description 'Cut long pauses from audio.' -Icon 'Cut' -StepsFactory { Get-SilenceSteps } -Build { param($W) Build-SilenceJob $W } } },
        @{ Label = 'Remove Rumble / Hiss (Frequency Filter)'; Icon = 'Filters'; Desc = 'Cut low rumble or high hiss, or keep only the voice range.'; Value = { Start-StandardWorkflow -Title 'Frequency Filter' -Description 'Remove unwanted frequencies.' -Icon 'Filters' -StepsFactory { Get-FrequencyFilterSteps } -Build { param($W) Build-FrequencyFilterJob $W } } },
        @{ Label = 'Fix Audio / Video Sync'; Icon = 'Retry'; Desc = 'Shift the sound earlier or later when it does not match the picture.'; Value = { Start-StandardWorkflow -Title 'Fix Audio / Video Sync' -Description 'Shift the sound in time.' -Icon 'Retry' -StepsFactory { Get-SyncOffsetSteps } -Build { param($W) Build-SyncOffsetJob $W } } },
        @{ Label = 'Reverse Audio'; Icon = 'Rotate'; Desc = 'Play a short audio clip backwards.'; Value = { Start-StandardWorkflow -Title 'Reverse Audio' -Description 'Play audio backwards.' -Icon 'Rotate' -StepsFactory { Get-ReverseAudioSteps } -Build { param($W) Build-ReverseAudioJob $W } } }
    )
}

Export-ModuleMember -Function Get-FadeSteps, Build-FadeJob, Get-EqualizerSteps, Build-EqualizerJob, Get-DenoiseAudioSteps, Build-DenoiseAudioJob, Get-SilenceSteps, Build-SilenceJob, Get-FrequencyFilterSteps, Build-FrequencyFilterJob, Get-SyncOffsetSteps, Build-SyncOffsetJob, Get-ReverseAudioSteps, Build-ReverseAudioJob, Get-AudioEffectMenuItems
