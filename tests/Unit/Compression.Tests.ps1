Set-TestGroup 'Compression planning: target math'
Assert-Equal '20% reduction of 10 MiB targets 8 MiB' 8388608 (Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetReduction -Value 20)
Assert-Equal '50% reduction of 10 MiB targets 5 MiB' 5242880 (Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetReduction -Value 50)
Assert-Equal '90% reduction of 10 MiB targets 1 MiB' 1048576 (Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetReduction -Value 90)
Assert-Equal 'target size is returned as bytes' 3145728 (Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetSize -Value 3145728)
$rejected = $false
try { $null = Get-CompressionTargetBytes -SourceBytes 100 -Mode TargetReduction -Value 0.001 } catch { $rejected = $true }
Assert-True 'a positive reduction that rounds to the source size is rejected' $rejected

foreach ($badPercent in @(-1, 0, 100, 120)) {
    $rejected = $false
    try { $null = Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetReduction -Value $badPercent } catch { $rejected = $true }
    Assert-True "reduction $badPercent percent is rejected" $rejected
}
$rejected = $false
try { $null = Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetSize -Value 10485760 } catch { $rejected = $true }
Assert-True 'target size equal to the source is rejected with an explanation' $rejected
$rejected = $false
try { $null = Get-CompressionTargetBytes -SourceBytes 10485760 -Mode TargetSize -Value 0 } catch { $rejected = $true }
Assert-True 'zero target size is rejected' $rejected

Set-TestGroup 'Compression planning: codec-aware presets'
$light = Get-CompressionPreset -Encoder 'libx264' -Preset 'Light'
$balanced = Get-CompressionPreset -Encoder 'libx264' -Preset 'Balanced'
$strong = Get-CompressionPreset -Encoder 'libx264' -Preset 'Strong'
$maximum = Get-CompressionPreset -Encoder 'libx264' -Preset 'Maximum'
Assert-Equal 'Light uses the H.264 high-quality profile value' 18 $light.Quality
Assert-Equal 'Balanced uses the H.264 balanced profile value' 23 $balanced.Quality
Assert-Equal 'Strong uses the H.264 smaller-file profile value' 28 $strong.Quality
Assert-Equal 'Maximum uses the H.264 supported upper quality value' 51 $maximum.Quality
Assert-Equal 'quality presets use the encoder quality mode' 'Quality' $balanced.Mode
$bitrateFallback = Get-CompressionPreset -Encoder 'h264_mf' -Preset 'Balanced'
Assert-Equal 'encoders without quality controls fall back to bitrate mode' 'Bitrate' $bitrateFallback.Mode
Assert-True 'bitrate fallback is positive' ($bitrateFallback.BitrateBps -gt 0)
$mp3Light = Get-AudioCompressionPreset -Encoder 'libmp3lame' -Preset 'Light'
$mp3Maximum = Get-AudioCompressionPreset -Encoder 'libmp3lame' -Preset 'Maximum'
$vorbisLight = Get-AudioCompressionPreset -Encoder 'libvorbis' -Preset 'Light'
$vorbisMaximum = Get-AudioCompressionPreset -Encoder 'libvorbis' -Preset 'Maximum'
$aacBalanced = Get-AudioCompressionPreset -Encoder 'aac' -Preset 'Balanced'
$flacBalanced = Get-AudioCompressionPreset -Encoder 'flac' -Preset 'Balanced'
Assert-Equal 'MP3 Light favors quality with V0' 0 $mp3Light.Quality
Assert-Equal 'MP3 Maximum favors smaller size with V8' 8 $mp3Maximum.Quality
Assert-Equal 'Vorbis Light favors quality with its higher-is-better value' 8 $vorbisLight.Quality
Assert-Equal 'Vorbis Maximum chooses a lower quality value to reduce size' 2 $vorbisMaximum.Quality
Assert-Equal 'AAC Balanced bitrate is codec-aware' 128000 $aacBalanced.BitrateBps
Assert-True 'FLAC stays explicitly lossless' $flacBalanced.Lossless
Assert-Equal 'central target tolerance is five percent' 0.05 (Get-CompressionTargetTolerance)

