# OverlayTools.psm1 - workflow 15: Text & Watermark.
Set-StrictMode -Version 2.0

function Get-DefaultFontFile {
    $cands = @()
    if (Test-IsWindows) {
        $win = $env:WINDIR; if (-not $win) { $win = 'C:\Windows' }
        $cands = @((Join-Path $win 'Fonts\segoeui.ttf'), (Join-Path $win 'Fonts\arial.ttf'), (Join-Path $win 'Fonts\tahoma.ttf'))
    } else {
        $cands = @('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/dejavu/DejaVuSans.ttf', '/Library/Fonts/Arial.ttf', '/System/Library/Fonts/Helvetica.ttc', '/usr/share/fonts/TTF/DejaVuSans.ttf')
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c -PathType Leaf) { return $c } }
    return ''
}

function Get-PositionChoices {
    return @( (New-Choice 'tl' 'Top left' 'Place it in the upper left corner.'), (New-Choice 'tc' 'Top center' 'Place it centered along the top edge.'), (New-Choice 'tr' 'Top right' 'Place it in the upper right corner.'), (New-Choice 'c' 'Center' 'Place it in the middle of the picture.'), (New-Choice 'bl' 'Bottom left' 'Place it in the lower left corner.'), (New-Choice 'bc' 'Bottom center' 'Place it centered along the bottom edge (typical for captions).'), (New-Choice 'br' 'Bottom right' 'Place it in the lower right corner (typical for logos).') )
}

function Get-OverlayTimeSteps {
    param([string]$Prefix = 'o')
    $p = $Prefix
    $steps = @()
    $steps += @{ Id = "${p}start"; Type = 'Timestamp'; Prompt = 'Show from (start time)'; Help = 'Optional. Leave empty to show from the beginning.'; Example = '00:00:05'; Optional = $true
        Validate = { param($v, $W) $d = (Get-Media $W 'input').Duration; if ($null -ne $v -and $v -lt 0) { return 'Start time cannot be negative.' }; if ($null -ne $v -and $d -and $v -ge $d) { return ('Start time must be before the end of the video ({0}).' -f (Format-Duration $d)) }; $null }.GetNewClosure() }
    $steps += @{ Id = "${p}end"; Type = 'Timestamp'; Prompt = 'Show until (end time)'; Help = 'Optional. Leave empty to show until the end.'; Example = '00:00:15'; Optional = $true
        Validate = { param($v, $W) if ($null -eq $v) { return $null }; $s = Get-Answer $W "${p}start"; if ($null -ne $s -and $v -le $s) { return 'End time must be after the start time.' }; $d = (Get-Media $W 'input').Duration; if ($d -and $v -gt $d + 0.01) { return ('End time is beyond the end of the video ({0}).' -f (Format-Duration $d)) }; $null }.GetNewClosure() }
    return $steps
}

function Get-EnableExpression {
    param($Start, $End)
    if ($null -eq $Start -and $null -eq $End) { return '' }
    $s = 0; if ($null -ne $Start) { $s = $Start }
    if ($null -eq $End) { return ("enable='gte(t," + (Format-FFNumber $s 3) + ")'") }
    return ("enable='between(t," + (Format-FFNumber $s 3) + ',' + (Format-FFNumber $End 3) + ")'")
}

# ---- Add Text -----------------------------------------------------------------------------------

