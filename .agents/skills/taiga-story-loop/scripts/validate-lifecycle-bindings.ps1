<#
.SYNOPSIS
    Validate lifecycle-event ownership at the existing worker boundaries.

This is deterministic synthetic evidence only. It reads the checked-in worker
contracts, exercises duplicate/stale attempt guards for both review modes, and
invokes the real performance recorder with a disposable external ledger. It
does not call Taiga, start a service, poll a worker, or export a transcript.
#>

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
        throw "Lifecycle-binding assertion failed: $Message"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Needle,
        [Parameter(Mandatory)] [string] $Label
    )

    Assert-True $Text.Contains($Needle) "$Label must contain '$Needle'"
}

function Get-NullableText {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    return [string]$Value
}

function New-WorkflowState {
    param([ValidateSet('per_task', 'story_end_only')] [string] $ReviewMode)

    return [ordered]@{
        reviewMode = $ReviewMode
        currentRevision = $null
        observations = @{}
        attempts = @{}
        closedAttempts = @{}
        waits = @{}
        transitions = @()
    }
}

function Record-Transition {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $Identity,
        [AllowNull()] [string] $Revision = $null
    )

    $key = "$EventType|$Identity|$Revision"
    if ($State.observations.ContainsKey($key)) {
        return 'duplicate'
    }
    if ($EventType -in @('task_ready_for_review', 'review_started', 'review_findings', 'review_accepted') -and
        $null -ne $State.currentRevision -and [string]$Revision -cne [string]$State.currentRevision) {
        return 'stale'
    }
    $State.observations[$key] = $true
    $State.transitions = @($State.transitions) + [ordered]@{
        eventType = $EventType
        identity = $Identity
        revision = $Revision
    }
    return 'recorded'
}

function Start-ReviewAttempt {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [ValidateSet('task', 'final_story')] [string] $Scope,
        [Parameter(Mandatory)] [string] $RequestId,
        [Parameter(Mandatory)] [string] $AttemptId,
        [Parameter(Mandatory)] [string] $Revision
    )

    if ($Scope -eq 'task' -and $State.reviewMode -eq 'story_end_only') {
        return 'mode_rejected'
    }
    if ($State.attempts.ContainsKey($AttemptId)) {
        return 'duplicate'
    }
    if ($null -ne $State.currentRevision -and $Revision -cne [string]$State.currentRevision) {
        return 'stale'
    }
    $State.attempts[$AttemptId] = [ordered]@{
        requestId = $RequestId
        scope = $Scope
        revision = $Revision
    }
    return 'recorded'
}

function Close-ReviewAttempt {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [string] $AttemptId,
        [Parameter(Mandatory)] [string] $Revision
    )

    if (-not $State.attempts.ContainsKey($AttemptId)) {
        return 'stale'
    }
    if ([string]$State.attempts[$AttemptId].revision -cne $Revision) {
        return 'stale'
    }
    if ($State.closedAttempts.ContainsKey($AttemptId)) {
        return 'duplicate'
    }
    $State.closedAttempts[$AttemptId] = $true
    return 'recorded'
}

function Record-WaitBoundary {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [ValidateSet('wait_started', 'wait_ended')] [string] $EventType,
        [Parameter(Mandatory)] [string] $WaitId
    )

    $key = "$EventType|$WaitId"
    if ($State.observations.ContainsKey($key)) {
        return 'duplicate'
    }
    $State.observations[$key] = $true
    if ($EventType -eq 'wait_started') {
        $State.waits[$WaitId] = $true
    }
    return 'recorded'
}

function New-LifecycleEvent {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [Parameter(Mandatory)] [ValidateSet('task', 'final_story', 'story')] [string] $Scope,
        [Parameter(Mandatory)] [ValidateSet('coordinator', 'implementer', 'reviewer')] [string] $Role,
        [Parameter(Mandatory)] [ValidateSet('per_task', 'story_end_only')] [string] $ReviewMode,
        [AllowNull()] [Nullable[int]] $TaskRef = $null,
        [AllowNull()] [string] $PhaseId = $null,
        [AllowNull()] [string] $CorrectionId = $null,
        [AllowNull()] [string] $ReviewRequestId = $null,
        [AllowNull()] [string] $ReviewAttemptId = $null,
        [AllowNull()] [string] $ReviewKind = $null,
        [AllowNull()] [Nullable[int]] $ReviewAttemptOrdinal = $null,
        [AllowNull()] [string] $Revision = $null,
        [AllowNull()] [string] $SupersedesReviewAttemptId = $null,
        [AllowNull()] [string] $WaitId = $null,
        [AllowNull()] [string] $WaitKind = $null,
        [AllowNull()] [object] $Usage = $null,
        [AllowNull()] [object] $PullRequest = $null
    )

    return [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event'
        eventId = $EventId
        runId = $RunId
        projectId = 12
        storyId = 728
        storyRef = 144
        taskRef = $TaskRef
        role = $Role
        sessionId = "synthetic-$Role-session"
        workerId = "synthetic-$Role"
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
        provenance = [ordered]@{
            source = 'synthetic_fixture'
            observedBy = 'validator'
            coverage = 'fixed UTC lifecycle boundary'
            synthetic = $true
        }
        usage = $Usage
        waitId = Get-NullableText $WaitId
        waitKind = Get-NullableText $WaitKind
        pullRequest = $PullRequest
    }
}

