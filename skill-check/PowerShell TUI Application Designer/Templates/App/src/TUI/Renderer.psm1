# Renderer.psm1 - the ONLY module that writes to the screen. Sinks: Console (real) and Buffer (tests capture the output).
Set-StrictMode -Version 2.0
$script:Sink = 'Console'
$script:Ansi = $false
$script:Buffer = New-Object System.Text.StringBuilder
$script:Esc = [string][char]27

function Test-AnsiSupport {
    # NO_COLOR wins; {{ENVPREFIX}}_FORCE_ANSI=1 forces; redirected output never gets escape codes.
    if ($env:NO_COLOR) { return $false }
    if ($env:{{ENVPREFIX}}_FORCE_ANSI -eq '1') { return $true }
    try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
    if (-not (Test-IsWindows)) { return $true }
    if ($env:WT_SESSION -or $env:ConEmuANSI -eq 'ON' -or $env:TERM_PROGRAM) { return $true }
    try { if ($Host.UI.SupportsVirtualTerminal) { return $true } } catch { }
    return $false
}

function Initialize-Renderer {
    param([bool]$Ansi = $false, [ValidateSet('Console', 'Buffer')][string]$Sink = 'Console')
    $script:Ansi = $Ansi; $script:Sink = $Sink
    $script:Buffer = New-Object System.Text.StringBuilder
}

function Get-TerminalSize {
    $w = 100; $h = 30
    try { $w = [Console]::WindowWidth } catch { }
    try { $h = [Console]::WindowHeight } catch { }
    if ($w -lt 20) { $w = 80 }
    if ($h -lt 8) { $h = 30 }
    return [pscustomobject]@{ Width = $w; Height = $h }
}

function Write-Ui {
    # Writes text in a ROLE (see Theme). No newline.
    param([AllowEmptyString()][string]$Text, [string]$Role = 'Normal')
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append($Text); return }
    $st = Get-RoleStyle $Role
    if ($script:Ansi) { [Console]::Out.Write($script:Esc + '[' + $st.Ansi + 'm' + $Text + $script:Esc + '[0m') }
    else { Write-Host $Text -NoNewline -ForegroundColor $st.Legacy }
}

function Write-UiLine { param([AllowEmptyString()][string]$Text = '', [string]$Role = 'Normal') Write-Ui $Text $Role; Write-Ui "`n" 'Normal' }

function Clear-Ui {
    if ($script:Sink -eq 'Buffer') { [void]$script:Buffer.Append("`n=====CLEAR=====`n"); return }
    if ($script:Ansi) { [Console]::Out.Write($script:Esc + '[H' + $script:Esc + '[2J') } else { try { Clear-Host } catch { } }
}

function Enter-Screen {
    # Alternate screen + hidden cursor (ANSI only); always pair with Exit-Screen in a finally block.
    if ($script:Sink -eq 'Console' -and $script:Ansi) { [Console]::Out.Write($script:Esc + '[?1049h' + $script:Esc + '[?25l') }
}
function Exit-Screen {
    if ($script:Sink -eq 'Console') {
        if ($script:Ansi) { [Console]::Out.Write($script:Esc + '[?25h' + $script:Esc + '[?1049l' + $script:Esc + '[0m') }
        else { try { [Console]::CursorVisible = $true } catch { } }
    }
}

function Get-CapturedOutput { return $script:Buffer.ToString() }
function Clear-CapturedOutput { $script:Buffer = New-Object System.Text.StringBuilder }
function Get-LastFrame { return (((Get-CapturedOutput) -split '=====CLEAR=====')[-1]) }

Export-ModuleMember -Function Test-AnsiSupport, Initialize-Renderer, Get-TerminalSize, Write-Ui, Write-UiLine, Clear-Ui, Enter-Screen, Exit-Screen, Get-CapturedOutput, Clear-CapturedOutput, Get-LastFrame
