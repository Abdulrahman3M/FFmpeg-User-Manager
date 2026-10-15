# WorkflowCommon.psm1 - shared building blocks for every workflow: input/output steps, encoder steps,
# time-range steps, and the central job runner (progress, result, error and cancel handling).
Set-StrictMode -Version 2.0

# ---- small helpers -------------------------------------------------------------

function New-Choice {
    param($Value, [string]$Label, [string]$Desc = '', [bool]$Enabled = $true, [string]$Reason = '')
    return @{ Value = $Value; Label = $Label; Desc = $Desc; Enabled = $Enabled; Reason = $Reason }
}

function Get-Answer {
    param($W, [string]$Id, $Default = $null)
    if ($W.Answers.ContainsKey($Id)) { return $W.Answers[$Id] }
    return $Default
}

function Get-Media {
    # Probed media info stored by the input step (or $null).
    param($W, [string]$Id = 'input')
    $k = 'probe.' + $Id
    if ($W.Data.ContainsKey($k)) { return $W.Data[$k] }
    return $null
}

function Get-PresetList {
    param([string]$Name, $Fallback)
    try { $v = (Get-AppConfig).presets.$Name; if ($v) { return @($v) } } catch { }
    return $Fallback
}

function Get-NumberChoices {
    param([double[]]$Values, [string]$Unit = '', [string]$Format = '{0:0.##}', [double]$Recommended = [double]::NaN, [hashtable]$Descs = @{})
    $out = @()
    foreach ($v in $Values) {
        $label = ($Format -f $v) + $(if ($Unit) { ' ' + $Unit } else { '' })
        if (-not [double]::IsNaN($Recommended) -and $v -eq $Recommended) { $label += '  (Recommended)' }
        $d = ''; if ($Descs.ContainsKey([string]$v)) { $d = $Descs[[string]$v] }
        $out += , (New-Choice $v $label $d)
    }
    return $out
}

function Get-ContainerIdFromPath {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant().TrimStart('.')
    switch ($ext) { 'mp4' { return 'mp4' } 'm4v' { return 'mp4' } 'mkv' { return 'mkv' } 'webm' { return 'webm' } 'mov' { return 'mov' } 'avi' { return 'avi' } 'ts' { return 'ts' } 'flv' { return 'flv' } default { return '' } }
}

# ---- descriptions for numeric / preset choices ------------------------------------------------------

function Get-SpeedDescription {
    param([double]$Speed)
    if ($Speed -lt 0.5) { return 'Very slow motion; the clip becomes several times longer.' }
    if ($Speed -lt 1.0) { return 'Slow motion; the clip becomes longer.' }
    if ($Speed -eq 1.0) { return 'No change in speed.' }
    if ($Speed -le 1.5) { return 'A little faster; the clip becomes shorter.' }
    return 'Fast forward; the clip becomes much shorter.'
}

function Get-FpsDescription {
    param([double]$Fps)
    if ($Fps -le 12) { return 'Choppy, small file; fine for simple animations.' }
    if ($Fps -lt 24) { return 'Light on file size; slightly less smooth.' }
    if ($Fps -lt 25) { return 'Cinema film rate.' }
    if ($Fps -eq 25) { return 'Standard PAL television rate.' }
    if ($Fps -lt 30) { return 'Standard rate for NTSC-style video (29.97).' }
    if ($Fps -eq 30) { return 'Smooth, widely supported rate.' }
    if ($Fps -lt 50) { return 'Smoother motion; larger file.' }
    if ($Fps -eq 50) { return 'Smooth PAL high frame rate.' }
    return 'Very smooth motion for games and sports; larger file.'
}

function Get-SampleRateDescription {
    param([int]$Hz)
    switch ($Hz) {
        8000 { return 'Telephone quality; speech only.' }
        16000 { return 'Wideband speech; voice recordings.' }
        22050 { return 'Low quality music; small files.' }
        32000 { return 'Broadcast and some digital radio.' }
        44100 { return 'CD quality; standard for music.' }
        48000 { return 'Standard for video and film.' }
        96000 { return 'High-resolution audio for editing; large files.' }
        default { return 'Samples per second of the sound.' }
    }
}

function Get-EncoderPresetDescription {
    param([string]$Preset)
    switch -Regex ($Preset) {
        '^(ultrafast|p1)$' { return 'Fastest encoding; largest file for the quality.' }
        '^(superfast|p2)$' { return 'Very fast encoding; large file.' }
        '^(veryfast|p3)$' { return 'Fast encoding; somewhat large file.' }
        '^(faster|fast|p4)$' { return 'Quick encoding with a reasonable file size.' }
        '^(medium|p5)$' { return 'Balanced speed and file size. The usual choice.' }
        '^(slow|p6)$' { return 'Slower encoding; smaller file for the same quality.' }
        '^(slower|veryslow|placebo|p7)$' { return 'Very slow encoding; smallest file for the quality.' }
        '^[0-9]+$' { return 'Lower numbers are slower and produce smaller files.' }
        default { return 'Trades encoding time for file size: slower presets give smaller files.' }
    }
}

# ---- input steps ---------------------------------------------------------------

function Get-InputFileStep {
    <# A file question that validates existence and probes the file with ffprobe. Stores the probe in
       $W.Data['probe.<Id>'] and (for the primary input) shows the Source panel on later screens. #>
    param(
        [string]$Id = 'input', [string]$Prompt = 'Input file', [string]$Help = 'Type or paste the path. Quoted paths and spaces are fine.',
        [string]$Example = 'C:\Videos\example.mp4',
        [ValidateSet('Any', 'Video', 'Audio', 'Media')][string]$Require = 'Media',
        [switch]$NoPanel, [string]$PanelTitle = 'Source', [scriptblock]$Extra
    )
    $req = $Require; $noPanel = [bool]$NoPanel; $pid_ = $Id; $ptitle = $PanelTitle; $extra = $Extra
    $validate = {
        param($value, $W)
        $m = Get-MediaInfo -Path $value
        if (-not $m.Ok) { return $m.Error }
        $info = $m.Info
        if ($req -eq 'Video' -and -not $info.HasVideo) { return 'This file has no video stream.' }
        if ($req -eq 'Audio' -and -not $info.HasAudio) { return 'This file has no audio stream.' }
        if ($req -eq 'Media' -and -not ($info.HasVideo -or $info.HasAudio)) { return 'This file has no audio or video stream.' }
        if ($extra) { $msg = & $extra $info $W; if ($msg) { return $msg } }
        $W.Data['probe.' + $pid_] = $info
        if (-not $noPanel) { Set-WizardPanel $W ('source.' + $pid_) $ptitle (Get-MediaSummaryRows $info) 9 }
        return $null
    }.GetNewClosure()
    return @{ Id = $Id; Type = 'File'; Prompt = $Prompt; Help = $Help; Example = $Example; Validate = $validate }
}

# ---- output steps --------------------------------------------------------------

function Get-OutputFile {
    # Resolves the final output path from the answers of the standard output steps.
    param($W, [string]$Prefix = 'out')
    $dir = Get-Answer $W "${Prefix}dir"
    $name = [string](Get-Answer $W "${Prefix}name")
    $ext = ''
    if ($W.Data.ContainsKey("${Prefix}ext")) { $ext = [string](& $W.Data["${Prefix}ext"] $W) }
    if ($ext -and -not $name.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
        # Replace a different typed extension of a known kind, otherwise append.
        $cur = [System.IO.Path]::GetExtension($name)
        if ($cur -and $cur.Length -le 5 -and $cur -match '^\.[A-Za-z0-9]+$' -and ($W.Data.ContainsKey("${Prefix}replaceExt") -and $W.Data["${Prefix}replaceExt"])) { $name = [System.IO.Path]::GetFileNameWithoutExtension($name) + $ext } else { $name += $ext }
    }
    $path = Join-Path $dir $name
    $ov = ((Get-Answer $W "${Prefix}overwrite") -eq 'overwrite')
    return [pscustomobject]@{ Dir = $dir; Name = $name; Path = $path; Overwrite = $ov; Exists = (Test-Path -LiteralPath $path) }
}

