# OFFLINE PR DELIVERY CONTRACT CHECK.
# This fixture models coordinator decisions with synthetic Git/provider records.
# It never pushes, creates a PR, attaches an artifact, or writes to Taiga.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "PR delivery assertion failed: $Message" }
}

function New-DeliveryReceipt {
    param(
        [ValidateSet('standalone','legacy-standalone-feature','epic')] [string] $RunKind = 'epic',
        [string] $Repository = 'TaigaMCP',
        [string] $StoryBranch = 'codex/story-50-run1',
        [string] $ExpectedBranch = 'codex/story-50-run1',
        [string] $ExpectedWorktree = 'C:\\Temp\\story-50-run1',
        [string] $FeatureBranch = 'codex/feature-taiga-mcp-run1',
        [string] $PrBase = 'codex/feature-taiga-mcp-run1',
        [string] $ReviewBaseSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        [string] $ApprovedHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $BranchHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $DiffRange = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [ValidateSet('clean-tracked-source','dirty-tracked-source')]
        [string] $SourceState = 'clean-tracked-source',
        [bool] $IgnoredOutputsDeclared = $true,
        [bool] $Clean = $true,
        [bool] $ChecksPassed = $true,
        [string] $ChecksHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [bool] $FinalStoryReviewAccepted = $true,
        [string] $FinalStoryReviewHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    )
    [ordered]@{
        runKind = $RunKind
        repository = $Repository
        storyBranch = $StoryBranch
        expectedBranch = $ExpectedBranch
        expectedWorktree = $ExpectedWorktree
        featureBranch = $FeatureBranch
        prBase = $PrBase
        reviewBaseSha = $ReviewBaseSha
        approvedHead = $ApprovedHead
        branchHead = $BranchHead
        diffRange = $DiffRange
        sourceState = $SourceState
        ignoredOutputsDeclared = $IgnoredOutputsDeclared
        clean = $Clean
        checksPassed = $ChecksPassed
        checksHead = $ChecksHead
        finalStoryReviewAccepted = $FinalStoryReviewAccepted
        finalStoryReviewHead = $FinalStoryReviewHead
    }
}

function Test-DeliveryPreflight {
    param([hashtable] $Receipt)
    if ($Receipt.storyBranch -ne $Receipt.expectedBranch) { return 'unexpected_story_branch' }
    if ([string]::IsNullOrWhiteSpace($Receipt.expectedWorktree)) { return 'missing_story_worktree' }
    if ($Receipt.reviewBaseSha -notmatch '^[0-9a-f]{40}$') { return 'invalid_review_base' }
    if ($Receipt.branchHead -notmatch '^[0-9a-f]{40}$') { return 'invalid_review_head' }
    if ($Receipt.diffRange -ne "$($Receipt.reviewBaseSha)..$($Receipt.branchHead)") { return 'stale_review_range' }
    if ($Receipt.sourceState -ne 'clean-tracked-source') { return 'dirty_tracked_source' }
    if (-not $Receipt.ignoredOutputsDeclared) { return 'ignored_output_state_unknown' }
    if (-not $Receipt.clean) { return 'dirty_story_branch' }
    if ($Receipt.approvedHead -ne $Receipt.branchHead) { return 'stale_review' }
    if (-not $Receipt.checksPassed) { return 'failed_checks' }
    if ($Receipt.checksHead -ne $Receipt.branchHead) { return 'stale_checks' }
    if (-not $Receipt.finalStoryReviewAccepted) { return 'final_story_review_required' }
    if ($Receipt.finalStoryReviewHead -ne $Receipt.branchHead) { return 'stale_final_story_review' }
    if ($Receipt.runKind -eq 'standalone') {
        if (-not [string]::IsNullOrWhiteSpace($Receipt.featureBranch)) { return 'unexpected_feature_base' }
        if ($Receipt.prBase -ne 'master') { return 'wrong_standalone_base' }
    }
    elseif ([string]::IsNullOrWhiteSpace($Receipt.featureBranch) -or
        $Receipt.prBase -ne $Receipt.featureBranch) {
        return 'missing_feature_base'
    }
    'ready'
}

