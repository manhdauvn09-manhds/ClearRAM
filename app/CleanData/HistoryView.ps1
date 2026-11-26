#requires -version 5.1
# Read-only operation history window (CD-04). Uses JournalHistory.psm1; never writes or replays anything.
# Code (module, XAML) comes from this folder; -ProjectRoot only says whose .data to read.
$script:MCHistoryViewDir=$PSScriptRoot
function ConvertTo-MCHistoryRow {
    param($Run)
    $kind=if($Run.Type-eq'Temp'){'Dọn Temp'}elseif($Run.Type-eq'Memory'){'Memory mức 3'}else{'Không rõ'}
    $result=switch($Run.Status){'Completed'{'Hoàn tất'}'Partial'{'Một phần'}'Cancelled'{'Đã hủy'}'Interrupted'{'Bị gián đoạn'}default{'Không xác định'}}
    $integrity=switch($Run.Integrity){'Valid'{'Hợp lệ'}'Broken'{'Hỏng'}'NotChain'{'Thử nghiệm'}'Empty'{'Rỗng'}default{'Không đọc được'}}
    $started='';if($Run.Started){try{$started=([DateTime]::Parse($Run.Started,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')}catch{$started=[string]$Run.Started}}
    $note=if($Run.Problem){$Run.Problem}elseif($Run.Status-eq'Interrupted'){'Thiếu dòng kết thúc: lượt chạy có thể đã dừng giữa chừng. Kiểm tra lại file/app liên quan.'}else{''}
    [pscustomobject]@{Started=$started;Kind=$kind;Result=$result;Integrity=$integrity;Items=$Run.Items;Done=$Run.Done;Held=$Run.Held;Skipped=$Run.Skipped;Note=$note;File=$Run.File;Raw=$Run}
}
function Update-MCHistoryWindow {
    param($V)
    $type=[string]$V.UI.HistoryType.SelectedItem.Tag;if(-not$type){$type='All'}
    try{
        $runs=@(Get-MCJournalHistory -ProjectRoot $V.Root -Limit $V.Limit -Type $type)
        $V.Rows=@($runs|ForEach-Object{ConvertTo-MCHistoryRow $_});$V.UI.HistoryRuns.ItemsSource=$V.Rows
        $broken=@($runs|Where-Object{$_.Integrity-eq'Broken'-or$_.Integrity-eq'Unreadable'}).Count;$interrupted=@($runs|Where-Object{$_.Status-eq'Interrupted'}).Count;$tests=@($runs|Where-Object{$_.Integrity-eq'NotChain'}).Count
        $V.UI.HistorySummary.Text=('{0} lượt gần nhất · {1} nhật ký hỏng/không đọc được · {2} lượt bị gián đoạn · {3} nhật ký thử nghiệm' -f $runs.Count,$broken,$interrupted,$tests)
        $V.UI.HistoryStatus.Text=if(-not$runs.Count){'Chưa có nhật ký thao tác nào trong .data.'}else{'Đã đọc lúc '+[DateTime]::Now.ToString('HH:mm:ss')+'. Mã kiểm tra là SHA256 không khóa: phát hiện nhật ký bị hỏng, cắt cụt hoặc đảo dòng, nhưng không chống người cố ý ghi lại toàn bộ.'}
    }catch{$V.Rows=@();$V.UI.HistoryRuns.ItemsSource=$null;$V.UI.HistorySummary.Text='Không đọc được lịch sử.';$V.UI.HistoryStatus.Text=$_.Exception.Message}
}
function New-MCHistoryWindow {
    param([Parameter(Mandatory)][string]$ProjectRoot,[ValidateRange(1,500)][int]$Limit=200)
    Import-Module (Join-Path $script:MCHistoryViewDir 'JournalHistory.psm1') -Global -Force
    $reader=New-Object Xml.XmlNodeReader ([xml](Get-Content -LiteralPath (Join-Path $script:MCHistoryViewDir 'HistoryView.xaml') -Raw -Encoding UTF8));$dialog=[Windows.Markup.XamlReader]::Load($reader);$controls=@{}
    foreach($name in @('HistorySummary','HistoryType','HistoryRuns','HistoryStatus','HistoryRefresh','HistoryClose')){$controls[$name]=$dialog.FindName($name);if(-not$controls[$name]){throw "Missing history control: $name"}}
    $v=[pscustomobject]@{Window=$dialog;UI=$controls;Root=$ProjectRoot;Limit=$Limit;Rows=@()}
    $controls.HistoryRefresh.Add_Click({Update-MCHistoryWindow $v}.GetNewClosure())
    $controls.HistoryType.Add_SelectionChanged({Update-MCHistoryWindow $v}.GetNewClosure())
    $controls.HistoryClose.Add_Click({$v.Window.Close()}.GetNewClosure())
    Update-MCHistoryWindow $v
    $v
}
function Show-MCHistory {
    try{$v=New-MCHistoryWindow -ProjectRoot $diskRoot;$v.Window.Owner=$window;$v.Window.ShowDialog()|Out-Null}catch{$diskUI.DiskStatus.Text=$_.Exception.Message}
}
