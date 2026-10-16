# FFmpegCapabilities.psm1 - discovers what the INSTALLED FFmpeg build can do and caches it for the session.
# The installed build is the runtime source of truth; friendly presets are always checked against it.
Set-StrictMode -Version 2.0

$script:Cap = $null
$script:UsableCache = @{}

function New-EmptyCapabilities {
    return @{
        Loaded = $false; At = $null; Errors = @()
        Encoders = @{}; Decoders = @{}; Muxers = @{}; Demuxers = @{}; Filters = @{}
        ProtocolsIn = @{}; ProtocolsOut = @{}; HwAccels = @(); CodecEncoders = @{}; Path = ''
    }
}

function Get-DataLines {
    # Lines after the '------' separator FFmpeg prints below list headers.
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $start = 0
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*-{2,}\s*$') { $start = $i + 1; break } }
    return @($lines[$start..($lines.Count - 1)] | Where-Object { $_ -and $_.Trim() })
}

function ConvertFrom-FFCodecList {
    # -encoders / -decoders : ' V....D libx264   libx264 H.264 ...'
    param([string]$Text)
    $set = @{}
    foreach ($l in (Get-DataLines $Text)) {
        if ($l -match '^\s([VAS][\.FSXBD]{5})\s+(\S+)\s+(.*)$') { $set[$Matches[2]] = @{ Type = $Matches[1].Substring(0, 1); Description = $Matches[3].Trim() } }
    }
    return $set
}

function ConvertFrom-FFFormatList {
    # -muxers / -demuxers : ' E mp4   MP4 (MPEG-4 Part 14)'   (names may be comma separated for demuxers)
    param([string]$Text)
    $set = @{}
    foreach ($l in (Get-DataLines $Text)) {
        if ($l -match '^\s*([DE\.]{1,2})\s+(\S+)\s+(.*)$') {
            foreach ($n in ($Matches[2] -split ',')) { if ($n) { $set[$n] = @{ Description = $Matches[3].Trim() } } }
        }
    }
    return $set
}

function ConvertFrom-FFFilterList {
    # ' T.C acrossfade       AA->A      Cross fade two input audio streams.'   (FFmpeg up to 8: three flag columns)
    # ' TS afftdn            A->A       Denoise audio samples using FFT.'      (FFmpeg 9: two flag columns)
    param([string]$Text)
    $set = @{}
    foreach ($l in (Get-DataLines $Text)) {
        if ($l -match '^\s([T\.][S\.][C\.]?)\s+(\S+)\s+(\S+)\s+(.*)$') { $set[$Matches[2]] = @{ Io = $Matches[3]; Description = $Matches[4].Trim() } }
    }
    return $set
}

function ConvertFrom-FFProtocolList {
    param([string]$Text)
    $in = @{}; $out = @{}; $mode = ''
    foreach ($l in ($Text -split "`r?`n")) {
        if ($l -match '^\s*Input:') { $mode = 'in'; continue }
        if ($l -match '^\s*Output:') { $mode = 'out'; continue }
        if ($l -match '^\s+(\S+)\s*$') {
            if ($mode -eq 'in') { $in[$Matches[1]] = $true } elseif ($mode -eq 'out') { $out[$Matches[1]] = $true }
        }
    }
    return @{ In = $in; Out = $out }
}

function ConvertFrom-FFHwAccelList {
    param([string]$Text)
    $names = @()
    $seen = $false
    foreach ($l in ($Text -split "`r?`n")) {
        if ($l -match 'Hardware acceleration methods') { $seen = $true; continue }
        if ($seen -and $l -match '^\s*(\S+)\s*$') { $names += $Matches[1] }
    }
    return $names
}

function ConvertFrom-FFCodecsList {
    # ' DEV.LS h264  H.264 ... (decoders: h264 ...) (encoders: libx264 libx264rgb ...)'
    param([string]$Text)
    $map = @{}
    foreach ($l in (Get-DataLines $Text)) {
        if ($l -match '^\s([D\.][E\.][VASDT\.][I\.][L\.][S\.])\s+(\S+)\s+(.*)$') {
            $name = $Matches[2]; $desc = $Matches[3]
            if ($desc -match '\(encoders:\s*([^)]+)\)') { $map[$name] = @($Matches[1].Trim() -split '\s+') }
            elseif ($Matches[1][1] -eq 'E') { $map[$name] = @($name) }
        }
    }
    return $map
}

