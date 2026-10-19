# BAT launcher tests. Run with the real cmd.exe on Windows, or with Wine's cmd.exe when available (Linux).
$root = Get-TestRoot
$W = Get-TestWork
$batSrc = Join-Path $root 'FFmpeg-User-Manager.bat'
$onWin = (Test-IsWindows)
$runner = $null
if ($onWin) { $runner = 'cmd.exe' }
else {
    foreach ($c in @('wine64', 'wine', '/usr/lib/wine/wine64')) { $g = Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1; if ($g) { $runner = $g.Source; break } }
    if (-not $runner -and (Test-Path -LiteralPath '/usr/lib/wine/wine64')) { $runner = '/usr/lib/wine/wine64' }
}

Set-TestGroup 'BAT launcher: static checks'
$raw = [System.IO.File]::ReadAllBytes($batSrc)
$txt = [System.Text.Encoding]::ASCII.GetString($raw)
Assert-True 'FFmpeg-User-Manager.bat exists in the repository root' (Test-Path -LiteralPath $batSrc)
Assert-True 'launcher is pure ASCII (safe for every console code page)' (@($raw | Where-Object { $_ -gt 127 }).Count -eq 0)
Assert-True 'launcher uses CRLF line endings' ($txt.Contains("`r`n") -and -not ($txt -replace "`r`n", '').Contains("`n"))
Assert-True 'launcher never changes execution policy (only a process-scoped -ExecutionPolicy Bypass)' (($txt -notmatch '(?i)Set-ExecutionPolicy') -and ($txt -match '(?i)-ExecutionPolicy Bypass -File'))
Assert-True 'launcher targets Start-FFmpegTUI.ps1 relative to its own folder (no absolute developer paths)' (($txt -match '%~dp0') -and ($txt -notmatch '(?i)[a-z]:\\users\\|/home/|/root/'))
Assert-True 'launcher contains no media-processing logic (no ffmpeg/ffprobe calls)' ($txt -notmatch '(?i)ffmpeg\s+-|ffprobe\s+-')
Assert-True 'the canonical entry script exists' (Test-Path -LiteralPath (Join-Path $root 'Start-FFmpegTUI.ps1'))
Assert-True 'launcher routes a non-terminal start through Windows Terminal when wt.exe is available' (($txt -match '(?i)WT_SESSION') -and ($txt -match '(?i)wt\.exe') -and ($txt -match '(?i)-w new'))

if (-not $runner) {
    foreach ($n in @('launch from the repository folder', 'launch from another working directory', 'path containing spaces and parentheses', 'missing entry script gives a clear error and exit code', 'PowerShell 7 preferred when available', 'fallback to Windows PowerShell when pwsh is absent', 'error when no PowerShell exists', 'argument pass-through and exit-code propagation', 'double-click style start')) { Skip-Test "BAT: $n" 'cmd.exe is not available in this environment (not Windows, no Wine)' }
    return
}

