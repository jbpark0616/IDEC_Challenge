$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runRoot = Join-Path $projectRoot 'evidence/report700/cluster_all'
$originalRoot = Join-Path $projectRoot 'evidence/report700/cluster'
$driverLog = Join-Path $projectRoot 'evidence/report_baseline_700mhz/cluster_all_run.log'
$figureLog = Join-Path $projectRoot 'evidence/report_baseline_700mhz/selection_run.log'
$Host.UI.RawUI.WindowTitle = 'VGG measurement progress - live'
while ($true) {
    $doneCount = 0
    $lines = @()
    foreach ($layer in 1..13) {
        $states = @()
        foreach ($sparse in 0..1) {
            $file = Join-Path $runRoot "conv${layer}_sparse${sparse}.log"
            $reused = $false
            if (-not (Test-Path -LiteralPath $file) -and $layer -in @(1,5,9,13)) {
                $file = Join-Path $originalRoot "conv${layer}_sparse${sparse}.log"
                $reused = $true
            }
            $state = 'pending'
            if (Test-Path -LiteralPath $file) {
                $tail = @(Get-Content -LiteralPath $file -Tail 8)
                if (($tail -join "`n") -match 'PASS ISOLATED_LAYER') {
                    $doneCount++
                    $state = if ($reused) { 'PASS(saved)' } else { 'PASS' }
                } elseif (($tail -join "`n") -match '%Fatal|Aborting') {
                    $state = 'ERROR'
                } else {
                    $state = 'in progress'
                }
            }
            $states += $state
        }
        $lines += ('Conv{0,-2}   OFF: {1,-13} ON: {2,-13}' -f $layer, $states[0], $states[1])
    }
    $percent = 100.0 * $doneCount / 26
    $filled = [int][Math]::Floor($percent / 100 * 40)
    $bar = ('#' * $filled) + ('-' * (40 - $filled))
    $latest = Get-ChildItem -LiteralPath $runRoot -Filter 'conv*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $failed = (Test-Path -LiteralPath $driverLog) -and ((Get-Content -LiteralPath $driverLog -Tail 15) -join "`n") -match 'Traceback|CalledProcessError'
    Clear-Host
    Write-Host 'VGG OFF/ON measurements | 16 cores | U8/V8' -ForegroundColor Cyan
    Write-Host ('[{0}] {1:N1}%  ({2}/26 verified runs)' -f $bar, $percent, $doneCount) -ForegroundColor Green
    Write-Host 'Progress = completed run count, NOT elapsed-time percentage.'
    Write-Host 'Previously verified Conv1/5/9/13 results are included.'
    Write-Host ''
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ''
    if ($latest) {
        Write-Host ('Latest log: ' + $latest.Name)
        Get-Content -LiteralPath $latest.FullName -Tail 3 | ForEach-Object { Write-Host $_ }
        Write-Host ('Last log write: ' + $latest.LastWriteTime.ToString('HH:mm:ss'))
    }
    if ($failed) { Write-Host 'MEASUREMENT STOPPED WITH ERROR - see cluster_all_run.log' -ForegroundColor Red }
    if ($doneCount -eq 26) {
        Write-Host 'All measurements verified. Plot generation status:' -ForegroundColor Green
        if (Test-Path -LiteralPath $figureLog) { Get-Content -LiteralPath $figureLog -Tail 3 | ForEach-Object { Write-Host $_ } }
    }
    Write-Host ''
    Write-Host ('Refreshed: ' + (Get-Date -Format 'HH:mm:ss') + ' | refresh 2s | closing this window does NOT stop simulation')
    Start-Sleep -Seconds 2
}
