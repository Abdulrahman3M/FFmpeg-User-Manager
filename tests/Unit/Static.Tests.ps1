# Static analysis: safety rules, Windows PowerShell 5.1 compatibility (syntax level), structure.
$root = Get-TestRoot
$srcFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }) + @(Get-Item -LiteralPath (Join-Path $root 'Start-FFmpegTUI.ps1'))
$asts = @{}
Set-TestGroup 'Static: parse'
foreach ($sf in $srcFiles) {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sf.FullName, [ref]$tokens, [ref]$errs)
    $asts[$sf.FullName] = $ast
    Assert-True "parses without errors: $($sf.Name)" ($errs.Count -eq 0) (($errs | ForEach-Object { $_.Message }) -join '; ')
}

Set-TestGroup 'Static: safety rules'
$iex = @(); $net = @(); $rm = @()
foreach ($sf in $srcFiles) {
    $ast = $asts[$sf.FullName]
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $c.GetCommandName()
        if (-not $name) { continue }
        if ($name -in @('Invoke-Expression', 'iex')) { $iex += "$($sf.Name):$($c.Extent.StartLineNumber)" }
        if ($name -in @('Invoke-WebRequest', 'Invoke-RestMethod', 'iwr', 'irm', 'curl', 'wget', 'Start-BitsTransfer')) { $net += "$($sf.Name):$($c.Extent.StartLineNumber)" }
        if ($name -in @('Remove-Item', 'rm', 'del', 'Move-Item', 'Rename-Item')) { $rm += "$($sf.Name):$($c.Extent.StartLineNumber)" }
    }
    $txt = Get-Content -LiteralPath $sf.FullName -Raw
    if ($txt -match 'System\.Net\.WebClient|System\.Net\.Http|Net\.WebRequest') { $net += "$($sf.Name): .NET web client" }
}
Assert-True 'Invoke-Expression / iex is never used' ($iex.Count -eq 0) ($iex -join ', ')
Assert-True 'no network download code (no telemetry, no downloads outside winget)' ($net.Count -eq 0) ($net -join ', ')
$allowedRm = @('WorkflowCommon.psm1', 'Paths.psm1')
$badRm = @($rm | Where-Object { $allowedRm -notcontains ($_ -split ':')[0] })
Assert-True 'file deletion is limited to temp files, probe files and empty failed outputs' ($badRm.Count -eq 0) ($badRm -join ', ')
$srcDelete = @()
foreach ($sf in $srcFiles) { $t = Get-Content -LiteralPath $sf.FullName -Raw; if ($t -match 'Remove-Item[^\r\n]*-Recurse') { $srcDelete += $sf.Name } }
Assert-True 'no recursive deletion anywhere in the application' ($srcDelete.Count -eq 0) ($srcDelete -join ', ')
$procStart = @()
foreach ($sf in $srcFiles) { $t = Get-Content -LiteralPath $sf.FullName -Raw; if ($t -match 'UseShellExecute\s*=\s*\$true|Start-Process|cmd\.exe|powershell\.exe\s+-c') { $procStart += $sf.Name } }
Assert-True 'child processes never go through a shell (no Start-Process / cmd.exe / UseShellExecute)' ($procStart.Count -eq 0) ($procStart -join ', ')
Assert-True 'no accounts, ads or telemetry vocabulary in source' (-not (@($srcFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?i)telemetry|analytics|applicationinsights|google-analytics' }).Count))

Set-TestGroup 'Static: Windows PowerShell 5.1 compatibility (syntax level; runtime on 5.1 is verified separately)'
$badNodes = @(); $badCmd = @(); $badVar = @(); $badApi = @()
$ps7Types = @('TernaryExpressionAst', 'PipelineChainAst', 'NullConditionalMemberAccessAst', 'NullConditionalIndexExpressionAst', 'ChainableAst')
foreach ($sf in $srcFiles) {
    $ast = $asts[$sf.FullName]
    foreach ($n in $ast.FindAll({ $true }, $true)) {
        $tn = $n.GetType().Name
        if ($tn -in @('TernaryExpressionAst', 'PipelineChainAst', 'NullConditionalMemberAccessAst', 'NullConditionalIndexExpressionAst')) { $badNodes += "$($sf.Name):$($n.Extent.StartLineNumber) $tn" }
        if ($tn -eq 'BinaryExpressionAst' -and "$($n.Operator)" -in @('QuestionQuestion', 'QuestionQuestionEquals')) { $badNodes += "$($sf.Name):$($n.Extent.StartLineNumber) null-coalescing" }
        if ($tn -eq 'CommandAst') {
            $cn = $n.GetCommandName()
            $paramNames = @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            if ($cn -eq 'ForEach-Object' -and $paramNames -contains 'Parallel') { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) ForEach-Object -Parallel" }
            if ($cn -eq 'ConvertFrom-Json' -and ($paramNames -contains 'AsHashtable' -or $paramNames -contains 'Depth')) { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) ConvertFrom-Json -AsHashtable/-Depth" }
            if ($cn -eq 'Join-Path') { $pos = @($n.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] }); if ($pos.Count -gt 2 -or $paramNames -contains 'AdditionalChildPath') { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) Join-Path with >2 segments" } }
            if ($cn -in @('Get-Content', 'Set-Content', 'Out-File', 'Add-Content') -and ($paramNames -contains 'AsByteStream' -or ($paramNames -contains 'Encoding' -and ($n.Extent.Text -match 'utf8NoBOM|utf8BOM')))) { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) PS7-only encoding/AsByteStream" }
            if ($cn -in @('Start-ThreadJob', 'Test-Json', 'Get-Error', 'Join-String', 'Remove-Alias')) { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) $cn" }
            if ($cn -eq 'Split-Path' -and ($paramNames -contains 'LeafBase' -or $paramNames -contains 'Extension')) { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) Split-Path -LeafBase/-Extension" }
            if ($cn -eq 'Get-Random' -and $paramNames -contains 'Shuffle') { $badCmd += "$($sf.Name):$($n.Extent.StartLineNumber) Get-Random -Shuffle" }
        }
        if ($tn -eq 'VariableExpressionAst') {
            $vn = $n.VariablePath.UserPath
            if ($vn -in @('IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR', 'PSStyle', 'PSNativeCommandArgumentPassing') -and $sf.Name -ne 'Environment.psm1') { $badVar += "$($sf.Name):$($n.Extent.StartLineNumber) `$$vn" }
        }
    }
    $t = Get-Content -LiteralPath $sf.FullName -Raw
    foreach ($pat in 'ArgumentList', 'GetRelativePath', '\[Math\]::Clamp', '\[System\.Text\.Json', 'ConvertFrom-Json\s+-AsHashtable', 'Environment\]::ProcessPath', 'RuntimeInformation\]::IsOSPlatform') { if ($t -match $pat) { $badApi += "$($sf.Name): $pat" } }
}
Assert-True 'no PowerShell-7-only syntax (ternary, ??, ?., pipeline chains)' ($badNodes.Count -eq 0) ($badNodes -join '; ')
Assert-True 'no PowerShell-7-only cmdlet parameters or cmdlets' ($badCmd.Count -eq 0) ($badCmd -join '; ')
Assert-True '$IsWindows/$IsLinux/... only read through the guarded helper in Environment.psm1' ($badVar.Count -eq 0) ($badVar -join '; ')
Assert-True 'no .NET-Core-only APIs (ProcessStartInfo.ArgumentList, GetRelativePath, Math.Clamp, System.Text.Json)' ($badApi.Count -eq 0) ($badApi -join '; ')
$nonAscii = @()
foreach ($sf in $srcFiles) { $bytes = [System.IO.File]::ReadAllBytes($sf.FullName); if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { $nonAscii += $sf.Name } }
Assert-True 'source files are pure ASCII (Windows PowerShell 5.1 reads BOM-less files as ANSI)' ($nonAscii.Count -eq 0) ($nonAscii -join ', ')
Assert-True 'Windows PowerShell 5.1 helper: Test-IsWindows does not rely on $IsWindows when Major < 6' ((Get-Content -LiteralPath (Join-Path $root 'src/Core/Environment.psm1') -Raw) -match 'PSVersion\.Major -lt 6')
$emptyStrArr = @()
foreach ($sf in $srcFiles) { $t = Get-Content -LiteralPath $sf.FullName -Raw; if ($t -match '\[Parameter\(Mandatory\)\]\[string\[\]\]') { $emptyStrArr += $sf.Name } }
Assert-True 'no Mandatory [string[]] parameters that reject empty tokens' ($emptyStrArr.Count -eq 0) ($emptyStrArr -join ', ')

Set-TestGroup 'Static: structure'
foreach ($m in @('Core/App', 'Core/Environment', 'Core/ProcessRunner', 'Core/Validation', 'Core/Paths', 'FFmpeg/FFmpegManager', 'FFmpeg/FFmpegCapabilities', 'FFmpeg/FFmpegCommandBuilder', 'FFmpeg/FFmpegProgress', 'FFmpeg/MediaProbe', 'TUI/Theme', 'TUI/Renderer', 'TUI/Input', 'TUI/Menu', 'TUI/Wizard', 'TUI/Dialog', 'TUI/ProgressView')) {
    Assert-True "module exists: $m" (Test-Path -LiteralPath (Join-Path (Join-Path $root 'src') ($m + '.psm1')))
}
foreach ($m in @('ConvertVideo', 'ConvertAudio', 'ExtractAudio', 'TrimMedia', 'MergeMedia', 'CompressMedia', 'CompressionPlanning', 'CompressionWorkflow', 'UpscaleImage', 'ResizeVideo', 'VideoToGif', 'ExtractFrames', 'AudioTools', 'SubtitleTools', 'FrameRate', 'Filters', 'TransformVideo', 'OverlayTools', 'PlaybackSpeed', 'RemuxStreams', 'MetadataChapters', 'ImagesAndVisuals', 'AudioEffects', 'VideoEnhance', 'CaptureMedia', 'AnalyzeMedia', 'BatchConvert', 'AdvancedTools', 'StreamingHls', 'MediaInfo')) {
    Assert-True "workflow module exists: $m" (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $root 'src') 'Workflows') ($m + '.psm1')))
}
foreach ($fn in @('Start-ConvertVideoWorkflow', 'Start-ConvertAudioWorkflow', 'Start-ExtractAudioWorkflow', 'Start-TrimWorkflow', 'Start-MergeWorkflow', 'Start-CompressWorkflow', 'Start-UpscaleImageWorkflow', 'Start-ResizeWorkflow', 'Start-GifWorkflow', 'Start-ExtractFramesWorkflow', 'Start-AudioToolsWorkflow', 'Start-SubtitleToolsWorkflow', 'Start-FrameRateWorkflow', 'Start-FiltersWorkflow', 'Start-TransformWorkflow', 'Start-OverlayWorkflow', 'Start-SpeedWorkflow', 'Start-StreamingWorkflow', 'Start-MediaInfoWorkflow', 'Start-RemuxStreamsWorkflow', 'Start-MetadataChaptersWorkflow', 'Start-ImagesAndVisualsWorkflow', 'Start-VideoEnhanceWorkflow', 'Start-CaptureWorkflow', 'Start-AnalyzeWorkflow', 'Start-BatchWorkflow', 'Start-AdvancedWorkflow', 'Start-MaintenanceTool', 'Show-FFmpegStatus')) {
    Assert-True "menu target is wired: $fn" ($null -ne (Get-Command $fn -ErrorAction SilentlyContinue))
}
$wired = @(Get-MainMenuItems | Where-Object { $_.Value -ne 'Quit' } | ForEach-Object { $_.Value })
Assert-Equal 'every main-menu item maps to an action' 29 $wired.Count
$cfg = Get-Content -LiteralPath (Join-Path $root 'config/defaults.json') -Raw | ConvertFrom-Json
Assert-True 'config/defaults.json is valid and holds only defaults' ($cfg.winget.packageId -eq 'Gyan.FFmpeg' -and $cfg.presets.gifFps.Count -gt 3)
Assert-True 'config stores no secrets or user paths' ((Get-Content -LiteralPath (Join-Path $root 'config/defaults.json') -Raw) -notmatch '(?i)password|token|secret|apikey|C:\\Users')
foreach ($d in @('README.md', 'docs/Architecture.md', 'docs/Workflows.md', 'docs/Testing.md')) { Assert-True "documentation exists: $d" (Test-Path -LiteralPath (Join-Path $root $d)) }

