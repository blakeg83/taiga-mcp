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
    $reviewResumeActions = @('reviewer_message_resume')
    if ($State.turnStatus -eq 'awaiting_review' -or
        $Kind -eq 'coordinator_copy' -or
        ($null -ne $State.pendingReview -and $Kind -notin ($reviewEndpointActions + $reviewResumeActions))) {
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

function Assert-NoPendingAcceptanceEscalations {
    param([System.Collections.IDictionary] $State)

    if (@($State.pendingEscalations).Count -gt 0) {
        throw 'coordinator reconciliation is required before resuming the review flow.'
    }
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
        if ($State.Contains('provider')) {
            Capture-ProviderReviewBaseline $State @([int]$Event.taskId)
        }
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

    if ($State.Contains('provider') -and [string]$Event.kind -eq 'accepted') {
        Assert-NoPendingAcceptanceEscalations $State
        $acceptanceMarker = "task|$($Event.taskId)|$($Event.revision)"
        if ($State.acceptanceMarkers -contains $acceptanceMarker) {
            return [ordered]@{ decision = 'duplicate'; state = $State }
        }

        if ($null -ne $State.pendingAcceptance -and
            [string]$State.pendingAcceptance.marker -ceq $acceptanceMarker -and
            $State.turnStatus -eq 'active') {
            $result = Reconcile-TaskAcceptance $State $Event
            if ($result.decision -in @('advance_next_task', 'final_story_review')) {
                Add-ImplementerAction $State 'taiga_reconcile' ([string]$Event.taskId) ([string]$Event.revision)
            }
            if ($result.decision -eq 'advance_next_task') {
                Add-ImplementerAction $State 'advance_next_task' ([string](Get-CurrentTask $State).ref) 'pending'
            }
            return $result
        }

        Assert-TaskAcceptancePreflight $State $Event
        Authorize-ImplementerResume $State
        Add-ImplementerAction $State 'reviewer_message_resume' ([string]$Event.taskId) ([string]$Event.revision)
        $result = Reconcile-TaskAcceptance $State $Event
        if ($result.decision -in @('advance_next_task', 'final_story_review')) {
            Add-ImplementerAction $State 'taiga_reconcile' ([string]$Event.taskId) ([string]$Event.revision)
        }
        if ($result.decision -eq 'advance_next_task') {
            Add-ImplementerAction $State 'advance_next_task' ([string](Get-CurrentTask $State).ref) 'pending'
        }
        return $result
    }

    if ($State.Contains('provider') -and [string]$Event.kind -eq 'story_accepted') {
        Assert-NoPendingAcceptanceEscalations $State
        $storyMarker = "story|$($Event.revision)"
        if ($State.storyAcceptanceMarker -eq $storyMarker) {
            return [ordered]@{ decision = 'duplicate'; state = $State }
        }

        if ($State.pendingFinalStoryAcceptance -eq $storyMarker -and $State.turnStatus -eq 'active') {
            Assert-FinalStoryAcceptancePreflight $State $Event
            $result = Reconcile-FinalStoryAcceptance $State $Event
            if ($result.decision -eq 'final_story_reconciled') {
                Add-ImplementerAction $State 'taiga_reconcile' 'story' ([string]$Event.revision)
            }
            return $result
        }

        Assert-FinalStoryAcceptancePreflight $State $Event
        Authorize-ImplementerResume $State
        Add-ImplementerAction $State 'reviewer_message_resume' ([string]$Event.taskId) ([string]$Event.revision)
        $result = Reconcile-FinalStoryAcceptance $State $Event
        if ($result.decision -eq 'final_story_reconciled') {
            Add-ImplementerAction $State 'taiga_reconcile' 'story' ([string]$Event.revision)
        }
        return $result
    }

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
                $State.finalReviewRevision = [string]$Event.revision
                $created = Add-Action $State 'story_review' $task.ref ([string]$Event.revision) $State.implementer $State.reviewer
                if ($State.Contains('provider')) {
                    if ($created) {
                        Capture-ProviderReviewBaseline $State @($State.tasks | ForEach-Object { [int]$_.taskId })
                    }
                }
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

function New-ReconciliationState {
    param([ValidateSet('per_task', 'story_end_only')] [string] $ReviewMode)

    $state = New-StoryState $ReviewMode
    $state.repository = 'C:\Projects\TaigaMCP'
    $state.worktree = 'C:\Projects\TaigaMCP'
    $state.scopeHash = 'scope-87'
    $state.acceptanceMarkers = @()
    $state.acceptanceJournal = @{}
    $state.providerReviewBaselines = @{}
    $state.reconciliationHolds = @()
    $state.pendingAcceptance = $null
    $state.storyAcceptanceMarker = $null
    $state.pendingFinalStoryAcceptance = $null
    $state.finalReviewRevision = $null
    $state.finalStoryState = 'pending'
    $state.storyMerged = $false
    $state.storyReleased = $false
    $state.provider = [ordered]@{
        statusMapping = [ordered]@{
            not_started = 101
            in_progress = 102
            awaiting_review = 103
            accepted = 104
            blocked = 105
        }
        humanStatusId = 105
        tasks = @{}
        story = [ordered]@{ id = 870; version = 1; comments = @(); history = @() }
        taskWrites = @()
        storyWrites = @()
        barriers = [ordered]@{
            humanBeforeTaskWrite = @{}
            taskResponseLost = @{}
            storyResponseLost = @{}
        }
    }

    foreach ($taskId in @(65, 66)) {
        $state.provider.tasks[[string]$taskId] = [ordered]@{
            id = $taskId
            version = 1
            statusId = 102
            description = "- [ ] Implementation evidence`n- [ ] Independent review evidence`n- [ ] Final story review evidence`n- [ ] Human-owned note"
            comments = @()
            history = @()
        }
    }

    return $state
}

function Get-ProviderTaskSnapshot {
    param([System.Collections.IDictionary] $Provider, [int] $TaskId)

    $task = $Provider.tasks[[string]$TaskId]
    if ($null -eq $task) { throw "synthetic provider task $TaskId was not found" }
    return [ordered]@{
        id = $task.id
        version = [int]$task.version
        statusId = [int]$task.statusId
        description = [string]$task.description
        comments = @($task.comments)
    }
}

function Capture-ProviderReviewBaseline {
    param(
        [System.Collections.IDictionary] $State,
        [int[]] $TaskIds
    )

    foreach ($taskId in @($TaskIds)) {
        $snapshot = Get-ProviderTaskSnapshot $State.provider $taskId
        $State.providerReviewBaselines[[string]$taskId] = [ordered]@{
            version = [int]$snapshot.version
            statusId = [int]$snapshot.statusId
            description = [string]$snapshot.description
            historyCount = @($State.provider.tasks[[string]$taskId].history).Count
        }
    }
}

function Get-ProviderStorySnapshot {
    param([System.Collections.IDictionary] $Provider)

    return [ordered]@{
        id = $Provider.story.id
        version = [int]$Provider.story.version
        comments = @($Provider.story.comments)
    }
}

function Add-ProviderHistory {
    param([System.Collections.IDictionary] $Target, [string] $kind, [string] $marker)
    $Target.history = @($Target.history) + [ordered]@{ kind = $kind; marker = $marker; version = $Target.version }
}

function Invoke-ProviderTaskWrite {
    param(
        [System.Collections.IDictionary] $Provider,
        [int] $TaskId,
        [int] $ExpectedVersion,
        [int] $TargetStatusId,
        [string] $Description,
        [string] $ActionKey
    )

    $task = $Provider.tasks[[string]$TaskId]
    if ($null -eq $task) { throw "synthetic provider task $TaskId was not found" }
    if (@($Provider.statusMapping.Values) -notcontains $TargetStatusId) {
        throw "synthetic provider rejected undiscovered task status $TargetStatusId"
    }

    if ($Provider.barriers.humanBeforeTaskWrite.ContainsKey($ActionKey)) {
        $mutation = $Provider.barriers.humanBeforeTaskWrite[$ActionKey]
        $Provider.barriers.humanBeforeTaskWrite.Remove($ActionKey)
        $task.statusId = [int]$mutation.statusId
        $task.description = [string]$task.description + "`n" + [string]$mutation.append
        $task.version++
        Add-ProviderHistory $task 'human_edit' $ActionKey
        return [ordered]@{ outcome = 'conflict'; applied = $false; version = $task.version }
    }

    if ([int]$task.version -ne $ExpectedVersion) {
        return [ordered]@{ outcome = 'conflict'; applied = $false; version = $task.version }
    }

    $task.statusId = $TargetStatusId
    $task.description = $Description
    $task.version++
    $Provider.taskWrites = @($Provider.taskWrites) + [ordered]@{
        actionKey = $ActionKey
        taskId = $TaskId
        expectedVersion = $ExpectedVersion
        resultingVersion = $task.version
        statusId = $TargetStatusId
    }
    Add-ProviderHistory $task 'task_write' $ActionKey

    if ($Provider.barriers.taskResponseLost.ContainsKey($ActionKey)) {
        $Provider.barriers.taskResponseLost.Remove($ActionKey)
        return [ordered]@{ outcome = 'unknown'; applied = $true; version = $task.version }
    }

    return [ordered]@{ outcome = 'applied'; applied = $true; version = $task.version }
}

function Merge-ProviderChecklist {
    param([string] $CurrentDescription, [string[]] $Evidence)

    $merged = $CurrentDescription
    foreach ($item in @($Evidence)) {
        if ([string]::IsNullOrWhiteSpace($item)) { throw 'checklist evidence cannot be blank' }
        $unchecked = "- [ ] $item"
        $checked = "- [x] $item"
        if ($merged.Contains($unchecked)) {
            $merged = $merged.Replace($unchecked, $checked)
        } elseif (-not $merged.Contains($checked)) {
            throw "checklist item '$item' is not present in the authoritative task description"
        }
    }
    return $merged
}

function Invoke-ProviderStoryComment {
    param(
        [System.Collections.IDictionary] $Provider,
        [int] $ExpectedVersion,
        [string] $Text,
        [string] $Marker
    )

    $story = $Provider.story
    if (@($story.comments | Where-Object { [string]$_ -like "*$Marker*" }).Count -gt 0) {
        return [ordered]@{ outcome = 'duplicate'; applied = $true; version = $story.version }
    }
    if ([int]$story.version -ne $ExpectedVersion) {
        return [ordered]@{ outcome = 'conflict'; applied = $false; version = $story.version }
    }

    $story.comments = @($story.comments) + $Text
    $story.version++
    $Provider.storyWrites = @($Provider.storyWrites) + [ordered]@{
        marker = $Marker
        expectedVersion = $ExpectedVersion
        resultingVersion = $story.version
    }
    Add-ProviderHistory $story 'story_comment' $Marker

    if ($Provider.barriers.storyResponseLost.ContainsKey($Marker)) {
        $Provider.barriers.storyResponseLost.Remove($Marker)
        return [ordered]@{ outcome = 'unknown'; applied = $true; version = $story.version }
    }

    return [ordered]@{ outcome = 'applied'; applied = $true; version = $story.version }
}

function Add-ReconciliationHold {
    param([System.Collections.IDictionary] $State, [string] $Marker, [string] $Reason)
    $State.reconciliationHolds = @($State.reconciliationHolds) + [ordered]@{
        marker = $Marker
        reason = $Reason
        taskIndex = [int]$State.currentTaskIndex
    }
    return [ordered]@{ decision = 'reconcile_required'; state = $State; reason = $Reason }
}

function Confirm-ProviderTaskWrite {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Journal,
        [System.Collections.IDictionary] $Event,
        [System.Collections.IDictionary] $Before,
        [string] $TargetDescription
    )

    $provider = $State.provider
    $targetStatusId = [int]$provider.statusMapping.accepted
    $actionKey = [string]$Journal.marker
    if (-not $State.providerReviewBaselines.ContainsKey([string]$Before.id)) {
        throw "provider review baseline is missing for task $($Before.id)"
    }
    $baseline = $State.providerReviewBaselines[[string]$Before.id]
    if (-not $Journal.Contains('baselineVersion') -or $null -eq $Journal.baselineVersion) {
        $Journal.baselineVersion = [int]$baseline.version
        $Journal.baselineStatusId = [int]$baseline.statusId
        $Journal.baselineDescription = [string]$baseline.description
    }
    $changedFromBaseline = ([int]$Before.version -ne [int]$Journal.baselineVersion -or
        [int]$Before.statusId -ne [int]$Journal.baselineStatusId -or
        [string]$Before.description -cne [string]$Journal.baselineDescription)
    if ($Before.statusId -eq $targetStatusId -and $Before.description -eq $TargetDescription) {
        $Journal.statusConfirmed = $true
        return $null
    }

    $humanDecision = if ($Event.Contains('humanDecision')) { [string]$Event.humanDecision } else { '' }
    if ($humanDecision -eq '' -and
        ($changedFromBaseline -or $Before.statusId -eq [int]$provider.humanStatusId)) {
        return Add-ReconciliationHold $State $actionKey 'authoritative human status changed after the acceptance snapshot; an explicit preserve-or-replace decision is required'
    }
    if ($humanDecision -eq 'preserve_human_status') {
        return Add-ReconciliationHold $State $actionKey 'explicit decision preserved the human status; accepted transition remains unresolved'
    }
    if ($humanDecision -ne '' -and $humanDecision -ne 'replace_after_decision') {
        throw "unsupported human reconciliation decision: $humanDecision"
    }
    if ($humanDecision -eq 'replace_after_decision') {
        $Journal.humanDecision = $humanDecision
    }

    $write = Invoke-ProviderTaskWrite $provider $Before.id $Before.version $targetStatusId $TargetDescription $actionKey
    $after = Get-ProviderTaskSnapshot $provider $Before.id
    if (($write.outcome -in @('applied', 'unknown', 'conflict')) -and
        $after.statusId -eq $targetStatusId -and $after.description -eq $TargetDescription) {
        $Journal.statusConfirmed = $true
        $Journal.statusOutcome = if ($write.outcome -eq 'unknown') { 'confirmed_after_response_loss' } else { 'applied' }
        return $null
    }

    $outcome = [string]$write.outcome
    return Add-ReconciliationHold $State $actionKey "task write outcome '$outcome' did not produce the intended authoritative status/checklist"
}

function Confirm-ProviderStoryComment {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Journal,
        [string] $Text,
        [string] $Marker
    )

    $provider = $State.provider
    $storyBefore = Get-ProviderStorySnapshot $provider
    if (@($storyBefore.comments | Where-Object { [string]$_ -like "*$Marker*" }).Count -gt 0) {
        $Journal.commentConfirmed = $true
        return $null
    }

    $write = Invoke-ProviderStoryComment $provider $storyBefore.version $Text $Marker
    $storyAfter = Get-ProviderStorySnapshot $provider
    if (@($storyAfter.comments | Where-Object { [string]$_ -like "*$Marker*" }).Count -gt 0) {
        $Journal.commentConfirmed = $true
        $Journal.commentOutcome = if ($write.outcome -eq 'unknown') { 'confirmed_after_response_loss' } else { $write.outcome }
        return $null
    }

    return Add-ReconciliationHold $State $Marker "story progress comment outcome '$($write.outcome)' is unresolved"
}

