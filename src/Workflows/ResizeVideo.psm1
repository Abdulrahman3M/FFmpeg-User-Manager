# ResizeVideo.psm1 - workflow 7: Resize / Scale Video.
Set-StrictMode -Version 2.0

$script:PresetDims = @{ 'h2160' = @(3840, 2160); 'h1440' = @(2560, 1440); 'h1080' = @(1920, 1080); 'h720' = @(1280, 720); 'h480' = @(854, 480) }

function Get-TargetDimensions {
    # Returns @{ W; H } with $null where the target gives only one dimension.
    param([string]$Target)
    if ($script:PresetDims.ContainsKey($Target)) { return @{ W = $script:PresetDims[$Target][0]; H = $script:PresetDims[$Target][1]; Preset = $true } }
    if ($Target -match '^(\d+)x(\d+)$') { return @{ W = [int]$Matches[1]; H = [int]$Matches[2]; Preset = $false } }
    if ($Target -match '^\d+$') { return @{ W = [int]$Target; H = $null; Preset = $false } }
    return @{ W = $null; H = $null; Preset = $false }
}

function Get-ResizeSteps {
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += Get-ResolutionStep -Id 'target' -Prompt 'Target size'
    $steps += @{ Id = 'mode'; Type = 'Choice'; Prompt = 'Aspect ratio behavior'; Help = 'Preserving the aspect ratio never distorts the picture.'
        When = { param($W) (Get-Answer $W 'target') -ne 'keep' }
        Choices = {
            param($W)
            $d = Get-TargetDimensions ([string](Get-Answer $W 'target')); $both = ($d.W -and $d.H)
            $r = 'Needs both width and height (enter WxH as the custom size).'
            @( (New-Choice 'Preserve' 'Preserve aspect ratio' 'Scale so the picture keeps its proportions (recommended).'),
               (New-Choice 'Fit' 'Fit inside the size' 'Keep proportions and fit within width x height.' $both $r),
               (New-Choice 'Fill' 'Fill and crop' 'Keep proportions, fill the whole frame and crop the overflow.' $both $r),
               (New-Choice 'Stretch' 'Stretch (distorts the picture)' 'Force exact width x height. The picture may look squashed.' $both $r) )
        }
        Default = 'Preserve' }
    $steps += @{ Id = 'pad'; Type = 'YesNo'; Prompt = 'Add black bars to reach the exact size?'; Help = 'Padding keeps the full picture and fills the rest with black.'; Default = $false
        When = { param($W) (Get-Answer $W 'mode') -eq 'Fit' } }
    $steps += Get-AdvancedGateStep -Prompt 'Configure advanced scaling options?'
    $steps += @{ Id = 'algo'; Type = 'Choice'; Prompt = 'Scaling algorithm'; Help = 'Recommended works well for nearly everything. Lanczos is sharper; bilinear is faster.'
        When = { param($W) (Get-Answer $W 'target') -ne 'keep' -and (Get-Answer $W 'advanced' $false) }
        Choices = { param($W) @( (New-Choice '' 'Recommended (bicubic)'), (New-Choice 'lanczos' 'Lanczos (sharp)'), (New-Choice 'bilinear' 'Bilinear (fast)'), (New-Choice 'bicubic' 'Bicubic'), (New-Choice 'spline' 'Spline'), (New-Choice 'neighbor' 'Nearest neighbor (pixel art)') ) }
        Default = '' }
    $steps += Get-VideoTailSteps -Suffix 'resized'
    return $steps
}

function Build-ResizeJob {
    param($W)
    $info = Get-Media $W 'input'
    $target = [string](Get-Answer $W 'target' 'keep')
    if ($target -eq 'keep') { throw 'Choose a target size other than Keep original to resize the video.' }
    $d = Get-TargetDimensions $target
    $mode = [string](Get-Answer $W 'mode' 'Preserve')
    $algo = [string](Get-Answer $W 'algo' '')
    $vf = @()
    if ($mode -eq 'Preserve') {
        if ($target -match '^h(\d+)$') { $vf += (New-ScaleFilter -Height ([int]$Matches[1]) -Mode Preserve -Algorithm $algo) }
        elseif ($d.W -and $d.H) { $vf += (New-ScaleFilter -Width $d.W -Height $d.H -Mode Preserve -Algorithm $algo) }
        else { $vf += (New-ScaleFilter -Width $d.W -Mode Preserve -Algorithm $algo) }
    } else {
        $vf += (New-ScaleFilter -Width $d.W -Height $d.H -Mode $mode -Pad:([bool](Get-Answer $W 'pad' $false)) -Algorithm $algo)
    }
    $vf += 'setsar=1'
    $rows = @(@('Input', $info.FileName), @('Target', $target), @('Aspect ratio', $mode), @('Format', (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Label))
    return New-VideoProcessJob -W $W -Title 'Resizing video' -VideoFilters $vf -Rows $rows -AudioMode copy -StageName 'Scaling video'
}

function Start-ResizeWorkflow {
    Start-StandardWorkflow -Title 'Resize / Scale Video' -Description 'Change video dimensions while controlling aspect ratio and fit behavior.' -Icon 'Resize' -StepsFactory { Get-ResizeSteps } -Build { param($W) Build-ResizeJob $W }
}

Export-ModuleMember -Function Get-TargetDimensions, Get-ResizeSteps, Build-ResizeJob, Start-ResizeWorkflow