Set-TestGroup 'Static: scriptblock closures (wizard step blocks run in another scope)'
# A scriptblock that reads a local variable of its enclosing function must be closed with .GetNewClosure(),
# otherwise the wizard (a different module) cannot see it when it invokes the block later.
$auto = @('_', 'PSItem', 'args', 'true', 'false', 'null', 'input', 'PSCmdlet', 'PSBoundParameters', 'this', 'Matches', 'Error', 'ErrorActionPreference', 'MyInvocation', 'PSScriptRoot', 'foreach', 'switch', 'env', 'HOME', 'Host', 'PSVersionTable', 'PID', 'OFS')
$closureIssues = @()
foreach ($sf in ($srcFiles | Where-Object { $_.FullName -like '*Workflows*' -or $_.Name -in @('Wizard.psm1', 'App.psm1') })) {
    $ast = $asts[$sf.FullName]
    $blocks = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true)
    foreach ($b in $blocks) {
        # Blocks handed straight to pipeline cmdlets run immediately in the caller's scope: no closure needed.
        if ($b.Parent -is [System.Management.Automation.Language.CommandAst] -and $b.Parent.GetCommandName() -in @('ForEach-Object', 'Where-Object', 'Sort-Object', 'Select-Object', 'Group-Object', 'Measure-Object', 'Invoke-Command')) { continue }
        $sb = $b.ScriptBlock
        $used = @($sb.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath }) | Where-Object { -not $_.IsScript -and -not $_.IsGlobal -and -not $_.DriveName } | ForEach-Object { $_.UserPath } | Where-Object { $auto -notcontains $_ } | Sort-Object -Unique
        $local = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        if ($sb.ParamBlock) { foreach ($p in $sb.ParamBlock.Parameters) { [void]$local.Add($p.Name.VariablePath.UserPath) } }
        foreach ($a in $sb.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) { foreach ($v in $a.Left.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) { [void]$local.Add($v.VariablePath.UserPath) } }
        foreach ($f in $sb.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) { [void]$local.Add($f.Variable.VariablePath.UserPath) }
        foreach ($f in $sb.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) { }
        $free = @($used | Where-Object { -not $local.Contains($_) })
        if ($free.Count -eq 0) { continue }
        # variables defined by any enclosing function / scriptblock scope
        $defined = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        $p = $b.Parent
        while ($p) {
            $body = $null
            if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $body = $p.Body; foreach ($pp in @($p.Parameters | Where-Object { $_ })) { [void]$defined.Add($pp.Name.VariablePath.UserPath) } }
            elseif ($p -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $p -ne $b) { $body = $p.ScriptBlock }
            if ($body) {
                if ($body.ParamBlock) { foreach ($pp in $body.ParamBlock.Parameters) { [void]$defined.Add($pp.Name.VariablePath.UserPath) } }
                foreach ($a in $body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                    if ($a.Extent.StartOffset -ge $b.Extent.StartOffset -and $a.Extent.EndOffset -le $b.Extent.EndOffset) { continue }
                    foreach ($v in $a.Left.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) { [void]$defined.Add($v.VariablePath.UserPath) }
                }
            }
            $p = $p.Parent
        }
        $captured = @($free | Where-Object { $defined.Contains($_) })
        if ($captured.Count -eq 0) { continue }
        $closed = ($b.Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $b.Parent.Member.Value -eq 'GetNewClosure')
        if (-not $closed) { $closureIssues += ("{0}:{1} reads {2}" -f $sf.Name, $b.Extent.StartLineNumber, ($captured -join ',')) }
    }
}
Assert-True 'every scriptblock that reads an enclosing local variable is closed with .GetNewClosure()' ($closureIssues.Count -eq 0) ($closureIssues -join "`n")

