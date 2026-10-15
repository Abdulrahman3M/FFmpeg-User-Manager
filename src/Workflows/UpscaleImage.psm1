# UpscaleImage.psm1 - workflow 7: Upscale Image.
Set-StrictMode -Version 2.0

function Get-UpscaleDimensions {
    param([Parameter(Mandatory)][int]$Width, [Parameter(Mandatory)][int]$Height, [Parameter(Mandatory)][double]$Factor)
    if ($Width -le 0 -or $Height -le 0) { throw 'The source image dimensions must be positive.' }
    if ([double]::IsNaN($Factor) -or [double]::IsInfinity($Factor) -or $Factor -le 1.0 -or $Factor -gt 16.0) { throw 'Upscaling factor must be greater than 1 and no greater than 16.' }
    $scaledWidth = [double]$Width * $Factor
    $scaledHeight = [double]$Height * $Factor
    if ($scaledWidth -gt 32768 -or $scaledHeight -gt 32768) { throw 'The requested result exceeds the supported 32768-pixel limit. Choose a smaller factor.' }
    $targetWidth = [int][math]::Round($scaledWidth, 0, [MidpointRounding]::AwayFromZero)
    $targetHeight = [int][math]::Round($scaledHeight, 0, [MidpointRounding]::AwayFromZero)
    if ($targetWidth -le $Width -or $targetHeight -le $Height) { throw 'The selected factor does not create a larger image.' }
    return [pscustomobject]@{ Width = $targetWidth; Height = $targetHeight; Factor = $Factor }
}

function Get-UpscaleCustomDimensions {
    param([Parameter(Mandatory)][int]$Width, [Parameter(Mandatory)][int]$Height, [Parameter(Mandatory)][int]$TargetWidth, [Parameter(Mandatory)][int]$TargetHeight)
    if ($Width -le 0 -or $Height -le 0) { throw 'The source image dimensions must be positive.' }
    if ($TargetWidth -le 0 -or $TargetHeight -le 0) { throw 'Custom width and height must be positive whole numbers.' }
    if ($TargetWidth -gt 32768 -or $TargetHeight -gt 32768) { throw 'Custom dimensions cannot exceed the supported 32768-pixel limit.' }
    if ($TargetWidth -le $Width -or $TargetHeight -le $Height) { throw 'Custom width and height must both be larger than the source image.' }
    $factor = [math]::Min(([double]$TargetWidth / [double]$Width), ([double]$TargetHeight / [double]$Height))
    $scaledWidth = [int][math]::Round(([double]$Width * $factor), 0, [MidpointRounding]::AwayFromZero)
    $scaledHeight = [int][math]::Round(([double]$Height * $factor), 0, [MidpointRounding]::AwayFromZero)
    if ($scaledWidth -gt $TargetWidth) { $scaledWidth = $TargetWidth }
    if ($scaledHeight -gt $TargetHeight) { $scaledHeight = $TargetHeight }
    if ($scaledWidth -le $Width -or $scaledHeight -le $Height) { throw 'The custom resolution does not enlarge both source dimensions.' }
    return [pscustomobject]@{ Width = $scaledWidth; Height = $scaledHeight; Factor = $factor; TargetWidth = $TargetWidth; TargetHeight = $TargetHeight }
}

function Get-UpscaleFilter {
    param([Parameter(Mandatory)][int]$Width, [Parameter(Mandatory)][int]$Height, [Parameter(Mandatory)][double]$Factor)
    $dimensions = Get-UpscaleDimensions -Width $Width -Height $Height -Factor $Factor
    return (New-ScaleFilter -Height $dimensions.Height -Mode Preserve -Algorithm 'lanczos')
}