function Invoke-FFQuery {
    param([string]$What, [string]$FfmpegPath = '')
    $ff = $FfmpegPath
    if (-not $ff) { $ff = Get-FFmpegPath }
    $r = Invoke-ExternalCapture -FilePath $ff -Arguments @('-hide_banner', $What) -TimeoutSec 60
    if (-not $r.Started -or $r.ExitCode -ne 0) { return @{ Ok = $false; Text = ''; Error = "ffmpeg $What failed" } }
    return @{ Ok = $true; Text = $r.StdOut; Error = '' }
}

function Initialize-FFCapabilities {
    param([switch]$Force, [scriptblock]$OnProgress, [string]$FfmpegPath = '')
    if ($script:Cap -and $script:Cap.Loaded -and -not $Force -and -not $FfmpegPath) { return $script:Cap }
    $c = New-EmptyCapabilities
    $script:UsableCache = @{}
    $queryPath = $FfmpegPath
    if (-not $queryPath) { $queryPath = Get-FFmpegPath }
    $c.Path = $queryPath
    $jobs = @('-encoders', '-decoders', '-muxers', '-demuxers', '-filters', '-protocols', '-hwaccels', '-codecs')
    $n = 0
    foreach ($q in $jobs) {
        $n++
        if ($OnProgress) { & $OnProgress $q $n $jobs.Count }
        $r = Invoke-FFQuery -What $q -FfmpegPath $queryPath
        if (-not $r.Ok) { $c.Errors += $r.Error; continue }
        switch ($q) {
            '-encoders' { $c.Encoders = ConvertFrom-FFCodecList $r.Text }
            '-decoders' { $c.Decoders = ConvertFrom-FFCodecList $r.Text }
            '-muxers' { $c.Muxers = ConvertFrom-FFFormatList $r.Text }
            '-demuxers' { $c.Demuxers = ConvertFrom-FFFormatList $r.Text }
            '-filters' { $c.Filters = ConvertFrom-FFFilterList $r.Text }
            '-protocols' { $p = ConvertFrom-FFProtocolList $r.Text; $c.ProtocolsIn = $p.In; $c.ProtocolsOut = $p.Out }
            '-hwaccels' { $c.HwAccels = @(ConvertFrom-FFHwAccelList $r.Text) }
            '-codecs' { $c.CodecEncoders = ConvertFrom-FFCodecsList $r.Text }
        }
    }
    $c.Loaded = ($c.Encoders.Count -gt 0)
    $c.At = Get-Date
    if (-not $FfmpegPath) { $script:Cap = $c }
    return $c
}

function Set-FFCapabilityData {
    # Test seam: install a synthetic capability set.
    param([string[]]$Encoders = @(), [string[]]$Muxers = @(), [string[]]$Filters = @(), [string[]]$Protocols = @(), [string[]]$HwAccels = @())
    $c = New-EmptyCapabilities
    $currentPath = Get-FFmpegPath
    if ($currentPath) { try { $c.Path = [System.IO.Path]::GetFullPath($currentPath) } catch { $c.Path = $currentPath } }
    foreach ($e in $Encoders) { $c.Encoders[$e] = @{ Type = 'V'; Description = $e } }
    foreach ($m in $Muxers) { $c.Muxers[$m] = @{ Description = $m } }
    foreach ($f in $Filters) { $c.Filters[$f] = @{ Io = 'V->V'; Description = $f } }
    foreach ($p in $Protocols) { $c.ProtocolsIn[$p] = $true }
    $c.HwAccels = $HwAccels
    $c.Loaded = $true; $c.At = Get-Date
    $script:Cap = $c
    $script:UsableCache = @{}
}

function Get-FFCapabilities {
    if (-not $script:Cap -or -not $script:Cap.Loaded) { [void](Initialize-FFCapabilities) }
    return $script:Cap
}

function Get-FFCapabilityStatus {
    if (-not $script:Cap -or -not $script:Cap.Loaded) { return [pscustomobject]@{ Loaded = $false; At = $null; Encoders = 0; Decoders = 0; Muxers = 0; Demuxers = 0; Filters = 0; Protocols = 0; HwAccels = @() } }
    $c = $script:Cap
    return [pscustomobject]@{ Loaded = $true; At = $c.At; Encoders = $c.Encoders.Count; Decoders = $c.Decoders.Count; Muxers = $c.Muxers.Count; Demuxers = $c.Demuxers.Count; Filters = $c.Filters.Count; Protocols = $c.ProtocolsIn.Count; HwAccels = @($c.HwAccels) }
}

