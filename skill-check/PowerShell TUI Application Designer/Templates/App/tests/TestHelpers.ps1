# TestHelpers.ps1 - tiny test framework (no Pester needed; works on Windows PowerShell 5.1 and PowerShell 7).
Set-StrictMode -Version 2.0
$script:Results = New-Object System.Collections.Generic.List[object]
$script:Group = ''
$script:Root = Split-Path -Parent $PSScriptRoot

function Set-TestGroup { param([string]$Name) $script:Group = $Name; Write-Host ("`n== " + $Name) -ForegroundColor Cyan }
function Add-TestResult {
    param([string]$Name, [ValidateSet('PASS', 'FAIL', 'UNVERIFIED')][string]$Status, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Group = $script:Group; Name = $Name; Status = $Status; Detail = $Detail })
    $color = @{ PASS = 'Green'; FAIL = 'Red'; UNVERIFIED = 'Yellow' }[$Status]
    Write-Host ('  [{0}] {1}' -f $Status, $Name) -ForegroundColor $color
    if ($Status -ne 'PASS' -and $Detail) { Write-Host ('        ' + $Detail) -ForegroundColor DarkGray }
}
function Assert-True { param([string]$Name, $Condition, [string]$Detail = '') if ($Condition) { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' $Detail } }
function Assert-Equal { param([string]$Name, $Expected, $Actual) if ("$Expected" -eq "$Actual") { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' "expected [$Expected] actual [$Actual]" } }
function Assert-Contains { param([string]$Name, [string]$Text, [string]$Needle) if ($Text.Contains($Needle)) { Add-TestResult $Name 'PASS' } else { Add-TestResult $Name 'FAIL' "output does not contain [$Needle]" } }
function Skip-Test { param([string]$Name, [string]$Reason) Add-TestResult $Name 'UNVERIFIED' $Reason }   # never report PASS for something that did not run
function Get-TestResults { return $script:Results }

function Initialize-TestEnvironment {
    . (Join-Path (Join-Path $script:Root 'src') 'Import-Modules.ps1')
    Import-AppModules -Root $script:Root
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('apptests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $script:Work -Force)
    $env:{{ENVPREFIX}}_DATA_DIR = Join-Path $script:Work 'data'    # tests never touch the real user profile
    Initialize-Renderer -Ansi $false -Sink Buffer
    Set-IconTier 'Ascii'
}
function Remove-TestEnvironment { if ($script:Work -and (Test-Path -LiteralPath $script:Work) -and $script:Work.Contains('apptests-')) { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue } }
function Get-TestWork { return $script:Work }
function Get-TestRoot { return $script:Root }

function Invoke-Ui {
    # Runs an action with a scripted key string; returns what the user would have seen.
    param([scriptblock]$Action, [string]$Keys)
    Initialize-Renderer -Ansi $false -Sink Buffer
    Set-ScriptedInput $Keys
    $err = ''; $val = $null
    try { $val = & $Action } catch { $err = $_.Exception.Message }
    $out = Get-CapturedOutput
    Clear-ScriptedInput
    return [pscustomobject]@{ Output = $out; Error = $err; Value = $val }
}
