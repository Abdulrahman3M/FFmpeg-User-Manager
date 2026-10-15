# AnalyzeMedia.psm1 - Analyze & Detect: read-only checks that run FFmpeg filters to a null output and report
# what they find (volume, silence, black frames, scene changes, crop area, loudness, PSNR/SSIM quality).
# Nothing is written to disk and the source file is never modified.
Set-StrictMode -Version 2.0

$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-Dbl {
    param([string]$Text)
    $d = 0.0
    if ([double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
    return $null
}

# ---- parsers (pure functions, unit tested) -------------------------------------------------------

function ConvertFrom-VolumeDetect {
    param([string]$Log)
    $r = @{ Mean = $null; Max = $null }
    $m = [regex]::Match($Log, 'mean_volume:\s*(-?[\d.]+|-inf) dB'); if ($m.Success) { $r.Mean = ConvertTo-Dbl $m.Groups[1].Value }
    $m = [regex]::Match($Log, 'max_volume:\s*(-?[\d.]+|-inf) dB'); if ($m.Success) { $r.Max = ConvertTo-Dbl $m.Groups[1].Value }
    return $r
}

function ConvertFrom-SilenceDetect {
    # -> @(@{ Start; End; Duration })
    param([string]$Log)
    $out = @(); $start = $null
    foreach ($l in ($Log -split "`r?`n")) {
        $m = [regex]::Match($l, 'silence_start:\s*(-?[\d.]+)'); if ($m.Success) { $start = ConvertTo-Dbl $m.Groups[1].Value; continue }
        $m = [regex]::Match($l, 'silence_end:\s*(-?[\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)')
        if ($m.Success -and $null -ne $start) { $out += , @{ Start = $start; End = (ConvertTo-Dbl $m.Groups[1].Value); Duration = (ConvertTo-Dbl $m.Groups[2].Value) }; $start = $null }
    }
    if ($null -ne $start) { $out += , @{ Start = $start; End = $null; Duration = $null } }
    return $out
}

function ConvertFrom-BlackDetect {
    param([string]$Log)
    $out = @()
    foreach ($m in [regex]::Matches($Log, 'black_start:\s*([\d.]+)\s+black_end:\s*([\d.]+)\s+black_duration:\s*([\d.]+)')) {
        $out += , @{ Start = (ConvertTo-Dbl $m.Groups[1].Value); End = (ConvertTo-Dbl $m.Groups[2].Value); Duration = (ConvertTo-Dbl $m.Groups[3].Value) }
    }
    return $out
}

function ConvertFrom-SceneLog {
    # showinfo lines: 'n:  3 pts: ... pts_time:12.48 ...'
    param([string]$Log)
    $out = @()
    foreach ($l in ($Log -split "`r?`n")) {
        if ($l -notmatch 'Parsed_showinfo') { continue }
        $m = [regex]::Match($l, 'pts_time:\s*(-?[\d.]+)'); if ($m.Success) { $out += (ConvertTo-Dbl $m.Groups[1].Value) }
    }
    return $out
}

function ConvertFrom-CropDetect {
    # Returns the last reported 'crop=W:H:X:Y' (cropdetect with reset=0 converges on the largest area) or $null.
    param([string]$Log)
    $ms = [regex]::Matches($Log, 'crop=(\d+):(\d+):(\d+):(\d+)')
    if ($ms.Count -eq 0) { return $null }
    $m = $ms[$ms.Count - 1]
    return @{ W = [int]$m.Groups[1].Value; H = [int]$m.Groups[2].Value; X = [int]$m.Groups[3].Value; Y = [int]$m.Groups[4].Value }
}

function ConvertFrom-PsnrLog {
    param([string]$Log)
    $m = [regex]::Match($Log, 'PSNR.*?average:(inf|[\d.]+)')
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Value -eq 'inf') { return 100.0 }
    return (ConvertTo-Dbl $m.Groups[1].Value)
}

function ConvertFrom-SsimLog {
    param([string]$Log)
    $m = [regex]::Match($Log, 'SSIM.*?All:([\d.]+)')
    if (-not $m.Success) { return $null }
    return (ConvertTo-Dbl $m.Groups[1].Value)
}

function ConvertFrom-LoudnormLog {
    param([string]$Log)
    $m = [regex]::Match($Log, '\{[^{}]*"input_i"[^{}]*\}')
    if (-not $m.Success) { return $null }
    try { $j = $m.Value | ConvertFrom-Json } catch { return $null }
    return @{ I = (ConvertTo-Dbl ([string]$j.input_i)); TP = (ConvertTo-Dbl ([string]$j.input_tp)); LRA = (ConvertTo-Dbl ([string]$j.input_lra)); Thresh = (ConvertTo-Dbl ([string]$j.input_thresh)) }
}

function Format-TimeSpanList {
    param($Items, [string]$Noun)
    $lines = @()
    $i = 0
    foreach ($x in $Items) {
        $i++
        if ($null -eq $x.End) { $lines += ('  {0,3}. {1} - until the end' -f $i, (Format-Duration $x.Start)) }
        else { $lines += ('  {0,3}. {1} - {2}   ({3:0.##} s)' -f $i, (Format-Duration $x.Start), (Format-Duration $x.End), $x.Duration) }
    }
    return $lines
}

# ---- runner ----------------------------------------------------------------------------------------------

function Invoke-AnalysisPass {
    # Runs one FFmpeg analysis (output to null) with a progress screen; returns @{ Ok; Log; Cancelled; Error }.
    param([string]$Title, [string]$StageText, [string[]]$FfArgs, $TotalSec)
    $state = @{ Tick = 0 }
    $onTick = {
        param($s)
        $state.Tick++
        Show-JobProgress -Title $Title -StageText $StageText -Percent $s.Percent -OutTime $s.OutTime -TotalSec $s.TotalSec -Speed $s.Speed -Elapsed $s.Elapsed -Tick $state.Tick -Status 'Analyzing'
        if (Test-TuiKeyAvailable) { $k = Read-TuiKey; if ($k.Name -eq 'Esc' -or $k.Name -eq 'CtrlC') { return $true } }
        return $false
    }.GetNewClosure()
    $r = Invoke-FFmpegStage -FfmpegPath (Get-FFmpegPath) -Arguments (@('-nostdin', '-loglevel', 'info') + $FfArgs) -TotalSec $TotalSec -OnTick $onTick
    try { Show-Cursor } catch { }
    if ($r.Cancelled) { return @{ Ok = $false; Log = ''; Cancelled = $true; Error = '' } }
    if (-not $r.Started) { return @{ Ok = $false; Log = ''; Cancelled = $false; Error = $r.Error } }
    if ($r.ExitCode -ne 0) { return @{ Ok = $false; Log = $r.StdErr; Cancelled = $false; Error = (Get-FFmpegFailureReason $r.StdErr $r.ExitCode) } }
    return @{ Ok = $true; Log = $r.StdErr; Cancelled = $false; Error = '' }
}

function Start-AnalysisTool {
    # $Steps: wizard steps. $Plan: scriptblock ($W) -> @{ Title; Passes = @(@{ Name; Args }); Duration; Report = { param($logs) -> lines } }
    param([string]$Title, [string]$Description, [string]$Icon, [object[]]$Steps, [scriptblock]$Plan)
    while ($true) {
        $r = Invoke-Wizard -Title $Title -Description $Description -Icon $Icon -Steps $Steps
        if ($r.Status -ne 'Completed') { return }
        $spec = $null
        try { $spec = & $Plan $r.State } catch { $null = Show-Notice -Title 'This analysis cannot be run' -Lines @($_.Exception.Message) -Kind Warning; continue }
        $logs = @(); $failed = $false; $n = 0
        foreach ($p in $spec.Passes) {
            $n++
            $res = Invoke-AnalysisPass -Title $spec.Title -StageText ('Pass {0} of {1}: {2}' -f $n, @($spec.Passes).Count, $p.Name) -FfArgs $p.Args -TotalSec $spec.Duration
            if ($res.Cancelled) { $null = Show-Notice -Title 'Analysis cancelled' -Lines @('No changes were made to any file.') -Kind Warning; $failed = $true; break }
            if (-not $res.Ok) { $null = Show-Notice -Title 'The analysis failed' -Lines @('Reason:', $res.Error) -Kind Error; $failed = $true; break }
            $logs += , $res.Log
        }
        if ($failed) { continue }
        $lines = @(& $spec.Report $logs)
        Show-TextViewer -Title $spec.Title -Lines $lines
        $again = Show-Confirm -Title 'Analyze another file?' -Lines @('Choose Yes to run this analysis again with different settings.') -Default $false -Kind Info
        if (-not $again) { return }
    }
}

# ---- individual tools ------------------------------------------------------------------------------------

function Start-VolumeAnalysis {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Audio or video file' -Require Audio -Help 'Measures how loud the sound is. Nothing is changed.'
    Start-AnalysisTool -Title 'Measure Volume' -Description 'Find the average and peak volume of a file.' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        $m = Get-Media $W 'input'
        @{ Title = 'Measuring volume'; Duration = $m.Duration
            Passes = @(@{ Name = 'Reading audio'; Args = @('-i', $m.Path, '-map', ('0:' + $m.Audio[0].Index), '-vn', '-af', 'volumedetect', '-f', 'null', '-') })
            Report = { param($logs)
                $v = ConvertFrom-VolumeDetect $logs[0]
                $l = @('Volume report', '')
                if ($null -eq $v.Mean) { return @('The volume could not be measured.') }
                $l += ('Average (mean) volume : {0:0.#} dB' -f $v.Mean)
                $l += ('Loudest peak          : {0:0.#} dB' -f $v.Max)
                $l += ''
                if ($v.Max -ge -0.1) { $l += 'The peak touches 0 dB, so the audio may be clipping (distorted). Consider lowering the volume.' }
                elseif ($v.Max -lt -10) { $l += ('There is {0:0.#} dB of unused headroom. You can raise the volume by up to about {1:0.#} dB before clipping (Audio Tools, Adjust Volume).' -f (-$v.Max), ([math]::Floor(-$v.Max - 1))) }
                else { $l += 'The level looks healthy.' }
                return $l } } }
}

