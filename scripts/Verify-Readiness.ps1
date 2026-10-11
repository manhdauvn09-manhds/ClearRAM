#requires -version 5.1
[CmdletBinding()]
param([ValidateSet('AnySupportedClient','Windows10','Windows11')][string]$ExpectedFamily='AnySupportedClient',[switch]$DisposableVM,[switch]$Package,[switch]$OpenApp,[switch]$OwnTempSelfTest)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $projectRoot
$powerShellHost=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$outputRoot=Join-Path $projectRoot ('artifacts\readiness-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $outputRoot|Out-Null
$steps=New-Object 'System.Collections.Generic.List[object]';$failure=$null;$transcript=Join-Path $outputRoot 'transcript.txt';Start-Transcript -LiteralPath $transcript|Out-Null
function Step {
    param([string]$Name,[scriptblock]$Action)
    Write-Host "Running: $Name";$watch=[Diagnostics.Stopwatch]::StartNew()
    try{&$Action;if($LASTEXITCODE-ne0){throw "Exit code $LASTEXITCODE"};$steps.Add([pscustomobject]@{Name=$Name;Status='Passed';Seconds=$watch.Elapsed.TotalSeconds;Error=''})}
    catch{$steps.Add([pscustomobject]@{Name=$Name;Status='Failed';Seconds=$watch.Elapsed.TotalSeconds;Error=$_.Exception.Message});throw}
}
$osInfo=$null;$family='Unknown';$build=0;$capSource='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion/CurrentBuildNumber + InstallationType'
try{
    Write-Host 'Readiness checks mutate only disposable marked fixtures and the app own reports; general finder/app-data deletion stays disabled. Own Temp QA runs only with -OwnTempSelfTest.'
    $osInfo=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    if(-not[int]::TryParse([string]$osInfo.CurrentBuildNumber,[ref]$build)-or$osInfo.InstallationType-ne'Client'-or$build-lt10240){throw 'Supported Windows client build cannot be verified.'}
    $family=if($build-ge22000){'Windows11'}else{'Windows10'}
    Write-Host "OS: $family / $build / $($osInfo.DisplayVersion), source: $capSource"
    if($ExpectedFamily-ne'AnySupportedClient'-and$ExpectedFamily-ne$family){throw "Expected $ExpectedFamily, observed $family. Refusing to record a different platform as coverage."}
    Step 'Disk suites' {&$powerShellHost -NoProfile -File (Join-Path $projectRoot 'scripts\Verify-Phase10.ps1')}
    if($OwnTempSelfTest){
        Step 'Own Temp exact QA self-test' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'scripts\Verify-OwnTemp.ps1')}
        Step 'Own Temp WPF QA' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-TempUI.ps1')}
    }
    Step 'RAM Clear fixtures' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-Clear.ps1')}
    Step 'RAM checkbox fixtures' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-Checkboxes.ps1')}
    Step 'Memory level policy and readonly preview' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-MemoryLevels.ps1')}
    Step 'Core unit tests' {&$powerShellHost -NoProfile -File (Join-Path $projectRoot 'tests\Run-Tests.ps1')}
    Step 'Task graceful release own-child QA' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-TaskRelease.ps1')}
    Step 'Task window real dispatcher QA' {&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'tests\Check-TaskUI.ps1')}
    foreach($script in @('build-plan','check-plan','build-clean-data','check-clean-data','check-memory-design','check-runtime-policies')){
        $scriptPath=Join-Path $projectRoot ('plan\'+$script+'.mjs');Step $script {& node $scriptPath}
    }
    Step 'All PS5 sources parse' {
        $parseFiles=@(Get-ChildItem (Join-Path $projectRoot 'app'),(Join-Path $projectRoot 'tests'),(Join-Path $projectRoot 'scripts') -Recurse -File|Where-Object{$_.Extension-in@('.ps1','.psm1')})+@(Get-Item (Join-Path $projectRoot 'MemoryClear.ps1'),(Join-Path $projectRoot 'MemoryClear.Cli.ps1'))
        foreach($source in $parseFiles){$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($source.FullName,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ($source.Name+': '+(($errors|ForEach-Object{$_.Message})-join'; '))}}
        $global:LASTEXITCODE=0
    }
    if($Package){Step 'Package source preview' {&$powerShellHost -NoProfile -File (Join-Path $projectRoot 'scripts\Package-Preview.ps1')}}
}catch{$failure=$_.Exception.Message;Write-Host "FAILED: $failure" -ForegroundColor Red}
finally{
    $codeFiles=@(Get-ChildItem (Join-Path $projectRoot 'app') -Recurse -File)+@(Get-Item (Join-Path $projectRoot 'MemoryClear.ps1'),(Join-Path $projectRoot 'MemoryClear.Cli.ps1'))
    $hashes=@($codeFiles|ForEach-Object{[pscustomobject]@{Path=$_.FullName.Substring($projectRoot.Length+1);Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
    $report=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Family=$family;Build=$build;OSProvenance=$capSource;FamilyInference='Client build >=22000 classified Windows11; >=10240 Windows10';DisposableVMDeclaredByOperator=[bool]$DisposableVM;VMProofIndependent=$false;Status=if($failure){'Failed'}else{'LocalChecksPassed_ReleaseUnverified'};Error=$failure;Steps=$steps.ToArray();CodeHashes=$hashes;ReviewedTempCleanupAvailable=$true;GeneralFinderOrAppDataDeletionEnabled=$false;OwnTempSelfTestRequested=[bool]$OwnTempSelfTest;MissingReleaseEvidence=@('Verified orphan/app-data production authority','Windows10 and Windows11 VM matrix','External backup/full disk/disconnect and power loss','Mapped writers/filter drivers/multi-instance','Keyboard/DPI/operator acceptance');Transcript=$transcript}
    $report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $outputRoot 'readiness.json') -Encoding UTF8
    Write-Host ('Report: '+(Join-Path $outputRoot 'readiness.json'));Write-Host 'Local success does not unlock general finder/app-data cleanup or certify a release. Reviewed Temp is a separate narrow capability.';Stop-Transcript|Out-Null
}
if($failure){exit 1}
if($OpenApp){&$powerShellHost -NoProfile -STA -File (Join-Path $projectRoot 'MemoryClear.ps1');if($LASTEXITCODE-ne0){exit $LASTEXITCODE}}
