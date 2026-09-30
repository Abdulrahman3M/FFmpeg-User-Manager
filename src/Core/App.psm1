# App.psm1 - application bootstrap: terminal setup, FFmpeg lifecycle (detect/install/update), capability scan,
# main menu and the FFmpeg status/settings screen.
Set-StrictMode -Version 2.0

$script:StartupNotice = ''

# ---- FFmpeg lifecycle screens ------------------------------------------------------------------

function Invoke-WithSpinner {
    # Runs a manager operation that accepts an OnTick callback while animating a busy screen.
    # Esc/Q during the operation cancels it (returns Cancelled = $true).
    param([string]$Title, [string]$Message, [scriptblock]$Operation)
    $state = @{ Tick = 0; Last = ''; Cancelled = $false }
    $onTick = {
        param($elapsed, $last)
        $state.Tick++
        if ($last) { $state.Last = $last }
        Show-BusyScreen -Title $Title -Message ($(if ($state.Last) { $state.Last } else { $Message })) -Tick $state.Tick
        if (Test-TuiKeyAvailable) {
            $k = Read-TuiKey
            if ($k.Name -eq 'Esc' -or $k.Name -eq 'CtrlC' -or ($k.Name -eq 'Char' -and $k.Char.ToUpperInvariant() -eq 'Q')) { $state.Cancelled = $true; return $true }
        }
        return $false
    }.GetNewClosure()
    Show-BusyScreen -Title $Title -Message $Message -Tick 0
    $result = & $Operation $onTick
    return @{ Result = $result; Cancelled = $state.Cancelled }
}

function Show-FFmpegMissingFlow {
    <# Returns $true when a usable FFmpeg + ffprobe is available, $false when the user chose to exit. #>
    param($Detection)
    while ($true) {
        $wingetOk = Test-WingetAvailable
        $title = 'FFmpeg was not found.'
        $lines = @('FFmpeg is required to use this application.')
        switch ($Detection.Status) {
            'FfprobeMissing' { $title = 'ffprobe is missing.'; $lines = @('ffmpeg was found, but ffprobe (used to read media details) is not available.', $Detection.Detail) }
            'Broken' { $title = 'FFmpeg cannot be started.'; $lines = @($Detection.Detail) }
        }
        $actions = @()
        $dim = @()
        if ($wingetOk) {
            $lines += ''; $lines += 'This application can install FFmpeg automatically with Windows Package Manager (winget).'
            $lines += ('Package: ' + (Get-WingetPackageId))
            $actions += , @('I', 'Install FFmpeg automatically')
            if ($Detection.Status -ne 'Missing') { $dim += 'A new copy will be installed next to your existing files; nothing is replaced or deleted.' }
        } else {
            $lines += ''; $lines += 'Automatic installation is not available because Windows Package Manager (winget) was not found on this computer.'
            $dim += 'Install FFmpeg manually from https://ffmpeg.org/download.html (or install winget), make sure ffmpeg and ffprobe are on your PATH, then choose Retry.'
        }
        $actions += , @('R', 'Retry detection', 'PrimaryAccent')
        $actions += , @('Q', 'Exit', 'Warning')
        $act = Show-Notice -Title $title -Lines $lines -Kind Warning -Actions $actions -ShowHeader -DimLines $dim
        if ($act -eq 'Q' -or $act -eq 'CTRLC') { return $false }
        if ($act -eq 'R') {
            Update-ProcessPath
            $Detection = Find-FFmpegInstallation
            if ($Detection.Status -eq 'Ready') { return $true }
            continue
        }
        if ($act -eq 'I') {
            $go = Show-Confirm -Title 'Install FFmpeg?' -Lines @("winget will download and install '$(Get-WingetPackageId)' (FFmpeg and ffprobe).", 'You may be asked to accept the package source terms. Press Esc while it runs to cancel.') -Default $true -YesLabel 'Install now' -NoLabel 'Cancel' -Kind Info
            if (-not $go) { continue }
            $run = Invoke-WithSpinner -Title 'Installing FFmpeg' -Message 'Waiting for winget...' -Operation { param($tick) Install-FFmpegViaWinget -OnTick $tick }
            $res = $run.Result
            if ($run.Cancelled) { $null = Show-Notice -Title 'Installation cancelled' -Lines @('No changes were confirmed. You can try again.') -Kind Warning; $Detection = Find-FFmpegInstallation; if ($Detection.Status -eq 'Ready') { return $true }; continue }
            if ($res.Ok) {
                $null = Show-Notice -Title 'FFmpeg installed' -Lines @($res.Message) -Kind Success -Actions @(, @('Enter', 'Continue'))
                return $true
            }
            while ($true) {
                $a = Show-Notice -Title 'The installation could not be completed' -Lines @($res.Message) -Kind Error -Actions @(@('D', 'Show technical details'), @('R', 'Retry'), @('Q', 'Exit'))
                if ($a -eq 'D') { Show-TextViewer -Title 'winget output' -Lines @($res.Detail -split "`r?`n"); continue }
                if ($a -eq 'Q' -or $a -eq 'CTRLC') { return $false }
                break
            }
            $Detection = Find-FFmpegInstallation
            if ($Detection.Status -eq 'Ready') { return $true }
        }
    }
}

