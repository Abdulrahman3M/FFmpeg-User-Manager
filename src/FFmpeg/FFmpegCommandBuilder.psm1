# FFmpegCommandBuilder.psm1 - the one place FFmpeg command lines are constructed.
# Everything is a structured token list; user text is never concatenated into a shell string.
Set-StrictMode -Version 2.0

$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture

function Format-FFNumber {
    param([double]$Value, [int]$Decimals = 6)
    $s = $Value.ToString('0.' + ('#' * $Decimals), $script:Inv)
    if ($s -eq '') { $s = '0' }
    return $s
}

# ---- command object ----------------------------------------------------------

function New-FFCommand {
    return [pscustomobject]@{
        Global = New-Object System.Collections.Generic.List[string]
        Inputs = New-Object System.Collections.Generic.List[object]
        OutOpts = New-Object System.Collections.Generic.List[string]
        Output = ''
        Overwrite = $false
    }
}

function Add-FFInput {
    # Input options (e.g. -ss/-to/-f) precede the -i they apply to.
    param($Cmd, [string]$Path, [string[]]$Options = @())
    # A $null argument bound to [string[]] becomes one empty string; drop empty tokens.
    $Cmd.Inputs.Add(@{ Path = $Path; Options = @($Options | Where-Object { $null -ne $_ -and [string]$_ -ne '' }) })
    return ($Cmd.Inputs.Count - 1)
}

function Add-FFOutOpt {
    param($Cmd, [string[]]$Tokens)
    foreach ($t in $Tokens) { if ($null -ne $t -and [string]$t -ne '') { $Cmd.OutOpts.Add([string]$t) } }
}

function Set-FFOutput {
    param($Cmd, [string]$Path, [switch]$Overwrite)
    $Cmd.Output = $Path
    $Cmd.Overwrite = [bool]$Overwrite
}

function Get-FFTokens {
    # Final argument tokens (without the executable). Never overwrites unless explicitly confirmed (-y).
    param($Cmd)
    $t = New-Object System.Collections.Generic.List[string]
    foreach ($g in $Cmd.Global) { $t.Add($g) }
    $t.Add($(if ($Cmd.Overwrite) { '-y' } else { '-n' }))
    foreach ($in in $Cmd.Inputs) {
        foreach ($o in $in.Options) { $t.Add([string]$o) }
        $t.Add('-i'); $t.Add([string]$in.Path)
    }
    foreach ($o in $Cmd.OutOpts) { $t.Add($o) }
    if ($Cmd.Output) { $t.Add($Cmd.Output) }
    return $t.ToArray()
}

function Format-FFmpegCommandLine {
    # Display-only rendering for the Advanced "view command" screen.
    param([string[]]$Tokens)
    $ff = 'ffmpeg'
    $parts = @($ff)
    foreach ($tk in $Tokens) {
        if ($tk -match '[\s"''&()\[\];,]' -or $tk.Length -eq 0) { $parts += ('"' + $tk.Replace('"', '\"') + '"') } else { $parts += $tk }
    }
    return ($parts -join ' ')
}

# ---- filter escaping ---------------------------------------------------------