function Assert-TaskAcceptancePreflight {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Event
    )

    foreach ($required in @('eventId', 'taskId', 'revision', 'authorization', 'reviewerId', 'criteria', 'repository', 'worktree', 'branch', 'headSha', 'scopeHash', 'checklistEvidence')) {
        if (-not $Event.Contains($required)) { throw "acceptance requires $required" }
    }
    if ([string]$Event.revision -notmatch '^[0-9a-fA-F]{40}$' -or
        [string]$Event.headSha -notmatch '^[0-9a-fA-F]{40}$') { throw 'acceptance requires a full 40-character reviewed SHA and observed HEAD' }
    if ([string]$Event.authorization -cne [string]$State.authorization) { throw 'acceptance authorization is stale' }
    if ([string]$Event.repository -cne [string]$State.repository -or
        [string]$Event.worktree -cne [string]$State.worktree -or
        [string]$Event.branch -cne [string]$State.branch -or
        [string]$Event.headSha -cne [string]$Event.revision -or
        [string]$Event.scopeHash -cne [string]$State.scopeHash) { throw 'acceptance revision or scope binding is stale' }
    if ([string]$Event.reviewerId -cne [string]$State.reviewer) { throw 'acceptance sender is not the assigned reviewer' }
    if ([string]$Event.criteria -cne 'complete') { throw 'acceptance must cover all task criteria' }

    $task = Get-CurrentTask $State
    if ([int]$Event.taskId -ne [int]$task.taskId) { throw 'acceptance is not for the current ordered task' }
    if ($null -eq $State.pendingReview -or
        [int]$State.pendingReview.taskId -ne [int]$Event.taskId -or
        [string]$State.pendingReview.revision -cne [string]$Event.revision) { throw 'acceptance is not bound to the pending exact revision' }
}

