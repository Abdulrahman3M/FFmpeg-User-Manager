# Environment.psm1 - runtime/terminal environment detection and application configuration.
Set-StrictMode -Version 2.0

$script:Config = $null
$script:AppRoot = $null

function Set-AppRoot {
    param([Parameter(Mandatory)][string]$Path)
    $script:AppRoot = $Path
    $script:Config = $null
}

function Get-AppRoot { return $script:AppRoot }

function Get-AppName { return 'FFmpeg User Manager' }

function Test-SemVer {
    # Semantic Versioning 2.0.0 (MAJOR.MINOR.PATCH with optional -prerelease and +build).
    param([string]$Text)
    return ($Text -match '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$')
}

function Get-AppVersion {
    # The canonical version lives in the VERSION file at the repository root (first line, SemVer).
    $fallback = '0.0.0-unknown'
    if (-not $script:AppRoot) { return $fallback }
    $file = Join-Path $script:AppRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $fallback }
    try {
        $v = ((Get-Content -LiteralPath $file -TotalCount 1 -ErrorAction Stop) | Select-Object -First 1)
        if ($null -eq $v) { return $fallback }
        $v = ([string]$v).Trim()
        if (Test-SemVer $v) { return $v }
    } catch { }
    return $fallback
}

function Get-AppConfig {
    if ($null -ne $script:Config) { return $script:Config }
    $default = [pscustomobject]@{
        appName = 'FFmpeg User Manager'
        winget  = [pscustomobject]@{ packageId = 'Gyan.FFmpeg'; source = 'winget' }
        ui      = [pscustomobject]@{ maxWidth = 100; compactBelow = 72 }
        presets = [pscustomobject]@{
            gifFps = @(10, 15, 20, 24, 30); gifWidths = @(320, 480, 640, 720)
            resolutions = @(2160, 1440, 1080, 720, 480); frameRates = @(24, 25, 30, 50, 60)
            speeds = @(0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0)
            sampleRates = @(8000, 16000, 22050, 32000, 44100, 48000, 96000)
        }
    }
    $cfg = $default
    if ($script:AppRoot) {
        $file = Join-Path (Join-Path $script:AppRoot 'config') 'defaults.json'
        if (Test-Path -LiteralPath $file) {
            try { $cfg = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { $cfg = $default }
        }
    }
    $script:Config = $cfg
    return $cfg
}

function Test-IsWindows {
    # $IsWindows does not exist in Windows PowerShell 5.1 (which is always Windows).
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }
    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function Get-RuntimeInfo {
    $edition = 'Desktop'
    if ($PSVersionTable.ContainsKey('PSEdition')) { $edition = [string]$PSVersionTable.PSEdition }
    return [pscustomobject]@{
        PSVersion = $PSVersionTable.PSVersion.ToString()
        Major     = $PSVersionTable.PSVersion.Major
        Edition   = $edition
        IsWindows = (Test-IsWindows)
    }
}

function Test-InteractiveConsole {
    try {
        if ([Console]::IsInputRedirected) { return $false }
        if ([Console]::IsOutputRedirected) { return $false }
        return $true
    } catch { return $false }
}

function Test-AnsiSupport {
    # Windows PowerShell 5.1 on legacy conhost does not process VT sequences by default.
    if ($env:FFTUI_FORCE_ANSI -eq '1') { return $true }
    if ($env:NO_COLOR) { return $false }
    if ($env:FFTUI_NO_ANSI -eq '1') { return $false }
    try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
    if (-not (Test-IsWindows)) { return ($env:TERM -and $env:TERM -ne 'dumb') }
    if ($env:WT_SESSION -or $env:ConEmuANSI -eq 'ON' -or $env:TERM_PROGRAM) { return $true }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # PowerShell 7 enables VT processing on conhost of Windows 10 1607+.
        try { if ($Host.UI.SupportsVirtualTerminal) { return $true } } catch { }
    }
    # Try to enable virtual-terminal processing on the console output handle (Windows 10+).
    try {
        if (-not ('FFTui.NativeConsole' -as [type])) {
            Add-Type -Namespace FFTui -Name NativeConsole -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)] public static extern System.IntPtr GetStdHandle(int h);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(System.IntPtr h, out int m);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(System.IntPtr h, int m);
'@
        }
        $h = [FFTui.NativeConsole]::GetStdHandle(-11)
        $mode = 0
        if ([FFTui.NativeConsole]::GetConsoleMode($h, [ref]$mode)) {
            if (($mode -band 4) -ne 0) { return $true }
            return [FFTui.NativeConsole]::SetConsoleMode($h, ($mode -bor 4))
        }
    } catch { }
    return $false
}

function Set-ConsoleUtf8Output {
    # Makes the console write UTF-8 so the icon/box characters reach the screen unchanged. Returns $true on success.
    if (-not (Test-IsWindows)) { return $true }
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); return $true } catch { return $false }
}

