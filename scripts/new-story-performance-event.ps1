# Construct one version-1 telemetry event from explicit type-scoped inputs.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PerformanceEventValue {
    param([AllowNull()] [object] $Value)
    return $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string] $Value)
}

function Get-PerformanceEventNullableValue {
    param([AllowNull()] [object] $Value)
    if (-not (Test-PerformanceEventValue $Value)) { return $null }
    [string] $Value
}

function New-StoryPerformanceEvent {
    param(
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [Parameter(Mandatory)] [int] $ProjectId,
        [Parameter(Mandatory)] [int] $StoryId,
        [Parameter(Mandatory)] [int] $StoryRef,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [ValidateSet('story','task','final_story')] [string] $Scope,
        [Parameter(Mandatory)] [ValidateSet('coordinator','implementer','reviewer')] [string] $Role,
        [Parameter(Mandatory)] [ValidateSet('per_task','story_end_only')] [string] $ReviewMode,
        [AllowNull()] [object] $TaskRef = $null,
        [AllowNull()] [string] $PhaseId = $null,
        [AllowNull()] [string] $CorrectionId = $null,
        [AllowNull()] [string] $ReviewRequestId = $null,
        [AllowNull()] [string] $ReviewAttemptId = $null,
        [AllowNull()] [string] $ReviewKind = $null,
        [AllowNull()] [object] $ReviewAttemptOrdinal = $null,
        [AllowNull()] [string] $SupersedesReviewAttemptId = $null,
        [AllowNull()] [string] $Revision = $null,
        [AllowNull()] [string] $SessionId = $null,
        [AllowNull()] [string] $WorkerId = $null,
        [AllowNull()] [string] $TransitionId = $null,
        [AllowNull()] [object] $Provenance = $null,
        [AllowNull()] [object] $Usage = $null,
        [AllowNull()] [string] $WaitId = $null,
        [AllowNull()] [string] $WaitKind = $null,
        [AllowNull()] [object] $PullRequest = $null
    )

    $reviewEvents = @('review_started', 'review_findings', 'review_accepted', 'final_review_started', 'final_review_accepted')
    $correctionEvents = @('correction_started', 'correction_ready')
    $waitEvents = @('wait_started', 'wait_ended')
    $phaseEvents = @('implementation_started', 'task_ready_for_review') + $reviewEvents + $correctionEvents
    $isReview = $EventType -in $reviewEvents
    $isCorrection = $EventType -in $correctionEvents
    $isWait = $EventType -in $waitEvents
    $phaseValue = Get-PerformanceEventNullableValue $PhaseId
    $correctionValue = Get-PerformanceEventNullableValue $CorrectionId
    $reviewRequestValue = Get-PerformanceEventNullableValue $ReviewRequestId
    $reviewAttemptValue = Get-PerformanceEventNullableValue $ReviewAttemptId
    $reviewKindValue = Get-PerformanceEventNullableValue $ReviewKind
    $supersedesValue = Get-PerformanceEventNullableValue $SupersedesReviewAttemptId
    $revisionValue = Get-PerformanceEventNullableValue $Revision
    $sessionValue = Get-PerformanceEventNullableValue $SessionId
    $workerValue = Get-PerformanceEventNullableValue $WorkerId
    $transitionValue = Get-PerformanceEventNullableValue $TransitionId
    $waitIdValue = Get-PerformanceEventNullableValue $WaitId
    $waitKindValue = Get-PerformanceEventNullableValue $WaitKind

    $reviewValues = @($reviewRequestValue, $reviewAttemptValue, $reviewKindValue, $ReviewAttemptOrdinal)
    if (-not $isReview -and @($reviewValues | Where-Object { Test-PerformanceEventValue $_ }).Count -gt 0) {
        throw "event-type constructor rejected review identity on non-review event '$EventType'"
    }
    if (-not $isCorrection -and ((Test-PerformanceEventValue $correctionValue) -or (Test-PerformanceEventValue $supersedesValue))) {
        throw "event-type constructor rejected correction identity on non-correction event '$EventType'"
    }
    if ($isCorrection -and @($reviewValues | Where-Object { Test-PerformanceEventValue $_ }).Count -gt 0) {
        throw "event-type constructor rejected review identity on correction event '$EventType'"
    }
    if (-not $isWait -and ((Test-PerformanceEventValue $waitIdValue) -or (Test-PerformanceEventValue $waitKindValue))) {
        throw "event-type constructor rejected wait identity on non-wait event '$EventType'"
    }
    if ($EventType -notin @('pr_ready') -and $null -ne $PullRequest) {
        throw "event-type constructor rejected pullRequest on non-pr_ready event '$EventType'"
    }
    if ($EventType -notin $phaseEvents -and (Test-PerformanceEventValue $phaseValue)) {
        throw "event-type constructor rejected phaseId on boundary '$EventType'"
    }

    $event = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event'
        eventId = $EventId
        runId = $RunId
        projectId = $ProjectId
        storyId = $StoryId
        storyRef = $StoryRef
        taskRef = $TaskRef
        role = $Role
        sessionId = $sessionValue
        workerId = $workerValue
        transitionId = if ($null -eq $transitionValue) { $EventId } else { $transitionValue }
        scope = $Scope
        phaseId = if ($EventType -in $phaseEvents) { $phaseValue } else { $null }
        correctionId = if ($isCorrection) { $correctionValue } else { $null }
        reviewRequestId = if ($isReview) { $reviewRequestValue } else { $null }
        reviewAttemptId = if ($isReview) { $reviewAttemptValue } else { $null }
        reviewKind = if ($isReview) { $reviewKindValue } else { $null }
        reviewAttemptOrdinal = if ($isReview) { $ReviewAttemptOrdinal } else { $null }
        supersedesReviewAttemptId = if ($isCorrection) { $supersedesValue } else { $null }
        eventType = $EventType
        occurredAtUtc = $OccurredAtUtc
        revision = $revisionValue
        reviewMode = $ReviewMode
        provenance = $Provenance
        usage = $Usage
        waitId = if ($isWait) { $waitIdValue } else { $null }
        waitKind = if ($isWait) { $waitKindValue } else { $null }
        pullRequest = if ($EventType -ceq 'pr_ready') { $PullRequest } else { $null }
    }
    [pscustomobject] $event
}
