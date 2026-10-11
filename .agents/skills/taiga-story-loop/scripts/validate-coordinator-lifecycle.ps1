# Deterministic coordinator lifecycle/action-trace fixture.
# It uses synthetic state only: no live chats, schedules, Taiga writes, or sleeps.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Throws([scriptblock] $Action, [string] $Message) {
    $thrown = $false
    try { & $Action } catch { $thrown = $true }
    Assert-True $thrown $Message
}

function New-LifecycleState {
    param(
        [ValidateSet('story', 'epic')] [string] $PairKind,
        [ValidateSet('per_task', 'story_end_only')] [string] $ReviewMode
    )

    [ordered]@{
        PairKind = $PairKind
        ReviewMode = $ReviewMode
        CurrentTask = 1
        CurrentRevision = 'feature-head-a1'
        Setup = [ordered]@{
            IdentitiesConfirmed = $true
            AssignmentsConfirmed = $true
            ContinuationConfirmed = $true
            HeartbeatConfirmed = $true
        }
        DispatchConfirmed = $false
        CoordinatorTurn = 'active'
        PendingCoordinator = $null
        Heartbeat = [ordered]@{
            Schedule = 'ACTIVE'
            TickConsumed = $false
            CursorSnapshot = 'implementer impl-cursor-a1 | reviewer review-cursor-a1'
        }
        Workers = @(
            [pscustomobject]@{ Role = 'implementer'; State = 'running'; ThreadId = 'impl-thread'; HostId = 'local'; Cursor = 'impl-cursor-a1' }
            [pscustomobject]@{ Role = 'reviewer'; State = 'running'; ThreadId = 'review-thread'; HostId = 'local'; Cursor = 'review-cursor-a1' }
        )
        CoordinatorActions = [System.Collections.Generic.List[object]]::new()
        WorkerEvents = [System.Collections.Generic.List[object]]::new()
        WaitInvocations = [System.Collections.Generic.List[object]]::new()
        TickHistory = [System.Collections.Generic.List[object]]::new()
        ConsumedEvents = [System.Collections.Generic.HashSet[string]]::new()
        IntegratedReviewHead = 'integrated-head-a1'
        IntegratedFeatureHead = $null
        ExactHeadRereviews = [System.Collections.Generic.List[string]]::new()
        TaskAccepted = $false
    }
}

function Add-CoordinatorAction {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [string] $Kind
    )

    [void]$State.CoordinatorActions.Add([pscustomobject]@{ Kind = $Kind })
}

function Assert-DispatchTerminal {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State)

    $lastAction = if ($State.CoordinatorActions.Count -eq 0) { $null } else { [string]$State.CoordinatorActions[$State.CoordinatorActions.Count - 1].Kind }
    Assert-True ($State.DispatchConfirmed -and $State.CoordinatorTurn -eq 'ended' -and $lastAction -eq 'end_turn') 'confirmed dispatch must end the coordinator turn'
}

function Confirm-Dispatch {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State)

    if ($State.DispatchConfirmed) { throw 'duplicate dispatch is not allowed' }
    foreach ($key in @('IdentitiesConfirmed', 'AssignmentsConfirmed', 'ContinuationConfirmed', 'HeartbeatConfirmed')) {
        if (-not $State.Setup[$key]) { throw "dispatch is unresolved: $key" }
    }
    $State.DispatchConfirmed = $true
    Add-CoordinatorAction -State $State -Kind 'confirmed_dispatch'
    $State.CoordinatorTurn = 'ended'
    Add-CoordinatorAction -State $State -Kind 'end_turn'
    Assert-DispatchTerminal -State $State
}

function Invoke-CoordinatorAction {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [string] $Kind
    )

    $forbidden = @(
        'wait_threads', 'foreground_wait', 'poll_worker', 'poll_reviewer',
        'keep_alive', 'read_transcript', 'read_ticket', 'read_source',
        'wake_awaiting_review', 'poll_awaiting_review'
    )
    if ($forbidden -contains $Kind) { throw "coordinator action '$Kind' is forbidden in the healthy lifecycle" }
    if ($State.CoordinatorTurn -eq 'ended') { throw "coordinator action '$Kind' is forbidden after the terminal dispatch boundary" }
    Add-CoordinatorAction -State $State -Kind $Kind
}