function Start-LoudnessAnalysis {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Audio or video file' -Require Audio -Help 'Measures perceived loudness in LUFS, the unit streaming services use. Nothing is changed.'
    Start-AnalysisTool -Title 'Measure Loudness (LUFS)' -Description 'Check loudness the way streaming platforms do.' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        if (-not (Test-FFFilter 'loudnorm')) { throw 'Your FFmpeg build does not include the loudnorm filter used for this measurement.' }
        $m = Get-Media $W 'input'
        @{ Title = 'Measuring loudness'; Duration = $m.Duration
            Passes = @(@{ Name = 'Reading audio'; Args = @('-i', $m.Path, '-map', ('0:' + $m.Audio[0].Index), '-vn', '-af', 'loudnorm=print_format=json', '-f', 'null', '-') })
            Report = { param($logs)
                $v = ConvertFrom-LoudnormLog $logs[0]
                if (-not $v -or $null -eq $v.I) { return @('The loudness could not be measured (the audio may be silent).') }
                $l = @('Loudness report', '')
                $l += ('Integrated loudness : {0:0.#} LUFS' -f $v.I)
                $l += ('True peak           : {0:0.#} dBTP' -f $v.TP)
                $l += ('Loudness range      : {0:0.#} LU' -f $v.LRA)
                $l += ''
                $l += 'Typical targets: -16 LUFS podcasts and streaming, -14 LUFS music platforms, -23 LUFS broadcast.'
                $l += 'To reach a target, use Audio Tools, Normalize Loudness.'
                return $l } } }
}

