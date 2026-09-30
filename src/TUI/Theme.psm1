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

# Icon tiers. Icons are plain characters (there are no image assets to load or lose), so the only way an icon can
# fail to show is when the terminal cannot draw the glyph. Three tiers make that impossible:
#   Emoji  - color emoji (Windows Terminal, VS Code, ConEmu, UTF-8 terminals on Linux/macOS)
#   Symbol - single-column symbols from the classic OEM (code page 437) set; drawn by every console font
#            (Consolas, Lucida Console, raster fonts), so legacy conhost always shows an icon
#   Ascii  - bracketed text tags; only for redirected output or when forced with FFTUI_ASCII=1
# name -> @(emoji, symbol, ascii). Every emoji used is a wide (two column) emoji-presentation character.
function script:U { param([int]$Code) return [string][char]::ConvertFromUtf32($Code) }
$script:Icons = @{
    Video      = @((U 0x1F3AC), (U 0x25BA), '[VIDEO]')
    Audio      = @((U 0x1F3B5), (U 0x266A), '[AUDIO]')
    Extract    = @((U 0x1F50A), (U 0x266B), '[XAUD]')
    Cut        = @((U 0x1F52A), (U 0x00F7), '[CUT]')
    Merge      = @((U 0x1F517), (U 0x256C), '[MERGE]')
    Compress   = @((U 0x1F4E6), (U 0x25BC), '[PACK]')
    Resize     = @((U 0x1F4D0), (U 0x2195), '[SIZE]')
    Gif        = @((U 0x1F300), (U 0x263B), '[GIF]')
    Frames     = @((U 0x1F4F8), (U 0x25A0), '[FRAME]')
    AudioTools = @((U 0x1F509), (U 0x2261), '[VOL]')
    Subtitle   = @((U 0x1F4DD), (U 0x00B6), '[SUB]')
    FrameRate  = @((U 0x23E9), (U 0x203C), '[FPS]')
    Filters    = @((U 0x1F3A8), (U 0x263C), '[FX]')
    Rotate     = @((U 0x1F504), (U 0x221E), '[ROT]')
    Text       = @((U 0x1F524), (U 0x00A7), '[TEXT]')
    Speed      = @((U 0x26A1), (U 0x00BB), '[SPEED]')
    Stream     = @((U 0x1F310), (U 0x2248), '[HLS]')
    Info       = @((U 0x1F50D), (U 0x263A), '[INFO]')
    Settings   = @((U 0x1F527), (U 0x2665), '[SET]')
    Quit       = @((U 0x274C), (U 0x25C4), '[EXIT]')
    Ok         = @((U 0x2705), (U 0x221A), '[OK]')
    Warn       = @((U 0x26A0), (U 0x25B2), '[!]')
    Fail       = @((U 0x274C), 'x', '[X]')
    Back       = @((U 0x1F519), (U 0x2190), '<-')
    Update     = @((U 0x23EB), (U 0x2191), '[UP]')
    Bullet     = @((U 0x203A), (U 0x00BB), '>')
    Arrow      = @((U 0x25B6), (U 0x25BA), '>')
    Option     = @((U 0x1F539), (U 0x2022), '*')
    Yes        = @((U 0x2705), (U 0x221A), '[Y]')
    No         = @((U 0x274C), 'x', '[N]')
    Continue   = @((U 0x1F449), (U 0x25BA), '[>]')
    Add        = @((U 0x2795), '+', '[+]')
    Remove     = @((U 0x2796), '-', '[-]')
    MoveUp     = @((U 0x1F53C), (U 0x25B2), '[^]')
    MoveDown   = @((U 0x1F53D), (U 0x25BC), '[v]')
    Retry      = @((U 0x1F501), (U 0x2194), '[R]')
    Details    = @((U 0x1F4C4), (U 0x2261), '[...]')
    Folder     = @((U 0x1F4C1), (U 0x25A0), '[DIR]')
    Home       = @((U 0x1F3E0), (U 0x2302), '[HOME]')
    Search     = @((U 0x1F50E), (U 0x263A), '[?]')
    Network    = @((U 0x1F310), (U 0x2248), '[NET]')
    Image      = @((U 0x1F304), (U 0x25D8), '[IMG]')
    Chapters   = @((U 0x1F516), (U 0x00B6), '[CH]')
    Hardware   = @((U 0x1F680), (U 0x2660), '[HW]')
    Record     = @((U 0x1F534), (U 0x25CF), '[REC]')
    Batch      = @((U 0x1F4DA), (U 0x2663), '[BATCH]')
    Tag        = @((U 0x1F4CC), (U 0x2666), '[TAG]')
    Code       = @((U 0x1F4BB), (U 0x00A4), '[CMD]')
    Chart      = @((U 0x1F4CA), (U 0x25B2), '[STATS]')
    Remux      = @((U 0x1F500), (U 0x2194), '[REMUX]')
    Enhance    = @((U 0x2728), (U 0x2642), '[ENH]')
    Map        = @((U 0x1F9ED), (U 0x2229), '[MAP]')
}

$script:UseAnsi = $false
$script:IconTier = 'Ascii'

function Initialize-Theme {
    # -Unicode accepts a tier name (Emoji | Symbol | Ascii) or a bool ($true = Emoji, $false = Ascii).
    param([bool]$Ansi, $Unicode = 'Emoji')
    $script:UseAnsi = $Ansi
    if ($Unicode -is [bool]) { $script:IconTier = $(if ($Unicode) { 'Emoji' } else { 'Ascii' }) }
    elseif (@('Emoji', 'Symbol', 'Ascii') -contains [string]$Unicode) { $script:IconTier = [string]$Unicode }
    else { $script:IconTier = 'Ascii' }
}

function Get-IconTierInUse { return $script:IconTier }

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
    switch ($script:IconTier) {
        'Emoji' { return $script:Icons[$Name][0] }
        'Symbol' { return $script:Icons[$Name][1] }
        default { return $script:Icons[$Name][2] }
    }
}

function Get-IconNames { return @($script:Icons.Keys) }

function Get-BoxChars {
    if ($script:IconTier -eq 'Symbol') {
        return [pscustomobject]@{ TL = [string][char]0x250C; TR = [string][char]0x2510; BL = [string][char]0x2514; BR = [string][char]0x2518; H = [string][char]0x2500; V = [string][char]0x2502; Bar = [string][char]0x2550; Dot = [string][char]0x00B7; Ellipsis = '...'; Up = [string][char]0x2191; Down = [string][char]0x2193 }
    }
    if ($script:IconTier -eq 'Emoji') {
        return [pscustomobject]@{ TL = [string][char]0x256D; TR = [string][char]0x256E; BL = [string][char]0x2570; BR = [string][char]0x256F; H = [string][char]0x2500; V = [string][char]0x2502; Bar = [string][char]0x2501; Dot = [string][char]0x00B7; Ellipsis = [string][char]0x2026; Up = [string][char]0x2191; Down = [string][char]0x2193 }
    }
    return [pscustomobject]@{ TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '-'; V = '|'; Bar = '='; Dot = '-'; Ellipsis = '...'; Up = '^'; Down = 'v' }
}

Export-ModuleMember -Function Initialize-Theme, Get-ThemeAnsi, Get-ThemeConsoleColor, Get-ThemeRoleNames, Get-Icon, Get-IconNames, Get-IconTierInUse, Get-BoxChars
