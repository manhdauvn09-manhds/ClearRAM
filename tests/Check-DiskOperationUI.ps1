#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent;Set-Location -LiteralPath $projectRoot
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1')
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
function Check {param($Name,$Action);try{&$Action;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Click {param($Button);$Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))}
function Wait-Worker {
    param($View)
    $watch=[Diagnostics.Stopwatch]::StartNew();$frame=[Windows.Threading.DispatcherFrame]::new();$poll=[Windows.Threading.DispatcherTimer]::new();$poll.Interval=[TimeSpan]::FromMilliseconds(100)
    $callback={$frame.Continue=$View.Busy-and$watch.Elapsed.TotalSeconds-lt20}.GetNewClosure();$poll.Add_Tick($callback)
    try{$poll.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}finally{$poll.Stop()}
    Assert (-not$View.Busy) 'Actual DispatcherTimer worker timeout'
}
$source=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));$backup=Join-Path $projectRoot ('artifacts\disk-backup-fixture-'+[guid]::NewGuid().ToString('N'))
foreach($r in @($source,$backup)){New-Item -ItemType Directory -Path $r|Out-Null;[IO.File]::WriteAllText((Join-Path $r '.memoryclear-fixture'),'Disposable operation UI test')}
foreach($name in @('temp.tmp','old.log','save.db','keep.bin')){[IO.File]::WriteAllText((Join-Path $source $name),'UI fixture original '+$name)}
$scan=Get-MCDiskScan -FixtureRoots @($source);$rows=@($scan.Rows|Where-Object{$_.Name-ne'.memoryclear-fixture'});$view=$null
try{
    $view=New-MCDiskOperationWindow $scan $rows $backup 'ui-scope';$ui2=$view.UI
    Check 'Operation window loads 27 controls and defaults to backup' {Assert ($ui2.Count-eq27-and$view.Plan.Mode-eq'Backup'-and-not$ui2.OperationRun.IsEnabled)}
    Check 'Main Windows delegation and example controls obey shared operation lock' {Assert ($diskUI.DiskWindowsStorage-and$diskUI.DiskWindowsApps-and$diskUI.DiskTransactions);Set-MCOperationState $true;Assert (-not$diskUI.DiskWindowsStorage.IsEnabled-and-not$diskUI.DiskWindowsApps.IsEnabled-and-not$diskUI.DiskTransactions.IsEnabled-and-not$ui.ClearMemory.IsEnabled);Set-MCOperationState $false}
    Check 'Mode change creates a new plan and clears prior review' {$old=$view.Plan.Id;$view.Rows[0].Reviewed=$true;$ui2.OperationPermanent.IsChecked=$true;Click $ui2.OperationPermanent;Assert ($view.Plan.Id-ne$old-and$view.Plan.Mode-eq'Permanent'-and-not@($view.Rows|Where-Object{$_.Reviewed}).Count);$ui2.OperationBackup.IsChecked=$true;Click $ui2.OperationBackup;Assert ($view.Plan.Mode-eq'Backup')}
    Check 'Next rejects missing acknowledgments and keeps blocked item unreviewable' {Click $ui2.OperationNext;Assert ($view.Plan.Stage-eq'Review'-and-not($view.Rows|Where-Object{$_.Risk-eq'Blocked'}).CanReview)}
    Check 'Item review moves to final confirmation; missing phrase cannot run' {foreach($r in $view.Rows){if($r.Risk-in@('Review','Danger')){$r.Reviewed=$true}};Click $ui2.OperationNext;Assert ($view.Plan.Stage-eq'Confirm'-and$ui2.OperationFinal.Visibility-eq'Visible');$ui2.OperationAck.IsChecked=$true;$ui2.OperationPhrase.Text='wrong';Click $ui2.OperationConfirm;Assert (-not$ui2.OperationRun.IsEnabled)}
    Check 'Back clears both item reviews and final fields' {Click $ui2.OperationBack;Assert ($view.Plan.Stage-eq'Review'-and-not@($view.Rows|Where-Object{$_.Reviewed}).Count-and-not$ui2.OperationAck.IsChecked-and$ui2.OperationPhrase.Text-eq'')}
    Check 'Correct second review enables only the selected frozen operation' {foreach($r in $view.Rows){if($r.Risk-in@('Review','Danger')){$r.Reviewed=$true}};Click $ui2.OperationNext;$ui2.OperationAck.IsChecked=$true;$ui2.OperationPhrase.Text=$view.Plan.Phrase;Click $ui2.OperationConfirm;Assert ($view.Plan.Stage-eq'Approved'-and$ui2.OperationRun.IsEnabled)}
    $content=$view.Window.Content;$content.Measure([Windows.Size]::new(960,690));$content.Arrange([Windows.Rect]::new(0,0,960,690));$content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(960,690,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $projectRoot 'artifacts\disk-operation-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    Check 'Actual background run disables edits and close, reports measured completion' {Click $ui2.OperationRun;Assert ($view.Busy-and$ui2.OperationStop.IsEnabled-and-not$ui2.OperationClose.IsEnabled-and-not$ui2.OperationPermanent.IsEnabled);Wait-Worker $view;Assert ($view.Result.Status-eq'Completed'-and$view.Result.Processed-eq3-and-not$ui2.OperationProgress.IsIndeterminate-and$ui2.OperationStatus.Text-like'*3/3*'-and(Test-Path (Join-Path $source 'keep.bin')))}
    Check 'Inspect runs in worker and displays three verified restore candidates' {Click $ui2.OperationInspect;Wait-Worker $view;Assert ($view.Result.Integrity-eq'VerifiedPrefix'-and$ui2.OperationHistory.Items.Count-eq3-and-not$ui2.OperationRestore.IsEnabled)}
    Check 'Restore requires explicit target selection and acknowledgment' {$ui2.OperationHistory.SelectedItem=@($ui2.OperationHistory.Items)[0];$ui2.OperationRestoreAck.IsChecked=$false;Update-MCOperationWindow $view;Assert (-not$ui2.OperationRestore.IsEnabled);$ui2.OperationRestoreAck.IsChecked=$true;Click $ui2.OperationRestoreAck;Assert $ui2.OperationRestore.IsEnabled}
    Check 'Background restore returns exact file and keeps backup; invalidates displayed history' {$path=$ui2.OperationHistory.SelectedItem.Path;Click $ui2.OperationRestore;Wait-Worker $view;Assert ($view.Result.Status-eq'Restored'-and(Test-Path $path)-and$ui2.OperationHistory.Items.Count-eq0-and-not$ui2.OperationRestore.IsEnabled)}
    Check 'Journal/restore failures release worker and preserve honest error status' {$ui2.OperationJournal.Text=Join-Path $source 'invalid.txt';Click $ui2.OperationInspect;Wait-Worker $view;Assert (-not$view.Busy-and-not$ui2.OperationProgress.IsIndeterminate-and$ui2.OperationStatus.Text-like'*Lỗi*')}
    Check 'Recent journal listing is bounded and uninspected, selection does not claim success' {Click $ui2.OperationRecent;Wait-Worker $view;Assert ($view.Result.Rows.Count-le200-and$view.Result.Rows.Count-gt0-and-not$view.Result.AutomaticReplay);$ui2.OperationRecentRuns.SelectedItem=@($ui2.OperationRecentRuns.Items)[0];Assert ($ui2.OperationHistory.Items.Count-eq0-and-not$ui2.OperationRestore.IsEnabled-and$ui2.OperationHistoryStatus.Text-like'*chưa kiểm tra*')}
}finally{if($view){$view.Timer.Stop();if($view.Token){$view.Token.Cancel()};if($view.Worker){$view.Worker.Stop();$view.Worker.Dispose()};Close-MCDiskOperation $view.Plan.Id;$view.Window.Close()};Set-MCOperationState $false}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=$results.ToArray();Image='artifacts/disk-operation-preview.png';Scope='Offscreen WPF actual background run/inspect/restore on marked fixtures';InteractiveAcceptance=$false;ProductionExecutionEnabled=$false}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $projectRoot 'docs\verification\disk-operation-ui-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize|Out-String|Write-Output;if($report.Failed){$results|Where-Object{-not$_.Passed}|Format-List|Out-String|Write-Output;exit 1}
