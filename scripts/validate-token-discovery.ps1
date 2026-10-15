# Offline portable regression; optional local real-source smoke emits counters only.
# RealSourcePaths: one coordinator source, or coordinator/implementer/reviewer in that order.
[CmdletBinding()]
param([string[]] $RealSourcePaths = @(), [string] $ArtifactRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Write-Json([string] $Path, [object] $Value) { [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false)) }
$root = Join-Path ([IO.Path]::GetTempPath()) ('taiga-token-225-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop') -Destination $root -Recurse
$runtime = Join-Path $root 'taiga-story-loop/scripts'
$store = Join-Path $root 'codex'
[IO.Directory]::CreateDirectory((Join-Path $store 'sessions')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $store 'archived_sessions')) | Out-Null
. (Join-Path $runtime 'new-story-performance-event.ps1')
$runDirectory = Join-Path $root 'runs/test'
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
$ledger = Join-Path $runDirectory 'events.jsonl'
$common = @{ ProjectId = 12; StoryId = 457; StoryRef = 225; RunId = 'test'; ReviewMode = 'per_task'; Provenance = @{ source = 'synthetic_fixture'; observedBy = 'regression'; coverage = 'fixed timestamps with real Codex record shape'; synthetic = $false } }
$events = [Collections.Generic.List[object]]::new()
function Event([hashtable] $Parameters) { $events.Add((New-StoryPerformanceEvent @common @Parameters)) }
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sha = (& git -C $repository rev-parse HEAD).Trim()
Event @{ EventId = 'story-start'; EventType = 'story_started'; OccurredAtUtc = '2026-10-14T10:00:00Z'; Scope = 'story'; Role = 'coordinator'; WorkerId = 'coord'; SessionId = 'coord' }
$implementation = @{ Scope = 'task'; Role = 'implementer'; WorkerId = 'impl'; SessionId = 'impl'; TaskRef = 1; PhaseId = 'task-1' }
Event ($implementation + @{ EventId = 'impl-start'; EventType = 'implementation_started'; OccurredAtUtc = '2026-10-14T10:01:00Z' })
Event ($implementation + @{ EventId = 'impl-end'; EventType = 'task_ready_for_review'; OccurredAtUtc = '2026-10-14T10:04:00Z'; Revision = $sha })
$review = @{ Scope = 'task'; Role = 'reviewer'; WorkerId = 'review'; SessionId = 'review'; TaskRef = 1; PhaseId = 'review-1'; ReviewRequestId = 'request-1'; ReviewAttemptId = 'attempt-1'; ReviewKind = 'initial_task'; ReviewAttemptOrdinal = 1; Revision = $sha }
Event ($review + @{ EventId = 'review-start'; EventType = 'review_started'; OccurredAtUtc = '2026-10-14T10:05:00Z' })
Event ($review + @{ EventId = 'review-end'; EventType = 'review_findings'; OccurredAtUtc = '2026-10-14T10:08:00Z' })
$correction = @{ Scope = 'task'; Role = 'implementer'; WorkerId = 'impl'; SessionId = 'impl'; TaskRef = 1; PhaseId = 'fix-1'; CorrectionId = 'correction-1'; SupersedesReviewAttemptId = 'attempt-1' }
Event ($correction + @{ EventId = 'fix-start'; EventType = 'correction_started'; OccurredAtUtc = '2026-10-14T10:09:00Z' })
Event ($correction + @{ EventId = 'fix-end'; EventType = 'correction_ready'; OccurredAtUtc = '2026-10-14T10:12:00Z'; Revision = $sha })
$rereview = @{ Scope = 'task'; Role = 'reviewer'; WorkerId = 'review'; SessionId = 'review'; TaskRef = 1; PhaseId = 'rereview-1'; ReviewRequestId = 'request-1'; ReviewAttemptId = 'attempt-2'; ReviewKind = 'correction_rereview'; ReviewAttemptOrdinal = 2; Revision = $sha }
Event ($rereview + @{ EventId = 'rereview-start'; EventType = 'review_started'; OccurredAtUtc = '2026-10-14T10:13:00Z' })
Event ($rereview + @{ EventId = 'rereview-end'; EventType = 'review_accepted'; OccurredAtUtc = '2026-10-14T10:16:00Z' })
$finalReview = @{ Scope = 'final_story'; Role = 'reviewer'; WorkerId = 'review'; SessionId = 'review'; PhaseId = 'final'; ReviewRequestId = 'final-request'; ReviewAttemptId = 'final-attempt'; ReviewKind = 'final_story'; ReviewAttemptOrdinal = 1; Revision = $sha }
Event ($finalReview + @{ EventId = 'final-start'; EventType = 'final_review_started'; OccurredAtUtc = '2026-10-14T10:17:00Z' })
Event ($finalReview + @{ EventId = 'final-end'; EventType = 'final_review_accepted'; OccurredAtUtc = '2026-10-14T10:20:00Z' })
$wait = @{ Scope = 'story'; Role = 'coordinator'; WorkerId = 'coord'; SessionId = 'coord'; WaitId = 'wait-1'; WaitKind = 'worker_wait' }
Event ($wait + @{ EventId = 'wait-start'; EventType = 'wait_started'; OccurredAtUtc = '2026-10-14T10:21:00Z' })
Event ($wait + @{ EventId = 'wait-end'; EventType = 'wait_ended'; OccurredAtUtc = '2026-10-14T10:24:00Z' })
Event @{ EventId = 'ready'; EventType = 'pr_ready'; OccurredAtUtc = '2026-10-14T10:25:00Z'; Scope = 'story'; Role = 'coordinator'; WorkerId = 'coord'; SessionId = 'coord'; Revision = $sha; PullRequest = @{ provider = 'github'; owner = 'fixture'; repository = 'fixture'; number = 1; reviewedHead = $sha } }
[IO.File]::WriteAllLines($ledger, @($events | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress }))
function Source([string] $Id) {
    $path = Join-Path $store "sessions/rollout-test-$Id.jsonl"
    $records = @(@{ type = 'session_meta'; payload = @{ id = $Id } } | ConvertTo-Json -Compress)
    for ($minute = 0; $minute -le 25; $minute++) {
        $records += @{ timestamp = ('2026-10-14T10:{0:00}:10Z' -f $minute); type = 'event_msg'; payload = @{ type = 'token_count'; info = @{ total_token_usage = @{ input_tokens = 100 * $minute; cached_input_tokens = 20 * $minute; output_tokens = 10 * $minute; reasoning_output_tokens = 5 * $minute } } } } | ConvertTo-Json -Depth 10 -Compress
    }
    [IO.File]::WriteAllLines($path, $records)
    return $path
}
foreach ($id in @('coord','impl','review')) { $null = Source $id }
$profiles = @(@{ role = 'coordinator'; workerId = 'coord'; sessionId = 'coord'; model = 'actual-test-profile'; effort = 'high'; effectiveFromUtc = '2026-10-14T10:00:00Z' },
    @{ role = 'implementer'; workerId = 'impl'; sessionId = 'impl'; model = 'actual-test-profile'; effort = 'high'; effectiveFromUtc = '2026-10-14T10:00:00Z' },
    @{ role = 'reviewer'; workerId = 'review'; sessionId = 'review'; model = 'actual-test-profile'; effort = 'high'; effectiveFromUtc = '2026-10-14T10:00:00Z' })
