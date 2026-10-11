#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$hostPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Write-Host 'Phase10 verification: only disposable fixtures under workspace artifacts; no real user cleanup.'
foreach($test in @('Check-DiskInventory.ps1','Check-DiskOwnership.ps1','Check-DiskAppProfiles.ps1','Check-DiskOwnerHistory.ps1','Check-DiskGuard.ps1','Check-DiskFixtureExecutor.ps1','Check-DiskUI.ps1','Check-DiskReview.ps1','Check-DiskReviewUI.ps1','Check-DiskOperations.ps1','Check-DiskCrash.ps1','Check-DiskOperationUI.ps1','Check-WindowsProviders.ps1','Check-TempCleanup.ps1')){
    Write-Host "Running $test"
    & $hostPowerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $projectRoot ('tests\'+$test))
    if($LASTEXITCODE-ne0){throw "Failed $test (exit $LASTEXITCODE). See docs/verification reports."}
}
Write-Host 'Phase10 local fixture checks passed. This does not prove Win10/Win11 VM or production cleanup release.'
Write-Host 'Reports: docs/verification/disk-*.json. Fixtures retained for review; do not recursively delete without verifying their absolute paths.'
