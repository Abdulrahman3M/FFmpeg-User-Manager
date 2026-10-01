# TransformVideo.psm1 - workflow 14: Crop / Rotate / Flip.
Set-StrictMode -Version 2.0

function Get-SourceSize {
    param($W)
    $v = (Get-Media $W 'input').Video[0]
    $d = Get-DisplayVideoSize $v
    return @{ W = [int]$d[0]; H = [int]$d[1] }
}

# ---- Crop ---------------------------------------------------------------------------------

function Get-CropSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'cropmode'; Type = 'Choice'; Prompt = 'Crop method'; Help = 'Centered crops keep the middle of the picture.'
        Choices = { param($W) @( (New-Choice 'aspect' 'Aspect ratio preset (centered)' 'Crop to 16:9, 4:3, 1:1, 9:16 or 21:9.'), (New-Choice 'centered' 'Custom size (centered)' 'Enter a width and height; the position is calculated.'), (New-Choice 'manual' 'Custom size and position' 'Enter width, height, X and Y yourself.') ) }; Default = 'aspect' }
    $steps += @{ Id = 'ratio'; Type = 'Choice'; Prompt = 'Aspect ratio'; Help = 'The largest centered area with this ratio is kept.'; When = { param($W) (Get-Answer $W 'cropmode') -eq 'aspect' }
        Choices = { param($W) @( (New-Choice '16:9' '16:9 (widescreen)' 'Modern TVs, YouTube and most screens.'), (New-Choice '4:3' '4:3 (classic)' 'Older TVs and some presentations.'), (New-Choice '1:1' '1:1 (square)' 'Social media posts.'), (New-Choice '9:16' '9:16 (vertical)' 'Phone stories and short videos.'), (New-Choice '21:9' '21:9 (ultrawide)' 'Cinema-style wide picture.') ) }; Default = '16:9' }
    $dimMsg = { param($v, $W, [string]$axis) $s = Get-SourceSize $W; $max = $(if ($axis -eq 'w') { $s.W } else { $s.H }); if ($v -gt $max) { return "Cannot be larger than the source ($max px)." }; if ($v % 2) { return 'Use an even number (most codecs need even dimensions).' }; $null }
    $steps += @{ Id = 'cw'; Type = 'Integer'; Prompt = 'Crop width (px)'; Help = 'Width of the area to keep.'; Example = '1280'; Min = 16; Label = 'Width'; When = { param($W) (Get-Answer $W 'cropmode') -in @('centered', 'manual') }
        Validate = { param($v, $W) $s = Get-SourceSize $W; if ($v -gt $s.W) { return "Cannot be larger than the source width ($($s.W) px)." }; if ($v % 2) { return 'Use an even number (most codecs need even dimensions).' }; $null } }
    $steps += @{ Id = 'ch'; Type = 'Integer'; Prompt = 'Crop height (px)'; Help = 'Height of the area to keep.'; Example = '720'; Min = 16; Label = 'Height'; When = { param($W) (Get-Answer $W 'cropmode') -in @('centered', 'manual') }
        Validate = { param($v, $W) $s = Get-SourceSize $W; if ($v -gt $s.H) { return "Cannot be larger than the source height ($($s.H) px)." }; if ($v % 2) { return 'Use an even number (most codecs need even dimensions).' }; $null } }
    $steps += @{ Id = 'cx'; Type = 'Integer'; Prompt = 'X position (px from the left)'; Help = 'Left edge of the crop area.'; Example = '0'; Min = 0; Label = 'X'; Default = 0; When = { param($W) (Get-Answer $W 'cropmode') -eq 'manual' }
        Validate = { param($v, $W) $s = Get-SourceSize $W; if ($v + [int](Get-Answer $W 'cw') -gt $s.W) { return "X + width exceeds the source width ($($s.W) px)." }; $null } }
    $steps += @{ Id = 'cy'; Type = 'Integer'; Prompt = 'Y position (px from the top)'; Help = 'Top edge of the crop area.'; Example = '0'; Min = 0; Label = 'Y'; Default = 0; When = { param($W) (Get-Answer $W 'cropmode') -eq 'manual' }
        Validate = { param($v, $W) $s = Get-SourceSize $W; if ($v + [int](Get-Answer $W 'ch') -gt $s.H) { return "Y + height exceeds the source height ($($s.H) px)." }; $null } }
    $steps += Get-VideoTailSteps -Suffix 'cropped'
    return $steps
}

function Get-CropRectangle {
    param($W)
    $s = Get-SourceSize $W
    switch ([string](Get-Answer $W 'cropmode' 'aspect')) {
        'aspect' {
            $parts = ([string](Get-Answer $W 'ratio' '16:9')).Split(':'); $a = [double]$parts[0]; $b = [double]$parts[1]
            $rw = $s.W; $rh = [int][math]::Floor($rw * $b / $a)
            if ($rh -gt $s.H) { $rh = $s.H; $rw = [int][math]::Floor($rh * $a / $b) }
            if ($rw % 2) { $rw-- }; if ($rh % 2) { $rh-- }
            return @{ W = $rw; H = $rh; X = [int][math]::Floor(($s.W - $rw) / 2); Y = [int][math]::Floor(($s.H - $rh) / 2) }
        }
        'centered' { $rw = [int](Get-Answer $W 'cw'); $rh = [int](Get-Answer $W 'ch'); return @{ W = $rw; H = $rh; X = [int][math]::Floor(($s.W - $rw) / 2); Y = [int][math]::Floor(($s.H - $rh) / 2) } }
        default { return @{ W = [int](Get-Answer $W 'cw'); H = [int](Get-Answer $W 'ch'); X = [int](Get-Answer $W 'cx' 0); Y = [int](Get-Answer $W 'cy' 0) } }
    }
}

