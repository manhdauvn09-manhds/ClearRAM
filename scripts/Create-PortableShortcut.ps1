#requires -version 5.1
[CmdletBinding()]
param([string]$PackageRoot='')
$ErrorActionPreference='Stop'
if(-not$PackageRoot){$PackageRoot=$PSScriptRoot}
$bundle=[IO.Path]::GetFullPath($PackageRoot);Set-Location -LiteralPath $bundle
$launcher=Join-Path $bundle 'MemoryClear.ps1'
if(-not(Test-Path -LiteralPath $launcher -PathType Leaf)){throw "Missing launcher: $launcher"}
$desktop=[Environment]::GetFolderPath('Desktop');if(-not$desktop-or-not(Test-Path -LiteralPath $desktop)){throw 'Desktop unavailable'}
$hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcutPath=Join-Path $desktop 'MemoryClear Portable 2026-10-11.lnk'
$argsText='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$launcher+'"'
Write-Host "Creating portable shortcut: $shortcutPath"
$shell=$null;$shortcut=$null;$check=$null
try{$shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($shortcutPath)
 if((Test-Path -LiteralPath $shortcutPath)-and($shortcut.Arguments-ne$argsText-or$shortcut.TargetPath-ne$hostPath)){throw 'Different existing shortcut preserved. Remove or rename it yourself before retrying.'}
 $shortcut.TargetPath=$hostPath;$shortcut.Arguments=$argsText;$shortcut.WorkingDirectory=$bundle;$shortcut.Description='MemoryClear portable preview 2026-10-11';$shortcut.IconLocation=$hostPath+',0';$shortcut.WindowStyle=7;$shortcut.Save()
 $check=$shell.CreateShortcut($shortcutPath);if($check.TargetPath-ne$hostPath-or$check.Arguments-ne$argsText-or$check.WorkingDirectory-ne$bundle){throw 'Shortcut readback failed'}
 Write-Host "VERIFIED: $shortcutPath"
 [pscustomobject]@{Shortcut=$shortcutPath;Target=$check.TargetPath;Arguments=$check.Arguments;WorkingDirectory=$check.WorkingDirectory;Verified=$true;Launched=$false}
}finally{foreach($c in @($check,$shortcut,$shell)){if($c){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($c)}}}