function Start-SilenceAnalysis {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Audio or video file' -Require Audio -Help 'Lists the quiet gaps in a recording with their start and end times. Nothing is changed.'
    $steps += @{ Id = 'noise'; Type = 'Choice'; Prompt = 'What counts as silence?'; Help = 'Sound quieter than this level is silence. Noisy recordings need a less negative level.'
        Choices = { param($W) @( (New-Choice -40 '-40 dB (noisy room)' 'Treats fairly audible background sound as silence.'), (New-Choice -50 '-50 dB  (Recommended)' 'Good for normal recordings.'), (New-Choice -60 '-60 dB (very quiet)' 'Only near-total silence counts.') ) }; Default = -50 }
    $steps += @{ Id = 'mind'; Type = 'Choice'; Prompt = 'Shortest gap to report'; Help = 'Shorter quiet moments are ignored.'
        Choices = { param($W) @( (New-Choice 0.5 '0.5 seconds' 'Report even short gaps.'), (New-Choice 1.0 '1 second  (Recommended)' 'Report gaps of a second or longer.'), (New-Choice 2.0 '2 seconds' 'Report only long gaps.') ) }; Default = 1.0 }
    Start-AnalysisTool -Title 'Detect Silence' -Description 'Find quiet gaps in audio.' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        $m = Get-Media $W 'input'
        $noise = [int](Get-Answer $W 'noise' -50); $d = [double](Get-Answer $W 'mind' 1.0)
        @{ Title = 'Detecting silence'; Duration = $m.Duration
            Passes = @(@{ Name = 'Listening'; Args = @('-i', $m.Path, '-map', ('0:' + $m.Audio[0].Index), '-vn', '-af', ("silencedetect=noise=${noise}dB:d=" + (Format-FFNumber $d 2)), '-f', 'null', '-') })
            Report = { param($logs)
                $s = @(ConvertFrom-SilenceDetect $logs[0])
                $l = @("Silence report ($($s.Count) gap(s) found)", '')
                if ($s.Count -eq 0) { $l += 'No silent gaps were found with these settings.' } else { $l += Format-TimeSpanList $s 'gap' }
                return $l } } }
}

