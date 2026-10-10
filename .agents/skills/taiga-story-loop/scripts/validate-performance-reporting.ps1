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
        'Task #148')) {
    Assert-Contains $normalized $marker "reference is missing '$marker'"
}

Assert-Contains $normalized 'Do not use them as token totals or cost.' 'reference must prohibit cost attribution from account limits'
Assert-Contains $normalized 'Account-level limits' 'account-level limits must be distinguished from story attribution'
Assert-True ($normalized.Contains('unknown, not zero')) 'unknown values must not be converted to zero'

$jsonMatches = [regex]::Matches($reference, '(?ms)^```json\s*\r?\n(?<json>.*?)\r?\n```')
Assert-True ($jsonMatches.Count -ge 9) 'reference must contain discovery, phase, token, event, and report examples'

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
Assert-True ([string]$finalFindings.events[1].eventType -ceq 'review_findings') 'final review findings must close through review_findings'

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
        'privacy-unavailable')) {
    Assert-Contains $normalized $fixtureId "requirement-to-fixture matrix is missing $fixtureId"
}
foreach ($contractMarker in @(
        'schemaVersion: 1'
        'eventId'
        'phaseId'
        'correctionId'
        'supersedesReviewAttemptId'
        '`revision` may be `null` before a commit exists'
        'final-story correction'
        'Replaying the same ID'
        'same ID with any different payload is a conflict'
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
    param([System.Collections.IDictionary] $Payload)

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

Write-Output 'Passed performance-reporting contract fixture: discovery provenance, versioned event/report examples, stable phase identities, final findings closure, recursive replay/no-op/conflict identity, interval coverage/overlap, external recovery pointer, report identity, exact token subtotal semantics, cumulative baseline/reset handling, privacy rejection, and unavailable fallback; synthetic and non-live.'
exit 0