function Invoke-UpdateFlow {
    # Quick update check at startup / from the status screen. Never blocks on failure.
    param([switch]$Interactive)
    $run = Invoke-WithSpinner -Title 'Checking for FFmpeg updates' -Message 'Asking Windows Package Manager... (Esc to skip)' -Operation { param($tick) Get-FFmpegUpdateStatus -OnTick $tick }
    if ($run.Cancelled) { $script:StartupNotice = 'The update check was skipped.'; return }
    $st = $run.Result
    switch ($st.State) {
        'UpdateAvailable' {
            $act = Show-Notice -Title 'FFmpeg update available' -Lines @("Installed: $($st.Installed)", "Available: $($st.Available)") -Kind Info -Icon 'Update' -Actions @(@('U', 'Update now'), @('C', 'Continue without updating')) -ShowHeader
            if ($act -eq 'U') {
                $up = Invoke-WithSpinner -Title 'Updating FFmpeg' -Message 'Waiting for winget...' -Operation { param($tick) Update-FFmpegViaWinget -OnTick $tick }
                if ($up.Cancelled) { $script:StartupNotice = 'The update was cancelled.'; $null = Find-FFmpegInstallation; return }
                $r = $up.Result
                if ($r.Ok) { $null = Show-Notice -Title 'FFmpeg updated' -Lines @($r.Message, "Version: $($r.Version)") -Kind Success; $script:StartupNotice = '' }
                else {
                    $script:StartupNotice = 'The FFmpeg update did not complete; continuing with the installed version.'
                    $a = Show-Notice -Title 'The update could not be completed' -Lines @($r.Message, 'You can keep using the installed version.') -Kind Warning -Actions @(@('D', 'Show technical details'), @('C', 'Continue'))
                    if ($a -eq 'D') { Show-TextViewer -Title 'winget output' -Lines @($r.Detail -split "`r?`n") }
                    $null = Find-FFmpegInstallation
                }
            }
        }
        'UpToDate' { $script:StartupNotice = '' }
        default { $script:StartupNotice = $st.Message }
    }
    if ($Interactive -and $st.State -in @('Unknown', 'Unmanaged')) { $null = Show-Notice -Title 'Update status' -Lines @($st.Message) -Kind Info }
}

function Initialize-CapabilityScan {
    param([switch]$Force)
    $state = @{ n = 0 }
    $onProg = { param($what, $n, $total) Show-BusyScreen -Title 'Scanning FFmpeg capabilities' -Message ("Reading $what ($n of $total)") -Tick $n }.GetNewClosure()
    Show-BusyScreen -Title 'Scanning FFmpeg capabilities' -Message 'Reading formats, codecs and filters...' -Tick 0
    $c = Initialize-FFCapabilities -Force:$Force -OnProgress $onProg
    return $c
}

# ---- status / settings ---------------------------------------------------------------------------

