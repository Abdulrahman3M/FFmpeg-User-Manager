# TestHelpers.ps1 - tiny dependency-free test framework (works on Windows PowerShell 5.1 and PowerShell 7.x).
Set-StrictMode -Version 2.0

$script:Results = New-Object System.Collections.Generic.List[object]
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Work = $null
$script:Group = ''

function Get-TestRoot { return $script:Root }
function Get-TestWork { return $script:Work }

function Initialize-TestEnvironment {
    param([switch]$SkipCapabilities)
    . (Join-Path (Join-Path $script:Root 'src') 'Import-Modules.ps1')
    Import-FFTuiModules -Root $script:Root
    Set-AppRoot $script:Root
    $env:FFTUI_NO_PICKER = '1'
    $env:FFTUI_SKIP_UPDATE = '1'
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('fftui-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $script:Work -Force)
    Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 40
    $d = Find-FFmpegInstallation
    if ($d.Status -ne 'Ready') { throw "FFmpeg is required for the tests: $($d.Status)" }
    if (-not $SkipCapabilities) { $null = Initialize-FFCapabilities -Force }
}

function Remove-TestEnvironment {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work) -and $script:Work.Contains('fftui-tests-')) { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
}

function Set-TestGroup { param([string]$Name) $script:Group = $Name; Write-Host ("`n== $Name") -ForegroundColor Cyan }

function Add-TestResult {
    param([string]$Name, [ValidateSet('PASS', 'FAIL', 'UNVERIFIED')][string]$Status, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Group = $script:Group; Name = $Name; Status = $Status; Detail = $Detail })
    $color = @{ PASS = 'Green'; FAIL = 'Red'; UNVERIFIED = 'Yellow' }[$Status]
    Write-Host ("  [{0}] {1}" -f $Status, $Name) -ForegroundColor $color
    if ($Status -ne 'PASS' -and $Detail) { Write-Host ("        " + ($Detail -replace "`n", "`n        ")) -ForegroundColor DarkGray }
}

