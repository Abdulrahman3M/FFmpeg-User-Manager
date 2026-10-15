Set-TestGroup 'Image upscaling: dimensions and factors'
$upscale15 = Get-UpscaleDimensions -Width 640 -Height 480 -Factor 1.5
Assert-Equal '1.5x preserves the requested height' 720 $upscale15.Height
Assert-Equal '1.5x preserves the source aspect ratio' 960 $upscale15.Width
$upscale2 = Get-UpscaleDimensions -Width 641 -Height 479 -Factor 2
Assert-Equal '2x rounds dimensions up to even encoder-safe values' '1282x958' ("{0}x{1}" -f $upscale2.Width, $upscale2.Height)
$upscale4 = Get-UpscaleDimensions -Width 640 -Height 480 -Factor 4
Assert-Equal '4x quadruples both source dimensions' '2560x1920' ("{0}x{1}" -f $upscale4.Width, $upscale4.Height)
$customResolution = Get-UpscaleCustomDimensions -Width 640 -Height 360 -TargetWidth 1600 -TargetHeight 1200
Assert-Equal 'custom resolution fits within its bounds while preserving source aspect ratio' '1600x900' ("{0}x{1}" -f $customResolution.Width, $customResolution.Height)
$rejected = $false
try { $null = Get-UpscaleCustomDimensions -Width 640 -Height 480 -TargetWidth 1280 -TargetHeight 0 } catch { $rejected = $true }
Assert-True 'custom resolution rejects non-positive dimensions' $rejected
$rejected = $false
try { $null = Get-UpscaleCustomDimensions -Width 640 -Height 480 -TargetWidth 640 -TargetHeight 960 } catch { $rejected = $true }
Assert-True 'custom resolution rejects a request that does not enlarge both dimensions' $rejected
$rejected = $false
try { $null = Get-UpscaleCustomDimensions -Width 640 -Height 480 -TargetWidth 40000 -TargetHeight 40000 } catch { $rejected = $true }
Assert-True 'custom resolution rejects dimensions outside the FFmpeg practical limit' $rejected
$rejected = $false
try { $null = Get-UpscaleDimensions -Width 640 -Height 480 -Factor 1 } catch { $rejected = $true }
Assert-True '1x is rejected because it does not upscale' $rejected
$rejected = $false
try { $null = Get-UpscaleDimensions -Width 10000 -Height 9000 -Factor 4 } catch { $rejected = $true }
Assert-True 'dimensions beyond FFmpeg practical image limits are rejected' $rejected

Set-TestGroup 'Image upscaling: guided workflow'
$upscaleSteps = @(Get-UpscaleSteps)
$inputStep = $upscaleSteps | Where-Object { $_.Id -eq 'input' } | Select-Object -First 1
Assert-Contains 'upscaling accepts still images' ([string]$inputStep.Prompt) 'image'
$factorStep = $upscaleSteps | Where-Object { $_.Id -eq 'factor' } | Select-Object -First 1
$factorChoices = @()
if ($factorStep) { $factorChoices = @(& $factorStep.Choices $null) }
Assert-Equal 'upscaling offers three presets plus custom resolution' 4 $factorChoices.Count
$factorLabels = @($factorChoices | ForEach-Object { $_.Label })
Assert-Contains 'upscaling offers 1.5x' ($factorLabels -join '|') '1.5x'
Assert-Contains 'upscaling offers 2x' ($factorLabels -join '|') '2x'
Assert-Contains 'upscaling offers 4x' ($factorLabels -join '|') '4x'
Assert-Contains 'upscaling offers custom resolution' ($factorLabels -join '|') 'Custom Resolution'
$filter = Get-UpscaleFilter -Width 640 -Height 480 -Factor 2
Assert-Contains 'the shared upscale filter always uses Lanczos' $filter 'flags=lanczos'
Assert-Contains 'upscaling explains that it cannot recover lost detail' ([string]$factorStep.Help) 'detail'
