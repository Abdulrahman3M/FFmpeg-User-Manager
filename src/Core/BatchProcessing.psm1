# BatchProcessing.psm1 - reusable, sequential batch collection, queue state, and safe output planning.
Set-StrictMode -Version 2.0

function Get-BatchFilesFromFolder {
    param([string]$Folder, [string[]]$Extensions, [bool]$Recurse = $false)
    return @((Get-BatchFolderInventory -Folder $Folder -Extensions $Extensions -Recurse $Recurse).Files)
}

function Get-BatchFolderInventory {
    param([string]$Folder, [string[]]$Extensions, [bool]$Recurse = $false)
    $opts = @{ LiteralPath = $Folder; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $opts['Recurse'] = $true }
    $all = @(Get-ChildItem @opts | Sort-Object FullName)
    $allowed = @($Extensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $compatible = @($all | Where-Object { $allowed -contains $_.Extension.ToLowerInvariant() })
    return [pscustomobject]@{ Total = $all.Count; Compatible = $compatible.Count; Unsupported = ($all.Count - $compatible.Count); Files = $compatible }
}

function New-BatchQueue {
    param([string[]]$Paths)
    $items = @(); $index = 0
    foreach ($path in @($Paths)) {
        if (-not $path) { continue }
        $index++
        $items += , ([pscustomobject]@{ Index = $index; InputPath = [string]$path; OutputPath = ''; Status = 'Waiting'; Error = '' })
    }
    return $items
}

function Get-BatchQueueSummary {
    param($Queue)
    $all = @($Queue)
    return [pscustomobject]@{
        Total = $all.Count
        Completed = @($all | Where-Object { $_.Status -eq 'Completed' }).Count
        Failed = @($all | Where-Object { $_.Status -eq 'Failed' }).Count
        Skipped = @($all | Where-Object { $_.Status -eq 'Skipped' }).Count
        Remaining = @($all | Where-Object { $_.Status -in @('Waiting', 'Processing') }).Count
    }
}

function Resolve-BatchOutputPath {
    param([string]$InputPath, [string]$OutputFolder, [string]$Extension, [ValidateSet('skip', 'overwrite', 'rename')][string]$Policy, [hashtable]$ReservedNames = @{})
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $number = 1
    while ($true) {
        $suffix = if ($number -eq 1) { '' } else { '_' + $number }
        $name = $stem + $suffix + $Extension
        $path = Join-Path $OutputFolder $name
        $reserved = $ReservedNames.ContainsKey($name.ToLowerInvariant())
        $exists = Test-Path -LiteralPath $path
        if (-not $reserved -and -not $exists) { return [pscustomobject]@{ Action = 'Process'; ActionPath = $path; Overwrite = $false } }
        if ($number -eq 1 -and $Policy -eq 'skip') { return [pscustomobject]@{ Action = 'Skip'; ActionPath = $path; Overwrite = $false } }
        if ($number -eq 1 -and $Policy -eq 'overwrite') { return [pscustomobject]@{ Action = 'Process'; ActionPath = $path; Overwrite = $true } }
        $number++
    }
}

Export-ModuleMember -Function Get-BatchFilesFromFolder, Get-BatchFolderInventory, New-BatchQueue, Get-BatchQueueSummary, Resolve-BatchOutputPath
