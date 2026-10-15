function New-CompressionTestState {
    param([string]$SourcePath, [string]$OutputDirectory, [string]$OutputName, [hashtable]$Answers = @{})
    $probe = Get-MediaInfo $SourcePath
    if (-not $probe.Ok) { throw "Could not probe fixture '$SourcePath': $($probe.Error)" }
    $state = @{ Answers = @{}; Data = @{ 'probe.input' = $probe.Info } }
    foreach ($key in $Answers.Keys) { $state.Answers[$key] = $Answers[$key] }
    $state.Answers['outdir'] = $OutputDirectory
    $state.Answers['outname'] = $OutputName
    $state.Answers['outoverwrite'] = 'rename'
    $extension = [System.IO.Path]::GetExtension($OutputName)
    $state.Data['out.ext'] = { param($W) $extension }.GetNewClosure()
    return $state
}

function Invoke-CompressionSmokeJob {
    param($Job)
    $results = @()
    foreach ($stage in @($Job.Stages)) {
        $run = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments (@('-hide_banner', '-loglevel', 'error', '-nostdin') + @($stage.Arguments)) -TimeoutSec 180
        if (-not $run.Started -or $run.TimedOut -or $run.ExitCode -ne 0) { throw ("FFmpeg stage '{0}' failed: {1}" -f $stage.Name, $run.StdErr) }
        $results += , $run
    }
    if ($Job.ContainsKey('FinalizeOutput') -and $Job.FinalizeOutput) { & $Job.FinalizeOutput $Job $results }
    Remove-JobTempFiles $Job
    return $Job
}

function Get-ImageAlphaRange {
    param([string]$Path)
    $rawPath = Join-Path $script:Work ('.fftui-alpha-' + [guid]::NewGuid().ToString('N') + '.raw')
    try {
        $run = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-loglevel', 'error', '-i', $Path, '-vf', 'alphaextract', '-frames:v', '1', '-pix_fmt', 'gray', '-f', 'rawvideo', $rawPath) -TimeoutSec 60
        if (-not $run.Started -or $run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $rawPath)) { throw ('Could not decode an alpha plane: ' + $run.StdErr) }
        $alphaBytes = [System.IO.File]::ReadAllBytes($rawPath)
        if ($alphaBytes.Length -eq 0) { throw 'The decoded alpha plane is empty.' }
        $minimum = 255; $maximum = 0
        foreach ($alphaByte in $alphaBytes) {
            if ($alphaByte -lt $minimum) { $minimum = [int]$alphaByte }
            if ($alphaByte -gt $maximum) { $maximum = [int]$alphaByte }
        }
        return [pscustomobject]@{ Minimum = $minimum; Maximum = $maximum }
    } finally {
        if (Test-Path -LiteralPath $rawPath) { Remove-Item -LiteralPath $rawPath -Force -ErrorAction SilentlyContinue }
    }
}

