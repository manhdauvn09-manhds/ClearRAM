#requires -version 5.1
$script:memoryTaskRoot=Split-Path $PSScriptRoot -Parent
function New-MCMemoryTaskWindow {
    param([object[]]$Rows,[int[]]$ExcludedIds=@())
    Import-Module (Join-Path $memoryTaskRoot 'app\MemoryClear.Tasks.psm1') -Global
    $reader=New-Object Xml.XmlNodeReader ([xml](Get-Content (Join-Path $memoryTaskRoot 'app\MemoryTaskView.xaml') -Raw -Encoding UTF8));$dialog=[Windows.Markup.XamlReader]::Load($reader);$u=@{}
    foreach($name in @('TaskItems','TaskProgress','TaskStatus','TaskExecute','TaskCancel','TaskClose','TaskAck','TaskRescan')){$u[$name]=$dialog.FindName($name)}
    $v=[pscustomobject]@{Window=$dialog;UI=$u;Root=$memoryTaskRoot;Rows=$Rows;Excluded=$ExcludedIds;Context=[guid]::NewGuid().ToString('N');Plan=$null;Result=$null;Busy=$false;Worker=$null;Async=$null;Token=$null;Events=$null;Watch=$null;Action='';Timer=$null}
    $u.TaskAck.Add_Click({Update-MCTaskWindow $v}.GetNewClosure())
    $u.TaskExecute.Add_Click({try{Confirm-MCTaskPlan $v.Plan.Id $v.Context ([bool]$v.UI.TaskAck.IsChecked);Start-MCTaskWindowWorker $v 'Run'}catch{$v.UI.TaskStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $u.TaskRescan.Add_Click({if($v.Plan){Close-MCTaskPlan $v.Plan.Id};$v.Plan=$null;$v.UI.TaskAck.IsChecked=$false;$v.UI.TaskItems.ItemsSource=$null;Start-MCTaskWindowWorker $v 'Plan'}.GetNewClosure())
    $u.TaskCancel.Add_Click({if($v.Token){$v.Token.Cancel();$v.UI.TaskStatus.Text='Đang dừng; yêu cầu đóng đã gửi không thể hoàn tác. Không force các app còn chạy.'}}.GetNewClosure())
    $u.TaskClose.Add_Click({$v.Window.Close()}.GetNewClosure())
    $dialog.Add_Closing({param($sender,$e);if($v.Busy){$e.Cancel=$true;$v.Token.Cancel();$v.UI.TaskStatus.Text='Đang dừng; chờ worker kết thúc rồi đóng.'}}.GetNewClosure())
    $dialog.Add_Closed({$v.Timer.Stop();if($v.Plan){Close-MCTaskPlan $v.Plan.Id}}.GetNewClosure())
    $v.Timer=New-Object Windows.Threading.DispatcherTimer;$v.Timer.Interval=[TimeSpan]::FromMilliseconds(150);$v.Timer.Add_Tick({Complete-MCTaskWindowWorker $v}.GetNewClosure());$v.Timer.Start();Start-MCTaskWindowWorker $v 'Plan';$v
}
function Update-MCTaskWindow {
    param($V)
    $canRun=$false;try{$canRun=(Get-MCTaskPolicy).executionEnabled}catch{}
    $V.UI.TaskExecute.IsEnabled=-not$V.Busy-and$canRun-and$V.Plan-and$V.Plan.EligibleCount-gt0-and-not$V.Result-and[bool]$V.UI.TaskAck.IsChecked
    $V.UI.TaskAck.IsEnabled=-not$V.Busy-and-not$V.Result;$V.UI.TaskRescan.IsEnabled=-not$V.Busy;$V.UI.TaskClose.IsEnabled=-not$V.Busy;$V.UI.TaskCancel.IsEnabled=$V.Busy
}
function Start-MCTaskWindowWorker {
    param($V,[ValidateSet('Plan','Run')][string]$Action)
    if($V.Busy){return};$V.Busy=$true;$V.Action=$Action;$V.Result=$null;$V.Token=New-Object Threading.CancellationTokenSource;$V.Events=New-Object 'Collections.Concurrent.ConcurrentQueue[object]';$V.Watch=[Diagnostics.Stopwatch]::StartNew();$V.UI.TaskProgress.IsIndeterminate=$true;Update-MCTaskWindow $V
    try{$V.Worker=[PowerShell]::Create();$id=if($V.Plan){$V.Plan.Id}else{''}
        $V.Worker.AddScript('param($root,$action,$rows,$excluded,$id,$context,$token,$events);Import-Module (Join-Path $root "app\MemoryClear.Tasks.psm1");if($action-eq"Plan"){New-MCTaskPlan -Rows $rows -ExcludedIds $excluded -Context $context -CancellationToken $token}else{Invoke-MCTaskPlan -Id $id -Context $context -CancellationToken $token -Events $events}').AddArgument($V.Root).AddArgument($Action).AddArgument($V.Rows).AddArgument($V.Excluded).AddArgument($id).AddArgument($V.Context).AddArgument($V.Token.Token).AddArgument($V.Events)|Out-Null;$V.Async=$V.Worker.BeginInvoke()
    }catch{$V.Busy=$false;if($V.Worker){$V.Worker.Dispose()};$V.Token.Dispose();$V.UI.TaskProgress.IsIndeterminate=$false;Update-MCTaskWindow $V;$V.UI.TaskStatus.Text=$_.Exception.Message}
}
function Complete-MCTaskWindowWorker {
    param($V)
    if(-not$V.Busy-or-not$V.Async){return};$e=$null
    $hadEvent=$false
    while($V.Events.TryDequeue([ref]$e)){$hadEvent=$true;$V.UI.TaskProgress.IsIndeterminate=$false;$V.UI.TaskProgress.Maximum=$e.Total;$V.UI.TaskProgress.Value=$e.Completed;$V.UI.TaskStatus.Text=('{0}/{1} · {2} · {3} · {4:N1}s'-f$e.Completed,$e.Total,$e.Name,$e.Status,$e.Seconds)}
    if(-not$V.Async.IsCompleted){if(-not$hadEvent-and$V.UI.TaskProgress.IsIndeterminate){$V.UI.TaskStatus.Text=('{0} · {1:N1}s · đóng nhẹ, không tự force'-f$V.Action,$V.Watch.Elapsed.TotalSeconds)};return};$message=''
    try{$out=@($V.Worker.EndInvoke($V.Async));if($V.Worker.Streams.Error.Count){throw ($V.Worker.Streams.Error|Out-String)};if(-not$out.Count){throw 'Worker không trả kết quả.'}
        if($V.Action-eq'Plan'){$V.Plan=$out[-1];$V.UI.TaskItems.ItemsSource=$V.Plan.Items;$message=('{0} mục opt-in · {1} đủ điều kiện. Đọc tác động rồi chấp nhận đóng nhẹ; app hỏi lưu/quá thời gian sẽ được giữ lại.'-f$V.Plan.Items.Count,$V.Plan.EligibleCount);if(-not(Get-MCTaskPolicy).executionEnabled){$message+=' Executor đang khóa theo gate.'}}
        else{$V.Result=$out[-1];$r=$V.Result;foreach($row in $V.Plan.Items){$match=@($r.Items|Where-Object{$_.Pid-eq$row.Pid});if($match.Count){$row.Reason=$match[0].Status+' · '+$match[0].Reason}};$V.UI.TaskItems.Items.Refresh();$message=('{0} · đã xác nhận thoát {1}/{2} app · {3:N1}s · kết thúc {4:HH:mm:ss}. '-f$r.Status,$r.Exited,$r.Total,$r.Seconds,$r.Finished)+$r.Message+' Nhật ký: '+$r.Journal}
    }catch{$V.Result=[pscustomobject]@{Status='Unverified'};$message=if($V.Token.IsCancellationRequested){'Đã dừng. Kiểm tra nhật ký nếu yêu cầu đóng đã gửi; không tự chạy lại.'}else{'Kết quả chưa xác minh: '+$_.Exception.Message}}
    finally{$V.Watch.Stop();$V.Busy=$false;$V.Worker.Dispose();$V.Worker=$null;$V.Token.Dispose();$V.Token=$null;$V.Async=$null;$V.UI.TaskProgress.IsIndeterminate=$false;Update-MCTaskWindow $V;$V.UI.TaskStatus.Text=$message}
}
function Show-MCMemoryTaskPreview {
    if($operation){return};if(-not$snapshot){Show-MCMessage 'Cần chờ mẫu process đầu tiên.';return};$v=$null
    try{$script:memoryTaskModalActive=$true;Set-MCOperationState $true;$v=New-MCMemoryTaskWindow @($snapshot.Rows) ([int[]]@($PID,$lastForegroundPid));$v.Window.Owner=$window;$v.Window.ShowDialog()|Out-Null}
    catch{Show-MCMessage $_.Exception.Message}finally{if($v-and$v.Plan){Close-MCTaskPlan $v.Plan.Id};$script:memoryTaskModalActive=$false;Set-MCOperationState $false;$script:nextScan=[DateTime]::MinValue}
}
