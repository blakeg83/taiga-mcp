# SYNTHETIC PERFORMANCE-CAPABILITY CHECK.
# This fixture validates the task #146 capability matrix and sanitized
# examples. It does not contact Taiga, Codex, GitHub, a browser, or a live
# provider, and it does not read prompt bodies, transcripts, or session logs.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Performance-reporting assertion failed: $Message"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Needle,
        [Parameter(Mandatory)] [string] $Message
    )

    Assert-True $Text.Contains($Needle, [StringComparison]::Ordinal) $Message
}

function Get-RequiredExample {
    param(
        [Parameter(Mandatory)] [object[]] $Examples,
        [Parameter(Mandatory)] [string] $ExampleId
    )

    $matches = @($Examples | Where-Object { [string]$_.exampleId -ceq $ExampleId })
    Assert-True ($matches.Count -eq 1) "example '$ExampleId' must appear exactly once"
    return $matches[0]
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$referencePath = Join-Path $skillRoot 'references/performance-reporting.md'
Assert-True (Test-Path -LiteralPath $referencePath -PathType Leaf) 'capability reference is present'

$reference = Get-Content -LiteralPath $referencePath -Raw
$normalized = [regex]::Replace($reference, '\s+', ' ')

foreach ($marker in @(
        'Attributable telemetry capability matrix'
        'Discovery date: 2026-10-09'
        'UI/browser evidence: not applicable'
        'Exact read-only probes and results'
        'mcp__codex_app__create_thread'
        'mcp__codex_app__get_usage_limits'
        'mcp__codex_app__list_threads({ limit: 50 })'
        'get_goal({})'
        'measured`, `partial`, `unavailable`, or `unverified`'
        'prompt bodies'
        'transcripts'
        'counters: null'
        'never be reported as observed usage'
        'Executable fallback'
        'validate-performance-reporting.ps1'
        'Task #147'
        'Task #148')) {
    Assert-Contains $normalized $marker "reference is missing '$marker'"
}

Assert-Contains $normalized 'Do not use them as token totals or cost.' 'reference must prohibit cost attribution from account limits'
Assert-Contains $normalized 'Account-level limits' 'account-level limits must be distinguished from story attribution'
Assert-True ($normalized.Contains('unknown, not zero')) 'unknown values must not be converted to zero'

$jsonMatches = [regex]::Matches($reference, '(?ms)^```json\s*\r?\n(?<json>.*?)\r?\n```')
Assert-True ($jsonMatches.Count -eq 3) 'reference must contain three sanitized JSON examples'

$examples = @()
foreach ($match in $jsonMatches) {
    $json = $match.Groups['json'].Value
    try {
        $examples += ($json | ConvertFrom-Json)
    }
    catch {
        throw "sanitized JSON example is invalid: $($_.Exception.Message)"
    }
}

$exampleIds = @($examples | ForEach-Object { [string]$_.exampleId })
Assert-True ($exampleIds.Count -eq @($exampleIds | Select-Object -Unique).Count) 'sanitized example IDs must be unique'

$observed = Get-RequiredExample -Examples $examples -ExampleId 'observed-coordinator-thread-metadata'
Assert-True ([string]$observed.evidenceClass -ceq 'observed_host_metadata') 'host example must be labeled observed host metadata'
Assert-True ([string]$observed.source -ceq 'mcp__codex_app__list_threads') 'host example must name its source probe'
Assert-True ([string]$observed.role -ceq 'coordinator') 'host example must preserve its role'
Assert-True ([string]$observed.status -ceq 'idle') 'host example must preserve the observed status'
Assert-True ($null -eq $observed.usage) 'host identity example must not invent usage'

$unavailable = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-unavailable-worker-usage'
Assert-True ([string]$unavailable.evidenceClass -ceq 'synthetic_fixture') 'unavailable example must be synthetic'
Assert-True ([string]$unavailable.state -ceq 'unavailable') 'unavailable example must use unavailable state'
Assert-True ($null -eq $unavailable.streamId) 'unavailable example must not invent a stream ID'
Assert-True ($null -eq $unavailable.counters) 'unavailable example must keep counters null'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$unavailable.reason)) 'unavailable example must explain its limitation'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$unavailable.fallback)) 'unavailable example must name an executable-safe fallback'

$partial = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-partial-worker-usage'
Assert-True ([string]$partial.evidenceClass -ceq 'synthetic_fixture') 'partial example must be synthetic'
Assert-True ([string]$partial.state -ceq 'partial') 'partial example must use partial state'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$partial.streamId)) 'partial example must identify its stream'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$partial.baseline)) 'partial example must identify its baseline'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$partial.coverage)) 'partial example must identify coverage'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$partial.resetHandling)) 'partial example must identify reset handling'

foreach ($counterName in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')) {
    $counterProperty = $partial.counters.PSObject.Properties[$counterName]
    Assert-True ($null -ne $counterProperty) "partial example must name $counterName"
    Assert-True ([int]$counterProperty.Value -ge 0) "$counterName must be nonnegative in the synthetic example"
}

Write-Output 'Passed performance-reporting capability fixture: source/provenance separation, observed host metadata, unavailable fallback, partial stream coverage, and reset semantics; synthetic and non-live.'
exit 0