function Get-AddTextSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'text'; Type = 'Text'; Prompt = 'Text to show'; Help = 'Any characters are fine; they are handled safely.'; Example = 'My holiday - 2026'; Label = 'Text'; NoTrim = $false
        Validate = { param($v, $W) if ($v.Length -gt 500) { return 'The text is too long (500 characters maximum).' }; $null } }
    $steps += @{ Id = 'font'; Type = 'Choice'; Prompt = 'Font'; Help = 'Choose a font file for the text.'
        Choices = { param($W) $d = Get-DefaultFontFile; @( (New-Choice 'default' ('Default font' + $(if ($d) { '  (' + [System.IO.Path]::GetFileName($d) + ')' } else { '  (system default)' })) 'A plain, readable font from your system.') ) }
        AllowCustom = @{ Label = 'Choose a font file...'; Type = 'File'; Prompt = 'Font file path'; Help = 'A .ttf, .otf or .ttc font file.'; Example = 'C:\Windows\Fonts\arial.ttf'; Desc = 'Type or paste a font file path.' }
        Validate = { param($v, $W) if ($v -ne 'default' -and [System.IO.Path]::GetExtension([string]$v).ToLowerInvariant() -notin @('.ttf', '.otf', '.ttc')) { return 'Choose a .ttf, .otf or .ttc font file.' }; $null }
        Default = 'default' }
    $steps += @{ Id = 'size'; Type = 'Choice'; Prompt = 'Text size'; Help = 'Font height in pixels.'
        Choices = { param($W) @( (New-Choice 18 'Small (18)' 'Small text for unobtrusive notes.'), (New-Choice 24 'Medium (24)' 'Comfortable size for captions.'), (New-Choice 36 'Large (36)' 'Large, easy to read text.'), (New-Choice 52 'Extra large (52)' 'Very large text for titles.'), (New-Choice 72 'Huge (72)' 'Huge text that dominates the picture.') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 8; Max = 500; Prompt = 'Custom text size'; Help = 'Pixels between 8 and 500.'; Example = '40'; ValueLabel = 'Size'; Desc = 'For example 40.' }; Default = 36 }
    $steps += @{ Id = 'pos'; Type = 'Choice'; Prompt = 'Position'; Help = 'Where the text appears.'; Choices = { param($W) @(Get-PositionChoices) }; Default = 'bc' }
    $steps += @{ Id = 'color'; Type = 'Choice'; Prompt = 'Text color'; Help = 'Choose a color.'
        Choices = { param($W) @( (New-Choice 'white' 'White' 'The most readable color on dark footage.'), (New-Choice 'yellow' 'Yellow' 'Classic subtitle color; stands out on most footage.'), (New-Choice 'black' 'Black' 'Best on bright footage.'), (New-Choice 'red' 'Red' 'Strong accent color.'), (New-Choice 'lime' 'Green' 'Bright green.'), (New-Choice 'cyan' 'Cyan' 'Bright blue-green.') ) }
        AllowCustom = @{ Label = 'Custom color...'; Type = 'Color'; Prompt = 'Custom color'; Help = 'A color name or hex code.'; Example = '#FFCC00'; Desc = 'For example #FFCC00.' }; Default = 'white' }
    $steps += @{ Id = 'opacity'; Type = 'Choice'; Prompt = 'Text opacity'; Help = '100% is fully solid.'
        Choices = { param($W) @( (New-Choice 1.0 '100% (solid)' 'Fully opaque; nothing shows through.'), (New-Choice 0.75 '75%' 'Mostly solid with a hint of transparency.'), (New-Choice 0.5 '50%' 'Half transparent.'), (New-Choice 0.25 '25%' 'Very faint, watermark style.') ) }; Default = 1.0 }
    $steps += @{ Id = 'box'; Type = 'YesNo'; Prompt = 'Draw a background box behind the text?'; Help = 'A box makes text easier to read over busy pictures.'; YesDesc = 'A semi-transparent box is drawn behind the text so it is always readable.'; NoDesc = 'Only the letters are drawn, directly on the picture.'; Default = $true }
    $steps += @{ Id = 'boxcolor'; Type = 'Choice'; Prompt = 'Background box color'; Help = 'Semi-transparent so the picture still shows through.'; When = { param($W) [bool](Get-Answer $W 'box' $true) }
        Choices = { param($W) @( (New-Choice 'black' 'Black' 'Best on bright footage.'), (New-Choice 'white' 'White' 'The most readable color on dark footage.'), (New-Choice 'blue' 'Blue' 'Deep blue.') ) }; Default = 'black' }
    $steps += Get-OverlayTimeSteps -Prefix 'o'
    $steps += Get-AdvancedGateStep -Prompt 'Set an exact pixel position?'
    $steps += @{ Id = 'cx'; Type = 'Integer'; Prompt = 'X position (px from the left)'; Help = 'Overrides the position preset.'; Example = '40'; Min = 0; Label = 'X'; Default = 40; When = { param($W) [bool](Get-Answer $W 'advanced' $false) } }
    $steps += @{ Id = 'cy'; Type = 'Integer'; Prompt = 'Y position (px from the top)'; Help = 'Overrides the position preset.'; Example = '40'; Min = 0; Label = 'Y'; Default = 40; When = { param($W) [bool](Get-Answer $W 'advanced' $false) } }
    $steps += Get-VideoTailSteps -Suffix 'text'
    return $steps
}

function Get-TextPositionExpr {
    param([string]$Pos, [int]$Margin = 24)
    switch ($Pos) {
        'tl' { return @("$Margin", "$Margin") } 'tc' { return @('(w-text_w)/2', "$Margin") } 'tr' { return @("w-text_w-$Margin", "$Margin") }
        'c' { return @('(w-text_w)/2', '(h-text_h)/2') }
        'bl' { return @("$Margin", "h-text_h-$Margin") } 'bc' { return @('(w-text_w)/2', "h-text_h-$Margin") } 'br' { return @("w-text_w-$Margin", "h-text_h-$Margin") }
        default { return @('(w-text_w)/2', "h-text_h-$Margin") }
    }
}

