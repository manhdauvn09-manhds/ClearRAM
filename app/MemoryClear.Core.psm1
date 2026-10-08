Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
if (-not ('MemoryClear.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs') }
$script:Root = Split-Path $PSScriptRoot -Parent
$script:Data = Join-Path $script:Root '.data'

function Get-MCSettings {
    $file = Join-Path $script:Data 'settings.json'
    $defaults = [pscustomobject]@{ SchemaVersion=1; ProtectedPaths=@(); AllowClosePaths=@(); RefreshSeconds=3; AutoKill=$false }
    if (-not (Test-Path -LiteralPath $file)) { return $defaults }
    try {
        $settings = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.SchemaVersion -ne 1 -or $settings.RefreshSeconds -lt 2 -or $settings.RefreshSeconds -gt 30) { throw 'Invalid settings schema or refresh interval.' }
        foreach ($name in @('ProtectedPaths','AllowClosePaths')) {
            if ($null -eq $settings.$name) { $settings.$name = @() }
            foreach ($value in @($settings.$name)) { if ($value -isnot [string] -or -not [IO.Path]::IsPathRooted($value)) { throw 'Executable paths must be absolute.' } }
        }
        $settings.AutoKill = $false
        return $settings
    } catch { $defaults | Add-Member NoteProperty Warning ('Settings invalid; using safe defaults: ' + $_.Exception.Message); return $defaults }
}
function Save-MCSettings {
    param($Settings)
    New-Item -ItemType Directory -Path $script:Data -Force | Out-Null
    $Settings.AutoKill = $false
    $Settings.PSObject.Properties.Remove('Warning')
    $file = Join-Path $script:Data 'settings.json'
    $temp = $file + '.tmp'
    [IO.File]::WriteAllText($temp,($Settings | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temp -Destination $file -Force
}
function Write-MCEvent {
    param($Event)
    New-Item -ItemType Directory -Path $script:Data -Force | Out-Null
    $file = Join-Path $script:Data 'activity.json'
    $items = @()
    if (Test-Path -LiteralPath $file) { try { $parsedEvents = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json; $items = @($parsedEvents) } catch {} }
    $items = @($items | Select-Object -Last 199) + @($Event)
    $temp = $file + '.tmp'
    [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $items -Depth 5),[Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temp -Destination $file -Force
}
function Get-MCContext {
    $services = @{}; $servicesKnown = $false
    try { Get-CimInstance Win32_Service -OperationTimeoutSec 5 -ErrorAction Stop | ForEach-Object { if ($_.ProcessId -gt 0) { $services[[int]$_.ProcessId] = $true } }; $servicesKnown = $true } catch {}
    [pscustomobject]@{ UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId; SelfId=$PID; WindowsRoot=[IO.Path]::GetFullPath($env:windir).TrimEnd('\') + '\'; Services=$services; ServicesKnown=$servicesKnown }
}
function Test-MCPolicy {
    param($Identity, $Context, $Settings)
    $reason = ''
    if ($Settings.PSObject.Properties.Match('Warning').Count -gt 0) { $reason='Invalid settings; repair configuration before action' }
    elseif (-not $Identity.Known -or $Identity.StartTicks -le 0 -or -not $Identity.Path -or -not $Identity.Sid) { $reason='Unknown identity / insufficient permission' }
    elseif ($Identity.Pid -le 4 -or $Identity.Pid -eq $Context.SelfId) { $reason='System / MemoryClear host' }
    elseif ($Identity.Critical) { $reason='Critical process' }
    elseif ($Identity.Sid -ne $Context.UserSid -or $Identity.Session -ne $Context.SessionId) { $reason='Different user / session' }
    elseif (-not $Context.ServicesKnown) { $reason='Service inventory unavailable' }
    elseif ($Context.Services.ContainsKey([int]$Identity.Pid)) { $reason='Windows service' }
    elseif ($Identity.Path.StartsWith($Context.WindowsRoot,[StringComparison]::OrdinalIgnoreCase)) { $reason='Windows component' }
    elseif (@($Settings.ProtectedPaths | Where-Object { [string]::Equals($_,$Identity.Path,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { $reason='Protected by user' }
    [pscustomobject]@{ Allowed=($reason -eq ''); Reason=$(if($reason){$reason}else{'Manual action available'}); AllowClose=(@($Settings.AllowClosePaths | Where-Object { [string]::Equals($_,$Identity.Path,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and $reason -eq '') }
}
function Get-MCSnapshot {
    param($Previous)
    $settings = Get-MCSettings
    $system = [MemoryClear.Native]::ReadSystem()
    $context = $null
    if ($Previous -and (([Diagnostics.Stopwatch]::GetTimestamp() - $Previous.ContextTimestamp) / [Diagnostics.Stopwatch]::Frequency) -lt 15) { $context=$Previous.Context; $contextTime=$Previous.ContextTimestamp }
    else { $context=Get-MCContext; $contextTime=[Diagnostics.Stopwatch]::GetTimestamp() }
    $cpu = $null; $elapsed=0.0
    if ($Previous) {
        $total=($system.Kernel-$Previous.System.Kernel)+($system.User-$Previous.System.User)
        if ($total -gt 0) { $cpu=[Math]::Round([Math]::Max(0,[Math]::Min(100,100*(1-($system.Idle-$Previous.System.Idle)/$total))),1) }
        $elapsed=($system.Timestamp-$Previous.System.Timestamp)/[double][Diagnostics.Stopwatch]::Frequency
    }
    $samples=@{}; $metadata=@{}; $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach ($process in [Diagnostics.Process]::GetProcesses()) {
        try {
            $processId=$process.Id; $name=$process.ProcessName; $working=$null; $private=$null; $cpuTime=$null; $ticks=0
            try { $ticks=$process.StartTime.ToUniversalTime().Ticks; $working=$process.WorkingSet64; $private=$process.PrivateMemorySize64; $cpuTime=$process.TotalProcessorTime.TotalSeconds } catch {}
            $key="$processId/$ticks"; $identity=$null
            if ($Previous -and $Previous.Metadata.ContainsKey($key) -and $contextTime -eq $Previous.ContextTimestamp) { $identity=$Previous.Metadata[$key] }
            else { $identity=[MemoryClear.Native]::Inspect($processId) }
            $metadata[$key]=$identity; $policy=Test-MCPolicy $identity $context $settings
            $usage=$null
            if ($null -ne $cpuTime) { $samples[$key]=$cpuTime; if ($Previous -and $elapsed -gt 0 -and $elapsed -lt 30 -and $Previous.Samples.ContainsKey($key)) { $usage=[Math]::Round([Math]::Max(0,[Math]::Min(100,100*($cpuTime-$Previous.Samples[$key])/$elapsed/[Environment]::ProcessorCount)),1) } }
            $rows.Add([MemoryClear.ProcessRow]@{Pid=$processId;Name=$name;StartTicks=$identity.StartTicks;Path=$identity.Path;RamMB=$(if($null-ne$working){[Math]::Round($working/1MB,1)}else{$null});PrivateMB=$(if($null-ne$private){[Math]::Round($private/1MB,1)}else{$null});Cpu=$usage;Policy=$policy.Reason;Allowed=$policy.Allowed;AllowClose=$policy.AllowClose;Identity=$identity})
        } catch {} finally { $process.Dispose() }
    }
    [pscustomobject]@{System=$system;Cpu=$cpu;Rows=@($rows.ToArray() | Sort-Object RamMB -Descending);Samples=$samples;Metadata=$metadata;Context=$context;ContextTimestamp=$contextTime;Settings=$settings;Timestamp=[DateTime]::UtcNow.ToString('o')}
}
function Set-MCAllowClosePermission {
    param([int]$ProcessId,[long]$StartTicks,[bool]$Enabled)
    $identity=[MemoryClear.Native]::Inspect($ProcessId)
    if(-not$identity.Known -or $identity.StartTicks-ne$StartTicks){throw 'Process identity changed or could not be verified.'}
    $settings=Get-MCSettings
    $policy=Test-MCPolicy $identity (Get-MCContext) $settings
    if($Enabled-and-not$policy.Allowed){throw ('Process is protected: '+$policy.Reason)}
    $settings.AllowClosePaths=@($settings.AllowClosePaths|Where-Object{-not[string]::Equals($_,$identity.Path,[StringComparison]::OrdinalIgnoreCase)})
    if($Enabled){$settings.AllowClosePaths=@($settings.AllowClosePaths)+@($identity.Path)}
    Save-MCSettings $settings
    [pscustomobject]@{Path=$identity.Path;Enabled=$Enabled}
}
function Invoke-MCAction {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][long]$StartTicks,[ValidateSet('Close','Kill')][string]$Action='Close')
    $guard=$null
    $result=[ordered]@{Timestamp=[DateTime]::UtcNow.ToString('o');Pid=$ProcessId;StartTicks=$StartTicks;Action=$Action;Status='Denied';Message='';AvailableBefore=0;AvailableAfter=0}
    try {
        $guard=[MemoryClear.Native]::Acquire($ProcessId,$StartTicks,($Action-eq'Kill'))
        $policy=Test-MCPolicy $guard.Identity (Get-MCContext) (Get-MCSettings)
        if(-not $policy.Allowed){throw $policy.Reason}
        if(-not $PSCmdlet.ShouldProcess(($guard.Identity.Path+' [PID '+$ProcessId+']'),$Action)){ $result.Status='Cancelled';$result.Message='No action performed';return [pscustomobject]$result }
        $policy=Test-MCPolicy $guard.Identity (Get-MCContext) (Get-MCSettings)
        if(-not $policy.Allowed -or $guard.HasExited){throw 'Target exited or protection changed while waiting for confirmation.'}
        $result.AvailableBefore=[MemoryClear.Native]::ReadSystem().AvailableBytes
        if($Action-eq'Close') { if($guard.CloseWindow()){ $result.Status='Requested';$result.Message='Close requested; app may show a save dialog. No automatic force kill.' }else{ $result.Status='NoWindow';$result.Message='No closeable main window; no force kill performed.' } }
        else { $guard.Kill();if($guard.Wait(1000)){ $result.Status='Exited';$result.Message='Process exit verified' }else{ $result.Status='Pending';$result.Message='Termination requested; exit not verified yet' } }
        $result.AvailableAfter=[MemoryClear.Native]::ReadSystem().AvailableBytes
    } catch { $result.Message=$_.Exception.Message }
    finally {if($guard){$guard.Dispose()}}
    try {Write-MCEvent ([pscustomobject]$result)}catch{$result.Message+=' (Activity log write failed: '+$_.Exception.Message+')'}
    [pscustomobject]$result
}
Export-ModuleMember -Function Get-MCSettings,Save-MCSettings,Write-MCEvent,Get-MCContext,Test-MCPolicy,Get-MCSnapshot,Set-MCAllowClosePermission,Invoke-MCAction
