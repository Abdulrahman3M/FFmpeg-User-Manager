# Log.psm1 - append-only diagnostic log in the per-user data folder. Never throws, never logs secrets.
Set-StrictMode -Version 2.0

function Write-AppLog {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    try {
        $dir = Get-AppDataDirectory -AppName '{{AppId}}' -Override $env:{{ENVPREFIX}}_DATA_DIR
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        $file = Join-Path $dir 'app.log'
        if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) { Move-Item -LiteralPath $file -Destination ($file + '.old') -Force }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        [System.IO.File]::AppendAllText($file, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

Export-ModuleMember -Function Write-AppLog
