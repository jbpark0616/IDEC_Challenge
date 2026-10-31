param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
$word=New-Object -ComObject Word.Application
$word.Visible=$false
$word.DisplayAlerts=0
$doc=$null
try {
  $doc=$word.Documents.Open($Source,$false,$true)
  $doc.Repaginate()
  $doc.ExportAsFixedFormat($Output,17)
  Write-Output $Output
} finally {
  if ($null -ne $doc) { $doc.Close(0); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($doc) }
  $word.Quit()
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
