#requires -version 5.1
function New-MCDiskReviewWindow {
    param($ScanResult,[object[]]$Rows,[string]$ContextToken,[hashtable]$FixtureRisks=$null)
    Import-Module (Join-Path $script:diskRoot 'app\CleanData\Review.psm1') -Global
    $session=New-MCDiskReviewSession $ScanResult $Rows $ContextToken -FixtureRisks $FixtureRisks
    $reader=New-Object Xml.XmlNodeReader ([xml](Get-Content (Join-Path $script:diskRoot 'app\CleanData\ReviewView.xaml') -Raw -Encoding UTF8))
    try{$dialog=[Windows.Markup.XamlReader]::Load($reader)}catch{Close-MCDiskReview $session.SessionId;throw}
    $controls=@{};foreach($name in @('ReviewHeading','ReviewSummary','ReviewItems','ReviewFinalPanel','ReviewAcknowledge','ReviewPhraseHint','ReviewPhrase','ReviewStatus','ReviewBack','ReviewNext','ReviewConfirm','ReviewClose')){$controls[$name]=$dialog.FindName($name)}
    $labels=@{Safe='Mẫu an toàn';Review='Cần duyệt';Danger='Nguy hiểm';Blocked='Bị chặn · giữ'}
    $rowsView=@($session.Items|ForEach-Object{[pscustomobject]@{Id=$_.Id;Name=$_.Name;Path=$_.Path;Risk=$_.Risk;RiskLabel=$labels[$_.Risk];AllocatedMB=[Math]::Round($_.AllocatedBytes/1MB,2);Description=$_.Effect+' '+$_.Reason;Reviewed=$false;CanReview=($_.Risk-in@('Review','Danger'))}})
    $view=[pscustomobject]@{Window=$dialog;UI=$controls;Rows=$rowsView;SessionId=$session.SessionId;Context=$ContextToken;State=$session}
    $dialog.Tag=$view;$controls.ReviewItems.ItemsSource=$rowsView
    $controls.ReviewNext.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Invoke-MCDiskReviewWindowNext $v})
    $controls.ReviewConfirm.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Invoke-MCDiskReviewWindowConfirm $v})
    $controls.ReviewBack.Add_Click({$v=[Windows.Window]::GetWindow($this).Tag;Reset-MCDiskReview $v.SessionId;foreach($row in $v.Rows){$row.Reviewed=$false};$v.UI.ReviewAcknowledge.IsChecked=$false;$v.UI.ReviewPhrase.Text='';Update-MCDiskReviewWindow $v})
    $controls.ReviewClose.Add_Click({[Windows.Window]::GetWindow($this).Close()})
    $dialog.Add_Closed({Close-MCDiskReview $this.Tag.SessionId})
    Update-MCDiskReviewWindow $view
    return $view
}
function Update-MCDiskReviewWindow {
    param($View,[string]$Message='')
    $state=Get-MCDiskReviewState $View.SessionId;$View.State=$state;$ui=$View.UI
    $ui.ReviewHeading.Text=if($state.Stage-in@('Invalidated','Cancelled')){'Phiên duyệt hết hiệu lực · cần quét và duyệt lại'}elseif($state.Stage-eq'Confirm'){'02 · Xác nhận cuối cho danh sách đã duyệt'}elseif($state.Stage-eq'PreviewApproved'){'Đã hoàn tất duyệt thử · không có file nào bị xóa'}else{'01 · Đọc tác động của từng mục · chỉ xem trước'}
    $ui.ReviewSummary.Text=('{0} mục trong kế hoạch xem trước · {1} mục bị chặn · allocated {2:N2} MB / logical {3:N2} MB · hết hạn {4:HH:mm:ss}'-f$state.EligibleCount,$state.BlockedCount,($state.AllocatedBytes/1MB),($state.LogicalBytes/1MB),$state.ExpiresUtc.ToLocalTime())
    foreach($row in $View.Rows){$row.CanReview=$state.Stage-eq'Review'-and$row.Risk-in@('Review','Danger')};$ui.ReviewItems.Items.Refresh()
    $ui.ReviewFinalPanel.Visibility=if($state.Stage-eq'Confirm'){'Visible'}else{'Collapsed'}
    $danger=@($View.Rows|Where-Object{$_.Risk-eq'Danger'}).Count-gt0
    $ui.ReviewPhraseHint.Text=if($danger){'Gõ đúng: '+$state.Phrase}else{'Không có mục nguy hiểm cần gõ cụm từ; vẫn cần xác nhận đã đọc hậu quả.'}
    $ui.ReviewPhrase.Visibility=if($danger){'Visible'}else{'Collapsed'}
    $ui.ReviewNext.IsEnabled=$state.Stage-eq'Review'-and$state.EligibleCount-gt0
    $ui.ReviewConfirm.IsEnabled=$state.Stage-eq'Confirm'
    $ui.ReviewBack.IsEnabled=$state.Stage-eq'Confirm'
    $ui.ReviewStatus.Text=if($Message){$Message}elseif($state.Stage-eq'PreviewApproved'){'Duyệt thử hoàn tất. Đã xóa: 0 file / 0 byte. Xóa thật vẫn khóa; kết quả này không phải quyền thực thi.'}elseif(-not$state.EligibleCount){'Các mục này chưa đủ điều kiện xóa. Có thể xem lý do/tác động; không thể xác nhận để bỏ qua bảo vệ.'}else{'Chỉ mục Cần duyệt / Nguy hiểm cần đánh dấu Đã đọc. Mục bị chặn được giữ; không tính vào dung lượng dự kiến.'}
}
function Invoke-MCDiskReviewWindowNext {
    param($View)
    try{$View.UI.ReviewItems.CommitEdit()|Out-Null;$ids=@($View.Rows|Where-Object{$_.Reviewed}|ForEach-Object{$_.Id});Move-MCDiskReviewNext $View.SessionId $View.Context $ids|Out-Null;Update-MCDiskReviewWindow $View}catch{Update-MCDiskReviewWindow $View $_.Exception.Message}
}
function Invoke-MCDiskReviewWindowConfirm {
    param($View)
    try{Confirm-MCDiskReview $View.SessionId $View.Context -Acknowledge ([bool]$View.UI.ReviewAcknowledge.IsChecked) -Phrase $View.UI.ReviewPhrase.Text|Out-Null;Update-MCDiskReviewWindow $View}catch{Update-MCDiskReviewWindow $View $_.Exception.Message}
}
function Show-MCDiskReview {
    if($operation-or$diskRunning-or-not$diskResult){return}
    $selected=@($diskUI.DiskFiles.SelectedItems);if(-not$selected.Count){$diskUI.DiskStatus.Text='Chọn mục để xem phạm vi và tác động; chưa xóa.';return}
    $view=$null
    try{
        $script:diskModalActive=$true;Set-MCOperationState $true
        $context=([ordered]@{Run=$diskResult.RunId;Level1=[bool]$diskUI.DiskLevel1.IsChecked;Level2=[bool]$diskUI.DiskLevel2.IsChecked;Level3=[bool]$diskUI.DiskLevel3.IsChecked;AppData=[bool]$diskUI.DiskAppData.IsChecked;Large=[bool]$diskUI.DiskLarge.IsChecked;Minimum=$diskUI.DiskMinimumMB.Text;Age=$diskUI.DiskMinimumAge.Text;Extensions=$diskUI.DiskExtensions.Text;Roots=$diskUserRoots;Selected=@($selected.Identity|Sort-Object)}|ConvertTo-Json -Compress)
        $view=New-MCDiskReviewWindow $diskResult $selected $context;$view.Window.Owner=$window;$view.Window.ShowDialog()|Out-Null
        $diskUI.DiskStatus.Text='Đã đóng bản xem trước. Không xóa file; xác nhận của cửa sổ đã đóng không được giữ để thực thi.'
    }catch{$diskUI.DiskStatus.Text=$_.Exception.Message}
    finally{if($view){Close-MCDiskReview $view.SessionId};$script:diskModalActive=$false;Set-MCOperationState $false}
}
