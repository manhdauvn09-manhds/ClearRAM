#requires -version 5.1
# Readonly evidence; never authorizes cleanup or infers an uninstall from absence.
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$script:OwnerProject=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function Get-MCDiskOwnerPolicy {
    $p=Get-Content -LiteralPath (Join-Path $script:OwnerProject 'app\owner-analysis-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $fields=@('$schema','schemaVersion','governs','mode','executionEnabled','maximumEntriesPerSource','cimTimeoutSeconds','freshnessSeconds','maximumRows','inferRemovalFromAbsence','collectCommandLine')
    foreach($name in $p.PSObject.Properties.Name){if($fields-notcontains$name){throw 'Unknown owner policy field.'}}
    if($p.schemaVersion-ne1-or$p.governs-ne'product_runtime'-or$p.mode-ne'Readonly'){throw 'Invalid owner analysis policy.'}
    foreach($name in @('executionEnabled','inferRemovalFromAbsence','collectCommandLine')){if($p.$name-isnot[bool]-or$p.$name-ne$false){throw 'Owner analysis cannot enable deletion, absence inference or command-line collection.'}}
    foreach($bound in @(@('maximumEntriesPerSource',1,10000),@('cimTimeoutSeconds',1,30),@('freshnessSeconds',1,300),@('maximumRows',1,1000))){$v=$p.($bound[0]);if($v-isnot[int]-or$v-lt$bound[1]-or$v-gt$bound[2]){throw 'Invalid owner analysis budget.'}}
    return $p
}
function ConvertTo-MCDiskExecutablePath {
    param([string]$Value,[switch]$ExecutableOnly)
    # Parse only an unambiguous quoted executable, or an absolute .exe without spaces.
    # Do not read/retain arguments, resolve PATH or expand environment variables.
    $text=$Value.Trim();$candidate=$null
    if($ExecutableOnly-and$text-match'^[A-Za-z]:\\[^"\r\n]+\.exe$'){$candidate=$text}
    elseif($text-match'^"([A-Za-z]:\\[^"\r\n]+\.exe)"(?:\s|$)'){$candidate=$Matches[1]}
    elseif($text-match'^([A-Za-z]:\\[^\s"\r\n]+\.exe)(?:\s|$)'){$candidate=$Matches[1]}
    if(-not$candidate){return $null}
    try{return [MemoryClear.Storage.FileInventory]::Canonical($candidate)}catch{return $null}
}
function Get-MCDiskDependencyInventory {
    param([Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $policy=Get-MCDiskOwnerPolicy;$entries=New-Object 'System.Collections.Generic.List[object]';$issues=New-Object 'System.Collections.Generic.List[string]';$sources=New-Object 'System.Collections.Generic.List[object]'
    foreach($kind in @('Process','Service','Task')){
        $complete=$true;$count=0
        try{
            $CancellationToken.ThrowIfCancellationRequested()
            $raw=if($kind-eq'Process'){Get-CimInstance -ClassName Win32_Process -Property ProcessId,Name,ExecutablePath -OperationTimeoutSec $policy.cimTimeoutSeconds -ErrorAction Stop}
            elseif($kind-eq'Service'){Get-CimInstance -ClassName Win32_Service -Property Name,State,PathName -OperationTimeoutSec $policy.cimTimeoutSeconds -ErrorAction Stop}
            else{Get-CimInstance -Namespace root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Property TaskName,Actions -OperationTimeoutSec $policy.cimTimeoutSeconds -ErrorAction Stop}
            foreach($entry in $raw){
                $CancellationToken.ThrowIfCancellationRequested();$count++;if($count-gt$policy.maximumEntriesPerSource){$complete=$false;$issues.Add($kind+':BudgetExceeded');break}
                $executables=@(if($kind-eq'Task'){$entry.Actions|ForEach-Object{if($_.PSObject.Properties['Execute']){[string]$_.Execute}else{''}}}elseif($kind-eq'Process'){[string]$entry.ExecutablePath}else{[string]$entry.PathName})
                if($executables.Count-eq0){$complete=$false}
                foreach($executable in $executables){
                    $path=if($kind-eq'Process'){try{[MemoryClear.Storage.FileInventory]::Canonical($executable)}catch{$null}}else{ConvertTo-MCDiskExecutablePath $executable -ExecutableOnly:($kind-eq'Task')}
                    if(-not$path){$complete=$false;continue}
                    if($entries.Count-ge($policy.maximumEntriesPerSource*3)){$complete=$false;break}
                    $entries.Add([pscustomobject]@{Kind=$kind;Name=if($kind-eq'Task'){[string]$entry.TaskName}else{[string]$entry.Name};Executable=$path})
                }
            }
        }catch{if($CancellationToken.IsCancellationRequested){throw};$complete=$false;$issues.Add($kind+':Unavailable')}
        $sources.Add([pscustomobject]@{Kind=$kind;Complete=$complete;Visited=$count})
    }
    [pscustomobject]@{Entries=$entries.ToArray();Sources=$sources.ToArray();Issues=$issues.ToArray();Complete=(@($sources|Where-Object{-not$_.Complete}).Count-eq0);CapturedUtc=[DateTime]::UtcNow;RemovalInferenceEnabled=$false}
}
function Resolve-MCDiskOwnerEvidence {
    param([string]$Path,$Inventory,$Dependencies=$null)
    $policy=Get-MCDiskOwnerPolicy;$matches=New-Object 'System.Collections.Generic.List[object]';$references=New-Object 'System.Collections.Generic.List[object]'
    $full=[MemoryClear.Storage.FileInventory]::Canonical($Path)
    foreach($app in $Inventory.Apps){
        if(-not$app.Location){continue}
        try{$location=[MemoryClear.Storage.FileInventory]::Canonical($app.Location)}catch{continue}
        if($full-eq$location-or[MemoryClear.Storage.FileInventory]::Within($full,$location)){$matches.Add([pscustomobject]@{Name=$app.Name;Publisher=$app.Publisher;Location=$location;Source=$app.Source})}
    }
    $fresh=$false
    if($null-ne$Dependencies){
        try{$elapsed=([DateTime]::UtcNow-[DateTime]$Dependencies.CapturedUtc).TotalSeconds;$fresh=$elapsed-ge0-and$elapsed-le$policy.freshnessSeconds}catch{}
        if($fresh){foreach($reference in $Dependencies.Entries){
            try{$parent=Split-Path ([MemoryClear.Storage.FileInventory]::Canonical($reference.Executable)) -Parent
                if($full-eq$reference.Executable-or[MemoryClear.Storage.FileInventory]::Within($full,$parent)){$references.Add($reference)}
            }catch{}
        }}
    }
    $distinct=@($matches.ToArray()|Sort-Object Name,Publisher,Location -Unique)
    $state=if($references.Count){'ReferencedProtected'}elseif($distinct.Count-gt1){'SharedMetadataProtected'}elseif($distinct.Count-eq1){'InstalledMetadataProtected'}else{'UnknownProtected'}
    $names=(@($distinct|Select-Object -ExpandProperty Name)-join', ')
    $label=if($references.Count){'Có tham chiếu process/service/task'}elseif($distinct.Count-gt1){'Nhiều app cùng khớp · giữ'}elseif($distinct.Count-eq1){$names+' · đường dẫn cài đặt'}else{'Chưa xác minh chủ sở hữu · giữ'}
    $evidence=if($matches.Count){'Đường dẫn khớp metadata InstallLocation; không chứng minh dữ liệu có thể bỏ.'}else{'Chưa có mapping chủ sở hữu. Tên AppData hoặc thiếu khóa uninstall không chứng minh app đã gỡ.'}
    if(-not$Inventory.Complete){$evidence+=' Inventory cài đặt chưa đầy đủ.'}
    if(-not$fresh){$evidence+=' Snapshot tham chiếu thiếu hoặc đã cũ.'}elseif(-not$Dependencies.Complete){$evidence+=' Inventory process/service/task chưa đầy đủ.'}
    [pscustomobject]@{State=$state;OwnerLabel=$label;Risk='Blocked';DeletionAllowed=$false;Matches=$matches.ToArray();References=$references.ToArray();Evidence=$evidence;DependencySnapshotFresh=$fresh}
}
function Get-MCDiskOwnerAnalysis {
    param($ScanResult,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,$FixtureInventory=$null,$FixtureDependencies=$null,[string]$FixtureHistoryDirectory='')
    $policy=Get-MCDiskOwnerPolicy
    if($ScanResult.Rows.Count-gt$policy.maximumRows){throw 'Owner analysis page exceeds budget.'}
    if($null-ne$FixtureInventory){
        if(-not$ScanResult.Fixture){throw 'Injected inventory only permitted for marked fixture scans.'}
        foreach($row in $ScanResult.Rows){if(-not[MemoryClear.Storage.FileInventory]::Within($row.Path,(Join-Path $script:OwnerProject 'artifacts'))){throw 'Injected inventory cannot inspect user paths.'}}
        $inventory=$FixtureInventory;$dependencies=$FixtureDependencies
    }else{
        try{$CancellationToken.ThrowIfCancellationRequested();$inventory=Get-MCDiskAppInventory;$dependencies=Get-MCDiskDependencyInventory -CancellationToken $CancellationToken}
        catch{if(-not$CancellationToken.IsCancellationRequested){throw};$result=$ScanResult.PSObject.Copy();$result.Status='Cancelled';$result.Message='Đã dừng phân tích ứng dụng; giữ kết quả quét chỉ đọc, chưa xóa file nào.';return $result}
    }
    $history=Update-MCDiskObservationHistory -ScanResult $ScanResult -Inventory $inventory -Dependencies $dependencies -CancellationToken $CancellationToken -FixtureDirectory $FixtureHistoryDirectory
    $rows=New-Object 'System.Collections.Generic.List[object]';$unknown=0;$profiles=(Get-MCDiskAppCatalog).profiles
    foreach($row in $ScanResult.Rows){
        if($CancellationToken.IsCancellationRequested){$copy=$row.PSObject.Copy();$copy|Add-Member -NotePropertyName OwnerLabel -NotePropertyValue 'Chưa phân tích · đã dừng' -Force;$rows.Add($copy);continue}
        $assessment=Resolve-MCDiskOwnerEvidence -Path $row.Path -Inventory $inventory -Dependencies $dependencies
        # Positive path/shared ownership wins; catalog lifecycle supplements unknown AppData only.
        if($assessment.State-eq'UnknownProtected'-and$row.PSObject.Properties['DataEvidence']){$assessment=Resolve-MCDiskAppLifecycle $row.DataEvidence $inventory $dependencies $profiles}
        if($row.PSObject.Properties['DataEvidence']-and$history.Profiles.ContainsKey($row.DataEvidence.ProfileId)){
            $observation=$history.Profiles[$row.DataEvidence.ProfileId];$assessment.Evidence+=' '+$observation.Evidence
            $assessment|Add-Member -NotePropertyName HistoryEvidence -NotePropertyValue $observation -Force
            if($assessment.State-eq'ResidualCandidateUnverified'-and$observation.State-eq'PreviouslyObservedInstalled'){$assessment.State='PreviouslyObservedMissingProtected';$assessment.OwnerLabel=$row.DataEvidence.AppName+' · từng thấy cài, hiện thiếu metadata · chưa chứng minh gỡ'}
        }
        $copy=$row.PSObject.Copy();$copy|Add-Member -NotePropertyName OwnerLabel -NotePropertyValue $assessment.OwnerLabel -Force
        $copy|Add-Member -NotePropertyName OwnerEvidence -NotePropertyValue $assessment -Force
        if($assessment.State-in@('UnknownProtected','UnknownLifecycleProtected','ResidualCandidateUnverified','PreviouslyObservedMissingProtected')){$unknown++};$rows.Add($copy)
    }
    $result=$ScanResult.PSObject.Copy();$result.Rows=$rows.ToArray()
    $complete=$inventory.Complete-and$null-ne$dependencies-and$dependencies.Complete-and$history.Status-notin@('Unavailable','Partial','Cancelled')
    $result.Status=if($CancellationToken.IsCancellationRequested){'Cancelled'}elseif(-not$complete-or$ScanResult.Status-ne'CompletedReadonly'){'Partial'}else{'CompletedReadonly'}
    $result.Message="Phân tích chỉ đọc: $($rows.Count) file / $unknown chưa rõ owner. Metadata và tham chiếu không chứng minh rác; chưa xóa file nào. $($result.Status). $($history.Message)"
    $result|Add-Member -NotePropertyName ObservationHistory -NotePropertyValue $history -Force
    $result|Add-Member -NotePropertyName OwnershipAnalyzed -NotePropertyValue $true -Force
    $result|Add-Member -NotePropertyName OwnershipInventoryComplete -NotePropertyValue $complete -Force
    return $result
}
