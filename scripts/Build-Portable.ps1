#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Set-Location -LiteralPath $root
$version='2026.10.11.1-preview'
$id=[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
$out=Join-Path $root ('artifacts\releases\'+$id);$package=Join-Path $out 'MemoryClear'
New-Item -ItemType Directory -Path $package|Out-Null
Write-Host "Building portable PS5.1 package $version at $package"
foreach($name in @('MemoryClear.ps1','MemoryClear.Cli.ps1','Start-MemoryClear.cmd','MemoryClear-Plan.html','MemoryClear-CleanData-Plan.html','MemoryClear-Memory-Plan.html','MemoryClear-CleanData-Prototype.html')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $package $name)}
Copy-Item -LiteralPath (Join-Path $root 'app') -Destination (Join-Path $package 'app') -Recurse
Copy-Item -LiteralPath (Join-Path $root 'scripts\Create-PortableShortcut.ps1') -Destination (Join-Path $package 'Create-DesktopShortcut.ps1')
$readme=@'
MemoryClear portable preview - Windows PowerShell 5.1 / WPF

Run: double-click Start-MemoryClear.cmd. No Node, SDK or administrator elevation required.
Extract the whole folder first; do not launch inside ZIP. Keep app beside MemoryClear.ps1.

Available: Clear Normal/Strong (working-set trim, no automatic killing), three Memory cards,
saved opt-in/task-impact preview, reviewed user Temp cleanup with progress/cancel/journal,
large-file discovery and Windows Storage delegation. Large files are not automatically junk.

Memory level 3 graceful executor is prepared and tested only against disposable QA children.
The shipped executionEnabled=false safety gate stays closed pending full safety/action acceptance.
No automatic force, UAC bypass, arbitrary app-data deletion or recursive system cleanup.
Win11 local checks do not certify Windows10 or a final production release.

Personal settings/history are excluded. A fresh .data folder is created on first use.
Existing source-folder settings remain untouched. The opt-in list starts empty in this folder.
Local operation journals are tamper-evident, not a server-enforced security boundary.

SHA256 manifest: package-manifest.json. ZIP checksum: adjacent .sha256 file.
'@
[IO.File]::WriteAllText((Join-Path $package 'README-RUN.txt'),$readme,[Text.UTF8Encoding]::new($true))
$files=@(Get-ChildItem -LiteralPath $package -Recurse -File)
$manifest=[pscustomobject]@{Version=$version;Timestamp=[DateTime]::UtcNow.ToString('o');Kind='PortablePreview';Windows10Verified=$false;PersonalDataIncluded=$false;MemoryTaskExecutionEnabled=$false;Files=@($files|ForEach-Object{[pscustomobject]@{Path=$_.FullName.Substring($package.Length+1);Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})}
$manifest|ConvertTo-Json -Depth 6|Set-Content (Join-Path $package 'package-manifest.json') -Encoding UTF8
foreach($file in $files|Where-Object{$_.Extension-in@('.ps1','.psm1')}){$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ($file.FullName+': '+($errors.Message-join'; '))}}
Write-Host 'Verifying packaged WPF loading and native compilation (no cleaning actions)...'
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -File (Join-Path $package 'MemoryClear.ps1') -SmokeTest -ControlsOnly
if($LASTEXITCODE-ne0){throw 'Packaged GUI smoke failed'}
$zip=Join-Path $out ('MemoryClear-'+$version+'.zip');Compress-Archive -LiteralPath $package -DestinationPath $zip -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try{foreach($entry in $manifest.Files){$name='MemoryClear/'+$entry.Path.Replace('\','/');$z=@($archive.Entries|Where-Object{$_.FullName.Replace('\','/')-eq$name});if($z.Count-ne1){throw ('Missing ZIP entry: '+$name)};$s=$z[0].Open();$hash=[Security.Cryptography.SHA256]::Create();try{$actual=[BitConverter]::ToString($hash.ComputeHash($s)).Replace('-','');if($actual-ne$entry.Sha256){throw ('ZIP hash mismatch: '+$name)}}finally{$s.Dispose();$hash.Dispose()}};if(@($archive.Entries|Where-Object{$_.FullName-match'(^|/)(\.data|\.git|\.harness|\.claude)/'}).Count){throw 'Private data entered archive'}}finally{$archive.Dispose()}
$sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
[IO.File]::WriteAllText(($zip+'.sha256'),($sha+'  '+[IO.Path]::GetFileName($zip)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
$proof=[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Version=$version;Folder=$package;Launcher=(Join-Path $package 'Start-MemoryClear.cmd');Archive=$zip;Sha256=$sha;FileCount=$manifest.Files.Count;PackagedControlsSmoke='Passed';ArchiveEntryHashes='Passed';ReleaseAcceptance='Unverified';MemoryTaskExecutionEnabled=$false}
$proof|ConvertTo-Json|Set-Content (Join-Path $root 'docs\verification\portable-build.json') -Encoding UTF8
Write-Host "READY: $zip"
Write-Host "RUN: $(Join-Path $package 'Start-MemoryClear.cmd')"
