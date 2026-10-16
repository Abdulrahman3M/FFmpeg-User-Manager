# FFmpegManager.psm1 - FFmpeg/ffprobe detection, winget installation and update checks.
# UI-free: callers (App.psm1) drive the screens. External calls are injectable for tests.
Set-StrictMode -Version 2.0

$script:Tool = [pscustomobject]@{ Ffmpeg = ''; Ffprobe = ''; Ffplay = ''; Version = ''; Build = ''; ProbeVersion = ''; Source = ''; Directory = '' }
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

function Get-BundledFFmpegPath {
    $root = Get-AppRoot
    if (-not $root) { return '' }
    $path = Join-Path (Join-Path (Join-Path (Join-Path $root 'External-Libraries') 'FFmpeg') 'bin') 'ffmpeg.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return ''
}

function Get-BundledFFprobePath {
    $root = Get-AppRoot
    if (-not $root) { return '' }
    $path = Join-Path (Join-Path (Join-Path (Join-Path $root 'External-Libraries') 'FFmpeg') 'bin') 'ffprobe.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return ''
}

function Find-FFmpegInstallation {
    <# Returns Status: Ready | Missing | FfprobeMissing | Broken ; bundled, custom and system pairs are never mixed. #>
    $script:Tool = [pscustomobject]@{ Ffmpeg = ''; Ffprobe = ''; Ffplay = ''; Version = ''; Build = ''; ProbeVersion = ''; Source = ''; Directory = '' }
    $ff = ''; $fp = ''; $source = ''
    $bundledFF = Get-BundledFFmpegPath; $bundledFP = Get-BundledFFprobePath
    if ($bundledFF -or $bundledFP) {
        $ff = $bundledFF; $fp = $bundledFP; $source = 'Bundled'
    } elseif ($env:FFTUI_FFMPEG_PATH) {
        $customDirectory = [string]$env:FFTUI_FFMPEG_PATH
        $ffPath = Join-Path $customDirectory 'ffmpeg.exe'; $fpPath = Join-Path $customDirectory 'ffprobe.exe'
        if (Test-Path -LiteralPath $ffPath -PathType Leaf) { $ff = $ffPath }
        if (Test-Path -LiteralPath $fpPath -PathType Leaf) { $fp = $fpPath }
        if ($ff -or $fp -or (Test-Path -LiteralPath $customDirectory -PathType Container)) { $source = 'Custom' }
    } else {
        $ff = Find-FFTool 'ffmpeg'; $fp = Find-FFTool 'ffprobe'; $source = 'System'
        if ($ff -and $fp) {
            $ffDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ff))
            $fpDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($fp))
            if (-not [string]::Equals($ffDirectory, $fpDirectory, [StringComparison]::OrdinalIgnoreCase)) {
                $res = [pscustomobject]@{ Status = 'Broken'; Ffmpeg = $ff; Ffprobe = $fp; Version = ''; Build = ''; Detail = 'ffmpeg and ffprobe were found in different system runtime directories; the application will not mix them.'; Source = $source; Directory = '' }
                return $res
            }
        }
    }
    $directory = ''
    if ($ff) { try { $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ff)) } catch { $directory = '' } }
    $res = [pscustomobject]@{ Status = 'Missing'; Ffmpeg = $ff; Ffprobe = $fp; Version = ''; Build = ''; Detail = ''; Source = $source; Directory = $directory }
    if (-not $ff -and -not $fp) { return $res }
    if ($ff -and -not $fp) {
        $res.Status = if ($source -eq 'System') { 'FfprobeMissing' } else { 'Broken' }
        $res.Detail = if ($source -eq 'System') { "ffmpeg was found at '$ff' but ffprobe is missing. This may be a stale PATH entry." } else { "The $($source.ToLowerInvariant()) runtime is incomplete: ffprobe is missing. The application will not mix runtimes." }
        return $res
    }
    if (-not $ff) {
        $res.Status = if ($source -eq 'System') { 'Missing' } else { 'Broken' }
        $res.Detail = "ffprobe was found in the $($source.ToLowerInvariant()) runtime, but ffmpeg is missing. The application will not mix runtimes."
        return $res
    }
    $ffc = Test-FFToolCallable $ff 'ffmpeg'
    if (-not $ffc.Ok) {
        $res.Status = 'Broken'
        $res.Detail = if ($source -eq 'System') { "ffmpeg was found at '$ff' but cannot be run ($($ffc.Error)). This is usually a stale PATH entry." } else { "ffmpeg was found at '$ff' in the $($source.ToLowerInvariant()) runtime but cannot be run ($($ffc.Error))." }
        return $res
    }
    $res.Version = $ffc.Version; $res.Build = $ffc.Build
    $fpc = Test-FFToolCallable $fp 'ffprobe'
    if (-not $fpc.Ok) {
        $res.Status = 'FfprobeMissing'
        $res.Detail = "ffprobe was found at '$fp' but cannot be run ($($fpc.Error))."
        return $res
    }
    $res.Status = 'Ready'
    $script:Tool = [pscustomobject]@{ Ffmpeg = $ff; Ffprobe = $fp; Ffplay = [string](Find-FFTool 'ffplay'); Version = $ffc.Version; Build = $ffc.Build; ProbeVersion = $fpc.Version; Source = $source; Directory = $directory }
    return $res
}

