# Copy-folder regression. Child execution has no source-checkout path or helpers.
[CmdletBinding()]
param(
    [string] $InstalledSkillPath,
    [string] $FixtureRoot,
    [string] $ExampleArtifactRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Write-Json([string] $Path, [object] $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
}

if (-not $InstalledSkillPath) {
    $ownedRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-portability-224-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.Directory]::CreateDirectory($ownedRoot) | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop') -Destination $ownedRoot -Recurse
        # Keep development-only validators outside the portable runtime under test.
        Get-ChildItem -LiteralPath (Join-Path $ownedRoot 'taiga-story-loop/scripts') -Filter 'validate-*.ps1' |
            Remove-Item
        # The test driver travels separately; it imports no source-tree fixture builders.
        $driver = Join-Path $ownedRoot 'regression.ps1'
        Copy-Item -LiteralPath $PSCommandPath -Destination $driver
        $arguments = @('-NoProfile', '-NonInteractive', '-File', $driver,
            '-InstalledSkillPath', (Join-Path $ownedRoot 'taiga-story-loop'), '-FixtureRoot', $ownedRoot)
        if ($ExampleArtifactRoot) { $arguments += @('-ExampleArtifactRoot', $ExampleArtifactRoot) }
        & pwsh @arguments
        Assert-True ($LASTEXITCODE -eq 0) 'standalone installed telemetry regression failed'
    }
    finally {
        # This is the literal unique root created above; never an operator-selected path.
        $resolvedOwnedRoot = [IO.Path]::GetFullPath($ownedRoot)
        Assert-True ($resolvedOwnedRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedOwnedRoot).StartsWith('taiga-portability-224-')) 'cleanup must stay in the owned disposable root'
        if (Test-Path -LiteralPath $resolvedOwnedRoot) { Remove-Item -LiteralPath $resolvedOwnedRoot -Recurse -Force }
    }
    exit
}

# Everything below runs from the installed copy in a fresh PowerShell process.
$runtime = Join-Path $InstalledSkillPath 'scripts'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $InstalledSkillPath '../../../../scripts/finalize-story-performance.ps1'))) 'original repository layout must be absent'
$repository = Join-Path $FixtureRoot 'unrelated-project'
[IO.Directory]::CreateDirectory($repository) | Out-Null
Set-Location -LiteralPath $repository
& git init --quiet
Assert-True ($LASTEXITCODE -eq 0) 'temporary Git repository initialization failed'
[IO.File]::WriteAllText((Join-Path $repository 'sample.txt'), "synthetic target`n")
& git add sample.txt
& git -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m 'Synthetic baseline'
Assert-True ($LASTEXITCODE -eq 0) 'temporary Git baseline failed'
$head = (& git rev-parse HEAD).Trim()
. (Join-Path $runtime 'new-story-performance-event.ps1')
. (Join-Path $runtime 'format-story-performance-utc.ps1')
$runRoot = Join-Path $FixtureRoot 'runs'
$runId = 'standalone-synthetic'
$provenance = @{ source = 'synthetic_fixture'; observedBy = 'portability-regression'; coverage = 'fixed UTC boundaries'; synthetic = $true }
$common = @{ ProjectId = 12; StoryId = 728; StoryRef = 144; RunId = $runId; ReviewMode = 'per_task'; Provenance = $provenance }
function Record-Boundary([hashtable] $Boundary) {
    $event = New-StoryPerformanceEvent @common @Boundary
    $json = $event | ConvertTo-Json -Depth 100 -Compress
    $result = (& (Join-Path $runtime 'record-story-performance-transition.ps1') -ExternalRunRoot $runRoot -RunId $runId -EventJson $json -TaskRefs @(155)) | ConvertFrom-Json -Depth 100
    Assert-True ($result.status -eq 'appended') "installed boundary failed: $($Boundary.EventType); $($result.diagnostics -join '; ')"
}
Record-Boundary @{ EventId = 'start'; EventType = 'story_started'; OccurredAtUtc = '2026-10-14T04:00:00Z'; Scope = 'story'; Role = 'coordinator'; WorkerId = 'coordinator'; SessionId = 'coordinator-session' }
$implementation = @{ Scope = 'task'; Role = 'implementer'; WorkerId = 'implementer'; SessionId = 'implementer-session'; TaskRef = 155; PhaseId = 'implementation-155' }
Record-Boundary ($implementation + @{ EventId = 'implement-start'; EventType = 'implementation_started'; OccurredAtUtc = '2026-10-14T04:01:00Z' })
Record-Boundary ($implementation + @{ EventId = 'implement-end'; EventType = 'task_ready_for_review'; OccurredAtUtc = '2026-10-14T04:06:00Z'; Revision = $head })
$review = @{ Scope = 'task'; Role = 'reviewer'; WorkerId = 'reviewer'; SessionId = 'reviewer-session'; TaskRef = 155; PhaseId = 'review-155'; ReviewRequestId = 'request-155'; ReviewAttemptId = 'attempt-155'; ReviewKind = 'initial_task'; ReviewAttemptOrdinal = 1; Revision = $head }
Record-Boundary ($review + @{ EventId = 'review-start'; EventType = 'review_started'; OccurredAtUtc = '2026-10-14T04:07:00Z' })
Record-Boundary ($review + @{ EventId = 'review-end'; EventType = 'review_accepted'; OccurredAtUtc = '2026-10-14T04:09:00Z' })
$finalReview = @{ Scope = 'final_story'; Role = 'reviewer'; WorkerId = 'reviewer'; SessionId = 'reviewer-session'; PhaseId = 'final-review'; ReviewRequestId = 'final-request'; ReviewAttemptId = 'final-attempt'; ReviewKind = 'final_story'; ReviewAttemptOrdinal = 1; Revision = $head }
Record-Boundary ($finalReview + @{ EventId = 'final-start'; EventType = 'final_review_started'; OccurredAtUtc = '2026-10-14T04:10:00Z' })
Record-Boundary ($finalReview + @{ EventId = 'final-end'; EventType = 'final_review_accepted'; OccurredAtUtc = '2026-10-14T04:12:00Z' })

