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
            if ($k.Name -eq 'Esc' -or $k.Name -eq 'CtrlC') { $state.Cancelled = $true; return $true }
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

function Invoke-IconStyleFlow {
    # Offered once on Windows consoles that cannot be recognized as emoji-capable. The answer is remembered
    # (per-user settings file), so the question is never asked again; the Status screen can change it later.
    param([switch]$Force)
    if ((Get-IconTierInUse) -eq 'Ascii') { return }
    if (-not $Force) {
        if (-not (Test-IsWindows)) { return }
        if ($env:FFTUI_ICONS -or $env:FFTUI_ASCII -eq '1' -or $env:FFTUI_UNICODE -eq '1') { return }
        if (Get-UserSetting 'icons') { return }
        if ((Get-IconTierInUse) -ne 'Symbol') { return }
    }
    $sample = (@(0x1F3AC, 0x1F3B5, 0x1F4E6, 0x1F300) | ForEach-Object { [char]::ConvertFromUtf32($_) }) -join '  '
    $lines = @('Your terminal is using simple symbol icons. Colorful emoji icons look nicer and work in Windows Terminal.',
        '', ('Preview: ' + $sample), '',
        'If you can see four small pictures above (not empty boxes or question marks), emoji will work for you.',
        'Your choice is saved for this Windows account and you will not be asked again. You can change it later in FFmpeg Status / Settings.')
    $yes = Show-Confirm -Title 'Use colorful emoji icons?' -Lines $lines -Default $true -YesLabel 'Yes, use emoji icons' -NoLabel 'No, keep the simple symbols' -Kind Info
    $v = $(if ($yes) { 'emoji' } else { 'symbol' })
    $saved = Set-UserSetting 'icons' $v
    Initialize-Theme -Ansi (Test-AnsiMode) -Unicode $(if ($yes) { 'Emoji' } else { 'Symbol' })
    if (-not $saved) { $script:StartupNotice = 'The icon choice could not be saved, so you may be asked again next time.' }
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
        $uni = switch (Get-IconTierInUse) { 'Emoji' { 'emoji icons' } 'Symbol' { 'console-safe symbol icons' } default { 'ASCII icons' } }
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
        $render = {
            Write-Header
            Write-UiBlank
            Write-UiSegments @(@(((Get-Icon 'Settings') + '  '), 'PrimaryAccent'), @('FFmpeg Status / Settings', 'Title'))
            Write-Rule
            Write-KeyValueTable -Rows $rows -LabelWidth 13 -Indent 1
            Write-Rule
        }.GetNewClosure()
        $items = @(
            @{ Label = 'Re-scan capabilities'; Icon = 'Retry'; Desc = 'Read the encoders, formats and filters again (use after updating FFmpeg).'; Value = 'scan' },
            @{ Label = 'Check for updates'; Icon = 'Update'; Desc = 'Ask Windows Package Manager whether a newer FFmpeg is available.'; Value = 'update' },
            @{ Label = 'Re-detect FFmpeg paths'; Icon = 'Search'; Desc = 'Look for ffmpeg and ffprobe again, for example after installing them manually.'; Value = 'paths' },
            @{ Label = 'Icon style (emoji or symbols)'; Icon = 'Settings'; Desc = 'Choose colorful emoji icons or simple symbols; the choice is remembered.'; Value = 'icons' },
            @{ Label = 'Back'; Icon = 'Back'; Desc = 'Return to the main menu.'; Value = 'back' }
        )
        $r = Show-Menu -Items $items -AllowBack -InfoRenderer $render -InfoLines ($rows.Count + 9)
        if ($r.Action -ne 'Select') { return }
        switch ($r.Item.Value) {
            'back' { return }
            'scan' { $null = Initialize-CapabilityScan -Force }
            'icons' { Invoke-IconStyleFlow -Force }
            'update' { Invoke-UpdateFlow -Interactive }
            'paths' {
                Update-ProcessPath
                $d = Find-FFmpegInstallation
                if ($d.Status -eq 'Ready') { $null = Initialize-CapabilityScan -Force }
                else { $null = Show-Notice -Title 'FFmpeg could not be detected' -Lines @($(if ($d.Detail) { $d.Detail } else { 'ffmpeg or ffprobe is not available on PATH.' })) -Kind Warning }
            }
        }
    }
}

# ---- main menu ----------------------------------------------------------------------------------------

