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
        [string] $CurrentScope = ''
    )
    if ([string]::IsNullOrEmpty($CurrentPrUrl)) { $CurrentPrUrl = $PrUrl }
    if ([string]::IsNullOrEmpty($CurrentRepository)) { $CurrentRepository = $Repository }
    if ([string]::IsNullOrEmpty($CurrentBase)) { $CurrentBase = $Base }
    if ([string]::IsNullOrEmpty($CurrentScope)) { $CurrentScope = $Scope }
    [ordered]@{
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
        promptCount = 1
        workerDispatchCount = 0
    }
}

function New-MergePrompt {
    param([hashtable] $Gate)
    "Story #50 PR ready: $($Gate.prUrl)`nRepository: $($Gate.repository)`nScope: $($Gate.scope)`nBase: $($Gate.base)`nHead: $($Gate.reviewedHead)`n`nYes - merge and continue to the next ordered story`nNo - hold for feedback`n`nMerge this exact PR and continue? Reply Yes or No."
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
    [ordered]@{ state = 'merged_verified'; merge = $true; advance = $true; dispatch = 1 }
}

function Route-RequestedChanges {
    param([string] $CurrentPair = 'implementer-50/reviewer-50')
    [ordered]@{ destination = $CurrentPair; freshReviewRequired = $true; newPromptRequired = $true; newWorker = $false }
}

$prompt = New-MergePrompt (New-Gate)
foreach ($marker in @('Yes - merge and continue', 'No - hold for feedback', 'https://example.invalid/pr/50', 'Repository: TaigaMCP', 'Scope: story-50', 'Reply Yes or No')) {
    Assert-True $prompt.Contains($marker) "prompt must include $marker"
}

$no = Resolve-Decision (New-Gate -Reply 'No')
Assert-True ($no.state -eq 'hold_feedback' -and -not $no.merge -and -not $no.advance -and $no.dispatch -eq 0) 'No must hold without dispatch'

$silent = Resolve-Decision (New-Gate)
Assert-True ($silent.state -eq 'wait_for_user' -and -not $silent.merge -and -not $silent.advance -and $silent.dispatch -eq 0) 'missing response must not authorize merge'

$yesMerged = Resolve-Decision (New-Gate -Reply 'Yes' -MergeResult 'merged')
Assert-True ($yesMerged.state -eq 'merged_verified' -and $yesMerged.merge -and $yesMerged.advance -and $yesMerged.dispatch -eq 1) 'explicit Yes plus verified merge must advance'

$yesFailed = Resolve-Decision (New-Gate -Reply 'Yes' -MergeResult 'failed')
Assert-True ($yesFailed.state -eq 'merge_unverified' -and -not $yesFailed.advance -and $yesFailed.dispatch -eq 0) 'failed merge must hold the current story'

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

Write-Output 'Passed offline merge-gate fixture: exact PR identity prompt, Yes/No/no-response handling, stale identity or HEAD approval, failed merge hold, verified advancement, correction routing, and quiet recovery.'
