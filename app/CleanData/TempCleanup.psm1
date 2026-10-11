#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MemoryClear.Disk.psm1')
$script:Project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:Sessions=[MemoryClear.Storage.OperationSessionStore]::TempSessions
function Get-MCTempPolicy {
    $json=Get-Content (Join-Path $script:Project 'app\temp-cleanup-policy.json') -Raw -Encoding UTF8
    $p=$json|ConvertFrom-Json
    $names=@('$schema','governs','schemaVersion','capability','minimumDays','extensions','maximumItems','maximumEntries','maximumSeconds','ttlSeconds','permanentRequiresTwoSteps','allowElevation','recursive')
    if(@($p.PSObject.Properties).Count-ne$names.Count-or@($p.PSObject.Properties.Name|Where-Object{$_-notin$names}).Count-or$p.governs-ne'product_runtime'-or$p.schemaVersion-ne1-or$p.capability-ne'ReviewedTopLevelOwnTemp'-or$p.permanentRequiresTwoSteps-isnot[bool]-or$p.allowElevation-isnot[bool]-or$p.recursive-isnot[bool]-or$p.permanentRequiresTwoSteps-cne$true-or$p.allowElevation-cne$false-or$p.recursive-cne$false-or($p.extensions-join',')-cne'.tmp,.log'-or@($p.minimumDays).Count-ne3){throw 'Invalid Temp cleanup policy.'}
    foreach($days in $p.minimumDays){if($days-isnot[int]-or$days-lt3-or$days-gt365){throw 'Invalid Temp age policy.'}}
    foreach($bound in @(@('maximumItems',100),@('maximumEntries',5000),@('maximumSeconds',15),@('ttlSeconds',600))){if($p.($bound[0])-isnot[int]-or$p.($bound[0])-lt1-or$p.($bound[0])-gt$bound[1]){throw 'Invalid Temp budget.'}}
    $p
}
function Get-MCTempHash {param([string]$Text);$h=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$h.Dispose()}}
function Get-MCTempStamp {Get-MCTempHash (Get-Content (Join-Path $script:Project 'app\temp-cleanup-policy.json') -Raw -Encoding UTF8)}
function Read-MCTempItems {param([string]$Json);foreach($row in ($Json|ConvertFrom-Json)){$row}}
function New-MCTempPlan {
    param([ValidateRange(1,3)][int]$Level=1,[Parameter(Mandatory)][string]$Context,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[string[]]$CandidatePaths=@())
    $policy=Get-MCTempPolicy;$root=[MemoryClear.Storage.FileInventory]::OwnTempRoot();$days=$policy.minimumDays[$Level-1]
    if(-not(Test-MCDiskScanRoot $root (Get-MCDiskContext))){throw 'Temp overlaps a protected/cloud scope or cloud inventory is unavailable.'}
    if($CandidatePaths.Count-gt$policy.maximumItems){throw 'Too many requested Temp files.'}
    foreach($key in @($script:Sessions.Keys)){if([DateTime]::UtcNow-ge$script:Sessions[$key].Expires){$unused=$null;$script:Sessions.TryRemove($key,[ref]$unused)|Out-Null}}
    if($script:Sessions.Count-ge8){throw 'Close previous Temp plans.'}
    $rows=New-Object 'System.Collections.Generic.List[object]';$seen=@{};$skipped=0;$visited=0;$partial=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
    $iterator=$null;if($CandidatePaths.Count){$iterator=$CandidatePaths.GetEnumerator()}else{$iterator=[IO.Directory]::EnumerateFiles($root,'*',[IO.SearchOption]::TopDirectoryOnly).GetEnumerator()}
    try{while($iterator.MoveNext()){
        $CancellationToken.ThrowIfCancellationRequested();$visited++
        if($visited-gt$policy.maximumEntries-or$watch.Elapsed.TotalSeconds-ge$policy.maximumSeconds-or$rows.Count-ge$policy.maximumItems){$partial=$true;break}
        $path=$iterator.Current;if([IO.Path]::GetExtension($path).ToLowerInvariant()-notin$policy.extensions){$skipped++;continue}
        try{$snapshot=[MemoryClear.Storage.FileInventory]::Snapshot($path,$root);[MemoryClear.Storage.FileInventory]::ValidateOwnTemp($snapshot,$days)
            if($seen.ContainsKey($snapshot.Identity)){$skipped++;continue};$seen[$snapshot.Identity]=$true
            $hash=[MemoryClear.Storage.FileInventory]::HashSnapshot($snapshot,$CancellationToken)
            $rows.Add([pscustomobject]@{Id=$snapshot.Identity;Name=[IO.Path]::GetFileName($path);Path=$path;MB=[Math]::Round($snapshot.AllocatedBytes/1MB,2);AgeDays=[Math]::Floor(([DateTime]::UtcNow-[DateTime]::FromFileTimeUtc($snapshot.LastWriteFileTime)).TotalDays);Risk='Review';Effect='Xóa vĩnh viễn: có thể mất log chẩn đoán hoặc dữ liệu tạm phục vụ khôi phục/cài đặt. Không có Undo.';Snapshot=$snapshot;Sha256=$hash})
        }catch{if($CancellationToken.IsCancellationRequested){throw};$skipped++}
    }}finally{if($iterator-is[IDisposable]){$iterator.Dispose()};$watch.Stop()}
    $id=[guid]::NewGuid().ToString('N');$now=[DateTime]::UtcNow
    $script:Sessions[$id]=[pscustomobject]@{Id=$id;Context=$Context;Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Stamp=(Get-MCTempStamp);Created=$now;Expires=$now.AddSeconds($policy.ttlSeconds);Root=$root;Days=$days;Payload=($rows.ToArray()|ConvertTo-Json -Depth 10 -Compress);Stage='Review';Consumed=$false;Partial=$partial;Skipped=$skipped;Visited=$visited}
    Get-MCTempPlan $id
}
function Get-MCTempPlan {param([string]$Id);if(-not$script:Sessions.ContainsKey($Id)){throw 'Temp plan is closed.'};$s=$script:Sessions[$Id];[pscustomobject]@{Id=$Id;Stage=$s.Stage;Root=$s.Root;Days=$s.Days;Items=@(Read-MCTempItems $s.Payload);Partial=$s.Partial;Skipped=$s.Skipped;Visited=$s.Visited;Expires=$s.Expires}}
function Assert-MCTempPlan {
    param([string]$Id,[string]$Context)
    Get-MCTempPolicy|Out-Null;if(-not$script:Sessions.ContainsKey($Id)){throw 'Unknown Temp plan.'};$s=$script:Sessions[$Id]
    if($s.Consumed-or$s.Stage-eq'Invalidated'-or$s.Context-cne$Context-or$s.Sid-ne[Security.Principal.WindowsIdentity]::GetCurrent().User.Value-or$s.Stamp-ne(Get-MCTempStamp)-or[DateTime]::UtcNow-ge$s.Expires-or[DateTime]::UtcNow-lt$s.Created-or$s.Root-ne[MemoryClear.Storage.FileInventory]::OwnTempRoot()-or-not(Test-MCDiskScanRoot $s.Root (Get-MCDiskContext))){$s.Stage='Invalidated';throw 'Temp scope/SID/policy/TTL changed.'};$s
}
function Review-MCTempPlan {
    param([string]$Id,[string]$Context,[string[]]$SelectedIds)
    $s=Assert-MCTempPlan $Id $Context;if($s.Stage-ne'Review'){throw 'First review step required.'};$all=@(Read-MCTempItems $s.Payload)
    if($SelectedIds.Count-lt1-or@($SelectedIds|Select-Object -Unique).Count-ne$SelectedIds.Count-or@($SelectedIds|Where-Object{$_-notin$all.Id}).Count){throw 'Select current Temp items and read their impact.'}
    $chosen=@($all|Where-Object{$_.Id-in$SelectedIds});$s.Payload=($chosen|ConvertTo-Json -Depth 10 -Compress);$s.Stage='Confirm';Get-MCTempPlan $Id
}
function Confirm-MCTempPlan {
    param([string]$Id,[string]$Context,[bool]$Acknowledged=$false)
    $s=Assert-MCTempPlan $Id $Context;if($s.Stage-ne'Confirm'-or-not$Acknowledged){throw 'Second permanent-delete acknowledgment required.'}
    foreach($item in @(Read-MCTempItems $s.Payload)){[MemoryClear.Storage.FileInventory]::ValidateOwnTemp([MemoryClear.Storage.FileRecord]$item.Snapshot,$s.Days)}
    $s.Stage='Approved'
}
function Close-MCTempPlan {param([string]$Id);$unused=$null;$script:Sessions.TryRemove($Id,[ref]$unused)|Out-Null}
function Invoke-MCTempPlan {
    param([string]$Id,[string]$Context,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[Collections.Concurrent.ConcurrentQueue[object]]$Events=$null)
    $s=Assert-MCTempPlan $Id $Context;if($s.Stage-ne'Approved'){throw 'Both Temp review steps must finish before execution.'}
    $mutex=New-Object Threading.Mutex($false,('Local\MemoryClear.DiskOperation.'+$s.Sid));$owned=$false;$ledger=$null;$outcomes=New-Object 'System.Collections.Generic.List[object]';$watch=[Diagnostics.Stopwatch]::StartNew();$state=[pscustomobject]@{Sequence=0;Previous=('0'*64)}
    $write={param($event);$payload=$event|ConvertTo-Json -Depth 12 -Compress;$hash=Get-MCTempHash ($state.Previous+"`n"+$payload);$ledger.Append(([pscustomobject]@{Sequence=($state.Sequence+1);PreviousHash=$state.Previous;Payload=$payload;Hash=$hash}|ConvertTo-Json -Compress));$state.Sequence++;$state.Previous=$hash}
    try{$owned=$mutex.WaitOne(0);if(-not$owned){throw 'Another Disk operation is running.'};$s=Assert-MCTempPlan $Id $Context;if($s.Stage-ne'Approved'){throw 'Already consumed.'}
        $ledger=New-Object MemoryClear.Storage.FileInventory+TempLedger($script:Project,$s.Id);$s.Consumed=$true;$s.Stage='Running';$items=@(Read-MCTempItems $s.Payload)
        & $write ([pscustomobject]@{Kind='Plan';SchemaVersion=1;Capability='ReviewedTopLevelOwnTemp';Sid=$s.Sid;PolicyStamp=$s.Stamp;Items=$items;Utc=[DateTime]::UtcNow.ToString('o')})
        $journalFault=$false
        foreach($item in $items){
            if($CancellationToken.IsCancellationRequested-or[DateTime]::UtcNow-ge$s.Expires){break};$receipt=$null;$errorText='';$status='Skipped'
            try{if($s.Stamp-ne(Get-MCTempStamp)){throw 'Policy changed; source retained.'}
                $observer=[Action[string,MemoryClear.Storage.FixtureReceipt]]{param($stage,$pending);& $write ([pscustomobject]@{Kind='Item';Path=$item.Path;Identity=$item.Id;Stage=$stage;Utc=[DateTime]::UtcNow.ToString('o')})}
                $receipt=[MemoryClear.Storage.FileInventory]::ExecuteOwnTemp([MemoryClear.Storage.FileRecord]$item.Snapshot,$s.Days,$item.Sha256,$CancellationToken,$observer);$status='Deleted'
                & $write ([pscustomobject]@{Kind='Item';Path=$item.Path;Identity=$item.Id;Stage='Committed';Utc=[DateTime]::UtcNow.ToString('o')})
            }catch{$errorText=$_.Exception.Message;$status=if($receipt-and$receipt.Deleted){'DeletedJournalIncomplete'}elseif($CancellationToken.IsCancellationRequested){'Cancelled'}else{'Skipped'}}
            $outcome=[pscustomobject]@{Path=$item.Path;Status=$status;Error=$errorText;AllocatedBytes=$item.Snapshot.AllocatedBytes}
            try{& $write ([pscustomobject]@{Kind='Outcome';Path=$item.Path;Identity=$item.Id;Status=$status;Error=$errorText;Utc=[DateTime]::UtcNow.ToString('o')})}
            catch{$journalFault=$true;$outcome.Status=if($receipt-and$receipt.Deleted){'DeletedJournalIncomplete'}else{'SkippedJournalIncomplete'};$outcome.Error+=' Journal: '+$_.Exception.Message}
            $outcomes.Add($outcome)
            if($Events){$Events.Enqueue([pscustomobject]@{Completed=$outcomes.Count;Total=$items.Count;Path=$item.Path;Status=$outcome.Status;Seconds=$watch.Elapsed.TotalSeconds})}
            if($journalFault){break}
        }
        $status=if($CancellationToken.IsCancellationRequested){'Cancelled'}elseif($outcomes.Count-ne$items.Count-or@($outcomes|Where-Object{$_.Status-ne'Deleted'}).Count){'Partial'}else{'Completed'}
        if($journalFault){$status='InterruptedUnproven'}else{try{& $write ([pscustomobject]@{Kind='Finished';Status=$status;Utc=[DateTime]::UtcNow.ToString('o')})}catch{$status='InterruptedUnproven'}};$s.Stage=$status
        $total=0L;foreach($r in $outcomes){if($r.Status-in@('Deleted','DeletedJournalIncomplete')){$total+=$r.AllocatedBytes}}
        [pscustomobject]@{Status=$status;Items=$outcomes.ToArray();Processed=$outcomes.Count;Total=$items.Count;KnownAllocatedBytes=$total;Seconds=$watch.Elapsed.TotalSeconds;Finished=[DateTime]::Now;Journal=(Join-Path $script:Project ('.data\temp-operation-'+$s.Id+'.jsonl'))}
    }catch{if($s.Stage-eq'Running'){$s.Stage='InterruptedUnproven'};throw}finally{if($ledger){$ledger.Dispose()};if($owned){$mutex.ReleaseMutex()};$mutex.Dispose();$watch.Stop()}
}
Export-ModuleMember -Function Get-MCTempPolicy,New-MCTempPlan,Get-MCTempPlan,Review-MCTempPlan,Confirm-MCTempPlan,Close-MCTempPlan,Invoke-MCTempPlan
