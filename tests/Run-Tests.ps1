#requires -version 5.1
param([switch]$Integration)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$reportDir=Join-Path $root 'artifacts\tests'
New-Item -ItemType Directory -Path $reportDir -Force|Out-Null
$results=New-Object 'System.Collections.Generic.List[object]'
function Check {param([string]$Name,[scriptblock]$Test);try{& $Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Assert {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
Check 'PowerShell source parses' {
  foreach($file in Get-ChildItem $root -Recurse -Include *.ps1,*.psm1 | Where-Object{$_.FullName-notmatch'\\artifacts\\'}){
    $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    Assert ($errors.Count-eq0) ($file.Name+': '+(($errors|ForEach-Object{$_.Message})-join'; '))
  }
}
Import-Module (Join-Path $root 'app\MemoryClear.Core.psm1') -Force
$module=Get-Module MemoryClear.Core
$testData=Join-Path $reportDir ('settings-'+[Guid]::NewGuid().ToString('N'))
& $module {param($Directory);$script:Data=$Directory} $testData
$context=[pscustomobject]@{UserSid='S-1-5-21-test';SessionId=1;SelfId=900;WindowsRoot='C:\Windows\';Services=@{};ServicesKnown=$true}
$settings=[pscustomobject]@{SchemaVersion=1;ProtectedPaths=@();AllowClosePaths=@();RefreshSeconds=3;AutoKill=$false}
function Identity { [pscustomobject]@{Pid=123;StartTicks=123456;Path='C:\Apps\editor.exe';Sid='S-1-5-21-test';Session=1;Critical=$false;Known=$true} }
Check 'Same-user application can be manually selected' {Assert ((Test-MCPolicy (Identity) $context $settings).Allowed)}
Check 'Unknown identity fails closed' {$id=Identity;$id.Known=$false;Assert (-not(Test-MCPolicy $id $context $settings).Allowed)}
Check 'Critical process fails closed' {$id=Identity;$id.Critical=$true;Assert (-not(Test-MCPolicy $id $context $settings).Allowed)}
Check 'Different SID and session fail closed' {$id=Identity;$id.Sid='other';Assert (-not(Test-MCPolicy $id $context $settings).Allowed);$id=Identity;$id.Session=2;Assert (-not(Test-MCPolicy $id $context $settings).Allowed)}
Check 'Windows component and host are blocked' {$id=Identity;$id.Path='c:\WINDOWS\System32\example.exe';Assert (-not(Test-MCPolicy $id $context $settings).Allowed);$id=Identity;$id.Pid=900;Assert (-not(Test-MCPolicy $id $context $settings).Allowed)}
Check 'Service and unavailable service inventory fail closed' {$c=$context.PSObject.Copy();$c.Services=@{123=$true};Assert (-not(Test-MCPolicy (Identity) $c $settings).Allowed);$c.ServicesKnown=$false;Assert (-not(Test-MCPolicy (Identity) $c $settings).Allowed)}
Check 'Protection takes precedence over emergency allowlist' {$s=$settings.PSObject.Copy();$s.ProtectedPaths=@('C:\Apps\editor.exe');$s.AllowClosePaths=@('C:\Apps\editor.exe');$p=Test-MCPolicy (Identity) $context $s;Assert (-not$p.Allowed-and-not$p.AllowClose)}
Check 'Emergency allowlist is explicit and path-specific' {Assert (-not(Test-MCPolicy (Identity) $context $settings).AllowClose);$s=$settings.PSObject.Copy();$s.AllowClosePaths=@('c:\apps\EDITOR.exe');Assert ((Test-MCPolicy (Identity) $context $s).AllowClose)}
Check 'Settings round-trip enforces automation off' {$s=$settings.PSObject.Copy();$s.AutoKill=$true;Save-MCSettings $s;$loaded=Get-MCSettings;Assert (-not$loaded.AutoKill-and$loaded.RefreshSeconds-eq3)}
Check 'Malformed settings fail closed and can be repaired' {[IO.File]::WriteAllText((Join-Path $testData 'settings.json'),'bad json');$loaded=Get-MCSettings;Assert (-not$loaded.AutoKill-and@($loaded.AllowClosePaths).Count-eq0-and$loaded.Warning);Assert (-not(Test-MCPolicy (Identity) $context $loaded).Allowed);Save-MCSettings $loaded;Assert ((Test-MCPolicy (Identity) $context (Get-MCSettings)).Allowed)}
Check 'Snapshot bounds and CPU warm-up' {$script:first=Get-MCSnapshot;Assert ($null-eq$first.Cpu);Assert ($first.System.AvailableBytes-gt0-and$first.System.AvailableBytes-le$first.System.TotalBytes);Start-Sleep -Milliseconds 500;$script:second=Get-MCSnapshot $first;Assert ($second.Cpu-ge0-and$second.Cpu-le100);Assert ($second.Rows.Count-gt0);foreach($row in $second.Rows){if($null-ne$row.Cpu){Assert ($row.Cpu-ge0-and$row.Cpu-le100)}}}
Check 'Current host is denied even with real identity' {$row=$second.Rows|Where-Object{$_.Pid-eq$PID};Assert ($null-ne$row-and-not$row.Allowed)}
Check 'Audit log stays bounded' {for($i=0;$i-lt205;$i++){Write-MCEvent ([pscustomobject]@{Index=$i})};$parsed=Get-Content (Join-Path $testData 'activity.json') -Raw|ConvertFrom-Json;$events=@($parsed);Assert ($events.Count-eq200-and$events[0].Index-eq5)}
if($Integration){
  $fixture=Join-Path $reportDir 'MemoryClear.TestApp.exe'
  if(-not(Test-Path $fixture)){
    Add-Type -TypeDefinition 'using System; using System.Windows.Forms; public class Fixture { [STAThread] public static void Main() { Application.Run(new Form { Text="MemoryClear disposable test fixture", Width=300, Height=150, ShowInTaskbar=false }); } }' -ReferencedAssemblies System.Windows.Forms,System.Drawing -OutputAssembly $fixture -OutputType WindowsApplication
  }
  function StartFixture { $p=Start-Process -FilePath $fixture -WindowStyle Hidden -PassThru;for($i=0;$i-lt30;$i++){Start-Sleep -Milliseconds 100;$p.Refresh();if($p.MainWindowHandle-ne[IntPtr]::Zero){break}};return $p }
  Check 'Stale identity is rejected without killing fixture' {$p=StartFixture;try{$id=[MemoryClear.Native]::Inspect($p.Id);$r=Invoke-MCAction -ProcessId $p.Id -StartTicks ($id.StartTicks+1) -Action Kill -Confirm:$false;Assert ($r.Status-eq'Denied');$p.Refresh();Assert (-not$p.HasExited)}finally{if(-not$p.HasExited){$p.Kill()};$p.Dispose()}}
  Check 'Hidden fixture without main window is not force-killed' {$p=StartFixture;try{$id=[MemoryClear.Native]::Inspect($p.Id);$r=Invoke-MCAction -ProcessId $p.Id -StartTicks $id.StartTicks -Action Close -Confirm:$false;Assert ($r.Status-eq'NoWindow') $r.Message;$p.Refresh();Assert (-not$p.HasExited)}finally{if(-not$p.HasExited){$p.Kill()};$p.Dispose()}}
  Check 'Force kill verifies fixture exit' {$p=StartFixture;try{$id=[MemoryClear.Native]::Inspect($p.Id);$r=Invoke-MCAction -ProcessId $p.Id -StartTicks $id.StartTicks -Action Kill -Confirm:$false;Assert ($r.Status-eq'Exited') $r.Message;Assert ($p.WaitForExit(1000))}finally{if(-not$p.HasExited){$p.Kill()};$p.Dispose()}}
}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Integration=[bool]$Integration;Results=@($results.ToArray());Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count}
$report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $reportDir 'results.json') -Encoding UTF8
$results|Format-Table Name,Passed,Error -AutoSize
Write-Output "TESTS passed=$($report.Passed) failed=$($report.Failed)"
if($report.Failed){exit 1}