function Invoke-HeartbeatTick {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [int] $TimeoutMs = 0,
        [hashtable] $ReturnedCursors = @{},
        [ValidateSet('unchanged', 'changed', 'unknown', 'failed')] [string] $Outcome = 'unchanged'
    )

    if ($State.Heartbeat.Schedule -eq 'PAUSED') {
        return [pscustomobject]@{ Decision = 'quiet_paused'; Targets = @(); SnapshotChanged = $false }
    }
    if ($State.Heartbeat.Schedule -ne 'ACTIVE') { throw 'unresolved heartbeat schedule requires reconciliation' }
    if ($TimeoutMs -ne 0) { throw 'heartbeat wait must be compact and nonblocking' }
    if ($State.Heartbeat.TickConsumed) { throw 'heartbeat tick may contain at most one wait snapshot' }
    $State.Heartbeat.TickConsumed = $true

    $targets = @($State.Workers | Where-Object {
        [string]$_.State -ceq 'running' -and
        -not ([string]$_.Role -ceq 'implementer' -and [string]$_.State -ceq 'awaiting_review')
    })
    if ($targets.Count -eq 0) {
        return [pscustomobject]@{ Decision = 'quiet_no_eligible_workers'; Targets = @(); SnapshotChanged = $false }
    }
    if ($Outcome -in @('unknown', 'failed')) { throw 'unknown or failed heartbeat result requires reconciliation' }

    $targetPacket = @($targets | ForEach-Object {
        [ordered]@{ Role = [string]$_.Role; ThreadId = [string]$_.ThreadId; HostId = [string]$_.HostId; AfterCursor = [string]$_.Cursor }
    })
    [void]$State.WaitInvocations.Add([pscustomobject]@{ TimeoutMs = 0; Targets = $targetPacket })
    $changed = $false
    foreach ($target in $targets) {
        if ($ReturnedCursors.ContainsKey([string]$target.Role) -and
            [string]$ReturnedCursors[[string]$target.Role] -cne [string]$target.Cursor) {
            $target.Cursor = [string]$ReturnedCursors[[string]$target.Role]
            $changed = $true
        }
    }
    if ($changed) {
        $State.Heartbeat.CursorSnapshot = 'implementer ' + [string]$State.Workers[0].Cursor + ' | reviewer ' + [string]$State.Workers[1].Cursor
    }
    [pscustomobject]@{ Decision = if ($changed) { 'cursor_retained' } else { 'quiet_unchanged' }; Targets = $targetPacket; SnapshotChanged = $changed }
}

function Apply-TaskAcceptance {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Event
    )

    if ([string]$Event.EventId -in $State.ConsumedEvents) { return 'duplicate' }
    if ([int]$Event.TaskId -ne [int]$State.CurrentTask) { throw 'stale task acceptance cannot advance the ordered pointer' }
    if ([string]$Event.Revision -cne [string]$State.CurrentRevision) { throw 'stale task acceptance revision cannot advance the ordered pointer' }
    if (-not $Event.AcceptanceEvidence) { throw 'correction-ready evidence alone is not acceptance' }
    [void]$State.ConsumedEvents.Add([string]$Event.EventId)
    $State.TaskAccepted = $true
    [void]$State.WorkerEvents.Add([pscustomobject]@{ Kind = 'task_acceptance'; Destination = 'implementer'; Revision = [string]$Event.Revision })
    return 'accepted_directly'
}

function Advance-NextTask {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Event
    )

    if ([string]$Event.EventId -in $State.ConsumedEvents) { throw 'duplicate advancement event is not allowed' }
    if (-not $State.TaskAccepted -or [int]$Event.TaskId -ne [int]$State.CurrentTask -or
        [string]$Event.Revision -cne [string]$State.CurrentRevision) {
        throw 'stale or unaccepted event cannot advance the ordered pointer'
    }
    [void]$State.ConsumedEvents.Add([string]$Event.EventId)
    $State.CurrentTask++
    $State.TaskAccepted = $false
    [void]$State.WorkerEvents.Add([pscustomobject]@{ Kind = 'advance_next_task'; Destination = 'implementer'; Task = $State.CurrentTask })
}

function Apply-RoutineEpicFinding {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State)

    if ($State.PairKind -ne 'epic') { throw 'routine epic findings require the integrated pair' }
    [void]$State.WorkerEvents.Add([pscustomobject]@{ Kind = 'epic_finding'; Destination = 'epic-fix-implementer' })
}

function Copy-RoutineEpicFindingToCoordinator {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State)

    throw 'routine epic finding copy to coordinator is forbidden'
}

