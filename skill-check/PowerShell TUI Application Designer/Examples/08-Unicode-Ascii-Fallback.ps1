<# 08 - Unicode / emoji / ASCII fallback: pick the icon TIER once (Emoji, Symbol, Ascii) from facts about the terminal, print the same
   menu in all three, and let the user override with an environment variable. Source stays ASCII: glyphs come from code points.
   Run:  pwsh -File 08-Unicode-Ascii-Fallback.ps1 #>
Set-StrictMode -Version 2.0
function Resolve-Tier {
    param([hashtable]$Env, [bool]$IsWin, [bool]$Redirected)
    $force = ([string]$Env['EXAMPLE_ICONS']).ToLowerInvariant()
    if ($force -in @('emoji', 'symbol', 'ascii')) { return (Get-Culture).TextInfo.ToTitleCase($force) }
    if ($Redirected) { return 'Ascii' }
    if (-not $IsWin) { if ([string]$Env['LANG'] -match 'UTF-?8') { return 'Emoji' } return 'Ascii' }
    if ($Env['WT_SESSION'] -or $Env['TERM_PROGRAM']) { return 'Emoji' }
    return 'Symbol'        # classic Windows console: single-column glyphs from the Windows Glyph List 4 always draw
}
$isWin = $true; if ($PSVersionTable.PSVersion.Major -ge 6) { $isWin = [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue) }
$redir = $false; try { $redir = [Console]::IsOutputRedirected } catch { $redir = $true }
$envFacts = @{ EXAMPLE_ICONS = $env:EXAMPLE_ICONS; LANG = $env:LANG; WT_SESSION = $env:WT_SESSION; TERM_PROGRAM = $env:TERM_PROGRAM }
$tier = Resolve-Tier -Env $envFacts -IsWin $isWin -Redirected $redir
if ($isWin) { try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { } }   # glyphs must reach the console as UTF-8
$icons = @{
    Emoji  = @{ Success = [char]::ConvertFromUtf32(0x2705); Warning = [char]::ConvertFromUtf32(0x1F536); Error = [char]::ConvertFromUtf32(0x274C) }
    Symbol = @{ Success = [string][char]0x221A; Warning = [string][char]0x25B2; Error = [string][char]0x00D7 }
    Ascii  = @{ Success = '+'; Warning = '!'; Error = 'x' }
}
Write-Output ('Tier in use: ' + $tier)
foreach ($t in 'Emoji', 'Symbol', 'Ascii') { Write-Output ('{0,-7} {1} Success   {2} Warning   {3} Error' -f $t, $icons[$t].Success, $icons[$t].Warning, $icons[$t].Error) }
Write-Output ('Selected: ' + $icons[$tier].Success + ' ready')