function Show-FFmpegStatus {
    while ($true) {
        $t = Get-FFmpegInfo
        $rt = Get-RuntimeInfo
        $cap = Get-FFCapabilityStatus
        $upd = Get-LastUpdateStatus
        $updText = switch ($upd.State) { 'NotChecked' { 'Not checked yet' } 'UpdateAvailable' { "Update available: $($upd.Available)" } 'UpToDate' { 'Up to date' } 'Unmanaged' { 'Not managed by winget' } default { 'Unknown' } }
        if ($upd.Message -and $upd.State -in @('Unknown', 'Unmanaged')) { $updText += ' - ' + $upd.Message }
        $hw = if ($cap.Loaded -and $cap.HwAccels.Count -gt 0) { ($cap.HwAccels -join ', ') } else { 'none detected' }
        $capText = if ($cap.Loaded) { "Loaded at $($cap.At.ToString('HH:mm:ss')): $($cap.Encoders) encoders, $($cap.Decoders) decoders, $($cap.Muxers) muxers, $($cap.Demuxers) demuxers, $($cap.Filters) filters, $($cap.Protocols) protocols" } else { 'Not loaded' }
        $ansiText = if (Test-AnsiMode) { 'Enabled (ANSI colors)' } else { 'Disabled (legacy console colors)' }
        $uni = if ((Get-BoxChars).H -eq '-') { 'ASCII fallback icons' } else { 'Unicode icons' }
        $pm = if (Test-WingetAvailable) { 'winget available (' + (Get-WingetPackageId) + ')' } else { 'winget not available' }
        $rows = @(
            @('Application', ((Get-AppName) + ' v' + (Get-AppVersion))),
            @('FFmpeg', $(if ($t.Ffmpeg) { $t.Ffmpeg } else { 'not found' })),
            @('ffprobe', $(if ($t.Ffprobe) { $t.Ffprobe } else { 'not found' })),
            @('ffplay', $(if ($t.Ffplay) { $t.Ffplay } else { 'not found (optional)' })),
            @('Version', $(if ($t.Version) { $t.Version } else { 'unknown' })),
            @('PowerShell', ("{0} ({1})" -f $rt.PSVersion, $rt.Edition)),
            @('Terminal', ($ansiText + '; ' + $uni)),
            @('Accelerators', $hw),
            @('Capabilities', $capText),
            @('Package mgr', $pm),
            @('Updates', $updText)
        )
        Hide-Cursor
        Start-Frame
        Write-Header
        Write-UiBlank
        Write-UiSegments @(@(((Get-Icon 'Settings') + '  '), 'PrimaryAccent'), @('FFmpeg Status / Settings', 'Title'))
        Write-Rule
        Write-KeyValueTable -Rows $rows -LabelWidth 13 -Indent 1
        Write-Rule
        Write-KeyHints @(@('C', 'Re-scan capabilities'), @('U', 'Check for updates'), @('P', 'Re-detect FFmpeg paths'), @('B', 'Back'))
        Stop-Frame
        $k = Read-TuiKey
        if ($k.Name -eq 'Esc' -or $k.Name -eq 'CtrlC') { return }
        if ($k.Name -eq 'Char') {
            switch ($k.Char.ToUpperInvariant()) {
                'B' { return }
                'C' { $null = Initialize-CapabilityScan -Force }
                'U' { Invoke-UpdateFlow -Interactive }
                'P' {
                    Update-ProcessPath
                    $d = Find-FFmpegInstallation
                    if ($d.Status -eq 'Ready') { $null = Initialize-CapabilityScan -Force }
                    else { $null = Show-Notice -Title 'FFmpeg could not be detected' -Lines @($(if ($d.Detail) { $d.Detail } else { 'ffmpeg or ffprobe is not available on PATH.' })) -Kind Warning }
                }
            }
        }
    }
}

# ---- main menu ----------------------------------------------------------------------------------------