# Synthetic delivery tests production preflight; this is not a real PR receipt.
$receipt = @{
    runKind = 'standalone'; repository = 'unrelated-project'; storyBranch = 'codex/synthetic'; expectedBranch = 'codex/synthetic'
    expectedWorktree = $repository; featureBranch = ''; prBase = 'master'; reviewBaseSha = $head; approvedHead = $head; branchHead = $head
    diffRange = "$head..$head"; sourceState = 'clean-tracked-source'; ignoredOutputsDeclared = $true; clean = $true
    checksPassed = $true; checksHead = $head; finalStoryReviewAccepted = $true; finalStoryReviewHead = $head
}
$delivery = @{
    state = 'created'; providerConfirmed = $true; receipt = $receipt; repository = $receipt.repository
    storyBranch = $receipt.storyBranch; prBase = 'master'; reviewedHead = $head
    pr = @{ url = 'https://github.com/fixture/unrelated-project/pull/1'; number = 1; repository = $receipt.repository; headBranch = $receipt.storyBranch; base = 'master'; head = $head; state = 'open'; isClosed = $false }
}
$deliveryPath = Join-Path $FixtureRoot 'delivery.json'
Write-Json $deliveryPath $delivery
$evidencePath = Join-Path $FixtureRoot 'missing-sources.json'
Write-Json $evidencePath @{ rows = @(@{ role = 'implementer'; scope = 'story-144'; sessionId = 'implementer-session'; sourcePath = (Join-Path $FixtureRoot 'absent-session.jsonl') }) }
$parameters = @{
    DeliveryPath = $deliveryPath; ExternalRunRoot = $runRoot; RunId = $runId; ArtifactRoot = (Join-Path $FixtureRoot 'reports')
    BaseRevision = $head; RepositoryPath = $repository; ReviewMode = 'per_task'; TaskRefs = @(155)
    OccurredAtUtc = '2026-10-14T04:15:00Z'; ArtifactsAccessibleToUser = $true; ObservedEvidencePath = $evidencePath
}
$result = (& (Join-Path $runtime 'finalize-story-performance.ps1') @parameters) | ConvertFrom-Json -Depth 100 -DateKind String
Assert-True ($result.reportState -eq 'published' -and $result.prReadyEvent) "installed finalization failed: $($result.limitations -join '; ')"
$report = Get-Content -LiteralPath $result.jsonPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-True ($report.metrics.timeToPr.state -eq 'measured' -and $report.metrics.timeToPr.value -eq 900000) 'story elapsed metric must use recorded UTC boundaries in milliseconds'
Assert-True ($report.metrics.implementationElapsed.state -eq 'measured' -and $report.metrics.implementationElapsed.value -eq 300000) 'implementation interval must be measured in milliseconds'
Assert-True ($report.metrics.reviewElapsed.state -eq 'measured' -and $report.metrics.reviewElapsed.value -eq 240000) 'task and final-story review intervals must be measured in milliseconds'
Assert-True ($report.metrics.observedTotalTokens.state -in @('partial', 'unavailable') -and $null -eq $report.metrics.observedTotalTokens.value) 'missing counter sources must never become fabricated token measurements'
Assert-True ($result.collectionAttempt.collectorInvoked -and $result.collectionAttempt.status -eq 'source_unavailable') 'installed collector must attempt missing sources without failing publication'
$manifest = Get-Content -LiteralPath $result.manifestPath -Raw | ConvertFrom-Json -Depth 100
Assert-True ($manifest.artifacts.Count -eq 2) 'JSON and Markdown artifacts must both be published'
foreach ($artifact in $manifest.artifacts) {
    Assert-True ((Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash -ieq $artifact.sha256) 'artifact checksum must match published content'
}
$markdown = Get-Content -LiteralPath $result.markdownPath -Raw
Assert-True ($markdown.Contains('unavailable') -and $markdown.Contains('measured')) 'readable report must disclose measurement coverage'
$ledger = @(Get-Content -LiteralPath (Join-Path $runRoot "$runId/events.jsonl") | ForEach-Object { ($_ | ConvertFrom-Json -Depth 100 -DateKind String).event })
Assert-True ($ledger.Count -eq 8 -and $ledger[0].eventType -eq 'story_started' -and $ledger[-1].eventType -eq 'pr_ready') 'all lifecycle boundaries must persist'
Assert-True (@($ledger | Where-Object { $_.occurredAtUtc -notmatch 'Z$' -or [string]::IsNullOrWhiteSpace($_.eventId) }).Count -eq 0) 'identities and UTC timestamps must be valid'
$repeat = (& (Join-Path $runtime 'finalize-story-performance.ps1') @parameters) | ConvertFrom-Json -Depth 100
Assert-True ($repeat.reportState -eq 'published' -and $repeat.reportId -ceq $result.reportId) 'installed finalization must reuse the same report identity'
if ($ExampleArtifactRoot) {
    [IO.Directory]::CreateDirectory($ExampleArtifactRoot) | Out-Null
    Copy-Item -LiteralPath $result.jsonPath -Destination (Join-Path $ExampleArtifactRoot 'standalone-example.json')
    Copy-Item -LiteralPath $result.markdownPath -Destination (Join-Path $ExampleArtifactRoot 'standalone-example.md')
}
'PASS: installed-only lifecycle, finalizer, collector, JSON/Markdown checksums, measured elapsed time, unavailable tokens, and report reuse'