function Get-ExecutableArchitecture {
    param([Parameter(Mandatory)][string]$Path)
    $stream = $null; $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        if ($stream.Length -lt 64) { return 'Unknown' }
        $reader = New-Object System.IO.BinaryReader($stream)
        $null = $stream.Seek(60, [System.IO.SeekOrigin]::Begin)
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 6)) { return 'Unknown' }
        $null = $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin)
        if ($reader.ReadUInt32() -ne 0x00004550) { return 'Unknown' }
        $machine = $reader.ReadUInt16()
        switch ($machine) {
            332 { return 'x86' }
            34404 { return 'x64' }
            43620 { return 'arm64' }
            default { return 'Unknown' }
        }
    } catch { return 'Unknown' }
    finally { if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() } }
}

function Test-FFmpegRuntimeRequirements {
    <# Verifies an active or staged runtime against the canonical manifest and the existing capability parser. #>
    param([string]$FfmpegPath = '', [string]$FfprobePath = '', [string]$Source = '', [string]$ExpectedVersion = '')
    $detection = $null
    if (-not $FfmpegPath -and -not $FfprobePath) {
        $detection = Find-FFmpegInstallation
        $FfmpegPath = [string]$detection.Ffmpeg; $FfprobePath = [string]$detection.Ffprobe
        $Source = [string]$detection.Source
    } elseif (-not $Source) { $Source = 'Candidate' }
    $definition = Get-ExternalLibraryDefinition -Id 'ffmpeg'
    if (-not $ExpectedVersion -and $Source -eq 'Bundled') { $ExpectedVersion = [string]$definition.CurrentVersion }
    $missingExecutables = @(); $missingEncoders = @(); $missingFilters = @(); $version = ''; $architecture = 'Unknown'; $directory = ''
    $ffResult = Test-FFToolCallable -Path $FfmpegPath -Name 'ffmpeg'
    $fpResult = Test-FFToolCallable -Path $FfprobePath -Name 'ffprobe'
    if (-not $ffResult.Ok) { $missingExecutables += 'ffmpeg.exe' }
    if (-not $fpResult.Ok) { $missingExecutables += 'ffprobe.exe' }
    if ($FfmpegPath) { try { $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($FfmpegPath)) } catch { $directory = '' } }
    if ($ffResult.Ok) { $version = [string]$ffResult.Version; $architecture = Get-ExecutableArchitecture -Path $FfmpegPath }
    $capabilityPath = ''
    if ($FfmpegPath) { try { $capabilityPath = [System.IO.Path]::GetFullPath($FfmpegPath) } catch { $capabilityPath = $FfmpegPath } }
    if ($missingExecutables.Count -eq 0) {
        $capabilities = $null
        $cached = Get-FFCapabilities
        if ($cached.Loaded -and $cached.Path -and [string]::Equals([string]$cached.Path, $capabilityPath, [StringComparison]::OrdinalIgnoreCase)) { $capabilities = $cached }
        else { $capabilities = Initialize-FFCapabilities -Force -FfmpegPath $FfmpegPath }
        foreach ($name in @($definition.RequiredEncoders)) { if (-not $capabilities.Encoders.ContainsKey([string]$name)) { $missingEncoders += [string]$name } }
        foreach ($name in @($definition.RequiredFilters)) { if (-not $capabilities.Filters.ContainsKey([string]$name)) { $missingFilters += [string]$name } }
    }
    $architectureReady = [string]::Equals($architecture, [string]$definition.Architecture, [StringComparison]::OrdinalIgnoreCase)
    $versionMatches = $true
    if ($ExpectedVersion) {
        $versionToken = ''
        if ($version -match '^(?<version>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))') { $versionToken = $Matches.version }
        $versionMatches = [string]::Equals($versionToken, $ExpectedVersion, [StringComparison]::OrdinalIgnoreCase)
    }
    $ready = ($missingExecutables.Count -eq 0 -and $missingEncoders.Count -eq 0 -and $missingFilters.Count -eq 0 -and $architectureReady -and $versionMatches)
    $details = @()
    if ($missingExecutables.Count -gt 0) { $details += ('Unavailable executables: ' + ($missingExecutables -join ', ')) }
    if ($missingEncoders.Count -gt 0) { $details += ('Missing encoders: ' + ($missingEncoders -join ', ')) }
    if ($missingFilters.Count -gt 0) { $details += ('Missing filters: ' + ($missingFilters -join ', ')) }
    if (-not $architectureReady) { $details += ('Architecture mismatch: expected ' + [string]$definition.Architecture + ', detected ' + $architecture) }
    if (-not $versionMatches) { $details += ('Version mismatch: expected ' + $ExpectedVersion + ', detected ' + $version) }
    if ($ready) { $details += 'The runtime meets the manifest acceptance requirements.' }
    return [pscustomobject]@{ Ready = $ready; MissingExecutables = @($missingExecutables); MissingEncoders = @($missingEncoders); MissingFilters = @($missingFilters); Version = $version; ExpectedVersion = $ExpectedVersion; VersionMatches = $versionMatches; Architecture = $architecture; ArchitectureMatches = $architectureReady; Source = $Source; Directory = $directory; Detail = ($details -join ' ') }
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
    if ($script:Hooks.FindCommand -and -not (& $script:Hooks.FindCommand 'winget')) { return $null }
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

Export-ModuleMember -Function Set-FFManagerHooks, Get-FFmpegPath, Get-FFprobePath, Get-BundledFFmpegPath, Get-BundledFFprobePath, Get-FFmpegInfo, Get-LastUpdateStatus, Update-ProcessPath, Find-FFTool, Test-FFToolCallable, Find-FFmpegInstallation, Get-ExecutableArchitecture, Test-FFmpegRuntimeRequirements, Get-WingetPackageId, Test-WingetAvailable, ConvertFrom-WingetPackageLine, Get-FFmpegUpdateStatus, Install-FFmpegViaWinget, Update-FFmpegViaWinget