function Start-BlackAnalysis {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Lists moments where the picture is black (fades, dropouts, scene gaps). Nothing is changed.'
    $steps += @{ Id = 'mind'; Type = 'Choice'; Prompt = 'Shortest black moment to report'; Help = 'Shorter black flashes are ignored.'
        Choices = { param($W) @( (New-Choice 0.1 '0.1 seconds' 'Report even very short black flashes.'), (New-Choice 0.5 '0.5 seconds  (Recommended)' 'Report black moments of half a second or more.'), (New-Choice 1.0 '1 second' 'Report only long black moments.') ) }; Default = 0.5 }
    Start-AnalysisTool -Title 'Detect Black Frames' -Description 'Find black moments in a video.' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        if (-not (Test-FFFilter 'blackdetect')) { throw 'Your FFmpeg build does not include the blackdetect filter.' }
        $m = Get-Media $W 'input'; $d = [double](Get-Answer $W 'mind' 0.5)
        @{ Title = 'Detecting black frames'; Duration = $m.Duration
            Passes = @(@{ Name = 'Watching'; Args = @('-i', $m.Path, '-map', ('0:' + $m.Video[0].Index), '-an', '-vf', ('blackdetect=d=' + (Format-FFNumber $d 2) + ':pix_th=0.10'), '-f', 'null', '-') })
            Report = { param($logs)
                $b = @(ConvertFrom-BlackDetect $logs[0])
                $l = @("Black moments ($($b.Count) found)", '')
                if ($b.Count -eq 0) { $l += 'No black moments were found.' } else { $l += Format-TimeSpanList $b 'moment' }
                return $l } } }
}

function Start-SceneAnalysis {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Lists the times where the picture changes a lot (cuts between shots). Nothing is changed.'
    $steps += @{ Id = 'sens'; Type = 'Choice'; Prompt = 'Sensitivity'; Help = 'Higher sensitivity reports more changes, including small ones.'
        Choices = { param($W) @( (New-Choice 0.6 'Low (only obvious cuts)' 'Only big changes between shots.'), (New-Choice 0.4 'Medium  (Recommended)' 'Normal cuts between shots.'), (New-Choice 0.2 'High (many changes)' 'Also small changes such as camera moves and flashes.') ) }; Default = 0.4 }
    Start-AnalysisTool -Title 'Detect Scene Changes' -Description 'Find cuts between shots.' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        $m = Get-Media $W 'input'; $t = [double](Get-Answer $W 'sens' 0.4)
        @{ Title = 'Detecting scene changes'; Duration = $m.Duration
            Passes = @(@{ Name = 'Watching'; Args = @('-i', $m.Path, '-map', ('0:' + $m.Video[0].Index), '-an', '-vf', ("select='gt(scene," + (Format-FFNumber $t 2) + ")',showinfo"), '-f', 'null', '-') })
            Report = { param($logs)
                $s = @(ConvertFrom-SceneLog $logs[0])
                $l = @("Scene changes ($($s.Count) found)", '')
                if ($s.Count -eq 0) { $l += 'No scene changes were found. Try a higher sensitivity.' } else { $i = 0; foreach ($x in $s) { $i++; $l += ('  {0,3}. {1}' -f $i, (Format-Duration $x)) } }
                $l += ''; $l += 'Tip: use these times with Trim / Cut Media to split a video at the cuts.'
                return $l } } }
}

