# FFmpegManager.psm1 - FFmpeg/ffprobe detection, winget installation and update checks.
# UI-free: callers (App.psm1) drive the screens. External calls are injectable for tests.
Set-StrictMode -Version 2.0

$script:Tool = [pscustomobject]@{ Ffmpeg = ''; Ffprobe = ''; Ffplay = ''; Version = ''; Build = ''; ProbeVersion = '' }
$script:Hooks = @{ FindCommand = $null; Winget = $null; RefreshPath = $null }
$script:LastUpdate = [pscustomobject]@{ State = 'NotChecked'; Installed = ''; Available = ''; Message = '' }

function Set-FFManagerHooks {
    # Test seams: FindCommand {param($name)} -> path|$null ; Winget {param($argsArray,$onTick)} -> capture result ; RefreshPath {}
    param([scriptblock]$FindCommand, [scriptblock]$Winget, [scriptblock]$RefreshPath, [switch]$Reset)
    if ($Reset) { $script:Hooks = @{ FindCommand = $null; Winget = $null; RefreshPath = $null }; return }
    if ($FindCommand) { $script:Hooks.FindCommand = $FindCommand }
    if ($Winget) { $script:Hooks.Winget = $Winget }
    if ($RefreshPath) { $script:Hooks.RefreshPath = $RefreshPath }
}

function Get-FFmpegPath { return $script:Tool.Ffmpeg }
function Get-FFprobePath { return $script:Tool.Ffprobe }
function Get-FFmpegInfo { return $script:Tool }
function Get-LastUpdateStatus { return $script:LastUpdate }

function Update-ProcessPath {
    # Re-reads Machine + User PATH (and the WinGet links folder) into this process so a fresh install is found.
    if ($script:Hooks.RefreshPath) { & $script:Hooks.RefreshPath; return }
    if (-not (Test-IsWindows)) { return }
    try {
        $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $u = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($chunk in @($m, $u, $env:Path)) {
            if (-not $chunk) { continue }
            foreach ($p in ($chunk -split ';')) { if ($p -and -not ($parts -contains $p)) { $parts.Add($p) } }
        }
        if ($env:LOCALAPPDATA) {
            $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
            if ((Test-Path -LiteralPath $links) -and -not ($parts -contains $links)) { $parts.Add($links) }
        }
        $env:Path = ($parts -join ';')
    } catch { }
}

function Find-FFTool {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:Hooks.FindCommand) { return (& $script:Hooks.FindCommand $Name) }
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return [string]$cmd.Source }
    if ((Test-IsWindows) -and $env:LOCALAPPDATA) {
        $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
        foreach ($ext in '.exe') {
            $c = Join-Path $links ($Name + $ext)
            if (Test-Path -LiteralPath $c) { return $c }
        }
        $pk = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path -LiteralPath $pk) {
            $hit = Get-ChildItem -LiteralPath $pk -Filter ($Name + '.exe') -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function Test-FFToolCallable {
    # A stale PATH entry is not an installation: the tool must actually run and report a version.
    param([string]$Path, [string]$Name)
    $r = [pscustomobject]@{ Ok = $false; Version = ''; Build = ''; Error = '' }
    if (-not $Path) { $r.Error = 'not found'; return $r }
    $out = Invoke-ExternalCapture -FilePath $Path -Arguments @('-hide_banner', '-version') -TimeoutSec 20
    if (-not $out.Started) { $r.Error = $out.Error; return $r }
    if ($out.ExitCode -ne 0) { $r.Error = "exit code $($out.ExitCode)"; return $r }
    $first = ($out.StdOut -split "`r?`n" | Select-Object -First 1)
    if ($first -match '^\s*(ffmpeg|ffprobe|ffplay)\s+version\s+(\S+)') {
        $r.Ok = $true; $r.Version = $Matches[2]; $r.Build = $first.Trim()
    } else { $r.Error = 'unexpected output' }
    return $r
}

function Find-FFmpegInstallation {
    <# Returns Status: Ready | Missing | FfprobeMissing | Broken ; fills the tool registry when Ready. #>
    $ff = Find-FFTool 'ffmpeg'
    $fp = Find-FFTool 'ffprobe'
    $res = [pscustomobject]@{ Status = 'Missing'; Ffmpeg = $ff; Ffprobe = $fp; Version = ''; Build = ''; Detail = '' }
    if (-not $ff -and -not $fp) { return $res }
    $ffc = Test-FFToolCallable $ff 'ffmpeg'
    if (-not $ffc.Ok) {
        if ($ff) { $res.Status = 'Broken'; $res.Detail = "ffmpeg was found at '$ff' but cannot be run ($($ffc.Error)). This is usually a stale PATH entry." }
        else { $res.Status = 'Missing' }
        return $res
    }
    $res.Version = $ffc.Version; $res.Build = $ffc.Build
    $fpc = Test-FFToolCallable $fp 'ffprobe'
    if (-not $fpc.Ok) {
        $res.Status = 'FfprobeMissing'
        $res.Detail = if ($fp) { "ffprobe was found at '$fp' but cannot be run ($($fpc.Error))." } else { 'ffmpeg was found but ffprobe is missing.' }
        return $res
    }
    $res.Status = 'Ready'
    $script:Tool = [pscustomobject]@{ Ffmpeg = $ff; Ffprobe = $fp; Ffplay = [string](Find-FFTool 'ffplay'); Version = $ffc.Version; Build = $ffc.Build; ProbeVersion = $fpc.Version }
    return $res
}

# ---- winget -------------------------------------------------------------------

function Get-WingetPackageId {
    $id = 'Gyan.FFmpeg'; try { $id = [string](Get-AppConfig).winget.packageId } catch { }
    return $id
}
function Get-WingetSource {
    $s = 'winget'; try { $s = [string](Get-AppConfig).winget.source } catch { }
    return $s
}

function Get-WingetPath {
    if ($script:Hooks.Winget) { return 'winget' }
    $c = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return [string]$c.Source }
    return $null
}