function Apply-EpicIntegrationReady {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Event
    )

    if ($State.PairKind -ne 'epic' -or [string]$Event.ReviewedHead -cne [string]$State.IntegratedReviewHead) { throw 'integration-ready event is not bound to the reviewed integrated HEAD' }
    foreach ($field in @('FindingId', 'ReviewRequestId', 'CorrectedHead', 'CorrectionBranch', 'CorrectionWorktree', 'CleanSource', 'Delta', 'Checks', 'NextAction')) {
        if (-not $Event.Contains($field) -or [string]::IsNullOrWhiteSpace([string]$Event[$field])) { throw "integration-ready event is missing $field" }
    }
    if (-not $Event.CleanSource -or [string]$Event.CorrectedHead -ceq [string]$Event.ReviewedHead) { throw 'integration-ready event must contain a clean changed revision' }
    if ($null -ne $State.PendingCoordinator) { throw 'a coordinator event is already pending' }
    $State.PendingCoordinator = 'epic_integration'
    $State.CoordinatorTurn = 'active'
    $State.Integration = $Event
}

function Integrate-EpicCorrection {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State)

    if ($State.PendingCoordinator -ne 'epic_integration') { throw 'epic integration requires a current integration-ready event' }
    if ($null -ne $State.IntegratedFeatureHead) { throw 'duplicate epic integration is not allowed' }
    $State.IntegratedFeatureHead = [string]$State.Integration.CorrectedHead
    Add-CoordinatorAction -State $State -Kind 'reviewed_integration'
    [void]$State.ExactHeadRereviews.Add([string]$State.IntegratedFeatureHead)
    Add-CoordinatorAction -State $State -Kind 'exact_feature_head_rereview_dispatch'
    $State.PendingCoordinator = $null
    $State.CoordinatorTurn = 'ended'
    Add-CoordinatorAction -State $State -Kind 'end_turn'
    Assert-DispatchTerminal -State $State
}

function Open-CoordinatorEvent {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $State,
        [Parameter(Mandatory)] [ValidateSet('final_approval', 'genuine_blocker', 'dispatch_reconciliation')] [string] $Kind
    )

    if ($null -ne $State.PendingCoordinator) { throw 'duplicate coordinator event is not allowed' }
    $State.PendingCoordinator = $Kind
    $State.CoordinatorTurn = 'active'
}

function Open-ApprovalGate {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State)

    if ($null -ne $State.PendingCoordinator) { throw 'approval gate cannot overlap another coordinator event' }
    $State.PendingCoordinator = 'pr_approval'
    $State.Heartbeat.Schedule = 'PAUSED'
    $State.CoordinatorTurn = 'active'
    Add-CoordinatorAction -State $State -Kind 'pause_heartbeat_for_approval'
}

function Assert-WorkerDirectRoute {
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $State, [Parameter(Mandatory)] [int] $ActionCount)
    Assert-True ($State.CoordinatorActions.Count -eq $ActionCount) 'routine worker event must not create a coordinator action'
}

# Confirmed dispatch ends the coordinator turn for both story review modes and
# for the separate integrated epic pair.
foreach ($pairKind in @('story', 'epic')) {
    foreach ($reviewMode in @('per_task', 'story_end_only')) {
        $dispatchState = New-LifecycleState -PairKind $pairKind -ReviewMode $reviewMode
        Confirm-Dispatch -State $dispatchState
        Assert-DispatchTerminal -State $dispatchState
    }
}

# Healthy heartbeat budget: no eligible workers means no wait; active workers
# receive one timeoutMs:0 snapshot and a changed cursor is retained.
$noEligible = New-LifecycleState -PairKind story -ReviewMode per_task
$noEligible.Workers[0].State = 'awaiting_review'
$noEligible.Workers[1].State = 'waiting_for_implementation'
$noEligibleResult = Invoke-HeartbeatTick -State $noEligible
Assert-True ($noEligibleResult.Decision -eq 'quiet_no_eligible_workers' -and $noEligible.WaitInvocations.Count -eq 0) 'healthy heartbeat must not wait when no worker is eligible'
$activeHeartbeat = New-LifecycleState -PairKind story -ReviewMode per_task
$activeHeartbeatResult = Invoke-HeartbeatTick -State $activeHeartbeat -ReturnedCursors @{ reviewer = 'review-cursor-b2' }
Assert-True ($activeHeartbeatResult.Decision -eq 'cursor_retained' -and $activeHeartbeat.WaitInvocations.Count -eq 1 -and $activeHeartbeat.WaitInvocations[0].TimeoutMs -eq 0) 'healthy heartbeat must use at most one compact wait'
Assert-True ($activeHeartbeat.Heartbeat.CursorSnapshot.Contains('reviewer review-cursor-b2') -and $activeHeartbeat.TickHistory.Count -eq 0) 'healthy heartbeat must retain changed cursors without tick history'

