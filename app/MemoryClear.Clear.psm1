Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MemoryClear.Core.psm1')
$script:LastClearTick=0L
$script:LastClearCooldown=0
function Get-MCClearPolicy {
    param([ValidateSet('Normal','Strong')][string]$Mode='Normal')
    $policy=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'clear-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($policy.schemaVersion-is[bool]-or$policy.schemaVersion-ne2-or$policy.governs-ne'product_runtime'){throw 'Invalid Clear policy schema.'}
    $bounds=@{minWorkingSetMB=@(16,4096);maxCpuPercent=@(0,1);sampleMilliseconds=@(500,5000);liveProbeMilliseconds=@(100,1000);maxProcesses=@(1,32);maxDurationSeconds=@(5,120);cooldownSeconds=@(30,600);targetAvailableFraction=@(0.05,0.5)}
    foreach($name in $policy.PSObject.Properties.Name){if($name-notin@('$schema','governs','schemaVersion','strong')-and-not$bounds.ContainsKey($name)){throw "Unknown Clear policy field: $name"}}
    foreach($name in $bounds.Keys){$value=$policy.$name;if($value-isnot[ValueType]-or$value-is[bool]-or$value-lt$bounds[$name][0]-or$value-gt$bounds[$name][1]){throw "Invalid Clear policy field: $name"}}
    foreach($name in @('sampleMilliseconds','liveProbeMilliseconds','maxProcesses','maxDurationSeconds','cooldownSeconds')){if([Math]::Truncate($policy.$name)-ne$policy.$name){throw "Integer required: $name"}}
    $strongFields=@('minWorkingSetMB','maxCpuPercent','maxProcesses','maxDurationSeconds','cooldownSeconds','targetAvailableFraction')
    if($policy.strong-isnot[pscustomobject]){throw 'Invalid Strong Clear policy.'}
    foreach($name in $policy.strong.PSObject.Properties.Name){if($name-notin$strongFields){throw "Unknown Strong Clear policy field: $name"}}
    foreach($name in $strongFields){$value=$policy.strong.$name;if($value-isnot[ValueType]-or$value-is[bool]-or$value-lt$bounds[$name][0]-or$value-gt$bounds[$name][1]){throw "Invalid Strong Clear policy field: $name"}}
    foreach($name in @('maxProcesses','maxDurationSeconds','cooldownSeconds')){if([Math]::Truncate($policy.strong.$name)-ne$policy.strong.$name){throw "Integer required: strong.$name"}}
    if($Mode-eq'Strong'){foreach($name in $strongFields){$policy.$name=$policy.strong.$name}}
    return $policy
}
function Send-MCClearProgress {
    param([System.Collections.Concurrent.ConcurrentQueue[object]]$Queue,[string]$Stage,[string]$Message,[int]$Processed=0,[int]$Total=0)
    if($null-ne$Queue){$Queue.Enqueue([pscustomobject]@{Stage=$Stage;Message=$Message;Processed=$Processed;Total=$Total})}
}
function Get-MCClearCandidates {
    param($Snapshot,$Previous,$Policy,[int[]]$ExcludedIds=@(),[string[]]$ExcludedPaths=@())
    $prior=@{};foreach($row in $Previous.Rows){$prior["$($row.Pid)/$($row.StartTicks)"]=$row}
    @($Snapshot.Rows|Where-Object{
        $key="$($_.Pid)/$($_.StartTicks)";$old=$prior[$key]
        $_.Allowed-and$_.StartTicks-gt0-and$null-ne$_.RamMB-and$_.RamMB-ge$Policy.minWorkingSetMB-and
        $null-ne$_.Cpu-and$_.Cpu-le$Policy.maxCpuPercent-and$old-and$null-ne$old.Cpu-and$old.Cpu-le$Policy.maxCpuPercent-and
        $ExcludedIds-notcontains$_.Pid-and$ExcludedPaths-notcontains$_.Path
    }|Sort-Object RamMB -Descending|Select-Object -First $Policy.maxProcesses)
}
function Invoke-MCTrim {
    param([int]$ProcessId,[long]$StartTicks,$Policy,[int[]]$ExcludedIds=@(),[string[]]$ExcludedPaths=@(),[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $guard=$null;$result=[ordered]@{Timestamp=[DateTime]::UtcNow.ToString('o');Pid=$ProcessId;Action='Trim';Status='Skipped';Message='';AvailableBefore=0;AvailableAfter=0}
    try {
        if($ExcludedIds-contains$ProcessId){throw 'Excluded active process.'}
        $guard=[MemoryClear.Native]::AcquireForTrim($ProcessId,$StartTicks)
        if($ExcludedPaths-contains$guard.Identity.Path){throw 'Excluded active application.'}
        $permission=Test-MCPolicy $guard.Identity (Get-MCContext) (Get-MCSettings)
        if(-not$permission.Allowed){throw $permission.Reason}
        $settings=Get-MCSettings;$permission=Test-MCPolicy $guard.Identity (Get-MCContext) $settings
        if(-not$permission.Allowed){throw $permission.Reason}
        $cpuBefore=$guard.CpuSeconds;$watch=[Diagnostics.Stopwatch]::StartNew();Start-Sleep -Milliseconds $Policy.liveProbeMilliseconds
        $cpu=100*($guard.CpuSeconds-$cpuBefore)/$watch.Elapsed.TotalSeconds/[Environment]::ProcessorCount
        if($cpu-gt$Policy.maxCpuPercent){throw 'Process became busy; skipped.'}
        $foreground=[MemoryClear.Native]::Inspect([MemoryClear.Native]::ForegroundProcessId())
        if($foreground.Pid-eq$ProcessId-or($foreground.Known-and$foreground.Path-eq$guard.Identity.Path)){throw 'Application became foreground; skipped.'}
        if($CancellationToken.IsCancellationRequested){throw 'Clear cancelled before trim.'}
        $result.AvailableBefore=[MemoryClear.Native]::ReadSystem().AvailableBytes
        $guard.Trim();$result.Status='Trimmed';$result.Message='Working set trim requested; process remains running; commit is not released.'
        $result.AvailableAfter=[MemoryClear.Native]::ReadSystem().AvailableBytes
    }catch{$result.Message=$_.Exception.Message}finally{if($guard){$guard.Dispose()}}
    try{Write-MCEvent ([pscustomobject]$result)}catch{$result.Message+=' (Audit write failed: '+$_.Exception.Message+')'}
    [pscustomobject]$result
}
function Invoke-MCClear {
    param($Previous,[int[]]$ExcludedIds=@(),[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[switch]$DryRun,[ValidateSet('Normal','Strong')][string]$Mode='Normal',[System.Collections.Concurrent.ConcurrentQueue[object]]$ProgressQueue=$null)
    Send-MCClearProgress $ProgressQueue 'Validating' 'Đang kiểm tra cấu hình Clear...'
    $policy=Get-MCClearPolicy -Mode $Mode;$now=[Diagnostics.Stopwatch]::GetTimestamp()
    $cooldown=[Math]::Max($script:LastClearCooldown,$policy.cooldownSeconds)
    $elapsed=($now-$script:LastClearTick)/[double][Diagnostics.Stopwatch]::Frequency
    if(-not$DryRun-and$script:LastClearTick-gt0-and$elapsed-lt$cooldown){
        $remaining=[int][Math]::Ceiling($cooldown-$elapsed);$message="Clear vừa chạy; chờ thêm $remaining giây để hạn chế app nạp RAM liên tục."
        Send-MCClearProgress $ProgressQueue 'Cooldown' $message
        return [pscustomobject]@{Status='Cooldown';Mode=$Mode;RetryAfterSeconds=$remaining;Message=$message}
    }
    $before=[MemoryClear.Native]::ReadSystem();$watch=[Diagnostics.Stopwatch]::StartNew();$outcomes=@();$reason='NoCandidates'
    if(-not$DryRun-and-not$CancellationToken.IsCancellationRequested){$script:LastClearTick=$now;$script:LastClearCooldown=$policy.cooldownSeconds;[GC]::Collect()}
    $snapshot=$Previous;$second=$null;$candidates=@()
    for($i=0;$i-lt3;$i++){
        if($CancellationToken.IsCancellationRequested){$reason='Cancelled';break}
        if($watch.Elapsed.TotalSeconds-ge$policy.maxDurationSeconds){$reason='TimeLimit';break}
        Send-MCClearProgress $ProgressQueue 'Scanning' ("Đang lấy mẫu RAM/CPU $($i+1)/3; giữ nguyên ứng dụng...")
        $second=$snapshot;$snapshot=Get-MCSnapshot -Previous $second
        if($i-lt2){[void]$CancellationToken.WaitHandle.WaitOne($policy.sampleMilliseconds)}
    }
    $excludedPaths=@();foreach($id in @($ExcludedIds+[MemoryClear.Native]::ForegroundProcessId())){if($id-gt0){$identity=[MemoryClear.Native]::Inspect($id);if($identity.Known){$excludedPaths+=@($identity.Path)}}}
    if($reason-notin@('Cancelled','TimeLimit')){$candidates=@(Get-MCClearCandidates $snapshot $second $policy $ExcludedIds $excludedPaths)}
    if($DryRun){Send-MCClearProgress $ProgressQueue 'DryRun' 'Đã lập danh sách; không thực hiện thao tác.';return [pscustomobject]@{Status='DryRun';Mode=$Mode;Candidates=$candidates;Message='No process was trimmed or closed.'}}
    $processed=0
    if($candidates.Count){Send-MCClearProgress $ProgressQueue 'Processing' 'Đã chọn ứng viên; bắt đầu kiểm tra lại từng process.' 0 $candidates.Count}
    foreach($row in $candidates){
        if($CancellationToken.IsCancellationRequested){$reason='Cancelled';break}
        if($watch.Elapsed.TotalSeconds-ge$policy.maxDurationSeconds){$reason='TimeLimit';break}
        if([MemoryClear.Native]::ReadSystem().AvailableBytes-ge$before.TotalBytes*$policy.targetAvailableFraction){$reason='EnoughAvailable';break}
        Send-MCClearProgress $ProgressQueue 'Processing' ("Đang kiểm tra $($processed+1)/$($candidates.Count): $($row.Name) · PID $($row.Pid)") $processed $candidates.Count
        $outcomes+=@(Invoke-MCTrim -ProcessId $row.Pid -StartTicks $row.StartTicks -Policy $policy -ExcludedIds $ExcludedIds -ExcludedPaths $excludedPaths -CancellationToken $CancellationToken)
        $reason='CandidatesFinished'
        $processed++
        Send-MCClearProgress $ProgressQueue 'Processing' ("Đã xử lý $processed/$($candidates.Count): $($row.Name) · $($outcomes[-1].Status)") $processed $candidates.Count
    }
    if($CancellationToken.IsCancellationRequested){$reason='Cancelled'}elseif($watch.Elapsed.TotalSeconds-ge$policy.maxDurationSeconds){$reason='TimeLimit'}
    $after=[MemoryClear.Native]::ReadSystem();$trimmed=@($outcomes|Where-Object{$_.Status-eq'Trimmed'}).Count
    $reasons=@{NoCandidates='Không có ứng viên.';Cancelled='Đã dừng theo yêu cầu.';TimeLimit='Đã hết ngân sách thời gian.';EnoughAvailable='Đã đạt mức RAM khả dụng mục tiêu.';CandidatesFinished='Đã xử lý danh sách đủ điều kiện.'}
    $message=('Clear: đã trim {0} process, đóng/kill 0. RAM khả dụng {1:N2} → {2:N2} GB. {3}'-f$trimmed,($before.AvailableBytes/1GB),($after.AvailableBytes/1GB),$reasons[$reason])
    if($trimmed-eq0-and$reason-eq'NoCandidates'){$message+=' Không có ứng viên phù hợp; app đang dùng/được bảo vệ được giữ lại.'}
    if($reason-eq'EnoughAvailable'){$message+=' RAM khả dụng đã đạt mức mục tiêu; không cần trim thêm.'}
    if($after.CommitLimitBytes-gt0-and$after.CommitBytes/[double]$after.CommitLimitBytes-ge0.9){$message+=' Commit gần giới hạn; trim không giải phóng cấp phát này. Cần lưu và đóng bớt app để giảm commit.'}
    $result=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Action='Clear';Mode=$Mode;Status=$reason;Processed=$processed;CandidateCount=$candidates.Count;DurationSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,1);Trimmed=$trimmed;Closed=0;Killed=0;AvailableBefore=$before.AvailableBytes;AvailableAfter=$after.AvailableBytes;CommitBefore=$before.CommitBytes;CommitAfter=$after.CommitBytes;Results=$outcomes;Message=$message}
    Send-MCClearProgress $ProgressQueue $reason $message $processed $candidates.Count
    try{Write-MCEvent $result}catch{$result.Message+=' Nhật ký không ghi được: '+$_.Exception.Message}
    return $result
}
Export-ModuleMember -Function Get-MCClearPolicy,Get-MCClearCandidates,Invoke-MCTrim,Invoke-MCClear
