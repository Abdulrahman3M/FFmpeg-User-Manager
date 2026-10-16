# Web Media Optimization smoke tests use the real FFmpeg and ffprobe executables.
$W = Get-TestWork
$sourceVideo = New-Fixture 'web media sample.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=4:size=160x120:rate=20', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=4', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$webmCodecs = @(Get-WebMCodecChoices)
if ($webmCodecs.Count -eq 0) {
    Skip-Test 'WebM conversion and sample-size estimate' 'the installed FFmpeg build has no WebM muxer plus VP9/AV1 encoder'
} else {
    $webmOutput = Join-Path $W 'web media sample_web.webm'
    $ui = Invoke-Flow { Start-WebMWorkflow } @(
        (New-Rule 'Input video' "$sourceVideo{Enter}"),
        (New-Rule 'WebM video codec' '01'),
        (New-Rule 'Video quality' '02'),
        (New-Rule 'Output resolution' '01'),
        (New-Rule 'Audio' '01'),
        (New-Rule 'Estimate size before converting?' '02'),
        (New-Rule 'Output folder' '{Enter}'),
        (New-Rule 'Output WebM file name' '{Enter}'),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Completed successfully' '{#Main menu}' 1)
    ) -MaxCalls 100
    Assert-True 'WebM workflow converts a real video without an estimate when the user skips sampling' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
    Assert-True 'WebM output is valid video with the selected VP9 encoder' ((Test-ValidMediaFile $webmOutput 'video') -and (Get-StreamOf (Get-ProbeJson $webmOutput) 'video')[0].codec_name -eq 'vp9')
    Assert-True 'source video remains untouched after WebM conversion' (Test-Path -LiteralPath $sourceVideo)

    $estimatedOutput = Join-Path $W 'web media sample_estimated.webm'
    $ui = Invoke-Flow { Start-WebMWorkflow } @(
        (New-Rule 'Input video' "$sourceVideo{Enter}"),
        (New-Rule 'WebM video codec' '01'),
        (New-Rule 'Video quality' '02'),
        (New-Rule 'Output resolution' '01'),
        (New-Rule 'Audio' '01'),
        (New-Rule 'Estimate size before converting?' '{Enter}'),
        (New-Rule 'Output folder' '{Enter}'),
        (New-Rule 'Output WebM file name' '{Clear}web media sample_estimated.webm{Enter}'),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Estimate complete' '01' 1),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Completed successfully' '{#Main menu}' 1)
    ) -MaxCalls 140
    Assert-True 'WebM size estimate completes then continues into the actual conversion' ($ui.Error -eq '' -and $ui.Output.Contains('Estimate complete') -and $ui.Output.Contains('Likely range') -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
    Assert-True 'sample estimate eventually creates only the requested final output, without changing the source' ((Test-ValidMediaFile $estimatedOutput 'video') -and (Test-Path -LiteralPath $sourceVideo))
}

$lossyDir = Join-Path $W 'webp lossy inputs'
$lossyOne = New-Fixture 'one.png' @('-f', 'lavfi', '-i', 'testsrc=size=80x60:duration=1', '-frames:v', '1') -Dir $lossyDir
$lossyTwo = New-Fixture 'two.jpg' @('-f', 'lavfi', '-i', 'color=c=blue:s=80x60:d=1', '-frames:v', '1', '-q:v', '4') -Dir $lossyDir
$folderSelection = [pscustomobject]@{ Answers = @{ webpInputMode = 'folder'; webpFolder = $lossyDir } }
$selectedWebPPaths = @(Get-WebPSelectedFiles $folderSelection)
Assert-True 'folder-selected WebP inputs are full path strings on both PowerShell editions' (@($selectedWebPPaths | Where-Object { $_ -is [string] -and @($lossyOne, $lossyTwo) -contains $_ }).Count -eq 2)
if (-not (Test-WebPAvailable)) {
    Skip-Test 'WebP batch conversion' 'the installed FFmpeg build has no libwebp encoder and WebP muxer'
} else {
    $ui = Invoke-Flow { Start-WebPWorkflow } @(
        (New-Rule 'Select images' '02'),
        (New-Rule 'Folder containing images' "$lossyDir{Enter}"),
        (New-Rule 'WebP encoding mode' '01'),
        (New-Rule 'Lossy image quality' '03'),
        (New-Rule 'Output folder' '{Enter}'),
        (New-Rule 'If a WebP output already exists' '01'),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Completed successfully' '{#Main menu}' 1)
    ) -MaxCalls 120
    $lossyOut = Join-Path $lossyDir 'WebP'
    Assert-True 'lossy WebP folder batch completes for PNG and JPEG inputs' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
    Assert-True 'batch WebP files are valid and both source images remain untouched' ((Test-ValidMediaFile (Join-Path $lossyOut 'one.webp') 'video') -and (Test-ValidMediaFile (Join-Path $lossyOut 'two.webp') 'video') -and (Test-Path -LiteralPath $lossyOne) -and (Test-Path -LiteralPath $lossyTwo))

    $losslessDir = Join-Path $W 'webp lossless inputs'
    $losslessSource = New-Fixture 'lossless.png' @('-f', 'lavfi', '-i', 'testsrc2=size=64x64:duration=1,format=rgba,colorchannelmixer=aa=0.5', '-frames:v', '1', '-pix_fmt', 'rgba', '-c:v', 'png') -Dir $losslessDir
    $ui = Invoke-Flow { Start-WebPWorkflow } @(
        (New-Rule 'Select images' '02'),
        (New-Rule 'Folder containing images' "$losslessDir{Enter}"),
        (New-Rule 'WebP encoding mode' '02'),
        (New-Rule 'Output folder' '{Enter}'),
        (New-Rule 'If a WebP output already exists' '01'),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Completed successfully' '{#Main menu}' 1)
    ) -MaxCalls 120
    $losslessOut = Join-Path $losslessDir 'WebP'
    Assert-True 'lossless WebP encoding completes for a real PNG image' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully')) (Get-LastFrame $ui.Output)
    Assert-True 'lossless WebP output is valid and original image is unchanged' ((Test-ValidMediaFile (Join-Path $losslessOut 'lossless.webp') 'video') -and (Test-Path -LiteralPath $losslessSource))
    $alphaRaw = Join-Path $losslessDir 'lossless-alpha.rgba'
    $alphaDecode = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-loglevel', 'error', '-y', '-i', (Join-Path $losslessOut 'lossless.webp'), '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgba', $alphaRaw)
    $alphaPixelBytes = @(); if ($alphaDecode.ExitCode -eq 0 -and (Test-Path -LiteralPath $alphaRaw)) { $alphaPixelBytes = [System.IO.File]::ReadAllBytes($alphaRaw) }
    $transparentPixelCount = 0; for ($pixelByte = 3; $pixelByte -lt $alphaPixelBytes.Length; $pixelByte += 4) { if ($alphaPixelBytes[$pixelByte] -lt 255) { $transparentPixelCount++ } }
    Assert-True 'lossless WebP retains source PNG alpha transparency' ($alphaDecode.ExitCode -eq 0 -and $transparentPixelCount -gt 0)
}

$mediaFilesBeforeEstimate = @(Get-ChildItem -LiteralPath $W -File -Recurse).Count
$ui = Invoke-Flow { Start-WebSizeEstimateWorkflow } @(
    (New-Rule 'Input video' "$sourceVideo{Enter}"),
    (New-Rule 'Target video bitrate' '{Enter}'),
    (New-Rule 'Include audio in the estimate?' '{Enter}'),
    (New-Rule 'Target audio bitrate' '{Enter}'),
    (New-ScreenRule 'Summary' '{Enter}' 1),
    (New-ScreenRule 'Approximate video size' '02' 1)
) -MaxCalls 80
$mediaFilesAfterEstimate = @(Get-ChildItem -LiteralPath $W -File -Recurse).Count
Assert-True 'target-bitrate estimate uses source duration and creates no media output' ($ui.Error -eq '' -and $ui.Output.Contains('Method: target bitrate') -and $ui.Output.Contains('Estimated size') -and $mediaFilesAfterEstimate -eq $mediaFilesBeforeEstimate)

$ui = Invoke-Ui { Start-WebMediaOptimizationWorkflow } '{Esc}'
Assert-True 'Web Media Optimization submenu enables OBJ-to-GLB using bundled Assimp' ($ui.Error -eq '' -and $ui.Output.Contains('Convert Video to WebM') -and $ui.Output.Contains('Convert Images to WebP') -and $ui.Output.Contains('Convert OBJ to GLB') -and $ui.Output.Contains('Manage 3D Converter'))

Set-TestGroup 'OBJ-to-GLB end-to-end with bundled Assimp'
$oldAssimpPath = $env:PATH
$env:PATH = Join-Path $env:SystemRoot 'System32'
$modelDir = Join-Path (Join-Path (Get-TestRoot) 'tests\output') ('assimp-e2e-' + [guid]::NewGuid().ToString('N'))
try {
    $assimpStatus = Get-ThreeDToolStatus
    Assert-True 'bundled Assimp is usable without the package-manager installation directory on PATH' ($assimpStatus.Available -and $assimpStatus.Path -eq (Join-Path (Get-AppRoot) 'External-Libraries\Assimp\bin\assimp.exe')) $assimpStatus.Reason
    [void](New-Item -ItemType Directory -Path $modelDir -Force)
    $modelObj = Join-Path $modelDir 'textured-triangle.obj'
    $modelMtl = Join-Path $modelDir 'textured-triangle.mtl'
    $modelTexture = Join-Path $modelDir 'diffuse.ppm'
    $modelGlb = Join-Path $modelDir 'textured-triangle.glb'
    [System.IO.File]::WriteAllText($modelObj, "mtllib textured-triangle.mtl`no textured triangle`nv 0 0 0`nv 1 0 0`nv 0 1 0`nvt 0 0`nvt 1 0`nvt 0 1`nvn 0 0 1`nusemtl matte`nf 1/1/1 2/2/1 3/3/1`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($modelMtl, "newmtl matte`nKa 0.2 0.2 0.2`nKd 1.0 1.0 1.0`nmap_Kd diffuse.ppm`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($modelTexture, "P3`n2 2`n255`n255 0 0 0 255 0`n0 0 255 255 255 0`n", (New-Object System.Text.UTF8Encoding($false)))
    $modelSourceHashes = @((Get-FileHash -LiteralPath $modelObj -Algorithm SHA256).Hash, (Get-FileHash -LiteralPath $modelMtl -Algorithm SHA256).Hash, (Get-FileHash -LiteralPath $modelTexture -Algorithm SHA256).Hash)
    $trace = New-Object 'System.Collections.Generic.List[string]'
    $ui = Invoke-Flow { Start-ObjToGlbWorkflow } @(
        (New-Rule 'Input Wavefront OBJ file' "$modelObj{Enter}"),
        (New-Rule 'Output folder' '{Enter}'),
        (New-Rule 'Output GLB file name' 'textured-triangle.glb{Enter}'),
        (New-ScreenRule 'Summary' '{Enter}' 1),
        (New-ScreenRule 'Completed successfully' '{#Main menu}' 1)
    ) -MaxCalls 100 -Trace $trace
    Assert-True 'real conversion finishes through the application wizard and shared output-safe job runner' ($ui.Error -eq '' -and $ui.Output.Contains('Completed successfully') -and (Test-Path -LiteralPath $modelGlb -PathType Leaf)) (Get-LastFrame $ui.Output)
    $convertedModel = $null; try { $convertedModel = Read-GlbJsonChunk -Path $modelGlb } catch { }
    $convertedPrimitive = $null; $convertedMeshes = @(Get-WebJsonProperty $convertedModel 'meshes'); $convertedMaterials = @(Get-WebJsonProperty $convertedModel 'materials'); $convertedImages = @(Get-WebJsonProperty $convertedModel 'images'); $convertedAsset = Get-WebJsonProperty $convertedModel 'asset'
    if ($convertedMeshes.Count -gt 0 -and @(Get-WebJsonProperty $convertedMeshes[0] 'primitives').Count -gt 0) { $convertedPrimitive = (Get-WebJsonProperty $convertedMeshes[0] 'primitives')[0] }
    $warnings = @(Get-ObjGlbWarnings -ObjPath $modelObj -GlbPath $modelGlb -DependencyReport (Get-ObjDependencyReport -Path $modelObj))
    $convertedAttributes = Get-WebJsonProperty $convertedPrimitive 'attributes'
    Assert-True 'GLB output contains glTF 2 geometry, normals, UV coordinates, material and texture reference' ($null -ne $convertedModel -and (Get-WebJsonProperty $convertedAsset 'version') -eq '2.0' -and $null -ne (Get-WebJsonProperty $convertedAttributes 'POSITION') -and $null -ne (Get-WebJsonProperty $convertedAttributes 'NORMAL') -and $null -ne (Get-WebJsonProperty $convertedAttributes 'TEXCOORD_0') -and $convertedMaterials.Count -gt 0 -and $convertedImages.Count -gt 0)
    Assert-True 'application reports the external texture reference and leaves every OBJ/MTL/texture source unchanged' (@($warnings | Where-Object { $_ -match 'external files|embedded GLB texture' }).Count -gt 0 -and $ui.Output -match 'external files|embedded GLB texture' -and (Get-FileHash -LiteralPath $modelObj -Algorithm SHA256).Hash -eq $modelSourceHashes[0] -and (Get-FileHash -LiteralPath $modelMtl -Algorithm SHA256).Hash -eq $modelSourceHashes[1] -and (Get-FileHash -LiteralPath $modelTexture -Algorithm SHA256).Hash -eq $modelSourceHashes[2]) ($warnings -join '; ')
} finally { $env:PATH = $oldAssimpPath; if ($modelDir -and (Test-Path -LiteralPath $modelDir -PathType Container)) { Remove-Item -LiteralPath $modelDir -Recurse -Force } }