function Write-EventsThroughRecorder {
    param(
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object[]] $Events,
        [Parameter(Mandatory)] [string] $RecorderPath
    )

    [IO.Directory]::CreateDirectory($ExternalRoot) | Out-Null
    foreach ($event in @($Events)) {
        $eventJson = $event | ConvertTo-Json -Compress -Depth 30
        & pwsh -NoProfile -File $RecorderPath -ExternalRunRoot $ExternalRoot -RunId $RunId -EventJson $eventJson | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "real recorder should accept event $($event.eventId)"
    }
    return Join-Path (Join-Path $ExternalRoot $RunId) 'events.jsonl'
}

function Read-LedgerEvents {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return @(Get-Content -LiteralPath $LedgerPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$contractPaths = [ordered]@{
    workerPair = Join-Path $skillRoot 'references/worker-pair.md'
    workerHandoffs = Join-Path $skillRoot 'references/worker-handoffs.md'
    automaticFlow = Join-Path $skillRoot 'references/automatic-review-flow.md'
    taskExecution = Join-Path $skillRoot 'references/task-execution.md'
    implementerPrompt = Join-Path $skillRoot 'assets/implementation-prompt.md'
    reviewerPrompt = Join-Path $skillRoot 'assets/reviewer-prompt.md'
}
$recorderPath = Join-Path $PSScriptRoot 'write-performance-event.ps1'

foreach ($entry in $contractPaths.GetEnumerator()) {
    Assert-True (Test-Path -LiteralPath $entry.Value -PathType Leaf) "missing contract $($entry.Key)"
}
Assert-True (Test-Path -LiteralPath $recorderPath -PathType Leaf) 'missing performance recorder entry point'

$workerPairText = Get-Content -LiteralPath $contractPaths.workerPair -Raw
$workerHandoffsText = Get-Content -LiteralPath $contractPaths.workerHandoffs -Raw
$automaticFlowText = Get-Content -LiteralPath $contractPaths.automaticFlow -Raw
$taskExecutionText = Get-Content -LiteralPath $contractPaths.taskExecution -Raw
$implementerPromptText = Get-Content -LiteralPath $contractPaths.implementerPrompt -Raw
$reviewerPromptText = Get-Content -LiteralPath $contractPaths.reviewerPrompt -Raw

$requiredEvents = @(
    'story_started', 'implementation_started', 'task_ready_for_review',
    'review_started', 'review_findings', 'review_accepted',
    'correction_started', 'correction_ready', 'final_review_started',
    'final_review_accepted', 'wait_started', 'wait_ended', 'pr_ready'
)
foreach ($eventType in $requiredEvents) {
    Assert-Contains $workerPairText $eventType "worker-pair ownership matrix"
}
foreach ($text in @($workerPairText, $workerHandoffsText, $automaticFlowText, $taskExecutionText, $implementerPromptText, $reviewerPromptText)) {
    Assert-Contains $text 'reviewAttemptId' 'stable review-attempt identity'
    Assert-Contains $text 'waitId' 'stable wait identity'
    Assert-Contains $text 'model/effort' 'model/effort provenance'
    Assert-Contains $text 'unavailable' 'honest usage fallback'
    Assert-Contains $text 'telemetry-only' 'no telemetry-only workflow message'
}
foreach ($text in @($workerHandoffsText, $automaticFlowText, $taskExecutionText, $implementerPromptText)) {
    Assert-Contains $text 'write-performance-event.ps1' 'actual recorder entry point'
    Assert-Contains $text 'story_end_only' 'story-end-only mode contract'
    Assert-Contains $text 'per_task' 'per-task mode contract'
}
Assert-Contains $reviewerPromptText 'review_started' 'reviewer start boundary'
Assert-Contains $reviewerPromptText 'final_review_started' 'reviewer final boundary'
Assert-Contains $taskExecutionText 'implementer owns `correction_started` and `correction_ready`' 'implementer final-correction ownership'
Assert-Contains $taskExecutionText 'reviewer owns' 'reviewer final-review ownership'
Assert-Contains $implementerPromptText 'The implementer owns task and final-story' 'implementer prompt correction ownership'
Assert-Contains $implementerPromptText '`final_review_started`' 'implementer prompt final-review ownership'

$revisionA = 'a' * 40
$revisionB = 'b' * 40
$revisionC = 'c' * 40
$perTask = New-WorkflowState 'per_task'
Assert-True ((Record-Transition $perTask 'implementation_started' 'task-156-phase-1') -eq 'recorded') 'per_task implementation start should record'
$perTask.currentRevision = $revisionA
Assert-True ((Record-Transition $perTask 'task_ready_for_review' 'task-156-phase-1' $revisionA) -eq 'recorded') 'per_task ready boundary should record'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-1' 'task-156-attempt-1' $revisionA) -eq 'recorded') 'initial task review should record'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-1' 'task-156-attempt-1' $revisionA) -eq 'duplicate') 'duplicate handoff must not add an attempt'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-2' 'task-156-stale-attempt' $revisionB) -eq 'stale') 'stale revision must not add an attempt'
Assert-True (@($perTask.attempts.Keys).Count -eq 1) 'duplicate/stale task handoffs must leave one attempt'
Assert-True ((Close-ReviewAttempt $perTask 'task-156-attempt-1' $revisionA) -eq 'recorded') 'finding boundary should close the current attempt'
Assert-True ((Record-Transition $perTask 'correction_started' 'task-156-correction-1') -eq 'recorded') 'correction start should record'
$perTask.currentRevision = $revisionB
Assert-True ((Record-Transition $perTask 'correction_ready' 'task-156-correction-1' $revisionB) -eq 'recorded') 'correction-ready boundary should record'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-2' 'task-156-attempt-2' $revisionB) -eq 'recorded') 'correction re-review should record'
Assert-True ((Close-ReviewAttempt $perTask 'task-156-attempt-2' $revisionB) -eq 'recorded') 'task acceptance boundary should close the re-review'
Assert-True ((Record-WaitBoundary $perTask 'wait_started' 'task-156-review-wait') -eq 'recorded') 'explicit wait start should record'
Assert-True ((Record-WaitBoundary $perTask 'wait_ended' 'task-156-review-wait') -eq 'recorded') 'explicit wait end should record'
Assert-True ((Record-WaitBoundary $perTask 'wait_started' 'task-156-review-wait') -eq 'duplicate') 'replayed wait must not create a second boundary'