Set-TestGroup 'Compression planning: image quality and size targets'
Assert-Equal '512 KB parses as 512 KiB' 524288 (ConvertFrom-CompressionSizeText '512 KB')
Assert-Equal '1.5 GiB parses using the shared binary size units' 1610612736 (ConvertFrom-CompressionSizeText '1.5 GiB')
$sizeRejected = $false
try { $null = ConvertFrom-CompressionSizeText 'not a size' } catch { $sizeRejected = $true }
Assert-True 'malformed target size is rejected' $sizeRejected
$jpeg = Get-ImageCompressionProfile -Format 'jpeg' -Preset 'Balanced'
$png = Get-ImageCompressionProfile -Format 'png' -Preset 'Maximum'
$webp = Get-ImageCompressionProfile -Format 'webp' -Preset 'Strong'
Assert-Equal 'JPEG quality is based on its own qscale range' 4 $jpeg.Quality
Assert-Equal 'PNG remains lossless at the strongest compression preset' $true $png.Lossless
Assert-Equal 'PNG maximum uses FFmpeg mixed prediction while staying lossless' 5 $png.Prediction
Assert-Equal 'WebP uses its own higher-is-better quality scale' 70 $webp.Quality
Assert-Equal 'JPEG target search has a bounded candidate count' 8 @(Get-ImageCompressionCandidates -Format 'jpeg').Count
Assert-Equal 'lossless PNG has no lossy quality-search candidates' 0 @(Get-ImageCompressionCandidates -Format 'png').Count
Assert-Equal 'WebP target search has a bounded candidate count' 8 @(Get-ImageCompressionCandidates -Format 'webp').Count
Assert-True 'yuva420p is recognized as an alpha pixel format' (Test-CompressionPixelHasAlpha ([pscustomobject]@{ HasVideo = $true; Video = @([pscustomobject]@{ PixFmt = 'yuva420p' }) }))
Assert-True 'yuv420p is not mistaken for an alpha pixel format' (-not (Test-CompressionPixelHasAlpha ([pscustomobject]@{ HasVideo = $true; Video = @([pscustomobject]@{ PixFmt = 'yuv420p' }) })))
$candidate = Get-BestImageCandidateIndex -CandidateSizes @(9500, 7000, 5800, 3000) -TargetBytes 6000 -Tolerance 0.05
Assert-Equal 'image search keeps the highest-quality candidate within target tolerance' 2 $candidate
$fallbackCandidate = Get-BestImageCandidateIndex -CandidateSizes @(10000, 9000, 8000) -TargetBytes 1000 -Tolerance 0.05
Assert-Equal 'image search picks the smallest result when none meets the target' 2 $fallbackCandidate
$unreachableAssessment = Get-CompressionTargetAssessment -SourceBytes 10000 -TargetBytes 1000
Assert-Equal '90% target reduction is reported as high quality risk' 'High' $unreachableAssessment.QualityRisk
Assert-True 'aggressive target assessment includes a warning' $unreachableAssessment.Warn
Assert-True 'image result helper detects a missed target tolerance' (-not (Test-CompressionTargetMet -OutputBytes 8000 -TargetBytes 1000 -Tolerance 0.05))
Assert-True 'image result helper accepts a result within target tolerance' (Test-CompressionTargetMet -OutputBytes 1040 -TargetBytes 1000 -Tolerance 0.05)

