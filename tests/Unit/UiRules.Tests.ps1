# Static UI rules: numbered options only (no letter keys), a description under every option, help and an example for
# every question, and no local variable that silently shadows a parameter (PowerShell variables are case-insensitive).
$root = Get-TestRoot
$srcFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -Include '*.psm1', '*.ps1')
$asts = @{}
foreach ($sf in $srcFiles) { $tokens = $null; $errs = $null; $asts[$sf.FullName] = [System.Management.Automation.Language.Parser]::ParseFile($sf.FullName, [ref]$tokens, [ref]$errs) }

function Get-HashKeys { param($H) $k = @{}; foreach ($kv in $H.KeyValuePairs) { $k[$kv.Item1.Extent.Text.Trim("'", '"')] = $kv.Item2 }; return $k }

Set-TestGroup 'UI rules: numbers only, no letter keys'
$letterHits = @(); $keyHits = @()
foreach ($sf in $srcFiles) {
    $txt = Get-Content -LiteralPath $sf.FullName -Raw
    if ($txt -match "Char\.ToUpperInvariant\(\)\s*-eq\s*'[A-Za-z]'") { $letterHits += $sf.Name }
    if ($sf.Name -ne 'Menu.psm1' -and $txt -match "(?m)@\{[^}\r\n]*\bKey\s*=\s*'") { $keyHits += $sf.Name }
    if ($txt -match 'Get-MenuHotkeys|-AutoKeys') { $letterHits += ($sf.Name + ' (hotkeys)') }
}
Assert-True 'no source file reacts to a letter key (menus, dialogs and screens are numeric; Esc / Enter / Ctrl+C / arrows only)' ($letterHits.Count -eq 0) ($letterHits -join ', ')
Assert-True 'no menu item or dialog action is given a hand-written key (numbers are assigned automatically)' ($keyHits.Count -eq 0) ($keyHits -join ', ')
$bracketKeys = @(); foreach ($sf in $srcFiles) { $txt = Get-Content -LiteralPath $sf.FullName -Raw; if ($txt -cmatch "'\s*\[[A-Z]\]\s") { $bracketKeys += $sf.Name } }
Assert-True 'no "[X] label" letter-style option text anywhere' ($bracketKeys.Count -eq 0) ($bracketKeys -join ', ')

Set-TestGroup 'UI rules: every option and question explains itself'
$noDesc = @(); $noYesDesc = @(); $noHelp = @(); $noExample = @(); $noMenuDesc = @()
$stepTypes = @('Choice', 'MultiChoice', 'YesNo', 'Text', 'Integer', 'Decimal', 'Timestamp', 'Bitrate', 'FrameRate', 'Color', 'Resolution', 'File', 'Files', 'Directory')
$textTypes = @('Text', 'Integer', 'Decimal', 'Timestamp', 'Bitrate', 'FrameRate', 'Color', 'Resolution', 'File', 'Directory')
foreach ($sf in $srcFiles) {
    $ast = $asts[$sf.FullName]
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        if ($c.GetCommandName() -ne 'New-Choice') { continue }
        $pos = @($c.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
        $named = @($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Desc' })
        if ($pos.Count -lt 3 -and $named.Count -eq 0) { $noDesc += "$($sf.Name):$($c.Extent.StartLineNumber)" }
    }
    foreach ($h in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
        $k = Get-HashKeys $h
        if ($k.ContainsKey('Id') -and $k.ContainsKey('Type')) {
            $t = $k['Type'].Extent.Text.Trim("'", '"')
            if ($stepTypes -contains $t) {
                $where = "$($sf.Name):$($h.Extent.StartLineNumber)"
                if (-not $k.ContainsKey('Help')) { $noHelp += $where }
                if ($t -eq 'YesNo' -and -not ($k.ContainsKey('YesDesc') -and $k.ContainsKey('NoDesc'))) { $noYesDesc += $where }
                if ($textTypes -contains $t -and -not $k.ContainsKey('Example')) { $noExample += $where }
            }
        }
        if ($k.ContainsKey('Label') -and ($k.ContainsKey('Value') -or $k.ContainsKey('Icon')) -and -not $k.ContainsKey('Desc')) { $noMenuDesc += "$($sf.Name):$($h.Extent.StartLineNumber)" }
    }
}
Assert-True 'every choice offered in a wizard question has a description (New-Choice value label DESCRIPTION)' ($noDesc.Count -eq 0) ($noDesc -join ', ')
Assert-True 'every Yes/No question describes both answers (YesDesc and NoDesc)' ($noYesDesc.Count -eq 0) ($noYesDesc -join ', ')
Assert-True 'every wizard question has help text that says what to enter or choose' ($noHelp.Count -eq 0) ($noHelp -join ', ')
Assert-True 'every typed-input question has an example' ($noExample.Count -eq 0) ($noExample -join ', ')
Assert-True 'every menu / dialog item has a description' ($noMenuDesc.Count -eq 0) ($noMenuDesc -join ', ')

Set-TestGroup 'UI rules: variable names are case-insensitive'
$shadow = @()
foreach ($sf in $srcFiles) {
    $ast = $asts[$sf.FullName]
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $fn.Body.ParamBlock) { continue }
        $params = @($fn.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath.ToLowerInvariant() })
        $seenSelf = @{}
        $assigns = @($fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) | Sort-Object { $_.Extent.StartOffset })
        foreach ($a in $assigns) {
            $left = $a.Left
            if ($left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $nm = $left.VariablePath.UserPath.ToLowerInvariant()
            if ($params -notcontains $nm) { continue }
            $selfRef = @($a.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath.ToLowerInvariant() -eq $nm }, $true)).Count -gt 0
            # A parameter copied to a lower-case local ($noPanel = [bool]$NoPanel) is the same variable and is the safe idiom.
            if ($selfRef) { $seenSelf[$nm] = $true; continue }
            if ($a.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) { continue }
            $declared = @($fn.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath.ToLowerInvariant() -eq $nm })[0].Name.VariablePath.UserPath
            # Re-assigning a parameter under its own spelling is deliberate; a different spelling is almost always an accident.
            if (($declared -cne $left.VariablePath.UserPath) -and -not $seenSelf.ContainsKey($nm)) { $shadow += ($sf.Name + ':' + $fn.Name + ' $' + $left.VariablePath.UserPath + ' collides with parameter $' + $declared) }
        }
    }
}
Assert-True 'no function assigns a variable whose name differs from a parameter only by case' ($shadow.Count -eq 0) ($shadow -join '; ')