function Get-UpscaleSteps {
    $inputExtra = {
        param($Info, $W)
        if ((Get-CompressionMediaKind $Info) -ne 'Image') { return 'Choose a still JPEG, PNG, or WebP image.' }
        try { $null = Get-CompressionImageFormat $Info } catch { return $_.Exception.Message }
        if (-not (Test-FFFilter 'scale')) { return 'The installed FFmpeg build does not include the scale filter required for upscaling.' }
        if ([int]$Info.Video[0].Width -le 0 -or [int]$Info.Video[0].Height -le 0) { return 'The source image dimensions could not be read.' }
        return $null
    }.GetNewClosure()
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input image (JPEG, PNG, or WebP)' -Require Any -Extra $inputExtra
    $steps += @{
        Id = 'factor'; Type = 'Choice'; Prompt = 'Upscaling factor'; Help = 'The image is enlarged with Lanczos. Upscaling adds pixels but cannot recover detail that was not in the source.'
        Choices = { param($W) @( (New-Choice 1.5 '1.5x' 'Enlarge by 50%; a moderate increase in dimensions.'), (New-Choice 2 '2x' 'Double width and height; four times as many pixels.'), (New-Choice 4 '4x' 'Quadruple width and height; sixteen times as many pixels.'), (New-Choice 'custom' 'Custom Resolution' 'Set maximum width and height; the source aspect ratio is preserved within those bounds.') ) }
        Default = 2
    }
    $customResolution = { param($W) (Get-Answer $W 'factor') -eq 'custom' }.GetNewClosure()
    $steps += @{
        Id = 'customWidth'; Type = 'Integer'; Prompt = 'Custom maximum width'; Label = 'Width'; Example = '1600'; Help = 'Enter a positive width in pixels, greater than the source width and no greater than 32768. Height is fitted to preserve aspect ratio.'
        Min = 1; Max = 32768; When = $customResolution
        Validate = {
            param($Value, $W)
            $Info = Get-Media $W 'input'
            if ([int]$Value -le [int]$Info.Video[0].Width) { return 'Custom width must be larger than the source width.' }
            return $null
        }.GetNewClosure()
    }
    $steps += @{
        Id = 'customHeight'; Type = 'Integer'; Prompt = 'Custom maximum height'; Label = 'Height'; Example = '1200'; Help = 'Enter a positive height in pixels, greater than the source height and no greater than 32768. The output fits within the requested width and height without stretching.'
        Min = 1; Max = 32768; When = $customResolution
        Validate = {
            param($Value, $W)
            $Info = Get-Media $W 'input'
            try { $null = Get-UpscaleCustomDimensions -Width ([int]$Info.Video[0].Width) -Height ([int]$Info.Video[0].Height) -TargetWidth ([int](Get-Answer $W 'customWidth')) -TargetHeight ([int]$Value) }
            catch { return $_.Exception.Message }
            return $null
        }.GetNewClosure()
    }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'upscaled' -Extension {
        param($W)
        $Info = Get-Media $W 'input'
        $profile = Get-ImageCompressionProfile -Format (Get-CompressionImageFormat $Info) -Preset 'Light' -Lossless:((Get-CompressionImageFormat $Info) -in @('png', 'webp'))
        return [string]$profile.Extension
    }.GetNewClosure()
    return $steps
}

