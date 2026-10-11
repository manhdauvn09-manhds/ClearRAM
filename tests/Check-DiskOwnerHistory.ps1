#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1') -Force
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Fixture {
    $root=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'))
    $file=Join-Path $root 'Local\Google\Chrome\User Data\Default\Cache\data'
    New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force|Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.memoryclear-fixture'),'History fixture')
    [IO.File]::WriteAllText($file,'Unchanged fixture data')
    [pscustomobject]@{Root=$root;File=$file;History=(Join-Path $root '.data\disk-owner-history.json');Scan=(Get-MCDiskScan -AppData -FixtureRoots @($root))}
}
$installed=[pscustomobject]@{Complete=$true;Apps=@([pscustomobject]@{Name='Google Chrome';Publisher='Google LLC';Source='CurrentUser/Registry64';InstallationId='CurrentUser/Registry64/FixtureChrome';Version='1.2.3';Location='C:\Fixture\Chrome'})}
$absent=[pscustomobject]@{Complete=$true;Apps=@()}
function Deps {param([bool]$Complete=$true);[pscustomobject]@{Complete=$Complete;Entries=@();CapturedUtc=[DateTime]::UtcNow}}
function Observe {param($Fixture,$Inventory=$installed,$Dependencies=(Deps));Update-MCDiskObservationHistory $Fixture.Scan $Inventory $Dependencies -FixtureDirectory $Fixture.Root}
function MutateHistory {param($Fixture,[scriptblock]$Change)
    $envelope=[IO.File]::ReadAllText($Fixture.History)|ConvertFrom-Json;$data=$envelope.Payload|ConvertFrom-Json;&$Change $data
    $payload=$data|ConvertTo-Json -Depth 12 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    [IO.File]::WriteAllText($Fixture.History,([pscustomobject]@{Payload=$payload;Sha256=$hash}|ConvertTo-Json -Compress))
}
Check 'History policy bounded readonly and own-metadata storage' {$p=Get-MCDiskHistoryPolicy;Assert (-not$p.executionEnabled-and$p.maximumProfiles-eq20-and$p.maximumBytes-eq262144)}
$fixture=Fixture
Check 'First observed install records provenance and version under marked fixture only' {$r=Observe $fixture;Assert ($r.Status-eq'Saved'-and$r.Saved-and$r.Profiles['chrome-stable'].State-eq'ObservedInstalled') ($r|ConvertTo-Json -Depth 5 -Compress);$text=[IO.File]::ReadAllText($fixture.History);Assert ($text.Contains('FixtureChrome')-and$text.Contains('1.2.3')-and-not$r.DeletionAllowed)}
Check 'Later missing metadata surfaces prior observation without verifying uninstall' {$r=Get-MCDiskOwnerAnalysis $fixture.Scan -FixtureInventory $absent -FixtureDependencies (Deps) -FixtureHistoryDirectory $fixture.Root;Assert ($r.Rows[0].OwnerEvidence.State-eq'PreviouslyObservedMissingProtected'-and-not$r.Rows[0].OwnerEvidence.DeletionAllowed-and$r.ObservationHistory.Saved) ($r|ConvertTo-Json -Depth 6 -Compress)}
Check 'Missing from first observation never manufactures historical install evidence' {$f=Fixture;$r=Observe $f $absent;Assert ($r.Profiles['chrome-stable'].State-eq'NoInstalledHistory'-and$null-eq$r.Profiles['chrome-stable'].LastInstalledUtc)}
Check 'Incomplete inventory and dependency evidence still block lifecycle promotion' {$i=[pscustomobject]@{Complete=$false;Apps=@()};$r=Get-MCDiskOwnerAnalysis $fixture.Scan -FixtureInventory $i -FixtureDependencies (Deps $false) -FixtureHistoryDirectory $fixture.Root;Assert ($r.Rows[0].OwnerEvidence.State-eq'UnknownLifecycleProtected'-and$r.Status-eq'Partial')}
Check 'Active reference overrides historical missing metadata' {$d=Deps;$d.Entries=@([pscustomobject]@{Kind='Process';Name='Fixture';Executable='C:\Fixture\chrome.exe'});$r=Get-MCDiskOwnerAnalysis $fixture.Scan -FixtureInventory $absent -FixtureDependencies $d -FixtureHistoryDirectory $fixture.Root;Assert ($r.Rows[0].OwnerEvidence.State-eq'PossibleReferenceProtected')}
Check 'Corrupted history stays untouched and reports unavailable rather than empty/green' {$f=Fixture;Observe $f|Out-Null;[IO.File]::AppendAllText($f.History,'broken');$before=(Get-FileHash $f.History).Hash;$r=Observe $f;Assert ($r.Status-eq'Unavailable'-and-not$r.Saved-and$r.Profiles.Count-eq0-and(Get-FileHash $f.History).Hash-eq$before)}
Check 'Changed catalog starts new baseline, never carries previous installed evidence' {$f=Fixture;Observe $f|Out-Null;MutateHistory $f {param($d);$d.CatalogHash=('0'*64)};$r=Observe $f $absent;Assert ($r.Status-eq'CatalogReset'-and$r.Profiles['chrome-stable'].State-eq'CatalogChanged'-and$null-eq$r.Profiles['chrome-stable'].LastInstalledUtc)}
Check 'Different SID and future timestamp reject history without overwriting it' {foreach($mode in @('sid','future')){$f=Fixture;Observe $f|Out-Null;if($mode-eq'sid'){MutateHistory $f {param($d);$d.Sid='S-1-5-21-999-999-999-999'}}else{MutateHistory $f {param($d);$d.UpdatedUtc=[DateTime]::UtcNow.AddDays(1).ToString('o')}};$before=(Get-FileHash $f.History).Hash;$r=Observe $f;Assert ($r.Status-eq'Unavailable'-and(Get-FileHash $f.History).Hash-eq$before) $mode}}
Check 'Expired installed observation is displayed but cannot promote a residual' {$f=Fixture;Observe $f|Out-Null;MutateHistory $f {param($d);$d.Records[0].LastInstalledUtc=[DateTime]::UtcNow.AddDays(-200).ToString('o')};$r=Get-MCDiskOwnerAnalysis $f.Scan -FixtureInventory $absent -FixtureDependencies (Deps) -FixtureHistoryDirectory $f.Root;Assert ($r.Rows[0].OwnerEvidence.State-eq'ResidualCandidateUnverified'-and$r.ObservationHistory.Profiles['chrome-stable'].State-eq'HistoryExpired')}
Check 'Changed root identity clears previous installed association' {$f=Fixture;Observe $f|Out-Null;MutateHistory $f {param($d);$d.Records[0].RootIdentity='00000000:0000000000000000'};$r=Observe $f $absent;Assert ($r.Profiles['chrome-stable'].State-eq'NoInstalledHistory')}
Check 'Root changed after scan reports partial and cannot use old identity' {$f=Fixture;Observe $f|Out-Null;$f.Scan.AppRootObservations[0].Probe.Identity='00000000:0000000000000000';$r=Observe $f $absent;Assert ($r.Status-eq'Partial'-and$r.Profiles['chrome-stable'].State-eq'RootChanged')}
Check 'Concurrent history handle causes unavailable, with file bytes preserved' {$before=(Get-FileHash $fixture.History).Hash;$store=[MemoryClear.Storage.FileInventory]::OpenObservationStore($fixture.Root,262144);try{$r=Observe $fixture;Assert ($r.Status-eq'Unavailable'-and-not$r.Saved)}finally{$store.Dispose()};Assert ((Get-FileHash $fixture.History).Hash-eq$before)}
Check 'History hardlink and data-directory junction are rejected before writing' {
    $f=Fixture;New-Item -ItemType Directory -Path (Join-Path $f.Root '.data')|Out-Null;$target=Join-Path $f.Root 'target.json';[IO.File]::WriteAllText($target,'Preserve target');New-Item -ItemType HardLink -Path $f.History -Target $target|Out-Null;$r=Observe $f;Assert ($r.Status-eq'Unavailable'-and[IO.File]::ReadAllText($target)-eq'Preserve target')
    $g=Fixture;$outside=Join-Path $g.Root 'target-dir';New-Item -ItemType Directory -Path $outside|Out-Null;New-Item -ItemType Junction -Path (Join-Path $g.Root '.data') -Target $outside|Out-Null;$r=Observe $g;Assert ($r.Status-eq'Unavailable'-and-not(Test-Path (Join-Path $outside 'disk-owner-history.json')))
}
Check 'Cancellation and fixture-default analysis do not create a production or fixture history' {$f=Fixture;$cts=New-Object Threading.CancellationTokenSource;try{$cts.Cancel();$r=Update-MCDiskObservationHistory $f.Scan $installed (Deps) -FixtureDirectory $f.Root -CancellationToken $cts.Token;Assert ($r.Status-eq'Cancelled'-and-not(Test-Path $f.History))}finally{$cts.Dispose()};$r=Get-MCDiskOwnerAnalysis $f.Scan -FixtureInventory $installed -FixtureDependencies (Deps);Assert ($r.ObservationHistory.Status-eq'FixtureNotPersisted'-and-not(Test-Path $f.History))}
Check 'Fixture history cannot write to arbitrary directory or non-fixture scan' {$f=Fixture;$f.Scan.Fixture=$false;$failed=$false;try{Observe $f|Out-Null}catch{$failed=$true};Assert ($failed-and-not(Test-Path $f.History))}
Check 'App data unchanged and history never grants deletion' {Assert ([IO.File]::ReadAllText($fixture.File)-eq'Unchanged fixture data');$r=Observe $fixture $absent;Assert (-not$r.DeletionAllowed)}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=$results.ToArray();Scope='Marked native fixtures and synthetic metadata; writes only fixture own history, no real user data/history changes';Unverified=@('Actual install/uninstall events and native live coverage','Crash/power-loss VM and multi-user deployment','Production deletion authority')}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $projectRoot 'docs\verification\disk-owner-history-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize|Out-String|Write-Output
if($report.Failed){$results|Where-Object{-not$_.Passed}|Format-List|Out-String|Write-Output;exit 1}
