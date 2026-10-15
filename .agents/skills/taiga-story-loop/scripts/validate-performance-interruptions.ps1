# Focused issue #226 regression through the production constructor, transition
# recorder, and reporter. All data is disposable; no provider or quota is used.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'new-story-performance-event.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('taiga-interruptions-' + [guid]::NewGuid().ToString('N'))
$runId = 'issue-226'
$head = 'a' * 40
$common = @{ ProjectId = 12; StoryId = 1; StoryRef = 1; RunId = $runId; ReviewMode = 'per_task'; Provenance = @{ source = 'synthetic_fixture'; observedBy = 'issue-226-regression'; coverage = 'deterministic boundary controls'; synthetic = $true } }
function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Issue-226 regression: $Message" }
}
function Record([object] $Event) {
    $result = (& (Join-Path $PSScriptRoot 'record-story-performance-transition.ps1') -ExternalRunRoot $root -RunId $runId -EventJson ($Event | ConvertTo-Json -Depth 100 -Compress) -TaskRefs @(17)) | ConvertFrom-Json -Depth 100
    return $result
}
function Read-Events {
    return @(Get-Content -LiteralPath (Join-Path $root "$runId/events.jsonl") | ForEach-Object { ($_ | ConvertFrom-Json -Depth 100 -DateKind String).event })
}
function Record-Confirmed([object] $Event) {
    $result = Record $Event
    Assert-True ($result.status -in @('appended', 'noop')) "$($Event.eventId): $($result.diagnostics -join '; ')"
    return $result
}
try {
    $null = Record-Confirmed (New-StoryPerformanceEvent @common -EventId start -EventType story_started -OccurredAtUtc '2026-10-15T00:00:00Z' -Scope story -Role coordinator -WorkerId coordinator -SessionId coordinator)
    $implementation = @{ Scope = 'task'; Role = 'implementer'; TaskRef = 17; PhaseId = 'implementation'; WorkerId = 'implementer'; SessionId = 'implementer' }
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @implementation -EventId implement-start -EventType implementation_started -OccurredAtUtc '2026-10-15T00:01:00Z')
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @implementation -EventId implement-ready -EventType task_ready_for_review -OccurredAtUtc '2026-10-15T00:20:00Z' -Revision $head)

    # The exact Task #17 enum error is repaired once without moving the boundary.
    $review = @{ Scope = 'task'; Role = 'reviewer'; TaskRef = 17; PhaseId = 'review'; WorkerId = 'reviewer'; SessionId = 'reviewer'; ReviewRequestId = 'request-17'; ReviewAttemptId = 'attempt-17'; ReviewAttemptOrdinal = 1; Revision = $head }
    $invalid = New-StoryPerformanceEvent @common @review -ReviewKind initial -EventId review-start -EventType review_started -OccurredAtUtc '2026-10-15T00:21:00Z'
    $recovered = Record-Confirmed $invalid
    Assert-True (($recovered.diagnostics -join ';') -match 'recorder_validation_rejected:.*reviewKind' -and ($recovered.diagnostics -join ';') -match 'recorder_validation_recovered:') 'specific rejection and confirmed recovery must be surfaced'
    Assert-True ($recovered.telemetryState -eq 'verified') 'a confirmed repair is not left as an unresolved telemetry gap'
    $replay = Record-Confirmed $invalid
    Assert-True ($replay.status -eq 'noop') 'repaired original payload must replay without duplicate events'
    $stored = @((Read-Events) | Where-Object eventId -eq review-start)
    Assert-True ($stored.Count -eq 1 -and $stored[0].reviewKind -eq 'initial_task' -and $stored[0].occurredAtUtc -eq $invalid.occurredAtUtc) 'repair preserves observed boundary and event identity'
    $bad = New-StoryPerformanceEvent @common @review -ReviewKind unsupported -EventId bad-review -EventType review_started -OccurredAtUtc '2026-10-15T00:21:00Z'
    $rejected = Record $bad
    Assert-True ($rejected.status -eq 'unavailable' -and ($rejected.diagnostics -join ';') -match 'recorder_validation_rejected:') 'unknown enum is actionable and not guessed'
    # Execution continues after the diagnostic; accepted initial evidence is intact.
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @review -ReviewKind initial_task -EventId findings -EventType review_findings -OccurredAtUtc '2026-10-15T00:40:00Z')

    $correction = @{ Scope = 'task'; Role = 'implementer'; TaskRef = 17; PhaseId = 'correction'; CorrectionId = 'correction-17'; SupersedesReviewAttemptId = 'attempt-17'; WorkerId = 'implementer'; SessionId = 'implementer' }
    $end = New-StoryPerformanceEvent @common @correction -EventId correction-end -EventType correction_ready -OccurredAtUtc '2026-10-15T00:50:00Z' -Revision $head
    $missing = Record $end
    Assert-True ($missing.status -eq 'unavailable' -and ($missing.diagnostics -join ';') -match 'phase_boundary_conflict') 'missing correction start must not be silently closed'
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @correction -EventId correction-start -EventType correction_started -OccurredAtUtc '2026-10-15T00:41:00Z')
    $late = New-StoryPerformanceEvent @common @correction -EventId correction-late -EventType correction_ready -OccurredAtUtc '2026-10-15T00:40:00Z' -Revision $head
    Assert-True ((Record $late).status -eq 'unavailable') 'start after the completion boundary is rejected'
    $null = Record-Confirmed $end
    Assert-True ((Record (New-StoryPerformanceEvent @common @correction -EventId replacement-start -EventType correction_started -OccurredAtUtc '2026-10-15T00:39:00Z')).status -eq 'unavailable') 'a replacement timestamp cannot manufacture correction coverage'

    # Implementation and reviewer quota episodes use the affected identity.
    # Their overlapping confirmed intervals must be unioned, not summed.
    foreach ($role in @('implementer', 'reviewer', 'coordinator')) {
        $context = $common + @{ Scope = $(if ($role -eq 'coordinator') { 'story' } else { 'task' }); TaskRef = $(if ($role -eq 'coordinator') { $null } else { 17 }); Role = $role; WorkerId = $role; SessionId = $role }
        $failureTime = switch ($role) { implementer { '2026-10-15T00:05:00Z' } reviewer { '2026-10-15T00:23:00Z' } coordinator { '2026-10-15T00:07:00Z' } }
        $failure = New-StoryPerformanceInterruptionEvent -Context $context -InterruptionId "$role-quota" -Observation usage_limit_exceeded -OccurredAtUtc $failureTime
        $null = Record-Confirmed $failure
        # Failed automated attempts reconcile the same saved failure observation.
        Assert-True ((Record-Confirmed $failure).status -eq 'noop') 'failed recovery must not duplicate the interruption'
        $recoveryTime = if ($role -eq 'reviewer') { '2026-10-15T00:28:00Z' } else { '2026-10-15T00:10:00Z' }
        $recovery = New-StoryPerformanceInterruptionEvent -Context $context -InterruptionId "$role-quota" -Observation quota_capacity_verified -OccurredAtUtc $recoveryTime
        $null = Record-Confirmed $recovery
        Assert-True ((Record-Confirmed $recovery).status -eq 'noop') 'verified recovery reconciliation must not duplicate the end'
    }
    $null = Record-Confirmed (New-StoryPerformanceEvent @common -EventId pr-ready -EventType pr_ready -OccurredAtUtc '2026-10-15T01:00:00Z' -Scope story -Role coordinator -WorkerId coordinator -SessionId coordinator -Revision $head -PullRequest @{ provider = 'github'; owner = 'fixture'; repository = 'fixture'; number = 1; reviewedHead = $head })
    $ledger = Join-Path $root "$runId/events.jsonl"
    $report = (& (Join-Path $PSScriptRoot 'get-story-performance.ps1') -EventsPath $ledger -TaskRefs @(17) -ReviewMode per_task) | ConvertFrom-Json -Depth 100
    Assert-True ($report.metrics.quotaBlockedElapsed.value -eq 600000 -and $report.metrics.quotaAdjustedElapsed.value -eq 3000000) 'overlapping confirmed quota waits are subtracted once'

    # Failed automated recovery followed by a manual resume proves no exact
    # availability timestamp during the gap. Keep quota incomplete, not zero.
    $context = $common + @{ Scope = 'task'; TaskRef = 17; Role = 'reviewer'; WorkerId = 'reviewer'; SessionId = 'reviewer' }
    $null = Record-Confirmed (New-StoryPerformanceInterruptionEvent -Context $context -InterruptionId manual-quota -Observation usage_limit_exceeded -OccurredAtUtc '2026-10-15T00:31:00Z')
    $null = Record-Confirmed (New-StoryPerformanceInterruptionEvent -Context $context -InterruptionId manual-quota -Observation manual_resume_wait -OccurredAtUtc '2026-10-15T00:32:00Z')
    $null = Record-Confirmed (New-StoryPerformanceInterruptionEvent -Context $context -InterruptionId manual-quota -Observation manual_resumed -OccurredAtUtc '2026-10-15T00:38:00Z')
    $report = (& (Join-Path $PSScriptRoot 'get-story-performance.ps1') -EventsPath $ledger -TaskRefs @(17) -ReviewMode per_task) | ConvertFrom-Json -Depth 100
    Assert-True ($report.metrics.quotaBlockedElapsed.state -eq 'partial' -and $null -eq $report.metrics.quotaAdjustedElapsed.value) 'unknown availability cannot become a fully measured adjusted total'
    Assert-True ($report.metrics.quotaBlockedElapsed.knownSubtotal -eq 600000 -and $report.metrics.quotaBlockedElapsed.missingData -match 'manual resumption') 'partial reporting retains confirmed subtotal and explains missing capacity evidence'
    Assert-True ($report.metrics.reviewElapsed.value -eq 1140000) 'review duration remains total wall time rather than inferred active time'
    $manual = @($report.waits | Where-Object waitKind -eq manual_resume)
    Assert-True ($manual.Count -eq 1 -and $manual[0].elapsedMilliseconds -eq 360000) 'manual authorization waiting is separately attributable'
    Assert-True (@((Read-Events) | Where-Object { $_.eventId -eq 'manual-quota/quota_capacity_verified' }).Count -eq 0) 'manual resume never fabricates a quota end'

    # Lightweight local workflow smoke: real edits, checks, and Git revisions,
    # with production recording before each activity. This is a local smoke,
    # not independent worker-chat review or an induced account quota failure.
    $runId = 'local-smoke'
    $common.RunId = $runId
    $repository = Join-Path $root 'smoke-repository'
    [IO.Directory]::CreateDirectory($repository) | Out-Null
    & git -C $repository init --quiet
    Assert-True ($LASTEXITCODE -eq 0) 'smoke repository initializes'
    function Now-Utc { [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'") }
    function Commit-Smoke {
        & git -C $repository add increment.ps1
        Assert-True ($LASTEXITCODE -eq 0) 'smoke source stages'
        & git -C $repository -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m 'Smoke source revision'
        Assert-True ($LASTEXITCODE -eq 0) 'smoke revision commits'
        return (& git -C $repository rev-parse HEAD).Trim()
    }
    $null = Record-Confirmed (New-StoryPerformanceEvent @common -EventId start -EventType story_started -OccurredAtUtc (Now-Utc) -Scope story -Role coordinator -WorkerId coordinator -SessionId coordinator)
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @implementation -EventId implement-start -EventType implementation_started -OccurredAtUtc (Now-Utc))
    $source = Join-Path $repository 'increment.ps1'
    [IO.File]::WriteAllText($source, 'param([int] $Value) $Value + 1')
    Assert-True ((& $source -Value 1) -eq 2) 'initial implementation check executes actual source'
    $head = Commit-Smoke
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @implementation -EventId implement-ready -EventType task_ready_for_review -OccurredAtUtc (Now-Utc) -Revision $head)
    $review.Revision = $head
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @review -ReviewKind initial -EventId review-start -EventType review_started -OccurredAtUtc (Now-Utc))
    Assert-True ((& $source -Value 1) -ne 3) 'review discovers the correction scenario through actual source'
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @review -ReviewKind initial_task -EventId findings -EventType review_findings -OccurredAtUtc (Now-Utc))
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @correction -EventId correction-start -EventType correction_started -OccurredAtUtc (Now-Utc))
    # Investigation and validation occur after the start is confirmed in the ledger.
    $null = Get-Content -LiteralPath $source
    [IO.File]::WriteAllText($source, 'param([int] $Value) $Value + 2')
    Assert-True ((& $source -Value 1) -eq 3) 'correction check executes changed source'
    $head = Commit-Smoke
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @correction -EventId correction-end -EventType correction_ready -OccurredAtUtc (Now-Utc) -Revision $head)
    $review.Revision = $head
    $review.PhaseId = 'rereview'
    $review.ReviewRequestId = 'rerequest-17'
    $review.ReviewAttemptId = 'reattempt-17'
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @review -ReviewKind correction_rereview -EventId rereview-start -EventType review_started -OccurredAtUtc (Now-Utc))
    Assert-True ((& $source -Value 1) -eq 3) 're-review executes actual correction'
    $null = Record-Confirmed (New-StoryPerformanceEvent @common @review -ReviewKind correction_rereview -EventId accepted -EventType review_accepted -OccurredAtUtc (Now-Utc))
    $smokeReport = (& (Join-Path $PSScriptRoot 'get-story-performance.ps1') -EventsPath (Join-Path $root "$runId/events.jsonl") -TaskRefs @(17) -ReviewMode per_task) | ConvertFrom-Json -Depth 100
    Assert-True ($smokeReport.metrics.initialTaskReviews.value -eq 1) 'smoke report recognizes the initial review'
    Assert-True ($smokeReport.metrics.tasksCompleted.value -eq 1) 'repaired review start preserves task acceptance statistics'
    Assert-True (@($smokeReport.anomalies | Where-Object { $_.code -in @('orphan_review_closure', 'missing_initial_review_evidence') }).Count -eq 0) 'recovered start leaves no orphan review or missing initial evidence'
    'Issue #226 interruption, boundary, and rejection regressions passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFileName($resolved).StartsWith('taiga-interruptions-')) { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
