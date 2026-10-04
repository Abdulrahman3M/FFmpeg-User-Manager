<#
.SYNOPSIS
    Reports what this machine/terminal can do, so an agent can decide icon tier, color mode and launcher before writing UI code.
.DESCRIPTION
    Read-only. Works on Windows PowerShell 5.1 and PowerShell 7.x, Windows and Linux. Exit code 0 always (it reports, it does not judge).
    -Json prints the same facts as JSON for tools.
#>
[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$isWin = $true
if ($PSVersionTable.PSVersion.Major -ge 6) { $v = Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue; $isWin = [bool]$v }
$platform = 'Windows'
if (-not $isWin) { $platform = 'Linux'; $m = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue; if ($m) { $platform = 'macOS' } }
$edition = 'Desktop'; if ($PSVersionTable.ContainsKey('PSEdition')) { $edition = [string]$PSVersionTable.PSEdition }
$outRedir = $false; $inRedir = $false
try { $outRedir = [Console]::IsOutputRedirected; $inRedir = [Console]::IsInputRedirected } catch { $outRedir = $true; $inRedir = $true }
$width = 0; $height = 0
try { $width = [Console]::WindowWidth; $height = [Console]::WindowHeight } catch { }
$outEnc = ''; try { $outEnc = [Console]::OutputEncoding.WebName } catch { }
$vt = $false; try { $vt = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
$term = [ordered]@{ WT_SESSION = [bool]$env:WT_SESSION; TERM_PROGRAM = [string]$env:TERM_PROGRAM; ConEmuANSI = [string]$env:ConEmuANSI; TERM = [string]$env:TERM; LANG = [string]$env:LANG; NO_COLOR = [bool]$env:NO_COLOR }
# Same decision as the template's Resolve-IconTier (kept in sync on purpose; see References/Unicode-and-Emoji-Handling.md)
$tier = 'Ascii'
if (-not $outRedir) {
    if ($isWin) { if ($env:WT_SESSION -or $env:TERM_PROGRAM -or $env:ConEmuANSI -eq 'ON') { $tier = 'Emoji' } else { $tier = 'Symbol' } }
    elseif ([string]$env:LANG -match 'UTF-?8' -or [string]$env:LC_ALL -match 'UTF-?8') { $tier = 'Emoji' }
}
$emojiFont = $null
if ($isWin) {
    $emojiFont = (Test-Path -LiteralPath (Join-Path $env:WINDIR 'Fonts\seguiemj.ttf'))
}
$pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$winps = Get-Command powershell -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$facts = [ordered]@{
    Platform = $platform; PowerShell = [string]$PSVersionTable.PSVersion; Edition = $edition
    OutputRedirected = $outRedir; InputRedirected = $inRedir; Interactive = ((-not $outRedir) -and (-not $inRedir))
    WindowWidth = $width; WindowHeight = $height; OutputEncoding = $outEnc; VirtualTerminalHost = $vt
    Terminal = $term; SuggestedIconTier = $tier; SegoeUIEmojiInstalled = $emojiFont
    Pwsh7OnPath = [bool]$pwsh; WindowsPowerShellOnPath = [bool]$winps
}
if ($Json) { $facts | ConvertTo-Json -Depth 4; return }
foreach ($k in $facts.Keys) {
    $val = $facts[$k]
    if ($val -is [System.Collections.IDictionary]) { Write-Output ('{0,-24}' -f $k); foreach ($tk in $val.Keys) { Write-Output ('  {0,-22} {1}' -f $tk, $val[$tk]) } }
    else { Write-Output ('{0,-24} {1}' -f $k, $val) }
}
