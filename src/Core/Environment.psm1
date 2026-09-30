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

function Get-AppConfig {
    if ($null -ne $script:Config) { return $script:Config }
    $default = [pscustomobject]@{
        appName = 'FFmpeg TUI'
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
    if ($env:NO_COLOR) { return $false }
    if ($env:FFTUI_FORCE_ANSI -eq '1') { return $true }
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

function Test-UnicodeIconSupport {
    if ($env:FFTUI_ASCII -eq '1') { return $false }
    if ($env:FFTUI_UNICODE -eq '1') { return $true }
    try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
    if (-not (Test-IsWindows)) { return ($env:LANG -match 'UTF-?8' -or $env:LC_ALL -match 'UTF-?8') }
    # Windows Terminal / VS Code / ConEmu render emoji; legacy conhost usually does not.
    if ($env:WT_SESSION -or $env:TERM_PROGRAM -or $env:ConEmuANSI -eq 'ON') {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
        return $true
    }
    return $false
}

function Get-TerminalSize {
    $w = 100; $h = 30
    try { $w = [Console]::WindowWidth } catch { }
    try { $h = [Console]::WindowHeight } catch { }
    if ($w -lt 20) { $w = 80 }
    if ($h -lt 8) { $h = 30 }
    return [pscustomobject]@{ Width = $w; Height = $h }
}

Export-ModuleMember -Function Set-AppRoot, Get-AppRoot, Get-AppConfig, Test-IsWindows, Get-RuntimeInfo, Test-InteractiveConsole, Test-AnsiSupport, Test-UnicodeIconSupport, Get-TerminalSize
