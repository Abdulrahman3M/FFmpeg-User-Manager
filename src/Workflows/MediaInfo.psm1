# MediaInfo.psm1 - workflow 18: Media Information (readable ffprobe summary + technical details).
Set-StrictMode -Version 2.0

function Show-MediaInfoScreen {
    # Sections: File, Video, Audio, Subtitles, Metadata, Streams. Returns 'Another' or 'Back'.
    param($Info, [string]$Title = 'Media Information')
    $uiw = Get-UiWidth
    $sections = Get-MediaDetailSections $Info
    $lines = New-Object System.Collections.Generic.List[object]
    foreach ($k in $sections.Keys) {
        $lines.Add(@{ Type = 'rule'; Text = $k })
        foreach ($r in $sections[$k]) { $lines.Add(@{ Type = 'row'; Row = $r }) }
    }
    $top = 0
    while ($true) {
        $size = Get-UiSize
        $page = [math]::Max(6, $size.Height - 6)
        Hide-Cursor
        Start-Frame
        Write-UiSegments @(@(((Get-Icon 'Info') + '  '), 'PrimaryAccent'), @($Title, 'Title'))
        $end = [math]::Min($lines.Count, $top + $page)
        for ($i = $top; $i -lt $end; $i++) {
            $l = $lines[$i]
            if ($l.Type -eq 'rule') { Write-Rule -Title $l.Text } else { Write-KeyValueTable -Rows @(, $l.Row) -LabelWidth 18 -Indent 1 }
        }
        $hints = @(@('T', 'Technical details'), @('N', 'Inspect another'), @('Esc', 'Back'))
        if ($lines.Count -gt $page) { $hints = @(@('Up/Down', 'Scroll')) + $hints }
        Write-KeyHints $hints
        Stop-Frame
        $k = Read-TuiKey
        switch ($k.Name) {
            'Up' { if ($top -gt 0) { $top-- } }
            'Down' { if ($top + $page -lt $lines.Count) { $top++ } }
            'PageUp' { $top = [math]::Max(0, $top - $page) }
            'PageDown' { $top = [math]::Max(0, [math]::Min($lines.Count - $page, $top + $page)) }
            'Esc' { return 'Back' }
            'CtrlC' { return 'Back' }
            'Char' {
                switch ($k.Char.ToUpperInvariant()) {
                    'T' { Show-TextViewer -Title 'Technical details' -Lines (Get-TechnicalDetailLines $Info) }
                    'N' { return 'Another' }
                    'B' { return 'Back' }
                }
            }
        }
    }
}

function Get-TechnicalDetailLines {
    # Formatted (not raw JSON) listing of every field ffprobe reports per stream.
    param($Info)
    $lines = @()
    $r = Invoke-ExternalCapture -FilePath (Get-FFprobePath) -Arguments @('-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', '-i', $Info.Path) -TimeoutSec 60
    if ($r.ExitCode -ne 0) { return @('Technical details are not available for this input.') }
    try { $j = $r.StdOut | ConvertFrom-Json } catch { return @('Technical details could not be read.') }
    $lines += 'Container'
    foreach ($p in $j.format.PSObject.Properties) { if ($p.Name -ne 'tags' -and "$($p.Value)" -ne '') { $lines += ('  {0,-22} {1}' -f $p.Name, $p.Value) } }
    foreach ($s in @($j.streams)) {
        $lines += ''
        $lines += ("Stream #{0} ({1})" -f $s.index, $s.codec_type)
        foreach ($p in $s.PSObject.Properties) {
            if ($p.Name -in @('tags', 'disposition', 'side_data_list')) { continue }
            if ("$($p.Value)" -eq '') { continue }
            $lines += ('  {0,-22} {1}' -f $p.Name, $p.Value)
        }
        if ($s.tags) { foreach ($t in $s.tags.PSObject.Properties) { $lines += ('  tag:{0,-18} {1}' -f $t.Name, $t.Value) } }
    }
    return $lines
}

function Start-MediaInfoWorkflow {
    $step = Get-InputFileStep -Id 'input' -Prompt 'File to inspect' -Require Any -NoPanel -Help 'Type or paste the path of any media file.'
    while ($true) {
        $r = Invoke-Wizard -Title 'Media Information' -Description 'Inspect a media file using ffprobe in a readable summary.' -Icon 'Info' -Steps @($step)
        if ($r.Status -ne 'Completed') { return }
        $info = Get-Media $r.State 'input'
        $act = Show-MediaInfoScreen -Info $info
        if ($act -ne 'Another') { return }
    }
}

Export-ModuleMember -Function Show-MediaInfoScreen, Get-TechnicalDetailLines, Start-MediaInfoWorkflow
