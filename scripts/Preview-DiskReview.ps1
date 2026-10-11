#requires -version 5.1
# Interactive operator preview. All files are newly-created disposable samples; no cleanup.
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
if([Threading.Thread]::CurrentThread.ApartmentState-ne'STA'){throw 'Run with powershell -STA -File this script.'}
Write-Host 'Creating disposable samples under workspace artifacts; opening review only. No deletion.'
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1')
$root=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
[IO.File]::WriteAllText((Join-Path $root '.memoryclear-fixture'),'Operator review sample')
foreach($name in @('sample-save.db','sample-protected.bin')){[IO.File]::WriteAllText((Join-Path $root $name),'Sample file; review must not delete')}
$scan=Get-MCDiskScan -FixtureRoots @($root);$rows=@($scan.Rows|Where-Object{$_.Name-ne'.memoryclear-fixture'});$risks=@{};$hashes=@{}
foreach($row in $rows){$risks[$row.Identity]=if($row.Name-eq'sample-save.db'){'Danger'}else{'Blocked'};$row.Effect='Dữ liệu mẫu: xóa vĩnh viễn database/save có thể mất nội dung, không có Undo.';$hashes[$row.Path]=(Get-FileHash -LiteralPath $row.Path).Hash}
$view=New-MCDiskReviewWindow $scan $rows 'operator-example' -FixtureRisks $risks
try{$view.Window.ShowDialog()|Out-Null}finally{$view.Window.Close();Close-MCDiskReview $view.SessionId;$window.Close()}
foreach($path in $hashes.Keys){if(-not(Test-Path -LiteralPath $path)-or(Get-FileHash -LiteralPath $path).Hash-ne$hashes[$path]){throw 'Sample file changed unexpectedly.'}}
Write-Host 'Verified: every sample still exists with the same hash. No file deleted. Fixtures retained.'
Write-Host ('Sample directory: '+$root)
