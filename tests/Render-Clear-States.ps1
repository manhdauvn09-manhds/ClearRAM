#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
$script:snapshot=[pscustomobject]@{Rows=[MemoryClear.ProcessRow[]]@();System=[MemoryClear.Native]::ReadSystem();Cpu=$null};Update-MCView
function Save-ClearStateImage {
    param([string]$Name)
    $content=$window.Content;$content.Measure([Windows.Size]::new(1072,700));$content.Arrange([Windows.Rect]::new(0,0,1072,700));$content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1072,700,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $path=Join-Path $projectRoot ('artifacts\'+$Name);$stream=[IO.File]::Create($path);try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
# UI examples only. Dummy in-flight scan prevents launching any real Clear worker.
$script:job=[pscustomobject]@{DummyScan=$true};$ui.StrongClear.IsChecked=$true
Start-MCOneClickClear
$clearProgressQueue.Enqueue([pscustomobject]@{Stage='Processing';Message='Đang kiểm tra process thử · 2/7 (minh họa giao diện, chưa trim app thật).';Processed=2;Total=7})
Update-MCClearProgress;Save-ClearStateImage 'clear-running-preview.png'
Complete-MCClearUI ([pscustomobject]@{Status='CandidatesFinished';Message='Hoàn tất minh họa giao diện; không thực hiện Clear trên app công việc.'})
Save-ClearStateImage 'clear-completed-preview.png'
$clearCancellation.Cancel();$clearCancellation.Dispose();$script:clearCancellation=$null;$script:job=$null
Write-Output 'CLEAR_STATE_RENDER_PASS running and completed controls; illustrative events only, no user process actions'
