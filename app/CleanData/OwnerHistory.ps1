#requires -version 5.1
# Local observations are untrusted supporting evidence, never uninstall/delete authority.
function Get-MCDiskHistoryPolicy {
    $p=Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'app\owner-history-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($name in $p.PSObject.Properties.Name){if($name-notin@('$schema','schemaVersion','governs','executionEnabled','maximumBytes','maximumProfiles','maximumMatches','maximumAgeDays')){throw 'Unknown history policy field.'}}
    if($p.schemaVersion-ne1-or$p.governs-ne'product_runtime'-or$p.executionEnabled-isnot[bool]-or$p.executionEnabled){throw 'History cannot authorize cleanup.'}
    foreach($bound in @(@('maximumBytes',4096,1048576),@('maximumProfiles',1,20),@('maximumMatches',1,8),@('maximumAgeDays',1,365))){$v=$p.($bound[0]);if($v-isnot[int]-or$v-lt$bound[1]-or$v-gt$bound[2]){throw 'Invalid history budget.'}}
    $p
}
function Get-MCDiskTextHash {
    param([string]$Text)
    $hash=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
}
function Assert-MCDiskHistoryFields {
    param($Object,[string[]]$Fields)
    if($null-eq$Object-or$Object-isnot[pscustomobject]){throw 'History object expected.'}
    if(@($Object.PSObject.Properties).Count-ne$Fields.Count){throw 'Unexpected history shape.'}
    foreach($name in $Fields){if(-not$Object.PSObject.Properties[$name]){throw 'Missing history field.'}}
}
function Read-MCDiskHistoryPayload {
    param([string]$Text,$Policy,[DateTime]$Now)
    if(-not$Text){return $null}
    $envelope=$Text|ConvertFrom-Json
    Assert-MCDiskHistoryFields $envelope @('Payload','Sha256')
    if($envelope.Payload-isnot[string]-or$envelope.Sha256-isnot[string]-or$envelope.Sha256-cne(Get-MCDiskTextHash $envelope.Payload)){throw 'History checksum mismatch.'}
    $data=$envelope.Payload|ConvertFrom-Json
    Assert-MCDiskHistoryFields $data @('SchemaVersion','Sid','CatalogHash','UpdatedUtc','Records')
    if($data.SchemaVersion-ne1-or$data.Sid-isnot[string]-or$data.Sid-notmatch'^S-1-[0-9-]{1,180}$'-or$data.CatalogHash-notmatch'^[a-f0-9]{64}$'-or$data.Records-isnot[Array]-or$data.Records.Count-gt$Policy.maximumProfiles){throw 'Invalid history header.'}
    $updated=[DateTime]::Parse($data.UpdatedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
    if($updated.Kind-ne[DateTimeKind]::Utc-or$updated-gt$Now){throw 'History clock is invalid/future.'}
    $ids=@{}
    foreach($record in $data.Records){
        Assert-MCDiskHistoryFields $record @('ProfileId','Root','RootIdentity','LastObservedUtc','LastInstalledUtc','LastInstalledMatches')
        if($record.ProfileId-notmatch'^[a-z][a-z0-9-]{1,39}$'-or$ids.ContainsKey($record.ProfileId)){throw 'Invalid/duplicate historical profile.'};$ids[$record.ProfileId]=$true
        if($record.Root-isnot[string]-or$record.Root.Length-gt32767-or([MemoryClear.Storage.FileInventory]::Canonical($record.Root))-ne$record.Root-or$record.RootIdentity-notmatch'^[A-F0-9]{8}:[A-F0-9]{16}$'){throw 'Invalid historical root.'}
        $observed=[DateTime]::Parse($record.LastObservedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
        if($observed.Kind-ne[DateTimeKind]::Utc-or$observed-gt$updated){throw 'Invalid history observation time.'}
        if($record.LastInstalledMatches-isnot[Array]-or$record.LastInstalledMatches.Count-gt$Policy.maximumMatches){throw 'Invalid historical match count.'}
        if($null-ne$record.LastInstalledUtc){$date=[DateTime]::Parse($record.LastInstalledUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind);if($date.Kind-ne[DateTimeKind]::Utc-or$date-gt$observed-or$record.LastInstalledMatches.Count-eq0){throw 'Invalid installed observation.'}}
        elseif($record.LastInstalledMatches.Count){throw 'Undated installed metadata.'}
        foreach($match in $record.LastInstalledMatches){Assert-MCDiskHistoryFields $match @('Source','InstallationId','Version');foreach($field in @('Source','InstallationId','Version')){if($match.$field-isnot[string]-or$match.$field.Length-gt512){throw 'Invalid metadata provenance.'}};if(-not$match.Source-or-not$match.InstallationId){throw 'Missing metadata provenance.'}}
    }
    return $data
}
function Update-MCDiskObservationHistory {
    param($ScanResult,$Inventory,$Dependencies,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[string]$FixtureDirectory='')
    $policy=Get-MCDiskHistoryPolicy;$result=[pscustomobject]@{Status='NotApplicable';Message='';Profiles=@{};Saved=$false;DeletionAllowed=$false}
    if(-not$ScanResult.PSObject.Properties['AppDataMode']-or-not$ScanResult.AppDataMode){return $result}
    if($ScanResult.Fixture-and-not$FixtureDirectory){$result.Status='FixtureNotPersisted';return $result}
    if($FixtureDirectory){
        $FixtureDirectory=[MemoryClear.Storage.FileInventory]::Canonical($FixtureDirectory)
        if(-not$ScanResult.Fixture-or-not[MemoryClear.Storage.FileInventory]::Within($FixtureDirectory,(Join-Path $script:ProjectRoot 'artifacts'))-or-not(Test-Path -LiteralPath (Join-Path $FixtureDirectory '.memoryclear-fixture') -PathType Leaf)){throw 'History fixtures require a marked workspace directory.'}
        foreach($row in $ScanResult.Rows){if(-not[MemoryClear.Storage.FileInventory]::Within($row.Path,$FixtureDirectory)){throw 'History fixture row is outside scope.'}}
    }
    $store=$null
    try{
        $CancellationToken.ThrowIfCancellationRequested()
        $context=Get-MCDiskContext;$sid=$context.Sid
        if($FixtureDirectory){$context=[pscustomobject]@{Local=(Join-Path $FixtureDirectory 'Local');Roaming=(Join-Path $FixtureDirectory 'Roaming')}}
        $catalog=Get-MCDiskAppCatalog;$roots=@(Get-MCDiskAppRoots $context)
        $catalogHash=Get-MCDiskTextHash ($catalog|ConvertTo-Json -Depth 12 -Compress)
        $storeRoot=if($FixtureDirectory){$FixtureDirectory}else{$script:ProjectRoot}
        $store=[MemoryClear.Storage.FileInventory]::OpenObservationStore($storeRoot,$policy.maximumBytes)
        $now=[DateTime]::UtcNow;$previous=Read-MCDiskHistoryPayload ($store.ReadText()) $policy $now
        if($null-ne$previous-and$previous.Sid-ne$sid){throw 'History belongs to another SID.'}
        $reset=$null-ne$previous-and$previous.CatalogHash-ne$catalogHash
        $records=New-Object 'System.Collections.Generic.List[object]'
        $anyUnavailable=$false
        foreach($entry in $roots){
            $CancellationToken.ThrowIfCancellationRequested();$id=$entry.Profile.id
            $expected=@($ScanResult.AppRootObservations|Where-Object{$_.Probe.Path-eq$entry.Root-and$_.Probe.State-in@('Present','EmptyAtObservation')})
            if($expected.Count-ne1){continue}
            $probe=[MemoryClear.Storage.FileInventory]::ProbeDirectory($entry.Root)
            if($probe.State-notin@('Present','EmptyAtObservation')-or$probe.Identity-ne$expected[0].Probe.Identity){$anyUnavailable=$true;$result.Profiles[$id]=[pscustomobject]@{State='RootChanged';LastInstalledUtc=$null;Evidence='Thư mục đổi hoặc chưa đọc được; lịch sử không áp dụng.'};continue}
            $prior=@(if($null-ne$previous-and-not$reset){$previous.Records|Where-Object{$_.ProfileId-eq$id-and$_.Root-eq$entry.Root-and$_.RootIdentity-eq$probe.Identity}})
            $record=[pscustomobject]@{ProfileId=$id;Root=$entry.Root;RootIdentity=$probe.Identity;LastObservedUtc=$now.ToString('o');LastInstalledUtc=$null;LastInstalledMatches=@()}
            if($prior.Count-eq1){$record.LastInstalledUtc=$prior[0].LastInstalledUtc;$record.LastInstalledMatches=$prior[0].LastInstalledMatches}
            $matches=@($Inventory.Apps|Where-Object{$entry.Profile.installNames-contains$_.Name-and$entry.Profile.publishers-contains$_.Publisher})
            $provenance=@($matches|Where-Object{$_.PSObject.Properties['InstallationId']-and$_.PSObject.Properties['Version']-and$_.InstallationId-and$_.Source-and([string]$_.InstallationId).Length-le512-and([string]$_.Source).Length-le512-and([string]$_.Version).Length-le512}|Select-Object -First $policy.maximumMatches|ForEach-Object{[pscustomobject]@{Source=[string]$_.Source;InstallationId=[string]$_.InstallationId;Version=[string]$_.Version}})
            if($provenance.Count){$record.LastInstalledUtc=$now.ToString('o');$record.LastInstalledMatches=$provenance}
            $expired=$null-ne$record.LastInstalledUtc-and($now-[DateTime]$record.LastInstalledUtc).TotalDays-gt$policy.maximumAgeDays
            $state=if($provenance.Count){'ObservedInstalled'}elseif($expired){'HistoryExpired'}elseif($prior.Count-eq1-and$record.LastInstalledUtc){'PreviouslyObservedInstalled'}elseif($reset){'CatalogChanged'}else{'NoInstalledHistory'}
            $evidence=if($record.LastInstalledUtc){'Từng thấy metadata cài đặt lúc '+$record.LastInstalledUtc+'; nguồn: '+(($record.LastInstalledMatches|ForEach-Object{$_.Source+' / '+$_.InstallationId+' / version '+$_.Version})-join'; ')+'.'}else{'Chưa có lần quan sát metadata cài đặt có nguồn phù hợp với thư mục hiện tại.'}
            if($expired){$evidence+=' Lịch sử quá cũ, không dùng để suy luận tình trạng hiện tại.'}
            $result.Profiles[$id]=[pscustomobject]@{State=$state;LastInstalledUtc=$record.LastInstalledUtc;Evidence=$evidence+' Lịch sử local có thể bị sửa; không là sự kiện uninstall đã xác minh hay quyền xóa.'}
            $records.Add($record)
        }
        # Keep observations for roots not seen this page, bounded by this catalog; never infer absence from no files.
        if($null-ne$previous-and-not$reset){foreach($record in $previous.Records){if($catalog.profiles.id-contains$record.ProfileId-and-not(@($records.ToArray()|Where-Object{$_.ProfileId-eq$record.ProfileId}).Count)){$records.Add($record)}}}
        if($records.Count-gt$policy.maximumProfiles){throw 'History profile budget exceeded.'}
        $data=[pscustomobject]@{SchemaVersion=1;Sid=$sid;CatalogHash=$catalogHash;UpdatedUtc=$now.ToString('o');Records=$records.ToArray()}
        $payload=$data|ConvertTo-Json -Depth 12 -Compress;$envelope=[pscustomobject]@{Payload=$payload;Sha256=(Get-MCDiskTextHash $payload)}|ConvertTo-Json -Compress
        $CancellationToken.ThrowIfCancellationRequested();$store.Commit($envelope);$result.Saved=$true
        $result.Status=if($anyUnavailable){'Partial'}elseif($reset){'CatalogReset'}else{'Saved'}
        $result.Message='Đã lưu lịch sử quan sát local; không xác minh sự kiện gỡ app.'
        if($anyUnavailable){$result.Message+=' Có thư mục thay đổi/không đọc được, không dùng lịch sử cho mục đó.'}
        if($reset){$result.Message+=' Catalog đổi: bắt đầu lại căn cứ quan sát.'}
    }catch{
        $result.Profiles=@{};$result.Status=if($CancellationToken.IsCancellationRequested){'Cancelled'}else{'Unavailable'}
        $result.Message=if($CancellationToken.IsCancellationRequested){'Đã dừng lưu lịch sử.'}else{'Không dùng/lưu được lịch sử (khóa, hỏng, khác user hoặc không đủ quyền); giữ dữ liệu. '+$_.Exception.Message}
    }finally{if($store){$store.Dispose()}}
    return $result
}