function Start-CropAnalysis {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Finds black bars around the picture and suggests the crop size that removes them. Nothing is changed.'
    Start-AnalysisTool -Title 'Detect Black Bars' -Description 'Find the crop that removes black borders.' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        if (-not (Test-FFFilter 'cropdetect')) { throw 'Your FFmpeg build does not include the cropdetect filter.' }
        $m = Get-Media $W 'input'
        $dur = $m.Duration; $limit = @(); if ($dur -and $dur -gt 90) { $limit = @('-t', '90') }
        $vid = $m.Video[0]
        @{ Title = 'Detecting black bars'; Duration = $(if ($limit.Count) { 90 } else { $dur })
            Passes = @(@{ Name = 'Watching'; Args = @($limit + @('-i', $m.Path, '-map', ('0:' + $m.Video[0].Index), '-an', '-vf', 'cropdetect=limit=24:round=2:reset=0', '-f', 'null', '-')) })
            Report = { param($logs)
                $c = ConvertFrom-CropDetect $logs[0]
                if (-not $c) { return @('No crop suggestion could be made.') }
                $v = $vid
                $l = @('Black bar report', '')
                $l += ('Picture size      : {0}x{1}' -f $v.Width, $v.Height)
                $l += ('Suggested crop    : {0}x{1} at position ({2}, {3})' -f $c.W, $c.H, $c.X, $c.Y)
                $l += ''
                if ($c.W -eq $v.Width -and $c.H -eq $v.Height) { $l += 'There are no black bars to remove.' }
                else { $l += 'To apply it, open Crop / Rotate / Flip, then Crop, choose "Custom size and position" and enter these numbers.' }
                $l += '(Only the first 90 seconds were examined.)'
                return $l }.GetNewClosure() } }
}

function Start-CompareAnalysis {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Original video (the reference)' -Require Video -PanelTitle 'Original' -Help 'The untouched source.'
    $steps += Get-InputFileStep -Id 'other' -Prompt 'Converted or compressed video' -Require Video -PanelTitle 'Converted' -NoPanel -Help 'The result you want to compare against the original. Both should show the same content.'
    Start-AnalysisTool -Title 'Compare Video Quality' -Description 'Measure how closely a converted video matches the original (PSNR and SSIM).' -Icon 'Chart' -Steps $steps -Plan {
        param($W)
        if (-not ((Test-FFFilter 'psnr') -and (Test-FFFilter 'ssim') -and (Test-FFFilter 'scale2ref'))) { throw 'Your FFmpeg build does not include the psnr, ssim and scale2ref filters needed for this comparison.' }
        $a = Get-Media $W 'input'; $b = Get-Media $W 'other'
        $dur = [math]::Min([double]$(if ($a.Duration) { $a.Duration } else { 0 }), [double]$(if ($b.Duration) { $b.Duration } else { 0 }))
        $mk = { param($f) @('-i', $b.Path, '-i', $a.Path, '-lavfi', "[0:v][1:v]scale2ref=flags=bicubic[dist][ref];[dist][ref]$f", '-f', 'null', '-') }.GetNewClosure()
        @{ Title = 'Comparing quality'; Duration = $dur
            Passes = @(@{ Name = 'PSNR'; Args = (& $mk 'psnr') }, @{ Name = 'SSIM'; Args = (& $mk 'ssim') })
            Report = { param($logs)
                $p = ConvertFrom-PsnrLog $logs[0]; $s = ConvertFrom-SsimLog $logs[1]
                $l = @('Quality comparison', '')
                if ($null -eq $p -or $null -eq $s) { return @('The comparison did not produce usable numbers.') }
                $l += ('PSNR (higher is better) : {0:0.##} dB' -f $p)
                $l += ('SSIM (1.0 = identical)  : {0:0.####}' -f $s)
                $l += ''
                $verdict = 'Visible loss of quality.'
                if ($s -ge 0.99 -and $p -ge 40) { $verdict = 'Excellent: practically identical to the original.' }
                elseif ($s -ge 0.97 -and $p -ge 35) { $verdict = 'Very good: differences are hard to see.' }
                elseif ($s -ge 0.93 -and $p -ge 30) { $verdict = 'Acceptable: small differences are visible when looking closely.' }
                $l += $verdict
                $l += ''; $l += 'The converted video is scaled to the original size for the comparison.'
                return $l } } }
}

