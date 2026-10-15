# Paths.psm1 - path cleaning/resolution, file-name safety, size/duration formatting, folder opening.
Set-StrictMode -Version 2.0

function ConvertTo-CleanPath {
    # Accepts typed/pasted/dropped paths: "quoted", 'quoted', & 'C:\x' (console drag-drop), spaces, Unicode.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text.Trim()
    if ($t.StartsWith('& ')) { $t = $t.Substring(2).Trim() }
    if ($t.Length -ge 2) {
        $f = $t[0]; $l = $t[$t.Length - 1]
        if (($f -eq '"' -and $l -eq '"') -or ($f -eq "'" -and $l -eq "'")) { $t = $t.Substring(1, $t.Length - 2) }
    }
    return $t
}

function Resolve-UserPath {
    # Returns a full normalized path (no existence requirement) or $null when the text is not a usable path.
    param([string]$Text)
    $t = ConvertTo-CleanPath $Text
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.IndexOf([char]0) -ge 0) { return $null }
    try {
        if (-not [System.IO.Path]::IsPathRooted($t)) {
            $base = (Get-Location -PSProvider FileSystem).ProviderPath
            $t = Join-Path $base $t
        }
        return [System.IO.Path]::GetFullPath($t)
    } catch { return $null }
}

function Test-InputFile {
    # Returns $null when OK, otherwise a user-facing error message.
    param([string]$FullPath)
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return 'Please enter a file path.' }
    if (Test-Path -LiteralPath $FullPath -PathType Container) { return 'That path is a folder, not a file.' }
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return "File not found: $FullPath" }
    try {
        $fi = New-Object System.IO.FileInfo($FullPath)
        if ($fi.Length -le 0) { return 'The file is empty (zero bytes).' }
        $fs = [System.IO.File]::Open($FullPath, 'Open', 'Read', 'ReadWrite')
        $fs.Dispose()
    } catch [System.UnauthorizedAccessException] {
        return 'Access to the file was denied.'
    } catch [System.IO.IOException] {
        return 'The file is locked by another program or cannot be read.'
    } catch {
        return "The file cannot be read: $($_.Exception.Message)"
    }
    return $null
}

$script:ReservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')

function Test-ValidFileName {
    # Returns $null when valid, otherwise a message. Name only (no directory).
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'File name cannot be empty.' }
    if ($Name -ne $Name.Trim()) { return 'File name cannot start or end with a space.' }
    if ($Name.EndsWith('.')) { return 'File name cannot end with a dot.' }
    $bad = '<>:"/\|?*'.ToCharArray()
    foreach ($c in $Name.ToCharArray()) {
        if ($bad -contains $c -or [int]$c -lt 32) { return "File name contains an invalid character: $c" }
    }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Name).ToUpperInvariant()
    if ($script:ReservedNames -contains $stem) { return "'$stem' is a reserved Windows name." }
    if ($Name.Length -gt 200) { return 'File name is too long (200 characters maximum).' }
    return $null
}

function Get-SafeFileStem {
    param([string]$Name)
    $s = [string]$Name
    foreach ($c in '<>:"/\|?*'.ToCharArray()) { $s = $s.Replace([string]$c, '_') }
    $s = $s.Trim().TrimEnd('.')
    if (-not $s) { $s = 'output' }
    return $s
}

function Test-PathTooLong {
    param([string]$FullPath)
    return ($FullPath.Length -ge 250)
}

function Test-DirectoryWritable {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
    $probe = Join-Path $Dir ('.fftui_w_' + [guid]::NewGuid().ToString('N'))
    try { [System.IO.File]::WriteAllBytes($probe, [byte[]]@()); Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue; return $true }
    catch { return $false }
}

function Format-FileSize {
    param($Bytes)
    if ($null -eq $Bytes) { return 'unknown' }
    $b = [double]$Bytes
    if ($b -lt 1024) { return ('{0:N0} B' -f $b) }
    if ($b -lt 1MB) { return ('{0:N1} KB' -f ($b / 1KB)) }
    if ($b -lt 1GB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    return ('{0:N2} GB' -f ($b / 1GB))
}

function Format-Duration {
    param($Seconds)
    if ($null -eq $Seconds) { return 'unknown' }
    $s = [double]$Seconds
    if ($s -lt 0) { $s = 0 }
    $ts = [TimeSpan]::FromSeconds([math]::Floor($s))
    return ('{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
}

function Open-OutputFolder {
    # Opens the folder (selecting the file on Windows when possible). Never goes through a shell string.
    param([Parameter(Mandatory)][string]$Path)
    try {
        $isFile = Test-Path -LiteralPath $Path -PathType Leaf
        $dir = $Path
        if ($isFile) { $dir = [System.IO.Path]::GetDirectoryName($Path) }
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
        if (Get-Command Test-IsWindows -ErrorAction SilentlyContinue) { $win = Test-IsWindows } else { $win = $true }
        if ($win) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'explorer.exe'
            if ($isFile) { $psi.Arguments = '/select,"' + $Path + '"' } else { $psi.Arguments = '"' + $dir + '"' }
            $psi.UseShellExecute = $false
            [void][System.Diagnostics.Process]::Start($psi)
            return $true
        }
        $opener = Get-Command xdg-open, open -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($opener) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $opener.Source
            $psi.Arguments = '"' + $dir + '"'
            $psi.UseShellExecute = $false
            [void][System.Diagnostics.Process]::Start($psi)
            return $true
        }
    } catch { }
    return $false
}

function Test-NativePickerAvailable {
    if ($env:FFTUI_NO_PICKER -eq '1') { return $false }
    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not [bool](Get-Variable IsWindows -ValueOnly -ErrorAction SilentlyContinue)) { return $false }
    try {
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { return $false }
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Show-NativePicker {
    # Optional Windows picker. Returns a path or $null (cancel / unavailable). Typed input remains the fallback.
    param([ValidateSet('File', 'Folder', 'Save')][string]$Mode = 'File', [string]$Filter = 'All files (*.*)|*.*', [string]$InitialDirectory)
    if (-not (Test-NativePickerAvailable)) { return $null }
    try {
        if ($Mode -eq 'Folder') {
            $d = New-Object System.Windows.Forms.FolderBrowserDialog
            if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) { $d.SelectedPath = $InitialDirectory }
            if ($d.ShowDialog() -eq 'OK') { return $d.SelectedPath }
            return $null
        }
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = $Filter
        if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) { $d.InitialDirectory = $InitialDirectory }
        if ($d.ShowDialog() -eq 'OK') { return $d.FileName }
    } catch { }
    return $null
}

Export-ModuleMember -Function ConvertTo-CleanPath, Resolve-UserPath, Test-InputFile, Test-ValidFileName, Get-SafeFileStem, Test-PathTooLong, Test-DirectoryWritable, Format-FileSize, Format-Duration, Open-OutputFolder, Test-NativePickerAvailable, Show-NativePicker
