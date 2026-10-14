# Finalize existing telemetry after confirmed exact-HEAD PR delivery. No provider writes.
[CmdletBinding(DefaultParameterSetName = 'Object')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Object')] [hashtable] $Delivery,
    [Parameter(Mandatory, ParameterSetName = 'File')] [string] $DeliveryPath,
    [Parameter(Mandatory)] [string] $ExternalRunRoot,
    [Parameter(Mandatory)] [string] $RunId,
    [Parameter(Mandatory)] [string] $ArtifactRoot,
    [Parameter(Mandatory)] [string] $BaseRevision,
    [Parameter(Mandatory)] [string] $RepositoryPath,
    [ValidateSet('per_task','story_end_only')] [string] $ReviewMode = 'per_task',
    [int[]] $TaskRefs = @(),
    [string] $MetadataPath,
    [string] $ObservedEvidencePath,
    [string] $TaskOutcomePath,
    [string] $Scope,
    [string] $OccurredAtUtc,
    [switch] $ArtifactsAccessibleToUser,
    [string] $RecorderPath = (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1'),
    [string] $AggregatorPath = (Join-Path $PSScriptRoot 'get-story-performance.ps1'),
    [string] $CollectorPath = (Join-Path $PSScriptRoot 'collect-role-token-usage.ps1')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'format-story-performance-utc.ps1')
if ([string]::IsNullOrWhiteSpace($OccurredAtUtc)) {
    $OccurredAtUtc = Format-StoryPerformanceUtcTimestamp -Timestamp ([DateTimeOffset]::UtcNow)
}
function Assert-True { param([bool] $Condition, [string] $Message) if (-not $Condition) { throw $Message } }
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

function New-RevisionBoundLedgerView {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $ReviewedHead,
        [Parameter(Mandatory)] [string] $ViewRoot
    )

    $records = @(Get-Content -LiteralPath $LedgerPath | ForEach-Object {
            $parsed = $_ | ConvertFrom-Json -Depth 100 -DateKind String
            if ([int] $parsed.schemaVersion -eq 2 -and [string] $parsed.kind -ceq 'story_performance_event_frame') { $parsed = $parsed.event }
            $parsed
        })
    $ready = @($records | Where-Object { $_.eventType -ceq 'pr_ready' -and $_.pullRequest.reviewedHead -ceq $ReviewedHead })
    Assert-True ($ready.Count -eq 1) 'revision-bound view requires exactly one selected pr_ready'
    $readyTime = [DateTimeOffset]::Parse($ready[0].occurredAtUtc)
    $selected = @($records | Where-Object {
        [DateTimeOffset]::Parse($_.occurredAtUtc) -le $readyTime -and (
        [string]$_.eventType -ne 'pr_ready' -or
        [string]$_.pullRequest.reviewedHead -eq $ReviewedHead)
    })
    Assert-True (@($selected | Where-Object { [string]$_.eventType -eq 'pr_ready' }).Count -eq 1) "revision-bound view must select exactly one pr_ready event for $ReviewedHead"
    [IO.Directory]::CreateDirectory($ViewRoot) | Out-Null
    $viewPath = Join-Path $ViewRoot "events-$ReviewedHead.jsonl"
    $lines = @($selected | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 100 })
    [IO.File]::WriteAllLines($viewPath, $lines, [Text.UTF8Encoding]::new($false))
    $viewPath
}