function Test-WingetAvailable { return [bool](Get-WingetPath) }

function Invoke-Winget {
    param([string[]]$Arguments, [int]$TimeoutSec = 120, [scriptblock]$OnTick)
    if ($script:Hooks.Winget) { return (& $script:Hooks.Winget $Arguments $OnTick) }
    $w = Get-WingetPath
    if (-not $w) { return [pscustomobject]@{ Started = $false; ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = 'winget not available' } }
    return (Invoke-ExternalStreaming -FilePath $w -Arguments $Arguments -TimeoutSec $TimeoutSec -OnTick $OnTick)
}

function ConvertFrom-WingetPackageLine {
    # Locale-independent: finds the row containing the package id and reads Version [Available] Source after it.
    param([string]$Text, [string]$PackageId)
    foreach ($line in ($Text -split "`r?`n")) {
        $l = ($line -split "`r")[-1]
        $idx = $l.IndexOf($PackageId, [StringComparison]::OrdinalIgnoreCase)
        if ($idx -lt 0) { continue }
        $rest = $l.Substring($idx + $PackageId.Length).Trim()
        $tok = @($rest -split '\s+' | Where-Object { $_ })
        if ($tok.Count -eq 0) { continue }
        $r = [pscustomobject]@{ Found = $true; Installed = $tok[0]; Available = ''; Source = '' }
        if ($tok.Count -eq 2) { $r.Source = $tok[1] }
        elseif ($tok.Count -ge 3) { $r.Available = $tok[1]; $r.Source = $tok[2] }
        return $r
    }
    return [pscustomobject]@{ Found = $false; Installed = ''; Available = ''; Source = '' }
}

function Get-FFmpegUpdateStatus {
    <#
      State: UpdateAvailable | UpToDate | Unmanaged | Unknown.
      Never throws and never blocks the application: any uncertainty is 'Unknown' / 'Unmanaged'.
    #>
    param([scriptblock]$OnTick)
    $st = [pscustomobject]@{ State = 'Unknown'; Installed = $script:Tool.Version; Available = ''; Message = '' }
    try {
        if (-not (Test-WingetAvailable)) {
            $st.State = 'Unknown'; $st.Message = 'Windows Package Manager (winget) is not available, so updates cannot be checked automatically.'
            $script:LastUpdate = $st; return $st
        }
        $id = Get-WingetPackageId; $src = Get-WingetSource
        $list = Invoke-Winget -Arguments @('list', '--id', $id, '--exact', '--source', $src, '--accept-source-agreements') -TimeoutSec 60 -OnTick $OnTick
        $li = ConvertFrom-WingetPackageLine ([string]$list.StdOut) $id
        if (-not $li.Found) {
            if ($list.Started -and -not $list.TimedOut) {
                $st.State = 'Unmanaged'; $st.Message = 'This FFmpeg was not installed by winget, so it will not be updated automatically.'
            } else { $st.Message = 'The winget package list could not be read.' }
            $script:LastUpdate = $st; return $st
        }
        $st.Installed = $li.Installed
        $up = Invoke-Winget -Arguments @('upgrade', '--id', $id, '--exact', '--source', $src, '--accept-source-agreements') -TimeoutSec 90 -OnTick $OnTick
        if ($up.TimedOut -or -not $up.Started) { $st.Message = 'The update check timed out or could not start.'; $script:LastUpdate = $st; return $st }
        $ui = ConvertFrom-WingetPackageLine ([string]$up.StdOut) $id
        if ($ui.Found -and $ui.Available) {
            $st.State = 'UpdateAvailable'; $st.Installed = $ui.Installed; $st.Available = $ui.Available
            $st.Message = "Version $($ui.Available) is available."
        } elseif ($up.ExitCode -eq 0 -or $up.ExitCode -eq -1978335189) {
            $st.State = 'UpToDate'; $st.Message = 'FFmpeg is up to date.'
        } else {
            $st.Message = ('The update status could not be determined (winget exit code {0}). Check your internet connection or package sources.' -f $up.ExitCode)
        }
    } catch { $st.State = 'Unknown'; $st.Message = "The update check failed: $($_.Exception.Message)" }
    $script:LastUpdate = $st
    return $st
}

