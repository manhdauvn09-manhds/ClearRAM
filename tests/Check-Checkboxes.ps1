#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
# Load the real window, bindings and handlers offscreen. No process action is invoked.
. (Join-Path $root 'MemoryClear.ps1') -SmokeTest -ControlsOnly
$testFolder=Join-Path $root ('artifacts\checkbox-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testFolder -Force|Out-Null
$module=Get-Module MemoryClear.Core
& $module {param($Directory);$script:Data=$Directory} $testFolder
$fixture=Join-Path $testFolder 'CheckboxFixture.exe'
Add-Type -TypeDefinition 'using System; using System.Threading; public class CheckboxFixture { public static void Main() { Thread.Sleep(60000); } }' -OutputAssembly $fixture -OutputType WindowsApplication
$children=@();$report=$null
function Assert-Checkbox {param([bool]$Condition,[string]$Message);if(-not$Condition){throw $Message}}
function Find-TaggedCheckbox {
    param([Windows.DependencyObject]$Node,[string]$Tag)
    if($Node-is[Windows.Controls.CheckBox]-and$Node.Tag-eq$Tag){return $Node}
    for($i=0;$i-lt[Windows.Media.VisualTreeHelper]::GetChildrenCount($Node);$i++){$found=Find-TaggedCheckbox ([Windows.Media.VisualTreeHelper]::GetChild($Node,$i)) $Tag;if($found){return $found}}
}
function Get-RowCheckbox {
    param($Item,[string]$Tag)
    $ui.Processes.ScrollIntoView($Item);$ui.Processes.UpdateLayout()
    $container=$ui.Processes.ItemContainerGenerator.ContainerFromItem($Item)
    Assert-Checkbox ($null-ne$container) 'Could not generate DataGrid row.'
    $checkbox=Find-TaggedCheckbox $container $Tag
    Assert-Checkbox ($null-ne$checkbox) "Checkbox not found: $Tag"
    return $checkbox
}
function Click-SelectionCheckbox {
    param($Checkbox)
    $event=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,[Environment]::TickCount,[Windows.Input.MouseButton]::Left)
    $event.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseDownEvent
    $Checkbox.RaiseEvent($event)
}
function Click-AllowCheckbox {
    param($Checkbox)
    [Windows.Controls.Primitives.ToggleButton].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($Checkbox,@())|Out-Null
}
try {
    $children=@((Start-Process -FilePath $fixture -WindowStyle Hidden -PassThru),(Start-Process -FilePath $fixture -WindowStyle Hidden -PassThru))
    Start-Sleep -Milliseconds 300
    $settings=Get-MCSettings;$context=Get-MCContext;$rows=@()
    foreach($processId in @($children[0].Id,$children[1].Id,$PID)){
        $identity=[MemoryClear.Native]::Inspect($processId);$policy=Test-MCPolicy $identity $context $settings
        $rows+=@([MemoryClear.ProcessRow]@{Pid=$processId;StartTicks=$identity.StartTicks;Path=$identity.Path;Name=$(if($processId-eq$PID){'Test host'}else{'CheckboxFixture'});Identity=$identity;Allowed=$policy.Allowed;AllowClose=$policy.AllowClose;Policy=$policy.Reason})
    }
    $script:snapshot=[pscustomobject]@{Rows=$rows;System=[MemoryClear.Native]::ReadSystem();Cpu=$null}
    $ui.Search.Text='CheckboxFixture';Update-MCView
    $content=$window.Content;$content.Measure([Windows.Size]::new(1072,684));$content.Arrange([Windows.Rect]::new(0,0,1072,684));$content.UpdateLayout()
    $row1=$ui.Processes.ItemsSource|Where-Object{$_.Pid-eq$children[0].Id};$row2=$ui.Processes.ItemsSource|Where-Object{$_.Pid-eq$children[1].Id}
    Assert-Checkbox ($row1.Allowed-and$row2.Allowed) ("Own disposable fixtures should be actionable: $($row1.Policy); $($row2.Policy). Service inventory known: $($context.ServicesKnown)")
    $select1=Get-RowCheckbox $row1.PSObject.BaseObject 'MCSelect';Click-SelectionCheckbox $select1
    $select2=Get-RowCheckbox $row2.PSObject.BaseObject 'MCSelect';Click-SelectionCheckbox $select2
    Assert-Checkbox ($ui.Processes.SelectedItems.Count-eq2) 'Checking second item must retain first selection without Ctrl.'
    Update-MCView
    Assert-Checkbox ($ui.Processes.SelectedItems.Count-eq2) 'Selection lost after refresh.'
    Click-SelectionCheckbox (Get-RowCheckbox $row1.PSObject.BaseObject 'MCSelect')
    Assert-Checkbox ($ui.Processes.SelectedItems.Count-eq1) 'Unchecking one item must retain the other.'
    Click-AllowCheckbox (Get-RowCheckbox $row1.PSObject.BaseObject 'MCAllowClose')
    Assert-Checkbox (@((Get-MCSettings).AllowClosePaths)-contains$fixture) 'Tick must persist executable permission.'
    $loadedSettings=Get-MCSettings
    foreach($row in $snapshot.Rows){$row.AllowClose=(Test-MCPolicy $row.Identity $context $loadedSettings).AllowClose};Update-MCView
    $row1=$snapshot.Rows|Where-Object{$_.Pid-eq$children[0].Id};$row2=$snapshot.Rows|Where-Object{$_.Pid-eq$children[1].Id}
    Assert-Checkbox ($row1.AllowClose-and$row2.AllowClose) 'Permission must persist after rescan and cover same executable.'
    Click-AllowCheckbox (Get-RowCheckbox $row1.PSObject.BaseObject 'MCAllowClose')
    Assert-Checkbox (-not(@((Get-MCSettings).AllowClosePaths)-contains$fixture)) 'Untick must remove saved permission.'
    $ui.Search.Text='';Update-MCView
    $self=$snapshot.Rows|Where-Object{$_.Pid-eq$PID}
    $blocked=Get-RowCheckbox $self.PSObject.BaseObject 'MCAllowClose'
    Assert-Checkbox (-not$blocked.IsEnabled) 'Protected process permission checkbox must be disabled.'
    foreach($child in $children){$child.Refresh();Assert-Checkbox (-not$child.HasExited) 'Checkboxes must not close or kill a process.'}
    $report=[pscustomobject]@{Passed=$true;PowerShell=$PSVersionTable.PSVersion.ToString();MultiSelectWithoutCtrl=$true;SelectionSurvivesRefresh=$true;AllowPermissionSaved=$true;PermissionSurvivesReload=$true;UntickRemovesPermission=$true;ProtectedCheckboxDisabled=$true;NoProcessAction=$true;Timestamp=[DateTime]::UtcNow.ToString('o')}
    $report|ConvertTo-Json|Set-Content (Join-Path $root 'artifacts\checkbox-tests.json') -Encoding UTF8
    Write-Output 'CHECKBOX_TESTS_PASS multi-select, refresh, permission save/rescan/remove, protection, no process actions'
} catch {
    [pscustomobject]@{Passed=$false;PowerShell=$PSVersionTable.PSVersion.ToString();Error=$_.Exception.Message;Timestamp=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'artifacts\checkbox-tests.json') -Encoding UTF8
    throw
} finally {
    foreach($child in $children){if(-not$child.HasExited){$child.Kill()};$child.Dispose()}
}
