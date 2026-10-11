#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$script:ProviderRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function Get-MCWindowsProviderCatalog {
    $p=Get-Content (Join-Path $script:ProviderRoot 'app\windows-cleanup-providers.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if(@($p.PSObject.Properties.Name|Where-Object{$_-notin@('$schema','governs','schemaVersion','mode','providers')}).Count-or$p.governs-ne'product_runtime'-or$p.schemaVersion-ne1-or$p.mode-ne'WindowsDelegated'-or@($p.providers).Count-ne3){throw 'Invalid Windows provider catalog.'}
    $expected=@{Storage='ms-settings:storagesense';Apps='ms-settings:appsfeatures';Update='ms-settings:windowsupdate'};$seen=@{}
    foreach($entry in $p.providers){if(@($entry.PSObject.Properties.Name|Where-Object{$_-notin@('id','label','uri','minimumBuild','effect')}).Count-or-not$expected.ContainsKey($entry.id)-or$seen.ContainsKey($entry.id)-or$entry.uri-cne$expected[$entry.id]-or$entry.minimumBuild-ne10240-or-not$entry.label-or-not$entry.effect){throw 'Provider URI/identity is not allowlisted.'};$seen[$entry.id]=$true}
    $p
}
function Get-MCWindowsCleanupCapabilities {
    $build=$null;$edition='Unknown';$status='Unknown';$errorText='';$source='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion/CurrentBuildNumber'
    try{$os=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop;$n=0;if(-not[int]::TryParse([string]$os.CurrentBuildNumber,[ref]$n)){throw 'Unparseable authoritative Windows build.'};$build=$n;$edition=[string]$os.EditionID;$status=if($n-ge10240-and[Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){'SupportedDelegation'}else{'Unsupported'}}catch{$errorText=$_.Exception.Message}
    $catalog=Get-MCWindowsProviderCatalog
    [pscustomobject]@{Status=$status;Build=$build;Edition=$edition;Source=$source;Error=$errorText;Providers=$catalog.providers;Mode='WindowsDelegated';DirectSystemWrites=$false;RequiresAdminBypass=$false;MeasuredCleanupBytes=$null}
}
function Open-MCWindowsCleanup {
    param([ValidateSet('Storage','Apps','Update')][string]$Provider='Storage',[switch]$PreviewOnly)
    $cap=Get-MCWindowsCleanupCapabilities;$entry=@($cap.Providers|Where-Object{$_.id-eq$Provider})[0]
    if($cap.Status-ne'SupportedDelegation'-or$cap.Build-lt$entry.minimumBuild){return [pscustomobject]@{Status='Unavailable';Provider=$Provider;Uri=$entry.uri;Message='Không xác minh được Windows build hỗ trợ. Mở Settings > System > Storage thủ công.';Error=$cap.Error;DeletedBytes=$null}}
    if($PreviewOnly){return [pscustomobject]@{Status='Prepared';Provider=$Provider;Uri=$entry.uri;Message=$entry.effect;DeletedBytes=$null;LaunchExecuted=$false}}
    try{Start-Process -FilePath $entry.uri -ErrorAction Stop|Out-Null;[pscustomobject]@{Status='Delegated';Provider=$Provider;Uri=$entry.uri;Message='Đã chuyển sang Windows. MemoryClear chưa xác minh việc dọn hoặc dung lượng thu hồi. '+$entry.effect;DeletedBytes=$null;LaunchExecuted=$true}}
    catch{[pscustomobject]@{Status='Failed';Provider=$Provider;Uri=$entry.uri;Message='Không mở được Windows Settings; chưa xác minh việc dọn.';Error=$_.Exception.Message;DeletedBytes=$null;LaunchExecuted=$false}}
}
Export-ModuleMember -Function Get-MCWindowsProviderCatalog,Get-MCWindowsCleanupCapabilities,Open-MCWindowsCleanup
