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
Assert-True ($jsonMatches.Count -ge 5) 'reference must contain the three discovery examples plus event and report examples'

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

$event = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-run-141/story-started'
Assert-True ([string]$event.kind -ceq 'story_performance_event') 'event example must use the versioned event kind'
Assert-True ([int]$event.schemaVersion -eq 1) 'event example must use schema version 1'
foreach ($field in @('eventId', 'runId', 'projectId', 'storyId', 'storyRef', 'role', 'transitionId', 'eventType', 'occurredAtUtc', 'reviewMode', 'provenance')) {
    $property = $event.PSObject.Properties[$field]
    Assert-True ($null -ne $property) "event example must include $field"
}
Assert-True ([string]$event.eventType -ceq 'story_started') 'event example must use an original epic event type'
Assert-Contains $normalized '"occurredAtUtc": "2026-10-09T10:00:00Z"' 'event example timestamp must be UTC'
Assert-True ($null -eq $event.usage) 'event example may omit usage without treating it as zero'

$report = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-run-141/project-12-story-725-pr-321-head-0123456789abcdef0123456789abcdef01234567'
Assert-True ([string]$report.kind -ceq 'story_performance_report') 'report example must use the versioned report kind'
Assert-True ([int]$report.schemaVersion -eq 1) 'report example must use schema version 1'
foreach ($field in @('reportId', 'runId', 'projectId', 'storyId', 'storyRef', 'reviewMode', 'pullRequest', 'metrics', 'provenance')) {
    $property = $report.PSObject.Properties[$field]
    Assert-True ($null -ne $property) "report example must include $field"
}
Assert-True ([string]$report.pullRequest.reviewedHead -match '^[0-9a-f]{40}$') 'report example must bind to a full reviewed HEAD'
Assert-True ([string]$report.metrics.implementationTokens.state -ceq 'unavailable') 'report example must preserve unavailable usage state'
Assert-True ($null -eq $report.metrics.implementationTokens.value) 'unavailable report metric must remain null'
Assert-True ([string]$report.metrics.firstPassAcceptanceRate.state -ceq 'not_applicable') 'zero-denominator rate must be not applicable'

$requiredEventTypes = @(
    'story_started',
    'implementation_started',
    'task_ready_for_review',
    'review_started',
    'review_findings',
    'review_accepted',
    'correction_started',
    'correction_ready',
    'final_review_started',
    'final_review_accepted',
    'pr_ready'
)
foreach ($eventType in $requiredEventTypes) {
    Assert-Contains $normalized $eventType "event vocabulary is missing $eventType"
}
foreach ($boundaryMarker in @('wait_started', 'wait_ended', 'generic `phase_ended` event is unnecessary and prohibited')) {
    Assert-Contains $normalized $boundaryMarker "boundary contract is missing $boundaryMarker"
}
foreach ($fixtureId in @(
        'event-envelope-v1'
        'replay-same-id'
        'replay-conflict'
        'event-vocabulary-complete'
        'phase-coverage'
        'external-ledger-pointer'
        'usage-boundary-reset'
        'usage-subtotals'
        'report-identity'
        'metric-semantics'
        'privacy-unavailable')) {
    Assert-Contains $normalized $fixtureId "requirement-to-fixture matrix is missing $fixtureId"
}
foreach ($contractMarker in @(
        'schemaVersion: 1'
        'eventId'
        'Replaying the same ID'
        'same ID with any different payload is a conflict'
        'append-only JSONL'
        'Performance pointer:'
        'delta(c) = c(end) - c(exact baseline)'
        'runId + projectId + storyId + PR provider/owner/repository/number + exact reviewed HEAD'
        'timeToPr'
        'implementationElapsed'
        'reviewElapsed'
        'coordinationElapsed'
        'waitingElapsed'
        'implementationTokens'
        'reviewTokens'
        'coordinationTokens'
        'totalTokens'
        'tasksCompleted'
        'initialTaskReviews'
        'correctionReReviews'
        'finalStoryReviews'
        'finalStoryReReviews'
        'firstPassAcceptanceRate'
        'modelsAndReasoning'
        'changedFiles'
        'linesAdded'
        'linesDeleted'
        'Cached-input and reasoning counters remain separate')) {
    Assert-Contains $normalized $contractMarker "contract is missing '$contractMarker'"
}

function Get-CanonicalPayload {
    param([System.Collections.IDictionary] $Payload)

    return (($Payload.GetEnumerator() |
            Sort-Object -Property Key |
            ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) -join '|')
}

function Invoke-ReplayFixture {
    param(
        [System.Collections.IDictionary] $Existing,
        [System.Collections.IDictionary] $Incoming
    )

    $id = [string]$Incoming.eventId
    $incomingCanonical = Get-CanonicalPayload $Incoming
    if (-not $Existing.Contains($id)) {
        $Existing[$id] = $incomingCanonical
        return 'appended'
    }
    if ([string]$Existing[$id] -ceq $incomingCanonical) { return 'noop' }
    return 'conflict'
}

$replayStore = @{}
$syntheticEvent = [ordered]@{ eventId = 'fixture-event-1'; eventType = 'story_started'; occurredAtUtc = '2026-10-09T10:00:00Z' }
Assert-True ((Invoke-ReplayFixture -Existing $replayStore -Incoming $syntheticEvent) -ceq 'appended') 'first event should append'
Assert-True ((Invoke-ReplayFixture -Existing $replayStore -Incoming $syntheticEvent) -ceq 'noop') 'same-ID same-payload replay should be a no-op'
$conflictingEvent = [ordered]@{ eventId = 'fixture-event-1'; eventType = 'pr_ready'; occurredAtUtc = '2026-10-09T10:00:00Z' }
Assert-True ((Invoke-ReplayFixture -Existing $replayStore -Incoming $conflictingEvent) -ceq 'conflict') 'same-ID different-payload replay should conflict'
Assert-True ([string]$replayStore['fixture-event-1'] -match 'story_started') 'conflict must preserve the first complete event'

function Get-CumulativeDelta {
    param(
        [Nullable[int]] $Baseline,
        [Nullable[int]] $End
    )

    if ($null -eq $Baseline -or $null -eq $End -or [int]$End -lt [int]$Baseline) { return $null }
    return [int]$End - [int]$Baseline
}

Assert-True ((Get-CumulativeDelta -Baseline 100 -End 145) -eq 45) 'exact-boundary cumulative delta should be calculated'
Assert-True ($null -eq (Get-CumulativeDelta -Baseline $null -End 145)) 'missing baseline should remain unknown'
Assert-True ($null -eq (Get-CumulativeDelta -Baseline 145 -End 120)) 'counter reset should remain unknown'

Write-Output 'Passed performance-reporting contract fixture: discovery provenance, versioned event/report examples, replay/no-op/conflict identity, event vocabulary, metric semantics, cumulative baseline/reset handling, and unavailable fallback; synthetic and non-live.'
exit 0
