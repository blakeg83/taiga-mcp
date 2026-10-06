[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Automatic review-flow assertion failed: $Message" }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
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
        pendingEscalations = @()
        consumedEvents = @()
        actions = @()
        turns = @()
        implementerActions = @()
        rejectedImplementerActions = @()
        recoveryObservations = @()
        currentTurnId = 1
        turnStatus = 'active'
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

function Add-ImplementerAction {
    param(
        [System.Collections.IDictionary] $State,
        [string] $Kind,
        [string] $TaskRef,
        [string] $Revision
    )

    $currentTurnActions = @($State.implementerActions | Where-Object { [int]$_.turn -eq [int]$State.currentTurnId })
    $forbiddenWhileReviewPending = @(
        'wait_threads'
        'read_reviewer_chat'
        'review_monitor'
        'keep_alive'
        'unchanged_acknowledgement'
        'source_edit'
        'coordinator_copy'
    )
    $reviewEndpointActions = @('send_review_handoff', 'final_response')
    if ($State.turnStatus -eq 'awaiting_review' -or
        $Kind -eq 'coordinator_copy' -or
        ($null -ne $State.pendingReview -and $Kind -notin $reviewEndpointActions)) {
        $State.rejectedImplementerActions = @($State.rejectedImplementerActions) + [ordered]@{
            kind = $Kind
            task = $TaskRef
            revision = $Revision
            turn = [int]$State.currentTurnId
        }
        if ($State.turnStatus -eq 'awaiting_review') {
            throw "implementer action '$Kind' is forbidden after the review handoff turn ended"
        }
        throw "implementer action '$Kind' is forbidden while review is pending"
    }

    $State.implementerActions = @($State.implementerActions) + [ordered]@{
        kind = $Kind
        task = $TaskRef
        revision = $Revision
        chat = $State.implementer
        turn = [int]$State.currentTurnId
        ordinal = $currentTurnActions.Count + 1
    }
}

function Authorize-ImplementerResume {
    param([System.Collections.IDictionary] $State)

    Assert-True ($State.turnStatus -eq 'awaiting_review') 'reviewer resume requires an ended implementer turn'
    $State.currentTurnId = [int]$State.currentTurnId + 1
    $State.turnStatus = 'active'
}

function End-ImplementerReviewTurn {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Task,
        [string] $HandoffKind
    )

    Assert-True ($null -ne $State.pendingReview) "$HandoffKind requires a pending review"
    Add-ImplementerAction $State 'send_review_handoff' $Task.ref ([string]$Task.pendingSha)
    Add-ImplementerAction $State 'final_response' $Task.ref ([string]$Task.pendingSha)
    $trace = @($State.implementerActions | Where-Object { [int]$_.turn -eq [int]$State.currentTurnId })
    $authorizedPrefixKinds = @('reviewer_message_resume', 'source_edit', 'taiga_reconcile', 'advance_next_task')
    $prefix = @()
    if ($trace.Count -gt 2) {
        $prefix = @($trace | Select-Object -First ($trace.Count - 2))
    }
    $invalidPrefix = @($prefix | Where-Object { [string]$_.kind -notin $authorizedPrefixKinds })
    $hasTerminalHandoffSuffix = ($trace.Count -ge 2 -and
        [string]$trace[-2].kind -ceq 'send_review_handoff' -and
        [string]$trace[-1].kind -ceq 'final_response')
    $ended = ($hasTerminalHandoffSuffix -and $invalidPrefix.Count -eq 0)
    Assert-True $ended "$HandoffKind must terminate from the exact action trace"
    $State.turnStatus = 'awaiting_review'
    $State.turns = @($State.turns) + [ordered]@{
        actor = 'implementer'
        chat = $State.implementer
        turn = [int]$State.currentTurnId
        handoff = $HandoffKind
        task = $Task.ref
        branch = $State.branch
        revision = [string]$Task.pendingSha
        reviewer = $State.reviewer
        authorization = $State.authorization
        state = 'awaiting_review'
        ended = $ended
        lastAction = [string]$trace[-1].kind
        actionCount = $trace.Count
    }
}

