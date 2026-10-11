#requires -version 5.1
param()
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
. (Join-Path $projectRoot 'MemoryClear.ps1') -SmokeTest -ControlsOnly
$script:diskUiChecks=0
function Assert {param([bool]$Condition,[string]$Message);if(-not$Condition){throw $Message};$script:diskUiChecks++}
Assert ( $diskUI.Count-eq29) 'Expected 29 disk controls'
Assert ($diskUI.DiskClean.IsEnabled-and$diskUI.DiskClean.Content-eq'Dọn Temp có duyệt...') 'Separate reviewed Temp entry must be available'
Assert ($window.FindName('MainTabs').Items.Count-eq2) 'Expected Memory and Disk tabs'
$script:diskResult=[pscustomobject]@{Offset=0;HasMore=$false;Rows=@([pscustomobject]@{Name='old-temp.bin';Path='C:\Fixture\old-temp.bin';Identity='fixture-ID';LogicalMB=12;AllocatedMB=12;AgeDays=10;Risk='SafeCandidate';RiskLabel='Temp cũ · ứng viên';Effect='Readonly fixture; not deletion permission'},[pscustomobject]@{Name='backup.vhdx';Path='C:\Fixture\backup.vhdx';Identity='fixture-VM';LogicalMB=10240;AllocatedMB=5120;AgeDays=120;Risk='NeedsReview';RiskLabel='Cần duyệt giá trị';Effect='Could contain VM/user data; not auto selected'})}
Update-MCDiskView;Assert ($diskUI.DiskFiles.Items.Count-eq2) 'Fixture rows missing'
$diskUI.DiskSearch.Text='backup';Assert ($diskUI.DiskFiles.Items.Count-eq1) 'Search must filter readonly rows'
$diskUI.DiskSearch.Text=''
Set-MCOperationState $true;Assert (-not$diskUI.DiskScan.IsEnabled-and-not$ui.ClearMemory.IsEnabled-and-not$diskUI.DiskChooseFolder.IsEnabled-and-not$diskUI.DiskMinimumMB.IsEnabled) 'Shared operation lock missing'
Set-MCOperationState $false;Assert ($diskUI.DiskScan.IsEnabled-and$ui.ClearMemory.IsEnabled) 'Shared lock release failed'
$fixture=Join-Path $projectRoot ('artifacts\disk-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture|Out-Null
[IO.File]::WriteAllText((Join-Path $fixture '.memoryclear-fixture'),'GUI worker fixture');[IO.File]::WriteAllText((Join-Path $fixture 'worker.txt'),'Do not delete')
Start-MCDiskScan -FixtureRoots @($fixture)
Assert ($diskRunning-and$operation-and-not$ui.ClearMemory.IsEnabled) 'Worker failed to claim shared operation'
$deadline=[DateTime]::UtcNow.AddSeconds(20)
while($diskRunning-and[DateTime]::UtcNow-lt$deadline){$frame=New-Object Windows.Threading.DispatcherFrame;$pump=New-Object Windows.Threading.DispatcherTimer;$pump.Interval=[TimeSpan]::FromMilliseconds(50);$pump.Add_Tick({$frame.Continue=$false;$pump.Stop()});$pump.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
Assert (-not$diskRunning-and-not$operation) 'Worker failed to release shared operation'
Assert ($diskResult.Status-eq'CompletedReadonly'-and$diskResult.Rows.Count-eq2) 'Native fixture worker result missing'
Assert (Test-Path -LiteralPath (Join-Path $fixture 'worker.txt')) 'Readonly worker changed data'
Assert $diskUI.DiskAnalyze.IsEnabled 'Analysis button should enable after a scan'
$fixtureInventory=[pscustomobject]@{Complete=$true;Apps=@([pscustomobject]@{Name='Example fixture app';Publisher='Fixture';Location=$fixture;Source='Fixture'})}
$fixtureDependencies=[pscustomobject]@{Complete=$false;CapturedUtc=[DateTime]::UtcNow;Entries=@();Sources=@();Issues=@('Fixture unknown service')}
Start-MCDiskOwnerAnalysis -FixtureInventory $fixtureInventory -FixtureDependencies $fixtureDependencies
Assert ($diskRunning-and$operation-and-not$diskUI.DiskAnalyze.IsEnabled-and-not$ui.ClearMemory.IsEnabled) 'Analysis must claim RAM/Disk shared lock'
$deadline=[DateTime]::UtcNow.AddSeconds(20)
while($diskRunning-and[DateTime]::UtcNow-lt$deadline){$frame=New-Object Windows.Threading.DispatcherFrame;$pump=New-Object Windows.Threading.DispatcherTimer;$pump.Interval=[TimeSpan]::FromMilliseconds(50);$pump.Add_Tick({$frame.Continue=$false;$pump.Stop()});$pump.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
Assert (-not$diskRunning-and-not$operation-and$diskResult.OwnershipAnalyzed-and$diskResult.Status-eq'Partial') 'Analysis worker must report incomplete inventory and release shared lock'
Assert ($diskResult.Rows[0].OwnerEvidence.State-eq'InstalledMetadataProtected'-and-not$diskResult.Rows[0].OwnerEvidence.DeletionAllowed-and(Test-Path -LiteralPath (Join-Path $fixture 'worker.txt'))) 'Analysis cannot grant deletion or change fixture'
$diskUI.DiskSearch.Text='Example fixture app';Assert ($diskUI.DiskFiles.Items.Count-eq2) 'Owner name should be searchable';$diskUI.DiskSearch.Text=''
$diskUI.DiskLarge.IsChecked=$true;$diskUI.DiskMinimumMB.Text='1';$diskUI.DiskMinimumAge.Text='30';$diskUI.DiskExtensions.Text='.iso,.zip'
$options=Get-MCDiskFinderOptions;Assert ($options.MinimumMB-eq1-and$options.MinimumAgeDays-eq30-and$options.Extensions.Count-eq2) 'Finder options did not parse'
Assert ($null-eq$diskResult-and$diskUI.DiskFiles.Items.Count-eq0-and-not$diskUI.DiskNext.IsEnabled) 'Finder changes must invalidate old preview/pages'
Assert (-not$diskUI.DiskAnalyze.IsEnabled) 'Scope change must invalidate owner analysis'
$diskUI.DiskMinimumMB.Text='invalid';$failed=$false;try{Get-MCDiskFinderOptions|Out-Null}catch{$failed=$true};Assert $failed 'Invalid size accepted'
$diskUI.DiskMinimumMB.Text='1';$diskUI.DiskExtensions.Text='.iso'
$finderFile=Join-Path $fixture 'personal-archive.iso';$finderStream=[IO.File]::Create($finderFile);try{$finderStream.SetLength(2MB)}finally{$finderStream.Dispose()};[IO.File]::SetLastWriteTimeUtc($finderFile,[DateTime]::UtcNow.AddDays(-90))
Start-MCDiskScan -FixtureRoots @($fixture)
$deadline=[DateTime]::UtcNow.AddSeconds(20)
while($diskRunning-and[DateTime]::UtcNow-lt$deadline){$frame=New-Object Windows.Threading.DispatcherFrame;$pump=New-Object Windows.Threading.DispatcherTimer;$pump.Interval=[TimeSpan]::FromMilliseconds(50);$pump.Add_Tick({$frame.Continue=$false;$pump.Stop()});$pump.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
Assert (-not$diskRunning-and-not$operation-and$diskResult.Rows.Count-eq1-and$diskResult.Rows[0].Name-eq'personal-archive.iso'-and$diskResult.Rows[0].Risk-eq'NeedsReview') 'Finder options did not reach native background worker'
Assert ($diskUI.DiskFiles.SelectedItems.Count-eq0-and(Test-Path -LiteralPath $finderFile)) 'Finder must not select or delete personal files'
$diskUI.DiskMinimumMB.Text='512';$diskUI.DiskMinimumAge.Text='0';$diskUI.DiskExtensions.Text='';$diskUI.DiskLarge.IsChecked=$false
$catalogFile=Join-Path $fixture 'Roaming\Code\CachedData\version\data.bin';New-Item -ItemType Directory -Path (Split-Path $catalogFile -Parent) -Force|Out-Null;[IO.File]::WriteAllText($catalogFile,'Readonly catalog GUI fixture')
$diskUI.DiskAppData.IsChecked=$true
$diskUI.DiskAppData.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
Assert ($null-eq$diskResult-and-not$diskUI.DiskLarge.IsChecked) 'AppData scope must reset previous preview and finder'
Start-MCDiskScan -FixtureRoots @($fixture)
Assert ($diskRunning-and-not$diskUI.DiskAppData.IsEnabled-and-not$ui.ClearMemory.IsEnabled) 'Catalog worker must hold shared lock'
$deadline=[DateTime]::UtcNow.AddSeconds(20)
while($diskRunning-and[DateTime]::UtcNow-lt$deadline){$frame=New-Object Windows.Threading.DispatcherFrame;$pump=New-Object Windows.Threading.DispatcherTimer;$pump.Interval=[TimeSpan]::FromMilliseconds(50);$pump.Add_Tick({$frame.Continue=$false;$pump.Stop()});$pump.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
Assert (-not$diskRunning-and-not$operation-and$diskResult.Rows.Count-eq1-and$diskResult.Rows[0].DataEvidence.DataClass-eq'CacheCandidate'-and$diskResult.Status-eq'CompletedReadonly') 'AppData mode did not reach native worker'
Assert ($diskUI.DiskClean.IsEnabled-and$diskUI.DiskFiles.SelectedItems.Count-eq0-and(Test-Path -LiteralPath $catalogFile)) 'Catalog cannot enable deletion or select data'
$historyInventory=[pscustomobject]@{Complete=$true;Apps=@([pscustomobject]@{Name='Microsoft Visual Studio Code (User)';Publisher='Microsoft Corporation';Source='CurrentUser/Registry64';InstallationId='CurrentUser/Registry64/FixtureCode';Version='1.2';Location='C:\Fixture\Code'})}
$historyDependencies=[pscustomobject]@{Complete=$true;CapturedUtc=[DateTime]::UtcNow;Entries=@()}
Start-MCDiskOwnerAnalysis -FixtureInventory $historyInventory -FixtureDependencies $historyDependencies -FixtureHistoryDirectory $fixture
$deadline=[DateTime]::UtcNow.AddSeconds(30)
while($diskRunning-and[DateTime]::UtcNow-lt$deadline){$frame=New-Object Windows.Threading.DispatcherFrame;$pump=New-Object Windows.Threading.DispatcherTimer;$pump.Interval=[TimeSpan]::FromMilliseconds(50);$pump.Add_Tick({$frame.Continue=$false;$pump.Stop()});$pump.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}

Assert (-not$diskRunning-and-not$operation-and$diskResult.ObservationHistory.Saved-and$diskResult.Rows[0].OwnerEvidence.State-eq'InstalledCatalogProtected') 'GUI worker must save observed metadata only to marked history fixture'
$historyInventory.Apps=@();$historyDependencies.CapturedUtc=[DateTime]::UtcNow
Start-MCDiskOwnerAnalysis -FixtureInventory $historyInventory -FixtureDependencies $historyDependencies -FixtureHistoryDirectory $fixture
$deadline=[DateTime]::UtcNow.AddSeconds(30)
while($diskRunning-and[DateTime]::UtcNow-lt$deadline){$frame=New-Object Windows.Threading.DispatcherFrame;$pump=New-Object Windows.Threading.DispatcherTimer;$pump.Interval=[TimeSpan]::FromMilliseconds(50);$pump.Add_Tick({$frame.Continue=$false;$pump.Stop()});$pump.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}

Assert (-not$diskRunning-and-not$operation-and$diskResult.Rows[0].OwnerEvidence.State-eq'PreviouslyObservedMissingProtected') 'GUI worker must surface previous install observation without calling it verified uninstall'
Assert ($diskUI.DiskClean.IsEnabled-and$diskResult.Rows[0].OwnerEvidence.Evidence.Contains('FixtureCode')-and(Test-Path -LiteralPath $catalogFile)) 'History cannot grant deletion; details must retain provenance'
$script:catalogPreview=$diskResult
$diskUI.DiskLarge.IsChecked=$true;$diskUI.DiskLarge.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
Assert (-not$diskUI.DiskAppData.IsChecked-and$null-eq$diskResult) 'Finder scope must clear AppData preview'
$diskUI.DiskLarge.IsChecked=$false;$diskUI.DiskAppData.IsChecked=$true

$script:diskResult=$catalogPreview;Update-MCDiskView;Set-MCDiskBusy $false;$diskUI.DiskState.Text='Đã quét xong · chỉ đọc';$diskUI.DiskStatus.Text=$catalogPreview.Message
$window.FindName('MainTabs').SelectedIndex=1
$content=$window.Content;$content.Measure([Windows.Size]::new(1072,684));$content.Arrange([Windows.Rect]::new(0,0,1072,684));$content.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1072,684,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$path=Join-Path $projectRoot 'artifacts\disk-ui-preview.png';$stream=[IO.File]::Create($path);try{$encoder.Save($stream)}finally{$stream.Dispose()}
[pscustomobject]@{Timestamp=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();Passed=$diskUiChecks;Failed=0;DiskControls=$diskUI.Count;Tabs=2;SharedLock=$true;SearchFilter=$true;FixtureBackgroundWorker=$true;ScannerDeletionEnabled=$false;ReviewedTempEntryAvailable=$diskUI.DiskClean.IsEnabled;Mode='Offscreen WPF/native readonly fixture worker; no user file scan/deletion or visible window';Image='artifacts/disk-ui-preview.png';WorkingSetMB=[Math]::Round([Diagnostics.Process]::GetCurrentProcess().WorkingSet64/1MB,1)}|ConvertTo-Json|Set-Content (Join-Path $projectRoot 'docs\verification\disk-ui-tests.json') -Encoding UTF8
$window.Close();Write-Output 'PASS Disk WPF fixture: controls/tabs/finder options/preview invalidation/search/shared lock/deletion disabled/offscreen render.'