$storyEndOnly = New-WorkflowState 'story_end_only'
Assert-True ((Record-Transition $storyEndOnly 'implementation_started' 'task-156-phase-1') -eq 'recorded') 'story_end_only implementation start should record'
$storyEndOnly.currentRevision = $revisionA
Assert-True ((Record-Transition $storyEndOnly 'task_ready_for_review' 'task-156-phase-1' $revisionA) -eq 'recorded') 'story_end_only implementation-ready boundary should record'
Assert-True ((Start-ReviewAttempt $storyEndOnly 'task' 'task-156-request-1' 'task-156-invalid-task-attempt' $revisionA) -eq 'mode_rejected') 'story_end_only must reject per-task review attempts'
Assert-True ((Start-ReviewAttempt $storyEndOnly 'final_story' 'story-156-final-request' 'story-156-final-attempt-1' $revisionA) -eq 'recorded') 'story_end_only final review should record'
Assert-True ((Close-ReviewAttempt $storyEndOnly 'story-156-final-attempt-1' $revisionA) -eq 'recorded') 'story_end_only final acceptance should close the attempt'
Assert-True (@($storyEndOnly.attempts.Keys).Count -eq 1) 'story_end_only must retain only the final attempt'

$externalRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-lifecycle-bindings-' + [guid]::NewGuid().ToString('N'))
$perTaskRunId = 'synthetic-lifecycle-per-task'
$storyEndRunId = 'synthetic-lifecycle-story-end-only'
$perTaskEvents = @(
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-10T00:00:00Z' -Scope story -Role coordinator -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-implementation-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-10T00:01:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-implementation-1' -Role implementer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-implementation-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-10T00:02:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-implementation-1' -Revision $revisionA -Role implementer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-10T00:03:00Z' -Scope task -TaskRef 156 -WaitId 'per-task-review-wait' -WaitKind reviewer -Role coordinator -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-10T00:04:00Z' -Scope task -TaskRef 156 -WaitId 'per-task-review-wait' -WaitKind reviewer -Role coordinator -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-review-start-1' -EventType 'review_started' -OccurredAtUtc '2026-10-10T00:05:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-review-1' -ReviewRequestId 'per-task-review-request-1' -ReviewAttemptId 'per-task-review-attempt-1' -ReviewKind initial_task -ReviewAttemptOrdinal 1 -Revision $revisionA -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-review-findings-1' -EventType 'review_findings' -OccurredAtUtc '2026-10-10T00:06:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-review-1' -ReviewRequestId 'per-task-review-request-1' -ReviewAttemptId 'per-task-review-attempt-1' -ReviewKind initial_task -ReviewAttemptOrdinal 1 -Revision $revisionA -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-correction-start' -EventType 'correction_started' -OccurredAtUtc '2026-10-10T00:07:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-correction-1' -CorrectionId 'per-task-correction-1' -SupersedesReviewAttemptId 'per-task-review-attempt-1' -Role implementer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-correction-ready' -EventType 'correction_ready' -OccurredAtUtc '2026-10-10T00:08:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-correction-1' -CorrectionId 'per-task-correction-1' -SupersedesReviewAttemptId 'per-task-review-attempt-1' -Revision $revisionB -Role implementer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-review-start-2' -EventType 'review_started' -OccurredAtUtc '2026-10-10T00:09:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-review-2' -ReviewRequestId 'per-task-review-request-2' -ReviewAttemptId 'per-task-review-attempt-2' -ReviewKind correction_rereview -ReviewAttemptOrdinal 1 -Revision $revisionB -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-review-accepted-2' -EventType 'review_accepted' -OccurredAtUtc '2026-10-10T00:10:00Z' -Scope task -TaskRef 156 -PhaseId 'per-task-review-2' -ReviewRequestId 'per-task-review-request-2' -ReviewAttemptId 'per-task-review-attempt-2' -ReviewKind correction_rereview -ReviewAttemptOrdinal 1 -Revision $revisionB -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-final-start-1' -EventType 'final_review_started' -OccurredAtUtc '2026-10-10T00:11:00Z' -Scope final_story -PhaseId 'per-task-final-1' -ReviewRequestId 'per-task-final-request-1' -ReviewAttemptId 'per-task-final-attempt-1' -ReviewKind final_story -ReviewAttemptOrdinal 1 -Revision $revisionB -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-final-findings-1' -EventType 'review_findings' -OccurredAtUtc '2026-10-10T00:12:00Z' -Scope final_story -PhaseId 'per-task-final-1' -ReviewRequestId 'per-task-final-request-1' -ReviewAttemptId 'per-task-final-attempt-1' -ReviewKind final_story -ReviewAttemptOrdinal 1 -Revision $revisionB -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-final-correction-start' -EventType 'correction_started' -OccurredAtUtc '2026-10-10T00:13:00Z' -Scope final_story -PhaseId 'per-task-final-correction-1' -CorrectionId 'per-task-final-correction-1' -SupersedesReviewAttemptId 'per-task-final-attempt-1' -Role implementer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-final-correction-ready' -EventType 'correction_ready' -OccurredAtUtc '2026-10-10T00:14:00Z' -Scope final_story -PhaseId 'per-task-final-correction-1' -CorrectionId 'per-task-final-correction-1' -SupersedesReviewAttemptId 'per-task-final-attempt-1' -Revision $revisionC -Role implementer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-final-start-2' -EventType 'final_review_started' -OccurredAtUtc '2026-10-10T00:15:00Z' -Scope final_story -PhaseId 'per-task-final-2' -ReviewRequestId 'per-task-final-request-1' -ReviewAttemptId 'per-task-final-attempt-2' -ReviewKind final_story_rereview -ReviewAttemptOrdinal 2 -Revision $revisionC -Role reviewer -ReviewMode per_task),
    (New-LifecycleEvent -RunId $perTaskRunId -EventId 'per-task-final-accepted-2' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-10T00:16:00Z' -Scope final_story -PhaseId 'per-task-final-2' -ReviewRequestId 'per-task-final-request-1' -ReviewAttemptId 'per-task-final-attempt-2' -ReviewKind final_story_rereview -ReviewAttemptOrdinal 2 -Revision $revisionC -Role reviewer -ReviewMode per_task)
)
$storyEndEvents = @(
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-story-start' -EventType 'story_started' -OccurredAtUtc '2026-10-10T01:00:00Z' -Scope story -Role coordinator -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-implementation-start' -EventType 'implementation_started' -OccurredAtUtc '2026-10-10T01:01:00Z' -Scope task -TaskRef 156 -PhaseId 'story-end-implementation-1' -Role implementer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-implementation-ready' -EventType 'task_ready_for_review' -OccurredAtUtc '2026-10-10T01:02:00Z' -Scope task -TaskRef 156 -PhaseId 'story-end-implementation-1' -Revision $revisionA -Role implementer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-wait-start' -EventType 'wait_started' -OccurredAtUtc '2026-10-10T01:03:00Z' -Scope story -WaitId 'story-end-final-wait' -WaitKind final-review -Role coordinator -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-wait-end' -EventType 'wait_ended' -OccurredAtUtc '2026-10-10T01:04:00Z' -Scope story -WaitId 'story-end-final-wait' -WaitKind final-review -Role coordinator -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-final-start-1' -EventType 'final_review_started' -OccurredAtUtc '2026-10-10T01:05:00Z' -Scope final_story -PhaseId 'story-end-final-1' -ReviewRequestId 'story-end-final-request-1' -ReviewAttemptId 'story-end-final-attempt-1' -ReviewKind final_story -ReviewAttemptOrdinal 1 -Revision $revisionA -Role reviewer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-final-findings-1' -EventType 'review_findings' -OccurredAtUtc '2026-10-10T01:06:00Z' -Scope final_story -PhaseId 'story-end-final-1' -ReviewRequestId 'story-end-final-request-1' -ReviewAttemptId 'story-end-final-attempt-1' -ReviewKind final_story -ReviewAttemptOrdinal 1 -Revision $revisionA -Role reviewer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-final-correction-start' -EventType 'correction_started' -OccurredAtUtc '2026-10-10T01:07:00Z' -Scope final_story -PhaseId 'story-end-final-correction-1' -CorrectionId 'story-end-final-correction-1' -SupersedesReviewAttemptId 'story-end-final-attempt-1' -Role implementer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-final-correction-ready' -EventType 'correction_ready' -OccurredAtUtc '2026-10-10T01:08:00Z' -Scope final_story -PhaseId 'story-end-final-correction-1' -CorrectionId 'story-end-final-correction-1' -SupersedesReviewAttemptId 'story-end-final-attempt-1' -Revision $revisionB -Role implementer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-final-start-2' -EventType 'final_review_started' -OccurredAtUtc '2026-10-10T01:09:00Z' -Scope final_story -PhaseId 'story-end-final-2' -ReviewRequestId 'story-end-final-request-1' -ReviewAttemptId 'story-end-final-attempt-2' -ReviewKind final_story_rereview -ReviewAttemptOrdinal 2 -Revision $revisionB -Role reviewer -ReviewMode story_end_only),
    (New-LifecycleEvent -RunId $storyEndRunId -EventId 'story-end-final-accepted-2' -EventType 'final_review_accepted' -OccurredAtUtc '2026-10-10T01:10:00Z' -Scope final_story -PhaseId 'story-end-final-2' -ReviewRequestId 'story-end-final-request-1' -ReviewAttemptId 'story-end-final-attempt-2' -ReviewKind final_story_rereview -ReviewAttemptOrdinal 2 -Revision $revisionB -Role reviewer -ReviewMode story_end_only)
)

