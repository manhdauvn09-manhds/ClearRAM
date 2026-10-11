#requires -version 5.1
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$BackupRoot,[Parameter(Mandatory=$true)][ValidateSet('BackupVerified','DeleteStarted','Committed')][string]$Checkpoint)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent;Set-Location -LiteralPath $projectRoot
Import-Module (Join-Path $projectRoot 'app\CleanData\Operations.psm1')
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1')
& (Get-Module Operations) {
    param($checkpoint)
    $script:CrashCheckpoint=$checkpoint;$script:OriginalWrite=(Get-Command Write-MCOperationEvent).ScriptBlock
    function script:Write-MCOperationEvent {
        param($Ledger,$Event)
        & $script:OriginalWrite $Ledger $Event
        if($Event.PSObject.Properties['Stage']-and$Event.Stage-eq$script:CrashCheckpoint){[Environment]::Exit(77)}
    }
} $Checkpoint
$scan=Get-MCDiskScan -FixtureRoots @($SourceRoot);$rows=@($scan.Rows|Where-Object{$_.Name-eq'save.db'})
$p=New-MCDiskOperation $scan $rows -Mode Backup -BackupRoot $BackupRoot -ContextToken 'crash-fixture'
Move-MCDiskOperationReview $p.Id 'crash-fixture' @($p.Items.Id)|Out-Null
Confirm-MCDiskOperation $p.Id 'crash-fixture' -Acknowledged $true -Phrase $p.Phrase|Out-Null
Invoke-MCDiskOperation $p.Id 'crash-fixture'|Out-Null
throw 'Requested crash checkpoint was not reached.'
