# Theme.psm1 - the single source of truth for colors (semantic roles) and icons (with ASCII fallbacks).
Set-StrictMode -Version 2.0

$script:Roles = @{
    PrimaryAccent   = @{ Ansi = '96';   Console = 'Cyan' }
    SecondaryAccent = @{ Ansi = '94';   Console = 'Blue' }
    Title           = @{ Ansi = '1;97'; Console = 'White' }
    NormalText      = @{ Ansi = '97';   Console = 'Gray' }
    DimText         = @{ Ansi = '90';   Console = 'DarkGray' }
    Success         = @{ Ansi = '92';   Console = 'Green' }
    Warning         = @{ Ansi = '93';   Console = 'Yellow' }
    Error           = @{ Ansi = '91';   Console = 'Red' }
    Border          = @{ Ansi = '36';   Console = 'DarkCyan' }
    Selected        = @{ Ansi = '1;96'; Console = 'Cyan' }
    Muted           = @{ Ansi = '90';   Console = 'DarkGray' }
}

# name -> @(unicode, ascii)
$script:Icons = @{
    Video = @([string][char]::ConvertFromUtf32(0x1F3AC), '[VIDEO]')
    Audio = @([string][char]::ConvertFromUtf32(0x1F3B5), '[AUDIO]')
    Extract = @([string][char]::ConvertFromUtf32(0x1F50A), '[XAUD]')
    Cut = @([string][char]0x2702, '[CUT]')
    Merge = @([string][char]::ConvertFromUtf32(0x1F517), '[MERGE]')
    Compress = @([string][char]::ConvertFromUtf32(0x1F4E6), '[PACK]')
    Resize = @([string][char]::ConvertFromUtf32(0x1F4D0), '[SIZE]')
    Gif = @([string][char]::ConvertFromUtf32(0x1F5BC), '[GIF]')
    Frames = @([string][char]::ConvertFromUtf32(0x1F4F8), '[FRAME]')
    AudioTools = @([string][char]::ConvertFromUtf32(0x1F509), '[VOL]')
    Subtitle = @([string][char]::ConvertFromUtf32(0x1F4DD), '[SUB]')
    FrameRate = @([string][char]::ConvertFromUtf32(0x1F39E), '[FPS]')
    Filters = @([string][char]::ConvertFromUtf32(0x1F3A8), '[FX]')
    Rotate = @([string][char]::ConvertFromUtf32(0x1F504), '[ROT]')
    Text = @([string][char]::ConvertFromUtf32(0x1F58A), '[TEXT]')
    Speed = @([string][char]0x26A1, '[SPEED]')
    Stream = @([string][char]::ConvertFromUtf32(0x1F310), '[HLS]')
    Info = @([string][char]::ConvertFromUtf32(0x1F50D), '[INFO]')
    Settings = @([string][char]0x2699, '[SET]')
    Quit = @([string][char]0x274C, '[X]')
    Ok = @([string][char]0x2713, '[OK]')
    Warn = @([string][char]0x26A0, '[!]')
    Fail = @([string][char]0x2715, '[X]')
    Back = @([string][char]0x2190, '<-')
    Update = @([string][char]0x2B06, '[UP]')
    Bullet = @([string][char]0x203A, '>')
    Arrow = @([string][char]0x25B6, '>')
}

$script:UseAnsi = $false
$script:UseUnicode = $false

function Initialize-Theme {
    param([bool]$Ansi, [bool]$Unicode)
    $script:UseAnsi = $Ansi
    $script:UseUnicode = $Unicode
}

function Get-ThemeAnsi {
    param([string]$Role)
    if ($script:Roles.ContainsKey($Role)) { return $script:Roles[$Role].Ansi }
    return $script:Roles['NormalText'].Ansi
}

function Get-ThemeConsoleColor {
    param([string]$Role)
    if ($script:Roles.ContainsKey($Role)) { return $script:Roles[$Role].Console }
    return $script:Roles['NormalText'].Console
}

function Get-ThemeRoleNames { return @($script:Roles.Keys) }

function Get-Icon {
    param([string]$Name)
    if (-not $script:Icons.ContainsKey($Name)) { return '' }
    if ($script:UseUnicode) { return $script:Icons[$Name][0] }
    return $script:Icons[$Name][1]
}

function Get-IconNames { return @($script:Icons.Keys) }

function Get-BoxChars {
    if ($script:UseUnicode) {
        return [pscustomobject]@{ TL = [string][char]0x256D; TR = [string][char]0x256E; BL = [string][char]0x2570; BR = [string][char]0x256F; H = [string][char]0x2500; V = [string][char]0x2502; Bar = [string][char]0x2501; Dot = [string][char]0x00B7; Ellipsis = [string][char]0x2026; Up = [string][char]0x2191; Down = [string][char]0x2193 }
    }
    return [pscustomobject]@{ TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '-'; V = '|'; Bar = '='; Dot = '-'; Ellipsis = '...'; Up = '^'; Down = 'v' }
}

Export-ModuleMember -Function Initialize-Theme, Get-ThemeAnsi, Get-ThemeConsoleColor, Get-ThemeRoleNames, Get-Icon, Get-IconNames, Get-BoxChars
