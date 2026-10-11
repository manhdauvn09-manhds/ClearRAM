#requires -version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $root
. (Join-Path $root 'MemoryClear.ps1') -SmokeTest -ControlsOnly
. (Join-Path $root 'app\MemoryTaskView.ps1')
$checks=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Value,[string]$Message);if(-not$Value){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Action);try{&$Action;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Pump {param($View);$w=[Diagnostics.Stopwatch]::StartNew();while($View.Busy-and$w.Elapsed.TotalSeconds-lt30){$f=New-Object Windows.Threading.DispatcherFrame;$null=[Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$f.Continue=$false});[Windows.Threading.Dispatcher]::PushFrame($f);Start-Sleep -Milliseconds 40};Assert (-not$View.Busy) 'Worker/timer timeout';Assert (-not$View.UI.TaskProgress.IsIndeterminate) 'Spinner still active'}
function Click {param($Button);$Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))}
$v=$null
try{
 Check 'Async planner locks actions while running' {$script:v=New-MCMemoryTaskWindow @();$v.Window.WindowStartupLocation='Manual';$v.Window.Left=-32000;$v.Window.Top=-32000;$v.Window.ShowInTaskbar=$false;$v.Window.ShowActivated=$false;$v.Window.Show();Assert ($v.Busy-and$v.UI.TaskCancel.IsEnabled-and-not$v.UI.TaskExecute.IsEnabled-and-not$v.UI.TaskRescan.IsEnabled) 'Worker lock failed'}
 Check 'DispatcherTimer completes real worker and reports empty opt-in' {Pump $v;Assert ($v.Plan-and$v.Plan.EligibleCount-eq0-and$v.UI.TaskStatus.Text.Contains('0')) 'No real empty result'}
 Check 'Acknowledgement cannot enable empty or gated execution' {$v.UI.TaskAck.IsChecked=$true;Click $v.UI.TaskAck;Assert (-not$v.UI.TaskExecute.IsEnabled) 'Empty list executable';Assert (-not(Get-MCTaskPolicy).executionEnabled) 'Shipped gate changed'}
 Check 'Rescan expires previous session and clears acknowledgement' {$old=$v.Plan.Id;Click $v.UI.TaskRescan;Assert (-not[MemoryClear.TaskSessionStore]::Plans.ContainsKey($old)-and-not$v.UI.TaskAck.IsChecked) 'Old session retained';Pump $v;Assert ($v.Plan.Id-ne$old) 'Session reused'}
 Check 'Cancel signal is observed and worker unlocks' {Click $v.UI.TaskRescan;Click $v.UI.TaskCancel;Pump $v;Assert ($v.UI.TaskClose.IsEnabled-and-not$v.UI.TaskCancel.IsEnabled) 'Cancel left lock'}
 Check 'Closing handler removes plan and stops timer' {$id=if($v.Plan){$v.Plan.Id}else{''};$v.Window.Close();Assert (-not$v.Timer.IsEnabled-and(-not$id-or-not[MemoryClear.TaskSessionStore]::Plans.ContainsKey($id))) 'Plan/timer leak'}
}finally{if($v){if($v.Token){$v.Token.Cancel()};if($v.Busy){Pump $v};$v.Timer.Stop();if($v.Plan){Close-MCTaskPlan $v.Plan.Id};$v.Window.Close()};$window.Close()}
$r=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($checks|Where-Object{$_.Passed}).Count;Failed=@($checks|Where-Object{-not$_.Passed}).Count;Checks=$checks.ToArray();Scope='Real WPF controls/DispatcherTimer/async empty planner/rescan/cancel; shipped executor remains gated; no user app closed';Unverified=@('Human keyboard/DPI','Nonempty GUI execution and save prompt','Win10')}
$r|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'docs\verification\task-ui-tests.json') -Encoding UTF8
Write-Host ('Task UI: '+$r.Passed+' passed, '+$r.Failed+' failed');if($r.Failed){$r.Checks|Where-Object{-not$_.Passed}|Format-List;exit 1}