function New-PrBody {
    param(
        [string] $StoryRef,
        [string] $PrBase,
        [string] $Head,
        [string[]] $Checks,
        [hashtable] $Receipt
    )
    @(
        '## Problem'
        "Deliver story #$StoryRef through the $PrBase branch topology."
        ''
        '## Changes'
        'Reviewed story implementation.'
        ''
        '## Validation'
        $Checks
        ''
        '## Review'
        "- Reviewed HEAD: ``$Head``"
        "- Review input: repository ``$($Receipt.repository)`` | worktree ``$($Receipt.expectedWorktree)`` | branch ``$($Receipt.expectedBranch)``"
        "- Base/diff: ``$($Receipt.reviewBaseSha)`` | ``$($Receipt.diffRange)`` | paths ``<relevant changed paths>``"
        "- Source state: ``$($Receipt.sourceState)``; ignored verification outputs: ``declared``"
        '- Review profile: ``gpt-6.1-sol/medium``'
        "- Final story review: exact current story HEAD accepted; independent verification and inspected worker evidence recorded"
        '- Review state: accepted for PR delivery; merge still requires user approval'
        ''
        '## Scope'
        "- Story: #$StoryRef"
        "- Base: ``$PrBase``"
        "- Head: ``$Head``"
    ) -join "`n"
}

function Resolve-Pr {
    param(
        [object[]] $Existing,
        [hashtable] $Receipt,
        [string] $PrUrl = 'https://example.invalid/pr/50'
    )
    $identityMatches = @($Existing | Where-Object {
        $_.PSObject.Properties['repository'] -and
        $_.PSObject.Properties['headBranch'] -and
        $_.PSObject.Properties['base'] -and
        $_.PSObject.Properties['head'] -and
        $_.repository -eq $Receipt.repository -and
        $_.headBranch -eq $Receipt.storyBranch -and
        $_.base -eq $Receipt.prBase -and
        $_.head -eq $Receipt.branchHead
    })

    $unknownState = @($identityMatches | Where-Object {
        -not $_.PSObject.Properties['state'] -or
        -not $_.PSObject.Properties['isClosed'] -or
        $null -eq $_.state -or
        $null -eq $_.isClosed
    })
    if ($unknownState.Count -gt 0) {
        $candidate = if ($unknownState.Count -eq 1) { $unknownState[0] } else { $null }
        return [ordered]@{ state = 'reconcile'; reason = 'provider_state_unknown'; pr = $candidate }
    }

    $matches = @($identityMatches | Where-Object {
        $_.state -eq 'open' -and
        $_.isClosed -eq $false
    })
    if ($matches.Count -gt 1) { return [ordered]@{ state = 'ambiguous'; pr = $null } }
    if ($matches.Count -eq 1) { return [ordered]@{ state = 'reused'; pr = $matches[0] } }
    [ordered]@{
        state = 'create'
        pr = [pscustomobject]@{
            url = $PrUrl
            repository = $Receipt.repository
            base = $Receipt.prBase
            head = $Receipt.branchHead
        }
    }
}

function New-StoryLink {
    param([psobject] $Pr, [hashtable] $Receipt, [string[]] $Checks)
    "Task-independent story delivery | state: pr_ready_for_approval | PR: $($Pr.url) | base: $($Receipt.prBase) | head: $($Receipt.branchHead) | checks: $($Checks -join '; ')"
}

$valid = New-DeliveryReceipt
Assert-True ((Test-DeliveryPreflight $valid) -eq 'ready') 'matching clean approved HEAD should be deliverable'

$wrongExpectedBranch = New-DeliveryReceipt -ExpectedBranch 'codex/other-story'
Assert-True ((Test-DeliveryPreflight $wrongExpectedBranch) -eq 'unexpected_story_branch') 'unexpected story branch must block delivery'

