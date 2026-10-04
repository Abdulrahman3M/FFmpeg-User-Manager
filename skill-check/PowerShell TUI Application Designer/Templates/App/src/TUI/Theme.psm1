# Theme.psm1 - the ONE place for colors and icons. Other modules ask for a ROLE or an icon NAME, never a color/glyph.
# Icons come in three tiers: Emoji (modern terminals), Symbol (single-column glyphs from the Windows Glyph List 4, drawn by
# every console font) and Ascii (redirected output / forced). A new icon needs all three forms.
Set-StrictMode -Version 2.0
$script:Tier = ''   # the tier in use; empty = detect on first use (tests and the settings screen can override it)

function ConvertFrom-CodePoint { param([int]$Code) return [char]::ConvertFromUtf32($Code) }

function Get-IconTable {
    # Name -> Emoji / Symbol / Ascii. Source stays ASCII-only: glyphs are built from code points.
    return @{
        Run      = @{ Emoji = (ConvertFrom-CodePoint 0x1F680); Symbol = (ConvertFrom-CodePoint 0x25BA); Ascii = '>' }
        Form     = @{ Emoji = (ConvertFrom-CodePoint 0x1F4DD); Symbol = (ConvertFrom-CodePoint 0x2666); Ascii = '*' }
        Settings = @{ Emoji = (ConvertFrom-CodePoint 0x1F527); Symbol = (ConvertFrom-CodePoint 0x263C); Ascii = '#' }
        About    = @{ Emoji = (ConvertFrom-CodePoint 0x1F4A1); Symbol = (ConvertFrom-CodePoint 0x263A); Ascii = 'i' }
        Exit     = @{ Emoji = (ConvertFrom-CodePoint 0x1F6AA); Symbol = (ConvertFrom-CodePoint 0x25C4); Ascii = '<' }
        Success  = @{ Emoji = (ConvertFrom-CodePoint 0x2705); Symbol = (ConvertFrom-CodePoint 0x221A); Ascii = '+' }
        Warning  = @{ Emoji = (ConvertFrom-CodePoint 0x1F536); Symbol = (ConvertFrom-CodePoint 0x25B2); Ascii = '!' }
        Error    = @{ Emoji = (ConvertFrom-CodePoint 0x274C); Symbol = (ConvertFrom-CodePoint 0x00D7); Ascii = 'x' }
        Info     = @{ Emoji = (ConvertFrom-CodePoint 0x1F4A1); Symbol = (ConvertFrom-CodePoint 0x263A); Ascii = 'i' }
        Yes      = @{ Emoji = (ConvertFrom-CodePoint 0x2705); Symbol = (ConvertFrom-CodePoint 0x221A); Ascii = '+' }
        No       = @{ Emoji = (ConvertFrom-CodePoint 0x274C); Symbol = (ConvertFrom-CodePoint 0x00D7); Ascii = 'x' }
        Item     = @{ Emoji = (ConvertFrom-CodePoint 0x1F539); Symbol = (ConvertFrom-CodePoint 0x2666); Ascii = '-' }
    }
}

function Resolve-IconTier {
    # Pure decision logic (unit tested). $Env is a hashtable of the relevant variables.
    #   Emoji  : modern terminals (Windows Terminal, VS Code, ConEmu, UTF-8 Linux/macOS)
    #   Symbol : classic Windows console (conhost / Windows PowerShell window): single-column WGL4 glyphs
    #   Ascii  : redirected output, or forced
    # Overrides: {{ENVPREFIX}}_ICONS=emoji|symbol|ascii, {{ENVPREFIX}}_ASCII=1.
    param([hashtable]$Env, [bool]$IsWin, [bool]$Redirected, [bool]$Utf8Ok = $true)
    $force = ([string]$Env['{{ENVPREFIX}}_ICONS']).ToLowerInvariant()
    if ($force -eq 'emoji') { return 'Emoji' }
    if ($force -eq 'symbol') { return 'Symbol' }
    if ($force -eq 'ascii') { return 'Ascii' }
    if ($Env['{{ENVPREFIX}}_ASCII'] -eq '1') { return 'Ascii' }
    if ($Redirected) { return 'Ascii' }
    if (-not $IsWin) {
        if ([string]$Env['LANG'] -match 'UTF-?8' -or [string]$Env['LC_ALL'] -match 'UTF-?8') { return 'Emoji' }
        return 'Ascii'
    }
    if (-not $Utf8Ok) { return 'Ascii' }
    if ($Env['WT_SESSION'] -or $Env['TERM_PROGRAM'] -or $Env['ConEmuANSI'] -eq 'ON') { return 'Emoji' }
    return 'Symbol'
}

