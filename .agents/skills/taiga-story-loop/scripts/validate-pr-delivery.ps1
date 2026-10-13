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
        [string] $PrUrl = 'https://github.com/blakeg83/taiga-mcp/pull/157'
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
    number = 157
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

function New-PerformanceEvent {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [ValidateSet('per_task','story_end_only')] [string] $ReviewMode = 'per_task',
        [ValidateSet('story','task','final_story')] [string] $Scope = 'story',
        [AllowNull()] [object] $TaskRef = $null,
        [AllowNull()] [object] $PhaseId = $null,
        [ValidateSet('coordinator','implementer','reviewer')] [string] $Role = 'coordinator',
        [AllowNull()] [object] $SessionId = 'synthetic-coordinator-session',
        [AllowNull()] [object] $WorkerId = 'synthetic-coordinator',
        [AllowNull()] [object] $ReviewRequestId = $null,
        [AllowNull()] [object] $ReviewAttemptId = $null,
        [AllowNull()] [object] $ReviewKind = $null,
        [AllowNull()] [object] $ReviewAttemptOrdinal = $null,
        [AllowNull()] [object] $Revision = $null,
        [AllowNull()] [object] $PullRequest = $null
    )

    [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event'
        eventId = $EventId
        runId = $RunId
        projectId = 12
        storyId = 728
        storyRef = 144
        taskRef = $TaskRef
        role = $Role
        sessionId = $SessionId
        workerId = $WorkerId
        transitionId = $EventId
        scope = $Scope
        phaseId = $PhaseId
        correctionId = $null
        reviewRequestId = $ReviewRequestId
        reviewAttemptId = $ReviewAttemptId
        reviewKind = $ReviewKind
        reviewAttemptOrdinal = $ReviewAttemptOrdinal
        supersedesReviewAttemptId = $null
        eventType = $EventType
        occurredAtUtc = $OccurredAtUtc
        revision = $Revision
        reviewMode = $ReviewMode
        provenance = [ordered]@{
            source = 'synthetic_fixture'
            observedBy = 'validate-pr-delivery'
            coverage = 'fixed UTC delivery fixture'
            synthetic = $true
        }
        usage = $null
        waitId = $null
        waitKind = $null
        pullRequest = $PullRequest
    }
}

function Invoke-PerformanceRecorder {
    param(
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $ExternalRunRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object] $Event
    )

    $eventJson = $Event | ConvertTo-Json -Compress -Depth 30
    & pwsh -NoProfile -File $RecorderPath -ExternalRunRoot $ExternalRunRoot -RunId $RunId -EventJson $eventJson *> $null
    return ($LASTEXITCODE -eq 0)
}

function Append-PerformanceEvents {
    param(
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $ExternalRunRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object[]] $Events
    )

    foreach ($event in $Events) {
        Assert-True (Invoke-PerformanceRecorder -RecorderPath $RecorderPath -ExternalRunRoot $ExternalRunRoot -RunId $RunId -Event $event) "synthetic lifecycle event must reach the recorder: $($event.eventId)"
    }
}

function New-SyntheticTaskReviewEvents {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [int] $TaskRef,
        [Parameter(Mandatory)] [string] $ReviewedHead,
        [Parameter(Mandatory)] [string] $StartUtc,
        [Parameter(Mandatory)] [string] $EndUtc
    )

    $phaseId = "task-$TaskRef-review"
    $requestId = "task-$TaskRef-request-1"
    $attemptId = "task-$TaskRef-attempt-1"
    @(
        (New-PerformanceEvent -RunId $RunId -EventId "$attemptId-start" -EventType 'review_started' -OccurredAtUtc $StartUtc -Scope task -TaskRef $TaskRef -PhaseId $phaseId -Role reviewer -SessionId 'synthetic-reviewer-session' -WorkerId 'synthetic-reviewer' -ReviewRequestId $requestId -ReviewAttemptId $attemptId -ReviewKind initial_task -ReviewAttemptOrdinal 1 -Revision $ReviewedHead),
        (New-PerformanceEvent -RunId $RunId -EventId "$attemptId-accepted" -EventType 'review_accepted' -OccurredAtUtc $EndUtc -Scope task -TaskRef $TaskRef -PhaseId $phaseId -Role reviewer -SessionId 'synthetic-reviewer-session' -WorkerId 'synthetic-reviewer' -ReviewRequestId $requestId -ReviewAttemptId $attemptId -ReviewKind initial_task -ReviewAttemptOrdinal 1 -Revision $ReviewedHead)
    )
}

