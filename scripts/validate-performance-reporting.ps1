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

function New-Event {
    param(
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [Parameter(Mandatory)] [string] $Scope,
        [int] $TaskRef,
        [string] $PhaseId,
        [string] $CorrectionId,
        [string] $ReviewRequestId,
        [string] $ReviewAttemptId,
        [string] $ReviewKind,
        [int] $ReviewAttemptOrdinal,
        [string] $Revision,
        [string] $WaitId,
        [string] $WaitKind,
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
        phaseId = $PhaseId
        correctionId = $CorrectionId
        reviewRequestId = $ReviewRequestId
        reviewAttemptId = $ReviewAttemptId
        reviewKind = $ReviewKind
        reviewAttemptOrdinal = if ($ReviewAttemptOrdinal -gt 0) { $ReviewAttemptOrdinal } else { $null }
        supersedesReviewAttemptId = $null
        eventType = $EventType
        occurredAtUtc = $OccurredAtUtc
        revision = $Revision
        reviewMode = $ReviewMode
        provenance = [ordered]@{ source = 'synthetic_fixture'; observedBy = 'validator'; coverage = 'fixed UTC fixture'; synthetic = $true }
        usage = $null
        waitId = $WaitId
        waitKind = $WaitKind
        pullRequest = $null
    }
    return [pscustomobject] $event
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-task152-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$ledger = Join-Path $root 'per-task.jsonl'
$storyEndLedger = Join-Path $root 'story-end-only.jsonl'
$edgeLedger = Join-Path $root 'edge-cases.jsonl'
$scriptPath = Join-Path $PSScriptRoot 'get-story-performance.ps1'

try {
    $revisionA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $revisionB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $events = @(
        (New-Event -EventId 'story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-09T10:00:00Z' -Scope 'story' -Role 'coordinator'),
        (New-Event -EventId 'impl-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T10:05:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-impl' -Role 'implementer'),
        (New-Event -EventId 'impl-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T10:15:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-impl' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:20:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-review' -ReviewRequestId 'task-152-request-1' -ReviewAttemptId 'task-152-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'review-accepted' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T10:25:00Z' -Scope 'task' -TaskRef 152 -PhaseId 'task-152-review' -ReviewRequestId 'task-152-request-1' -ReviewAttemptId 'task-152-attempt-1' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'correction-start' -EventType 'correction_started' -OccurredAtUtc '2026-10-09T10:30:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-correction' -CorrectionId 'task-153-correction' -Revision $null -Role 'implementer'),
        (New-Event -EventId 'correction-ready' -EventType 'correction_ready' -OccurredAtUtc '2026-10-09T10:40:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-correction' -CorrectionId 'task-153-correction' -Revision $revisionB -Role 'implementer'),
        (New-Event -EventId 'rereview-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T10:45:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-rereview' -ReviewRequestId 'task-153-request-2' -ReviewAttemptId 'task-153-attempt-2' -ReviewKind 'correction_rereview' -ReviewAttemptOrdinal 1 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'rereview-findings' -EventType 'review_findings' -OccurredAtUtc '2026-10-09T10:50:00Z' -Scope 'task' -TaskRef 153 -PhaseId 'task-153-rereview' -ReviewRequestId 'task-153-request-2' -ReviewAttemptId 'task-153-attempt-2' -ReviewKind 'correction_rereview' -ReviewAttemptOrdinal 1 -Revision $revisionB -Role 'reviewer'),
        (New-Event -EventId 'wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T10:51:00Z' -Scope 'story' -WaitId 'story-wait-1' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T10:53:00Z' -Scope 'story' -WaitId 'story-wait-1' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'pr-ready' -EventType 'pr_ready' -OccurredAtUtc '2026-10-09T11:00:00Z' -Scope 'story' -Revision $revisionB -Role 'coordinator')
    )
    $events[-1].pullRequest = [ordered]@{ provider = 'github'; owner = 'blakeg83'; repository = 'taiga-mcp'; number = 143; reviewedHead = $revisionB }
    $lines = @($events | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 })
    $lines += $lines[3]
    $lines += ((New-Event -EventId 'orphan-closure' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:59:00Z' -Scope 'task' -TaskRef 999 -PhaseId 'orphan' -ReviewRequestId 'orphan-request' -ReviewAttemptId 'orphan-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer') | ConvertTo-Json -Compress -Depth 20)
    [IO.File]::WriteAllLines($ledger, $lines, [Text.UTF8Encoding]::new($false))

    $jsonText = & pwsh -NoProfile -File $scriptPath -EventsPath $ledger -ReviewMode per_task
    Assert-True ($LASTEXITCODE -eq 0) 'per-task aggregator should exit successfully'
    $report = $jsonText | ConvertFrom-Json -Depth 100
    Assert-True ([int64]$report.metrics.timeToPr.value -eq 3600000) 'timeToPr should use direct UTC boundaries'
    Assert-True ([int64]$report.metrics.implementationElapsed.value -eq 1200000) 'implementationElapsed should sum implementation and correction intervals'
    Assert-True ([int64]$report.metrics.reviewElapsed.value -eq 600000) 'reviewElapsed should sum distinct review attempts'
    Assert-True ([int64]$report.metrics.waitingElapsed.value -eq 120000) 'waitingElapsed should measure explicit wait boundaries'
    Assert-True ([int]$report.metrics.initialTaskReviews.value -eq 1) 'duplicate review start should count one initial task review'
    Assert-True ([int]$report.metrics.correctionReReviews.value -eq 1) 'correction re-review should count one attempt'
    Assert-True (@($report.reviewAttempts).Count -eq 2) 'request/attempt identities should produce two distinct review attempts'
    Assert-True (@($report.reviewAttempts | Select-Object -ExpandProperty reviewRequestId -Unique).Count -eq 2) 'review requests should remain attributable separately'
    Assert-True ([int]$report.metrics.firstPassAcceptanceRate.numerator -eq 1 -and [int]$report.metrics.firstPassAcceptanceRate.denominator -eq 1) 'first-pass numerator and denominator should be explicit'
    Assert-True ([string]$report.metrics.firstPassAcceptanceRate.state -eq 'measured' -and [double]$report.metrics.firstPassAcceptanceRate.value -eq 1) 'first-pass rate should be measured from authoritative acceptance'
    Assert-True (@($report.anomalies | Where-Object { $_.code -eq 'duplicate_event' }).Count -eq 1) 'exact replay should be disclosed'
    Assert-True (@($report.anomalies | Where-Object { $_.code -eq 'orphan_review_closure' }).Count -eq 1) 'orphan closure should be disclosed'

    $storyEndEvents = @(
        (New-Event -EventId 'story-end-final-start' -EventType 'final_review_started' -OccurredAtUtc '2026-10-09T12:00:00Z' -Scope 'final_story' -PhaseId 'final-1' -ReviewRequestId 'final-request-1' -ReviewAttemptId 'final-attempt-1' -ReviewKind 'final_story' -ReviewAttemptOrdinal 1 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer'),
        (New-Event -EventId 'story-end-final-accepted' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-09T12:10:00Z' -Scope 'final_story' -PhaseId 'final-1' -ReviewRequestId 'final-request-1' -ReviewAttemptId 'final-attempt-1' -ReviewKind 'final_story' -ReviewAttemptOrdinal 1 -Revision $revisionB -ReviewMode 'story_end_only' -Role 'reviewer')
    )
    [IO.File]::WriteAllLines($storyEndLedger, @($storyEndEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $storyEndJson = & pwsh -NoProfile -File $scriptPath -EventsPath $storyEndLedger -ReviewMode story_end_only
    Assert-True ($LASTEXITCODE -eq 0) 'story-end-only aggregator should exit successfully'
    $storyEnd = $storyEndJson | ConvertFrom-Json -Depth 100
    Assert-True ([int]$storyEnd.metrics.initialTaskReviews.value -eq 0 -and [int]$storyEnd.metrics.correctionReReviews.value -eq 0) 'story_end_only must have zero per-task and correction reviews'
    Assert-True ([int]$storyEnd.metrics.finalStoryReviews.value -eq 1) 'story_end_only final review remains countable'
    Assert-True ([string]$storyEnd.metrics.firstPassAcceptanceRate.state -eq 'not_applicable') 'story_end_only first-pass denominator is not applicable'

    $edgeEvents = @(
        (New-Event -EventId 'edge-missing-end' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:00:00Z' -Scope 'task' -TaskRef 160 -PhaseId 'edge-missing' -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-a-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:00:00Z' -Scope 'task' -TaskRef 161 -PhaseId 'edge-overlap-a' -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-a-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T09:10:00Z' -Scope 'task' -TaskRef 161 -PhaseId 'edge-overlap-a' -Revision $revisionA -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-b-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-09T09:05:00Z' -Scope 'task' -TaskRef 162 -PhaseId 'edge-overlap-b' -Role 'implementer'),
        (New-Event -EventId 'edge-overlap-b-end' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-09T09:15:00Z' -Scope 'task' -TaskRef 162 -PhaseId 'edge-overlap-b' -Revision $revisionB -Role 'implementer'),
        (New-Event -EventId 'edge-reversed-review-start' -EventType 'review_started' -OccurredAtUtc '2026-10-09T09:20:00Z' -Scope 'task' -TaskRef 163 -PhaseId 'edge-review' -ReviewRequestId 'edge-request' -ReviewAttemptId 'edge-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-reversed-review-end' -EventType 'review_accepted' -OccurredAtUtc '2026-10-09T09:19:00Z' -Scope 'task' -TaskRef 163 -PhaseId 'edge-review' -ReviewRequestId 'edge-request' -ReviewAttemptId 'edge-attempt' -ReviewKind 'initial_task' -ReviewAttemptOrdinal 1 -Revision $revisionA -Role 'reviewer'),
        (New-Event -EventId 'edge-reversed-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-09T09:30:00Z' -Scope 'story' -WaitId 'edge-wait' -WaitKind 'reviewer' -Role 'coordinator'),
        (New-Event -EventId 'edge-reversed-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-09T09:29:00Z' -Scope 'story' -WaitId 'edge-wait' -WaitKind 'reviewer' -Role 'coordinator')
    )
    [IO.File]::WriteAllLines($edgeLedger, @($edgeEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }), [Text.UTF8Encoding]::new($false))
    $edgeJson = & pwsh -NoProfile -File $scriptPath -EventsPath $edgeLedger -ReviewMode per_task
    Assert-True ($LASTEXITCODE -eq 0) 'edge-case aggregator should exit successfully with incomplete evidence'
    $edge = $edgeJson | ConvertFrom-Json -Depth 100
    Assert-True ([string]$edge.metrics.implementationElapsed.state -eq 'partial' -and [int64]$edge.metrics.implementationElapsed.value -eq 1200000) 'missing implementation boundary should keep valid overlap totals partial and explicit'
    Assert-True ([string]$edge.metrics.reviewElapsed.state -eq 'partial' -and $null -eq $edge.metrics.reviewElapsed.value) 'reversed review closure should not create elapsed time'
    Assert-True ([string]$edge.metrics.waitingElapsed.state -eq 'partial' -and $null -eq $edge.metrics.waitingElapsed.value) 'reversed wait boundary should not create elapsed time'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'missing_boundary' }).Count -ge 1) 'missing boundary should be diagnosed'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'overlapping_intervals' }).Count -eq 1) 'overlap should be disclosed rather than subtracted'
    Assert-True (@($edge.anomalies | Where-Object { $_.code -eq 'negative_interval' }).Count -ge 2) 'impossible reversed review and wait sequences should be diagnosed'
    Assert-True ([string]$edge.metrics.firstPassAcceptanceRate.state -eq 'partial' -and [int]$edge.metrics.firstPassAcceptanceRate.denominator -eq 1) 'first-pass coverage should remain partial when acceptance ordering is impossible'

    Write-Output 'PASS: task #152 deterministic aggregation fixtures (per_task and story_end_only)'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