Set-TestGroup 'Compression workflow: Simple and Advanced entry'
$compressSteps = @(Get-CompressSteps)
$compressStepIds = @($compressSteps | ForEach-Object { $_.Id })
Assert-Equal 'compression wizard uses unique IDs across conditional target questions' $compressStepIds.Count (@($compressStepIds | Select-Object -Unique).Count)
$inputStep = $compressSteps | Where-Object { $_.Id -eq 'input' } | Select-Object -First 1
Assert-Contains 'compression input identifies images as supported' ([string]$inputStep.Prompt) 'image'
$modeStep = $compressSteps | Where-Object { $_.Id -eq 'mode' } | Select-Object -First 1
$modeChoices = @()
if ($modeStep) { $modeChoices = @(& $modeStep.Choices $null) }
Assert-Equal 'compression mode has exactly two choices' 2 $modeChoices.Count
$firstModeLabel = ''; $secondModeLabel = ''
if ($modeChoices.Count -gt 0) { $firstModeLabel = $modeChoices[0].Label }
if ($modeChoices.Count -gt 1) { $secondModeLabel = $modeChoices[1].Label }
Assert-Equal 'Simple mode is first' 'Simple' $firstModeLabel
Assert-Equal 'Advanced mode is second' 'Advanced' $secondModeLabel
$strategyStep = $compressSteps | Where-Object { $_.Id -eq 'strategy' } | Select-Object -First 1
$strategyChoices = @()
if ($strategyStep) { $strategyChoices = @(& $strategyStep.Choices $null) }
Assert-Equal 'Simple compression exposes six approved strategies' 6 $strategyChoices.Count
$strategyFirst = ''; $strategyFifth = ''; $strategySixth = ''
if ($strategyChoices.Count -gt 0) { $strategyFirst = $strategyChoices[0].Label }
if ($strategyChoices.Count -gt 4) { $strategyFifth = $strategyChoices[4].Label }
if ($strategyChoices.Count -gt 5) { $strategySixth = $strategyChoices[5].Label }
Assert-Equal 'Light is the first Simple strategy' 'Light Compression' $strategyFirst
Assert-Equal 'Target Size is the fifth Simple strategy' 'Target Size' $strategyFifth
Assert-Equal 'Target Reduction is the sixth Simple strategy' 'Target Reduction' $strategySixth
$unknownDurationState = @{ Answers = @{ mode = 'Simple' }; Data = @{ 'probe.input' = [pscustomobject]@{ IsImageOnly = $false; HasVideo = $true; HasAudio = $false; Duration = $null } } }
$unknownDurationChoices = @(& $strategyStep.Choices $unknownDurationState)
$unknownDurationSize = $unknownDurationChoices | Where-Object { $_.Value -eq 'TargetSize' } | Select-Object -First 1
$unknownDurationReduction = $unknownDurationChoices | Where-Object { $_.Value -eq 'TargetReduction' } | Select-Object -First 1
Assert-Equal 'Simple target size is disabled when media duration is unknown' $false $unknownDurationSize.Enabled
Assert-Equal 'Simple target reduction is disabled when media duration is unknown' $false $unknownDurationReduction.Enabled

$startCompression = Get-Command Start-CompressWorkflow -ErrorAction SilentlyContinue
Assert-True 'compression workflow is wired to the shared builder' ($null -ne $startCompression)

Set-TestGroup 'Compression planning: bitrate and measured results'
$plan = Get-CompressionBitratePlan -TargetBytes 10485760 -DurationSec 60 -AudioBps 128000
Assert-Equal 'target bitrate plan subtracts the audio budget' 1228158 $plan.VideoBitrateBps
Assert-Equal 'target bitrate plan records the requested audio budget' 128000 $plan.AudioBitrateBps
$rejected = $false
try { $null = Get-CompressionBitratePlan -TargetBytes 1048576 -DurationSec 60 -AudioBps 128000 } catch { $rejected = $true }
Assert-True 'audio budget that leaves no practical video bitrate is rejected' $rejected
$metrics = Get-CompressionResultMetrics -SourceBytes 1000 -OutputBytes 800 -TargetBytes 900
Assert-Equal 'result metrics measure bytes saved' 200 $metrics.BytesSaved
Assert-Equal 'result metrics measure actual reduction percent' 20 $metrics.ReductionPercent
Assert-Equal 'result metrics measure target difference' -100 $metrics.TargetDifferenceBytes
$grown = Get-CompressionResultMetrics -SourceBytes 1000 -OutputBytes 1200
Assert-Equal 'larger output reports negative saved bytes, not a false saving' -200 $grown.BytesSaved
Assert-Equal 'larger output reports negative reduction percent' -20 $grown.ReductionPercent