function New-SyntheticSetupMetadata {
    param([Parameter(Mandatory)] [string] $RunId)

    [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_setup'
        runId = $RunId
        projectId = 12
        storyId = 728
        profiles = @(
            [ordered]@{
                role = 'coordinator'; workerId = 'synthetic-coordinator'; sessionId = 'synthetic-coordinator-session'; model = 'gpt-6.1-sol'; effort = 'medium'; effectiveFromUtc = '2026-10-10T02:59:00Z'; effectiveToUtc = $null; changeId = 'coordinator-profile'
                provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'validate-pr-delivery'; coverage = 'complete synthetic assignment interval'; synthetic = $true }
            }
            [ordered]@{
                role = 'implementer'; workerId = 'synthetic-implementer'; sessionId = 'synthetic-implementer-session'; model = 'gpt-5.6-sol'; effort = 'high'; effectiveFromUtc = '2026-10-10T02:59:00Z'; effectiveToUtc = $null; changeId = 'implementer-profile'
                provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'validate-pr-delivery'; coverage = 'complete synthetic assignment interval'; synthetic = $true }
            }
            [ordered]@{
                role = 'reviewer'; workerId = 'synthetic-reviewer'; sessionId = 'synthetic-reviewer-session'; model = 'gpt-6.1-sol'; effort = 'high'; effectiveFromUtc = '2026-10-10T02:59:00Z'; effectiveToUtc = $null; changeId = 'reviewer-profile'
                provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'validate-pr-delivery'; coverage = 'complete synthetic assignment interval'; synthetic = $true }
            }
        )
        provenance = [ordered]@{ source = 'setup_assignment'; observedBy = 'validate-pr-delivery'; coverage = 'complete synthetic setup fixture'; synthetic = $true }
    }
}

function New-SyntheticPerformanceRun {
    param(
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $ExternalRunRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [ValidateSet('per_task','story_end_only')] [string] $ReviewMode = 'per_task'
    )

    [IO.Directory]::CreateDirectory($ExternalRunRoot) | Out-Null
    $storyStarted = New-PerformanceEvent -RunId $RunId -EventId "$RunId/story-started" -EventType 'story_started' -OccurredAtUtc $OccurredAtUtc -ReviewMode $ReviewMode
    Assert-True (Invoke-PerformanceRecorder -RecorderPath $RecorderPath -ExternalRunRoot $ExternalRunRoot -RunId $RunId -Event $storyStarted) 'synthetic story_started must reach the recorder'
    Join-Path (Join-Path $ExternalRunRoot $RunId) 'events.jsonl'
}

function Invoke-ReportFinalization {
    param(
        [Parameter(Mandatory)] [hashtable] $Delivery,
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $AggregatorPath,
        [Parameter(Mandatory)] [string] $ExternalRunRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $ArtifactRoot,
        [Parameter(Mandatory)] [string] $BaseRevision,
        [Parameter(Mandatory)] [string] $RepositoryPath,
        [ValidateSet('per_task','story_end_only')] [string] $ReviewMode = 'per_task',
        [string] $OccurredAtUtc = '2026-10-10T02:00:00Z',
        [AllowEmptyCollection()] [int[]] $TaskRefs = @(),
        [string] $MetadataPath,
        [string] $ObservedEvidencePath,
        [string] $TaskOutcomePath,
        [string] $CollectorPath
    )

    $PSBoundParameters['OccurredAtUtc'] = $OccurredAtUtc
    $entry = Join-Path $PSScriptRoot '../../../../scripts/finalize-story-performance.ps1'
    (& $entry @PSBoundParameters) | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String
}