$missingWorktree = New-DeliveryReceipt -ExpectedWorktree ''
Assert-True ((Test-DeliveryPreflight $missingWorktree) -eq 'missing_story_worktree') 'missing story worktree must block delivery'

$staleRange = New-DeliveryReceipt -DiffRange 'cccccccccccccccccccccccccccccccccccccccc..aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
Assert-True ((Test-DeliveryPreflight $staleRange) -eq 'stale_review_range') 'stale review diff range must block delivery'

$dirtySource = New-DeliveryReceipt -SourceState 'dirty-tracked-source'
Assert-True ((Test-DeliveryPreflight $dirtySource) -eq 'dirty_tracked_source') 'dirty tracked source must block delivery'

$standalone = New-DeliveryReceipt -RunKind standalone -FeatureBranch '' -PrBase 'master'
Assert-True ((Test-DeliveryPreflight $standalone) -eq 'ready') 'standalone story should deliver directly to master without a feature branch'

$legacy = New-DeliveryReceipt -RunKind legacy-standalone-feature
Assert-True ((Test-DeliveryPreflight $legacy) -eq 'ready') 'legacy standalone resume should preserve its recorded feature PR base'

$stale = New-DeliveryReceipt -BranchHead 'cccccccccccccccccccccccccccccccccccccccc' -DiffRange 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..cccccccccccccccccccccccccccccccccccccccc'
Assert-True ((Test-DeliveryPreflight $stale) -eq 'stale_review') 'changed branch HEAD must invalidate review approval'

$dirty = New-DeliveryReceipt -Clean $false
Assert-True ((Test-DeliveryPreflight $dirty) -eq 'dirty_story_branch') 'dirty story branch must block delivery'

$oldChecks = New-DeliveryReceipt -ChecksHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-DeliveryPreflight $oldChecks) -eq 'stale_checks') 'checks for another HEAD must block delivery'

$taskAcceptanceOnly = New-DeliveryReceipt -FinalStoryReviewAccepted $false
Assert-True ((Test-DeliveryPreflight $taskAcceptanceOnly) -eq 'final_story_review_required') 'task acceptance alone must not release story PR delivery'

$staleFinalStoryReview = New-DeliveryReceipt -FinalStoryReviewHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-DeliveryPreflight $staleFinalStoryReview) -eq 'stale_final_story_review') 'final story approval for another HEAD must block delivery'

$existing = [pscustomobject]@{
    url = 'https://example.invalid/pr/existing'
    repository = 'TaigaMCP'
    headBranch = 'codex/story-50-run1'
    base = 'codex/feature-taiga-mcp-run1'
    head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    state = 'open'
    isClosed = $false
}
$reused = Resolve-Pr @($existing) $valid
Assert-True ($reused.state -eq 'reused' -and $reused.pr.url -eq $existing.url) 'matching PR must be reused'

$wrongBranch = [pscustomobject]@{
    url = 'https://example.invalid/pr/wrong-branch'
    repository = 'TaigaMCP'
    headBranch = 'codex/other-story'
    base = 'codex/feature-taiga-mcp-run1'
    head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    state = 'open'
    isClosed = $false
}
$wrongBranchResult = Resolve-Pr @($wrongBranch) $valid 'https://example.invalid/pr/new-branch'
Assert-True ($wrongBranchResult.state -eq 'create') 'PR from another head branch must not be reused'

$closed = [pscustomobject]@{
    url = 'https://example.invalid/pr/closed'
    repository = 'TaigaMCP'
    headBranch = 'codex/story-50-run1'
    base = 'codex/feature-taiga-mcp-run1'
    head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    state = 'closed'
    isClosed = $true
}
$closedResult = Resolve-Pr @($closed) $valid 'https://example.invalid/pr/new-closed'
Assert-True ($closedResult.state -eq 'create') 'closed or unmerged PR must not be reused'

