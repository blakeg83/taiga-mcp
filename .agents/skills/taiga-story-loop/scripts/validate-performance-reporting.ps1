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

function Assert-Throws {
    param(
        [Parameter(Mandatory)] [scriptblock] $Action,
        [Parameter(Mandatory)] [string] $Message
    )

    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
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
        'Task #148'
        'Review-attempt counting and bounded-overhead acceptance cases'
        'reviewKind'
        'reviewAttemptOrdinal'
        'duplicate no-op'
        'marked stale'
        'story_end_only deliberately has zero per-task reviews'
        'source-backed usage boundary'
        'addedAgents'
        'measurement-only messages'
        'same-SHA retry'
        'negativeControls'
        'budget-exceeded'
        'changed-outcome'
        'changed-workload'
        'missing-comparable-evidence'
        'synthetic-overhead-baseline-candidate')) {
    Assert-Contains $normalized $marker "reference is missing '$marker'"
}

Assert-Contains $normalized 'Do not use them as token totals or cost.' 'reference must prohibit cost attribution from account limits'
Assert-Contains $normalized 'Account-level limits' 'account-level limits must be distinguished from story attribution'
Assert-True ($normalized.Contains('unknown, not zero')) 'unknown values must not be converted to zero'

$jsonMatches = [regex]::Matches($reference, '(?ms)^```json\s*\r?\n(?<json>.*?)\r?\n```')
Assert-True ($jsonMatches.Count -ge 14) 'reference must contain discovery, phase, token, event, report, review, usage, and overhead examples'

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
foreach ($field in @('eventId', 'runId', 'projectId', 'storyId', 'storyRef', 'scope', 'phaseId', 'role', 'transitionId', 'reviewKind', 'reviewAttemptOrdinal', 'eventType', 'occurredAtUtc', 'reviewMode', 'provenance')) {
    $property = $event.PSObject.Properties[$field]
    Assert-True ($null -ne $property) "event example must include $field"
}
Assert-True ([string]$event.eventType -ceq 'story_started') 'event example must use an original epic event type'
Assert-True ([string]$event.scope -ceq 'story') 'story_started example must use story scope'
Assert-True ($null -eq $event.phaseId) 'story_started example must leave phase identity null'
Assert-True ($null -eq $event.reviewKind -and $null -eq $event.reviewAttemptOrdinal) 'story_started example must leave review identity fields null'
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

$nullBeforeCommit = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-phase-null-before-commit'
Assert-True (@($nullBeforeCommit.events).Count -eq 2) 'null-before-commit example must contain a start and ready event'
Assert-True ([string]$nullBeforeCommit.events[0].eventType -ceq 'implementation_started') 'null-before-commit example must start implementation'
Assert-True ([string]$nullBeforeCommit.events[1].eventType -ceq 'task_ready_for_review') 'null-before-commit example must end at task-ready'
Assert-True ([string]$nullBeforeCommit.events[0].phaseId -ceq [string]$nullBeforeCommit.events[1].phaseId) 'implementation start and ready must share phase identity'
Assert-True ($null -eq $nullBeforeCommit.events[0].revision) 'implementation start may be null before commit'
Assert-True ([string]$nullBeforeCommit.events[1].revision -match '^[0-9a-f]{40}$') 'task-ready must carry a full resulting revision'

$correction = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-correction-new-revision'
Assert-True (@($correction.events).Count -eq 2) 'correction example must contain a start and ready event'
Assert-True ([string]$correction.events[0].correctionId -ceq [string]$correction.events[1].correctionId) 'correction pair must share correction identity'
Assert-True ([string]$correction.events[0].phaseId -ceq [string]$correction.events[1].phaseId) 'correction pair must share phase identity'
Assert-True ($null -eq $correction.events[0].revision) 'correction start may be null before the corrected commit'
Assert-True ([string]$correction.events[1].revision -ceq '2222222222222222222222222222222222222222') 'correction ready must carry the new revision'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$correction.events[0].supersedesReviewAttemptId)) 'correction must link the finding attempt it supersedes'

$finalFindings = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-final-review-findings'
Assert-True (@($finalFindings.events).Count -eq 2) 'final findings example must contain start and findings'
Assert-True ([string]$finalFindings.events[0].scope -ceq 'final_story' -and [string]$finalFindings.events[1].scope -ceq 'final_story') 'final findings must use final-story scope'
Assert-True ([string]$finalFindings.events[0].phaseId -ceq [string]$finalFindings.events[1].phaseId) 'final review findings must share phase identity'
Assert-True ([string]$finalFindings.events[0].reviewAttemptId -ceq [string]$finalFindings.events[1].reviewAttemptId) 'final review findings must share attempt identity'
Assert-True ([string]$finalFindings.events[0].reviewKind -ceq 'final_story' -and [int]$finalFindings.events[0].reviewAttemptOrdinal -eq 1) 'final review example must identify its first final attempt'
Assert-True ([string]$finalFindings.events[1].eventType -ceq 'review_findings') 'final review findings must close through review_findings'

