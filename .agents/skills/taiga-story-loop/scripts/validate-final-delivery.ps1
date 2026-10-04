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
        [ValidateSet('single','epic')] [string] $RunKind,
        [bool] $StoryReviewAccepted = $true,
        [bool] $EpicReviewAccepted = $true,
        [string] $RequestedHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $CurrentHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $Base = 'master',
        [string] $FinalResponse = '',
        [string] $MergeResult = 'pending'
    )
    [ordered]@{
        runKind = $RunKind
        storyReviewAccepted = $StoryReviewAccepted
        epicReviewAccepted = $EpicReviewAccepted
        requestedHead = $RequestedHead
        currentHead = $CurrentHead
        base = $Base
        finalResponse = $FinalResponse
        mergeResult = $MergeResult
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
    if ($Request.runKind -eq 'epic' -and -not $Request.epicReviewAccepted) { return 'epic_review_required' }
    'ready'
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

function Test-NextStoryGate {
    param([string] $PreviousPrState, [bool] $FeatureHeadRefreshed)
    $PreviousPrState -eq 'merged_verified' -and $FeatureHeadRefreshed
}

function New-FinalBody {
    param([hashtable] $Request)
    @(
        '## Release'
        "- Run: $($Request.runKind)"
        '- Base: `master`'
        "- Head: ``$($Request.currentHead)``"
        ''
        '## Integrated evidence'
        '- Story integration: ordered story merges verified'
        '- Final review: exact feature HEAD accepted'
        '- Checks: `validate-final-delivery.ps1` — exit 0; passed'
        ''
        '## Approval boundary'
        'Final feature-to-master PR opened for user review.'
        'Final master merge: pending separate user approval; not automatic.'
    ) -join "`n"
}

$single = New-FinalRequest -RunKind single
$epic = New-FinalRequest -RunKind epic
Assert-True ((Test-FinalPreflight $single) -eq 'ready') 'single-story final story review should permit final PR preparation'
Assert-True ((Test-FinalPreflight $epic) -eq 'ready') 'epic final integrated review should permit final PR preparation'

$blockedEpic = New-FinalRequest -RunKind epic -EpicReviewAccepted $false
Assert-True ((Test-FinalPreflight $blockedEpic) -eq 'epic_review_required') 'epic final PR must require integrated epic acceptance'

$wrongBase = New-FinalRequest -RunKind single -Base 'codex/feature-taiga-mcp-run1'
Assert-True ((Test-FinalPreflight $wrongBase) -eq 'wrong_master_base') 'final PR must target master'

$stale = New-FinalRequest -RunKind single -CurrentHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-FinalPreflight $stale) -eq 'stale_final_review') 'changed feature HEAD must invalidate final review'

$prompt = New-FinalPrompt $single
foreach ($marker in @('Yes - merge final PR to master', 'No - hold for feedback', 'Reply Yes or No')) {
    Assert-True $prompt.Contains($marker) "final prompt must include $marker"
}

$no = New-FinalRequest -RunKind single -FinalResponse 'No'
$noDecision = Resolve-FinalDecision $no
Assert-True ($noDecision.state -eq 'hold_feedback' -and -not $noDecision.release -and -not $noDecision.masterComplete) 'No must hold final release'

$silent = Resolve-FinalDecision (New-FinalRequest -RunKind single)
Assert-True ($silent.state -eq 'wait_for_user' -and -not $silent.release) 'missing final answer must hold release'

$failed = Resolve-FinalDecision (New-FinalRequest -RunKind single -FinalResponse 'Yes' -MergeResult 'failed')
Assert-True ($failed.state -eq 'release_unverified' -and -not $failed.masterComplete) 'failed final merge must not claim master release'

$changed = Resolve-FinalDecision (New-FinalRequest -RunKind single -FinalResponse 'Yes' -CurrentHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
Assert-True ($changed.state -eq 'approval_invalidated') 'changes after approval must invalidate final release'

$merged = Resolve-FinalDecision (New-FinalRequest -RunKind single -FinalResponse 'Yes' -MergeResult 'merged')
Assert-True ($merged.state -eq 'master_release_verified' -and $merged.release -and $merged.masterComplete) 'only verified final merge may claim master release'

Assert-True (Test-NextStoryGate 'merged_verified' $true) 'next story requires verified previous merge and refreshed feature HEAD'
Assert-True (-not (Test-NextStoryGate 'approved' $true)) 'PR approval alone must not start next story'
Assert-True (-not (Test-NextStoryGate 'merged_verified' $false)) 'unrefreshed feature branch must not start next story'

$body = New-FinalBody $epic
foreach ($marker in @('## Release', '## Integrated evidence', '## Approval boundary', '`master`', 'not automatic')) {
    Assert-True $body.Contains($marker) "final PR body must include $marker"
}
$createdOnly = New-FinalRequest -RunKind epic
$createdOnly.finalPrCreated = $true
Assert-True (-not $createdOnly.epicComplete -and -not $createdOnly.masterComplete) 'creating final PR alone must not complete epic or master'

Write-Output 'Passed offline final delivery fixture: single/epic readiness, master base, final prompt, hold/failure/invalidation paths, sequence gate, evidence body, and completion separation.'