$unknownState = [pscustomobject]@{
    url = 'https://example.invalid/pr/unknown-state'
    repository = 'TaigaMCP'
    headBranch = 'codex/story-50-run1'
    base = 'codex/feature-taiga-mcp-run1'
    head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    state = $null
    isClosed = $null
}
$unknownStateResult = Resolve-Pr @($unknownState) $valid 'https://example.invalid/pr/should-not-create'
Assert-True ($unknownStateResult.state -eq 'reconcile' -and $unknownStateResult.reason -eq 'provider_state_unknown' -and $unknownStateResult.pr.url -eq $unknownState.url) 'matching PR with unknown provider state must reconcile instead of creating a duplicate'

$created = Resolve-Pr @() $valid 'https://example.invalid/pr/new'
Assert-True ($created.state -eq 'create' -and $created.pr.base -eq $valid.featureBranch -and $created.pr.head -eq $valid.branchHead) 'new PR must target exact feature base and reviewed HEAD'

$standalonePr = Resolve-Pr @() $standalone 'https://example.invalid/pr/standalone'
Assert-True ($standalonePr.state -eq 'create' -and $standalonePr.pr.base -eq 'master' -and $standalonePr.pr.head -eq $standalone.branchHead) 'standalone PR must target master and the reviewed HEAD'

$legacyPr = Resolve-Pr @() $legacy 'https://example.invalid/pr/legacy'
Assert-True ($legacyPr.state -eq 'create' -and $legacyPr.pr.base -eq $legacy.featureBranch -and $legacyPr.pr.head -eq $legacy.branchHead) 'legacy standalone PR must target the preserved feature branch and reviewed HEAD'

$body = New-PrBody '50' $valid.prBase $valid.branchHead @('- `dotnet test` — exit 0; passed', '- `validate-pr-delivery.ps1` — exit 0; passed') $valid
foreach ($marker in @('## Problem', '## Changes', '## Validation', '## Review', '## Scope', $valid.featureBranch, $valid.branchHead, 'Final story review', 'independent verification', 'inspected worker evidence')) {
    Assert-True $body.Contains($marker) "PR body must include $marker"
}
foreach ($marker in @($valid.expectedWorktree, $valid.expectedBranch, $valid.reviewBaseSha, $valid.diffRange, 'clean-tracked-source', 'ignored verification outputs')) {
    Assert-True $body.Contains($marker) "PR body must include review-input marker $marker"
}

$link = New-StoryLink $created.pr $valid @('dotnet test: exit 0', 'contract fixture: exit 0')
foreach ($marker in @('pr_ready_for_approval', $created.pr.url, $valid.featureBranch, $valid.branchHead, 'exit 0')) {
    Assert-True $link.Contains($marker) "story link must include $marker"
}

$wrongBase = New-DeliveryReceipt -FeatureBranch '' -PrBase 'master'
Assert-True ((Test-DeliveryPreflight $wrongBase) -eq 'missing_feature_base') 'missing feature base must block delivery'

$standaloneWrongBase = New-DeliveryReceipt -RunKind standalone -FeatureBranch '' -PrBase 'codex/feature-taiga-mcp-run1'
Assert-True ((Test-DeliveryPreflight $standaloneWrongBase) -eq 'wrong_standalone_base') 'standalone story must not target a feature branch'

$legacyWrongBase = New-DeliveryReceipt -RunKind legacy-standalone-feature -PrBase 'master'
Assert-True ((Test-DeliveryPreflight $legacyWrongBase) -eq 'missing_feature_base') 'legacy standalone resume must not be converted to a direct master story PR'

Write-Output 'Passed offline PR delivery fixture: standalone direct-master, legacy preserved-feature, and epic feature-base topologies, exact-head preflight, stale/dirty/check guards, PR branch/state reuse guards, unknown-state reconciliation, PR create identity, review evidence, and Taiga link evidence.'
