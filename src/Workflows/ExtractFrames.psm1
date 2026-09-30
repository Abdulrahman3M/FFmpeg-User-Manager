# ExtractFrames.psm1 - workflow 9: Extract Frames / Images.
Set-StrictMode -Version 2.0

$script:ImageFormats = @(
    @{ Id = 'png'; Label = 'PNG'; Ext = '.png'; Encoder = 'png'; Desc = 'Lossless; larger files.'; Quality = $false },
    @{ Id = 'jpg'; Label = 'JPEG'; Ext = '.jpg'; Encoder = 'mjpeg'; Desc = 'Small files; lossy.'; Quality = 'jpg' },
    @{ Id = 'webp'; Label = 'WebP'; Ext = '.webp'; Encoder = 'libwebp'; Desc = 'Modern format with good compression.'; Quality = 'webp' },
    @{ Id = 'bmp'; Label = 'BMP'; Ext = '.bmp'; Encoder = 'bmp'; Desc = 'Uncompressed bitmap.'; Quality = $false },
    @{ Id = 'tiff'; Label = 'TIFF'; Ext = '.tif'; Encoder = 'tiff'; Desc = 'High-quality archival format.'; Quality = $false }
)

function Get-ImageFormat { param([string]$Id) foreach ($f in $script:ImageFormats) { if ($f.Id -eq $Id) { return $f } } return $null }

function Get-FramePattern {
    param([string]$Prefix, [int]$Pad, [string]$Ext)
    return ("{0}_%0{1}d{2}" -f $Prefix, $Pad, $Ext)
}

function Get-FrameExample {
    param([string]$Prefix, [int]$Pad, [string]$Ext)
    return ("{0}_{1}{2}" -f $Prefix, ('1'.PadLeft($Pad, '0')), $Ext)
}

