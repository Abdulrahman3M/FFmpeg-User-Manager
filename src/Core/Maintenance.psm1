# Maintenance.psm1 - "Check & Maintain FFmpeg Setup": a guided health check. Every step explains what it does, gives an
# example and says whether the internet is used; nothing is downloaded or installed unless the user agrees to that step.
Set-StrictMode -Version 2.0

function Test-EmojiFontInstalled {
    # Segoe UI Emoji ships with Windows 10/11. $null = cannot be determined (non-Windows).
    if (-not (Test-IsWindows)) { return $null }
    try {
        if ($env:WINDIR -and (Test-Path -LiteralPath (Join-Path $env:WINDIR 'Fonts\seguiemj.ttf'))) { return $true }
        $k = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction Stop
        return [bool](@($k.PSObject.Properties | Where-Object { $_.Name -like 'Segoe UI Emoji*' }).Count)
    } catch { return $false }
}

function Get-TerminalEmojiHint {
    # Best-effort only: the application cannot see how the terminal really draws a glyph; the preview in step 4 is the real test.
    if (-not (Test-IsWindows)) { return 'not applicable on this system' }
    if ($env:WT_SESSION) { return 'Windows Terminal detected (draws emoji well)' }
    if ($env:TERM_PROGRAM -or $env:ConEmuANSI -eq 'ON') { return 'a modern terminal was detected' }
    return 'the classic console host (cmd/conhost): emoji support is limited, the preview in step 4 shows what you really get'
}

function Confirm-MaintenanceStep {
    param([string]$Title, [string[]]$What, [string]$Example, [string]$Internet)
    $lines = @($What) + @('', ('Example: ' + $Example), '', ('Internet: ' + $Internet))
    return (Show-Confirm -Title $Title -Lines $lines -Default $true -YesLabel 'Yes, run this step' -NoLabel 'No, skip this step' -Kind Info)
}

function Start-MaintenanceTool {
    $res = New-Object System.Collections.Generic.List[string]
    $intro = Show-Confirm -Title 'Check & Maintain FFmpeg Setup' -Lines @(
        'This tool looks for problems with FFmpeg and with how this application shows its screens, one step at a time.',
        'Before each step you are told what it does, shown an example, and told whether it uses the internet.',
        'Nothing is downloaded or installed unless you say yes to that step.', '',
        'Steps: 1 FFmpeg and ffprobe  2 FFmpeg updates  3 Emoji font  4 Icon style  5 Capability re-scan.') -Default $true -YesLabel 'Start the check' -NoLabel 'Back to the main menu' -Kind Info
    if (-not $intro) { return }

    if (Confirm-MaintenanceStep -Title 'Step 1 of 5: Is FFmpeg installed and working?' -What @('Looks for ffmpeg and ffprobe, and really starts them to prove they work.', 'If one is missing or broken you are offered an automatic installation with Windows Package Manager (winget).') -Example 'FFmpeg is not found after you installed it by hand because the PATH is stale; the tool re-checks the PATH first.' -Internet 'only if you choose to install FFmpeg (a download of about 100 MB).') {
        Update-ProcessPath
        $d = Find-FFmpegInstallation
        if ($d.Status -ne 'Ready') { if (Show-FFmpegMissingFlow $d) { $res.Add('FFmpeg: repaired / installed') } else { $res.Add('FFmpeg: still missing (not installed)') } }
        else { $res.Add('FFmpeg: OK (' + (Get-FFmpegInfo).Version + ')') }
    } else { $res.Add('FFmpeg check: skipped') }

    if (Confirm-MaintenanceStep -Title 'Step 2 of 5: Is there a newer FFmpeg?' -What @('Asks Windows Package Manager whether a newer FFmpeg is available.', 'If there is one, you are asked before anything is downloaded; updating replaces only the winget-managed FFmpeg.') -Example 'You have FFmpeg 7.1 and version 8.0 is available: you choose Update now or Continue.' -Internet 'yes, to check; a download only if you choose to update.') {
        Invoke-UpdateFlow -Interactive
        $u = Get-LastUpdateStatus
        $res.Add('Updates: ' + $(switch ($u.State) { 'UpToDate' { 'FFmpeg is up to date' } 'UpdateAvailable' { 'an update is available (not installed)' } 'Unmanaged' { 'FFmpeg is not managed by winget' } default { 'could not be determined' } }))
    } else { $res.Add('Update check: skipped') }

    $font = Test-EmojiFontInstalled
    if (Confirm-MaintenanceStep -Title 'Step 3 of 5: Is the emoji font available?' -What @('Emoji icons need the Segoe UI Emoji font, which Windows 10 and 11 include.', 'This step only checks that it exists on this computer.') -Example 'On some Windows Server or stripped-down editions the font is missing and emoji appear as empty boxes.' -Internet 'no.') {
        if ($null -eq $font) { $res.Add('Emoji font: not applicable on this system') }
        elseif ($font) { $res.Add('Emoji font: Segoe UI Emoji is installed'); $res.Add('Terminal: ' + (Get-TerminalEmojiHint)) }
        else {
            $res.Add('Emoji font: Segoe UI Emoji is MISSING')
            $null = Show-Notice -Title 'Segoe UI Emoji was not found' -Kind Warning -Lines @('Without it, emoji icons may show as empty boxes. Segoe UI Emoji is part of Windows and is not offered as a separate download, so this application does not download any font.', 'Use the simple symbol icons instead (next step). Nothing else is changed and no system repair is started.')
        }
    } else { $res.Add('Emoji font check: skipped') }

    if (Confirm-MaintenanceStep -Title 'Step 4 of 5: Choose the icon style' -What @('Lets you pick colorful emoji icons or simple symbols, with a preview, and remembers the choice.') -Example 'If you saw boxes in the preview of step 3, choose the simple symbols.' -Internet 'no.') {
        Invoke-IconStyleFlow -Force; $res.Add('Icon style: ' + (Get-IconTierInUse))
    } else { $res.Add('Icon style: unchanged') }

    if (Confirm-MaintenanceStep -Title 'Step 5 of 5: Re-read what FFmpeg can do' -What @('Reads the encoders, formats and filters of your FFmpeg again so the menus match it exactly.') -Example 'After updating FFmpeg, a new encoder appears in the codec lists.' -Internet 'no.') {
        $null = Initialize-CapabilityScan -Force; $res.Add('Capabilities: re-scanned')
    } else { $res.Add('Capability re-scan: skipped') }

    $null = Show-Notice -Title 'Maintenance finished' -Kind Success -Lines @($res.ToArray())
}

Export-ModuleMember -Function Test-EmojiFontInstalled, Get-TerminalEmojiHint, Start-MaintenanceTool
