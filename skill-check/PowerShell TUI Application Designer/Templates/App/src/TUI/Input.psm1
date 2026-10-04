# Input.psm1 - the ONLY module that reads the keyboard. A scripted queue lets tests and CI drive the whole UI.
# Tokens: {Enter} {Esc} {Up} {Down} {Backspace} {CtrlC}; every other character is typed literally.
Set-StrictMode -Version 2.0
$script:Queue = New-Object System.Collections.Generic.Queue[object]
$script:Scripted = $false

function New-Key { param([string]$Name, [string]$Char = '') return [pscustomobject]@{ Name = $Name; Char = $Char } }

function Set-ScriptedInput {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Keys)
    $script:Queue = New-Object System.Collections.Generic.Queue[object]
    $script:Scripted = $true
    $i = 0
    while ($i -lt $Keys.Length) {
        if ($Keys[$i] -eq '{') {
            $close = $Keys.IndexOf('}', $i)
            if ($close -gt $i) {
                $tok = $Keys.Substring($i + 1, $close - $i - 1)
                if ($tok -in @('Enter', 'Esc', 'Up', 'Down', 'Backspace', 'CtrlC')) { $script:Queue.Enqueue((New-Key $tok)); $i = $close + 1; continue }
            }
        }
        $script:Queue.Enqueue((New-Key 'Char' ([string]$Keys[$i]))); $i++
    }
}

function Clear-ScriptedInput { $script:Queue = New-Object System.Collections.Generic.Queue[object]; $script:Scripted = $false }
function Test-ScriptedInput { return $script:Scripted }

function Read-AppKey {
    if ($script:Scripted) {
        if ($script:Queue.Count -eq 0) { throw 'Scripted input exhausted.' }   # a test that runs out of keys must fail loudly
        return $script:Queue.Dequeue()
    }
    $k = [Console]::ReadKey($true)
    if (($k.Modifiers -band [ConsoleModifiers]::Control) -and $k.Key -eq [ConsoleKey]::C) { return (New-Key 'CtrlC') }
    switch ($k.Key) {
        'Enter' { return (New-Key 'Enter') }
        'Escape' { return (New-Key 'Esc') }
        'UpArrow' { return (New-Key 'Up') }
        'DownArrow' { return (New-Key 'Down') }
        'Backspace' { return (New-Key 'Backspace') }
        default { if ($k.KeyChar -ne [char]0) { return (New-Key 'Char' ([string]$k.KeyChar)) } return (New-Key 'Other') }
    }
}

Export-ModuleMember -Function Set-ScriptedInput, Clear-ScriptedInput, Test-ScriptedInput, Read-AppKey
