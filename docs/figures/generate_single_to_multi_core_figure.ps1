$ErrorActionPreference = 'Stop'

$figureDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$singlePath = Join-Path $figureDir 'single_core.svg'
$multiPath = Join-Path $figureDir 'winograd_multi_core_arch.svg'
$outputPath = Join-Path $figureDir 'single_to_multi_core_architecture.svg'

function Get-SvgBody([string]$path) {
    $svg = Get-Content -Raw -LiteralPath $path
    if ($svg -notmatch '^<svg[^>]*>(.*)</svg>\s*$') {
        throw "Invalid SVG: $path"
    }
    return $Matches[1]
}

$singleBody = Get-SvgBody $singlePath
$multiBody = Get-SvgBody $multiPath

$combined = @"
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1053" viewBox="0 0 3600 3160" overflow="hidden">
  <title>Single-core and multi-core Winograd accelerator architectures</title>
  <desc>The verified single-core accelerator is shown above and its tile-parallel multi-core extension is shown below.</desc>
  <g transform="translate(310 40) scale(0.85)">
    $singleBody
  </g>
  <text x="1800" y="1160" text-anchor="middle" fill="#27313A" font-family="Arial, sans-serif" font-size="58">(a) Single-core Winograd accelerator</text>
  <g transform="translate(165 1260)">
    $multiBody
  </g>
  <text x="1800" y="3090" text-anchor="middle" fill="#27313A" font-family="Arial, sans-serif" font-size="58">(b) Tile-parallel multi-core architecture</text>
</svg>
"@

Set-Content -LiteralPath $outputPath -Value $combined -Encoding UTF8
Write-Output $outputPath