function Assert-FinalStoryAcceptancePreflight {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Event
    )

    foreach ($required in @('eventId', 'taskId', 'revision', 'authorization', 'reviewerId', 'criteria', 'repository', 'worktree', 'branch', 'headSha', 'scopeHash')) {
        if (-not $Event.Contains($required)) { throw "final story acceptance requires $required" }
    }
    if ([string]$Event.revision -notmatch '^[0-9a-fA-F]{40}$' -or
        [string]$Event.headSha -notmatch '^[0-9a-fA-F]{40}$') { throw 'final story acceptance requires a full 40-character reviewed SHA and observed HEAD' }
    if ([string]$Event.authorization -cne [string]$State.authorization -or
        [string]$Event.repository -cne [string]$State.repository -or
        [string]$Event.worktree -cne [string]$State.worktree -or
        [string]$Event.branch -cne [string]$State.branch -or
        [string]$Event.headSha -cne [string]$Event.revision -or
        [string]$Event.scopeHash -cne [string]$State.scopeHash) { throw 'final story acceptance binding is stale' }
    if ($null -eq $State.finalReviewRevision -or
        [string]$Event.revision -cne [string]$State.finalReviewRevision) { throw 'final story acceptance is not bound to the pending final-review revision' }
    if ([string]$Event.reviewerId -cne [string]$State.reviewer -or [string]$Event.criteria -cne 'complete') {
        throw 'final story acceptance is not from the assigned reviewer with complete criteria'
    }
}