function New-ConfirmedDelivery {
    param(
        [Parameter(Mandatory)] [hashtable] $Receipt,
        [Parameter(Mandatory)] [hashtable] $Resolution,
        [Parameter(Mandatory)] [string] $ReviewedHead
    )

    Assert-True ($Resolution.state -in @('create', 'reused')) "provider resolution must be create or reused before confirmation: $($Resolution.state)"
    $providerPr = [pscustomobject]@{
        url = 'https://github.com/blakeg83/taiga-mcp/pull/157'
        number = if ($Resolution.pr.PSObject.Properties['number']) { [int]$Resolution.pr.number } else { 157 }
        repository = [string]$Receipt.repository
        headBranch = [string]$Receipt.storyBranch
        base = [string]$Receipt.prBase
        head = $ReviewedHead
        state = 'open'
        isClosed = $false
    }
    [ordered]@{
        state = if ($Resolution.state -eq 'reused') { 'reused' } else { 'created' }
        providerConfirmed = $true
        pr = $providerPr
        reviewedHead = $ReviewedHead
        prBase = [string]$Receipt.prBase
        repository = [string]$Receipt.repository
        storyBranch = [string]$Receipt.storyBranch
        receipt = $Receipt
    }
}

function New-DeliveryVariant {
    param(
        [Parameter(Mandatory)] [hashtable] $BaseDelivery,
        [string] $Repository = 'TaigaMCP',
        [string] $HeadBranch = 'codex/story-50-run1',
        [string] $Head = ('a' * 40),
        [string] $ProviderBase = 'codex/feature-taiga-mcp-run1',
        [string] $DeliveryRepository = 'TaigaMCP',
        [string] $DeliveryStoryBranch = 'codex/story-50-run1',
        [string] $DeliveryPrBase = 'codex/feature-taiga-mcp-run1',
        [AllowNull()] [object] $ProviderState = 'open',
        [AllowNull()] [object] $IsClosed = $false,
        [string] $ReviewedHead = ('a' * 40),
        [string] $State = 'reused',
        [bool] $ProviderConfirmed = $true
    )

    [ordered]@{
        state = $State
        providerConfirmed = $ProviderConfirmed
        pr = [pscustomobject]@{
            url = [string]$BaseDelivery.pr.url
            number = [int]$BaseDelivery.pr.number
            repository = $Repository
            headBranch = $HeadBranch
            base = $ProviderBase
            head = $Head
            state = $ProviderState
            isClosed = $IsClosed
        }
        reviewedHead = $ReviewedHead
        repository = $DeliveryRepository
        storyBranch = $DeliveryStoryBranch
        prBase = $DeliveryPrBase
        receipt = $BaseDelivery.receipt
    }
}

$reportFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-pr-report-finalization-' + [guid]::NewGuid().ToString('N'))
$reportRepositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$reportRecorderPath = Join-Path $PSScriptRoot 'write-performance-event.ps1'
$reportAggregatorPath = Join-Path $reportRepositoryPath 'scripts/get-story-performance.ps1'
$reportBase = 'b' * 40
$reportHeadA = 'a' * 40
$reportHeadB = 'c' * 40
$confirmedCreate = New-ConfirmedDelivery -Receipt $valid -Resolution $created -ReviewedHead $reportHeadA
$confirmedReuse = New-ConfirmedDelivery -Receipt $valid -Resolution $reused -ReviewedHead $reportHeadA

