#requires -version 5.1
# Catalog classification is evidence for a preview, never cleanup authority.
function Get-MCDiskAppCatalog {
    $catalog=Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'app\disk-app-profiles.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($field in $catalog.PSObject.Properties.Name){if($field-notin@('$schema','schemaVersion','governs','executionEnabled','profiles')){throw 'Unknown catalog field.'}}
    if($catalog.schemaVersion-ne1-or$catalog.governs-ne'product_runtime'-or$catalog.executionEnabled-isnot[bool]-or$catalog.executionEnabled){throw 'App catalog must be readonly.'}
    $ids=@{};if(@($catalog.profiles).Count-lt1-or@($catalog.profiles).Count-gt20){throw 'Invalid profile count.'}
    foreach($p in $catalog.profiles){
        foreach($field in $p.PSObject.Properties.Name){if($field-notin@('id','name','knownFolder','relativeRoot','layout','installNames','publishers','executables','cacheBranches','protectedBranches','cacheEffect','personalEffect','sources')){throw 'Unknown app profile field.'}}
        foreach($field in @('id','name','relativeRoot','cacheEffect','personalEffect')){if($p.$field-isnot[string]-or-not$p.$field-or$p.$field.Length-gt1024){throw 'Invalid profile text.'}}
        foreach($field in @('installNames','publishers','executables','cacheBranches','protectedBranches','sources')){if($p.$field-isnot[Array]-or$p.$field.Count-lt1-or$p.$field.Count-gt24){throw 'Invalid profile list.'};foreach($value in $p.$field){if($value-isnot[string]-or-not$value-or$value.Length-gt1024){throw 'Invalid profile list value.'}}}
        if($p.id-notmatch'^[a-z][a-z0-9-]{1,39}$'-or$ids.ContainsKey($p.id)){throw 'Invalid/duplicate app profile ID.'};$ids[$p.id]=$true
        if($p.knownFolder-notin@('Local','Roaming')-or$p.layout-notin@('Chromium','Flat')){throw 'Unsupported app profile scope/layout.'}
        foreach($path in @($p.relativeRoot)+@($p.cacheBranches)+@($p.protectedBranches)){
            if($path-isnot[string]-or$path-notmatch'^[a-zA-Z0-9 _.-]+(\\[a-zA-Z0-9 _.-]+)*$'){throw 'Invalid relative profile path.'}
            foreach($segment in ($path-split'\\')){if($segment-in@('.','..')-or$segment.TrimEnd(' ','.')-ne$segment){throw 'Ambiguous profile path.'}}
        }
        if(@($p.cacheBranches).Count-gt16-or@($p.protectedBranches).Count-gt24-or@($p.installNames).Count-gt10-or@($p.publishers).Count-gt10){throw 'Profile rule budget exceeded.'}
        if(@($p.installNames).Count-eq0-or@($p.publishers).Count-eq0-or@($p.sources).Count-eq0){throw 'Profile needs metadata/provenance.'}
        foreach($exe in $p.executables){if($exe-notmatch'^[a-zA-Z0-9 ._-]+\.exe$'){throw 'Invalid reference executable.'}}
        foreach($source in $p.sources){if($source-notmatch'^https://'){throw 'Profile provenance must be an HTTPS source.'}}
    }
    return $catalog
}
function Get-MCDiskAppRoots {
    param($Context)
    foreach($profile in (Get-MCDiskAppCatalog).profiles){
        $base=[MemoryClear.Storage.FileInventory]::Canonical([string]$Context.($profile.knownFolder))
        $root=[MemoryClear.Storage.FileInventory]::Canonical((Join-Path $base $profile.relativeRoot))
        if(-not[MemoryClear.Storage.FileInventory]::Within($root,$base)){throw 'Profile root escaped known folder.'}
        [pscustomobject]@{Profile=$profile;Root=$root}
    }
}
function Resolve-MCDiskAppData {
    param([string]$Path,$Context,$CatalogRoots=$null)
    $full=[MemoryClear.Storage.FileInventory]::Canonical($Path)
    if($null-eq$CatalogRoots){$CatalogRoots=@(Get-MCDiskAppRoots $Context)}
    foreach($entry in $CatalogRoots){
        if(-not[MemoryClear.Storage.FileInventory]::Within($full,$entry.Root)){continue}
        $p=$entry.Profile;$relative=$full.Substring($entry.Root.Length+1);$parts=$relative-split'\\';$branch=$relative
        # Only known profile shapes; arbitrary subfolders named Cache never qualify.
        if($p.layout-eq'Chromium'){
            if($parts.Count-gt1-and($parts[0]-eq'Default'-or$parts[0]-match'^Profile [1-9][0-9]{0,3}$')){$branch=($parts[1..($parts.Count-1)]-join'\')}
            else{$branch='__unknown_profile__'}
        }
        $class='UnknownAppData';$label='Chưa rõ loại · giữ';$effect='Dữ liệu ứng dụng chưa xác minh; có thể chứa tài khoản, database hoặc nội dung cá nhân.'
        foreach($protected in $p.protectedBranches){if($branch-eq$protected-or$branch.StartsWith($protected+'\',[StringComparison]::OrdinalIgnoreCase)){$class='ProtectedUserData';$label='Dữ liệu cá nhân · giữ';$effect=$p.personalEffect;break}}
        if($class-eq'UnknownAppData'){foreach($cache in $p.cacheBranches){if($branch.StartsWith($cache+'\',[StringComparison]::OrdinalIgnoreCase)){$class='CacheCandidate';$label='Cache · cần xác minh';$effect=$p.cacheEffect;break}}}
        return [pscustomobject]@{ProfileId=$p.id;AppName=$p.name;Root=$entry.Root;RelativePath=$relative;DataClass=$class;Label=$label;Effect=$effect;Sources=@($p.sources);Evidence='Khớp đường dẫn mặc định trong catalog. Chưa xác minh phiên bản, custom/portable profile, app đang dùng hoặc điều kiện xóa.';DeletionAllowed=$false}
    }
    return $null
}
function Resolve-MCDiskAppLifecycle {
    param($DataEvidence,$Inventory,$Dependencies,$Profiles=(Get-MCDiskAppCatalog).profiles)
    $p=@($Profiles|Where-Object{$_.id-eq$DataEvidence.ProfileId})
    if($p.Count-ne1){throw 'Unknown app profile.'};$profile=$p[0]
    $installed=@($Inventory.Apps|Where-Object{$profile.installNames-contains$_.Name-and$profile.publishers-contains$_.Publisher})
    $fresh=$false;$refs=@()
    if($null-ne$Dependencies){
        try{$age=([DateTime]::UtcNow-[DateTime]$Dependencies.CapturedUtc).TotalSeconds;$fresh=$age-ge0-and$age-le(Get-MCDiskOwnerPolicy).freshnessSeconds}catch{}
        if($fresh){$refs=@($Dependencies.Entries|Where-Object{$profile.executables-contains[IO.Path]::GetFileName($_.Executable)})}
    }
    $state=if($refs.Count){'PossibleReferenceProtected'}elseif($installed.Count){'InstalledCatalogProtected'}elseif(-not$Inventory.Complete-or-not$fresh-or-not$Dependencies.Complete){'UnknownLifecycleProtected'}else{'ResidualCandidateUnverified'}
    $label=switch($state){
        PossibleReferenceProtected {'Có process/service/task cùng tên · giữ'}
        InstalledCatalogProtected {'Còn metadata cài đặt · giữ'}
        ResidualCandidateUnverified {'Có thể còn sót · chưa chứng minh đã gỡ'}
        default {'Chưa đủ dữ liệu cài đặt/tham chiếu · giữ'}
    }
    $evidence=$DataEvidence.Evidence+' Không có lịch sử uninstall đã xác minh; thiếu metadata không chứng minh app đã gỡ. Tham chiếu tên executable chỉ là lý do bảo vệ, không chứng minh chủ sở hữu.'
    [pscustomobject]@{State=$state;OwnerLabel=$profile.name+' · '+$label;Risk='Blocked';DeletionAllowed=$false;Matches=$installed;References=$refs;Evidence=$evidence;DependencySnapshotFresh=$fresh;DataEvidence=$DataEvidence}
}
