#requires -version 5.1
function New-MCTempWindow {
    param([ValidateRange(1,3)][int]$Level=1,[string[]]$CandidatePaths=@())
    Import-Module (Join-Path $diskRoot 'app\CleanData\TempCleanup.psm1') -Global -DisableNameChecking
    $reader=New-Object Xml.XmlNodeReader ([xml](Get-Content (Join-Path $diskRoot 'app\CleanData\TempView.xaml') -Raw -Encoding UTF8));$dialog=[Windows.Markup.XamlReader]::Load($reader);$controls=@{}
    foreach($name in @('TempScope','TempFiles','TempSelectAll','TempStage','TempAck','TempProgress','TempStatus','TempBack','TempNext','TempRun','TempStop','TempClose')){$controls[$name]=$dialog.FindName($name);if(-not$controls[$name]){throw "Missing Temp control: $name"}}
    $v=[pscustomobject]@{Window=$dialog;UI=$controls;Root=$diskRoot;Level=$Level;CandidatePaths=$CandidatePaths;Context=[guid]::NewGuid().ToString('N');Plan=$null;Rows=@();Busy=$false;Worker=$null;Async=$null;Token=$null;Events=$null;Watch=$null;Action='';Timer=$null;Result=$null}
    $controls.TempSelectAll.Add_Click({if(-not$v.Busy-and$v.Plan-and$v.Plan.Stage-eq'Review'){foreach($r in $v.Rows){$r.Selected=$true};$v.UI.TempFiles.Items.Refresh()}}.GetNewClosure())
    $controls.TempNext.Add_Click({try{$v.UI.TempFiles.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)|Out-Null;$v.UI.TempFiles.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)|Out-Null;$ids=@($v.Rows|Where-Object{$_.Selected}|ForEach-Object{$_.Id});$v.Plan=Review-MCTempPlan $v.Plan.Id $v.Context $ids;$v.UI.TempAck.IsChecked=$false;Update-MCTempWindow $v;$v.UI.TempStatus.Text='Đã cố định danh sách. Kiểm tra lần cuối rồi đánh dấu chấp nhận xóa vĩnh viễn.'}catch{$v.UI.TempStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $controls.TempAck.Add_Click({Update-MCTempWindow $v}.GetNewClosure())
    $controls.TempRun.Add_Click({try{Confirm-MCTempPlan $v.Plan.Id $v.Context ([bool]$v.UI.TempAck.IsChecked);Start-MCTempWindowWorker $v 'Run'}catch{$v.UI.TempStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $controls.TempBack.Add_Click({if($v.Plan){Close-MCTempPlan $v.Plan.Id};$v.Plan=$null;$v.Rows=@();$v.UI.TempFiles.ItemsSource=$null;$v.UI.TempAck.IsChecked=$false;Start-MCTempWindowWorker $v 'Scan'}.GetNewClosure())
    $controls.TempStop.Add_Click({if($v.Token){$v.Token.Cancel();$v.UI.TempStatus.Text='Đang dừng tại ranh giới file; giữ nguyên các mục chưa xử lý.'}}.GetNewClosure())
    $controls.TempClose.Add_Click({$v.Window.Close()}.GetNewClosure())
    $dialog.Add_Closing({param($sender,$event);if($v.Busy){$event.Cancel=$true;$v.Token.Cancel();$v.UI.TempStatus.Text='Đang dừng; chờ kết quả rồi đóng cửa sổ.'}}.GetNewClosure())
    $dialog.Add_Closed({$v.Timer.Stop();if($v.Plan){Close-MCTempPlan $v.Plan.Id}}.GetNewClosure())
    $v.Timer=New-Object Windows.Threading.DispatcherTimer;$v.Timer.Interval=[TimeSpan]::FromMilliseconds(150);$v.Timer.Add_Tick({Complete-MCTempWindowWorker $v}.GetNewClosure());$v.Timer.Start();Start-MCTempWindowWorker $v 'Scan';$v
}
function Update-MCTempWindow {
    param($V)
    $review=$V.Plan-and$V.Plan.Stage-eq'Review';$confirm=$V.Plan-and$V.Plan.Stage-eq'Confirm'
    $V.UI.TempFiles.IsReadOnly=$V.Busy-or-not$review;$V.UI.TempSelectAll.IsEnabled=-not$V.Busy-and$review
    $V.UI.TempNext.IsEnabled=-not$V.Busy-and$review-and$V.Rows.Count-gt0;$V.UI.TempRun.IsEnabled=-not$V.Busy-and$confirm-and[bool]$V.UI.TempAck.IsChecked
    $V.UI.TempAck.Visibility=if($confirm){'Visible'}else{'Collapsed'};$V.UI.TempAck.IsEnabled=-not$V.Busy
    $V.UI.TempBack.IsEnabled=-not$V.Busy;$V.UI.TempClose.IsEnabled=-not$V.Busy;$V.UI.TempStop.IsEnabled=$V.Busy
    $V.UI.TempStage.Text=if($V.Busy){'Đang '+$(if($V.Action-eq'Scan'){'quét và kiểm tra file'}else{'dọn Temp'})}elseif($review){'Bước 1 · Chọn file sau khi đọc tác động'}elseif($confirm){'Bước 2 · '+$V.Plan.Items.Count+' file đã được duyệt'}else{'Đã kết thúc / chưa có kế hoạch xóa hợp lệ'}
}
function Start-MCTempWindowWorker {
    param($V,[ValidateSet('Scan','Run')][string]$Action)
    if($V.Busy){return};$V.Busy=$true;$V.Action=$Action;$V.Result=$null;$V.Token=New-Object Threading.CancellationTokenSource;$V.Events=New-Object 'Collections.Concurrent.ConcurrentQueue[object]';$V.Watch=[Diagnostics.Stopwatch]::StartNew();$V.UI.TempProgress.IsIndeterminate=$true;Update-MCTempWindow $V
    try{$V.Worker=[PowerShell]::Create();$id=if($V.Plan){$V.Plan.Id}else{''}
        $V.Worker.AddScript('param($root,$action,$level,$id,$context,$token,$events,$paths); Import-Module (Join-Path $root "app\CleanData\TempCleanup.psm1") -DisableNameChecking; if($action-eq"Scan"){New-MCTempPlan -Level $level -Context $context -CancellationToken $token -CandidatePaths $paths}else{Invoke-MCTempPlan -Id $id -Context $context -CancellationToken $token -Events $events}').AddArgument($V.Root).AddArgument($Action).AddArgument($V.Level).AddArgument($id).AddArgument($V.Context).AddArgument($V.Token.Token).AddArgument($V.Events).AddArgument($V.CandidatePaths)|Out-Null;$V.Async=$V.Worker.BeginInvoke()
    }catch{$V.Busy=$false;if($V.Worker){$V.Worker.Dispose();$V.Worker=$null};$V.Token.Dispose();$V.Token=$null;$V.UI.TempProgress.IsIndeterminate=$false;Update-MCTempWindow $V;$V.UI.TempStatus.Text=$_.Exception.Message}
}
function Complete-MCTempWindowWorker {
    param($V)
    if(-not$V.Busy-or-not$V.Async){return};$e=$null
    while($V.Events.TryDequeue([ref]$e)){$V.UI.TempProgress.IsIndeterminate=$false;$V.UI.TempProgress.Maximum=$e.Total;$V.UI.TempProgress.Value=$e.Completed;$V.UI.TempStatus.Text=('{0}/{1} · {2} · {3:N1}s · {4}'-f$e.Completed,$e.Total,$e.Status,$e.Seconds,[IO.Path]::GetFileName($e.Path))}
    if(-not$V.Async.IsCompleted){$V.UI.TempStage.Text=('{0} · {1:N1}s'-f$V.Action,$V.Watch.Elapsed.TotalSeconds);return};$message=''
    try{$out=@($V.Worker.EndInvoke($V.Async));if($V.Worker.Streams.Error.Count){throw ($V.Worker.Streams.Error|Out-String)};if(-not$out.Count){throw 'Không có kết quả xác minh.'};$V.Result=$out[-1]
        if($V.Action-eq'Scan'){$V.Plan=$V.Result;$rows=New-Object 'System.Collections.Generic.List[object]';foreach($i in $V.Plan.Items){$rows.Add([pscustomobject]@{Id=$i.Id;Name=$i.Name;Path=$i.Path;MB=$i.MB;AgeDays=$i.AgeDays;Effect=$i.Effect;Selected=$false})};$V.Rows=$rows.ToArray();$V.UI.TempFiles.ItemsSource=$V.Rows;$V.UI.TempScope.Text=$V.Plan.Root+' · ≥'+$V.Plan.Days+' ngày';$message=('{0} ứng viên; {1} mục giữ lại. '-f$V.Rows.Count,$V.Plan.Skipped)+$(if($V.Plan.Partial){'Kết quả một phần; có giới hạn.'}else{'Quét xong.'})+' Chưa xóa file.'}
        else{$r=$V.Result;$V.Plan=Get-MCTempPlan $V.Plan.Id
            foreach($row in $V.Rows){$match=@($r.Items|Where-Object{$_.Path-eq$row.Path});if($match.Count){$row.Selected=$false;$row.Effect=$match[0].Status+' · '+$(if($match[0].Error){$match[0].Error}else{'Đã xác minh kết quả native.'})}else{$row.Effect='Chưa xử lý · file được giữ lại.'}};$V.UI.TempFiles.Items.Refresh()
            $message=('{0} · {1}/{2} file xử lý · {3:N1}s · kết thúc {4:HH:mm:ss} · allocated của file đã xóa {5:N2} MB (không phải free-disk đo được). Nhật ký: {6}'-f$r.Status,$r.Processed,$r.Total,$r.Seconds,$r.Finished,($r.KnownAllocatedBytes/1MB),$r.Journal)}
    }catch{$message=if($V.Token.IsCancellationRequested){'Đã dừng. Không tự chạy lại; các file chưa xử lý giữ nguyên.'}else{'Chưa thực hiện hoặc kết quả chưa xác minh: '+$_.Exception.Message}}
    finally{$V.Watch.Stop();$V.Busy=$false;$V.Worker.Dispose();$V.Worker=$null;$V.Token.Dispose();$V.Token=$null;$V.Async=$null;$V.UI.TempProgress.IsIndeterminate=$false;Update-MCTempWindow $V;$V.UI.TempStatus.Text=$message}
}
function Show-MCTempCleanup {
    if($operation-or$diskRunning){return};$v=$null
    try{$script:diskModalActive=$true;Set-MCOperationState $true;$level=if($diskUI.DiskLevel3.IsChecked){3}elseif($diskUI.DiskLevel2.IsChecked){2}else{1};$v=New-MCTempWindow $level;$v.Window.Owner=$window;$v.Window.ShowDialog()|Out-Null;$diskUI.DiskStatus.Text=if($v.Result-and$v.Action-eq'Run'){'Dọn Temp: '+$v.Result.Status+'; xem nhật ký trong .data.'}else{'Đã đóng dọn Temp. Không tự xóa từ danh sách scanner.'}}
    catch{$diskUI.DiskStatus.Text=$_.Exception.Message}finally{$script:diskModalActive=$false;Set-MCOperationState $false}
}