# Direct worker routes do not add coordinator actions.
$acceptState = New-LifecycleState -PairKind story -ReviewMode per_task
Confirm-Dispatch -State $acceptState
$acceptActionCount = $acceptState.CoordinatorActions.Count
$acceptResult = Apply-TaskAcceptance -State $acceptState -Event ([ordered]@{ EventId = 'accept-1'; TaskId = 1; Revision = 'feature-head-a1'; AcceptanceEvidence = $true })
Assert-True ($acceptResult -eq 'accepted_directly' -and $acceptState.TaskAccepted) 'task acceptance must remain direct to the implementer'
Assert-WorkerDirectRoute -State $acceptState -ActionCount $acceptActionCount
Advance-NextTask -State $acceptState -Event ([ordered]@{ EventId = 'advance-1'; TaskId = 1; Revision = 'feature-head-a1' })
Assert-True ($acceptState.CurrentTask -eq 2 -and -not $acceptState.TaskAccepted) 'accepted direct evidence must allow one ordered next-task advancement'
Assert-Throws { Advance-NextTask -State $acceptState -Event ([ordered]@{ EventId = 'advance-1'; TaskId = 1; Revision = 'feature-head-a1' }) } 'duplicate advancement must be rejected'
$findingState = New-LifecycleState -PairKind epic -ReviewMode story_end_only
Confirm-Dispatch -State $findingState
$findingActionCount = $findingState.CoordinatorActions.Count
Apply-RoutineEpicFinding -State $findingState
Assert-WorkerDirectRoute -State $findingState -ActionCount $findingActionCount
Assert-Throws { Copy-RoutineEpicFindingToCoordinator -State $findingState } 'routine epic finding copy must be rejected'
Assert-WorkerDirectRoute -State $findingState -ActionCount $findingActionCount

# Coordinator-owned integration captures the corrected feature HEAD, dispatches
# exact-head re-review, and ends the resumed turn.
$integrationState = New-LifecycleState -PairKind epic -ReviewMode per_task
Confirm-Dispatch -State $integrationState
Apply-EpicIntegrationReady -State $integrationState -Event ([ordered]@{
    FindingId = 'finding-1'; ReviewRequestId = 'epic-review-1'; ReviewedHead = 'integrated-head-a1'; CorrectedHead = 'feature-head-b2';
    CorrectionBranch = 'epic-fix-branch'; CorrectionWorktree = 'C:\synthetic\epic-fix'; CleanSource = $true; Delta = 'reviewed..corrected'; Checks = 'fixture exit 0'; NextAction = 'exact-head re-review'
})
Assert-True ($integrationState.PendingCoordinator -eq 'epic_integration') 'integration-ready correction must open coordinator integration'
Integrate-EpicCorrection -State $integrationState
Assert-True ($integrationState.IntegratedFeatureHead -eq 'feature-head-b2' -and $integrationState.ExactHeadRereviews[0] -eq 'feature-head-b2' -and $integrationState.CoordinatorActions.Kind -contains 'exact_feature_head_rereview_dispatch') 'integration must dispatch exact feature-head re-review'
Assert-Throws { Integrate-EpicCorrection -State $integrationState } 'duplicate epic integration must be rejected'

# Final approval, genuine blockers, failed/unknown dispatch, and approval waits
# are bounded coordinator events rather than healthy worker progress.
$finalApprovalState = New-LifecycleState -PairKind story -ReviewMode per_task
Open-CoordinatorEvent -State $finalApprovalState -Kind final_approval
Assert-True ($finalApprovalState.PendingCoordinator -eq 'final_approval') 'final approval must open bounded coordinator coordination'
$blockerState = New-LifecycleState -PairKind story -ReviewMode per_task
Open-CoordinatorEvent -State $blockerState -Kind genuine_blocker
Assert-True ($blockerState.PendingCoordinator -eq 'genuine_blocker') 'genuine blocker must open bounded coordinator coordination'
$failedDispatchState = New-LifecycleState -PairKind story -ReviewMode per_task
$failedDispatchState.Setup.AssignmentsConfirmed = $false
Assert-Throws { Confirm-Dispatch -State $failedDispatchState } 'failed dispatch must not be reported as healthy'
Open-CoordinatorEvent -State $failedDispatchState -Kind dispatch_reconciliation
Assert-True (-not $failedDispatchState.DispatchConfirmed -and $failedDispatchState.PendingCoordinator -eq 'dispatch_reconciliation') 'failed dispatch must open reconciliation'
$unknownDispatchState = New-LifecycleState -PairKind story -ReviewMode per_task
Open-CoordinatorEvent -State $unknownDispatchState -Kind dispatch_reconciliation
Assert-True ($unknownDispatchState.PendingCoordinator -eq 'dispatch_reconciliation' -and -not $unknownDispatchState.DispatchConfirmed) 'unknown dispatch must remain bounded and unreplayed'
$approvalState = New-LifecycleState -PairKind story -ReviewMode per_task
Open-ApprovalGate -State $approvalState
$approvalTick = Invoke-HeartbeatTick -State $approvalState
Assert-True ($approvalState.Heartbeat.Schedule -eq 'PAUSED' -and $approvalTick.Decision -eq 'quiet_paused' -and $approvalState.WaitInvocations.Count -eq 0) 'PR approval waiting must keep recovery paused'

