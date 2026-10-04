# Process.psm1 - run external programs from an ARGUMENT ARRAY. No shell strings, no Invoke-Expression, ever.
Set-StrictMode -Version 2.0

function ConvertTo-ProcessArgument {
    # Windows command-line quoting rules (CommandLineToArgvW): works for paths with spaces, quotes and trailing backslashes.
    param([AllowEmptyString()][string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument.IndexOfAny([char[]]@(' ', "`t", "`n", '"')) -lt 0) { return $Argument }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\', ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
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

function Invoke-External {
    # Returns Started / ExitCode / StdOut / StdErr / TimedOut / Error. Output is read asynchronously (no pipe deadlock).
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [int]$TimeoutSec = 60)
    $res = [pscustomobject]@{ Started = $false; ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $false; Error = '' }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = ConvertTo-ProcessArgumentString $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
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
        } else { $p.WaitForExit() }
        try { $res.StdOut = $outTask.Result } catch { }
        try { $res.StdErr = $errTask.Result } catch { }
        if ($p.HasExited) { $res.ExitCode = $p.ExitCode }
    } catch { $res.Error = $_.Exception.Message } finally { if ($p) { $p.Dispose() } }
    return $res
}

Export-ModuleMember -Function ConvertTo-ProcessArgument, ConvertTo-ProcessArgumentString, Invoke-External
