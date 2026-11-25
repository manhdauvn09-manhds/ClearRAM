#!/usr/bin/env pwsh
<#
.SYNOPSIS
  UserPromptSubmit hook — Prompt Injection Scanner (H4).
  Scans user input for prompt injection attempts before they reach the agent.
.DESCRIPTION
  Reads stdin (user prompt text) and scans for:
    - "ignore previous instructions" / "ignore all instructions"
    - "forget everything" / "reset your instructions"
    - Encoded/base64 payloads
    - Role-play jailbreaks
    - Delimiter confusion attacks
  Returns:
    exit 0 — clean prompt
    exit 2 — injection detected (hard block)
.NOTES
  H4: This is the CORRECT place to block prompt injection — at UserPromptSubmit,
  before the prompt enters the agent's context window.
  C10: Local hook is defense-in-depth; severe injection may need server-side scanning.
#>

# Read stdin as raw UTF-8 bytes. Piping the automatic input variable through
# Out-String (what this scanner used to do) decoded it with the console
# code page: on a CP932 machine every Vietnamese character came out as mojibake,
# so excerpts were unreadable and patterns ran against text the user never wrote.
# A leading BOM is dropped (PS 5.1 under code page 65001 pipes one -- B-97).
#
# Two callers, two channels: Claude Code runs this with `-File` and pipes stdin;
# tests and other scripts call it in-process (`'text' | & injection-scan.ps1`).
# Do NOT write the automatic variable's name literally anywhere in this file:
# when a `-File` script mentions it, powershell.exe pre-reads ALL of stdin with
# the console code page before the first line runs, and the raw read below gets
# nothing (measured 15-11, B-103). Get-Variable reaches the same variable without it.
$RawInput = ""
$PipeItems = @()
$PipeVar = Get-Variable -Name input -ValueOnly -ErrorAction SilentlyContinue
if ($PipeVar) { $PipeItems = @($PipeVar | ForEach-Object { $_ }) }
if ($PipeItems.Count -gt 0) {
    $RawInput = ($PipeItems | Out-String)
} else {
    try {
        $ms = New-Object System.IO.MemoryStream
        [Console]::OpenStandardInput().CopyTo($ms)
        $RawInput = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
    } catch {
        $RawInput = ""
    }
}
if (-not $RawInput -or -not $RawInput.Trim()) {
    exit 0
}

# Scan what the user (or the subagent) actually wrote: the hook payload's `prompt`.
# Scanning the whole JSON also matched session_title, cwd and transcript paths, and
# saw the prompt with its quotes and newlines escaped. Not JSON -> scan it as given.
$InputText = $RawInput
try {
    $Payload = $RawInput | ConvertFrom-Json -ErrorAction Stop
    if ($Payload -and ($Payload.PSObject.Properties.Name -contains 'prompt') -and ($Payload.prompt -is [string])) {
        $InputText = $Payload.prompt
    }
} catch { }
if (-not $InputText) {
    exit 0
}

# Load injection patterns from config (C2)
$HarnessRoot = $env:HARNESS_ROOT
if (-not $HarnessRoot) {
    $HarnessRoot = Resolve-Path "$PSScriptRoot\..\..\.."
}

