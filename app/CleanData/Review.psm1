#requires -version 5.1
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MemoryClear.Disk.psm1')
$script:ReviewRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:Sessions=@{}
function Get-MCDiskReviewPolicy {
    $p=Get-Content (Join-Path $script:ReviewRoot 'app\disk-review-policy.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($field in $p.PSObject.Properties.Name){if($field-notin@('$schema','schemaVersion','governs','mode','executionEnabled','maximumItems','maximumSessions','ttlSeconds')){throw 'Unknown review policy field.'}}
    if($p.schemaVersion-ne1-or$p.governs-ne'product_runtime'-or$p.mode-ne'PreviewOnly'-or$p.executionEnabled-isnot[bool]-or$p.executionEnabled){throw 'Review must remain preview only.'}
    foreach($b in @(@('maximumItems',1,100),@('maximumSessions',1,8),@('ttlSeconds',1,600))){if($p.($b[0])-isnot[int]-or$p.($b[0])-lt$b[1]-or$p.($b[0])-gt$b[2]){throw 'Invalid review budget.'}}
    $p
}
function Get-MCReviewHash {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-MCReviewPolicyStamp {
    $parts=@();foreach($file in @('disk-review-policy.json','clean-data-policy.json','disk-app-profiles.json','owner-analysis-policy.json','owner-history-policy.json')){$parts+=@(Get-Content (Join-Path $script:ReviewRoot ('app\'+$file)) -Raw -Encoding UTF8)}
    Get-MCReviewHash ($parts-join"`n")
}
function New-MCDiskReviewSession {
    param($ScanResult,[object[]]$SelectedRows,[string]$ContextToken,[hashtable]$FixtureRisks=$null)
    $policy=Get-MCDiskReviewPolicy
    if(-not$ContextToken-or$SelectedRows.Count-lt1-or$SelectedRows.Count-gt$policy.maximumItems){throw 'Chọn 1–100 mục để xem kế hoạch.'}
    foreach($key in @($script:Sessions.Keys)){if([DateTime]::UtcNow-ge$script:Sessions[$key].Expires){$script:Sessions.Remove($key)}}
    if($script:Sessions.Count-ge$policy.maximumSessions){throw 'Đóng phiên duyệt trước khi tạo phiên mới.'}
    if($null-ne$FixtureRisks-and-not$ScanResult.Fixture){throw 'Fixture risks cannot apply to user data.'}
    $items=New-Object 'System.Collections.Generic.List[object]';$seen=@{}
    foreach($row in $SelectedRows){
        $match=@($ScanResult.Rows|Where-Object{$_.Identity-eq$row.Identity-and$_.Path-eq$row.Path})
        if($match.Count-ne1-or$seen.ContainsKey($row.Identity)-or-not$row.PSObject.Properties['Snapshot']){throw 'Selection is not a unique current scan item.'};$seen[$row.Identity]=$true
        $s=$row.Snapshot
        if($s.Path-ne$row.Path-or$s.Identity-ne$row.Identity){throw 'Row/snapshot mismatch.'}
        $risk='Blocked';$reason='Chưa có điều kiện xóa đã xác minh; xác nhận không mở khóa mục này.'
        if($null-ne$FixtureRisks){
            $root=[MemoryClear.Storage.FileInventory]::Canonical($s.Root)
            if(-not[MemoryClear.Storage.FileInventory]::Within($root,(Join-Path $script:ReviewRoot 'artifacts'))-or-not[IO.Path]::GetFileName($root).StartsWith('disk-fixture-')-or-not(Test-Path -LiteralPath (Join-Path $root '.memoryclear-fixture'))-or-not[MemoryClear.Storage.FileInventory]::Within($s.Path,$root)-or[IO.Path]::GetFileName($s.Path)-eq'.memoryclear-fixture'){throw 'Review examples require marked disposable files.'}
            if($FixtureRisks.ContainsKey($row.Identity)){$risk=[string]$FixtureRisks[$row.Identity]}
            if($risk-notin@('Safe','Review','Danger','Blocked')){throw 'Invalid fixture risk.'}
            $reason='Dữ liệu mẫu do test tạo; chỉ thử luồng duyệt, không xóa.'
        }
        $items.Add([pscustomobject]@{Id=$row.Identity;Path=$row.Path;Name=$row.Name;Risk=$risk;Reason=$reason;Effect=[string]$row.Effect;LogicalBytes=[long]$s.LogicalBytes;AllocatedBytes=[long]$s.AllocatedBytes;Snapshot=$s})
    }
    # Freeze by serialization; no mutable row/snapshot reference retained from the view.
    $id=[guid]::NewGuid().ToString('N');$payload=$items.ToArray()|ConvertTo-Json -Depth 10 -Compress
    $script:Sessions[$id]=[pscustomobject]@{Id=$id;RunId=$ScanResult.RunId;Created=[DateTime]::UtcNow;Expires=[DateTime]::UtcNow.AddSeconds($policy.ttlSeconds);Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Context=$ContextToken;Policy=(Get-MCReviewPolicyStamp);Payload=$payload;Stage='Review';Reviewed=@();Phrase=('XAC NHAN '+$id.Substring(0,8));Fixture=($null-ne$FixtureRisks)}
    Get-MCDiskReviewState $id
}
function ConvertFrom-MCReviewPayload {
    param([string]$Payload)
    $parsed=ConvertFrom-Json -InputObject $Payload;foreach($item in $parsed){$item}
}
function Get-MCDiskReviewState {
    param([string]$SessionId)
    if(-not$script:Sessions.ContainsKey($SessionId)){throw 'Phiên duyệt đã đóng hoặc không tồn tại.'}
    $s=$script:Sessions[$SessionId];$items=@(ConvertFrom-MCReviewPayload $s.Payload)
    $logical=0L;$allocated=0L;foreach($item in $items){if($item.Risk-ne'Blocked'){$logical+=$item.LogicalBytes;$allocated+=$item.AllocatedBytes}}
    [pscustomobject]@{SessionId=$s.Id;Stage=$s.Stage;RunId=$s.RunId;ExpiresUtc=$s.Expires;Items=$items;EligibleCount=@($items|Where-Object{$_.Risk-ne'Blocked'}).Count;BlockedCount=@($items|Where-Object{$_.Risk-eq'Blocked'}).Count;LogicalBytes=$logical;AllocatedBytes=$allocated;Phrase=$s.Phrase;ExecutionEnabled=$false;DeletedBytes=0;Fixture=$s.Fixture}
}
function Assert-MCDiskReviewCurrent {
    param([string]$SessionId,[string]$ContextToken)
    if(-not$script:Sessions.ContainsKey($SessionId)){throw 'Phiên duyệt không còn hiệu lực.'}
    $s=$script:Sessions[$SessionId]
    try{
        if($s.Stage-in@('Invalidated','Cancelled')-or$ContextToken-cne$s.Context-or[DateTime]::UtcNow-ge$s.Expires-or[DateTime]::UtcNow-lt$s.Created-or$s.Sid-ne[Security.Principal.WindowsIdentity]::GetCurrent().User.Value-or$s.Policy-ne(Get-MCReviewPolicyStamp)){throw 'Phạm vi, policy, user hoặc thời hạn đã đổi.'}
        foreach($item in @(ConvertFrom-MCReviewPayload $s.Payload)){
            if($item.Risk-eq'Blocked'){continue}
            $a=$item.Snapshot;$b=[MemoryClear.Storage.FileInventory]::Snapshot($a.Path,$a.Root)
            foreach($field in @('Identity','AncestorIdentity','LogicalBytes','AllocatedBytes','LastWriteFileTime','Links','Attributes')){if($a.$field-ne$b.$field){throw 'File/identity/nội dung đã đổi; cần quét và duyệt lại.'}}
            if($b.Links-ne1){throw 'File có hardlink; không dùng bản duyệt cũ.'}
        }
    }catch{$s.Stage='Invalidated';$s.Reviewed=@();throw}
    return $s
}
function Move-MCDiskReviewNext {
    param([string]$SessionId,[string]$ContextToken,[string[]]$ReviewedIds=@())
    $s=Assert-MCDiskReviewCurrent $SessionId $ContextToken
    if($s.Stage-ne'Review'){throw 'Cần bắt đầu từ bước duyệt từng mục.'}
    $items=@(ConvertFrom-MCReviewPayload $s.Payload);$eligible=@($items|Where-Object{$_.Risk-ne'Blocked'});$required=@($items|Where-Object{$_.Risk-in@('Review','Danger')}|ForEach-Object{$_.Id})
    if(-not$eligible.Count){$s.Stage='Blocked';return Get-MCDiskReviewState $SessionId}
    if(@($ReviewedIds|Select-Object -Unique).Count-ne$ReviewedIds.Count-or$ReviewedIds.Count-ne$required.Count-or@($required|Where-Object{$ReviewedIds-notcontains$_}).Count){throw 'Đọc tác động và đánh dấu đã duyệt từng mục rủi ro; không duyệt thay mục bị chặn.'}
    $s.Reviewed=@($ReviewedIds);$s.Stage=if($required.Count){'Confirm'}else{'PreviewApproved'}
    Get-MCDiskReviewState $SessionId
}
function Confirm-MCDiskReview {
    param([string]$SessionId,[string]$ContextToken,[bool]$Acknowledge=$false,[string]$Phrase='')
    $s=Assert-MCDiskReviewCurrent $SessionId $ContextToken
    if($s.Stage-ne'Confirm'){throw 'Chưa hoàn tất bước duyệt từng mục hoặc phiên đã hoàn tất.'}
    $danger=@(@(ConvertFrom-MCReviewPayload $s.Payload)|Where-Object{$_.Risk-eq'Danger'}).Count-gt0
    if(-not$Acknowledge-or($danger-and$Phrase-cne$s.Phrase)){throw 'Cần xác nhận hậu quả và gõ đúng cụm từ của phiên này.'}
    $s.Stage='PreviewApproved'
    Get-MCDiskReviewState $SessionId
}
function Reset-MCDiskReview {
    param([string]$SessionId,[switch]$Cancel)
    if($script:Sessions.ContainsKey($SessionId)){$s=$script:Sessions[$SessionId];$s.Stage=if($Cancel){'Cancelled'}elseif($s.Stage-in@('Invalidated','Cancelled')){$s.Stage}else{'Review'};$s.Reviewed=@()}
}
function Close-MCDiskReview {param([string]$SessionId);$script:Sessions.Remove($SessionId)}
Export-ModuleMember -Function Get-MCDiskReviewPolicy,New-MCDiskReviewSession,Get-MCDiskReviewState,Move-MCDiskReviewNext,Confirm-MCDiskReview,Reset-MCDiskReview,Close-MCDiskReview
