[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Automatic review-flow assertion failed: $Message" }
}

function New-StoryState {
    param([ValidateSet('per_task', 'story_end_only')] [string] $ReviewMode)

    return [ordered]@{
        reviewMode = $ReviewMode
        authorization = 'start-87'
        branch = 'codex/story-87'
        implementer = 'implementer-story-87'
        reviewer = 'reviewer-story-87'
        coordinator = 'coordinator-story-87'
        currentTaskIndex = 0
        tasks = @(
            [ordered]@{ taskId = 65; ref = '#65'; state = 'in_progress'; pendingSha = $null; acceptedSha = $null },
            [ordered]@{ taskId = 66; ref = '#66'; state = 'not_started'; pendingSha = $null; acceptedSha = $null }
        )
        pendingReview = $null
        consumedEvents = @()
        actions = @()
    }
}

function Get-CurrentTask {
    param([System.Collections.IDictionary] $State)
    return $State.tasks[$State.currentTaskIndex]
}

function Add-Unique {
    param([System.Collections.IDictionary] $State, [string] $EventId)
    if ($State.consumedEvents -contains $EventId) { return $false }
    $State.consumedEvents = @($State.consumedEvents) + $EventId
    return $true
}

function Add-Action {
    param(
        [System.Collections.IDictionary] $State,
        [string] $Kind,
        [string] $TaskRef,
        [string] $Revision,
        [string] $Sender,
        [string] $Destination
    )
    $key = "$Kind|$TaskRef|$Revision"
    if (@($State.actions | Where-Object { $_.key -eq $key }).Count -gt 0) { return $false }
    $State.actions = @($State.actions) + [ordered]@{
        key = $key
        kind = $Kind
        task = $TaskRef
        revision = $Revision
        branch = $State.branch
        sender = $Sender
        destination = $Destination
        worker = if ($Kind -eq 'review') { $State.reviewer } else { $State.implementer }
    }
    return $true
}