function Test-FFEncoder { param([string]$Name) return (Get-FFCapabilities).Encoders.ContainsKey($Name) }
function Test-FFDecoder { param([string]$Name) return (Get-FFCapabilities).Decoders.ContainsKey($Name) }
function Test-FFMuxer { param([string]$Name) return (Get-FFCapabilities).Muxers.ContainsKey($Name) }
function Test-FFDemuxer { param([string]$Name) return (Get-FFCapabilities).Demuxers.ContainsKey($Name) }
function Test-FFFilter { param([string]$Name) return (Get-FFCapabilities).Filters.ContainsKey($Name) }
function Test-FFHwAccel { param([string]$Name) return ((Get-FFCapabilities).HwAccels -contains $Name) }
function Test-FFProtocol {
    param([string]$Name, [ValidateSet('Input', 'Output')][string]$Direction = 'Input')
    $c = Get-FFCapabilities
    if ($Direction -eq 'Input') { return $c.ProtocolsIn.ContainsKey($Name) }
    return $c.ProtocolsOut.ContainsKey($Name)
}
function Get-FFHwAccels { return @((Get-FFCapabilities).HwAccels) }

function Test-FFAllFilters {
    param([string[]]$Names)
    foreach ($n in $Names) { if (-not (Test-FFFilter $n)) { return $false } }
    return $true
}

function Get-FFFilterList {
    $f = (Get-FFCapabilities).Filters
    return @($f.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ Name = $_; Io = $f[$_].Io; Description = $f[$_].Description } })
}

function Test-FFEncoderUsable {
    # Hardware encoders can be compiled in yet unusable (no GPU/driver). Try a tiny encode once per session.
    param([string]$Name)
    if ($script:UsableCache.ContainsKey($Name)) { return $script:UsableCache[$Name] }
    $ok = $false
    if (Test-FFEncoder $Name) {
        if ($Name -notmatch '_(nvenc|qsv|amf|videotoolbox|vaapi|mf|v4l2m2m|vulkan)$') { $ok = $true }
        else {
            $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=black:s=256x256:d=0.1:r=10', '-frames:v', '1', '-c:v', $Name, '-f', 'null', '-') -TimeoutSec 15
            $ok = ($r.Started -and $r.ExitCode -eq 0 -and -not $r.TimedOut)
        }
    }
    $script:UsableCache[$Name] = $ok
    return $ok
}

# ---- friendly presets, always validated against the installed build ----------

$script:VideoCodecFamilies = @(
    @{ Id = 'h264'; Label = 'H.264 / AVC'; Desc = 'Most compatible. Works almost everywhere.'; Sw = @('libx264', 'libopenh264'); Hw = @('h264_nvenc', 'h264_qsv', 'h264_amf', 'h264_videotoolbox', 'h264_mf') },
    @{ Id = 'hevc'; Label = 'H.265 / HEVC'; Desc = 'Smaller files than H.264; less universal playback.'; Sw = @('libx265'); Hw = @('hevc_nvenc', 'hevc_qsv', 'hevc_amf', 'hevc_videotoolbox', 'hevc_mf') },
    @{ Id = 'av1'; Label = 'AV1'; Desc = 'Very efficient; slow to encode, newer players only.'; Sw = @('libsvtav1', 'libaom-av1', 'librav1e'); Hw = @('av1_nvenc', 'av1_qsv', 'av1_amf') },
    @{ Id = 'vp9'; Label = 'VP9'; Desc = 'Open codec, good for WebM and the web.'; Sw = @('libvpx-vp9'); Hw = @('vp9_qsv') },
    @{ Id = 'vp8'; Label = 'VP8'; Desc = 'Older open codec for WebM.'; Sw = @('libvpx'); Hw = @() },
    @{ Id = 'mpeg4'; Label = 'MPEG-4 Part 2'; Desc = 'Legacy codec, widely playable in AVI/MP4.'; Sw = @('mpeg4'); Hw = @() },
    @{ Id = 'prores'; Label = 'Apple ProRes'; Desc = 'Editing-grade intermediate codec (large files).'; Sw = @('prores_ks', 'prores'); Hw = @() }
)