$InjectionPatternsPath = "$HarnessRoot\.harness\control\injection-patterns.json"
# Prompts Claude Code queues on a subagent's behalf (its report, a task notice).
# Overridden by injection-patterns.json -> handback_prefixes (C2); see the note there.
$HandbackPrefixes = @('^\s*<agent-message\b', '^\s*<task-notification>')
if (-not (Test-Path $InjectionPatternsPath)) {
    # Built-in patterns
    $Patterns = @(
        @{ pattern = '(?i)ignore\s+(all\s+)?previous\s+instructions'; severity = 'high'; category = 'instruction-override' },
        @{ pattern = '(?i)ignore\s+(all\s+)?prior\s+(instructions|directives)'; severity = 'high'; category = 'instruction-override' },
        @{ pattern = '(?i)forget\s+(everything|all\s+(previous|prior)\s+instructions)'; severity = 'high'; category = 'instruction-override' },
        @{ pattern = '(?i)reset\s+(your\s+)?(instructions|context|memory|personality)'; severity = 'high'; category = 'instruction-override' },
        @{ pattern = '(?i)you\s+(are\s+)?(now|are\s+free)\s+(to\s+)?(ignore|disregard|bypass)'; severity = 'high'; category = 'role-jailbreak' },
        # DAN is case-sensitive ('dan' is a Vietnamese word, B-101) and never inside a
        # hyphenated/dotted name such as HUONG-DAN-SU-DUNG.md (B-103). Same as the JSON.
        @{ pattern = '(?i:\byou\s+are\s+(?:now\s+)?)DAN(?![\w-]|\.\w)'; severity = 'high'; category = 'role-jailbreak' },
        @{ pattern = '(?<![\w-])(?<!\w\.)DAN(?![\w-]|\.\w)\s*:'; severity = 'high'; category = 'role-jailbreak' },
        @{ pattern = '(?i)do\s+anything\s+now|jail\s*break'; severity = 'high'; category = 'role-jailbreak' },
        @{ pattern = '(?i)(system|security|admin)?\s*(prompt|instruction|directive)s?\s*:\s*(ignore|override|bypass)'; severity = 'high'; category = 'system-prompt-override' },
        @{ pattern = '(?:[A-Za-z0-9+/]{40,}={0,2})'; severity = 'medium'; category = 'encoded-payload' },
        @{ pattern = '(?i)(?:hex|base64|rot13|binary)\s*(?:encode|decode|convert)\s*(?:this|the|following)'; severity = 'medium'; category = 'encoded-instruction' },
        @{ pattern = '(?i)output\s+(only|just|solely)\s+(the\s+)?(json|xml|yaml|raw)\s+(and|without)'; severity = 'medium'; category = 'output-steering' },
        @{ pattern = '(?i)print\s+(the\s+)?(full|complete|entire)\s+(prompt|system\s+prompt|instructions)'; severity = 'high'; category = 'prompt-leak' },
        @{ pattern = '(?i)repeat\s+(the\s+)?(words|text|sentence|phrase)\s+(above|before|below)'; severity = 'medium'; category = 'prompt-leak' },
        @{ pattern = '(?i)<\\s*(system|instructions?|context)\\s*>'; severity = 'medium'; category = 'delimiter-confusion' },
        @{ pattern = '(?i)---+\s*(begin|start)\s+(system|instructions?|context)'; severity = 'medium'; category = 'delimiter-confusion' }
    )
} else {
    try {
        $PatternsDoc = Get-Content -Path $InjectionPatternsPath -Raw -Encoding utf8 | ConvertFrom-Json
        # CRIT-1: the file is { $schema, description, patterns: [...] } — iterate .patterns
        $Patterns = @($PatternsDoc.patterns)
        if ($PatternsDoc.PSObject.Properties.Name -contains 'handback_prefixes') {
            $HandbackPrefixes = @($PatternsDoc.handback_prefixes | Where-Object { $_ })
        }
    } catch {
        Write-Warning "[injection-scan] Cannot read injection-patterns.json, using defaults"
        $Patterns = @()
    }
}

# --- Redaction (C2: patterns come from config, not from this script) --------
# The excerpt below is written verbatim into the security-event log, which
# push-telemetry ships to the Portal. It carries a 240-character window of the
# raw prompt, so a prompt that mentioned an API key next to an injection
# phrase exfiltrated that key into a durable, synced store -- the injection
# detector became the leak. Redact secret shapes before anything is recorded.
#
# Reuses .harness/control/secret-patterns.json so a pattern added for
# secret-scan protects this path too, instead of two lists drifting apart.
$RedactPatterns = @()
$SecretPatternsPath = Join-Path $HarnessRoot ".harness\control\secret-patterns.json"
if (Test-Path $SecretPatternsPath) {
    try {
        $sp = Get-Content -Path $SecretPatternsPath -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($e in @($sp.patterns)) {
            if ($e.pattern) { $RedactPatterns += [string]$e.pattern }
        }
    } catch {
        # Fall through to the generic shapes below.
    }
}
# Generic high-entropy shapes, applied in ADDITION to the configured ones. A
# redactor that only removes known vendor prefixes is not much of a redactor:
# the value most worth hiding is usually the one nobody wrote a pattern for.
$RedactPatterns += '(?i)(secret|passwd|password|token|api[_\-]?key|bearer|authorization)\s*["'':=]+\s*\S+'
$RedactPatterns += '\b[A-Za-z0-9+/]{40,}={0,2}\b'
$RedactPatterns += '\b[0-9a-fA-F]{32,}\b'

