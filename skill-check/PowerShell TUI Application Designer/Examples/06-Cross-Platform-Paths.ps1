<# 06 - Cross-platform paths: build paths with Join-Path (two arguments for 5.1 compatibility), never with '\' or '/' strings;
   use -LiteralPath for user-typed paths (brackets are legal in names); per-user data folder per OS; no hard-coded drive letters.
   Run:  pwsh -File 06-Cross-Platform-Paths.ps1 #>
Set-StrictMode -Version 2.0
$isWin = $true
if ($PSVersionTable.PSVersion.Major -ge 6) { $isWin = [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue) }
if ($isWin) { $base = $env:APPDATA } else { $base = $env:XDG_CONFIG_HOME; if (-not $base -and $env:HOME) { $base = Join-Path $env:HOME '.config' } }
if (-not $base) { $base = [System.IO.Path]::GetTempPath() }
$dataDir = Join-Path $base 'ExampleApp'
Write-Output ('Per-user data folder: ' + $dataDir)
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('example-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$name = 'report [final] (1) & notes.txt'                 # legal on both systems; wildcard characters in the name
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$file = Join-Path $tmp $name
[System.IO.File]::WriteAllText($file, 'hello')
Write-Output ('Exists via -LiteralPath: ' + (Test-Path -LiteralPath $file))
Write-Output ('Exists via wildcard path (WRONG for brackets): ' + (Test-Path -Path $file))
Write-Output ('Full path: ' + [System.IO.Path]::GetFullPath($file))
Write-Output ('Directory separator on this system: ' + [System.IO.Path]::DirectorySeparatorChar)
Write-Output ('Case-sensitive file system? ' + (-not (Test-Path -LiteralPath ($file.ToUpperInvariant()))))
Remove-Item -LiteralPath $tmp -Recurse -Force
