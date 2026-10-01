# VideoEnhance.psm1 - Video Enhancement: deinterlace, denoise, stabilize, reverse, pad to an aspect ratio, loop.
Set-StrictMode -Version 2.0

# ---- deinterlace -------------------------------------------------------------------------------

function Get-DeinterlaceSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Interlaced video (old TV recordings, some camcorders) shows comb-like lines on moving objects. Deinterlacing removes them.'
    $steps += @{ Id = 'method'; Type = 'Choice'; Prompt = 'Deinterlacing method'; Help = 'Both remove the comb lines; the better method is slower.'
        Choices = { param($W) @(
            (New-Choice 'yadif' 'Yadif (fast)  (Recommended)' 'Good quality and fast.' (Test-FFFilter 'yadif') 'Requires the yadif filter (not in this FFmpeg build).'),
            (New-Choice 'bwdif' 'Bwdif (better quality, slower)' 'Slightly sharper result on fine detail.' (Test-FFFilter 'bwdif') 'Requires the bwdif filter (not in this FFmpeg build).')) }
        Default = { param($W) if (Test-FFFilter 'yadif') { 'yadif' } else { 'bwdif' } } }
    $steps += Get-VideoTailSteps -Suffix 'deinterlaced'
    return $steps
}

function Build-DeinterlaceJob {
    param($W)
    $info = Get-Media $W 'input'
    $m = [string](Get-Answer $W 'method' 'yadif')
    if (-not (Test-FFFilter $m)) { throw "Your FFmpeg build does not include the $m filter." }
    $notes = @(); if ($info.Video[0].FieldOrder -in @('progressive', '')) { $notes += 'This video is reported as progressive (not interlaced). Deinterlacing is harmless but usually unnecessary.' }
    return New-VideoProcessJob -W $W -Title 'Deinterlacing video' -VideoFilters @("${m}=mode=0:parity=-1:deint=0") -Rows @(@('Input', $info.FileName), @('Method', $m)) -AudioMode copy -Notes $notes -StageName 'Deinterlacing'
}

# ---- denoise --------------------------------------------------------------------------------------

function Get-DenoiseVideoSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Grainy or noisy footage (low light, old recordings) looks cleaner and compresses smaller after denoising.'
    $steps += @{ Id = 'level'; Type = 'Choice'; Prompt = 'Noise reduction strength'; Help = 'Stronger settings remove more grain but can soften fine detail.'
        Choices = { param($W) @( (New-Choice 'light' 'Light' 'Barely visible cleanup.'), (New-Choice 'medium' 'Medium  (Recommended)' 'Balanced.'), (New-Choice 'strong' 'Strong' 'Very clean but softer picture.') ) }; Default = 'medium' }
    $steps += Get-VideoTailSteps -Suffix 'denoised'
    return $steps
}

function Build-DenoiseVideoJob {
    param($W)
    if (-not (Test-FFFilter 'hqdn3d')) { throw 'Your FFmpeg build does not include the hqdn3d denoise filter.' }
    $info = Get-Media $W 'input'
    $lvl = [string](Get-Answer $W 'level' 'medium')
    $f = @{ light = 'hqdn3d=2:1.5:3:2.25'; medium = 'hqdn3d=4:3:6:4.5'; strong = 'hqdn3d=8:6:9:6.75' }[$lvl]
    return New-VideoProcessJob -W $W -Title 'Reducing video noise' -VideoFilters @($f) -Rows @(@('Input', $info.FileName), @('Strength', $lvl)) -AudioMode copy -StageName 'Reducing noise'
}

# ---- stabilize ------------------------------------------------------------------------------------

function Get-StabilizeSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Shaky handheld footage becomes steadier. Two passes are needed, so it takes about twice as long as a normal conversion.'
    $steps += @{ Id = 'strength'; Type = 'Choice'; Prompt = 'Stabilization strength'; Help = 'Stronger smoothing removes more shake but crops and zooms a little more.'
        Choices = { param($W) @( (New-Choice 'light' 'Light' 'Removes small jitter; little cropping.'), (New-Choice 'medium' 'Medium  (Recommended)' 'Good for walking or handheld shots.'), (New-Choice 'strong' 'Strong' 'Very smooth; noticeable zoom.') ) }; Default = 'medium' }
    $steps += Get-VideoTailSteps -Suffix 'stabilized'
    return $steps
}

