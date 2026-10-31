$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'free_topic_vgg'))
$auditRoot = Join-Path $workspaceRoot 'archive/free_topic_cleanup_20261028'
$plan = Get-Content -LiteralPath (Join-Path $auditRoot 'plan.json') -Raw | ConvertFrom-Json
if (-not $plan.archive_verified) { throw 'Archive has not been verified' }
$archivePath = Join-Path $workspaceRoot $plan.archive
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower() -ne $plan.archive_sha256) {
    throw 'Archive hash mismatch'
}
$resolvedTargets = @()
foreach ($relative in $plan.targets) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $relative))
    if (-not $candidate.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target outside intended project: $candidate"
    }
    $resolved = (Resolve-Path -LiteralPath $candidate).ProviderPath
    if (-not $resolved.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved target outside intended project: $resolved"
    }
    $item = Get-Item -LiteralPath $resolved -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point: $resolved" }
    if ($item.PSIsContainer) { $ancestor = $item.Parent } else { $ancestor = $item.Directory }
    while ($null -ne $ancestor -and $ancestor.FullName.StartsWith($projectRoot,[StringComparison]::OrdinalIgnoreCase)) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse ancestor: $ancestor" }
        $ancestor = $ancestor.Parent
    }
    if ($item.PSIsContainer) {
        $links = @(Get-ChildItem -LiteralPath $resolved -Directory -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        if ($links.Count) { throw "Reparse points under $resolved" }
    }
    $resolvedTargets += $resolved
}
# Confirm no source/report changed after the archive was made.
foreach ($entry in $plan.archived_files) {
    $file = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $entry.path))
    $isRemoved = $false
    foreach ($target in $resolvedTargets) {
        if ($file -eq $target -or $file.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) {
            $isRemoved = $true
            break
        }
    }
    if ($isRemoved -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower() -ne $entry.sha256) {
        throw "File changed since archival: $file"
    }
}
# All absolute paths and the verified archive are checked before any deletion.
foreach ($target in $resolvedTargets) {
    Remove-Item -LiteralPath $target -Recurse -Force
}
foreach ($entry in $plan.protected_files) {
    $file = Join-Path $workspaceRoot $entry.path
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower() -ne $entry.sha256) {
        throw "Protected file mismatch: $file"
    }
}
$result = [ordered]@{
    status = 'complete'
    deleted_targets = $resolvedTargets.Count
    deleted_files = @($plan.deleted_files).Count
    deleted_bytes = $plan.bytes_to_remove
    archive_bytes = $plan.archive_bytes
    net_reclaimed_bytes = $plan.bytes_to_remove - $plan.archive_bytes
    protected_files_verified = @($plan.protected_files).Count
    retired_experiments = $plan.retired_experiments
    retired_scripts = @($plan.retired_scripts).Count
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $auditRoot 'result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 5
