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

function New-PerformanceEvent {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventType,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
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
        taskRef = $null
        role = 'coordinator'
        sessionId = 'synthetic-coordinator-session'
        workerId = 'synthetic-coordinator'
        transitionId = $EventId
        scope = 'story'
        phaseId = $null
        correctionId = $null
        reviewRequestId = $null
        reviewAttemptId = $null
        reviewKind = $null
        reviewAttemptOrdinal = $null
        supersedesReviewAttemptId = $null
        eventType = $EventType
        occurredAtUtc = $OccurredAtUtc
        revision = $Revision
        reviewMode = 'per_task'
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

function New-SyntheticPerformanceRun {
    param(
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $ExternalRunRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $OccurredAtUtc
    )

    [IO.Directory]::CreateDirectory($ExternalRunRoot) | Out-Null
    $storyStarted = New-PerformanceEvent -RunId $RunId -EventId "$RunId/story-started" -EventType 'story_started' -OccurredAtUtc $OccurredAtUtc
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
        [Parameter(Mandatory)] [string] $RepositoryPath
    )

    $pr = $Delivery.pr
    $confirmed = $Delivery.providerConfirmed -eq $true -and
        $Delivery.state -in @('created', 'reused') -and
        $null -ne $pr -and
        [string]$pr.head -eq [string]$Delivery.reviewedHead -and
        [string]$pr.base -eq [string]$Delivery.prBase
    if (-not $confirmed) {
        return [ordered]@{
            deliveryState = 'reconcile'
            reportState = 'not_attempted'
            prReadyEvent = $false
            reportId = $null
            jsonPath = $null
            response = 'PR delivery reconciliation required; performance report not attempted.'
        }
    }

    $prIdentity = [ordered]@{
        provider = 'github'
        owner = 'blakeg83'
        repository = 'taiga-mcp'
        number = [int]$pr.number
        reviewedHead = [string]$Delivery.reviewedHead
    }
    $prReady = New-PerformanceEvent -RunId $RunId -EventId "$RunId/pr-ready-$($pr.number)-$($Delivery.reviewedHead)" -EventType 'pr_ready' -OccurredAtUtc '2026-10-10T02:00:00Z' -Revision ([string]$Delivery.reviewedHead) -PullRequest $prIdentity
    if (-not (Invoke-PerformanceRecorder -RecorderPath $RecorderPath -ExternalRunRoot $ExternalRunRoot -RunId $RunId -Event $prReady)) {
        return [ordered]@{
            deliveryState = 'confirmed'
            reportState = 'unavailable'
            prReadyEvent = $false
            reportId = $null
            jsonPath = $null
            response = 'PR ready for approval; performance report unavailable (recorder failure).'
        }
    }

    try {
        [IO.Directory]::CreateDirectory($ArtifactRoot) | Out-Null
        $ledgerPath = Join-Path (Join-Path $ExternalRunRoot $RunId) 'events.jsonl'
        $output = @(& pwsh -NoProfile -File $AggregatorPath -EventsPath $ledgerPath -ReviewMode per_task -ReviewedHead ([string]$Delivery.reviewedHead) -BaseRevision $BaseRevision -RepositoryPath $RepositoryPath -ArtifactDirectory $ArtifactRoot 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join [Environment]::NewLine)
        }
        $report = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100
        $jsonArtifact = Get-ChildItem -LiteralPath $ArtifactRoot -File -Filter '*.json' |
            Where-Object { $_.Name -notlike '*.manifest.json' } |
            Select-Object -First 1
        Assert-True ($null -ne $jsonArtifact) 'confirmed report must publish a JSON artifact'
        $summary = "report=$($report.reportId); timeToPr=$($report.metrics.timeToPr.state); limitations=$(@($report.provenance.limitations) -join ', ')"
        return [ordered]@{
            deliveryState = 'confirmed'
            reportState = 'published'
            prReadyEvent = $true
            reportId = [string]$report.reportId
            jsonPath = $jsonArtifact.FullName
            response = "PR ready for approval; performance report: $summary; JSON artifact: $($jsonArtifact.FullName)"
        }
    }
    catch {
        return [ordered]@{
            deliveryState = 'confirmed'
            reportState = 'unavailable'
            prReadyEvent = $true
            reportId = $null
            jsonPath = $null
            response = "PR ready for approval; performance report unavailable/limited: $($_.Exception.Message)"
        }
    }
}

$reportFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-mcp-pr-report-finalization-' + [guid]::NewGuid().ToString('N'))
$reportRepositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$reportRecorderPath = Join-Path $PSScriptRoot 'write-performance-event.ps1'
$reportAggregatorPath = Join-Path $reportRepositoryPath 'scripts/get-story-performance.ps1'
$reportBase = 'b' * 40
$reportHeadA = 'a' * 40
$reportHeadB = 'c' * 40
$reportPrA = [pscustomobject]@{
    url = 'https://example.invalid/pr/report-a'
    number = 157
    base = $valid.prBase
    head = $reportHeadA
}
$confirmedCreate = [ordered]@{
    state = 'created'
    providerConfirmed = $true
    pr = $reportPrA
    reviewedHead = $reportHeadA
    prBase = $valid.prBase
}
$confirmedReuse = [ordered]@{
    state = 'reused'
    providerConfirmed = $true
    pr = $reportPrA
    reviewedHead = $reportHeadA
    prBase = $valid.prBase
}

try {
    $runA = New-SyntheticPerformanceRun -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -OccurredAtUtc '2026-10-10T01:59:00Z'
    $artifactA = Join-Path $reportFixtureRoot 'artifacts-a'
    $createdReport = Invoke-ReportFinalization -Delivery $confirmedCreate -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -ArtifactRoot $artifactA -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($createdReport.deliveryState -eq 'confirmed' -and $createdReport.reportState -eq 'published' -and $createdReport.prReadyEvent) 'confirmed PR creation must append pr_ready and publish a report'
    Assert-True ($createdReport.response.Contains('performance report:') -and $createdReport.response.Contains('JSON artifact:') -and (Test-Path -LiteralPath $createdReport.jsonPath -PathType Leaf)) 'normal confirmed response must include a concise report and JSON artifact reference'

    $reusedReport = Invoke-ReportFinalization -Delivery $confirmedReuse -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-a' -ArtifactRoot $artifactA -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($reusedReport.reportState -eq 'published' -and $reusedReport.reportId -eq $createdReport.reportId -and $reusedReport.jsonPath -eq $createdReport.jsonPath) 'duplicate confirmed PR reuse must reuse the same report identity and JSON artifact'
    $runALedgerLines = @(Get-Content -LiteralPath $runA)
    Assert-True ($runALedgerLines.Count -eq 2) 'duplicate confirmed PR observation must not append a second pr_ready event'

    $reportPrB = [pscustomobject]@{ url = 'https://example.invalid/pr/report-b'; number = 157; base = $valid.prBase; head = $reportHeadB }
    $confirmedNewHead = [ordered]@{ state = 'reused'; providerConfirmed = $true; pr = $reportPrB; reviewedHead = $reportHeadB; prBase = $valid.prBase }
    $runB = New-SyntheticPerformanceRun -RecorderPath $reportRecorderPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-b' -OccurredAtUtc '2026-10-10T02:09:00Z'
    $newHeadReport = Invoke-ReportFinalization -Delivery $confirmedNewHead -RecorderPath $reportRecorderPath -AggregatorPath $reportAggregatorPath -ExternalRunRoot $reportFixtureRoot -RunId 'synthetic-pr-report-b' -ArtifactRoot (Join-Path $reportFixtureRoot 'artifacts-b') -BaseRevision $reportBase -RepositoryPath $reportRepositoryPath
    Assert-True ($newHeadReport.reportState -eq 'published' -and $newHeadReport.reportId -ne $createdReport.reportId -and $newHeadReport.jsonPath -ne $createdReport.jsonPath) 'a newly confirmed reviewed HEAD must retain a new report sibling'

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
