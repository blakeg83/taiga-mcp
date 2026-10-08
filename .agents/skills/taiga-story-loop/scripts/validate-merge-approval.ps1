# OFFLINE YES/NO MERGE-GATE CONTRACT CHECK.
# Synthetic state only; this fixture never merges, updates Taiga, or messages a user.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Merge approval assertion failed: $Message" }
}

function New-Gate {
    param(
        [ValidateSet('standalone','legacy-standalone-feature','epic')] [string] $RunKind = 'epic',
        [string] $Head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $CurrentHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $Reply = '',
        [string] $MergeResult = 'pending',
        [string] $PrUrl = 'https://example.invalid/pr/50',
        [string] $CurrentPrUrl = '',
        [string] $Repository = 'TaigaMCP',
        [string] $CurrentRepository = '',
        [string] $Base = 'codex/feature-taiga-mcp-run1',
        [string] $CurrentBase = '',
        [string] $Scope = 'story-50',
        [string] $CurrentScope = '',
        [ValidateSet('ACTIVE','PAUSED')] [string] $HeartbeatState = 'ACTIVE',
        [string] $CurrentHeartbeatState = '',
        [bool] $HasNextStory = $true,
        [bool] $NextStoryStarted = $false
    )
    if ([string]::IsNullOrEmpty($CurrentPrUrl)) { $CurrentPrUrl = $PrUrl }
    if ([string]::IsNullOrEmpty($CurrentRepository)) { $CurrentRepository = $Repository }
    if ([string]::IsNullOrEmpty($CurrentBase)) { $CurrentBase = $Base }
    if ([string]::IsNullOrEmpty($CurrentScope)) { $CurrentScope = $Scope }
    if ([string]::IsNullOrEmpty($CurrentHeartbeatState)) { $CurrentHeartbeatState = $HeartbeatState }
    [ordered]@{
        runKind = $RunKind
        prUrl = $PrUrl
        repository = $Repository
        base = $Base
        scope = $Scope
        reviewedHead = $Head
        currentPrUrl = $CurrentPrUrl
        currentRepository = $CurrentRepository
        currentBase = $CurrentBase
        currentScope = $CurrentScope
        currentHead = $CurrentHead
        reply = $Reply
        mergeResult = $MergeResult
        hasNextStory = $HasNextStory
        nextStoryStarted = $NextStoryStarted
        heartbeatId = 'synthetic-heartbeat-50'
        heartbeatState = $HeartbeatState
        currentHeartbeatState = $CurrentHeartbeatState
        promptCount = 1
        workerDispatchCount = 0
    }
}

function New-MergePrompt {
    param([hashtable] $Gate)
    if ($Gate.runKind -eq 'epic') {
        "Story #50 PR ready: $($Gate.prUrl)`nRepository: $($Gate.repository)`nScope: $($Gate.scope)`nBase: $($Gate.base)`nHead: $($Gate.reviewedHead)`n`nYes - merge and continue to the next ordered story`nNo - hold for feedback`n`nMerge this exact PR and continue? Reply Yes or No."
    }
    elseif ($Gate.runKind -eq 'legacy-standalone-feature') {
        "Story #50 PR ready: $($Gate.prUrl)`nRepository: $($Gate.repository)`nScope: $($Gate.scope)`nBase: $($Gate.base)`nHead: $($Gate.reviewedHead)`n`nLegacy standalone: Yes - merge this exact PR and continue to final release`nNo - hold for feedback`n`nMerge this exact PR and continue to final release? Reply Yes or No."
    }
    else {
        "Story #50 PR ready: $($Gate.prUrl)`nRepository: $($Gate.repository)`nScope: $($Gate.scope)`nBase: $($Gate.base)`nHead: $($Gate.reviewedHead)`n`nYes - merge this exact PR`nNo - hold for feedback`n`nMerge this exact PR? Reply Yes or No."
    }
}

function Resolve-Decision {
    param([hashtable] $Gate)
    if ($Gate.reply -ne 'Yes') {
        return [ordered]@{ state = if ($Gate.reply -eq 'No') { 'hold_feedback' } else { 'wait_for_user' }; merge = $false; advance = $false; dispatch = 0 }
    }
    if ($Gate.currentPrUrl -ne $Gate.prUrl -or
        $Gate.currentRepository -ne $Gate.repository -or
        $Gate.currentBase -ne $Gate.base -or
        $Gate.currentScope -ne $Gate.scope -or
        $Gate.currentHead -ne $Gate.reviewedHead) {
        return [ordered]@{ state = 'approval_stale'; merge = $false; advance = $false; dispatch = 0 }
    }
    if ($Gate.mergeResult -ne 'merged') {
        return [ordered]@{ state = 'merge_unverified'; merge = $false; advance = $false; dispatch = 0 }
    }
    [ordered]@{
        state = 'merged_verified'
        merge = $true
        advance = ($Gate.runKind -eq 'epic' -and $Gate.hasNextStory)
        dispatch = if ($Gate.runKind -eq 'epic' -and $Gate.hasNextStory) { 1 } else { 0 }
        complete = ($Gate.runKind -eq 'standalone')
        finalDelivery = ($Gate.runKind -eq 'legacy-standalone-feature')
        integratedReview = ($Gate.runKind -eq 'epic' -and -not $Gate.hasNextStory)
    }
}