function Get-ExtractFramesSteps {
    $range = { param($W) (Get-Answer $W 'mode') -eq 'range' }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'mode'; Type = 'Choice'; Prompt = 'Extraction mode'; Help = 'What frames should be saved?'
        Choices = { param($W) @( (New-Choice 'single' 'Single frame at a timestamp' 'Save one picture.'), (New-Choice 'interval' 'One frame every N seconds' 'Example: every 5 seconds.'), (New-Choice 'fps' 'N frames per second' 'Example: 2 frames for every second of video.'), (New-Choice 'range' 'Frames from a time range' 'Save frames only from part of the video.') ) }
        Default = 'single' }
    $steps += @{ Id = 'time'; Type = 'Timestamp'; Prompt = 'Timestamp'; Help = 'The moment to capture.'; Example = '00:00:05  or  5  or  0:05'; Default = '0'
        When = { param($W) (Get-Answer $W 'mode') -eq 'single' }
        Validate = { param($v, $W) $d = (Get-Media $W 'input').Duration; if ($v -lt 0) { return 'The timestamp cannot be negative.' }; if ($d -and $v -ge $d) { return ('The timestamp must be before the end of the video ({0}).' -f (Format-Duration $d)) }; $null } }
    $steps += @{ Id = 'interval'; Type = 'Decimal'; Prompt = 'Seconds between frames'; Help = 'One frame is saved every this many seconds.'; Example = '5'; Min = 0.04; Max = 86400; Label = 'Interval'; Unit = 'seconds'; Default = 5
        When = { param($W) (Get-Answer $W 'mode') -in @('interval', 'range') } }
    $steps += @{ Id = 'rate'; Type = 'Decimal'; Prompt = 'Frames per second'; Help = 'How many frames to save for each second of video.'; Example = '2'; Min = 0.01; Max = 240; Label = 'Rate'; Unit = 'frames/second'; Default = 1
        When = { param($W) (Get-Answer $W 'mode') -eq 'fps' } }
    $steps += Get-TimeRangeSteps -Prefix 't' -InputId 'input' -Prompt 'Which part of the video?' -RequireRange -When $range
    $steps += @{ Id = 'imgfmt'; Type = 'Choice'; Prompt = 'Image format'; Help = 'Only formats supported by your FFmpeg build are listed.'
        Choices = { param($W) @($script:ImageFormats | Where-Object { Test-FFEncoder $_.Encoder } | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'png' }
    $steps += @{ Id = 'imgq'; Type = 'Choice'; Prompt = 'Image quality'; Help = 'Higher quality creates larger files.'
        When = { param($W) [bool](Get-ImageFormat ([string](Get-Answer $W 'imgfmt' 'png'))).Quality }
        Choices = { param($W) if ((Get-Answer $W 'imgfmt') -eq 'jpg') { @( (New-Choice 2 'High (best)'), (New-Choice 5 'Good (Recommended)'), (New-Choice 10 'Medium'), (New-Choice 18 'Low (smallest)') ) } else { @( (New-Choice 95 'High (best)'), (New-Choice 80 'Good (Recommended)'), (New-Choice 60 'Medium'), (New-Choice 40 'Low (smallest)') ) } }
        Default = { param($W) if ((Get-Answer $W 'imgfmt') -eq 'jpg') { 5 } else { 80 } } }
    $steps += Get-ResolutionStep -Id 'resolution' -Prompt 'Image size'
    $steps += @{ Id = 'maxframes'; Type = 'Integer'; Prompt = 'Maximum number of images'; Help = 'Optional. Stops after this many images.'; Example = '100'; Optional = $true; Min = 1; Max = 1000000; Label = 'Image limit'
        When = { param($W) (Get-Answer $W 'mode') -ne 'single' } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix '' -FolderOnly
    $steps += @{ Id = 'prefix'; Type = 'Text'; Prompt = 'File name prefix'; Help = 'Images are named <prefix>_<number>.<extension>.'; Label = 'Prefix'
        Default = { param($W) (Get-SafeFileStem ([System.IO.Path]::GetFileNameWithoutExtension((Get-Media $W 'input').Path))) + '_frame' }
        Validate = { param($v, $W) $e = Test-ValidFileName ($v + '_0001.png'); if ($e) { return $e }; if ($v -match '%') { return 'The prefix cannot contain a % sign.' }; $null } }
    $steps += @{ Id = 'pad'; Type = 'Integer'; Prompt = 'Number width (zero padding)'; Help = 'Digits used for the frame number. 4 gives 0001, 0002, ...'; Example = '4'; Min = 1; Max = 9; Default = 4; Label = 'Padding'
        }
    $steps += @{ Id = 'overwrite'; Type = 'Choice'; Prompt = 'Images with these names already exist'; Help = 'Existing files are never replaced without your confirmation.'
        When = { param($W) (Test-FrameOutputsExist $W) }
        Choices = { param($W) @( (New-Choice 'rename' 'Choose a different prefix'), (New-Choice 'overwrite' 'Overwrite the existing images') ) }; Default = 'rename'
        OnAnswer = { param($v, $W) if ($v -eq 'rename') { $W.Goto = 'prefix' } } }
    return $steps
}

function Get-FrameOutputInfo {
    param($W)
    $fmt = Get-ImageFormat ([string](Get-Answer $W 'imgfmt' 'png'))
    $dir = Get-Answer $W 'outdir'
    $prefix = [string](Get-Answer $W 'prefix' 'frame'); $pad = [int](Get-Answer $W 'pad' 4)
    return [pscustomobject]@{ Dir = $dir; Fmt = $fmt; Prefix = $prefix; Pad = $pad; Pattern = (Get-FramePattern $prefix $pad $fmt.Ext); Example = (Get-FrameExample $prefix $pad $fmt.Ext) }
}

function Test-FrameOutputsExist {
    param($W)
    $o = Get-FrameOutputInfo $W
    if (-not (Test-Path -LiteralPath $o.Dir -PathType Container)) { return $false }
    $first = Join-Path $o.Dir ($o.Example)
    return (Test-Path -LiteralPath $first)
}

function Build-ExtractFramesJob {
    param($W)
    $info = Get-Media $W 'input'
    $o = Get-FrameOutputInfo $W
    $mode = [string](Get-Answer $W 'mode' 'single')
    $vf = @()
    $cmd = New-FFCommand
    $dur = $info.Duration
    $inOpts = @()
    switch ($mode) {
        'single' { $inOpts = @('-ss', (Format-FFNumber ([double](Get-Answer $W 'time' 0)) 3)); Add-FFOutOpt $cmd @('-frames:v', '1'); $dur = $null }
        'interval' { $vf += ('fps=1/' + (Format-FFNumber ([double](Get-Answer $W 'interval' 5)) 6)) }
        'fps' { $vf += ('fps=' + (Format-FFNumber ([double](Get-Answer $W 'rate' 1)) 6)) }
        'range' { $r = Resolve-TimeRange $W 't' 'input'; $inOpts = Get-RangeInputOptions $r; $vf += ('fps=1/' + (Format-FFNumber ([double](Get-Answer $W 'interval' 5)) 6)); $dur = $r.Duration }
    }
    $rf = Get-ResolutionFilter ([string](Get-Answer $W 'resolution' 'keep')); if ($rf) { $vf += $rf }
    [void](Add-FFInput $cmd $info.Path $inOpts)
    $opts = @('-map', ('0:' + $info.Video[0].Index), '-an', '-sn')
    if ($vf.Count -gt 0) { $opts += @('-vf', (Join-FFFilters $vf)) }
    $maxf = Get-Answer $W 'maxframes'
    if ($maxf -and $mode -ne 'single') { $opts += @('-frames:v', [string][int]$maxf) }
    $q = Get-Answer $W 'imgq'
    switch ($o.Fmt.Id) {
        'png' { $opts += @('-c:v', 'png') }
        'jpg' { $opts += @('-c:v', 'mjpeg', '-q:v', [string][int]$q, '-pix_fmt', 'yuvj420p') }
        'webp' { $opts += @('-c:v', 'libwebp', '-quality', [string][int]$q) }
        'bmp' { $opts += @('-c:v', 'bmp') }
        'tiff' { $opts += @('-c:v', 'tiff') }
    }
    $opts += @('-start_number', '1')
    Add-FFOutOpt $cmd $opts
    $ov = ((Get-Answer $W 'overwrite') -eq 'overwrite')
    Set-FFOutput $cmd (Join-Path $o.Dir $o.Pattern) -Overwrite:$ov
    $notes = @(); if ($ov) { $notes += 'Existing images with the same names will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Mode', $mode), @('Format', $o.Fmt.Label), @('Folder', $o.Dir), @('Naming', ('e.g. ' + $o.Example)))
    $dirLocal = $o.Dir; $prefixLocal = $o.Prefix; $extLocal = $o.Fmt.Ext
    $counter = { @(Get-ChildItem -LiteralPath $dirLocal -Filter ($prefixLocal + '_*' + $extLocal) -File -ErrorAction SilentlyContinue).Count }.GetNewClosure()
    return New-JobObject -Title 'Extracting frames' -Summary $rows -Stages @(@{ Name = 'Extracting images'; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $o.Dir -OutputKind 'Folder' -EnsureDirs @($o.Dir) -Notes $notes -CountOutputs $counter
}

function Start-ExtractFramesWorkflow {
    Start-StandardWorkflow -Title 'Extract Frames / Images' -Description 'Save frames from a video as JPG, PNG, WebP or another supported image format.' -Icon 'Frames' -StepsFactory { Get-ExtractFramesSteps } -Build { param($W) Build-ExtractFramesJob $W }
}

Export-ModuleMember -Function Get-FramePattern, Get-FrameExample, Get-ExtractFramesSteps, Build-ExtractFramesJob, Start-ExtractFramesWorkflow