function Complete-ReviewHandoff {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Event,
        [switch] $DeliveryFailed
    )

    if ($DeliveryFailed) {
        $failure = [ordered]@{
            eventId = "$($Event.eventId)-delivery-failed"
            kind = 'unknown_delivery'
            taskId = $Event.taskId
            revision = $Event.revision
            authorization = $Event.authorization
        }
        return Apply-Event $State $failure
    }

    $result = Apply-Event $State $Event
    if ($result.decision -eq 'dispatch_review') {
        $handoffKind = 'initial'
        if ($Event.Contains('previousRevision')) { $handoffKind = 'correction' }
        End-ImplementerReviewTurn $State (Get-CurrentTask $State) $handoffKind
    }
    return $result
}

function Resume-ImplementerOnReviewerMessage {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Event
    )

    $result = Apply-Event $State $Event
    if ($result.decision -ne 'duplicate') {
        Authorize-ImplementerResume $State
        Add-ImplementerAction $State 'reviewer_message_resume' ([string]$Event.taskId) ([string]$Event.revision)
        if ($result.decision -in @('advance_next_task', 'final_story_review')) {
            Add-ImplementerAction $State 'taiga_reconcile' ([string]$Event.taskId) ([string]$Event.revision)
        }
        if ($result.decision -eq 'advance_next_task') {
            Add-ImplementerAction $State 'advance_next_task' ([string](Get-CurrentTask $State).ref) 'pending'
        }
    }
    return $result
}

function Observe-HealthyReviewRecovery {
    param([System.Collections.IDictionary] $State)

    if (@($State.pendingEscalations).Count -gt 0) {
        $State.recoveryObservations = @($State.recoveryObservations) + [ordered]@{
            decision = 'reconcile_required'
            escalationCount = @($State.pendingEscalations).Count
            implementerAction = 'none'
        }
        return [ordered]@{ decision = 'reconcile_required'; state = $State }
    }

    Assert-True ($null -ne $State.pendingReview) 'healthy review recovery requires a pending review'
    $State.recoveryObservations = @($State.recoveryObservations) + [ordered]@{
        decision = 'healthy_idle_no_wake'
        task = [string]$State.pendingReview.taskId
        revision = [string]$State.pendingReview.revision
        implementerAction = 'none'
    }
    return [ordered]@{ decision = 'healthy_idle_no_wake'; state = $State }
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

    if ((@($State.pendingEscalations).Count -gt 0) -and
        (@('ready_for_review', 'changes_requested', 'implementation_ready', 'accepted') -contains [string]$Event.kind)) {
        throw 'coordinator reconciliation is required before resuming the review flow.'
    }

    switch ([string]$Event.kind) {
        'unknown_delivery' {
            $State.pendingEscalations = @($State.pendingEscalations) + [ordered]@{ eventId = [string]$Event.eventId; kind = [string]$Event.kind; revision = [string]$Event.revision }
            return [ordered]@{ decision = 'escalate_coordinator'; state = $State }
        }
        'revision_conflict' {
            $State.pendingEscalations = @($State.pendingEscalations) + [ordered]@{ eventId = [string]$Event.eventId; kind = [string]$Event.kind; revision = [string]$Event.revision }
            return [ordered]@{ decision = 'escalate_coordinator'; state = $State }
        }
        'coordinator_reconciled' {
            if ([string]$Event.coordinatorId -cne [string]$State.coordinator) { throw 'reconciliation sender is not the coordinator.' }
            $matching = @($State.pendingEscalations | Where-Object { [string]$_.eventId -ceq [string]$Event.escalationId })
            if ($matching.Count -ne 1) { throw 'reconciliation must identify one pending escalation.' }
            $State.pendingEscalations = @($State.pendingEscalations | Where-Object { [string]$_.eventId -cne [string]$Event.escalationId })
            return [ordered]@{ decision = 'reconciled'; state = $State }
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
                $created = Add-Action $State 'story_review' $task.ref ([string]$Event.revision) $State.implementer $State.reviewer
                return [ordered]@{ decision = if ($created) { 'final_story_review' } else { 'duplicate' }; state = $State }
            }
            $State.currentTaskIndex = [int]$State.currentTaskIndex + 1
            $next = Get-CurrentTask $State
            $next.state = 'in_progress'
            $created = Add-Action $State 'advance_next_task' $next.ref 'pending' $State.implementer $State.implementer
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
            [void](Add-Action $State 'acceptance' $task.ref ([string]$Event.revision) $State.reviewer $State.implementer)
            $State.actions = @($State.actions) + [ordered]@{ key = "taiga|$($task.ref)|$($Event.revision)"; kind = 'taiga_reconcile'; task = $task.ref; revision = [string]$Event.revision; branch = $State.branch; sender = $State.implementer; destination = 'Taiga'; worker = 'implementer' }
            if ($State.currentTaskIndex -eq ($State.tasks.Count - 1)) {
                $created = Add-Action $State 'story_review' $task.ref ([string]$Event.revision) $State.implementer $State.reviewer
                return [ordered]@{ decision = if ($created) { 'final_story_review' } else { 'duplicate' }; state = $State }
            }
            $State.currentTaskIndex = [int]$State.currentTaskIndex + 1
            $next = Get-CurrentTask $State
            $next.state = 'in_progress'
            $created = Add-Action $State 'advance_next_task' $next.ref 'pending' $State.implementer $State.implementer
            return [ordered]@{ decision = if ($created) { 'advance_next_task' } else { 'duplicate' }; state = $State }
        }
        'idle' { return [ordered]@{ decision = 'wait'; state = $State } }
        default { throw "unsupported event kind: $($Event.kind)" }
    }
}

