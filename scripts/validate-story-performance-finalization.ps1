# Synthetic regression cases exercise production entry points. No provider calls.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Reuse the existing event/setup/confirmed-delivery builders and baseline cases.
. (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/validate-pr-delivery.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-finalization-214-' + [guid]::NewGuid().ToString('N'))
$recorder = Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1'
$transition = Join-Path $PSScriptRoot 'record-story-performance-transition.ps1'
$finalizer = Join-Path $PSScriptRoot 'finalize-story-performance.ps1'
$aggregator = Join-Path $PSScriptRoot 'get-story-performance.ps1'
. (Join-Path $PSScriptRoot 'format-story-performance-utc.ps1')
$head = (& git -C $PSScriptRoot rev-parse HEAD).Trim()
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$receipt = New-DeliveryReceipt -ApprovedHead $head -BranchHead $head -ChecksHead $head -FinalStoryReviewHead $head -ReviewBaseSha $head -DiffRange "$head..$head"
$delivery = New-ConfirmedDelivery -Receipt $receipt -Resolution (Resolve-Pr @() $receipt) -ReviewedHead $head
$encoding = [Text.UTF8Encoding]::new($false)

function Write-Json {
    param([string] $Path, [object] $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), $encoding)
}
function Record-Transition {
    param([object] $Event)
    (& $transition -ExternalRunRoot $fixtureRoot -RunId $Event.runId -EventJson ($Event | ConvertTo-Json -Depth 100 -Compress) -TaskRefs @(155,156)) | ConvertFrom-Json -Depth 100
}
function Start-Run {
    param([string] $RunId, [string] $Mode = 'story_end_only')
    $event = New-PerformanceEvent -RunId $RunId -EventId "$RunId-start" -EventType story_started -OccurredAtUtc '2026-10-10T04:00:00Z' -ReviewMode $Mode
    $observation = Record-Transition $event
    Assert-True ($observation.status -eq 'appended' -and $observation.telemetryState -eq 'limited' -and $observation.diagnostics.Count -gt 0) 'initialization records missing setup/session evidence immediately without blocking'
    return Join-Path (Join-Path $fixtureRoot $RunId) 'events.jsonl'
}
function Finish-Run {
    param([string] $RunId, [string] $Mode = 'story_end_only', [string] $Evidence = '', [string] $Outcomes = '', [string] $Collector = '')
    $parameters = @{ Delivery = $delivery; ExternalRunRoot = $fixtureRoot; RunId = $RunId; ArtifactRoot = (Join-Path $fixtureRoot "$RunId-artifacts"); BaseRevision = $head; RepositoryPath = $repository; ReviewMode = $Mode; TaskRefs = @(155,156); OccurredAtUtc = '2026-10-10T04:20:00Z'; ArtifactsAccessibleToUser = $true }
    if ($Evidence) { $parameters.ObservedEvidencePath = $Evidence }
    if ($Outcomes) { $parameters.TaskOutcomePath = $Outcomes }
    if ($Collector) { $parameters.CollectorPath = $Collector }
    (& $finalizer @parameters) | ConvertFrom-Json -Depth 100 -DateKind String
}
try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null

    $capturedInstant = [DateTimeOffset]::Parse(
        '2026-10-10T04:00:00.1234567-07:00',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind)
    $canonicalInstant = Format-StoryPerformanceUtcTimestamp -Timestamp $capturedInstant
    $roundTrippedInstant = [DateTimeOffset]::Parse(
        $canonicalInstant,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind)
    Assert-True ($canonicalInstant -match 'Z$' -and $roundTrippedInstant.UtcDateTime.Ticks -eq $capturedInstant.UtcDateTime.Ticks) 'canonical UTC formatting emits literal Z and preserves the captured instant'

    $runtimeRun = 'runtime-timestamp'
    $runtimeBoundary = Format-StoryPerformanceUtcTimestamp -Timestamp ([DateTimeOffset]::UtcNow)
    $runtimeStart = New-PerformanceEvent -RunId $runtimeRun -EventId "$runtimeRun-start" -EventType story_started -OccurredAtUtc $runtimeBoundary -ReviewMode story_end_only
    $runtimeStartResult = Record-Transition $runtimeStart
    Assert-True ($runtimeStartResult.status -eq 'appended') 'runtime-generated story_started reaches the production recorder'
    $runtimeLedger = Join-Path (Join-Path $fixtureRoot $runtimeRun) 'events.jsonl'
    $runtimeSetup = New-SyntheticSetupMetadata $runtimeRun
    foreach ($profile in $runtimeSetup.profiles) { $profile.effectiveFromUtc = $runtimeBoundary }
    $runtimeSetupPath = Join-Path $fixtureRoot 'runtime-setup.json'
    Write-Json $runtimeSetupPath $runtimeSetup
    $runtimeReport = (& $aggregator -EventsPath $runtimeLedger -ReviewMode story_end_only -MetadataPath $runtimeSetupPath) | ConvertFrom-Json -Depth 100
    Assert-True ($runtimeReport.metrics.modelsAndReasoning.state -eq 'measured') 'the same runtime-generated UTC boundary is accepted for setup profile metadata'

    $zeroOffset = [DateTimeOffset]::Parse(
        '2026-10-10T04:00:00.1234567+00:00',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind)
    $canonicalZeroOffset = Format-StoryPerformanceUtcTimestamp -Timestamp $zeroOffset
    $roundTrippedZeroOffset = [DateTimeOffset]::Parse(
        $canonicalZeroOffset,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind)
    Assert-True ($canonicalZeroOffset -match 'Z$' -and $roundTrippedZeroOffset.UtcDateTime.Ticks -eq $zeroOffset.UtcDateTime.Ticks) 'zero-offset DateTimeOffset round-trips through canonical UTC construction with the same instant'
    $invalidEvent = New-PerformanceEvent -RunId $runtimeRun -EventId "$runtimeRun-invalid" -EventType story_started -OccurredAtUtc ($zeroOffset.ToString('o')) -ReviewMode story_end_only
    $runtimeLength = (Get-Item -LiteralPath $runtimeLedger).Length
    $invalidOutput = @(& pwsh -NoProfile -File $recorder -ExternalRunRoot $fixtureRoot -RunId $runtimeRun -EventJson ($invalidEvent | ConvertTo-Json -Compress -Depth 100) 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($invalidOutput -join [Environment]::NewLine).Contains('UTC timestamp ending in Z') -and (Get-Item -LiteralPath $runtimeLedger).Length -eq $runtimeLength) 'non-Z UTC input follows recorder validation without changing the immutable ledger'
    $invalidTransition = Record-Transition $invalidEvent
    Assert-True ($invalidTransition.status -eq 'unavailable' -and ($invalidTransition.diagnostics -join '; ').Contains('recorder_validation_rejected: occurredAtUtc must be an ISO 8601 UTC timestamp ending in Z') -and (Get-Item -LiteralPath $runtimeLedger).Length -eq $runtimeLength) 'transition wrapper surfaces the bounded timestamp validation reason without blocking the caller or appending invalid input'
    $correctionDiagnosticRun = 'recorder-correction-diagnostic'
    $correctionDiagnosticEvent = New-PerformanceEvent -RunId $correctionDiagnosticRun -EventId "$correctionDiagnosticRun-invalid" -EventType story_started -OccurredAtUtc '2026-10-10T04:00:00Z' -ReviewMode story_end_only
    $correctionDiagnosticEvent.correctionId = 'synthetic-secret-correction'
    $correctionDiagnostic = Record-Transition $correctionDiagnosticEvent
    $correctionDiagnosticText = $correctionDiagnostic.diagnostics -join '; '
    Assert-True ($correctionDiagnostic.status -eq 'unavailable' -and $correctionDiagnosticText.Contains('recorder_validation_rejected: correctionId is allowed only on correction events') -and -not $correctionDiagnosticText.Contains('synthetic-secret-correction') -and -not (Test-Path -LiteralPath (Join-Path $fixtureRoot $correctionDiagnosticRun) -PathType Container)) 'transition wrapper surfaces the bounded correction-field validation reason without exposing payload values or appending invalid input'

    $defaultRun = Start-Run 'omitted-finalizer-timestamp'
    $defaultParameters = @{ Delivery = $delivery; ExternalRunRoot = $fixtureRoot; RunId = 'omitted-finalizer-timestamp'; ArtifactRoot = (Join-Path $fixtureRoot 'omitted-finalizer-timestamp-artifacts'); BaseRevision = $head; RepositoryPath = $repository; ReviewMode = 'story_end_only'; TaskRefs = @(155,156) }
    $defaultResult = (& $finalizer @defaultParameters) | ConvertFrom-Json -Depth 100 -DateKind String
    $defaultEvents = @(Get-Content -LiteralPath $defaultRun | ForEach-Object {
            $parsed = $_ | ConvertFrom-Json -Depth 100 -DateKind String
            if ($parsed.kind -ceq 'story_performance_event_frame') { $parsed.event } else { $parsed }
        })
    $defaultReady = @($defaultEvents | Where-Object eventType -eq 'pr_ready')
    Assert-True ($defaultResult.reportState -eq 'published' -and $defaultReady.Count -eq 1 -and [string]$defaultReady[0].occurredAtUtc -match 'Z$') 'omitted finalizer timestamp uses a generated canonical UTC boundary'

    foreach ($invalidOccurredAt in @('', ' ')) {
        $invalidRun = if ($invalidOccurredAt.Length -eq 0) { 'empty-finalizer-timestamp' } else { 'blank-finalizer-timestamp' }
        $invalidLedger = Start-Run $invalidRun
        $beforeInvalidLedger = (Get-FileHash -LiteralPath $invalidLedger -Algorithm SHA256).Hash
        $invalidParameters = @{ Delivery = $delivery; ExternalRunRoot = $fixtureRoot; RunId = $invalidRun; ArtifactRoot = (Join-Path $fixtureRoot "$invalidRun-artifacts"); BaseRevision = $head; RepositoryPath = $repository; ReviewMode = 'story_end_only'; TaskRefs = @(155,156); OccurredAtUtc = $invalidOccurredAt }
        $invalidResult = (& $finalizer @invalidParameters) | ConvertFrom-Json -Depth 100 -DateKind String
        $afterInvalidLedger = (Get-FileHash -LiteralPath $invalidLedger -Algorithm SHA256).Hash
        Assert-True ($invalidResult.reportState -eq 'unavailable' -and -not $invalidResult.prReadyEvent -and $beforeInvalidLedger -ceq $afterInvalidLedger -and -not (Test-Path -LiteralPath (Join-Path $fixtureRoot "$invalidRun-artifacts") -PathType Container)) "explicit finalizer timestamp '$invalidOccurredAt' is rejected without replacement, ledger append, or report publication"
    }

    $ledger = Start-Run 'complete'
    # Two overlapping implementation phases: sum=15 min, union=10 min.
    foreach ($task in @(155,156)) {
        $startUtc = if ($task -eq 155) { '2026-10-10T04:01:00Z' } else { '2026-10-10T04:06:00Z' }
        $null = Record-Transition (New-PerformanceEvent -RunId complete -EventId "impl-$task-start" -EventType implementation_started -OccurredAtUtc $startUtc -ReviewMode story_end_only -Scope task -TaskRef $task -PhaseId "impl-$task" -Role implementer)
        $endUtc = if ($task -eq 155) { '2026-10-10T04:11:00Z' } else { '2026-10-10T04:11:00Z' }
        $closed = Record-Transition (New-PerformanceEvent -RunId complete -EventId "impl-$task-ready" -EventType task_ready_for_review -OccurredAtUtc $endUtc -ReviewMode story_end_only -Scope task -TaskRef $task -PhaseId "impl-$task" -Role implementer -Revision $head)
        Assert-True ($closed.telemetryState -eq 'verified') 'matching implementation boundaries are verified'
    }
    foreach ($boundary in @('wait_started','wait_ended')) {
        $utc = if ($boundary -eq 'wait_started') { '2026-10-10T04:07:00Z' } else { '2026-10-10T04:09:00Z' }
        $event = New-PerformanceEvent -RunId complete -EventId $boundary -EventType $boundary -OccurredAtUtc $utc -ReviewMode story_end_only
        $event.waitId = 'observed-quota'; $event.waitKind = 'quota_blocked'
        $null = Record-Transition $event
    }
    # Final-story findings followed by valid correction; review fields stay null.
    foreach ($boundary in @('final_review_started','review_findings')) {
        $event = New-PerformanceEvent -RunId complete -EventId $boundary -EventType $boundary -OccurredAtUtc '2026-10-10T04:12:00Z' -ReviewMode story_end_only -Scope final_story -PhaseId final-review -Role reviewer -ReviewRequestId request-1 -ReviewAttemptId attempt-1 -ReviewKind final_story -ReviewAttemptOrdinal 1 -Revision $head
        $null = Record-Transition $event
    }
    $correction = New-PerformanceEvent -RunId complete -EventId correction-start -EventType correction_started -OccurredAtUtc '2026-10-10T04:13:00Z' -ReviewMode story_end_only -Scope final_story -PhaseId correction-1 -Role implementer
    $correction.correctionId = 'correction-1'; $correction.supersedesReviewAttemptId = 'attempt-1'
    $bad = [ordered]@{}; foreach ($key in $correction.Keys) { $bad[$key] = $correction[$key] }
    $bad.eventId = 'invalid-correction'; $bad.transitionId = $bad.eventId; $bad.reviewAttemptId = 'attempt-1'
    $length = (Get-Item -LiteralPath $ledger).Length
    $rejected = Record-Transition $bad
    Assert-True ($rejected.status -eq 'unavailable' -and (Get-Item -LiteralPath $ledger).Length -eq $length) 'invalid correction review identity is rejected before immutable recording'
    $valid = Record-Transition $correction
    Assert-True ($valid.telemetryState -eq 'verified') 'correction linkage is valid at its lifecycle transition'
    $correction.eventType = 'correction_ready'; $correction.eventId = 'correction-end'; $correction.transitionId = $correction.eventId
    $correction.occurredAtUtc = '2026-10-10T04:14:00Z'; $correction.revision = $head
    $null = Record-Transition $correction
    foreach ($boundary in @('final_review_started','final_review_accepted')) {
        $event = New-PerformanceEvent -RunId complete -EventId "$boundary-2" -EventType $boundary -OccurredAtUtc '2026-10-10T04:15:00Z' -ReviewMode story_end_only -Scope final_story -PhaseId final-review-2 -Role reviewer -ReviewRequestId request-2 -ReviewAttemptId attempt-2 -ReviewKind final_story_rereview -ReviewAttemptOrdinal 1 -Revision $head
        $null = Record-Transition $event
    }
    $rows = @()
    foreach ($role in @('coordinator','implementer','reviewer')) {
        $session = "$role-local-session"
        $path = Join-Path $fixtureRoot "$role.jsonl"
        $lines = @(([ordered]@{ type = 'session_meta'; payload = @{ id = $session } } | ConvertTo-Json -Compress))
        foreach ($sample in @(@{ time = '2026-10-10T04:00:00Z'; input = 100; output = 20 }, @{ time = '2026-10-10T04:20:00Z'; input = 160; output = 40 })) {
            $lines += ([ordered]@{ timestamp = $sample.time; type = 'event_msg'; payload = @{ type = 'token_count'; info = @{ total_token_usage = @{ input_tokens = $sample.input; cached_input_tokens = 0; output_tokens = $sample.output; reasoning_output_tokens = 0; total_tokens = $sample.input + $sample.output } } } } | ConvertTo-Json -Depth 20 -Compress)
        }
        [IO.File]::WriteAllLines($path, $lines, $encoding)
        $rows += @{ role = $role; scope = 'story-144'; sessionId = $session; sourcePath = $path }
    }
    $evidence = Join-Path $fixtureRoot 'bound-sources.json'; Write-Json $evidence @{ rows = $rows }
    $setup = New-SyntheticSetupMetadata 'bound-init'
    foreach ($profile in $setup.profiles) { $profile.sessionId = "$($profile.role)-local-session" }
    $setupPath = Join-Path $fixtureRoot 'bound-setup.json'; Write-Json $setupPath $setup
    $initialization = New-PerformanceEvent -RunId bound-init -EventId bound-init-start -EventType story_started -OccurredAtUtc '2026-10-10T04:00:00Z' -ReviewMode story_end_only -SessionId 'coordinator-local-session'
    $boundInit = (& $transition -ExternalRunRoot $fixtureRoot -RunId bound-init -EventJson ($initialization | ConvertTo-Json -Depth 100 -Compress) -TaskRefs @(155,156) -MetadataPath $setupPath -ObservedEvidencePath $evidence) | ConvertFrom-Json -Depth 100
    Assert-True ($boundInit.status -eq 'appended' -and $boundInit.telemetryState -eq 'verified') "known setup/session identities are verified at initialization: $($boundInit.diagnostics -join '; ')"
    $outcomes = Join-Path $fixtureRoot 'outcomes.json'
    Write-Json $outcomes @{ schemaVersion = 1; kind = 'story_performance_task_outcomes'; runId = 'complete'; projectId = 12; storyId = 728; reviewedHead = $head; tasks = @(@{ taskRef = 155; accepted = $false; isDone = $true; source = 'taiga_task_status'; observedAtUtc = '2026-10-10T04:19:00Z'; evidenceReference = 'synthetic-task-155-status' }, @{ taskRef = 156; accepted = $true; isDone = $false; source = 'task_acceptance'; observedAtUtc = '2026-10-10T04:19:00Z'; evidenceReference = 'synthetic-task-156-acceptance' }) }
    $finished = Finish-Run complete -Evidence $evidence -Outcomes $outcomes
    Assert-True ($finished.reportState -eq 'published') "production finalization publishes: $($finished.response)"
    $report = Get-Content -LiteralPath $finished.jsonPath -Raw | ConvertFrom-Json -Depth 100
    Assert-True ($report.provenance.collectionAttempt.status -eq 'measured' -and $report.metrics.observedTotalTokens.state -eq 'measured') 'collector output is automatically supplied before report publication'
    Assert-True ($report.metrics.tasksCompleted.state -eq 'measured' -and $report.metrics.tasksCompleted.value -eq 2 -and $report.metrics.firstPassAcceptanceRate.state -eq 'not_applicable') 'story_end_only counts authoritative task outcomes without task reviews'
    Assert-True ($report.metrics.implementationElapsed.value -eq 960000 -and $report.metrics.implementationWallClock.value -eq 660000) 'sum includes correction and overlap; implementation union counts overlap once'
    Assert-True ($report.metrics.quotaBlockedElapsed.value -eq 120000 -and $report.metrics.quotaAdjustedElapsed.value -eq 1080000 -and $report.metrics.activeExecutionElapsed.state -eq 'unavailable') 'only confirmed quota overlap is subtracted; active time remains unavailable'
    Assert-True (@($report.anomalies | Where-Object code -eq 'invalid_event').Count -eq 0) 'correction accepted by recorder is accepted by the aggregator'
    Assert-True ($finished.response.Contains('Markdown artifact:') -and $finished.response.Contains($head)) 'normal delivery includes PR, reviewed HEAD, summary and accessible JSON/Markdown links'
    $digest = (Get-FileHash -LiteralPath $finished.jsonPath).Hash
    $again = Finish-Run complete -Evidence (Join-Path $fixtureRoot 'missing-evidence.json')
    Assert-True ($again.reportId -ceq $finished.reportId -and $again.collectionAttempt.status -eq 'measured' -and (Get-FileHash -LiteralPath $finished.jsonPath).Hash -ceq $digest) 'same HEAD reconciles existing immutable report without replacing evidence or recollecting'
    $negativeOutcomes = Get-Content -LiteralPath $outcomes -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    foreach ($task in $negativeOutcomes.tasks) { $task.accepted = $false; $task.isDone = $false }
    Write-Json $outcomes $negativeOutcomes
    $negativeReport = (& $aggregator -EventsPath $ledger -ReviewedHead $head -TaskRefs @(155,156) -TaskOutcomePath $outcomes) | ConvertFrom-Json -Depth 100
    Assert-True ($negativeReport.metrics.tasksCompleted.state -eq 'measured' -and $negativeReport.metrics.tasksCompleted.value -eq 0) 'authoritative non-Done outcomes measure zero rather than implying unavailable task evidence'
    $negativeOutcomes.reviewedHead = 'b' * 40; Write-Json $outcomes $negativeOutcomes
    $invalidOutcomeReport = (& $aggregator -EventsPath $ledger -ReviewedHead $head -TaskRefs @(155,156) -TaskOutcomePath $outcomes) | ConvertFrom-Json -Depth 100
    Assert-True ($invalidOutcomeReport.metrics.tasksCompleted.state -eq 'unavailable' -and @($invalidOutcomeReport.anomalies | Where-Object code -eq 'invalid_task_outcomes').Count -eq 1) 'stale task outcomes never inherit final-story approval or count as individual acceptance'

    $missingLedger = Start-Run missing -Mode per_task
    $ready = New-PerformanceEvent -RunId missing -EventId missing-ready -EventType task_ready_for_review -OccurredAtUtc '2026-10-10T04:04:00Z' -Scope task -TaskRef 155 -PhaseId missing-start -Role implementer -Revision $head
    $diagnostic = Record-Transition $ready
    Assert-True ($diagnostic.status -eq 'appended' -and ($diagnostic.diagnostics -join ' ').Contains('matching implementation_started')) 'missing start is diagnosed immediately but valid ready observation is retained'
    $null = Record-Transition (New-PerformanceEvent -RunId missing -EventId open-start -EventType implementation_started -OccurredAtUtc '2026-10-10T04:06:00Z' -Scope task -TaskRef 156 -PhaseId missing-end -Role implementer)
    $orphan = Record-Transition (New-PerformanceEvent -RunId missing -EventId orphan-acceptance -EventType review_accepted -OccurredAtUtc '2026-10-10T04:08:00Z' -Scope task -TaskRef 155 -PhaseId orphan-review -Role reviewer -ReviewRequestId orphan-request -ReviewAttemptId orphan-attempt -ReviewKind initial_task -ReviewAttemptOrdinal 1 -Revision $head)
    Assert-True (($orphan.diagnostics -join '; ').Contains('matching review_started')) 'orphan review closure is diagnosed at the closure transition'
    $prematureFinal = Record-Transition (New-PerformanceEvent -RunId missing -EventId premature-final -EventType final_review_started -OccurredAtUtc '2026-10-10T04:09:00Z' -Scope final_story -PhaseId premature-final -Role reviewer -ReviewRequestId premature-request -ReviewAttemptId premature-attempt -ReviewKind final_story -ReviewAttemptOrdinal 1 -Revision $head)
    Assert-True (($prematureFinal.diagnostics -join '; ').Contains('task #156 implementation-end')) 'missing implementation end is detected at the existing final-review transition'
    $partial = Finish-Run missing -Mode per_task
    Assert-True ($partial.reportState -eq 'published') "incomplete lifecycle still publishes: $($partial.response)"
    $partialReport = Get-Content -LiteralPath $partial.jsonPath -Raw | ConvertFrom-Json -Depth 100
    Assert-True ($partial.reportState -eq 'published' -and $partial.collectionAttempt.status -eq 'source_unavailable' -and $partial.collectionAttempt.discoveryAttempted -and -not $partial.collectionAttempt.collectorInvoked -and $null -eq $partialReport.metrics.implementationElapsed.value) 'absent bindings are discovered; incomplete timing is not fabricated; delivery still publishes'
    $standalone = (& $aggregator -EventsPath $missingLedger -TaskRefs @(155,156)) | ConvertFrom-Json -Depth 100
    Assert-True ($standalone.provenance.collectionAttempt.status -eq 'skipped') 'bypassing mandatory finalization exposes skipped collection separately'

    $null = Start-Run 'collector-failed'
    $failed = Finish-Run 'collector-failed' -Evidence $evidence -Collector (Join-Path $fixtureRoot 'missing-collector.ps1')
    Assert-True ($failed.deliveryState -eq 'confirmed' -and $failed.reportState -eq 'published' -and $failed.collectionAttempt.status -eq 'failed' -and $failed.collectionAttempt.collectorInvoked) 'collector failure is distinguished and never invalidates confirmed delivery'
    $failedReport = Get-Content -LiteralPath $failed.jsonPath -Raw | ConvertFrom-Json -Depth 100
    Assert-True ($failedReport.metrics.tasksCompleted.state -eq 'unavailable') 'absent task review in story_end_only does not mean incomplete tasks'
    $null = Start-Run 'invalid-setup'
    $invalidSetup = (& $finalizer -Delivery $delivery -ExternalRunRoot $fixtureRoot -RunId invalid-setup -ArtifactRoot (Join-Path $fixtureRoot 'invalid-setup-artifacts') -BaseRevision $head -RepositoryPath $repository -ReviewMode story_end_only -TaskRefs @(155,156) -MetadataPath (Join-Path $fixtureRoot 'missing-setup.json') -OccurredAtUtc '2026-10-10T04:20:00Z') | ConvertFrom-Json -Depth 100
    Assert-True ($invalidSetup.reportState -eq 'published' -and $invalidSetup.metricCoverage.modelsAndReasoning -eq 'unavailable' -and ($invalidSetup.limitations -join '; ').Contains('setup metadata was invalid')) 'invalid optional setup evidence is diagnosed before publication and still yields a limited report'

    $null = Start-Run 'invalid-session'
    Write-Json (Join-Path $fixtureRoot 'wrong-binding.json') @{ rows = @(@{ role = 'implementer'; sessionId = 'wrong-session'; scope = 'story-144'; sourcePath = $rows[0].sourcePath }) }
    $invalid = Finish-Run 'invalid-session' -Evidence (Join-Path $fixtureRoot 'wrong-binding.json')
    $invalidReport = Get-Content -LiteralPath $invalid.jsonPath -Raw | ConvertFrom-Json -Depth 100
    Assert-True ($invalid.collectionAttempt.status -eq 'source_unavailable' -and $null -eq $invalidReport.metrics.observedTotalTokens.value) 'unverified local session counters cannot be attributed'
    $null = Start-Run 'partial-roles'
    Write-Json (Join-Path $fixtureRoot 'one-role.json') @{ rows = @($rows[0]) }
    $oneRole = Finish-Run 'partial-roles' -Evidence (Join-Path $fixtureRoot 'one-role.json')
    Assert-True ($oneRole.collectionAttempt.status -eq 'partial') 'successful collection with missing roles reports partial coverage'

    $null = Start-Run 'open-quota'
    $openWait = New-PerformanceEvent -RunId open-quota -EventId open-quota-wait-start -EventType wait_started -OccurredAtUtc '2026-10-10T04:07:00Z' -ReviewMode story_end_only
    $openWait.waitId = 'quota'; $openWait.waitKind = 'quota_blocked'; $null = Record-Transition $openWait
    $openQuota = Finish-Run open-quota
    $openReport = Get-Content -LiteralPath $openQuota.jsonPath -Raw | ConvertFrom-Json -Depth 100
    Assert-True ($openReport.metrics.quotaBlockedElapsed.state -eq 'partial' -and $null -eq $openReport.metrics.quotaAdjustedElapsed.value) "incomplete quota boundaries remain partial without inferred blocked duration: blocked=$($openReport.metrics.quotaBlockedElapsed.state); adjusted=$($openReport.metrics.quotaAdjustedElapsed.value); waits=$($openReport.waits | ConvertTo-Json -Compress); response=$($openQuota.response)"
    $receiptsPath = Join-Path $fixtureRoot 'epic-receipts.json'
    Write-Json $receiptsPath @($finished)
    $index = (& (Join-Path $PSScriptRoot 'get-epic-performance-index.ps1') -StoryRefs @(144,145) -StoryReportsPath $receiptsPath) | ConvertFrom-Json -Depth 100
    Assert-True ($index.items.Count -eq 2 -and $index.items[0].reportState -eq 'published' -and $index.items[1].reportState -eq 'unavailable' -and $index.markdown.Contains('[Markdown]')) 'epic index automatically includes published and missing story reports'
    $finished.artifactsAccessibleToUser = $false
    Write-Json $receiptsPath @($finished)
    $localIndex = (& (Join-Path $PSScriptRoot 'get-epic-performance-index.ps1') -StoryRefs @(144) -StoryReportsPath $receiptsPath) | ConvertFrom-Json -Depth 100
    Assert-True ($null -eq $localIndex.items[0].jsonReference -and -not $localIndex.markdown.Contains('[JSON]')) 'local machine paths are not claimed to be accessible user artifacts'
    $deliveryPath = Join-Path $fixtureRoot 'delivery.json'; Write-Json $deliveryPath $delivery
    $fromFile = (& $finalizer -DeliveryPath $deliveryPath -ExternalRunRoot $fixtureRoot -RunId complete -ArtifactRoot (Join-Path $fixtureRoot 'complete-artifacts') -BaseRevision $head -RepositoryPath $repository -ReviewMode story_end_only -TaskRefs @(155,156)) | ConvertFrom-Json -Depth 100
    Assert-True ($fromFile.reportState -eq 'published' -and $fromFile.reportId -ceq $finished.reportId) 'documented receipt-file production entry point preserves exact-HEAD reuse'
    [IO.File]::AppendAllText($finished.jsonPath, ' ', $encoding)
    $corruptHash = (Get-FileHash -LiteralPath $finished.jsonPath).Hash
    $corrupt = Finish-Run complete
    Assert-True ($corrupt.reportState -eq 'unavailable' -and $corrupt.deliveryState -eq 'confirmed' -and (Get-FileHash -LiteralPath $finished.jsonPath).Hash -ceq $corruptHash) 'existing checksum conflicts are disclosed without overwriting artifacts or blocking confirmed PR delivery'
}
catch { throw "$($_.Exception.Message)`n$($_.ScriptStackTrace)" }
finally {
    # The verified target is this fixture's fresh unique directory under Temp.
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    Assert-True ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) 'fixture cleanup stays within Temp'
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'Passed issue #214 production finalization/transition regression cases.'
