# Unit tests: shared batch file collection, collision policy, and queue state.
Set-TestGroup 'Batch processing core'

$batchRoot = Get-TestWork
$source = Join-Path $batchRoot 'inputs'
$out = Join-Path $batchRoot 'outputs'
[void](New-Item -ItemType Directory -Path $source -Force)
[void](New-Item -ItemType Directory -Path $out -Force)
$one = Join-Path $source 'one file.mp4'
$two = Join-Path $source 'two file.mp4'
[System.IO.File]::WriteAllBytes($one, [byte[]](1..8))
[System.IO.File]::WriteAllBytes($two, [byte[]](1..8))
$unicodeName = ([string][char]0x0645) + ([string][char]0x0644) + ([string][char]0x0641) + ' space.mp4'
$unicodePath = Join-Path $source $unicodeName
[System.IO.File]::WriteAllBytes($unicodePath, [byte[]](1..8))
$unsupportedPath = Join-Path $source 'notes.txt'
[System.IO.File]::WriteAllText($unsupportedPath, 'not media')

$queue = @(New-BatchQueue -Paths @($one, $two))
Assert-True 'multiple paths create waiting queue entries in order' ($queue.Count -eq 2 -and $queue[0].Status -eq 'Waiting' -and $queue[1].Index -eq 2)
Assert-Equal 'queue summary starts with all items remaining' '0|0|0|2' ((Get-BatchQueueSummary $queue).Completed.ToString() + '|' + (Get-BatchQueueSummary $queue).Failed.ToString() + '|' + (Get-BatchQueueSummary $queue).Skipped.ToString() + '|' + (Get-BatchQueueSummary $queue).Remaining.ToString())

$p = Resolve-BatchOutputPath -InputPath $one -OutputFolder $out -Extension '.mkv' -Policy 'rename' -ReservedNames @{}
Assert-Equal 'new batch output keeps input stem and changes extension' (Join-Path $out 'one file.mkv') $p.ActionPath
[System.IO.File]::WriteAllBytes($p.ActionPath, [byte[]](1..8))
$skip = Resolve-BatchOutputPath -InputPath $one -OutputFolder $out -Extension '.mkv' -Policy 'skip' -ReservedNames @{}
Assert-Equal 'existing output is skipped when policy is skip' 'Skip' $skip.Action
$rename = Resolve-BatchOutputPath -InputPath $one -OutputFolder $out -Extension '.mkv' -Policy 'rename' -ReservedNames @{}
Assert-Equal 'existing output is collision-safely renamed' (Join-Path $out 'one file_2.mkv') $rename.ActionPath

$found = @(Get-BatchFilesFromFolder -Folder $source -Extensions @('.mp4') -Recurse $false)
Assert-True 'folder collection filters compatible files and preserves spaces and Unicode' ($found.Count -eq 3 -and $found[0].Name -eq 'one file.mp4' -and @($found | Where-Object { $_.Name -eq $unicodeName }).Count -eq 1)
$inventory = Get-BatchFolderInventory -Folder $source -Extensions @('.mp4')
Assert-Equal 'folder inventory counts all files' 4 $inventory.Total
Assert-Equal 'folder inventory separates compatible and unsupported files' '3|1' ($inventory.Compatible.ToString() + '|' + $inventory.Unsupported.ToString())
$emptySource = Join-Path $batchRoot 'empty inputs'
[void](New-Item -ItemType Directory -Path $emptySource -Force)
$emptyInventory = Get-BatchFolderInventory -Folder $emptySource -Extensions @('.mp4')
Assert-Equal 'empty folders report zero compatible and unsupported files' '0|0' ($emptyInventory.Compatible.ToString() + '|' + $emptyInventory.Unsupported.ToString())

$runQueue = @(New-BatchQueue -Paths @($one, $two, $one))
$job = New-JobObject -Title 'Batch test' -Summary @() -Stages @(
    @{ Name = 'First'; Arguments = @('-version'); BatchItem = $runQueue[0] },
    @{ Name = 'Broken'; Arguments = @('-definitely-not-an-ffmpeg-option'); BatchItem = $runQueue[1] },
    @{ Name = 'Last'; Arguments = @('-version'); BatchItem = $runQueue[2] }
) -OutputPath $out -OutputKind 'Folder' -EnsureDirs @($out)
$job.BatchQueue = $runQueue; $job.ContinueOnFailure = $true
$ui = Invoke-Ui { Invoke-FFJob -Job $job } '0303030303'
$summary = Get-BatchQueueSummary $runQueue
Assert-True 'a failed batch item does not stop the following item' ($ui.Error -eq '' -and $summary.Completed -eq 2 -and $summary.Failed -eq 1) ("error=[{0}] completed={1} failed={2}" -f $ui.Error, $summary.Completed, $summary.Failed)
Assert-Contains 'batch result identifies failures instead of reporting full success' (Get-FlatText $ui.Output) 'Batch completed with failures'
