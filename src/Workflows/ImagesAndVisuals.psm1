# ImagesAndVisuals.psm1 - Images & Slideshows: pictures to video, image sequences to video, audio to video, contact sheets.
Set-StrictMode -Version 2.0

$script:SlideSizes = @(
    @{ Id = '1920x1080'; Label = '1920x1080 (Full HD, landscape)'; Desc = 'Sharp widescreen video for TVs, YouTube and monitors.' },
    @{ Id = '1280x720'; Label = '1280x720 (HD, landscape)'; Desc = 'Smaller widescreen video; quick to create and share.' },
    @{ Id = '1080x1920'; Label = '1080x1920 (portrait, phone stories)'; Desc = 'Vertical video for phone stories and shorts.' },
    @{ Id = '1080x1080'; Label = '1080x1080 (square)'; Desc = 'Square video for social media posts.' }
)

function ConvertFrom-SizeText {
    # '1280x720' -> @{ W; H } (even numbers), or $null.
    param([string]$Text)
    $m = [regex]::Match($Text.Trim().ToLowerInvariant().Replace(' ', ''), '^(\d+)x(\d+)$')
    if (-not $m.Success) { return $null }
    $w = [int]$m.Groups[1].Value; $h = [int]$m.Groups[2].Value
    if ($w % 2) { $w++ }; if ($h % 2) { $h++ }
    return @{ W = $w; H = $h }
}

