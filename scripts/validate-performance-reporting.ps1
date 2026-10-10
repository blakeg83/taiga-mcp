<#
.SYNOPSIS
    Run deterministic task #152 aggregation fixtures.

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
        sessionId = 'synthetic-session'
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

$root = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-task152-' + [Guid]::NewGuid().ToString('N'))
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
        (New-Event -EventId 'usage-impl-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:00:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-impl' -Role 'implementer' -Usage $usageImplStart),
        (New-Event -EventId 'usage-impl-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T09:10:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-impl' -Revision $comparisonHead -Role 'implementer' -Usage $usageImplEnd),
        (New-Event -EventId 'usage-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-review' -ReviewRequestId 'usage-review-request' -ReviewAttemptId 'usage-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -Usage $usageReviewStart),
        (New-Event -EventId 'usage-review-start-replay' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-review' -ReviewRequestId 'usage-review-request' -ReviewAttemptId 'usage-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -Usage $usageReviewStart),
        (New-Event -EventId 'usage-review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:25:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-review' -ReviewRequestId 'usage-review-request' -ReviewAttemptId 'usage-review-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -Usage $usageReviewEnd),
        (New-Event -EventId 'usage-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:30:00Z' -Scope 'story' -WaitId 'usage-wait' -WaitKind 'reviewer' -Role 'coordinator' -Usage $usageWaitStart),
        (New-Event -EventId 'usage-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:35:00Z' -Scope 'story' -WaitId 'usage-wait' -WaitKind 'reviewer' -Role 'coordinator' -Usage $usageWaitEnd),
        (New-Event -EventId 'usage-pr-ready' -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T09:40:00Z' -Scope 'story' -Revision $comparisonHead -Role 'coordinator')
    )
    $usageEvents[4].transitionId = $usageEvents[3].transitionId
    foreach ($usageEvent in $usageEvents) { $usageEvent.runId = 'synthetic-usage-153' }
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
        (New-Event -EventId 'usage-partial-impl-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T10:00:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-reset' -Role 'implementer' -Usage $usageReset),
        (New-Event -EventId 'usage-partial-impl-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T10:10:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-reset' -Revision $comparisonHead -Role 'implementer' -Usage $usageResetEnd),
        (New-Event -EventId 'usage-partial-worker-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T10:30:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-worker-change' -Role 'implementer' -Usage $usageWorkerStart),
        (New-Event -EventId 'usage-partial-worker-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T10:40:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-worker-change' -Revision $comparisonHead -Role 'implementer' -Usage $usageWorkerEnd),
        (New-Event -EventId 'usage-partial-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-missing' -ReviewRequestId 'usage-missing-request' -ReviewAttemptId 'usage-missing-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer' -Usage $usageMissingStart),
        (New-Event -EventId 'usage-partial-review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:25:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'usage-missing' -ReviewRequestId 'usage-missing-request' -ReviewAttemptId 'usage-missing-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $comparisonHead -Role 'reviewer')
    )
    foreach ($partialEvent in $usagePartialEvents) { $partialEvent.runId = 'synthetic-usage-153-partial' }
    [IO.File]::WriteAllLines($usageLedger, @($usagePartialEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $partialJson = & $scriptPath -EventsPath $usageLedger -ReviewMode per_task -TaskRefs @(152)
    Assert-True ($LASTEXITCODE -eq 0) 'partial usage fixture should aggregate without inventing totals'
    $partialReport = $partialJson | ConvertFrom-Json -Depth 100
    Assert-True ([string]$partialReport.metrics.implementationTokens.state -eq 'partial' -and $null -eq $partialReport.metrics.implementationTokens.value) 'counter reset must make implementation token coverage partial with null total'
    Assert-True ([string]$partialReport.metrics.reviewTokens.state -eq 'partial' -and $null -eq $partialReport.metrics.reviewTokens.value) 'missing review usage boundary must remain partial with null total'
    Assert-True (@($partialReport.anomalies | Where-Object { $_.code -eq 'usage_counter_reset' }).Count -eq 1 -and @($partialReport.anomalies | Where-Object { $_.code -eq 'usage_stream_conflict' }).Count -eq 1 -and @($partialReport.anomalies | Where-Object { $_.code -eq 'usage_missing_boundary' }).Count -eq 1) 'reset, worker/session changes, and missing usage boundaries must be disclosed explicitly'

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
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'overlapping_intervals' }).Count -ge 6) 'cross-category overlap should be disclosed rather than subtracted'
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
    Assert-True ($overlapDiagnostics.Count -eq 3) 'only nesting and genuine cross-category intersections should be disclosed; disjoint, touching, and zero-duration intervals should not'

    $repeatJson = & $scriptPath -EventsPath $ledger -ReviewMode per_task -TaskRefs @(152, 153)
    Assert-True ($LASTEXITCODE -eq 0 -and $repeatJson -ceq $jsonText) 'repeating aggregation over the same ledger should be byte stable'

    Write-Output 'PASS: task #152 deterministic aggregation fixtures (per_task and story_end_only)'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
