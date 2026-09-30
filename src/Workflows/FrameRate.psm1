# FrameRate.psm1 - workflow 12: Change Frame Rate.
Set-StrictMode -Version 2.0

function Get-FrameRateSteps {
    $list = Get-PresetList 'frameRates' @(24, 25, 30, 50, 60)
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'fps'; Type = 'Choice'; Prompt = 'Target frame rate'; Help = 'The current frame rate is shown in the Source panel above.'
        Choices = { param($W) @($list | ForEach-Object { New-Choice ([double]$_) ("{0:0.##} FPS" -f $_) (Get-FpsDescription $_) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'FrameRate'; Prompt = 'Custom frame rate'; Help = 'Frames per second between 0.1 and 240.'; Example = '29.97'; Desc = 'For example 29.97.' }
        Default = 30.0
        Validate = { param($v, $W) $cur = (Get-Media $W 'input').Video[0].Fps; if ($cur -and [math]::Abs($cur - $v) -lt 0.01) { return ('The video already runs at {0:0.##} FPS. Choose a different rate.' -f $cur) }; $null } }
    $steps += @{ Id = 'method'; Type = 'Choice'; Prompt = 'Conversion method'; Help = "Standard drops or duplicates frames (fast).`nMotion interpolation creates synthetic in-between frames: it is much slower."
        Choices = { param($W) @( (New-Choice 'standard' 'Standard (drop / duplicate frames)' 'Fast and predictable. Recommended.'), (New-Choice 'interpolate' 'Motion interpolation' 'Smoother slow motion; slow to process.' (Test-FFFilter 'minterpolate') 'Requires the minterpolate filter (not in this FFmpeg build).') ) }
        Default = 'standard' }
    $steps += Get-VideoTailSteps -Suffix 'fps'
    return $steps
}

function Build-FrameRateJob {
    param($W)
    $info = Get-Media $W 'input'
    $fps = [double](Get-Answer $W 'fps' 30)
    $method = [string](Get-Answer $W 'method' 'standard')
    if ($method -eq 'interpolate') { $f = 'minterpolate=fps=' + (Format-FFNumber $fps 4) } else { $f = 'fps=' + (Format-FFNumber $fps 4) }
    $notes = @(); if ($method -eq 'interpolate') { $notes += 'Motion interpolation is slow and creates synthetic frames; artifacts may appear on fast motion.' }
    $rows = @(@('Input', $info.FileName), @('From', $(if ($info.Video[0].Fps) { ("{0:0.##} FPS" -f $info.Video[0].Fps) } else { 'unknown' })), @('To', ("{0:0.##} FPS" -f $fps)), @('Method', $(if ($method -eq 'interpolate') { 'Motion interpolation' } else { 'Standard' })))
    return New-VideoProcessJob -W $W -Title 'Changing frame rate' -VideoFilters @($f) -Rows $rows -Notes $notes -AudioMode copy -StageName 'Converting frame rate'
}

function Start-FrameRateWorkflow {
    Start-StandardWorkflow -Title 'Change Frame Rate' -Description 'Convert a video to a different playback frame rate.' -Icon 'FrameRate' -StepsFactory { Get-FrameRateSteps } -Build { param($W) Build-FrameRateJob $W }
}

Export-ModuleMember -Function Get-FrameRateSteps, Build-FrameRateJob, Start-FrameRateWorkflow