$state = New-StoryState 'per_task'
$ready = Complete-ReviewHandoff $state @{ eventId = 'ready-per_task'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($ready.decision -eq 'dispatch_review') 'per_task should dispatch the initial review'
Assert-True (@($state.actions | Where-Object kind -eq 'review').Count -eq 1) 'per_task should prepare one review action'
Assert-True ($state.actions[0].sender -eq $state.implementer -and $state.actions[0].destination -eq $state.reviewer) 'initial review must stay direct between the worker pair'
Assert-True (@($state.actions | Where-Object { $_.destination -eq $state.coordinator }).Count -eq 0) 'initial readiness must not notify the coordinator'
Assert-True (@($state.turns).Count -eq 1) 'initial handoff must end one implementer turn'
$initialTurn = @($state.turns)[0]
$initialTrace = @($state.implementerActions | Where-Object { [int]$_.turn -eq [int]$initialTurn.turn })
$initialTraceKinds = @($initialTrace | ForEach-Object { [string]$_.kind })
$traceEnded = ($initialTraceKinds.Count -eq 2 -and $initialTraceKinds[0] -eq 'send_review_handoff' -and $initialTraceKinds[1] -eq 'final_response')
Assert-True ($initialTurn.ended -eq $traceEnded -and $initialTurn.lastAction -eq [string]$initialTrace[-1].kind -and $initialTurn.actionCount -eq $initialTrace.Count) 'initial handoff termination must be derived from its action trace'
Assert-True ($initialTurn.chat -eq $state.implementer -and $initialTurn.reviewer -eq $state.reviewer) 'initial handoff must retain the same worker pair'
Assert-True ($initialTurn.branch -eq $state.branch -and $initialTurn.revision -eq 'sha-a1') 'initial handoff must retain branch and full pending revision'
foreach ($forbiddenAction in @('wait_threads', 'read_reviewer_chat', 'review_monitor', 'keep_alive', 'unchanged_acknowledgement', 'source_edit', 'coordinator_copy')) {
    Assert-Throws { Add-ImplementerAction $state $forbiddenAction '#65' 'sha-a1' } "pending review must reject implementer $forbiddenAction"
}
Assert-True (@($state.rejectedImplementerActions).Count -eq 7) 'fixture must attempt every forbidden post-termination action'
Assert-True (@($state.implementerActions | Where-Object { $_.kind -in @('wait_threads', 'read_reviewer_chat', 'review_monitor', 'keep_alive', 'unchanged_acknowledgement', 'source_edit', 'coordinator_copy') }).Count -eq 0) 'implementer trace must contain no polling, monitor, keep-alive, unchanged acknowledgement, source edit, or coordinator copy after termination'
Assert-True (@($state.implementerActions | Where-Object { [int]$_.turn -eq [int]$initialTurn.turn }).Count -eq $initialTurn.actionCount) 'post-termination attempts must not append to the ended turn trace'
$healthyRecovery = Observe-HealthyReviewRecovery $state
Assert-True ($healthyRecovery.decision -eq 'healthy_idle_no_wake' -and $state.recoveryObservations[0].implementerAction -eq 'none') 'healthy awaiting_review recovery must not wake or poll the implementer'
$duplicate = Complete-ReviewHandoff $state @{ eventId = 'ready-per_task'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($duplicate.decision -eq 'duplicate') 'per_task should ignore duplicate ready events'
Assert-True (@($state.turns).Count -eq 1) 'duplicate ready must not start another implementer turn'
$stale = $false
try { Apply-Event $state @{ eventId = 'stale-per_task'; kind = 'accepted'; taskId = 65; revision = 'sha-old'; reviewerId = 'reviewer-story-87'; criteria = 'complete'; authorization = 'start-87' } | Out-Null } catch { $stale = $true }
Assert-True $stale 'per_task should reject stale acceptance'
$finding = Resume-ImplementerOnReviewerMessage $state @{ eventId = 'finding-per_task'; kind = 'changes_requested'; taskId = 65; reviewedRevision = 'sha-a1'; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($finding.decision -eq 'route_correction') 'per_task should route correction to the same pair'
Assert-True ($state.turnStatus -eq 'active' -and $state.currentTurnId -eq 2) 'current reviewer finding must authorize a new implementer turn'
Add-ImplementerAction $state 'source_edit' '#65' 'working-tree'
$correctionAction = @($state.actions | Where-Object kind -eq 'correction')[0]
Assert-True ($correctionAction.sender -eq $state.reviewer -and $correctionAction.destination -eq $state.implementer) 'routine findings must go directly to the implementer'
Assert-True (@($state.actions | Where-Object { $_.destination -eq $state.coordinator }).Count -eq 0) 'routine findings and corrections must not notify the coordinator'
$correctionReady = Complete-ReviewHandoff $state @{ eventId = 'ready-correction-per_task'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; previousRevision = 'sha-a1'; authorization = 'start-87' }
Assert-True ($correctionReady.decision -eq 'dispatch_review') 'per_task should dispatch correction re-review'
Assert-True (@($state.turns).Count -eq 2 -and @($state.turns)[1].handoff -eq 'correction') 'correction-ready handoff must end the same implementer chat turn'
$correctionTurn = @($state.turns)[1]
$correctionTrace = @($state.implementerActions | Where-Object { [int]$_.turn -eq [int]$correctionTurn.turn })
Assert-True ($correctionTurn.ended -and $correctionTurn.actionCount -eq $correctionTrace.Count -and [string]$correctionTrace[-1].kind -eq $correctionTurn.lastAction) 'correction termination must be derived from its action trace'
Assert-True (@($state.implementerActions | Where-Object kind -eq 'final_response').Count -eq 2) 'initial and correction handoffs must each have one final response'
$actionCountBeforeEscalation = @($state.actions).Count
$unknownDelivery = Apply-Event $state @{ eventId = 'unknown-delivery-per_task'; kind = 'unknown_delivery'; taskId = 65; revision = 'sha-a2'; authorization = 'start-87' }
Assert-True ($unknownDelivery.decision -eq 'escalate_coordinator') 'unknown delivery must escalate to the coordinator'
Assert-True ($state.tasks[0].state -eq 'awaiting_review' -and $state.pendingReview.revision -eq 'sha-a2') 'an already confirmed review remains pending while delivery evidence is reconciled'
$unknownRecovery = Observe-HealthyReviewRecovery $state
Assert-True ($unknownRecovery.decision -eq 'reconcile_required' -and $state.recoveryObservations[-1].implementerAction -eq 'none') 'unresolved unknown delivery must require reconciliation rather than appear healthy'
$revisionConflict = Apply-Event $state @{ eventId = 'revision-conflict-per_task'; kind = 'revision_conflict'; taskId = 65; revision = 'sha-a2'; authorization = 'start-87' }
Assert-True ($revisionConflict.decision -eq 'escalate_coordinator') 'revision conflicts must escalate to the coordinator'
Assert-True (@($state.actions).Count -eq $actionCountBeforeEscalation -and $state.currentTaskIndex -eq 0) 'escalation events must not mutate routine review state'
$resumeBeforeReconciliation = $false
try { Apply-Event $state @{ eventId = 'resume-before-reconciliation'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; previousRevision = 'sha-a1'; authorization = 'start-87' } | Out-Null } catch { $resumeBeforeReconciliation = $true }
Assert-True $resumeBeforeReconciliation 'review flow must remain stopped until coordinator reconciliation'
$reconcileUnknown = Apply-Event $state @{ eventId = 'reconcile-unknown-delivery-per_task'; kind = 'coordinator_reconciled'; taskId = 65; revision = 'sha-a2'; escalationId = 'unknown-delivery-per_task'; coordinatorId = 'coordinator-story-87'; authorization = 'start-87' }
Assert-True ($reconcileUnknown.decision -eq 'reconciled' -and @($state.pendingEscalations).Count -eq 1) 'coordinator must reconcile the unknown delivery before resume'
$reconcileConflict = Apply-Event $state @{ eventId = 'reconcile-revision-conflict-per_task'; kind = 'coordinator_reconciled'; taskId = 65; revision = 'sha-a2'; escalationId = 'revision-conflict-per_task'; coordinatorId = 'coordinator-story-87'; authorization = 'start-87' }
Assert-True ($reconcileConflict.decision -eq 'reconciled' -and @($state.pendingEscalations).Count -eq 0) 'coordinator must reconcile the revision conflict before resume'
$healthyAfterReconciliation = Observe-HealthyReviewRecovery $state
Assert-True ($healthyAfterReconciliation.decision -eq 'healthy_idle_no_wake') 'reconciled confirmed delivery may return to healthy quiet recovery'
$accepted = Resume-ImplementerOnReviewerMessage $state @{ eventId = 'accepted-per_task'; kind = 'accepted'; taskId = 65; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; criteria = 'complete'; authorization = 'start-87' }
Assert-True ($accepted.decision -eq 'advance_next_task') 'per_task should advance only after exact acceptance'
Assert-True ($state.currentTaskIndex -eq 1 -and $state.tasks[1].state -eq 'in_progress') 'per_task should start the next declared task'
$acceptanceAction = @($state.actions | Where-Object kind -eq 'acceptance')[0]
Assert-True ($acceptanceAction.sender -eq $state.reviewer -and $acceptanceAction.destination -eq $state.implementer) 'task acceptance must go directly to the implementer'
$taigaAction = @($state.actions | Where-Object kind -eq 'taiga_reconcile')[0]
Assert-True ($taigaAction.sender -eq $state.implementer -and $taigaAction.destination -eq 'Taiga') 'implementer must own accepted-task Taiga reconciliation'
$advanceAction = @($state.actions | Where-Object kind -eq 'advance_next_task')[0]
Assert-True ($advanceAction.sender -eq $state.implementer -and $advanceAction.destination -eq $state.implementer) 'implementer must own next-task advancement without a coordinator gate'
Assert-True (@($state.actions | Where-Object { $_.destination -eq $state.coordinator }).Count -eq 0) 'task acceptance must not notify the coordinator'
$implementerActionCountAfterAcceptance = @($state.implementerActions).Count
$duplicateAcceptance = Resume-ImplementerOnReviewerMessage $state @{ eventId = 'accepted-per_task'; kind = 'accepted'; taskId = 65; revision = 'sha-a2'; reviewerId = 'reviewer-story-87'; criteria = 'complete'; authorization = 'start-87' }
Assert-True ($duplicateAcceptance.decision -eq 'duplicate' -and @($state.implementerActions).Count -eq $implementerActionCountAfterAcceptance) 'duplicate acceptance must not resume or write again'
$nextReady = Complete-ReviewHandoff $state @{ eventId = 'ready-next-task-per_task'; kind = 'ready_for_review'; taskId = 66; revision = 'sha-b1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($nextReady.decision -eq 'dispatch_review') 'accepted task should allow next task review handoff'
Assert-True (@($state.turns).Count -eq 3 -and @($state.turns)[2].task -eq '#66') 'next task review handoff must end a new implementer turn'
$nextTurn = @($state.turns)[2]
$nextTrace = @($state.implementerActions | Where-Object { [int]$_.turn -eq [int]$nextTurn.turn })
$nextPrefix = @($nextTrace | Select-Object -First ($nextTrace.Count - 2))
$nextTerminal = @($nextTrace | Select-Object -Last 2)
Assert-True (($nextPrefix | ForEach-Object { [string]$_.kind }) -join ',' -eq 'reviewer_message_resume,taiga_reconcile,advance_next_task') 'next task handoff must allow authorized preceding work'
Assert-True ($nextTurn.ended -and $nextTurn.lastAction -eq 'final_response' -and $nextTerminal.Count -eq 2 -and $nextTerminal[0].kind -eq 'send_review_handoff' -and $nextTerminal[1].kind -eq 'final_response') 'next task handoff must validate the terminal handoff suffix'
$idle = Apply-Event $state @{ eventId = 'idle-per_task'; kind = 'idle'; taskId = 66; revision = 'sha-b1'; authorization = 'start-87' }
Assert-True ($idle.decision -eq 'wait') 'per_task should not infer acceptance from idle'

$failedDeliveryState = New-StoryState 'per_task'
$failedDelivery = Complete-ReviewHandoff $failedDeliveryState @{ eventId = 'failed-initial-delivery'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-f1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' } -DeliveryFailed
Assert-True ($failedDelivery.decision -eq 'escalate_coordinator') 'failed handoff delivery must escalate to the coordinator'
Assert-True ($failedDeliveryState.tasks[0].state -eq 'in_progress' -and $null -eq $failedDeliveryState.pendingReview) 'failed delivery must not enter awaiting_review'
Assert-True (@($failedDeliveryState.turns).Count -eq 0) 'failed delivery must not end a false review-wait turn'
$failedRecovery = Observe-HealthyReviewRecovery $failedDeliveryState
Assert-True ($failedRecovery.decision -eq 'reconcile_required') 'failed delivery recovery must require reconciliation'
$reconciledFailedDelivery = Apply-Event $failedDeliveryState @{ eventId = 'reconcile-failed-initial-delivery'; kind = 'coordinator_reconciled'; taskId = 65; revision = 'sha-f1'; escalationId = 'failed-initial-delivery-delivery-failed'; coordinatorId = 'coordinator-story-87'; authorization = 'start-87' }
Assert-True ($reconciledFailedDelivery.decision -eq 'reconciled' -and @($failedDeliveryState.pendingEscalations).Count -eq 0) 'failed delivery must be reconciled before retry'
$retryAfterFailedDelivery = Complete-ReviewHandoff $failedDeliveryState @{ eventId = 'retry-initial-delivery'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-f1'; reviewerId = 'reviewer-story-87'; authorization = 'start-87' }
Assert-True ($retryAfterFailedDelivery.decision -eq 'dispatch_review' -and @($failedDeliveryState.turns).Count -eq 1) 'reconciled delivery may dispatch exactly one review and end the turn'

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
$storyEndReviewAction = @($storyEndState.actions | Where-Object kind -eq 'story_review')[0]
Assert-True ($storyEndReviewAction.sender -eq $storyEndState.implementer -and $storyEndReviewAction.destination -eq $storyEndState.reviewer) 'story_end_only final review request must stay in the worker pair'
Assert-True (@($storyEndState.actions | Where-Object { $_.destination -eq $storyEndState.coordinator }).Count -eq 0) 'story_end_only advancement must not notify the coordinator'

$scopeState = New-StoryState 'per_task'
$scopeError = $false
try { Apply-Event $scopeState @{ eventId = 'scope-change'; kind = 'ready_for_review'; taskId = 65; revision = 'sha-a1'; reviewerId = 'reviewer-story-87'; authorization = 'changed-start' } | Out-Null } catch { $scopeError = $true }
Assert-True $scopeError 'scope changes must stop automatic dispatch'

Write-Output 'Passed automatic review-flow fixture: trace-derived end-of-turn initial/correction handoffs with post-termination action rejection, reviewer-message resume, no implementer polling/monitor/keep-alive/unchanged acknowledgement, healthy-versus-unresolved-delivery recovery, direct acceptance/advancement, both review modes, duplicate/stale/idle guards, coordinator escalation, and scope gating.'
