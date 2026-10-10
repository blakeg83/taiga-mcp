<#
.SYNOPSIS
    Run deterministic integrated story-loop reporting and recovery fixtures.

The fixture is synthetic evidence only. It uses fixed UTC timestamps and a
unique disposable external directory; it does not call Taiga, start a service,
write workflow state, or export a transcript.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Get-NullableText {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        return $null
    }
    return [string] $Value
}

function New-Event {
    param(
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [Parameter(Mandatory)] [string] $Scope,
        [AllowNull()] [Nullable[int]] $TaskRef = $null,
        [AllowNull()] [string] $PhaseId = $null,
        [AllowNull()] [string] $CorrectionId = $null,
        [AllowNull()] [string] $ReviewRequestId = $null,
        [AllowNull()] [string] $ReviewAttemptId = $null,
        [AllowNull()] [string] $ReviewKind = $null,
        [AllowNull()] [Nullable[int]] $ReviewAttemptOrdinal = $null,
        [AllowNull()] [string] $Revision = $null,
        [AllowNull()] [string] $WaitId = $null,
        [AllowNull()] [string] $WaitKind = $null,
        [AllowNull()] [string] $SupersedesReviewAttemptId = $null,
        [AllowNull()] [object] $Usage = $null,
        [string] $ReviewMode = 'per_task',
        [string] $SessionId = 'synthetic-session',
        [string] $Role = 'coordinator'
    )

    $event = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event'
        eventId = $EventId
        runId = 'synthetic-task-152'
        projectId = 12
        storyId = 727
        storyRef = 143
        taskRef = $TaskRef
        role = $Role
        sessionId = $SessionId
        workerId = 'synthetic-worker'
        transitionId = $EventId
        scope = $Scope
        phaseId = Get-NullableText $PhaseId
        correctionId = Get-NullableText $CorrectionId
        reviewRequestId = Get-NullableText $ReviewRequestId
        reviewAttemptId = Get-NullableText $ReviewAttemptId
        reviewKind = Get-NullableText $ReviewKind
        reviewAttemptOrdinal = $ReviewAttemptOrdinal
        supersedesReviewAttemptId = Get-NullableText $SupersedesReviewAttemptId
        eventType = $EventType
        occurredAtUtc = $OccurredAtUtc
        revision = Get-NullableText $Revision
        reviewMode = $ReviewMode
        provenance = [ordered]@{ source = 'synthetic_fixture'; observedBy = 'validator'; coverage = 'fixed UTC fixture'; synthetic = $true }
        usage = $Usage
        waitId = Get-NullableText $WaitId
        waitKind = Get-NullableText $WaitKind
        pullRequest = $null
    }
    return [pscustomobject] $event
}

function New-UsageSample {
    param(
        [Parameter(Mandatory)] [string] $StreamId,
        [Parameter(Mandatory)] [string] $Role,
        [Parameter(Mandatory)] [string] $SessionId,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $SampledAtUtc,
        [Parameter(Mandatory)] [string] $BaselineAtUtc,
        [Parameter(Mandatory)] [object] $Counters,
        [AllowNull()] [object] $CounterSemantics = $null
    )

    if ($null -eq $CounterSemantics) {
        $CounterSemantics = [ordered]@{ cachedInput = 'included_in_input'; reasoning = 'included_in_output' }
    }
    return [pscustomobject][ordered]@{
        state = 'measured'
        streamId = $StreamId
        role = $Role
        sessionId = $SessionId
        source = $Source
        counterSemantics = $CounterSemantics
        coverage = 'synthetic exact boundary'
        sampledAtUtc = $SampledAtUtc
        baselineAtUtc = $BaselineAtUtc
        counters = $Counters
    }
}

function Write-EventsThroughRecorder {
    param(
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object[]] $Events,
        [Parameter(Mandatory)] [string] $RecorderPath
    )

    foreach ($event in $Events) {
        $eventJson = $event | ConvertTo-Json -Compress -Depth 20
        & pwsh -NoProfile -File $RecorderPath -ExternalRunRoot $ExternalRoot -RunId $RunId -EventJson $eventJson | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "recorder should accept event $($event.eventId)"
    }
    return Join-Path (Join-Path $ExternalRoot $RunId) 'events.jsonl'
}

function Invoke-WorkflowFixture {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Path
    )

    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "missing workflow fixture '$Name'"
    $output = & pwsh -NoProfile -File $Path 2>&1
    $exitCode = $LASTEXITCODE
    $diagnostic = [string]($output -join [Environment]::NewLine)
    Assert-True ($exitCode -eq 0) "workflow fixture '$Name' failed with exit ${exitCode}: $diagnostic"
    return [pscustomobject]@{
        name = $Name
        path = $Path
        exitCode = $exitCode
        output = $diagnostic
    }
}

function Invoke-RecorderEvent {
    param(
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object] $Event,
        [int] $FaultAfterBytes = -1
    )

    $arguments = @(
        '-NoProfile',
        '-File', $RecorderPath,
        '-ExternalRunRoot', $ExternalRoot,
        '-RunId', $RunId,
        '-EventJson', ($Event | ConvertTo-Json -Compress -Depth 20)
    )
    if ($FaultAfterBytes -ge 0) {
        $arguments += @('-FaultAfterBytes', [string] $FaultAfterBytes)
    }
    $output = & pwsh @arguments 2>&1
    $jsonLines = @($output | ForEach-Object { [string] $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-True ($jsonLines.Count -gt 0) "recorder invocation for $($Event.eventId) must return a JSON result"
    $result = $null
    try {
        $result = $jsonLines[-1] | ConvertFrom-Json -Depth 50 -DateKind String
    }
    catch {
        throw "recorder invocation for $($Event.eventId) returned non-JSON output '$($jsonLines[-1])'"
    }
    return [pscustomobject]@{
        ExitCode = [int] $LASTEXITCODE
        Result = $result
        Output = $jsonLines
    }
}

function Invoke-AutomaticReviewMeasurementScenario {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $TracePath,
        [int] $FaultAfterBytes = -1
    )

    $arguments = @(
        '-NoProfile',
        '-File', $Path,
        '-MeasurementExternalRunRoot', $ExternalRoot,
        '-MeasurementRunId', $RunId,
        '-MeasurementTracePath', $TracePath
    )
    if ($FaultAfterBytes -ge 0) {
        $arguments += @('-MeasurementFaultAfterBytes', [string]$FaultAfterBytes)
    }
    $output = & pwsh @arguments 2>&1
    $exitCode = [int]$LASTEXITCODE
    $diagnostic = [string]($output -join [Environment]::NewLine)
    Assert-True ($exitCode -eq 0) "automatic review measurement fixture '$RunId' failed with exit ${exitCode}: $diagnostic"
    Assert-True (Test-Path -LiteralPath $TracePath -PathType Leaf) "automatic review measurement fixture '$RunId' must write a trace"
    try {
        return [IO.File]::ReadAllText($TracePath) | ConvertFrom-Json -Depth 50 -DateKind String
    }
    catch {
        throw "automatic review measurement fixture '$RunId' wrote invalid trace JSON: $($_.Exception.Message)"
    }
}

function New-UsageWindowEvents {
    param(
        [Parameter(Mandatory)] [int] $TaskRef,
        [Parameter(Mandatory)] [string] $PhaseId,
        [Parameter(Mandatory)] [string] $StartUtc,
        [Parameter(Mandatory)] [string] $EndUtc,
        [Parameter(Mandatory)] [object] $StartUsage,
        [Parameter(Mandatory)] [object] $EndUsage,
        [Parameter(Mandatory)] [string] $Revision
    )

    return @(
        (New-Event -EventId ("usage-safety-{0}-start" -f $TaskRef) -EventType 'implementation_started' -OccurredAtUtc $StartUtc -Scope 'task' -TaskRef $TaskRef -PhaseId $PhaseId -Role 'implementer' -SessionId ([string] $StartUsage.sessionId) -Usage $StartUsage),
        (New-Event -EventId ("usage-safety-{0}-end" -f $TaskRef) -EventType 'task_ready_for_review' -OccurredAtUtc $EndUtc -Scope 'task' -TaskRef $TaskRef -PhaseId $PhaseId -Revision $Revision -Role 'implementer' -SessionId ([string] $EndUsage.sessionId) -Usage $EndUsage)
    )
}

