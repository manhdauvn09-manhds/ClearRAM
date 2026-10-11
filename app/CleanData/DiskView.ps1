. (Join-Path $PSScriptRoot 'ReviewView.ps1')
#requires -version 5.1
. (Join-Path $PSScriptRoot 'OperationView.ps1')
. (Join-Path $PSScriptRoot 'TempView.ps1')
function Initialize-MCDiskView {
    param([string]$ProjectRoot)
    $script:diskRoot=[IO.Path]::GetFullPath($ProjectRoot)

    $diskReader=New-Object Xml.XmlNodeReader ([xml](Get-Content -LiteralPath (Join-Path $diskRoot 'app\CleanData\DiskView.xaml') -Raw -Encoding UTF8))
    $script:diskView=[Windows.Markup.XamlReader]::Load($diskReader);$window.FindName('DiskHost').Content=$diskView
    $script:diskUI=@{};foreach($name in @('DiskScope','DiskLevel1','DiskLevel2','DiskLevel3','DiskSearch','DiskLarge','DiskScan','DiskStop','DiskFiles','DiskElapsed','DiskState','DiskProgress','DiskStatus','DiskDetails','DiskClean','DiskPrevious','DiskNext','DiskMinimumMB','DiskMinimumAge','DiskExtensions','DiskChooseFolder','DiskResetFolder','DiskFolderHint','DiskAnalyze','DiskAppData','DiskReview')){$script:diskUI[$name]=$diskView.FindName($name);if(-not$diskUI[$name]){throw "Missing disk control: $name"}}
    $script:diskRunning=$false;$script:diskModalActive=$false;$script:diskResult=$null;$script:diskPS=$null;$script:diskToken=$null;$script:diskWatch=$null
    foreach($name in @('DiskWindowsStorage','DiskWindowsApps','DiskTransactions')){$script:diskUI[$name]=$diskView.FindName($name);if(-not$diskUI[$name]){throw "Missing disk control: $name"}}
    $script:diskUserRoots=@()
    $diskUI.DiskWindowsStorage.Add_Click({Open-MCDiskWindowsPanel 'Storage'})
    $diskUI.DiskWindowsApps.Add_Click({Open-MCDiskWindowsPanel 'Apps'})
    $diskUI.DiskTransactions.Add_Click({Show-MCDiskTransactionExample})
    $diskUI.DiskClean.Add_Click({Show-MCTempCleanup})
    $diskUI.DiskScope.Text='Ổ Windows: '+[IO.Path]::GetPathRoot($env:SystemRoot)+' · Chỉ đọc · App data chưa rõ chủ sở hữu giữ lại'
    $diskUI.DiskSearch.Add_TextChanged({Update-MCDiskView})
    $diskUI.DiskFiles.Add_SelectionChanged({$diskUI.DiskReview.IsEnabled=-not$operation-and$null-ne$diskResult-and$diskUI.DiskFiles.SelectedItems.Count-gt0})
    $diskUI.DiskReview.Add_Click({Show-MCDiskReview})
    $diskUI.DiskAnalyze.Add_Click({Start-MCDiskOwnerAnalysis})
    $diskUI.DiskScan.Add_Click({Start-MCDiskScan});$diskUI.DiskPrevious.Add_Click({if($diskResult){Start-MCDiskScan -Offset ([Math]::Max(0,$diskResult.Offset-1000))}});$diskUI.DiskNext.Add_Click({if($diskResult){Start-MCDiskScan -Offset ($diskResult.Offset+1000)}})
    $diskUI.DiskStop.Add_Click({if($diskToken){$diskToken.Cancel();$diskUI.DiskState.Text='Đang dừng tại ranh giới file...'}})
    foreach($name in @('DiskLevel1','DiskLevel2','DiskLevel3')){$diskUI[$name].Add_Click({Reset-MCDiskPreview})}
    $diskUI.DiskAppData.Add_Click({if($diskUI.DiskAppData.IsChecked){$diskUI.DiskLarge.IsChecked=$false};Reset-MCDiskPreview})
    $diskUI.DiskLarge.Add_Click({if($diskUI.DiskLarge.IsChecked){$diskUI.DiskAppData.IsChecked=$false};Reset-MCDiskPreview})
    foreach($name in @('DiskMinimumMB','DiskMinimumAge','DiskExtensions')){$diskUI[$name].Add_TextChanged({Reset-MCDiskPreview})}
    $diskUI.DiskChooseFolder.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Chọn thư mục cá nhân trên ổ Windows để tìm file chỉ đọc';$dialog.ShowNewFolderButton=$false
        try{if($dialog.ShowDialog()-eq[Windows.Forms.DialogResult]::OK){$script:diskUserRoots=@($dialog.SelectedPath);$diskUI.DiskLarge.IsChecked=$true;$diskUI.DiskAppData.IsChecked=$false;$diskUI.DiskFolderHint.Text='Tìm chỉ đọc trong: '+$dialog.SelectedPath;Reset-MCDiskPreview}}finally{$dialog.Dispose()}
    })
    $diskUI.DiskResetFolder.Add_Click({$script:diskUserRoots=@();$diskUI.DiskFolderHint.Text='Tìm file: các thư mục cá nhân trên ổ Windows · mọi ứng viên đều cần duyệt';Reset-MCDiskPreview})
    $diskUI.DiskDetails.Add_Click({$row=$diskUI.DiskFiles.SelectedItem;if($row){$owner=if($row.PSObject.Properties['OwnerEvidence']){"`n"+$row.OwnerLabel+"`n"+$row.OwnerEvidence.Evidence}else{"`nChưa phân tích chủ sở hữu."};Show-MCMessage ("$($row.Name)`n$($row.Path)`nAllocated $($row.AllocatedMB) MB / logical $($row.LogicalMB) MB`nTuổi từ lần ghi: $($row.AgeDays) ngày`n$($row.Risk)`n$($row.Effect)`nIdentity: $($row.Identity)$owner`nChưa xóa file.")}})
    $script:diskTimer=New-Object Windows.Threading.DispatcherTimer;$diskTimer.Interval=[TimeSpan]::FromMilliseconds(250)
    $diskTimer.Add_Tick({if(-not$diskRunning){return};$diskUI.DiskElapsed.Text=('{0:N1}s'-f$diskWatch.Elapsed.TotalSeconds);if(-not$diskAsync.IsCompleted){return}
        try{$output=@($diskPS.EndInvoke($diskAsync));if($diskPS.Streams.Error.Count){throw ($diskPS.Streams.Error|Out-String)};if(-not$output.Count){throw 'Scanner không trả kết quả; chưa có số liệu.'};$script:diskResult=$output[-1];Update-MCDiskView;$stateLabels=@{CompletedReadonly='Đã quét xong · chỉ đọc';Partial='Kết quả một phần · có mục bỏ qua/giới hạn';Cancelled='Đã dừng quét';NoEligibleRoots='Không có phạm vi đủ điều kiện'};$diskUI.DiskState.Text=$stateLabels[$diskResult.Status];$diskUI.DiskStatus.Text=$diskResult.Message
        }catch{$diskUI.DiskState.Text='Lỗi quét · chưa có kết quả hợp lệ';$diskUI.DiskStatus.Text=$_.Exception.Message}
        finally{$diskWatch.Stop();$script:diskRunning=$false;$diskUI.DiskProgress.IsIndeterminate=$false;$diskUI.DiskProgress.Value=0;Set-MCDiskBusy $false;if($diskPS){$diskPS.Dispose();$script:diskPS=$null};if($diskToken){$diskToken.Dispose();$script:diskToken=$null};Set-MCOperationState $false;$script:nextScan=[DateTime]::MinValue}
    });$diskTimer.Start()
    $window.Add_Closed({$diskTimer.Stop();if($diskToken){$diskToken.Cancel()};if($diskPS){$diskPS.Stop();$diskPS.Dispose()};if($diskToken){$diskToken.Dispose()}})
}
function Set-MCDiskBusy {
    param([bool]$Busy)
    $diskUI.DiskClean.IsEnabled=-not$Busy
    foreach($name in @('DiskLevel1','DiskLevel2','DiskLevel3','DiskLarge','DiskAppData','DiskReview','DiskScan','DiskMinimumMB','DiskMinimumAge','DiskExtensions','DiskChooseFolder','DiskResetFolder','DiskWindowsStorage','DiskWindowsApps','DiskTransactions')){$diskUI[$name].IsEnabled=-not$Busy}
    foreach($name in @('DiskMinimumMB','DiskMinimumAge','DiskExtensions')){$diskUI[$name].IsEnabled=-not$Busy-and$diskUI.DiskLarge.IsChecked}
    $diskUI.DiskReview.IsEnabled=-not$Busy-and$null-ne$diskResult-and$diskUI.DiskFiles.SelectedItems.Count-gt0
    $diskUI.DiskStop.IsEnabled=$Busy;$diskUI.DiskPrevious.IsEnabled=-not$Busy-and$null-ne$diskResult-and$diskResult.Offset-gt0;$diskUI.DiskNext.IsEnabled=-not$Busy-and$null-ne$diskResult-and$diskResult.HasMore
    $diskUI.DiskAnalyze.IsEnabled=-not$Busy-and$null-ne$diskResult-and$diskResult.Rows.Count-gt0
}
function Reset-MCDiskPreview {
    $script:diskResult=$null;$diskUI.DiskFiles.ItemsSource=$null;$diskUI.DiskPrevious.IsEnabled=$false;$diskUI.DiskNext.IsEnabled=$false
    $diskUI.DiskAnalyze.IsEnabled=$false
    Set-MCDiskBusy ([bool]$operation)
    $diskUI.DiskState.Text='Phạm vi đã đổi · cần quét lại';$diskUI.DiskStatus.Text='Chưa có kế hoạch xóa. Kích thước/tuổi file không chứng minh file là rác; mọi bảo vệ giữ nguyên.'
}
function Get-MCDiskFinderOptions {
    $minimum=0;$age=0;$extensions=@();$roots=@()
    if($diskUI.DiskLarge.IsChecked){
        if(-not[int]::TryParse($diskUI.DiskMinimumMB.Text.Trim(),[ref]$minimum)-or$minimum-lt1-or$minimum-gt1048576){throw 'Dung lượng tối thiểu cần là số nguyên 1–1048576 MB.'}
        if(-not[int]::TryParse($diskUI.DiskMinimumAge.Text.Trim(),[ref]$age)-or$age-lt0-or$age-gt36500){throw 'Tuổi từ lần ghi cần là số nguyên 0–36500 ngày.'}
        $extensions=@($diskUI.DiskExtensions.Text.Trim()-split'[,;\s]+'|Where-Object{$_})
        if($extensions.Count-gt16){throw 'Chọn tối đa 16 đuôi file.'}
        foreach($ext in $extensions){if($ext-notmatch'^\.[a-zA-Z0-9]{1,12}$'){throw 'Đuôi file cần dạng .iso,.zip,.log; không dùng wildcard hoặc đường dẫn.'}}
        $roots=$diskUserRoots
    }
    [pscustomobject]@{MinimumMB=$minimum;MinimumAgeDays=$age;Extensions=$extensions;UserRoots=$roots}
}
function Open-MCDiskWindowsPanel {
    param([ValidateSet('Storage','Apps','Update')][string]$Provider)
    if($operation-or$diskRunning){return}
    try{Import-Module (Join-Path $diskRoot 'app\CleanData\WindowsProviders.psm1') -Global;$result=Open-MCWindowsCleanup $Provider;$diskUI.DiskState.Text=$result.Status+' · Windows';$diskUI.DiskStatus.Text=$result.Message}catch{$diskUI.DiskState.Text='Không mở được Windows';$diskUI.DiskStatus.Text=$_.Exception.Message}
}
function Show-MCDiskTransactionExample {
    if($operation-or$diskRunning){return};$view=$null
    try{
        $script:diskModalActive=$true;Set-MCOperationState $true
        Import-Module (Join-Path $diskRoot 'app\CleanData\MemoryClear.Disk.psm1') -Global
        $root=Join-Path $diskRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));$backup=Join-Path $diskRoot ('artifacts\disk-backup-fixture-'+[guid]::NewGuid().ToString('N'))
        foreach($r in @($root,$backup)){New-Item -ItemType Directory -Path $r|Out-Null;[IO.File]::WriteAllText((Join-Path $r '.memoryclear-fixture'),'Disposable interactive transaction example')}
        foreach($name in @('temp.tmp','old.log','save.db','keep.bin')){[IO.File]::WriteAllText((Join-Path $root $name),'Dữ liệu mẫu riêng: '+$name)}
        $scan=Get-MCDiskScan -FixtureRoots @($root);$rows=@($scan.Rows|Where-Object{$_.Name-ne'.memoryclear-fixture'})
        $view=New-MCDiskOperationWindow $scan $rows $backup;$view.Window.Owner=$window;$view.Window.ShowDialog()|Out-Null
        $diskUI.DiskStatus.Text='Đã đóng giao dịch mẫu. Mọi file tác động nằm trong artifacts riêng; xóa production vẫn khóa.'
    }catch{$diskUI.DiskStatus.Text=$_.Exception.Message}finally{if($view-and$view.Plan){Close-MCDiskOperation $view.Plan.Id};$script:diskModalActive=$false;Set-MCOperationState $false}
}
function Update-MCDiskView {
    if(-not$diskResult){return};$q=$diskUI.DiskSearch.Text.Trim()
    $diskUI.DiskFiles.ItemsSource=@($diskResult.Rows|Where-Object{$owner=if($_.PSObject.Properties['OwnerLabel']){$_.OwnerLabel}else{''};-not$q-or($_.Name+' '+$_.Path+' '+$_.Effect+' '+$owner).IndexOf($q,[StringComparison]::OrdinalIgnoreCase)-ge0}|Sort-Object -Property LogicalMB -Descending)
}
function Start-MCDiskOwnerAnalysis {
    param($FixtureInventory=$null,$FixtureDependencies=$null,[string]$FixtureHistoryDirectory='')
    if($operation-or$diskRunning-or-not$diskResult-or-not$diskResult.Rows.Count){return}
    try{
        $script:diskToken=New-Object Threading.CancellationTokenSource;$script:diskWatch=[Diagnostics.Stopwatch]::StartNew();$script:diskRunning=$true
        Set-MCOperationState $true;Set-MCDiskBusy $true;$diskUI.DiskState.Text='Đang đối chiếu ứng dụng · chỉ đọc';$diskUI.DiskProgress.IsIndeterminate=$true
        $script:diskPS=[PowerShell]::Create()
        $diskPS.AddScript('param($root,$scan,$token,$inventory,$dependencies,$historyDirectory); Import-Module (Join-Path $root "app\CleanData\MemoryClear.Disk.psm1"); Get-MCDiskOwnerAnalysis -ScanResult $scan -CancellationToken $token -FixtureInventory $inventory -FixtureDependencies $dependencies -FixtureHistoryDirectory $historyDirectory').AddArgument($diskRoot).AddArgument($diskResult).AddArgument($diskToken.Token).AddArgument($FixtureInventory).AddArgument($FixtureDependencies).AddArgument($FixtureHistoryDirectory)|Out-Null
        $script:diskAsync=$diskPS.BeginInvoke()
    }catch{
        if($diskWatch){$diskWatch.Stop()};if($diskPS){$diskPS.Dispose();$script:diskPS=$null};if($diskToken){$diskToken.Dispose();$script:diskToken=$null}
        $script:diskRunning=$false;Set-MCDiskBusy $false;Set-MCOperationState $false;$diskUI.DiskProgress.IsIndeterminate=$false;$diskUI.DiskState.Text='Không thể phân tích';$diskUI.DiskStatus.Text=$_.Exception.Message
    }
}
function Start-MCDiskScan {
    param([string[]]$FixtureRoots=@(),[int]$Offset=0)
    if($operation-or$diskRunning){$diskUI.DiskStatus.Text='Đang có operation RAM/Disk; chờ lượt hiện tại hoàn tất.';return}
    $level=if($diskUI.DiskLevel3.IsChecked){3}elseif($diskUI.DiskLevel2.IsChecked){2}else{1}
    try {
    if($diskUI.DiskAppData.IsChecked-and$diskUI.DiskLarge.IsChecked){throw 'Chọn một phạm vi quét.'}
    $options=Get-MCDiskFinderOptions
    $script:diskToken=New-Object Threading.CancellationTokenSource;$script:diskWatch=[Diagnostics.Stopwatch]::StartNew();$script:diskRunning=$true
    Set-MCOperationState $true;Set-MCDiskBusy $true;$diskUI.DiskState.Text='Đang quét chỉ đọc';$diskUI.DiskProgress.IsIndeterminate=$true
    $script:diskPS=[PowerShell]::Create()
    $diskPS.AddScript('param($root,$level,$large,$token,$fixtures,$offset,$options,$appData); Import-Module (Join-Path $root "app\CleanData\MemoryClear.Disk.psm1"); Get-MCDiskScan -Level $level -AppData:$appData -IncludeLargeFiles:$large -CancellationToken $token -FixtureRoots $fixtures -Offset $offset -MinimumMB $options.MinimumMB -MinimumAgeDays $options.MinimumAgeDays -Extensions $options.Extensions -UserRoots $options.UserRoots').AddArgument($diskRoot).AddArgument($level).AddArgument([bool]$diskUI.DiskLarge.IsChecked).AddArgument($diskToken.Token).AddArgument($FixtureRoots).AddArgument($Offset).AddArgument($options).AddArgument([bool]$diskUI.DiskAppData.IsChecked)|Out-Null
    $script:diskAsync=$diskPS.BeginInvoke()
    }catch{
        if($diskWatch){$diskWatch.Stop()};if($diskPS){$diskPS.Dispose();$script:diskPS=$null};if($diskToken){$diskToken.Dispose();$script:diskToken=$null}
        $script:diskRunning=$false;Set-MCDiskBusy $false;Set-MCOperationState $false;$diskUI.DiskProgress.IsIndeterminate=$false;$diskUI.DiskState.Text='Không thể bắt đầu quét';$diskUI.DiskStatus.Text=$_.Exception.Message
    }
}
