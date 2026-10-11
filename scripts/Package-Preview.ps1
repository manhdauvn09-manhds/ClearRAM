#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
Write-Host "Packaging MemoryClear source preview from $projectRoot"
$sourceFiles=@('MemoryClear.ps1','MemoryClear.Cli.ps1','Start-MemoryClear.cmd','app','tests','docs','plan','scripts','README.md','Handoff.md','IMPLEMENTATION_PLAN.md','MemoryClear-Plan.html','MemoryClear-CleanData-Plan.html','MemoryClear-Memory-Plan.html','MemoryClear-CleanData-Prototype.html','AGENTS.md')
foreach($relativePath in $sourceFiles){if(-not(Test-Path -LiteralPath (Join-Path $projectRoot $relativePath))){throw "Missing source: $relativePath"}}
foreach($relativePath in @('MemoryClear.ps1','MemoryClear.Cli.ps1','app\MemoryClear.Core.psm1','app\MemoryClear.Clear.psm1','app\CleanData\TempCleanup.psm1','app\MemoryClear.Tasks.psm1','app\MemoryTaskView.ps1','app\CleanData\Operations.psm1','app\CleanData\OperationView.ps1','app\CleanData\WindowsProviders.psm1','scripts\Verify-Readiness.ps1','scripts\Preview-DiskOperations.ps1')){
    $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot $relativePath),[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){throw ($relativePath+': '+(($errors|ForEach-Object{$_.Message})-join'; '))}
}
$outputDirectory=Join-Path $projectRoot 'artifacts';New-Item -ItemType Directory -Path $outputDirectory -Force|Out-Null
$archivePath=Join-Path $outputDirectory ('MemoryClear-PowerShell-Clear-preview-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'.zip')
if(Test-Path -LiteralPath $archivePath){throw 'Output already exists; run again after one second.'}
Compress-Archive -LiteralPath @($sourceFiles|ForEach-Object{Join-Path $projectRoot $_}) -DestinationPath $archivePath -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
try{foreach($required in @('MemoryClear.ps1','app/MemoryClear.Clear.psm1','app/clear-policy.json','app/clear-policy.schema.json','app/CleanData/TempCleanup.psm1','app/memory-task-policy.json','app/MemoryTaskView.xaml','app/CleanData/Operations.psm1','app/CleanData/OperationView.xaml','app/CleanData/WindowsProviders.psm1','app/disk-execution-policy.json','MemoryClear-CleanData-Plan.html','MemoryClear-Memory-Plan.html','scripts/Verify-Readiness.ps1')){
    if(-not@($archive.Entries|Where-Object{$_.FullName.Replace('\','/')-eq$required}).Count){throw "Missing packaged file: $required"}
}}finally{$archive.Dispose()}
$hash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[IO.File]::WriteAllText(($archivePath+'.sha256'),($hash+'  '+[IO.Path]::GetFileName($archivePath)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
Write-Host "Archive verified: $archivePath"
Write-Host "SHA256: $hash"
Write-Host 'Source preview only. Does not certify Windows/VM/soak acceptance. Personal .data is excluded.'
