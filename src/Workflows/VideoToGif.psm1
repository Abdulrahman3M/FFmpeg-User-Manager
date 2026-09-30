# VideoToGif.psm1 - workflow 8: Video to GIF (palette-based high quality path).
Set-StrictMode -Version 2.0

function Get-GifSteps {
    $fpsList = Get-PresetList 'gifFps' @(10, 15, 20, 24, 30)
    $widthList = Get-PresetList 'gifWidths' @(320, 480, 640, 720)
    $speedList = Get-PresetList 'speeds' @(0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0)
    $hq = { param($W) (Get-Answer $W 'palette' 'high') -eq 'high' }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += Get-TimeRangeSteps -Prefix 't' -InputId 'input' -Prompt 'Clip range'
    $steps += @{ Id = 'fps'; Type = 'Choice'; Prompt = 'Frame rate'; Help = 'Higher FPS looks smoother but increases GIF size.'
        Choices = { param($W) @($fpsList | ForEach-Object { New-Choice ([double]$_) (("{0:0.##} FPS" -f $_) + $(if ($_ -eq 15) { '  (Recommended)' } else { '' })) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'FrameRate'; Prompt = 'Custom GIF frame rate'; Help = 'Frames per second between 0.1 and 240 (GIFs above 30 FPS rarely play smoothly).'; Example = '12'; Desc = 'For example 12.' }
        Default = 15.0 }
    $steps += @{ Id = 'maxframes'; Type = 'Integer'; Prompt = 'Maximum number of frames'; Help = 'Optional. Stops the GIF after this many frames.'; Example = '150'; Optional = $true; Min = 1; Max = 100000; Label = 'Frame limit' }
    $steps += @{ Id = 'speed'; Type = 'Choice'; Prompt = 'GIF speed'; Help = '1.0x keeps the original speed. Faster speeds shorten the GIF.'
        Choices = { param($W) @($speedList | ForEach-Object { New-Choice ([double]$_) (("{0:0.0#}x" -f $_) + $(if ($_ -eq 1.0) { '  (Original speed)' } else { '' })) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.1; Max = 8; Prompt = 'Custom speed'; Help = 'A multiplier between 0.1 and 8.'; Example = '1.75'; ValueLabel = 'Speed'; Desc = 'For example 1.75.' }
        Default = 1.0 }
    $steps += @{ Id = 'width'; Type = 'Choice'; Prompt = 'Width'; Help = 'Smaller dimensions reduce file size significantly.'
        Choices = { param($W) $m = Get-Media $W 'input'; @(New-Choice 0 'Keep original size') + @($widthList | ForEach-Object { New-Choice ([int]$_) (("{0} px" -f $_) + $(if ($_ -eq 480) { '  (Recommended)' } else { '' })) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 16; Max = 4096; Prompt = 'Custom width'; Help = 'Enter a positive pixel value, e.g. 1280.'; Example = '1280'; ValueLabel = 'Width'; Desc = 'Enter a pixel value.' }
        Default = 480 }
    $steps += @{ Id = 'keepaspect'; Type = 'YesNo'; Prompt = 'Preserve the aspect ratio?'; Help = 'Recommended: the height is calculated automatically so the picture is not distorted.'; Default = $true
        YesLabel = 'Yes, keep the proportions'; NoLabel = 'No, set the height myself'; When = { param($W) [int](Get-Answer $W 'width' 0) -gt 0 } }
    $steps += @{ Id = 'height'; Type = 'Integer'; Prompt = 'Height'; Help = 'Enter a positive pixel value.'; Example = '360'; Min = 16; Max = 4096; Label = 'Height'
        When = { param($W) ([int](Get-Answer $W 'width' 0) -gt 0) -and -not (Get-Answer $W 'keepaspect' $true) } }
    $steps += @{ Id = 'palette'; Type = 'Choice'; Prompt = 'Palette quality'; Help = 'High Quality creates a better color palette before generating the GIF.'
        Choices = { param($W) $ok = Test-FFAllFilters @('palettegen', 'paletteuse'); @( (New-Choice 'high' 'High Quality / Recommended' 'Generates an optimized palette (best colors).' $ok 'Your FFmpeg build lacks palettegen/paletteuse.'), (New-Choice 'fast' 'Fast' 'Uses the default palette; quicker but lower color quality.') ) }
        Default = { param($W) if (Test-FFAllFilters @('palettegen', 'paletteuse')) { 'high' } else { 'fast' } } }
    $steps += @{ Id = 'colors'; Type = 'Choice'; Prompt = 'Number of colors'; Help = 'Fewer colors make smaller files. 256 is the GIF maximum.'; When = $hq
        Choices = { param($W) @( (New-Choice 256 '256 colors (Recommended)'), (New-Choice 128 '128 colors'), (New-Choice 64 '64 colors'), (New-Choice 32 '32 colors'), (New-Choice 16 '16 colors') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 2; Max = 256; Prompt = 'Custom color count'; Help = 'A number between 2 and 256.'; Example = '200'; ValueLabel = 'Colors'; Desc = 'Between 2 and 256.' }
        Default = 256 }
    $steps += @{ Id = 'dither'; Type = 'Choice'; Prompt = 'Dithering method'; Help = 'Dithering smooths color transitions. Recommended works well for most videos.'; When = $hq
        Choices = { param($W) @( (New-Choice 'sierra2_4a' 'Recommended (Sierra 2-4A)' 'Smooth results with modest size.'), (New-Choice 'floyd_steinberg' 'Floyd-Steinberg' 'Classic error diffusion.'), (New-Choice 'bayer' 'Bayer (ordered)' 'Patterned, smaller files.'), (New-Choice 'none' 'None' 'No dithering; smallest, may show banding.') ) }
        Default = 'sierra2_4a' }
    $steps += @{ Id = 'loop'; Type = 'Choice'; Prompt = 'Loop behavior'; Help = 'How many times the animation repeats.'
        Choices = { param($W) @( (New-Choice 0 'Infinite loop (Recommended)'), (New-Choice -1 'Play once (no loop)') ) }
        AllowCustom = @{ Label = 'Repeat a set number of times...'; Type = 'Integer'; Min = 1; Max = 1000; Prompt = 'Number of repeats'; Help = 'How many extra times the GIF repeats after the first play.'; Example = '3'; ValueLabel = 'Repeats'; Desc = 'For example 3.' }
        Default = 0 }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'gif' -Extension { param($W) '.gif' }
    return $steps
}

function Get-GifFilterGraph {
    # Builds the filter chain from validated numbers only (no user text).
    param([double]$Speed, [double]$Fps, [int]$Width, $Height, [string]$Palette, [int]$Colors, [string]$Dither)
    $f = @()
    if ([math]::Abs($Speed - 1.0) -gt 1e-9) { $f += ('setpts=PTS/' + (Format-FFNumber $Speed 6)) }
    $f += ('fps=' + (Format-FFNumber $Fps 4))
    if ($Width -gt 0) {
        if ($Height) { $f += "scale=${Width}:${Height}:flags=lanczos" } else { $f += "scale=${Width}:-1:flags=lanczos" }
    }
    $chain = $f -join ','
    if ($Palette -eq 'high') {
        $d = $Dither; if ($d -eq 'bayer') { $d = 'bayer:bayer_scale=3' }
        return ($chain + ',split[s0][s1];[s0]palettegen=max_colors=' + $Colors + ':stats_mode=full[p];[s1][p]paletteuse=dither=' + $d)
    }
    return $chain
}

function Build-GifJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $range = Resolve-TimeRange $W 't' 'input'
    $speed = [double](Get-Answer $W 'speed' 1.0); $fps = [double](Get-Answer $W 'fps' 15)
    $width = [int](Get-Answer $W 'width' 0)
    $height = $null; if ($width -gt 0 -and -not (Get-Answer $W 'keepaspect' $true)) { $height = [int](Get-Answer $W 'height') }
    $palette = [string](Get-Answer $W 'palette' 'high')
    $graph = Get-GifFilterGraph -Speed $speed -Fps $fps -Width $width -Height $height -Palette $palette -Colors ([int](Get-Answer $W 'colors' 256)) -Dither ([string](Get-Answer $W 'dither' 'sierra2_4a'))
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path (Get-RangeInputOptions $range))
    Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index), '-an', '-vf', $graph)
    $maxf = Get-Answer $W 'maxframes'
    if ($maxf) { Add-FFOutOpt $cmd @('-frames:v', [string][int]$maxf) }
    Add-FFOutOpt $cmd @('-loop', [string][int](Get-Answer $W 'loop' 0), '-f', 'gif')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    if ($fps -gt 30) { $notes += 'Frame rates above 30 FPS are often played more slowly by browsers and viewers.' }
    $dur = $range.Duration; if ($dur) { $dur = $dur / $speed }
    $loopTxt = switch ([int](Get-Answer $W 'loop' 0)) { 0 { 'Infinite' } -1 { 'Play once' } default { ('Repeat ' + (Get-Answer $W 'loop') + ' time(s)') } }
    $rows = @(
        @('Input', $info.FileName),
        @('Range', $(if ($range.Full) { 'Entire video' } else { ('{0} + {1} s' -f (Format-Duration $range.Start), (Format-FFNumber $range.Duration 2)) })),
        @('Frame rate', ("{0:0.##} FPS" -f $fps)), @('Speed', ("{0:0.##}x" -f $speed)),
        @('Width', $(if ($width -gt 0) { "$width px" + $(if ($height) { " x $height px" } else { ' (aspect kept)' }) } else { 'Original' })),
        @('Palette', $(if ($palette -eq 'high') { "High quality, $(Get-Answer $W 'colors' 256) colors, dither $(Get-Answer $W 'dither' 'sierra2_4a')" } else { 'Fast (default palette)' })),
        @('Loop', $loopTxt), @('Output', $out.Path)
    )
    return New-JobObject -Title 'Creating GIF' -Summary $rows -Stages @(@{ Name = 'Rendering GIF'; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

function Start-GifWorkflow {
    Start-StandardWorkflow -Title 'Video to GIF' -Description 'Convert a video or selected clip into an animated GIF.' -Icon 'Gif' -StepsFactory { Get-GifSteps } -Build { param($W) Build-GifJob $W }
}

Export-ModuleMember -Function Get-GifSteps, Get-GifFilterGraph, Build-GifJob, Start-GifWorkflow