# Worker identity is only accepted as a session candidate after header verification.
$profiles[1].sessionId = $null
$bindingPath = Join-Path $runDirectory 'observed-role-token-usage.json'
$binding = (& (Join-Path $runtime 'initialize-story-performance-roles.ps1') -ExternalRunRoot (Join-Path $root 'runs') -RunId test -ProjectId 12 -StoryId 457 -Profiles $profiles -CodexHome $store) | ConvertFrom-Json -Depth 100
Assert ($binding.rows.Count -eq 3) 'initialization must create all three verified bindings'
$setup = Get-Content (Join-Path $runDirectory 'setup-metadata.json') -Raw | ConvertFrom-Json
Assert ($null -ne $setup.provenance -and $setup.profiles.Count -eq 3) 'valid complete setup must be generated'
$usagePath = Join-Path $root 'usage.json'
$collector = Join-Path $runtime 'collect-role-token-usage.ps1'
$usage = (& $collector -ObservedEvidencePath $bindingPath -EventsPath $ledger -StatePath (Join-Path $root 'cursor.json') -OutputPath $usagePath) | ConvertFrom-Json -Depth 100
Assert ($usage.coverage -eq 'partial' -and $usage.roleTotals.implementer.inputTokens -eq 2400) 'asynchronous real-format counters must produce a partial delta'
$report = (& (Join-Path $runtime 'get-story-performance.ps1') -EventsPath $ledger -UsageMetadataPath $usagePath -TaskRefs @(1)) | ConvertFrom-Json -Depth 100
Assert ($report.metrics.observedImplementerTokens.value -eq 2640 -and $report.metrics.observedImplementerTokens.state -eq 'partial') 'partial role delta must remain visible without double counting'
Assert ($report.metrics.implementationTokens.knownSubtotal -eq 440) 'implementation and correction must each use separate inner sample windows'
Assert ($report.metrics.reviewTokens.knownSubtotal -eq 660) 'initial review, re-review, and final review must use separate sample windows'
Assert ($report.metrics.coordinationTokens.knownSubtotal -eq 220) 'explicit coordinator interval must use its own verified source'
Assert ($report.metrics.implementationTokens.evidence[0].state -eq 'partial') 'asynchronous phase samples must never be labeled exact'
# Metadata counters cannot become numeric authority by claiming verification.
$forgedSession = @($usage.sessions | Where-Object role -eq 'implementer')[0]
$forgedSession.sourceSamples[3].counters.inputTokens = 999999
Write-Json $usagePath $usage
$reread = (& (Join-Path $runtime 'get-story-performance.ps1') -EventsPath $ledger -UsageMetadataPath $usagePath -TaskRefs @(1)) | ConvertFrom-Json -Depth 100
Assert ($reread.metrics.implementationTokens.knownSubtotal -eq 440) 'reporter must re-read sources rather than trust supplied numbers'
# A normal finalization must recover a missing binding file and invoke collection.
$receipt = @{
    runKind = 'standalone'; repository = 'fixture'; storyBranch = 'codex/fixture'; expectedBranch = 'codex/fixture'
    expectedWorktree = $repository; featureBranch = ''; prBase = 'master'; reviewBaseSha = $sha; approvedHead = $sha; branchHead = $sha
    diffRange = "$sha..$sha"; sourceState = 'clean-tracked-source'; ignoredOutputsDeclared = $true; clean = $true
    checksPassed = $true; checksHead = $sha; finalStoryReviewAccepted = $true; finalStoryReviewHead = $sha
}
$delivery = @{
    state = 'created'; providerConfirmed = $true; receipt = $receipt; repository = 'fixture'; storyBranch = 'codex/fixture'; prBase = 'master'; reviewedHead = $sha
    pr = @{ url = 'https://github.com/fixture/fixture/pull/1'; number = 1; repository = 'fixture'; headBranch = 'codex/fixture'; base = 'master'; head = $sha; state = 'open'; isClosed = $false }
}
Remove-Item -LiteralPath $bindingPath
$previousCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = $store
    $final = (& (Join-Path $runtime 'finalize-story-performance.ps1') -Delivery $delivery -ExternalRunRoot (Join-Path $root 'runs') -RunId test -ArtifactRoot (Join-Path $root 'reports') -BaseRevision $sha -RepositoryPath $repository -TaskRefs @(1)) | ConvertFrom-Json -Depth 100
    Assert ($final.reportState -eq 'published') "finalizer must publish: $($final.limitations -join '; ')"
    Assert ($final.collectionAttempt.discoveryAttempted -and $final.collectionAttempt.collectorInvoked) 'finalizer must discover and collect without a binding file'
    $markdown = Get-Content -LiteralPath $final.markdownPath -Raw
    Assert ($markdown.Contains('Phase token coverage') -and $markdown.Contains('220')) 'published report must expose useful phase costs'
    $badSetup = (& (Join-Path $runtime 'finalize-story-performance.ps1') -Delivery $delivery -ExternalRunRoot (Join-Path $root 'runs') -RunId test -ArtifactRoot (Join-Path $root 'invalid-setup-reports') -BaseRevision $sha -RepositoryPath $repository -TaskRefs @(1) -MetadataPath (Join-Path $root 'missing-setup.json')) | ConvertFrom-Json -Depth 100
    Assert ($badSetup.reportState -eq 'published' -and ($badSetup.limitations -join '; ').Contains('setup metadata was invalid')) 'explicit invalid setup must produce a limited report with its diagnostic'
    $explicitPath = Join-Path $root 'selected-bindings.json'
    Copy-Item -LiteralPath $bindingPath -Destination $explicitPath
    $selectedDigest = (Get-FileHash -LiteralPath $explicitPath).Hash
    $env:CODEX_HOME = Join-Path $root 'unavailable-store'
    $explicit = (& (Join-Path $runtime 'finalize-story-performance.ps1') -Delivery $delivery -ExternalRunRoot (Join-Path $root 'runs') -RunId test -ArtifactRoot (Join-Path $root 'explicit-reports') -BaseRevision $sha -RepositoryPath $repository -TaskRefs @(1) -ObservedEvidencePath $explicitPath) | ConvertFrom-Json -Depth 100
    Assert ($explicit.reportState -eq 'published' -and $explicit.collectionAttempt.collectorInvoked -and (Get-FileHash -LiteralPath $explicitPath).Hash -eq $selectedDigest) 'explicit source bindings must be preserved when sources live outside Codex storage'


}
finally { $env:CODEX_HOME = $previousCodexHome }
# Exact samples, reset crossings, and insufficient coverage use the same production path.
$originalSources = @{}
foreach ($id in @('coord','impl','review')) {
    $path = Join-Path $store "sessions/rollout-test-$id.jsonl"
    $originalSources[$path] = [IO.File]::ReadAllText($path)
    [IO.File]::WriteAllText($path, $originalSources[$path].Replace(':10Z', ':00Z'))
}
$exactUsage = (& $collector -ObservedEvidencePath $bindingPath -EventsPath $ledger -StatePath (Join-Path $root 'exact-cursor.json') -OutputPath $usagePath) | ConvertFrom-Json -Depth 100
$exactReport = (& (Join-Path $runtime 'get-story-performance.ps1') -EventsPath $ledger -UsageMetadataPath $usagePath -TaskRefs @(1)) | ConvertFrom-Json -Depth 100
Assert ($exactReport.metrics.implementationTokens.state -eq 'measured' -and $exactReport.metrics.implementationTokens.value -eq 660) 'exact complete phase counters must remain measured'
foreach ($path in $originalSources.Keys) { [IO.File]::WriteAllText($path, $originalSources[$path]) }
$implPath = Join-Path $store 'sessions/rollout-test-impl.jsonl'
$resetLines = @(Get-Content -LiteralPath $implPath | ForEach-Object {
    $record = $_ | ConvertFrom-Json -Depth 30 -DateKind String
    if ($record.PSObject.Properties['timestamp'] -and $record.timestamp -eq '2026-10-14T10:02:10Z') {
        $record.payload.info.total_token_usage.input_tokens = 0
        $record.payload.info.total_token_usage.cached_input_tokens = 0
        $record.payload.info.total_token_usage.output_tokens = 0
        $record.payload.info.total_token_usage.reasoning_output_tokens = 0
    }
    $record | ConvertTo-Json -Compress -Depth 30
})
[IO.File]::WriteAllLines($implPath, $resetLines)
$null = & $collector -ObservedEvidencePath $bindingPath -EventsPath $ledger -StatePath (Join-Path $root 'reset-cursor.json') -OutputPath $usagePath
$resetReport = (& (Join-Path $runtime 'get-story-performance.ps1') -EventsPath $ledger -UsageMetadataPath $usagePath -TaskRefs @(1)) | ConvertFrom-Json -Depth 100
Assert ($resetReport.metrics.implementationTokens.evidence[0].state -eq 'unavailable') 'a phase crossing a counter reset must have no attributed delta'
[IO.File]::WriteAllText($implPath, $originalSources[$implPath])
$limited = @(Get-Content -LiteralPath $implPath | Where-Object { $_ -notmatch '10:0[23]:10Z' })
[IO.File]::WriteAllLines($implPath, $limited)
$null = & $collector -ObservedEvidencePath $bindingPath -EventsPath $ledger -StatePath (Join-Path $root 'limited-cursor.json') -OutputPath $usagePath
$limitedReport = (& (Join-Path $runtime 'get-story-performance.ps1') -EventsPath $ledger -UsageMetadataPath $usagePath -TaskRefs @(1)) | ConvertFrom-Json -Depth 100
Assert ($limitedReport.metrics.implementationTokens.evidence[0].state -eq 'unavailable') 'one inner sample cannot manufacture phase usage'
[IO.File]::WriteAllText($implPath, $originalSources[$implPath])
$resolve = Join-Path $runtime 'resolve-story-token-sources.ps1'
$bindings = @($profiles | ForEach-Object { @{ role = $_.role; scope = 'story'; workerId = $_.workerId; sessionId = $_.sessionId } })
Move-Item -LiteralPath (Join-Path $store 'sessions/rollout-test-impl.jsonl') -Destination (Join-Path $store 'archived_sessions/rollout-test-impl.jsonl')
$archived = (& $resolve -Bindings $bindings -OutputPath $bindingPath -CodexHome $store) | ConvertFrom-Json
Assert (@($archived.rows | Where-Object sourcePath -Like '*archived_sessions*').Count -eq 1) 'archived sources must be rediscovered'
Copy-Item -LiteralPath (Join-Path $store 'archived_sessions/rollout-test-impl.jsonl') -Destination (Join-Path $store 'sessions/rollout-copy-impl.jsonl')
$ambiguous = (& $resolve -Bindings $bindings -OutputPath $bindingPath -CodexHome $store) | ConvertFrom-Json
Assert ($ambiguous.rows.Count -eq 2 -and @($ambiguous.diagnostics | Where-Object category -eq 'binding_ambiguous').Count -eq 1) 'duplicate verified candidates must not be guessed'
[IO.File]::WriteAllText((Join-Path $store 'sessions/rollout-test-review.jsonl'), '{"type":"session_meta","payload":{"id":"wrong"}}' + "`n")
$mismatch = (& $resolve -Bindings $bindings -OutputPath $bindingPath -CodexHome $store) | ConvertFrom-Json
Assert ($mismatch.rows.Count -eq 1) 'mismatched embedded identity must not bind'
$lock = [IO.FileStream]::new((Join-Path $store 'sessions/rollout-test-coord.jsonl'), 'Open', 'ReadWrite', 'None')
try {
    $locked = (& $resolve -Bindings $bindings -OutputPath $bindingPath -CodexHome $store) | ConvertFrom-Json
    Assert (@($locked.diagnostics | Where-Object category -eq 'source_inaccessible').Count -eq 1) 'inaccessible source must be diagnosed'
}
finally { $lock.Dispose() }
$missing = (& $resolve -Bindings $bindings -OutputPath $bindingPath -CodexHome (Join-Path $root 'absent')) | ConvertFrom-Json
Assert ($missing.rows.Count -eq 0 -and $missing.diagnostics.Count -eq 3) 'missing sources must stay unavailable'
# Transition helper must reject duplicate semantic ends and orphan completions before append.
$duplicate = $events[2] | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$duplicate.eventId = 'another-completion'
$transition = Join-Path $runtime 'record-story-performance-transition.ps1'
$rejected = (& $transition -ExternalRunRoot (Join-Path $root 'runs') -RunId test -EventJson ($duplicate | ConvertTo-Json -Depth 100)) | ConvertFrom-Json
Assert ($rejected.status -eq 'unavailable' -and (Get-Content $ledger).Count -eq $events.Count) 'duplicate end must not corrupt ledger'
$duplicate.taskRef = 2; $duplicate.phaseId = 'orphan'
$rejected = (& $transition -ExternalRunRoot (Join-Path $root 'runs') -RunId test -EventJson ($duplicate | ConvertTo-Json -Depth 100)) | ConvertFrom-Json
Assert ($rejected.status -eq 'unavailable' -and (Get-Content $ledger).Count -eq $events.Count) 'missing start must not corrupt ledger'
if ($RealSourcePaths.Count) {
    if ($RealSourcePaths.Count -notin @(1,3)) { throw 'supply one coordinator source or all three ordered role sources' }
    $realRows = @()
    $realRoles = @('coordinator','implementer','reviewer')
    $sourceIndex = 0
    foreach ($path in $RealSourcePaths) {
        $reader = [IO.StreamReader]::new([IO.FileStream]::new($path, 'Open', 'Read', [IO.FileShare]::ReadWrite))
        try { $header = $reader.ReadLine() | ConvertFrom-Json -Depth 30 } finally { $reader.Dispose() }
        Assert ($header.type -eq 'session_meta') 'real source must have identity metadata'
        $realRows += @{ role = $realRoles[$sourceIndex]; scope = 'local-smoke'; workerId = $header.payload.id; sessionId = $header.payload.id; sourcePath = $path }
        $sourceIndex++
    }
    $destination = if ($ArtifactRoot) { $ArtifactRoot } else { Join-Path $root 'real-smoke' }
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    Write-Json (Join-Path $destination 'bindings.json') @{ rows = $realRows }
    $real = (& $collector -ObservedEvidencePath (Join-Path $destination 'bindings.json') -StatePath (Join-Path $destination 'cursor.json') -OutputPath (Join-Path $destination 'usage.json') -Scope local-smoke -SessionLifetime) | ConvertFrom-Json -Depth 100
    Assert ($null -ne $real.roleTotals.coordinator -and $real.roleTotals.coordinator.totalTokens -gt 0) 'real Codex counters must be consumed'
    if ($RealSourcePaths.Count -eq 3) {
        Assert ($null -ne $real.roleTotals.implementer -and $null -ne $real.roleTotals.reviewer) 'all three real role sources must yield counters'
    }
    Write-Output "PASS: real local Codex counter smoke; metadata-only artifact $destination"
}
Write-Output "PASS: portable source discovery, setup validation, partial role/phase deltas, numeric authority, archive, ambiguity, mismatch, missing sources, and lifecycle guards ($root)"