# Rejected actions prove the terminal boundary, heartbeat budget, awaiting-review
# quietness, stale-event guard, and correction-evidence acceptance guard.
$brokenBoundary = New-LifecycleState -PairKind story -ReviewMode per_task
$brokenBoundary.DispatchConfirmed = $true
[void]$brokenBoundary.CoordinatorActions.Add([pscustomobject]@{ Kind = 'confirmed_dispatch' })
Assert-Throws { Assert-DispatchTerminal -State $brokenBoundary } 'missing terminal boundary must be rejected'
$terminalState = New-LifecycleState -PairKind story -ReviewMode per_task
Confirm-Dispatch -State $terminalState
$terminalActionCount = $terminalState.CoordinatorActions.Count
foreach ($forbidden in @('foreground_wait', 'poll_worker', 'keep_alive', 'read_transcript')) {
    Assert-Throws { Invoke-CoordinatorAction -State $terminalState -Kind $forbidden } "post-dispatch $forbidden must be rejected"
}
Assert-True ($terminalState.CoordinatorActions.Count -eq $terminalActionCount) 'rejected post-dispatch actions must not append trace entries'
$blockingWait = New-LifecycleState -PairKind story -ReviewMode per_task
Assert-Throws { Invoke-HeartbeatTick -State $blockingWait -TimeoutMs 1000 } 'blocking heartbeat wait must be rejected'
Invoke-HeartbeatTick -State $blockingWait | Out-Null
Assert-Throws { Invoke-HeartbeatTick -State $blockingWait } 'repeated heartbeat wait must be rejected'
$awaitingReview = New-LifecycleState -PairKind story -ReviewMode per_task
$awaitingReview.Workers[0].State = 'awaiting_review'
$awaitingReview.Workers[1].State = 'waiting_for_implementation'
$awaitingResult = Invoke-HeartbeatTick -State $awaitingReview
Assert-True ($awaitingResult.Decision -eq 'quiet_no_eligible_workers' -and $awaitingReview.WaitInvocations.Count -eq 0) 'awaiting_review implementer must not be polled or woken'
Assert-Throws { Invoke-CoordinatorAction -State $awaitingReview -Kind 'wake_awaiting_review' } 'awaiting_review wake-up must be rejected'
$staleState = New-LifecycleState -PairKind story -ReviewMode per_task
Assert-Throws { Apply-TaskAcceptance -State $staleState -Event ([ordered]@{ EventId = 'stale-1'; TaskId = 99; Revision = 'feature-head-a1'; AcceptanceEvidence = $true }) } 'stale task event must not advance the ordered pointer'
Assert-Throws { Apply-TaskAcceptance -State $staleState -Event ([ordered]@{ EventId = 'correction-only-1'; TaskId = 1; Revision = 'feature-head-a1'; AcceptanceEvidence = $false }) } 'correction-ready evidence alone must not become acceptance'
Apply-TaskAcceptance -State $staleState -Event ([ordered]@{ EventId = 'accept-stale-advance'; TaskId = 1; Revision = 'feature-head-a1'; AcceptanceEvidence = $true }) | Out-Null
Assert-Throws { Advance-NextTask -State $staleState -Event ([ordered]@{ EventId = 'stale-advance'; TaskId = 1; Revision = 'old-head' }) } 'stale advancement event must be rejected'
Assert-True ($staleState.CurrentTask -eq 1) 'stale and correction-only events must not mutate the advancement pointer'

Write-Output 'Passed coordinator lifecycle fixture: story per_task/story_end_only and integrated epic dispatch termination, bounded heartbeat waits and cursor retention, direct worker routes, coordinator-owned integration/exact-head re-review, approval pause, actionable reconciliation, and rejected foreground/duplicate/stale/awaiting-review/correction-only actions; synthetic and non-live.'