function Get-SizeStep {
    param([string]$Id = 'size', [string]$Prompt = 'Video size', [string]$Default = '1280x720')
    return @{ Id = $Id; Type = 'Choice'; Prompt = $Prompt; Help = 'Pictures that do not match are scaled to fit and centered with black bars; nothing is stretched.'
        Choices = { param($W) @($script:SlideSizes | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Resolution'; Prompt = 'Custom video size'; Help = 'Width x height in pixels.'; Example = '1600x900'; Desc = 'For example 1600x900.' }
        Default = $Default
        Validate = { param($v, $W) if (-not (ConvertFrom-SizeText ([string]$v))) { return 'Enter a size such as 1280x720 (width and height).' }; $null } }
}

function Get-EasyVideoEncoding {
    # Container + encoder questions shared by the workflows in this module (simple level).
    param([string]$Suffix, [string]$InputId, [string[]]$ProtectIds = @())
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $steps = @()
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The file type of the result. MP4 plays almost everywhere.'
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp4' }
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript $cont -Level Simple
    $steps += Get-OutputSteps -Prefix 'out' -InputId $InputId -Suffix $Suffix -ProtectIds $ProtectIds -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext }
    return $steps
}

function Get-AutoAudioTokens {
    # Re-encodes audio with the first suitable encoder for the container.
    param([string]$Container)
    $c = Get-VideoContainer $Container
    $l = @(Get-AudioEncoderChoices -AllowedFamilies @($c.Audio))
    if ($l.Count -eq 0) { throw 'No usable audio encoder is available for this format.' }
    $enc = [string]$l[0].Encoder
    return (Get-AudioEncodeArgs -Encoder $enc -BitrateBps (Get-DefaultAudioBitrate $enc))
}

# ---- 1. Pictures to slideshow -----------------------------------------------------------------

function Get-SlideshowSteps {
    $steps = @()
    $steps += @{ Id = 'images'; Type = 'Files'; Prompt = 'Pictures for the slideshow'; Min = 1
        Help = 'Add the pictures in the order they should appear (JPG, PNG, WebP, BMP and similar). You can reorder them on the next screen.'
        Validate = { param($v, $W) $m = Get-MediaInfo -Path $v; if (-not $m.Ok -or -not $m.Info.HasVideo) { return 'That file is not a picture FFmpeg can read.' }; $null } }
    $steps += @{ Id = 'secs'; Type = 'Choice'; Prompt = 'How long should each picture stay on screen?'; Help = 'Seconds per picture. The total length is this number times the number of pictures.'
        Choices = { param($W) @( (New-Choice 2.0 '2 seconds' 'Fast slideshow.'), (New-Choice 3.0 '3 seconds  (Recommended)' 'Comfortable pace.'), (New-Choice 5.0 '5 seconds' 'Relaxed pace.'), (New-Choice 10.0 '10 seconds' 'Long hold, good for text slides.') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.2; Max = 600; Prompt = 'Seconds per picture'; Help = 'Between 0.2 and 600 seconds.'; Example = '4.5'; ValueLabel = 'Seconds'; Desc = 'For example 4.5.' }
        Default = 3.0 }
    $steps += Get-SizeStep
    $steps += @{ Id = 'fps'; Type = 'Choice'; Prompt = 'Frame rate'; Help = 'Frames per second of the video. A slideshow looks the same at any rate; 30 is the most compatible.'
        Choices = { param($W) @( (New-Choice 25.0 '25 FPS' 'Standard video rate in many countries.'), (New-Choice 30.0 '30 FPS  (Recommended)' 'Smooth and widely supported.'), (New-Choice 60.0 '60 FPS' 'Larger file, no visible benefit for still pictures.') ) }; Default = 30.0 }
    $steps += @{ Id = 'music'; Type = 'YesNo'; Prompt = 'Add background music?'; Help = 'Choose an audio file to play under the slideshow. It is cut at the end of the slideshow.'; Default = $false; YesLabel = 'Yes, add an audio file'; NoLabel = 'No, silent video'; YesDesc = 'You will be asked for the audio file next.'; NoDesc = 'The video will have no sound.' }
    $songStep = Get-InputFileStep -Id 'song' -Prompt 'Background music file' -Require Audio -NoPanel -Help 'Any audio file, for example an MP3.'
    $songStep.When = { param($W) [bool](Get-Answer $W 'music' $false) }
    $steps += $songStep
    $steps += Get-EasyVideoEncoding -Suffix 'slideshow' -InputId 'images'
    return $steps
}

function Build-SlideshowJob {
    param($W)
    $images = @(Get-Answer $W 'images' @())
    if ($images.Count -eq 0) { throw 'Add at least one picture.' }
    $secs = [double](Get-Answer $W 'secs' 3)
    $sz = ConvertFrom-SizeText ([string](Get-Answer $W 'size' '1280x720'))
    $fps = [double](Get-Answer $W 'fps' 30)
    $container = [string](Get-Answer $W 'format' 'mp4')
    $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $sb = New-Object System.Text.StringBuilder
    foreach ($p in $images) { [void]$sb.Append("file '" + ([string]$p).Replace("'", "'\''") + "'`nduration " + (Format-FFNumber $secs 3) + "`n") }
    $list = New-TempTextFile $sb.ToString() '.txt'
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $list @('-f', 'concat', '-safe', '0'))
    $useMusic = [bool](Get-Answer $W 'music' $false)
    $song = $null
    if ($useMusic) { $song = Get-Media $W 'song'; [void](Add-FFInput $cmd $song.Path) }
    $vf = ("scale={0}:{1}:force_original_aspect_ratio=decrease,pad={0}:{1}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p" -f $sz.W, $sz.H)
    Add-FFOutOpt $cmd @('-map', '0:v', '-vf', $vf, '-r', (Format-FFNumber $fps 3))
    $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true
    Add-FFOutOpt $cmd $ve.Tokens
    if ($useMusic) { Add-FFOutOpt $cmd (@('-map', '1:a') + (Get-AutoAudioTokens $container) + @('-shortest')) } else { Add-FFOutOpt $cmd @('-an') }
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $total = $secs * $images.Count
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Pictures', [string]$images.Count), @('Each picture', ((Format-FFNumber $secs 2) + ' s')), @('Total length', (Format-Duration $total)), @('Size', ('{0}x{1} at {2} FPS' -f $sz.W, $sz.H, (Format-FFNumber $fps 2))), @('Music', $(if ($useMusic) { $song.FileName } else { 'None' })), @('Output', $out.Path))
    return New-JobObject -Title 'Creating slideshow' -Summary $rows -Stages @(@{ Name = 'Creating video'; Arguments = (Get-FFTokens $cmd); DurationSec = $total }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -TempFiles @($list) -Notes $notes
}

# ---- 2. Image sequence to video ---------------------------------------------------------------

function Get-SequenceInfo {
    # Pattern such as C:\frames\frame_%04d.png -> @{ Dir; Prefix; Suffix; Digits; Regex }
    param([string]$Pattern)
    $dir = [System.IO.Path]::GetDirectoryName($Pattern); $name = [System.IO.Path]::GetFileName($Pattern)
    $m = [regex]::Match($name, '^(.*)%0?(\d*)d(.*)$')
    if (-not $m.Success) { return $null }
    $digits = 0; if ($m.Groups[2].Value) { $digits = [int]$m.Groups[2].Value }
    $rx = '^' + [regex]::Escape($m.Groups[1].Value) + '(\d+)' + [regex]::Escape($m.Groups[3].Value) + '$'
    return @{ Dir = $dir; Prefix = $m.Groups[1].Value; Suffix = $m.Groups[3].Value; Digits = $digits; Regex = $rx }
}

function Get-SequenceFrameCount {
    param([string]$Pattern, [int]$Start)
    $s = Get-SequenceInfo $Pattern
    if (-not $s -or -not (Test-Path -LiteralPath $s.Dir -PathType Container)) { return 0 }
    $nums = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $s.Dir -File -ErrorAction SilentlyContinue)) { $m = [regex]::Match($f.Name, $s.Regex); if ($m.Success) { $nums[[int64]$m.Groups[1].Value] = $true } }
    $n = 0; $i = [int64]$Start
    while ($nums.ContainsKey($i)) { $n++; $i++ }
    return $n
}