function Get-MainMenuItems {
    $items = @(
        @{ Icon = 'Video'; Label = 'Convert Video Format'; Desc = 'Convert a video to another container or video format.'; Value = 'ConvertVideo' },
        @{ Icon = 'Audio'; Label = 'Convert Audio Format'; Desc = 'Convert an audio file to MP3, AAC, FLAC, WAV, Opus, and other supported formats.'; Value = 'ConvertAudio' },
        @{ Icon = 'Extract'; Label = 'Extract Audio from Video'; Desc = 'Save one audio stream from a video as a separate audio file.'; Value = 'ExtractAudio' },
        @{ Icon = 'Cut'; Label = 'Trim / Cut Media'; Desc = 'Keep only a selected time range from a video or audio file.'; Value = 'Trim' },
        @{ Icon = 'Merge'; Label = 'Merge Media'; Desc = 'Join multiple compatible video or audio files into one output.'; Value = 'Merge' },
        @{ Icon = 'Compress'; Label = 'Compress Media'; Desc = 'Reduce video or audio file size with guided quality controls.'; Value = 'Compress' },
        @{ Icon = 'Resize'; Label = 'Resize / Scale Video'; Desc = 'Change video dimensions while controlling aspect ratio and fit behavior.'; Value = 'Resize' },
        @{ Icon = 'Gif'; Label = 'Video to GIF'; Desc = 'Convert a video or selected clip into an animated GIF.'; Value = 'Gif' },
        @{ Icon = 'Frames'; Label = 'Extract Frames / Images'; Desc = 'Save frames from a video as JPG, PNG, WebP, or another supported image format.'; Value = 'Frames' },
        @{ Icon = 'AudioTools'; Label = 'Audio Tools'; Desc = 'Adjust volume, sample rate, channels, speed, and other common audio properties.'; Value = 'AudioTools' },
        @{ Icon = 'Subtitle'; Label = 'Subtitle Tools'; Desc = 'Extract, add, remove, copy, or burn subtitle streams.'; Value = 'SubtitleTools' },
        @{ Icon = 'FrameRate'; Label = 'Change Frame Rate'; Desc = 'Convert a video to a different playback frame rate.'; Value = 'FrameRate' },
        @{ Icon = 'Filters'; Label = 'Filters & Color'; Desc = 'Apply common visual filters and color adjustments.'; Value = 'Filters' },
        @{ Icon = 'Rotate'; Label = 'Crop / Rotate / Flip'; Desc = 'Crop the frame or change video orientation.'; Value = 'Transform' },
        @{ Icon = 'Text'; Label = 'Text & Watermark'; Desc = 'Add text or an image/logo overlay to video.'; Value = 'Overlay' },
        @{ Icon = 'Speed'; Label = 'Change Playback Speed'; Desc = 'Make video/audio slower or faster while controlling synchronization.'; Value = 'Speed' },
        @{ Icon = 'Stream'; Label = 'Streaming / HLS'; Desc = 'Work with supported streams and create common HLS outputs.'; Value = 'Streaming' },
        @{ Icon = 'Info'; Label = 'Media Information'; Desc = 'Inspect a media file using ffprobe in a readable summary.'; Value = 'MediaInfo' },
        @{ Icon = 'Remux'; Label = 'Remux & Streams'; Desc = 'Change a container with no re-encoding, keep chosen tracks, fix track languages.'; Value = 'Remux' },
        @{ Icon = 'Tag'; Label = 'Metadata & Chapters'; Desc = 'Edit tags, remove metadata, add chapters, or attach cover art without re-encoding.'; Value = 'Metadata' },
        @{ Icon = 'Image'; Label = 'Images & Slideshows'; Desc = 'Slideshows from pictures, audio to video, or a thumbnail sheet of a video.'; Value = 'Images' },
        @{ Icon = 'Enhance'; Label = 'Video Enhancement'; Desc = 'Deinterlace, denoise, stabilize, add bars for an aspect ratio, reverse or loop.'; Value = 'Enhance' },
        @{ Icon = 'Record'; Label = 'Record / Capture'; Desc = 'Record the screen, a webcam or a microphone for a set time.'; Value = 'Capture' },
        @{ Icon = 'Chart'; Label = 'Analyze & Detect'; Desc = 'Measure loudness, find silence, black frames and cuts, or compare video quality.'; Value = 'Analyze' },
        @{ Icon = 'Batch'; Label = 'Batch Convert Folder'; Desc = 'Convert every video or audio file in a folder with the same settings.'; Value = 'Batch' },
        @{ Icon = 'Code'; Label = 'Advanced FFmpeg'; Desc = 'Browse every codec and filter, test the GPU, or run your own FFmpeg options.'; Value = 'Advanced' },
        @{ Icon = 'Settings'; Label = 'FFmpeg Status / Settings'; Desc = 'View FFmpeg version, detected capabilities, paths, and update status.'; Value = 'Status' },
        @{ Icon = 'Quit'; Label = 'Exit'; Desc = 'Close FFmpeg User Manager. Nothing is left running.'; Value = 'Quit' }
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
        'Remux' { Start-RemuxStreamsWorkflow }
        'Metadata' { Start-MetadataChaptersWorkflow }
        'Images' { Start-ImagesAndVisualsWorkflow }
        'Enhance' { Start-VideoEnhanceWorkflow }
        'Capture' { Start-CaptureWorkflow }
        'Analyze' { Start-AnalyzeWorkflow }
        'Batch' { Start-BatchWorkflow }
        'Advanced' { Start-AdvancedWorkflow }
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
        $r = Show-Menu -Items $items -ShowHeader -InitialIndex $idx -FooterNote $note -AllowQuit
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
    $ansi = Test-AnsiSupport; $uni = Get-IconTier
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
        Invoke-IconStyleFlow
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

Export-ModuleMember -Function Invoke-IconStyleFlow, Show-FFmpegMissingFlow, Invoke-UpdateFlow, Initialize-CapabilityScan, Show-FFmpegStatus, Get-MainMenuItems, Invoke-MainMenuAction, Start-MainMenu, Start-FFmpegTuiApp, Invoke-WithSpinner