function Build-AddTextJob {
    param($W)
    if (-not (Test-FFFilter 'drawtext')) { throw 'Your FFmpeg build does not include the drawtext filter (needs freetype), so text cannot be added.' }
    $info = Get-Media $W 'input'
    $text = [string](Get-Answer $W 'text' '')
    $tf = New-TempTextFile $text '.txt'
    $fontSel = [string](Get-Answer $W 'font' 'default')
    $font = if ($fontSel -eq 'default') { Get-DefaultFontFile } else { $fontSel }
    $color = [string](Get-Answer $W 'color' 'white'); $op = [double](Get-Answer $W 'opacity' 1.0)
    $parts = @()
    if ($font) { $parts += ('fontfile=' + (ConvertTo-FFFilterPath $font)) }
    $parts += ('textfile=' + (ConvertTo-FFFilterPath $tf))
    $parts += 'expansion=none'
    $parts += ('fontsize=' + [int](Get-Answer $W 'size' 36))
    $parts += ('fontcolor=' + (ConvertTo-FFFilterValue $color) + '@' + (Format-FFNumber $op 3))
    if ((Get-Answer $W 'advanced' $false)) { $xy = @([string][int](Get-Answer $W 'cx' 40), [string][int](Get-Answer $W 'cy' 40)) } else { $xy = Get-TextPositionExpr ([string](Get-Answer $W 'pos' 'bc')) }
    $parts += ('x=' + $xy[0]); $parts += ('y=' + $xy[1])
    if ((Get-Answer $W 'box' $true)) { $parts += 'box=1'; $parts += ('boxcolor=' + (ConvertTo-FFFilterValue ([string](Get-Answer $W 'boxcolor' 'black'))) + '@0.5'); $parts += 'boxborderw=12' }
    $en = Get-EnableExpression (Get-Answer $W 'ostart') (Get-Answer $W 'oend')
    if ($en) { $parts += $en }
    $f = 'drawtext=' + ($parts -join ':')
    $rows = @(@('Input', $info.FileName), @('Text', $text), @('Position', $(if ((Get-Answer $W 'advanced' $false)) { "x=$($xy[0]) y=$($xy[1])" } else { [string](Get-Answer $W 'pos' 'bc') })), @('Size', [string](Get-Answer $W 'size' 36)))
    $job = New-VideoProcessJob -W $W -Title 'Adding text' -VideoFilters @($f) -Rows $rows -AudioMode copy -StageName 'Adding text'
    $job.TempFiles = @($tf)
    return $job
}

# ---- Watermark --------------------------------------------------------------------------------------