function ConvertTo-CmdPath { param([string]$P) if ($onWin) { return $P }; return ('Z:' + ($P -replace '/', '\')) }
$script:CscPath = $null
if ($onWin) { $script:CscPath = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
function Invoke-BatCase {
    # Builds a sandbox (launcher + stub PowerShell executables) and runs a wrapper .cmd with the real cmd interpreter.
    param([string]$Name, [switch]$WithEntry, [switch]$Pwsh, [switch]$WinPs, [switch]$WindowsTerminal, [switch]$OutsideWindowsTerminal, [string]$BatArgs = '', [int]$StubRc = 0, [string]$Dir = '', [switch]$DoubleClick, [string]$StartDir = '', [switch]$UseStub, [string]$RuntimePath = '')
    $case = Join-Path $W ('bat_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    if (-not $Dir) { $Dir = 'app' }
    $app = Join-Path $case $Dir; $bin = Join-Path $case 'bin'
    [void](New-Item -ItemType Directory -Path $app -Force); [void](New-Item -ItemType Directory -Path $bin -Force)
    [System.IO.File]::Copy($batSrc, (Join-Path $app 'FFmpeg-User-Manager.bat'))
    if ($WithEntry) { [System.IO.File]::WriteAllText((Join-Path $app 'Start-FFmpegTUI.ps1'), '# stub') }
    if ($RuntimePath) { [System.IO.File]::WriteAllText((Join-Path $app 'Start-FFmpegTUI.ps1'), 'param([switch]$Version) if ($Version) { Write-Output "ENTRY-REACHED" } else { exit 92 }') }
    # Dummy executables (detection only) and, for execution tests, a .cmd stub selected through FFUM_POWERSHELL.
    foreach ($pair in @(@($Pwsh, 'pwsh'), @($WinPs, 'powershell'))) { if ($pair[0]) { [System.IO.File]::WriteAllText((Join-Path $bin ($pair[1] + '.exe')), 'MZ dummy') } }
    if ($WindowsTerminal) {
        $wt = Join-Path $bin 'wt.exe'
        [System.IO.File]::WriteAllText($wt, 'MZ dummy')
        if ($onWin -and $script:CscPath) {
            $wtCs = Join-Path $bin 'wt.cs'
            # Exercise the parsed executable and arguments, rather than only recording the raw command line.
            [System.IO.File]::WriteAllText($wtCs, 'using System; using System.Diagnostics; class P { static int Main(string[] a) { string p = Environment.GetEnvironmentVariable("FFUM_WT_LOG"); if (!String.IsNullOrEmpty(p)) System.IO.File.WriteAllText(p, Environment.CommandLine); if (a.Length < 3 || a[0] != "-w" || a[1] != "new" || !System.IO.File.Exists(a[2])) return 91; string tail = ""; for (int i=3;i<a.Length;i++) tail += " \"" + a[i] + "\""; ProcessStartInfo s = new ProcessStartInfo(a[2], tail); s.UseShellExecute=false; using (Process c=Process.Start(s)) { c.WaitForExit(); return c.ExitCode; } } }')
            $wtCompile = Invoke-ExternalCapture -FilePath $script:CscPath -Arguments @('/nologo', ('/out:' + $wt), $wtCs) -TimeoutSec 120
        }
    }
    $stub = Join-Path $bin 'stub.cmd'
    [System.IO.File]::WriteAllText($stub, ("@echo off`r`necho STUB-RUN %*`r`nexit /b $StubRc`r`n"))
    # On real Windows a batch file started from a batch file WITHOUT `call` never returns to the caller, which real PowerShell executables do.
    # So the stub must be a real executable there; it is compiled with the .NET Framework compiler that ships with Windows (no download).
    if ($onWin -and $script:CscPath) {
        $stubExe = Join-Path $bin 'stub.exe'
        $cs = Join-Path $bin 'stub.cs'
        [System.IO.File]::WriteAllText($cs, ('using System; class P { static int Main() { string c = Environment.CommandLine; string a = c.StartsWith("\"") ? c.Substring(c.IndexOf((char)34, 1) + 1) : (c.IndexOf((char)32) >= 0 ? c.Substring(c.IndexOf((char)32)) : ""); Console.WriteLine("STUB-RUN" + a); return ' + $StubRc + '; } }'))
        $cr = Invoke-ExternalCapture -FilePath $script:CscPath -Arguments @('/nologo', ('/out:' + $stubExe), $cs) -TimeoutSec 120
        if (Test-Path -LiteralPath $stubExe) { $stub = $stubExe } else { Write-Host ('        stub compile failed: ' + $cr.StdOut + $cr.StdErr) }
    }
    $batWin = ConvertTo-CmdPath (Join-Path $app 'FFmpeg-User-Manager.bat')
    $binWin = ConvertTo-CmdPath $bin
    $startWin = $(if ($StartDir) { ConvertTo-CmdPath $StartDir } else { ConvertTo-CmdPath $case })
    $lines = @('@echo off', 'setlocal EnableDelayedExpansion', "set `"PATH=$binWin;%SystemRoot%\system32;%SystemRoot%`"")
    if (-not $OutsideWindowsTerminal) { $lines += 'set "WT_SESSION=launcher-test"' }
    if ($WindowsTerminal) { $lines += "set `"FFUM_WT_LOG=$(ConvertTo-CmdPath (Join-Path $case 'wt.log'))`"" }
    $lines += "cd /d `"$startWin`""
    if ($UseStub) { $lines += "set `"FFUM_POWERSHELL=$(ConvertTo-CmdPath $stub)`""; $lines += 'set "FFUM_TRACE=1"' } else { $lines += 'set "FFUM_TRACE=1"' }
    if ($RuntimePath) { $lines += "set `"FFUM_POWERSHELL=$RuntimePath`"" }
    # cmd /c (not CALL) so the exit code is the launcher's real process exit code; stdin is empty so PAUSE cannot block.
    # The launcher path goes through a variable + delayed expansion so characters such as & ( ) in it are not parsed by this wrapper.
    $lines += "set `"FFUM_TEST_BAT=$batWin`""
    $lines += "cmd /c `"`"!FFUM_TEST_BAT!`" $BatArgs`" <nul"
    $lines += 'echo EXIT=%ERRORLEVEL%'
    $wrapper = Join-Path $case 'run.cmd'
    [System.IO.File]::WriteAllText($wrapper, (($lines -join "`r`n") + "`r`n"))
    $saved = $env:WINEDEBUG; $savedPfx = $env:WINEPREFIX
    $env:WINEDEBUG = '-all'; if (-not $env:WINEPREFIX) { $env:WINEPREFIX = (Join-Path ([System.IO.Path]::GetTempPath()) 'fftui-wine-prefix') }
    try {
        if ($onWin) { $r = Invoke-ExternalCapture -FilePath 'cmd.exe' -Arguments @('/c', $wrapper) -TimeoutSec 90 }
        else { $r = Invoke-ExternalCapture -FilePath $runner -Arguments @('cmd', '/c', (ConvertTo-CmdPath $wrapper)) -TimeoutSec 240 }
    } finally { $env:WINEDEBUG = $saved; $env:WINEPREFIX = $savedPfx }
    $m = [regex]::Match($r.StdOut, 'EXIT=(\d+)')
    $wtLog = Join-Path $case 'wt.log'
    $wtText = $(if (Test-Path -LiteralPath $wtLog -PathType Leaf) { [System.IO.File]::ReadAllText($wtLog) } else { '' })
    return [pscustomobject]@{ Out = $r.StdOut; Exit = $(if ($m.Success) { [int]$m.Groups[1].Value } else { -1 }); Case = $case; Wt = $wtText }
}

Set-TestGroup 'BAT launcher: behavior under the real cmd interpreter'
$r = Invoke-BatCase -WithEntry -Pwsh -WinPs -StartDir $root
Assert-True 'PowerShell 7 (pwsh.exe) is preferred when both runtimes are on PATH' ($r.Out -match 'Launcher runtime: .*pwsh\.exe' -and $r.Out -notmatch 'Launcher runtime: .*powershell\.exe') $r.Out
$r = Invoke-BatCase -WithEntry -WinPs
Assert-True 'Windows PowerShell 5.1 (powershell.exe) is used when pwsh.exe is absent' ($r.Out -match 'Launcher runtime: .*powershell\.exe') $r.Out
$r = Invoke-BatCase -WithEntry
$hasSysPs = ($r.Out -match 'Launcher runtime: .*WindowsPowerShell')
if ($hasSysPs) { Assert-True 'no PowerShell on PATH: the standard Windows PowerShell location is used as last resort' $true }
else {
    Assert-Equal 'no PowerShell at all: exit code 3' 3 $r.Exit
    Assert-True 'no PowerShell at all: clear message' ($r.Out -match 'Neither PowerShell 7') $r.Out
}
$r = Invoke-BatCase -Pwsh -WinPs
Assert-Equal 'missing entry script: exit code 2' 2 $r.Exit
Assert-True 'missing entry script: useful error naming the expected file' ($r.Out -match 'entry script was not found' -and $r.Out -match 'Start-FFmpegTUI\.ps1') $r.Out
Assert-True 'missing entry script: PowerShell is never started' ($r.Out -notmatch 'Launcher runtime') $r.Out
$r = Invoke-BatCase -WithEntry -UseStub -StartDir $root
Assert-True 'launch from another working directory than the launcher folder' ($r.Out -match 'STUB-RUN' -and $r.Exit -eq 0) $r.Out
Assert-True 'PowerShell is started with -NoProfile, a process-scoped Bypass and the absolute entry script path' ($r.Out -match '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "[A-Za-z]:\\.*\\app\\Start-FFmpegTUI\.ps1"') $r.Out
$r = Invoke-BatCase -WithEntry -UseStub -Dir 'My Apps (x86) & tools'
Assert-True 'path containing spaces, parentheses and an ampersand works' ($r.Out -match 'STUB-RUN' -and $r.Out -match 'My Apps \(x86\) & tools' -and $r.Exit -eq 0) $r.Out
$r = Invoke-BatCase -WithEntry -UseStub -BatArgs '-SkipUpdateCheck -Version' -StubRc 7
Assert-True 'arguments are passed through to the PowerShell script' ($r.Out -match 'Start-FFmpegTUI\.ps1" -SkipUpdateCheck -Version') $r.Out
Assert-Equal 'the PowerShell exit code is returned by the launcher' 7 $r.Exit
if ($onWin -and $script:CscPath) {
    $unicodeDir = '02 ' + [char]0x2502 + ' Assistance Projects\FFmpeg User Manager'
    $r = Invoke-BatCase -WithEntry -UseStub -WindowsTerminal -OutsideWindowsTerminal -BatArgs '-Version' -Dir $unicodeDir
    Assert-True 'Terminal dispatch executes the selected runtime with the intact Unicode entry path' ($r.Exit -eq 0 -and $r.Out -match 'STUB-RUN' -and $r.Out.Contains($unicodeDir) -and $r.Out -match 'Start-FFmpegTUI\.ps1.*-Version') ($r.Out + "`nWT: " + $r.Wt)
    $realRuntime = (Get-Process -Id $PID).Path
    $r = Invoke-BatCase -WithEntry -WindowsTerminal -OutsideWindowsTerminal -RuntimePath $realRuntime -BatArgs '-Version' -Dir $unicodeDir
    Assert-True 'Terminal dispatch reaches a real PowerShell script in a Unicode project directory' ($r.Exit -eq 0 -and $r.Out -match 'ENTRY-REACHED') ($r.Out + "`nWT: " + $r.Wt)
} else {
    Skip-Test 'a non-terminal start opens Windows Terminal without passing a Unicode project path to wt.exe' 'requires the Windows .NET Framework compiler used by the launcher sandbox'
}
$probe = Invoke-BatCase -WithEntry -UseStub
$cmdLineOk = $false
try {
    $pp = Join-Path $W 'cmdline_probe.cmd'; [System.IO.File]::WriteAllText($pp, "@echo off`r`necho PROBE[%CMDCMDLINE%]`r`n")
    if ($onWin) { $q = Invoke-ExternalCapture -FilePath 'cmd.exe' -Arguments @('/c', $pp) -TimeoutSec 30 } else { $env:WINEDEBUG = '-all'; $q = Invoke-ExternalCapture -FilePath $runner -Arguments @('cmd', '/c', (ConvertTo-CmdPath $pp)) -TimeoutSec 120 }
    $cmdLineOk = ($q.StdOut -match 'PROBE\[.+\]')
} catch { }
if (-not $cmdLineOk) {
    Skip-Test 'double-click style start: failing run pauses so the error stays visible' 'this cmd interpreter (Wine) does not populate %CMDCMDLINE%, which the launcher uses to detect a double-click start; verify on real Windows'
    Skip-Test 'double-click style start: successful run closes without a prompt' 'same reason (%CMDCMDLINE% unavailable in this environment)'
} else {
    $r = Invoke-BatCase -WithEntry -UseStub -StubRc 5
    Assert-True 'double-click style start (cmd /c): a failing run is reported and pauses instead of vanishing' ($r.Out -match 'exited with code 5') $r.Out
    $r = Invoke-BatCase -WithEntry -UseStub -StubRc 0
    Assert-True 'double-click style start: a successful run closes without an extra prompt' ($r.Out -notmatch 'exited with code') $r.Out
}
