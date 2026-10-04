# Settings.psm1 - small per-user JSON settings file (UTF-8 without BOM, readable by 5.1 and 7).
Set-StrictMode -Version 2.0

function Get-SettingsPath { param([string]$AppName = '{{AppId}}') return (Join-Path (Get-AppDataDirectory -AppName $AppName -Override $env:{{ENVPREFIX}}_DATA_DIR) 'settings.json') }

function Get-UserSetting {
    param([Parameter(Mandatory)][string]$Name, [string]$Default = '')
    $p = Get-SettingsPath
    try {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $j = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json
            if ($j.PSObject.Properties[$Name]) { return [string]$j.$Name }
        }
    } catch { }
    return $Default
}

function Set-UserSetting {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
    $p = Get-SettingsPath
    $h = @{}
    try { if (Test-Path -LiteralPath $p -PathType Leaf) { foreach ($pr in ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json).PSObject.Properties) { $h[$pr.Name] = $pr.Value } } } catch { }
    $h[$Name] = $Value
    try {
        $dir = Split-Path -Parent $p
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        [System.IO.File]::WriteAllText($p, ($h | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }   # a read-only profile must never crash the app
}

Export-ModuleMember -Function Get-SettingsPath, Get-UserSetting, Set-UserSetting
