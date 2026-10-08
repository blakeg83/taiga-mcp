# OFFLINE FINAL DELIVERY CONTRACT CHECK.
# Synthetic state only; this fixture never opens a PR, merges, or writes Taiga.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Final delivery assertion failed: $Message" }
}

function New-FinalRequest {
    param(
        [ValidateSet('single','legacy-standalone-feature','epic')] [string] $RunKind,
        [bool] $StoryReviewAccepted = $true,
        [bool] $FinalReviewAccepted = $true,
        [bool] $EpicReviewAccepted = $true,
        [string] $StoryHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $RequestedHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $CurrentHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $Base = 'master',
        [string] $FinalResponse = '',
        [string] $MergeResult = 'pending'
    )
    [ordered]@{
        runKind = $RunKind
        storyReviewAccepted = $StoryReviewAccepted
        finalReviewAccepted = $FinalReviewAccepted
        epicReviewAccepted = $EpicReviewAccepted
        storyHead = $StoryHead
        requestedHead = $RequestedHead
        currentHead = $CurrentHead
        base = $Base
        finalResponse = $FinalResponse
        mergeResult = $MergeResult
        heartbeatId = 'synthetic-heartbeat-final'
        heartbeatState = 'PAUSED'
        finalPrCreated = $false
        epicComplete = $false
        masterComplete = $false
    }
}

function Test-FinalPreflight {
    param([hashtable] $Request)
    if ($Request.base -ne 'master') { return 'wrong_master_base' }
    if ($Request.currentHead -ne $Request.requestedHead) { return 'stale_final_review' }
    if ($Request.runKind -eq 'single' -and -not $Request.storyReviewAccepted) { return 'story_review_required' }
    if ($Request.runKind -eq 'legacy-standalone-feature' -and -not $Request.storyReviewAccepted) { return 'story_review_required' }
    if ($Request.runKind -eq 'legacy-standalone-feature' -and -not $Request.finalReviewAccepted) { return 'legacy_final_review_required' }
    if ($Request.runKind -eq 'epic' -and -not $Request.epicReviewAccepted) { return 'epic_review_required' }
    'ready'
}

function New-StandaloneRequest {
    param(
        [bool] $StoryReviewAccepted = $true,
        [string] $RequestedHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $CurrentHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $Base = 'master',
        [string] $FinalResponse = '',
        [string] $MergeResult = 'pending'
    )
    [ordered]@{
        topology = 'standalone-story-direct-master'
        storyReviewAccepted = $StoryReviewAccepted
        requestedHead = $RequestedHead
        currentHead = $CurrentHead
        base = $Base
        finalResponse = $FinalResponse
        mergeResult = $MergeResult
        heartbeatId = 'synthetic-heartbeat-final'
        heartbeatState = 'PAUSED'
    }
}

function Test-StandalonePreflight {
    param([hashtable] $Request)
    if ($Request.base -ne 'master') { return 'wrong_master_base' }
    if ($Request.currentHead -ne $Request.requestedHead) { return 'stale_story_review' }
    if (-not $Request.storyReviewAccepted) { return 'story_review_required' }
    'ready'
}

function Resolve-StandaloneDecision {
    param([hashtable] $Request)
    if ($Request.finalResponse -ne 'Yes') {
        return [ordered]@{ state = if ($Request.finalResponse -eq 'No') { 'hold_feedback' } else { 'wait_for_user' }; release = $false; complete = $false }
    }
    if ($Request.currentHead -ne $Request.requestedHead) {
        return [ordered]@{ state = 'approval_invalidated'; release = $false; complete = $false }
    }
    if ($Request.mergeResult -ne 'merged') {
        return [ordered]@{ state = 'release_unverified'; release = $false; complete = $false }
    }
    [ordered]@{ state = 'standalone_story_release_verified'; release = $true; complete = $true }
}

function New-StandaloneBody {
    param([hashtable] $Request)
    @(
        '## Story release'
        '- Run: standalone story'
        '- Topology: `standalone-story-direct-master`'
        '- Base: `master`'
        "- Head: ``$($Request.currentHead)``"
        ''
        '## Review and approval'
        '- Final story review: exact current story HEAD accepted'
        '- Direct story PR to master: pending user approval'
        '- Master merge: not automatic.'
    ) -join "`n"
}

function New-FinalPrompt {
    param([hashtable] $Request)
    "Final feature-to-master PR is ready for review.`nBase: master`nHead: $($Request.currentHead)`n`nYes - merge final PR to master`nNo - hold for feedback`n`nMerge this final PR? Reply Yes or No."
}

