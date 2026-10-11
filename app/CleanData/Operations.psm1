#requires -version 5.1
# Release gate remains closed. All mutations require marked disposable workspace fixtures.
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MemoryClear.Disk.psm1')
$script:Root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:Plans=[MemoryClear.Storage.OperationSessionStore]::Sessions
function Get-MCDiskExecutionPolicy {
    $p=Get-Content (Join-Path $script:Root 'app\disk-execution-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $fields=@('$schema','governs','schemaVersion','productionExecutionEnabled','maximumItems','ttlSeconds','maximumHistoryRows','maximumJournalBytes','fixtureRules','blockedNames','systemProviderMode')
    if(@($p.PSObject.Properties.Name|Where-Object{$_-notin$fields}).Count-or$p.governs-ne'product_runtime'-or$p.schemaVersion-ne1-or$p.productionExecutionEnabled-isnot[bool]-or$p.productionExecutionEnabled-or$p.systemProviderMode-ne'WindowsDelegated'){throw 'Unsupported execution policy; production cleanup stays locked.'}
    foreach($bound in @(@('maximumItems',1,100),@('ttlSeconds',1,600),@('maximumHistoryRows',1,200),@('maximumJournalBytes',4096,16777216))){$v=$p.($bound[0]);if($v-isnot[int]-or$v-lt$bound[1]-or$v-gt$bound[2]){throw 'Invalid execution budget.'}}
    if((($p.fixtureRules.PSObject.Properties.Name|Sort-Object)-join',')-ne'.db,.log,.tmp'-or$p.fixtureRules.'.tmp'-ne'Safe'-or$p.fixtureRules.'.log'-ne'Review'-or$p.fixtureRules.'.db'-ne'Danger'-or($p.blockedNames-join',')-ne'.memoryclear-fixture'){throw 'Unsupported fixture classification.'}
    $p
}
function Get-MCOperationHash {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-MCOperationStamp {
    $parts=@();foreach($name in @('disk-execution-policy.json','clean-data-policy.json','disk-app-profiles.json','owner-analysis-policy.json')){$parts+=@(Get-Content (Join-Path $script:Root ('app\'+$name)) -Raw -Encoding UTF8)}
    Get-MCOperationHash ($parts-join"`n")
}
function Assert-MCOperationRoot {
    param([string]$Root,[switch]$Backup)
    $full=[MemoryClear.Storage.FileInventory]::Canonical($Root);$prefix=if($Backup){'disk-backup-fixture-'}else{'disk-fixture-'}
    if(-not[MemoryClear.Storage.FileInventory]::Within($full,(Join-Path $script:Root 'artifacts'))-or-not[IO.Path]::GetFileName($full).StartsWith($prefix,[StringComparison]::Ordinal)-or-not(Test-Path -LiteralPath (Join-Path $full '.memoryclear-fixture') -PathType Leaf)){throw 'Only marked disposable fixture roots are executable.'}
    $marker=[MemoryClear.Storage.FileInventory]::Snapshot((Join-Path $full '.memoryclear-fixture'),$full)
    if($marker.Links-ne1){throw 'Unsafe fixture marker.'}
    $full
}
function ConvertFrom-MCOperationItems {param([string]$Payload);$parsed=ConvertFrom-Json -InputObject $Payload;foreach($item in $parsed){$item}}
function New-MCDiskOperation {
    param($ScanResult,[object[]]$SelectedRows,[ValidateSet('Permanent','Backup')][string]$Mode='Backup',[string]$BackupRoot='', [string]$ContextToken)
    $policy=Get-MCDiskExecutionPolicy
    if(-not$ScanResult.Fixture){throw 'Production execution awaits Windows/VM acceptance; use Windows Storage for system cleanup.'}
    if(-not$ContextToken-or$SelectedRows.Count-lt1-or$SelectedRows.Count-gt$policy.maximumItems){throw 'Select 1–100 current items.'}
    foreach($key in @($script:Plans.Keys)){if([DateTime]::UtcNow-ge$script:Plans[$key].Expires){[MemoryClear.Storage.OperationSessionStore]::Remove($key)}}
    if($script:Plans.Count-ge8){throw 'Close previous operation plans.'}
    $backup='';$backupAncestor='';if($Mode-eq'Backup'){$backup=Assert-MCOperationRoot $BackupRoot -Backup;$backupAncestor=[MemoryClear.Storage.FileInventory]::Snapshot((Join-Path $backup '.memoryclear-fixture'),$backup).AncestorIdentity}
    $items=New-Object 'System.Collections.Generic.List[object]';$seen=@{}
    foreach($row in $SelectedRows){
        $matches=@($ScanResult.Rows|Where-Object{$_.Identity-eq$row.Identity-and$_.Path-eq$row.Path})
        if($matches.Count-ne1-or$seen.ContainsKey($row.Identity)){throw 'Stale or duplicate selection.'};$seen[$row.Identity]=$true
        $snapshot=[MemoryClear.Storage.FileInventory]::Snapshot($row.Path,(Assert-MCOperationRoot $row.Snapshot.Root))
        foreach($field in @('Identity','AncestorIdentity','LogicalBytes','AllocatedBytes','LastWriteFileTime','Links','Attributes')){if($snapshot.$field-ne$row.Snapshot.$field){throw 'Scan changed; rescan before planning.'}}
        $name=[IO.Path]::GetFileName($snapshot.Path);$ext=[IO.Path]::GetExtension($name).ToLowerInvariant();$rule=$policy.fixtureRules.PSObject.Properties[$ext]
        $risk=if($name-in$policy.blockedNames-or$name.StartsWith('journal-',[StringComparison]::OrdinalIgnoreCase)-or$name.StartsWith('restore-',[StringComparison]::OrdinalIgnoreCase)-or$null-eq$rule){'Blocked'}else{[string]$rule.Value}
        $effect=switch($risk){'Safe'{'File temp mẫu tái tạo được; dọn trực tiếp.'}'Review'{'Log mẫu sẽ mất; backup cho phép phục hồi.'}'Danger'{'Database mẫu có thể mất dữ liệu; xóa vĩnh viễn không có Undo.'}default{'Không có rule độc lập hoặc là bằng chứng/marker; giữ lại.'}}
        $contentHash=if($risk-ne'Blocked'){[MemoryClear.Storage.FileInventory]::HashSnapshot($snapshot,[Threading.CancellationToken]::None)}else{''}
        $items.Add([pscustomobject]@{Id=$snapshot.Identity;Name=$name;Path=$snapshot.Path;Snapshot=$snapshot;Sha256=$contentHash;Risk=$risk;Effect=$effect})
    }
    $id=[guid]::NewGuid().ToString('N');$now=[DateTime]::UtcNow
    $script:Plans[$id]=[pscustomobject]@{Id=$id;ScanRunId=$ScanResult.RunId;Created=$now;Expires=$now.AddSeconds($policy.ttlSeconds);Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Stamp=(Get-MCOperationStamp);Context=$ContextToken;Mode=$Mode;Backup=$backup;BackupAncestor=$backupAncestor;Payload=($items.ToArray()|ConvertTo-Json -Depth 10 -Compress);Stage='Review';Reviewed=@();Phrase=('XOA MAU '+$id.Substring(0,8));Consumed=$false}
    Get-MCDiskOperation $id
}
function Get-MCDiskOperation {
    param([string]$Id)
    if(-not$script:Plans.ContainsKey($Id)){throw 'Operation plan closed or unavailable.'};$s=$script:Plans[$Id];$items=@(ConvertFrom-MCOperationItems $s.Payload)
    [pscustomobject]@{Id=$s.Id;Stage=$s.Stage;Items=$items;Mode=$s.Mode;BackupRoot=$s.Backup;ExpiresUtc=$s.Expires;Phrase=$s.Phrase;EligibleCount=@($items|Where-Object{$_.Risk-ne'Blocked'}).Count;FixtureOnly=$true;ProductionExecutionEnabled=$false}
}
function Assert-MCOperationCurrent {
    param([string]$Id,[string]$ContextToken)
    if(-not$script:Plans.ContainsKey($Id)){throw 'Unknown operation ID.'};$s=$script:Plans[$Id]
    try{
        Get-MCDiskExecutionPolicy|Out-Null
        if($s.Consumed-or$s.Stage-in@('Invalidated','Cancelled')-or$ContextToken-cne$s.Context-or$s.Sid-ne[Security.Principal.WindowsIdentity]::GetCurrent().User.Value-or[DateTime]::UtcNow-ge$s.Expires-or[DateTime]::UtcNow-lt$s.Created-or$s.Stamp-ne(Get-MCOperationStamp)){throw 'Operation scope/user/policy/TTL invalidated.'}
        foreach($item in @(ConvertFrom-MCOperationItems $s.Payload)){
            Assert-MCOperationRoot $item.Snapshot.Root|Out-Null
            if($item.Risk-eq'Blocked'){continue};$fresh=[MemoryClear.Storage.FileInventory]::Snapshot($item.Path,$item.Snapshot.Root)
            foreach($field in @('Identity','AncestorIdentity','LogicalBytes','AllocatedBytes','LastWriteFileTime','Links','Attributes')){if($fresh.$field-ne$item.Snapshot.$field){throw 'File changed after planning.'}}
            if([MemoryClear.Storage.FileInventory]::HashSnapshot($fresh,[Threading.CancellationToken]::None)-ne$item.Sha256){throw 'File content changed while metadata stayed the same.'}
        }
        if($s.Mode-eq'Backup'){Assert-MCOperationRoot $s.Backup -Backup|Out-Null;$ancestor=[MemoryClear.Storage.FileInventory]::Snapshot((Join-Path $s.Backup '.memoryclear-fixture'),$s.Backup).AncestorIdentity;if($ancestor-ne$s.BackupAncestor){throw 'Backup destination changed.'}}
    }catch{$s.Stage='Invalidated';$s.Reviewed=@();throw}
    $s
}
function Move-MCDiskOperationReview {
    param([string]$Id,[string]$ContextToken,[string[]]$ReviewedIds=@())
    $s=Assert-MCOperationCurrent $Id $ContextToken;if($s.Stage-ne'Review'){throw 'Review step required.'};$items=@(ConvertFrom-MCOperationItems $s.Payload);$required=@($items|Where-Object{$_.Risk-in@('Review','Danger')}|ForEach-Object{$_.Id})
    if(-not@($items|Where-Object{$_.Risk-ne'Blocked'}).Count){throw 'All selected items are blocked.'}
    if(@($ReviewedIds|Select-Object -Unique).Count-ne$ReviewedIds.Count-or$required.Count-ne$ReviewedIds.Count-or@($required|Where-Object{$ReviewedIds-notcontains$_}).Count){throw 'Read each selected risky item; blocked items cannot be approved.'}
    $s.Reviewed=@($ReviewedIds);$s.Stage=if($required.Count){'Confirm'}else{'Approved'};Get-MCDiskOperation $Id
}
function Confirm-MCDiskOperation {
    param([string]$Id,[string]$ContextToken,[bool]$Acknowledged=$false,[string]$Phrase='')
    $s=Assert-MCOperationCurrent $Id $ContextToken;if($s.Stage-ne'Confirm'){throw 'Complete item review before final confirmation.'}
    $danger=@(@(ConvertFrom-MCOperationItems $s.Payload)|Where-Object{$_.Risk-eq'Danger'}).Count-gt0
    if(-not$Acknowledged-or($danger-and$Phrase-cne$s.Phrase)){throw 'Final acknowledgment and exact danger phrase required.'}
    $s.Stage='Approved';Get-MCDiskOperation $Id
}
function Reset-MCDiskOperation {
    param([string]$Id)
    if($script:Plans.ContainsKey($Id)){$s=$script:Plans[$Id];if(-not$s.Consumed-and$s.Stage-notin@('Invalidated','Cancelled')){$s.Stage='Review';$s.Reviewed=@()}}
}
function Close-MCDiskOperation {param([string]$Id);[MemoryClear.Storage.OperationSessionStore]::Remove($Id)}
function Write-MCOperationEvent {
    param($Ledger,$Event)
    $payload=$Event|ConvertTo-Json -Depth 12 -Compress;$hash=Get-MCOperationHash ($Ledger.Previous+"`n"+$payload)
    $line=[pscustomobject]@{Sequence=($Ledger.Sequence+1);PreviousHash=$Ledger.Previous;Payload=$payload;Hash=$hash}|ConvertTo-Json -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($line+"`n");$Ledger.Stream.Write($bytes,0,$bytes.Length);$Ledger.Stream.Flush($true);$Ledger.Previous=$hash;$Ledger.Sequence++
}
function Invoke-MCDiskOperation {
    param([string]$Id,[string]$ContextToken,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[Collections.Concurrent.ConcurrentQueue[object]]$Events=$null)
    $s=Assert-MCOperationCurrent $Id $ContextToken;if($s.Stage-ne'Approved'){throw 'Independent executor requires an approved in-memory plan, not GUI flags.'}
    $items=@(ConvertFrom-MCOperationItems $s.Payload|Where-Object{$_.Risk-ne'Blocked'});$root=Assert-MCOperationRoot $items[0].Snapshot.Root
    foreach($item in $items){if($item.Snapshot.Root-ne$root){throw 'Single source root required per transaction.'}}
    $mutex=New-Object Threading.Mutex($false,('Local\MemoryClear.DiskOperation.'+$s.Sid));$owned=$false;$ledger=$null;$outcomes=New-Object 'System.Collections.Generic.List[object]';$watch=[Diagnostics.Stopwatch]::StartNew();$journal=Join-Path $root ('journal-'+$s.Id+'.jsonl');$done=0
    try{
        $owned=$mutex.WaitOne(0);if(-not$owned){throw 'Another Disk transaction is active.'}
        if($s.Consumed-or$s.Stage-ne'Approved'){throw 'Operation was already consumed or invalidated before acquiring the transaction lock.'}
        $stream=[IO.File]::Open($journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $ledger=[pscustomobject]@{Stream=$stream;Sequence=0;Previous=('0'*64)}
        $s.Consumed=$true;$s.Stage='Running'
        $header=[pscustomobject]@{SchemaVersion=3;Kind='Plan';RunId=$s.Id;Sid=$s.Sid;Mode=$s.Mode;Root=$root;BackupRoot=$s.Backup;PolicyStamp=$s.Stamp;Items=$items;Utc=[DateTime]::UtcNow.ToString('o');FixtureOnly=$true};Write-MCOperationEvent $ledger $header
        foreach($item in $items){
            if($CancellationToken.IsCancellationRequested){break};$receipt=$null;$errorText='';$status='Skipped';$backupPath=if($s.Mode-eq'Backup'){Join-Path $s.Backup ($s.Id+'-'+[guid]::NewGuid().ToString('N')+'.backup')}else{''}
            try{
                $native=[MemoryClear.Storage.FileRecord]$item.Snapshot
                $observer=[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pending)
                    Write-MCOperationEvent $ledger ([pscustomobject]@{SchemaVersion=3;Kind='Item';RunId=$s.Id;Identity=$item.Id;Path=$item.Path;Root=$root;Stage=$stage;Receipt=$pending;Utc=[DateTime]::UtcNow.ToString('o');FixtureOnly=$true})
                }
                $receipt=[MemoryClear.Storage.FileInventory]::ExecuteFixtureWithHash($native,(Join-Path $script:Root 'artifacts'),$backupPath,$s.BackupAncestor,$CancellationToken,$observer,$item.Sha256)
                $status=if($receipt.CleanupWarning){'DeletedCleanupWarning'}else{'Deleted'}
                Write-MCOperationEvent $ledger ([pscustomobject]@{SchemaVersion=3;Kind='Item';RunId=$s.Id;Identity=$item.Id;Path=$item.Path;Root=$root;Stage='Committed';Receipt=$receipt;Utc=[DateTime]::UtcNow.ToString('o');FixtureOnly=$true})
            }catch{$errorText=$_.Exception.Message;$status=if($receipt-and$receipt.Deleted){'DeletedJournalIncomplete'}elseif($CancellationToken.IsCancellationRequested){'Cancelled'}else{'Skipped'}}
            $done++;$outcome=[pscustomobject]@{Identity=$item.Id;Path=$item.Path;Risk=$item.Risk;Status=$status;Error=$errorText;Receipt=$receipt};$outcomes.Add($outcome)
            if($Events){$Events.Enqueue([pscustomobject]@{Kind='Progress';Completed=$done;Total=$items.Count;Path=$item.Path;Status=$status;Seconds=$watch.Elapsed.TotalSeconds})}
        }
        $status=if($CancellationToken.IsCancellationRequested){'Cancelled'}elseif(@($outcomes|Where-Object{$_.Status-ne'Deleted'}).Count){'Partial'}else{'Completed'}
        Write-MCOperationEvent $ledger ([pscustomobject]@{SchemaVersion=3;Kind='Finished';RunId=$s.Id;Status=$status;Processed=$done;Utc=[DateTime]::UtcNow.ToString('o');FixtureOnly=$true})
        $s.Stage=$status
        $logical=0L;$allocated=0L;foreach($item in $items){if(@($outcomes|Where-Object{$_.Identity-eq$item.Id-and$_.Status-like'Deleted*'}).Count){$logical+=$item.Snapshot.LogicalBytes;if($s.Mode-eq'Permanent'){$allocated+=$item.Snapshot.AllocatedBytes}}}
        [pscustomobject]@{RunId=$s.Id;Status=$status;Processed=$done;Total=$items.Count;Outcomes=$outcomes.ToArray();Journal=$journal;Seconds=$watch.Elapsed.TotalSeconds;DeletedLogicalBytes=$logical;KnownAllocatedBytes=$allocated;FixtureOnly=$true;RealUserCleanupExecuted=$false;FinishedUtc=[DateTime]::UtcNow}
    }finally{if($ledger){$ledger.Stream.Dispose()};if($owned){$mutex.ReleaseMutex()};$mutex.Dispose();$watch.Stop();if($s.Stage-eq'Running'){$s.Stage='InterruptedUnproven'}}
}
function Read-MCDiskOperationJournal {
    param([string]$Path,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $CancellationToken.ThrowIfCancellationRequested()
    $policy=Get-MCDiskExecutionPolicy;$full=[MemoryClear.Storage.FileInventory]::Canonical($Path);$root=Assert-MCOperationRoot (Split-Path $full -Parent)
    if([IO.Path]::GetFileName($full)-notmatch'^journal-([a-f0-9]{32})\.jsonl$'){throw 'Operation journal filename required.'};$runId=$Matches[1]
    $snapshot=[MemoryClear.Storage.FileInventory]::Snapshot($full,$root);if($snapshot.Links-ne1-or$snapshot.LogicalBytes-gt$policy.maximumJournalBytes){throw 'Unsafe/oversized journal.'}
    $reader=New-Object IO.StringReader([MemoryClear.Storage.FileInventory]::ReadSnapshotText($snapshot));$events=New-Object 'System.Collections.Generic.List[object]';$sequence=0;$previous='0'*64;$integrity='VerifiedPrefix';$message='';$header=$null;$finished=$null
    try{while($null-ne($line=$reader.ReadLine())){$CancellationToken.ThrowIfCancellationRequested();try{
        $e=$line|ConvertFrom-Json;if($e.Sequence-ne($sequence+1)-or$e.PreviousHash-ne$previous-or$e.Hash-ne(Get-MCOperationHash ($previous+"`n"+$e.Payload))){throw 'Journal chain invalid.'};$v=$e.Payload|ConvertFrom-Json
        if($v.SchemaVersion-ne3-or$v.RunId-ne$runId-or-not$v.FixtureOnly-or$finished){throw 'Journal contract invalid.'}
        if($sequence-eq0){if($v.Kind-ne'Plan'-or$v.Root-ne$root-or$v.Sid-ne[Security.Principal.WindowsIdentity]::GetCurrent().User.Value-or$v.Mode-notin@('Permanent','Backup')-or@($v.Items).Count-lt1-or@($v.Items).Count-gt$policy.maximumItems){throw 'Journal header invalid.'};$header=$v
            $ids=@{};foreach($item in $v.Items){if($ids.ContainsKey($item.Id)-or$item.Id-ne$item.Snapshot.Identity-or$item.Path-ne$item.Snapshot.Path-or$item.Snapshot.Root-ne$root-or-not[MemoryClear.Storage.FileInventory]::Within($item.Path,$root)-or$item.Risk-notin@('Safe','Review','Danger')){throw 'Journal item scope invalid.'};$ids[$item.Id]=$true}
        }elseif($v.Kind-eq'Item'){
            if($v.Root-ne$root-or@($header.Items|Where-Object{$_.Id-eq$v.Identity-and$_.Path-eq$v.Path}).Count-ne1-or$v.Stage-notin@('SourceLocked','BackupFlushed','BackupVerified','DeleteStarted','Committed')){throw 'Journal item event invalid.'}
        }elseif($v.Kind-eq'Finished'){$finished=$v}else{throw 'Unknown journal event.'}
        $events.Add($v);$sequence++;$previous=$e.Hash
    }catch{$integrity='InvalidOrTruncated';$message=$_.Exception.Message;break}}}finally{$reader.Dispose()}
    if(-not$header){$integrity='EmptyUnproven'}
    $rows=New-Object 'System.Collections.Generic.List[object]'
    if($header){foreach($item in $header.Items){
        $CancellationToken.ThrowIfCancellationRequested()
        $related=@($events|Where-Object{$_.Kind-eq'Item'-and$_.Identity-eq$item.Id});$last=if($related.Count){$related[-1]}else{$null};$receipt=$null;foreach($entry in $related){if($entry.Receipt-and$entry.Receipt.BackupPath-and$entry.Receipt.Sha256){$receipt=$entry.Receipt}}
        $source='Unknown';$parentMatches=$false
        $presence=[MemoryClear.Storage.FileInventory]::ProbeFilePresence($item.Path,$root)
        $parentMatches=$presence.AncestorIdentity-eq$item.Snapshot.AncestorIdentity
        if($presence.State-eq'Absent'){$source='MissingAtInspection'}else{try{$now=[MemoryClear.Storage.FileInventory]::Snapshot($item.Path,$root);$source=if($now.Identity-eq$item.Id){'PresentSameIdentity'}else{'PresentDifferentIdentity'}}catch{}}
        $backup='NotVerified';$backupSnapshot=$null
        if($receipt){try{
            $backupRoot=Assert-MCOperationRoot (Split-Path $receipt.BackupPath -Parent) -Backup;if($backupRoot-ne$header.BackupRoot){throw 'Backup root mismatch.'}
            $backupSnapshot=[MemoryClear.Storage.FileInventory]::Snapshot($receipt.BackupPath,$backupRoot)
            if($receipt.Sha256-ne$item.Sha256-or$backupSnapshot.Identity-ne$receipt.BackupIdentity-or$backupSnapshot.AncestorIdentity-ne$receipt.BackupAncestorIdentity-or$backupSnapshot.LogicalBytes-ne$receipt.Bytes-or[MemoryClear.Storage.FileInventory]::HashSnapshot($backupSnapshot,$CancellationToken)-ne$receipt.Sha256){throw 'Backup identity/hash mismatch.'};$backup='VerifiedAtInspection'
        }catch{$backup='NotVerified';$backupSnapshot=$null}}
        $sourceLabels=@{Unknown='Chưa xác minh';PresentSameIdentity='Còn file gốc';PresentDifferentIdentity='File mới ở đích';MissingAtInspection='Đích hiện trống'}
        $rows.Add([pscustomobject]@{Identity=$item.Id;Path=$item.Path;Root=$root;OriginalAncestor=$item.Snapshot.AncestorIdentity;ParentIdentityMatches=$parentMatches;SourceState=$source;SourceLabel=$sourceLabels[$source];BackupState=$backup;BackupLabel=if($backup-eq'VerifiedAtInspection'){'Đã xác minh'}else{'Chưa xác minh'};BackupSnapshot=$backupSnapshot;Receipt=$receipt;LastStage=if($last){$last.Stage}else{'NotStarted'};CanRestore=($integrity-eq'VerifiedPrefix'-and$backup-eq'VerifiedAtInspection'-and$source-eq'MissingAtInspection'-and$parentMatches);NeedsReview=($null-eq$finished-or$integrity-ne'VerifiedPrefix')})
    }}
    $CancellationToken.ThrowIfCancellationRequested()
    [pscustomobject]@{RunId=$runId;Path=$full;Integrity=$integrity;Message=$message;Items=$rows.ToArray();FinishedRecordPresent=($null-ne$finished);Status=if($finished){$finished.Status}else{'InterruptedUnproven'};VerifiedEvents=$sequence;AutomaticReplay=$false;TailCompletenessUnproven=$true;FixtureOnly=$true}
}
function Get-MCDiskOperationHistory {
    param([Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $policy=Get-MCDiskExecutionPolicy;$rows=New-Object 'System.Collections.Generic.List[object]';$watch=[Diagnostics.Stopwatch]::StartNew();$truncated=$false;$skipped=0
    $artifactRoot=Join-Path $script:Root 'artifacts';if(-not(Test-Path -LiteralPath $artifactRoot)){return [pscustomobject]@{Rows=@();Status='NoHistory';Skipped=0;Truncated=$false}}
    $directories=@(Get-ChildItem -LiteralPath $artifactRoot -Directory -Filter 'disk-fixture-*'|Select-Object -First 2000|Sort-Object LastWriteTimeUtc -Descending)
    foreach($directory in $directories){
        $CancellationToken.ThrowIfCancellationRequested();if($watch.Elapsed.TotalSeconds-ge10-or$rows.Count-ge$policy.maximumHistoryRows){$truncated=$true;break}
        try{$root=Assert-MCOperationRoot $directory.FullName;foreach($file in (Get-ChildItem -LiteralPath $root -Filter 'journal-*.jsonl' -File)){
            if($rows.Count-ge$policy.maximumHistoryRows){$truncated=$true;break};if($file.Name-notmatch'^journal-([a-f0-9]{32})\.jsonl$'){continue};$run=$Matches[1]
            $snapshot=[MemoryClear.Storage.FileInventory]::Snapshot($file.FullName,$root);if($snapshot.LogicalBytes-gt$policy.maximumJournalBytes){$skipped++;continue}
            $rows.Add([pscustomobject]@{RunId=$run;Path=$file.FullName;ModifiedUtc=[DateTime]::FromFileTimeUtc($snapshot.LastWriteFileTime);Label=([DateTime]::FromFileTimeUtc($snapshot.LastWriteFileTime).ToLocalTime().ToString('MM-dd HH:mm')+' · '+$run.Substring(0,8)+' · chưa kiểm tra');Status='Uninspected';FixtureOnly=$true})
        }}catch{$skipped++}
    }
    [pscustomobject]@{Rows=@($rows.ToArray()|Sort-Object ModifiedUtc -Descending);Status=if($truncated-or$skipped){'Partial'}elseif($rows.Count){'ListedUninspected'}else{'NoHistory'};Skipped=$skipped;Truncated=$truncated;AutomaticReplay=$false;FixtureOnly=$true}
}
function Restore-MCDiskOperationItem {
    param([string]$Journal,[string]$Identity,[switch]$Reviewed,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    if(-not$Reviewed){throw 'Review restore target and conflict before restoring.'}
    $inspection=Read-MCDiskOperationJournal $Journal -CancellationToken $CancellationToken;$rows=@($inspection.Items|Where-Object{$_.Identity-eq$Identity})
    if($rows.Count-ne1-or-not$rows[0].CanRestore){throw 'Restore requires a verified backup and an absent destination; never overwrite.'};$item=$rows[0]
    $parent=Split-Path $item.Path -Parent;$probe=[MemoryClear.Storage.FileInventory]::ProbeDirectory($parent);if($probe.State-notin@('Present','EmptyAtObservation')-or$probe.AncestorIdentity-ne$item.OriginalAncestor){throw 'Original parent unavailable/changed; do not recreate/replace ancestor automatically.'}
    $sourceSnapshot=$item.BackupSnapshot;$root=Assert-MCOperationRoot $item.Root
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$mutex=New-Object Threading.Mutex($false,('Local\MemoryClear.DiskOperation.'+$sid));$owned=$false;$ledger=$null;$receipt=$null;$restoreJournal=Join-Path $root ('restore-'+[guid]::NewGuid().ToString('N')+'.jsonl')
    try{
        $owned=$mutex.WaitOne(0);if(-not$owned){throw 'Another cleanup/restore transaction is active.'}
        $CancellationToken.ThrowIfCancellationRequested()
        $ledger=[pscustomobject]@{Stream=[IO.File]::Open($restoreJournal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);Sequence=0;Previous=('0'*64)}
        Write-MCOperationEvent $ledger ([pscustomobject]@{Kind='RestoreStarted';SourceJournal=$Journal;Identity=$Identity;Destination=$item.Path;Sha256=$item.Receipt.Sha256;Sid=$sid;Utc=[DateTime]::UtcNow.ToString('o');FixtureOnly=$true})
        $receipt=[MemoryClear.Storage.FileInventory]::RestoreFixture($sourceSnapshot,(Join-Path $script:Root 'artifacts'),$item.Path,$root,$probe.AncestorIdentity,$item.Receipt.Sha256,$CancellationToken)
        Write-MCOperationEvent $ledger ([pscustomobject]@{Kind='Restored';Identity=$Identity;Receipt=$receipt;Utc=[DateTime]::UtcNow.ToString('o');FixtureOnly=$true})
        [pscustomobject]@{Status='Restored';Path=$item.Path;Sha256=$receipt.Sha256;Bytes=$receipt.Bytes;FixtureOnly=$true;BackupRetained=$true;RestoreJournal=$restoreJournal}
    }catch{if($receipt){[pscustomobject]@{Status='RestoredJournalIncomplete';Path=$item.Path;Sha256=$receipt.Sha256;Bytes=$receipt.Bytes;FixtureOnly=$true;BackupRetained=$true;RestoreJournal=$restoreJournal;Error=$_.Exception.Message}}else{throw}}
    finally{if($ledger){$ledger.Stream.Dispose()};if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
Export-ModuleMember -Function Get-MCDiskExecutionPolicy,New-MCDiskOperation,Get-MCDiskOperation,Move-MCDiskOperationReview,Confirm-MCDiskOperation,Reset-MCDiskOperation,Close-MCDiskOperation,Invoke-MCDiskOperation,Read-MCDiskOperationJournal,Get-MCDiskOperationHistory,Restore-MCDiskOperationItem