$usageSafetyCaseNumber = 0
function Invoke-UsageSafetyReport {
    param(
        [Parameter(Mandatory)] [object[]] $WindowEvents,
        [Parameter(Mandatory)] [int[]] $TaskRefs,
        [switch] $PreserveEventSession
    )

    $script:usageSafetyCaseNumber++
    $runId = "synthetic-usage-safety-$script:usageSafetyCaseNumber"
    $storyStart = New-Event -EventId "usage-safety-$script:usageSafetyCaseNumber-story-start" -EventType 'story_started' -OccurredAtUtc '2026-10-09T10:00:00Z' -Scope 'story' -Role 'coordinator'
    $prReady = New-Event -EventId "usage-safety-$script:usageSafetyCaseNumber-pr-ready" -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T10:10:00Z' -Scope 'story' -Revision $revisionA -Role 'coordinator'
    $prReady.pullRequest = [ordered]@{ provider = 'github'; owner = 'blakeg83'; repository = 'taiga-mcp'; number = 153; reviewedHead = $revisionA }
    $flattenedWindowEvents = [System.Collections.Generic.List[object]]::new()
    foreach ($windowEvent in @($WindowEvents)) {
        foreach ($event in @($windowEvent)) { [void] $flattenedWindowEvents.Add($event) }
    }
    $events = @($storyStart) + @($flattenedWindowEvents.ToArray()) + @($prReady)
    foreach ($event in $events) {
        $event.runId = $runId
        if ($null -ne $event.usage -and -not $PreserveEventSession) {
            $usageSession = Get-NullableText $event.usage.sessionId
            if ($null -ne $usageSession) { $event.sessionId = $usageSession }
        }
    }
    $ledger = Write-EventsThroughRecorder -ExternalRoot $recorderRoot -RunId $runId -Events $events -RecorderPath $recorderPath
    $json = & $scriptPath -EventsPath $ledger -ReviewMode per_task -TaskRefs $TaskRefs
    Assert-True ($LASTEXITCODE -eq 0) "usage safety case $script:usageSafetyCaseNumber should aggregate successfully"
    return ($json | ConvertFrom-Json -Depth 100)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-story145-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$ledger = Join-Path $root 'per-task.jsonl'
$storyEndLedger = Join-Path $root 'story-end-only.jsonl'
$edgeLedger = Join-Path $root 'edge-cases.jsonl'
$finalRetryPerTaskLedger = Join-Path $root 'final-retry-per-task.jsonl'
$privacyLedger = Join-Path $root 'privacy.jsonl'
$utfLedger = Join-Path $root 'invalid-utf8.jsonl'
$orphanLedger = Join-Path $root 'orphan-order.jsonl'
$overlapLedger = Join-Path $root 'overlap-cases.jsonl'
$usageLedger = Join-Path $root 'usage-and-comparison.jsonl'
$usageSafetyLedger = Join-Path $root 'usage-safety-cases.jsonl'
$scriptPath = Join-Path $PSScriptRoot 'get-story-performance.ps1'
$recorderPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\.agents\skills\taiga-story-loop\scripts\write-performance-event.ps1'))
$recorderRoot = Join-Path $root 'external-ledgers'

try {
    $revisionA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $revisionB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $events = @(
        (New-Event -EventId 'story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-09T10:00:00Z' -Scope 'story' -Role 'coordinator'),
        (New-Event -EventId 'impl-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T10:05:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-impl' -Role 'implementer'),
        (New-Event -EventId 'impl-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T10:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-impl' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:20:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-review' -ReviewRequestId 'task-152-request-1' -ReviewAttemptId 'task-152-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:25:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-review' -ReviewRequestId 'task-152-request-1' -ReviewAttemptId 'task-152-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'task-153-initial-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:26:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-initial' -ReviewRequestId 'task-153-request-1' -ReviewAttemptId 'task-153-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'task-153-initial-findings' -EventType 'review_findings' -OccurredAtUtc '2026-10-09T10:29:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-initial' -ReviewRequestId 'task-153-request-1' -ReviewAttemptId 'task-153-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'correction-start' -EventType 'correction_started' -OccurredAtUtc '2026-10-09T10:30:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-correction' -CorrectionId 'task-153-correction' -SupersedesReviewAttemptId 'task-153-attempt-1' -Role 'implementer'),
        (New-Event -EventId 'correction-ready' -EventType 'correction_ready' -OccurredAtUtc '2026-10-09T10:40:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-correction' -CorrectionId 'task-153-correction' -SupersedesReviewAttemptId 'task-153-attempt-1' -Revision $revisionB -Role 'implementer'),
        (New-Event -EventId 'rereview-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:45:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-rereview' -ReviewRequestId 'task-153-request-2' -ReviewAttemptId 'task-153-attempt-2' -ReviewKind 'correction_rereview' -ReviewAttemptOrdinal 1 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'rereview-findings' -EventType 'review_findings' -OccurredAtUtc '2026-10-09T10:50:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-rereview' -ReviewRequestId 'task-153-request-2' -ReviewAttemptId 'task-153-attempt-2' -ReviewKind 'correction_rereview' -ReviewAttemptOrdinal 1 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:51:00Z' -Scope 'story' -WaitId 'story-wait-1' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T10:53:00Z' -Scope 'story' -WaitId 'story-wait-1' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'pr-ready' -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T11:00:00Z' -Scope 'story' -Revision $revisionB -Role 'coordinator')
    )
    $events[-1].pullRequest = [ordered]@{ provider = 'github'; owner = 'blakeg83'; repository = 'taiga-mcp'; number = 143; reviewedHead = $revisionB }
    $ledger = Write-EventsThroughRecorder -ExternalRoot $recorderRoot -RunId 'synthetic-task-152' -Events $events -RecorderPath $recorderPath
    $reviewReplay = New-Event -EventId 'review-start-replay' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:20:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-review' -ReviewRequestId 'task-152-request-1' -ReviewAttemptId 'task-152-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'
    $reviewReplay.transitionId = 'review-start'
    [void] (Write-EventsThroughRecorder -ExternalRoot $recorderRoot -RunId 'synthetic-task-152' -Events @($reviewReplay) -RecorderPath $recorderPath)
    [IO.File]::AppendAllText($ledger, (($events[3] | ConvertTo-Json -Compress -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $foreign = New-Event -EventId 'foreign-event' -EventType 'story_started' -OccurredAtUtc '2026-10-09T09:58:00Z' -Scope 'story' -Role 'coordinator'
    $foreign.runId = 'foreign-run'
    $foreign.storyId = 999
    $foreign.storyRef = 999
    $foreignPhase = New-Event -EventId 'foreign-phase' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:58:10Z' -Scope 'task' -TaskRef 998 -PhaseId 'foreign-phase' -Role 'implementer'
    $foreignReview = New-Event -EventId 'foreign-review' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:58:20Z' -Scope 'task' -TaskRef 998 -PhaseId 'foreign-review' -ReviewRequestId 'foreign-request' -ReviewAttemptId 'foreign-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'
    $foreignWait = New-Event -EventId 'foreign-wait' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:58:30Z' -Scope 'story' -WaitId 'foreign-wait' -WaitKind 'reviewer' -Role 'coordinator'
    $foreignPr = New-Event -EventId 'foreign-pr' -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T09:58:40Z' -Scope 'story' -Revision $revisionA -Role 'coordinator'
    $foreignPr.pullRequest = [ordered]@{ provider = 'github'; owner = 'foreign'; repository = 'foreign'; number = 998; reviewedHead = $revisionA }
    $foreignRecords = @($foreign, $foreignPhase, $foreignReview, $foreignWait, $foreignPr)
    foreach ($foreignRecord in $foreignRecords) {
        $foreignRecord.runId = 'foreign-run'
        $foreignRecord.projectId = 99
        $foreignRecord.storyId = 998
        $foreignRecord.storyRef = 998
    }
    $foreignLines = @($foreignRecords | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join [Environment]::NewLine
    $invalidLine = '{"eventId":"invalid-review","eventType":"review_accepted","occurredAtUtc":"2026-10-09T09:59:00Z"}'
    [IO.File]::AppendAllText($ledger, $foreignLines + [Environment]::NewLine + $invalidLine + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

    $jsonText = & $scriptPath -EventsPath $ledger -ReviewMode per_task -TaskRefs @(152, 153)
    Assert-True ($LASTEXITCODE -eq 0) 'per-task aggregator should exit successfully'
    $report = $jsonText | ConvertFrom-Json -Depth 100
    Assert-True ([int64]$report.metrics.timeToPr.value -eq 3600000) 'timeToPr should use direct UTC boundaries'
    Assert-True ([int64]$report.metrics.implementationElapsed.value -eq 1200000) 'implementationElapsed should sum implementation and correction intervals'
    Assert-True ([int64]$report.metrics.reviewElapsed.value -eq 780000) 'reviewElapsed should sum distinct review attempts'
    Assert-True ([string]$report.metrics.coordinationElapsed.state -eq 'measured' -and [int64]$report.metrics.coordinationElapsed.value -eq 120000) 'coordinationElapsed should use explicit coordinator-owned waits'
    Assert-True ([int64]$report.metrics.waitingElapsed.value -eq 120000) 'waitingElapsed should measure explicit wait boundaries'
    Assert-True ([int]$report.metrics.initialTaskReviews.value -eq 2) 'duplicate review start should count one initial task review per observed task'
    Assert-True ([int]$report.metrics.correctionReReviews.value -eq 1) 'correction re-review should count one attempt'
    Assert-True (@($report.reviewAttempts).Count -eq 3) 'request/attempt identities should produce three distinct review attempts'
    Assert-True (@($report.reviewAttempts | Select-Object -ExpandProperty reviewRequestId -Unique).Count -eq 3) 'review requests should remain attributable separately'
    Assert-True ([int]$report.metrics.firstPassAcceptanceRate.numerator -eq 1 -and [int]$report.metrics.firstPassAcceptanceRate.denominator -eq 2) 'first-pass numerator and denominator should be explicit'
    Assert-True ([string]$report.metrics.firstPassAcceptanceRate.state -eq 'measured' -and [double]$report.metrics.firstPassAcceptanceRate.value -eq 0.5) 'first-pass rate should be measured from authoritative acceptance'
    Assert-True (@($report.anomalies | Where-Object { $_.code -eq 'duplicate_event' }).Count -eq 1) 'exact replay should be disclosed'
    Assert-True (@($report.anomalies | Where-Object { $_.code -eq 'foreign_binding' }).Count -eq 5) 'foreign phase, review, wait, and PR evidence should be quarantined'
    Assert-True (@($report.anomalies | Where-Object { $_.code -eq 'invalid_event' }).Count -eq 1) 'invalid review evidence should be excluded'
    Assert-True ([string]$report.metrics.initialTaskReviews.state -eq 'measured') 'declared task coverage should be measured'
    Assert-True ([int]$report.coverage.validEventCount -eq 15) 'valid event count should exclude foreign and invalid records'
    Assert-True (@($report.anomalies | Where-Object { $_.code -eq 'duplicate_or_stale_review' }).Count -eq 1) 'same review identity with the same immutable payload should be disclosed as a replay'
    Assert-True ([string]$report.coverage.taskSet.state -eq 'measured' -and @($report.coverage.taskSet.declaredTaskRefs).Count -eq 2) 'declared task coverage should remain explicit and ordered'
    Assert-True ([string]$report.coverage.uncoveredStorySpan.state -eq 'partial' -and @($report.coverage.uncoveredStorySpan.value).Count -gt 0) 'uncovered story-span gaps should be reported explicitly'
    Assert-True ([string]$report.metrics.implementationTokens.state -eq 'unavailable' -and $null -eq $report.metrics.implementationTokens.value) 'missing implementer usage must remain unavailable rather than zero'
    Assert-True ([string]$report.metrics.totalTokens.state -eq 'unavailable' -and $null -eq $report.metrics.totalTokens.value) 'missing role usage must keep total tokens unavailable'
    Assert-True ([string]$report.metrics.modelsAndReasoning.state -eq 'unavailable') 'unproven model and reasoning profiles must remain unavailable'
    Assert-True ([string]$report.metrics.changedFiles.state -eq 'unavailable') 'comparison stats must remain unavailable without an explicit base revision'

    $comparisonHead = ([string] (& git rev-parse HEAD)).Trim()
    Assert-True ($comparisonHead -match '^[0-9a-f]{40}$') 'comparison fixture requires the current full Git HEAD'
    $comparisonBase = ([string] (& git rev-parse HEAD~1)).Trim()
    Assert-True ($comparisonBase -match '^[0-9a-f]{40}$') 'comparison fixture requires an exact parent Git base'
    $includedSemantics = [ordered]@{ cachedInput = 'included_in_input'; reasoning = 'included_in_output' }
    $disjointSemantics = [ordered]@{ cachedInput = 'disjoint_from_input'; reasoning = 'disjoint_from_output' }
    $usageImplStart = [ordered]@{
        state = 'measured'; streamId = 'usage-impl-stream'; role = 'implementer'; sessionId = 'usage-impl-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'exact implementation boundary'; sampledAtUtc = '2026-10-09T09:00:00Z'; baselineAtUtc = '2026-10-09T09:00:00Z'
        counters = [ordered]@{ inputTokens = 100; cachedInputTokens = 40; outputTokens = 20; reasoningTokens = 5 }
    }
    $usageImplEnd = [ordered]@{
        state = 'measured'; streamId = 'usage-impl-stream'; role = 'implementer'; sessionId = 'usage-impl-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'exact implementation boundary'; sampledAtUtc = '2026-10-09T09:10:00Z'; baselineAtUtc = '2026-10-09T09:00:00Z'
        counters = [ordered]@{ inputTokens = 145; cachedInputTokens = 70; outputTokens = 30; reasoningTokens = 8 }
    }
    $usageReviewStart = [ordered]@{
        state = 'measured'; streamId = 'usage-review-stream'; role = 'reviewer'; sessionId = 'usage-review-session'; source = 'synthetic-task153'
        counterSemantics = $disjointSemantics; coverage = 'exact review boundary'; sampledAtUtc = '2026-10-09T09:15:00Z'; baselineAtUtc = '2026-10-09T09:15:00Z'
        counters = [ordered]@{ inputTokens = 200; cachedInputTokens = 50; outputTokens = 100; reasoningTokens = 20 }
    }
    $usageReviewEnd = [ordered]@{
        state = 'measured'; streamId = 'usage-review-stream'; role = 'reviewer'; sessionId = 'usage-review-session'; source = 'synthetic-task153'
        counterSemantics = $disjointSemantics; coverage = 'exact review boundary'; sampledAtUtc = '2026-10-09T09:25:00Z'; baselineAtUtc = '2026-10-09T09:15:00Z'
        counters = [ordered]@{ inputTokens = 230; cachedInputTokens = 60; outputTokens = 130; reasoningTokens = 35 }
    }
    $usageWaitStart = [ordered]@{
        state = 'measured'; streamId = 'usage-coordinator-stream'; role = 'coordinator'; sessionId = 'usage-coordinator-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'exact wait boundary'; sampledAtUtc = '2026-10-09T09:30:00Z'; baselineAtUtc = '2026-10-09T09:30:00Z'
        counters = [ordered]@{ inputTokens = 10; cachedInputTokens = 2; outputTokens = 1; reasoningTokens = 0 }
    }
    $usageWaitEnd = [ordered]@{
        state = 'measured'; streamId = 'usage-coordinator-stream'; role = 'coordinator'; sessionId = 'usage-coordinator-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'exact wait boundary'; sampledAtUtc = '2026-10-09T09:35:00Z'; baselineAtUtc = '2026-10-09T09:30:00Z'
        counters = [ordered]@{ inputTokens = 15; cachedInputTokens = 7; outputTokens = 4; reasoningTokens = 1 }
    }
    $usageEvents = @(
        (New-Event -EventId 'usage-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-09T08:55:00Z' -Scope 'story' -Role 'coordinator'),
        (New-Event -EventId 'usage-impl-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:00:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-impl' -Role 'implementer' -SessionId 'usage-impl-session' -Usage $usageImplStart),
        (New-Event -EventId 'usage-impl-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T09:10:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-impl' -Revision $comparisonHead -Role 'implementer' -SessionId 'usage-impl-session' -Usage $usageImplEnd),
        (New-Event -EventId 'usage-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-review' -ReviewRequestId 'usage-review-request' -ReviewAttemptId 'usage-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -SessionId 'usage-review-session' -Usage $usageReviewStart),
        (New-Event -EventId 'usage-review-start-replay' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-review' -ReviewRequestId 'usage-review-request' -ReviewAttemptId 'usage-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -SessionId 'usage-review-session' -Usage $usageReviewStart),
        (New-Event -EventId 'usage-review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:25:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-review' -ReviewRequestId 'usage-review-request' -ReviewAttemptId 'usage-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -SessionId 'usage-review-session' -Usage $usageReviewEnd),
        (New-Event -EventId 'usage-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:30:00Z' -Scope 'story' -WaitId 'usage-wait' -WaitKind 'reviewer' -Role 'coordinator' -SessionId 'usage-coordinator-session' -Usage $usageWaitStart),
        (New-Event -EventId 'usage-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:35:00Z' -Scope 'story' -WaitId 'usage-wait' -WaitKind 'reviewer' -Role 'coordinator' -SessionId 'usage-coordinator-session' -Usage $usageWaitEnd),
        (New-Event -EventId 'usage-pr-ready' -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T09:40:00Z' -Scope 'story' -Revision $comparisonHead -Role 'coordinator')
    )
    $usageEvents[4].transitionId = $usageEvents[3].transitionId
    foreach ($usageEvent in $usageEvents) {
        $usageEvent.runId = 'synthetic-usage-153'
        $usageSession = if ($null -ne $usageEvent.usage) { Get-NullableText $usageEvent.usage.sessionId } else { $null }
        if ($null -ne $usageSession) { $usageEvent.sessionId = $usageSession }
    }
    $usageEvents[-1].pullRequest = [ordered]@{ provider = 'github'; owner = 'blakeg83'; repository = 'taiga-mcp'; number = 153; reviewedHead = $comparisonHead }
    $usageLedger = Write-EventsThroughRecorder -ExternalRoot $recorderRoot -RunId 'synthetic-usage-153' -Events $usageEvents -RecorderPath $recorderPath
    $usageJson = & $scriptPath -EventsPath $usageLedger -ReviewMode per_task -TaskRefs @(152) -BaseRevision $comparisonBase -ReviewedHead $comparisonHead -RepositoryPath (Get-Location).Path
    Assert-True ($LASTEXITCODE -eq 0) 'source-backed usage and comparison fixture should aggregate successfully'
    $usageReport = $usageJson | ConvertFrom-Json -Depth 100
    Assert-True ([string]$usageReport.metrics.implementationTokens.state -eq 'measured' -and [int64]$usageReport.metrics.implementationTokens.value -eq 55) 'included cached-input and reasoning counters must not be double-counted'
    Assert-True ([string]$usageReport.metrics.reviewTokens.state -eq 'measured' -and [int64]$usageReport.metrics.reviewTokens.value -eq 85) 'disjoint cached-input and reasoning counters must be included exactly once'
    Assert-True ([string]$usageReport.metrics.coordinationTokens.state -eq 'measured' -and [int64]$usageReport.metrics.coordinationTokens.value -eq 8) 'coordinator usage must use explicit wait boundaries'
    Assert-True ([string]$usageReport.metrics.totalTokens.state -eq 'measured' -and [int64]$usageReport.metrics.totalTokens.value -eq 148) 'total tokens must sum measured role subtotals only'
    Assert-True ([string]$usageReport.metrics.tasksCompleted.state -eq 'measured' -and [int]$usageReport.metrics.tasksCompleted.value -eq 1) 'tasksCompleted must count accepted declared task identities'
    Assert-True ([string]$usageReport.metrics.changedFiles.state -eq 'measured' -and [int]$usageReport.metrics.changedFiles.value -gt 0 -and [int]$usageReport.metrics.linesAdded.value -gt 0 -and [int]$usageReport.metrics.linesDeleted.value -ge 0) 'comparison metrics must use the exact base-to-reviewed-head Git diff'
    Assert-True ([string]$usageReport.metrics.modelsAndReasoning.state -eq 'unavailable') 'model and reasoning profiles must not be inferred from usage stream metadata'
    Assert-True (@($usageReport.anomalies | Where-Object { $_.code -eq 'duplicate_or_stale_review' }).Count -eq 1) 'duplicate usage-bearing review snapshots must not create a second review attempt'

    $usageReset = [ordered]@{
        state = 'measured'; streamId = 'usage-reset-stream'; role = 'implementer'; sessionId = 'usage-reset-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'reset fixture'; sampledAtUtc = '2026-10-09T10:00:00Z'; baselineAtUtc = '2026-10-09T10:00:00Z'
        counters = [ordered]@{ inputTokens = 100; outputTokens = 20 }
    }
    $usageResetEnd = [ordered]@{
        state = 'measured'; streamId = 'usage-reset-stream'; role = 'implementer'; sessionId = 'usage-reset-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'reset fixture'; sampledAtUtc = '2026-10-09T10:10:00Z'; baselineAtUtc = '2026-10-09T10:00:00Z'
        counters = [ordered]@{ inputTokens = 90; outputTokens = 25 }
    }
    $usageWorkerStart = [ordered]@{
        state = 'measured'; streamId = 'usage-worker-stream'; role = 'implementer'; sessionId = 'usage-worker-session-1'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'worker-change fixture'; sampledAtUtc = '2026-10-09T10:30:00Z'; baselineAtUtc = '2026-10-09T10:30:00Z'
        counters = [ordered]@{ inputTokens = 300; outputTokens = 40 }
    }
    $usageWorkerEnd = [ordered]@{
        state = 'measured'; streamId = 'usage-worker-stream'; role = 'implementer'; sessionId = 'usage-worker-session-2'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'worker-change fixture'; sampledAtUtc = '2026-10-09T10:40:00Z'; baselineAtUtc = '2026-10-09T10:30:00Z'
        counters = [ordered]@{ inputTokens = 320; outputTokens = 45 }
    }
    $usageMissingStart = [ordered]@{
        state = 'measured'; streamId = 'usage-missing-stream'; role = 'reviewer'; sessionId = 'usage-missing-session'; source = 'synthetic-task153'
        counterSemantics = $includedSemantics; coverage = 'missing-boundary fixture'; sampledAtUtc = '2026-10-09T10:15:00Z'; baselineAtUtc = '2026-10-09T10:15:00Z'
        counters = [ordered]@{ inputTokens = 400; outputTokens = 50 }
    }
    $usagePartialEvents = @(
        (New-Event -EventId 'usage-partial-impl-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T10:00:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-reset' -Role 'implementer' -SessionId 'usage-reset-session' -Usage $usageReset),
        (New-Event -EventId 'usage-partial-impl-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T10:10:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-reset' -Revision $comparisonHead -Role 'implementer' -SessionId 'usage-reset-session' -Usage $usageResetEnd),
        (New-Event -EventId 'usage-partial-worker-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T10:30:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-worker-change' -Role 'implementer' -SessionId 'usage-worker-session-1' -Usage $usageWorkerStart),
        (New-Event -EventId 'usage-partial-worker-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T10:40:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-worker-change' -Revision $comparisonHead -Role 'implementer' -SessionId 'usage-worker-session-2' -Usage $usageWorkerEnd),
        (New-Event -EventId 'usage-partial-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-missing' -ReviewRequestId 'usage-missing-request' -ReviewAttemptId 'usage-missing-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -SessionId 'usage-missing-session' -Usage $usageMissingStart),
        (New-Event -EventId 'usage-partial-review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:25:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-missing' -ReviewRequestId 'usage-missing-request' -ReviewAttemptId 'usage-missing-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer')
    )
    foreach ($partialEvent in $usagePartialEvents) {
        $partialEvent.runId = 'synthetic-usage-153-partial'
        $usageSession = if ($null -ne $partialEvent.usage) { Get-NullableText $partialEvent.usage.sessionId } else { $null }
        if ($null -ne $usageSession) { $partialEvent.sessionId = $usageSession }
    }
    [IO.File]::WriteAllLines($usageLedger, @($usagePartialEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $partialJson = & $scriptPath -EventsPath $usageLedger -ReviewMode per_task -TaskRefs @(152)
    Assert-True ($LASTEXITCODE -eq 0) 'partial usage fixture should aggregate without inventing totals'
    $partialReport = $partialJson | ConvertFrom-Json -Depth 100
    Assert-True ([string]$partialReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $partialReport.metrics.implementationTokens.value) 'counter reset must make implementation token coverage partial with null total'
    Assert-True ([string]$partialReport.metrics.reviewTokens.state -eq 'partial' -and $null -eq $partialReport.metrics.reviewTokens.value) 'missing review usage boundary must remain partial with null total'
    Assert-True (@($partialReport.anomalies | Where-Object { $_.code -eq 'usage_counter_reset' }).Count -eq 1 -and @($partialReport.anomalies | Where-Object { $_.code -eq 'usage_stream_conflict' }).Count -eq 1 -and @($partialReport.anomalies | Where-Object { $_.code -eq 'usage_missing_boundary' }).Count -eq 1) 'reset, worker/session changes, and missing usage boundaries must be disclosed explicitly'

    $duplicateStart = New-UsageSample -StreamId 'safety-same-stream' -Role 'implementer' -SessionId 'safety-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $duplicateEnd = New-UsageSample -StreamId 'safety-same-stream' -Role 'implementer' -SessionId 'safety-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $duplicateReport = Invoke-UsageSafetyReport -TaskRefs @(200, 201) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 200 -PhaseId 'safety-duplicate-a' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $duplicateStart -EndUsage $duplicateEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 201 -PhaseId 'safety-duplicate-b' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $duplicateStart -EndUsage $duplicateEnd -Revision $revisionA)
    )
    Assert-True ([string]$duplicateReport.metrics.implementationTokens.state -eq 'measured' -and [int64]$duplicateReport.metrics.implementationTokens.value -eq 60) 'identical cumulative windows must count once rather than double-counting overlapping tasks'
    Assert-True (@($duplicateReport.metrics.implementationTokens.evidence | Where-Object { $_.countable -eq $false -and $null -ne $_.duplicateOf }).Count -eq 1) 'identical usage windows must retain duplicate linkage in evidence'
    Assert-True (@($duplicateReport.anomalies | Where-Object { $_.code -eq 'duplicate_usage_window' }).Count -eq 1) 'identical usage windows must disclose deduplication'

    $nestedOuterStart = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $nestedOuterEnd = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:03:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 160; outputTokens = 20 })
    $nestedInnerStart = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:01:30Z' -BaselineAtUtc '2026-10-09T10:01:30Z' -Counters ([ordered]@{ inputTokens = 120; outputTokens = 12 })
    $nestedInnerEnd = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:30Z' -Counters ([ordered]@{ inputTokens = 140; outputTokens = 16 })
    $partialStart = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:04:00Z' -BaselineAtUtc '2026-10-09T10:04:00Z' -Counters ([ordered]@{ inputTokens = 200; outputTokens = 30 })
    $partialEnd = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:06:00Z' -BaselineAtUtc '2026-10-09T10:04:00Z' -Counters ([ordered]@{ inputTokens = 260; outputTokens = 40 })
    $partialInnerStart = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:05:00Z' -BaselineAtUtc '2026-10-09T10:05:00Z' -Counters ([ordered]@{ inputTokens = 240; outputTokens = 35 })
    $partialInnerEnd = New-UsageSample -StreamId 'safety-overlap-stream' -Role 'implementer' -SessionId 'safety-overlap-session' -Source 'safety-overlap-source' -SampledAtUtc '2026-10-09T10:07:00Z' -BaselineAtUtc '2026-10-09T10:05:00Z' -Counters ([ordered]@{ inputTokens = 280; outputTokens = 50 })
    $overlapReport = Invoke-UsageSafetyReport -TaskRefs @(202, 203, 204, 205) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 202 -PhaseId 'safety-nested-outer' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:03:00Z' -StartUsage $nestedOuterStart -EndUsage $nestedOuterEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 203 -PhaseId 'safety-nested-inner' -StartUtc '2026-10-09T10:01:30Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $nestedInnerStart -EndUsage $nestedInnerEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 204 -PhaseId 'safety-partial-a' -StartUtc '2026-10-09T10:04:00Z' -EndUtc '2026-10-09T10:06:00Z' -StartUsage $partialStart -EndUsage $partialEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 205 -PhaseId 'safety-partial-b' -StartUtc '2026-10-09T10:05:00Z' -EndUtc '2026-10-09T10:07:00Z' -StartUsage $partialInnerStart -EndUsage $partialInnerEnd -Revision $revisionA)
    )
    Assert-True ([string]$overlapReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $overlapReport.metrics.implementationTokens.value) 'nested and partly overlapping windows must not be summed'
    $overlapUsageDiagnostics = @($overlapReport.anomalies | Where-Object { $_.code -eq 'overlapping_usage_window' })
    Assert-True ($overlapUsageDiagnostics.Count -eq 2) "nested and partly overlapping windows must each disclose ambiguity (actual=$($overlapUsageDiagnostics.Count))"

    $disjointAStart = New-UsageSample -StreamId 'safety-disjoint-a' -Role 'implementer' -SessionId 'safety-session-a' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 10; outputTokens = 2 })
    $disjointAEnd = New-UsageSample -StreamId 'safety-disjoint-a' -Role 'implementer' -SessionId 'safety-session-a' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 15; outputTokens = 5 })
    $disjointBStart = New-UsageSample -StreamId 'safety-disjoint-b' -Role 'implementer' -SessionId 'safety-session-a' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 20; outputTokens = 3 })
    $disjointBEnd = New-UsageSample -StreamId 'safety-disjoint-b' -Role 'implementer' -SessionId 'safety-session-a' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 30; outputTokens = 8 })
    $disjointReport = Invoke-UsageSafetyReport -TaskRefs @(206, 207) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 206 -PhaseId 'safety-disjoint-a' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $disjointAStart -EndUsage $disjointAEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 207 -PhaseId 'safety-disjoint-b' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $disjointBStart -EndUsage $disjointBEnd -Revision $revisionA)
    )
    Assert-True ([string]$disjointReport.metrics.implementationTokens.state -eq 'measured' -and [int64]$disjointReport.metrics.implementationTokens.value -eq 23) 'disjoint usage streams must sum independently even when times overlap'

    $sourceAStart = New-UsageSample -StreamId 'safety-source-stream' -Role 'implementer' -SessionId 'safety-source-session' -Source 'safety-source-a' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 10; outputTokens = 2 })
    $sourceAEnd = New-UsageSample -StreamId 'safety-source-stream' -Role 'implementer' -SessionId 'safety-source-session' -Source 'safety-source-a' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 15; outputTokens = 5 })
    $sourceBStart = New-UsageSample -StreamId 'safety-source-stream-b' -Role 'implementer' -SessionId 'safety-source-session' -Source 'safety-source-b' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 10; outputTokens = 2 })
    $sourceBEnd = New-UsageSample -StreamId 'safety-source-stream-b' -Role 'implementer' -SessionId 'safety-source-session' -Source 'safety-source-b' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 15; outputTokens = 5 })
    $sourceReport = Invoke-UsageSafetyReport -TaskRefs @(208, 209) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 208 -PhaseId 'safety-source-a' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $sourceAStart -EndUsage $sourceAEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 209 -PhaseId 'safety-source-b' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $sourceBStart -EndUsage $sourceBEnd -Revision $revisionA)
    )
    Assert-True ([string]$sourceReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $sourceReport.metrics.implementationTokens.value) 'overlapping alternative sources must not be treated as additive streams'
    Assert-True (@($sourceReport.anomalies | Where-Object { $_.code -eq 'overlapping_usage_window' }).Count -eq 1) 'overlapping alternative sources must disclose ambiguity'

    $sessionStart = New-UsageSample -StreamId 'safety-session-stream' -Role 'implementer' -SessionId 'safety-session-source' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $sessionEnd = New-UsageSample -StreamId 'safety-session-stream' -Role 'implementer' -SessionId 'safety-session-source' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $changedEventSession = New-UsageWindowEvents -TaskRef 216 -PhaseId 'safety-event-session-change' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $sessionStart -EndUsage $sessionEnd -Revision $revisionA
    $changedEventSession[1].sessionId = 'other-event-session'
    $missingEventSession = New-UsageWindowEvents -TaskRef 217 -PhaseId 'safety-event-session-missing' -StartUtc '2026-10-09T10:03:00Z' -EndUtc '2026-10-09T10:04:00Z' -StartUsage $sessionStart -EndUsage $sessionEnd -Revision $revisionA
    $missingEventSession[1].sessionId = $null
    $sessionReport = Invoke-UsageSafetyReport -TaskRefs @(216, 217) -PreserveEventSession -WindowEvents @($changedEventSession, $missingEventSession)
    Assert-True ([string]$sessionReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $sessionReport.metrics.implementationTokens.value) 'contradictory or missing event-session provenance must not establish a measured usage total'
    Assert-True (@($sessionReport.anomalies | Where-Object { $_.code -eq 'usage_stream_conflict' }).Count -ge 2) 'event-session changes and missing identity must be disclosed'

    $unprovenStart = New-UsageSample -StreamId 'safety-unproven-stream' -Role 'implementer' -SessionId 'safety-unproven-session' -Source 'mcp__codex_app__get_usage_limits' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $unprovenEnd = New-UsageSample -StreamId 'safety-unproven-stream' -Role 'implementer' -SessionId 'safety-unproven-session' -Source 'mcp__codex_app__get_usage_limits' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $unprovenEvents = New-UsageWindowEvents -TaskRef 218 -PhaseId 'safety-unproven-source' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $unprovenStart -EndUsage $unprovenEnd -Revision $revisionA
    $unprovenEvents[0].provenance.synthetic = $false
    $unprovenEvents[1].provenance.synthetic = $false
    $unprovenReport = Invoke-UsageSafetyReport -TaskRefs @(218) -WindowEvents $unprovenEvents
    Assert-True ([string]$unprovenReport.metrics.implementationTokens.state -eq 'unavailable' -and $null -eq $unprovenReport.metrics.implementationTokens.value) 'self-declared account-limit usage must remain unavailable without an authorized attributable capability'
    Assert-True (@($unprovenReport.anomalies | Where-Object { $_.code -eq 'usage_source_unavailable' }).Count -eq 1) 'unproven usage source must be disclosed'

    $resetStart = New-UsageSample -StreamId 'safety-reset-stream' -Role 'implementer' -SessionId 'safety-reset-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $resetMiddle = New-UsageSample -StreamId 'safety-reset-stream' -Role 'implementer' -SessionId 'safety-reset-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:30Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 5; outputTokens = 1 })
    $resetEnd = New-UsageSample -StreamId 'safety-reset-stream' -Role 'implementer' -SessionId 'safety-reset-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $resetMiddleEvent = New-Event -EventId 'usage-safety-reset-middle' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:01:30Z' -Scope 'task' -TaskRef 210 -WaitId 'usage-safety-reset-middle' -WaitKind 'synthetic' -Role 'implementer' -Usage $resetMiddle
    $resetReport = Invoke-UsageSafetyReport -TaskRefs @(210) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 210 -PhaseId 'safety-reset' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $resetStart -EndUsage $resetEnd -Revision $revisionA),
        $resetMiddleEvent
    )
    Assert-True ([string]$resetReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $resetReport.metrics.implementationTokens.value) 'an intermediate reset followed by recovery must make the whole usage window partial'
    Assert-True (@($resetReport.anomalies | Where-Object { $_.code -eq 'usage_counter_reset' }).Count -ge 1) 'intermediate reset must be disclosed'

    $conflictStart = New-UsageSample -StreamId 'safety-conflict-stream' -Role 'implementer' -SessionId 'safety-conflict-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $conflictMiddleA = New-UsageSample -StreamId 'safety-conflict-stream' -Role 'implementer' -SessionId 'safety-conflict-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:30Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 120; outputTokens = 12 })
    $conflictMiddleB = New-UsageSample -StreamId 'safety-conflict-stream' -Role 'implementer' -SessionId 'safety-conflict-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:30Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 121; outputTokens = 12 })
    $conflictEnd = New-UsageSample -StreamId 'safety-conflict-stream' -Role 'implementer' -SessionId 'safety-conflict-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $conflictReport = Invoke-UsageSafetyReport -TaskRefs @(211) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 211 -PhaseId 'safety-conflict' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $conflictStart -EndUsage $conflictEnd -Revision $revisionA),
        (New-Event -EventId 'usage-safety-conflict-middle-a' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:01:30Z' -Scope 'task' -TaskRef 211 -WaitId 'usage-safety-conflict-a' -WaitKind 'synthetic' -Role 'implementer' -Usage $conflictMiddleA),
        (New-Event -EventId 'usage-safety-conflict-middle-b' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:01:30Z' -Scope 'task' -TaskRef 211 -WaitId 'usage-safety-conflict-b' -WaitKind 'synthetic' -Role 'implementer' -Usage $conflictMiddleB)
    )
    Assert-True ([string]$conflictReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $conflictReport.metrics.implementationTokens.value) 'same-time conflicting usage samples must not choose an arbitrary sequence'
    Assert-True (@($conflictReport.anomalies | Where-Object { $_.code -eq 'usage_intermediate_conflict' }).Count -ge 1) 'same-time conflicting usage samples must be disclosed'

    $missingMiddle = New-UsageSample -StreamId 'safety-missing-middle-stream' -Role 'implementer' -SessionId 'safety-missing-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:30Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 120 })
    $missingStart = New-UsageSample -StreamId 'safety-missing-middle-stream' -Role 'implementer' -SessionId 'safety-missing-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $missingEnd = New-UsageSample -StreamId 'safety-missing-middle-stream' -Role 'implementer' -SessionId 'safety-missing-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $missingReport = Invoke-UsageSafetyReport -TaskRefs @(212) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 212 -PhaseId 'safety-missing-middle' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $missingStart -EndUsage $missingEnd -Revision $revisionA),
        (New-Event -EventId 'usage-safety-missing-middle' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:01:30Z' -Scope 'task' -TaskRef 212 -WaitId 'usage-safety-missing-middle' -WaitKind 'synthetic' -Role 'implementer' -Usage $missingMiddle)
    )
    Assert-True ([string]$missingReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $missingReport.metrics.implementationTokens.value) 'missing required intermediate counters must make the whole usage window partial'
    Assert-True (@($missingReport.anomalies | Where-Object { $_.code -eq 'usage_missing_intermediate_counter' }).Count -ge 1) 'missing intermediate counters must be disclosed'

    $workerStart = New-UsageSample -StreamId 'safety-worker-stream' -Role 'implementer' -SessionId 'safety-worker-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $workerEnd = New-UsageSample -StreamId 'safety-worker-stream' -Role 'implementer' -SessionId 'safety-worker-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $workerEvents = New-UsageWindowEvents -TaskRef 213 -PhaseId 'safety-worker-change' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:00Z' -StartUsage $workerStart -EndUsage $workerEnd -Revision $revisionA
    $workerEvents[0].workerId = 'worker-a'
    $workerEvents[1].workerId = 'worker-b'
    $workerReport = Invoke-UsageSafetyReport -TaskRefs @(213) -WindowEvents $workerEvents
    Assert-True ([string]$workerReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $workerReport.metrics.implementationTokens.value) 'worker-only changes must invalidate usage attribution even when session and counters continue'
    Assert-True (@($workerReport.anomalies | Where-Object { $_.code -eq 'usage_stream_conflict' }).Count -ge 1) 'worker-only changes must be disclosed'

    $windowStart = New-UsageSample -StreamId 'safety-window-before' -Role 'implementer' -SessionId 'safety-window-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T09:59:00Z' -BaselineAtUtc '2026-10-09T09:59:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $windowEnd = New-UsageSample -StreamId 'safety-window-before' -Role 'implementer' -SessionId 'safety-window-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T09:59:00Z' -Counters ([ordered]@{ inputTokens = 150; outputTokens = 20 })
    $postStart = New-UsageSample -StreamId 'safety-window-after' -Role 'implementer' -SessionId 'safety-post-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:09:00Z' -BaselineAtUtc '2026-10-09T10:09:00Z' -Counters ([ordered]@{ inputTokens = 200; outputTokens = 30 })
    $postEnd = New-UsageSample -StreamId 'safety-window-after' -Role 'implementer' -SessionId 'safety-post-session' -Source 'safety-source' -SampledAtUtc '2026-10-09T10:11:00Z' -BaselineAtUtc '2026-10-09T10:09:00Z' -Counters ([ordered]@{ inputTokens = 250; outputTokens = 40 })
    $windowReport = Invoke-UsageSafetyReport -TaskRefs @(214, 215) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 214 -PhaseId 'safety-window-before' -StartUtc '2026-10-09T09:59:00Z' -EndUtc '2026-10-09T10:01:00Z' -StartUsage $windowStart -EndUsage $windowEnd -Revision $revisionA),
        (New-UsageWindowEvents -TaskRef 215 -PhaseId 'safety-window-after' -StartUtc '2026-10-09T10:09:00Z' -EndUtc '2026-10-09T10:11:00Z' -StartUsage $postStart -EndUsage $postEnd -Revision $revisionA)
    )
    Assert-True ([string]$windowReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $windowReport.metrics.implementationTokens.value) 'usage intervals before or after the measured story run must remain partial'
    Assert-True (@($windowReport.anomalies | Where-Object { $_.code -eq 'usage_interval_outside_run' }).Count -eq 2) 'before-start and post-PR straddling intervals must disclose run-window violations'
    Assert-True (@($windowReport.anomalies | Where-Object { $_.code -eq 'usage_sample_after_run' }).Count -eq 1) 'post-PR samples must be disclosed'

    $boundaryStart = New-UsageSample -StreamId 'safety-boundary-even' -Role 'implementer' -SessionId 'safety-boundary-session' -Source 'safety-boundary-source' -SampledAtUtc '2026-10-09T10:01:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 100; outputTokens = 10 })
    $boundaryMiddleA = New-UsageSample -StreamId 'safety-boundary-even' -Role 'implementer' -SessionId 'safety-boundary-session' -Source 'safety-boundary-source' -SampledAtUtc '2026-10-09T10:01:30Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 110; outputTokens = 12 })
    $boundaryMiddleB = New-UsageSample -StreamId 'safety-boundary-even' -Role 'implementer' -SessionId 'safety-boundary-session' -Source 'safety-boundary-source' -SampledAtUtc '2026-10-09T10:02:00Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 120; outputTokens = 14 })
    $boundaryEnd = New-UsageSample -StreamId 'safety-boundary-even' -Role 'implementer' -SessionId 'safety-boundary-session' -Source 'safety-boundary-source' -SampledAtUtc '2026-10-09T10:02:30Z' -BaselineAtUtc '2026-10-09T10:01:00Z' -Counters ([ordered]@{ inputTokens = 160; outputTokens = 22 })
    $boundaryReport = Invoke-UsageSafetyReport -TaskRefs @(219) -WindowEvents @(
        (New-UsageWindowEvents -TaskRef 219 -PhaseId 'safety-boundary-even' -StartUtc '2026-10-09T10:01:00Z' -EndUtc '2026-10-09T10:02:30Z' -StartUsage $boundaryStart -EndUsage $boundaryEnd -Revision $revisionA),
        (New-Event -EventId 'usage-safety-boundary-middle-a' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:01:30Z' -Scope 'task' -TaskRef 219 -WaitId 'usage-safety-boundary-a' -WaitKind 'synthetic' -Role 'implementer' -Usage $boundaryMiddleA),
        (New-Event -EventId 'usage-safety-boundary-middle-b' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:02:00Z' -Scope 'task' -TaskRef 219 -WaitId 'usage-safety-boundary-b' -WaitKind 'synthetic' -Role 'implementer' -Usage $boundaryMiddleB)
    )
    Assert-True ([string]$boundaryReport.metrics.implementationTokens.state -eq 'measured' -and [int64]$boundaryReport.metrics.implementationTokens.value -eq 72) 'even-sized usage index exact first/interior/last boundaries remain measured'

    $finalRetryPerTaskEvents = @(
        (New-Event -EventId 'per-task-final-story-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T11:30:00Z' -Scope 'final_story' -PhaseId 'per-task-final-1' -ReviewRequestId 'per-task-final-request' -ReviewAttemptId 'per-task-final-attempt-1' -ReviewKind 'final_story' -ReviewAttemptOrdinal 1 -Revision $revisionB -ReviewMode 'per_task' -Role 'reviewer'),
        (New-Event -EventId 'per-task-final-story-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T11:31:00Z' -Scope 'final_story' -PhaseId 'per-task-final-1' -ReviewRequestId 'per-task-final-request' -ReviewAttemptId 'per-task-final-attempt-1' -ReviewKind 'final_story' -ReviewAttemptOrdinal 1 -Revision $revisionB -ReviewMode 'per_task' -Role 'reviewer'),
        (New-Event -EventId 'per-task-final-story-retry-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T11:32:00Z' -Scope 'final_story' -PhaseId 'per-task-final-2' -ReviewRequestId 'per-task-final-request' -ReviewAttemptId 'per-task-final-attempt-2' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 2 -Revision $revisionB -ReviewMode 'per_task' -Role 'reviewer'),
        (New-Event -EventId 'per-task-final-story-retry-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T11:33:00Z' -Scope 'final_story' -PhaseId 'per-task-final-2' -ReviewRequestId 'per-task-final-request' -ReviewAttemptId 'per-task-final-attempt-2' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 2 -Revision $revisionB -ReviewMode 'per_task' -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($finalRetryPerTaskLedger, @($finalRetryPerTaskEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $finalRetryPerTaskJson = & $scriptPath -EventsPath $finalRetryPerTaskLedger -ReviewMode per_task
    Assert-True ($LASTEXITCODE -eq 0) 'per-task final-story retry fixture should aggregate successfully'
    $finalRetryPerTask = $finalRetryPerTaskJson | ConvertFrom-Json -Depth 100
    Assert-True ([int]$finalRetryPerTask.metrics.finalStoryReviews.value -eq 2 -and [int]$finalRetryPerTask.metrics.finalStoryReReviews.value -eq 1) 'per_task must count a first final-story request retry that changes only attempt classification'
    Assert-True (@($finalRetryPerTask.anomalies | Where-Object { $_.code -eq 'conflicting_review_request' }).Count -eq 0) 'per_task first final-story retry must not rebind its request'

    $privacyStart = New-Event -EventId 'privacy-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-09T08:00:00Z' -Scope 'story' -Role 'coordinator'
    $privacyPr = New-Event -EventId 'privacy-pr-ready' -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T08:01:00Z' -Scope 'story' -Revision $revisionA -Role 'coordinator'
    $privacyPr.pullRequest = [ordered]@{ provider = 'github'; owner = 'blakeg83'; repository = 'taiga-mcp'; number = 152; reviewedHead = $revisionA; secret = 'SYNTHETIC-PR-SECRET' }
    [IO.File]::WriteAllLines($privacyLedger, @($privacyStart, $privacyPr | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $privacyJson = & $scriptPath -EventsPath $privacyLedger -ReviewMode per_task
    Assert-True ($LASTEXITCODE -eq 0) 'privacy fixture should retain the valid non-PR event'
    $privacy = $privacyJson | ConvertFrom-Json -Depth 100
    Assert-True ([int]$privacy.coverage.validEventCount -eq 1 -and $null -eq $privacy.pullRequest) 'unallowlisted PR metadata should be excluded before report projection'
    Assert-True (-not ([string]$privacyJson).Contains('SYNTHETIC-PR-SECRET')) 'unallowlisted PR marker must not be echoed'
    Assert-True (@($privacy.anomalies | Where-Object { $_.code -eq 'invalid_event' }).Count -eq 1) 'unallowlisted PR metadata should be diagnosed safely'

    $utfStart = New-Event -EventId 'utf8-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-09T08:10:00Z' -Scope 'story' -Role 'coordinator'
    $utfValidBytes = [Text.UTF8Encoding]::new($false).GetBytes(($utfStart | ConvertTo-Json -Compress -Depth 20) + [Environment]::NewLine)
    $utfBytes = [System.Collections.Generic.List[byte]]::new()
    $utfBytes.AddRange($utfValidBytes)
    [void] $utfBytes.Add([byte] 0xC3)
    [void] $utfBytes.Add([byte] 0x28)
    [void] $utfBytes.Add([byte] 0x0A)
    [IO.File]::WriteAllBytes($utfLedger, $utfBytes.ToArray())
    $utfJson = & $scriptPath -EventsPath $utfLedger -ReviewMode per_task
    Assert-True ($LASTEXITCODE -eq 0) 'strict UTF-8 fixture should retain valid records'
    $utf = $utfJson | ConvertFrom-Json -Depth 100
    Assert-True ([int]$utf.coverage.validEventCount -eq 1 -and @($utf.anomalies | Where-Object { $_.code -eq 'invalid_utf8' }).Count -eq 1) 'invalid UTF-8 records should be excluded with a safe diagnostic'

    $orphanEvents = @(
        (New-Event -EventId 'orphan-order-story' -EventType 'story_started' -OccurredAtUtc '2026-10-09T08:20:00Z' -Scope 'story' -Role 'coordinator')
    )
    for ($orphanIndex = 0; $orphanIndex -lt 8; $orphanIndex++) {
        $orphanEvents += New-Event -EventId ("orphan-order-{0}" -f $orphanIndex) -EventType 'review_accepted' -OccurredAtUtc ("2026-10-09T08:{0:00}:00Z" -f (21 + $orphanIndex)) -Scope 'task' -TaskRef (200 + $orphanIndex) -PhaseId ("orphan-phase-{0}" -f $orphanIndex) -ReviewRequestId ("orphan-request-{0}" -f $orphanIndex) -ReviewAttemptId ("orphan-attempt-{0}" -f $orphanIndex) -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'
    }
    [IO.File]::WriteAllLines($orphanLedger, @($orphanEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $freshOutputs = [System.Collections.Generic.List[string]]::new()
    for ($processIndex = 0; $processIndex -lt 4; $processIndex++) {
        $freshOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $orphanLedger -ReviewMode per_task
        Assert-True ($LASTEXITCODE -eq 0) "fresh process $processIndex should aggregate orphan diagnostics"
        [void] $freshOutputs.Add([string] ($freshOutput -join ''))
    }
    Assert-True (@($freshOutputs | Select-Object -Unique).Count -eq 1) 'fresh processes should produce byte-stable anomaly ordering'

    $storyEndEvents = @(
        (New-Event -EventId 'story-end-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-09T11:55:00Z' -Scope 'story' -ReviewMode 'per_task' -Role 'coordinator'),
        (New-Event -EventId 'story-end-final-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T12:00:00Z' -Scope 'final_story' -PhaseId 'final-1' -ReviewRequestId 'final-request-1' -ReviewAttemptId 'final-attempt-1' -ReviewKind 'final_story' -ReviewAttemptOrdinal 1 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-final-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T12:10:00Z' -Scope 'final_story' -PhaseId 'final-1' -ReviewRequestId 'final-request-1' -ReviewAttemptId 'final-attempt-1' -ReviewKind 'final_story' -ReviewAttemptOrdinal 1 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-rereview-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T12:20:00Z' -Scope 'final_story' -PhaseId 'final-2' -ReviewRequestId 'final-request-1' -ReviewAttemptId 'final-attempt-2' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 2 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-rereview-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T12:30:00Z' -Scope 'final_story' -PhaseId 'final-2' -ReviewRequestId 'final-request-1' -ReviewAttemptId 'final-attempt-2' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 2 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-rereview-retry-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T12:40:00Z' -Scope 'final_story' -PhaseId 'final-3' -ReviewRequestId 'final-request-2' -ReviewAttemptId 'final-attempt-3' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 3 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-rereview-retry-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T12:50:00Z' -Scope 'final_story' -PhaseId 'final-3' -ReviewRequestId 'final-request-2' -ReviewAttemptId 'final-attempt-3' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 3 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($storyEndLedger, @($storyEndEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $storyEndJson = & $scriptPath -EventsPath $storyEndLedger -ReviewMode story_end_only
    Assert-True ($LASTEXITCODE -eq 0) 'story-end-only aggregator should exit successfully'
    $storyEnd = $storyEndJson | ConvertFrom-Json -Depth 100
    Assert-True ([int]$storyEnd.metrics.initialTaskReviews.value -eq 0 -and [int]$storyEnd.metrics.correctionReReviews.value -eq 0) 'story_end_only must have zero per-task and correction reviews'
    Assert-True ([int]$storyEnd.metrics.finalStoryReviews.value -eq 3 -and [int]$storyEnd.metrics.finalStoryReReviews.value -eq 2) 'story_end_only final review and same-request same-SHA retries remain countable'
    Assert-True (@($storyEnd.anomalies | Where-Object { $_.code -eq 'conflicting_review_request' }).Count -eq 0) 'story_end_only first final-story retry must not rebind its request'
    Assert-True ([string]$storyEnd.metrics.firstPassAcceptanceRate.state -eq 'not_applicable') 'story_end_only first-pass denominator is not applicable'
    Assert-True (@($storyEnd.anomalies | Where-Object { $_.code -eq 'conflicting_review_mode' }).Count -eq 1) 'conflicting event review modes should be disclosed'

    $edgeEvents = @(
        (New-Event -EventId 'edge-missing-end' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:00:00Z' -Scope 'task' -TaskRef 160 -PhaseId 'edge-missing' -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-a-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:00:00Z' -Scope 'task' -TaskRef 161 -PhaseId 'edge-overlap-a' -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-a-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T09:10:00Z' -Scope 'task' -TaskRef 161 -PhaseId 'edge-overlap-a' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-b-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:05:00Z' -Scope 'task' -TaskRef 162 -PhaseId 'edge-overlap-b' -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-b-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T09:15:00Z' -Scope 'task' -TaskRef 162 -PhaseId 'edge-overlap-b' -Revision $revisionB -Role 'implementer'),
        (New-Event -EventId 'edge-reversed-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:20:00Z' -Scope 'task' -TaskRef 163 -PhaseId 'edge-review' -ReviewRequestId 'edge-request' -ReviewAttemptId 'edge-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-reversed-review-end' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:19:00Z' -Scope 'task' -TaskRef 163 -PhaseId 'edge-review' -ReviewRequestId 'edge-request' -ReviewAttemptId 'edge-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-overlap-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:05:30Z' -Scope 'task' -TaskRef 164 -PhaseId 'edge-overlap-review' -ReviewRequestId 'edge-overlap-request' -ReviewAttemptId 'edge-overlap-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-overlap-review-end' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:07:30Z' -Scope 'task' -TaskRef 164 -PhaseId 'edge-overlap-review' -ReviewRequestId 'edge-overlap-request' -ReviewAttemptId 'edge-overlap-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-conflict-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:40:00Z' -Scope 'task' -TaskRef 165 -PhaseId 'edge-conflict-review' -ReviewRequestId 'edge-conflict-request' -ReviewAttemptId 'edge-conflict-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-conflict-review-start-replay' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:40:30Z' -Scope 'task' -TaskRef 165 -PhaseId 'edge-conflict-review-replay' -ReviewRequestId 'edge-conflict-request' -ReviewAttemptId 'edge-conflict-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-conflict-review-end-a' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:41:00Z' -Scope 'task' -TaskRef 165 -PhaseId 'edge-conflict-review' -ReviewRequestId 'edge-conflict-request' -ReviewAttemptId 'edge-conflict-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-conflict-review-end-b' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:42:00Z' -Scope 'task' -TaskRef 165 -PhaseId 'edge-conflict-review' -ReviewRequestId 'edge-conflict-request' -ReviewAttemptId 'edge-conflict-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-before-correction-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:55:00Z' -Scope 'task' -TaskRef 166 -PhaseId 'edge-before-correction-review' -ReviewRequestId 'edge-before-correction-request' -ReviewAttemptId 'edge-before-correction-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-before-correction-started' -EventType 'correction_started' -OccurredAtUtc '2026-10-09T09:56:00Z' -Scope 'task' -TaskRef 166 -PhaseId 'edge-before-correction-phase' -CorrectionId 'edge-before-correction' -SupersedesReviewAttemptId 'edge-before-correction-attempt' -Role 'implementer'),
        (New-Event -EventId 'edge-before-correction-ready' -EventType 'correction_ready' -OccurredAtUtc '2026-10-09T09:56:00Z' -Scope 'task' -TaskRef 166 -PhaseId 'edge-before-correction-phase' -CorrectionId 'edge-before-correction' -SupersedesReviewAttemptId 'edge-before-correction-attempt' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'edge-before-correction-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:57:00Z' -Scope 'task' -TaskRef 166 -PhaseId 'edge-before-correction-review' -ReviewRequestId 'edge-before-correction-request' -ReviewAttemptId 'edge-before-correction-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-mixed-closure-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:00:00Z' -Scope 'task' -TaskRef 167 -PhaseId 'edge-mixed-closure' -ReviewRequestId 'edge-mixed-request' -ReviewAttemptId 'edge-mixed-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-mixed-closure-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:01:00Z' -Scope 'task' -TaskRef 167 -PhaseId 'edge-mixed-closure' -ReviewRequestId 'edge-mixed-request' -ReviewAttemptId 'edge-mixed-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-mixed-closure-mismatched' -EventType 'review_findings' -OccurredAtUtc '2026-10-09T10:02:00Z' -Scope 'task' -TaskRef 167 -PhaseId 'edge-mixed-closure' -ReviewRequestId 'edge-mixed-request' -ReviewAttemptId 'edge-mixed-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'edge-cross-task-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:10:00Z' -Scope 'task' -TaskRef 168 -WaitId 'edge-cross-task-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-cross-task-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T10:11:00Z' -Scope 'task' -TaskRef 169 -WaitId 'edge-cross-task-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-kind-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:12:00Z' -Scope 'task' -TaskRef 170 -WaitId 'edge-kind-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-kind-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T10:13:00Z' -Scope 'task' -TaskRef 170 -WaitId 'edge-kind-wait' -WaitKind 'different-kind' -Role 'coordinator'),
        (New-Event -EventId 'edge-role-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:14:00Z' -Scope 'task' -TaskRef 171 -WaitId 'edge-role-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-role-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T10:15:00Z' -Scope 'task' -TaskRef 171 -WaitId 'edge-role-wait' -WaitKind 'reviewer' -Role 'implementer'),
        (New-Event -EventId 'edge-rebound-start-1' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:30:00Z' -Scope 'task' -TaskRef 172 -PhaseId 'edge-rebound-1' -ReviewRequestId 'edge-rebound-request-1' -ReviewAttemptId 'edge-rebound-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-rebound-end-1' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:31:00Z' -Scope 'task' -TaskRef 172 -PhaseId 'edge-rebound-1' -ReviewRequestId 'edge-rebound-request-1' -ReviewAttemptId 'edge-rebound-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-rebound-start-2' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:32:00Z' -Scope 'task' -TaskRef 172 -PhaseId 'edge-rebound-2' -ReviewRequestId 'edge-rebound-request-2' -ReviewAttemptId 'edge-rebound-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-rebound-end-2' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:33:00Z' -Scope 'task' -TaskRef 172 -PhaseId 'edge-rebound-2' -ReviewRequestId 'edge-rebound-request-2' -ReviewAttemptId 'edge-rebound-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-request-rebind-start-1' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:40:00Z' -Scope 'task' -TaskRef 173 -PhaseId 'edge-request-rebind-1' -ReviewRequestId 'edge-request-rebind' -ReviewAttemptId 'edge-request-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-request-rebind-end-1' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:41:00Z' -Scope 'task' -TaskRef 173 -PhaseId 'edge-request-rebind-1' -ReviewRequestId 'edge-request-rebind' -ReviewAttemptId 'edge-request-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-request-rebind-start-2' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:42:00Z' -Scope 'task' -TaskRef 173 -PhaseId 'edge-request-rebind-2' -ReviewRequestId 'edge-request-rebind' -ReviewAttemptId 'edge-request-attempt-2' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 2 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'edge-request-rebind-end-2' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:43:00Z' -Scope 'task' -TaskRef 173 -PhaseId 'edge-request-rebind-2' -ReviewRequestId 'edge-request-rebind' -ReviewAttemptId 'edge-request-attempt-2' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 2 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'edge-reversed-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:30:00Z' -Scope 'story' -WaitId 'edge-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-reversed-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:29:00Z' -Scope 'story' -WaitId 'edge-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-overlap-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:07:00Z' -Scope 'story' -WaitId 'edge-overlap-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-overlap-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:08:00Z' -Scope 'story' -WaitId 'edge-overlap-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'orphan-closure' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:59:00Z' -Scope 'task' -TaskRef 999 -PhaseId 'orphan' -ReviewRequestId 'orphan-request' -ReviewAttemptId 'orphan-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($edgeLedger, @($edgeEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    [IO.File]::AppendAllText($edgeLedger, '{"eventId":"interrupted-tail"', [Text.UTF8Encoding]::new($false))
    $edgeJson = & $scriptPath -EventsPath $edgeLedger -ReviewMode per_task -TaskRefs @(160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173)
    Assert-True ($LASTEXITCODE -eq 0) 'edge-case aggregator should exit successfully with incomplete evidence'
    $edge = $edgeJson | ConvertFrom-Json -Depth 100
    Assert-True ([string]$edge.metrics.implementationElapsed.state -eq 'partial' -and [int64]$edge.metrics.implementationElapsed.value -eq 1200000) 'missing implementation boundary should keep valid overlap totals partial and explicit'
    Assert-True ([string]$edge.metrics.reviewElapsed.state -eq 'partial' -and [int64]$edge.metrics.reviewElapsed.value -eq 240000) 'valid review overlap should be retained while reversed and conflicting attempts remain partial'
    Assert-True ([string]$edge.metrics.waitingElapsed.state -eq 'partial' -and [int64]$edge.metrics.waitingElapsed.value -eq 60000) 'valid wait overlap should be retained while the reversed wait remains partial'
    Assert-True ([string]$edge.metrics.coordinationElapsed.state -eq 'partial' -and [int64]$edge.metrics.coordinationElapsed.value -eq 60000) 'coordinationElapsed should remain partial when coordinator wait attribution is incomplete'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'missing_boundary' }).Count -ge 1) 'missing boundary should be diagnosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'overlapping_intervals' }).Count -ge 1) 'cross-category overlap clusters should be disclosed rather than subtracted'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'negative_interval' }).Count -ge 2) 'impossible reversed review and wait sequences should be diagnosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_review_start' }).Count -eq 1) 'changed review-start payload should be disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_review_closure' }).Count -eq 1) 'changed review-closure payload should be disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_review_identity' }).Count -ge 1) 'matching plus mismatched review closure evidence should be partial and disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_review_attempt' }).Count -eq 1) 'reusing an attempt identity under another request should be disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_review_request' }).Count -eq 1) 'reusing a request identity for another revision should be disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_boundary' }).Count -ge 2) 'changed wait kind and actor attribution should be disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'undeclared_task_evidence' }).Count -eq 1) 'undeclared task evidence should be quarantined'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'incomplete_tail' }).Count -eq 1) 'an interrupted non-newline tail should be excluded and diagnosed'
    Assert-True (@($edge.coverage.taskSet.missingInitialReviewTaskRefs).Count -eq 7) 'per-task coverage should name declared tasks without initial review evidence'
    Assert-True ([string]$edge.metrics.firstPassAcceptanceRate.state -eq 'partial' -and [int]$edge.metrics.firstPassAcceptanceRate.denominator -eq 7) 'first-pass coverage should remain partial when attempt rebinding evidence is ambiguous'
    Assert-True ([int]$edge.coverage.validEventCount -eq 38) 'task filtering should retain only valid records before aggregation'

    $overlapEvents = @(
        (New-Event -EventId 'overlap-disjoint-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T08:00:00Z' -Scope 'task' -TaskRef 180 -PhaseId 'overlap-disjoint' -Role 'implementer'),
        (New-Event -EventId 'overlap-disjoint-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T08:01:00Z' -Scope 'task' -TaskRef 180 -PhaseId 'overlap-disjoint' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'overlap-gap-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T08:02:00Z' -Scope 'task' -TaskRef 181 -PhaseId 'overlap-gap' -Role 'implementer'),
        (New-Event -EventId 'overlap-gap-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T08:03:00Z' -Scope 'task' -TaskRef 181 -PhaseId 'overlap-gap' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'overlap-touch-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T08:03:00Z' -Scope 'task' -TaskRef 182 -PhaseId 'overlap-touch' -Role 'implementer'),
        (New-Event -EventId 'overlap-touch-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T08:04:00Z' -Scope 'task' -TaskRef 182 -PhaseId 'overlap-touch' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'overlap-zero-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T08:05:00Z' -Scope 'task' -TaskRef 183 -PhaseId 'overlap-zero' -Role 'implementer'),
        (New-Event -EventId 'overlap-zero-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T08:05:00Z' -Scope 'task' -TaskRef 183 -PhaseId 'overlap-zero' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'overlap-nested-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T08:00:30Z' -Scope 'task' -TaskRef 184 -PhaseId 'overlap-nested' -Role 'implementer'),
        (New-Event -EventId 'overlap-nested-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T08:00:45Z' -Scope 'task' -TaskRef 184 -PhaseId 'overlap-nested' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'overlap-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T08:00:30Z' -Scope 'task' -TaskRef 185 -PhaseId 'overlap-review' -ReviewRequestId 'overlap-review-request' -ReviewAttemptId 'overlap-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'overlap-review-end' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T08:00:40Z' -Scope 'task' -TaskRef 185 -PhaseId 'overlap-review' -ReviewRequestId 'overlap-review-request' -ReviewAttemptId 'overlap-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($overlapLedger, @($overlapEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $overlapJson = & $scriptPath -EventsPath $overlapLedger -ReviewMode per_task -TaskRefs @(180, 181, 182, 183, 184, 185)
    Assert-True ($LASTEXITCODE -eq 0) 'exact overlap fixture should aggregate successfully'
    $overlap = $overlapJson | ConvertFrom-Json -Depth 100
    $overlapDiagnostics = @($overlap.anomalies | Where-Object { $_.code -eq 'overlapping_intervals' })
    Assert-True ($overlapDiagnostics.Count -eq 1) 'one connected overlap cluster should be disclosed; disjoint, touching, and zero-duration intervals should not'

    $artifactRoot = Join-Path $root 'published-reports'
    $artifactJsonA = Join-Path $artifactRoot 'report-a.json'
    $artifactMarkdownA = Join-Path $artifactRoot 'report-a.md'
    $artifactJsonB = Join-Path $artifactRoot 'report-b.json'
    $artifactMarkdownB = Join-Path $artifactRoot 'report-b.md'
    $artifactManifestA = "$artifactJsonA.complete.json"
    $artifactManifestB = "$artifactJsonB.complete.json"
    $metadataPath = Join-Path $root 'setup-metadata.json'
    $metadataJsonPath = Join-Path $artifactRoot 'metadata.json'
    $metadataMarkdownPath = Join-Path $artifactRoot 'metadata.md'
    $invalidMetadataPath = Join-Path $root 'invalid-setup-metadata.json'
    $invalidMetadataOutputPath = Join-Path $artifactRoot 'invalid-metadata.json'
    $changedLedger = Join-Path $root 'changed-head.jsonl'

    $setupMetadata = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_setup'
        runId = 'synthetic-task-152'
        projectId = 12
        storyId = 727
        profiles = @(
            [ordered]@{
                role = 'coordinator'; workerId = 'synthetic-coordinator'; sessionId = 'synthetic-coordinator-session'; model = 'gpt-6.1-sol'; effort = 'high'; effectiveFromUtc = '2026-10-09T09:59:00Z'; effectiveToUtc = '2026-10-09T10:30:00Z'; changeId = 'coordinator-initial';
                provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'synthetic-validator'; coverage = 'exact assignment interval'; synthetic = $true }
            }
            [ordered]@{
                role = 'implementer'; workerId = 'synthetic-implementer'; sessionId = 'synthetic-implementer-session'; model = 'gpt-5.6-luna'; effort = 'xhigh'; effectiveFromUtc = '2026-10-09T10:00:00Z'; effectiveToUtc = $null; changeId = 'implementer-profile-change-1';
                provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'synthetic-validator'; coverage = 'exact assignment interval'; synthetic = $true }
            }
        )
        provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'synthetic-validator'; coverage = 'complete setup fixture'; synthetic = $true }
    }
    [IO.File]::WriteAllText($metadataPath, ($setupMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

    $oneProfileMetadataPath = Join-Path $root 'one-profile-setup-metadata.json'
    $oneProfileOutputPath = Join-Path $artifactRoot 'one-profile.json'
    $oneProfileMetadata = $setupMetadata | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
    $oneProfileMetadata.profiles = @($oneProfileMetadata.profiles[0])
    [IO.File]::WriteAllText($oneProfileMetadataPath, ($oneProfileMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $oneProfileOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $oneProfileMetadataPath -OutputPath $oneProfileOutputPath 2>&1
    $oneProfileDiagnostic = [string]($oneProfileOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -eq 0) "a one-record profiles array should remain a valid array and publish successfully (diagnostic: $oneProfileDiagnostic)"
    $oneProfileReport = Get-Content -Raw -LiteralPath $oneProfileOutputPath | ConvertFrom-Json -Depth 100
    Assert-True ([string]$oneProfileReport.metrics.modelsAndReasoning.state -ceq 'measured' -and @($oneProfileReport.metrics.modelsAndReasoning.value).Count -eq 1) 'one supplied profile should remain measured'

    $shapeCases = @(
        [ordered]@{ name = 'zero-profiles'; profiles = @() }
        [ordered]@{ name = 'object-profiles'; profiles = $oneProfileMetadata.profiles[0] }
    )
    foreach ($shapeCase in $shapeCases) {
        $shapeMetadataPath = Join-Path $root "$($shapeCase.name)-setup-metadata.json"
        $shapeOutputPath = Join-Path $artifactRoot "$($shapeCase.name).json"
        $shapeMetadata = $setupMetadata | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
        $shapeMetadata.profiles = $shapeCase.profiles
        [IO.File]::WriteAllText($shapeMetadataPath, ($shapeMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        $shapeOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $shapeMetadataPath -OutputPath $shapeOutputPath 2>&1
        $shapeDiagnostic = [string]($shapeOutput -join [Environment]::NewLine)
        Assert-True ($LASTEXITCODE -ne 0 -and $shapeDiagnostic.Contains('setup_metadata_invalid') -and -not (Test-Path -LiteralPath $shapeOutputPath)) "$($shapeCase.name) metadata shape should fail safely"
    }

    $identityCases = @(
        [ordered]@{ name = 'fractional-project'; field = 'projectId'; value = 12.5 }
        [ordered]@{ name = 'string-project'; field = 'projectId'; value = '12' }
        [ordered]@{ name = 'boolean-story'; field = 'storyId'; value = $true }
        [ordered]@{ name = 'out-of-range-story'; field = 'storyId'; value = ([int64]::MaxValue) }
    )
    foreach ($identityCase in $identityCases) {
        $identityMetadataPath = Join-Path $root "$($identityCase.name)-setup-metadata.json"
        $identityOutputPath = Join-Path $artifactRoot "$($identityCase.name).json"
        $identityMetadata = $setupMetadata | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
        $identityMetadata.($identityCase.field) = $identityCase.value
        [IO.File]::WriteAllText($identityMetadataPath, ($identityMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        $identityOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $identityMetadataPath -OutputPath $identityOutputPath 2>&1
        $identityDiagnostic = [string]($identityOutput -join [Environment]::NewLine)
        Assert-True ($LASTEXITCODE -ne 0 -and $identityDiagnostic.Contains('setup_metadata_invalid') -and -not (Test-Path -LiteralPath $identityOutputPath)) "$($identityCase.name) metadata identity should fail safely"
    }

    $invalidUtf8MetadataPath = Join-Path $root 'invalid-utf8-setup-metadata.json'
    $invalidUtf8OutputPath = Join-Path $artifactRoot 'invalid-utf8.json'
    $metadataBytes = [Text.UTF8Encoding]::new($false).GetBytes(($setupMetadata | ConvertTo-Json -Depth 20))
    $markerBytes = [Text.UTF8Encoding]::new($false).GetBytes('gpt-6.1-sol')
    $markerIndex = -1
    for ($byteIndex = 0; $byteIndex -le $metadataBytes.Length - $markerBytes.Length; $byteIndex++) {
        $matchesMarker = $true
        for ($markerOffset = 0; $markerOffset -lt $markerBytes.Length; $markerOffset++) {
            if ($metadataBytes[$byteIndex + $markerOffset] -ne $markerBytes[$markerOffset]) { $matchesMarker = $false; break }
        }
        if ($matchesMarker) { $markerIndex = $byteIndex; break }
    }
    Assert-True ($markerIndex -ge 0) 'invalid UTF-8 fixture should locate its synthetic model marker'
    $metadataBytes[$markerIndex] = 0xFF
    [IO.File]::WriteAllBytes($invalidUtf8MetadataPath, $metadataBytes)
    $invalidUtf8Output = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $invalidUtf8MetadataPath -OutputPath $invalidUtf8OutputPath 2>&1
    $invalidUtf8Diagnostic = [string]($invalidUtf8Output -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0 -and $invalidUtf8Diagnostic.Contains('setup_metadata_invalid') -and -not (Test-Path -LiteralPath $invalidUtf8OutputPath)) 'invalid UTF-8 metadata must fail safely before publication'

    $nonOverlappingChangePath = Join-Path $root 'non-overlapping-profile-change.json'
    $nonOverlappingChangeOutputPath = Join-Path $artifactRoot 'non-overlapping-profile-change.json'
    $nonOverlappingMetadata = $setupMetadata | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
    $initialProfile = $nonOverlappingMetadata.profiles[1] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
    $changedProfile = $nonOverlappingMetadata.profiles[1] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
    $initialProfile.effectiveToUtc = '2026-10-09T10:30:00Z'
    $initialProfile.changeId = 'implementer-initial'
    $changedProfile.model = 'gpt-6.1-sol'
    $changedProfile.effectiveFromUtc = '2026-10-09T10:30:00Z'
    $changedProfile.changeId = 'implementer-change-2'
    $nonOverlappingMetadata.profiles = @($initialProfile, $changedProfile)
    [IO.File]::WriteAllText($nonOverlappingChangePath, ($nonOverlappingMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $nonOverlappingOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $nonOverlappingChangePath -OutputPath $nonOverlappingChangeOutputPath 2>&1
    $nonOverlappingDiagnostic = [string]($nonOverlappingOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -eq 0) "non-overlapping profile changes should remain valid (diagnostic: $nonOverlappingDiagnostic)"
    $nonOverlappingReport = Get-Content -Raw -LiteralPath $nonOverlappingChangeOutputPath | ConvertFrom-Json -Depth 100
    Assert-True ([string]$nonOverlappingReport.metrics.modelsAndReasoning.state -ceq 'measured' -and @($nonOverlappingReport.metrics.modelsAndReasoning.value).Count -eq 2) 'non-overlapping profile changes should remain measured'

    $conflictingProfilePath = Join-Path $root 'conflicting-profile.json'
    $conflictingProfileOutputPath = Join-Path $artifactRoot 'conflicting-profile.json'
    $conflictingMetadata = $setupMetadata | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
    $conflictingProfile = $conflictingMetadata.profiles[1] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 -DateKind String
    $conflictingProfile.model = 'gpt-6.1-sol'
    $conflictingProfile.effectiveFromUtc = '2026-10-09T10:20:00Z'
    $conflictingProfile.changeId = 'conflicting-overlap'
    $conflictingMetadata.profiles = @($conflictingMetadata.profiles[1], $conflictingProfile)
    [IO.File]::WriteAllText($conflictingProfilePath, ($conflictingMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $conflictingProfileOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $conflictingProfilePath -OutputPath $conflictingProfileOutputPath 2>&1
    $conflictingProfileDiagnostic = [string]($conflictingProfileOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0 -and $conflictingProfileDiagnostic.Contains('setup_metadata_conflict') -and -not (Test-Path -LiteralPath $conflictingProfileOutputPath)) 'overlapping conflicting assignments must not be reported as measured'

    $metadataOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $metadataPath -OutputPath $metadataJsonPath -MarkdownPath $metadataMarkdownPath 2>&1
    $metadataDiagnostic = [string]($metadataOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -eq 0) "validated setup metadata should aggregate and publish successfully (diagnostic: $metadataDiagnostic)"
    $metadataReport = Get-Content -Raw -LiteralPath $metadataJsonPath | ConvertFrom-Json -Depth 100
    $metadataMarkdown = Get-Content -Raw -LiteralPath $metadataMarkdownPath
    Assert-True ([string]$metadataReport.metrics.modelsAndReasoning.state -ceq 'measured' -and
        @($metadataReport.metrics.modelsAndReasoning.value).Count -eq 2 -and
        [string]$metadataReport.metrics.modelsAndReasoning.value[1].model -ceq 'gpt-5.6-luna' -and
        [string]$metadataReport.metrics.modelsAndReasoning.value[1].changeId -ceq 'implementer-profile-change-1' -and
        [int]$metadataReport.provenance.setupMetadata.recordCount -eq 2) 'supplied setup profiles and changes must remain source-backed in JSON'
    Assert-True ($metadataMarkdown.Contains('## Role profiles') -and $metadataMarkdown.Contains('model=gpt-6.1-sol') -and $metadataMarkdown.Contains('effort=xhigh') -and $metadataMarkdown.Contains('change=implementer-profile-change-1')) 'supplied setup profiles and changes must render semantically in Markdown'

    $invalidMetadata = $setupMetadata | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $invalidMetadata.profiles[0].provenance.PSObject.Properties.Remove('source')
    [IO.File]::WriteAllText($invalidMetadataPath, ($invalidMetadata | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $invalidMetadataOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -MetadataPath $invalidMetadataPath -OutputPath $invalidMetadataOutputPath 2>&1
    $invalidMetadataDiagnostic = [string]($invalidMetadataOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0 -and $invalidMetadataDiagnostic.Contains('setup_metadata_invalid') -and -not (Test-Path -LiteralPath $invalidMetadataOutputPath)) 'invalid setup provenance must fail safely before publishing'

    $mismatchOutputPath = Join-Path $artifactRoot 'mismatched-head.json'
    $mismatchOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -ReviewedHead $revisionA -OutputPath $mismatchOutputPath 2>&1
    $mismatchDiagnostic = [string]($mismatchOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0 -and $mismatchDiagnostic.Contains('report_identity_conflict') -and -not (Test-Path -LiteralPath $mismatchOutputPath)) 'explicit and PR reviewed HEAD disagreement must fail before publication'

    $missingIdentityDirectory = Join-Path $root 'unconfirmed-artifacts'
    $missingIdentityOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $edgeLedger -ReviewMode per_task -ArtifactDirectory $missingIdentityDirectory 2>&1
    $missingIdentityDiagnostic = [string]($missingIdentityOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0 -and $missingIdentityDiagnostic.Contains('report_identity_unavailable') -and -not (Test-Path -LiteralPath $missingIdentityDirectory)) 'artifact-directory publication must reject missing confirmed PR identity'

    $preflightJsonPath = Join-Path $artifactRoot 'preflight.json'
    $preflightMarkdownDirectory = Join-Path $artifactRoot 'preflight-markdown-directory'
    [IO.Directory]::CreateDirectory($preflightMarkdownDirectory) | Out-Null
    $preflightOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -OutputPath $preflightJsonPath -MarkdownPath $preflightMarkdownDirectory 2>&1
    $preflightDiagnostic = [string]($preflightOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0 -and $preflightDiagnostic.Contains('report_artifact_conflict') -and
        -not (Test-Path -LiteralPath $preflightJsonPath) -and -not (Test-Path -LiteralPath "$preflightJsonPath.complete.json")) 'all destinations must preflight before any report artifact is published'

    $artifactJsonRun = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task -OutputPath $artifactJsonA -MarkdownPath $artifactMarkdownA 2>&1
    $artifactPublicationDiagnostic = [string]($artifactJsonRun -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -eq 0) "artifact publication should aggregate successfully (diagnostic: $artifactPublicationDiagnostic)"
    $publishedArtifact = Get-Content -Raw -LiteralPath $artifactJsonA | ConvertFrom-Json -Depth 100
    $publishedMarkdown = Get-Content -Raw -LiteralPath $artifactMarkdownA
    $publishedManifest = Get-Content -Raw -LiteralPath $artifactManifestA | ConvertFrom-Json -Depth 100
    Assert-True ([int]$publishedArtifact.schemaVersion -eq 1 -and [string]$publishedArtifact.kind -ceq 'story_performance_report' -and
        -not [string]::IsNullOrWhiteSpace([string]$publishedArtifact.reportId)) 'published JSON should carry the versioned report shape and stable identity'
    foreach ($metricProperty in @($publishedArtifact.metrics.PSObject.Properties)) {
        foreach ($metricField in @('state', 'value', 'unit', 'source', 'calculation', 'coverage', 'missingData')) {
            Assert-True ($null -ne $metricProperty.Value.PSObject.Properties[$metricField]) "published metric $($metricProperty.Name) should declare $metricField"
        }
    }
    Assert-True ([string]$publishedArtifact.pullRequest.url -ceq 'https://github.com/blakeg83/taiga-mcp/pull/143') 'published JSON should expose the deterministic PR URL'
    Assert-True ([string]$publishedArtifact.pullRequest.reviewedHead -ceq [string]$publishedArtifact.comparison.reviewedHead) 'JSON PR and comparison HEADs must be frozen to one reviewed revision'
    Assert-True ([string]$publishedManifest.kind -ceq 'story_performance_report_artifact_set' -and
        [string]$publishedManifest.reportId -ceq [string]$publishedArtifact.reportId -and
        [bool]$publishedManifest.confirmed -and @($publishedManifest.artifacts).Count -eq 2) 'completion manifest should bind both artifacts to the canonical report identity'
    $manifestJsonEntry = @($publishedManifest.artifacts | Where-Object { $_.kind -ceq 'json' })[0]
    $manifestMarkdownEntry = @($publishedManifest.artifacts | Where-Object { $_.kind -ceq 'markdown' })[0]
    Assert-True ([string]$manifestJsonEntry.sha256 -ceq (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactJsonA).Hash.ToLowerInvariant() -and
        [string]$manifestMarkdownEntry.sha256 -ceq (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactMarkdownA).Hash.ToLowerInvariant()) 'completion manifest should bind exact artifact bytes'
    Assert-True ($publishedMarkdown.Contains([string]$publishedArtifact.reportId) -and
        $publishedMarkdown.Contains($revisionB) -and
        $publishedMarkdown.Contains('| implementationElapsed |') -and
        $publishedMarkdown.Contains('| modelsAndReasoning |') -and
        $publishedMarkdown.Contains('Source:') -and
        $publishedMarkdown.Contains('limitation=') -and
        $publishedMarkdown.Contains('- Changed files: unknown; state=unavailable') -and
        -not $publishedMarkdown.Contains('@{state=')) 'Markdown should retain identity, reviewed HEAD, metrics, sources, limitations, and clean comparison summaries'
    $artifactJsonBytesBeforeReuse = [IO.File]::ReadAllBytes($artifactJsonA)
    $artifactMarkdownBytesBeforeReuse = [IO.File]::ReadAllBytes($artifactMarkdownA)
    $artifactManifestBytesBeforeReuse = [IO.File]::ReadAllBytes($artifactManifestA)
    $reusedArtifactOutput = & $scriptPath -EventsPath $ledger -ReviewMode per_task -OutputPath $artifactJsonA -MarkdownPath $artifactMarkdownA
    Assert-True ($LASTEXITCODE -eq 0) 'identical artifact publication should be idempotent'
    Assert-True (([Convert]::ToBase64String([IO.File]::ReadAllBytes($artifactJsonA))) -ceq ([Convert]::ToBase64String($artifactJsonBytesBeforeReuse)) -and
        ([Convert]::ToBase64String([IO.File]::ReadAllBytes($artifactMarkdownA))) -ceq ([Convert]::ToBase64String($artifactMarkdownBytesBeforeReuse)) -and
        ([Convert]::ToBase64String([IO.File]::ReadAllBytes($artifactManifestA))) -ceq ([Convert]::ToBase64String($artifactManifestBytesBeforeReuse))) 'identical publication must reuse byte-identical artifacts and completion boundary'
    Assert-True (@(Get-ChildItem -LiteralPath $artifactRoot -Recurse -Force -File -Filter '*.tmp.*').Count -eq 0) 'successful publication must clean temporary siblings'

    $revisionC = 'cccccccccccccccccccccccccccccccccccccccc'
    $changedEvents = @($events | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json })
    $changedEvents[-1].revision = $revisionC
    $changedEvents[-1].pullRequest.reviewedHead = $revisionC
    [IO.File]::WriteAllLines($changedLedger, @($changedEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $changedArtifactOutput = & $scriptPath -EventsPath $changedLedger -ReviewMode per_task -ArtifactDirectory $artifactRoot
    Assert-True ($LASTEXITCODE -eq 0) 'a changed reviewed HEAD should publish a retained sibling report'
    $artifactJsonB = @((Get-ChildItem -LiteralPath $artifactRoot -Filter 'story-performance-*.json' -File | Where-Object { $_.Name -notlike '*.complete.json' -and $_.FullName -ne $artifactJsonA } | Select-Object -ExpandProperty FullName))[0]
    $artifactMarkdownB = @((Get-ChildItem -LiteralPath $artifactRoot -Filter 'story-performance-*.md' -File | Where-Object { $_.FullName -ne $artifactMarkdownA } | Select-Object -ExpandProperty FullName))[0]
    $artifactManifestB = "$artifactJsonB.complete.json"
    $changedArtifact = Get-Content -Raw -LiteralPath $artifactJsonB | ConvertFrom-Json -Depth 100
    Assert-True ([string]$publishedArtifact.reportId -cne [string]$changedArtifact.reportId -and
        [string]$publishedArtifact.comparison.reviewedHead -ceq $revisionB -and
        [string]$changedArtifact.comparison.reviewedHead -ceq $revisionC -and
        (Test-Path -LiteralPath $artifactJsonA) -and (Test-Path -LiteralPath $artifactJsonB) -and
        (Test-Path -LiteralPath $artifactManifestA) -and (Test-Path -LiteralPath $artifactManifestB) -and
        ([IO.Path]::GetFileName($artifactJsonB) -like 'story-performance-*.json')) 'distinct reviewed HEADs must retain distinct report identities, completion manifests, and identity-derived destinations'

    $conflictOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $changedLedger -ReviewMode per_task -OutputPath $artifactJsonA -MarkdownPath $artifactMarkdownA 2>&1
    $conflictText = [string]($conflictOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -ne 0) "a changed report must conflict instead of replacing an existing artifact (diagnostic: $conflictText)"
    Assert-True ($conflictText -match 'report_artifact_conflict') "artifact conflict should expose a safe conflict diagnostic (diagnostic: $conflictText)"
    Assert-True (([Convert]::ToBase64String([IO.File]::ReadAllBytes($artifactJsonA))) -ceq ([Convert]::ToBase64String($artifactJsonBytesBeforeReuse))) 'artifact conflict must preserve the original report bytes'
    Assert-True (@(Get-ChildItem -LiteralPath $artifactRoot -Recurse -Force -File -Filter '*.tmp.*').Count -eq 0) 'conflict handling must clean temporary siblings'

    $edgeArtifactMarkdown = Join-Path $artifactRoot 'edge-cases.md'
    $edgeArtifactOutput = & pwsh -NoProfile -File $scriptPath -EventsPath $edgeLedger -ReviewMode per_task -MarkdownPath $edgeArtifactMarkdown 2>&1
    $edgeArtifactDiagnostic = [string]($edgeArtifactOutput -join [Environment]::NewLine)
    Assert-True ($LASTEXITCODE -eq 0) "incomplete evidence should still publish a bounded Markdown artifact (diagnostic: $edgeArtifactDiagnostic)"
    $edgeMarkdown = Get-Content -Raw -LiteralPath $edgeArtifactMarkdown
    Assert-True ($edgeMarkdown.Contains('partial') -and $edgeMarkdown.Contains('incomplete_tail') -and $edgeMarkdown.Contains('unknown')) 'incomplete artifact Markdown must retain explicit partial, anomaly, and unknown limitations'

    $repeatJson = & $scriptPath -EventsPath $ledger -ReviewMode per_task -TaskRefs @(152, 153)
    Assert-True ($LASTEXITCODE -eq 0 -and $repeatJson -ceq $jsonText) 'repeating aggregation over the same ledger should be byte stable'

    # Integrate recorder recovery with aggregation. The interrupted write is
    # followed by a fresh-process replay of a complete boundary, a recovery
    # append for the interrupted identity, and a second stable-ID replay. The
    # report is read from this exact recovered ledger, so a recorder bug that
    # duplicates a complete event changes the asserted counts or durations.
    $recoveryRunId = 'synthetic-integrated-recovery'
    $recoveryEvents = @(
        (New-Event -EventId 'integrated-recovery-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-10T10:00:00Z' -Scope 'story' -Role 'coordinator'),
        (New-Event -EventId 'integrated-recovery-implementation-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-10T10:01:00Z' -Scope 'task' -TaskRef 301 -PhaseId 'integrated-recovery-implementation' -Role 'implementer'),
        (New-Event -EventId 'integrated-recovery-implementation-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-10T10:02:00Z' -Scope 'task' -TaskRef 301 -PhaseId 'integrated-recovery-implementation' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'integrated-recovery-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-10T10:03:00Z' -Scope 'task' -TaskRef 301 -PhaseId 'integrated-recovery-review' -ReviewRequestId 'integrated-recovery-request' -ReviewAttemptId 'integrated-recovery-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'integrated-recovery-review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-10T10:04:00Z' -Scope 'task' -TaskRef 301 -PhaseId 'integrated-recovery-review' -ReviewRequestId 'integrated-recovery-request' -ReviewAttemptId 'integrated-recovery-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'integrated-recovery-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-10T10:05:00Z' -Scope 'story' -WaitId 'integrated-recovery-wait' -WaitKind 'reviewer' -Role 'coordinator')
    )
    foreach ($recoveryEvent in $recoveryEvents) {
        $recoveryEvent.runId = $recoveryRunId
        $recoveryAppend = Invoke-RecorderEvent -RecorderPath $recorderPath -ExternalRoot $recorderRoot -RunId $recoveryRunId -Event $recoveryEvent
        Assert-True ($recoveryAppend.ExitCode -eq 0 -and [string]$recoveryAppend.Result.status -ceq 'appended') "recovery setup event $($recoveryEvent.eventId) should append"
    }
    $recoveryWaitEnd = New-Event -EventId 'integrated-recovery-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-10T10:06:00Z' -Scope 'story' -WaitId 'integrated-recovery-wait' -WaitKind 'reviewer' -Role 'coordinator'
    $recoveryWaitEnd.runId = $recoveryRunId
    $faultedRecoveryWrite = Invoke-RecorderEvent -RecorderPath $recorderPath -ExternalRoot $recorderRoot -RunId $recoveryRunId -Event $recoveryWaitEnd -FaultAfterBytes 11
    Assert-True ($faultedRecoveryWrite.ExitCode -eq 2 -and [string]$faultedRecoveryWrite.Result.status -ceq 'error' -and [string]$faultedRecoveryWrite.Result.errorCategory -ceq 'write_failed') 'integrated recovery fault must leave a safe write failure'
    $recoveryLedger = Join-Path (Join-Path $recorderRoot $recoveryRunId) 'events.jsonl'
    $faultedRecoveryBytes = [IO.File]::ReadAllBytes($recoveryLedger)
    Assert-True ($faultedRecoveryBytes.Length -gt 0 -and $faultedRecoveryBytes[$faultedRecoveryBytes.Length - 1] -ne [byte]0x0A) 'integrated recovery fault must leave a detectable incomplete tail'

    $replayedCompleteBoundary = Invoke-RecorderEvent -RecorderPath $recorderPath -ExternalRoot $recorderRoot -RunId $recoveryRunId -Event $recoveryEvents[3]
    Assert-True ($replayedCompleteBoundary.ExitCode -eq 0 -and [string]$replayedCompleteBoundary.Result.status -ceq 'noop') 'fresh-process replay of a complete boundary must not append a duplicate'
    $recoveredRecoveryWrite = Invoke-RecorderEvent -RecorderPath $recorderPath -ExternalRoot $recorderRoot -RunId $recoveryRunId -Event $recoveryWaitEnd
    Assert-True ($recoveredRecoveryWrite.ExitCode -eq 0 -and [string]$recoveredRecoveryWrite.Result.status -ceq 'appended' -and [bool]$recoveredRecoveryWrite.Result.recoveredIncompleteTail) 'fresh-process recovery append must retain the interrupted tail diagnostic'
    Assert-True (Test-Path -LiteralPath ([string]$recoveredRecoveryWrite.Result.diagnosticPath) -PathType Leaf) 'integrated recovery must persist a diagnostic sidecar'
    $recoveryDiagnosticText = [IO.File]::ReadAllText([string]$recoveredRecoveryWrite.Result.diagnosticPath)
    Assert-True ($recoveryDiagnosticText -match '"diagnosticType":"incomplete_tail"') 'integrated recovery diagnostic must identify the interrupted tail'
    $replayedRecoveredBoundary = Invoke-RecorderEvent -RecorderPath $recorderPath -ExternalRoot $recorderRoot -RunId $recoveryRunId -Event $recoveryWaitEnd
    Assert-True ($replayedRecoveredBoundary.ExitCode -eq 0 -and [string]$replayedRecoveredBoundary.Result.status -ceq 'noop') 'replaying the recovered boundary must remain a no-op'

    $recoveryPrReady = New-Event -EventId 'integrated-recovery-pr-ready' -EventType 'pr_ready' -OccurredAtUtc '2026-10-10T10:07:00Z' -Scope 'story' -Revision $revisionA -Role 'coordinator'
    $recoveryPrReady.runId = $recoveryRunId
    $recoveryPrReady.pullRequest = [ordered]@{ provider = 'github'; owner = 'blakeg83'; repository = 'taiga-mcp'; number = 145; reviewedHead = $revisionA }
    $recoveryPrAppend = Invoke-RecorderEvent -RecorderPath $recorderPath -ExternalRoot $recorderRoot -RunId $recoveryRunId -Event $recoveryPrReady
    Assert-True ($recoveryPrAppend.ExitCode -eq 0 -and [string]$recoveryPrAppend.Result.status -ceq 'appended') 'integrated recovery PR boundary should append'
    $recoveryReportJson = & $scriptPath -EventsPath $recoveryLedger -ReviewMode per_task -TaskRefs @(301)
    Assert-True ($LASTEXITCODE -eq 0) 'recovered ledger should aggregate successfully'
    $recoveryReport = $recoveryReportJson | ConvertFrom-Json -Depth 100
    Assert-True ([int64]$recoveryReport.metrics.timeToPr.value -eq 420000 -and [int64]$recoveryReport.metrics.implementationElapsed.value -eq 60000 -and [int64]$recoveryReport.metrics.reviewElapsed.value -eq 60000 -and [int64]$recoveryReport.metrics.waitingElapsed.value -eq 60000) 'recovered report must preserve exact elapsed values'
    Assert-True ([int]$recoveryReport.metrics.initialTaskReviews.value -eq 1 -and [int]$recoveryReport.metrics.tasksCompleted.value -eq 1 -and [int]$recoveryReport.coverage.validEventCount -eq 8) 'recovered report must not double-count complete or recovered boundaries'
    Assert-True (@($recoveryReport.reviewAttempts).Count -eq 1 -and @($recoveryReport.anomalies | Where-Object { $_.code -eq 'malformed_event' }).Count -ge 1) 'recovered report must retain one review attempt and disclose the quarantined interrupted fragment'

    # Pair a healthy ready-turn control with the same transition under a real
    # recorder fault. The child fixture invokes the existing
    # Complete-ReviewHandoff -> Apply-Event -> End-ImplementerReviewTurn path;
    # this wrapper only supplies the recorder fault and inspects the resulting
    # workflow trace.
    $automaticReviewFixturePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\.agents\skills\taiga-story-loop\scripts\validate-automatic-review-flow.ps1'))
    $measurementRoot = Join-Path $root 'automatic-review-measurement'
    $healthyTrace = Invoke-AutomaticReviewMeasurementScenario -Path $automaticReviewFixturePath -ExternalRoot $measurementRoot -RunId 'synthetic-measurement-healthy' -TracePath (Join-Path $measurementRoot 'healthy-trace.json')
    $faultedTrace = Invoke-AutomaticReviewMeasurementScenario -Path $automaticReviewFixturePath -ExternalRoot $measurementRoot -RunId 'synthetic-measurement-fault' -TracePath (Join-Path $measurementRoot 'faulted-trace.json') -FaultAfterBytes 9
    foreach ($workflowField in @('decision', 'authorization', 'reviewerId', 'workflowRevision', 'taskState', 'reviewGate', 'pendingReview', 'pendingRevision', 'currentTaskIndex', 'nextTaskState', 'reviewActionCount', 'reviewDestination', 'reviewActionRevision', 'turnCount', 'turnRevision')) {
        Assert-True ([string]$healthyTrace.workflow.$workflowField -ceq [string]$faultedTrace.workflow.$workflowField) "measurement failure must not change actual workflow trace field $workflowField"
    }
    Assert-True ([string]$healthyTrace.measurement.state -ceq 'recorded' -and [string]$faultedTrace.measurement.state -ceq 'unavailable' -and [int]$faultedTrace.measurement.recorderExitCode -ne 0) 'measurement failure must change only measurement coverage and retain a nonzero recorder failure'
    foreach ($trace in @($healthyTrace, $faultedTrace)) {
        Assert-True ([string]$trace.workflow.decision -ceq 'dispatch_review' -and [string]$trace.workflow.taskState -ceq 'awaiting_review' -and [string]$trace.workflow.reviewGate -ceq 'awaiting_review') 'actual ready transition must dispatch and end in awaiting_review'
        Assert-True ([bool]$trace.workflow.pendingReview -and [string]$trace.workflow.pendingRevision -ceq ('e' * 40) -and [string]$trace.workflow.workflowRevision -ceq ('e' * 40)) 'actual review must retain the supplied exact revision'
        Assert-True ([int]$trace.workflow.currentTaskIndex -eq 0 -and [string]$trace.workflow.nextTaskState -ceq 'not_started') 'actual ready transition must hold the next ordered task'
        Assert-True ([int]$trace.workflow.reviewActionCount -eq 1 -and [string]$trace.workflow.reviewDestination -ceq 'reviewer-story-87' -and [string]$trace.workflow.reviewActionRevision -ceq ('e' * 40)) 'actual dispatch trace must target the assigned reviewer once'
        Assert-True ([int]$trace.workflow.turnCount -eq 1 -and [string]$trace.workflow.turnRevision -ceq ('e' * 40)) 'actual dispatch must end exactly one implementer turn'
        $terminalKinds = @($trace.workflow.terminalActionKinds)
        Assert-True ($terminalKinds.Count -eq 2 -and [string]$terminalKinds[0] -ceq 'send_review_handoff' -and [string]$terminalKinds[1] -ceq 'final_response') 'actual terminal action trace must be the review handoff and final response'
        Assert-True ([bool]$trace.invalidAuthorization.rejected -and [int]$trace.invalidAuthorization.actionCount -eq 0 -and [int]$trace.invalidAuthorization.turnCount -eq 0 -and [string]$trace.invalidAuthorization.taskState -ceq 'in_progress' -and -not [bool]$trace.invalidAuthorization.pendingReview -and [string]$trace.invalidAuthorization.error -match 'stale') 'invalid authorization must be rejected without workflow mutation'
    }

    # Run the workflow-owned contract fixtures as part of this integrated
    # matrix. They invoke the production recorder (and, where applicable,
    # continuation writer) against disposable external roots, so this check
    # covers restart, concurrent writes, interrupted tails, injected recorder
    # failure, both review modes, and ordered-task/re-review guards without
    # changing workflow authority.
    $workflowFixtureRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\.agents\skills\taiga-story-loop\scripts'))
    $workflowFixtures = @(
        [ordered]@{ name = 'performance-event recorder lifecycle'; file = 'validate-performance-event.ps1' },
        [ordered]@{ name = 'lifecycle boundary ownership'; file = 'validate-lifecycle-bindings.ps1' },
        [ordered]@{ name = 'post-Start resume and measurement failure'; file = 'validate-performance-start.ps1' },
        [ordered]@{ name = 'automatic review and ordered-task flow'; file = 'validate-automatic-review-flow.ps1' }
    )
    $workflowFixtureResults = foreach ($fixture in $workflowFixtures) {
        Invoke-WorkflowFixture -Name ([string]$fixture.name) -Path (Join-Path $workflowFixtureRoot ([string]$fixture.file))
    }

    $scenarioEvidence = @(
        [ordered]@{ scenario = 'normal per-task operation'; setup = 'fixed UTC lifecycle events'; action = 'record then aggregate'; expected = 'measured elapsed/review metrics'; observed = 'report assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'correction and final re-review'; setup = 'finding, correction, and new full revision'; action = 'record both review attempts'; expected = 'distinct attributable attempts'; observed = 'per_task and final retry assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'story_end_only mode'; setup = 'implementation plus final-story events'; action = 'reject task review events'; expected = 'no task reviews, final review countable'; observed = 'mode assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'duplicate and stale observations'; setup = 'stable IDs plus stale revision'; action = 'replay and reject'; expected = 'no double-count or mutation'; observed = 'recorder/aggregator/lifecycle assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'restart and interrupted tail'; setup = 'confirmed line plus injected incomplete write'; action = 'start a fresh recorder process'; expected = 'preserve complete line and diagnose tail'; observed = 'recovery assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'concurrent writes'; setup = 'two recorder processes and same-ID replay'; action = 'append under the ledger lock'; expected = 'one line per distinct event'; observed = 'concurrency assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'unknown or partial telemetry'; setup = 'missing source-backed counters'; action = 'aggregate usage windows'; expected = 'null unavailable/partial state, no estimate'; observed = 'usage fallback assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'usage counter reset'; setup = 'synthetic cumulative stream with an intermediate decrease'; action = 'aggregate the reset window'; expected = 'partial null total with reset anomaly'; observed = 'usage_counter_reset assertion passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'PR reuse and new reviewed HEAD'; setup = 'same PR identity with changed full HEAD'; action = 'publish artifacts'; expected = 'reuse identical bytes, retain new sibling'; observed = 'artifact identity assertions passed'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'measurement failure'; setup = 'paired healthy/faulted ready-turn control through Complete-ReviewHandoff and Apply-Event with real recorder fault'; action = 'continue workflow without telemetry'; expected = 'actual dispatch trace, awaiting-review terminal state, next-task hold, and stale-authorization rejection unchanged'; observed = 'workflow-owned traces matched; only measurement became unavailable'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'attributable host token counters'; setup = '.agents/skills/taiga-story-loop/references/performance-reporting.md discovery dated 2026-10-09; probes: create_thread schema, get_usage_limits schema, list_threads({limit:50}), get_goal({}), repository search'; action = 'not_run by this validator; retain prior bounded discovery'; expected = 'measure only when worker/session counters are attributable'; observed = 'no fresh host probe claimed; prior discovery records per-worker counters unavailable'; evidence = 'unavailable'; status = 'not_run' }
    )
    Write-Output 'Scenario evidence (synthetic unless explicitly marked unavailable):'
    foreach ($scenario in $scenarioEvidence) {
        Write-Output (($scenario.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' | ')
    }

    Write-Output ('PASS: integrated reporting/recovery matrix; workflow fixtures: ' + (($workflowFixtureResults | ForEach-Object { "$($_.name)=exit$($_.exitCode)" }) -join ', '))
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