$perTaskReviews = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-review-counts-per-task'
Assert-True ([string]$perTaskReviews.reviewMode -ceq 'per_task') 'per-task review fixture must preserve per_task mode'
Assert-True (@($perTaskReviews.events | Where-Object { [string]$_.eventType -ceq 'review_started' }).Count -eq 3) 'per-task fixture must contain three authoritative review starts'
Assert-True ([string]$perTaskReviews.events[0].reviewKind -ceq 'initial_task') 'initial review must use initial_task kind'
Assert-True ([int]$perTaskReviews.events[0].reviewAttemptOrdinal -eq 1) 'initial review must start at ordinal one'
Assert-True (@($perTaskReviews.events | Where-Object { [string]$_.eventType -ceq 'correction_ready' }).Count -eq 1) 'per-task fixture must include the correction-ready boundary'
$correctionReviewStart = @($perTaskReviews.events | Where-Object { [string]$_.eventType -ceq 'review_started' -and [string]$_.reviewKind -ceq 'correction_rereview' })[0]
Assert-True ([string]$correctionReviewStart.reviewKind -ceq 'correction_rereview') 'correction re-review must use correction_rereview kind'
Assert-True ([string]$correctionReviewStart.revision -ceq 'cccccccccccccccccccccccccccccccccccccccc') 'correction re-review must use the corrected revision'
Assert-True ([string]$perTaskReviews.events[0].revision -ceq [string]$perTaskReviews.events[1].revision) 'review start and acceptance must retain the same revision'
$task148Assertions = {
    $perTaskCounts = Get-ReviewCountResult -Fixture $perTaskReviews
$perTaskObservations = Get-ReviewObservationResult -Fixture $perTaskReviews
Assert-True ($perTaskObservations.duplicateEventCount -eq 1) 'fixture control must derive one exact duplicate event'
Assert-True ($perTaskObservations.duplicateAttemptCount -eq 1) 'fixture control must derive one same-attempt duplicate with a new event ID'
Assert-True ($perTaskObservations.conflictCount -eq 1) 'fixture control must derive one changed-payload conflict'
Assert-True ($perTaskObservations.staleCount -eq 1) 'fixture control must derive one stale closed-attempt observation'
Assert-True ($perTaskObservations.unhandledCount -eq 0) 'fixture control must classify every observation'
Assert-True ([int]$perTaskReviews.expectedCounts.initialTaskReviews -eq $perTaskCounts.initialTaskReviews) 'per-task expected initial count must match the derived event count'
Assert-True ([int]$perTaskReviews.expectedCounts.correctionReReviews -eq $perTaskCounts.correctionReReviews) 'per-task expected correction count must match the derived event count'
Assert-True ([int]$perTaskReviews.expectedCounts.finalStoryReviews -eq $perTaskCounts.finalStoryReviews) 'per-task expected final count must match the derived event count'
Assert-True ([int]$perTaskReviews.expectedCounts.finalStoryReReviews -eq $perTaskCounts.finalStoryReReviews) 'per-task expected final re-review count must match the derived event count'
Assert-True ([int]$perTaskReviews.expectedCounts.tasksWithInitialReview -eq $perTaskCounts.tasksWithInitialReview) 'per-task expected denominator must match the derived task set'
Assert-True ([int]$perTaskReviews.expectedCounts.acceptedFirstAttemptTasks -eq $perTaskCounts.acceptedFirstAttemptTasks) 'per-task expected numerator must match the derived acceptance sequence'
Assert-True ([string]$perTaskReviews.expectedCounts.firstPassAcceptanceRate.state -ceq [string]$perTaskCounts.firstPassAcceptanceRate.state) 'per-task expected rate state must match derived coverage'
Assert-True ([double]$perTaskReviews.expectedCounts.firstPassAcceptanceRate.value -eq [double]$perTaskCounts.firstPassAcceptanceRate.value) 'per-task expected rate must match derived numerator and denominator'
Assert-True ([string]$perTaskReviews.expectedCounts.firstPassAcceptanceRate.coverage -ceq [string]$perTaskCounts.firstPassAcceptanceRate.coverage) 'per-task expected rate coverage must match derived closure coverage'

$storyEndOnlyReviews = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-review-counts-story-end-only'
Assert-True ([string]$storyEndOnlyReviews.reviewMode -ceq 'story_end_only') 'story-end-only fixture must preserve story_end_only mode'
Assert-True (@($storyEndOnlyReviews.events | Where-Object { [string]$_.scope -ceq 'task' }).Count -eq 0) 'story-end-only fixture must have no task review events'
Assert-True ([int]$storyEndOnlyReviews.constraints.taskReviewEvents -eq 0) 'story-end-only fixture must declare zero task reviews'
Assert-True ([int]$storyEndOnlyReviews.constraints.correctionReReviews -eq 0) 'story-end-only fixture must declare zero correction re-reviews'
Assert-True ([int]$storyEndOnlyReviews.constraints.addedAgents -eq 0 -and [int]$storyEndOnlyReviews.constraints.pollingEvents -eq 0 -and [int]$storyEndOnlyReviews.constraints.measurementOnlyMessages -eq 0) 'story-end-only fixture must prohibit added agents, polling, and measurement-only messages'
$storyEndOnlyCounts = Get-ReviewCountResult -Fixture $storyEndOnlyReviews
Assert-True ([int]$storyEndOnlyReviews.expectedCounts.initialTaskReviews -eq $storyEndOnlyCounts.initialTaskReviews) 'story-end-only initial count must be derived as zero'
Assert-True ([int]$storyEndOnlyReviews.expectedCounts.correctionReReviews -eq $storyEndOnlyCounts.correctionReReviews) 'story-end-only correction count must be derived as zero'
Assert-True ([int]$storyEndOnlyReviews.expectedCounts.finalStoryReviews -eq $storyEndOnlyCounts.finalStoryReviews) 'story-end-only final review total must remain countable'
Assert-True ([int]$storyEndOnlyReviews.expectedCounts.finalStoryReReviews -eq $storyEndOnlyCounts.finalStoryReReviews) 'story-end-only final re-review subset must be derived'
Assert-True ([string]$storyEndOnlyReviews.expectedCounts.firstPassAcceptanceRate.state -ceq [string]$storyEndOnlyCounts.firstPassAcceptanceRate.state) 'story-end-only first-pass rate must be derived as not applicable'
Assert-True ([int]$storyEndOnlyReviews.expectedCounts.firstPassAcceptanceRate.denominator -eq $storyEndOnlyCounts.firstPassAcceptanceRate.denominator) 'story-end-only first-pass denominator must be derived as zero'

$sameHeadReReviews = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-final-rereviews-same-head'
$sameHeadRevisions = @($sameHeadReReviews.events | ForEach-Object { [string]$_.revision } | Select-Object -Unique)
Assert-True ($sameHeadRevisions.Count -eq 1) 'same-head fixture must keep one reviewed revision'
Assert-True (@($sameHeadReReviews.events | Where-Object { [string]$_.reviewKind -ceq 'final_story_rereview' }).Count -eq 2) 'same-head fixture must contain two final re-review attempts'
Assert-True (@($sameHeadReReviews.events | Where-Object { [int]$_.reviewAttemptOrdinal -eq 2 }).Count -eq 1) 'same-head fixture must distinguish a real retry by ordinal'
$sameHeadCounts = Get-ReviewCountResult -Fixture $sameHeadReReviews
Assert-True ([int]$sameHeadReReviews.expectedCounts.finalStoryReviews -eq $sameHeadCounts.finalStoryReviews) 'same-head final total must include every distinct final attempt'
Assert-True ([int]$sameHeadReReviews.expectedCounts.finalStoryReReviews -eq $sameHeadCounts.finalStoryReReviews) 'same-head final re-review subset must be derived from later attempts'
$sameHeadAttemptIds = @($sameHeadReReviews.events | Where-Object { [string]$_.eventType -eq 'final_review_started' } | ForEach-Object { [string]$_.reviewAttemptId } | Sort-Object -Unique)
Assert-True ($sameHeadAttemptIds.Count -eq $sameHeadCounts.finalStoryReviews) 'same-head fixture must derive one distinct attempt per final total'
Assert-True ([bool]$sameHeadReReviews.expectedCounts.sameHeadDistinctAttempts -eq ($sameHeadAttemptIds.Count -eq 3)) 'same-head distinct-attempt claim must match derived identities'

$reviewUsageFallback = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-review-usage-unavailable-fallback'
Assert-True ([string]$reviewUsageFallback.sourceBackedUsage.state -ceq 'unavailable') 'review usage fallback must be explicitly unavailable'
Assert-True ($null -eq $reviewUsageFallback.sourceBackedUsage.streamId -and $null -eq $reviewUsageFallback.sourceBackedUsage.counters) 'review usage fallback must not invent a stream or counters'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$reviewUsageFallback.sourceBackedUsage.reason)) 'review usage fallback must explain its source limitation'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$reviewUsageFallback.sourceBackedUsage.fallback)) 'review usage fallback must name a safe fallback'
Assert-True (@($reviewUsageFallback.forbiddenEstimates).Count -ge 4) 'review usage fallback must name forbidden estimates'

