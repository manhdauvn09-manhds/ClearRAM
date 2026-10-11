function New-MCDiskOperationWindow {
    param($ScanResult,[object[]]$SelectedRows,[string]$BackupRoot,[string]$ContextToken='operation-window')
    Import-Module (Join-Path $PSScriptRoot 'Operations.psm1') -Global
    $reader=New-Object Xml.XmlNodeReader([xml](Get-Content (Join-Path $PSScriptRoot 'OperationView.xaml') -Raw -Encoding UTF8))
    try{$dialog=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Close()}
    $controls=@{};foreach($name in @('OperationTabs','OperationHeading','OperationSummary','OperationBackup','OperationPermanent','OperationBackupHint','OperationItems','OperationFinal','OperationAck','OperationPhraseHint','OperationPhrase','OperationJournal','OperationInspect','OperationHistoryStatus','OperationHistory','OperationRestoreAck','OperationRestore','OperationProgress','OperationStatus','OperationNext','OperationConfirm','OperationBack','OperationRun','OperationStop','OperationClose','OperationRecent','OperationRecentRuns')){$controls[$name]=$dialog.FindName($name);if(-not$controls[$name]){throw "Missing $name"}}
    $view=[pscustomobject]@{Window=$dialog;UI=$controls;Scan=$ScanResult;Selection=$SelectedRows;BackupRoot=$BackupRoot;Context=$ContextToken;Plan=$null;Rows=@();Worker=$null;Async=$null;Token=$null;Events=$null;Timer=$null;Watch=$null;Action='';Busy=$false;Result=$null;ModulePath=(Join-Path $PSScriptRoot 'Operations.psm1')}
    $dialog.Tag=$view
    Reset-MCOperationWindowPlan $view
    foreach($name in @('OperationBackup','OperationPermanent')){$controls[$name].Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Reset-MCOperationWindowPlan $v})}
    $controls.OperationNext.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;try{$v.UI.OperationItems.CommitEdit()|Out-Null;$ids=@($v.Rows|Where-Object{$_.Reviewed}|ForEach-Object{$_.Id});$v.Plan=Move-MCDiskOperationReview $v.Plan.Id $v.Context $ids;Update-MCOperationWindow $v}catch{$v.UI.OperationStatus.Text=$_.Exception.Message}})
    $controls.OperationConfirm.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;try{$v.Plan=Confirm-MCDiskOperation $v.Plan.Id $v.Context -Acknowledged ([bool]$v.UI.OperationAck.IsChecked) -Phrase $v.UI.OperationPhrase.Text;Update-MCOperationWindow $v}catch{$v.UI.OperationStatus.Text=$_.Exception.Message}})
    $controls.OperationBack.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Reset-MCDiskOperation $v.Plan.Id;foreach($r in $v.Rows){$r.Reviewed=$false};$v.UI.OperationAck.IsChecked=$false;$v.UI.OperationPhrase.Text='';Update-MCOperationWindow $v})
    $controls.OperationRun.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Start-MCOperationWindowWorker $v 'Run'})
    $controls.OperationStop.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;if($v.Token){$v.Token.Cancel();$v.UI.OperationStatus.Text='Đang dừng tại ranh giới an toàn; bản sao chưa hoàn tất có thể còn lại.'}})
    $controls.OperationInspect.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Start-MCOperationWindowWorker $v 'Inspect'})
    $controls.OperationRecent.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Start-MCOperationWindowWorker $v 'History'})
    $controls.OperationRecentRuns.Add_SelectionChanged({$v=[Windows.Window]::GetWindow($this).Tag;if($v.UI.OperationRecentRuns.SelectedItem){$v.UI.OperationJournal.Text=$v.UI.OperationRecentRuns.SelectedItem.Path;$v.UI.OperationHistory.ItemsSource=$null;$v.UI.OperationRestoreAck.IsChecked=$false;$v.UI.OperationHistoryStatus.Text='Nhật ký được chọn chưa kiểm tra; bấm Kiểm tra nhật ký.';Update-MCOperationWindow $v}})
    $controls.OperationRestore.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;if($v.UI.OperationRestoreAck.IsChecked-and$v.UI.OperationHistory.SelectedItem-and$v.UI.OperationHistory.SelectedItem.CanRestore){Start-MCOperationWindowWorker $v 'Restore'}})
    $controls.OperationHistory.Add_SelectionChanged({$v=[Windows.Window]::GetWindow($this).Tag;Update-MCOperationWindow $v})
    $controls.OperationRestoreAck.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Update-MCOperationWindow $v})
    $controls.OperationClose.Add_Click({[Windows.Window]::GetWindow($this).Close()})
    # DispatcherTimer does not expose Tag; closure retains the exact view instance.
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(150);$view.Timer=$timer
    $tick={Complete-MCOperationWindowWorker $view}.GetNewClosure();$timer.Add_Tick($tick);$timer.Start()
    $dialog.Add_Closing({param($sender,$e);$v=$sender.Tag;if($v.Busy){$e.Cancel=$true;$v.Token.Cancel();$v.UI.OperationStatus.Text='Đang dừng. Đợi worker kết thúc trước khi đóng để giữ bằng chứng.'}})
    $dialog.Add_Closed({$v=$this.Tag;$v.Timer.Stop();if($v.Plan){Close-MCDiskOperation $v.Plan.Id};if($v.Worker){$v.Worker.Dispose()};if($v.Token){$v.Token.Dispose()}})
    $view
}
function Reset-MCOperationWindowPlan {
    param($View)
    if($View.Busy){return};if($View.Plan){Close-MCDiskOperation $View.Plan.Id}
    $mode=if($View.UI.OperationPermanent.IsChecked){'Permanent'}else{'Backup'}
    $View.Plan=New-MCDiskOperation $View.Scan $View.Selection -Mode $mode -BackupRoot $View.BackupRoot -ContextToken $View.Context
    $labels=@{Safe='An toàn';Review='Cần duyệt';Danger='Nguy hiểm';Blocked='Bị chặn'}
    $View.Rows=@($View.Plan.Items|ForEach-Object{[pscustomobject]@{Id=$_.Id;Name=$_.Name;Path=$_.Path;Risk=$_.Risk;RiskLabel=$labels[$_.Risk];Effect=$_.Effect;Reviewed=$false;CanReview=$_.Risk-in@('Review','Danger')}})
    $View.UI.OperationItems.ItemsSource=$View.Rows;$View.UI.OperationAck.IsChecked=$false;$View.UI.OperationPhrase.Text=''
    Update-MCOperationWindow $View
}
function Update-MCOperationWindow {
    param($View)
    if($View.Plan){$View.Plan=Get-MCDiskOperation $View.Plan.Id};$p=$View.Plan;$ui=$View.UI
    $ui.OperationSummary.Text=('{0} mục · {1} file mẫu đủ điều kiện · phiên hết hạn {2:HH:mm:ss}'-f$p.Items.Count,$p.EligibleCount,$p.ExpiresUtc.ToLocalTime())
    $ui.OperationBackupHint.Text=if($p.Mode-eq'Backup'){'Backup cùng ổ: chưa thu hồi chỗ; có phục hồi'}else{'Xóa vĩnh viễn: không Undo'}
    foreach($r in $View.Rows){$r.CanReview=-not$View.Busy-and$p.Stage-eq'Review'-and$r.Risk-in@('Review','Danger')};$ui.OperationItems.Items.Refresh()
    $ui.OperationFinal.Visibility=if($p.Stage-eq'Confirm'){'Visible'}else{'Collapsed'}
    $danger=@($p.Items|Where-Object{$_.Risk-eq'Danger'}).Count-gt0;$ui.OperationPhrase.Visibility=if($danger){'Visible'}else{'Collapsed'};$ui.OperationPhraseHint.Text=if($danger){'Gõ đúng: '+$p.Phrase}else{'Chỉ cần xác nhận hậu quả của log mẫu; không có phrase nguy hiểm.'}
    foreach($name in @('OperationBackup','OperationPermanent','OperationInspect','OperationJournal','OperationHistory','OperationRestoreAck','OperationRecent','OperationRecentRuns')){$ui[$name].IsEnabled=-not$View.Busy}
    $ui.OperationNext.IsEnabled=-not$View.Busy-and$p.Stage-eq'Review'-and$p.EligibleCount-gt0
    $ui.OperationConfirm.IsEnabled=-not$View.Busy-and$p.Stage-eq'Confirm';$ui.OperationBack.IsEnabled=-not$View.Busy-and$p.Stage-eq'Confirm';$ui.OperationRun.IsEnabled=-not$View.Busy-and$p.Stage-eq'Approved';$ui.OperationStop.IsEnabled=$View.Busy;$ui.OperationClose.IsEnabled=-not$View.Busy
    $row=$ui.OperationHistory.SelectedItem;$ui.OperationRestore.IsEnabled=-not$View.Busy-and[bool]$ui.OperationRestoreAck.IsChecked-and$null-ne$row-and$row.CanRestore
    if(-not$View.Busy){$ui.OperationStatus.Text=if($p.Stage-eq'Approved'){'Đã duyệt đúng phạm vi. Chạy chỉ tác động file mẫu; backup mặc định giữ khả năng phục hồi.'}elseif($p.Stage-eq'Confirm'){'Bước2: xác nhận cuối sau khi đọc từng mục.'}elseif($p.Stage-eq'Review'){'Bước1: đọc tác động. Mục Safe không cần cảnh báo; mục bị chặn được giữ.'}else{'Trạng thái phiên: '+$p.Stage}}
}
function Start-MCOperationWindowWorker {
    param($View,[ValidateSet('Run','Inspect','Restore','History')][string]$Action)
    if($View.Busy){return}
    try{
        $View.Action=$Action;$View.Busy=$true;$View.Result=$null;$View.Token=New-Object Threading.CancellationTokenSource;$View.Events=New-Object 'Collections.Concurrent.ConcurrentQueue[object]';$View.Watch=[Diagnostics.Stopwatch]::StartNew();$View.Worker=[PowerShell]::Create()
        $journal=$View.UI.OperationJournal.Text;$identity=if($View.UI.OperationHistory.SelectedItem){$View.UI.OperationHistory.SelectedItem.Identity}else{''}
        $View.Worker.AddScript('param($module,$action,$id,$scope,$journal,$identity,$token,$events);Import-Module $module;if($action-eq"Run"){Invoke-MCDiskOperation $id $scope -CancellationToken $token -Events $events}elseif($action-eq"Inspect"){Read-MCDiskOperationJournal $journal -CancellationToken $token}elseif($action-eq"History"){Get-MCDiskOperationHistory -CancellationToken $token}else{Restore-MCDiskOperationItem $journal $identity -Reviewed -CancellationToken $token}').AddArgument($View.ModulePath).AddArgument($Action).AddArgument($View.Plan.Id).AddArgument($View.Context).AddArgument($journal).AddArgument($identity).AddArgument($View.Token.Token).AddArgument($View.Events)|Out-Null
        $View.UI.OperationProgress.IsIndeterminate=$true;$View.UI.OperationProgress.Value=0;Update-MCOperationWindow $View;$View.UI.OperationStatus.Text='Đang xử lý '+$Action+' · có thể dừng';$View.Async=$View.Worker.BeginInvoke()
    }catch{$View.Busy=$false;if($View.Worker){$View.Worker.Dispose();$View.Worker=$null};if($View.Token){$View.Token.Dispose();$View.Token=$null};$View.UI.OperationProgress.IsIndeterminate=$false;Update-MCOperationWindow $View;$View.UI.OperationStatus.Text=$_.Exception.Message}
}
function Complete-MCOperationWindowWorker {
    param($View)
    if(-not$View.Busy-or-not$View.Async){return}
    $e=$null;while($View.Events.TryDequeue([ref]$e)){$View.UI.OperationProgress.IsIndeterminate=$false;$View.UI.OperationProgress.Maximum=$e.Total;$View.UI.OperationProgress.Value=$e.Completed;$View.UI.OperationStatus.Text=('{0}/{1} · {2} · {3:N1}s · {4}'-f$e.Completed,$e.Total,$e.Status,$e.Seconds,[IO.Path]::GetFileName($e.Path))}
    if(-not$View.Async.IsCompleted){return};$message=''
    try{
        $output=@($View.Worker.EndInvoke($View.Async));if($View.Worker.Streams.Error.Count){throw ($View.Worker.Streams.Error|Out-String)};if(-not$output.Count){throw 'Worker returned no result.'};$View.Result=$output[-1]
        if($View.Action-eq'Run'){$r=$View.Result;$View.UI.OperationJournal.Text=$r.Journal;$message=('{0} · {1}/{2} file xử lý · {3:N1}s · kết thúc {4:HH:mm:ss} · gain metadata {5:N2} MB (không là free-disk đo được)'-f$r.Status,$r.Processed,$r.Total,$r.Seconds,$r.FinishedUtc.ToLocalTime(),($r.KnownAllocatedBytes/1MB))}
        elseif($View.Action-eq'Inspect'){$r=$View.Result;$View.UI.OperationHistory.ItemsSource=$r.Items;$View.UI.OperationHistoryStatus.Text=$r.Integrity+' · '+$r.Status+' · '+$r.VerifiedEvents+' events. '+$r.Message;$View.UI.OperationRestoreAck.IsChecked=$false;$message='Đã kiểm tra nguồn/backup tại thời điểm đọc; không tự resume xóa.'}
        elseif($View.Action-eq'History'){$View.UI.OperationRecentRuns.ItemsSource=$View.Result.Rows;$message='Nhật ký: '+$View.Result.Rows.Count+' · '+$View.Result.Status+'. Chọn một dòng và kiểm tra; không tự chạy lại.'}
        else{$message=$View.Result.Status+' · '+$View.Result.Path+' · backup giữ nguyên';$View.UI.OperationHistory.ItemsSource=$null;$View.UI.OperationRestoreAck.IsChecked=$false;$View.UI.OperationHistoryStatus.Text='Đã phục hồi; đọc lại nhật ký để kiểm trạng thái mới.'}
    }catch{$message=if($View.Token.IsCancellationRequested){'Đã dừng. Không tự chạy lại; kiểm tra nhật ký để biết mục đã xử lý.'}else{'Lỗi hoặc kết quả chưa xác minh: '+$_.Exception.Message}}
    finally{$View.Watch.Stop();$View.Busy=$false;$View.Worker.Dispose();$View.Worker=$null;$View.Token.Dispose();$View.Token=$null;$View.Async=$null;$View.UI.OperationProgress.IsIndeterminate=$false;Update-MCOperationWindow $View;$View.UI.OperationStatus.Text=$message}
}
