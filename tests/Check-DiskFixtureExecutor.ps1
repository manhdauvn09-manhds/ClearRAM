#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
Import-Module (Join-Path $projectRoot 'app\CleanData\FixtureExecutor.psm1') -Force
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Fixture { $root=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null;[IO.File]::WriteAllText((Join-Path $root '.memoryclear-fixture'),'Disposable executor test');[IO.File]::WriteAllText((Join-Path $root 'data.txt'),'Keep exact fixture data');return $root }
Check 'Safe fixture runs directly with flushed chained write-ahead journal' {$root=Fixture;$plan=New-MCDiskFixturePlan $root;$r=Invoke-MCDiskFixturePlan $plan;Assert ($r.Status-eq'CompletedFixture'-and-not(Test-Path -LiteralPath (Join-Path $root 'data.txt')));$inspection=Read-MCDiskFixtureJournal $r.Journal;Assert ($inspection.Integrity-eq'VerifiedPrefix');Assert (($inspection.Events.Stage-join',')-eq'Revalidated,SourceLocked,DeleteStarted,DeletedFixture');Assert (-not$inspection.AutomaticReplay-and$inspection.Items[0].SourceState-eq'MissingAtInspection')}
Check 'Danger cannot run before review and exact per-run confirmation' {$root=Fixture;$plan=New-MCDiskFixturePlan $root -Risk Danger;$blocked=$false;try{Invoke-MCDiskFixturePlan $plan -Reviewed|Out-Null}catch{$blocked=$true};Assert ($blocked-and(Test-Path -LiteralPath (Join-Path $root 'data.txt')));$r=Invoke-MCDiskFixturePlan $plan -Reviewed -Confirmation ('DELETE FIXTURE '+$plan.RunId);Assert ($r.Status-eq'CompletedFixture')}
Check 'Tampered manifest rejected before any write/delete' {$root=Fixture;$plan=New-MCDiskFixturePlan $root -Risk Danger;$plan.Risk='Safe';$blocked=$false;try{Invoke-MCDiskFixturePlan $plan|Out-Null}catch{$blocked=$true};Assert ($blocked-and(Test-Path -LiteralPath (Join-Path $root 'data.txt')))}
Check 'Backup same volume yields zero gain and restores exact fixture data' {$root=Fixture;$path=Join-Path $root 'data.txt';$hash=(Get-FileHash -LiteralPath $path).Hash;$plan=New-MCDiskFixturePlan $root -Mode Backup;$r=Invoke-MCDiskFixturePlan $plan;Assert ($r.Status-eq'CompletedFixture'-and$r.KnownAllocatedBytes-eq0);Assert ((Get-FileHash -LiteralPath $r.Outcomes[0].Backup).Hash-eq$hash);[IO.File]::Copy($r.Outcomes[0].Backup,$path,$false);Assert ((Get-FileHash -LiteralPath $path).Hash-eq$hash)}
Check 'Cancellation leaves source and reports cancelled' {$root=Fixture;$plan=New-MCDiskFixturePlan $root;$token=New-Object Threading.CancellationTokenSource;try{$token.Cancel();$r=Invoke-MCDiskFixturePlan $plan -CancellationToken $token.Token;Assert ($r.Status-eq'Cancelled'-and(Test-Path -LiteralPath (Join-Path $root 'data.txt')))}finally{$token.Dispose()}}
Check 'Changed source is skipped instead of forced or stale-delete' {$root=Fixture;$plan=New-MCDiskFixturePlan $root;[IO.File]::AppendAllText((Join-Path $root 'data.txt'),'Changed');$r=Invoke-MCDiskFixturePlan $plan;Assert ($r.Status-eq'Partial'-and(Test-Path -LiteralPath (Join-Path $root 'data.txt')))}
function BackupFixture {
    $root=Join-Path $projectRoot ('artifacts\disk-backup-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
    $marker=Join-Path $root '.memoryclear-fixture';[IO.File]::WriteAllText($marker,'Disposable backup test')
    [pscustomobject]@{Root=$root;Path=(Join-Path $root 'copy.bin');Ancestor=[MemoryClear.Storage.FileInventory]::Snapshot($marker,$root).AncestorIdentity}
}
Check 'Held source file and ancestor refuse writes/renames on a competing thread' {
    $root=Fixture;$path=Join-Path $root 'data.txt';$item=[MemoryClear.Storage.FileInventory]::Snapshot($path,$root);$backup=BackupFixture
    $observer=[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pendingReceipt)
        if($stage-eq'SourceLocked'){
            $worker=[PowerShell]::Create()
            try{
                [void]$worker.AddScript('param($file,$dir) $w=$false;$m=$false;try{[IO.File]::WriteAllText($file,"changed")}catch{$w=$true};try{[IO.Directory]::Move($dir,$dir+"-moved")}catch{$m=$true};[pscustomobject]@{WriteBlocked=$w;MoveBlocked=$m}').AddArgument($path).AddArgument($root)
                $async=$worker.BeginInvoke();$answer=$worker.EndInvoke($async);Assert ($answer[0].WriteBlocked-and$answer[0].MoveBlocked) 'Competing mutation was not blocked'
            }finally{$worker.Dispose()}
        }
    }
    $r=[MemoryClear.Storage.FileInventory]::ExecuteFixture($item,(Join-Path $projectRoot 'artifacts'),$backup.Path,$backup.Ancestor,[Threading.CancellationToken]::None,$observer)
    Assert ($r.Deleted-and$r.Sha256-eq(Get-FileHash -LiteralPath $backup.Path).Hash)
}
Check 'Cancel after backup flush retains source and reports no delete' {
    $root=Fixture;$path=Join-Path $root 'data.txt';$hash=(Get-FileHash -LiteralPath $path).Hash;$item=[MemoryClear.Storage.FileInventory]::Snapshot($path,$root);$backup=BackupFixture;$token=New-Object Threading.CancellationTokenSource
    try{
        $observer=[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pendingReceipt) if($stage-eq'BackupFlushed'){$token.Cancel()}}
        $failed=$false;try{[MemoryClear.Storage.FileInventory]::ExecuteFixture($item,(Join-Path $projectRoot 'artifacts'),$backup.Path,$backup.Ancestor,$token.Token,$observer)|Out-Null}catch{$failed=$true}
        Assert ($failed-and(Test-Path -LiteralPath $path)-and(Get-FileHash -LiteralPath $path).Hash-eq$hash)
    }finally{$token.Dispose()}
}
Check 'Backup cannot overwrite an existing destination and keeps source' {
    $root=Fixture;$path=Join-Path $root 'data.txt';$item=[MemoryClear.Storage.FileInventory]::Snapshot($path,$root);$backup=BackupFixture;[IO.File]::WriteAllText($backup.Path,'Existing valuable fixture backup')
    $hash=(Get-FileHash -LiteralPath $backup.Path).Hash;$failed=$false
    try{[MemoryClear.Storage.FileInventory]::ExecuteFixture($item,(Join-Path $projectRoot 'artifacts'),$backup.Path,$backup.Ancestor,[Threading.CancellationToken]::None,[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pendingReceipt)})|Out-Null}catch{$failed=$true}
    Assert ($failed-and(Test-Path -LiteralPath $path)-and(Get-FileHash -LiteralPath $backup.Path).Hash-eq$hash)
}
Check 'Backup parent replacement between preview and copy aborts' {
    $root=Fixture;$path=Join-Path $root 'data.txt';$item=[MemoryClear.Storage.FileInventory]::Snapshot($path,$root);$backup=BackupFixture
    $moved=$backup.Root+'-moved';$artifacts=[IO.Path]::GetFullPath((Join-Path $projectRoot 'artifacts'))
    Assert ([MemoryClear.Storage.FileInventory]::Within($backup.Root,$artifacts)-and[MemoryClear.Storage.FileInventory]::Within($moved,$artifacts))
    [IO.Directory]::Move($backup.Root,$moved);New-Item -ItemType Directory -Path $backup.Root|Out-Null;[IO.File]::WriteAllText((Join-Path $backup.Root '.memoryclear-fixture'),'Replacement fixture')
    $failed=$false;try{[MemoryClear.Storage.FileInventory]::ExecuteFixture($item,$artifacts,$backup.Path,$backup.Ancestor,[Threading.CancellationToken]::None,[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pendingReceipt)})|Out-Null}catch{$failed=$true}
    Assert ($failed-and(Test-Path -LiteralPath $path)-and-not(Test-Path -LiteralPath $backup.Path))
}
Check 'Journal failure before delete intent keeps original source' {
    $root=Fixture;$path=Join-Path $root 'data.txt';$item=[MemoryClear.Storage.FileInventory]::Snapshot($path,$root);$failed=$false
    try{[MemoryClear.Storage.FileInventory]::ExecuteFixture($item,(Join-Path $projectRoot 'artifacts'),$null,$null,[Threading.CancellationToken]::None,[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pendingReceipt)if($stage-eq'DeleteStarted'){throw 'Injected journal flush failure'}})|Out-Null}catch{$failed=$true}
    Assert ($failed-and(Test-Path -LiteralPath $path))
}
Check 'Interrupted journal is inspected without automatic replay' {
    $root=Fixture;$path=Join-Path $root 'data.txt';$plan=New-MCDiskFixturePlan $root -Mode Backup;$r=Invoke-MCDiskFixturePlan $plan
    $lines=[IO.File]::ReadAllLines($r.Journal);[IO.File]::WriteAllLines($r.Journal,$lines[0..($lines.Length-2)])
    $inspection=Read-MCDiskFixtureJournal $r.Journal
    Assert ($inspection.Integrity-eq'VerifiedPrefix'-and$inspection.TailCompletenessUnproven-and-not$inspection.AutomaticReplay-and$inspection.Items[0].NeedsReview-and$inspection.Items[0].LastStage-eq'DeleteStarted')
    Assert ($inspection.Items[0].SourceState-eq'MissingAtInspection')
    Assert ($inspection.Items[0].BackupState-eq'VerifiedAtInspection') 'Pre-delete backup receipt missing'
}
Check 'Malformed or modified journal refuses trusted recovery state' {
    $root=Fixture;$plan=New-MCDiskFixturePlan $root;$r=Invoke-MCDiskFixturePlan $plan;[IO.File]::AppendAllText($r.Journal,'{"Sequence":')
    $inspection=Read-MCDiskFixtureJournal $r.Journal;Assert ($inspection.Integrity-eq'InvalidOrTruncated'-and-not$inspection.AutomaticReplay)
    $lines=[IO.File]::ReadAllLines($r.Journal);$lines[0]=$lines[0].Replace('Revalidated','Changed');[IO.File]::WriteAllLines($r.Journal,$lines)
    $inspection=Read-MCDiskFixtureJournal $r.Journal;Assert ($inspection.Integrity-eq'InvalidOrTruncated'-and$inspection.VerifiedEvents-eq0)
}
Check 'Backup receipt identity and hash are checked during recovery inspection' {
    $root=Fixture;$plan=New-MCDiskFixturePlan $root -Mode Backup;$r=Invoke-MCDiskFixturePlan $plan
    $inspection=Read-MCDiskFixtureJournal $r.Journal;Assert ($inspection.Items[0].BackupState-eq'VerifiedAtInspection')
    [IO.File]::AppendAllText($r.Outcomes[0].Backup,'tampered');$inspection=Read-MCDiskFixtureJournal $r.Journal;Assert ($inspection.Items[0].BackupState-eq'NotVerified')
}
Check 'Recomputed local digest cannot authorize a protected marker item' {
    $root=Fixture;$plan=New-MCDiskFixturePlan $root
    $plan.Items=@([MemoryClear.Storage.FileInventory]::Snapshot((Join-Path $root '.memoryclear-fixture'),$root))
    $plan.Digest=& (Get-Module FixtureExecutor) {param($p) Get-MCDiskFixtureDigest $p} $plan
    $failed=$false;try{Invoke-MCDiskFixturePlan $plan|Out-Null}catch{$failed=$true}
    Assert ($failed-and(Test-Path -LiteralPath (Join-Path $root '.memoryclear-fixture'))-and-not(Test-Path -LiteralPath (Join-Path $root ('journal-'+$plan.RunId+'.jsonl'))))
}
Check 'Existing per-run journal cannot be replayed or overwritten' {
    $root=Fixture;$plan=New-MCDiskFixturePlan $root;$r=Invoke-MCDiskFixturePlan $plan;$hash=(Get-FileHash -LiteralPath $r.Journal).Hash
    $failed=$false;try{Invoke-MCDiskFixturePlan $plan|Out-Null}catch{$failed=$true}
    Assert ($failed-and(Get-FileHash -LiteralPath $r.Journal).Hash-eq$hash)
}
Check 'Empty fixture run and empty journal do not report cleanup success' {
    $root=Fixture;$plan=New-MCDiskFixturePlan $root;$plan.Items=@()
    $plan.Digest=& (Get-Module FixtureExecutor) {param($p) Get-MCDiskFixtureDigest $p} $plan
    $r=Invoke-MCDiskFixturePlan $plan;$inspection=Read-MCDiskFixtureJournal $r.Journal
    Assert ($r.Status-eq'NoEligibleFixtureItems'-and$inspection.Integrity-eq'EmptyUnproven'-and(Test-Path -LiteralPath (Join-Path $root 'data.txt')))
}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=$results.ToArray();Scope='Marked fixtures only; exclusive same-source-handle backup/hash/delete, competing thread and readonly journal recovery inspection';RealUserCleanupExecuted=$false;Unverified=@('Actual process/power loss and crash replay','External volume removal/full disk','Pre-existing writable memory maps and filesystem/filter-driver matrix','Production policy, backup authority and Windows10/11 VM')}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $projectRoot 'docs\verification\disk-fixture-executor-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize|Out-String|Write-Output
if($report.Failed-gt0){exit 1}