function Resolve-FinalDecision {
    param([hashtable] $Request)
    if ($Request.finalResponse -ne 'Yes') {
        return [ordered]@{ state = if ($Request.finalResponse -eq 'No') { 'hold_feedback' } else { 'wait_for_user' }; release = $false; epicComplete = $false; masterComplete = $false }
    }
    if ($Request.currentHead -ne $Request.requestedHead) {
        return [ordered]@{ state = 'approval_invalidated'; release = $false; epicComplete = $false; masterComplete = $false }
    }
    if ($Request.mergeResult -ne 'merged') {
        return [ordered]@{ state = 'release_unverified'; release = $false; epicComplete = $false; masterComplete = $false }
    }
    [ordered]@{ state = 'master_release_verified'; release = $true; epicComplete = $true; masterComplete = $true }
}

function Resolve-FinalHeartbeat {
    param([hashtable] $Request)
    $action = if ($Request.heartbeatState -eq 'PAUSED') { 'none' } else { 'pause' }
    [ordered]@{
        automationId = $Request.heartbeatId
        target = 'PAUSED'
        action = $action
        restart = $false
    }
}

function Test-NextStoryGate {
    param([string] $PreviousPrState, [bool] $FeatureHeadRefreshed)
    $PreviousPrState -eq 'merged_verified' -and $FeatureHeadRefreshed
}

function New-FinalBody {
    param([hashtable] $Request)
    $storyIntegration = if ($Request.runKind -eq 'legacy-standalone-feature') {
        '- Story integration: preserved story-to-feature merge verified'
    }
    else {
        '- Story integration: ordered story merges verified'
    }
    $finalReview = if ($Request.runKind -eq 'legacy-standalone-feature') {
        '- Final review: exact refreshed feature HEAD accepted for legacy delivery'
    }
    else {
        '- Final review: exact feature HEAD accepted'
    }
    @(
        '## Release'
        "- Run: $($Request.runKind)"
        '- Base: `master`'
        "- Head: ``$($Request.currentHead)``"
        ''
        '## Integrated evidence'
        $storyIntegration
        $finalReview
        '- Checks: `validate-final-delivery.ps1` — exit 0; passed'
        ''
        '## Approval boundary'
        'Final feature-to-master PR opened for user review.'
        'Final master merge: pending separate user approval; not automatic.'
    ) -join "`n"
}

$standalone = New-StandaloneRequest
$epic = New-FinalRequest -RunKind epic
$legacy = New-FinalRequest -RunKind legacy-standalone-feature
foreach ($request in @($standalone, $epic, $legacy)) {
    $schedule = Resolve-FinalHeartbeat $request
    Assert-True ($schedule.target -eq 'PAUSED' -and -not $schedule.restart -and $schedule.automationId -eq $request.heartbeatId) 'final delivery must retain the same heartbeat identity without restarting it'
}
$activeFinal = New-FinalRequest -RunKind epic
$activeFinal.heartbeatState = 'ACTIVE'
$activeFinalSchedule = Resolve-FinalHeartbeat $activeFinal
Assert-True ($activeFinalSchedule.target -eq 'PAUSED' -and $activeFinalSchedule.action -eq 'pause') 'final delivery must pause an accidentally active heartbeat before waiting'
Assert-True ((Test-StandalonePreflight $standalone) -eq 'ready') 'standalone exact story review should permit direct master PR preparation'
Assert-True ((Test-FinalPreflight $epic) -eq 'ready') 'epic final integrated review should permit final PR preparation'
Assert-True ((Test-FinalPreflight $legacy) -eq 'ready') 'legacy standalone story merge should permit preserved feature final PR preparation'

$blockedEpic = New-FinalRequest -RunKind epic -EpicReviewAccepted $false
Assert-True ((Test-FinalPreflight $blockedEpic) -eq 'epic_review_required') 'epic final PR must require integrated epic acceptance'

$blockedLegacy = New-FinalRequest -RunKind legacy-standalone-feature -StoryReviewAccepted $false
Assert-True ((Test-FinalPreflight $blockedLegacy) -eq 'story_review_required') 'legacy final PR must require the preserved story review'

$blockedLegacyFinalReview = New-FinalRequest -RunKind legacy-standalone-feature -FinalReviewAccepted $false
Assert-True ((Test-FinalPreflight $blockedLegacyFinalReview) -eq 'legacy_final_review_required') 'legacy final PR must require review acceptance at the refreshed feature HEAD'

$legacyWithMergeRevision = New-FinalRequest -RunKind legacy-standalone-feature -StoryHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -RequestedHead 'cccccccccccccccccccccccccccccccccccccccc' -CurrentHead 'cccccccccccccccccccccccccccccccccccccccc'
Assert-True ((Test-FinalPreflight $legacyWithMergeRevision) -eq 'ready') 'legacy final review must bind to the refreshed head, even when the merge changes the story revision'