function Set-ConsoleUtf8Output {
    # Windows only: make the console write UTF-8 so the glyphs arrive unchanged. Also needed when output is redirected.
    if (-not (Test-IsWindows)) { return $true }
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); return $true } catch { return $false }
}

function Get-IconTier {
    $names = '{{ENVPREFIX}}_ICONS', '{{ENVPREFIX}}_ASCII', 'LANG', 'LC_ALL', 'WT_SESSION', 'TERM_PROGRAM', 'ConEmuANSI'
    $e = @{}; foreach ($n in $names) { $e[$n] = [Environment]::GetEnvironmentVariable($n) }
    if (-not $e['{{ENVPREFIX}}_ICONS'] -and $e['{{ENVPREFIX}}_ASCII'] -ne '1') {
        $saved = Get-UserSetting 'icons'
        if ($saved -in @('emoji', 'symbol')) { $e['{{ENVPREFIX}}_ICONS'] = $saved }   # the user's remembered choice
    }
    $redirected = $false
    try { $redirected = [Console]::IsOutputRedirected } catch { $redirected = $true }
    $win = Test-IsWindows
    $utf8 = $true
    if ($win) { $utf8 = Set-ConsoleUtf8Output }
    return (Resolve-IconTier -Env $e -IsWin $win -Redirected $redirected -Utf8Ok $utf8)
}

function Get-Icon {
    param([Parameter(Mandatory)][string]$Name, [string]$Tier = '')
    if (-not $Tier) { $Tier = $script:Tier; if (-not $Tier) { $Tier = Get-IconTier } }
    $t = Get-IconTable
    if (-not $t.ContainsKey($Name)) { $Name = 'Item' }
    return $t[$Name][$Tier]
}

function Set-IconTier { param([ValidateSet('Emoji', 'Symbol', 'Ascii')][string]$Tier) $script:Tier = $Tier }
function Get-IconTierInUse { if ($script:Tier) { return $script:Tier } return (Get-IconTier) }

# Roles -> ANSI SGR codes and the legacy console color. Add a role here, never a color elsewhere.
function Get-RoleStyle {
    param([Parameter(Mandatory)][string]$Role)
    $s = @{
        Title    = @{ Ansi = '1;36'; Legacy = 'Cyan' }
        Heading  = @{ Ansi = '1;37'; Legacy = 'White' }
        Normal   = @{ Ansi = '0';    Legacy = 'Gray' }
        Dim      = @{ Ansi = '90';   Legacy = 'DarkGray' }
        Selected = @{ Ansi = '1;96'; Legacy = 'Cyan' }
        Number   = @{ Ansi = '36';   Legacy = 'Cyan' }
        Key      = @{ Ansi = '96';   Legacy = 'Cyan' }
        Success  = @{ Ansi = '32';   Legacy = 'Green' }
        Warning  = @{ Ansi = '33';   Legacy = 'Yellow' }
        Error    = @{ Ansi = '31';   Legacy = 'Red' }
        Info     = @{ Ansi = '34';   Legacy = 'Blue' }
    }
    if ($s.ContainsKey($Role)) { return $s[$Role] }
    return $s['Normal']
}

Export-ModuleMember -Function Get-IconTable, Resolve-IconTier, Set-ConsoleUtf8Output, Get-IconTier, Get-Icon, Set-IconTier, Get-IconTierInUse, Get-RoleStyle