function Get-OutputSteps {
    <#
      Standard output questions: folder, (create folder), file name, overwrite handling.
      -Extension: scriptblock ($W) returning the extension incl. dot ('' for none). -InputIds: sources to protect.
      -Suffix: appended to the source name for the suggested file name.
    #>
    param([string]$Prefix = 'out', [string]$InputId = 'input', [string]$Suffix = 'output', [scriptblock]$Extension, [string]$NamePrompt = 'Output file name', [string[]]$ProtectIds = @('input'), [switch]$FolderOnly)
    $pfx = $Prefix; $iid = $InputId; $sfx = $Suffix; $extSb = $Extension; $protect = $ProtectIds; $prompt = $NamePrompt; $folderOnly = [bool]$FolderOnly
    $srcDir = {
        param($W)
        $m = Get-Media $W $iid
        if ($m) { return [System.IO.Path]::GetDirectoryName($m.Path) }
        $p = Get-Answer $W $iid
        if ($p -is [array]) { $p = $p[0] }
        if ($p) { return [System.IO.Path]::GetDirectoryName([string]$p) }
        return (Get-Location).ProviderPath
    }.GetNewClosure()
    $steps = @()
    $steps += @{
        Id = "${pfx}dir"; Type = 'Choice'; Prompt = 'Output folder'; Help = 'Where should the result be saved?'
        Choices = { param($W) @( (New-Choice (& $srcDir $W) 'Same folder as the source file' (& $srcDir $W)) ) }.GetNewClosure()
        AllowCustom = @{ Label = 'Choose another folder...'; Type = 'Directory'; Prompt = 'Output folder path'; Help = 'Type or paste a folder path. It will be created (after confirmation) if it does not exist.'; Example = 'C:\Videos\Converted'; Desc = 'Type or paste a folder path.' }
        Default = $srcDir
        Validate = { param($v, $W) if ((Test-Path -LiteralPath $v -PathType Container) -and -not (Test-DirectoryWritable $v)) { return 'You do not have permission to write to that folder. Choose another folder.' }; if (Test-Path -LiteralPath $v -PathType Leaf) { return 'That path is a file, not a folder.' }; $null }
        OnAnswer = { param($v, $W) $W.Data["${pfx}dirWasNew"] = -not (Test-Path -LiteralPath $v -PathType Container) }.GetNewClosure()
    }
    $steps += @{
        Id = "${pfx}mkdir"; Type = 'YesNo'; Prompt = 'The output folder does not exist. Create it?'; Help = 'The folder is created only when the job starts.'
        Default = $true; YesLabel = 'Create the folder'; NoLabel = 'Choose a different folder'; YesDesc = 'The folder is made when the job starts.'; NoDesc = 'Go back and pick a folder that already exists.'
        When = { param($W) -not (Test-Path -LiteralPath (Get-Answer $W "${pfx}dir") -PathType Container) }.GetNewClosure()
        OnAnswer = { param($v, $W) if (-not $v) { $W.Goto = "${pfx}dir" } }.GetNewClosure()
    }
    if (-not $folderOnly) {
        $steps += @{
            Id = "${pfx}name"; Type = 'Text'; Prompt = $prompt; Label = 'File name'; Example = 'my movie.mp4'
            Help = 'The extension is added automatically if you leave it out.'
            Default = {
                param($W)
                $m = Get-Media $W $iid
                $src = $(if ($m) { $m.Path } else { [string](@(Get-Answer $W $iid))[0] })
                $e = ''; if ($extSb) { $e = [string](& $extSb $W) }
                return (New-OutputName $src $sfx $e)
            }.GetNewClosure()
            Validate = {
                param($v, $W)
                $msg = Test-ValidFileName $v
                if ($msg) { return $msg }
                $W.Data["${pfx}ext"] = $extSb
                # Evaluate against the candidate name (Answers not yet updated for this step).
                $dir = Get-Answer $W "${pfx}dir"
                $cand = Join-Path $dir $v
                if ($extSb) { $e = [string](& $extSb $W); if ($e -and -not $v.EndsWith($e, [StringComparison]::OrdinalIgnoreCase)) { $cand = Join-Path $dir ($v + $e) } }
                foreach ($id in $protect) {
                    foreach ($src in @(Get-Answer $W $id)) {
                        if ($src -and ([string]$src).Length -gt 0 -and [string]::Equals([System.IO.Path]::GetFullPath([string]$src), [System.IO.Path]::GetFullPath($cand), [StringComparison]::OrdinalIgnoreCase)) { return 'The output file would overwrite the source file. Choose a different name or folder.' }
                    }
                }
                if (Test-PathTooLong $cand) { return 'The full output path is too long. Choose a shorter name or folder.' }
                return $null
            }.GetNewClosure()
            OnAnswer = { param($v, $W) $W.Data["${pfx}ext"] = $extSb }.GetNewClosure()
        }
        $steps += @{
            Id = "${pfx}overwrite"; Type = 'Choice'; Prompt = 'That output file already exists'; Help = 'Existing files are never replaced without your confirmation.'
            Choices = { param($W) @( (New-Choice 'rename' 'Choose a different name' 'Go back and type another file name so nothing is replaced.'), (New-Choice 'overwrite' 'Overwrite the existing file' 'The existing file will be replaced.') ) }
            Default = 'rename'
            When = { param($W) (Get-OutputFile $W -Prefix $pfx).Exists }.GetNewClosure()
            OnAnswer = { param($v, $W) if ($v -eq 'rename') { $W.Goto = "${pfx}name" } }.GetNewClosure()
        }
    }
    return $steps
}

# ---- format / codec steps --------------------------------------------------------

function Get-ContainerStep {
    param([string]$Id = 'format', [string]$InputId = 'input', [string]$Prompt = 'Output format')
    $iid = $InputId
    return @{
        Id = $Id; Type = 'Choice'; Prompt = $Prompt; Help = 'The file type of the result. Only formats supported by your FFmpeg build are listed.'
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $m = Get-Media $W $iid; $c = ''; if ($m) { $c = Get-ContainerIdFromPath $m.Path }; if ($c -and (Test-FFMuxer (Get-VideoContainer $c).Muxer)) { return $c }; return 'mp4' }.GetNewClosure()
    }
}