function Get-MainMenuItems {
    $items = @(
        @{ Key = '1'; Icon = 'Video'; Label = 'Convert Video Format'; Desc = 'Convert a video to another container or video format.'; Value = 'ConvertVideo' },
        @{ Key = '2'; Icon = 'Audio'; Label = 'Convert Audio Format'; Desc = 'Convert an audio file to MP3, AAC, FLAC, WAV, Opus, and other supported formats.'; Value = 'ConvertAudio' },
        @{ Key = '3'; Icon = 'Extract'; Label = 'Extract Audio from Video'; Desc = 'Save one audio stream from a video as a separate audio file.'; Value = 'ExtractAudio' },
        @{ Key = '4'; Icon = 'Cut'; Label = 'Trim / Cut Media'; Desc = 'Keep only a selected time range from a video or audio file.'; Value = 'Trim' },
        @{ Key = '5'; Icon = 'Merge'; Label = 'Merge Media'; Desc = 'Join multiple compatible video or audio files into one output.'; Value = 'Merge' },
        @{ Key = '6'; Icon = 'Compress'; Label = 'Compress Media'; Desc = 'Reduce video or audio file size with guided quality controls.'; Value = 'Compress' },
        @{ Key = '7'; Icon = 'Resize'; Label = 'Resize / Scale Video'; Desc = 'Change video dimensions while controlling aspect ratio and fit behavior.'; Value = 'Resize' },
        @{ Key = '8'; Icon = 'Gif'; Label = 'Video to GIF'; Desc = 'Convert a video or selected clip into an animated GIF.'; Value = 'Gif' },
        @{ Key = '9'; Icon = 'Frames'; Label = 'Extract Frames / Images'; Desc = 'Save frames from a video as JPG, PNG, WebP, or another supported image format.'; Value = 'Frames' },
        @{ Key = 'A'; Icon = 'AudioTools'; Label = 'Audio Tools'; Desc = 'Adjust volume, sample rate, channels, speed, and other common audio properties.'; Value = 'AudioTools' },
        @{ Key = 'B'; Icon = 'Subtitle'; Label = 'Subtitle Tools'; Desc = 'Extract, add, remove, copy, or burn subtitle streams.'; Value = 'SubtitleTools' },
        @{ Key = 'C'; Icon = 'FrameRate'; Label = 'Change Frame Rate'; Desc = 'Convert a video to a different playback frame rate.'; Value = 'FrameRate' },
        @{ Key = 'D'; Icon = 'Filters'; Label = 'Filters & Color'; Desc = 'Apply common visual filters and color adjustments.'; Value = 'Filters' },
        @{ Key = 'E'; Icon = 'Rotate'; Label = 'Crop / Rotate / Flip'; Desc = 'Crop the frame or change video orientation.'; Value = 'Transform' },
        @{ Key = 'F'; Icon = 'Text'; Label = 'Text & Watermark'; Desc = 'Add text or an image/logo overlay to video.'; Value = 'Overlay' },
        @{ Key = 'G'; Icon = 'Speed'; Label = 'Change Playback Speed'; Desc = 'Make video/audio slower or faster while controlling synchronization.'; Value = 'Speed' },
        @{ Key = 'H'; Icon = 'Stream'; Label = 'Streaming / HLS'; Desc = 'Work with supported streams and create common HLS outputs.'; Value = 'Streaming' },
        @{ Key = 'I'; Icon = 'Info'; Label = 'Media Information'; Desc = 'Inspect a media file using ffprobe in a readable summary.'; Value = 'MediaInfo' },
        @{ Key = 'S'; Icon = 'Settings'; Label = 'FFmpeg Status / Settings'; Desc = 'View FFmpeg version, detected capabilities, paths, and update status.'; Value = 'Status' },
        @{ Key = 'Q'; Icon = 'Quit'; Label = 'Exit'; Desc = ''; Value = 'Quit' }
    )
    return $items
}

function Invoke-MainMenuAction {
    param([string]$Action)
    switch ($Action) {
        'ConvertVideo' { Start-ConvertVideoWorkflow }
        'ConvertAudio' { Start-ConvertAudioWorkflow }
        'ExtractAudio' { Start-ExtractAudioWorkflow }
        'Trim' { Start-TrimWorkflow }
        'Merge' { Start-MergeWorkflow }
        'Compress' { Start-CompressWorkflow }
        'Resize' { Start-ResizeWorkflow }
        'Gif' { Start-GifWorkflow }
        'Frames' { Start-ExtractFramesWorkflow }
        'AudioTools' { Start-AudioToolsWorkflow }
        'SubtitleTools' { Start-SubtitleToolsWorkflow }
        'FrameRate' { Start-FrameRateWorkflow }
        'Filters' { Start-FiltersWorkflow }
        'Transform' { Start-TransformWorkflow }
        'Overlay' { Start-OverlayWorkflow }
        'Speed' { Start-SpeedWorkflow }
        'Streaming' { Start-StreamingWorkflow }
        'MediaInfo' { Start-MediaInfoWorkflow }
        'Status' { Show-FFmpegStatus }
    }
}

