#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$script:ProjectRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if(-not('MemoryClear.Storage.FileInventory'-as[type])){Add-Type -Path (Join-Path $PSScriptRoot 'FileInventory.cs')}
. (Join-Path $PSScriptRoot 'Ownership.ps1')
. (Join-Path $PSScriptRoot 'AppProfiles.ps1')
. (Join-Path $PSScriptRoot 'OwnerHistory.ps1')
function Get-MCDiskPolicy {
    $p=Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'app\clean-data-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $allowed=@('$schema','governs','schemaVersion','executionEnabled','privilegedWrites','followReparsePoints','maxRows','maxEntries','maxSeconds','largeMinimumMB','levels','orphanVendorRules','backupRequiredForUserData','systemProviderMode')
    foreach($name in $p.PSObject.Properties.Name){if($allowed-notcontains$name){throw 'Unknown disk policy field.'}}
    if($p.governs-ne'product_runtime'-or$p.schemaVersion-ne1-or$p.executionEnabled-ne$false-or$p.privilegedWrites-ne$false-or$p.followReparsePoints-ne$false-or$p.backupRequiredForUserData-ne$true-or$p.systemProviderMode-ne'WindowsDelegated'-or@($p.orphanVendorRules).Count-ne0){throw 'Unsupported disk policy; cleanup must stay disabled in readonly phase.'}
    if($p.maxRows-lt1-or$p.maxRows-gt5000-or$p.maxEntries-lt1-or$p.maxEntries-gt100000-or$p.maxSeconds-lt1-or$p.maxSeconds-gt120-or$p.largeMinimumMB-lt1){throw 'Disk scan budget invalid.'}
    if(@($p.levels).Count-ne3-or(@($p.levels.id|Sort-Object)-join',')-ne'1,2,3'){throw 'Expected three disk levels.'}
    foreach($level in $p.levels){if($level.tempDays-lt1-or$level.logDays-lt1){throw 'Retention invalid.'}}
    return $p
}
function Get-MCDiskContext {
    $local=[Environment]::GetFolderPath('LocalApplicationData');$roaming=[Environment]::GetFolderPath('ApplicationData')
    $cloud=New-Object 'System.Collections.Generic.List[string]'
    foreach($value in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)){if($value){$cloud.Add($value)}}
    $providerKnown=$true
    try{if(Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager'){foreach($key in Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager'){
        $scope=Join-Path $key.PSPath 'UserSyncRoots';if(Test-Path $scope){$v=Get-ItemProperty $scope;foreach($prop in $v.PSObject.Properties){if($prop.Name-notlike'PS*'-and$prop.Value-is[string]){$cloud.Add($prop.Value)}}}
    }}}catch{$providerKnown=$false}
    $knownFolders=@();foreach($name in @('MyDocuments','MyVideos','MyPictures','DesktopDirectory')){$folder=[Environment]::GetFolderPath($name);if($folder){$knownFolders+=@($folder)}}
    # Downloads resolved from the OS user-shell-folder GUID, not an assumed directory name.
    try{$downloads=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}';if($downloads){$knownFolders+=@([Environment]::ExpandEnvironmentVariables($downloads))}}catch{}
    [pscustomobject]@{Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;OSRoot=$env:SystemRoot;Local=$local;Roaming=$roaming;Temp=(Join-Path $local 'Temp');KnownFolders=@($knownFolders|Select-Object -Unique);CloudRoots=$cloud.ToArray();CloudInventoryKnown=$providerKnown}
}
function Test-MCDiskScanRoot {
    param([string]$Path,$Context)
    try{$full=[MemoryClear.Storage.FileInventory]::Canonical($Path)}catch{return $false}
    if(-not$Context.CloudInventoryKnown){return $false}
    if([IO.Path]::GetPathRoot($full)-ne[IO.Path]::GetPathRoot($Context.OSRoot)){return $false}
    foreach($root in @($Context.CloudRoots)+@($Context.OSRoot,$env:ProgramFiles,${env:ProgramFiles(x86)},$script:ProjectRoot)){
        if($root){try{$r=[MemoryClear.Storage.FileInventory]::Canonical($root);if($full-eq$r-or[MemoryClear.Storage.FileInventory]::Within($full,$r)-or[MemoryClear.Storage.FileInventory]::Within($r,$full)){return $false}}catch{return $false}}
    }
    return $true
}
function Get-MCDiskAppInventory {
    $apps=New-Object 'System.Collections.Generic.List[object]';$complete=$true;$sources=New-Object 'System.Collections.Generic.List[string]'
    $maximum=(Get-MCDiskOwnerPolicy).maximumEntriesPerSource
    foreach($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)){
        foreach($view in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)){
            $base=$null;$uninstall=$null
            try{$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view);$uninstall=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall');$sources.Add("$hive/$view")
                if($uninstall){foreach($name in $uninstall.GetSubKeyNames()){if($apps.Count-ge$maximum){$complete=$false;break};$entry=$null;try{$entry=$uninstall.OpenSubKey($name);$display=$entry.GetValue('DisplayName');if($display){$apps.Add([pscustomobject]@{Name=[string]$display;Publisher=[string]$entry.GetValue('Publisher');Location=[string]$entry.GetValue('InstallLocation');Source="$hive/$view";InstallationId="$hive/$view/$name";Version=[string]$entry.GetValue('DisplayVersion')})}}finally{if($entry){$entry.Dispose()}}}}
            }catch{$complete=$false}finally{if($uninstall){$uninstall.Dispose()};if($base){$base.Dispose()}}
        }
    }
    try{if(Get-Command Get-AppxPackage -ErrorAction SilentlyContinue){foreach($package in Get-AppxPackage -ErrorAction Stop){if($apps.Count-ge$maximum){$complete=$false;break};$apps.Add([pscustomobject]@{Name=[string]$package.Name;Publisher=[string]$package.Publisher;Location=[string]$package.InstallLocation;Source='MSIX/CurrentUser';InstallationId=[string]$package.PackageFullName;Version=[string]$package.Version})};$sources.Add('MSIX/CurrentUser')}else{$complete=$false}}catch{$complete=$false}
    [pscustomobject]@{Apps=$apps.ToArray();Complete=$complete;Sources=$sources.ToArray();OrphanDeletionEnabled=$false;Reason='Missing install keys never prove orphan data. No verified vendor rules configured; portable/shared/unknown app data protected.'}
}
function Get-MCDiskOwnership {
    param([string]$Path,$Inventory,[object[]]$VendorRules=@())
    if(@($VendorRules).Count-ne0){throw 'Verified vendor rules are not implemented; refusing speculative orphan classification.'}
    Resolve-MCDiskOwnerEvidence -Path $Path -Inventory $Inventory
}
function Get-MCDiskScan {
    param([ValidateRange(1,3)][int]$Level=1,[switch]$IncludeLargeFiles,[switch]$AppData,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,[object[]]$FixtureRoots=@(),[ValidateRange(0,1048576)][int]$MinimumMB=0,[ValidateRange(0,36500)][int]$MinimumAgeDays=0,[string[]]$Extensions=@(),[string[]]$UserRoots=@(),[ValidateRange(0,100000)][int]$Offset=0)
    $policy=Get-MCDiskPolicy;$context=Get-MCDiskContext;$roots=@();$fixture=@($FixtureRoots).Count-gt0
    if($AppData-and($IncludeLargeFiles-or$UserRoots.Count-or$MinimumMB-or$MinimumAgeDays-or$Extensions.Count)){throw 'App-data catalog mode cannot be combined with file finder options.'}
    if($fixture){
        $artifactRoot=Join-Path $script:ProjectRoot 'artifacts'
        foreach($r in $FixtureRoots){if(-not[MemoryClear.Storage.FileInventory]::Within([string]$r,$artifactRoot)-or-not(Test-Path -LiteralPath (Join-Path $r '.memoryclear-fixture') -PathType Leaf)){throw 'Fixture scans are limited to marked workspace artifact directories.'};$roots+=@([string]$r)}
    }else{
        if(-not$AppData-and-not$IncludeLargeFiles-and(Test-MCDiskScanRoot $context.Temp $context)){$roots+=@($context.Temp)}
        if($UserRoots.Count-and-not$IncludeLargeFiles){throw 'Custom folders are only for readonly file finder.'}
        if($IncludeLargeFiles){
            $requested=if($UserRoots.Count){$UserRoots}else{$context.KnownFolders}
            foreach($r in $requested){
                $known=$false;foreach($folder in $context.KnownFolders){try{if([MemoryClear.Storage.FileInventory]::Canonical($r)-eq[MemoryClear.Storage.FileInventory]::Canonical($folder)-or[MemoryClear.Storage.FileInventory]::Within($r,$folder)){$known=$true;break}}catch{}}
                if($UserRoots.Count-and(-not$known-or-not(Test-MCDiskScanRoot $r $context))){throw 'Choose a local subfolder of current-user Documents/Downloads/Desktop/Pictures/Videos on the Windows volume; protected/cloud folders are blocked.'}
                if((Test-Path -LiteralPath $r -PathType Container)-and(Test-MCDiskScanRoot $r $context)){$roots+=@($r)}
            }
        }
    }
    $appContext=$context;$appRoots=@();$observations=@();$probeIncomplete=$false
    if($AppData){
        if($fixture){if($FixtureRoots.Count-ne1){throw 'App-data fixtures require one marked root.'};$appContext=[pscustomobject]@{Local=(Join-Path $FixtureRoots[0] 'Local');Roaming=(Join-Path $FixtureRoots[0] 'Roaming')}}
        $appRoots=@(Get-MCDiskAppRoots $appContext);$roots=@()
        foreach($entry in $appRoots){
            # Native scan validates the complete ancestor chain, including reparse/cloud flags.
            # Probe distinguishes expected absence from unavailable/protected roots.
            if($CancellationToken.IsCancellationRequested){break}
            if($fixture-or(Test-MCDiskScanRoot $entry.Root $context)){
                $probe=[MemoryClear.Storage.FileInventory]::ProbeDirectory($entry.Root);$observations+=@([pscustomobject]@{App=$entry.Profile.name;Probe=$probe})
                if($probe.State-in@('Present','EmptyAtObservation')){$roots+=@($entry.Root)}elseif($probe.State-eq'Unavailable'){$probeIncomplete=$true}
            }else{$probeIncomplete=$true;$observations+=@([pscustomobject]@{App=$entry.Profile.name;Probe=[pscustomobject]@{Path=$entry.Root;State='ExcludedByScope';Identity=$null;Issue='Protected/cloud/off-volume scope'}})}
        }
    }
    if($MinimumMB-lt0){throw 'Minimum size must be non-negative.'}
    $minimum=if($IncludeLargeFiles){if($MinimumMB-gt0){[long]$MinimumMB*1MB}else{[long]$policy.largeMinimumMB*1MB}}else{0L}
    if(-not$IncludeLargeFiles-and($MinimumAgeDays-gt0-or$Extensions.Count-gt0)){throw 'Age/type finder filters do not apply to temp mode.'}
    $maximumWrite=if($MinimumAgeDays-gt0){[DateTime]::UtcNow.AddDays(-$MinimumAgeDays).ToFileTimeUtc()}else{[long]::MaxValue}
    $scan=[MemoryClear.Storage.FileInventory]::ScanFilteredPage([string[]]$roots,$minimum,$maximumWrite,[string[]]$Extensions,$policy.maxRows,$policy.maxEntries,$policy.maxSeconds,$Offset,$CancellationToken)
    $rows=New-Object 'System.Collections.Generic.List[object]';$cutoff=[DateTime]::UtcNow.AddDays(-[int]$policy.levels[$Level-1].tempDays)
    foreach($file in $scan.Files){
        $age=[Math]::Max(0,[Math]::Floor(([DateTime]::UtcNow-[DateTime]::FromFileTimeUtc($file.LastWriteFileTime)).TotalDays))
        $isTemp=(-not$AppData)-and(-not$IncludeLargeFiles)-and($fixture-or[MemoryClear.Storage.FileInventory]::Within($file.Path,$context.Temp))
        $old=$file.LastWriteFileTime-le$cutoff.ToFileTimeUtc()
        $risk=if($isTemp-and$old){'SafeCandidate'}elseif($isTemp){'KeepRecent'}else{'NeedsReview'}
        $effect=if($isTemp){'Ứng viên temp theo retention; chưa có quyền xóa. File đang dùng/đổi identity phải bỏ qua khi triển khai executor.'}else{'File lớn/cũ chưa biết giá trị; có thể là tài liệu, video, bộ cài hoặc backup. Không tự chọn để xóa.'}
        $riskLabel=if($risk-eq'SafeCandidate'){'Temp cũ · ứng viên'}elseif($risk-eq'KeepRecent'){'Giữ file mới'}else{'Cần duyệt giá trị'}
        $row=[pscustomobject]@{Name=[IO.Path]::GetFileName($file.Path);Path=$file.Path;Identity=$file.Identity;LogicalMB=[Math]::Round($file.LogicalBytes/1MB,2);AllocatedMB=[Math]::Round($file.AllocatedBytes/1MB,2);AgeDays=$age;Risk=$risk;RiskLabel=$riskLabel;Effect=$effect;Category=if($isTemp){'Temp'}else{'Large file'};Snapshot=$file;DeletionEnabled=$false}
        if($AppData){$data=Resolve-MCDiskAppData $file.Path $appContext $appRoots;$row.Risk='Blocked';$row.Category='App data';$row.RiskLabel=$data.Label;$row.Effect=$data.Effect;$row|Add-Member -NotePropertyName DataEvidence -NotePropertyValue $data;$row|Add-Member -NotePropertyName OwnerLabel -NotePropertyValue ($data.AppName+' · chưa đối chiếu cài đặt')}
        $rows.Add($row)
    }
    $status=if($scan.Cancelled-or$CancellationToken.IsCancellationRequested){'Cancelled'}elseif($probeIncomplete){'Partial'}elseif($roots.Count-eq0){'NoEligibleRoots'}elseif($scan.Truncated-or$scan.Skipped-gt0-or-not$context.CloudInventoryKnown){'Partial'}else{'CompletedReadonly'}
    $rootLabels=@{Present='có dữ liệu';EmptyAtObservation='rỗng tại lúc kiểm tra';Absent='không có thư mục mặc định';Unavailable='chưa đọc được / bị bảo vệ';ExcludedByScope='ngoài phạm vi cho phép'}
    $appNote=if($AppData){' AppData mặc định: '+(($observations|ForEach-Object{$_.App+': '+$rootLabels[$_.Probe.State]})-join'; ')+'. Không bao phủ portable/custom profile; cache chỉ là ứng viên.'}else{''}
    [pscustomobject]@{AppDataMode=[bool]$AppData;AppRootObservations=$observations;RunId=[guid]::NewGuid().ToString('N');Rows=$rows.ToArray();Status=$status;Visited=$scan.Visited;Skipped=$scan.Skipped;Duplicates=$scan.Duplicates;Truncated=$scan.Truncated;Offset=$Offset;Matched=$scan.Matched;HasMore=$scan.HasMore;Issues=@($scan.Issues);Seconds=$scan.Seconds;LogicalBytes=$scan.LogicalBytes;AllocatedBytes=$scan.AllocatedBytes;RootCount=$roots.Count;ExecutionEnabled=$false;Fixture=$fixture;CloudInventoryKnown=$context.CloudInventoryKnown;Message="Quét chỉ đọc: $($rows.Count) dòng từ vị trí $Offset / $($scan.Visited) mục; bỏ qua $($scan.Skipped); $status. Chưa xóa file nào.$appNote"}
}
Export-ModuleMember -Function Get-MCDiskPolicy,Get-MCDiskContext,Test-MCDiskScanRoot,Get-MCDiskAppInventory,Get-MCDiskOwnership,Get-MCDiskScan,Get-MCDiskOwnerPolicy,ConvertTo-MCDiskExecutablePath,Get-MCDiskDependencyInventory,Resolve-MCDiskOwnerEvidence,Get-MCDiskOwnerAnalysis,Get-MCDiskAppCatalog,Get-MCDiskAppRoots,Resolve-MCDiskAppData,Resolve-MCDiskAppLifecycle,Get-MCDiskHistoryPolicy,Update-MCDiskObservationHistory