function Resolve-PublishedReportArtifacts {
    param(
        [Parameter(Mandatory)] [string] $ArtifactRoot,
        [Parameter(Mandatory)] [string] $ReportId
    )

    $matches = @()
    foreach ($manifestPath in @(Get-ChildItem -LiteralPath $ArtifactRoot -File -Filter '*.complete.json')) {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath.FullName | ConvertFrom-Json -Depth 100
        if ([string]$manifest.reportId -eq $ReportId) {
            $matches += [pscustomobject]@{ path = $manifestPath.FullName; manifest = $manifest }
        }
    }
    Assert-True ($matches.Count -eq 1) "report identity must resolve to exactly one completion manifest: $ReportId"
    $jsonEntries = @($matches[0].manifest.artifacts | Where-Object { [string]$_.kind -eq 'json' })
    Assert-True ($jsonEntries.Count -eq 1 -and (Test-Path -LiteralPath $jsonEntries[0].path -PathType Leaf)) "report identity must resolve to one published JSON artifact: $ReportId"
    Assert-True (@($matches[0].manifest.artifacts | Where-Object kind -eq 'markdown').Count -eq 1) 'report requires a Markdown sibling'
    foreach ($entry in @($matches[0].manifest.artifacts)) {
        Assert-True ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ieq $entry.sha256) 'report_artifact_conflict: published checksum mismatch'
    }
    [ordered]@{
        jsonPath = [string]$jsonEntries[0].path
        markdownPath = [string](@($matches[0].manifest.artifacts | Where-Object kind -eq 'markdown')[0].path)
        manifestPath = $matches[0].path
    }
}

