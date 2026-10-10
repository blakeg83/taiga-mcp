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

$revisionA = 'a' * 40
$revisionB = 'b' * 40
$perTask = New-WorkflowState 'per_task'
Assert-True ((Record-Transition $perTask 'implementation_started' 'task-156-phase-1') -eq 'recorded') 'per_task implementation start should record'
$perTask.currentRevision = $revisionA
Assert-True ((Record-Transition $perTask 'task_ready_for_review' 'task-156-phase-1' $revisionA) -eq 'recorded') 'per_task ready boundary should record'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-1' 'task-156-attempt-1' $revisionA) -eq 'recorded') 'initial task review should record'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-1' 'task-156-attempt-1' $revisionA) -eq 'duplicate') 'duplicate handoff must not add an attempt'
Assert-True ((Start-ReviewAttempt $perTask 'task' 'task-156-request-2' 'task-156-stale-attempt' $revisionB) -eq 'stale') 'stale revision must not add an attempt'
Assert-True (@($perTask.attempts.Keys).Count -eq 1) 'duplicate/stale task handoffs must leave one attempt'
Assert-True ((Close-ReviewAttempt $perTask 'task-156-attempt-1' $revisionA) -eq 'recorded') 'finding boundary should close the current attempt'
Assert-True ((Record-Transition $perTask 'correction_started' 'task-156-correction-1' $revisionA) -eq 'recorded') 'correction start should record'
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
Assert-True ((Start-ReviewAttempt $storyEndOnly 'task' 'task-156-request-1' 'task-156-invalid-task-attempt' $revisionA) -eq 'mode_rejected') 'story_end_only must reject per-task review attempts'
Assert-True ((Start-ReviewAttempt $storyEndOnly 'final_story' 'story-156-final-request' 'story-156-final-attempt-1' $revisionA) -eq 'recorded') 'story_end_only final review should record'
Assert-True ((Close-ReviewAttempt $storyEndOnly 'story-156-final-attempt-1' $revisionA) -eq 'recorded') 'story_end_only final acceptance should close the attempt'
Assert-True (@($storyEndOnly.attempts.Keys).Count -eq 1) 'story_end_only must retain only the final attempt'

$externalRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-lifecycle-bindings-' + [guid]::NewGuid().ToString('N'))
$runId = 'synthetic-lifecycle-bindings'
$storyStart = [ordered]@{
    schemaVersion = 1
    kind = 'story_performance_event'
    eventId = 'synthetic-lifecycle-story-start'
    runId = $runId
    projectId = 12
    storyId = 728
    storyRef = 144
    taskRef = $null
    role = 'coordinator'
    sessionId = 'synthetic-coordinator-session'
    workerId = 'synthetic-coordinator'
    transitionId = 'synthetic-lifecycle-story-start'
    scope = 'story'
    phaseId = $null
    correctionId = $null
    reviewRequestId = $null
    reviewAttemptId = $null
    reviewKind = $null
    reviewAttemptOrdinal = $null
    supersedesReviewAttemptId = $null
    eventType = 'story_started'
    occurredAtUtc = '2026-10-10T00:00:00Z'
    revision = $null
    reviewMode = 'per_task'
    provenance = [ordered]@{ source = 'synthetic_fixture'; observedBy = 'validator'; coverage = 'fixed UTC fixture'; synthetic = $true }
    usage = $null
    waitId = $null
    waitKind = $null
    pullRequest = $null
}

try {
    [IO.Directory]::CreateDirectory($externalRoot) | Out-Null
    $eventJson = $storyStart | ConvertTo-Json -Compress -Depth 20
    & pwsh -NoProfile -File $recorderPath -ExternalRunRoot $externalRoot -RunId $runId -EventJson $eventJson | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'real recorder should accept the synthetic story_started event'
    $ledgerPath = Join-Path (Join-Path $externalRoot $runId) 'events.jsonl'
    Assert-True (Test-Path -LiteralPath $ledgerPath -PathType Leaf) 'real recorder should create the external ledger'
    & pwsh -NoProfile -File $recorderPath -ExternalRunRoot $externalRoot -RunId $runId -EventJson $eventJson | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'real recorder should treat an exact event replay as a no-op'
    $ledgerLines = @(Get-Content -LiteralPath $ledgerPath)
    Assert-True ($ledgerLines.Count -eq 1) 'exact event replay must not append a second ledger line'
}
finally {
    if (Test-Path -LiteralPath $externalRoot) {
        Remove-Item -LiteralPath $externalRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: synthetic lifecycle ownership, stable duplicate/stale guards, both review modes, and real-recorder idempotency; no live Taiga/provider/telemetry evidence claimed.'