function Show-UnexpectedError {
    param($ErrorRecord)
    $msg = $ErrorRecord.Exception.Message
    $detail = @($msg, '', [string]$ErrorRecord.ScriptStackTrace)
    while ($true) {
        $a = Show-Notice -Title 'Something went wrong' -Lines @('The action could not be completed, but the application is still running.', '', $msg) -Kind Error -Actions @(@('D', 'Show technical details'), @('M', 'Back to the main menu'))
        if ($a -eq 'D') { Show-TextViewer -Title 'Technical details' -Lines $detail; continue }
        return
    }
}

function Start-MainMenu {
    $items = Get-MainMenuItems
    $idx = 0
    while ($true) {
        $note = $script:StartupNotice
        $r = Show-Menu -Items $items -ShowHeader -InitialIndex $idx -FooterNote $note
        if ($r.Action -eq 'Quit' -or ($r.Action -eq 'Select' -and $r.Item.Value -eq 'Quit')) { return }
        if ($r.Action -ne 'Select') { continue }
        $idx = $r.Index
        try { Invoke-MainMenuAction ([string]$r.Item.Value) }
        catch {
            if ($_.Exception.Message -eq 'Scripted input exhausted.') { throw }
            Restore-JobCursorSafe
            Show-UnexpectedError $_
        }
    }
}

function Restore-JobCursorSafe { try { Show-Cursor } catch { } }

# ---- entry point ----------------------------------------------------------------------------------------------

function Start-FFmpegTuiApp {
    <#
      Returns a process exit code. -ScriptedInput / -TestSink are automation hooks used by the test-suite.
    #>
    param([string]$Root, [string]$ScriptedInput, [switch]$SkipUpdateCheck, [switch]$BufferOutput)
    Set-AppRoot $Root
    Set-HeaderInfo -Title ((Get-AppName) + ' v' + (Get-AppVersion))
    $rt = Get-RuntimeInfo
    if (-not $ScriptedInput) {
        if ($Host.Name -match 'ISE') {
            Write-Host 'FFmpeg User Manager cannot run inside the PowerShell ISE. Please start it from Windows Terminal, PowerShell or a console window.'
            return 2
        }
        if (-not (Test-InteractiveConsole)) {
            Write-Host 'FFmpeg User Manager needs an interactive console (input and output cannot be redirected). Start it directly from a terminal window.'
            return 2
        }
    }
    $sink = 'Console'; if ($BufferOutput) { $sink = 'Buffer' }
    $ansi = Test-AnsiSupport; $uni = Test-UnicodeIconSupport
    if ($BufferOutput) { $ansi = $false }
    Initialize-Renderer -Ansi $ansi -Unicode $uni -Sink $sink -Width $(if ($BufferOutput) { 100 } else { 0 }) -Height $(if ($BufferOutput) { 40 } else { 0 })
    if ($ScriptedInput) { Set-TuiScriptedInput $ScriptedInput }
    $exit = 0
    try {
        if (-not $ScriptedInput) { try { [Console]::TreatControlCAsInput = $true } catch { } }
        Enter-AltScreen
        Show-BusyScreen -Title 'Starting' -Message 'Checking FFmpeg...' -Tick 0
        $det = Find-FFmpegInstallation
        if ($det.Status -ne 'Ready') {
            if (-not (Show-FFmpegMissingFlow $det)) { return 0 }
        }
        if (-not $SkipUpdateCheck -and $env:FFTUI_SKIP_UPDATE -ne '1') { Invoke-UpdateFlow }
        $null = Initialize-CapabilityScan
        Set-HeaderInfo -Text ('| FFmpeg ' + (Get-FFmpegInfo).Version)
        Start-MainMenu
    } catch {
        $exit = 1
        Restore-TerminalState
        Write-Host ''
        Write-PlainError ('FFmpeg User Manager stopped because of an unexpected error: ' + $_.Exception.Message)
        if ($ScriptedInput) { Write-Host $_.ScriptStackTrace }
    } finally {
        Restore-TerminalState
        if ($ScriptedInput) { Clear-TuiScriptedInput }
    }
    return $exit
}

Export-ModuleMember -Function Show-FFmpegMissingFlow, Invoke-UpdateFlow, Initialize-CapabilityScan, Show-FFmpegStatus, Get-MainMenuItems, Invoke-MainMenuAction, Start-MainMenu, Start-FFmpegTuiApp, Invoke-WithSpinner
