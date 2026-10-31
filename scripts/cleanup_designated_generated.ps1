param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ($workspaceRoot -ne 'C:\IDEC_challenge') { throw 'Unexpected workspace root' }
function Assert-WorkspacePath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($workspaceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Outside workspace: $absolute"
    }
    return $absolute
}
$archiveRoot = Assert-WorkspacePath (Join-Path $workspaceRoot 'archive\designated_legacy_20261025')
if (Test-Path -LiteralPath (Join-Path $archiveRoot 'cleanup_result.json')) {
    Write-Output 'This cleanup is already complete. See cleanup_result.json; nothing changed.'
    exit
}
$experiment = Join-Path $workspaceRoot 'experiments\row_sparse_fixed'
$legacyRelative = @('row_only_v1','bypass_pipelined_v2','iterations\bypass_unpipelined',
                    'iterations\onehot_cursor','iterations\clock_gating')
$legacyRoots = @($legacyRelative | ForEach-Object { Assert-WorkspacePath (Join-Path $experiment $_) } | Where-Object { Test-Path -LiteralPath $_ })
$generatedRoots = @($legacyRoots) + @(Join-Path $experiment 'results')
$removals = @()
foreach ($dir in $generatedRoots) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $items = @(Get-ChildItem -LiteralPath $dir -Recurse -Force)
    if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Reparse point in $dir" }
    $removals += @($items | Where-Object { -not $_.PSIsContainer -and $_.Extension -in @('.vvp','.vcd','.fst','.wdb','.pyc') })
}
$removals += @(Get-ChildItem -LiteralPath $workspaceRoot -File | Where-Object { $_.Name -match '^vivado_\d+\.backup\.(jou|log)$' -or $_.Name -eq 'xelab.pb' })
$plan = @($removals | ForEach-Object {
    [PSCustomObject]@{path=(Assert-WorkspacePath $_.FullName);bytes=$_.Length;reason='reproducible legacy simulation output or stale Vivado backup'}
})
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
$planPath = Join-Path $archiveRoot 'cleanup_plan.json'
if ($Apply -and (Test-Path -LiteralPath $planPath)) {
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
} else {
    $plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8
}
Write-Output ('Generated files eligible: ' + $plan.Count + ', bytes=' + (($plan | Measure-Object bytes -Sum).Sum))
Write-Output ('Legacy folders to archive: ' + ($legacyRoots -join ', '))
if (-not $Apply) { exit }
if (Get-Process vivado,xsim,xelab,vvp,openroad -ErrorAction SilentlyContinue) { throw 'EDA process still running; defer cleanup' }
$protected = @{}
foreach ($dir in @((Join-Path $workspaceRoot 'verilog'), (Join-Path $experiment 'iterations\matched_ablation\rtl'),(Join-Path $experiment 'iterations\final_995_icg\rtl'))) {
    foreach ($file in Get-ChildItem -LiteralPath $dir -File) { $protected[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
}
foreach ($item in $plan) {
    $checkedPath = Assert-WorkspacePath $item.path
    if (Test-Path -LiteralPath $checkedPath) { Remove-Item -LiteralPath $checkedPath -Force }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archives = @()
foreach ($dir in $legacyRoots) {
    $checkedDir = Assert-WorkspacePath $dir
    $relative = $checkedDir.Substring($experiment.Length + 1)
    $zipPath = Assert-WorkspacePath (Join-Path $archiveRoot ($relative.Replace('\','_') + '.zip'))
    $sources = @(Get-ChildItem -LiteralPath $checkedDir -File -Recurse -Force | ForEach-Object {
        [PSCustomObject]@{path=$_.FullName.Substring($checkedDir.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    if (-not (Test-Path -LiteralPath $zipPath)) {
        [IO.Compression.ZipFile]::CreateFromDirectory($checkedDir,$zipPath,[IO.Compression.CompressionLevel]::Fastest,$false)
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($source in $sources) {
            $entry = $zip.GetEntry($source.path)
            if ($null -eq $entry) { $entry = $zip.GetEntry($source.path.Replace('/','\')) }
            if ($null -eq $entry -or $entry.Length -ne $source.bytes) { throw "Archive entry missing: $($source.path)" }
            $stream = $entry.Open(); $hasher = [Security.Cryptography.SHA256]::Create()
            try { $actual = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','') }
            finally { $stream.Dispose(); $hasher.Dispose() }
            if ($actual -ne $source.sha256) { throw "Archive hash mismatch: $($source.path)" }
        }
    } finally { $zip.Dispose() }
    $archives += [PSCustomObject]@{original=$checkedDir;archive=$zipPath;zip_sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash;files=$sources}
    # Absolute target is checked again immediately before recursive deletion.
    $checkedDir = Assert-WorkspacePath $checkedDir
    Remove-Item -LiteralPath $checkedDir -Recurse -Force
    Write-Output ('Archived and verified: ' + $relative)
}
$emptyCache = Assert-WorkspacePath (Join-Path $workspaceRoot '.Xil')
if ((Test-Path -LiteralPath $emptyCache) -and -not (Get-ChildItem -LiteralPath $emptyCache -Force)) {
    Remove-Item -LiteralPath $emptyCache -Force
}
foreach ($path in $protected.Keys) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $protected[$path]) { throw "Protected RTL changed: $path" }
}
[PSCustomObject]@{removed_files=$plan;archives=$archives;protected_rtl_unchanged=$true;completed=(Get-Date -Format o)} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $archiveRoot 'cleanup_result.json') -Encoding UTF8
Write-Output 'Cleanup complete; original and final RTL hashes unchanged.'