$overhead = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-overhead-baseline-candidate'
Assert-True ([string]$overhead.baseline.outcomeFingerprint -ceq [string]$overhead.candidate.outcomeFingerprint) 'overhead fixture must compare equivalent outcomes'
Assert-True ([string]$overhead.workloadId -ceq 'fixed-review-contract-workload-1') 'overhead fixture must identify one fixed workload'
Assert-True ([int]$overhead.baseline.addedAgents -eq 0 -and [int]$overhead.candidate.addedAgents -eq 0) 'overhead fixture must add no agents'
Assert-True ([int]$overhead.baseline.pollingEvents -eq 0 -and [int]$overhead.candidate.pollingEvents -eq 0) 'overhead fixture must add no polling'
Assert-True ([int]$overhead.baseline.measurementOnlyMessages -eq 0 -and [int]$overhead.candidate.measurementOnlyMessages -eq 0) 'overhead fixture must add no measurement-only messages'
Assert-True ([int]$overhead.candidate.eventCount -eq 14 -and [int]$overhead.budget.maxAddedEvents -eq 14) 'overhead fixture must bound lifecycle event additions'
$overheadDecision = Get-OverheadDecision -Baseline $overhead.baseline -Candidate $overhead.candidate -Budget $overhead.budget
Assert-True ([string]$overhead.overhead.state -ceq $overheadDecision.state) 'overhead state must match the derived elapsed evidence state'
Assert-True ([int]$overhead.overhead.elapsedMilliseconds -eq $overheadDecision.elapsedMilliseconds) 'overhead elapsed delta must be derived from baseline and candidate'
Assert-True ([double]$overhead.overhead.elapsedPercent -eq $overheadDecision.elapsedPercent) 'overhead percentage must be derived from baseline and candidate'
Assert-True ([string]$overhead.overhead.usageOverhead -ceq 'unavailable') 'overhead fixture must keep usage unavailable separate from elapsed acceptance'
Assert-True ([bool]$overhead.acceptance.sameOutcome -eq $overheadDecision.sameOutcome -and [bool]$overhead.acceptance.sameWorkload -eq $overheadDecision.sameWorkload -and [bool]$overhead.acceptance.withinBudget -eq $overheadDecision.withinBudget -and [bool]$overhead.acceptance.noExtraAgentsPollingOrMeasurementMessages -eq $overheadDecision.noExtraAgentsPollingOrMeasurementMessages) 'overhead acceptance fields must match derived controls'
foreach ($negativeControl in @($overhead.negativeControls)) {
    $negativeDecision = Get-OverheadDecision -Baseline $negativeControl.baseline -Candidate $negativeControl.candidate -Budget $negativeControl.budget
    Assert-True (-not $negativeDecision.accepted) "overhead negative control '$($negativeControl.case)' must fail derived acceptance"
}
$requiredNegativeControls = @('budget-exceeded', 'changed-outcome', 'changed-workload', 'extra-agent', 'extra-polling', 'extra-message', 'missing-comparable-evidence')
$actualNegativeControls = @($overhead.negativeControls | ForEach-Object { [string]$_.case })
foreach ($requiredNegativeControl in $requiredNegativeControls) {
    Assert-True ($actualNegativeControls -contains $requiredNegativeControl) "overhead fixture must include negative control '$requiredNegativeControl'"
}
}