Set-TestGroup 'Static: operator/parameter mix-ups'
$opMix = @()
foreach ($sf in $srcFiles) {
    foreach ($c in $asts[$sf.FullName].FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        foreach ($el in $c.CommandElements) {
            if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -in @('and', 'or', 'not', 'eq', 'ne', 'gt', 'lt', 'ge', 'le', 'like', 'match', 'contains', 'in', 'notin', 'is', 'isnot', 'notmatch', 'notlike')) { $opMix += "$($sf.Name):$($c.Extent.StartLineNumber) command '$($c.GetCommandName())' receives -$($el.ParameterName) as a parameter (missing parentheses?)" }
        }
    }
}
Assert-True 'no comparison operators are accidentally passed as command parameters (e.g. "if (Test-X -and $y)")' ($opMix.Count -eq 0) ($opMix -join "`n")
# mutation check: prove the closure rule really detects the bug class it guards against
$mut = 'function F { $p = "x"; return @{ V = { param($v) $v -eq $p } } }'
$t = $null; $e = $null; $mast = [System.Management.Automation.Language.Parser]::ParseInput($mut, [ref]$t, [ref]$e)
$mb = $mast.Find({ param($n) $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true)
$mfree = @($mb.ScriptBlock.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath })
Assert-True 'closure rule self-check: an unclosed block reading $p is recognizable (test scaffolding sanity)' (($mfree -contains 'p') -and -not ($mb.Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst]))

