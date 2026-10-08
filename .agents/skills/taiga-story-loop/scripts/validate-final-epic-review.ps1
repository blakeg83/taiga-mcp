# OFFLINE FINAL EPIC REVIEW CONTRACT CHECK.
# Synthetic review records only; this fixture never creates chats, branches,
# commits, merges, or pull requests.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Final epic review assertion failed: $Message" }
}

function New-ReviewRequest {
    param(
        [string] $CurrentHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $RequestedHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string[]] $StoryRefs = @('#46', '#47', '#48', '#49', '#50', '#51', '#52'),
        [bool] $AllMerged = $true
    )
    [ordered]@{
        epicRef = '#45'
        epicSubject = 'Build a lean, message-driven Taiga story loop'
        reviewerModel = 'gpt-6.1-sol'
        reviewerEffort = 'high'
        featureBranch = 'codex/feature-taiga-mcp-run1'
        currentHead = $CurrentHead
        requestedHead = $RequestedHead
        storyRefs = $StoryRefs
        allMerged = $AllMerged
        coverage = @('unmet epic requirements', 'combined behavior', 'cross-story transitions', 'approval boundaries', 'regressions')
    }
}

function Test-ReviewRequest {
    param([hashtable] $Request)
    if ($Request.reviewerModel -ne 'gpt-6.1-sol' -or $Request.reviewerEffort -ne 'high') { return 'wrong_reviewer_profile' }
    if (-not $Request.allMerged) { return 'stories_not_integrated' }
    if ($Request.currentHead -ne $Request.requestedHead) { return 'stale_feature_head' }
    if ($Request.storyRefs.Count -eq 0) { return 'missing_story_scope' }
    'ready'
}

function New-EpicReviewPair {
    [ordered]@{
        implementerModel = 'gpt-5.6-luna'
        implementerEffort = 'xhigh'
        reviewerModel = 'gpt-6.1-sol'
        reviewerEffort = 'high'
        createdBy = 'coordinator'
        freshFromStoryPair = $true
        creationOrder = @('implementer', 'reviewer')
        idsResolved = $true
        reviewerStartedFirst = $true
        implementerWaitingForFinding = $true
        reuseForCorrections = $true
        noPerFindingChat = $true
    }
}

function Test-EpicReviewPair {
    param([hashtable] $Pair)
    if ($Pair.createdBy -ne 'coordinator') { return 'not_coordinator_created' }
    if (-not $Pair.freshFromStoryPair) { return 'reuses_story_pair' }
    if ($Pair.implementerModel -ne 'gpt-5.6-luna' -or $Pair.implementerEffort -ne 'xhigh') { return 'wrong_implementer_profile' }
    if ($Pair.reviewerModel -ne 'gpt-6.1-sol' -or $Pair.reviewerEffort -ne 'high') { return 'wrong_reviewer_profile' }
    if (-not $Pair.idsResolved) { return 'unresolved_worker_ids' }
    if (($Pair.creationOrder -join ',') -ne 'implementer,reviewer') { return 'wrong_creation_order' }
    if (-not $Pair.reviewerStartedFirst -or -not $Pair.implementerWaitingForFinding) { return 'wrong_initial_dispatch' }
    if (-not $Pair.reuseForCorrections -or -not $Pair.noPerFindingChat) { return 'wrong_correction_lifecycle' }
    'ready'
}

function Get-ReviewCoverage {
    param([hashtable] $Request)
    @($Request.coverage)
}

function Route-ReviewFinding {
    param([string] $ReviewedHead)
    [ordered]@{
        destination = 'fresh-epic-fix-implementer'
        correctionBranch = 'codex/integration-fix-run1'
        reviewedHead = $ReviewedHead
        isolated = $true
        rereviewProfile = 'gpt-6.1-sol/high'
        sameFreshPair = $true
        priorApprovalSuperseded = $true
    }
}

$ready = New-ReviewRequest
$pair = New-EpicReviewPair
Assert-True ((Test-ReviewRequest $ready) -eq 'ready') 'complete merged story set at current HEAD should be reviewable'
Assert-True ($ready.reviewerModel -eq 'gpt-6.1-sol' -and $ready.reviewerEffort -eq 'high') 'final review must use Sol 6.1 high'
Assert-True ((Get-ReviewCoverage $ready).Count -eq 5) 'review must cover integrated behavior and regressions'
Assert-True ((Test-EpicReviewPair $pair) -eq 'ready') 'epic review must create a fresh coordinator-owned worker pair'
Assert-True ($pair.implementerModel -eq 'gpt-5.6-luna' -and $pair.implementerEffort -eq 'xhigh') 'epic-fix implementer must use Luna 5.6 xhigh'
Assert-True ($pair.reviewerModel -eq 'gpt-6.1-sol' -and $pair.reviewerEffort -eq 'high') 'epic reviewer must use Sol 6.1 high'
Assert-True ($pair.freshFromStoryPair -and $pair.reviewerStartedFirst -and $pair.implementerWaitingForFinding) 'reviewer starts while fresh implementer waits for a finding'

$stale = New-ReviewRequest -RequestedHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-ReviewRequest $stale) -eq 'stale_feature_head') 'changed feature HEAD must require fresh final review'

$notMerged = New-ReviewRequest -AllMerged $false
Assert-True ((Test-ReviewRequest $notMerged) -eq 'stories_not_integrated') 'unmerged story PRs must block final epic review'

$wrongProfile = New-ReviewRequest
$wrongProfile.reviewerEffort = 'medium'
Assert-True ((Test-ReviewRequest $wrongProfile) -eq 'wrong_reviewer_profile') 'medium review must not substitute for final high review'

$finding = Route-ReviewFinding $ready.currentHead
Assert-True ($finding.destination -eq 'fresh-epic-fix-implementer' -and $finding.isolated -and $finding.correctionBranch -like 'codex/integration-fix-*') 'findings must route to the fresh implementer on an isolated integration correction branch'
Assert-True ($finding.rereviewProfile -eq 'gpt-6.1-sol/high' -and $finding.sameFreshPair -and $finding.priorApprovalSuperseded) 'corrections must reuse the fresh pair for exact-head high re-review'

Write-Output 'Passed offline final epic review fixture: fresh coordinator-created Luna 5.6 xhigh/Sol 6.1 high pair, reviewer-first dispatch, ordered merged-story scope, integrated coverage, stale-head guard, isolated correction routing, pair reuse, and exact-head re-review.'
