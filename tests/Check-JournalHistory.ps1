#requires -version 5.1
# CD-04 read-only journal history: chain verification and run summary.
# Fixture journals live under artifacts\journal-fixture-*; the real .data is only read and must stay byte-identical.
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $projectRoot
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1') -DisableNameChecking
Import-Module (Join-Path $projectRoot 'app\CleanData\JournalHistory.psm1') -Force
$checks=New-Object 'System.Collections.Generic.List[object]'
function Assert {param([bool]$Value,[string]$Message='Assertion failed');if(-not$Value){throw $Message}}
function Check {param([string]$Name,[scriptblock]$Action);try{&$Action;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Hash {param([string]$Text);$h=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$h.Dispose()}}
function Chain {param([object[]]$Events);$prev='0'*64;$n=0;foreach($e in $Events){$n++;$payload=$e|ConvertTo-Json -Depth 8 -Compress;$h=Hash ($prev+"`n"+$payload);[pscustomobject]@{Sequence=$n;PreviousHash=$prev;Payload=$payload;Hash=$h}|ConvertTo-Json -Compress;$prev=$h}}
function Journal {param([string]$Type,[string[]]$Lines,[switch]$NoFinalNewline);$id=[guid]::NewGuid().ToString('N');$path=Join-Path $data ($Type+'-operation-'+$id+'.jsonl');$text=($Lines-join"`n");if(-not$NoFinalNewline-and$Lines.Count){$text+="`n"};[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)));$path}
function Ev {param([string]$Kind,[hashtable]$More=@{});$o=[ordered]@{Kind=$Kind};foreach($k in $More.Keys){$o[$k]=$More[$k]};$o['Utc']=[DateTime]::UtcNow.ToString('o');[pscustomobject]$o}
$fixture=Join-Path $projectRoot ('artifacts\journal-fixture-'+[guid]::NewGuid().ToString('N'));$data=Join-Path $fixture '.data';New-Item -ItemType Directory -Path $data -Force|Out-Null
$tempPlan=Ev 'Plan' @{Capability='ReviewedTopLevelOwnTemp';Items=@(@{Id='A'},@{Id='B'})}
$tempRun=@($tempPlan,(Ev 'Item' @{Identity='A';Stage='Committed'}),(Ev 'Outcome' @{Identity='A';Status='Deleted'}),(Ev 'Item' @{Identity='B';Stage='SourceLocked'}),(Ev 'Outcome' @{Identity='B';Status='Skipped'}),(Ev 'Finished' @{Status='Partial'}))
$memPlan=Ev 'Plan' @{Capability='OptInGracefulOnly';Items=@(@{Pid=1},@{Pid=2})}

