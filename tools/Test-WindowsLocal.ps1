<#
 Local Windows verification helper (Windows PowerShell 5.1 and PowerShell 7).
 Runs the full automated suite under every PowerShell edition found on this computer, prints what the
 application detects about this terminal, and lists the checks that only a person at a real Windows
 Terminal can do. It changes nothing on the system, downloads nothing and never installs anything.

 Usage (from the project folder):   .\tools\Test-WindowsLocal.ps1
                                    .\tools\Test-WindowsLocal.ps1 -SkipSuite     (only the detection report + checklist)
 Run it once from a normal (non-administrator) window: the "read permission denied" test can only be
 proven by a standard user, because an administrator ignores the denial.
#>
[CmdletBinding()]
param([switch]$SkipSuite)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runTests = Join-Path (Join-Path $root 'tests') 'Run-Tests.ps1'
$results = @()

if (-not $SkipSuite) {
    foreach ($exe in @('powershell.exe', 'pwsh.exe')) {
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { Write-Host ("[skip] {0} is not installed on this computer" -f $exe); continue }
        Write-Host ("`n===== Full suite under {0} =====" -f $exe)
        $log = Join-Path ([System.IO.Path]::GetTempPath()) ('fftui-local-' + ($exe -replace '\.exe', '') + '.log')
        & $cmd.Source -NoProfile -ExecutionPolicy Bypass -File $runTests *> $log
        $code = $LASTEXITCODE
        $summary = (Select-String -Path $log -Pattern '==== SUMMARY' | Select-Object -Last 1).Line
        $unv = @(Select-String -Path $log -Pattern '^\s*\[UNVERIFIED\]' | ForEach-Object { $_.Line.Trim() })
        $fail = @(Select-String -Path $log -Pattern '^FAIL:' | ForEach-Object { $_.Line })
        Write-Host $summary
        foreach ($u in $unv) { Write-Host ('   ' + $u) }
        foreach ($f in $fail) { Write-Host ('   ' + $f) -ForegroundColor Red }
        Write-Host ("   full log: {0}" -f $log)
        $results += [pscustomobject]@{ Edition = $exe; ExitCode = $code; Summary = $summary }
    }
}

Write-Host "`n===== What the application detects about this terminal ====="
. (Join-Path (Join-Path $root 'src') 'Import-Modules.ps1')
Import-FFTuiModules -Root $root
Set-AppRoot $root
Write-Host ("Segoe UI Emoji installed : {0}" -f (Test-EmojiFontInstalled))
Write-Host ("Terminal                 : {0}" -f (Get-TerminalEmojiHint))
Write-Host ("Icon set that would be used: {0}" -f (Get-IconTier))
Write-Host ("Saved icon choice        : {0}" -f (Get-UserSetting 'icons'))

Write-Host @"

===== Manual checks (cannot be automated; do them in a real Windows Terminal) =====
 [ ] 1. Double-click FFmpeg-User-Manager.bat: the main menu opens, every option shows  Number  Icon  Name.
 [ ] 2. Choose 28 (Check & Maintain FFmpeg Setup), answer Yes to each step once: all five steps run, nothing is
        downloaded unless you say Yes to an install/update. Then choose 29 (Exit): the window closes cleanly.
 [ ] 3. In the icon step choose the emoji set: the preview shows colored emoji, not empty boxes. If boxes appear,
        choose the simple symbols (the choice is remembered).
 [ ] 4. Open the same .bat from a classic cmd.exe window and from Windows Terminal: icons look consistent with the
        saved choice.
 [ ] 5. Screen / webcam / microphone recording (main menu: Record / Capture): a short recording
        produces a playable file. (Needs real devices.)
 [ ] 6. While a conversion is running close the terminal window: no ffmpeg.exe process stays behind (Task Manager).
 [ ] 7. If winget is installed: run step 1 of the maintenance tool with FFmpeg removed from PATH and answer Yes only on
        a test machine - it installs Gyan.FFmpeg through winget after asking.
"@
if (@($results | Where-Object { $_.ExitCode -ne 0 }).Count -gt 0) { exit 1 }