try {
    $runA = New-SyntheticPerformanceRun -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -OccurredAtUtc '2026-10-10T01:59:00Z'
    $artifactA = Join-Path $reportFixtureRoot 'artifacts-a'
    $createdReport = Invoke-ReportFinalization -Delivery $confirmedCreate -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -ArtifactRoot $artifactA -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($createdReport.deliveryState -eq 'confirmed' -and $createdReport.reportState -eq 'published' -and $createdReport.prReadyEvent) "confirmed PR creation must append pr_ready and publish a report: $($createdReport.response)"
    Assert-True ($createdReport.response.Contains('performance report:') -and $createdReport.response.Contains('JSON artifact:') -and (Test-Path -LiteralPath $createdReport.jsonPath -PathType Leaf)) 'normal confirmed response must include a concise report and JSON artifact reference'
    $createdJson = Get-Content -Raw -LiteralPath $createdReport.jsonPath | ConvertFrom-Json -Depth 100
    Assert-True ([string]$createdJson.reportId -eq $createdReport.reportId -and (Test-Path -LiteralPath $createdReport.manifestPath -PathType Leaf)) 'normal response artifact reference must bind the returned report identity and manifest'
    $createdJsonBytes = [IO.File]::ReadAllBytes($createdReport.jsonPath)

    $reusedReport = Invoke-ReportFinalization -Delivery $confirmedReuse -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -ArtifactRoot $artifactA -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($reusedReport.reportState -eq 'published' -and $reusedReport.reportId -eq $createdReport.reportId -and $reusedReport.jsonPath -eq $createdReport.jsonPath) 'duplicate confirmed PR reuse must reuse the same report identity and JSON artifact'
    $runALedgerLines = @(Get-Content -LiteralPath $runA)
    Assert-True ($runALedgerLines.Count -eq 2) 'duplicate confirmed PR observation must not append a second pr_ready event'

    $newHeadReceipt = New-DeliveryReceipt -ApprovedHead $reportHeadB -BranchHead $reportHeadB -ChecksHead $reportHeadB -FinalStoryReviewHead $reportHeadB -DiffRange "$reportBase..$reportHeadB"
    Assert-True ((Test-DeliveryPreflight $newHeadReceipt) -eq 'ready') 'new reviewed HEAD must pass the existing exact preflight before finalization'
    $existingNewHead = [pscustomobject]@{
        url = $confirmedCreate.pr.url
        number = 157
        repository = $newHeadReceipt.repository
        headBranch = $newHeadReceipt.storyBranch
        base = $newHeadReceipt.prBase
        head = $reportHeadB
        state = 'open'
        isClosed = $false
    }
    $newHeadResolution = Resolve-Pr @($existingNewHead) $newHeadReceipt
    Assert-True ($newHeadResolution.state -eq 'reused') 'provider resolution must reuse the exact PR after its branch advances to the newly reviewed HEAD'
    $confirmedNewHead = New-ConfirmedDelivery -Receipt $newHeadReceipt -Resolution $newHeadResolution -ReviewedHead $reportHeadB
    $newHeadReport = Invoke-ReportFinalization -Delivery $confirmedNewHead -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -ArtifactRoot $artifactA -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath -OccurredAtUtc '2026-10-10T02:09:00Z'
    Assert-True ($newHeadReport.reportState -eq 'published' -and $newHeadReport.reportId -ne $createdReport.reportId -and $newHeadReport.jsonPath -ne $createdReport.jsonPath) 'a newly confirmed reviewed HEAD must retain a new report sibling'
    $newHeadJson = Get-Content -Raw -LiteralPath $newHeadReport.jsonPath | ConvertFrom-Json -Depth 100
    Assert-True ([string]$newHeadJson.reportId -eq $newHeadReport.reportId -and [string]$newHeadJson.comparison.reviewedHead -eq $reportHeadB) 'new reviewed HEAD artifact must bind the selected report identity and revision'
    $duplicateNewHead = Invoke-ReportFinalization -Delivery $confirmedNewHead -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -ArtifactRoot $artifactA -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath -OccurredAtUtc '2026-10-10T02:09:00Z'
    Assert-True ($duplicateNewHead.reportState -eq 'published' -and $duplicateNewHead.reportId -eq $newHeadReport.reportId -and $duplicateNewHead.jsonPath -eq $newHeadReport.jsonPath) 'duplicate observation of the new reviewed HEAD must reuse its report sibling'
    $runAWithBothHeads = @(Get-Content -LiteralPath $runA)
    Assert-True ($runAWithBothHeads.Count -eq 3 -and (Test-Path -LiteralPath $createdReport.jsonPath -PathType Leaf) -and
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($createdReport.jsonPath)) -ceq [Convert]::ToBase64String($createdJsonBytes)) 'same-run changed HEAD sequence must preserve one story_started and one pr_ready per reviewed HEAD and retain immutable prior artifacts'

    $knownRunId = 'synthetic-pr-report-known-dataflow'
    $knownRun = New-SyntheticPerformanceRun -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId $knownRunId -OccurredAtUtc '2026-10-10T03:00:00Z'
    $knownTaskRefs = @(155, 156, 157)
    $knownTaskTimes = @(
        [ordered]@{ task = 155; start = '2026-10-10T03:05:00Z'; end = '2026-10-10T03:06:00Z' }
        [ordered]@{ task = 156; start = '2026-10-10T03:10:00Z'; end = '2026-10-10T03:11:00Z' }
        [ordered]@{ task = 157; start = '2026-10-10T03:15:00Z'; end = '2026-10-10T03:16:00Z' }
    )
    foreach ($taskTime in $knownTaskTimes) {
        $taskEvents = New-SyntheticTaskReviewEvents -RunId $knownRunId -TaskRef $taskTime.task -ReviewedHead $reportHeadA -StartUtc $taskTime.start -EndUtc $taskTime.end
        Append-PerformanceEvents -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId $knownRunId -Events $taskEvents
    }
    $knownMetadataPath = Join-Path $reportFixtureRoot 'synthetic-known-setup-metadata.json'
    $knownMetadata = New-SyntheticSetupMetadata -RunId $knownRunId
    [IO.File]::WriteAllText($knownMetadataPath, ($knownMetadata | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    $knownArtifactRoot = Join-Path $reportFixtureRoot 'known-artifacts'
    $knownReport = Invoke-ReportFinalization -Delivery $confirmedCreate -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId $knownRunId -ArtifactRoot $knownArtifactRoot -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath -OccurredAtUtc '2026-10-10T03:30:00Z' -TaskRefs $knownTaskRefs -MetadataPath $knownMetadataPath
    Assert-True ($knownReport.reportState -eq 'published') "complete-start/lifecycle/finalization fixture must publish through the actual aggregator (response: $($knownReport.response))"
    $knownJson = Get-Content -Raw -LiteralPath $knownReport.jsonPath | ConvertFrom-Json -Depth 100
    Assert-True ([string]$knownJson.metrics.modelsAndReasoning.state -eq 'measured' -and
        @($knownJson.metrics.modelsAndReasoning.value).Count -eq 3 -and
        [string]$knownJson.provenance.setupMetadata.state -eq 'measured' -and
        [string]$knownJson.coverage.taskSet.state -eq 'measured' -and
        @($knownJson.coverage.taskSet.declaredTaskRefs).Count -eq 3 -and
        [int]$knownJson.coverage.taskSet.declaredTaskRefs[0] -eq 155 -and
        [int]$knownJson.coverage.taskSet.declaredTaskRefs[2] -eq 157) "finalization must preserve validated setup profiles and the authorized ordered task set (profiles=$(@($knownJson.metrics.modelsAndReasoning.value).Count), profileState=$($knownJson.metrics.modelsAndReasoning.state), metadataState=$($knownJson.provenance.setupMetadata.state), taskState=$($knownJson.coverage.taskSet.state), taskRefs=$($knownJson.coverage.taskSet.declaredTaskRefs -join ','))"
    $missingMetadataArtifactRoot = Join-Path $reportFixtureRoot 'known-artifacts-missing-metadata'
    $missingMetadataReport = Invoke-ReportFinalization -Delivery $confirmedCreate -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId $knownRunId -ArtifactRoot $missingMetadataArtifactRoot -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath -OccurredAtUtc '2026-10-10T03:30:00Z' -TaskRefs $knownTaskRefs
    Assert-True ($missingMetadataReport.reportState -eq 'published') 'missing setup metadata must retain the bounded report fallback'
    $missingMetadataJson = Get-Content -Raw -LiteralPath $missingMetadataReport.jsonPath | ConvertFrom-Json -Depth 100
    Assert-True ([string]$missingMetadataJson.metrics.modelsAndReasoning.state -eq 'unavailable' -and
        [string]$missingMetadataJson.provenance.setupMetadata.state -eq 'unavailable' -and
        [string]$missingMetadataJson.coverage.taskSet.state -eq 'measured') 'missing metadata fallback must disclose unavailable provenance without losing declared task coverage'

    $invalidProviderCases = @(
        [ordered]@{ name = 'wrong repository'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -Repository 'OtherRepo' }
        [ordered]@{ name = 'wrong story branch'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -HeadBranch 'codex/other-story' }
        [ordered]@{ name = 'repository identity copy drift'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -Repository 'OtherRepo' -DeliveryRepository 'OtherRepo' }
        [ordered]@{ name = 'story branch identity copy drift'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -HeadBranch 'codex/other-story' -DeliveryStoryBranch 'codex/other-story' }
        [ordered]@{ name = 'base identity copy drift'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -ProviderBase 'master' -DeliveryPrBase 'master' }
        [ordered]@{ name = 'closed PR'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -ProviderState 'closed' -IsClosed $true }
        [ordered]@{ name = 'unknown PR state'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -ProviderState $null -IsClosed $null }
        [ordered]@{ name = 'mismatched approved HEAD'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -Head $reportHeadA -ReviewedHead $reportHeadB }
        [ordered]@{ name = 'approval bypass with matching B copies'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -Head $reportHeadB -ReviewedHead $reportHeadB }
        [ordered]@{ name = 'response-lost create'; delivery = New-DeliveryVariant -BaseDelivery $confirmedCreate -State 'reconcile' -ProviderConfirmed $false }
    )
    foreach ($invalidProviderCase in $invalidProviderCases) {
        $invalidArtifactRoot = Join-Path $reportFixtureRoot ('invalid-' + ($invalidProviderCase.name -replace '[^a-z0-9]+', '-'))
        $invalidResult = Invoke-ReportFinalization -Delivery $invalidProviderCase.delivery -RecorderPath (Join-Path $reportFixtureRoot 'missing-recorder.ps1') -AggregatorPath (Join-Path $reportFixtureRoot 'missing-aggregator.ps1') -ExternalRunRoot $reportFixtureRoot -RunId ('invalid-' + [guid]::NewGuid().ToString('N')) -ArtifactRoot $invalidArtifactRoot -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
        Assert-True ($invalidResult.deliveryState -eq 'reconcile' -and $invalidResult.reportState -eq 'not_attempted' -and -not $invalidResult.prReadyEvent) "$($invalidProviderCase.name) must not finalize"
        Assert-True (-not (Test-Path -LiteralPath $invalidArtifactRoot)) "$($invalidProviderCase.name) must not invoke aggregation or create artifacts"
    }

    $unknownDelivery = [ordered]@{ state = 'reconcile'; providerConfirmed = $false; pr = $null; reviewedHead = $reportHeadA; prBase = $valid.prBase }
    $unknownReport = Invoke-ReportFinalization -Delivery $unknownDelivery -RecorderPath (Join-Path $reportFixtureRoot 'missing-recorder.ps1') -AggregatorPath (Join-Path $reportFixtureRoot 'missing-aggregator.ps1') -ExternalRunRoot $reportFixtureRoot -RunId 'unknown-run' -ArtifactRoot (Join-Path $reportFixtureRoot 'unknown-artifacts') -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($unknownReport.deliveryState -eq 'reconcile' -and -not $unknownReport.prReadyEvent -and $unknownReport.reportState -eq 'not_attempted') 'unknown provider outcome must reconcile without pr_ready or aggregation'

    $runRecorderFailure = New-SyntheticPerformanceRun -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-recorder-failure' -OccurredAtUtc '2026-10-10T02:19:00Z'
    $recorderFailure = Invoke-ReportFinalization -Delivery $confirmedCreate -RecorderPath (Join-Path $reportFixtureRoot 'missing-recorder.ps1') -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-recorder-failure' -ArtifactRoot (Join-Path $reportFixtureRoot 'recorder-failure-artifacts') -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($recorderFailure.deliveryState -eq 'confirmed' -and $recorderFailure.reportState -eq 'unavailable' -and -not $recorderFailure.prReadyEvent -and $recorderFailure.response.Contains('recorder failure')) 'recorder failure must preserve confirmed delivery and disclose a limitation'
    Assert-True (@(Get-Content -LiteralPath $runRecorderFailure | Where-Object { $_ -like '*pr_ready*' }).Count -eq 0) 'recorder failure must not fabricate pr_ready'

    $runReportFailure = New-SyntheticPerformanceRun -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-aggregation-failure' -OccurredAtUtc '2026-10-10T02:29:00Z'
    $aggregationFailure = Invoke-ReportFinalization -Delivery $confirmedCreate -RecorderPath $reportRecorderPath -AggregatorPath (Join-Path $reportFixtureRoot 'missing-aggregator.ps1') -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-aggregation-failure' -ArtifactRoot (Join-Path $reportFixtureRoot 'aggregation-failure-artifacts') -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($aggregationFailure.deliveryState -eq 'confirmed' -and $aggregationFailure.reportState -eq 'unavailable' -and $aggregationFailure.prReadyEvent -and $aggregationFailure.response.Contains('unavailable/limited')) 'aggregator failure must preserve confirmed delivery and disclose a limitation'
}
finally {
    if (Test-Path -LiteralPath $reportFixtureRoot) {
        Remove-Item -LiteralPath $reportFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'Passed offline PR delivery fixture and report-finalization fixtures: exact-head preflight, topology/reuse/unknown guards, unknown-state reconciliation, confirmed create/reuse-only pr_ready, real aggregator publication, duplicate report reuse, new reviewed-head retention, recorder/report fail-open limitations, and concise JSON response references.'
