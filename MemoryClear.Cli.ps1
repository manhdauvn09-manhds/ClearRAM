#requires -version 5.1
[CmdletBinding()]
param([ValidateSet('List','Inspect','Close','Kill')][string]$Command='List',[int]$ProcessId=0,[long]$StartTicks=0,[switch]$Json,[switch]$Execute)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'app\MemoryClear.Core.psm1') -Force
try {
    if($Command-eq'List'){$first=Get-MCSnapshot;Start-Sleep -Milliseconds 700;$snapshot=Get-MCSnapshot -Previous $first;$result=@($snapshot.Rows|Select-Object Name,Pid,StartTicks,RamMB,PrivateMB,Cpu,Policy,Allowed,Path)}
    elseif($Command-eq'Inspect'){$snapshot=Get-MCSnapshot;$result=@($snapshot.Rows|Where-Object{$_.Pid-eq$ProcessId}|Select-Object Name,Pid,StartTicks,RamMB,PrivateMB,Cpu,Policy,Allowed,Path);if(-not$result.Count){throw 'Process not found.'}}
    else{if($ProcessId-le0-or$StartTicks-le0){throw 'Close/Kill require -ProcessId and -StartTicks from List/Inspect.'}
      if(-not$Execute){$result=[pscustomobject]@{DryRun=$true;Pid=$ProcessId;StartTicks=$StartTicks;Action=$Command;Message='No action performed. Use -Execute for an interactive confirmation.'}}
      else{$result=Invoke-MCAction -ProcessId $ProcessId -StartTicks $StartTicks -Action $Command;if($result.Status-eq'Denied'){if($Json){$result|ConvertTo-Json -Depth 5}else{$result};exit 2}}
    }
    if($Json){ConvertTo-Json -InputObject $result -Depth 5}else{$result}
}catch{Write-Error $_.Exception.Message;exit 1}
