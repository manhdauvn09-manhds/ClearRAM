#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'MemoryClear.ps1') -SmokeTest -ControlsOnly
Import-Module (Join-Path $root 'app\MemoryClear.Clear.psm1') -Force
$clearModule=Get-Module MemoryClear.Clear
$coreModule=Get-Module MemoryClear.Core
$folder=Join-Path $root ('artifacts\clear-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder -Force|Out-Null
& $coreModule {param($Directory);$script:Data=$Directory} $folder
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert-Clear {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
function Check-Clear {param([string]$Name,[scriptblock]$Test);try{& $Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Assert-Throws {param([scriptblock]$Action);$thrown=$false;try{& $Action|Out-Null}catch{$thrown=$true};Assert-Clear $thrown 'Expected rejection.'}
$policy=Get-MCClearPolicy
Check-Clear 'Product policy and source syntax' {
    Assert-Clear ($policy.governs-eq'product_runtime'-and$policy.maxProcesses-le32)
    foreach($file in @('MemoryClear.ps1','app\MemoryClear.Clear.psm1','app\MemoryClear.Core.psm1','tests\Check-Clear.ps1')){
        $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)|Out-Null
        Assert-Clear ($errors.Count-eq0) (($errors|ForEach-Object{$_.Message})-join'; ')
    }
}
Check-Clear 'Planner skips unknown CPU, busy, protected, reused identity and active path' {
    $rows=@();for($i=1;$i-le8;$i++){$rows+=@([MemoryClear.ProcessRow]@{Pid=$i;StartTicks=$i;Path=('C:\Fixture\{0}.exe'-f$i);RamMB=(100+$i);Cpu=0;Allowed=$true})}
    $prior=@($rows|ForEach-Object{[MemoryClear.ProcessRow]@{Pid=$_.Pid;StartTicks=$_.StartTicks;Path=$_.Path;RamMB=$_.RamMB;Cpu=$_.Cpu;Allowed=$true}})
    $rows[1].Cpu=$null;$rows[2].Cpu=5;$rows[3].Allowed=$false;$rows[4].StartTicks=999;$rows[5].RamMB=10;$prior[6].Cpu=1
    $found=@(Get-MCClearCandidates ([pscustomobject]@{Rows=$rows}) ([pscustomobject]@{Rows=$prior}) $policy @() @('c:\fixture\8.EXE'))
    Assert-Clear ($found.Count-eq1-and$found[0].Pid-eq1) 'Unexpected candidate selected.'
    Assert-Clear (@(Get-MCClearCandidates ([pscustomobject]@{Rows=$rows}) ([pscustomobject]@{Rows=$prior}) $policy @(1) @('c:\fixture\8.EXE')).Count-eq0)
}
Check-Clear 'Planner caps count and prioritizes working set' {
    $rows=@();for($i=1;$i-le20;$i++){$rows+=@([MemoryClear.ProcessRow]@{Pid=$i;StartTicks=$i;RamMB=(100+$i);Cpu=0;Allowed=$true;Path='C:\Fixture\app.exe'})}
    $s=[pscustomobject]@{Rows=$rows};$found=@(Get-MCClearCandidates $s $s $policy)
    Assert-Clear ($found.Count-eq$policy.maxProcesses-and$found[0].Pid-eq20)
}
Check-Clear 'Strong profile expands candidates while retaining protected and foreground exclusions' {
    $strong=Get-MCClearPolicy -Mode Strong
    Assert-Clear ($strong.minWorkingSetMB-eq32-and$strong.maxCpuPercent-eq1-and$strong.maxProcesses-eq32-and$strong.maxDurationSeconds-eq60-and$strong.cooldownSeconds-eq120)
    $rows=@();for($i=1;$i-le4;$i++){$rows+=@([MemoryClear.ProcessRow]@{Name='Fixture';Pid=$i;StartTicks=$i;RamMB=48;Cpu=0.5;Allowed=$true;Path=('C:\Fixture\{0}.exe'-f$i)})}
    $rows[1].Allowed=$false;$rows[3].Cpu=$null;$s=[pscustomobject]@{Rows=$rows}
    Assert-Clear (@(Get-MCClearCandidates $s $s $policy).Count-eq0)
    $found=@(Get-MCClearCandidates $s $s $strong @() @('C:\Fixture\3.exe'))
    Assert-Clear ($found.Count-eq1-and$found[0].Pid-eq1)
}
Check-Clear 'Invalid policy fails closed' {
    Copy-Item (Join-Path $root 'app\MemoryClear.Clear.psm1') (Join-Path $folder 'BadClear.psm1')
    '# Policy-reader test stub; native actions are never called.'|Set-Content (Join-Path $folder 'MemoryClear.Core.psm1') -Encoding UTF8
    $bad=$policy.PSObject.Copy();$bad.maxProcesses=1000;$bad|ConvertTo-Json|Set-Content (Join-Path $folder 'clear-policy.json') -Encoding UTF8
    $badModule=Import-Module (Join-Path $folder 'BadClear.psm1') -Prefix Bad -PassThru
    try{
        Assert-Throws {& $badModule {Get-MCClearPolicy}}
        $bad=$policy.PSObject.Copy();$bad.maxCpuPercent=$false;$bad|ConvertTo-Json|Set-Content (Join-Path $folder 'clear-policy.json') -Encoding UTF8
        Assert-Throws {& $badModule {Get-MCClearPolicy}}
    }finally{Remove-Module $badModule}
}
Check-Clear 'One click without selection queues Clear and supports pending cancel' {
    Assert-Clear ($ui.Processes.SelectedItems.Count-eq0)
    $script:job=[pscustomobject]@{DummyScan=$true}
    $ui.ClearMemory.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Assert-Clear ($clearRequested-and$operation-and-not$ui.ClearMemory.IsEnabled-and$clearCancellation) 'Clear request was not queued.'
    Assert-Clear ($ui.ClearProgress.IsIndeterminate-and$clearRunning-and-not$ui.StrongClear.IsEnabled) 'Pending Clear must visibly show activity and lock mode.'
    $capturedToken=$clearCancellation.Token
    $ui.CancelOperation.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Assert-Clear (-not$clearRequested-and$capturedToken.IsCancellationRequested-and$null-eq$clearCancellation)
    Assert-Clear (-not$ui.ClearProgress.IsIndeterminate-and-not$clearRunning-and$ui.ClearState.Text.Contains('Đã dừng')) 'Pending cancel must not leave a spinner running.'
    $script:job=$null;Set-MCOperationState $false
}
Check-Clear 'UI captures Strong mode and displays real count progress plus terminal states' {
    $script:job=[pscustomobject]@{DummyScan=$true};$ui.StrongClear.IsChecked=$true
    Start-MCOneClickClear
    Assert-Clear ($clearMode-eq'Strong') 'Mode must be captured at click.'
    $clearProgressQueue.Enqueue([pscustomobject]@{Stage='Processing';Message='Fixture progress';Processed=2;Total=7});Update-MCClearProgress
    Assert-Clear (-not$ui.ClearProgress.IsIndeterminate-and$ui.ClearProgress.Maximum-eq7-and$ui.ClearProgress.Value-eq2-and$ui.ClearState.Text.Contains('2/7'))
    foreach($status in @('Error','Cancelled','TimeLimit','Cooldown')){
        Complete-MCClearUI ([pscustomobject]@{Status=$status;Message=$status})
        Assert-Clear (-not$ui.ClearProgress.IsIndeterminate-and$ui.ClearProgress.Value-lt$ui.ClearProgress.Maximum-and$ui.ClearMemory.IsEnabled-and$ui.StrongClear.IsEnabled) ('Incorrect terminal state: '+$status)
    }
    Complete-MCClearUI ([pscustomobject]@{Status='CandidatesFinished';Message='Completed fixture result'})
    Assert-Clear ($ui.ClearProgress.Value-eq100-and$ui.ClearState.Text.Contains('Hoàn tất')-and$ui.ClearElapsed.Text.Contains('Mạnh hơn'))
    $script:clearRequested=$false;$script:job=$null;$clearCancellation.Cancel();$clearCancellation.Dispose();$script:clearCancellation=$null;$ui.StrongClear.IsChecked=$false
}
Check-Clear 'Real GUI worker receives cancellation token without scanning user processes' {
    $script:pool=[RunspaceFactory]::CreateRunspacePool(1,1);$pool.Open()
    $script:clearCancellation=New-Object Threading.CancellationTokenSource;$clearCancellation.Cancel()
    $script:clearMode='Strong';$script:clearProgressQueue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    try{
        Start-MCWorker 'Clear' $null
        $output=@($job.EndInvoke($async));Assert-Clear ($job.Streams.Error.Count-eq0) ($job.Streams.Error|Out-String)
        Assert-Clear ($output.Count-eq1-and$output[0].Status-eq'Cancelled'-and$output[0].Trimmed-eq0)
        Assert-Clear ($output[0].Mode-eq'Strong'-and$clearProgressQueue.Count-ge2) 'Worker must share live progress events with GUI.'
        $event=$null;$stages=@();while($clearProgressQueue.TryDequeue([ref]$event)){$stages+=@($event.Stage)}
        Assert-Clear ($stages[0]-eq'Validating'-and$stages[-1]-eq'Cancelled')
    }finally{if($job){$job.Dispose();$script:job=$null};$pool.Close();$pool.Dispose();$clearCancellation.Dispose();$script:clearCancellation=$null;$script:clearMode='Normal'}
}
# Dedicated disposable process holds data; only this PID is ever actually trimmed.
$source=@'
using System;
using System.IO;
using System.Threading;
public class ClearFixture {
  public static void Main(string[] args) {
    byte[] data=new byte[32*1024*1024];
    for(int i=0;i<data.Length;i+=4096) data[i]=(byte)((i/4096)%251);
    File.WriteAllText(Path.Combine(args[0],"ready"),"ready");
    DateTime end=DateTime.UtcNow.AddSeconds(60);
    while(DateTime.UtcNow<end && !File.Exists(Path.Combine(args[0],"stop"))) {
      if(File.Exists(Path.Combine(args[0],"verify"))) {
        bool valid=true; for(int i=0;i<data.Length;i+=4096) if(data[i]!=(byte)((i/4096)%251)) valid=false;
        File.WriteAllText(Path.Combine(args[0],"verified"),valid?"OK":"CORRUPTED");
        File.Delete(Path.Combine(args[0],"verify"));
      }
      Thread.Sleep(50);
    }
    GC.KeepAlive(data);
  }
}
'@
$child=$null;$measurement=$null
try {
    $fixture=Join-Path $folder 'ClearFixture.exe'
    Add-Type -TypeDefinition $source -OutputAssembly $fixture -OutputType WindowsApplication
    $child=Start-Process -FilePath $fixture -ArgumentList ('"'+$folder+'"') -WindowStyle Hidden -PassThru
    for($i=0;$i-lt50-and-not(Test-Path (Join-Path $folder 'ready'));$i++){Start-Sleep -Milliseconds 100}
    Assert-Clear (Test-Path (Join-Path $folder 'ready')) 'Fixture failed to start.'
    $identity=[MemoryClear.Native]::Inspect($child.Id)
    Check-Clear 'Stable handle rejects stale PID identity and cannot close or kill' {
        Assert-Throws {[MemoryClear.Native]::AcquireForTrim($child.Id,($identity.StartTicks+1))}
        $guard=[MemoryClear.Native]::AcquireForTrim($child.Id,$identity.StartTicks)
        try{Assert-Throws {$guard.Kill()};Assert-Throws {$guard.CloseWindow()}}finally{$guard.Dispose()}
        $child.Refresh();Assert-Clear (-not$child.HasExited)
    }
    Check-Clear 'Excluded PID and protected path deny trim' {
        $r=Invoke-MCTrim $child.Id $identity.StartTicks $policy @($child.Id)
        Assert-Clear ($r.Status-eq'Skipped')
        $s=Get-MCSettings;$s.ProtectedPaths=@($identity.Path);Save-MCSettings $s
        try{$r=Invoke-MCTrim $child.Id $identity.StartTicks $policy;Assert-Clear ($r.Status-eq'Skipped') $r.Message}finally{$s.ProtectedPaths=@();Save-MCSettings $s}
    }
    Check-Clear 'Cancelled Clear skips all scans and actions; cooldown prevents repetition' {
        $cts=New-Object Threading.CancellationTokenSource;$cts.Cancel()
        try{$r=Invoke-MCClear -CancellationToken $cts.Token;Assert-Clear ($r.Status-eq'Cancelled'-and$r.Trimmed-eq0-and$r.Closed-eq0-and$r.Killed-eq0)}finally{$cts.Dispose()}
        & $clearModule {$script:LastClearTick=[Diagnostics.Stopwatch]::GetTimestamp()}
        $r=Invoke-MCClear;Assert-Clear ($r.Status-eq'Cooldown')
        & $clearModule {$script:LastClearCooldown=120;$script:LastClearTick=[Diagnostics.Stopwatch]::GetTimestamp()-90*[Diagnostics.Stopwatch]::Frequency}
        $r=Invoke-MCClear -Mode Normal;Assert-Clear ($r.Status-eq'Cooldown'-and$r.RetryAfterSeconds-gt0) 'Switching mode must not bypass the prior Strong cooldown.'
        & $clearModule {$script:LastClearTick=0L;$script:LastClearCooldown=0}
    }
    Check-Clear 'Real trim preserves fixture process and data' {
        Start-Sleep -Milliseconds 300;$child.Refresh();$before=$child.WorkingSet64
        $r=Invoke-MCTrim $child.Id $identity.StartTicks $policy
        Assert-Clear ($r.Status-eq'Trimmed') $r.Message
        $child.Refresh();$after=$child.WorkingSet64;Assert-Clear (-not$child.HasExited)
        [IO.File]::WriteAllText((Join-Path $folder 'verify'),'verify')
        for($i=0;$i-lt30-and-not(Test-Path (Join-Path $folder 'verified'));$i++){Start-Sleep -Milliseconds 100}
        Assert-Clear ((Get-Content (Join-Path $folder 'verified') -Raw)-eq'OK') 'Fixture data verification failed.'
        $script:measurement=[pscustomobject]@{BeforeWorkingSetMB=[Math]::Round($before/1MB,2);AfterWorkingSetMB=[Math]::Round($after/1MB,2);DataVerified=$true;StillRunning=$true;OnlyDisposableFixture=$true}
    }
    # Render the real controls without a full system inventory or a real Clear call.
    $script:snapshot=[pscustomobject]@{Rows=[MemoryClear.ProcessRow[]]@();System=[MemoryClear.Native]::ReadSystem();Cpu=$null};Update-MCView
    Complete-MCClearUI ([pscustomobject]@{Status='CandidatesFinished';Message='Hoàn tất lượt thử: giữ nguyên process và dữ liệu. RAM có thể nạp lại.'})
    $content=$window.Content;$content.Measure([Windows.Size]::new(1072,700));$content.Arrange([Windows.Rect]::new(0,0,1072,700));$content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1072,700,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $root 'artifacts\clear-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
} catch {
    $results.Add([pscustomobject]@{Name='Fixture/render setup';Passed=$false;Error=$_.Exception.Message})
} finally {
    if($child){[IO.File]::WriteAllText((Join-Path $folder 'stop'),'stop');if(-not$child.WaitForExit(2000)){$child.Kill()};$child.Dispose()}
}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=@($results.ToArray());Measurement=$measurement;Mode='Offscreen UI and owned fixture only; no user process trimmed'}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'artifacts\clear-tests.json') -Encoding UTF8
$results|Format-Table Name,Passed,Error -AutoSize
Write-Output "CLEAR_TESTS passed=$($report.Passed) failed=$($report.Failed)"
if($report.Failed){exit 1}
