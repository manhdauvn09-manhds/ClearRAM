#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MemoryClear.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'CleanData\MemoryClear.Disk.psm1')
function Get-MCTaskPolicy {
    $p=Get-Content (Join-Path $PSScriptRoot 'memory-task-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $names=@('$schema','governs','schemaVersion','profileMode','executionEnabled','forceEnabled','ttlSeconds','maximumItems','closeTimeoutSeconds','defaultAllowlistEmpty','foregroundBlocked','serviceBlocked','autoForceAfterTimeout')
    if(@($p.PSObject.Properties).Count-ne$names.Count-or@($p.PSObject.Properties.Name|Where-Object{$_-notin$names}).Count-or$p.governs-ne'product_runtime'-or$p.schemaVersion-ne1-or$p.profileMode-ne'UserOptInExecutablePaths'){throw 'Invalid Memory task policy.'}
    if($p.executionEnabled-isnot[bool]-or$p.executionEnabled){throw 'Task execution is gated in this portable preview; changing a flag cannot unlock it.'}
    foreach($field in @('forceEnabled','autoForceAfterTimeout')){if($p.$field-isnot[bool]-or$p.$field){throw 'Automatic force is prohibited.'}}
    foreach($field in @('defaultAllowlistEmpty','foregroundBlocked','serviceBlocked')){if($p.$field-isnot[bool]-or-not$p.$field){throw 'Required task protections cannot be removed.'}}
    foreach($bound in @(@('ttlSeconds',60),@('maximumItems',10),@('closeTimeoutSeconds',20))){if($p.($bound[0])-isnot[int]-or$p.($bound[0])-lt1-or$p.($bound[0])-gt$bound[1]){throw 'Invalid task budget.'}};$p
}
function Get-MCTaskForegroundId {[MemoryClear.Native]::ForegroundProcessId()}
function Test-MCTaskCandidate {
    param($Identity,$Context,$Settings,[int[]]$ExcludedIds=@(),[string[]]$ExcludedPaths=@(),[bool]$ForegroundKnown=$true)
    $base=Test-MCPolicy $Identity $Context $Settings
    $reason=if(-not$base.Allowed){$base.Reason}elseif(-not$ForegroundKnown){'Foreground identity unavailable'}elseif($Identity.Pid-in$ExcludedIds-or@($ExcludedPaths|Where-Object{[string]::Equals($_,$Identity.Path,[StringComparison]::OrdinalIgnoreCase)}).Count){'Foreground / caller / cùng executable được giữ lại'}elseif(-not$base.AllowClose){'Executable chưa được user bật Cho đóng gấp'}else{''}
    [pscustomobject]@{Eligible=($reason-eq'');Reason=if($reason){$reason}else{'Opt-in theo executable; chưa chứng minh app không quan trọng'};Action='GracefulOnly';ForceAllowed=$false;Effect='Đóng có thể dừng cửa sổ, nhạc, thông báo, công việc nền hoặc hỏi lưu. Khi hỏi lưu/quá thời gian sẽ giữ app; không tự force. RAM chỉ được xác nhận sau khi process đã thoát.'}
}
function New-MCTaskPreview {
    param([object[]]$Rows,[int[]]$ExcludedIds=@(),[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $policy=Get-MCTaskPolicy;$settings=Get-MCSettings;$context=Get-MCContext;$foreground=Get-MCTaskForegroundId;$exclusions=@($ExcludedIds)+@($foreground,$PID)
    $excludedPaths=@();$foregroundKnown=$foreground-gt0
    foreach($processId in $exclusions){if($processId-gt0){$identity=[MemoryClear.Native]::Inspect($processId);if($identity.Known){$excludedPaths+=@($identity.Path)}elseif($processId-eq$foreground){$foregroundKnown=$false}}}
    $out=New-Object 'System.Collections.Generic.List[object]';$eligible=0;$seen=@{}
    foreach($row in $Rows){
        $CancellationToken.ThrowIfCancellationRequested()
        # Only saved opt-in paths enter the release plan. Other processes stay out by default.
        if(-not$row.Path-or@($settings.AllowClosePaths|Where-Object{[string]::Equals($_,$row.Path,[StringComparison]::OrdinalIgnoreCase)}).Count-eq0){continue}
        $key="$($row.Pid)/$($row.StartTicks)";if($seen.ContainsKey($key)){continue};$seen[$key]=$true;$guard=$null;$fingerprint=$null;$candidate=$null
        try{$guard=[MemoryClear.Native]::Acquire($row.Pid,$row.StartTicks,$false);$candidate=Test-MCTaskCandidate $guard.Identity $context $settings $exclusions $excludedPaths $foregroundKnown
            $window=0L;$thread=[uint32]0
            if($candidate.Eligible){$window=[MemoryClear.Native]::TaskWindow($row.Pid);$thread=[MemoryClear.Native]::WindowThread($window,$row.Pid);if(-not$window-or-not$thread){throw 'Không có cửa sổ có thể đóng nhẹ; giữ lại.'};$file=[MemoryClear.Storage.FileInventory]::Snapshot($guard.Identity.Path,[IO.Path]::GetDirectoryName($guard.Identity.Path));$fingerprint=[pscustomobject]@{Snapshot=$file;Sha256=[MemoryClear.Storage.FileInventory]::HashSnapshot($file,$CancellationToken)};if($guard.HasExited){throw 'Process đã thoát khi lập preview.'};$eligible++}
            $out.Add([pscustomobject]@{Pid=$row.Pid;StartTicks=$row.StartTicks;Name=$row.Name;Path=$guard.Identity.Path;Sid=$guard.Identity.Sid;Session=$guard.Identity.Session;Window=$window;Thread=$thread;RamMB=$row.RamMB;Eligible=$candidate.Eligible;Reason=$candidate.Reason;Effect=$candidate.Effect;Executable=$fingerprint;ForceAllowed=$false})
        }catch{if($CancellationToken.IsCancellationRequested){throw};$out.Add([pscustomobject]@{Pid=$row.Pid;StartTicks=$row.StartTicks;Name=$row.Name;Path=$row.Path;Sid='';Session=-1;RamMB=$row.RamMB;Eligible=$false;Reason='Không xác minh được process/executable: '+$_.Exception.Message;Effect='Giữ lại. Không có quyền đóng/force từ preview.';Executable=$null;ForceAllowed=$false})}finally{if($guard){$guard.Dispose()}}
        if($out.Count-ge$policy.maximumItems){break}
    }
    $now=[DateTime]::UtcNow
    [pscustomobject]@{Id=[guid]::NewGuid().ToString('N');CreatedUtc=$now;ExpiresUtc=$now.AddSeconds($policy.ttlSeconds);Sid=$context.UserSid;Items=$out.ToArray();EligibleCount=$eligible;ExecutionEnabled=$false;Truncated=($out.Count-ge$policy.maximumItems);Scope='Saved user opt-in executable paths only';SettingsJson=($settings|ConvertTo-Json -Depth 6 -Compress);PolicyJson=($policy|ConvertTo-Json -Depth 6 -Compress);Message='Chỉ preview, tối đa10 mục/TTL60s; executor mức3 còn safety/QA gates. Không đóng/trim/kill process nào. Tên/CPU/RAM không chứng minh task không quan trọng.'}
}
function Get-MCTaskDigest {param([string]$Text);$hash=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$hash.Dispose()}}
function New-MCTaskPlan {
    param([object[]]$Rows,[int[]]$ExcludedIds=@(),[Parameter(Mandatory)][string]$Context,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    foreach($key in @([MemoryClear.TaskSessionStore]::Plans.Keys)){if([DateTime]::UtcNow-ge[MemoryClear.TaskSessionStore]::Plans[$key].Expires){[MemoryClear.TaskSessionStore]::Remove($key)}}
    if([MemoryClear.TaskSessionStore]::Plans.Count-ge8){throw 'Đóng các phiên Memory cũ trước.'}
    $preview=New-MCTaskPreview $Rows $ExcludedIds $CancellationToken
    [MemoryClear.TaskSessionStore]::Plans[$preview.Id]=[pscustomobject]@{Id=$preview.Id;Context=$Context;Sid=$preview.Sid;Created=$preview.CreatedUtc;Expires=$preview.ExpiresUtc;Payload=($preview.Items|ConvertTo-Json -Depth 12 -Compress);Settings=$preview.SettingsJson;Policy=$preview.PolicyJson;Excluded=$ExcludedIds;Stage='Review';Consumed=$false}
    $preview
}
function Read-MCTaskItems {param([string]$Payload);foreach($i in ($Payload|ConvertFrom-Json)){$i}}
function Assert-MCTaskPlan {
    param([string]$Id,[string]$Context)
    if(-not[MemoryClear.TaskSessionStore]::Plans.ContainsKey($Id)){throw 'Phiên Memory đã đóng hoặc không tồn tại.'};$s=[MemoryClear.TaskSessionStore]::Plans[$Id]
    $policy=Get-MCTaskPolicy;$settings=Get-MCSettings
    if($s.Consumed-or$s.Stage-eq'Invalidated'-or$s.Context-cne$Context-or$s.Sid-ne[Security.Principal.WindowsIdentity]::GetCurrent().User.Value-or[DateTime]::UtcNow-ge$s.Expires-or[DateTime]::UtcNow-lt$s.Created-or$s.Settings-cne($settings|ConvertTo-Json -Depth 6 -Compress)-or$s.Policy-cne($policy|ConvertTo-Json -Depth 6 -Compress)){$s.Stage='Invalidated';throw 'Phiên hết hạn hoặc scope/quyền/user/policy đã đổi; lập danh sách mới.'};$s
}
function Confirm-MCTaskPlan {
    param([string]$Id,[string]$Context,[bool]$Acknowledged=$false)
    $s=Assert-MCTaskPlan $Id $Context;if($s.Stage-ne'Review'-or-not$Acknowledged){throw 'Cần đọc tác động và chấp nhận đóng danh sách opt-in.'}
    if(-not@((Read-MCTaskItems $s.Payload)|Where-Object{$_.Eligible}).Count){throw 'Không có tác vụ đủ điều kiện.'};$s.Stage='Approved'
}
function Close-MCTaskPlan {param([string]$Id);[MemoryClear.TaskSessionStore]::Remove($Id)}
function Invoke-MCTaskPlan {
    param([string]$Id,[string]$Context,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[Collections.Concurrent.ConcurrentQueue[object]]$Events=$null)
    $s=Assert-MCTaskPlan $Id $Context;$policy=Get-MCTaskPolicy;if(-not$policy.executionEnabled-or$s.Stage-ne'Approved'){throw 'Executor chưa mở hoặc chưa duyệt danh sách.'}
    $mutex=New-Object Threading.Mutex($false,('Local\MemoryClear.TaskRelease.'+$s.Sid));$owned=$false;$ledger=$null;$out=New-Object 'System.Collections.Generic.List[object]';$watch=[Diagnostics.Stopwatch]::StartNew();$chain=[pscustomobject]@{Sequence=0;Previous=('0'*64)}
    $write={param($event);$payload=$event|ConvertTo-Json -Depth 12 -Compress;$hash=Get-MCTaskDigest ($chain.Previous+"`n"+$payload);$ledger.Append(([pscustomobject]@{Sequence=($chain.Sequence+1);PreviousHash=$chain.Previous;Payload=$payload;Hash=$hash}|ConvertTo-Json -Compress));$chain.Sequence++;$chain.Previous=$hash}
    try{$owned=$mutex.WaitOne(0);if(-not$owned){throw 'Một lượt giải phóng tác vụ khác đang chạy.'};$s=Assert-MCTaskPlan $Id $Context
        if($s.Stage-ne'Approved'){throw 'Phiên đã tiêu thụ.'};$ledger=New-Object MemoryClear.Storage.FileInventory+TempLedger((Split-Path $PSScriptRoot -Parent),$s.Id,'memory-operation');$s.Consumed=$true;$s.Stage='Running'
        $items=@(Read-MCTaskItems $s.Payload|Where-Object{$_.Eligible});& $write ([pscustomobject]@{Kind='Plan';Capability='OptInGracefulOnly';Sid=$s.Sid;Items=$items;Utc=[DateTime]::UtcNow.ToString('o')})
        foreach($item in $items){
            if($CancellationToken.IsCancellationRequested){break};$guard=$null;$status='Skipped';$reason='';$sent=$false
            try{
                if([DateTime]::UtcNow-ge$s.Expires-or$s.Settings-cne((Get-MCSettings)|ConvertTo-Json -Depth 6 -Compress)-or$s.Policy-cne((Get-MCTaskPolicy)|ConvertTo-Json -Depth 6 -Compress)){throw 'TTL/quyền/policy đổi; giữ lại.'}
                $ctx=Get-MCContext;$foreground=Get-MCTaskForegroundId;$excludedPaths=@();$known=$foreground-gt0
                foreach($pidValue in @($s.Excluded)+@($foreground,$PID)){if($pidValue-gt0){$idValue=[MemoryClear.Native]::Inspect($pidValue);if($idValue.Known){$excludedPaths+=@($idValue.Path)}elseif($pidValue-eq$foreground){$known=$false}}}
                $guard=[MemoryClear.Native]::Acquire($item.Pid,$item.StartTicks,$false);$candidate=Test-MCTaskCandidate $guard.Identity $ctx (Get-MCSettings) (@($s.Excluded)+@($foreground,$PID)) $excludedPaths $known
                if(-not$candidate.Eligible-or$guard.Identity.Path-ne$item.Path-or$guard.Identity.Sid-ne$item.Sid-or$guard.Identity.Session-ne$item.Session){throw 'Target/policy không còn khớp: '+$candidate.Reason}
                $fresh=[MemoryClear.Storage.FileInventory]::Snapshot($item.Path,$item.Executable.Snapshot.Root)
                foreach($field in @('Identity','AncestorIdentity','LogicalBytes','AllocatedBytes','LastWriteFileTime','Links','Attributes')){if($fresh.$field-ne$item.Executable.Snapshot.$field){throw 'Executable đã đổi; giữ lại.'}}
                if([MemoryClear.Storage.FileInventory]::HashSnapshot($fresh,$CancellationToken)-ne$item.Executable.Sha256){throw 'Executable hash đã đổi; giữ lại.'}
                if($CancellationToken.IsCancellationRequested){break};if([MemoryClear.Native]::WindowThread($item.Window,$item.Pid)-ne$item.Thread){throw 'Cửa sổ đã đổi; giữ lại.'}
                & $write ([pscustomobject]@{Kind='CloseStarted';Pid=$item.Pid;StartTicks=$item.StartTicks;Window=$item.Window;Utc=[DateTime]::UtcNow.ToString('o')})
                if($CancellationToken.IsCancellationRequested){break};$guard.CloseTaskWindow($item.Window,$item.Thread)|Out-Null;$sent=$true;$wait=[Diagnostics.Stopwatch]::StartNew()
                while(-not$guard.HasExited-and$wait.Elapsed.TotalSeconds-lt$policy.closeTimeoutSeconds-and-not$CancellationToken.IsCancellationRequested){$guard.Wait(100)|Out-Null;if($Events){$Events.Enqueue([pscustomobject]@{Completed=$out.Count;Total=$items.Count;Name=$item.Name;Status='WaitingForExit';Seconds=$watch.Elapsed.TotalSeconds})}}
                $status=if($guard.HasExited){'Exited'}elseif($CancellationToken.IsCancellationRequested){'HeldCancelled'}else{'HeldTimeout'};$reason=if($status-eq'Exited'){'Đã xác nhận thoát.'}else{'App còn chạy hoặc đang hỏi lưu. Không force; không ghi nhận gain.'}
            }catch{$reason=$_.Exception.Message;$status=if($sent){'RequestedUnverified'}else{'Skipped'}}finally{if($guard){$guard.Dispose()}}
            $result=[pscustomobject]@{Pid=$item.Pid;Name=$item.Name;Path=$item.Path;Status=$status;Reason=$reason;ForceUsed=$false};$out.Add($result)
            & $write ([pscustomobject]@{Kind='Outcome';Result=$result;Utc=[DateTime]::UtcNow.ToString('o')})
            if($Events){$Events.Enqueue([pscustomobject]@{Completed=$out.Count;Total=$items.Count;Name=$item.Name;Status=$status;Seconds=$watch.Elapsed.TotalSeconds})}
        }
        $status=if($CancellationToken.IsCancellationRequested){'Cancelled'}elseif($out.Count-ne$items.Count-or@($out|Where-Object{$_.Status-ne'Exited'}).Count){'Partial'}else{'Completed'}
        & $write ([pscustomobject]@{Kind='Finished';Status=$status;Utc=[DateTime]::UtcNow.ToString('o')});$s.Stage=$status
        [pscustomobject]@{Status=$status;Items=$out.ToArray();Processed=$out.Count;Total=$items.Count;Exited=@($out|Where-Object{$_.Status-eq'Exited'}).Count;Seconds=$watch.Elapsed.TotalSeconds;Finished=[DateTime]::Now;Journal=(Join-Path (Split-Path $PSScriptRoot -Parent) ('.data\memory-operation-'+$s.Id+'.jsonl'));Message='Chỉ gửi đóng nhẹ; mục chưa thoát được giữ lại, không tự force. Không ước lượng RAM/CPU gain từ working set.'}
    }catch{$s.Stage='InterruptedUnproven';throw}finally{if($ledger){$ledger.Dispose()};if($owned){$mutex.ReleaseMutex()};$mutex.Dispose();$watch.Stop()}
}
Export-ModuleMember -Function Get-MCTaskPolicy,Test-MCTaskCandidate,New-MCTaskPreview,New-MCTaskPlan,Confirm-MCTaskPlan,Close-MCTaskPlan,Invoke-MCTaskPlan
