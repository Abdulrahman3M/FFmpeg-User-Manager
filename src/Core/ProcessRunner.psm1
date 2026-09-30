# ProcessRunner.psm1 - safe external process execution. Arguments are always passed as a structured
# array and quoted per the Windows CommandLineToArgvW rules; nothing is ever evaluated by PowerShell.
Set-StrictMode -Version 2.0

function ConvertTo-ProcessArgument {
    param([AllowEmptyString()][string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument.IndexOfAny([char[]]@(' ', "`t", "`n", "`v", '"')) -lt 0) { return $Argument }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') {
            [void]$sb.Append('\', ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue
        }
        if ($bs -gt 0) { [void]$sb.Append('\', $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append('\', ($bs * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)
    if (-not $Arguments) { return '' }
    return (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
}

function New-ProcessStartInfo {
    param([string]$FilePath, [string[]]$Arguments, [bool]$RedirectInput = $false)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ConvertTo-ProcessArgumentString $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $RedirectInput
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    return $psi
}

function Invoke-ExternalCapture {
    # Runs a program to completion capturing stdout/stderr. Returns ExitCode/StdOut/StdErr/TimedOut/Started.
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [int]$TimeoutSec = 60)
    $res = [pscustomobject]@{ Started = $false; ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $false; Error = '' }
    $p = $null
    try {
        $psi = New-ProcessStartInfo -FilePath $FilePath -Arguments $Arguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $res.Started = $true
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            $res.TimedOut = $true
            try { $p.Kill() } catch { }
            [void]$p.WaitForExit(2000)
        } else {
            $p.WaitForExit()
        }
        try { $res.StdOut = $outTask.Result } catch { }
        try { $res.StdErr = $errTask.Result } catch { }
        if ($p.HasExited) { $res.ExitCode = $p.ExitCode }
    } catch {
        $res.Error = $_.Exception.Message
    } finally {
        if ($p) { $p.Dispose() }
    }
    return $res
}

function Invoke-ExternalStreaming {
    # Like Invoke-ExternalCapture but reports the latest output line to -OnTick (used for winget install/update).
    # -OnTick receives (elapsedSeconds, lastLine) and returns $true to cancel.
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [int]$TimeoutSec = 1800, [scriptblock]$OnTick)
    $res = [pscustomobject]@{ Started = $false; ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' }
    $p = $null
    $all = New-Object System.Text.StringBuilder
    $last = ''
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = New-ProcessStartInfo -FilePath $FilePath -Arguments $Arguments -RedirectInput $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $res.Started = $true
        try { $p.StandardInput.Close() } catch { }
        $errTask = $p.StandardError.ReadToEndAsync()
        $lineTask = $p.StandardOutput.ReadLineAsync()
        $done = $false
        while (-not ($done -and $p.HasExited)) {
            if (-not $done -and $lineTask.IsCompleted) {
                $line = $null
                try { $line = $lineTask.Result } catch { }
                if ($null -eq $line) { $done = $true } else {
                    [void]$all.AppendLine($line)
                    $seg = ($line -split "`r")[-1].Trim()
                    if ($seg -and $seg -notmatch '^[\|/\-]$') { $last = $seg }
                    $lineTask = $p.StandardOutput.ReadLineAsync()
                }
                continue
            }
            Start-Sleep -Milliseconds 100
            if ($done -and -not $p.HasExited) { [void]$p.WaitForExit(100) }
            if ($OnTick) {
                $cancel = $false
                try { $cancel = [bool](& $OnTick $sw.Elapsed.TotalSeconds $last) } catch { }
                if ($cancel) { $res.Cancelled = $true; try { $p.Kill() } catch { }; break }
            }
            if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) { $res.TimedOut = $true; try { $p.Kill() } catch { }; break }
        }
        [void]$p.WaitForExit(3000)
        try { $res.StdErr = $errTask.Result } catch { }
        if ($p.HasExited) { $res.ExitCode = $p.ExitCode }
    } catch { $res.Error = $_.Exception.Message } finally { if ($p) { $p.Dispose() } }
    $res.StdOut = $all.ToString()
    return $res
}

Export-ModuleMember -Function ConvertTo-ProcessArgument, ConvertTo-ProcessArgumentString, New-ProcessStartInfo, Invoke-ExternalCapture, Invoke-ExternalStreaming