function Reconcile-TaskAcceptance {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Event
    )

    $marker = "task|$($Event.taskId)|$($Event.revision)"
    if ($State.acceptanceMarkers -contains $marker) {
        return [ordered]@{ decision = 'duplicate'; state = $State }
    }
    Assert-TaskAcceptancePreflight $State $Event

    $task = Get-CurrentTask $State

    $journal = $null
    if ($State.acceptanceJournal.ContainsKey($marker)) {
        $journal = $State.acceptanceJournal[$marker]
    } else {
        $journal = [ordered]@{
            marker = $marker
            statusConfirmed = $false
            commentConfirmed = $false
            humanDecision = $null
        }
        $State.acceptanceJournal[$marker] = $journal
    }
    $State.pendingAcceptance = $journal

    $provider = $State.provider
    $before = Get-ProviderTaskSnapshot $provider ([int]$Event.taskId)
    $targetDescription = Merge-ProviderChecklist $before.description @($Event.checklistEvidence)
    if ($null -eq $journal.statusConfirmed) { $journal.statusConfirmed = $false }
    if ($journal.statusConfirmed -and
        ($before.statusId -ne [int]$provider.statusMapping.accepted -or $before.description -ne $targetDescription)) {
        $journal.statusConfirmed = $false
    }
    if (-not $journal.statusConfirmed) {
        $hold = Confirm-ProviderTaskWrite $State $journal $Event $before $targetDescription
        if ($null -ne $hold) { return $hold }
    }

    $commentMarker = "Task #$($Event.taskId) accepted | acceptance: $marker"
    $comment = "$commentMarker | commit: $($Event.revision) | status: accepted | checklist merged from current version"
    if (-not $journal.commentConfirmed) {
        $hold = Confirm-ProviderStoryComment $State $journal $comment $commentMarker
        if ($null -ne $hold) { return $hold }
    }

    $task.state = 'accepted'
    $task.acceptedSha = [string]$Event.revision
    $task.pendingSha = $null
    $State.pendingReview = $null
    $State.pendingAcceptance = $null
    $State.acceptanceMarkers = @($State.acceptanceMarkers) + $marker
    [void](Add-Action $State 'acceptance' $task.ref ([string]$Event.revision) $State.reviewer $State.implementer)
    [void](Add-Action $State 'taiga_reconcile' $task.ref ([string]$Event.revision) $State.implementer 'Taiga')

    if ([int]$State.currentTaskIndex -eq ($State.tasks.Count - 1)) {
        [void](Add-Action $State 'story_review' $task.ref ([string]$Event.revision) $State.implementer $State.reviewer)
        return [ordered]@{ decision = 'final_story_review'; state = $State }
    }

    $State.currentTaskIndex = [int]$State.currentTaskIndex + 1
    $next = Get-CurrentTask $State
    $next.state = 'in_progress'
    [void](Add-Action $State 'advance_next_task' $next.ref 'pending' $State.implementer $State.implementer)
    return [ordered]@{ decision = 'advance_next_task'; state = $State }
}

function Reconcile-FinalStoryAcceptance {
    param(
        [System.Collections.IDictionary] $State,
        [System.Collections.IDictionary] $Event
    )

    $marker = "story|$($Event.revision)"
    if ($State.storyAcceptanceMarker -eq $marker) {
        return [ordered]@{ decision = 'duplicate'; state = $State }
    }
    Assert-FinalStoryAcceptancePreflight $State $Event
    $State.pendingFinalStoryAcceptance = $marker

    foreach ($task in @($State.tasks)) {
        if ([string]$task.state -ne 'implementation_complete' -or [string]::IsNullOrWhiteSpace([string]$task.pendingSha)) {
            throw "final story acceptance requires implementation evidence for task $($task.ref)"
        }
        $providerTask = Get-ProviderTaskSnapshot $State.provider ([int]$task.taskId)
        $targetDescription = Merge-ProviderChecklist $providerTask.description @('Final story review evidence')
        $actionKey = "story-task|$($task.taskId)|$($Event.revision)"
        if (-not $State.acceptanceJournal.ContainsKey($actionKey)) {
            $State.acceptanceJournal[$actionKey] = [ordered]@{
                marker = $actionKey
                statusConfirmed = $false
                commentConfirmed = $true
                humanDecision = $null
            }
        }
        $journal = $State.acceptanceJournal[$actionKey]
        $State.pendingAcceptance = $journal
        $hold = Confirm-ProviderTaskWrite $State $journal $Event $providerTask $targetDescription
        if ($null -ne $hold) { return $hold }
    }

    $commentMarker = "Story #870 final review accepted | acceptance: $marker"
    $comment = "$commentMarker | reviewed HEAD: $($Event.revision) | tasks reconciled by implementer | merge/release: pending separate gate"
    $storyBefore = Get-ProviderStorySnapshot $State.provider
    if (@($storyBefore.comments | Where-Object { [string]$_ -like "*$commentMarker*" }).Count -eq 0) {
        $write = Invoke-ProviderStoryComment $State.provider $storyBefore.version $comment $commentMarker
        $storyAfter = Get-ProviderStorySnapshot $State.provider
        if (@($storyAfter.comments | Where-Object { [string]$_ -like "*$commentMarker*" }).Count -eq 0) {
            return Add-ReconciliationHold $State $commentMarker "final story comment outcome '$($write.outcome)' is unresolved"
        }
    }

    foreach ($task in @($State.tasks)) {
        $task.state = 'accepted'
        $task.acceptedSha = [string]$task.pendingSha
        $task.pendingSha = $null
    }
    $State.storyAcceptanceMarker = $marker
    $State.pendingFinalStoryAcceptance = $null
    $State.pendingAcceptance = $null
    $State.finalStoryState = 'accepted'
    $State.storyMerged = $false
    $State.storyReleased = $false
    return [ordered]@{ decision = 'final_story_reconciled'; state = $State }
}

