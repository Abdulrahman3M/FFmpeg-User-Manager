# FFmpegProgress.psm1 - runs one FFmpeg stage as a child process, parses `-progress pipe:1` output,
# supports cooperative cancellation and captures stderr for the error-details view.
Set-StrictMode -Version 2.0

function ConvertFrom-ProgressTime {
    param([string]$Text)
    if ($Text -match '^(-?)(\d+):(\d+):(\d+(?:\.\d+)?)$') {
        $v = [int]$Matches[2] * 3600 + [int]$Matches[3] * 60 + [double]::Parse($Matches[4], [System.Globalization.CultureInfo]::InvariantCulture)
        if ($Matches[1] -eq '-') { return 0.0 }
        return $v
    }
    return $null
}

function Update-ProgressState {
    # Applies one key=value line of FFmpeg's progress stream to $State.
    param($State, [string]$Line)
    $i = $Line.IndexOf('=')
    if ($i -le 0) { return }
    $k = $Line.Substring(0, $i).Trim(); $v = $Line.Substring($i + 1).Trim()
    switch ($k) {
        'out_time_us' { $n = 0L; if ([int64]::TryParse($v, [ref]$n) -and $n -ge 0) { $State.OutTime = $n / 1000000.0 } }
        'out_time_ms' { }   # historically microseconds too; out_time_us/out_time are authoritative
        'out_time' { $t = ConvertFrom-ProgressTime $v; if ($null -ne $t) { $State.OutTime = $t } }
        'frame' { $n = 0L; if ([int64]::TryParse($v, [ref]$n)) { $State.Frame = $n } }
        'fps' { $d = 0.0; if ([double]::TryParse($v, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $State.Fps = $d } }
        'speed' { if ($v -match '^([\d.]+)x$') { $State.Speed = [double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture) } }
        'total_size' { $n = 0L; if ([int64]::TryParse($v, [ref]$n)) { $State.Size = $n } }
        'progress' { $State.Ended = ($v -eq 'end') }
    }
}

function Get-ProgressPercent {
    # Returns $null when the total duration is unknown (never a fake percentage).
    param($State, $TotalSec)
    if ($null -eq $TotalSec -or [double]$TotalSec -le 0) { return $null }
    $p = [math]::Floor(($State.OutTime / [double]$TotalSec) * 100)
    if ($p -lt 0) { $p = 0 }
    if ($p -gt 100) { $p = 100 }
    return [int]$p
}

function Invoke-FFmpegStage {
    <#
      Runs ffmpeg with the given argument tokens. -OnTick receives the live state and returns $true to request
      cancellation. Returns ExitCode, StdErr, Cancelled, Elapsed, State.
    #>
    param(
        [Parameter(Mandatory)][string]$FfmpegPath,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments,
        $TotalSec = $null,
        [scriptblock]$OnTick
    )
    $state = [pscustomobject]@{ OutTime = 0.0; Frame = 0L; Fps = 0.0; Speed = 0.0; Size = 0L; Ended = $false; Percent = $null; Elapsed = [TimeSpan]::Zero; TotalSec = $TotalSec }
    $res = [pscustomobject]@{ Started = $false; ExitCode = -1; StdErr = ''; Cancelled = $false; Elapsed = [TimeSpan]::Zero; State = $state; Error = '' }
    $all = @('-hide_banner', '-loglevel', 'warning', '-progress', 'pipe:1', '-nostats') + $Arguments
    $p = $null
    $lifetimeJob = [IntPtr]::Zero
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (Test-IsWindows) { $lifetimeJob = New-ProcessLifetimeJob }
        $psi = New-ProcessStartInfo -FilePath $FfmpegPath -Arguments $all -RedirectInput $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $res.Started = $true
        if ($lifetimeJob -ne [IntPtr]::Zero) { Add-ProcessToLifetimeJob -JobHandle $lifetimeJob -Process $p }
        $errTask = $p.StandardError.ReadToEndAsync()
        $lineTask = $p.StandardOutput.ReadLineAsync()
        $lastTick = [DateTime]::MinValue
        $streamDone = $false
        while (-not ($streamDone -and $p.HasExited)) {
            if (-not $streamDone) {
                if ($lineTask.IsCompleted) {
                    $line = $null
                    try { $line = $lineTask.Result } catch { $streamDone = $true }
                    if ($null -eq $line) { $streamDone = $true }
                    else { Update-ProgressState $state $line; $lineTask = $p.StandardOutput.ReadLineAsync() }
                    continue
                }
            } elseif (-not $p.HasExited) {
                [void]$p.WaitForExit(50)
            }
            $now = [DateTime]::UtcNow
            if (($now - $lastTick).TotalMilliseconds -ge 150) {
                $lastTick = $now
                $state.Elapsed = $sw.Elapsed
                $state.Percent = Get-ProgressPercent $state $TotalSec
                if ($OnTick) {
                    $cancel = $false
                    try { $cancel = [bool](& $OnTick $state) } catch { $cancel = $false }
                    if ($cancel -and -not $res.Cancelled) {
                        $res.Cancelled = $true
                        try { $p.StandardInput.WriteLine('q'); $p.StandardInput.Flush() } catch { }
                        if (-not $p.WaitForExit(4000)) { try { $p.Kill() } catch { } }
                    }
                }
            }
            if (-not $lineTask.IsCompleted -and -not $streamDone) { Start-Sleep -Milliseconds 30 }
        }
        $p.WaitForExit()
        try { $res.StdErr = $errTask.Result } catch { }
        $res.ExitCode = $p.ExitCode
    } catch {
        $res.Error = $_.Exception.Message
    } finally {
        $sw.Stop(); $res.Elapsed = $sw.Elapsed
        if ($p) { try { if (-not $p.HasExited) { $p.Kill() } } catch { }; $p.Dispose() }
        if ($lifetimeJob -ne [IntPtr]::Zero) { Close-ProcessLifetimeJob -JobHandle $lifetimeJob }
    }
    return $res
}

Export-ModuleMember -Function ConvertFrom-ProgressTime, Update-ProgressState, Get-ProgressPercent, Invoke-FFmpegStage
