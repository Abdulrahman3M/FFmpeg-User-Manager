# Platform.psm1 - the ONLY module that knows which operating system / PowerShell edition is running.
# Everything else asks these functions. ($IsWindows does not exist in Windows PowerShell 5.1.)
Set-StrictMode -Version 2.0

function Test-IsWindows {
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }   # Windows PowerShell 5.1 runs on Windows only
    $v = Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue
    return [bool]$v
}

function Get-PlatformName {
    if (Test-IsWindows) { return 'Windows' }
    $m = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
    if ($m) { return 'macOS' }
    return 'Linux'
}

function Get-RuntimeInfo {
    $edition = 'Desktop'; if ($PSVersionTable.ContainsKey('PSEdition')) { $edition = [string]$PSVersionTable.PSEdition }
    return [pscustomobject]@{ Platform = (Get-PlatformName); PowerShell = [string]$PSVersionTable.PSVersion; Edition = $edition }
}

function Get-AppDataDirectory {
    # Per-user data folder (settings, logs). APPNAME_DATA_DIR style override is supported through -Override (tests).
    param([Parameter(Mandatory)][string]$AppName, [string]$Override = '')
    if ($Override) { return $Override }
    if (Test-IsWindows) { $base = $env:APPDATA } else {
        $base = $env:XDG_CONFIG_HOME
        if (-not $base -and $env:HOME) { $base = Join-Path $env:HOME '.config' }
    }
    if (-not $base) { $base = [System.IO.Path]::GetTempPath() }
    return (Join-Path $base $AppName)
}

function Find-Executable {
    # Returns the full path of a program on PATH (or $null). Never guesses a hard-coded location.
    param([Parameter(Mandatory)][string]$Name)
    $c = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return [string]$c.Source }
    return $null
}

function Get-CurrentPowerShellPath {
    # The host that is running this script (pwsh, or Windows PowerShell): used to start child processes portably.
    $name = 'pwsh'; if ($PSVersionTable.PSVersion.Major -lt 6) { $name = 'powershell' }
    $exe = if (Test-IsWindows) { $name + '.exe' } else { $name }
    $p = Join-Path $PSHOME $exe
    if (Test-Path -LiteralPath $p) { return $p }
    return (Find-Executable $name)
}

Export-ModuleMember -Function Test-IsWindows, Get-PlatformName, Get-RuntimeInfo, Get-AppDataDirectory, Find-Executable, Get-CurrentPowerShellPath
