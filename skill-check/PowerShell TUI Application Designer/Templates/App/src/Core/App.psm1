# App.psm1 - the application: main menu loop and the actions. Business logic lives in Core modules, never in the TUI modules.
Set-StrictMode -Version 2.0

function Get-AppVersion {
    param([string]$Root)
    $f = Join-Path $Root 'VERSION'
    if (Test-Path -LiteralPath $f) { return ((Get-Content -LiteralPath $f -TotalCount 1)).Trim() }
    return '0.0.0'
}

function Test-PersonName {
    # Returns $null when valid, else the message. Pure function: unit tested without any UI.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 'Please type a name.' }
    if ($Text.Length -gt 40) { return 'The name can have at most 40 characters.' }
    return $null
}

function Invoke-DemoForm {
    $name = Read-ValidatedInput -Prompt 'Your name' -Help 'Any name, up to 40 characters.' -Example 'Ada Lovelace' -Validate { param($t) Test-PersonName $t }
    if ($null -eq $name) { return }
    if (Show-Confirm -Title 'Save this name?' -Message ('The name is: ' + $name) -YesLabel 'Yes, save it' -YesDesc 'Store the name in your settings.' -NoLabel 'No, discard it' -NoDesc 'Keep the old value.') {
        if (Set-UserSetting -Name 'name' -Value $name) { Show-Notice -Title 'Saved' -Lines @('Hello, ' + $name + '.') -Kind Success }
        else { Show-Notice -Title 'Could not save' -Lines @('The settings file is not writable. Nothing was changed.') -Kind Error }
    }
}

function Invoke-DemoCommand {
    # External program from an argument array; here the host PowerShell itself, which exists on every platform.
    $ps = Get-CurrentPowerShellPath
    if (-not $ps) { Show-Notice -Title 'PowerShell not found' -Lines @('Cannot locate the PowerShell executable.') -Kind Error; return }
    $r = Invoke-External -FilePath $ps -Arguments @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') -TimeoutSec 30
    if ($r.Started -and $r.ExitCode -eq 0) { Show-Notice -Title 'Command finished' -Lines @('PowerShell version: ' + $r.StdOut.Trim()) -Kind Success }
    else { Write-AppLog ('demo command failed: exit ' + $r.ExitCode + ' ' + $r.Error) 'ERROR'; Show-Notice -Title 'Command failed' -Lines @('Exit code ' + $r.ExitCode + '. Details were written to the log file.') -Kind Error }
}

function Invoke-IconStyleChoice {
    $cur = Get-IconTierInUse
    $items = @(
        (New-MenuItem -Label 'Emoji icons' -Desc 'Colorful icons; needs a terminal that draws emoji (Windows Terminal, most Linux terminals).' -Value 'emoji' -Icon 'Run'),
        (New-MenuItem -Label 'Simple symbols' -Desc 'Single-column symbols that every console font can draw.' -Value 'symbol' -Icon 'Settings'),
        (New-MenuItem -Label 'Plain text' -Desc 'ASCII only: use this when icons show as empty boxes.' -Value 'ascii' -Icon 'Item')
    )
    $r = Show-Menu -Title ('Icon style (now: ' + $cur + ')') -Description 'The choice is remembered for next time.' -Items $items
    if ($r) {
        $tier = (Get-Culture).TextInfo.ToTitleCase($r)
        Set-IconTier $tier
        if ($r -ne 'ascii') { [void](Set-UserSetting -Name 'icons' -Value $r) }
    }
}

function Show-AppAbout {
    param([string]$Root)
    $ri = Get-RuntimeInfo
    Show-Notice -Title 'About {{AppName}}' -Lines @(('Version ' + (Get-AppVersion $Root) + '.'), ('Running on ' + $ri.Platform + ' with PowerShell ' + $ri.PowerShell + ' (' + $ri.Edition + ').'), ('Icons: ' + (Get-IconTierInUse) + '.')) -Kind Info
}

function Start-TuiApp {
    param([Parameter(Mandatory)][string]$Root)
    $quit = $false
    while (-not $quit) {
        $items = @(
            (New-MenuItem -Label 'Demo form' -Desc 'Type a value with help, an example and validation.' -Value 'form' -Icon 'Form'),
            (New-MenuItem -Label 'Run a command' -Desc 'Start an external program safely and show its result.' -Value 'cmd' -Icon 'Run'),
            (New-MenuItem -Label 'Icon style' -Desc 'Choose emoji, simple symbols or plain text.' -Value 'icons' -Icon 'Settings'),
            (New-MenuItem -Label 'About' -Desc 'Version, platform and PowerShell edition.' -Value 'about' -Icon 'About'),
            (New-MenuItem -Label 'Exit' -Desc 'Close {{AppName}}. Nothing is left running.' -Value 'exit' -Icon 'Exit')
        )
        $choice = Show-Menu -Title '{{AppName}}' -Description 'Choose a number and press Enter.' -Items $items
        switch ($choice) {
            'form' { Invoke-DemoForm }
            'cmd' { Invoke-DemoCommand }
            'icons' { Invoke-IconStyleChoice }
            'about' { Show-AppAbout -Root $Root }
            'exit' { $quit = $true }
            $null { $quit = $true }   # Esc on the main menu leaves the app
        }
    }
}

Export-ModuleMember -Function Get-AppVersion, Test-PersonName, Start-TuiApp