function Build-StabilizeJob {
    param($W)
    if (-not ((Test-FFFilter 'vidstabdetect') -and (Test-FFFilter 'vidstabtransform'))) { throw 'Your FFmpeg build does not include the vidstab filters (libvidstab), which stabilization needs.' }
    $info = Get-Media $W 'input'
    $lvl = [string](Get-Answer $W 'strength' 'medium')
    $smooth = @{ light = 5; medium = 10; strong = 20 }[$lvl]
    $shake = @{ light = 4; medium = 5; strong = 7 }[$lvl]
    $trf = Join-Path ([System.IO.Path]::GetTempPath()) ('fftui_' + [guid]::NewGuid().ToString('N') + '.trf')
    $trfF = ConvertTo-FFFilterPath $trf
    $job = New-VideoProcessJob -W $W -Title 'Stabilizing video' -VideoFilters @("vidstabtransform=input=${trfF}:smoothing=${smooth}:zoom=0:optzoom=1", 'unsharp=5:5:0.8:3:3:0.4') -Rows @(@('Input', $info.FileName), @('Strength', $lvl)) -AudioMode copy -StageName 'Stabilizing'
    $analysis = @('-nostdin', '-i', $info.Path, '-map', ('0:' + $info.Video[0].Index), '-an', '-vf', "vidstabdetect=shakiness=${shake}:accuracy=15:result=${trfF}", '-f', 'null', '-')
    $job.Stages = @(@{ Name = 'Analyzing motion'; Arguments = $analysis; DurationSec = $info.Duration }, @{ Name = 'Stabilizing'; Arguments = $job.Stages[0].Arguments; DurationSec = $info.Duration })
    $job.TempFiles = @($job.TempFiles) + @($trf)
    return $job
}

# ---- reverse ----------------------------------------------------------------------------------------

function Get-ReverseVideoSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'The clip is played backwards, picture and sound. The whole clip is held in memory, so use short clips (up to 2 minutes).' -Extra {
        param($info, $W) if ($info.Duration -and $info.Duration -gt 120) { return 'This video is longer than 2 minutes. Trim it first (Trim / Cut Media); reversing needs the whole clip in memory.' }; $null }
    $steps += Get-VideoTailSteps -Suffix 'reversed'
    return $steps
}

function Build-ReverseVideoJob {
    param($W)
    $info = Get-Media $W 'input'
    $audio = 'none'; $af = @()
    if ($info.HasAudio) { $audio = 'auto'; $af = @('areverse') }
    return New-VideoProcessJob -W $W -Title 'Reversing video' -VideoFilters @('reverse') -AudioFilters $af -AudioMode $audio -Rows @(@('Input', $info.FileName), @('Effect', 'Play backwards')) -SubMode remove -StageName 'Reversing'
}

# ---- pad to aspect ratio ------------------------------------------------------------------------

function Get-PadSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'Adds bars around the picture (letterbox / pillarbox) so it fits another shape without cropping or stretching.'
    $steps += @{ Id = 'ratio'; Type = 'Choice'; Prompt = 'Target shape (aspect ratio)'; Help = 'The picture is centered on a canvas of this shape; nothing is cut off.'
        Choices = { param($W) @( (New-Choice '16/9' '16:9 (widescreen)' 'YouTube, TVs, most screens.'), (New-Choice '4/3' '4:3 (classic)' 'Old TVs and some slides.'), (New-Choice '1/1' '1:1 (square)' 'Social media posts.'), (New-Choice '9/16' '9:16 (vertical)' 'Phone stories and shorts.'), (New-Choice '21/9' '21:9 (ultrawide)' 'Cinema look.') ) }; Default = '16/9' }
    $steps += @{ Id = 'color'; Type = 'Choice'; Prompt = 'Bar color'; Help = 'Color of the added bars.'
        Choices = { param($W) @( (New-Choice 'black' 'Black  (Recommended)' 'Classic black bars.'), (New-Choice 'white' 'White' 'White bars.'), (New-Choice 'gray' 'Gray' 'Neutral gray bars.') ) }; Default = 'black' }
    $steps += Get-VideoTailSteps -Suffix 'padded'
    return $steps
}

function Build-PadJob {
    param($W)
    $info = Get-Media $W 'input'
    $ratio = [string](Get-Answer $W 'ratio' '16/9')
    if ($ratio -notmatch '^\d+/\d+$') { throw 'Unknown aspect ratio.' }
    $color = [string](Get-Answer $W 'color' 'black')
    $f = "pad=w='ceil(max(iw,ih*$ratio)/2)*2':h='ceil(max(ih,iw/($ratio))/2)*2':x='(ow-iw)/2':y='(oh-ih)/2':color=$color"
    return New-VideoProcessJob -W $W -Title 'Adding bars' -VideoFilters @($f, 'setsar=1') -Rows @(@('Input', $info.FileName), @('Shape', $ratio.Replace('/', ':')), @('Bars', $color)) -AudioMode copy -StageName 'Adding bars'
}