function Get-VideoEncodeSteps {
    <#
      Codec / quality / bitrate / preset questions. -Level Full asks everything; Simple asks codec + quality level.
      -ContainerScript returns the container id ($W). -OfferCopy adds 'Copy original codec'.
    #>
    param([string]$Prefix = 'v', [scriptblock]$ContainerScript, [switch]$OfferCopy, [ValidateSet('Full', 'Simple')][string]$Level = 'Full', [switch]$Gate, [scriptblock]$GateWhen)
    $p = $Prefix; $cs = $ContainerScript; $copy = [bool]$OfferCopy; $lvl = $Level
    $contOf = { param($W) $c = 'mkv'; if ($cs) { $c = [string](& $cs $W) }; return (Get-VideoContainer $c) }.GetNewClosure()
    $whenBase = { param($W) $true }
    if ($GateWhen) { $whenBase = $GateWhen }
    $wb = $whenBase
    $steps = @()
    $steps += @{
        Id = "${p}codec"; Type = 'Choice'; Prompt = 'Video codec'; Help = 'Automatic picks a good encoder for the chosen format. Only encoders in your FFmpeg build are listed.'
        When = $wb
        Choices = {
            param($W)
            $cont = & $contOf $W
            $allowed = @(); if ($cont) { $allowed = @($cont.Video) }
            $list = @( (New-Choice 'auto' 'Automatic / Recommended' 'Best supported encoder for this format.') )
            if ($copy) { $list += , (New-Choice 'copy' 'Copy original codec' 'No re-encoding: fastest, no quality loss (only when compatible).') }
            foreach ($c in (Get-VideoEncoderChoices -AllowedFamilies $allowed -IncludeHardware)) { $list += , (New-Choice $c.Encoder ($c.Label + $(if (-not $c.Hardware) { '  [' + $c.Encoder + ']' } else { '' })) $c.Desc) }
            return $list
        }.GetNewClosure()
        Default = 'auto'
    }
    $isEnc = { param($W) (& $wb $W) -and ((Get-Answer $W "${p}codec") -notin @('auto', 'copy', $null)) }.GetNewClosure()
    $isReenc = { param($W) (& $wb $W) -and ((Get-Answer $W "${p}codec") -ne 'copy') }.GetNewClosure()
    if ($lvl -eq 'Simple') {
        $steps += @{
            Id = "${p}level"; Type = 'Choice'; Prompt = 'Video quality'; Help = 'Higher quality creates larger files.'
            When = $isReenc
            Choices = { param($W) @( (New-Choice 'Recommended' 'Recommended' 'Balanced quality and size.'), (New-Choice 'high' 'High quality' 'Larger file, best quality.'), (New-Choice 'small' 'Smaller file' 'Smaller file, some quality loss.') ) }
            Default = 'Recommended'
        }
        return $steps
    }
    $steps += @{
        Id = "${p}qmode"; Type = 'Choice'; Prompt = 'Quality mode'; Help = 'Quality-based keeps consistent quality; bitrate-based targets a file size.'
        When = $isEnc
        Choices = { param($W) $enc = [string](Get-Answer $W "${p}codec"); $q = Test-EncoderSupportsQuality $enc; @( (New-Choice 'Recommended' 'Recommended' 'Balanced defaults for this encoder.'), (New-Choice 'Quality' 'Quality level' 'Choose a quality level (best for most uses).' $q 'This encoder does not support quality-based mode.'), (New-Choice 'Bitrate' 'Target bitrate' 'Set an average bitrate in kbps/Mbps.') ) }.GetNewClosure()
        Default = 'Recommended'
    }
    $steps += @{
        Id = "${p}quality"; Type = 'Choice'; Prompt = 'Quality level'; Help = 'Lower numbers mean higher quality and larger files (except where noted).'
        When = { param($W) (& $isEnc $W) -and ((Get-Answer $W "${p}qmode") -eq 'Quality') }.GetNewClosure()
        Choices = { param($W) @(Get-QualityChoices ([string](Get-Answer $W "${p}codec"))) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom value...'; Type = 'Integer'; Prompt = 'Custom quality value'; Help = 'Enter a whole number in the encoder range.'; Example = '23'; ValueLabel = 'Quality' }
        Validate = { param($v, $W) $pr = Get-EncoderProfile ([string](Get-Answer $W "${p}codec")); if ($pr.Quality -ne 'none' -and ($v -lt $pr.Min -or $v -gt $pr.Max)) { return "Quality must be between $($pr.Min) and $($pr.Max) for this encoder." }; return $null }.GetNewClosure()
        Default = { param($W) (Get-EncoderProfile ([string](Get-Answer $W "${p}codec"))).Balanced }.GetNewClosure()
    }
    $steps += @{
        Id = "${p}bitrate"; Type = 'Choice'; Prompt = 'Target video bitrate'; Help = 'Higher bitrate gives better quality and a larger file.'
        When = { param($W) (& $isEnc $W) -and ((Get-Answer $W "${p}qmode") -eq 'Bitrate') }.GetNewClosure()
        Choices = { param($W) @( (New-Choice 1000000 '1 Mbps' 'Small file, low quality.'), (New-Choice 2500000 '2.5 Mbps' '480p-720p.'), (New-Choice 5000000 '5 Mbps' '1080p.'), (New-Choice 8000000 '8 Mbps' 'High quality 1080p.'), (New-Choice 15000000 '15 Mbps' '4K-ish quality.') ) }
        AllowCustom = @{ Label = 'Custom bitrate...'; Type = 'Bitrate'; Prompt = 'Custom video bitrate'; Help = 'Use k or M suffix.'; Example = '3500k'; Desc = 'For example 3500k or 6M.' }
        Default = 5000000
    }
    $steps += @{
        Id = "${p}preset"; Type = 'Choice'; Prompt = 'Encoding speed / preset'; Help = 'Slower presets create smaller files at the same quality but take longer.'
        When = { param($W) (& $isEnc $W) -and ((Get-EncoderProfile ([string](Get-Answer $W "${p}codec"))).ContainsKey('Presets')) }.GetNewClosure()
        Choices = { param($W) $pr = Get-EncoderProfile ([string](Get-Answer $W "${p}codec")); @($pr.Presets | ForEach-Object { New-Choice $_ ($_ + $(if ($_ -eq $pr.DefaultPreset) { '  (Recommended)' } else { '' })) (Get-EncoderPresetDescription $_) }) }.GetNewClosure()
        Default = { param($W) (Get-EncoderProfile ([string](Get-Answer $W "${p}codec"))).DefaultPreset }.GetNewClosure()
    }
    return $steps
}

function Resolve-VideoEncode {
    # Returns @{ Copy; Tokens; Encoder } from the answers of Get-VideoEncodeSteps.
    param($W, [string]$Prefix = 'v', [string]$Container, [bool]$Faststart = $false, [string]$PixFmt = '', $Gop = $null)
    $p = $Prefix
    $codec = [string](Get-Answer $W "${p}codec" 'auto')
    if ($codec -eq 'copy') { return @{ Copy = $true; Tokens = @('-c:v', 'copy'); Encoder = 'copy' } }
    $cont = Get-VideoContainer $Container
    if ($codec -eq 'auto') {
        $allowed = @(); if ($cont) { $allowed = @($cont.Video) }
        $choices = @(Get-VideoEncoderChoices -AllowedFamilies $allowed)
        if ($choices.Count -eq 0) { throw "No usable video encoder is available in your FFmpeg build for the $Container format." }
        $codec = [string]$choices[0].Encoder
    }
    $level = [string](Get-Answer $W "${p}level" '')
    $mode = [string](Get-Answer $W "${p}qmode" 'Recommended')
    $quality = Get-Answer $W "${p}quality"
    $prof = Get-EncoderProfile $codec
    if ($level -eq 'high' -and $prof.Quality -ne 'none') { $mode = 'Quality'; $quality = $prof.High }
    elseif ($level -eq 'small' -and $prof.Quality -ne 'none') { $mode = 'Quality'; $quality = $prof.Small }
    $tokens = Get-VideoEncodeArgs -Encoder $codec -Mode $mode -Quality $quality -Preset ([string](Get-Answer $W "${p}preset" '')) -BitrateBps (Get-Answer $W "${p}bitrate") -Container $Container -Faststart $Faststart -PixFmt $PixFmt -Gop $Gop
    return @{ Copy = $false; Tokens = $tokens; Encoder = $codec }
}

function Get-AudioEncodeSteps {
    param([string]$Prefix = 'a', [scriptblock]$ContainerScript, [switch]$OfferCopy, [switch]$OfferRemove, [scriptblock]$When, [switch]$Full, [scriptblock]$FormatAudioFamilies, [switch]$OfferVbr)
    $p = $Prefix; $cs = $ContainerScript; $copy = [bool]$OfferCopy; $rem = [bool]$OfferRemove; $full = [bool]$Full; $fam = $FormatAudioFamilies; $vbr = [bool]$OfferVbr
    $wb = { param($W) $true }; if ($When) { $wb = $When }
    $allowedOf = {
        param($W)
        if ($fam) { return @(& $fam $W) }
        if ($cs) { $c = Get-VideoContainer ([string](& $cs $W)); if ($c) { return @($c.Audio) } }
        return @()
    }.GetNewClosure()
    $steps = @()
    $steps += @{
        Id = "${p}codec"; Type = 'Choice'; Prompt = 'Audio'; Help = 'Choose what happens to the audio track.'
        When = $wb
        Choices = {
            param($W)
            $list = @( (New-Choice 'auto' 'Convert automatically / Recommended' 'Re-encode audio to a compatible codec.') )
            if ($copy) { $list = @( (New-Choice 'copy' 'Keep original audio (copy)' 'No re-encoding: fastest, no quality loss.') ) + $list }
            foreach ($c in (Get-AudioEncoderChoices -AllowedFamilies (& $allowedOf $W))) { $list += , (New-Choice $c.Encoder ($c.Label + '  [' + $c.Encoder + ']') $c.Desc) }
            if ($rem) { $list += , (New-Choice 'none' 'Remove audio' 'The result will have no sound.') }
            return $list
        }.GetNewClosure()
        Default = $(if ($copy) { 'copy' } else { 'auto' })
    }
    $isEnc = { param($W) (& $wb $W) -and ((Get-Answer $W "${p}codec") -notin @('copy', 'none', $null)) }.GetNewClosure()
    $encoderOf = {
        param($W)
        $c = [string](Get-Answer $W "${p}codec" 'auto')
        if ($c -eq 'auto') { $l = @(Get-AudioEncoderChoices -AllowedFamilies (& $allowedOf $W)); if ($l.Count) { return [string]$l[0].Encoder } else { return '' } }
        return $c
    }.GetNewClosure()
    $lossy = { param($W) (& $isEnc $W) -and ((& $encoderOf $W) -notin @('flac', 'alac', 'pcm_s16le', '')) }.GetNewClosure()
    if ($vbr) {
        $steps += @{
            Id = "${p}qm"; Type = 'Choice'; Prompt = 'Audio quality mode'; Help = 'Variable quality (VBR) targets a quality level; bitrate targets a fixed size per second.'
            When = { param($W) (& $lossy $W) -and ((& $encoderOf $W) -in @('libmp3lame', 'libvorbis')) }.GetNewClosure()
            Choices = { param($W) @( (New-Choice 'Bitrate' 'Bitrate' 'Constant target bitrate.'), (New-Choice 'Quality' 'Variable quality (VBR)' 'Best size/quality balance.') ) }
            Default = 'Bitrate'
        }
        $steps += @{
            Id = "${p}vbr"; Type = 'Choice'; Prompt = 'VBR quality level'; Help = 'Higher quality creates larger files.'
            When = { param($W) (& $lossy $W) -and ((Get-Answer $W "${p}qm" 'Bitrate') -eq 'Quality') }.GetNewClosure()
            Choices = { param($W) if ((& $encoderOf $W) -eq 'libmp3lame') { @( (New-Choice 0 'Best (V0, ~245 kbps)' 'Highest MP3 quality; largest files.'), (New-Choice 2 'High (V2, ~190 kbps)' 'Excellent quality; the usual choice for music.'), (New-Choice 4 'Standard (V4, ~165 kbps)' 'Good quality at a smaller size.'), (New-Choice 6 'Small (V6, ~130 kbps)' 'Smallest files; fine for speech.') ) } else { @( (New-Choice 8 'Best (8)' 'Highest quality; largest files.'), (New-Choice 6 'High (6)' 'High quality at a moderate size.'), (New-Choice 4 'Standard (4)' 'Good quality for most uses.'), (New-Choice 2 'Small (2)' 'Smallest files; lower quality.') ) } }.GetNewClosure()
            Default = { param($W) if ((& $encoderOf $W) -eq 'libmp3lame') { 2 } else { 6 } }.GetNewClosure()
        }
    }
    $steps += @{
        Id = "${p}bitrate"; Type = 'Choice'; Prompt = 'Audio bitrate'; Help = 'Higher bitrate means better sound and larger files.'
        When = { param($W) (& $lossy $W) -and ((Get-Answer $W "${p}qm" 'Bitrate') -ne 'Quality') }.GetNewClosure()
        Choices = { param($W) @( (New-Choice 96000 '96 kbps' 'Voice / small.'), (New-Choice 128000 '128 kbps' 'Good quality.'), (New-Choice 192000 '192 kbps' 'High quality.'), (New-Choice 256000 '256 kbps' 'Very high quality.'), (New-Choice 320000 '320 kbps' 'Maximum for MP3.') ) }
        AllowCustom = @{ Label = 'Custom bitrate...'; Type = 'Bitrate'; Prompt = 'Custom audio bitrate'; Help = 'Use k suffix.'; Example = '160k'; Desc = 'For example 160k.' }
        Default = { param($W) Get-DefaultAudioBitrate (& $encoderOf $W) }.GetNewClosure()
    }
    if ($full) {
        $srList = Get-PresetList 'sampleRates' @(8000, 16000, 22050, 32000, 44100, 48000, 96000)
        $steps += @{
            Id = "${p}sr"; Type = 'Choice'; Prompt = 'Sample rate'; Help = 'Keep original unless you need a specific rate.'
            When = $isEnc
            Choices = { param($W) @(New-Choice 0 'Keep original' 'Leave this setting as it is in the source file.') + @($srList | ForEach-Object { New-Choice $_ ("{0:N0} Hz" -f $_) (Get-SampleRateDescription ([int]$_)) }) }.GetNewClosure()
            AllowCustom = @{ Label = 'Custom...'; Type = 'Integer'; Min = 8000; Max = 192000; Prompt = 'Custom sample rate (Hz)'; Help = 'Between 8000 and 192000.'; Example = '44100'; ValueLabel = 'Sample rate' }
            Default = 0
        }
        $steps += @{
            Id = "${p}ch"; Type = 'Choice'; Prompt = 'Channels'; Help = 'Mono has one channel, stereo has two (left/right).'
            When = $isEnc
            Choices = { param($W) @( (New-Choice 0 'Keep original' 'Leave this setting as it is in the source file.'), (New-Choice 1 'Mono' 'One channel; smallest size, good for speech.'), (New-Choice 2 'Stereo' 'Left and right channels; standard for music.'), (New-Choice 6 '5.1 surround' 'Six channels for home cinema.') ) }
            AllowCustom = @{ Label = 'Custom count...'; Type = 'Integer'; Min = 1; Max = 8; Prompt = 'Number of channels'; Help = 'Between 1 and 8.'; Example = '2'; ValueLabel = 'Channels' }
            Default = 0
        }
    }
    return $steps
}

function Resolve-AudioEncode {
    # Returns @{ None; Copy; Tokens; Encoder }.
    param($W, [string]$Prefix = 'a', [string]$Container, [string[]]$AllowedFamilies = @(), [bool]$HasAudio = $true)
    $p = $Prefix
    if (-not $HasAudio) { return @{ None = $true; Copy = $false; Tokens = @('-an'); Encoder = '' } }
    $codec = [string](Get-Answer $W "${p}codec" 'auto')
    if ($codec -eq 'none') { return @{ None = $true; Copy = $false; Tokens = @('-an'); Encoder = '' } }
    if ($codec -eq 'copy') { return @{ None = $false; Copy = $true; Tokens = @('-c:a', 'copy'); Encoder = 'copy' } }
    if ($codec -eq 'auto') {
        $allowed = $AllowedFamilies
        if ($allowed.Count -eq 0) { $c = Get-VideoContainer $Container; if ($c) { $allowed = @($c.Audio) } }
        $l = @(Get-AudioEncoderChoices -AllowedFamilies $allowed)
        if ($l.Count -eq 0) { throw 'No usable audio encoder is available in your FFmpeg build for this format.' }
        $codec = [string]$l[0].Encoder
    }
    $br = Get-Answer $W "${p}bitrate"
    if (-not $br -and $codec -notin @('flac', 'alac', 'pcm_s16le')) { $br = Get-DefaultAudioBitrate $codec }
    $sr = Get-Answer $W "${p}sr" 0; $ch = Get-Answer $W "${p}ch" 0
    if ($sr -eq 0) { $sr = $null }; if ($ch -eq 0) { $ch = $null }
    $qm = [string](Get-Answer $W "${p}qm" 'Bitrate')
    $tokens = Get-AudioEncodeArgs -Encoder $codec -BitrateBps $br -Mode $qm -VbrQuality (Get-Answer $W "${p}vbr") -SampleRate $sr -Channels $ch
    return @{ None = $false; Copy = $false; Tokens = $tokens; Encoder = $codec }
}

# ---- time range ------------------------------------------------------------------

function Get-TimeRangeSteps {
    <# Range questions: entire media, start+end, or start+duration. Times are validated against the media duration. #>
    param([string]$Prefix = 't', [string]$InputId = 'input', [string]$Prompt = 'Time range', [switch]$RequireRange, [string]$WhenId = '', [scriptblock]$When)
    $p = $Prefix; $iid = $InputId
    $wb = { param($W) $true }; if ($When) { $wb = $When }
    $dur = { param($W) $m = Get-Media $W $iid; if ($m) { return $m.Duration } else { return $null } }.GetNewClosure()
    $steps = @()
    $steps += @{
        Id = "${p}range"; Type = 'Choice'; Prompt = $Prompt; Help = 'Use only part of the media, or all of it.'
        When = $wb
        Choices = { param($W) $l = @(); if (-not $RequireRange) { $l += , (New-Choice 'full' 'Entire file' 'Use the whole duration.') }; $l += , (New-Choice 'startend' 'Start time + end time' 'Example: from 00:00:10 to 00:00:25.'); $l += , (New-Choice 'startdur' 'Start time + duration' 'Example: start at 00:00:10 and keep 15 seconds.'); return $l }.GetNewClosure()
        Default = $(if ($RequireRange) { 'startend' } else { 'full' })
    }
    $steps += @{
        Id = "${p}start"; Type = 'Timestamp'; Prompt = 'Start time'; Help = 'Where the selected range begins.'; Example = '00:00:10  or  10  or  1:30'; Default = '0'
        When = { param($W) (& $wb $W) -and ((Get-Answer $W "${p}range") -in @('startend', 'startdur')) }.GetNewClosure()
        Validate = { param($v, $W) $d = & $dur $W; if ($v -lt 0) { return 'Start time cannot be negative.' }; if ($null -ne $d -and $v -ge $d) { return ('Start time must be before the end of the media ({0}).' -f (Format-Duration $d)) }; return $null }.GetNewClosure()
    }
    $steps += @{
        Id = "${p}end"; Type = 'Timestamp'; Prompt = 'End time'; Help = 'Where the selected range ends. Must be after the start time.'; Example = '00:00:25  or  25  or  0:25'
        When = { param($W) (& $wb $W) -and ((Get-Answer $W "${p}range") -eq 'startend') }.GetNewClosure()
        Default = { param($W) $d = & $dur $W; $s = [double](Get-Answer $W "${p}start" 0); if ($null -ne $d) { return (ConvertTo-TimestampText $d) }; return (ConvertTo-TimestampText ($s + 10)) }.GetNewClosure()
        Validate = { param($v, $W) $d = & $dur $W; $s = [double](Get-Answer $W "${p}start" 0); if ($v -le $s) { return 'End time must be after the start time.' }; if ($null -ne $d -and $v -gt $d + 0.01) { return ('End time is beyond the end of the media ({0}).' -f (Format-Duration $d)) }; return $null }.GetNewClosure()
    }
    $steps += @{
        Id = "${p}dur"; Type = 'Timestamp'; Prompt = 'Duration'; Help = 'How much to keep, counted from the start time.'; Example = '15  or  0:15  or  00:00:15'
        When = { param($W) (& $wb $W) -and ((Get-Answer $W "${p}range") -eq 'startdur') }.GetNewClosure()
        Validate = { param($v, $W) $d = & $dur $W; $s = [double](Get-Answer $W "${p}start" 0); if ($v -le 0) { return 'Duration must be greater than zero.' }; if ($null -ne $d -and ($s + $v) -gt $d + 0.01) { return ('Start + duration exceeds the media length ({0}).' -f (Format-Duration $d)) }; return $null }.GetNewClosure()
    }
    return $steps
}

function Resolve-TimeRange {
    # Returns @{ Full; Start; Duration } (Duration = $null for open-ended).
    param($W, [string]$Prefix = 't', [string]$InputId = 'input')
    $p = $Prefix
    $range = [string](Get-Answer $W "${p}range" 'full')
    $m = Get-Media $W $InputId
    $total = $null; if ($m) { $total = $m.Duration }
    if ($range -eq 'full') { return @{ Full = $true; Start = 0.0; Duration = $total } }
    $s = [double](Get-Answer $W "${p}start" 0)
    if ($range -eq 'startend') { $d = [double](Get-Answer $W "${p}end") - $s } else { $d = [double](Get-Answer $W "${p}dur") }
    return @{ Full = $false; Start = $s; Duration = $d }
}

function Get-RangeInputOptions {
    # -ss / -t placed before -i for fast seeking (re-encode paths are still frame-accurate).
    param($Range)
    $o = @()
    if (-not $Range.Full) {
        if ($Range.Start -gt 0) { $o += @('-ss', (Format-FFNumber $Range.Start 3)) }
        $o += @('-t', (Format-FFNumber $Range.Duration 3))
    }
    return $o
}

# ---- codec families / stream mapping -------------------------------------------------

function Get-VideoFamily {
    param([string]$Codec)
    switch ($Codec) { 'h264' { 'h264' } 'hevc' { 'hevc' } 'av1' { 'av1' } 'vp9' { 'vp9' } 'vp8' { 'vp8' } 'mpeg4' { 'mpeg4' } 'prores' { 'prores' } 'mpeg2video' { 'mpeg2' } default { $Codec } }
}

function Get-AudioFamily {
    param([string]$Codec)
    if ($Codec -like 'pcm_*') { return 'pcm' }
    switch ($Codec) { 'aac' { 'aac' } 'mp3' { 'mp3' } 'opus' { 'opus' } 'vorbis' { 'vorbis' } 'flac' { 'flac' } 'alac' { 'alac' } 'ac3' { 'ac3' } default { $Codec } }
}

function Test-CopyAllowed {
    # Returns $null when stream copy of the given source streams into the container is fine, else a message.
    param($Info, [string]$Container, [bool]$Video = $true, [bool]$Audio = $true)
    $c = Get-VideoContainer $Container
    if (-not $c) { return $null }
    if ($Video -and $Info.HasVideo) {
        $f = Get-VideoFamily $Info.Video[0].Codec
        if ($c.Video -notcontains $f) { return ("The source video codec ({0}) cannot be stored in {1} without re-encoding. Choose another video codec or format." -f (Get-FriendlyCodecName $Info.Video[0].Codec), $c.Label) }
    }
    if ($Audio -and $Info.HasAudio) {
        foreach ($a in $Info.Audio) {
            $f = Get-AudioFamily $a.Codec
            if ($c.Audio -notcontains $f) { return ("The source audio codec ({0}) cannot be stored in {1} without re-encoding. Choose to convert the audio instead." -f (Get-FriendlyCodecName $a.Codec), $c.Label) }
        }
    }
    return $null
}

function Get-SubtitleMapping {
    # Which subtitle streams can be carried into the container. Bitmap subtitles cannot be converted to text formats.
    param($Info, [string]$Container, [string]$Mode = 'copy')
    $r = @{ Maps = @(); Codec = ''; Dropped = 0; Tokens = @() }
    if ($Mode -ne 'copy' -or -not $Info.HasSubtitles) { return $r }
    $c = Get-VideoContainer $Container
    $subCodec = 'none'; if ($c) { $subCodec = $c.Sub }
    if ($subCodec -eq 'none') { $r.Dropped = $Info.Subtitles.Count; return $r }
    foreach ($s in $Info.Subtitles) {
        if ($s.IsText -or ($subCodec -eq 'copy')) { $r.Maps += $s.Index } else { $r.Dropped++ }
    }
    if ($r.Maps.Count -gt 0) {
        $r.Codec = $subCodec
        foreach ($i in $r.Maps) { $r.Tokens += @('-map', "0:$i") }
        $r.Tokens += @('-c:s', $subCodec)
    }
    return $r
}

function Get-ResolutionChoices {
    $out = @( (New-Choice 'keep' 'Keep original' 'Leave this setting as it is in the source file.') )
    foreach ($h in (Get-PresetList 'resolutions' @(2160, 1440, 1080, 720, 480))) {
        $n = switch ([int]$h) { 2160 { '4K (2160p)' } 1440 { '1440p' } 1080 { '1080p (Full HD)' } 720 { '720p (HD)' } 480 { '480p' } default { "${h}p" } }
        $out += , (New-Choice ("h$h") $n "Scale to $h pixels high; the width follows automatically.")
    }
    return $out
}

function Get-ResolutionFilter {
    # Values: keep | h<height> | <W>x<H> (fit inside, aspect kept) | <W> (width only). Returns '' for keep.
    param([string]$Value, [string]$Algorithm = '')
    if (-not $Value -or $Value -eq 'keep') { return '' }
    if ($Value -match '^h(\d+)$') { return (New-ScaleFilter -Height ([int]$Matches[1]) -Mode Preserve -Algorithm $Algorithm) }
    if ($Value -match '^(\d+)[xX](\d+)$') { return (New-ScaleFilter -Width ([int]$Matches[1]) -Height ([int]$Matches[2]) -Mode Preserve -Algorithm $Algorithm) }
    if ($Value -match '^\d+$') { return (New-ScaleFilter -Width ([int]$Value) -Mode Preserve -Algorithm $Algorithm) }
    throw "Unrecognized resolution: $Value"
}

function Get-ResolutionStep {
    param([string]$Id = 'resolution', [string]$Prompt = 'Resolution')
    return @{
        Id = $Id; Type = 'Choice'; Prompt = $Prompt; Help = 'Smaller dimensions create smaller files. The aspect ratio is always kept.'
        Choices = { param($W) @(Get-ResolutionChoices) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Resolution'; Prompt = 'Custom resolution'; Help = 'Enter width x height (fits inside, aspect kept) or just a width.'; Example = '1280x720  or  1280'; Desc = 'For example 1280x720 or just 1280.' }
        Default = 'keep'
    }
}

function Get-FrameRateStep {
    param([string]$Id = 'fps', [string]$Prompt = 'Frame rate', [string]$Help = 'Keep the original unless you need a specific rate.')
    $list = Get-PresetList 'frameRates' @(24, 25, 30, 50, 60)
    return @{
        Id = $Id; Type = 'Choice'; Prompt = $Prompt; Help = $Help
        Choices = { param($W) @(New-Choice 0 'Keep original' 'Leave this setting as it is in the source file.') + @($list | ForEach-Object { New-Choice ([double]$_) ("{0:0.##} FPS" -f $_) (Get-FpsDescription ([double]$_)) }) }.GetNewClosure()
        AllowCustom = @{ Label = 'Custom...'; Type = 'FrameRate'; Prompt = 'Custom frame rate'; Help = 'Frames per second between 0.1 and 240.'; Example = '29.97'; Desc = 'For example 29.97.' }
        Default = 0
    }
}

function Get-SubtitleBehaviorStep {
    param([string]$Id = 'subs', [string]$InputId = 'input')
    $iid = $InputId
    return @{
        Id = $Id; Type = 'Choice'; Prompt = 'Subtitles'; Help = 'Text subtitles can be carried into MP4/MKV/WebM/MOV. Bitmap subtitles cannot be converted.'
        When = { param($W) $m = Get-Media $W $iid; [bool]($m -and $m.HasSubtitles) }.GetNewClosure()
        Choices = { param($W) @( (New-Choice 'copy' 'Copy compatible subtitles' 'Keep the subtitle tracks that this file type can hold.'), (New-Choice 'remove' 'Remove subtitles' 'The result has no subtitle tracks.') ) }
        Default = 'copy'
    }
}

function Get-MetadataStep {
    param([string]$Id = 'metadata')
    return @{ Id = $Id; Type = 'Choice'; Prompt = 'Metadata'; Help = 'Titles, dates and similar tags stored inside the file.'
        Choices = { param($W) @( (New-Choice 'keep' 'Preserve metadata' 'Keep titles, dates and similar tags from the source.'), (New-Choice 'strip' 'Strip metadata' 'Remove tags and chapters.') ) }; Default = 'keep' }
}

function Get-MetadataTokens {
    param([string]$Mode)
    if ($Mode -eq 'strip') { return @('-map_metadata', '-1', '-map_chapters', '-1') }
    return @('-map_metadata', '0')
}

# ---- advanced gate ------------------------------------------------------------------

function Get-AdvancedGateStep {
    param([string]$Id = 'advanced', [string]$Prompt = 'Configure advanced options?')
    return @{ Id = $Id; Type = 'YesNo'; Prompt = $Prompt; Help = 'Expert settings such as pixel format, keyframe interval and hardware decoding. Recommended defaults are used when you choose No.'; Default = $false; YesLabel = 'Yes, show advanced options'; NoLabel = 'No, use recommended defaults'; YesDesc = 'You will be asked about pixel format, keyframes and hardware decoding.'; NoDesc = 'Safe, well-tested defaults are used. Best for most people.' }
}

# ---- failure reasons --------------------------------------------------------------

function Get-FFmpegFailureReason {
    param([string]$StdErr, [int]$ExitCode)
    $lines = @($StdErr -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $known = @(
        @('No such file or directory', 'An input or output path could not be found.'),
        @('Permission denied', 'Access to a file or folder was denied. Check that you can write to the output folder and that the file is not open elsewhere.'),
        @('Unknown encoder', 'The selected encoder is not available in this FFmpeg build.'),
        @('Encoder .* not found', 'The selected encoder is not available in this FFmpeg build.'),
        @('Error while opening encoder', 'The encoder rejected the chosen settings for this media.'),
        @('Could not write header', 'The selected format cannot store this combination of streams. Try another output format or codec.'),
        @('Invalid argument', 'FFmpeg rejected one of the settings for this media.'),
        @('Invalid data found', 'The input file is damaged or not valid media.'),
        @('moov atom not found', 'The input file is incomplete or damaged.'),
        @('No such filter', 'A required filter is not available in this FFmpeg build.'),
        @('Filter .* not found', 'A required filter is not available in this FFmpeg build.'),
        @('already exists', 'The output file already exists.'),
        @('Disk quota|No space left', 'There is not enough free disk space.'),
        @('Conversion failed', 'FFmpeg could not complete the conversion.')
    )
    foreach ($k in $known) { if ($StdErr -match $k[0]) { $why = $k[1]; $tail = ($lines | Select-Object -Last 1); return $why + $(if ($tail) { "`n" + $tail } else { '' }) } }
    if ($lines.Count -gt 0) { return (($lines | Select-Object -Last 2) -join "`n") }
    return "FFmpeg stopped with exit code $ExitCode."
}

# ---- central job runner -------------------------------------------------------------

function Invoke-FFJob {
    <#
      Runs a job (Stages, Output, Summary) with progress, cancellation, and result/failure screens.
      Returns 'Again' | 'Menu'.
      Job: @{ Stages=@(@{Name;Arguments|Factory;DurationSec}); OutputPath; OutputKind='File'|'Folder'; OverwriteOutput;
              EnsureDirs; TempFiles; SourceSize; Title }
    #>
    param([Parameter(Mandatory)]$Job)
    while ($true) {
        $ff = Get-FFmpegPath
        $failure = $null
        $batchFailures = @()
        $cancelled = $false
        $stageResults = @()
        $existedBefore = $false
        $outPath = [string]$Job.OutputPath
        if ($outPath -and @('Folder', 'Network') -notcontains $Job.OutputKind) { $existedBefore = Test-Path -LiteralPath $outPath }
        try {
            foreach ($d in @($Job.EnsureDirs)) { if ($d -and -not (Test-Path -LiteralPath $d -PathType Container)) { [void](New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop) } }
        } catch {
            $act = Show-Notice -Title 'The output folder could not be created' -Lines @($_.Exception.Message) -Kind Error -Actions @(@('B', 'Back to menu'))
            Remove-JobTempFiles $Job; return 'Menu'
        }
        $swAll = [System.Diagnostics.Stopwatch]::StartNew()
        $stageIndex = 0
        foreach ($st in @($Job.Stages)) {
            $stageIndex++
            $tokens = @()
            if ($st.ContainsKey('Factory') -and $st.Factory) {
                try { $tokens = @(& $st.Factory $Job $stageResults) }
                catch { $failure = [pscustomobject]@{ Started = $false; ExitCode = -1; StdErr = ''; Cancelled = $false; Error = $_.Exception.Message }; break }
            } else { $tokens = @($st.Arguments) }
            $total = $null; if ($st.ContainsKey('DurationSec')) { $total = $st.DurationSec }
            $stageName = [string]$st.Name
            if ($st.ContainsKey('BatchItem') -and $st.BatchItem) { $st.BatchItem.Status = 'Processing' }
            $stageText = 'Stage {0} of {1}: {2}' -f $stageIndex, @($Job.Stages).Count, $stageName
            $onTick = {
                param($state)
                $script:JobTick++
                Show-JobProgress -Title $(if ($Job.Title) { [string]$Job.Title } else { 'Processing' }) -StageText $(if (@($Job.Stages).Count -gt 1) { $stageText } else { '' }) -Percent $state.Percent -OutTime $state.OutTime -TotalSec $state.TotalSec -Speed $state.Speed -Elapsed $swAll.Elapsed -Tick $script:JobTick -Status $stageName
                if (Test-TuiKeyAvailable) {
                    $k = Read-TuiKey
                    $isQ = ($k.Name -eq 'CtrlC') -or ($k.Name -eq 'Esc')
                    if ($isQ) {
                        $yes = Show-Confirm -Title 'Cancel this job?' -Lines @('FFmpeg will be stopped. The output file may be incomplete.') -Default $false -YesLabel 'Yes, cancel the job' -NoLabel 'No, keep going'
                        if ($yes) { return $true }
                    }
                }
                return $false
            }.GetNewClosure()
            $script:JobTick = 0
            $r = Invoke-FFmpegStage -FfmpegPath $ff -Arguments $tokens -TotalSec $total -OnTick $onTick
            $stageResults += , $r
            if ($r.Cancelled) { $cancelled = $true; break }
            $stageFailed = ((-not $r.Started) -or $r.ExitCode -ne 0)
            if ($stageFailed) {
                if ($st.ContainsKey('BatchItem') -and $st.BatchItem) { $st.BatchItem.Status = 'Failed'; $st.BatchItem.Error = $(if ($r.Error) { $r.Error } else { Get-FFmpegFailureReason $r.StdErr $r.ExitCode }) }
                if ($Job.ContainsKey('ContinueOnFailure') -and $Job.ContinueOnFailure) { $batchFailures += , $r; continue }
                $failure = $r; break
            }
            if ($st.ContainsKey('BatchItem') -and $st.BatchItem) { $st.BatchItem.Status = 'Completed' }
        }
        $swAll.Stop()
        Restore-JobCursor
        $lastR = $null; if ($stageResults.Count -gt 0) { $lastR = $stageResults[$stageResults.Count - 1] }
        $tokensText = ''
        foreach ($st in @($Job.Stages)) { $tokensText += ('[' + $st.Name + '] ' + (Format-FFmpegCommandLine @($st.Arguments)) + "`n") }
        Remove-JobTempFiles $Job
        if ($cancelled) {
            $lines = @('The job was cancelled.')
            if ($outPath -and $Job.OutputKind -ne 'Network' -and (Test-Path -LiteralPath $outPath)) { $lines += 'A partial output file may exist and is potentially incomplete:'; $lines += $outPath }
            $ca = Show-Notice -Title 'Job cancelled' -Lines $lines -Kind Warning -Actions @(@('M', 'Main menu'), @('R', 'Run again'))
            if ($ca -eq 'R') { return 'Again' }
            return 'Menu'
        }
        if ($null -ne $failure) {
            if ($outPath -and @('Folder', 'Network') -notcontains $Job.OutputKind -and -not $existedBefore -and (Test-Path -LiteralPath $outPath)) {
                try { if ((New-Object System.IO.FileInfo($outPath)).Length -eq 0) { Remove-Item -LiteralPath $outPath -Force } } catch { }
            }
            $reason = if ($failure.Error) { $failure.Error } else { Get-FFmpegFailureReason $failure.StdErr $failure.ExitCode }
            while ($true) {
                $act = Show-Notice -Title 'Processing failed.' -Lines @('Reason:', $reason) -Kind Error -Actions @(@('D', 'Show technical details'), @('R', 'Retry'), @('B', 'Back'))
                if ($act -eq 'D') {
                    $details = @(('Exit code: ' + $failure.ExitCode), '', 'Command:') + @($tokensText -split "`n") + @('', 'FFmpeg output:') + @($failure.StdErr -split "`r?`n")
                    Show-TextViewer -Title 'Technical details' -Lines $details
                    continue
                }
                if ($act -eq 'R') { break }
                return 'Menu'
            }
            if ($act -eq 'R') { continue }
        }
        # ---- success
        $lines = @('Output:')
        $rows = @()
        if ($Job.OutputKind -eq 'Folder') {
            $count = 0
            if ($Job.ContainsKey('CountOutputs') -and $Job.CountOutputs) { $count = [int](& $Job.CountOutputs) }
            $lines += $outPath
            if ($count -gt 0) { $lines += ''; $lines += "Files created: $count" }
            if ($Job.ContainsKey('BatchQueue') -and $Job.BatchQueue) {
                $q = Get-BatchQueueSummary $Job.BatchQueue
                $lines += ''; $lines += ('Completed: {0}   Failed: {1}   Skipped: {2}' -f $q.Completed, $q.Failed, $q.Skipped)
                $failedNames = @($Job.BatchQueue | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object { ([System.IO.Path]::GetFileName($_.InputPath) + ': ' + $_.Error) })
                if ($failedNames.Count -gt 0) { $lines += ''; $lines += 'Failed files:'; $lines += @($failedNames | Select-Object -First 10) }
            }
        } elseif ($Job.OutputKind -eq 'Network') {
            $lines = @('Sent to:', [string]$Job.OutputDisplay)
        } else {
            $lines += $outPath
            if (Test-Path -LiteralPath $outPath) {
                $newSize = (New-Object System.IO.FileInfo($outPath)).Length
                $lines += ''; $lines += 'Size:'; $lines += (Format-FileSize $newSize)
                if ($Job.ContainsKey('SourceSize') -and $Job.SourceSize -and $Job.SourceSize -gt 0 -and $Job.ContainsKey('CompareSize') -and $Job.CompareSize) {
                    $diff = 100.0 * ($newSize - $Job.SourceSize) / $Job.SourceSize
                    $lines += ''; $lines += ('Original size: {0}   New size: {1}   Change: {2:+0.#;-0.#}%' -f (Format-FileSize $Job.SourceSize), (Format-FileSize $newSize), $diff)
                }
            }
        }
        $lines += ''; $lines += ('Elapsed: ' + (Format-Duration $swAll.Elapsed.TotalSeconds))
        if ($Job.ContainsKey('ResultNotes')) { foreach ($n in @($Job.ResultNotes)) { $lines += ''; $lines += [string]$n } }
        while ($true) {
            $doneActions = @(@('O', 'Open output folder'), @('R', 'Run again'), @('M', 'Main menu'))
            if ($Job.OutputKind -eq 'Network') { $doneActions = @(@('R', 'Run again'), @('M', 'Main menu')) }
            $act = Show-Notice -Title 'Completed successfully' -Lines $lines -Kind Success -Actions $doneActions
            if ($act -eq 'O') { $target = $outPath; [void](Open-OutputFolder -Path $target); continue }
            if ($act -eq 'R') { return 'Again' }
            return 'Menu'
        }
    }
}

function Restore-JobCursor { try { Show-Cursor } catch { } }

function Remove-JobTempFiles {
    param($Job)
    if ($Job.ContainsKey('TempFiles')) { foreach ($f in @($Job.TempFiles)) { try { if ($f -and (Test-Path -LiteralPath $f)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } catch { } } }
}

function New-TempTextFile {
    # UTF-8 (no BOM) temp file for filter text / concat lists; caller adds it to Job.TempFiles.
    param([string]$Content, [string]$Suffix = '.txt')
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('fftui_' + [guid]::NewGuid().ToString('N') + $Suffix)
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Start-StandardWorkflow {
    # Runs wizard -> job repeatedly ("Run again") until the user returns to the menu.
    param([string]$Title, [string]$Description, [string]$Icon, [scriptblock]$StepsFactory, [scriptblock]$Build)
    while ($true) {
        $steps = @(& $StepsFactory)
        $r = Invoke-Wizard -Title $Title -Description $Description -Icon $Icon -Steps $steps -Build $Build
        if ($r.Status -ne 'Completed') { return }
        $job = $r.Job
        if (-not $job.ContainsKey('Title')) { $job.Title = $Title }
        $act = Invoke-FFJob -Job $job
        if ($act -ne 'Again') { return }
    }
}

function Get-InputPathList {
    param($W, [string]$Id = 'input')
    return @(@(Get-Answer $W $Id) | Where-Object { $_ })
}

function New-JobObject {
    param([string]$Title, $Summary, $Stages, [string]$OutputPath, [string]$OutputKind = 'File', [string[]]$EnsureDirs = @(), [string[]]$TempFiles = @(), $SourceSize = $null, [bool]$CompareSize = $false, [string[]]$Notes = @(), [string[]]$ResultNotes = @(), [scriptblock]$CountOutputs)
    $j = @{ Title = $Title; Summary = @($Summary); Stages = @($Stages); OutputPath = $OutputPath; OutputKind = $OutputKind; EnsureDirs = @($EnsureDirs); TempFiles = @($TempFiles); SourceSize = $SourceSize; CompareSize = $CompareSize; Notes = @($Notes); ResultNotes = @($ResultNotes) }
    if ($CountOutputs) { $j.CountOutputs = $CountOutputs }
    return $j
}

function Get-FileSizeSafe {
    param([string]$Path)
    try { return (New-Object System.IO.FileInfo($Path)).Length } catch { return $null }
}

# ---- shared "process a video with filters" and "process audio" building blocks ----------------

function Get-VideoTailSteps {
    # Output format + codec/quality (simple) + output folder/name for filter-style video workflows.
    param([string]$Suffix, [string]$InputId = 'input', [switch]$SkipFormat)
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $steps = @()
    if (-not $SkipFormat) { $steps += Get-ContainerStep -Id 'format' -InputId $InputId }
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript $cont -Level Simple
    $steps += Get-OutputSteps -Prefix 'out' -InputId $InputId -Suffix $Suffix -Extension { param($W) (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext }
    return $steps
}

function New-VideoProcessJob {
    <# Builds a re-encoding video job from answers: filters (-vf) or a filter_complex graph, audio copy/re-encode,
       compatible subtitles, metadata. Returns the job hashtable. #>
    param(
        $W, [string]$Title, [string]$InputId = 'input', [string[]]$VideoFilters = @(), [string]$FilterComplex = '', [string]$FilterComplexOutLabel = '[v]',
        [string[]]$ExtraInputs = @(), [string[]]$ExtraInputOptions = @(), [string[]]$AudioFilters = @(), [ValidateSet('copy', 'auto', 'none')][string]$AudioMode = 'copy',
        [string]$SubMode = 'copy', [object[]]$Rows = @(), [double]$Speed = 1.0, [string[]]$Notes = @(), [string]$StageName = 'Encoding video', $DurationSec = $null,
        [string[]]$RangeOptions = @()
    )
    $info = Get-Media $W $InputId
    $container = [string](Get-Answer $W 'format' 'mp4')
    $c = Get-VideoContainer $container
    $out = Get-OutputFile $W
    $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true
    $notes = @($Notes)
    $ae = $null
    $mode = $AudioMode
    if ($AudioFilters.Count -gt 0 -and $mode -eq 'copy') { $mode = 'auto' }
    if (-not $info.HasAudio) { $mode = 'none' }
    if ($mode -eq 'copy') {
        $msg = Test-CopyAllowed $info $container -Video $false -Audio $true
        if ($msg) { $mode = 'auto'; $notes += 'The original audio cannot be copied into this format, so it will be re-encoded.' }
    }
    if ($mode -eq 'none') { $ae = @{ None = $true; Copy = $false; Tokens = @('-an'); Encoder = '' } }
    elseif ($mode -eq 'copy') { $ae = @{ None = $false; Copy = $true; Tokens = @('-c:a', 'copy'); Encoder = 'copy' } }
    else {
        $l = @(Get-AudioEncoderChoices -AllowedFamilies @($c.Audio))
        if ($l.Count -eq 0) { throw 'No usable audio encoder is available for this format.' }
        $enc = [string]$l[0].Encoder
        $srcFam = ''; if ($info.HasAudio) { $srcFam = Get-AudioFamily $info.Audio[0].Codec }
        foreach ($x in $l) { if ($x.Id -eq $srcFam) { $enc = [string]$x.Encoder; break } }
        $ae = @{ None = $false; Copy = $false; Tokens = (Get-AudioEncodeArgs -Encoder $enc -BitrateBps (Get-DefaultAudioBitrate $enc)); Encoder = $enc }
    }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path (@($RangeOptions)))
    foreach ($e in $ExtraInputs) { [void](Add-FFInput $cmd $e @($ExtraInputOptions)) }
    if ($FilterComplex) {
        Add-FFOutOpt $cmd @('-filter_complex', $FilterComplex, '-map', $FilterComplexOutLabel)
    } else {
        Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index))
        if ($VideoFilters.Count -gt 0) { Add-FFOutOpt $cmd @('-vf', (Join-FFFilters $VideoFilters)) }
    }
    if ($info.HasAudio -and -not $ae.None) { Add-FFOutOpt $cmd @('-map', '0:a') }
    $sm = Get-SubtitleMapping $info $container $SubMode
    if ($sm.Tokens.Count -gt 0) { Add-FFOutOpt $cmd $sm.Tokens }
    if ($sm.Dropped -gt 0) { $notes += "$($sm.Dropped) subtitle stream(s) cannot be stored in this format and will be left out." }
    Add-FFOutOpt $cmd $ve.Tokens
    if ($AudioFilters.Count -gt 0 -and -not $ae.None) { Add-FFOutOpt $cmd @('-af', ($AudioFilters -join ',')) }
    Add-FFOutOpt $cmd $ae.Tokens
    Add-FFOutOpt $cmd (Get-MetadataTokens 'keep')
    Add-FFOutOpt $cmd @('-f', $c.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $dur = $DurationSec; if ($null -eq $dur -and $info.Duration) { $dur = $info.Duration / $Speed }
    $rows = @($Rows) + @(, @('Output', $out.Path))
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    return New-JobObject -Title $Title -Summary $rows -Stages @(@{ Name = $StageName; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $true -Notes $notes
}

function Get-AudioToolTailSteps {
    # Output format + audio codec for audio tools. Video inputs keep their video stream untouched (copy).
    param([string]$Suffix, [string]$InputId = 'input')
    $iid = $InputId
    $hasVideo = { param($W) $m = Get-Media $W $iid; [bool]($m -and $m.HasVideo) }.GetNewClosure()
    $steps = @()
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The video stream is copied unchanged; only the audio is processed.'
        When = $hasVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $m = Get-Media $W $iid; $c = Get-ContainerIdFromPath $m.Path; if ($c) { $c } else { 'mkv' } }.GetNewClosure() }
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The audio file type of the result.'
        When = { param($W) -not (& $hasVideo $W) }.GetNewClosure()
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $m = Get-Media $W $iid; $ext = [System.IO.Path]::GetExtension($m.Path).ToLowerInvariant().TrimStart('.'); foreach ($f in Get-AvailableAudioFormats) { if ($f.Id -eq $ext) { return $f.Id } }; return 'flac' }.GetNewClosure() }
    $fam = {
        param($W)
        if (& $hasVideo $W) { $c = Get-VideoContainer ([string](Get-Answer $W 'format' 'mkv')); if ($c) { return @($c.Audio) } }
        else { $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { return @($f.Codecs) } }
        return @()
    }.GetNewClosure()
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies $fam -Full:$false
    $steps += Get-OutputSteps -Prefix 'out' -InputId $InputId -Suffix $Suffix -Extension {
        param($W)
        $m = Get-Media $W 'input'
        if ($m -and $m.HasVideo) { return (Get-VideoContainer ([string](Get-Answer $W 'format' 'mkv'))).Ext }
        return (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext
    }
    return $steps
}

function New-AudioProcessJob {
    <# Audio-processing job: -af filters and/or extra output options; video (if any) is stream-copied. #>
    param($W, [string]$Title, [string]$InputId = 'input', [string[]]$AudioFilters = @(), [string[]]$ExtraAudioOptions = @(), [object[]]$Rows = @(), [string[]]$Notes = @(), [double]$Speed = 1.0, [string]$StageName = 'Processing audio')
    $info = Get-Media $W $InputId
    $hasVideo = $info.HasVideo
    $out = Get-OutputFile $W
    $notes = @($Notes)
    if ($hasVideo) { $container = [string](Get-Answer $W 'format' 'mkv'); $c = Get-VideoContainer $container; $muxer = $c.Muxer; $families = @($c.Audio) }
    else { $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); $muxer = $f.Muxer; $families = @($f.Codecs); $container = '' }
    $ae = Resolve-AudioEncode $W -Prefix 'a' -Container $container -AllowedFamilies $families -HasAudio $true
    if ($ae.None -or $ae.Copy -and $AudioFilters.Count -gt 0) { throw 'Audio processing requires re-encoding the audio.' }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    if ($hasVideo) { Add-FFOutOpt $cmd @('-map', ('0:' + $info.Video[0].Index), '-c:v', 'copy') } else { Add-FFOutOpt $cmd @('-vn') }
    Add-FFOutOpt $cmd @('-map', ('0:' + $info.Audio[0].Index))
    if ($AudioFilters.Count -gt 0) { Add-FFOutOpt $cmd @('-af', ($AudioFilters -join ',')) }
    Add-FFOutOpt $cmd $ae.Tokens
    Add-FFOutOpt $cmd $ExtraAudioOptions
    if ($hasVideo) { $sm = Get-SubtitleMapping $info $container 'copy'; if ($sm.Tokens.Count -gt 0) { Add-FFOutOpt $cmd $sm.Tokens } }
    Add-FFOutOpt $cmd (Get-MetadataTokens 'keep')
    Add-FFOutOpt $cmd @('-f', $muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $rows = @($Rows) + @(, @('Output', $out.Path))
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $dur = $null; if ($info.Duration) { $dur = $info.Duration / $Speed }
    return New-JobObject -Title $Title -Summary $rows -Stages @(@{ Name = $StageName; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

function Show-WorkflowSubmenu {
    # Generic submenu launcher: Items = @(@{Label;Desc;Key;Icon;Run=<scriptblock>}). Loops until Back.
    param([string]$Title, [string]$Subtitle = '', [object[]]$Items)
    $idx = 0
    while ($true) {
        $r = Show-Menu -Title $Title -Subtitle $Subtitle -Items $Items -AllowBack -InitialIndex $idx -ShowHeader
        if ($r.Action -ne 'Select') { return }
        $idx = $r.Index
        & $r.Item.Value
    }
}

Export-ModuleMember -Function Get-SpeedDescription, Get-FpsDescription, Get-SampleRateDescription, Get-EncoderPresetDescription, Get-VideoTailSteps, New-VideoProcessJob, Get-AudioToolTailSteps, New-AudioProcessJob, Show-WorkflowSubmenu, Get-VideoFamily, Get-AudioFamily, Test-CopyAllowed, Get-SubtitleMapping, Get-ResolutionChoices, Get-ResolutionFilter, Get-ResolutionStep, Get-FrameRateStep, Get-SubtitleBehaviorStep, Get-MetadataStep, Get-MetadataTokens, New-Choice, Get-Answer, Get-Media, Get-PresetList, Get-NumberChoices, Get-ContainerIdFromPath, Get-InputFileStep, Get-OutputFile, Get-OutputSteps, Get-ContainerStep, Get-VideoEncodeSteps, Resolve-VideoEncode, Get-AudioEncodeSteps, Resolve-AudioEncode, Get-TimeRangeSteps, Resolve-TimeRange, Get-RangeInputOptions, Get-AdvancedGateStep, Get-FFmpegFailureReason, Invoke-FFJob, Remove-JobTempFiles, New-TempTextFile, Start-StandardWorkflow, Get-InputPathList, New-JobObject, Get-FileSizeSafe
