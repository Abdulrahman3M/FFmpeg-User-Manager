Set-TestGroup 'Platform'
Assert-True 'Test-IsWindows returns a boolean' ((Test-IsWindows) -is [bool])
Assert-True 'platform name is one of Windows/Linux/macOS' ((Get-PlatformName) -in @('Windows', 'Linux', 'macOS'))
Assert-Equal 'data directory override wins' 'X' (Get-AppDataDirectory -AppName 'a' -Override 'X')
Assert-True 'Find-Executable returns $null for a program that does not exist' ($null -eq (Find-Executable 'definitely-not-a-real-program-xyz'))

Set-TestGroup 'Process argument quoting'
Assert-Equal 'plain argument is untouched' 'abc' (ConvertTo-ProcessArgument 'abc')
Assert-Equal 'spaces are quoted' '"a b"' (ConvertTo-ProcessArgument 'a b')
Assert-Equal 'empty argument becomes ""' '""' (ConvertTo-ProcessArgument '')
Assert-Equal 'embedded quote is escaped' '"a\"b c"' (ConvertTo-ProcessArgument 'a"b c')
Assert-Equal 'trailing backslash before the closing quote is doubled' '"C:\my dir\\"' (ConvertTo-ProcessArgument 'C:\my dir\')
$child = Join-Path (Get-TestWork) 'child args.ps1'
[System.IO.File]::WriteAllText($child, 'Write-Output ("n=" + $args.Count + " first=" + $args[0])')
$r = Invoke-External -FilePath (Get-CurrentPowerShellPath) -Arguments @('-NoProfile', '-File', $child, 'one two', 'three') -TimeoutSec 60
Assert-True 'external program runs and exits 0' ($r.Started -and $r.ExitCode -eq 0) ($r.Error)
Assert-Equal 'an argument with a space arrives as ONE argument' 'n=2 first=one two' $r.StdOut.Trim()
$r2 = Invoke-External -FilePath 'definitely-not-a-real-program-xyz' -TimeoutSec 5
Assert-True 'a missing program is reported, not thrown' ((-not $r2.Started) -and $r2.Error.Length -gt 0)

Set-TestGroup 'Settings'
Assert-Equal 'unset setting returns the default' 'dflt' (Get-UserSetting 'nothing' 'dflt')
Assert-True 'a setting can be written' (Set-UserSetting 'k' 'v')
Assert-Equal 'a written setting is read back' 'v' (Get-UserSetting 'k')

Set-TestGroup 'Validation'
Assert-True 'empty name is rejected' ($null -ne (Test-PersonName ''))
Assert-True 'a normal name is accepted' ($null -eq (Test-PersonName 'Ada Lovelace'))
Assert-True 'a 41 character name is rejected' ($null -ne (Test-PersonName ('x' * 41)))
