#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $projectRoot
if([Threading.Thread]::CurrentThread.ApartmentState-ne'STA'){throw 'Run with powershell -NoProfile -STA -File this-script.ps1'}
Write-Host "Opening transaction/restore example from $projectRoot"
Write-Host 'Only new marked files under workspace artifacts can be mutated. Personal files remain outside this executor.'
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
Show-MCDiskTransactionExample
if($operation-or$diskModalActive){throw 'Shared operation lock was not released.'}
Write-Host 'Example window closed, shared operation lock released. Fixtures/backups/journals retained for review.'