function Build-CropJob {
    param($W)
    $info = Get-Media $W 'input'; $s = Get-SourceSize $W
    $r = Get-CropRectangle $W
    if ($r.W -le 0 -or $r.H -le 0 -or $r.X -lt 0 -or $r.Y -lt 0 -or ($r.X + $r.W) -gt $s.W -or ($r.Y + $r.H) -gt $s.H) { throw "The crop area does not fit inside the source picture ($($s.W)x$($s.H))." }
    $f = "crop=$($r.W):$($r.H):$($r.X):$($r.Y)"
    return New-VideoProcessJob -W $W -Title 'Cropping video' -VideoFilters @($f) -Rows @(@('Input', $info.FileName), @('Source', "$($s.W)x$($s.H)"), @('Crop', "$($r.W)x$($r.H) at ($($r.X), $($r.Y))")) -AudioMode copy -StageName 'Cropping video'
}

# ---- Rotate ---------------------------------------------------------------------------------

function Get-RotateSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'rot'; Type = 'Choice'; Prompt = 'Rotation'; Help = 'Turn the picture. 90-degree steps keep full quality of the frame.'
        Choices = { param($W) @( (New-Choice 'cw90' '90 degrees clockwise' 'Turn right; fixes a video that was filmed on its left side.'), (New-Choice 'ccw90' '90 degrees counter-clockwise' 'Turn left; fixes a video that was filmed on its right side.'), (New-Choice '180' '180 degrees' 'Turn upside down; fixes a video filmed upside down.') ) }
        AllowCustom = @{ Label = 'Custom angle...'; Type = 'Decimal'; Min = -360; Max = 360; Prompt = 'Custom angle (degrees)'; Help = 'Positive turns clockwise. The frame grows to fit; corners are filled with black.'; Example = '15'; ValueLabel = 'Angle'; Desc = 'For example 15.' }
        Default = 'cw90' }
    $steps += Get-VideoTailSteps -Suffix 'rotated'
    return $steps
}

function Build-RotateJob {
    param($W)
    $info = Get-Media $W 'input'
    $r = Get-Answer $W 'rot' 'cw90'
    switch -Exact ([string]$r) {
        'cw90' { $f = 'transpose=1'; $label = '90 degrees clockwise' }
        'ccw90' { $f = 'transpose=2'; $label = '90 degrees counter-clockwise' }
        '180' { $f = 'transpose=1,transpose=1'; $label = '180 degrees' }
        default {
            if (-not (Test-FFFilter 'rotate')) { throw 'Your FFmpeg build does not include the rotate filter needed for custom angles.' }
            $deg = [double]$r
            $rad = Format-FFNumber ($deg * [math]::PI / 180) 8
            # The rotated frame is larger and can have odd dimensions; H.264/H.265 need even ones.
            $f = "rotate=${rad}:ow=rotw(${rad}):oh=roth(${rad}):c=black,scale=trunc(iw/2)*2:trunc(ih/2)*2"; $label = ('{0:0.##} degrees' -f $deg)
        }
    }
    return New-VideoProcessJob -W $W -Title 'Rotating video' -VideoFilters @($f) -Rows @(@('Input', $info.FileName), @('Rotation', $label)) -AudioMode copy -StageName 'Rotating video'
}

# ---- Flip -----------------------------------------------------------------------------------------

function Get-FlipSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'flip'; Type = 'Choice'; Prompt = 'Flip direction'; Help = 'Mirror the picture.'
        Choices = { param($W) @( (New-Choice 'h' 'Horizontal (mirror left/right)' 'Left and right swap, like a mirror.'), (New-Choice 'v' 'Vertical (upside down)' 'Top and bottom swap.'), (New-Choice 'both' 'Both' 'Flip in both directions (same as a 180-degree turn).') ) }; Default = 'h' }
    $steps += Get-VideoTailSteps -Suffix 'flipped'
    return $steps
}

function Build-FlipJob {
    param($W)
    $info = Get-Media $W 'input'
    $d = [string](Get-Answer $W 'flip' 'h')
    $f = switch ($d) { 'h' { 'hflip' } 'v' { 'vflip' } default { 'hflip,vflip' } }
    return New-VideoProcessJob -W $W -Title 'Flipping video' -VideoFilters @($f) -Rows @(@('Input', $info.FileName), @('Flip', $d)) -AudioMode copy -StageName 'Flipping video'
}

function Start-TransformWorkflow {
    $items = @(
        @{ Label = 'Crop'; Desc = 'Keep only part of the frame by aspect ratio or exact size.'; Value = { Start-StandardWorkflow -Title 'Crop' -Description 'Cut away the edges of the picture.' -Icon 'Rotate' -StepsFactory { Get-CropSteps } -Build { param($W) Build-CropJob $W } } },
        @{ Label = 'Rotate'; Desc = 'Turn the video by 90, 180 or a custom angle.'; Value = { Start-StandardWorkflow -Title 'Rotate' -Description 'Rotate the picture.' -Icon 'Rotate' -StepsFactory { Get-RotateSteps } -Build { param($W) Build-RotateJob $W } } },
        @{ Label = 'Flip'; Desc = 'Mirror the video horizontally or vertically.'; Value = { Start-StandardWorkflow -Title 'Flip' -Description 'Mirror the picture.' -Icon 'Rotate' -StepsFactory { Get-FlipSteps } -Build { param($W) Build-FlipJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Rotate') + '  Crop / Rotate / Flip') -Subtitle 'Crop the frame or change video orientation.' -Items $items
}

Export-ModuleMember -Function Get-CropSteps, Get-CropRectangle, Build-CropJob, Get-RotateSteps, Build-RotateJob, Get-FlipSteps, Build-FlipJob, Start-TransformWorkflow
