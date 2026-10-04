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
        [string] $Repository = 'TaigaMCP',
        [string] $StoryBranch = 'codex/story-50-run1',
        [string] $FeatureBranch = 'codex/feature-taiga-mcp-run1',
        [string] $ApprovedHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [string] $BranchHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        [bool] $Clean = $true,
        [bool] $ChecksPassed = $true,
        [string] $ChecksHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    )
    [ordered]@{
        repository = $Repository
        storyBranch = $StoryBranch
        featureBranch = $FeatureBranch
        approvedHead = $ApprovedHead
        branchHead = $BranchHead
        clean = $Clean
        checksPassed = $ChecksPassed
        checksHead = $ChecksHead
    }
}

function Test-DeliveryPreflight {
    param([hashtable] $Receipt)
    if (-not $Receipt.clean) { return 'dirty_story_branch' }
    if ($Receipt.approvedHead -ne $Receipt.branchHead) { return 'stale_review' }
    if (-not $Receipt.checksPassed) { return 'failed_checks' }
    if ($Receipt.checksHead -ne $Receipt.branchHead) { return 'stale_checks' }
    if ([string]::IsNullOrWhiteSpace($Receipt.featureBranch)) { return 'missing_feature_base' }
    'ready'
}

function New-PrBody {
    param(
        [string] $StoryRef,
        [string] $FeatureBranch,
        [string] $Head,
        [string[]] $Checks
    )
    @(
        '## Problem'
        "Deliver story #$StoryRef into the integration feature branch."
        ''
        '## Changes'
        'Reviewed story implementation.'
        ''
        '## Validation'
        $Checks
        ''
        '## Review'
        "- Reviewed HEAD: ``$Head``"
        '- Review profile: ``gpt-6.1-sol/medium``'
        '- Review state: accepted for PR delivery; merge still requires user approval'
        ''
        '## Scope'
        "- Story: #$StoryRef"
        "- Base: ``$FeatureBranch``"
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
        $_.base -eq $Receipt.featureBranch -and
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
            base = $Receipt.featureBranch
            head = $Receipt.branchHead
        }
    }
}

function New-StoryLink {
    param([psobject] $Pr, [hashtable] $Receipt, [string[]] $Checks)
    "Task-independent story delivery | state: pr_ready_for_approval | PR: $($Pr.url) | base: $($Receipt.featureBranch) | head: $($Receipt.branchHead) | checks: $($Checks -join '; ')"
}

$valid = New-DeliveryReceipt
Assert-True ((Test-DeliveryPreflight $valid) -eq 'ready') 'matching clean approved HEAD should be deliverable'

$stale = New-DeliveryReceipt -BranchHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-DeliveryPreflight $stale) -eq 'stale_review') 'changed branch HEAD must invalidate review approval'

$dirty = New-DeliveryReceipt -Clean $false
Assert-True ((Test-DeliveryPreflight $dirty) -eq 'dirty_story_branch') 'dirty story branch must block delivery'

$oldChecks = New-DeliveryReceipt -ChecksHead 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
Assert-True ((Test-DeliveryPreflight $oldChecks) -eq 'stale_checks') 'checks for another HEAD must block delivery'

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

$body = New-PrBody '50' $valid.featureBranch $valid.branchHead @('- `dotnet test` — exit 0; passed', '- `validate-pr-delivery.ps1` — exit 0; passed')
foreach ($marker in @('## Problem', '## Changes', '## Validation', '## Review', '## Scope', $valid.featureBranch, $valid.branchHead)) {
    Assert-True $body.Contains($marker) "PR body must include $marker"
}

$link = New-StoryLink $created.pr $valid @('dotnet test: exit 0', 'contract fixture: exit 0')
foreach ($marker in @('pr_ready_for_approval', $created.pr.url, $valid.featureBranch, $valid.branchHead, 'exit 0')) {
    Assert-True $link.Contains($marker) "story link must include $marker"
}

$wrongBase = New-DeliveryReceipt -FeatureBranch ''
Assert-True ((Test-DeliveryPreflight $wrongBase) -eq 'missing_feature_base') 'missing feature base must block delivery'

Write-Output 'Passed offline PR delivery fixture: exact-head preflight, stale/dirty/check guards, PR branch/state reuse guards, unknown-state reconciliation, PR create identity, review evidence, and Taiga link evidence.'