function Resolve-HeartbeatSchedule {
    param([hashtable] $Gate, [hashtable] $Decision)
    $target = if ($Decision.state -eq 'merged_verified' -and
        $Gate.runKind -eq 'epic' -and
        $Gate.hasNextStory -and
        $Gate.nextStoryStarted) { 'ACTIVE' } else { 'PAUSED' }
    $action = if ($Gate.currentHeartbeatState -eq $target) {
        'none'
    }
    elseif ($target -eq 'ACTIVE') {
        'reactivate'
    }
    else {
        'pause'
    }
    [ordered]@{
        automationId = $Gate.heartbeatId
        current = $Gate.currentHeartbeatState
        target = $target
        action = $action
    }
}

function Route-RequestedChanges {
    param([string] $CurrentPair = 'implementer-50/reviewer-50')
    [ordered]@{ destination = $CurrentPair; freshReviewRequired = $true; newPromptRequired = $true; newWorker = $false }
}

$prompt = New-MergePrompt (New-Gate)
foreach ($marker in @('Yes - merge and continue', 'No - hold for feedback', 'https://example.invalid/pr/50', 'Repository: TaigaMCP', 'Scope: story-50', 'Reply Yes or No')) {
    Assert-True $prompt.Contains($marker) "prompt must include $marker"
}

$standalonePrompt = New-MergePrompt (New-Gate -RunKind standalone -Base 'master')
foreach ($marker in @('Yes - merge this exact PR', 'Base: master', 'No - hold for feedback')) {
    Assert-True $standalonePrompt.Contains($marker) "standalone prompt must include $marker"
}
Assert-True (-not $standalonePrompt.Contains('continue to the next ordered story')) 'standalone prompt must not promise a next story'

$legacyPrompt = New-MergePrompt (New-Gate -RunKind legacy-standalone-feature)
foreach ($marker in @('Legacy standalone: Yes - merge this exact PR and continue to final release', 'Base: codex/feature-taiga-mcp-run1', 'No - hold for feedback')) {
    Assert-True $legacyPrompt.Contains($marker) "legacy prompt must include $marker"
}
Assert-True (-not $legacyPrompt.Contains('continue to the next ordered story')) 'legacy prompt must not promise a next story'

$no = Resolve-Decision (New-Gate -Reply 'No')
Assert-True ($no.state -eq 'hold_feedback' -and -not $no.merge -and -not $no.advance -and $no.dispatch -eq 0) 'No must hold without dispatch'

$silent = Resolve-Decision (New-Gate)
Assert-True ($silent.state -eq 'wait_for_user' -and -not $silent.merge -and -not $silent.advance -and $silent.dispatch -eq 0) 'missing response must not authorize merge'
$silentSchedule = Resolve-HeartbeatSchedule (New-Gate) $silent
Assert-True ($silentSchedule.target -eq 'PAUSED' -and $silentSchedule.action -eq 'pause') 'pending approval must pause the active heartbeat'
$alreadyPaused = New-Gate -HeartbeatState 'PAUSED'
$alreadyPausedSchedule = Resolve-HeartbeatSchedule $alreadyPaused (Resolve-Decision $alreadyPaused)
Assert-True ($alreadyPausedSchedule.target -eq 'PAUSED' -and $alreadyPausedSchedule.action -eq 'none') 'paused approval must not schedule another update'

$yesMergedGate = New-Gate -Reply 'Yes' -MergeResult 'merged' -HeartbeatState 'PAUSED' -NextStoryStarted $true
$yesMerged = Resolve-Decision $yesMergedGate
Assert-True ($yesMerged.state -eq 'merged_verified' -and $yesMerged.merge -and $yesMerged.advance -and $yesMerged.dispatch -eq 1) 'explicit Yes plus verified merge must advance'
$yesMergedSchedule = Resolve-HeartbeatSchedule $yesMergedGate $yesMerged
Assert-True ($yesMergedSchedule.target -eq 'ACTIVE' -and $yesMergedSchedule.action -eq 'reactivate' -and $yesMergedSchedule.automationId -eq $yesMergedGate.heartbeatId) 'verified epic merge must reactivate the same heartbeat when the next story starts'

$mergedBeforeNextStory = New-Gate -Reply 'Yes' -MergeResult 'merged' -HeartbeatState 'PAUSED'
$mergedBeforeNextStoryDecision = Resolve-Decision $mergedBeforeNextStory
$mergedBeforeNextStorySchedule = Resolve-HeartbeatSchedule $mergedBeforeNextStory $mergedBeforeNextStoryDecision
Assert-True ($mergedBeforeNextStorySchedule.target -eq 'PAUSED' -and $mergedBeforeNextStorySchedule.action -eq 'none') 'verified merge must remain paused until the next story actually starts'

