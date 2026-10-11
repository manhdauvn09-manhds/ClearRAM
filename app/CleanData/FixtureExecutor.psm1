#requires -version 5.1
# Development fixture executor only. Not imported by the shipping GUI.
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MemoryClear.Disk.psm1')
$script:FixtureProject=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function New-MCDiskFixturePlan {
    param([string]$Root,[ValidateSet('Safe','Danger')][string]$Risk='Safe',[ValidateSet('Permanent','Backup')][string]$Mode='Permanent')
    $artifacts=Join-Path $script:FixtureProject 'artifacts'
    if(-not[MemoryClear.Storage.FileInventory]::Within($Root,$artifacts)-or-not[IO.Path]::GetFileName($Root).StartsWith('disk-fixture-')-or-not(Test-Path -LiteralPath (Join-Path $Root '.memoryclear-fixture'))){throw 'Marked disposable root required.'}
    $scan=Get-MCDiskScan -FixtureRoots @($Root)
    $items=@($scan.Rows|Where-Object{$_.Name-ne'.memoryclear-fixture'-and$_.Name-notlike'journal-*.jsonl'}|ForEach-Object{$_.Snapshot})
    $plan=[pscustomobject]@{RunId=[guid]::NewGuid().ToString('N');Created=[DateTime]::UtcNow;Expires=[DateTime]::UtcNow.AddMinutes(10);Root=$Root;Risk=$Risk;Mode=$Mode;Items=$items;FixtureOnly=$true;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Digest=''}
    $plan.Digest=Get-MCDiskFixtureDigest $plan
    return $plan
}
function Get-MCDiskFixtureDigest {
    param($Plan)
    $serialized=($Plan|Select-Object RunId,Created,Expires,Root,Risk,Mode,Items,FixtureOnly,UserSid|ConvertTo-Json -Depth 8 -Compress)
    $sha=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($serialized))).Replace('-','')}finally{$sha.Dispose()}
}
function Invoke-MCDiskFixturePlan {
    param($Plan,[switch]$Reviewed,[string]$Confirmation='', [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    if(-not$Plan.FixtureOnly-or$Plan.UserSid-ne[Security.Principal.WindowsIdentity]::GetCurrent().User.Value-or[DateTime]::UtcNow-ge$Plan.Expires-or$Plan.Digest-ne(Get-MCDiskFixtureDigest $Plan)){throw 'Invalid/stale/tampered fixture manifest.'}
    if($Plan.Risk-eq'Danger'-and(-not$Reviewed-or$Confirmation-ne('DELETE FIXTURE '+$Plan.RunId))){throw 'Danger requires item review and exact run confirmation.'}
    Assert-MCDiskFixtureScope $Plan
    $artifacts=Join-Path $script:FixtureProject 'artifacts';$journal=Join-Path $Plan.Root ('journal-'+$Plan.RunId+'.jsonl');$outcomes=New-Object 'System.Collections.Generic.List[object]'
    # A local digest detects accidental edits, not adversarial authority. No privileged actions.
    $mutex=New-Object Threading.Mutex($false,('Local\MemoryClear.DiskFixture.'+$Plan.UserSid));$owned=$false;$ledger=$null
    try{
        $owned=$mutex.WaitOne(0);if(-not$owned){throw 'Another fixture operation is running.'}
        # CREATE_NEW prevents replay/overwriting an old operation's evidence.
        $ledger=[pscustomobject]@{Stream=[IO.File]::Open($journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);Sequence=0;PreviousHash=('0'*64);PlanDigest=$Plan.Digest}
        foreach($item in $Plan.Items){
            if($CancellationToken.IsCancellationRequested){break}
            $status='Skipped';$backupPath=$null;$message='';$allocated=0L;$receipt=$null;$backupAncestor=$null
            try{
                $fresh=[MemoryClear.Storage.FileInventory]::Snapshot($item.Path,$item.Root)
                if($fresh.Identity-ne$item.Identity-or$fresh.AncestorIdentity-ne$item.AncestorIdentity-or$fresh.LastWriteFileTime-ne$item.LastWriteFileTime-or$fresh.LogicalBytes-ne$item.LogicalBytes-or$fresh.Links-ne1){throw 'Identity/content/parent changed.'}
                Write-MCDiskFixtureJournal $ledger $Plan.RunId $item 'Revalidated'
                if($Plan.Mode-eq'Backup'){
                    $backupRoot=Join-Path $artifacts ('disk-backup-fixture-'+$Plan.RunId);if(-not(Test-Path -LiteralPath $backupRoot)){New-Item -ItemType Directory -Path $backupRoot|Out-Null}
                    $marker=Join-Path $backupRoot '.memoryclear-fixture'
                    if(-not(Test-Path -LiteralPath $marker)){[IO.File]::WriteAllText($marker,'Disposable backup fixture')}
                    $backupAncestor=[MemoryClear.Storage.FileInventory]::Snapshot($marker,$backupRoot).AncestorIdentity
                    $backupPath=Join-Path $backupRoot ([IO.Path]::GetFileName($item.Path)+'-'+[guid]::NewGuid().ToString('N'))
                }
                $observer=[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pendingReceipt) Write-MCDiskFixtureJournal $ledger $Plan.RunId $item $stage $backupPath $pendingReceipt}
                $receipt=[MemoryClear.Storage.FileInventory]::ExecuteFixture($item,$artifacts,$backupPath,$backupAncestor,$CancellationToken,$observer)
                $status=if($receipt.CleanupWarning){'DeletedCleanupWarning'}else{'DeletedFixture'};$allocated=if($Plan.Mode-eq'Backup'){0L}else{$item.AllocatedBytes}
                Write-MCDiskFixtureJournal $ledger $Plan.RunId $item 'DeletedFixture' $backupPath $receipt
            }catch{
                $message=$_.Exception.Message
                # Never label an already committed delete "Skipped" if the final journal write failed.
                if($null-ne$receipt-and$receipt.Deleted){$status='DeletedJournalIncomplete'}
                else{Write-MCDiskFixtureJournal $ledger $Plan.RunId $item 'Skipped' $backupPath}
            }
            $outcomes.Add([pscustomobject]@{Identity=$item.Identity;Status=$status;Message=$message;Backup=$backupPath;Receipt=$receipt;KnownAllocatedBytes=$allocated})
        }
    }finally{if($null-ne$ledger){$ledger.Stream.Dispose()};if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
    $knownAllocated=0L;foreach($outcome in $outcomes){$knownAllocated+=$outcome.KnownAllocatedBytes}
    [pscustomobject]@{RunId=$Plan.RunId;FixtureOnly=$true;Journal=$journal;Outcomes=$outcomes.ToArray();Status=if($CancellationToken.IsCancellationRequested){'Cancelled'}elseif($Plan.Items.Count-eq0){'NoEligibleFixtureItems'}elseif(@($outcomes|Where-Object{$_.Status-ne'DeletedFixture'}).Count){'Partial'}else{'CompletedFixture'};KnownAllocatedBytes=$knownAllocated;RealUserCleanupExecuted=$false}
}
function Write-MCDiskFixtureJournal {
    param($Ledger,[string]$RunId,$Item,[string]$Stage,[string]$BackupPath='',$Receipt=$null)
    $payload=[pscustomobject]@{SchemaVersion=2;Time=[DateTime]::UtcNow.ToString('o');RunId=$RunId;InputHash=$Ledger.PlanDigest;Identity=$Item.Identity;SourcePath=$Item.Path;Root=$Item.Root;Stage=$Stage;BackupPath=$BackupPath;Receipt=$Receipt;FixtureOnly=$true}|ConvertTo-Json -Depth 6 -Compress
    $hash=Get-MCDiskJournalHash ($Ledger.PreviousHash+"`n"+$payload)
    $line=[pscustomobject]@{Sequence=($Ledger.Sequence+1);PreviousHash=$Ledger.PreviousHash;Payload=$payload;Hash=$hash}|ConvertTo-Json -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($line+"`n")
    $Ledger.Stream.Write($bytes,0,$bytes.Length);$Ledger.Stream.Flush($true)
    $Ledger.Sequence++;$Ledger.PreviousHash=$hash
}
function Get-MCDiskJournalHash {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$sha.Dispose()}
}
function Assert-MCDiskFixtureScope {
    param($Plan)
    $artifacts=Join-Path $script:FixtureProject 'artifacts'
    $root=[MemoryClear.Storage.FileInventory]::Canonical($Plan.Root)
    if(-not[MemoryClear.Storage.FileInventory]::Within($root,$artifacts)-or-not[IO.Path]::GetFileName($root).StartsWith('disk-fixture-')-or-not(Test-Path -LiteralPath (Join-Path $root '.memoryclear-fixture'))){throw 'Independent fixture scope check failed.'}
    if($Plan.RunId-notmatch'^[a-f0-9]{32}$'-or$Plan.Risk-notin@('Safe','Danger')-or$Plan.Mode-notin@('Permanent','Backup')-or$Plan.Created-gt[DateTime]::UtcNow-or$Plan.Expires-gt$Plan.Created.AddMinutes(11)-or$Plan.Items.Count-gt1000){throw 'Invalid fixture scope fields.'}
    foreach($item in $Plan.Items){if($item.Root-ne$root-or-not[MemoryClear.Storage.FileInventory]::Within($item.Path,$root)-or[IO.Path]::GetFileName($item.Path)-eq'.memoryclear-fixture'-or[IO.Path]::GetFileName($item.Path)-like'journal-*'){throw 'Item outside fixture plan or protected evidence.'}}
}
function Read-MCDiskFixtureJournal {
    param([string]$Path)
    $pathFull=[MemoryClear.Storage.FileInventory]::Canonical($Path);$root=Split-Path $pathFull -Parent
    if(-not[MemoryClear.Storage.FileInventory]::Within($root,(Join-Path $script:FixtureProject 'artifacts'))-or-not[IO.Path]::GetFileName($root).StartsWith('disk-fixture-')-or-not(Test-Path -LiteralPath (Join-Path $root '.memoryclear-fixture'))-or[IO.Path]::GetFileName($pathFull)-notmatch'^journal-[a-f0-9]{32}\.jsonl$'){throw 'Fixture journal scope required.'}
    # Inspection only: never resume deletion or overwrite a restore destination.
    $snapshot=[MemoryClear.Storage.FileInventory]::Snapshot($pathFull,$root)
    if($snapshot.Links-ne1-or$snapshot.LogicalBytes-gt16MB){throw 'Invalid/oversized journal.'}
    $events=New-Object 'System.Collections.Generic.List[object]';$sequence=0;$previous='0'*64;$integrity='VerifiedPrefix';$message=''
    $reader=New-Object IO.StringReader([MemoryClear.Storage.FileInventory]::ReadSnapshotText($snapshot))
    try{while($null-ne($line=$reader.ReadLine())){
        try{
            $entry=$line|ConvertFrom-Json
            if($entry.Sequence-ne($sequence+1)-or$entry.PreviousHash-ne$previous-or$entry.Hash-ne(Get-MCDiskJournalHash ($previous+"`n"+$entry.Payload))){throw 'Journal sequence/hash mismatch.'}
            $event=$entry.Payload|ConvertFrom-Json
            if($event.SchemaVersion-ne2-or$event.InputHash-notmatch'^[A-F0-9]{64}$'-or$event.Stage-notin@('Revalidated','SourceLocked','BackupFlushed','BackupVerified','DeleteStarted','DeletedFixture','Skipped')-or-not$event.FixtureOnly-or$event.Root-ne$root-or-not[MemoryClear.Storage.FileInventory]::Within($event.SourcePath,$root)-or$event.RunId-ne([IO.Path]::GetFileNameWithoutExtension($pathFull).Substring(8))){throw 'Journal event contract/scope mismatch.'}
            $events.Add($event);$sequence++;$previous=$entry.Hash
        }catch{$integrity='InvalidOrTruncated';$message=$_.Exception.Message;break}
    }}finally{$reader.Dispose()}
    $items=New-Object 'System.Collections.Generic.List[object]'
    foreach($group in ($events|Group-Object Identity)){
        $last=$group.Group[-1];$source='Unknown';$backup='NotVerified'
        $receipts=@($group.Group|Where-Object{$null-ne$_.Receipt-and$_.Receipt.Sha256})
        $backupReceipt=if($receipts.Count){$receipts[-1].Receipt}else{$null}
        try{$now=[MemoryClear.Storage.FileInventory]::Snapshot($last.SourcePath,$root);$source=if($now.Identity-eq$last.Identity){'PresentSameIdentity'}else{'PresentDifferentIdentity'}}catch{if(-not(Test-Path -LiteralPath $last.SourcePath)){$source='MissingAtInspection'}}
        if($null-ne$backupReceipt-and$backupReceipt.BackupPath){
            try{
                $backupRoot=Split-Path $backupReceipt.BackupPath -Parent
                if(-not[MemoryClear.Storage.FileInventory]::Within($backupRoot,(Join-Path $script:FixtureProject 'artifacts'))-or-not[IO.Path]::GetFileName($backupRoot).StartsWith('disk-backup-fixture-')-or-not(Test-Path -LiteralPath (Join-Path $backupRoot '.memoryclear-fixture'))){throw 'Backup outside fixture scope.'}
                $now=[MemoryClear.Storage.FileInventory]::Snapshot($backupReceipt.BackupPath,$backupRoot)
                if($now.Links-eq1-and$now.Identity-eq$backupReceipt.BackupIdentity-and$now.AncestorIdentity-eq$backupReceipt.BackupAncestorIdentity-and[MemoryClear.Storage.FileInventory]::HashSnapshot($now,[Threading.CancellationToken]::None)-eq$backupReceipt.Sha256){$backup='VerifiedAtInspection'}
            }catch{$backup='NotVerified'}
        }
        $items.Add([pscustomobject]@{Identity=$last.Identity;LastStage=$last.Stage;SourceState=$source;BackupState=$backup;NeedsReview=($last.Stage-ne'DeletedFixture'-or$integrity-ne'VerifiedPrefix')})
    }
    if($sequence-eq0-and$integrity-eq'VerifiedPrefix'){$integrity='EmptyUnproven'}
    [pscustomobject]@{Integrity=$integrity;Message=$message;VerifiedEvents=$sequence;Items=$items.ToArray();Events=$events.ToArray();FixtureOnly=$true;AutomaticReplay=$false;TailCompletenessUnproven=$true}
}
Export-ModuleMember -Function New-MCDiskFixturePlan,Invoke-MCDiskFixturePlan,Read-MCDiskFixtureJournal