Set-TestGroup 'Compression and upscaling: real FFmpeg output and source safety'
$sourceVideo = New-Fixture 'compression source.mp4' @('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25:duration=8', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=8', '-c:v', 'libx264', '-preset', 'fast', '-crf', '16', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '96k', '-shortest')
$videoHash = (Get-FileHash -LiteralPath $sourceVideo -Algorithm SHA256).Hash
$videoInfo = Get-MediaInfo $sourceVideo
if ($videoInfo.Ok -and (Test-FFEncoder 'libx264') -and (Test-FFEncoder 'aac')) {
    $videoDir = Join-Path $script:Work 'video outputs'
    $null = New-Item -ItemType Directory -Path $videoDir -Force
    $simpleVideoState = New-CompressionTestState -SourcePath $sourceVideo -OutputDirectory $videoDir -OutputName 'balanced video.mp4' -Answers @{ mode = 'Simple'; strategy = 'Balanced' }
    $simpleVideo = Invoke-CompressionSmokeJob (Build-CompressionJob $simpleVideoState)
    Assert-True 'Simple Balanced produces a valid video output' (Test-ValidMediaFile $simpleVideo.OutputPath 'video')
    Assert-True 'Simple video compression keeps the original audio stream' ((Get-StreamOf (Get-ProbeJson $simpleVideo.OutputPath) 'audio').Count -eq 1)
    Assert-True 'video result opts into detailed measured size metrics' ($simpleVideo.DetailedSizeMetrics -and $simpleVideo.SourceSize -gt 0)
    Assert-Equal 'video compression never modifies the source' $videoHash (Get-FileHash -LiteralPath $sourceVideo -Algorithm SHA256).Hash

    $targetVideoState = New-CompressionTestState -SourcePath $sourceVideo -OutputDirectory $videoDir -OutputName 'target reduction.mp4' -Answers @{ mode = 'Advanced'; format = 'mp4'; goal = 'reduction'; videoTargetReduction = 50; vcodec = 'libx264'; preset = 'ultrafast'; resolution = 'keep'; fps = 0; acodec = 'copy' }
    $targetVideo = Invoke-CompressionSmokeJob (Build-CompressionJob $targetVideoState)
    $expectedVideoTarget = Get-CompressionTargetBytes -SourceBytes (Get-CompressionSourceBytes $videoInfo.Info) -Mode TargetReduction -Value 50
    Assert-True 'Advanced video target reduction creates a playable output' (Test-ValidMediaFile $targetVideo.OutputPath 'video')
    Assert-Equal 'Advanced 50% target is calculated from source bytes' $expectedVideoTarget $targetVideo.TargetSizeBytes
    Assert-True 'pre-execution summary includes the requested target and estimated output' (@($targetVideo.Summary | Where-Object { $_[0] -eq 'Requested target' }).Count -eq 1 -and @($targetVideo.Summary | Where-Object { $_[0] -eq 'Estimated output' }).Count -eq 1)
    Assert-True 'pre-execution notes warn about aggressive target quality risk' (@($targetVideo.Notes | Where-Object { $_ -match 'Aggressive target' }).Count -eq 1)
    Assert-Equal 'video target reduction never modifies the source' $videoHash (Get-FileHash -LiteralPath $sourceVideo -Algorithm SHA256).Hash
    $metricDisplayJob = New-JobObject -Title 'Compression result metrics check' -Summary @() -Stages @() -OutputPath $targetVideo.OutputPath -SourceSize (Get-CompressionSourceBytes $videoInfo.Info) -DetailedSizeMetrics $true -TargetSizeBytes $expectedVideoTarget
    $metricDisplay = Invoke-Ui -Action { Invoke-FFJob -Job $metricDisplayJob } -Keys '03'
    Assert-Contains 'compression result screen reports actual reduction' $metricDisplay.Output 'Actual reduction:'
    Assert-Contains 'compression result screen reports measured bytes saved' $metricDisplay.Output 'Bytes saved:'
    Assert-Contains 'compression result screen compares actual output with requested target' $metricDisplay.Output 'Requested target:'
} else { Skip-Test 'real video compression and size targeting' 'the installed FFmpeg lacks a required encoder or source probe' }

$sourceAudio = New-Fixture 'compression source.wav' @('-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=44100:duration=6', '-c:a', 'pcm_s16le')
$audioHash = (Get-FileHash -LiteralPath $sourceAudio -Algorithm SHA256).Hash
$audioInfo = Get-MediaInfo $sourceAudio
if ($audioInfo.Ok -and (Test-FFEncoder 'libmp3lame') -and (Test-FFMuxer 'mp3')) {
    $audioDir = Join-Path $script:Work 'audio outputs'
    $null = New-Item -ItemType Directory -Path $audioDir -Force
    $audioState = New-CompressionTestState -SourcePath $sourceAudio -OutputDirectory $audioDir -OutputName 'balanced audio.mp3' -Answers @{ mode = 'Simple'; strategy = 'Balanced' }
    $audioJob = Invoke-CompressionSmokeJob (Build-CompressionJob $audioState)
    Assert-True 'Simple audio compression produces a playable MP3' (Test-ValidMediaFile $audioJob.OutputPath 'audio')
    Assert-True 'lossy audio compression is reported honestly' (@($audioJob.Notes | Where-Object { $_ -match 'Lossy' }).Count -gt 0)
    Assert-Equal 'audio compression never modifies the source' $audioHash (Get-FileHash -LiteralPath $sourceAudio -Algorithm SHA256).Hash
} else { Skip-Test 'real audio compression' 'MP3 encoder/muxer is unavailable' }

$alphaImage = New-Fixture 'alpha source.png' @('-f', 'lavfi', '-i', 'color=c=red:s=64x48:d=0.1', '-frames:v', '1', '-vf', 'format=rgba,colorchannelmixer=aa=0.5', '-pix_fmt', 'rgba', '-f', 'image2')
$alphaHash = (Get-FileHash -LiteralPath $alphaImage -Algorithm SHA256).Hash
$alphaInfo = Get-MediaInfo $alphaImage
$imageDir = Join-Path $script:Work 'image outputs'
[void](New-Item -ItemType Directory -Path $imageDir -Force)
if ($alphaInfo.Ok -and (Get-CompressionMediaKind $alphaInfo.Info) -eq 'Image' -and (Test-FFEncoder 'png')) {
    $compressImageState = New-CompressionTestState -SourcePath $alphaImage -OutputDirectory $imageDir -OutputName 'compressed alpha.png' -Answers @{ mode = 'Simple'; strategy = 'Maximum' }
    $compressedImage = Invoke-CompressionSmokeJob (Build-CompressionJob $compressImageState)
    $compressedImageInfo = Get-MediaInfo $compressedImage.OutputPath
    Assert-True 'PNG compression writes a valid still image' ($compressedImageInfo.Ok -and $compressedImageInfo.Info.IsImageOnly)
    Assert-True 'PNG compression preserves alpha pixels' (Test-CompressionPixelHasAlpha $compressedImageInfo.Info)
    $compressedPngAlpha = Get-ImageAlphaRange $compressedImage.OutputPath
    Assert-Equal 'PNG compression preserves the source alpha value' 128 $compressedPngAlpha.Minimum
    Assert-Equal 'PNG compression does not make transparent pixels opaque' 128 $compressedPngAlpha.Maximum
    Assert-True 'PNG remains lossless at Maximum Compression' (@($compressedImage.Notes | Where-Object { $_ -match 'remains lossless' }).Count -gt 0)
    Assert-Equal 'PNG compression never modifies the source' $alphaHash (Get-FileHash -LiteralPath $alphaImage -Algorithm SHA256).Hash

    $compressionOverwritePath = Join-Path $imageDir 'overwrite compressed alpha.png'
    [System.IO.File]::WriteAllText($compressionOverwritePath, 'existing confirmed output')
    $compressionOverwriteHash = (Get-FileHash -LiteralPath $compressionOverwritePath -Algorithm SHA256).Hash
    $compressionOverwriteState = New-CompressionTestState -SourcePath $alphaImage -OutputDirectory $imageDir -OutputName 'overwrite compressed alpha.png' -Answers @{ mode = 'Simple'; strategy = 'Maximum' }
    $compressionOverwriteState.Answers['outoverwrite'] = 'overwrite'
    $compressionOverwriteValid = $false; $compressionOverwriteChanged = $false
    try {
        $compressionOverwriteJob = Invoke-CompressionSmokeJob (Build-CompressionJob $compressionOverwriteState)
        $compressionOverwriteInfo = Get-MediaInfo $compressionOverwritePath
        $compressionOverwriteValid = $compressionOverwriteInfo.Ok -and $compressionOverwriteInfo.Info.IsImageOnly
        $compressionOverwriteChanged = $compressionOverwriteHash -ne (Get-FileHash -LiteralPath $compressionOverwritePath -Algorithm SHA256).Hash
    } catch { }
    Assert-True 'confirmed PNG compression overwrite produces a valid image' $compressionOverwriteValid
    Assert-True 'confirmed PNG compression overwrite replaces the existing output' $compressionOverwriteChanged

    $upscaleState = New-CompressionTestState -SourcePath $alphaImage -OutputDirectory $imageDir -OutputName 'upscaled alpha.png' -Answers @{ factor = 2 }
    $upscaleJob = Invoke-CompressionSmokeJob (Build-UpscaleImageJob $upscaleState)
    $upscaledInfo = Get-MediaInfo $upscaleJob.OutputPath
    Assert-True '2x image upscaling creates a valid PNG' ($upscaledInfo.Ok -and $upscaledInfo.Info.IsImageOnly)
    Assert-Equal '2x PNG upscaling doubles width' 128 $upscaledInfo.Info.Video[0].Width
    Assert-Equal '2x PNG upscaling doubles height' 96 $upscaledInfo.Info.Video[0].Height
    Assert-True '2x PNG upscaling preserves alpha' (Test-CompressionPixelHasAlpha $upscaledInfo.Info)
    $upscaledPngAlpha = Get-ImageAlphaRange $upscaleJob.OutputPath
    Assert-True 'PNG upscaling preserves non-opaque alpha values within one rounding level' ($upscaledPngAlpha.Minimum -ge 127 -and $upscaledPngAlpha.Maximum -le 129)
    Assert-True 'upscaling reports that detail is not reconstructed' (@($upscaleJob.Notes | Where-Object { $_ -match 'does not restore detail' }).Count -gt 0)
    Assert-True 'upscaling result reports measured output dimensions' (@($upscaleJob.ResultNotes | Where-Object { $_ -match 'Actual dimensions: 128 x 96' }).Count -eq 1)
    Assert-Equal 'upscaling never modifies the source' $alphaHash (Get-FileHash -LiteralPath $alphaImage -Algorithm SHA256).Hash

    $upscaleOverwritePath = Join-Path $imageDir 'overwrite upscaled alpha.png'
    [System.IO.File]::WriteAllText($upscaleOverwritePath, 'existing confirmed output')
    $upscaleOverwriteHash = (Get-FileHash -LiteralPath $upscaleOverwritePath -Algorithm SHA256).Hash
    $upscaleOverwriteState = New-CompressionTestState -SourcePath $alphaImage -OutputDirectory $imageDir -OutputName 'overwrite upscaled alpha.png' -Answers @{ factor = 2 }
    $upscaleOverwriteState.Answers['outoverwrite'] = 'overwrite'
    $upscaleOverwriteValid = $false; $upscaleOverwriteChanged = $false
    try {
        $upscaleOverwriteJob = Invoke-CompressionSmokeJob (Build-UpscaleImageJob $upscaleOverwriteState)
        $upscaleOverwriteInfo = Get-MediaInfo $upscaleOverwritePath
        $upscaleOverwriteValid = $upscaleOverwriteInfo.Ok -and $upscaleOverwriteInfo.Info.IsImageOnly -and [int]$upscaleOverwriteInfo.Info.Video[0].Width -eq 128 -and [int]$upscaleOverwriteInfo.Info.Video[0].Height -eq 96
        $upscaleOverwriteChanged = $upscaleOverwriteHash -ne (Get-FileHash -LiteralPath $upscaleOverwritePath -Algorithm SHA256).Hash
    } catch { }
    Assert-True 'confirmed image upscale overwrite produces the expected dimensions' $upscaleOverwriteValid
    Assert-True 'confirmed image upscale overwrite replaces the existing output' $upscaleOverwriteChanged

    $upscale4State = New-CompressionTestState -SourcePath $alphaImage -OutputDirectory $imageDir -OutputName '4x upscaled alpha.png' -Answers @{ factor = 4 }
    $upscale4Job = Invoke-CompressionSmokeJob (Build-UpscaleImageJob $upscale4State)
    $upscale4Info = Get-MediaInfo $upscale4Job.OutputPath
    Assert-True '4x upscale creates a valid image' ($upscale4Info.Ok -and $upscale4Info.Info.IsImageOnly)
    Assert-Equal '4x upscale quadruples actual width' 256 $upscale4Info.Info.Video[0].Width
    Assert-Equal '4x upscale quadruples actual height' 192 $upscale4Info.Info.Video[0].Height
    Assert-True '4x upscale result reports measured output dimensions' (@($upscale4Job.ResultNotes | Where-Object { $_ -match 'Actual dimensions: 256 x 192' }).Count -eq 1)

    $customUpscaleState = New-CompressionTestState -SourcePath $alphaImage -OutputDirectory $imageDir -OutputName 'custom upscaled alpha.png' -Answers @{ factor = 'custom'; customWidth = 160; customHeight = 120 }
    $customUpscaleJob = Invoke-CompressionSmokeJob (Build-UpscaleImageJob $customUpscaleState)
    $customUpscaledInfo = Get-MediaInfo $customUpscaleJob.OutputPath
    Assert-True 'custom resolution upscale creates a valid image' ($customUpscaledInfo.Ok -and $customUpscaledInfo.Info.IsImageOnly)
    Assert-Equal 'custom resolution uses the requested width bound' 160 $customUpscaledInfo.Info.Video[0].Width
    Assert-Equal 'custom resolution preserves source aspect ratio within requested bounds' 120 $customUpscaledInfo.Info.Video[0].Height
    Assert-True 'custom upscale result reports actual measured dimensions' (@($customUpscaleJob.ResultNotes | Where-Object { $_ -match 'Actual dimensions: 160 x 120' }).Count -eq 1)
} else { Skip-Test 'real PNG compression and alpha-preserving upscale' 'PNG encoder or alpha fixture support is unavailable' }

if ($alphaInfo.Ok -and (Test-FFEncoder 'libwebp') -and (Test-FFMuxer 'webp')) {
    $webpSource = New-Fixture 'alpha source.webp' @('-i', $alphaImage, '-frames:v', '1', '-c:v', 'libwebp', '-lossless', '1', '-pix_fmt', 'bgra', '-f', 'webp')
    $webpInfo = Get-MediaInfo $webpSource
    $webpHash = (Get-FileHash -LiteralPath $webpSource -Algorithm SHA256).Hash
    if ($webpInfo.Ok -and (Test-CompressionPixelHasAlpha $webpInfo.Info)) {
        Assert-Equal 'WebP lossless source mode is detected from its image chunk' 'Lossless' (Get-CompressionImageLosslessState $webpInfo.Info)
        $webpTargetBytes = [long][math]::Max(1, [math]::Floor((Get-CompressionSourceBytes $webpInfo.Info) * 0.7))
        $webpTargetText = $webpTargetBytes.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ' B'
        $webpTargetState = New-CompressionTestState -SourcePath $webpSource -OutputDirectory $imageDir -OutputName 'webp target.webp' -Answers @{ mode = 'Advanced'; imageGoal = 'size'; imageTargetSize = $webpTargetText }
        $webpTarget = Invoke-CompressionSmokeJob (Build-CompressionJob $webpTargetState)
        $webpTargetInfo = Get-MediaInfo $webpTarget.OutputPath
        Assert-True 'lossless WebP target produces a valid still image' ($webpTargetInfo.Ok -and $webpTargetInfo.Info.IsImageOnly)
        Assert-Equal 'lossless WebP target stays a single lossless encode instead of a lossy quality search' 1 @($webpTarget.Stages).Count
        Assert-True 'lossless WebP target preserves alpha pixels' (Test-CompressionPixelHasAlpha $webpTargetInfo.Info)
        $compressedWebpAlpha = Get-ImageAlphaRange $webpTarget.OutputPath
        Assert-Equal 'lossless WebP compression preserves the source alpha value' 128 $compressedWebpAlpha.Minimum
        Assert-True 'lossless WebP target explains why its size may not be reached' (@($webpTarget.Notes | Where-Object { $_ -match 'stays lossless to preserve alpha' }).Count -eq 1)
        $webpUpscaleState = New-CompressionTestState -SourcePath $webpSource -OutputDirectory $imageDir -OutputName 'upscaled alpha.webp' -Answers @{ factor = 1.5 }
        $webpUpscale = Invoke-CompressionSmokeJob (Build-UpscaleImageJob $webpUpscaleState)
        $webpUpscaledInfo = Get-MediaInfo $webpUpscale.OutputPath
        Assert-Equal '1.5x WebP upscale rounds width while preserving aspect ratio' 96 $webpUpscaledInfo.Info.Video[0].Width
        Assert-Equal '1.5x WebP upscale rounds height while preserving aspect ratio' 72 $webpUpscaledInfo.Info.Video[0].Height
        Assert-True 'WebP upscaling preserves alpha pixels' (Test-CompressionPixelHasAlpha $webpUpscaledInfo.Info)
        $upscaledWebpAlpha = Get-ImageAlphaRange $webpUpscale.OutputPath
        Assert-True 'WebP upscaling preserves non-opaque alpha values within one rounding level' ($upscaledWebpAlpha.Minimum -ge 127 -and $upscaledWebpAlpha.Maximum -le 129)
        Assert-Equal 'WebP compression and upscaling never modify the source' $webpHash (Get-FileHash -LiteralPath $webpSource -Algorithm SHA256).Hash

        $opaqueWebp = New-Fixture 'lossy target source.webp' @('-f', 'lavfi', '-i', 'testsrc2=size=160x120:rate=1:duration=1', '-frames:v', '1', '-c:v', 'libwebp', '-quality', '75', '-pix_fmt', 'yuv420p', '-f', 'webp')
        $opaqueWebpInfo = Get-MediaInfo $opaqueWebp
        if ($opaqueWebpInfo.Ok -and (Get-CompressionImageLosslessState $opaqueWebpInfo.Info) -eq 'Lossy' -and -not (Test-CompressionPixelHasAlpha $opaqueWebpInfo.Info)) {
            $opaqueTargetBytes = [long][math]::Max(1, [math]::Floor((Get-CompressionSourceBytes $opaqueWebpInfo.Info) * 0.7))
            $opaqueTargetText = $opaqueTargetBytes.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ' B'
            $opaqueTargetState = New-CompressionTestState -SourcePath $opaqueWebp -OutputDirectory $imageDir -OutputName 'lossy webp target.webp' -Answers @{ mode = 'Advanced'; imageGoal = 'size'; imageTargetSize = $opaqueTargetText }
            $opaqueTarget = Invoke-CompressionSmokeJob (Build-CompressionJob $opaqueTargetState)
            $opaqueTargetInfo = Get-MediaInfo $opaqueTarget.OutputPath
            Assert-True 'bounded lossy WebP target search produces a valid still image' ($opaqueTargetInfo.Ok -and $opaqueTargetInfo.Info.IsImageOnly)
            Assert-Equal 'lossy WebP target search runs eight bounded quality candidates' 8 @($opaqueTarget.Stages).Count
            Assert-True 'lossy WebP target search records the selected quality' (@($opaqueTarget.ResultNotes | Where-Object { $_ -match 'Selected quality' }).Count -eq 1)
        } else { Skip-Test 'bounded lossy WebP target search' 'the installed decoder did not identify a supported opaque lossy WebP fixture' }
    } else { Skip-Test 'WebP alpha target and upscale' 'the installed libwebp encoder did not produce a probed alpha image' }
} else { Skip-Test 'WebP alpha target and upscale' 'the installed FFmpeg build lacks the WebP encoder or muxer' }

$jpeg = New-Fixture 'target search source.jpg' @('-f', 'lavfi', '-i', 'testsrc2=size=160x120:rate=1:duration=1', '-frames:v', '1', '-q:v', '2', '-update', '1', '-f', 'image2')
$jpegInfo = Get-MediaInfo $jpeg
if ($jpegInfo.Ok -and (Get-CompressionMediaKind $jpegInfo.Info) -eq 'Image' -and (Test-FFEncoder 'mjpeg') -and (Test-FFMuxer 'image2')) {
    $imageDir = Join-Path $script:Work 'image outputs'
    $null = New-Item -ItemType Directory -Path $imageDir -Force
    $targetBytes = [long][math]::Max(1, [math]::Floor((Get-CompressionSourceBytes $jpegInfo.Info) * 0.6))
    $targetSizeText = $targetBytes.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ' B'
    $targetImageState = New-CompressionTestState -SourcePath $jpeg -OutputDirectory $imageDir -OutputName 'target search.jpg' -Answers @{ mode = 'Advanced'; imageGoal = 'size'; imageTargetSize = $targetSizeText }
    $targetImage = Invoke-CompressionSmokeJob (Build-CompressionJob $targetImageState)
    $targetImageInfo = Get-MediaInfo $targetImage.OutputPath
    Assert-True 'bounded JPEG target search produces a valid still image' ($targetImageInfo.Ok -and $targetImageInfo.Info.IsImageOnly)
    Assert-Equal 'JPEG target search runs exactly eight bounded quality candidates' 8 @($targetImage.Stages).Count
    Assert-Equal 'JPEG search records the target for measured result comparison' $targetBytes $targetImage.TargetSizeBytes
    Assert-True 'JPEG target search records which quality was selected' (@($targetImage.ResultNotes | Where-Object { $_ -match 'Selected quality' }).Count -eq 1)
    $impossibleTargetState = New-CompressionTestState -SourcePath $jpeg -OutputDirectory $imageDir -OutputName 'unreachable target.jpg' -Answers @{ mode = 'Advanced'; imageGoal = 'size'; imageTargetSize = '1 B' }
    $impossibleTarget = Invoke-CompressionSmokeJob (Build-CompressionJob $impossibleTargetState)
    Assert-True 'unreachable image target is explicitly reported after bounded quality search' (@($impossibleTarget.ResultNotes | Where-Object { $_ -match 'was not reached within tolerance' }).Count -eq 1)
} else { Skip-Test 'bounded JPEG target-size search' 'JPEG encoder/muxer is unavailable' }
