#requires -version 5.1
# CD-04 history window: offscreen WPF, fixture journals only (artifacts\history-ui-*, deleted after run).
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $projectRoot
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Value,[string]$Message='Assertion failed');if(-not$Value){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Action);try{&$Action;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Click {param($Button);$Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))}
function Hash {param([string]$Text);$h=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$h.Dispose()}}
function Write-Journal {param([string]$Type,[object[]]$Events,[int]$Corrupt=0)
    $prev='0'*64;$n=0;$lines=foreach($e in $Events){$n++;$payload=$e|ConvertTo-Json -Depth 6 -Compress;$h=Hash ($prev+"`n"+$payload);if($n-eq$Corrupt){$payload=$payload.Replace('Committed','Changed')};[pscustomobject]@{Sequence=$n;PreviousHash=$prev;Payload=$payload;Hash=$h}|ConvertTo-Json -Compress;$prev=$h}
    $path=Join-Path $data ($Type+'-operation-'+[guid]::NewGuid().ToString('N')+'.jsonl');[IO.File]::WriteAllText($path,(($lines-join"`n")+"`n"),(New-Object Text.UTF8Encoding($false)));$path}
$fixture=Join-Path $projectRoot ('artifacts\history-ui-'+[guid]::NewGuid().ToString('N'));$data=Join-Path $fixture '.data';New-Item -ItemType Directory -Path $data -Force|Out-Null
$utc=[DateTime]::UtcNow.ToString('o')
Write-Journal 'temp' @([pscustomobject]@{Kind='Plan';Capability='ReviewedTopLevelOwnTemp';Items=@(@{Id='A'});Utc=$utc},[pscustomobject]@{Kind='Item';Identity='A';Stage='Committed';Utc=$utc},[pscustomobject]@{Kind='Outcome';Identity='A';Status='Deleted';Utc=$utc},[pscustomobject]@{Kind='Finished';Status='Completed';Utc=$utc})|Out-Null
Write-Journal 'temp' @([pscustomobject]@{Kind='Plan';Capability='ReviewedTopLevelOwnTemp';Items=@(@{Id='B'});Utc=$utc},[pscustomobject]@{Kind='Item';Identity='B';Stage='Committed';Utc=$utc},[pscustomobject]@{Kind='Finished';Status='Completed';Utc=$utc}) -Corrupt 2|Out-Null
Write-Journal 'memory' @([pscustomobject]@{Kind='Plan';Capability='OptInGracefulOnly';Items=@(@{Pid=1});Utc=$utc},[pscustomobject]@{Kind='Outcome';Result=@{Status='HeldTimeout'};Utc=$utc})|Out-Null
$v=$null
try{
    Check 'Disk tab has the read-only history button' {Assert ($null-ne$diskUI.DiskHistory-and[string]$diskUI.DiskHistory.Content-like'Lịch sử*') 'DiskHistory missing'}
    $v=New-MCHistoryWindow -ProjectRoot $fixture
    Check 'All fixture runs listed with Vietnamese labels' {Assert (@($v.Rows).Count-eq3) ("rows "+@($v.Rows).Count);Assert (@($v.Rows|Where-Object{$_.Kind-eq'Dọn Temp'-and$_.Result-eq'Hoàn tất'-and$_.Integrity-eq'Hợp lệ'-and$_.Done-eq1}).Count-eq1) 'Completed temp row'}
    Check 'Edited journal shows as broken with its reason' {$b=@($v.Rows|Where-Object{$_.Integrity-eq'Hỏng'});Assert ($b.Count-eq1-and$b[0].Note.Length-gt0-and$b[0].Result-eq'Không xác định') ($b|ConvertTo-Json -Depth 2 -Compress)}
    Check 'Run without end entry shows as interrupted with guidance' {$i=@($v.Rows|Where-Object{$_.Result-eq'Bị gián đoạn'});Assert ($i.Count-eq1-and$i[0].Kind-eq'Memory mức 3'-and$i[0].Held-eq1-and$i[0].Note.Length-gt0)}
    Check 'Summary counts broken and interrupted runs' {$t=$v.UI.HistorySummary.Text;Assert ($t.StartsWith('3 ')-and$t.Contains('1 nhật ký hỏng')-and$t.Contains('1 lượt bị gián đoạn')) $t}
    Check 'Type filter narrows to Memory runs' {$v.UI.HistoryType.SelectedIndex=2;Assert (@($v.Rows).Count-eq1-and@($v.Rows)[0].Kind-eq'Memory mức 3') 'Filter';$v.UI.HistoryType.SelectedIndex=0;Assert (@($v.Rows).Count-eq3) 'Back to all'}
    Check 'Refresh picks up a new journal' {Write-Journal 'temp' @([pscustomobject]@{Kind='Plan';Capability='ReviewedTopLevelOwnTemp';Items=@();Utc=$utc},[pscustomobject]@{Kind='Finished';Status='Cancelled';Utc=$utc})|Out-Null;Click $v.UI.HistoryRefresh;Assert (@($v.Rows).Count-eq4-and@($v.Rows|Where-Object{$_.Result-eq'Đã hủy'}).Count-eq1)}
    Check 'Window offers no action besides refresh and close' {$buttons=New-Object 'System.Collections.Generic.List[object]';$stack=New-Object 'System.Collections.Generic.Stack[object]';$stack.Push($v.Window.Content);while($stack.Count){$n=$stack.Pop();if($n-is[Windows.Controls.Button]){$buttons.Add($n.Name)};foreach($c in [Windows.LogicalTreeHelper]::GetChildren($n)){if($c-is[Windows.DependencyObject]){$stack.Push($c)}}};Assert ((@($buttons|Sort-Object)-join',')-eq'HistoryClose,HistoryRefresh') ($buttons-join',');Assert $v.UI.HistoryRuns.IsReadOnly 'Grid editable'}
    Check 'Missing .data shows an empty, explained history' {$e=New-MCHistoryWindow -ProjectRoot (Join-Path $fixture 'empty');try{Assert (@($e.Rows).Count-eq0-and$e.UI.HistoryStatus.Text.Contains('Chưa có'))}finally{$e.Window.Close()}}
    Check 'Offscreen visual renders' {$content=$v.Window.Content;$content.Measure([Windows.Size]::new(1020,640));$content.Arrange([Windows.Rect]::new(0,0,1020,640));$content.UpdateLayout();$bmp=[Windows.Media.Imaging.RenderTargetBitmap]::new(1020,640,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($content);$enc=New-Object Windows.Media.Imaging.PngBitmapEncoder;$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp));$png=Join-Path $projectRoot 'artifacts\history-ui-preview.png';$fs=[IO.File]::Create($png);try{$enc.Save($fs)}finally{$fs.Dispose()};Assert ((Get-Item -LiteralPath $png).Length-gt10KB) 'Render too small'}
}finally{if($v){$v.Window.Close()};Remove-Item -LiteralPath $fixture -Recurse -Force}
$r=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Checks=$results.ToArray();Scope='Offscreen WPF history window on fixture journals (deleted after run); preview artifacts\history-ui-preview.png';Unverified=@('Human keyboard/DPI','Shown as a real modal from the Disk tab')}
$r|ConvertTo-Json -Depth 6|Set-Content (Join-Path $projectRoot 'docs\verification\history-ui-tests.json') -Encoding UTF8
Write-Host ('History UI: '+$r.Passed+' passed, '+$r.Failed+' failed')
if($r.Failed){$r.Checks|Where-Object{-not$_.Passed}|Format-List;exit 1}
