# Validation.psm1 - validated parsing of free-form answers. Every function returns
# [pscustomobject]@{ Ok; Value; Error } and never throws for user mistakes.
Set-StrictMode -Version 2.0

function New-ValidationResult {
    param([bool]$Ok, $Value = $null, [string]$Error = '')
    return [pscustomobject]@{ Ok = $Ok; Value = $Value; Error = $Error }
}

function ConvertFrom-TimestampText {
    # Accepts: 90 | 90.5 | 1:30 | 01:02:03 | 01:02:03.250 | 1h2m3s | 2m30s | 45s
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return New-ValidationResult $false $null 'Enter a time such as 90, 1:30 or 00:01:30.5.' }
    $t = $Text.Trim()
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $num = [System.Globalization.NumberStyles]::Float
    $hasUnit = ($t.IndexOfAny([char[]]@('h', 'm', 's')) -ge 0)   # test first: a second -match would overwrite $Matches
    if ($hasUnit -and $t -match '^(?:(?<h>\d+)h)?(?:(?<m>\d+)m)?(?:(?<s>\d+(?:\.\d+)?)s)?$') {
        $h = 0; $m = 0; $s = 0.0
        if ($Matches['h']) { $h = [int]$Matches['h'] }
        if ($Matches['m']) { $m = [int]$Matches['m'] }
        if ($Matches['s']) { $s = [double]::Parse($Matches['s'], $inv) }
        return New-ValidationResult $true ($h * 3600 + $m * 60 + $s)
    }
    if ($t -match '^\d+(?:[.,]\d+)?$') {
        return New-ValidationResult $true ([double]::Parse($t.Replace(',', '.'), $inv))
    }
    if ($t -match '^(?:(?<h>\d+):)?(?<m>\d{1,2}):(?<s>\d{1,2}(?:[.,]\d+)?)$') {
        $h = 0; if ($Matches['h']) { $h = [int]$Matches['h'] }
        $m = [int]$Matches['m']
        $s = [double]::Parse($Matches['s'].Replace(',', '.'), $inv)
        if ($m -ge 60 -or $s -ge 60) { return New-ValidationResult $false $null 'Minutes and seconds must be below 60 (example: 01:30).' }
        return New-ValidationResult $true ($h * 3600 + $m * 60 + $s)
    }
    return New-ValidationResult $false $null 'Not a valid time. Use seconds (90), MM:SS (1:30) or HH:MM:SS (00:01:30.5).'
}

function ConvertTo-TimestampText {
    param([double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $ms = [math]::Round(($Seconds - [math]::Floor($Seconds)) * 1000)
    $whole = [int64][math]::Floor($Seconds)
    if ($ms -ge 1000) { $whole++; $ms = 0 }
    $h = [int][math]::Floor($whole / 3600); $m = [int][math]::Floor(($whole % 3600) / 60); $s = [int]($whole % 60)
    return ('{0:00}:{1:00}:{2:00}.{3:000}' -f $h, $m, $s, [int]$ms)
}

function ConvertFrom-IntegerText {
    param([string]$Text, $Min = $null, $Max = $null, [string]$Label = 'Value')
    $t = ([string]$Text).Trim()
    if ($t -notmatch '^[+-]?\d+$') { return New-ValidationResult $false $null "$Label must be a whole number (example: 1280)." }
    $v = 0L
    if (-not [int64]::TryParse($t, [ref]$v)) { return New-ValidationResult $false $null "$Label is out of range." }
    if ($null -ne $Min -and $v -lt $Min) { return New-ValidationResult $false $null "$Label must be at least $Min." }
    if ($null -ne $Max -and $v -gt $Max) { return New-ValidationResult $false $null "$Label must be at most $Max." }
    return New-ValidationResult $true $v
}

function ConvertFrom-DecimalText {
    param([string]$Text, $Min = $null, $Max = $null, [string]$Label = 'Value')
    $t = ([string]$Text).Trim().Replace(',', '.')
    if ($t.EndsWith('x') -or $t.EndsWith('X')) { $t = $t.Substring(0, $t.Length - 1) }
    if ($t -notmatch '^[+-]?(\d+(\.\d*)?|\.\d+)$') { return New-ValidationResult $false $null "$Label must be a number (example: 1.5)." }
    $v = [double]::Parse($t, [System.Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $Min -and $v -lt $Min) { return New-ValidationResult $false $null "$Label must be at least $Min." }
    if ($null -ne $Max -and $v -gt $Max) { return New-ValidationResult $false $null "$Label must be at most $Max." }
    return New-ValidationResult $true $v
}

function ConvertFrom-BitrateText {
    # 128k | 2500k | 4M | 192000 -> integer bits/second
    param([string]$Text, [string]$Label = 'Bitrate')
    $t = ([string]$Text).Trim().ToLowerInvariant().Replace('bps', '').Replace('/s', '')
    if ($t -match '^(\d+(?:\.\d+)?)\s*([km]?)$') {
        $n = [double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        switch ($Matches[2]) { 'k' { $n *= 1000 } 'm' { $n *= 1000000 } }
        if ($n -lt 8000) { if ($Matches[2] -eq '') { return New-ValidationResult $false $null "$Label is too low. Try 128k or 2500k." } }
        if ($n -lt 1000) { return New-ValidationResult $false $null "$Label is too low. Try 128k or 2500k." }
        return New-ValidationResult $true ([int64][math]::Round($n))
    }
    return New-ValidationResult $false $null "$Label must look like 128k, 2500k or 4M."
}

function Format-Bitrate {
    param([int64]$BitsPerSecond)
    if ($BitsPerSecond -ge 1000000 -and ($BitsPerSecond % 100000) -eq 0) { return ('{0:0.#}M' -f ($BitsPerSecond / 1e6)) }
    return ('{0}k' -f [int][math]::Round($BitsPerSecond / 1000))
}

function ConvertFrom-FrameRateText {
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if ($t -match '^(\d+)/(\d+)$') {
        $d = [double]$Matches[2]; if ($d -le 0) { return New-ValidationResult $false $null 'Invalid frame rate.' }
        $v = [double]$Matches[1] / $d
    } else {
        $r = ConvertFrom-DecimalText $t 0.1 240 'Frame rate'
        if (-not $r.Ok) { return $r }
        $v = $r.Value
    }
    if ($v -lt 0.1 -or $v -gt 240) { return New-ValidationResult $false $null 'Frame rate must be between 0.1 and 240 FPS.' }
    return New-ValidationResult $true $v
}

function ConvertFrom-ColorText {
    # Named colors (letters only) or #RRGGBB / 0xRRGGBB; returns FFmpeg-compatible string.
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if ($t -match '^#([0-9a-fA-F]{6})$') { return New-ValidationResult $true ('0x' + $Matches[1].ToUpperInvariant()) }
    if ($t -match '^0x([0-9a-fA-F]{6})$') { return New-ValidationResult $true ('0x' + $Matches[1].ToUpperInvariant()) }
    if ($t -match '^[a-zA-Z]{3,20}$') { return New-ValidationResult $true $t.ToLowerInvariant() }
    return New-ValidationResult $false $null 'Use a color name (white, yellow) or hex such as #FFCC00.'
}

Export-ModuleMember -Function New-ValidationResult, ConvertFrom-TimestampText, ConvertTo-TimestampText, ConvertFrom-IntegerText, ConvertFrom-DecimalText, ConvertFrom-BitrateText, Format-Bitrate, ConvertFrom-FrameRateText, ConvertFrom-ColorText
