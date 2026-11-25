<#
.SYNOPSIS
  harnessd -- thin wrapper over .harness/scripts/lib/harnessd.py (C7 twin: bash/harnessd.sh).
.DESCRIPTION
  ensure | start | stop | status | bench [n] | serve   (see the Python module for the rest)
  Wired at SessionStart and UserPromptSubmit as `ensure`: starts the resident daemon that
  serves the PreToolUse / PostToolUse http hooks when it is not running. Prints nothing when
  the daemon is already healthy (UserPromptSubmit stdout becomes prompt context). Never fails
  the hook: any problem is one line in .harness/telemetry/hook-errors.log.
#>
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

$Lib = Join-Path $PSScriptRoot "..\lib\harnessd.py"
if (-not (Test-Path -LiteralPath $Lib)) { exit 0 }
$py = $null
foreach ($n in @("python", "python3", "py")) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c) { $py = $c.Source; break }
}
if (-not $py) { exit 0 }
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $py $Lib @Rest
    $code = $LASTEXITCODE
} finally { $ErrorActionPreference = $prev }
if ($null -eq $code) { $code = 0 }
exit $code
