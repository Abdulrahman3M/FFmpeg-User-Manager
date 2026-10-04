<# 03 - Typed input with help, an example and validation. The validator is a PURE function (testable without any UI):
   it returns $null when valid, otherwise the message. Esc cancels.
   Run:  pwsh -File 03-User-Input-Validation.ps1 [-Demo] #>
param([switch]$Demo)
. (Join-Path $PSScriptRoot 'Shared/TinyTui.ps1')
function Test-PortNumber {
    param([string]$Text)
    if ($Text -notmatch '^\d+$') { return 'Type whole digits only, for example 8080.' }
    $n = [int64]$Text
    if ($n -lt 1 -or $n -gt 65535) { return 'The port must be between 1 and 65535.' }
    return $null
}
function Read-Validated {
    param([string]$Prompt, [string]$Help, [string]$Example, [scriptblock]$Validate)
    $text = ''; $err = ''
    while ($true) {
        Write-Line ''; Write-Line $Prompt 'Cyan'; Write-Line ('  ' + $Help) 'DarkGray'; Write-Line ('  Example: ' + $Example) 'DarkGray'
        if ($err) { Write-Line ('  ! ' + $err) 'Red' }
        Write-Line ('> ' + $text) 'White'
        $k = Read-TinyKey
        switch ($k) {
            'Esc' { return $null }
            'Backspace' { if ($text.Length -gt 0) { $text = $text.Substring(0, $text.Length - 1) } }
            'Enter' { $m = & $Validate $text; if (-not $m) { return $text }; $err = [string]$m }
            default { $text += $k; $err = '' }
        }
    }
}
if ($Demo) { Set-DemoKeys 'abc{Enter}{Backspace}{Backspace}{Backspace}99999{Enter}{Backspace}{Backspace}{Backspace}{Backspace}{Backspace}8080{Enter}' }
$port = Read-Validated -Prompt 'Port number' -Help 'The TCP port the service listens on (1-65535).' -Example '8080' -Validate { param($t) Test-PortNumber $t }
Write-Line ('Accepted port: ' + $port) 'Green'