$tokenSubtotalExample = Get-RequiredExample -Examples $examples -ExampleId 'synthetic-token-subtotal'
Assert-True ([string]$tokenSubtotalExample.counterSemantics.cachedInput -ceq 'included_in_input') 'token example must declare cached-input inclusion'
Assert-True ([string]$tokenSubtotalExample.counterSemantics.reasoning -ceq 'included_in_output') 'token example must declare reasoning inclusion'
Assert-True ([int]$tokenSubtotalExample.components.input -eq 100) 'token example input component must exclude a cached-input double count'
Assert-True ([int]$tokenSubtotalExample.components.output -eq 30) 'token example output component must exclude a reasoning double count'
Assert-True ([int]$tokenSubtotalExample.roleTotalTokens -eq 130) 'token example role total must follow the declared formula'

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
        'privacy-unavailable'
        'synthetic-review-counts-per-task'
        'synthetic-review-counts-story-end-only'
        'synthetic-final-rereviews-same-head'
        'synthetic-review-usage-unavailable-fallback'
        'synthetic-overhead-baseline-candidate')) {
    Assert-Contains $normalized $fixtureId "requirement-to-fixture matrix is missing $fixtureId"
}
foreach ($contractMarker in @(
        'schemaVersion: 1'
        'eventId'
        'phaseId'
        'correctionId'
        'supersedesReviewAttemptId'
        '`revision` may be `null` before a commit exists'
        '`phaseId` is `null`'
        'explicit waits, which use `waitId` instead'
        'or `final_review_started` when `scope=final_story`'
        'final-story correction'
        'Replaying the same ID'
        'same ID with any different payload is a conflict'
        'finalStoryReviews counts every distinct authoritative final-story attempt'
        'finalStoryReReviews can never exceed'
        'projections of the full version-1'
        'append-only JSONL'
        'Performance pointer:'
        'delta(c) = c(end) - c(exact baseline)'
        'inputComponent ='
        'roleTotalTokens = inputComponent + outputComponent'
        'cachedInput = included_in_input'
        'reasoning = included_in_output'
        'state: partial` and `value: null'
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
        'Cached-input and reasoning counters remain separate'
        'Prompt, transcript, source-text, and secret fields are rejected')) {
    Assert-Contains $normalized $contractMarker "contract is missing '$contractMarker'"
}

function ConvertTo-CanonicalValue {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object { [string]$_ })) {
            $result[[string]$key] = ConvertTo-CanonicalValue -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $result[$property.Name] = ConvertTo-CanonicalValue -Value $property.Value
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-CanonicalValue -Value $_ })
    }
    return $Value
}