# ---- loop ------------------------------------------------------------------------------------------

function Get-LoopSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'Repeats the whole file several times without re-encoding (for example a short animation or background music).'
    $steps += @{ Id = 'times'; Type = 'Integer'; Prompt = 'How many times in total?'; Label = 'Times'; Min = 2; Max = 100; Default = 3; Example = '3'
        Help = 'Total number of plays in the output. 3 means the original plus two repeats.' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'looped' -Extension { param($W) [System.IO.Path]::GetExtension((Get-Media $W 'input').Path) }
    return $steps
}

function Build-LoopJob {
    param($W)
    $info = Get-Media $W 'input'
    $times = [int](Get-Answer $W 'times' 3)
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path @('-stream_loop', [string]($times - 1)))
    Add-FFOutOpt $cmd @('-map', '0:v?', '-map', '0:a?', '-c', 'copy')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $dur = $null; if ($info.Duration) { $dur = $info.Duration * $times }
    $rows = @(@('Input', $info.FileName), @('Plays', [string]$times), @('Output', $out.Path))
    return New-JobObject -Title 'Looping media' -Summary $rows -Stages @(@{ Name = 'Repeating'; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -Notes $notes
}

function Start-VideoEnhanceWorkflow {
    $items = @(
        @{ Label = 'Deinterlace'; Icon = 'Filters'; Desc = 'Remove comb-like lines from old TV or camcorder footage.'; Enabled = ((Test-FFFilter 'yadif') -or (Test-FFFilter 'bwdif')); Reason = 'Requires the yadif or bwdif filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Deinterlace' -Description 'Remove interlacing lines.' -Icon 'Filters' -StepsFactory { Get-DeinterlaceSteps } -Build { param($W) Build-DeinterlaceJob $W } } },
        @{ Label = 'Reduce Video Noise'; Icon = 'Filters'; Desc = 'Clean grainy footage from low light or old recordings.'; Enabled = (Test-FFFilter 'hqdn3d'); Reason = 'Requires the hqdn3d filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Reduce Video Noise' -Description 'Clean up grainy video.' -Icon 'Filters' -StepsFactory { Get-DenoiseVideoSteps } -Build { param($W) Build-DenoiseVideoJob $W } } },
        @{ Label = 'Stabilize Shaky Video'; Icon = 'Rotate'; Desc = 'Smooth out handheld camera shake (two passes).'; Enabled = ((Test-FFFilter 'vidstabdetect') -and (Test-FFFilter 'vidstabtransform')); Reason = 'Requires the vidstab filters (libvidstab), which this FFmpeg build lacks.'; Value = { Start-StandardWorkflow -Title 'Stabilize Video' -Description 'Reduce camera shake.' -Icon 'Rotate' -StepsFactory { Get-StabilizeSteps } -Build { param($W) Build-StabilizeJob $W } } },
        @{ Label = 'Add Bars to Fit an Aspect Ratio'; Icon = 'Resize'; Desc = 'Letterbox or pillarbox a video into 16:9, 4:3, 1:1 or 9:16 without cropping.'; Value = { Start-StandardWorkflow -Title 'Add Bars (Pad)' -Description 'Fit the picture into another shape.' -Icon 'Resize' -StepsFactory { Get-PadSteps } -Build { param($W) Build-PadJob $W } } },
        @{ Label = 'Reverse Video'; Icon = 'Retry'; Desc = 'Play a short clip backwards, picture and sound.'; Enabled = (Test-FFFilter 'reverse'); Reason = 'Requires the reverse filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Reverse Video' -Description 'Play a clip backwards.' -Icon 'Retry' -StepsFactory { Get-ReverseVideoSteps } -Build { param($W) Build-ReverseVideoJob $W } } },
        @{ Label = 'Loop (Repeat) a Clip'; Icon = 'Retry'; Desc = 'Repeat a video or audio file several times without re-encoding.'; Value = { Start-StandardWorkflow -Title 'Loop a Clip' -Description 'Repeat a file several times.' -Icon 'Retry' -StepsFactory { Get-LoopSteps } -Build { param($W) Build-LoopJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Enhance') + '  Video Enhancement') -Subtitle 'Clean up, steady, reshape or repeat video.' -Items $items
}

Export-ModuleMember -Function Get-DeinterlaceSteps, Build-DeinterlaceJob, Get-DenoiseVideoSteps, Build-DenoiseVideoJob, Get-StabilizeSteps, Build-StabilizeJob, Get-ReverseVideoSteps, Build-ReverseVideoJob, Get-PadSteps, Build-PadJob, Get-LoopSteps, Build-LoopJob, Start-VideoEnhanceWorkflow