function Get-WatermarkSteps {
    $steps = @(); $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += Get-InputFileStep -Id 'logo' -Prompt 'Image / logo file' -Require Any -NoPanel -Example 'C:\Images\logo.png' -Help 'A PNG (with transparency), JPG or other image.' -Extra { param($info, $W) if (-not $info.HasVideo) { return 'This file is not a readable image.' }; $null }
    $steps += @{ Id = 'pos'; Type = 'Choice'; Prompt = 'Position'; Help = 'Where the logo appears.'
        Choices = { param($W) @( (New-Choice 'tl' 'Top left' 'Place it in the upper left corner.'), (New-Choice 'tr' 'Top right' 'Place it in the upper right corner.'), (New-Choice 'bl' 'Bottom left' 'Place it in the lower left corner.'), (New-Choice 'br' 'Bottom right' 'Place it in the lower right corner (typical for logos).'), (New-Choice 'c' 'Center' 'Place it in the middle of the picture.') ) }; Default = 'br' }
    $steps += @{ Id = 'margin'; Type = 'Choice'; Prompt = 'Margin from the edge'; Help = 'Distance between the logo and the edge of the picture.'; When = { param($W) (Get-Answer $W 'pos') -ne 'c' }
        Choices = { param($W) @( (New-Choice 10 '10 px' 'Close to the edge.'), (New-Choice 20 '20 px (Recommended)' 'A comfortable margin from the edge.'), (New-Choice 40 '40 px' 'A generous margin.'), (New-Choice 80 '80 px' 'A large margin from the edge.') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 0; Max = 2000; Prompt = 'Custom margin (px)'; Help = 'Pixels.'; Example = '30'; ValueLabel = 'Margin'; Desc = 'For example 30.' }; Default = 20 }
    $steps += @{ Id = 'scale'; Type = 'Choice'; Prompt = 'Logo size (percent of the video width)'; Help = 'The logo keeps its proportions.'
        Choices = { param($W) @( (New-Choice 0 'Original size' 'Keep the logo at its own pixel size.'), (New-Choice 5 '5%' 'A tiny logo (5% of the video width).'), (New-Choice 10 '10% (Recommended)' 'A neat logo (10% of the video width).'), (New-Choice 15 '15%' 'A clearly visible logo.'), (New-Choice 20 '20%' 'A large logo.'), (New-Choice 30 '30%' 'A very large logo.') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 1; Max = 100; Prompt = 'Custom size (% of video width)'; Help = 'Between 1 and 100.'; Example = '12'; ValueLabel = 'Size'; Desc = 'Between 1 and 100.' }; Default = 10 }
    $steps += @{ Id = 'opacity'; Type = 'Choice'; Prompt = 'Opacity'; Help = '100% is fully solid.'
        Choices = { param($W) @( (New-Choice 1.0 '100% (solid)' 'Fully opaque; nothing shows through.'), (New-Choice 0.75 '75%' 'Mostly solid with a hint of transparency.'), (New-Choice 0.5 '50%' 'Half transparent.'), (New-Choice 0.25 '25%' 'Very faint, watermark style.') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.05; Max = 1; Prompt = 'Custom opacity'; Help = 'A value from 0.05 to 1.'; Example = '0.6'; ValueLabel = 'Opacity'; Desc = 'For example 0.6.' }; Default = 1.0 }
    $steps += Get-OverlayTimeSteps -Prefix 'o'
    $steps += Get-VideoTailSteps -Suffix 'watermark'
    return $steps
}

function Build-WatermarkJob {
    param($W)
    $v = Get-Media $W 'input'; $logo = Get-Media $W 'logo'
    $m = [int](Get-Answer $W 'margin' 20)
    $scale = [int](Get-Answer $W 'scale' 10)
    $op = [double](Get-Answer $W 'opacity' 1.0)
    $vw = (Get-DisplayVideoSize $v.Video[0])[0]
    $chain = @()
    if ($scale -gt 0) { $lw = [int]([math]::Max(8, 2 * [math]::Round(($vw * $scale / 100) / 2))); $chain += "scale=${lw}:-2" }
    $chain += 'format=rgba'
    if ($op -lt 0.999) { $chain += ('colorchannelmixer=aa=' + (Format-FFNumber $op 3)) }
    $pos = switch ([string](Get-Answer $W 'pos' 'br')) { 'tl' { "${m}:${m}" } 'tr' { "main_w-overlay_w-${m}:${m}" } 'bl' { "${m}:main_h-overlay_h-${m}" } 'c' { '(main_w-overlay_w)/2:(main_h-overlay_h)/2' } default { "main_w-overlay_w-${m}:main_h-overlay_h-${m}" } }
    $en = Get-EnableExpression (Get-Answer $W 'ostart') (Get-Answer $W 'oend')
    $ov = 'overlay=' + $pos + $(if ($en) { ':' + $en } else { '' })
    $fc = '[1:v]' + ($chain -join ',') + '[wm];[0:v][wm]' + $ov + '[v]'
    $rows = @(@('Video', $v.FileName), @('Logo', $logo.FileName), @('Position', [string](Get-Answer $W 'pos' 'br')), @('Size', $(if ($scale -gt 0) { "$scale% of video width" } else { 'Original' })), @('Opacity', ("{0:0.##}" -f $op)))
    return New-VideoProcessJob -W $W -Title 'Adding watermark' -FilterComplex $fc -ExtraInputs @($logo.Path) -Rows $rows -AudioMode copy -StageName 'Adding watermark' -DurationSec $v.Duration
}

function Start-OverlayWorkflow {
    $items = @(
        @{ Label = 'Add Text'; Desc = 'Write text over the video with size, color, position and timing.'; Enabled = (Test-FFFilter 'drawtext'); Reason = 'Requires the drawtext filter (not in this FFmpeg build).'; Value = { Start-StandardWorkflow -Title 'Add Text' -Description 'Add text to a video.' -Icon 'Text' -StepsFactory { Get-AddTextSteps } -Build { param($W) Build-AddTextJob $W } } },
        @{ Label = 'Add Image / Logo Watermark'; Desc = 'Place a logo or picture over the video.'; Value = { Start-StandardWorkflow -Title 'Add Image / Logo Watermark' -Description 'Overlay a logo on a video.' -Icon 'Text' -StepsFactory { Get-WatermarkSteps } -Build { param($W) Build-WatermarkJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Text') + '  Text & Watermark') -Subtitle 'Add text or an image/logo overlay to a video.' -Items $items
}

Export-ModuleMember -Function Get-DefaultFontFile, Get-AddTextSteps, Build-AddTextJob, Get-WatermarkSteps, Build-WatermarkJob, Start-OverlayWorkflow