try {
    $perTaskLedger = Write-EventsThroughRecorder -ExternalRoot $externalRoot -RunId $perTaskRunId -Events $perTaskEvents -RecorderPath $recorderPath
    $perTaskLedgerEvents = Read-LedgerEvents $perTaskLedger
    Assert-True ($perTaskLedgerEvents.Count -eq $perTaskEvents.Count) 'per_task recorder ledger should contain every lifecycle boundary'
    Assert-True (@($perTaskLedgerEvents | Where-Object eventType -eq 'implementation_started').Count -eq 1 -and
        @($perTaskLedgerEvents | Where-Object eventType -eq 'task_ready_for_review').Count -eq 1) 'per_task implementation boundaries should pair once'
    Assert-True (@($perTaskLedgerEvents | Where-Object eventType -eq 'review_started').Count -eq 2 -and
        @($perTaskLedgerEvents | Where-Object eventType -eq 'review_accepted').Count -eq 1) 'per_task task review attempts should include initial and correction re-review'
    Assert-True (@($perTaskLedgerEvents | Where-Object eventType -eq 'correction_started').Count -eq 2 -and
        @($perTaskLedgerEvents | Where-Object eventType -eq 'correction_ready').Count -eq 2) 'per_task task and final-story corrections should pair once'
    Assert-True (@($perTaskLedgerEvents | Where-Object eventType -eq 'final_review_started').Count -eq 2 -and
        @($perTaskLedgerEvents | Where-Object eventType -eq 'final_review_accepted').Count -eq 1) 'per_task final review should include a finding and re-review'
    Assert-True (@($perTaskLedgerEvents | Where-Object eventType -eq 'wait_started').Count -eq 1 -and
        @($perTaskLedgerEvents | Where-Object eventType -eq 'wait_ended').Count -eq 1) 'per_task wait boundaries should pair once'
    $perTaskCountBeforeReplay = $perTaskLedgerEvents.Count
    Write-EventsThroughRecorder -ExternalRoot $externalRoot -RunId $perTaskRunId -Events @($perTaskEvents | Where-Object eventId -eq 'per-task-review-start-1') -RecorderPath $recorderPath | Out-Null
    Assert-True ((Read-LedgerEvents $perTaskLedger).Count -eq $perTaskCountBeforeReplay) 'exact review handoff replay must not add a ledger attempt'
    Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-stale-request' 'task-156-stale-attempt-2' $revisionC) -eq 'stale') 'stale handoff must be rejected before recorder append'
    Assert-True ((Read-LedgerEvents $perTaskLedger).Count -eq $perTaskCountBeforeReplay) 'stale handoff rejection must not add a ledger event'

    $storyEndLedger = Write-EventsThroughRecorder -ExternalRoot $externalRoot -RunId $storyEndRunId -Events $storyEndEvents -RecorderPath $recorderPath
    $storyEndLedgerEvents = Read-LedgerEvents $storyEndLedger
    Assert-True ($storyEndLedgerEvents.Count -eq $storyEndEvents.Count) 'story_end_only recorder ledger should contain every lifecycle boundary'
    Assert-True (@($storyEndLedgerEvents | Where-Object eventType -eq 'implementation_started').Count -eq 1 -and
        @($storyEndLedgerEvents | Where-Object eventType -eq 'task_ready_for_review').Count -eq 1) 'story_end_only must record the implementation-ready end without task review dispatch'
    Assert-True (@($storyEndLedgerEvents | Where-Object { $_.scope -eq 'task' -and $_.eventType -in @('review_started', 'review_findings', 'review_accepted', 'correction_started', 'correction_ready') }).Count -eq 0) 'story_end_only must omit task-scoped review/correction events'
    Assert-True (@($storyEndLedgerEvents | Where-Object eventType -eq 'final_review_started').Count -eq 2 -and
        @($storyEndLedgerEvents | Where-Object eventType -eq 'review_findings').Count -eq 1 -and
        @($storyEndLedgerEvents | Where-Object eventType -eq 'correction_started').Count -eq 1 -and
        @($storyEndLedgerEvents | Where-Object eventType -eq 'correction_ready').Count -eq 1 -and
        @($storyEndLedgerEvents | Where-Object eventType -eq 'final_review_accepted').Count -eq 1) 'story_end_only must retain final-story finding, correction, and re-review boundaries'
    Assert-True (@($storyEndLedgerEvents | Where-Object eventType -eq 'wait_started').Count -eq 1 -and
        @($storyEndLedgerEvents | Where-Object eventType -eq 'wait_ended').Count -eq 1) 'story_end_only wait boundaries should pair once'
    $storyEndCountBeforeReplay = $storyEndLedgerEvents.Count
    Write-EventsThroughRecorder -ExternalRoot $externalRoot -RunId $storyEndRunId -Events @($storyEndEvents | Where-Object eventId -eq 'story-end-final-start-1') -RecorderPath $recorderPath | Out-Null
    Assert-True ((Read-LedgerEvents $storyEndLedger).Count -eq $storyEndCountBeforeReplay) 'exact final review replay must not add a story_end_only attempt'
}
finally {
    if (Test-Path -LiteralPath $externalRoot) {
        Remove-Item -LiteralPath $externalRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: synthetic lifecycle ownership, stable duplicate/stale guards, both review modes, and real-recorder idempotency; no live Taiga/provider/telemetry evidence claimed.'