function Get-CanonicalPayload {
    param([AllowNull()] [object] $Payload)

    $canonical = ConvertTo-CanonicalValue -Value $Payload
    return (ConvertTo-Json -InputObject $canonical -Compress -Depth 20)
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

function Get-ReviewPayloadWithoutEventId {
    param([Parameter(Mandatory)] [object] $Event)

    $payload = [ordered]@{}
    foreach ($property in @($Event.PSObject.Properties)) {
        if ($property.Name -cne 'eventId') {
            $payload[$property.Name] = $property.Value
        }
    }
    return Get-CanonicalPayload -Payload $payload
}

function Get-ReviewCountResult {
    param([Parameter(Mandatory)] [object] $Fixture)

    $events = @($Fixture.events)
    $starts = @($events | Where-Object {
            [string]$_.eventType -ceq 'review_started' -or
            [string]$_.eventType -ceq 'final_review_started'
        })
    $attempts = @{}
    foreach ($start in $starts) {
        $attemptId = [string]$start.reviewAttemptId
        Assert-True (-not [string]::IsNullOrWhiteSpace($attemptId)) 'review start must carry an attempt identity'
        Assert-True (-not $attempts.ContainsKey($attemptId)) "authoritative review attempts must be unique: $attemptId"
        $attempts[$attemptId] = $start
    }

    $initialStarts = @($starts | Where-Object { [string]$_.reviewKind -ceq 'initial_task' })
    $initialTaskRefs = @($initialStarts | ForEach-Object { [string]$_.taskRef } | Sort-Object -Unique)
    $correctionAttemptIds = @($starts |
        Where-Object { [string]$_.reviewKind -ceq 'correction_rereview' } |
        ForEach-Object { [string]$_.reviewAttemptId } |
        Sort-Object -Unique)

    $finalStarts = @($starts |
        Where-Object { [string]$_.scope -ceq 'final_story' } |
        Sort-Object { [DateTime]::Parse([string]$_.occurredAtUtc) })
    $finalAttemptIds = @($finalStarts | ForEach-Object { [string]$_.reviewAttemptId } | Sort-Object -Unique)
    $firstFinalAttemptId = if ($finalAttemptIds.Count -gt 0) { [string]$finalAttemptIds[0] } else { $null }
    $finalReReviewAttemptIds = @($finalAttemptIds | Where-Object { [string]$_ -cne $firstFinalAttemptId })
    $seenFinalAttemptIds = @{}
    foreach ($finalStart in $finalStarts) {
        $attemptId = [string]$finalStart.reviewAttemptId
        $expectedKind = if ($seenFinalAttemptIds.Count -eq 0) { 'final_story' } else { 'final_story_rereview' }
        Assert-True ([string]$finalStart.reviewKind -ceq $expectedKind) "final attempt $attemptId must use the derived review kind $expectedKind"
        $seenFinalAttemptIds[$attemptId] = $true
    }

    $acceptedFirstAttemptTasks = 0
    $closedInitialOutcomes = 0
    foreach ($taskRef in $initialTaskRefs) {
        $taskStarts = @($initialStarts |
            Where-Object { [string]$_.taskRef -ceq [string]$taskRef } |
            Sort-Object { [DateTime]::Parse([string]$_.occurredAtUtc) })
        $firstStart = $taskStarts[0]
        $firstAttemptId = [string]$firstStart.reviewAttemptId
        $closures = @($events |
            Where-Object {
                $attemptProperty = $_.PSObject.Properties['reviewAttemptId']
                $null -ne $attemptProperty -and [string]$attemptProperty.Value -ceq $firstAttemptId -and
                ([string]$_.eventType -ceq 'review_findings' -or
                    [string]$_.eventType -ceq 'review_accepted')
            } |
            Sort-Object { [DateTime]::Parse([string]$_.occurredAtUtc) })
        if ($closures.Count -eq 0) { continue }
        $closedInitialOutcomes++
        if ([string]$closures[0].eventType -ceq 'review_accepted') {
            $acceptedFirstAttemptTasks++
        }
    }

    $denominator = $initialTaskRefs.Count
    if ($denominator -eq 0) {
        $rate = [ordered]@{
            state = 'not_applicable'
            value = $null
            numerator = 0
            denominator = 0
            coverage = 'story_end_only intentionally has no per-task review denominator'
        }
    }
    else {
        $rateState = if ($closedInitialOutcomes -eq $denominator) { 'measured' } else { 'partial' }
        $rate = [ordered]@{
            state = $rateState
            value = [double]$acceptedFirstAttemptTasks / [double]$denominator
            numerator = $acceptedFirstAttemptTasks
            denominator = $denominator
            coverage = "$closedInitialOutcomes of $denominator initial task review outcomes are authoritative"
        }
    }

    return [pscustomobject]@{
        initialTaskReviews = $initialTaskRefs.Count
        correctionReReviews = $correctionAttemptIds.Count
        finalStoryReviews = $finalAttemptIds.Count
        finalStoryReReviews = $finalReReviewAttemptIds.Count
        tasksWithInitialReview = $denominator
        acceptedFirstAttemptTasks = $acceptedFirstAttemptTasks
        firstPassAcceptanceRate = [pscustomobject]$rate
    }
}

function Get-ReviewObservationResult {
    param([Parameter(Mandatory)] [object] $Fixture)

    $ledgerByEventId = @{}
    $attemptPayloadById = @{}
    $closedAtByAttemptId = @{}
    foreach ($event in @($Fixture.events)) {
        $eventId = [string]$event.eventId
        Assert-True (-not [string]::IsNullOrWhiteSpace($eventId)) 'review fixture events must have event IDs'
        Assert-True (-not $ledgerByEventId.ContainsKey($eventId)) "fixture authoritative event IDs must be unique: $eventId"
        $ledgerByEventId[$eventId] = Get-CanonicalPayload -Payload $event

        if ([string]$event.eventType -ceq 'review_started' -or [string]$event.eventType -ceq 'final_review_started') {
            $attemptId = [string]$event.reviewAttemptId
            Assert-True (-not [string]::IsNullOrWhiteSpace($attemptId)) 'review fixture starts must have attempt IDs'
            Assert-True (-not $attemptPayloadById.ContainsKey($attemptId)) "fixture authoritative attempt IDs must be unique: $attemptId"
            $attemptPayloadById[$attemptId] = Get-ReviewPayloadWithoutEventId -Event $event
        }

        if ([string]$event.eventType -ceq 'review_findings' -or
            [string]$event.eventType -ceq 'review_accepted' -or
            [string]$event.eventType -ceq 'final_review_accepted') {
            $attemptId = [string]$event.reviewAttemptId
            if (-not [string]::IsNullOrWhiteSpace($attemptId)) {
                $occurred = [DateTime]::Parse([string]$event.occurredAtUtc)
                if (-not $closedAtByAttemptId.ContainsKey($attemptId) -or $occurred -lt $closedAtByAttemptId[$attemptId]) {
                    $closedAtByAttemptId[$attemptId] = $occurred
                }
            }
        }
    }

    $duplicateEventCount = 0
    $duplicateAttemptCount = 0
    $conflictCount = 0
    $staleCount = 0
    $unhandledCount = 0
    foreach ($observation in @($Fixture.observations)) {
        $eventId = [string]$observation.eventId
        $attemptId = [string]$observation.reviewAttemptId
        $canonical = Get-CanonicalPayload -Payload $observation
        if ($ledgerByEventId.ContainsKey($eventId)) {
            if ([string]$ledgerByEventId[$eventId] -ceq $canonical) {
                $duplicateEventCount++
            }
            else {
                $conflictCount++
            }
            continue
        }

        if ($attemptPayloadById.ContainsKey($attemptId)) {
            $occurred = [DateTime]::Parse([string]$observation.occurredAtUtc)
            if ($closedAtByAttemptId.ContainsKey($attemptId) -and $occurred -gt $closedAtByAttemptId[$attemptId]) {
                $staleCount++
            }
            elseif ([string]$attemptPayloadById[$attemptId] -ceq (Get-ReviewPayloadWithoutEventId -Event $observation)) {
                $duplicateAttemptCount++
            }
            else {
                $conflictCount++
            }
            continue
        }

        $unhandledCount++
    }

    return [pscustomobject]@{
        duplicateEventCount = $duplicateEventCount
        duplicateAttemptCount = $duplicateAttemptCount
        conflictCount = $conflictCount
        staleCount = $staleCount
        unhandledCount = $unhandledCount
    }
}

function Get-OverheadDecision {
    param(
        [AllowNull()] [object] $Baseline,
        [AllowNull()] [object] $Candidate,
        [AllowNull()] [object] $Budget
    )

    if ($null -eq $Baseline -or $null -eq $Candidate -or $null -eq $Budget) {
        return [pscustomobject]@{
            accepted = $false
            state = 'unavailable'
            sameOutcome = $false
            sameWorkload = $false
            withinBudget = $false
            noExtraAgentsPollingOrMeasurementMessages = $false
            elapsedMilliseconds = $null
            elapsedPercent = $null
        }
    }

    $sameOutcome = [string]$Baseline.outcomeFingerprint -ceq [string]$Candidate.outcomeFingerprint
    $sameWorkload = -not [string]::IsNullOrWhiteSpace([string]$Baseline.workloadId) -and
        [string]$Baseline.workloadId -ceq [string]$Candidate.workloadId
    $elapsedDelta = [double]$Candidate.elapsedMilliseconds - [double]$Baseline.elapsedMilliseconds
    $elapsedOverhead = [math]::Max(0, $elapsedDelta)
    $elapsedPercent = if ([double]$Baseline.elapsedMilliseconds -gt 0) {
        [math]::Round(($elapsedOverhead / [double]$Baseline.elapsedMilliseconds) * 100, 6)
    }
    else {
        $null
    }
    $eventDelta = [int]$Candidate.eventCount - [int]$Baseline.eventCount
    $noExtra = [int]$Candidate.addedAgents -eq 0 -and
        [int]$Candidate.pollingEvents -eq 0 -and
        [int]$Candidate.measurementOnlyMessages -eq 0
    $withinBudget = $null -ne $elapsedPercent -and
        $elapsedOverhead -le [double]$Budget.maxElapsedMilliseconds -and
        $elapsedPercent -le [double]$Budget.maxElapsedPercent -and
        $eventDelta -le [int]$Budget.maxAddedEvents -and
        [int]$Candidate.addedAgents -le [int]$Budget.maxAddedAgents -and
        [int]$Candidate.pollingEvents -le [int]$Budget.maxPollingEvents -and
        [int]$Candidate.measurementOnlyMessages -le [int]$Budget.maxMeasurementOnlyMessages

    return [pscustomobject]@{
        accepted = $sameOutcome -and $sameWorkload -and $withinBudget -and $noExtra
        state = if ($sameOutcome -and $sameWorkload -and $null -ne $elapsedPercent) { 'measured' } else { 'partial' }
        sameOutcome = $sameOutcome
        sameWorkload = $sameWorkload
        withinBudget = $withinBudget
        noExtraAgentsPollingOrMeasurementMessages = $noExtra
        elapsedMilliseconds = [int]$elapsedOverhead
        elapsedPercent = $elapsedPercent
    }
}

$replayStore = @{}
$syntheticEvent = [ordered]@{ eventId = 'fixture-event-1'; eventType = 'story_started'; occurredAtUtc = '2026-10-09T10:00:00Z' }
Assert-True ((Invoke-ReplayFixture -Existing $replayStore -Incoming $syntheticEvent) -ceq 'appended') 'first event should append'
Assert-True ((Invoke-ReplayFixture -Existing $replayStore -Incoming $syntheticEvent) -ceq 'noop') 'same-ID same-payload replay should be a no-op'
$conflictingEvent = [ordered]@{ eventId = 'fixture-event-1'; eventType = 'pr_ready'; occurredAtUtc = '2026-10-09T10:00:00Z' }
Assert-True ((Invoke-ReplayFixture -Existing $replayStore -Incoming $conflictingEvent) -ceq 'conflict') 'same-ID different-payload replay should conflict'
Assert-True ([string]$replayStore['fixture-event-1'] -match 'story_started') 'conflict must preserve the first complete event'

$nestedStore = @{}
$nestedEventA = [ordered]@{
    eventId = 'fixture-nested-event'
    eventType = 'review_started'
    provenance = [ordered]@{ source = 'workflow_transition'; coverage = 'direct' }
    usage = [ordered]@{ state = 'unavailable'; counters = $null }
}
$nestedEventB = [ordered]@{
    usage = [ordered]@{ counters = $null; state = 'unavailable' }
    provenance = [ordered]@{ coverage = 'direct'; source = 'workflow_transition' }
    eventType = 'review_started'
    eventId = 'fixture-nested-event'
}
Assert-True ((Invoke-ReplayFixture -Existing $nestedStore -Incoming $nestedEventA) -ceq 'appended') 'nested event should append'
Assert-True ((Invoke-ReplayFixture -Existing $nestedStore -Incoming $nestedEventB) -ceq 'noop') 'reordered nested keys should be a no-op'
$nestedConflict = [ordered]@{
    eventId = 'fixture-nested-event'
    eventType = 'review_started'
    provenance = [ordered]@{ source = 'workflow_transition'; coverage = 'partial' }
    usage = [ordered]@{ state = 'unavailable'; counters = $null }
}
Assert-True ((Invoke-ReplayFixture -Existing $nestedStore -Incoming $nestedConflict) -ceq 'conflict') 'changed nested value should conflict'
Assert-True ([string]$nestedStore['fixture-nested-event'] -match '"coverage":"direct"') 'nested conflict must preserve the first payload'

function Get-CumulativeDelta {
    param(
        [Nullable[int]] $Baseline,
        [Nullable[int]] $End,
        [Nullable[int]] $SampleAtUtc,
        [Nullable[int]] $RunEndUtc
    )

    if ($null -ne $SampleAtUtc -and $null -ne $RunEndUtc -and [int]$SampleAtUtc -gt [int]$RunEndUtc) { return $null }
    if ($null -eq $Baseline -or $null -eq $End -or [int]$End -lt [int]$Baseline) { return $null }
    return [int]$End - [int]$Baseline
}

Assert-True ((Get-CumulativeDelta -Baseline 100 -End 145) -eq 45) 'exact-boundary cumulative delta should be calculated'
Assert-True ($null -eq (Get-CumulativeDelta -Baseline $null -End 145)) 'missing baseline should remain unknown'
Assert-True ($null -eq (Get-CumulativeDelta -Baseline 145 -End 120)) 'counter reset should remain unknown'
Assert-True ($null -eq (Get-CumulativeDelta -Baseline 100 -End 145 -SampleAtUtc 110 -RunEndUtc 100)) 'post-run sample must not be attributed'

function Get-IntervalMilliseconds {
    param(
        [Nullable[int]] $Start,
        [Nullable[int]] $End
    )

    if ($null -eq $Start -or $null -eq $End -or [int]$End -lt [int]$Start) { return $null }
    return ([int]$End - [int]$Start) * 1000
}

Assert-True ((Get-IntervalMilliseconds -Start 10 -End 20) -eq 10000) 'paired phase interval should calculate elapsed milliseconds'
Assert-True ($null -eq (Get-IntervalMilliseconds -Start 10 -End $null)) 'missing phase end should remain unknown'
Assert-True ($null -eq (Get-IntervalMilliseconds -Start 20 -End 10)) 'reversed phase interval should remain unknown'
$implementationDuration = Get-IntervalMilliseconds -Start 10 -End 20
$reviewDuration = Get-IntervalMilliseconds -Start 15 -End 25
Assert-True (($implementationDuration + $reviewDuration) -eq 20000) 'overlapping phases must retain separate elapsed totals'
Assert-True (($implementationDuration + $reviewDuration) -ne (Get-IntervalMilliseconds -Start 10 -End 25)) 'overlap must not be subtracted from phase totals'

function Test-RecoveryPointer {
    param([string] $Pointer)

    return ($Pointer -match '^Performance pointer: schema=1 \| run=[^|]+ \| project=[^|]+ \| story=[^|]+ \| ledger=(?!C:\\Users\\Blake\\\.codex\\worktrees)[^|]+ \| lastEvent=[^|]+ \| lastObservedUtc=.+$' -and
        $Pointer -notmatch '(?i)prompt|transcript|secret|password')
}

$pointer = 'Performance pointer: schema=1 | run=synthetic-run-141 | project=12 | story=725/141 | ledger=C:\\Temp\\TaigaMCP\\synthetic-run-141\\events.jsonl | lastEvent=synthetic-event-1 | lastObservedUtc=2026-10-09T10:00:00Z'
Assert-True (Test-RecoveryPointer -Pointer $pointer) 'recovery pointer must be compact, external, and privacy-safe'

function Get-ReportIdentity {
    param(
        [string] $RunId,
        [int] $ProjectId,
        [int] $StoryId,
        [string] $Provider,
        [string] $Owner,
        [string] $Repository,
        [int] $Number,
        [string] $ReviewedHead
    )

    return ($RunId, $ProjectId, $StoryId, $Provider, $Owner, $Repository, $Number, $ReviewedHead) -join '|'
}

$reportIdentityA = Get-ReportIdentity -RunId 'run-1' -ProjectId 12 -StoryId 725 -Provider 'github' -Owner 'blakeg83' -Repository 'taiga-mcp' -Number 321 -ReviewedHead ('a' * 40)
$reportIdentityB = Get-ReportIdentity -RunId 'run-1' -ProjectId 12 -StoryId 725 -Provider 'github' -Owner 'blakeg83' -Repository 'taiga-mcp' -Number 321 -ReviewedHead ('a' * 40)
$reportIdentityC = Get-ReportIdentity -RunId 'run-1' -ProjectId 12 -StoryId 725 -Provider 'github' -Owner 'blakeg83' -Repository 'taiga-mcp' -Number 321 -ReviewedHead ('b' * 40)
Assert-True ($reportIdentityA -ceq $reportIdentityB) 'same story/PR/exact HEAD must reuse report identity'
Assert-True ($reportIdentityA -cne $reportIdentityC) 'new exact HEAD must create a new report identity'

function Get-RoleTokenSubtotal {
    param(
        [Nullable[int]] $InputDelta,
        [Nullable[int]] $CachedInputDelta,
        [Nullable[int]] $OutputDelta,
        [Nullable[int]] $ReasoningDelta,
        [string] $CachedInputRelationship,
        [string] $ReasoningRelationship
    )

    if ($CachedInputRelationship -notin @('included_in_input', 'disjoint_from_input') -or
        $ReasoningRelationship -notin @('included_in_output', 'disjoint_from_output')) {
        return [ordered]@{ state = 'partial'; value = $null }
    }
    if ($null -eq $InputDelta -or $null -eq $OutputDelta) {
        return [ordered]@{ state = 'partial'; value = $null }
    }
    if ($CachedInputRelationship -eq 'disjoint_from_input' -and $null -eq $CachedInputDelta) {
        return [ordered]@{ state = 'partial'; value = $null }
    }
    if ($ReasoningRelationship -eq 'disjoint_from_output' -and $null -eq $ReasoningDelta) {
        return [ordered]@{ state = 'partial'; value = $null }
    }
    $inputComponent = [int]$InputDelta
    if ($CachedInputRelationship -eq 'disjoint_from_input') { $inputComponent += [int]$CachedInputDelta }
    $outputComponent = [int]$OutputDelta
    if ($ReasoningRelationship -eq 'disjoint_from_output') { $outputComponent += [int]$ReasoningDelta }
    return [ordered]@{ state = 'measured'; value = $inputComponent + $outputComponent; input = $inputComponent; output = $outputComponent }
}

$includedSubtotal = Get-RoleTokenSubtotal -InputDelta 100 -CachedInputDelta 40 -OutputDelta 30 -ReasoningDelta 8 -CachedInputRelationship included_in_input -ReasoningRelationship included_in_output
Assert-True ([string]$includedSubtotal.state -ceq 'measured' -and [int]$includedSubtotal.value -eq 130) 'included subtotals must not double-count cached or reasoning tokens'
$disjointSubtotal = Get-RoleTokenSubtotal -InputDelta 100 -CachedInputDelta 40 -OutputDelta 30 -ReasoningDelta 8 -CachedInputRelationship disjoint_from_input -ReasoningRelationship disjoint_from_output
Assert-True ([int]$disjointSubtotal.value -eq 178) 'disjoint subtotals must add only explicitly disjoint components'
$unknownSubtotal = Get-RoleTokenSubtotal -InputDelta 100 -CachedInputDelta 40 -OutputDelta 30 -ReasoningDelta 8 -CachedInputRelationship unknown -ReasoningRelationship included_in_output
Assert-True ([string]$unknownSubtotal.state -ceq 'partial' -and $null -eq $unknownSubtotal.value) 'unspecified token inclusion must remain partial and null'

function Assert-NoPrivateFields {
    param([System.Collections.IDictionary] $Payload)

    $forbidden = @('prompt', 'transcript', 'sourceText', 'secret', 'password', 'authToken', 'messageBody')
    foreach ($key in $Payload.Keys) {
        if ([string]$key -in $forbidden) { throw "private field is not allowed: $key" }
        $value = $Payload[$key]
        if ($value -is [System.Collections.IDictionary]) { Assert-NoPrivateFields -Payload $value }
    }
}

$safePayload = [ordered]@{ provenance = [ordered]@{ source = 'workflow_transition'; coverage = 'direct' }; usage = $null }
Assert-NoPrivateFields -Payload $safePayload
$privatePayload = [ordered]@{ provenance = [ordered]@{ source = 'workflow_transition' }; prompt = 'not allowed' }
Assert-Throws { Assert-NoPrivateFields -Payload $privatePayload } 'privacy fixture must reject prompt/transcript/secret fields'

& $task148Assertions

Write-Output 'Passed performance-reporting contract fixture: discovery provenance, versioned event/report examples, stable phase identities, final findings closure, recursive replay/no-op/conflict identity, interval coverage/overlap, external recovery pointer, report identity, exact token subtotal semantics, cumulative baseline/reset handling, privacy rejection, review-attempt counting in both modes, same-head re-reviews, unavailable review usage, and bounded baseline/candidate overhead; synthetic and non-live.'
exit 0
