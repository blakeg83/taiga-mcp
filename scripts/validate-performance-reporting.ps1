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
        usage = $null
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
$privacyLedger = Join-Path $root 'privacy.jsonl'
$utfLedger = Join-Path $root 'invalid-utf8.jsonl'
$orphanLedger = Join-Path $root 'orphan-order.jsonl'
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
        (New-Event -EventId 'story-end-rereview-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T12:20:00Z' -Scope 'final_story' -PhaseId 'final-2' -ReviewRequestId 'final-request-2' -ReviewAttemptId 'final-attempt-2' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 2 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-rereview-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T12:30:00Z' -Scope 'final_story' -PhaseId 'final-2' -ReviewRequestId 'final-request-2' -ReviewAttemptId 'final-attempt-2' -ReviewKind 'final_story_rereview' -ReviewAttemptOrdinal 2 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($storyEndLedger, @($storyEndEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $storyEndJson = & $scriptPath -EventsPath $storyEndLedger -ReviewMode story_end_only
    Assert-True ($LASTEXITCODE -eq 0) 'story-end-only aggregator should exit successfully'
    $storyEnd = $storyEndJson | ConvertFrom-Json -Depth 100
    Assert-True ([int]$storyEnd.metrics.initialTaskReviews.value -eq 0 -and [int]$storyEnd.metrics.correctionReReviews.value -eq 0) 'story_end_only must have zero per-task and correction reviews'
    Assert-True ([int]$storyEnd.metrics.finalStoryReviews.value -eq 2 -and [int]$storyEnd.metrics.finalStoryReReviews.value -eq 1) 'story_end_only final review and same-SHA re-review remain countable'
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
        (New-Event -EventId 'edge-reversed-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:30:00Z' -Scope 'story' -WaitId 'edge-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-reversed-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:29:00Z' -Scope 'story' -WaitId 'edge-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-overlap-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:07:00Z' -Scope 'story' -WaitId 'edge-overlap-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-overlap-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:08:00Z' -Scope 'story' -WaitId 'edge-overlap-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'orphan-closure' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:59:00Z' -Scope 'task' -TaskRef 999 -PhaseId 'orphan' -ReviewRequestId 'orphan-request' -ReviewAttemptId 'orphan-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($edgeLedger, @($edgeEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    [IO.File]::AppendAllText($edgeLedger, '{"eventId":"interrupted-tail"', [Text.UTF8Encoding]::new($false))
    $edgeJson = & $scriptPath -EventsPath $edgeLedger -ReviewMode per_task -TaskRefs @(160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171)
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
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'conflicting_boundary' }).Count -ge 2) 'changed wait kind and actor attribution should be disclosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'undeclared_task_evidence' }).Count -eq 1) 'undeclared task evidence should be quarantined'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'incomplete_tail' }).Count -eq 1) 'an interrupted non-newline tail should be excluded and diagnosed'
    Assert-True (@($edge.coverage.taskSet.missingInitialReviewTaskRefs).Count -eq 7) 'per-task coverage should name declared tasks without initial review evidence'
    Assert-True ([string]$edge.metrics.firstPassAcceptanceRate.state -eq 'partial' -and [int]$edge.metrics.firstPassAcceptanceRate.denominator -eq 5) 'first-pass coverage should remain partial when acceptance ordering is impossible'
    Assert-True ([int]$edge.coverage.validEventCount -eq 30) 'task filtering should retain only valid records before aggregation'

    $repeatJson = & $scriptPath -EventsPath $ledger -ReviewMode per_task -TaskRefs @(152, 153)
    Assert-True ($LASTEXITCODE -eq 0 -and $repeatJson -ceq $jsonText) 'repeating aggregation over the same ledger should be byte stable'

    Write-Output 'PASS: task #152 deterministic aggregation fixtures (per_task and story_end_only)'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
