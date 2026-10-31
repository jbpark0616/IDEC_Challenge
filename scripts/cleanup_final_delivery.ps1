$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location $root
$audit = Join-Path $root 'docs/report_data/final_delivery'
New-Item -ItemType Directory -Force $audit | Out-Null
$protected = @(Get-ChildItem verilog,free_topic_vgg/rtl,submission/IDEC2026 -Recurse -File) + @(Get-ChildItem docs -Filter '*제출용.pdf' -File)
$hashes = @($protected | ForEach-Object { [pscustomobject]@{path=$_.FullName.Substring($root.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
$hashes | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $audit 'protected_sha256.json')
Copy-Item .submission_review/final_gate_1000.log,.submission_review/final_rtl_1000.log,.submission_review/final_check.tcl $audit
$synth = 'free_topic_vgg/evidence/timing_writer_pipeline/netlist'
New-Item -ItemType Directory -Force $synth | Out-Null
Get-ChildItem free_topic_vgg/build/full_cluster_writer_pipeline/results -Recurse -File | Where-Object {$_.Name -in @('1_2_yosys.v','1_2_yosys.sdc','1_synth.sdc')} | Copy-Item -Destination $synth
Add-Type -AssemblyName System.IO.Compression.FileSystem
$old = Join-Path $root 'archive/designated_before_final_20261029.zip'
$new = Join-Path $root 'verification/designated_ablation_reference.zip'
$originalHash=(Get-FileHash -LiteralPath $old).Hash
$src=[IO.Compression.ZipFile]::OpenRead($old)
$dst=[IO.Compression.ZipFile]::Open($new,[IO.Compression.ZipArchiveMode]::Create)
$prefix='experiments/row_sparse_fixed/iterations/matched_ablation/'
$saved=@()
try {
 foreach($e in $src.Entries) {
  if($e.FullName.StartsWith($prefix) -and ($e.FullName -match '/cases/[^/]+/rtl/[^/]+\.v$' -or $e.FullName -match '/power/synth/[^/]+/(activity_power.rpt|simulation.log|activity_annotation.rpt)$')) {
   $n=$dst.CreateEntry($e.FullName,[IO.Compression.CompressionLevel]::Optimal)
   $i=$e.Open(); $o=$n.Open(); try{$i.CopyTo($o)}finally{$i.Dispose();$o.Dispose()}
   $saved+=$e.FullName
  }
 }
}finally{$src.Dispose();$dst.Dispose()}
if($saved.Count -ne 68){throw "Unexpected reference count: $($saved.Count)"}
@{original_archive_sha256=$originalHash;preserved_entries=$saved;reference_zip_sha256=(Get-FileHash $new).Hash} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $audit 'ablation_reference.json')
$targets=@('build','tmp','.report_review','.submission_review','archive','experiments','free_topic_vgg/build','hs_err_pid31384.dmp','xelab.pb','docs/IDEC_지정주제_결과보고서_검토수정본.docx')
$deleted=@()
foreach($relative in $targets){
 $p=[IO.Path]::GetFullPath((Join-Path $root $relative))
 if(-not $p.StartsWith($root+[IO.Path]::DirectorySeparatorChar)){throw "Outside workspace: $p"}
 if(Test-Path -LiteralPath $p){
  $bytes=(Get-ChildItem -LiteralPath $p -Recurse -File -Force | Measure-Object Length -Sum).Sum
  if((Get-Item -LiteralPath $p).PSIsContainer -eq $false){$bytes=(Get-Item -LiteralPath $p).Length}
  Remove-Item -LiteralPath $p -Recurse -Force
  $deleted += [pscustomobject]@{path=$relative;bytes=$bytes}
 }
}
$deleted | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $audit 'removed_generated_files.json')
foreach($h in $hashes){if((Get-FileHash -LiteralPath (Join-Path $root $h.path)).Hash -ne $h.sha256){throw "Changed protected file: $($h.path)"}}
Write-Output ('PASS protected hashes; removed bytes: '+($deleted|Measure-Object bytes -Sum).Sum)
