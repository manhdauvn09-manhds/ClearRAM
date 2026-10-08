#requires -version 5.1
param([int]$Samples=4)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'app\MemoryClear.Core.psm1') -Force
$before=[MemoryClear.Native]::ReadSystem();$os=Get-CimInstance Win32_OperatingSystem;$after=[MemoryClear.Native]::ReadSystem()
$referenceTotal=[long]$os.TotalVisibleMemorySize*1KB;$referenceAvailable=[long]$os.FreePhysicalMemory*1KB
$availableTolerance=[Math]::Max(64MB,0.1*$referenceAvailable)
$totalMatch=[Math]::Abs([double]$after.TotalBytes-$referenceTotal)-le1MB
$availableMatch=$referenceAvailable-ge([Math]::Min($before.AvailableBytes,$after.AvailableBytes)-$availableTolerance)-and$referenceAvailable-le([Math]::Max($before.AvailableBytes,$after.AvailableBytes)+$availableTolerance)
$watch=[Diagnostics.Stopwatch]::StartNew();$previous=Get-MCSnapshot;$cold=$watch.Elapsed.TotalMilliseconds
$process=[Diagnostics.Process]::GetCurrentProcess();$process.Refresh();$cpuBefore=$process.TotalProcessorTime.TotalSeconds;$steady=[Diagnostics.Stopwatch]::StartNew();$durations=@();$maxWorkingSet=0.0
for($i=0;$i-lt$Samples;$i++){Start-Sleep -Seconds 3;$scan=[Diagnostics.Stopwatch]::StartNew();$previous=Get-MCSnapshot $previous;$scan.Stop();$durations+=@($scan.Elapsed.TotalMilliseconds);$process.Refresh();$maxWorkingSet=[Math]::Max($maxWorkingSet,$process.WorkingSet64/1MB)}
$process.Refresh();$cpuPercent=100*($process.TotalProcessorTime.TotalSeconds-$cpuBefore)/$steady.Elapsed.TotalSeconds/[Environment]::ProcessorCount
$report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');OS=$os.Caption;Build=$os.BuildNumber;LogicalCPUs=[Environment]::ProcessorCount;PowerShell=$PSVersionTable.PSVersion.ToString();Samples=$Samples;TotalMatchesCIM=$totalMatch;AvailableWithinCIMWindow=$availableMatch;AvailableToleranceMB=[Math]::Round($availableTolerance/1MB,1);TotalGB=[Math]::Round($after.TotalBytes/1GB,2);ColdScanMs=[Math]::Round($cold,1);AverageSteadyScanMs=[Math]::Round(($durations|Measure-Object -Average).Average,1);CpuPercentWholeMachine=[Math]::Round($cpuPercent,2);PeakObservedWorkingSetMB=[Math]::Round($maxWorkingSet,1);Scope='Short collector baseline only. Not GUI idle/soak or VM acceptance.'}
New-Item -ItemType Directory -Path (Join-Path $root 'artifacts') -Force|Out-Null
$report|ConvertTo-Json|Set-Content (Join-Path $root 'artifacts\monitor-baseline.json') -Encoding UTF8
$report
if(-not$totalMatch-or-not$availableMatch){exit 1}