$script:AudioCodecFamilies = @(
    @{ Id = 'aac'; Label = 'AAC'; Desc = 'Best all-round choice for MP4/M4A.'; Enc = @('aac', 'libfdk_aac'); Lossless = $false },
    @{ Id = 'mp3'; Label = 'MP3'; Desc = 'Universal compatibility.'; Enc = @('libmp3lame', 'libshine'); Lossless = $false },
    @{ Id = 'opus'; Label = 'Opus'; Desc = 'Best quality at low bitrates.'; Enc = @('libopus', 'opus'); Lossless = $false },
    @{ Id = 'vorbis'; Label = 'Vorbis (OGG)'; Desc = 'Open lossy codec.'; Enc = @('libvorbis', 'vorbis'); Lossless = $false },
    @{ Id = 'flac'; Label = 'FLAC'; Desc = 'Lossless compression.'; Enc = @('flac'); Lossless = $true },
    @{ Id = 'alac'; Label = 'ALAC'; Desc = 'Apple lossless compression.'; Enc = @('alac'); Lossless = $true },
    @{ Id = 'ac3'; Label = 'AC-3 (Dolby Digital)'; Desc = 'Surround-sound compatible codec.'; Enc = @('ac3', 'ac3_fixed'); Lossless = $false },
    @{ Id = 'pcm'; Label = 'PCM (WAV, uncompressed)'; Desc = 'Uncompressed audio.'; Enc = @('pcm_s16le'); Lossless = $true }
)

function Get-VideoCodecFamilies { return $script:VideoCodecFamilies }
function Get-AudioCodecFamilies { return $script:AudioCodecFamilies }

function Get-VideoEncoderChoices {
    <# Returns available video codec choices: @{ Id; Label; Desc; Encoder; Hardware; Family }.
       -AllowedFamilies restricts to a container's compatible codecs. Hardware encoders are listed
       only when a real test encode succeeds. #>
    param([string[]]$AllowedFamilies = @(), [switch]$IncludeHardware)
    $out = @()
    # When a container restricts the families, honor the container's own preference order (first = recommended).
    $ordered = @($script:VideoCodecFamilies)
    if ($AllowedFamilies.Count -gt 0) {
        $ordered = @()
        foreach ($id in $AllowedFamilies) { foreach ($fam in $script:VideoCodecFamilies) { if ($fam.Id -eq $id) { $ordered += , $fam } } }
    }
    foreach ($fam in $ordered) {
        foreach ($e in $fam.Sw) {
            if (Test-FFEncoder $e) { $out += , @{ Id = $fam.Id; Label = $fam.Label; Desc = $fam.Desc; Encoder = $e; Hardware = $false; Family = $fam.Id; Value = $e }; break }
        }
        if ($IncludeHardware) {
            foreach ($e in $fam.Hw) {
                if ((Test-FFEncoder $e) -and (Test-FFEncoderUsable $e)) { $out += , @{ Id = $fam.Id + ':hw'; Label = $fam.Label + ' (hardware: ' + $e + ')'; Desc = 'GPU-accelerated encode; faster, usually larger files.'; Encoder = $e; Hardware = $true; Family = $fam.Id; Value = $e } }
            }
        }
    }
    return $out
}

function Get-AudioEncoderChoices {
    param([string[]]$AllowedFamilies = @())
    $out = @()
    $ordered = @($script:AudioCodecFamilies)
    if ($AllowedFamilies.Count -gt 0) {
        $ordered = @()
        foreach ($id in $AllowedFamilies) { foreach ($fam in $script:AudioCodecFamilies) { if ($fam.Id -eq $id) { $ordered += , $fam } } }
    }
    foreach ($fam in $ordered) {
        foreach ($e in $fam.Enc) {
            if (Test-FFEncoder $e) { $out += , @{ Id = $fam.Id; Label = $fam.Label; Desc = $fam.Desc; Encoder = $e; Lossless = $fam.Lossless; Value = $e }; break }
        }
    }
    return $out
}

Export-ModuleMember -Function ConvertFrom-FFCodecList, ConvertFrom-FFFormatList, ConvertFrom-FFFilterList, ConvertFrom-FFProtocolList, ConvertFrom-FFHwAccelList, ConvertFrom-FFCodecsList, Initialize-FFCapabilities, Set-FFCapabilityData, Get-FFCapabilities, Get-FFCapabilityStatus, Test-FFEncoder, Test-FFDecoder, Test-FFMuxer, Test-FFDemuxer, Test-FFFilter, Test-FFHwAccel, Test-FFProtocol, Get-FFHwAccels, Test-FFAllFilters, Get-FFFilterList, Test-FFEncoderUsable, Get-VideoCodecFamilies, Get-AudioCodecFamilies, Get-VideoEncoderChoices, Get-AudioEncoderChoices