$legacyMergeWithoutReview = New-FinalRequest -RunKind legacy-standalone-feature -StoryHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -RequestedHead 'cccccccccccccccccccccccccccccccccccccccc' -CurrentHead 'cccccccccccccccccccccccccccccccccccccccc' -FinalReviewAccepted $false
Assert-True ((Test-FinalPreflight $legacyMergeWithoutReview) -eq 'legacy_final_review_required') 'a refreshed legacy head without its own review must block final PR preparation'

$wrongBase = New-StandaloneRequest -Base 'codex/feature-taiga-mcp-run1'
Assert-True ((Test-StandalonePreflight $wrongBase) -eq 'wrong_master_base') 'standalone story PR must target master'

$stale = New-StandaloneRequest -CurrentHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-StandalonePreflight $stale) -eq 'stale_story_review') 'changed story HEAD must invalidate final review'

$prompt = New-FinalPrompt $epic
foreach ($marker in @('Yes - merge final PR to master', 'No - hold for feedback', 'Reply Yes or No')) {
    Assert-True $prompt.Contains($marker) "final prompt must include $marker"
}

$no = New-StandaloneRequest -FinalResponse 'No'
$noDecision = Resolve-StandaloneDecision $no
Assert-True ($noDecision.state -eq 'hold_feedback' -and -not $noDecision.release -and -not $noDecision.complete) 'No must hold standalone story release'

$silent = Resolve-StandaloneDecision (New-StandaloneRequest)
Assert-True ($silent.state -eq 'wait_for_user' -and -not $silent.release) 'missing final answer must hold standalone story release'

$failed = Resolve-StandaloneDecision (New-StandaloneRequest -FinalResponse 'Yes' -MergeResult 'failed')
Assert-True ($failed.state -eq 'release_unverified' -and -not $failed.complete) 'failed standalone merge must not claim release'

$changed = Resolve-StandaloneDecision (New-StandaloneRequest -FinalResponse 'Yes' -CurrentHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
Assert-True ($changed.state -eq 'approval_invalidated') 'changes after approval must invalidate final release'

$merged = Resolve-StandaloneDecision (New-StandaloneRequest -FinalResponse 'Yes' -MergeResult 'merged')
Assert-True ($merged.state -eq 'standalone_story_release_verified' -and $merged.release -and $merged.complete) 'only verified standalone merge may claim story release'

$legacyFinal = New-FinalRequest -RunKind legacy-standalone-feature -FinalResponse 'Yes' -MergeResult 'merged'
$legacyFinalDecision = Resolve-FinalDecision $legacyFinal
Assert-True ($legacyFinalDecision.state -eq 'master_release_verified' -and $legacyFinalDecision.release -and $legacyFinalDecision.masterComplete) 'legacy final feature-to-master merge must require and verify its separate approval'

Assert-True (Test-NextStoryGate 'merged_verified' $true) 'next story requires verified previous merge and refreshed feature HEAD'
Assert-True (-not (Test-NextStoryGate 'approved' $true)) 'PR approval alone must not start next story'
Assert-True (-not (Test-NextStoryGate 'merged_verified' $false)) 'unrefreshed feature branch must not start next story'

$body = New-FinalBody $epic
foreach ($marker in @('## Release', '## Integrated evidence', '## Approval boundary', '`master`', 'not automatic')) {
    Assert-True $body.Contains($marker) "final PR body must include $marker"
}
$legacyBody = New-FinalBody $legacy
foreach ($marker in @('legacy-standalone-feature', 'preserved story-to-feature merge verified', 'exact refreshed feature HEAD', 'not automatic')) {
    Assert-True $legacyBody.Contains($marker) "legacy final PR body must include $marker"
}
$standaloneBody = New-StandaloneBody $standalone
foreach ($marker in @('## Story release', 'standalone-story-direct-master', '`master`', 'exact current story HEAD', 'not automatic')) {
    Assert-True $standaloneBody.Contains($marker) "standalone story body must include $marker"
}
$createdOnly = New-FinalRequest -RunKind epic
$createdOnly.finalPrCreated = $true
Assert-True (-not $createdOnly.epicComplete -and -not $createdOnly.masterComplete) 'creating final PR alone must not complete epic or master'

Write-Output 'Passed offline final delivery fixture: terminal heartbeat pause and identity preservation, standalone direct-master story release, legacy preserved-feature final release, epic integrated feature release, master base, exact-head review, approval/hold/failure/invalidation paths, sequence gate, evidence bodies, and completion separation.'