function Build-UpscaleImageJob {
    param($W)
    $Info = Get-Media $W 'input'
    if (-not $Info -or (Get-CompressionMediaKind $Info) -ne 'Image') { throw 'Choose a supported still image before building the upscale job.' }
    $format = Get-CompressionImageFormat $Info
    $selectedFactor = Get-Answer $W 'factor' 2
    $sourceWidth = [int]$Info.Video[0].Width; $sourceHeight = [int]$Info.Video[0].Height
    if ([string]$selectedFactor -eq 'custom') {
        $dimensions = Get-UpscaleCustomDimensions -Width $sourceWidth -Height $sourceHeight -TargetWidth ([int](Get-Answer $W 'customWidth')) -TargetHeight ([int](Get-Answer $W 'customHeight'))
        $filter = New-ScaleFilter -Width $dimensions.Width -Height $dimensions.Height -Mode Preserve -Algorithm 'lanczos'
    } else {
        $factor = [double]$selectedFactor
        $dimensions = Get-UpscaleDimensions -Width $sourceWidth -Height $sourceHeight -Factor $factor
        $filter = Get-UpscaleFilter -Width $sourceWidth -Height $sourceHeight -Factor $factor
    }
    $factor = [double]$dimensions.Factor
    $lossless = ($format -in @('png', 'webp'))
    $profile = Get-ImageCompressionProfile -Format $format -Preset 'Light' -Lossless:$lossless
    $hasAlpha = Test-CompressionPixelHasAlpha $Info
    $output = Get-OutputFile $W
    $arguments = Get-CompressionImageArguments -Info $Info -OutputPath $output.Path -Profile $profile -Quality $profile.Quality -HasAlpha:$hasAlpha -VideoFilter $filter -Overwrite:$output.Overwrite
    $notes = @('Lanczos enlarges the existing pixels; it does not restore detail that was absent from the source image.')
    if ($format -eq 'jpeg' -and $hasAlpha) { $notes += 'JPEG cannot preserve transparency; transparent pixels are composited by FFmpeg.' }
    if ($format -eq 'webp') { $notes += 'WebP is written losslessly to avoid adding another lossy generation; the output may be larger.' }
    if ($output.Overwrite) { $notes += 'The existing output file will be overwritten because you chose that option.' }
    $dimensionLabel = if ([string]$selectedFactor -eq 'custom') { 'Planned output dimensions (preserve ratio)' } else { 'Planned output dimensions' }
    $summary = @(@('Input', $Info.FileName), @('Source dimensions', ('{0} x {1}' -f $sourceWidth, $sourceHeight)), @('Requested scale', ('{0}x' -f (Format-FFNumber $factor 3))), @($dimensionLabel, ('about {0} x {1}' -f $dimensions.Width, $dimensions.Height)), @('Scaling filter', 'Lanczos'), @('Output format', $format.ToUpperInvariant()), @('Output', $output.Path))
    $job = New-JobObject -Title 'Upscaling image' -Summary $summary -Stages @(@{ Name = 'Upscaling image'; Arguments = $arguments; DurationSec = $null }) -OutputPath $output.Path -EnsureDirs @($output.Dir) -SourceSize (Get-CompressionSourceBytes $Info) -CompareSize $true -Notes $notes
    $job.FinalizeOutput = {
        param($CompletedJob, $StageResults)
        $outputProbe = Get-MediaInfo -Path ([string]$CompletedJob.OutputPath)
        if ($outputProbe.Ok -and $outputProbe.Info.Video.Count -gt 0) {
            $actualWidth = [int]$outputProbe.Info.Video[0].Width; $actualHeight = [int]$outputProbe.Info.Video[0].Height
            $scaleX = [double]$actualWidth / [double]$sourceWidth
            $scaleY = [double]$actualHeight / [double]$sourceHeight
            $CompletedJob.ResultNotes += ('Actual dimensions: {0} x {1}; measured scale: {2}x wide, {3}x high.' -f $actualWidth, $actualHeight, (Format-FFNumber $scaleX 3), (Format-FFNumber $scaleY 3))
        } else {
            $CompletedJob.ResultNotes += 'The output dimensions could not be verified with ffprobe.'
        }
        $CompletedJob.ResultNotes += 'Scaling algorithm: Lanczos.'
    }.GetNewClosure()
    return $job
}

function Start-UpscaleImageWorkflow {
    Start-StandardWorkflow -Title 'Upscale Image' -Description 'Enlarge JPEG, PNG, or WebP images by 1.5x, 2x, 4x, or a custom resolution using Lanczos scaling.' -Icon 'Upscale' -StepsFactory { Get-UpscaleSteps } -Build { param($W) Build-UpscaleImageJob $W }
}

Export-ModuleMember -Function Get-UpscaleDimensions, Get-UpscaleCustomDimensions, Get-UpscaleFilter, Get-UpscaleSteps, Build-UpscaleImageJob, Start-UpscaleImageWorkflow