function ConvertTo-FFFilterValue {
    # Two-level escaping (option value, then filtergraph) for a literal value such as a file path.
    param([AllowEmptyString()][string]$Text)
    $s = $Text
    $s = $s.Replace('\', '\\').Replace("'", "\'").Replace(':', '\:').Replace('=', '\=')
    $s = $s.Replace('\', '\\').Replace("'", "\'").Replace(',', '\,').Replace(';', '\;').Replace('[', '\[').Replace(']', '\]')
    return $s
}

function ConvertTo-FFFilterPath {
    # Windows separators become '/', which FFmpeg accepts; then the path is escaped like any literal value.
    param([string]$Path)
    $p = $Path
    if (Test-IsWindows) { $p = $p.Replace('\', '/') }
    return (ConvertTo-FFFilterValue $p)
}

function Join-FFFilters {
    param([string[]]$Filters)
    return (@($Filters | Where-Object { $_ }) -join ',')
}

function Get-AtempoChain {
    # atempo accepts 0.5-2.0 per instance: chain instances for values outside that range.
    param([double]$Speed)
    if ($Speed -le 0) { throw 'Speed must be greater than zero.' }
    $parts = New-Object System.Collections.Generic.List[string]
    $s = $Speed
    while ($s -gt 2.0 + 1e-9) { $parts.Add('atempo=2.0'); $s = $s / 2.0 }
    while ($s -lt 0.5 - 1e-9) { $parts.Add('atempo=0.5'); $s = $s / 0.5 }
    if ([math]::Abs($s - 1.0) -gt 1e-9 -or $parts.Count -eq 0) { $parts.Add('atempo=' + $s.ToString('0.0#####', $script:Inv)) }
    elseif ($parts.Count -eq 0) { $parts.Add('atempo=1.0') }
    return ($parts -join ',')
}

function New-ScaleFilter {
    <# Mode: Preserve (aspect kept; give width and/or height) | Fit | Fill | Stretch.
       Pad: with Fit, add bars to reach exactly WxH.  Never distorts unless Mode = Stretch. #>
    param($Width = $null, $Height = $null, [ValidateSet('Preserve', 'Fit', 'Fill', 'Stretch')][string]$Mode = 'Preserve', [switch]$Pad, [string]$PadColor = 'black', [string]$Algorithm = '')
    $flags = ''; if ($Algorithm) { $flags = ':flags=' + $Algorithm }
    $w = $Width; $h = $Height
    switch ($Mode) {
        'Preserve' {
            if ($w -and -not $h) { return "scale=${w}:-2$flags" }
            if ($h -and -not $w) { return "scale=-2:${h}$flags" }
            return "scale=${w}:${h}:force_original_aspect_ratio=decrease:force_divisible_by=2$flags"
        }
        'Fit' {
            $f = "scale=${w}:${h}:force_original_aspect_ratio=decrease:force_divisible_by=2$flags"
            if ($Pad) { $f += ",pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=$PadColor" }
            return $f
        }
        'Fill' { return "scale=${w}:${h}:force_original_aspect_ratio=increase$flags,crop=${w}:${h}" }
        'Stretch' { return "scale=${w}:${h}$flags" }
    }
}

# ---- containers ---------------------------------------------------------------

$script:VideoContainers = @(
    @{ Id = 'mp4'; Label = 'MP4'; Ext = '.mp4'; Muxer = 'mp4'; Desc = 'Most compatible container for phones, browsers and TVs.'; Video = @('h264', 'hevc', 'av1', 'mpeg4', 'vp9'); Audio = @('aac', 'mp3', 'opus', 'ac3', 'alac', 'flac'); Sub = 'mov_text' },
    @{ Id = 'mkv'; Label = 'MKV (Matroska)'; Ext = '.mkv'; Muxer = 'matroska'; Desc = 'Flexible container that supports nearly everything.'; Video = @('h264', 'hevc', 'av1', 'vp9', 'vp8', 'mpeg4', 'prores'); Audio = @('aac', 'mp3', 'opus', 'vorbis', 'flac', 'ac3', 'alac', 'pcm'); Sub = 'copy' },
    @{ Id = 'webm'; Label = 'WebM'; Ext = '.webm'; Muxer = 'webm'; Desc = 'Open web format (VP8/VP9/AV1 with Opus/Vorbis).'; Video = @('vp9', 'vp8', 'av1'); Audio = @('opus', 'vorbis'); Sub = 'webvtt' },
    @{ Id = 'mov'; Label = 'MOV (QuickTime)'; Ext = '.mov'; Muxer = 'mov'; Desc = 'Apple QuickTime container; good for editing.'; Video = @('h264', 'hevc', 'prores', 'mpeg4'); Audio = @('aac', 'alac', 'pcm', 'ac3', 'mp3'); Sub = 'mov_text' },
    @{ Id = 'avi'; Label = 'AVI'; Ext = '.avi'; Muxer = 'avi'; Desc = 'Legacy container for older players.'; Video = @('mpeg4', 'h264'); Audio = @('mp3', 'ac3', 'pcm'); Sub = 'none' },
    @{ Id = 'ts'; Label = 'MPEG-TS'; Ext = '.ts'; Muxer = 'mpegts'; Desc = 'Broadcast/streaming transport stream.'; Video = @('h264', 'hevc'); Audio = @('aac', 'mp3', 'ac3'); Sub = 'none' },
    @{ Id = 'flv'; Label = 'FLV'; Ext = '.flv'; Muxer = 'flv'; Desc = 'Legacy Flash video container.'; Video = @('h264'); Audio = @('aac', 'mp3'); Sub = 'none' }
)

$script:AudioFormats = @(
    @{ Id = 'mp3'; Label = 'MP3'; Ext = '.mp3'; Muxer = 'mp3'; Codecs = @('mp3'); Desc = 'Universal compatibility.' },
    @{ Id = 'm4a'; Label = 'AAC in M4A'; Ext = '.m4a'; Muxer = 'ipod'; Codecs = @('aac', 'alac'); Desc = 'Good quality and small size; works on Apple/Android.' },
    @{ Id = 'flac'; Label = 'FLAC'; Ext = '.flac'; Muxer = 'flac'; Codecs = @('flac'); Desc = 'Lossless compression.' },
    @{ Id = 'wav'; Label = 'WAV'; Ext = '.wav'; Muxer = 'wav'; Codecs = @('pcm'); Desc = 'Uncompressed audio.' },
    @{ Id = 'opus'; Label = 'Opus'; Ext = '.opus'; Muxer = 'opus'; Codecs = @('opus'); Desc = 'Best quality at low bitrates.' },
    @{ Id = 'ogg'; Label = 'OGG (Vorbis)'; Ext = '.ogg'; Muxer = 'ogg'; Codecs = @('vorbis', 'opus', 'flac'); Desc = 'Open format with Vorbis audio.' },
    @{ Id = 'aac'; Label = 'AAC (ADTS)'; Ext = '.aac'; Muxer = 'adts'; Codecs = @('aac'); Desc = 'Raw AAC stream.' },
    @{ Id = 'ac3'; Label = 'AC-3'; Ext = '.ac3'; Muxer = 'ac3'; Codecs = @('ac3'); Desc = 'Dolby Digital audio.' },
    @{ Id = 'mka'; Label = 'MKA (Matroska Audio)'; Ext = '.mka'; Muxer = 'matroska'; Codecs = @('aac', 'mp3', 'opus', 'vorbis', 'flac', 'ac3', 'alac', 'pcm'); Desc = 'Flexible audio container.' }
)

function Get-VideoContainers { return $script:VideoContainers }
function Get-AudioFormats { return $script:AudioFormats }
function Get-VideoContainer { param([string]$Id) foreach ($c in $script:VideoContainers) { if ($c.Id -eq $Id) { return $c } } return $null }
function Get-AudioFormat { param([string]$Id) foreach ($c in $script:AudioFormats) { if ($c.Id -eq $Id) { return $c } } return $null }

function Get-AvailableVideoContainers {
    $out = @()
    foreach ($c in $script:VideoContainers) { if (Test-FFMuxer $c.Muxer) { $out += , $c } }
    return $out
}
function Get-AvailableAudioFormats {
    $out = @()
    foreach ($c in $script:AudioFormats) {
        if (-not (Test-FFMuxer $c.Muxer)) { continue }
        if ((Get-AudioEncoderChoices -AllowedFamilies $c.Codecs).Count -eq 0) { continue }
        $out += , $c
    }
    return $out
}

# ---- encoder profiles (how to drive each encoder; NOT a capability list) -----

$script:X26xPresets = @('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow')
$script:EncoderProfiles = @{
    'libx264'    = @{ Quality = 'crf'; Min = 0; Max = 51; High = 18; Balanced = 23; Small = 28; PresetFlag = '-preset'; Presets = $script:X26xPresets; DefaultPreset = 'medium'; PixFmt = 'yuv420p' }
    'libx265'    = @{ Quality = 'crf'; Min = 0; Max = 51; High = 22; Balanced = 28; Small = 32; PresetFlag = '-preset'; Presets = $script:X26xPresets; DefaultPreset = 'medium'; PixFmt = 'yuv420p'; TagHvc1 = $true }
    'libsvtav1'  = @{ Quality = 'crf'; Min = 0; Max = 63; High = 26; Balanced = 32; Small = 40; PresetFlag = '-preset'; Presets = @('4', '5', '6', '7', '8', '9', '10', '12'); DefaultPreset = '8'; PixFmt = 'yuv420p' }
    'libaom-av1' = @{ Quality = 'crf'; Min = 0; Max = 63; High = 24; Balanced = 30; Small = 38; PresetFlag = '-cpu-used'; Presets = @('2', '3', '4', '5', '6', '8'); DefaultPreset = '6'; PixFmt = 'yuv420p'; ZeroBitrate = $true; Extra = @('-row-mt', '1') }
    'librav1e'   = @{ Quality = 'qp'; Min = 0; Max = 255; High = 80; Balanced = 100; Small = 140; PresetFlag = '-speed'; Presets = @('4', '6', '8', '10'); DefaultPreset = '6'; PixFmt = 'yuv420p' }
    'libvpx-vp9' = @{ Quality = 'crf'; Min = 0; Max = 63; High = 24; Balanced = 31; Small = 38; PresetFlag = '-cpu-used'; Presets = @('0', '1', '2', '3', '4', '5'); DefaultPreset = '2'; PixFmt = 'yuv420p'; ZeroBitrate = $true; Extra = @('-row-mt', '1', '-deadline', 'good') }
    'libvpx'     = @{ Quality = 'crf'; Min = 4; Max = 63; High = 8; Balanced = 12; Small = 20; PresetFlag = '-cpu-used'; Presets = @('0', '1', '2', '3', '4', '5'); DefaultPreset = '2'; PixFmt = 'yuv420p'; NeedBitrateWithCrf = '2M' }
    'mpeg4'      = @{ Quality = 'qscale'; Min = 2; Max = 31; High = 3; Balanced = 5; Small = 9; PixFmt = 'yuv420p'; Tag = 'xvid' }
    'prores_ks'  = @{ Quality = 'none'; PixFmt = 'yuv422p10le'; Extra = @('-profile:v', '3') }
    'libopenh264' = @{ Quality = 'none'; PixFmt = 'yuv420p'; DefaultBitrate = 4000000 }
    'h264_nvenc' = @{ Quality = 'cq'; Min = 0; Max = 51; High = 19; Balanced = 24; Small = 30; PresetFlag = '-preset'; Presets = @('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'); DefaultPreset = 'p5'; PixFmt = 'yuv420p' }
    'hevc_nvenc' = @{ Quality = 'cq'; Min = 0; Max = 51; High = 21; Balanced = 26; Small = 32; PresetFlag = '-preset'; Presets = @('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'); DefaultPreset = 'p5'; PixFmt = 'yuv420p'; TagHvc1 = $true }
    'av1_nvenc'  = @{ Quality = 'cq'; Min = 0; Max = 63; High = 24; Balanced = 30; Small = 38; PresetFlag = '-preset'; Presets = @('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'); DefaultPreset = 'p5'; PixFmt = 'yuv420p' }
    'h264_qsv'   = @{ Quality = 'global_quality'; Min = 1; Max = 51; High = 19; Balanced = 24; Small = 30; PresetFlag = '-preset'; Presets = @('veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow'); DefaultPreset = 'medium'; PixFmt = 'nv12' }
    'hevc_qsv'   = @{ Quality = 'global_quality'; Min = 1; Max = 51; High = 21; Balanced = 26; Small = 32; PresetFlag = '-preset'; Presets = @('veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow'); DefaultPreset = 'medium'; PixFmt = 'nv12'; TagHvc1 = $true }
    'av1_qsv'    = @{ Quality = 'global_quality'; Min = 1; Max = 51; High = 24; Balanced = 30; Small = 38; PresetFlag = '-preset'; Presets = @('veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow'); DefaultPreset = 'medium'; PixFmt = 'nv12' }
    'h264_amf'   = @{ Quality = 'qp'; Min = 0; Max = 51; High = 19; Balanced = 24; Small = 30; PresetFlag = '-quality'; Presets = @('speed', 'balanced', 'quality'); DefaultPreset = 'balanced'; PixFmt = 'nv12' }
    'hevc_amf'   = @{ Quality = 'qp'; Min = 0; Max = 51; High = 21; Balanced = 26; Small = 32; PresetFlag = '-quality'; Presets = @('speed', 'balanced', 'quality'); DefaultPreset = 'balanced'; PixFmt = 'nv12'; TagHvc1 = $true }
    'av1_amf'    = @{ Quality = 'qp'; Min = 0; Max = 255; High = 80; Balanced = 100; Small = 140; PresetFlag = '-quality'; Presets = @('speed', 'balanced', 'quality'); DefaultPreset = 'balanced'; PixFmt = 'nv12' }
    'h264_videotoolbox' = @{ Quality = 'vtq'; Min = 1; Max = 100; High = 75; Balanced = 60; Small = 45; PixFmt = 'yuv420p' }
    'hevc_videotoolbox' = @{ Quality = 'vtq'; Min = 1; Max = 100; High = 75; Balanced = 60; Small = 45; PixFmt = 'yuv420p'; TagHvc1 = $true }
    'h264_mf'    = @{ Quality = 'none'; PixFmt = 'nv12'; DefaultBitrate = 5000000 }
    'hevc_mf'    = @{ Quality = 'none'; PixFmt = 'nv12'; DefaultBitrate = 5000000 }
}

function Get-EncoderProfile {
    param([string]$Encoder)
    if ($script:EncoderProfiles.ContainsKey($Encoder)) { return $script:EncoderProfiles[$Encoder] }
    return @{ Quality = 'none'; PixFmt = ''; DefaultBitrate = 5000000 }
}

function Test-EncoderSupportsQuality { param([string]$Encoder) return ((Get-EncoderProfile $Encoder).Quality -ne 'none') }

function Get-QualityChoices {
    # Friendly quality levels for an encoder (High / Balanced / Small) plus valid custom range.
    param([string]$Encoder)
    $p = Get-EncoderProfile $Encoder
    if ($p.Quality -eq 'none') { return @() }
    $name = switch ($p.Quality) { 'crf' { 'CRF' } 'cq' { 'CQ' } 'qp' { 'QP' } 'qscale' { 'Q' } 'global_quality' { 'Quality' } 'vtq' { 'Quality' } default { 'Level' } }
    $higherBetter = ($p.Quality -eq 'vtq')
    $note = if ($higherBetter) { 'higher = better' } else { 'lower = better' }
    return @(
        @{ Value = $p.High; Label = "High quality ($name $($p.High))"; Desc = 'Larger file, best visual quality.' },
        @{ Value = $p.Balanced; Label = "Balanced ($name $($p.Balanced))"; Desc = 'Good quality at a reasonable size.' },
        @{ Value = $p.Small; Label = "Smaller file ($name $($p.Small))"; Desc = 'Smaller file, visible quality loss.' }
    )
}

function Get-VideoEncodeArgs {
    <# Mode: Recommended | Quality | Bitrate.  Quality is the numeric value for the encoder's quality flag. #>
    param(
        [Parameter(Mandatory)][string]$Encoder,
        [ValidateSet('Recommended', 'Quality', 'Bitrate')][string]$Mode = 'Recommended',
        $Quality = $null, [string]$Preset = '', $BitrateBps = $null,
        [string]$Container = '', [bool]$Faststart = $false, [string]$PixFmt = '', $Gop = $null
    )
    $p = Get-EncoderProfile $Encoder
    $t = New-Object System.Collections.Generic.List[string]
    $t.Add('-c:v'); $t.Add($Encoder)
    $q = $Quality
    if ($Mode -eq 'Recommended') { if ($p.Quality -ne 'none') { $q = $p.Balanced } else { $BitrateBps = $(if ($p.ContainsKey('DefaultBitrate')) { $p.DefaultBitrate } else { 5000000 }) } }
    if ($Mode -eq 'Quality' -and $p.Quality -eq 'none') { $Mode = 'Bitrate'; if (-not $BitrateBps) { $BitrateBps = $(if ($p.ContainsKey('DefaultBitrate')) { $p.DefaultBitrate } else { 5000000 }) } }
    if ($Mode -eq 'Bitrate') {
        if (-not $BitrateBps) { throw 'A target bitrate is required.' }
        $t.Add('-b:v'); $t.Add([string][int64]$BitrateBps)
    } elseif ($p.Quality -ne 'none') {
        $qv = [int]$q
        switch ($p.Quality) {
            'crf' { $t.Add('-crf'); $t.Add([string]$qv); if ($p.ContainsKey('ZeroBitrate') -and $p.ZeroBitrate) { $t.Add('-b:v'); $t.Add('0') } elseif ($p.ContainsKey('NeedBitrateWithCrf')) { $t.Add('-b:v'); $t.Add([string]$p.NeedBitrateWithCrf) } }
            'cq' { $t.Add('-rc'); $t.Add('vbr'); $t.Add('-cq'); $t.Add([string]$qv); $t.Add('-b:v'); $t.Add('0') }
            'qp' {
                if ($Encoder -like '*_amf') { $t.Add('-rc'); $t.Add('cqp'); $t.Add('-qp_i'); $t.Add([string]$qv); $t.Add('-qp_p'); $t.Add([string]$qv) }
                else { $t.Add('-qp'); $t.Add([string]$qv) }
            }
            'qscale' { $t.Add('-q:v'); $t.Add([string]$qv) }
            'global_quality' { $t.Add('-global_quality'); $t.Add([string]$qv) }
            'vtq' { $t.Add('-q:v'); $t.Add([string]$qv) }
        }
    }
    if ($p.ContainsKey('PresetFlag')) {
        $pr = $Preset; if (-not $pr) { $pr = [string]$p.DefaultPreset }
        if ($pr) { $t.Add($p.PresetFlag); $t.Add($pr) }
    }
    if ($p.ContainsKey('Extra')) { foreach ($x in $p.Extra) { $t.Add([string]$x) } }
    $pf = $PixFmt; if (-not $pf) { $pf = [string]$p.PixFmt }
    if ($pf) { $t.Add('-pix_fmt'); $t.Add($pf) }
    if ($p.ContainsKey('TagHvc1') -and $p.TagHvc1 -and $Container -in @('mp4', 'mov', 'm4v')) { $t.Add('-tag:v'); $t.Add('hvc1') }
    if ($p.ContainsKey('Tag') -and $Container -eq 'mp4') { }
    if ($Gop) { $t.Add('-g'); $t.Add([string][int]$Gop) }
    if ($Faststart -and $Container -in @('mp4', 'mov', 'm4v')) { $t.Add('-movflags'); $t.Add('+faststart') }
    return $t.ToArray()
}

function Get-AudioEncodeArgs {
    <# Encoder = ffmpeg encoder name.  Mode: Bitrate | Quality (VBR where the encoder supports it). #>
    param([Parameter(Mandatory)][string]$Encoder, $BitrateBps = $null, [ValidateSet('Bitrate', 'Quality')][string]$Mode = 'Bitrate', $VbrQuality = $null, $SampleRate = $null, $Channels = $null, [switch]$Stream0)
    $t = New-Object System.Collections.Generic.List[string]
    $t.Add('-c:a'); $t.Add($Encoder)
    $lossless = $Encoder -in @('flac', 'alac', 'pcm_s16le', 'pcm_s24le')
    if (-not $lossless) {
        if ($Mode -eq 'Quality' -and $null -ne $VbrQuality -and $Encoder -in @('libmp3lame', 'libvorbis')) { $t.Add('-q:a'); $t.Add([string]$VbrQuality) }
        elseif ($BitrateBps) { $t.Add('-b:a'); $t.Add([string][int64]$BitrateBps) }
    }
    if ($SampleRate) { $t.Add('-ar'); $t.Add([string][int64]$SampleRate) }
    if ($Channels) { $t.Add('-ac'); $t.Add([string][int]$Channels) }
    return $t.ToArray()
}

function Get-DefaultAudioBitrate {
    param([string]$Encoder)
    switch ($Encoder) { 'libopus' { return 128000 } 'opus' { return 128000 } 'libmp3lame' { return 192000 } 'ac3' { return 384000 } default { return 192000 } }
}

function Get-TargetBitrateForSize {
    # Compatibility wrapper over the shared compression planner.
    param([double]$TargetBytes, [double]$DurationSec, [double]$AudioBps = 128000)
    $plan = Get-CompressionBitratePlan -TargetBytes ([long][math]::Floor($TargetBytes)) -DurationSec $DurationSec -AudioBps $AudioBps -MediaType Video
    return [int64]$plan.VideoBitrateBps
}

function New-OutputName {
    param([string]$SourcePath, [string]$Suffix, [string]$Extension)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $ext = $Extension; if ($ext -and -not $ext.StartsWith('.')) { $ext = '.' + $ext }
    return (Get-SafeFileStem ($stem + $(if ($Suffix) { '_' + $Suffix } else { '' }))) + $ext
}

Export-ModuleMember -Function Format-FFNumber, New-FFCommand, Add-FFInput, Add-FFOutOpt, Set-FFOutput, Get-FFTokens, Format-FFmpegCommandLine, ConvertTo-FFFilterValue, ConvertTo-FFFilterPath, Join-FFFilters, Get-AtempoChain, New-ScaleFilter, Get-VideoContainers, Get-AudioFormats, Get-VideoContainer, Get-AudioFormat, Get-AvailableVideoContainers, Get-AvailableAudioFormats, Get-EncoderProfile, Test-EncoderSupportsQuality, Get-QualityChoices, Get-VideoEncodeArgs, Get-AudioEncodeArgs, Get-DefaultAudioBitrate, Get-TargetBitrateForSize, New-OutputName
