<#
.SYNOPSIS
  harness-handoff-render -- thin wrapper over .harness/scripts/lib/harness_handoff_gen.py
  (C7 twin: bash/harness-handoff-render.sh).
.DESCRIPTION
  render [ROOT] [-Write] [-NoCi] [-NoDoctor] -Fleet <base>   sinh khoi NOW tu su that vao Handoff.md
  check  [ROOT] [-Json]                                      muc OPEN nao trong handoff.yaml da thoa until:
.EXAMPLE
  powershell -File E:\Develop\HarnessAI-ToolKIT\.harness\scripts\powershell\harness-handoff-render.ps1 render -Write -Fleet E:\Develop
#>
param(
    [string]$Command = "render",
    [string]$Root = "",
    [switch]$Write,
    [switch]$NoCi,
    [switch]$NoDoctor,
    [switch]$Json,
    [string]$Fleet = ""
)
$Lib = Join-Path $PSScriptRoot "..\lib\harness_handoff_gen.py"
if (-not (Test-Path -LiteralPath $Lib)) { Write-Host "[handoff] missing $Lib"; exit 1 }
$py = $null
foreach ($n in @("python", "python3", "py")) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c) { $py = $c.Source; break }
}
if (-not $py) { Write-Host "[handoff] no python on PATH"; exit 1 }
if (-not $Root) { $Root = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) }
$a = @($Command, $Root)
if ($Write) { $a += "--write" }
if ($NoCi) { $a += "--no-ci" }
if ($NoDoctor) { $a += "--no-doctor" }
if ($Json) { $a += "--json" }
if ($Fleet) { $a += @("--fleet", $Fleet) }
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try { & $py $Lib @a; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
if ($null -eq $code) { $code = 0 }
exit $code
