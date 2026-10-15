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

function global:Expand-KeyMacros {
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
    param([scriptblock]$Action, [object[]]$Rules = @(), [string]$Default = '{Enter}', [int]$Width = 100, [int]$Height = 40, [int]$MaxCalls = 500, [System.Collections.Generic.List[string]]$Trace = $null)
    Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width $Width -Height $Height
    Clear-CapturedOutput
    $tr = $Trace
    $state = @{ Rules = @($Rules | ForEach-Object { @{ M = $_.M; K = $_.K; N = $(if ($_.ContainsKey('N')) { $_.N } else { 1000 }); Used = 0 } }); Default = $Default }
    $provider = {
        param($frame)
        $chosen = $null; $why = 'default'
        foreach ($r in $state.Rules) {
            if ($r.Used -lt $r.N -and $frame -match $r.M) { $r.Used++; $chosen = (Expand-KeyMacros $r.K $frame); $why = ('rule ' + $r.M); break }
        }
        if ($null -eq $chosen) { $chosen = (Expand-KeyMacros $state.Default $frame) }
        if ($null -ne $tr) {
            # diagnostic trace (used by tests/Repro): question text, numbered options shown, answer typed
            $opts = @(); $ctx = @()
            foreach ($ln in ($frame -split "`r?`n")) {
                if ($ln -match '^\s*(?:\S\s)?\s*(\d{2,})\s+(\S+)\s+(.+?)\s*$') { $opts += ($Matches[1] + ' ' + $Matches[3]) } elseif ($ln.Trim() -and $opts.Count -eq 0) { $ctx += $ln.Trim() }
            }
            $q = ($ctx | Select-Object -Last 2) -join ' / '
            $tr.Add(('screen: [{0}]  options: [{1}]  keys sent: [{2}]  ({3})' -f $q, ($opts -join ' | '), $chosen, $why))
        }
        return $chosen
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
    # Minimal file server on 127.0.0.1 (raw TCP) for network-stream tests. Returns @{ Url; Stop }.
    param([string]$Root, [int]$Port = 0)
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    $Port = $listener.LocalEndpoint.Port
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($listener, $root)
        $rootFull = [System.IO.Path]::GetFullPath($root)
        if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) { $rootFull += [System.IO.Path]::DirectorySeparatorChar }
        while ($true) {
            try { $client = $listener.AcceptTcpClient() } catch { break }
            $stream = $null
            try {
                $stream = $client.GetStream()
                $stream.ReadTimeout = 5000
                $requestBuffer = New-Object System.IO.MemoryStream
                $chunk = New-Object byte[] 1024
                $requestText = ''
                while ($requestBuffer.Length -lt 16384) {
                    $read = $stream.Read($chunk, 0, $chunk.Length)
                    if ($read -le 0) { break }
                    $requestBuffer.Write($chunk, 0, $read)
                    $requestText = [System.Text.Encoding]::ASCII.GetString($requestBuffer.ToArray())
                    if ($requestText.Contains("`r`n`r`n")) { break }
                }
                $requestBuffer.Dispose()
                $requestLine = ($requestText -split "`r?`n", 2)[0]
                $parts = $requestLine -split ' ', 3
                if ($parts.Count -lt 2 -or $parts[0] -notin @('GET', 'HEAD')) { throw 'Unsupported HTTP request.' }
                $rawPath = ($parts[1] -split '\?', 2)[0]
                $name = [System.Uri]::UnescapeDataString($rawPath.TrimStart('/'))
                $file = [System.IO.Path]::GetFullPath((Join-Path $rootFull $name))
                $content = New-Object byte[] 0
                $status = '404 Not Found'
                if ($file.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                    $content = [System.IO.File]::ReadAllBytes($file)
                    $status = '200 OK'
                }
                $headers = "HTTP/1.1 $status`r`nContent-Length: $($content.Length)`r`nContent-Type: application/octet-stream`r`nConnection: close`r`n`r`n"
                $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                if ($parts[0] -eq 'GET' -and $content.Length -gt 0) { $stream.Write($content, 0, $content.Length) }
                $stream.Flush()
            } catch { }
            finally { if ($stream) { $stream.Dispose() }; $client.Close() }
        }
    }).AddArgument($listener).AddArgument($Root)
    $handle = $ps.BeginInvoke()
    $stop = { try { $listener.Stop() } catch { }; try { $ps.Stop(); $ps.Dispose(); $rs.Dispose() } catch { } }.GetNewClosure()
    return [pscustomobject]@{ Url = "http://127.0.0.1:$Port"; Stop = $stop }
}