function Get-UserSettingsPath {
    # Per-user preferences (never inside the project folder). FFTUI_SETTINGS_DIR overrides the location (tests).
    $dir = $env:FFTUI_SETTINGS_DIR
    if (-not $dir) {
        if (Test-IsWindows) { $base = $env:APPDATA } else { $base = $env:XDG_CONFIG_HOME; if (-not $base -and $env:HOME) { $base = Join-Path $env:HOME '.config' } }
        if (-not $base) { return '' }
        $dir = Join-Path $base 'FFmpeg-User-Manager'
    }
    return (Join-Path $dir 'settings.json')
}

function Get-UserSetting {
    param([string]$Name)
    $p = Get-UserSettingsPath
    if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
    try { $j = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json; if ($j.PSObject.Properties[$Name]) { return [string]$j.$Name } } catch { }
    return ''
}

function Set-UserSetting {
    # Returns $true when saved. Only plain preferences are stored (no secrets, no paths).
    param([string]$Name, [string]$Value)
    $p = Get-UserSettingsPath
    if (-not $p) { return $false }
    try {
        $h = [ordered]@{}
        if (Test-Path -LiteralPath $p -PathType Leaf) { $j = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json; foreach ($pr in $j.PSObject.Properties) { $h[$pr.Name] = $pr.Value } }
        $h[$Name] = $Value
        $d = Split-Path -Parent $p
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
        [System.IO.File]::WriteAllText($p, ($h | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

function Resolve-IconTier {
    # Pure decision logic (unit tested): Emoji | Symbol | Ascii. $Env is a hashtable of the relevant variables.
    #   Emoji  - modern terminals (Windows Terminal, VS Code, ConEmu, UTF-8 Linux/macOS)
    #   Symbol - legacy Windows console (conhost, the Windows PowerShell 5.1 window): single-column glyphs from the
    #            Windows Glyph List 4 that every console font draws, so an icon is always visible
    #   Ascii  - redirected output, or forced with FFTUI_ASCII=1 (FFTUI_ICONS=emoji|symbol|ascii overrides detection)
    param([hashtable]$Env, [bool]$IsWin, [bool]$Redirected, [bool]$Utf8Ok = $true)
    $force = ([string]$Env['FFTUI_ICONS']).ToLowerInvariant()
    if ($force -eq 'emoji') { return 'Emoji' }
    if ($force -eq 'symbol') { return 'Symbol' }
    if ($force -eq 'ascii') { return 'Ascii' }
    if ($Env['FFTUI_ASCII'] -eq '1') { return 'Ascii' }
    if ($Env['FFTUI_UNICODE'] -eq '1') { return 'Emoji' }
    if ($Redirected) { return 'Ascii' }
    if (-not $IsWin) {
        if ([string]$Env['LANG'] -match 'UTF-?8' -or [string]$Env['LC_ALL'] -match 'UTF-?8') { return 'Emoji' }
        return 'Ascii'
    }
    if (-not $Utf8Ok) { return 'Ascii' }
    if ($Env['WT_SESSION'] -or $Env['TERM_PROGRAM'] -or $Env['ConEmuANSI'] -eq 'ON') { return 'Emoji' }
    return 'Symbol'
}

function Get-IconTier {
    $names = 'FFTUI_ICONS', 'FFTUI_ASCII', 'FFTUI_UNICODE', 'LANG', 'LC_ALL', 'WT_SESSION', 'TERM_PROGRAM', 'ConEmuANSI'
    $e = @{}; foreach ($n in $names) { $e[$n] = [Environment]::GetEnvironmentVariable($n) }
    if (-not $e['FFTUI_ICONS'] -and $e['FFTUI_ASCII'] -ne '1') { $saved = Get-UserSetting 'icons'; if ($saved -in @('emoji', 'symbol')) { $e['FFTUI_ICONS'] = $saved } }
    $redirected = $false
    try { $redirected = [Console]::IsOutputRedirected } catch { $redirected = $true }
    $win = Test-IsWindows
    $utf8 = $true
    # also when output is redirected: a forced emoji/symbol set must reach a parent process as UTF-8, not as OEM-code-page '?'
    if ($win) { $utf8 = Set-ConsoleUtf8Output }
    return (Resolve-IconTier -Env $e -IsWin $win -Redirected $redirected -Utf8Ok $utf8)
}

function Test-UnicodeIconSupport { return ((Get-IconTier) -ne 'Ascii') }

function Get-TerminalSize {
    $w = 100; $h = 30
    try { $w = [Console]::WindowWidth } catch { }
    try { $h = [Console]::WindowHeight } catch { }
    if ($w -lt 20) { $w = 80 }
    if ($h -lt 8) { $h = 30 }
    return [pscustomobject]@{ Width = $w; Height = $h }
}

Export-ModuleMember -Function Get-AppName, Test-SemVer, Get-AppVersion, Set-AppRoot, Get-AppRoot, Get-AppConfig, Test-IsWindows, Get-RuntimeInfo, Test-InteractiveConsole, Test-AnsiSupport, Test-UnicodeIconSupport, Get-UserSettingsPath, Get-UserSetting, Set-UserSetting, Resolve-IconTier, Get-IconTier, Set-ConsoleUtf8Output, Get-TerminalSize