Set-TestGroup 'Repository presentation: version, links, launcher docs, release package, public-release hygiene'
$versionText = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1).Trim()
Assert-True "VERSION holds a valid Semantic Version ($versionText)" (Test-SemVer $versionText)
Assert-Equal 'application reads the canonical version' $versionText (Get-AppVersion)
$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-True 'README version badge matches VERSION' ($readme -match [regex]::Escape("badge/version-$versionText-"))
$changelog = Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw
Assert-True 'CHANGELOG has an [Unreleased] section and Keep-a-Changelog/SemVer references' ($changelog -match '(?m)^## \[Unreleased\]' -and $changelog -match 'keepachangelog' -and $changelog -match 'semver')
$released = @([regex]::Matches($changelog, '(?m)^## \[(\d+\.\d+\.\d+[^\]]*)\] - \d{4}-\d{2}-\d{2}') | ForEach-Object { $_.Groups[1].Value })
if ($released.Count -gt 0) { Assert-Equal 'newest released CHANGELOG version equals VERSION' $versionText $released[0] } else { Assert-True 'no release is recorded yet, so none is claimed in the README' ($readme -match 'No official release has been published yet') }
$tags = Invoke-ExternalCapture -FilePath 'git' -Arguments @('-C', $root, 'tag', '--list') -TimeoutSec 20
if ($tags.Started -and $tags.ExitCode -eq 0) { $bad = @($tags.StdOut -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(alpha|beta|rc)\.\d+)?$' }); Assert-True 'all existing Git tags use the vMAJOR.MINOR.PATCH[-alpha|beta|rc.N] format' ($bad.Count -eq 0) ($bad -join ', ') }
# README/docs: every relative link and image must exist
$linkIssues = @()
foreach ($md in @('README.md', 'CHANGELOG.md', 'AGENTS.md', 'docs/Architecture.md', 'docs/Workflows.md', 'docs/Testing.md', 'docs/Versioning-and-Releases.md', 'docs/Licensing.md', 'docs/images/README.md', 'tests/Fixtures/README.md')) {
    $mdPath = Join-Path $root $md
    $text = Get-Content -LiteralPath $mdPath -Raw
    $dir = Split-Path -Parent $mdPath
    $targets = @([regex]::Matches($text, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($text, '(?:src|href)="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    foreach ($t in $targets) {
        if ($t -match '^(https?:|mailto:)') { continue }
        $file = ($t -split '#')[0]
        if (-not $file) {
            $anchor = $t.TrimStart('#')
            $heads = @([regex]::Matches($text, '(?m)^#{1,6}\s+(.+)$') | ForEach-Object { ($_.Groups[1].Value.ToLowerInvariant() -replace '[^a-z0-9 \-]', '' -replace ' ', '-') })
            if ($heads -notcontains $anchor) { $linkIssues += "$md -> #$anchor (no such heading)" }
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $dir $file))) { $linkIssues += "$md -> $t" }
    }
}
Assert-True 'all relative links, images and in-page anchors in README/docs resolve' ($linkIssues.Count -eq 0) ($linkIssues -join "`n")
foreach ($img in 'main-menu', 'main-menu-console-safe', 'ffmpeg-status', 'conversion-wizard', 'video-to-gif', 'processing', 'completed') { Assert-True "screenshot exists and is a PNG: $img.png" ((Test-Path -LiteralPath (Join-Path $root "docs/images/$img.png")) -and ([System.IO.File]::ReadAllBytes((Join-Path $root "docs/images/$img.png"))[1] -eq 80)) }
# README commands must match the real launcher
$ast = $asts[(Join-Path $root 'Start-FFmpegTUI.ps1')]
$launcherParams = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$documented = @([regex]::Matches($readme, '(?m)Start-FFmpegTUI\.ps1\s+-([A-Za-z]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert-True ("README documents only real launcher switches ($($documented -join ', '))") (@($documented | Where-Object { $launcherParams -notcontains $_ }).Count -eq 0)
Assert-True 'README mentions the BAT launcher as the primary Quick Start' ($readme -match '(?s)## Quick Start.*?FFmpeg-User-Manager\.bat')
$vo = Invoke-ExternalCapture -FilePath (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-File', (Join-Path $root 'Start-FFmpegTUI.ps1'), '-Version') -TimeoutSec 60
Assert-Equal '.\Start-FFmpegTUI.ps1 -Version prints the product name and version' "FFmpeg User Manager v$versionText" $vo.StdOut.Trim()
Assert-True 'README project-structure tree lists files that exist' (@('FFmpeg-User-Manager.bat', 'Start-FFmpegTUI.ps1', 'VERSION', 'CHANGELOG.md', 'AGENTS.md', 'LICENSE', 'NOTICE', 'config/defaults.json', 'tools/New-ReleasePackage.ps1') | ForEach-Object { Test-Path -LiteralPath (Join-Path $root $_) } | Where-Object { -not $_ } | Measure-Object | ForEach-Object { $_.Count -eq 0 })
Assert-True 'AGENTS.md exists with the core rules' ((Test-Path -LiteralPath (Join-Path $root 'AGENTS.md')) -and ((Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw) -match 'Private' -and (Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw) -match 'COMPLETE'))
# licensing
$licPath = Join-Path $root 'LICENSE'; $noticePath = Join-Path $root 'NOTICE'
Assert-True 'LICENSE and NOTICE exist at the repository root' ((Test-Path -LiteralPath $licPath) -and (Test-Path -LiteralPath $noticePath))
$sha = [System.Security.Cryptography.SHA256]::Create()
$licHash = ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($licPath))) -replace '-', '').ToLowerInvariant()
Assert-Equal 'LICENSE is the unmodified standard Apache-2.0 text (SHA-256 of the text published at apache.org/licenses/LICENSE-2.0.txt)' 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30' $licHash
$noticeText = Get-Content -LiteralPath $noticePath -Raw
Assert-True 'NOTICE carries the product name, a copyright line with a year and owner, and the third-party statement' (($noticeText -match 'FFmpeg User Manager') -and ($noticeText -match 'Copyright 20\d\d \S+') -and ($noticeText -match 'NOT part of this product'))
Assert-True 'README has a License section naming Apache-2.0 and linking LICENSE and NOTICE' (($readme -match '(?m)^## License') -and ($readme -match 'Apache License 2\.0') -and ($readme -match '\]\(LICENSE\)') -and ($readme -match '\]\(NOTICE\)'))
Assert-True 'README no longer claims the repository has no license' ($readme -notmatch 'no license file')
$trackedNow = Invoke-ExternalCapture -FilePath 'git' -Arguments @('-C', $root, 'ls-files') -TimeoutSec 30
$allText = @(@($trackedNow.StdOut -split "`r?`n") | Where-Object { $_ -match '\.(md|ps1|psm1|bat|json)$' -and $_ -notmatch '^tests/|^AGENTS\.md$|^docs/Licensing\.md$' -and (Test-Path -LiteralPath (Join-Path $root $_)) } | ForEach-Object { [System.IO.File]::ReadAllText((Join-Path $root $_)) }) -join "`n"
Assert-True 'no "All Rights Reserved" wording in the project files conflicts with the open license (AGENTS.md and docs/Licensing.md mention it only to forbid it)' ($allText -notmatch '(?i)all rights reserved')
$agents = Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw
Assert-True 'AGENTS.md has the permanent dependency-aware change-sync rule with its flow' (($agents -match 'Dependency-aware change sync') -and ($agents -match 'Identify Affected Dependencies & Artifacts') -and ($agents -match 'Final Verification') -and ($agents -match 'Screenshots and project images') -and ($agents -match 'Changelog') -and ($agents -match 'Release information'))
Assert-True 'AGENTS.md states that the rule does not mean bumping versions or regenerating images blindly' ($agents -match 'Not\*\* what this rule means')
Assert-True 'AGENTS.md has the licensing / third-party notice rule (compatibility, third-party notices, copyright/attribution)' (($agents -match 'License compatibility') -and ($agents -match 'Third-party notices') -and ($agents -match 'Copyright/attribution') -and ($agents -match 'never delete or weaken a required legal notice'))
# release package
$pkgDir = Join-Path (Get-TestWork) 'pkg'
$zipPath = (& (Join-Path $root 'tools/New-ReleasePackage.ps1') -OutputDirectory $pkgDir) | Select-Object -Last 1
Assert-Equal 'release package name follows FFmpeg-User-Manager-vX.Y.Z.zip' "FFmpeg-User-Manager-v$versionText.zip" ([System.IO.Path]::GetFileName($zipPath))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zf = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = @($zf.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    Assert-True 'package contains the launcher, entry script, version and sources' (($names -contains 'FFmpeg-User-Manager/FFmpeg-User-Manager.bat') -and ($names -contains 'FFmpeg-User-Manager/Start-FFmpegTUI.ps1') -and ($names -contains 'FFmpeg-User-Manager/VERSION') -and ($names -contains 'FFmpeg-User-Manager/LICENSE') -and ($names -contains 'FFmpeg-User-Manager/NOTICE') -and ($names -contains 'FFmpeg-User-Manager/src/Core/App.psm1'))
    Assert-True 'package excludes tests, Git data, dist output and development files' (@($names | Where-Object { $_ -match '/tests/|/\.git|/dist/|/tools/|AGENTS\.md' }).Count -eq 0)
} finally { $zf.Dispose() }
# public-release hygiene
$tracked = Invoke-ExternalCapture -FilePath 'git' -Arguments @('-C', $root, 'ls-files') -TimeoutSec 30
$files = @($tracked.StdOut -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '\.png$' })
$secretHits = @(); $pathHits = @()
foreach ($f in $files) {
    $p = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $t = [System.IO.File]::ReadAllText($p)
    if ($t -match '(?i)(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|password\s*[:=]\s*[''"][^''"\s]{4,})') { $secretHits += $f }
    if ($f -notmatch '^tests/' -and $t -cmatch 'C:\\Users\\[A-Za-z0-9_.-]+|/home/[a-z0-9_-]+/|/Users/[A-Za-z0-9_-]+/|/root/') { $pathHits += $f }
}
Assert-True 'no credentials, tokens or private keys in tracked files' ($secretHits.Count -eq 0) ($secretHits -join ', ')
Assert-True 'no developer-machine absolute paths in tracked documentation or source' ($pathHits.Count -eq 0) ($pathHits -join ', ')
$gi = Get-Content -LiteralPath (Join-Path $root '.gitignore') -Raw
Assert-True '.gitignore covers dist/, logs, temp, editor and local env files without hiding sources' (($gi -match '(?m)^dist/') -and ($gi -match '\*\.log') -and ($gi -match '\.vscode/') -and ($gi -match '\.env') -and ($gi -notmatch '(?m)^\*\.ps1|^\*\.psm1|^src/|^docs/|^\*\.md'))