Check 'Valid temp chain is summarised from its own entries' {$r=Test-MCJournal (Journal 'temp' @(Chain $tempRun));Assert ($r.Integrity-eq'Valid'-and$r.Type-eq'Temp'-and$r.Status-eq'Partial'-and$r.Items-eq2-and$r.Done-eq1-and$r.Skipped-eq1-and$r.Entries-eq6-and$r.Capability-eq'ReviewedTopLevelOwnTemp') ($r|ConvertTo-Json -Compress)}
Check 'Memory run without Finished is reported Interrupted, not Completed' {$r=Test-MCJournal (Journal 'memory' @(Chain @($memPlan,(Ev 'Outcome' @{Result=@{Status='Exited'}}))));Assert ($r.Integrity-eq'Valid'-and$r.Status-eq'Interrupted'-and$r.Done-eq1) ($r|ConvertTo-Json -Compress)}
Check 'Held memory outcomes are counted as held' {$r=Test-MCJournal (Journal 'memory' @(Chain @($memPlan,(Ev 'Outcome' @{Result=@{Status='HeldTimeout'}}),(Ev 'Outcome' @{Result=@{Status='Exited'}}),(Ev 'Finished' @{Status='Partial'}))));Assert ($r.Held-eq1-and$r.Done-eq1-and$r.Status-eq'Partial') ($r|ConvertTo-Json -Compress)}
Check 'Edited payload breaks the chain' {$l=@(Chain $tempRun);$e=$l[2]|ConvertFrom-Json;$e.Payload=$e.Payload.Replace('Deleted','Skipped');$l[2]=$e|ConvertTo-Json -Compress;$r=Test-MCJournal (Journal 'temp' $l);Assert ($r.Integrity-eq'Broken'-and$r.Problem.Contains('3')-and$r.Status-eq'Unknown') ($r|ConvertTo-Json -Compress)}
Check 'Removed line (sequence gap) breaks the chain' {$l=[Collections.ArrayList]@(Chain $tempRun);$l.RemoveAt(3);$r=Test-MCJournal (Journal 'temp' @($l));Assert ($r.Integrity-eq'Broken') ($r|ConvertTo-Json -Compress)}
Check 'Reordered lines break the chain' {$l=@(Chain $tempRun);$t=$l[1];$l[1]=$l[2];$l[2]=$t;$r=Test-MCJournal (Journal 'temp' $l);Assert ($r.Integrity-eq'Broken') ($r|ConvertTo-Json -Compress)}
Check 'Truncated last line is detected' {$l=@(Chain $tempRun);$l[-1]=$l[-1].Substring(0,20);$r=Test-MCJournal (Journal 'temp' $l -NoFinalNewline);Assert ($r.Integrity-eq'Broken') ($r|ConvertTo-Json -Compress)}
Check 'First entry must be the Plan' {$r=Test-MCJournal (Journal 'temp' @(Chain @((Ev 'Finished' @{Status='Completed'}))));Assert ($r.Integrity-eq'Broken'-and$r.Status-ne'Completed') ($r|ConvertTo-Json -Compress)}
Check 'Test-only journal without a chain is NotChain, not a false alarm' {$r=Test-MCJournal (Journal 'temp' @('{"Kind":"TestOnly","Deleted":false}'));Assert ($r.Integrity-eq'NotChain'-and$r.Status-eq'Unknown') ($r|ConvertTo-Json -Compress)}
Check 'Empty journal is Empty' {$r=Test-MCJournal (Journal 'temp' @());Assert ($r.Integrity-eq'Empty') ($r|ConvertTo-Json -Compress)}
Check 'Journal still open by the writer can be read without blocking it' {$id=[guid]::NewGuid().ToString('N');$log=New-Object MemoryClear.Storage.FileInventory+TempLedger($fixture,$id);try{foreach($line in @(Chain @($tempPlan))){$log.Append($line)};$r=Test-MCJournal (Join-Path $data ('temp-operation-'+$id+'.jsonl'));Assert ($r.Integrity-eq'Valid'-and$r.Status-eq'Interrupted') ($r|ConvertTo-Json -Compress);foreach($line in @(Chain @($tempPlan,(Ev 'Finished' @{Status='Completed'})))[1]){$log.Append($line)}}finally{$log.Dispose()};$r=Test-MCJournal (Join-Path $data ('temp-operation-'+$id+'.jsonl'));Assert ($r.Status-eq'Completed') 'Writer could not continue after read'}
Check 'History filters by name pattern, type and limit' {[IO.File]::WriteAllText((Join-Path $data 'temp-operation-notanid.jsonl'),'x');[IO.File]::WriteAllText((Join-Path $data 'settings.json'),'{}');$all=@(Get-MCJournalHistory -ProjectRoot $fixture -Limit 500);Assert (@($all|Where-Object{$_.File-eq'temp-operation-notanid.jsonl'-or$_.File-eq'settings.json'}).Count-eq0) 'Non-journal file listed';$mem=@(Get-MCJournalHistory -ProjectRoot $fixture -Type Memory);Assert ($mem.Count-ge2-and@($mem|Where-Object{$_.Type-ne'Memory'}).Count-eq0) 'Type filter';Assert (@(Get-MCJournalHistory -ProjectRoot $fixture -Limit 2).Count-eq2) 'Limit'}
Check 'Missing .data gives an empty history' {Assert (@(Get-MCJournalHistory -ProjectRoot (Join-Path $fixture 'nowhere')).Count-eq0)}
Check 'Real .data journals are read without any change' {
    $dir=Join-Path $projectRoot '.data';$before=@{};foreach($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*-operation-*.jsonl' -ErrorAction SilentlyContinue)){$before[$f.Name]=@($f.Length,$f.LastWriteTimeUtc.Ticks,(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)}
    $h=@(Get-MCJournalHistory -ProjectRoot $projectRoot -Limit 500);$script:realSummary=@($h|Group-Object Type,Integrity|ForEach-Object{[pscustomobject]@{Group=$_.Name;Count=$_.Count}})
    foreach($name in $before.Keys){$f=Get-Item -LiteralPath (Join-Path $dir $name);Assert ($f.Length-eq$before[$name][0]-and$f.LastWriteTimeUtc.Ticks-eq$before[$name][1]-and(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash-eq$before[$name][2]) "Journal changed: $name"}
    Assert ($h.Count-eq[Math]::Min(500,$before.Count)) 'Not every real journal was read'}
Check 'CLI History returns JSON and exit code 0' {$out=& powershell -NoProfile -File (Join-Path $projectRoot 'MemoryClear.Cli.ps1') History -Limit 2 -Json;Assert ($LASTEXITCODE-eq0) "exit $LASTEXITCODE";$j=($out-join"`n")|ConvertFrom-Json;Assert (@($j).Count-le2-and($j.Count-eq0-or@($j)[0].PSObject.Properties['Integrity'])) 'Unexpected CLI output'}

Remove-Item -LiteralPath $fixture -Recurse -Force
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=@($checks|Where-Object{$_.Passed}).Count;Failed=@($checks|Where-Object{-not$_.Passed}).Count;Checks=$checks.ToArray();RealJournals=$script:realSummary;Scope='Read-only journal history: fixture journals under artifacts (deleted after run); real .data journals only read and verified unchanged';Limits=@('Unkeyed SHA256 chain detects corruption/truncation/reordering, not a deliberate rewrite of the whole chain','No GUI history view yet')}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $projectRoot 'docs\verification\journal-history-tests.json') -Encoding UTF8
Write-Host ('Journal history: '+$report.Passed+' passed, '+$report.Failed+' failed')
if($report.Failed){$report.Checks|Where-Object{-not$_.Passed}|Format-List;exit 1}