function Apply-Event {
    param([System.Collections.IDictionary] $State, [System.Collections.IDictionary] $Event)

    foreach ($required in @('eventId', 'kind', 'taskId', 'revision', 'authorization')) {
        if (-not $Event.Contains($required) -or [string]::IsNullOrWhiteSpace([string]$Event[$required])) { throw "$required is required." }
    }
    if ([string]$Event.authorization -cne [string]$State.authorization) { throw 'Start authorization binding is stale.' }
    if (-not (Add-Unique $State ([string]$Event.eventId))) { return [ordered]@{ decision = 'duplicate'; state = $State } }

    $task = Get-CurrentTask $State
    if ([long]$Event.taskId -ne [long]$task.taskId) { throw 'event is not for the current ordered task.' }

    switch ([string]$Event.kind) {
        'unknown_delivery' {
            return [ordered]@{ decision = 'escalate_coordinator'; state = $State }
        }
        'revision_conflict' {
            return [ordered]@{ decision = 'escalate_coordinator'; state = $State }
        }
        'ready_for_review' {
            if ([string]$State.reviewMode -ne 'per_task') { throw 'per-task review dispatch is not available in story_end_only.' }
            if ([string]::IsNullOrWhiteSpace([string]$Event.reviewerId) -or [string]$Event.reviewerId -cne [string]$State.reviewer) { throw 'reviewer identity is required for review dispatch.' }
            if ($task.state -notin @('in_progress', 'awaiting_review')) { throw 'task is not ready for review.' }
            if ($State.pendingReview -and [string]$State.pendingReview.revision -cne [string]$Event.revision) { throw 'a different review is already pending.' }
            $task.state = 'awaiting_review'
            $task.pendingSha = [string]$Event.revision
            $State.pendingReview = [ordered]@{ taskId = $task.taskId; revision = [string]$Event.revision; reviewerId = [string]$Event.reviewerId; previousRevision = if ($Event.Contains('previousRevision')) { [string]$Event.previousRevision } else { $null } }
            $created = Add-Action $State 'review' $task.ref ([string]$Event.revision) $State.implementer $State.reviewer
            return [ordered]@{ decision = if ($created) { 'dispatch_review' } else { 'duplicate' }; state = $State }
        }
        'changes_requested' {
            if ($null -eq $State.pendingReview -or [string]$State.pendingReview.revision -cne [string]$Event.reviewedRevision) { throw 'finding is not bound to the pending review revision.' }
            if ([string]$Event.reviewerId -cne [string]$State.reviewer) { throw 'finding sender is not the assigned reviewer.' }
            $task.state = 'in_progress'
            $task.pendingSha = $null
            $State.pendingReview = $null
            $created = Add-Action $State 'correction' $task.ref ([string]$Event.revision) $State.reviewer $State.implementer
            return [ordered]@{ decision = if ($created) { 'route_correction' } else { 'duplicate' }; state = $State }
        }
        'implementation_ready' {
            if ([string]$State.reviewMode -ne 'story_end_only') { throw 'implementation-only advancement is not allowed in per_task mode.' }
            if ($task.state -notin @('in_progress', 'implementation_complete')) { throw 'task is not ready to advance by implementation evidence.' }
            $task.state = 'implementation_complete'
            $task.pendingSha = [string]$Event.revision
            if ($State.currentTaskIndex -eq ($State.tasks.Count - 1)) {
                $created = Add-Action $State 'story_review' $task.ref ([string]$Event.revision) $State.coordinator $State.reviewer
                return [ordered]@{ decision = if ($created) { 'final_story_review' } else { 'duplicate' }; state = $State }
            }
            $State.currentTaskIndex = [int]$State.currentTaskIndex + 1
            $next = Get-CurrentTask $State
            $next.state = 'in_progress'
            $created = Add-Action $State 'implementation' $next.ref 'pending' $State.coordinator $State.implementer
            return [ordered]@{ decision = if ($created) { 'advance_next_task_without_review' } else { 'duplicate' }; state = $State }
        }
        'accepted' {
            if ([string]$State.reviewMode -ne 'per_task') { throw 'task acceptance is not available before final story review.' }
            if ($null -eq $State.pendingReview -or [string]$State.pendingReview.revision -cne [string]$Event.revision) { throw 'acceptance is not bound to the pending exact revision.' }
            if ([string]$Event.reviewerId -cne [string]$State.reviewer) { throw 'acceptance sender is not the assigned reviewer.' }
            if ([string]$Event.criteria -cne 'complete') { throw 'acceptance must cover all task criteria.' }
            $task.state = 'accepted'
            $task.acceptedSha = [string]$Event.revision
            $task.pendingSha = $null
            $State.pendingReview = $null
            $State.actions = @($State.actions) + [ordered]@{ key = "taiga|$($task.ref)|$($Event.revision)"; kind = 'taiga_accept'; task = $task.ref; revision = [string]$Event.revision; branch = $State.branch; sender = $State.coordinator; destination = 'Taiga'; worker = 'coordinator' }
            if ($State.currentTaskIndex -eq ($State.tasks.Count - 1)) { return [ordered]@{ decision = 'final_story_review'; state = $State } }
            $State.currentTaskIndex = [int]$State.currentTaskIndex + 1
            $next = Get-CurrentTask $State
            $next.state = 'in_progress'
            $created = Add-Action $State 'implementation' $next.ref 'pending' $State.coordinator $State.implementer
            return [ordered]@{ decision = if ($created) { 'advance_next_task' } else { 'duplicate' }; state = $State }
        }
        'idle' { return [ordered]@{ decision = 'wait'; state = $State } }
        default { throw "unsupported event kind: $($Event.kind)" }
    }
}