function Get-WingetFailureHint {
    param([int]$ExitCode, [string]$Text)
    $hex = '0x{0:X8}' -f (([int64]$ExitCode) -band 4294967295L)
    $hint = "winget exit code $hex."
    if ($Text -match '(?i)admin|elevat|access is denied') { $hint += ' The installer needs administrator rights: restart the terminal as Administrator and try again.' }
    elseif ($Text -match '(?i)network|internet|could not connect|timed out|source') { $hint += ' A network or package-source problem occurred. Check your internet connection and try again.' }
    return $hint
}

function Install-FFmpegViaWinget {
    param([scriptblock]$OnTick)
    $r = [pscustomobject]@{ Ok = $false; Message = ''; Detail = ''; Installation = $null }
    if (-not (Test-WingetAvailable)) {
        $r.Message = 'Windows Package Manager (winget) is not available on this computer, so FFmpeg cannot be installed automatically.'
        return $r
    }
    $id = Get-WingetPackageId; $src = Get-WingetSource
    # Verify the package exists before installing anything.
    $show = Invoke-Winget -Arguments @('show', '--id', $id, '--exact', '--source', $src, '--accept-source-agreements') -TimeoutSec 60 -OnTick $OnTick
    if (-not $show.Started -or $show.ExitCode -ne 0) {
        $r.Message = "The FFmpeg package '$id' could not be verified in the package source. " + (Get-WingetFailureHint $show.ExitCode ($show.StdOut + $show.StdErr))
        $r.Detail = ($show.StdOut + "`n" + $show.StdErr).Trim()
        return $r
    }
    $ins = Invoke-Winget -Arguments @('install', '--id', $id, '--exact', '--source', $src, '--accept-package-agreements', '--accept-source-agreements') -TimeoutSec 1800 -OnTick $OnTick
    $r.Detail = ($ins.StdOut + "`n" + $ins.StdErr).Trim()
    if ($ins.Cancelled) { $r.Message = 'The installation was cancelled.'; return $r }
    Update-ProcessPath
    $inst = Find-FFmpegInstallation
    $r.Installation = $inst
    if ($inst.Status -eq 'Ready') { $r.Ok = $true; $r.Message = "FFmpeg $($inst.Version) is installed."; return $r }
    if ($ins.ExitCode -ne 0) { $r.Message = 'The installation did not complete. ' + (Get-WingetFailureHint $ins.ExitCode $r.Detail) }
    else { $r.Message = 'winget reported success, but ffmpeg and ffprobe were not found afterwards. Open a new terminal window and start the application again so the updated PATH is loaded.' }
    return $r
}

function Update-FFmpegViaWinget {
    param([scriptblock]$OnTick)
    $r = [pscustomobject]@{ Ok = $false; Message = ''; Detail = ''; Version = '' }
    $id = Get-WingetPackageId; $src = Get-WingetSource
    $up = Invoke-Winget -Arguments @('upgrade', '--id', $id, '--exact', '--source', $src, '--accept-package-agreements', '--accept-source-agreements') -TimeoutSec 1800 -OnTick $OnTick
    $r.Detail = ($up.StdOut + "`n" + $up.StdErr).Trim()
    if (-not $up.Started -or $up.ExitCode -ne 0) {
        $r.Message = 'The update did not complete. ' + (Get-WingetFailureHint $up.ExitCode $r.Detail)
        return $r
    }
    Update-ProcessPath
    $inst = Find-FFmpegInstallation
    if ($inst.Status -eq 'Ready') { $r.Ok = $true; $r.Version = $inst.Version; $r.Message = "FFmpeg was updated to $($inst.Version)." }
    else { $r.Message = 'The update finished but FFmpeg could not be verified afterwards. Restart the application.' }
    return $r
}

Export-ModuleMember -Function Set-FFManagerHooks, Get-FFmpegPath, Get-FFprobePath, Get-FFmpegInfo, Get-LastUpdateStatus, Update-ProcessPath, Find-FFTool, Test-FFToolCallable, Find-FFmpegInstallation, Get-WingetPackageId, Test-WingetAvailable, ConvertFrom-WingetPackageLine, Get-FFmpegUpdateStatus, Install-FFmpegViaWinget, Update-FFmpegViaWinget