function Invoke-Finalization {
    if ($DeliveryPath) { $Delivery = Get-Content -LiteralPath $DeliveryPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100 }
    $pr = if ($Delivery.ContainsKey('pr')) { $Delivery.pr } else { $null }
    $receipt = if ($Delivery.ContainsKey('receipt') -and $Delivery.receipt -is [hashtable]) { $Delivery.receipt } else { $null }
    $preflight = if ($null -ne $receipt) { Test-DeliveryPreflight -Receipt $receipt } else { 'missing_preflight' }
    $confirmed = $Delivery.providerConfirmed -eq $true -and
        $Delivery.state -in @('created', 'reused') -and
        $null -ne $receipt -and
        $preflight -eq 'ready' -and
        [string]$Delivery.repository -eq [string]$receipt.repository -and
        [string]$Delivery.storyBranch -eq [string]$receipt.storyBranch -and
        [string]$Delivery.prBase -eq [string]$receipt.prBase -and
        [string]$Delivery.reviewedHead -eq [string]$receipt.approvedHead -and
        [string]$Delivery.reviewedHead -eq [string]$receipt.branchHead -and
        [string]$Delivery.reviewedHead -eq [string]$receipt.checksHead -and
        [string]$Delivery.reviewedHead -eq [string]$receipt.finalStoryReviewHead -and
        $null -ne $pr -and
        [string]$pr.repository -eq [string]$receipt.repository -and
        [string]$pr.headBranch -eq [string]$receipt.storyBranch -and
        [string]$pr.head -eq [string]$receipt.branchHead -and
        [string]$pr.base -eq [string]$receipt.prBase -and
        [string]$pr.state -eq 'open' -and
        $pr.isClosed -eq $false
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

    $result = [ordered]@{
        deliveryState = 'confirmed'; reportState = 'unavailable'; prReadyEvent = $false
        reportId = $null; jsonPath = $null; markdownPath = $null; manifestPath = $null
        storyRef = $null; projectId = $null; storyId = $null; prUrl = $pr.url; reviewedHead = $Delivery.reviewedHead
        artifactsAccessibleToUser = [bool] $ArtifactsAccessibleToUser
        collectionAttempt = $null; metricCoverage = $null; limitations = @(); response = $null
    }
    $temporaryPaths = @()
    $viewRoot = $null
    try {
        if ($BaseRevision -cne $receipt.reviewBaseSha) { throw 'report base differs from the confirmed review preflight' }
        if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $RunId -in @('.', '..')) { throw 'invalid run identity' }
        $ledgerPath = Join-Path (Join-Path $ExternalRunRoot $RunId) 'events.jsonl'
        $records = @(Get-Content -LiteralPath $ledgerPath | ForEach-Object {
            $record = $_ | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String
            if ($record.kind -ceq 'story_performance_event_frame') { $record.event } else { $record }
        })
        $starts = @($records | Where-Object eventType -eq 'story_started')
        if ($starts.Count -ne 1 -or $starts[0].runId -cne $RunId -or $starts[0].reviewMode -cne $ReviewMode) { throw 'story initialization is missing, ambiguous, or mismatched' }
        $start = $starts[0]
        $result.storyRef = $start.storyRef; $result.projectId = $start.projectId; $result.storyId = $start.storyId
        # Derive PR identity from the confirmed provider record, never this repository.
        $prUri = [Uri] $pr.url
        $parts = $prUri.AbsolutePath.Trim('/').Split('/')
        if ($prUri.Scheme -ne 'https' -or $parts.Count -ne 4 -or $parts[2] -cne 'pull' -or [int] $parts[3] -ne [int] $pr.number) { throw 'invalid confirmed GitHub PR URL' }
        $identity = [ordered]@{ provider = 'github'; owner = $parts[0]; repository = $parts[1]; number = [int] $pr.number; reviewedHead = [string] $Delivery.reviewedHead }
        $existing = @($records | Where-Object { $_.eventType -ceq 'pr_ready' -and $_.revision -ceq $Delivery.reviewedHead })
        if ($existing.Count -gt 1) { throw 'ambiguous pr_ready evidence' }
        if ($existing.Count -eq 1) {
            $ready = $existing[0]
            foreach ($key in $identity.Keys) { if ($ready.pullRequest[$key] -cne $identity[$key]) { throw 'pr_ready identity conflict' } }
        }
        else {
            $ready = [ordered]@{}
            foreach ($key in $start.Keys) { $ready[$key] = $start[$key] }
            $ready.eventId = "$RunId/pr-ready-$($pr.number)-$($Delivery.reviewedHead)"
            $ready.transitionId = $ready.eventId
            $ready.eventType = 'pr_ready'; $ready.occurredAtUtc = $OccurredAtUtc
            $ready.revision = [string] $Delivery.reviewedHead; $ready.pullRequest = $identity
            $ready.usage = $null
            $ready.provenance = [ordered]@{ source = 'confirmed_pr_delivery'; observedBy = 'finalize-story-performance'; coverage = 'confirmed provider receipt and exact reviewed HEAD'; synthetic = [bool] $start.provenance.synthetic }
        }
        $recordOutput = @(& pwsh -NoProfile -File $RecorderPath -ExternalRunRoot $ExternalRunRoot -RunId $RunId -EventJson ($ready | ConvertTo-Json -Compress -Depth 100) 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'recorder failure; no confirmed pr_ready recording' }
        $recordResult = ($recordOutput -join "`n") | ConvertFrom-Json
        if ($recordResult.status -notin @('appended', 'noop')) { throw 'recorder failure or unknown recording outcome' }
        $result.prReadyEvent = $true
        # Reconcile immutable exact-HEAD artifacts before collecting new evidence.
        $priorReports = @()
        if (Test-Path -LiteralPath $ArtifactRoot -PathType Container) {
            foreach ($manifestFile in @(Get-ChildItem -LiteralPath $ArtifactRoot -Filter '*.complete.json' -File)) {
                $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json -Depth 100
                $jsonEntry = @($manifest.artifacts | Where-Object kind -eq 'json')
                if ($jsonEntry.Count -ne 1) { continue }
                $candidate = Get-Content -LiteralPath $jsonEntry[0].path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
                if ($candidate.runId -ceq $RunId -and $candidate.projectId -eq $start.projectId -and $candidate.storyId -eq $start.storyId -and
                    $candidate.pullRequest.reviewedHead -ceq $Delivery.reviewedHead -and $candidate.pullRequest.owner -ceq $identity.owner -and
                    $candidate.pullRequest.repository -ceq $identity.repository -and $candidate.pullRequest.number -eq $identity.number) {
                    if ($candidate.reportId -cne $manifest.reportId) { throw 'report_artifact_conflict: manifest identity mismatch' }
                    $priorReports += $candidate
                }
            }
        }
        if ($priorReports.Count -gt 1) { throw 'report_artifact_conflict: duplicate immutable report identity' }
        if ($priorReports.Count -eq 1) {
            $report = $priorReports[0]
            if ($report.reviewMode -cne $ReviewMode -or $report.comparison.baseRevision -cne $BaseRevision -or
                (@($report.coverage.taskSet.declaredTaskRefs) -join ',') -cne (@($TaskRefs) -join ',')) { throw 'report_artifact_conflict: authorized scope/base differs from published report' }
        }
        else {
            $viewRoot = Join-Path $ExternalRunRoot ('finalization-' + [guid]::NewGuid().ToString('N'))
            $eventsView = New-RevisionBoundLedgerView -LedgerPath $ledgerPath -ReviewedHead $Delivery.reviewedHead -ViewRoot $viewRoot
            $temporaryPaths += $eventsView
            $attempt = [ordered]@{
                schemaVersion = 1; kind = 'story_performance_collection_attempt'; runId = $RunId
                projectId = $start.projectId; storyId = $start.storyId; reviewedHead = $Delivery.reviewedHead
                discoveryAttempted = $true; collectorInvoked = $false; status = 'source_unavailable'; reason = $null
            }
            if ([string]::IsNullOrWhiteSpace($ObservedEvidencePath)) {
                $ObservedEvidencePath = Join-Path (Join-Path $ExternalRunRoot $RunId) 'observed-role-token-usage.json'
            }
            $usagePath = Join-Path $viewRoot 'usage.json'
            if (-not (Test-Path -LiteralPath $ObservedEvidencePath -PathType Leaf)) {
                $attempt.reason = 'observed role/session/source bindings unavailable; no trustworthy collector source selected'
            }
            else {
                try {
                    $attempt.collectorInvoked = $true
                    $collectorParameters = @{ ObservedEvidencePath = $ObservedEvidencePath; EventsPath = $eventsView; StatePath = (Join-Path $viewRoot 'cursor.json'); OutputPath = $usagePath }
                    if (-not [string]::IsNullOrWhiteSpace($Scope)) { $collectorParameters.Scope = $Scope }
                    $null = & $CollectorPath @collectorParameters
                    $usage = Get-Content -LiteralPath $usagePath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
                    if ($usage.kind -cne 'story_performance_role_token_usage' -or $usage.runId -cne $RunId -or $usage.projectId -ne $start.projectId -or $usage.storyId -ne $start.storyId) { throw 'invalid collector output identity' }
                    $attempt.status = if ($usage.coverage -eq 'unavailable') { 'source_unavailable' } elseif ($usage.coverage -eq 'measured' -and @($usage.roleTotals.PSObject.Properties).Count -eq 3) { 'measured' } else { 'partial' }
                    $attempt.reason = "collector coverage=$($usage.coverage); missing sessions, sources, or boundary counters remain unavailable"
                }
                catch {
                    $attempt.status = 'failed'; $attempt.reason = 'collector execution or output validation failed; attributable token totals unavailable'
                    $usagePath = $null
                }
            }
            $result.collectionAttempt = $attempt
            $attemptPath = Join-Path $viewRoot 'collection-attempt.json'
            [IO.File]::WriteAllText($attemptPath, ($attempt | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
            $temporaryPaths += @($attemptPath, (Join-Path $viewRoot 'usage.json'), (Join-Path $viewRoot 'cursor.json'))
            $parameters = @{ EventsPath = $eventsView; ReviewMode = $ReviewMode; TaskRefs = $TaskRefs; ReviewedHead = $Delivery.reviewedHead; BaseRevision = $BaseRevision; RepositoryPath = $RepositoryPath; CollectionAttemptPath = $attemptPath; ArtifactDirectory = $ArtifactRoot }
            if (-not [string]::IsNullOrWhiteSpace($MetadataPath)) { $parameters.MetadataPath = $MetadataPath }
            if (-not [string]::IsNullOrWhiteSpace($TaskOutcomePath)) { $parameters.TaskOutcomePath = $TaskOutcomePath }
            if ($attempt.collectorInvoked -and $null -ne $usagePath) { $parameters.UsageMetadataPath = $usagePath }
            try {
                $report = (& $AggregatorPath @parameters) | ConvertFrom-Json -Depth 100 -DateKind String
            }
            catch {
                # Setup validation happens before publication. Invalid optional setup
                # evidence must not prevent a limited report for a confirmed PR.
                if (-not $parameters.ContainsKey('MetadataPath') -or $_.Exception.Message -notlike 'setup_metadata_*') { throw }
                $parameters.Remove('MetadataPath')
                $attempt.setupMetadataLimitation = 'supplied setup metadata was invalid or unavailable; model/reasoning provenance is unavailable'
                [IO.File]::WriteAllText($attemptPath, ($attempt | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
                $report = (& $AggregatorPath @parameters) | ConvertFrom-Json -Depth 100 -DateKind String
            }
        }
        $artifacts = Resolve-PublishedReportArtifacts -ArtifactRoot $ArtifactRoot -ReportId $report.reportId
        $result.reportState = 'published'; $result.reportId = $report.reportId
        $result.jsonPath = $artifacts.jsonPath; $result.markdownPath = $artifacts.markdownPath; $result.manifestPath = $artifacts.manifestPath
        $result.collectionAttempt = if ($report.provenance.PSObject.Properties['collectionAttempt']) { $report.provenance.collectionAttempt } else { [ordered]@{ status = 'skipped'; reason = 'historical report has no collection-attempt evidence; preserved without overwrite' } }
        $result.metricCoverage = [ordered]@{}
        foreach ($metric in $report.metrics.PSObject.Properties) { $result.metricCoverage[$metric.Name] = $metric.Value.state }
        $result.limitations = @($report.provenance.limitations) + @($report.anomalies | ForEach-Object { "$($_.code): $($_.message)" })
        $refs = if ($ArtifactsAccessibleToUser) { "JSON artifact: [$($report.reportId)]($($result.jsonPath)); Markdown artifact: [report]($($result.markdownPath))" } else { 'JSON artifact: published locally; JSON/Markdown user access must be established before delivery' }
        $summaryLimitations = @($result.limitations | Where-Object { $_ -notlike 'Unknown values*' -and $_ -notlike 'Implementation/review elapsed*' } | Select-Object -First 3)
        $result.response = "PR ready for approval: $($pr.url); reviewed HEAD=$($Delivery.reviewedHead); performance report: published; timeToPr=$($report.metrics.timeToPr.state); implementation=$($report.metrics.implementationElapsed.state); tokens=$($report.metrics.observedTotalTokens.state); collection=$($result.collectionAttempt.status); limitations=$($summaryLimitations -join '; '); $refs"
    }
    catch {
        $result.limitations = @($_.Exception.Message)
        $result.response = "PR ready for approval: $($pr.url); reviewed HEAD=$($Delivery.reviewedHead); performance report unavailable/limited: $($_.Exception.Message)"
    }
    finally {
        foreach ($path in $temporaryPaths) { if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force } }
        if ($temporaryPaths.Count -gt 0 -and (Test-Path -LiteralPath $viewRoot -PathType Container)) { Remove-Item -LiteralPath $viewRoot -ErrorAction SilentlyContinue }
    }
    return $result
}
try { Invoke-Finalization | ConvertTo-Json -Depth 100 }
catch {
    [ordered]@{
        deliveryState = 'reconcile'; reportState = 'not_attempted'; prReadyEvent = $false
        reportId = $null; jsonPath = $null; markdownPath = $null; manifestPath = $null
        collectionAttempt = $null; metricCoverage = $null
        limitations = @('confirmed delivery/preflight input could not be read or validated')
        response = 'PR delivery evidence requires reconciliation; performance finalization unavailable/limited.'
    } | ConvertTo-Json -Depth 100
}
