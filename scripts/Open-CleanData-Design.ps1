[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
Write-Host 'MemoryClear Clean Data: verify design files; no cleanup, no UAC, no build.'
$designPath = Join-Path $projectRoot 'plan\clean-data-design.json'
$design = Get-Content -LiteralPath $designPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($design.artifactStatus -ne 'design_only' -or $design.executionEnabled -ne $false) { throw 'Expected a design-only prototype with execution disabled.' }
$memoryDesignPath = Join-Path $projectRoot 'plan\memory-design.json'
$memoryDesign = Get-Content -LiteralPath $memoryDesignPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($memoryDesign.artifactStatus -ne 'design_only' -or $memoryDesign.executionEnabled -ne $false) { throw 'Expected a design-only Memory prototype with execution disabled.' }
$pages = @('MemoryClear-Memory-Plan.html', 'MemoryClear-CleanData-Plan.html', 'MemoryClear-CleanData-Prototype.html')
foreach ($page in $pages) {
    $pagePath = Join-Path $projectRoot $page
    if (-not (Test-Path -LiteralPath $pagePath -PathType Leaf)) { throw "Missing design page: $page" }
    $html = [System.IO.File]::ReadAllText($pagePath)
    if ($html -match '__[A-Z_]+__') { throw "Unbuilt template: $page" }
    Write-Host "Verified and opening: $pagePath"
    Start-Process -FilePath $pagePath
}
Write-Host 'Memory plan, Disk plan and shared prototype handed to your default browser. All GB/progress are sample data.'
