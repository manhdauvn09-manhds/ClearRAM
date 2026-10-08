#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$launcher=Join-Path $projectRoot 'MemoryClear.ps1'
$desktopPath=[Environment]::GetFolderPath('Desktop')
$powerShellPath=Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(-not(Test-Path -LiteralPath $launcher)){throw "Missing launcher: $launcher"}
if(-not(Test-Path -LiteralPath $powerShellPath)){throw "Missing Windows PowerShell: $powerShellPath"}
if(-not$desktopPath-or-not(Test-Path -LiteralPath $desktopPath)){throw 'Desktop folder not found.'}
$shortcutPath=Join-Path $desktopPath 'MemoryClear.lnk'
$arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$launcher+'"'
Write-Host "Creating MemoryClear shortcut: $shortcutPath"
$shell=$null;$shortcut=$null;$verify=$null
try {
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($shortcutPath)
    if((Test-Path -LiteralPath $shortcutPath)-and$shortcut.Arguments-ne$arguments){throw 'An existing MemoryClear shortcut has a different command; preserve it and choose a different name.'}
    $shortcut.TargetPath=$powerShellPath
    $shortcut.Arguments=$arguments
    $shortcut.WorkingDirectory=$projectRoot
    $shortcut.Description='MemoryClear - PowerShell GUI, RAM and CPU monitor'
    $shortcut.IconLocation=$powerShellPath+',0'
    $shortcut.WindowStyle=7
    $shortcut.Save()
    $verify=$shell.CreateShortcut($shortcutPath)
    if(-not(Test-Path -LiteralPath $shortcutPath)-or$verify.TargetPath-ne$powerShellPath-or$verify.Arguments-ne$arguments-or$verify.WorkingDirectory-ne$projectRoot){throw 'Shortcut readback verification failed.'}
    $reportDirectory=Join-Path $projectRoot 'artifacts';New-Item -ItemType Directory -Path $reportDirectory -Force|Out-Null
    [pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Shortcut=$shortcutPath;Target=$verify.TargetPath;Arguments=$verify.Arguments;WorkingDirectory=$verify.WorkingDirectory;Verified=$true;Launched=$false}|ConvertTo-Json|Set-Content (Join-Path $reportDirectory 'desktop-shortcut.json') -Encoding UTF8
    Write-Host 'SHORTCUT_VERIFIED: Double-click MemoryClear on your Desktop to open the GUI.'
} finally {
    foreach($comObject in @($verify,$shortcut,$shell)){if($null-ne$comObject){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)}}
}
