#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $projectRoot
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run from a normal PowerShell window, without Run as administrator. This test deliberately refuses elevated cleanup.'}
Write-Host 'Verifying current-user Temp cleanup. Creates unique memoryclear-qa-* files, then tests only those exact files. Existing user files are never selected.'
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $ps -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-TempCleanup.ps1') -OwnTempSelfTest
if($LASTEXITCODE-ne0){throw 'Temp self-test failed; inspect docs/verification/temp-cleanup-tests.json.'}
$r=Get-Content (Join-Path $projectRoot 'docs\verification\temp-cleanup-tests.json') -Raw -Encoding UTF8|ConvertFrom-Json
if(-not$r.OwnTempSelfTestExecuted-or$r.Failed){throw 'Self-test evidence is missing or failed.'}
Write-Host ('Verified '+$r.Passed+' checks on this machine. Report: '+(Join-Path $projectRoot 'docs\verification\temp-cleanup-tests.json'))
Write-Host 'Remaining QA files are listed in the report and retained. This does not certify Windows10, cross-drive backup or all app-data cleanup.'
