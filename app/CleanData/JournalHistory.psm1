#requires -version 5.1
# Read-only history of production operation journals (.data\temp-operation-*.jsonl, .data\memory-operation-*.jsonl).
# Verifies each journal's hash chain and summarises the run. Never writes, renames or deletes a journal.
# The chain uses an unkeyed SHA256: it detects corruption, truncation and broken ordering,
# NOT a deliberate edit by someone who rewrites the whole chain.
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$script:MaxJournalBytes=16MB   # same cap as the writer (FileInventory.TempLedger.Append)
$script:Pattern='^(temp|memory)-operation-([a-f0-9]{32})\.jsonl$'

function Get-MCJournalDigest {param([string]$Text);$h=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')}finally{$h.Dispose()}}

function Read-MCJournalLines {
    param([string]$Path)
    # Read with full sharing so a journal still being written is never blocked or locked.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite-bor[IO.FileShare]::Delete))
    try{
        if($stream.Length-gt$script:MaxJournalBytes){throw 'Journal lớn hơn giới hạn 16 MiB.'}
        $reader=New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding($false,$true)),$false)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
    $complete=$text.EndsWith("`n")
    $lines=@($text.Split("`n")|Where-Object{$_-ne''})
    [pscustomobject]@{Lines=$lines;EndsWithNewline=($complete-or$text.Length-eq0)}
}

function Test-MCJournal {
    param([Parameter(Mandatory)][string]$Path)
    $name=[IO.Path]::GetFileName($Path);$match=[regex]::Match($name,$script:Pattern)
    $r=[ordered]@{Id='';Type='';File=$name;Integrity='Unreadable';Problem='';Entries=0;Capability='';Started=$null;Finished=$null;Status='';Items=0;Done=0;Held=0;Skipped=0}
    if(-not$match.Success){$r.Problem='Tên file không đúng mẫu journal.';return [pscustomobject]$r}
    $r.Type=if($match.Groups[1].Value-eq'temp'){'Temp'}else{'Memory'};$r.Id=$match.Groups[2].Value
    try{
        $item=Get-Item -LiteralPath $Path -Force
        if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Journal là reparse point; không đọc.'}
        $read=Read-MCJournalLines $Path
    }catch{$r.Problem=$_.Exception.Message;return [pscustomobject]$r}
    if(-not$read.Lines.Count){$r.Integrity='Empty';$r.Problem='Journal rỗng.';return [pscustomobject]$r}
    $previous='0'*64;$sequence=0;$deleted=@{}
    foreach($line in $read.Lines){
        $n=$sequence+1
        try{$e=$line|ConvertFrom-Json}catch{$r.Integrity='Broken';$r.Problem="Dòng $n không phải JSON hợp lệ.";break}
        if(-not($e-is[pscustomobject]-and$e.PSObject.Properties['Sequence']-and$e.PSObject.Properties['PreviousHash']-and$e.PSObject.Properties['Hash']-and$e.Payload-is[string])){
            if($n-eq1){$r.Integrity='NotChain';$r.Problem='Không có chuỗi hash (journal thử nghiệm hoặc định dạng khác); không đánh giá.'}else{$r.Integrity='Broken';$r.Problem="Dòng $n thiếu Sequence/PreviousHash/Hash/Payload."};break}
        try{$p=$e.Payload|ConvertFrom-Json}catch{$r.Integrity='Broken';$r.Problem="Payload dòng $n không phải JSON hợp lệ.";break}
        if($e.Sequence-ne$n){$r.Integrity='Broken';$r.Problem="Dòng $n có Sequence $($e.Sequence).";break}
        if($e.PreviousHash-ne$previous){$r.Integrity='Broken';$r.Problem="Dòng $n không nối với hash dòng trước.";break}
        if($e.Hash-ne(Get-MCJournalDigest ($previous+"`n"+$e.Payload))){$r.Integrity='Broken';$r.Problem="Hash dòng $n không khớp nội dung.";break}
        $previous=$e.Hash;$sequence=$n;$r.Entries=$n
        $kind=if($p.PSObject.Properties['Kind']){[string]$p.Kind}else{''}
        if($kind-eq'Plan'){
            if($n-ne1){$r.Integrity='Broken';$r.Problem="Plan xuất hiện ở dòng $n.";break}
            if($p.PSObject.Properties['Capability']){$r.Capability=[string]$p.Capability}
            if($p.PSObject.Properties['Items']){$r.Items=@($p.Items).Count}
            if($p.PSObject.Properties['Utc']){$r.Started=[string]$p.Utc}
        }elseif($n-eq1){$r.Integrity='Broken';$r.Problem='Dòng đầu không phải Plan.';break}
        elseif($kind-eq'Item'){if($p.Stage-eq'Committed'){$deleted[[string]$p.Identity]=$true}}
        elseif($kind-eq'Outcome'){
            $status=if($p.PSObject.Properties['Result']-and$p.Result.PSObject.Properties['Status']){[string]$p.Result.Status}elseif($p.PSObject.Properties['Status']){[string]$p.Status}else{''}
            if($status-eq'Exited'-or$status-like'Deleted*'){$r.Done++}elseif($status-like'Held*'){$r.Held++}else{$r.Skipped++}
        }
        elseif($kind-eq'Finished'){$r.Status=[string]$p.Status;$r.Finished=[string]$p.Utc}
    }
    if($r.Integrity-eq'NotChain'){$r.Status='Unknown';return [pscustomobject]$r}
    if($r.Integrity-ne'Broken'){
        if(-not$read.EndsWithNewline){$r.Integrity='Broken';$r.Problem='Dòng cuối bị cắt cụt.'}
        else{$r.Integrity='Valid'}
    }
    if($r.Type-eq'Temp'){$r.Done=[Math]::Max($r.Done,$deleted.Count)}
    if(-not$r.Status){$r.Status=if($r.Integrity-eq'Valid'){'Interrupted'}else{'Unknown'}}
    [pscustomobject]$r
}

function Get-MCJournalHistory {
    param([string]$ProjectRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),[ValidateRange(1,500)][int]$Limit=50,[ValidateSet('All','Temp','Memory')][string]$Type='All')
    $dir=Join-Path $ProjectRoot '.data'
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){return @()}
    $files=@(Get-ChildItem -LiteralPath $dir -File -Force|Where-Object{$_.Name-match$script:Pattern})
    if($Type-ne'All'){$prefix=$Type.ToLowerInvariant()+'-operation-';$files=@($files|Where-Object{$_.Name.StartsWith($prefix)})}
    $files=@($files|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First $Limit)
    foreach($f in $files){Test-MCJournal $f.FullName}
}

Export-ModuleMember -Function Test-MCJournal,Get-MCJournalHistory
