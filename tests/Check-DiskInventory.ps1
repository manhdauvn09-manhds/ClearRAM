#requires -version 5.1
param()
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$fixtureRoot=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $fixtureRoot '.memoryclear-fixture'),'Disposable fixture created by Check-DiskInventory.ps1')
$results=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Condition,[string]$Message='Assertion failed');if(-not$Condition){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1') -Force
$oldFile=Join-Path $fixtureRoot 'old-temp.bin';[IO.File]::WriteAllBytes($oldFile,(New-Object byte[] 8192));[IO.File]::SetLastWriteTimeUtc($oldFile,[DateTime]::UtcNow.AddDays(-10))
$fresh=Join-Path $fixtureRoot 'recent-temp.txt';[IO.File]::WriteAllText($fresh,'Keep recent file')
$large=Join-Path $fixtureRoot 'large-personal.iso';$stream=[IO.File]::OpenWrite($large);try{$stream.SetLength(2MB)}finally{$stream.Dispose()}
$nested=Join-Path $fixtureRoot 'nested';New-Item -ItemType Directory -Path $nested|Out-Null;[IO.File]::WriteAllText((Join-Path $nested 'child.txt'),'Nested file')
$hashBefore=(Get-FileHash -LiteralPath $oldFile -Algorithm SHA256).Hash
Check 'PS5 sources parse and runtime policy stays readonly' {
    foreach($file in @((Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1'),$PSCommandPath)){$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null;Assert ($errors.Count-eq0)}
    $p=Get-MCDiskPolicy;Assert (-not$p.executionEnabled-and-not$p.privilegedWrites-and-not$p.followReparsePoints);Assert ($p.levels.Count-eq3)
}
Check 'Native file identity, allocated size and metadata from handle' {
    $a=[MemoryClear.Storage.FileInventory]::Snapshot($oldFile,$fixtureRoot);$b=[MemoryClear.Storage.FileInventory]::Snapshot($oldFile,$fixtureRoot)
    Assert ($a.Identity-eq$b.Identity);Assert ($a.LogicalBytes-eq8192-and$a.AllocatedBytes-ge8192-and$a.Links-eq1);Assert ($a.LastWriteFileTime-eq[IO.File]::GetLastWriteTimeUtc($oldFile).ToFileTimeUtc())
}
Check 'Native scan nested fixtures and readonly data survives' {
    $script:scan=Get-MCDiskScan -FixtureRoots @($fixtureRoot);Assert ($scan.Rows.Count-ge5);Assert (-not$scan.ExecutionEnabled);Assert ((Get-FileHash -LiteralPath $oldFile -Algorithm SHA256).Hash-eq$hashBefore);Assert (Test-Path -LiteralPath $fresh)
    Assert (@($scan.Rows|Where-Object{$_.Name-eq'old-temp.bin'-and$_.Risk-eq'SafeCandidate'}).Count-eq1)
    Assert (@($scan.Rows|Where-Object{$_.Name-eq'recent-temp.txt'-and$_.Risk-eq'KeepRecent'}).Count-eq1)
}
Check 'Age differs from deletion authority; all rows have deletion disabled' {foreach($row in $scan.Rows){Assert (-not$row.DeletionEnabled);Assert (-not[string]::IsNullOrEmpty($row.Snapshot.Identity))} }
Check 'Overlapping roots dedupe file IDs and allocated bytes' {
    $once=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot),0,100,1000,10,[Threading.CancellationToken]::None)
    $twice=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot,$nested),0,100,1000,10,[Threading.CancellationToken]::None)
    Assert ($once.AllocatedBytes-eq$twice.AllocatedBytes-and$once.Files.Count-eq$twice.Files.Count);Assert ($twice.Duplicates-ge1)
}
Check 'Row/entry budget reports partial instead of silent completeness' {
    $limited=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot),0,1,100,10,[Threading.CancellationToken]::None);Assert ($limited.Files.Count-eq1-and$limited.Truncated)
    $entries=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot),0,100,1,10,[Threading.CancellationToken]::None);Assert ($entries.Visited-eq1-and$entries.Truncated)
}
Check 'Paged scan gives distinct next-page file IDs within bounded rows' {
    $first=[MemoryClear.Storage.FileInventory]::ScanPage([string[]]@($fixtureRoot),0,2,1000,10,0,[Threading.CancellationToken]::None)
    $next=[MemoryClear.Storage.FileInventory]::ScanPage([string[]]@($fixtureRoot),0,2,1000,10,2,[Threading.CancellationToken]::None)
    Assert ($first.HasMore-and$first.Files.Count-eq2-and$next.Files.Count-eq2);foreach($file in $first.Files){Assert (@($next.Files|Where-Object{$_.Identity-eq$file.Identity}).Count-eq0)}
}
Check 'Cancelled scan returns no success claim' {
    $cancel=New-Object Threading.CancellationTokenSource;try{$cancel.Cancel();$r=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot),0,100,100,10,$cancel.Token);Assert ($r.Cancelled-and$r.Files.Count-eq0)}finally{$cancel.Dispose()}
}
Check 'Missing/inaccessible root has issue instead of zero-green' {
    $r=[MemoryClear.Storage.FileInventory]::Scan([string[]]@((Join-Path $fixtureRoot 'missing')),0,100,100,10,[Threading.CancellationToken]::None);Assert ($r.Skipped-gt0-and$r.Issues.Count-gt0)
}
Check 'UNC/ADS/outside snapshot paths refused' {
    foreach($path in @('\\server\share\file','C:\temp\file:stream','C:\')){$blocked=$false;try{[MemoryClear.Storage.FileInventory]::Canonical($path)|Out-Null}catch{$blocked=$true};Assert $blocked}
    Assert (-not[MemoryClear.Storage.FileInventory]::Within(($fixtureRoot+'-other\file'),$fixtureRoot))
    $blocked=$false;try{[MemoryClear.Storage.FileInventory]::Snapshot($fresh,$nested)|Out-Null}catch{$blocked=$true};Assert $blocked
}
Check 'Hard links are excluded; junction recursion skipped' {
    $hard=Join-Path $fixtureRoot 'hard-alias.bin';New-Item -ItemType HardLink -Path $hard -Target $oldFile|Out-Null
    $junction=Join-Path $fixtureRoot 'junction';New-Item -ItemType Junction -Path $junction -Target $nested|Out-Null
    $r=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot),0,100,1000,10,[Threading.CancellationToken]::None)
    Assert ($r.Skipped-ge3);Assert (@($r.Files|Where-Object{$_.Path-eq$oldFile-or$_.Path-eq$hard-or$_.Path-like'*\junction\*'}).Count-eq0)
    $blocked=$false;try{[MemoryClear.Storage.FileInventory]::Snapshot((Join-Path $junction 'child.txt'),$fixtureRoot)|Out-Null}catch{$blocked=$true};Assert $blocked
}
Check 'Large-file mode filters threshold without content read or deletion' {
    $r=Get-MCDiskScan -IncludeLargeFiles -MinimumMB 1 -FixtureRoots @($fixtureRoot);Assert ($r.Rows.Count-eq1-and$r.Rows[0].Name-eq'large-personal.iso');Assert (Test-Path -LiteralPath $large)
    Assert ($r.Rows[0].Risk-eq'NeedsReview'-and-not$r.Rows[0].DeletionEnabled)
}
Check 'Finder age/type filters are applied before pagination and totals' {
    $older=Join-Path $fixtureRoot 'old-personal.iso';$stream=[IO.File]::Create($older);try{$stream.SetLength(1MB)}finally{$stream.Dispose()};[IO.File]::SetLastWriteTimeUtc($older,[DateTime]::UtcNow.AddDays(-90))
    $r=Get-MCDiskScan -IncludeLargeFiles -MinimumMB 1 -MinimumAgeDays 30 -Extensions @('.ISO') -FixtureRoots @($fixtureRoot)
    Assert ($r.Rows.Count-eq1-and$r.Rows[0].Name-eq'old-personal.iso'-and$r.Rows[0].Risk-eq'NeedsReview')
    Assert ($r.Matched-eq1-and$r.LogicalBytes-eq1MB)
    $next=[MemoryClear.Storage.FileInventory]::ScanFilteredPage([string[]]@($fixtureRoot),1MB,[DateTime]::UtcNow.AddDays(-30).ToFileTimeUtc(),[string[]]@('.iso'),1,1000,10,1,[Threading.CancellationToken]::None)
    Assert ($next.Files.Count-eq0-and$next.Matched-eq1-and-not$next.HasMore)
}
Check 'Invalid finder extension and custom protected scope fail closed' {
    foreach($ext in @('*.iso','.iso:secret','..\iso')){$failed=$false;try{Get-MCDiskScan -IncludeLargeFiles -MinimumMB 1 -Extensions @($ext) -FixtureRoots @($fixtureRoot)|Out-Null}catch{$failed=$true};Assert $failed}
    $failed=$false;try{Get-MCDiskScan -IncludeLargeFiles -UserRoots @($env:SystemRoot)|Out-Null}catch{$failed=$true};Assert $failed
    $failed=$false;try{Get-MCDiskScan -UserRoots @($fixtureRoot)|Out-Null}catch{$failed=$true};Assert $failed
}
Check 'App removal absence never marks unknown data safe' {
    foreach($complete in @($true,$false)){$owner=Get-MCDiskOwnership -Path $fixtureRoot -Inventory ([pscustomobject]@{Complete=$complete;Apps=@()});Assert ($owner.State-eq'UnknownProtected'-and-not$owner.DeletionAllowed)}
}
Check 'Denied fixture directory reported as partial with original ACL restored' {
    $denied=Join-Path $fixtureRoot 'denied';New-Item -ItemType Directory -Path $denied|Out-Null
    $acl=Get-Acl -LiteralPath $denied;$sddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
    try{
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::ReadAndExecute,[Security.AccessControl.AccessControlType]::Deny)
        $acl.AddAccessRule($rule);Set-Acl -LiteralPath $denied -AclObject $acl
        $r=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($denied),0,100,100,10,[Threading.CancellationToken]::None);Assert ($r.Skipped-gt0-and$r.Issues.Count-gt0)
    }finally{$restore=New-Object Security.AccessControl.DirectorySecurity;$restore.SetSecurityDescriptorSddlForm($sddl);Set-Acl -LiteralPath $denied -AclObject $restore}
}
Check 'Long path is either reported or safely skipped, never false-complete' {
    $path=Join-Path $fixtureRoot 'longpaths'
    for($i=0;$i-lt9;$i++){$path=Join-Path $path ('segment-'+('x'*20))}
    [IO.Directory]::CreateDirectory(('\\?\'+$path))|Out-Null
    [IO.File]::WriteAllText(('\\?\'+(Join-Path $path 'long-file.txt')),'Long path fixture')
    $r=[MemoryClear.Storage.FileInventory]::Scan([string[]]@($fixtureRoot),0,1000,1000,10,[Threading.CancellationToken]::None)
    Assert (@($r.Files|Where-Object{$_.Path-like'*\long-file.txt'}).Count-eq1-or$r.Issues.Count-gt0)
}
Check 'Cloud/protected/root boundaries block scan scope' {
    $c=[pscustomobject]@{OSRoot='C:\Windows';CloudInventoryKnown=$true;CloudRoots=@('C:\Users\Test\OneDrive')}
    Assert (-not(Test-MCDiskScanRoot 'C:\Windows\Temp' $c));Assert (-not(Test-MCDiskScanRoot 'C:\Users\Test\OneDrive\Files' $c));Assert (-not(Test-MCDiskScanRoot 'D:\Other' $c))
    Assert (-not(Test-MCDiskScanRoot 'C:\Users\Test' $c)) 'Ancestor scope must not include a known cloud root'
    Assert (Test-MCDiskScanRoot 'C:\Users\Test\Videos' $c);$c.CloudInventoryKnown=$false;Assert (-not(Test-MCDiskScanRoot 'C:\Users\Test\Videos' $c))
}
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($results|Where-Object{$_.Passed}).Count;Failed=@($results|Where-Object{-not$_.Passed}).Count;Results=$results.ToArray();Mode='Readonly native file scan on marked fixtures only';WorkingSetMB=[Math]::Round([Diagnostics.Process]::GetCurrentProcess().WorkingSet64/1MB,1);FixtureRelative=('artifacts\'+[IO.Path]::GetFileName($fixtureRoot));RealCleanupExecuted=$false;Unverified=@('Windows10/11 VM matrix','Real app ownership/vendor rules','Large-scale streaming/soak benchmark')}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $projectRoot 'docs\verification\disk-inventory-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize|Out-String|Write-Output
Write-Output ("Disk readonly tests: $($report.Passed) passed; $($report.Failed) failed; working set $($report.WorkingSetMB) MB. Disposable fixtures retained for inspection.")
if($report.Failed-gt0){exit 1}
