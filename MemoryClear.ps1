#requires -version 5.1
param([switch]$SmokeTest,[switch]$ControlsOnly)
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This version requires Windows 10/11.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Launch with powershell.exe -STA -File MemoryClear.ps1, or use Start-MemoryClear.cmd.' }
if(-not$SmokeTest){Write-Host ('MemoryClear: loading PowerShell GUI from '+$PSScriptRoot)}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Import-Module (Join-Path $PSScriptRoot 'app\MemoryClear.Core.psm1') -Force
$reader=New-Object Xml.XmlNodeReader ([xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'app\MainWindow.xaml') -Raw -Encoding UTF8))
$script:window=[Windows.Markup.XamlReader]::Load($reader)
$script:ui=@{}
foreach($name in @('ClearMemory','StrongClear','ClearProgress','ClearState','ClearElapsed','RamLabel','CpuLabel','CommitLabel','RamBar','CpuBar','Search','ActionableOnly','Refresh','Processes','CloseSelected','KillSelected','Protect','AllowClose','Details','TargetGB','Emergency','CancelOperation','Status','SelectionLabel')){$script:ui[$name]=$window.FindName($name);if(-not$ui[$name]){throw "Missing control: $name"}}
$script:snapshot=$null;$script:job=$null;$script:async=$null;$script:jobKind='';$script:queue=@();$script:operation=$false;$script:targetBytes=0;$script:nextScan=[DateTime]::MinValue;$script:cancelled=$false
$script:clearRequested=$false;$script:clearCancellation=$null;$script:lastForegroundPid=[MemoryClear.Native]::ForegroundProcessId()
$script:clearMode='Normal';$script:clearWatch=$null;$script:clearRunning=$false;$script:clearProgressQueue=$null
function Update-MCClearProgress {
    if(-not$clearRunning){return}
    $ui.ClearElapsed.Text=('{0:N0}s đã chạy'-f$clearWatch.Elapsed.TotalSeconds)
    $event=$null
    if($null-ne$clearProgressQueue){while($clearProgressQueue.TryDequeue([ref]$event)){
        $ui.Status.Text=$event.Message
        if($event.Stage-eq'Processing'-and$event.Total-gt0){
            $ui.ClearProgress.IsIndeterminate=$false;$ui.ClearProgress.Maximum=$event.Total;$ui.ClearProgress.Value=$event.Processed
            $ui.ClearState.Text="Clear · Đang xử lý $($event.Processed)/$($event.Total) process"
        }elseif($event.Stage-eq'Scanning'){$ui.ClearState.Text='Clear · Đang quét RAM/CPU';$ui.ClearProgress.IsIndeterminate=$true}
    }}
    if($cancelled){$ui.ClearState.Text='Clear · Đang dừng các bước tiếp theo...'}
}
function Complete-MCClearUI {
    param($Result)
    Update-MCClearProgress
    $script:clearRunning=$false;if($clearWatch){$clearWatch.Stop()}
    $ui.ClearProgress.IsIndeterminate=$false
    $ui.ClearMemory.Content='Clear';Set-MCOperationState $false
    $clock=[DateTime]::Now.ToString('HH:mm:ss');$modeLabel=if($clearMode-eq'Strong'){'Mạnh hơn'}else{'Thường'}
    $ui.ClearElapsed.Text=if($clearWatch){('{0:N1}s · {1}'-f$clearWatch.Elapsed.TotalSeconds,$modeLabel)}else{$modeLabel}
    $ui.ClearState.Foreground=[Windows.Media.Brushes]::DarkGreen
    if($Result.Status-eq'Error'){$ui.ClearState.Text="Clear · Lỗi lúc $clock";$ui.ClearState.Foreground=[Windows.Media.Brushes]::Firebrick}
    elseif($Result.Status-eq'Cancelled'){$ui.ClearState.Text="Clear · Đã dừng lúc $clock";$ui.ClearState.Foreground=[Windows.Media.Brushes]::DarkGoldenrod}
    elseif($Result.Status-eq'TimeLimit'){$ui.ClearState.Text="Clear · Đã dừng: hết thời gian ($clock)";$ui.ClearState.Foreground=[Windows.Media.Brushes]::DarkGoldenrod}
    elseif($Result.Status-eq'Cooldown'){$ui.ClearState.Text='Clear · Chưa chạy: đang trong khoảng nghỉ';$ui.ClearState.Foreground=[Windows.Media.Brushes]::DarkGoldenrod;$ui.ClearProgress.Value=0}
    else{$ui.ClearState.Text="Clear · Hoàn tất lúc $clock";$ui.ClearProgress.Maximum=100;$ui.ClearProgress.Value=100}
    $ui.Status.Text=$Result.Message
}
function Update-MCView {
    if(-not$snapshot){return}
    $selected=@($ui.Processes.SelectedItems | ForEach-Object{"$($_.Pid)/$($_.StartTicks)"})
    $sorts=@();if($null-ne$ui.Processes.ItemsSource){$sorts=@([Windows.Data.CollectionViewSource]::GetDefaultView($ui.Processes.ItemsSource).SortDescriptions)}
    $query=$ui.Search.Text.Trim();$rows=[MemoryClear.ProcessRow[]]@($snapshot.Rows | Where-Object{(-not$query -or $_.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase)-ge0 -or ([string]$_.Pid).Contains($query) -or ($_.Path -and $_.Path.IndexOf($query,[StringComparison]::OrdinalIgnoreCase)-ge0))-and(-not$ui.ActionableOnly.IsChecked-or$_.Allowed)})
    $ui.Processes.ItemsSource=$rows
    $view=[Windows.Data.CollectionViewSource]::GetDefaultView($rows);if($sorts.Count){$view.SortDescriptions.Clear();foreach($sort in $sorts){$view.SortDescriptions.Add($sort)}}
    foreach($row in $rows){if($selected -contains "$($row.Pid)/$($row.StartTicks)"){$ui.Processes.SelectedItems.Add($row.PSObject.BaseObject)|Out-Null}}
    $ui.RamLabel.Text=('{0:N2} / {1:N1} GB' -f ($snapshot.System.AvailableBytes/1GB),($snapshot.System.TotalBytes/1GB))
    $ui.CommitLabel.Text=('{0:N1} / {1:N1} GB' -f ($snapshot.System.CommitBytes/1GB),($snapshot.System.CommitLimitBytes/1GB))
    $ui.RamBar.Value=100*(1-$snapshot.System.AvailableBytes/[double]$snapshot.System.TotalBytes)
    if($null-ne$snapshot.Cpu){$ui.CpuLabel.Text="$($snapshot.Cpu)%";$ui.CpuBar.Value=$snapshot.Cpu}
}
function Set-MCOperationState {
    param([bool]$Active)
    $script:operation=$Active
    foreach($name in @('ClearMemory','StrongClear','CloseSelected','KillSelected','Protect','AllowClose','Emergency')){$ui[$name].IsEnabled=-not$Active}
    $ui.CancelOperation.IsEnabled=$Active
}
function Show-MCMessage {param([string]$Text);[Windows.MessageBox]::Show($window,$Text,'MemoryClear',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Information)|Out-Null}
function Start-MCQueue {
    param([object[]]$Rows,[string]$Action,[double]$Target=0)
    if($operation){return}
    if(@($Rows).Count-eq0){Show-MCMessage 'Không có process hợp lệ được chọn.';return}
    $blocked=@($Rows|Where-Object{-not$_.Allowed});if($blocked.Count){Show-MCMessage ('Có process được bảo vệ: '+(($blocked|ForEach-Object{"$($_.Name) [$($_.Pid)]: $($_.Policy)"})-join"`n"));return}
    $names=($Rows|ForEach-Object{"$($_.Name) — PID $($_.Pid)`n$($_.Path)"})-join"`n`n"
    $warning=if($Action-eq'Kill'){'Force kill có thể làm mất dữ liệu chưa lưu. Chỉ process được liệt kê sẽ bị kết thúc; không kill cả cây.'}else{'Gửi yêu cầu đóng bình thường. App có thể hiện hộp thoại lưu. Không tự force kill sau timeout.'}
    if([Windows.MessageBox]::Show($window,"$warning`n`n$names`n`nTiếp tục?",'Xác nhận '+$Action,[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)-ne[Windows.MessageBoxResult]::Yes){return}
    $script:queue=@($Rows|ForEach-Object{[pscustomobject]@{Pid=$_.Pid;StartTicks=$_.StartTicks;Action=$Action}});$script:targetBytes=$Target;$script:cancelled=$false
    Set-MCOperationState $true;$ui.Status.Text="Đã xác nhận $($queue.Count) process. Kiểm tra lại từng mục trước khi thao tác."
}
function Start-MCWorker {
    param([string]$Kind,$Item)
    $script:job=[PowerShell]::Create();$job.RunspacePool=$script:pool;$script:jobKind=$Kind
    if($Kind-eq'Scan'){$job.AddScript('param($root,$previous); Import-Module (Join-Path $root "app\MemoryClear.Core.psm1"); Get-MCSnapshot -Previous $previous').AddArgument($PSScriptRoot).AddArgument($snapshot)|Out-Null}
    elseif($Kind-eq'Clear'){$job.AddScript('param($root,$previous,$excluded,$token,$mode,$progress); Import-Module (Join-Path $root "app\MemoryClear.Clear.psm1"); Invoke-MCClear -Previous $previous -ExcludedIds $excluded -CancellationToken $token -Mode $mode -ProgressQueue $progress').AddArgument($PSScriptRoot).AddArgument($snapshot).AddArgument([int[]]@($PID,$lastForegroundPid)).AddArgument($clearCancellation.Token).AddArgument($clearMode).AddArgument($clearProgressQueue)|Out-Null}
    else{$job.AddScript('param($root,$item); Import-Module (Join-Path $root "app\MemoryClear.Core.psm1"); Invoke-MCAction -ProcessId $item.Pid -StartTicks $item.StartTicks -Action $item.Action -Confirm:$false').AddArgument($PSScriptRoot).AddArgument($Item)|Out-Null}
    $script:async=$job.BeginInvoke()
}
function Start-MCOneClickClear {
    if($operation){return}
    $script:clearMode=if($ui.StrongClear.IsChecked){'Strong'}else{'Normal'}
    $script:clearWatch=[Diagnostics.Stopwatch]::StartNew();$script:clearProgressQueue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]';$script:clearRunning=$true
    $script:clearCancellation=New-Object Threading.CancellationTokenSource
    $script:clearRequested=$true;$script:cancelled=$false;$script:targetBytes=0
    Set-MCOperationState $true
    $ui.ClearMemory.Content='Đang Clear...';$ui.ClearState.Text=if($job){'Clear · Chờ lượt quét hiện tại...'}else{'Clear · Đang chuẩn bị...'};$ui.ClearState.Foreground=[Windows.Media.Brushes]::DarkGreen
    $ui.ClearElapsed.Text='0s đã chạy';$ui.ClearProgress.Value=0;$ui.ClearProgress.IsIndeterminate=$true
    $ui.Status.Text='Clear đang kiểm tra process ít hoạt động. Giữ nguyên app và dữ liệu; không cần chọn dòng.'
    if(-not$job){$script:clearRequested=$false;Start-MCWorker 'Clear' $null}
}
$ui.ClearMemory.Add_Click({Start-MCOneClickClear})
$ui.Search.Add_TextChanged({Update-MCView});$ui.ActionableOnly.Add_Click({Update-MCView});$ui.Refresh.Add_Click({$script:nextScan=[DateTime]::MinValue})
function Find-MCCheckbox {
    param($Element)
    while($Element-and$Element-isnot[Windows.Controls.CheckBox]){
        if($Element-is[Windows.Media.Visual]){$Element=[Windows.Media.VisualTreeHelper]::GetParent($Element)}else{$Element=[Windows.LogicalTreeHelper]::GetParent($Element)}
    }
    return $Element
}
$ui.Processes.AddHandler([Windows.Input.Mouse]::PreviewMouseDownEvent,[Windows.Input.MouseButtonEventHandler]{
    param($sender,$eventArgs)
    $checkbox=Find-MCCheckbox $eventArgs.OriginalSource
    if($checkbox-and$checkbox.Tag-eq'MCSelect'-and$eventArgs.ChangedButton-eq[Windows.Input.MouseButton]::Left){
        $checkbox.SetCurrentValue([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty,(-not[bool]$checkbox.IsChecked))
        $binding=$checkbox.GetBindingExpression([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty);if($binding){$binding.UpdateSource()}
        $eventArgs.Handled=$true
    }
})
$ui.Processes.Add_SelectionChanged({$ui.SelectionLabel.Text="Đã chọn $($ui.Processes.SelectedItems.Count) process. RAM là working set; CPU chuẩn hóa theo toàn máy."})
$ui.CloseSelected.Add_Click({Start-MCQueue @($ui.Processes.SelectedItems) 'Close'})
$ui.KillSelected.Add_Click({Start-MCQueue @($ui.Processes.SelectedItems) 'Kill'})
$ui.CancelOperation.Add_Click({$pendingClear=$clearRequested;$script:queue=@();$script:clearRequested=$false;$script:cancelled=$true;if($clearCancellation){$clearCancellation.Cancel()};$ui.Status.Text='Đã yêu cầu dừng các bước tiếp theo. Thao tác đã gửi không thể hoàn tác.';if($pendingClear){Complete-MCClearUI ([pscustomobject]@{Status='Cancelled';Message='Đã hủy Clear trước khi bắt đầu; chưa trim process nào.'});$clearCancellation.Dispose();$script:clearCancellation=$null}elseif($clearRunning){$ui.ClearState.Text='Clear · Đang dừng các bước tiếp theo...'};if(-not$job){Set-MCOperationState $false}})
$ui.Details.Add_Click({$row=$ui.Processes.SelectedItem;if($row){Show-MCMessage ("$($row.Name) · PID $($row.Pid)`nStart ticks: $($row.StartTicks)`nExecutable: $($row.Path)`n$($row.Policy)`nRAM: $($row.RamMB) MB · Private: $($row.PrivateMB) MB`nUser SID: $($row.Identity.Sid) · Session: $($row.Identity.Session)")}})
function Toggle-MCPath {
    param([string]$Property)
    try{$rows=@($ui.Processes.SelectedItems);if(-not$rows.Count){return};$settings=Get-MCSettings
      foreach($row in $rows){if(-not$row.Path){throw 'Không xác minh được executable.'};if($Property-eq'AllowClosePaths'-and-not$row.Allowed){throw ('Process bị bảo vệ: '+$row.Policy)}
        if(@($settings.$Property)-contains$row.Path){$settings.$Property=@($settings.$Property|Where-Object{$_-ne$row.Path})}else{$settings.$Property=@($settings.$Property)+@($row.Path)}
      };Save-MCSettings $settings;$script:nextScan=[DateTime]::MinValue;$ui.Status.Text='Đã cập nhật quy tắc theo đường dẫn executable. Quy tắc chặn hệ thống luôn ưu tiên.'
    }catch{Show-MCMessage $_.Exception.Message}
}
$ui.Protect.Add_Click({Toggle-MCPath 'ProtectedPaths'});$ui.AllowClose.Add_Click({Toggle-MCPath 'AllowClosePaths'})
$ui.Processes.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent,[Windows.RoutedEventHandler]{
    param($sender,$eventArgs)
    $checkbox=$eventArgs.OriginalSource
    if($checkbox-isnot[Windows.Controls.CheckBox]-or$checkbox.Tag-ne'MCAllowClose'){return}
    $eventArgs.Handled=$true;$row=$checkbox.DataContext
    try{
        if($operation){throw 'Đang xử lý danh sách; hãy chờ hoặc dừng các bước tiếp theo trước khi đổi quyền.'}
        $permission=Set-MCAllowClosePermission -ProcessId $row.Pid -StartTicks $row.StartTicks -Enabled ([bool]$checkbox.IsChecked)
        foreach($item in $snapshot.Rows){if([string]::Equals($item.Path,$permission.Path,[StringComparison]::OrdinalIgnoreCase)){$item.AllowClose=$permission.Enabled-and$item.Allowed}}
        Update-MCView;$script:nextScan=[DateTime]::MinValue
        $ui.Status.Text=if($permission.Enabled){'Đã cho phép executable này đóng khẩn cấp. Chưa đóng process nào.'}else{'Đã bỏ executable này khỏi danh sách đóng khẩn cấp.'}
    }catch{$checkbox.IsChecked=$row.AllowClose;Show-MCMessage $_.Exception.Message}
})
$ui.Emergency.Add_Click({try{if(-not$snapshot){return};$target=0.0;if(-not[double]::TryParse($ui.TargetGB.Text,[ref]$target)-or$target-le0-or$target-ge($snapshot.System.TotalBytes/1GB)){throw 'Mục tiêu phải lớn hơn 0 và nhỏ hơn tổng RAM (GB).'}
    if($snapshot.System.AvailableBytes-ge($target*1GB)){Show-MCMessage 'RAM khả dụng đã đạt mục tiêu.';return}
    $rows=@($snapshot.Rows|Where-Object{$_.Allowed-and$_.AllowClose});if(-not$rows.Count){throw 'Chưa có ứng viên. Chọn process và bấm Cho phép đóng khẩn cấp trước.'};Start-MCQueue $rows 'Close' ($target*1GB)
  }catch{Show-MCMessage $_.Exception.Message}})
if($SmokeTest-and$ControlsOnly){return}
if($SmokeTest){
    $script:pool=[RunspaceFactory]::CreateRunspacePool(1,1);$pool.Open()
    try{Start-MCWorker 'Scan' $null;$workerResult=@($job.EndInvoke($async));if($job.Streams.Error.Count){throw ($job.Streams.Error|Out-String)};$script:snapshot=$workerResult[-1]}finally{if($job){$job.Dispose();$script:job=$null};$pool.Close();$pool.Dispose()}
    Start-Sleep -Milliseconds 500;$script:snapshot=Get-MCSnapshot $snapshot;Update-MCView;$ui.Status.Text="Đã đọc $($snapshot.Rows.Count) process. Chế độ thủ công; chưa thực hiện thao tác đóng/kill."
    $testView=[Windows.Data.CollectionViewSource]::GetDefaultView($ui.Processes.ItemsSource);$testView.SortDescriptions.Add([ComponentModel.SortDescription]::new('RamMB',[ComponentModel.ListSortDirection]::Descending))
    $selfRow=$snapshot.Rows|Where-Object{$_.Pid-eq$PID};if(-not$selfRow){throw 'Smoke selection fixture missing.'};$ui.Processes.SelectedItems.Add($selfRow.PSObject.BaseObject)|Out-Null
    Update-MCView;$testView=[Windows.Data.CollectionViewSource]::GetDefaultView($ui.Processes.ItemsSource)
    $sortPreserved=$testView.SortDescriptions.Count-eq1;$selectionPreserved=@($ui.Processes.SelectedItems|Where-Object{$_.Pid-eq$PID}).Count-eq1
    if(-not$sortPreserved-or-not$selectionPreserved){throw "Refresh state mismatch: sort=$sortPreserved ($($testView.SortDescriptions.Count)); selection=$selectionPreserved ($($ui.Processes.SelectedItems.Count))."}
    $previewDir=Join-Path $PSScriptRoot 'artifacts';New-Item -ItemType Directory -Path $previewDir -Force|Out-Null
    $content=$window.Content;$content.Measure([Windows.Size]::new(1072,684));$content.Arrange([Windows.Rect]::new(0,0,1072,684));$content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1072,684,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $previewDir 'gui-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    [pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Controls=$ui.Count;Rows=$ui.Processes.Items.Count;BackgroundWorkerPassed=$true;SortPreserved=$sortPreserved;SelectionPreserved=$selectionPreserved;WorkingSetMB=[Math]::Round([Diagnostics.Process]::GetCurrentProcess().WorkingSet64/1MB,1);Mode='Offscreen WPF layout; no real window or action shown'}|ConvertTo-Json|Set-Content (Join-Path $previewDir 'gui-smoke.json') -Encoding UTF8
    Write-Output "WPF_SMOKE_PASS controls=$($ui.Count) rows=$($ui.Processes.Items.Count)";$window.Close();return
}
$script:pool=[RunspaceFactory]::CreateRunspacePool(1,1);$pool.Open()
$script:timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({try{
    Update-MCClearProgress
    $foreground=[MemoryClear.Native]::ForegroundProcessId();if($foreground-gt0-and$foreground-ne$PID){$script:lastForegroundPid=$foreground}
    if($job){if(-not$async.IsCompleted){return};$output=@($job.EndInvoke($async));if($job.Streams.Error.Count){throw ($job.Streams.Error|Out-String)}
      if($jobKind-eq'Scan'){$script:snapshot=$output[-1];Update-MCView;if($ui.Status.Text.StartsWith('Đang khởi tạo')){$ui.Status.Text="Đã đọc $($snapshot.Rows.Count) process. Chế độ thủ công; chưa thực hiện thao tác đóng/kill."};$seconds=if($window.WindowState-eq'Minimized'){10}else{$snapshot.Settings.RefreshSeconds};$script:nextScan=[DateTime]::UtcNow.AddSeconds($seconds)}
      elseif($jobKind-eq'Clear'){$result=if($output.Count){$output[-1]}else{[pscustomobject]@{Status='Error';Message='Clear không trả kết quả; chưa xác minh thu hồi RAM.'}};Complete-MCClearUI $result;$script:nextScan=[DateTime]::MinValue;if($clearCancellation){$clearCancellation.Dispose();$script:clearCancellation=$null}}
      elseif($output.Count){$result=$output[-1];$ui.Status.Text="PID $($result.Pid) · $($result.Status): $($result.Message)";$script:nextScan=[DateTime]::MinValue}
      $job.Dispose();$script:job=$null
    }
    if($clearRequested){$script:clearRequested=$false;Start-MCWorker 'Clear' $null;return}
    if($operation){if($targetBytes-gt0-and[MemoryClear.Native]::ReadSystem().AvailableBytes-ge$targetBytes){$script:queue=@();$ui.Status.Text='Đã đạt mục tiêu RAM khả dụng; dừng các bước tiếp theo.'}
      if(-not$queue.Count){Set-MCOperationState $false;if($clearCancellation){$clearCancellation.Dispose();$script:clearCancellation=$null};if(-not$cancelled){$ui.Status.Text+=' · Đã xử lý hết danh sách hoặc đạt mục tiêu.'}}
      elseif([DateTime]::UtcNow-lt$nextScan){$item=$queue[0];$script:queue=@($queue|Select-Object -Skip 1);Start-MCWorker 'Action' $item;return}
    }
    if([DateTime]::UtcNow-ge$nextScan){Start-MCWorker 'Scan' $null}
  }catch{$failure='Lỗi: '+$_.Exception.Message;if($clearRunning){Complete-MCClearUI ([pscustomobject]@{Status='Error';Message=$failure})};if($job){$job.Dispose();$script:job=$null};$script:queue=@();$script:clearRequested=$false;if($clearCancellation){$clearCancellation.Cancel();$clearCancellation.Dispose();$script:clearCancellation=$null};Set-MCOperationState $false;$ui.Status.Text=$failure;$script:nextScan=[DateTime]::UtcNow.AddSeconds(5)}})
$window.Add_Closed({$timer.Stop();if($clearCancellation){$clearCancellation.Cancel()};if($job){$job.Stop();$job.Dispose()};$pool.Close();$pool.Dispose();if($clearCancellation){$clearCancellation.Dispose()}})
$timer.Start();Write-Host 'MemoryClear: controls and background worker initialized; opening window.';[void]$window.ShowDialog()