function Start-AnalyzeWorkflow {
    $items = @(
        @{ Label = 'Measure Volume'; Icon = 'Chart'; Desc = 'Average and peak volume, plus a clipping warning.'; Value = { Start-VolumeAnalysis } },
        @{ Label = 'Measure Loudness (LUFS)'; Icon = 'Chart'; Desc = 'Loudness as streaming services measure it.'; Enabled = (Test-FFFilter 'loudnorm'); Reason = 'Requires the loudnorm filter (not in this FFmpeg build).'; Value = { Start-LoudnessAnalysis } },
        @{ Label = 'Detect Silence'; Icon = 'Search'; Desc = 'List the quiet gaps in a recording with their times.'; Enabled = (Test-FFFilter 'silencedetect'); Reason = 'Requires the silencedetect filter (not in this FFmpeg build).'; Value = { Start-SilenceAnalysis } },
        @{ Label = 'Detect Black Frames'; Icon = 'Search'; Desc = 'List the moments where the picture goes black.'; Enabled = (Test-FFFilter 'blackdetect'); Reason = 'Requires the blackdetect filter (not in this FFmpeg build).'; Value = { Start-BlackAnalysis } },
        @{ Label = 'Detect Scene Changes'; Icon = 'Search'; Desc = 'List the times of cuts between shots.'; Enabled = ((Test-FFFilter 'select') -and (Test-FFFilter 'showinfo')); Reason = 'Requires the select and showinfo filters (not in this FFmpeg build).'; Value = { Start-SceneAnalysis } },
        @{ Label = 'Detect Black Bars (Crop Suggestion)'; Icon = 'Resize'; Desc = 'Find borders around the picture and the crop that removes them.'; Enabled = (Test-FFFilter 'cropdetect'); Reason = 'Requires the cropdetect filter (not in this FFmpeg build).'; Value = { Start-CropAnalysis } },
        @{ Label = 'Compare Video Quality (PSNR / SSIM)'; Icon = 'Chart'; Desc = 'Check how much quality a conversion or compression lost.'; Enabled = ((Test-FFFilter 'psnr') -and (Test-FFFilter 'ssim')); Reason = 'Requires the psnr and ssim filters (not in this FFmpeg build).'; Value = { Start-CompareAnalysis } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Chart') + '  Analyze & Detect') -Subtitle 'Read-only checks. They report what they find and never change your files.' -Items $items
}

Export-ModuleMember -Function ConvertFrom-VolumeDetect, ConvertFrom-SilenceDetect, ConvertFrom-BlackDetect, ConvertFrom-SceneLog, ConvertFrom-CropDetect, ConvertFrom-PsnrLog, ConvertFrom-SsimLog, ConvertFrom-LoudnormLog, Format-TimeSpanList, Invoke-AnalysisPass, Start-AnalysisTool, Start-VolumeAnalysis, Start-LoudnessAnalysis, Start-SilenceAnalysis, Start-BlackAnalysis, Start-SceneAnalysis, Start-CropAnalysis, Start-CompareAnalysis, Start-AnalyzeWorkflow