$standaloneMerged = Resolve-Decision (New-Gate -RunKind standalone -Base 'master' -Reply 'Yes' -MergeResult 'merged')
Assert-True ($standaloneMerged.state -eq 'merged_verified' -and $standaloneMerged.merge -and -not $standaloneMerged.advance -and $standaloneMerged.dispatch -eq 0 -and $standaloneMerged.complete) 'standalone merge must complete without dispatching a next story'
$standaloneScheduleGate = New-Gate -RunKind standalone -Base 'master' -Reply 'Yes' -MergeResult 'merged'
Assert-True ((Resolve-HeartbeatSchedule $standaloneScheduleGate $standaloneMerged).target -eq 'PAUSED') 'standalone completion must leave the heartbeat paused'

$legacyMerged = Resolve-Decision (New-Gate -RunKind legacy-standalone-feature -Reply 'Yes' -MergeResult 'merged')
Assert-True ($legacyMerged.state -eq 'merged_verified' -and $legacyMerged.merge -and -not $legacyMerged.advance -and $legacyMerged.dispatch -eq 0 -and $legacyMerged.finalDelivery -and -not $legacyMerged.complete) 'legacy standalone merge must unlock final delivery without dispatching a next story'
$legacyScheduleGate = New-Gate -RunKind legacy-standalone-feature -Reply 'Yes' -MergeResult 'merged'
Assert-True ((Resolve-HeartbeatSchedule $legacyScheduleGate $legacyMerged).target -eq 'PAUSED') 'legacy final-delivery transition must leave the heartbeat paused'

$finalEpicGate = New-Gate -Reply 'Yes' -MergeResult 'merged' -HasNextStory $false
$finalEpic = Resolve-Decision $finalEpicGate
Assert-True ($finalEpic.state -eq 'merged_verified' -and -not $finalEpic.advance -and $finalEpic.dispatch -eq 0 -and $finalEpic.integratedReview) 'final epic story must enter integrated review without dispatching another story'
Assert-True ((Resolve-HeartbeatSchedule $finalEpicGate $finalEpic).target -eq 'PAUSED') 'final epic story must leave the heartbeat paused'

$yesFailed = Resolve-Decision (New-Gate -Reply 'Yes' -MergeResult 'failed')
Assert-True ($yesFailed.state -eq 'merge_unverified' -and -not $yesFailed.advance -and $yesFailed.dispatch -eq 0) 'failed merge must hold the current story'
Assert-True ((Resolve-HeartbeatSchedule (New-Gate -Reply 'Yes' -MergeResult 'failed') $yesFailed).target -eq 'PAUSED') 'failed merge must keep the heartbeat paused until reconciliation'

$yesStale = Resolve-Decision (New-Gate -Reply 'Yes' -CurrentHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
Assert-True ($yesStale.state -eq 'approval_stale' -and -not $yesStale.merge) 'changed HEAD must invalidate Yes'

foreach ($identityCase in @(
        @{ Name = 'changed PR URL'; Gate = New-Gate -Reply 'Yes' -MergeResult 'merged' -CurrentPrUrl 'https://example.invalid/pr/51' }
        @{ Name = 'changed repository'; Gate = New-Gate -Reply 'Yes' -MergeResult 'merged' -CurrentRepository 'OtherRepo' }
        @{ Name = 'changed base'; Gate = New-Gate -Reply 'Yes' -MergeResult 'merged' -CurrentBase 'master' }
        @{ Name = 'changed story scope'; Gate = New-Gate -Reply 'Yes' -MergeResult 'merged' -CurrentScope 'story-51' }
    )) {
    $identityChanged = Resolve-Decision $identityCase.Gate
    Assert-True ($identityChanged.state -eq 'approval_stale' -and -not $identityChanged.merge -and -not $identityChanged.advance -and $identityChanged.dispatch -eq 0) "$($identityCase.Name) must invalidate Yes"
}

$changes = Route-RequestedChanges
Assert-True ($changes.destination -eq 'implementer-50/reviewer-50' -and $changes.freshReviewRequired -and $changes.newPromptRequired -and -not $changes.newWorker) 'requested changes must return to the existing pair'

$recovery = New-Gate
$recovery.promptCount = 1
$recovery.workerDispatchCount = 0
Assert-True ($recovery.promptCount -eq 1 -and $recovery.workerDispatchCount -eq 0) 'recovery while waiting must not repeat prompt or dispatch'

Write-Output 'Passed offline merge-gate fixture: approval-gate pause, same-heartbeat epic reactivation only when the next story starts, terminal standalone/final-epic/legacy pause, exact PR identity prompt, Yes/No/no-response handling, stale identity or HEAD approval, failed merge hold, correction routing, and quiet recovery.'