function New-TaskAcceptanceEvent {
    param(
        [System.Collections.IDictionary] $State,
        [string] $EventId,
        [string] $Revision,
        [int] $TaskId = 65
    )

    return [ordered]@{
        eventId = $EventId
        kind = 'accepted'
        taskId = $TaskId
        revision = $Revision
        reviewerId = $State.reviewer
        criteria = 'complete'
        authorization = $State.authorization
        repository = $State.repository
        worktree = $State.worktree
        branch = $State.branch
        headSha = $Revision
        scopeHash = $State.scopeHash
        checklistEvidence = @('Implementation evidence', 'Independent review evidence')
    }
}

function New-StoryAcceptanceEvent {
    param(
        [System.Collections.IDictionary] $State,
        [string] $EventId,
        [string] $Revision
    )

    return [ordered]@{
        eventId = $EventId
        kind = 'story_accepted'
        taskId = 66
        revision = $Revision
        reviewerId = $State.reviewer
        criteria = 'complete'
        authorization = $State.authorization
        repository = $State.repository
        worktree = $State.worktree
        branch = $State.branch
        headSha = $Revision
        scopeHash = $State.scopeHash
    }
}

function Copy-ReconciliationEvent {
    param([System.Collections.IDictionary] $Event)
    $copy = [ordered]@{}
    foreach ($key in $Event.Keys) { $copy[$key] = $Event[$key] }
    return $copy
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

# The acceptance path below uses a synthetic Taiga provider and controlled
# barriers. It models the implementer-owned read/compare/write sequence rather
# than treating a reviewer message as a provider write result.
$normalState = New-ReconciliationState 'per_task'
$normalSha = ('a' * 40)
Complete-ReviewHandoff $normalState @{ eventId = 'reconcile-ready'; kind = 'ready_for_review'; taskId = 65; revision = $normalSha; reviewerId = $normalState.reviewer; authorization = $normalState.authorization } | Out-Null
$normalAcceptance = New-TaskAcceptanceEvent $normalState 'accept-normal' $normalSha
$normalResult = Resume-ImplementerOnReviewerMessage $normalState $normalAcceptance
Assert-True ($normalResult.decision -eq 'advance_next_task') 'current acceptance must reconcile before advancing'
Assert-True ($normalState.provider.tasks['65'].statusId -eq $normalState.provider.statusMapping.accepted) 'accepted task must use the discovered project task status'
Assert-True ($normalState.provider.tasks['65'].description.Contains('- [x] Implementation evidence') -and $normalState.provider.tasks['65'].description.Contains('- [x] Independent review evidence')) 'acceptance must merge evidence-backed checklist items'
Assert-True ($normalState.provider.tasks['65'].description.Contains('- [ ] Human-owned note')) 'checklist merge must preserve unrelated human text'
Assert-True (@($normalState.provider.story.comments | Where-Object { $_ -like '*acceptance: task|65|*' }).Count -eq 1) 'acceptance must add one idempotent parent-story progress comment'
Assert-True ($normalState.currentTaskIndex -eq 1 -and $normalState.tasks[1].state -eq 'in_progress') 'advancement must happen only after task and comment reconciliation'
$normalWriteCount = @($normalState.provider.taskWrites).Count
$normalCommentCount = @($normalState.provider.storyWrites).Count
$duplicateAcceptance = Copy-ReconciliationEvent $normalAcceptance; $duplicateAcceptance.eventId = 'accept-normal-replayed'
$duplicateNormalResult = Resume-ImplementerOnReviewerMessage $normalState $duplicateAcceptance
Assert-True ($duplicateNormalResult.decision -eq 'duplicate') 'duplicate acceptance with a new message id must remain a no-op'
Assert-True (@($normalState.provider.taskWrites).Count -eq $normalWriteCount -and @($normalState.provider.storyWrites).Count -eq $normalCommentCount) 'duplicate acceptance must not duplicate provider writes'

$staleState = New-ReconciliationState 'per_task'
$staleSha = ('b' * 40)
Complete-ReviewHandoff $staleState @{ eventId = 'stale-ready'; kind = 'ready_for_review'; taskId = 65; revision = $staleSha; reviewerId = $staleState.reviewer; authorization = $staleState.authorization } | Out-Null
$staleAcceptance = New-TaskAcceptanceEvent $staleState 'stale-task' $staleSha 66
Assert-Throws { Resume-ImplementerOnReviewerMessage $staleState $staleAcceptance | Out-Null } 'acceptance for another task must not close the current task'
$oldAcceptance = New-TaskAcceptanceEvent $staleState 'stale-sha' (('c' * 40))
Assert-Throws { Resume-ImplementerOnReviewerMessage $staleState $oldAcceptance | Out-Null } 'acceptance for an old SHA must not advance the current task'
$invalidAcceptance = New-TaskAcceptanceEvent $staleState 'invalid-sha' 'x'
Assert-Throws { Resume-ImplementerOnReviewerMessage $staleState $invalidAcceptance | Out-Null } 'acceptance must require a full reviewed SHA'
Assert-True (@($staleState.provider.taskWrites).Count -eq 0 -and @($staleState.provider.storyWrites).Count -eq 0) 'stale acceptance must not reach the provider'

$escalatedTaskState = New-ReconciliationState 'per_task'
$escalatedTaskSha = ('8' * 40)
Complete-ReviewHandoff $escalatedTaskState @{ eventId = 'escalated-ready'; kind = 'ready_for_review'; taskId = 65; revision = $escalatedTaskSha; reviewerId = $escalatedTaskState.reviewer; authorization = $escalatedTaskState.authorization } | Out-Null
Apply-Event $escalatedTaskState @{ eventId = 'escalated-conflict'; kind = 'revision_conflict'; taskId = 65; revision = $escalatedTaskSha; authorization = $escalatedTaskState.authorization } | Out-Null
$escalatedTaskAcceptance = New-TaskAcceptanceEvent $escalatedTaskState 'escalated-acceptance' $escalatedTaskSha
Assert-Throws { Resume-ImplementerOnReviewerMessage $escalatedTaskState $escalatedTaskAcceptance | Out-Null } 'task acceptance must honor pending coordinator reconciliation'
Assert-True ($escalatedTaskState.currentTaskIndex -eq 0 -and @($escalatedTaskState.provider.taskWrites).Count -eq 0 -and @($escalatedTaskState.pendingEscalations).Count -eq 1) 'task acceptance must not bypass an unresolved escalation'

$humanState = New-ReconciliationState 'per_task'
$humanSha = ('d' * 40)
Complete-ReviewHandoff $humanState @{ eventId = 'human-ready'; kind = 'ready_for_review'; taskId = 65; revision = $humanSha; reviewerId = $humanState.reviewer; authorization = $humanState.authorization } | Out-Null
$humanAcceptance = New-TaskAcceptanceEvent $humanState 'accept-human-edit' $humanSha
$humanMarker = "task|65|$humanSha"
$humanState.provider.barriers.humanBeforeTaskWrite[$humanMarker] = [ordered]@{ statusId = $humanState.provider.humanStatusId; append = '- [x] Human-owned note' }
$humanConflict = Resume-ImplementerOnReviewerMessage $humanState $humanAcceptance
Assert-True ($humanConflict.decision -eq 'reconcile_required') 'a human edit between read and write must hold acceptance'
Assert-True ($humanState.provider.tasks['65'].statusId -eq $humanState.provider.humanStatusId -and $humanState.currentTaskIndex -eq 0) 'human status must be preserved while reconciliation is unresolved'
Assert-True (@($humanState.provider.storyWrites).Count -eq 0) 'human conflict must not add progress before a decision'
$humanAcceptance.humanDecision = 'replace_after_decision'
$humanResolved = Resume-ImplementerOnReviewerMessage $humanState $humanAcceptance
Assert-True ($humanResolved.decision -eq 'advance_next_task' -and $humanState.provider.tasks['65'].statusId -eq $humanState.provider.statusMapping.accepted) 'explicit replacement decision must use the current version and then advance'
Assert-True ($humanState.provider.tasks['65'].description.Contains('- [x] Human-owned note')) 'replacement must preserve the human checklist edit'

$reopenedState = New-ReconciliationState 'per_task'
$reopenedSha = ('6' * 40)
Complete-ReviewHandoff $reopenedState @{ eventId = 'reopened-ready'; kind = 'ready_for_review'; taskId = 65; revision = $reopenedSha; reviewerId = $reopenedState.reviewer; authorization = $reopenedState.authorization } | Out-Null
$reopenedAcceptance = New-TaskAcceptanceEvent $reopenedState 'accept-reopened' $reopenedSha
$reopenedMarker = "task|65|$reopenedSha"
$reopenedJournal = [ordered]@{ marker = $reopenedMarker; statusConfirmed = $false; commentConfirmed = $false; humanDecision = $null }
$reopenedState.acceptanceJournal[$reopenedMarker] = $reopenedJournal
$reopenedState.pendingAcceptance = $reopenedJournal
$reopenedBefore = Get-ProviderTaskSnapshot $reopenedState.provider 65
$reopenedDescription = Merge-ProviderChecklist $reopenedBefore.description @($reopenedAcceptance.checklistEvidence)
$null = Confirm-ProviderTaskWrite $reopenedState $reopenedJournal $reopenedAcceptance $reopenedBefore $reopenedDescription
$reopenedState.provider.tasks['65'].statusId = $reopenedState.provider.humanStatusId
$reopenedState.provider.tasks['65'].version++
$reopenedHold = Resume-ImplementerOnReviewerMessage $reopenedState $reopenedAcceptance
Assert-True ($reopenedHold.decision -eq 'reconcile_required' -and $reopenedState.currentTaskIndex -eq 0) 'recovery must re-read status after a human reopens a confirmed task'

$humanNewState = New-ReconciliationState 'per_task'
$humanNewSha = ('7' * 40)
Complete-ReviewHandoff $humanNewState @{ eventId = 'human-new-ready'; kind = 'ready_for_review'; taskId = 65; revision = $humanNewSha; reviewerId = $humanNewState.reviewer; authorization = $humanNewState.authorization } | Out-Null
$humanNewAcceptance = New-TaskAcceptanceEvent $humanNewState 'accept-human-new' $humanNewSha
$humanNewState.provider.tasks['65'].statusId = $humanNewState.provider.statusMapping.not_started
$humanNewState.provider.tasks['65'].version++
Add-ProviderHistory $humanNewState.provider.tasks['65'] 'human_edit' 'human-new-before-acceptance'
$humanNewConflict = Resume-ImplementerOnReviewerMessage $humanNewState $humanNewAcceptance
Assert-True ($humanNewConflict.decision -eq 'reconcile_required') 'a human change to another status must hold acceptance'
$humanNewRecovery = Resume-ImplementerOnReviewerMessage $humanNewState $humanNewAcceptance
Assert-True ($humanNewRecovery.decision -eq 'reconcile_required' -and $humanNewState.provider.tasks['65'].statusId -eq $humanNewState.provider.statusMapping.not_started -and @($humanNewState.provider.taskWrites).Count -eq 0) 'normal recovery must not overwrite a changed human status without a decision'

$lostState = New-ReconciliationState 'per_task'
$lostSha = ('e' * 40)
Complete-ReviewHandoff $lostState @{ eventId = 'lost-ready'; kind = 'ready_for_review'; taskId = 65; revision = $lostSha; reviewerId = $lostState.reviewer; authorization = $lostState.authorization } | Out-Null
$lostAcceptance = New-TaskAcceptanceEvent $lostState 'accept-response-lost' $lostSha
$lostMarker = "task|65|$lostSha"
$lostState.provider.barriers.taskResponseLost[$lostMarker] = $true
$lostResult = Resume-ImplementerOnReviewerMessage $lostState $lostAcceptance
Assert-True ($lostResult.decision -eq 'advance_next_task' -and $lostState.acceptanceJournal[$lostMarker].statusOutcome -eq 'confirmed_after_response_loss') 'an applied-but-response-lost task write must be confirmed by rereading authoritative detail'
Assert-True (@($lostState.provider.taskWrites).Count -eq 1) 'response-lost task writes must not be blindly retried'

$interruptedState = New-ReconciliationState 'per_task'
$interruptedSha = ('f' * 40)
Complete-ReviewHandoff $interruptedState @{ eventId = 'interrupted-ready'; kind = 'ready_for_review'; taskId = 65; revision = $interruptedSha; reviewerId = $interruptedState.reviewer; authorization = $interruptedState.authorization } | Out-Null
$interruptedAcceptance = New-TaskAcceptanceEvent $interruptedState 'accept-interrupted' $interruptedSha
$interruptedMarker = "task|65|$interruptedSha"
$interruptedJournal = [ordered]@{ marker = $interruptedMarker; statusConfirmed = $false; commentConfirmed = $false; humanDecision = $null }
$interruptedState.acceptanceJournal[$interruptedMarker] = $interruptedJournal
$interruptedState.pendingAcceptance = $interruptedJournal
$interruptedBefore = Get-ProviderTaskSnapshot $interruptedState.provider 65
$interruptedDescription = Merge-ProviderChecklist $interruptedBefore.description @($interruptedAcceptance.checklistEvidence)
$null = Confirm-ProviderTaskWrite $interruptedState $interruptedJournal $interruptedAcceptance $interruptedBefore $interruptedDescription
$interruptedRecovered = Reconcile-TaskAcceptance $interruptedState $interruptedAcceptance
Assert-True ($interruptedRecovered.decision -eq 'advance_next_task' -and @($interruptedState.provider.taskWrites).Count -eq 1 -and @($interruptedState.provider.storyWrites).Count -eq 1) 'resume after an interrupted task/comment sequence must finish only the missing progress write'

$finalTaskState = New-ReconciliationState 'per_task'
$firstFinalSha = ('1' * 40)
$lastFinalSha = ('2' * 40)
Complete-ReviewHandoff $finalTaskState @{ eventId = 'final-first-ready'; kind = 'ready_for_review'; taskId = 65; revision = $firstFinalSha; reviewerId = $finalTaskState.reviewer; authorization = $finalTaskState.authorization } | Out-Null
$firstFinalAcceptance = New-TaskAcceptanceEvent $finalTaskState 'final-first-accept' $firstFinalSha
Assert-True ((Resume-ImplementerOnReviewerMessage $finalTaskState $firstFinalAcceptance).decision -eq 'advance_next_task') 'the first accepted task must release the next declared task'
Complete-ReviewHandoff $finalTaskState @{ eventId = 'final-last-ready'; kind = 'ready_for_review'; taskId = 66; revision = $lastFinalSha; reviewerId = $finalTaskState.reviewer; authorization = $finalTaskState.authorization } | Out-Null
$lastFinalAcceptance = New-TaskAcceptanceEvent $finalTaskState 'final-last-accept' $lastFinalSha 66
$finalTaskResult = Resume-ImplementerOnReviewerMessage $finalTaskState $lastFinalAcceptance
Assert-True ($finalTaskResult.decision -eq 'final_story_review' -and @($finalTaskState.actions | Where-Object kind -eq 'story_review').Count -eq 1) 'the final task must hand off final story review after reconciliation'
Assert-True (-not $finalTaskState.storyMerged -and -not $finalTaskState.storyReleased) 'final task acceptance must not merge or release the story'

$escalatedFinalState = New-ReconciliationState 'story_end_only'
$escalatedFinalFirstSha = ('9' * 40)
$escalatedFinalLastSha = ('a' * 40)
Apply-Event $escalatedFinalState @{ eventId = 'escalated-final-ready-1'; kind = 'implementation_ready'; taskId = 65; revision = $escalatedFinalFirstSha; authorization = $escalatedFinalState.authorization } | Out-Null
foreach ($providerTask in @($escalatedFinalState.provider.tasks.Values)) {
    $providerTask.statusId = $escalatedFinalState.provider.statusMapping.awaiting_review
    $providerTask.version++
}
Apply-Event $escalatedFinalState @{ eventId = 'escalated-final-ready-2'; kind = 'implementation_ready'; taskId = 66; revision = $escalatedFinalLastSha; authorization = $escalatedFinalState.authorization } | Out-Null
$escalatedFinalState.turnStatus = 'awaiting_review'
Apply-Event $escalatedFinalState @{ eventId = 'escalated-final-conflict'; kind = 'revision_conflict'; taskId = 66; revision = $escalatedFinalLastSha; authorization = $escalatedFinalState.authorization } | Out-Null
$escalatedFinalAcceptance = New-StoryAcceptanceEvent $escalatedFinalState 'escalated-final-acceptance' $escalatedFinalLastSha
Assert-Throws { Resume-ImplementerOnReviewerMessage $escalatedFinalState $escalatedFinalAcceptance | Out-Null } 'final story acceptance must honor pending coordinator reconciliation'
Assert-True ($escalatedFinalState.finalStoryState -eq 'pending' -and @($escalatedFinalState.provider.taskWrites).Count -eq 0 -and @($escalatedFinalState.pendingEscalations).Count -eq 1) 'final story acceptance must not bypass an unresolved escalation'

$storyEndState = New-ReconciliationState 'story_end_only'
$storyEndFirstSha = ('3' * 40)
$storyEndLastSha = ('4' * 40)
Apply-Event $storyEndState @{ eventId = 'story-end-ready-1'; kind = 'implementation_ready'; taskId = 65; revision = $storyEndFirstSha; authorization = $storyEndState.authorization } | Out-Null
foreach ($providerTask in @($storyEndState.provider.tasks.Values)) {
    $providerTask.statusId = $storyEndState.provider.statusMapping.awaiting_review
    $providerTask.version++
}
Apply-Event $storyEndState @{ eventId = 'story-end-ready-2'; kind = 'implementation_ready'; taskId = 66; revision = $storyEndLastSha; authorization = $storyEndState.authorization } | Out-Null
Assert-True (@($storyEndState.provider.tasks.Values | Where-Object { $_.statusId -eq $storyEndState.provider.statusMapping.accepted }).Count -eq 0) 'story_end_only implementation milestones must not close tasks'
$storyEndState.provider.tasks['65'].statusId = $storyEndState.provider.statusMapping.not_started
$storyEndState.provider.tasks['65'].version++
Add-ProviderHistory $storyEndState.provider.tasks['65'] 'human_edit' 'story-end-human-before-duplicate-readiness'
$duplicateFinalReadiness = Apply-Event $storyEndState @{ eventId = 'story-end-ready-2-replayed'; kind = 'implementation_ready'; taskId = 66; revision = $storyEndLastSha; authorization = $storyEndState.authorization }
Assert-True ($duplicateFinalReadiness.decision -eq 'duplicate' -and $storyEndState.providerReviewBaselines['65'].statusId -eq $storyEndState.provider.statusMapping.awaiting_review) 'duplicate final readiness must not replace the frozen review baseline'
$storyEndState.turnStatus = 'awaiting_review'
$unrelatedStoryAcceptance = New-StoryAcceptanceEvent $storyEndState 'story-end-unrelated-sha' (('5' * 40))
Assert-Throws { Resume-ImplementerOnReviewerMessage $storyEndState $unrelatedStoryAcceptance | Out-Null } 'final story acceptance must match the pending final-review SHA'
$storyEndAcceptance = New-StoryAcceptanceEvent $storyEndState 'story-end-final-accept' $storyEndLastSha
$storyEndConflict = Resume-ImplementerOnReviewerMessage $storyEndState $storyEndAcceptance
Assert-True ($storyEndConflict.decision -eq 'reconcile_required' -and $storyEndState.finalStoryState -ne 'accepted') 'final story acceptance must preserve a human status until a decision'
$storyEndAcceptance.humanDecision = 'replace_after_decision'
$storyEndResult = Resume-ImplementerOnReviewerMessage $storyEndState $storyEndAcceptance
Assert-True ($storyEndResult.decision -eq 'final_story_reconciled' -and $storyEndState.finalStoryState -eq 'accepted') 'final story acceptance must reconcile deferred task closure'
Assert-True (@($storyEndState.provider.tasks.Values | Where-Object { $_.statusId -ne $storyEndState.provider.statusMapping.accepted }).Count -eq 0) 'final story acceptance must close every implementation task with current versions'
Assert-True (-not $storyEndState.storyMerged -and -not $storyEndState.storyReleased) 'final story acceptance must preserve separate merge and release gates'
$storyEndTaskWrites = @($storyEndState.provider.taskWrites).Count
$storyEndComments = @($storyEndState.provider.storyWrites).Count
$storyEndDuplicate = Copy-ReconciliationEvent $storyEndAcceptance; $storyEndDuplicate.eventId = 'story-end-final-replayed'
Assert-True ((Resume-ImplementerOnReviewerMessage $storyEndState $storyEndDuplicate).decision -eq 'duplicate') 'duplicate final story acceptance must be a no-op'
Assert-True (@($storyEndState.provider.taskWrites).Count -eq $storyEndTaskWrites -and @($storyEndState.provider.storyWrites).Count -eq $storyEndComments) 'duplicate final story acceptance must not repeat closure or comments'

Write-Output 'Passed automatic review-flow fixture: trace-derived end-of-turn initial/correction handoffs with post-termination action rejection, reviewer-message resume, no implementer polling/monitor/keep-alive/unchanged acknowledgement, healthy-versus-unresolved-delivery recovery, implementer-owned version-safe Taiga reconciliation with checklist/comment idempotency, human/version/response-loss/interruption barriers, direct acceptance/advancement, final-task and final-story gates, both review modes, duplicate/stale/idle guards, coordinator escalation, and scope gating.'
