#requires -version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
$checks=0
function Assert {param([bool]$Condition,[string]$Message);if(-not$Condition){throw $Message};$script:checks++}
function Click {param($Button);$Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))}
function RenderReview {param($View,[string]$Name)
    $content=$View.Window.Content;$content.Measure([Windows.Size]::new(980,650));$content.Arrange([Windows.Rect]::new(0,0,980,650));$content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(980,650,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $projectRoot ('artifacts\'+$Name+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
function FindCheckbox {param($Visual,[string]$Id)
    if($Visual-is[Windows.Controls.CheckBox]-and$Visual.DataContext-and$Visual.DataContext.Id-eq$Id){return $Visual}
    for($i=0;$i-lt[Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual);$i++){$found=FindCheckbox ([Windows.Media.VisualTreeHelper]::GetChild($Visual,$i)) $Id;if($found){return $found}}
}
$root=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
[IO.File]::WriteAllText((Join-Path $root '.memoryclear-fixture'),'Review UI fixture')
foreach($name in @('sample-save.db','sample-protected.bin')){[IO.File]::WriteAllText((Join-Path $root $name),'Do not delete fixture')}
Import-Module (Join-Path $projectRoot 'app\CleanData\MemoryClear.Disk.psm1')
$scan=Get-MCDiskScan -FixtureRoots @($root);$rows=@($scan.Rows|Where-Object{$_.Name-ne'.memoryclear-fixture'});$risks=@{};foreach($row in $rows){$risks[$row.Identity]=if($row.Name-eq'sample-save.db'){'Danger'}else{'Blocked'};$row.Effect='Ví dụ: xóa vĩnh viễn có thể mất database/save, không có Undo.'}
$view=New-MCDiskReviewWindow $scan $rows 'ui-scope' -FixtureRisks $risks
try{
    Assert ($diskUI.Count-eq29-and$diskUI.DiskReview) 'Expected 29 main Disk controls including review entry'
    Assert (-not$diskUI.DiskReview.IsEnabled) 'Review entry must be disabled without selection'
    $script:diskResult=$scan;Update-MCDiskView;$diskUI.DiskFiles.SelectedItem=$rows[0]
    Assert $diskUI.DiskReview.IsEnabled 'Review entry must enable only with current selection'
    Set-MCOperationState $true;Assert (-not$diskUI.DiskReview.IsEnabled-and-not$ui.ClearMemory.IsEnabled) 'Review entry must follow shared lock';Set-MCOperationState $false
    Assert ($view.State.Stage-eq'Review'-and$view.State.BlockedCount-eq1-and-not$view.UI.ReviewConfirm.IsEnabled) 'Initial review state unsafe'
    Click $view.UI.ReviewNext;Assert ($view.State.Stage-eq'Review') 'Cannot skip per-item acknowledgment'
    RenderReview $view 'disk-review-step1'
    $danger=@($view.Rows|Where-Object{$_.Risk-eq'Danger'})[0];$blocked=@($view.Rows|Where-Object{$_.Risk-eq'Blocked'})[0]
    $checkbox=FindCheckbox $view.UI.ReviewItems $danger.Id;$blockedBox=FindCheckbox $view.UI.ReviewItems $blocked.Id
    Assert ($checkbox-and$checkbox.IsEnabled-and$blockedBox-and-not$blockedBox.IsEnabled) 'Checkboxes must be editable only for risky eligible rows'
    $checkbox.IsChecked=$true;$checkbox.GetBindingExpression([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty).UpdateSource()
    Assert $danger.Reviewed 'Checkbox binding failed to record per-item review'
    Click $view.UI.ReviewNext;Assert ($view.State.Stage-eq'Confirm'-and$view.UI.ReviewFinalPanel.Visibility-eq'Visible'-and-not$danger.CanReview) 'Final step must freeze item review'
    RenderReview $view 'disk-review-step2'
    Click $view.UI.ReviewConfirm;Assert ($view.State.Stage-eq'Confirm') 'Final acknowledgment required'
    $view.UI.ReviewAcknowledge.IsChecked=$true;$view.UI.ReviewPhrase.Text='wrong';Click $view.UI.ReviewConfirm;Assert ($view.State.Stage-eq'Confirm') 'Wrong phrase was accepted'
    Click $view.UI.ReviewBack;Assert ($view.State.Stage-eq'Review'-and-not$danger.Reviewed-and-not$view.UI.ReviewAcknowledge.IsChecked-and$view.UI.ReviewPhrase.Text-eq'') 'Back must clear both approval steps'
    $danger.Reviewed=$true;Click $view.UI.ReviewNext;$view.UI.ReviewAcknowledge.IsChecked=$true;$view.UI.ReviewPhrase.Text=$view.State.Phrase;Click $view.UI.ReviewConfirm
    Assert ($view.State.Stage-eq'PreviewApproved'-and-not$view.UI.ReviewConfirm.IsEnabled-and-not$view.State.ExecutionEnabled-and$view.State.DeletedBytes-eq0) 'Completion must be preview only, non-replayable'
    Assert ((Test-Path (Join-Path $root 'sample-save.db'))-and-not$view.State.ExecutionEnabled) 'Readonly review must never delete or grant cleanup authority'
}finally{$view.Window.Close();Close-MCDiskReview $view.SessionId}
$blockedView=New-MCDiskReviewWindow $scan $rows 'production-preview'
try{Assert (-not$blockedView.UI.ReviewNext.IsEnabled-and$blockedView.State.EligibleCount-eq0-and$blockedView.State.BlockedCount-eq2) 'Normal GUI cannot treat fixture/catalog risk claims as cleanup authority'}finally{$blockedView.Window.Close();Close-MCDiskReview $blockedView.SessionId}
Reset-MCDiskPreview;Assert (-not$diskUI.DiskReview.IsEnabled) 'Clearing scan must disable review entry'
[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=$checks;Failed=0;Scope='Offscreen WPF event handlers, actual checkbox binding, native marked fixtures; no visible app/user-data changes';Images=@('artifacts/disk-review-step1.png','artifacts/disk-review-step2.png');DeletionEnabled=$false}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $projectRoot 'docs\verification\disk-review-ui-tests.json') -Encoding UTF8
$window.Close();Write-Output "PASS Review UI: $checks checks, preview only."
