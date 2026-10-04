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

function Get-ReviewCoverage {
    param([hashtable] $Request)
    @($Request.coverage)
}

function Route-ReviewFinding {
    param([string] $ReviewedHead)
    [ordered]@{
        destination = 'integration-implementer'
        correctionBranch = 'codex/integration-fix-run1'
        reviewedHead = $ReviewedHead
        isolated = $true
        rereviewProfile = 'gpt-6.1-sol/high'
        priorApprovalSuperseded = $true
    }
}

$ready = New-ReviewRequest
Assert-True ((Test-ReviewRequest $ready) -eq 'ready') 'complete merged story set at current HEAD should be reviewable'
Assert-True ($ready.reviewerModel -eq 'gpt-6.1-sol' -and $ready.reviewerEffort -eq 'high') 'final review must use Sol 6.1 high'
Assert-True ((Get-ReviewCoverage $ready).Count -eq 5) 'review must cover integrated behavior and regressions'

$stale = New-ReviewRequest -RequestedHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-ReviewRequest $stale) -eq 'stale_feature_head') 'changed feature HEAD must require fresh final review'

$notMerged = New-ReviewRequest -AllMerged $false
Assert-True ((Test-ReviewRequest $notMerged) -eq 'stories_not_integrated') 'unmerged story PRs must block final epic review'

$wrongProfile = New-ReviewRequest
$wrongProfile.reviewerEffort = 'medium'
Assert-True ((Test-ReviewRequest $wrongProfile) -eq 'wrong_reviewer_profile') 'medium review must not substitute for final high review'

$finding = Route-ReviewFinding $ready.currentHead
Assert-True ($finding.destination -eq 'integration-implementer' -and $finding.isolated -and $finding.correctionBranch -like 'codex/integration-fix-*') 'findings must route to an isolated integration correction branch'
Assert-True ($finding.rereviewProfile -eq 'gpt-6.1-sol/high' -and $finding.priorApprovalSuperseded) 'corrections must receive a fresh high re-review'

Write-Output 'Passed offline final epic review fixture: Sol 6.1 high profile, ordered merged-story scope, integrated coverage, stale-head guard, correction routing, and exact-head re-review.'