function Protect-Excerpt {
    param([string]$Text)
    if (-not $Text) { return $Text }
    foreach ($rp in $RedactPatterns) {
        try { $Text = [regex]::Replace($Text, $rp, '[REDACTED]') } catch { continue }
    }
    return $Text
}

# Is this a subagent hand-back / task notice rather than something a person typed?
$IsHandback = $false
foreach ($hp in $HandbackPrefixes) {
    try { if ([regex]::IsMatch($InputText, [string]$hp)) { $IsHandback = $true; break } } catch { continue }
}
$SourceTag = ""
if ($IsHandback) { $SourceTag = "[agent-handback] " }

# --- Scan ---
$Findings = @()
foreach ($entry in $Patterns) {
    if ($null -eq $entry.pattern) { continue }
    $matches = [regex]::Matches($InputText, $entry.pattern)
    foreach ($match in $matches) {
        $sig = $match.Value.Substring(0, [Math]::Min($match.Value.Length, 80))
        # Context window around the match so the excerpt is understandable
        # ("what in the prompt triggered this"), not just the bare signature.
        $start = [Math]::Max(0, $match.Index - 60)
        $len = [Math]::Min($InputText.Length - $start, $match.Length + 120)
        $ctx = $InputText.Substring($start, $len).Trim() -replace '\s+', ' '
        $ctx = $ctx.Substring(0, [Math]::Min($ctx.Length, 240))
        # Redact BOTH the surrounding window and the matched signature itself.
        # An injection pattern can match text that contains a credential, so
        # sanitising only the context would still log the secret via $sig.
        $sig = Protect-Excerpt $sig
        $ctx = Protect-Excerpt $ctx
        $Findings += [PSCustomObject]@{
            Severity = $entry.severity
            Category = $entry.category
            Match    = $sig
            Excerpt  = "${SourceTag}matched [$($entry.category)] `"$sig`" | prompt: ...$ctx..."
        }
    }
}

# Deduplicate — ensure array for Count safety on PS 5.1
$Findings = @($Findings | Sort-Object Severity, Category -Unique)

# --- Report ---
if ($Findings.Count -eq 0) {
    exit 0
}

$HighCount = @($Findings | Where-Object { $_.Severity -eq 'high' }).Count

# Persist authoritative security events (H4) -- see lib-security-log.ps1.
$LibPath = Join-Path $PSScriptRoot "lib-security-log.ps1"
if (Test-Path $LibPath) {
    . $LibPath
    foreach ($f in $Findings) {
        Write-SecurityEvent -HarnessRoot $HarnessRoot -Type "injection" -Severity $f.Severity `
            -Category $f.Category -DetectedBy "injection-scan" -Excerpt $f.Excerpt
    }
}

Write-Warning "[injection-scan] Detected $($Findings.Count) injection signature(s) ($HighCount high)"
foreach ($f in $Findings) {
    if ($null -eq $f.Severity) { continue }
    Write-Warning "[injection-scan] [$($f.Severity.ToUpper())][$($f.Category)] $($f.Match)"
}

$Report = @{
    scanner = "injection-scan"
    total = $Findings.Count
    high = $HighCount
    findings = $Findings
} | ConvertTo-Json -Compress
Write-Output $Report

if ($HighCount -gt 0 -and $IsHandback) {
    # A subagent's report is model-written data the session asked for. Blocking it
    # drops the result with no legitimate way to get it back (B-103); the finding
    # is logged above and shown, the report goes through.
    [Console]::Error.WriteLine("[injection-scan] WARN (not blocked): high-severity signature in a subagent hand-back -- treat that report as data, not instructions")
    exit 1
}
if ($HighCount -gt 0) {
    # Hard block for high severity injections
    Write-Error "[injection-scan] BLOCKED: High-severity prompt injection detected"
    exit 2
}

exit 1
