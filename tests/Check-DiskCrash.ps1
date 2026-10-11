#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent;Set-Location -LiteralPath $projectRoot
Import-Module (Join-Path $projectRoot 'app\CleanData\Operations.psm1')
$results=New-Object 'System.Collections.Generic.List[object]'
foreach($stage in @('BackupVerified','DeleteStarted','Committed')){
    $child=$null
    try{
        $root=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));$backup=Join-Path $projectRoot ('artifacts\disk-backup-fixture-'+[guid]::NewGuid().ToString('N'))
        foreach($r in @($root,$backup)){New-Item -ItemType Directory -Path $r|Out-Null;[IO.File]::WriteAllText((Join-Path $r '.memoryclear-fixture'),'Disposable process-crash fixture')}
        $source=Join-Path $root 'save.db';[IO.File]::WriteAllText($source,'Crash survival fixture data '+$stage);$hash=(Get-FileHash $source).Hash
        $worker=Join-Path $PSScriptRoot 'fixtures\Disk-CrashWorker.ps1';$arguments='-NoProfile -File "'+$worker+'" -SourceRoot "'+$root+'" -BackupRoot "'+$backup+'" -Checkpoint '+$stage
        $child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'worker.stdout') -RedirectStandardError (Join-Path $root 'worker.stderr')
        [void]$child.Handle
        if(-not$child.WaitForExit(30000)){throw 'Fixture child timeout.'};$child.Refresh();if($child.ExitCode-ne77){throw ('Child did not exit at checkpoint: '+$child.ExitCode+' '+[IO.File]::ReadAllText((Join-Path $root 'worker.stderr')))}
        $journals=@(Get-ChildItem -LiteralPath $root -Filter 'journal-*.jsonl');if($journals.Count-ne1){throw 'Expected one durable journal.'}
        $i=Read-MCDiskOperationJournal $journals[0].FullName
        if($i.Status-ne'InterruptedUnproven'-or$i.FinishedRecordPresent-or$i.AutomaticReplay-or$i.Integrity-ne'VerifiedPrefix'-or$i.Items[0].BackupState-ne'VerifiedAtInspection'){throw 'Interrupted journal/backup not reported accurately.'}
        if($stage-eq'Committed'){
            if(Test-Path $source){throw 'Committed source still present.'};$restored=Restore-MCDiskOperationItem $journals[0].FullName $i.Items[0].Identity -Reviewed;if($restored.Status-ne'Restored'-or(Get-FileHash $source).Hash-ne$hash){throw 'Recovery restore mismatch.'}
        }else{if(-not(Test-Path $source)-or(Get-FileHash $source).Hash-ne$hash-or$i.Items[0].CanRestore){throw 'Pre-delete crash failed source survival/conflict protection.'}}
        $results.Add([pscustomobject]@{Checkpoint=$stage;Passed=$true;Error='';ChildExit=77;Journal=$journals[0].FullName.Replace($projectRoot+'\','')})
    }catch{$results.Add([pscustomobject]@{Checkpoint=$stage;Passed=$false;Error=$_.Exception.Message})}
    finally{if($child){if(-not$child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose()}}
}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=$results.ToArray();Scope='Actual child-process abrupt exits; marked fixtures only';PowerLossVerified=$false;ExternalDiskLossVerified=$false;ProductionExecutionEnabled=$false}
$report|ConvertTo-Json -Depth 7|Set-Content (Join-Path $projectRoot 'docs\verification\disk-crash-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize|Out-String|Write-Output;if($report.Failed){$results|Where-Object{-not$_.Passed}|Format-List|Out-String|Write-Output;exit 1}
