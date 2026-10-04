<# 04 - External command from an ARGUMENT ARRAY (no shell string, no Invoke-Expression). Finds the program on PATH, never guesses a
   location, captures stdout/stderr asynchronously, applies a timeout and reports a missing program as a message, not a crash.
   Run:  pwsh -File 04-External-Command.ps1 [-Demo] #>
param([switch]$Demo)
. (Join-Path $PSScriptRoot 'Shared/TinyTui.ps1')
function ConvertTo-Arg {
    param([AllowEmptyString()][string]$A)
    if ($A.Length -eq 0) { return '""' }
    if ($A.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) { return $A }
    $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('"'); $bs = 0
    foreach ($ch in $A.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\', $bs * 2 + 1); [void]$sb.Append('"'); $bs = 0; continue }
        if ($bs -gt 0) { [void]$sb.Append('\', $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append('\', $bs * 2) }
    [void]$sb.Append('"'); return $sb.ToString()
}
function Invoke-Program {
    param([string]$File, [string[]]$Arguments = @(), [int]$TimeoutSec = 30)
    $r = [pscustomobject]@{ Started = $false; ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $false; Error = '' }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File; $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = New-Object System.Diagnostics.Process; $p.StartInfo = $psi; [void]$p.Start(); $r.Started = $true
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) { $r.TimedOut = $true; try { $p.Kill() } catch { } } else { $p.WaitForExit() }
        try { $r.StdOut = $o.Result; $r.StdErr = $e.Result } catch { }
        if ($p.HasExited) { $r.ExitCode = $p.ExitCode }
    } catch { $r.Error = $_.Exception.Message } finally { if ($p) { $p.Dispose() } }
    return $r
}
$hostName = 'pwsh'; if ($PSVersionTable.PSVersion.Major -lt 6) { $hostName = 'powershell' }
$exe = Get-Command $hostName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Write-Line 'PowerShell was not found on PATH.' 'Red'; exit 1 }
# a child script that reports how many arguments it received: arguments with spaces must arrive as ONE argument each
$child = Join-Path ([System.IO.Path]::GetTempPath()) ('child-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.ps1')
[System.IO.File]::WriteAllText($child, 'Write-Output ("args=" + $args.Count + " first=[" + $args[0] + "]")')
$r = Invoke-Program -File $exe.Source -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $child, 'a file with spaces.txt', 'second')
Remove-Item -LiteralPath $child -Force
Write-Line ('Started={0} Exit={1} Output={2}' -f $r.Started, $r.ExitCode, $r.StdOut.Trim()) 'Green'
$m = Invoke-Program -File 'this-program-does-not-exist' -TimeoutSec 5
Write-Line ('Missing program -> Started={0}; message: {1}' -f $m.Started, $m.Error) 'Yellow'
