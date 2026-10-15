# CompressMedia.psm1 - workflow 6: Compress Media.
Set-StrictMode -Version 2.0

function Get-CompressSteps { return (Get-CompressionSteps) }

function Get-AutoVideoEncoder {
    param($W)
    return (Get-CompressionAutoVideoEncoder $W)
}

function Build-CompressJob {
    param($W)
    return (Build-CompressionJob $W)
}

function Start-CompressWorkflow {
    Start-CompressionWorkflow
}

Export-ModuleMember -Function Get-CompressSteps, Get-AutoVideoEncoder, Build-CompressJob, Start-CompressWorkflow