function Assert-True {
    param([string]$Name, $Condition, [string]$Detail = '')
    if ($Condition) { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' $Detail }
}

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ("$Expected" -ceq "$Actual") { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' "expected [$Expected] but got [$Actual]" }
}

function Assert-Contains {
    param([string]$Name, [string]$Text, [string]$Needle)
    if ($Text.Contains($Needle)) { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' "output does not contain [$Needle]" }
}

function Assert-NotContains {
    param([string]$Name, [string]$Text, [string]$Needle)
    if (-not $Text.Contains($Needle)) { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' "output unexpectedly contains [$Needle]" }
}

function Skip-Test { param([string]$Name, [string]$Reason) Add-TestResult $Name 'UNVERIFIED' $Reason }

function Get-TestResults { return $script:Results.ToArray() }

function Invoke-Ui {
    # Runs a scriptblock with scripted keys in the buffered renderer. Returns @{ Output; Error; Remaining }.
    param([scriptblock]$Action, [string]$Keys, [int]$Width = 100, [int]$Height = 40, $Unicode = $true)
    Initialize-Renderer -Ansi $false -Unicode $Unicode -Sink Buffer -Width $Width -Height $Height
    Clear-CapturedOutput
    Set-TuiScriptedInput $Keys
    $err = ''
    $val = $null
    try { $val = & $Action } catch { $err = $_.Exception.Message + "`n" + $_.ScriptStackTrace }
    $rem = Get-TuiScriptedRemaining
    $out = Get-CapturedOutput
    Clear-TuiScriptedInput
    return [pscustomobject]@{ Output = $out; Error = $err; Remaining = $rem; Value = $val }
}

function Get-LastFrame {
    param([string]$Output)
    $parts = $Output -split '=====(?:FRAME|CLEAR)====='
    return $parts[$parts.Count - 1]
}

function New-Fixture {
    # Generates a small media fixture with ffmpeg (lavfi). Returns the full path.
    param([string]$Name, [string[]]$FfArgs, [string]$Dir)
    if (-not $Dir) { $Dir = $script:Work }
    if (-not (Test-Path -LiteralPath $Dir)) { [void](New-Item -ItemType Directory -Path $Dir -Force) }
    $p = Join-Path $Dir $Name
    $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments (@('-y', '-hide_banner', '-loglevel', 'error') + $FfArgs + @($p)) -TimeoutSec 120
    if ($r.ExitCode -ne 0) { throw "Fixture '$Name' failed: $($r.StdErr)" }
    return $p
}

function Get-ProbeJson {
    param([string]$Path)
    $r = Invoke-ExternalCapture -FilePath (Get-FFprobePath) -Arguments @('-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', '-i', $Path) -TimeoutSec 60
    if ($r.ExitCode -ne 0) { return $null }
    return ($r.StdOut | ConvertFrom-Json)
}

function Get-StreamOf {
    param($Json, [string]$Type)
    return ,@($Json.streams | Where-Object { $_.codec_type -eq $Type })
}

function Test-ValidMediaFile {
    param([string]$Path, [string]$Type = '')
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $j = Get-ProbeJson $Path
    if (-not $j) { return $false }
    if ($Type) { return ((Get-StreamOf $j $Type).Count -gt 0) }
    return $true
}

function Expand-KeyMacros {
    <#
      Test-only key macros resolved against the screen that is currently displayed:
        {#LAST}    number of the last numbered option on screen (for example the Custom... entry or Continue)
        {#label}   number of the first numbered option whose text contains "label" (case-insensitive)
      Options are shown as "NN icon label"; the macro types their number, exactly like a user would.
    #>
    param([string]$Keys, [string]$Frame)
    if ($Keys -notmatch '\{#') { return $Keys }
    $items = @()
    foreach ($line in ($Frame -split "`r?`n")) {
        $m = [regex]::Match($line, '^\s*(?:\S\s)?\s*(\d{2,})\s+(\S+)\s+(.+?)\s*$')
        if ($m.Success) { $items += , @{ Num = $m.Groups[1].Value; Text = $m.Groups[3].Value } }
    }
    return ([regex]::Replace($Keys, '\{#([^}]+)\}', {
        param($mm)
        $label = $mm.Groups[1].Value
        if ($label -eq 'LAST') { $hm = [regex]::Match($Frame, '(\d{2,})-(\d{2,}) Type a number'); if ($hm.Success) { return $hm.Groups[2].Value }; if ($items.Count -gt 0) { return $items[$items.Count - 1].Num } else { return '<<NO-OPTIONS>>' } }
        foreach ($it in $items) { if ($it.Text.IndexOf($label, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $it.Num } }
        return ('<<NO-OPTION:' + $label + '>>')
    }.GetNewClosure()))
}

function Invoke-Flow {
    <#
      Drives a workflow with rules: each rule is @{ M = 'regex matched against the current screen'; K = 'keys'; N = max uses }.
      The first matching rule with uses left supplies the keys; otherwise Enter (accept the default) is pressed.
    #>
    param([scriptblock]$Action, [object[]]$Rules = @(), [string]$Default = '{Enter}', [int]$Width = 100, [int]$Height = 40, [int]$MaxCalls = 500)
    Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width $Width -Height $Height
    Clear-CapturedOutput
    $state = @{ Rules = @($Rules | ForEach-Object { @{ M = $_.M; K = $_.K; N = $(if ($_.ContainsKey('N')) { $_.N } else { 1000 }); Used = 0 } }); Default = $Default }
    $provider = {
        param($frame)
        foreach ($r in $state.Rules) {
            if ($r.Used -lt $r.N -and $frame -match $r.M) { $r.Used++; return (Expand-KeyMacros $r.K $frame) }
        }
        return (Expand-KeyMacros $state.Default $frame)
    }.GetNewClosure()
    Set-TuiScriptedProvider $provider -MaxCalls $MaxCalls
    $err = ''; $val = $null
    try { $val = & $Action } catch { $err = $_.Exception.Message + "`n" + $_.ScriptStackTrace }
    $out = Get-CapturedOutput
    Clear-TuiScriptedInput
    return [pscustomobject]@{ Output = $out; Error = $err; Remaining = 0; Value = $val }
}

function New-FileListRules {
    <#
      Rules that fill a "Files" step: type each path at the text prompt, choose "Add another file" until the last file
      is listed, then choose "Done". Returns an array of rules (concatenate it with other rules using +).
    #>
    param([string]$Prompt, [string[]]$Files)
    $rules = @()
    $esc = [regex]::Escape($Prompt)
    foreach ($f in $Files) { $rules += @{ M = "(?s)\A(?!.*Add another file).*$esc"; K = "$f{Enter}"; N = 1 } }
    $last = [regex]::Escape([System.IO.Path]::GetFileName($Files[$Files.Count - 1]))
    $rules += @{ M = "(?s)$last.*Add another file|Add another file.*$last"; K = '{#Done}'; N = 1000 }
    $rules += @{ M = 'Add another file'; K = '{#Add another}'; N = 1000 }
    return $rules
}

function New-Rule { param([string]$Prompt, [string]$Keys, [int]$Times = 1000) return @{ M = ('(?m)^' + [regex]::Escape($Prompt) + '\s*$'); K = $Keys; N = $Times } }
function New-ScreenRule { param([string]$Pattern, [string]$Keys, [int]$Times = 1000) return @{ M = $Pattern; K = $Keys; N = $Times } }

function Get-FlatText {
    # Collapses wrapped lines so phrases can be matched regardless of terminal wrapping.
    param([string]$Text)
    return (($Text -replace '\s+', ' '))
}

function Invoke-FfLog {
    param([string[]]$FfArgs, [int]$Timeout = 120)
    $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments (@('-hide_banner', '-nostdin') + $FfArgs) -TimeoutSec $Timeout
    return ($r.StdErr + "`n" + $r.StdOut)
}

function Get-MeanVolume {
    param([string]$Path)
    $t = Invoke-FfLog @('-i', $Path, '-vn', '-af', 'volumedetect', '-f', 'null', '-')
    $m = [regex]::Match($t, 'mean_volume:\s*(-?[\d.]+) dB')
    if ($m.Success) { return [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) }
    return $null
}

function Get-IntegratedLoudness {
    param([string]$Path)
    $t = Invoke-FfLog @('-i', $Path, '-vn', '-af', 'ebur128', '-f', 'null', '-')
    $ms = [regex]::Matches($t, 'I:\s+(-?[\d.]+) LUFS')
    if ($ms.Count -gt 0) { return [double]::Parse($ms[$ms.Count - 1].Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) }
    return $null
}

function Get-VideoStat {
    # Average of a signalstats key (YAVG, SATAVG) over the whole video.
    param([string]$Path, [string]$Key = 'YAVG')
    $t = Invoke-FfLog @('-loglevel', 'info', '-i', $Path, '-an', '-vf', "signalstats,metadata=mode=print:key=lavfi.signalstats.$Key", '-f', 'null', '-')
    $vals = @([regex]::Matches($t, "lavfi\.signalstats\.$Key=([\d.]+)") | ForEach-Object { [double]::Parse($_.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) })
    if ($vals.Count -eq 0) { return $null }
    return (($vals | Measure-Object -Average).Average)
}

function Get-Psnr {
    # Average PSNR between two videos (first frame compare); 'inf' becomes 100.
    param([string]$A, [string]$B)
    $t = Invoke-FfLog @('-i', $A, '-i', $B, '-lavfi', '[0:v][1:v]scale2ref[a][b];[a][b]psnr', '-frames:v', '3', '-f', 'null', '-')
    $m = [regex]::Match($t, 'average:(inf|[\d.]+)')
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Value -eq 'inf') { return 100.0 }
    return [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Start-TestHttpServer {
    # Minimal file server on 127.0.0.1 (HttpListener) for network-stream tests. Returns @{ Url; Stop }.
    param([string]$Root, [int]$Port = 0)
    if ($Port -eq 0) { $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0); $l.Start(); $Port = $l.LocalEndpoint.Port; $l.Stop() }
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($listener, $root)
        while ($listener.IsListening) {
            try { $ctx = $listener.GetContext() } catch { break }
            try {
                $name = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
                $file = Join-Path $root $name
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    $bytes = [System.IO.File]::ReadAllBytes($file)
                    $ctx.Response.ContentLength64 = $bytes.Length
                    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else { $ctx.Response.StatusCode = 404 }
            } catch { }
            try { $ctx.Response.OutputStream.Close() } catch { }
        }
    }).AddArgument($listener).AddArgument($Root)
    $handle = $ps.BeginInvoke()
    $stop = { try { $listener.Stop(); $listener.Close() } catch { }; try { $ps.Stop(); $ps.Dispose(); $rs.Dispose() } catch { } }.GetNewClosure()
    return [pscustomobject]@{ Url = "http://127.0.0.1:$Port"; Stop = $stop }
}
