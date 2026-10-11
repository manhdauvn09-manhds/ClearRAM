#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1') -Force
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function App {param([string]$Location,[string]$Name='Example fixture app',[string]$Source='HKCU/Registry64');[pscustomobject]@{Name=$Name;Publisher='Fixture publisher';Location=$Location;Source=$Source}}
function Inventory {param([object[]]$Apps=@(),[bool]$Complete=$true);[pscustomobject]@{Apps=$Apps;Complete=$Complete}}
function Dependencies {param([object[]]$Entries=@(),[DateTime]$CapturedUtc=[DateTime]::UtcNow,[bool]$Complete=$true);[pscustomobject]@{Entries=$Entries;CapturedUtc=$CapturedUtc;Complete=$Complete}}
Check 'Runtime policy is readonly with schema and explicit budgets' {$p=Get-MCDiskOwnerPolicy;Assert ($p.governs-eq'product_runtime'-and-not$p.executionEnabled-and-not$p.collectCommandLine-and-not$p.inferRemovalFromAbsence);$schema=Get-Content (Join-Path $projectRoot 'app\owner-analysis-policy.schema.json') -Raw|ConvertFrom-Json;Assert ($schema.properties.executionEnabled.const-eq$false-and$schema.properties.inferRemovalFromAbsence.const-eq$false)}
Check 'Installed path metadata is positive evidence but never delete authority' {$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\App\cache.bin' (Inventory @((App 'C:\Fixture\App')));Assert ($r.State-eq'InstalledMetadataProtected'-and-not$r.DeletionAllowed-and$r.Matches.Count-eq1)}
Check 'Sibling path and matching app name do not prove data ownership' {$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\App-other\cache.bin' (Inventory @((App 'C:\Fixture\App')));Assert ($r.State-eq'UnknownProtected');$r=Resolve-MCDiskOwnerEvidence 'C:\Users\Fixture\AppData\Local\Example\cache.bin' (Inventory @((App 'C:\Fixture\App' 'Example')));Assert ($r.State-eq'UnknownProtected')}
Check 'Duplicate 32/64 metadata does not create a false shared-app warning' {$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\App\cache.bin' (Inventory @((App 'C:\Fixture\App'),(App 'c:\fixture\app' 'Example fixture app' 'HKCU/Registry32')));Assert ($r.State-eq'InstalledMetadataProtected')}
Check 'Overlapping locations from different applications remain shared/protected' {$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\Suite\Child\data.bin' (Inventory @((App 'C:\Fixture\Suite' 'Suite'),(App 'C:\Fixture\Suite\Child' 'Child')));Assert ($r.State-eq'SharedMetadataProtected'-and-not$r.DeletionAllowed)}
Check 'Process service and task references protect adjacent data, including portable apps' {foreach($kind in @('Process','Service','Task')){$deps=Dependencies @([pscustomobject]@{Kind=$kind;Name='Fixture';Executable='C:\Fixture\Portable\app.exe'});$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\Portable\data.bin' (Inventory) $deps;Assert ($r.State-eq'ReferencedProtected'-and$r.References[0].Kind-eq$kind-and-not$r.DeletionAllowed)}}
Check 'Stale and future dependency snapshots do not masquerade as current evidence' {foreach($date in @([DateTime]::UtcNow.AddHours(-1),[DateTime]::UtcNow.AddHours(1))){$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\Portable\data.bin' (Inventory) (Dependencies @([pscustomobject]@{Kind='Process';Name='Fixture';Executable='C:\Fixture\Portable\app.exe'}) $date);Assert (-not$r.DependencySnapshotFresh-and$r.State-eq'UnknownProtected')}}
Check 'Complete empty uninstall inventory and incomplete dependency inventory never prove removal' {foreach($complete in @($true,$false)){$r=Resolve-MCDiskOwnerEvidence 'C:\Fixture\RemovedName\database.db' (Inventory @() $complete) (Dependencies @() ([DateTime]::UtcNow) $false);Assert ($r.State-eq'UnknownProtected'-and$r.Risk-eq'Blocked'-and-not$r.DeletionAllowed)}}
Check 'Only unambiguous executable paths parsed; arguments are not retained' {Assert ((ConvertTo-MCDiskExecutablePath '"C:\Program Files\Fixture\svc.exe" -secret fixture')-eq'C:\Program Files\Fixture\svc.exe');Assert ((ConvertTo-MCDiskExecutablePath 'C:\Fixture\svc.exe -secret fixture')-eq'C:\Fixture\svc.exe');foreach($value in @('C:\Program Files\Fixture\svc.exe -run','%LOCALAPPDATA%\Fixture\svc.exe','svc.exe','\\server\share\svc.exe','C:\Fixture\svc.exe:stream')){Assert ($null-eq(ConvertTo-MCDiskExecutablePath $value))}}
Check 'Dependency collector handles inaccessible and ambiguous sources with no false completeness' {
    $r=& (Get-Module MemoryClear.Disk) {
        function Get-CimInstance {param($ClassName,$Property,$OperationTimeoutSec,$Namespace,$ErrorAction)
            if($ClassName-eq'Win32_Process'){return @([pscustomobject]@{ProcessId=1;Name='Fixture';ExecutablePath='C:\Fixture\app.exe'},[pscustomobject]@{ProcessId=2;Name='Unknown';ExecutablePath=$null})}
            if($ClassName-eq'Win32_Service'){return @([pscustomobject]@{Name='Fixture service';State='Stopped';PathName='"C:\Fixture\svc.exe" -private'})}
            throw 'Injected task provider unavailable'
        }
        Get-MCDiskDependencyInventory
    }
    Assert (-not$r.Complete-and$r.Entries.Count-eq2-and$r.Issues.Count-eq1) ($r|ConvertTo-Json -Depth 5 -Compress);Assert ($r.Entries[1].Executable-eq'C:\Fixture\svc.exe')
}
Check 'Complete synthetic collector handles task executable paths with spaces without logging arguments' {
    $r=& (Get-Module MemoryClear.Disk) {
        function Get-CimInstance {param($ClassName,$Property,$OperationTimeoutSec,$Namespace,$ErrorAction)
            if($Property-contains'CommandLine'){throw 'CommandLine must never be requested'}
            if($ClassName-eq'Win32_Process'){return [pscustomobject]@{ProcessId=1;Name='Fixture';ExecutablePath='C:\Fixture\app.exe'}}
            if($ClassName-eq'Win32_Service'){return [pscustomobject]@{Name='Fixture service';State='Stopped';PathName='"C:\Fixture\svc.exe" -private'}}
            return [pscustomobject]@{TaskName='Fixture task';Actions=@([pscustomobject]@{Execute='C:\Program Files\Fixture\task.exe';Arguments='private fixture'})}
        }
        Get-MCDiskDependencyInventory
    }
    Assert ($r.Complete-and$r.Entries.Count-eq3-and$r.Entries[2].Executable-eq'C:\Program Files\Fixture\task.exe')
    Assert (($r.Entries|ConvertTo-Json -Compress)-notlike'*private*') 'Arguments leaked into stored evidence'
}
Check 'Page analysis preserves snapshot/data; injected inventory cannot analyze user paths' {
    $root=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null;[IO.File]::WriteAllText((Join-Path $root '.memoryclear-fixture'),'Readonly ownership fixture');$file=Join-Path $root 'data.txt';[IO.File]::WriteAllText($file,'Keep fixture');$hash=(Get-FileHash -LiteralPath $file).Hash
    $scan=Get-MCDiskScan -FixtureRoots @($root);$r=Get-MCDiskOwnerAnalysis $scan -FixtureInventory (Inventory @((App $root))) -FixtureDependencies (Dependencies)
    Assert ($r.Rows.Count-eq$scan.Rows.Count-and$r.Rows[0].OwnerEvidence.State-eq'InstalledMetadataProtected'-and-not$r.Rows[0].DeletionEnabled-and(Get-FileHash -LiteralPath $file).Hash-eq$hash)
    Assert (-not$scan.PSObject.Properties['OwnershipAnalyzed']) 'Original scan was mutated'
    $scan.Fixture=$false;$failed=$false;try{Get-MCDiskOwnerAnalysis $scan -FixtureInventory (Inventory)|Out-Null}catch{$failed=$true};Assert $failed
}
Check 'Cancellation returns cancelled state without inventing cleanup or removing scan rows' {
    $token=New-Object Threading.CancellationTokenSource;try{$token.Cancel();$scan=[pscustomobject]@{Rows=@();Status='CompletedReadonly';Message='Original';Fixture=$false};$r=Get-MCDiskOwnerAnalysis $scan -CancellationToken $token.Token;Assert ($r.Status-eq'Cancelled'-and$r.Rows.Count-eq0)}finally{$token.Dispose()}
}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=$results.ToArray();Scope='Readonly ownership/dependency classification with synthetic inventory and marked files; CIM collector uses injected providers, no real app inventory scanned';RealUserCleanupExecuted=$false;Unverified=@('Native CIM/registry/MSIX live coverage and cancellation latency','Vendor/historical uninstall/cache-empty positive proofs','Windows10/11 VM/operator DPI/keyboard')}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $projectRoot 'docs\verification\disk-ownership-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize|Out-String|Write-Output
if($report.Failed-gt0){exit 1}