$state = New-StoryState 'per_task'
$ready = Apply-Event $state @{ eventId = 'ready-per_task'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($ready.decision -eq 'dispatch_review') 'per_task should dispatch the initial review'
Assert-True (@($state.actions | Where-Object kind -eq 'review').Count -eq 1) 'per_task should prepare one review action'
Assert-True ($state.actions[0].sender -eq $state.implementer -and $state.actions[0].destination -eq $state.reviewer) 'initial review must stay direct between the worker pair'
$duplicate = Apply-Event $state @{ eventId = 'ready-per_task'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($duplicate.decision -eq 'duplicate') 'per_task should ignore duplicate ready events'
$stale = $false
try { Apply-Event $state @{ eventId = 'stale-per_task'; kind = 'accepted'; taskId = 65; revision = 'sha-old'; reviewerId = 'reviewer-story-87'; criteria = 'complete'; authorization = 'start-87' } | Out-Null } catch { $stale = $true }
Assert-True $stale 'per_task should reject stale acceptance'
$finding = Apply-Event $state @{ eventId = 'finding-per_task'; kind = 'changes_requested'; taskId = 65; reviewedRevision = 'sha-a1'; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($finding.decision -eq 'route_correction') 'per_task should route correction to the same pair'
$correctionAction = @($state.actions | Where-Object kind -eq 'correction')[0]
Assert-True ($correctionAction.sender -eq $state.reviewer -and $correctionAction.destination -eq $state.implementer) 'routine findings must go directly to the implementer'
$actionCountBeforeEscalation = @($state.actions).Count
$unknownDelivery = Apply-Event $state @{ eventId = 'unknown-delivery-per_task'; kind = 'unknown_delivery'; taskId = 65; revision = 'sha-a2'; authorization = 'start-87' }
Assert-True ($unknownDelivery.decision -eq 'escalate_coordinator') 'unknown delivery must escalate to the coordinator'
$revisionConflict = Apply-Event $state @{ eventId = 'revision-conflict-per_task'; kind = 'revision_conflict'; taskId = 65; revision = 'sha-a2'; authorization = 'start-87' }
Assert-True ($revisionConflict.decision -eq 'escalate_coordinator') 'revision conflicts must escalate to the coordinator'
Assert-True (@($state.actions).Count -eq $actionCountBeforeEscalation -and $state.currentTaskIndex -eq 0) 'escalation events must not mutate routine review state'
$readyCorrection = Apply-Event $state @{ eventId = 'ready-correction-per_task'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; previousRevision = 'sha-a1'; authorization = 'start-87' }
Assert-True ($readyCorrection.decision -eq 'dispatch_review') 'per_task should dispatch correction re-review'
$accepted = Apply-Event $state @{ eventId = 'accepted-per_task'; kind = 'accepted'; taskId = 65; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; criteria = 'complete'; authorization = 'start-87' }
Assert-True ($accepted.decision -eq 'advance_next_task') 'per_task should advance only after exact acceptance'
Assert-True ($state.currentTaskIndex -eq 1 -and $state.tasks[1].state -eq 'in_progress') 'per_task should start the next declared task'
$idle = Apply-Event $state @{ eventId = 'idle-per_task'; kind = 'idle'; taskId = 66; revision = 'sha-a2'; authorization = 'start-87' }
Assert-True ($idle.decision -eq 'wait') 'per_task should not infer acceptance from idle'

$storyEndState = New-StoryState 'story_end_only'
$implementationReady = Apply-Event $storyEndState @{ eventId = 'implementation-ready-story-end-1'; kind = 'implementation_ready'; taskId = 65; revision = 'sha-b1'; authorization = 'start-87' }
Assert-True ($implementationReady.decision -eq 'advance_next_task_without_review') 'story_end_only should advance on implementation evidence'
Assert-True (@($storyEndState.actions | Where-Object kind -eq 'review').Count -eq 0) 'story_end_only should not dispatch a per-task review'
$perTaskReviewInStoryEnd = $false
try { Apply-Event $storyEndState @{ eventId = 'ready-story-end-invalid'; kind = 'ready_for_review'; taskId = 66; revision = 'sha-b2'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' } | Out-Null } catch { $perTaskReviewInStoryEnd = $true }
Assert-True $perTaskReviewInStoryEnd 'story_end_only should reject per-task review dispatch'
$taskAcceptanceBeforeFinal = $false
try { Apply-Event $storyEndState @{ eventId = 'accepted-story-end-early'; kind = 'accepted'; taskId = 66; revision = 'sha-b2'; reviewerId = 'reviewer-story-87'; criteria = 'complete'; authorization = 'start-87' } | Out-Null } catch { $taskAcceptanceBeforeFinal = $true }
Assert-True $taskAcceptanceBeforeFinal 'story_end_only should defer task acceptance until final story review'
$finalStoryReview = Apply-Event $storyEndState @{ eventId = 'implementation-ready-story-end-2'; kind = 'implementation_ready'; taskId = 66; revision = 'sha-b2'; authorization = 'start-87' }
Assert-True ($finalStoryReview.decision -eq 'final_story_review') 'story_end_only should request final story review after the last task'
Assert-True (@($storyEndState.actions | Where-Object kind -eq 'story_review').Count -eq 1) 'story_end_only should prepare one final story review'

$scopeState = New-StoryState 'per_task'
$scopeError = $false
try { Apply-Event $scopeState @{ eventId = 'scope-change'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a1'; reviewerId = 'reviewer-story-87'; authorization = 'changed-start' } | Out-Null } catch { $scopeError = $true }
Assert-True $scopeError 'scope changes must stop automatic dispatch'

Write-Output 'Passed automatic review-flow fixture: direct worker-pair dispatch/correction, exact acceptance advancement, duplicate/stale/idle guards, coordinator escalation, and scope gating.'