function Get-SequenceSteps {
    $steps = @()
    $steps += @{ Id = 'pattern'; Type = 'Text'; Prompt = 'Image sequence pattern'; Label = 'Pattern'
        Help = 'Path of the numbered pictures. Use %04d for a 4-digit counter (%03d for 3 digits, %d for no padding). Files must be consecutively numbered.'
        Example = 'C:\frames\frame_%04d.png'
        Validate = { param($v, $W)
            $p = Resolve-UserPath $v
            if (-not $p) { return 'That is not a valid path.' }
            if (-not (Get-SequenceInfo $p)) { return 'The pattern needs a counter such as %04d in the file name.' }
            $W.Data['seqPattern'] = $p
            $null } }
    $steps += @{ Id = 'startnum'; Type = 'Integer'; Prompt = 'Number of the first picture'; Label = 'First number'; Min = 0; Max = 999999999; Default = 1; Example = '1  or  0'
        Help = 'The number in the name of the first picture of the sequence (frame_0001.png is 1).'
        Validate = { param($v, $W) $n = Get-SequenceFrameCount $W.Data['seqPattern'] ([int]$v); if ($n -lt 1) { return 'No picture with that number was found for the pattern. Check the first number and the folder.' }; $W.Data['seqCount'] = $n; $null } }
    $steps += @{ Id = 'fps'; Type = 'Choice'; Prompt = 'Frame rate of the video'; Help = 'How many of your pictures are shown per second. 24 is cinematic, 30 is smooth.'
        Choices = { param($W) @( (New-Choice 12.0 '12 FPS' 'Hand-drawn animation look.'), (New-Choice 24.0 '24 FPS  (Recommended)' 'Film look.'), (New-Choice 30.0 '30 FPS' 'Smooth video.'), (New-Choice 60.0 '60 FPS' 'Very smooth motion.') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'FrameRate'; Prompt = 'Custom frame rate'; Help = 'Frames per second between 0.1 and 240.'; Example = '29.97'; Desc = 'For example 29.97.' }
        Default = 24.0 }
    $steps += Get-EasyVideoEncoding -Suffix 'sequence' -InputId 'pattern' -ProtectIds @()
    # The output name defaults come from the pattern's folder.
    for ($i = 0; $i -lt $steps.Count; $i++) {
        if ($steps[$i].Id -eq 'outdir') { $steps[$i].Choices = { param($W) @( (New-Choice ([System.IO.Path]::GetDirectoryName($W.Data['seqPattern'])) 'Same folder as the pictures' 'Save the video next to your numbered pictures.') ) }; $steps[$i].Default = { param($W) [System.IO.Path]::GetDirectoryName($W.Data['seqPattern']) } }
        if ($steps[$i].Id -eq 'outname') { $steps[$i].Default = { param($W) 'sequence_video' + (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext } }
    }
    return $steps
}

function Build-SequenceJob {
    param($W)
    $pattern = [string]$W.Data['seqPattern']
    $start = [int](Get-Answer $W 'startnum' 1)
    $fps = [double](Get-Answer $W 'fps' 24)
    $container = [string](Get-Answer $W 'format' 'mp4')
    $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $count = Get-SequenceFrameCount $pattern $start
    if ($count -lt 1) { throw 'No pictures were found for that pattern.' }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $pattern @('-framerate', (Format-FFNumber $fps 4), '-start_number', [string]$start))
    Add-FFOutOpt $cmd @('-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p')
    $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true
    Add-FFOutOpt $cmd $ve.Tokens
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $dur = $count / $fps
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Pattern', $pattern), @('Pictures', [string]$count), @('Frame rate', ((Format-FFNumber $fps 3) + ' FPS')), @('Length', (Format-Duration $dur)), @('Output', $out.Path))
    return New-JobObject -Title 'Creating video from pictures' -Summary $rows -Stages @(@{ Name = 'Creating video'; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

# ---- 3. Audio to video --------------------------------------------------------------------------

function Get-AudioVisualSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Audio file' -Require Audio -Help 'The sound that the new video will play.'
    $steps += @{ Id = 'style'; Type = 'Choice'; Prompt = 'What should the picture show?'; Help = 'Useful for uploading music or podcasts to sites that only accept video.'
        Choices = { param($W) @(
            (New-Choice 'cover' 'A still picture (album cover)' 'Shows one picture for the whole duration. Smallest file.'),
            (New-Choice 'waves' 'Animated sound waves' 'A moving waveform drawn from the audio.' (Test-FFFilter 'showwaves') 'Requires the showwaves filter (not in this FFmpeg build).'),
            (New-Choice 'spectrum' 'Scrolling spectrum' 'A colorful frequency display.' (Test-FFFilter 'showspectrum') 'Requires the showspectrum filter (not in this FFmpeg build).'),
            (New-Choice 'black' 'Plain black screen' 'No picture at all; smallest possible video.')) }
        Default = 'cover' }
    $coverStep = Get-InputFileStep -Id 'cover' -Prompt 'Picture to show' -Require Video -NoPanel -Example 'C:\Pictures\cover.jpg' -Help 'A JPG or PNG picture.'
    $coverStep.When = { param($W) (Get-Answer $W 'style') -eq 'cover' }
    $steps += $coverStep
    $steps += Get-SizeStep -Id 'size' -Prompt 'Video size'
    $steps += Get-EasyVideoEncoding -Suffix 'visual' -InputId 'input' -ProtectIds @('input')
    return $steps
}

function Build-AudioVisualJob {
    param($W)
    $info = Get-Media $W 'input'
    $style = [string](Get-Answer $W 'style' 'cover')
    $sz = ConvertFrom-SizeText ([string](Get-Answer $W 'size' '1280x720'))
    $container = [string](Get-Answer $W 'format' 'mp4')
    $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $cmd = New-FFCommand
    $dim = "$($sz.W)x$($sz.H)"
    switch ($style) {
        'cover' {
            $pic = Get-Media $W 'cover'
            [void](Add-FFInput $cmd $pic.Path @('-loop', '1', '-framerate', '25'))
            [void](Add-FFInput $cmd $info.Path)
            Add-FFOutOpt $cmd @('-map', '0:v', '-map', ('1:' + $info.Audio[0].Index), '-vf', ("scale={0}:{1}:force_original_aspect_ratio=decrease,pad={0}:{1}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p" -f $sz.W, $sz.H), '-shortest')
        }
        'black' {
            [void](Add-FFInput $cmd "color=c=black:s=${dim}:r=25" @('-f', 'lavfi'))
            [void](Add-FFInput $cmd $info.Path)
            Add-FFOutOpt $cmd @('-map', '0:v', '-map', ('1:' + $info.Audio[0].Index), '-vf', 'format=yuv420p', '-shortest')
        }
        default {
            [void](Add-FFInput $cmd $info.Path)
            if ($style -eq 'waves') { $g = "[0:a:0]showwaves=s=${dim}:mode=cline:colors=0x58d3ff:rate=25,format=yuv420p[v]" }
            else { $g = "[0:a:0]showspectrum=s=${dim}:slide=scroll:legend=0:color=intensity,fps=25,format=yuv420p[v]" }
            Add-FFOutOpt $cmd @('-filter_complex', $g, '-map', '[v]', '-map', '0:a:0')
        }
    }
    $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true
    Add-FFOutOpt $cmd $ve.Tokens
    Add-FFOutOpt $cmd (Get-AutoAudioTokens $container)
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $styleText = @{ cover = 'Still picture'; waves = 'Sound waves'; spectrum = 'Spectrum'; black = 'Black screen' }[$style]
    $rows = @(@('Audio', $info.FileName), @('Picture', $styleText), @('Size', $dim), @('Output', $out.Path))
    return New-JobObject -Title 'Creating video from audio' -Summary $rows -Stages @(@{ Name = 'Creating video'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

# ---- 4. Contact sheet ----------------------------------------------------------------------------

function Get-ContactSheetSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video -Help 'The video to summarize as one picture made of small thumbnails.'
    $steps += @{ Id = 'cols'; Type = 'Choice'; Prompt = 'Thumbnails per row'; Help = 'More columns make a wider picture.'
        Choices = { param($W) @( (New-Choice 3 '3 columns' 'A narrow sheet.'), (New-Choice 4 '4 columns  (Recommended)' 'A balanced sheet.'), (New-Choice 5 '5 columns' 'A wide sheet.'), (New-Choice 6 '6 columns' 'A very wide sheet.') ) }; Default = 4 }
    $steps += @{ Id = 'rows'; Type = 'Choice'; Prompt = 'Number of rows'; Help = 'Columns times rows is the total number of thumbnails, spread evenly over the video.'
        Choices = { param($W) @( (New-Choice 2 '2 rows' 'A short sheet.'), (New-Choice 3 '3 rows' 'A compact sheet.'), (New-Choice 4 '4 rows  (Recommended)' 'A balanced sheet.'), (New-Choice 5 '5 rows' 'A tall sheet.'), (New-Choice 6 '6 rows' 'A very tall sheet.') ) }; Default = 4 }
    $steps += @{ Id = 'tw'; Type = 'Choice'; Prompt = 'Width of each thumbnail'; Help = 'Pixels. The picture is about columns x this width wide.'
        Choices = { param($W) @( (New-Choice 160 '160 px (small)' 'Tiny thumbnails; small picture.'), (New-Choice 240 '240 px' 'Small thumbnails.'), (New-Choice 320 '320 px  (Recommended)' 'Clear thumbnails.'), (New-Choice 480 '480 px (large)' 'Large thumbnails; big picture.') ) }; Default = 320 }
    $steps += @{ Id = 'imgfmt'; Type = 'Choice'; Prompt = 'Picture format'; Help = 'JPG is smaller; PNG is lossless.'
        Choices = { param($W) @( (New-Choice 'jpg' 'JPG  (Recommended)' 'Small file.' (Test-FFEncoder 'mjpeg') 'Requires the mjpeg encoder.'), (New-Choice 'png' 'PNG' 'Lossless.' (Test-FFEncoder 'png') 'Requires the png encoder.') ) }; Default = 'jpg' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'sheet' -Extension { param($W) '.' + [string](Get-Answer $W 'imgfmt' 'jpg') }
    return $steps
}

function Build-ContactSheetJob {
    param($W)
    $info = Get-Media $W 'input'
    if (-not $info.Duration -or $info.Duration -le 0) { throw 'The length of this video is unknown, so thumbnails cannot be spread over it.' }
    $cols = [int](Get-Answer $W 'cols' 4); $rowsN = [int](Get-Answer $W 'rows' 4); $tw = [int](Get-Answer $W 'tw' 320)
    $fmt = [string](Get-Answer $W 'imgfmt' 'jpg')
    $out = Get-OutputFile $W
    $n = $cols * $rowsN
    $interval = $info.Duration / ($n + 0.5)
    $vf = ('fps=1/{0},scale={1}:-2,tile={2}x{3}:padding=4:margin=4:color=black' -f (Format-FFNumber $interval 4), $tw, $cols, $rowsN)
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index), '-vf', $vf, '-frames:v', '1', '-an')
    if ($fmt -eq 'jpg') { Add-FFOutOpt $cmd @('-q:v', '3') }
    Add-FFOutOpt $cmd @('-update', '1')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Thumbnails', ("{0} ({1} x {2})" -f $n, $cols, $rowsN)), @('Output', $out.Path))
    return New-JobObject -Title 'Creating contact sheet' -Summary $rows -Stages @(@{ Name = 'Creating picture'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

function Start-ImagesAndVisualsWorkflow {
    $items = @(
        @{ Label = 'Pictures to Slideshow Video'; Icon = 'Image'; Desc = 'Turn a list of photos into a video with a fixed time per picture and optional music.'; Value = { Start-StandardWorkflow -Title 'Slideshow' -Description 'Create a video from pictures.' -Icon 'Image' -StepsFactory { Get-SlideshowSteps } -Build { param($W) Build-SlideshowJob $W } } },
        @{ Label = 'Numbered Image Sequence to Video'; Icon = 'Frames'; Desc = 'Assemble numbered frames (frame_0001.png ...) into a video: animation or time-lapse.'; Value = { Start-StandardWorkflow -Title 'Image Sequence to Video' -Description 'Turn numbered pictures into a video.' -Icon 'Frames' -StepsFactory { Get-SequenceSteps } -Build { param($W) Build-SequenceJob $W } } },
        @{ Label = 'Audio to Video (Cover, Waves, Spectrum)'; Icon = 'Audio'; Desc = 'Give a song or podcast a picture so it can be uploaded where only video is accepted.'; Value = { Start-StandardWorkflow -Title 'Audio to Video' -Description 'Create a video from an audio file.' -Icon 'Audio' -StepsFactory { Get-AudioVisualSteps } -Build { param($W) Build-AudioVisualJob $W } } },
        @{ Label = 'Contact Sheet (Thumbnail Grid)'; Icon = 'Chart'; Desc = 'Summarize a video as one picture made of evenly spaced thumbnails.'; Value = { Start-StandardWorkflow -Title 'Contact Sheet' -Description 'Create a grid of thumbnails from a video.' -Icon 'Chart' -StepsFactory { Get-ContactSheetSteps } -Build { param($W) Build-ContactSheetJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Image') + '  Images & Slideshows') -Subtitle 'Create videos from pictures or audio, or summarize a video as a picture.' -Items $items
}

Export-ModuleMember -Function Get-EasyVideoEncoding, Get-AutoAudioTokens, Get-SizeStep, ConvertFrom-SizeText, Get-SequenceInfo, Get-SequenceFrameCount, Get-SlideshowSteps, Build-SlideshowJob, Get-SequenceSteps, Build-SequenceJob, Get-AudioVisualSteps, Build-AudioVisualJob, Get-ContactSheetSteps, Build-ContactSheetJob, Start-ImagesAndVisualsWorkflow
