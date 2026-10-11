# Synthetic validation for the task #149/#150 external event recorder.
# No network, Taiga, Git, browser, workflow state, or live data is used.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Performance-event assertion failed: $Message"
    }
}

function Invoke-Recorder {
    param(
        [Parameter(Mandatory)] [string] $Recorder,
        [Parameter(Mandatory)] [string] $ExternalRunRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $EventJson,
        [int] $LockTimeoutMilliseconds = -1,
        [int] $FaultAfterBytes = -1,
        [string] $LockReadyPath
    )

    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $arguments = @(
        '-NoProfile'
        '-File'
        $Recorder
        '-ExternalRunRoot'
        $ExternalRunRoot
        '-RunId'
        $RunId
        '-EventJson'
        $EventJson
    )
    if ($LockTimeoutMilliseconds -ge 0) {
        $arguments += @('-LockTimeoutMilliseconds', [string] $LockTimeoutMilliseconds)
    }
    if ($FaultAfterBytes -ge 0) {
        $arguments += @('-FaultAfterBytes', [string] $FaultAfterBytes)
    }
    if (-not [string]::IsNullOrWhiteSpace($LockReadyPath)) {
        $arguments += @('-LockReadyPath', $LockReadyPath)
    }
    $output = & $pwsh @arguments 2>&1
    return [pscustomobject]@{
        ExitCode = [int] $LASTEXITCODE
        Output = @($output | ForEach-Object { [string] $_ })
    }
}

function Get-RecorderResult {
    param(
        [Parameter(Mandatory)] [object] $Invocation,
        [Parameter(Mandatory)] [string] $Context
    )

    $jsonLines = @($Invocation.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-True ($jsonLines.Count -gt 0) "$Context returns a JSON result"
    try {
        return ($jsonLines[-1] | ConvertFrom-Json -DateKind String)
    }
    catch {
        throw "Performance-event assertion failed: $Context returned non-JSON output '$($jsonLines[-1])'"
    }
}

function Wait-ForFiles {
    param(
        [Parameter(Mandatory)] [string[]] $Paths,
        [int] $TimeoutMilliseconds = 60000
    )

    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.ElapsedMilliseconds -le $TimeoutMilliseconds) {
        $ready = @($Paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($ready.Count -eq $Paths.Count) {
            return
        }
        [Threading.Thread]::Yield() | Out-Null
    }
    throw "Performance-event assertion failed: readiness files did not appear within the bounded wait"
}

function Convert-EventToJson {
    param([Parameter(Mandatory)] [object] $Event)

    $payload = if ([int] $Event.schemaVersion -eq 2 -and [string] $Event.kind -ceq 'story_performance_event_frame') {
        $Event.event
    }
    else {
        $Event
    }
    return ($payload | ConvertTo-Json -Compress -Depth 20)
}

function Get-BloomBitPositionsForTest {
    param([Parameter(Mandatory)] [string] $EventId)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($EventId))
        return @(0..3 | ForEach-Object {
                [BitConverter]::ToUInt32($digest, $_ * 4) % 32768
            })
    }
    finally {
        $sha.Dispose()
    }
}

function Copy-Event {
    param([Parameter(Mandatory)] [object] $Event)

    return (Convert-EventToJson -Event $Event | ConvertFrom-Json -DateKind String)
}

function Set-EventProperty {
    param(
        [Parameter(Mandatory)] [object] $Event,
        [Parameter(Mandatory)] [string] $Name,
        [AllowNull()] [object] $Value
    )

    $property = $Event.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Event | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $property.Value = $Value
    }
    return $Event
}

function New-EventVariant {
    param(
        [Parameter(Mandatory)] [object] $Base,
        [Parameter(Mandatory)] [hashtable] $Changes
    )

    $variant = Copy-Event -Event $Base
    foreach ($entry in $Changes.GetEnumerator()) {
        Set-EventProperty -Event $variant -Name ([string] $entry.Key) -Value $entry.Value | Out-Null
    }
    return $variant
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$recorder = Join-Path $PSScriptRoot 'write-performance-event.ps1'
Assert-True (Test-Path -LiteralPath $recorder -PathType Leaf) 'recorder script exists'

$externalRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-' + [guid]::NewGuid().ToString('N'))
$disposableRoots = @($externalRoot)
$runId = 'synthetic-run-149'
$ledgerPath = Join-Path (Join-Path $externalRoot $runId) 'events.jsonl'

$validEvent = [ordered]@{
    schemaVersion = 1
    kind = 'story_performance_event'
    eventId = 'synthetic-run-149-story-started'
    runId = $runId
    projectId = 12
    storyId = 726
    storyRef = 142
    taskRef = $null
    role = 'coordinator'
    sessionId = 'synthetic-session-149'
    workerId = 'synthetic-worker-149'
    transitionId = 'story-started'
    scope = 'story'
    phaseId = $null
    correctionId = $null
    reviewRequestId = $null
    reviewAttemptId = $null
    reviewKind = $null
    reviewAttemptOrdinal = $null
    supersedesReviewAttemptId = $null
    eventType = 'story_started'
    occurredAtUtc = '2026-10-10T10:00:00Z'
    revision = $null
    reviewMode = 'per_task'
    provenance = [ordered]@{
        source = 'synthetic_fixture'
        observedBy = 'validator'
        coverage = 'direct'
        synthetic = $true
    }
    usage = $null
}

try {
    $validJson = Convert-EventToJson -Event $validEvent
    $first = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $externalRoot -RunId $runId -EventJson $validJson
    $firstResult = Get-RecorderResult -Invocation $first -Context 'valid event append'
    Assert-True ($first.ExitCode -eq 0) ("valid event append exits zero; exit=$($first.ExitCode); output=$($first.Output -join ' | ')")
    $expectedFirstLedgerRead = [IO.FileInfo]::new($ledgerPath).Length
    Assert-True ([long]$firstResult.scannedBytes -eq $expectedFirstLedgerRead -and [long]$firstResult.ledgerReadBytes -eq $expectedFirstLedgerRead) 'ordinary append must report the actual post-write ledger bytes read'
    Assert-True (Test-Path -LiteralPath $ledgerPath -PathType Leaf) 'valid append creates the external ledger'

    $lines = @(Get-Content -LiteralPath $ledgerPath)
    Assert-True ($lines.Count -eq 1) 'one valid event creates one ledger line'
    $roundTrip = $lines[0] | ConvertFrom-Json -DateKind String
    $roundTripJson = Convert-EventToJson -Event $roundTrip
    Assert-True ($roundTripJson -ceq $validJson) 'valid event round-trips unchanged'

    $bloomEdgeRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-bloom-edge-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $bloomEdgeRoot
    $bloomEdgeRunId = 'synthetic-run-bloom-edge'
    $bloomEdge32766 = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'bloom-edge-673'
        runId = $bloomEdgeRunId
        transitionId = 'bloom-edge-32766'
    }
    $bloomEdge32767 = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'bloom-edge-8904'
        runId = $bloomEdgeRunId
        transitionId = 'bloom-edge-32767'
    }
    Assert-True ((Get-BloomBitPositionsForTest -EventId ([string]$bloomEdge32766.eventId)) -contains 32766) 'Bloom lower edge fixture must hash to bit 32766'
    Assert-True ((Get-BloomBitPositionsForTest -EventId ([string]$bloomEdge32767.eventId)) -contains 32767) 'Bloom upper edge fixture must hash to bit 32767'
    $bloomEdgeFirst = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $bloomEdgeRoot -RunId $bloomEdgeRunId -EventJson (Convert-EventToJson $bloomEdge32766)
    $bloomEdgeFirstResult = Get-RecorderResult -Invocation $bloomEdgeFirst -Context 'Bloom lower bit boundary append'
    Assert-True ($bloomEdgeFirst.ExitCode -eq 0 -and $bloomEdgeFirstResult.status -ceq 'appended') 'Bloom bit 32766 recorder append must succeed'
    $bloomBytes = [IO.File]::ReadAllBytes([string]$bloomEdgeFirstResult.bloomPath)
    Assert-True ($bloomBytes.Length -eq 4104 -and (($bloomBytes[8 + 4095] -band [byte](1 -shl 6)) -ne 0)) 'Bloom bit 32766 must be stored in the final filter byte'
    $bloomEdgeSecond = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $bloomEdgeRoot -RunId $bloomEdgeRunId -EventJson (Convert-EventToJson $bloomEdge32767)
    $bloomEdgeSecondResult = Get-RecorderResult -Invocation $bloomEdgeSecond -Context 'Bloom upper bit boundary append'
    Assert-True ($bloomEdgeSecond.ExitCode -eq 0 -and $bloomEdgeSecondResult.status -ceq 'appended') 'Bloom bit 32767 recorder append must succeed'
    $bloomBytes = [IO.File]::ReadAllBytes([string]$bloomEdgeSecondResult.bloomPath)
    Assert-True (($bloomBytes[8 + 4095] -band [byte](1 -shl 7)) -ne 0) 'Bloom bit 32767 must be stored in the final filter byte'

    $bloomSaturationRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-bloom-saturation-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $bloomSaturationRoot
    $bloomSaturationRunId = 'synthetic-run-bloom-saturation'
    $bloomSaturationBase = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'bloom-saturation-base'
        runId = $bloomSaturationRunId
        transitionId = 'bloom-saturation-base'
    }
    $bloomSaturationBaseAppend = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $bloomSaturationRoot -RunId $bloomSaturationRunId -EventJson (Convert-EventToJson $bloomSaturationBase)
    $bloomSaturationBaseResult = Get-RecorderResult -Invocation $bloomSaturationBaseAppend -Context 'Bloom saturation baseline append'
    Assert-True ($bloomSaturationBaseAppend.ExitCode -eq 0 -and $bloomSaturationBaseResult.status -ceq 'appended') 'Bloom saturation baseline must append'
    $saturatedBloom = [IO.File]::ReadAllBytes([string]$bloomSaturationBaseResult.bloomPath)
    for ($byteIndex = 8; $byteIndex -lt $saturatedBloom.Length; $byteIndex++) {
        $saturatedBloom[$byteIndex] = 0xFF
    }
    [IO.File]::WriteAllBytes([string]$bloomSaturationBaseResult.bloomPath, $saturatedBloom)
    for ($saturationIndex = 1; $saturationIndex -le 4; $saturationIndex++) {
        $saturationEvent = New-EventVariant -Base $bloomSaturationBase -Changes @{
            eventId = "bloom-saturation-new-$saturationIndex"
            transitionId = "bloom-saturation-new-$saturationIndex"
        }
        $saturationJson = Convert-EventToJson -Event $saturationEvent
        $saturationLedgerPath = Join-Path (Join-Path $bloomSaturationRoot $bloomSaturationRunId) 'events.jsonl'
        $saturationBeforeLength = if (Test-Path -LiteralPath $saturationLedgerPath -PathType Leaf) { [IO.FileInfo]::new($saturationLedgerPath).Length } else { 0L }
        $saturationAppend = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $bloomSaturationRoot -RunId $bloomSaturationRunId -EventJson $saturationJson
        $saturationResult = Get-RecorderResult -Invocation $saturationAppend -Context "Bloom false-positive append $saturationIndex"
        $expectedSaturationRead = [IO.FileInfo]::new($saturationLedgerPath).Length - $saturationBeforeLength
        Assert-True ($saturationAppend.ExitCode -eq 0 -and $saturationResult.status -ceq 'appended' -and [bool]$saturationResult.bloomMayContainEvent -and [string]$saturationResult.scanMode -ceq 'incremental' -and [long]$saturationResult.scannedBytes -eq $expectedSaturationRead) "Bloom false-positive append $saturationIndex must remain ordinary bounded work"
    }

    $revisionA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $revisionB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $usage = [ordered]@{
        state = 'partial'
        streamId = 'synthetic-review-stream'
        role = 'reviewer'
        sessionId = 'synthetic-session-149'
        source = 'synthetic_fixture'
        counterSemantics = [ordered]@{
            cachedInput = 'included_in_input'
            reasoning = 'included_in_output'
        }
        coverage = 'one attributable interval'
        sampledAtUtc = '2026-10-10T10:10:00Z'
        baselineAtUtc = '2026-10-10T10:00:00Z'
        counters = [ordered]@{
            inputTokens = 100
            cachedInputTokens = 40
            outputTokens = 30
            reasoningTokens = 8
        }
        reason = 'synthetic counters are not host telemetry'
        fallback = 'retain partial coverage'
    }
    $implementationStarted = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-implementation-started'
        transitionId = 'implementation-started'
        taskRef = 149
        role = 'implementer'
        scope = 'task'
        phaseId = 'task-149-implementation-1'
        eventType = 'implementation_started'
    }
    $taskReady = New-EventVariant -Base $implementationStarted -Changes @{
        eventId = 'synthetic-task-ready'
        transitionId = 'task-ready'
        eventType = 'task_ready_for_review'
        revision = $revisionA
    }
    $reviewStarted = New-EventVariant -Base $taskReady -Changes @{
        eventId = 'synthetic-review-started'
        transitionId = 'review-started'
        role = 'reviewer'
        reviewRequestId = 'task-149-request-1'
        reviewAttemptId = 'task-149-attempt-1'
        reviewKind = 'initial_task'
        reviewAttemptOrdinal = 1
        eventType = 'review_started'
        usage = $usage
    }
    $reviewAccepted = New-EventVariant -Base $reviewStarted -Changes @{
        eventId = 'synthetic-review-accepted'
        transitionId = 'review-accepted'
        eventType = 'review_accepted'
        usage = $null
    }
    $correctionStarted = New-EventVariant -Base $reviewStarted -Changes @{
        eventId = 'synthetic-correction-started'
        transitionId = 'correction-started'
        role = 'implementer'
        phaseId = 'task-149-correction-1'
        correctionId = 'task-149-correction-1'
        supersedesReviewAttemptId = 'task-149-attempt-1'
        eventType = 'correction_started'
        revision = $null
        usage = $null
        reviewRequestId = $null
        reviewAttemptId = $null
        reviewKind = $null
        reviewAttemptOrdinal = $null
    }
    $correctionReady = New-EventVariant -Base $correctionStarted -Changes @{
        eventId = 'synthetic-correction-ready'
        transitionId = 'correction-ready'
        eventType = 'correction_ready'
        revision = $revisionB
    }
    $finalReviewStarted = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-final-review-started'
        transitionId = 'final-review-started'
        role = 'reviewer'
        scope = 'final_story'
        phaseId = 'story-142-final-review-1'
        eventType = 'final_review_started'
        revision = $revisionB
        reviewRequestId = 'story-142-final-request-1'
        reviewAttemptId = 'story-142-final-attempt-1'
        reviewKind = 'final_story'
        reviewAttemptOrdinal = 1
    }
    $finalFindings = New-EventVariant -Base $finalReviewStarted -Changes @{
        eventId = 'synthetic-final-review-findings'
        transitionId = 'final-review-findings'
        eventType = 'review_findings'
    }
    $finalAccepted = New-EventVariant -Base $finalReviewStarted -Changes @{
        eventId = 'synthetic-final-review-accepted'
        transitionId = 'final-review-accepted'
        eventType = 'final_review_accepted'
    }
    $prReady = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-pr-ready'
        transitionId = 'pr-ready'
        eventType = 'pr_ready'
        revision = $revisionB
        pullRequest = [ordered]@{
            provider = 'github'
            owner = 'synthetic-owner'
            repository = 'synthetic-repository'
            number = 321
            reviewedHead = $revisionB
        }
    }
    $waitStarted = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-wait-started'
        transitionId = 'wait-started'
        eventType = 'wait_started'
        waitId = 'synthetic-wait-1'
        waitKind = 'review'
    }
    $waitEnded = New-EventVariant -Base $waitStarted -Changes @{
        eventId = 'synthetic-wait-ended'
        transitionId = 'wait-ended'
        eventType = 'wait_ended'
    }
    $usageUnavailable = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-usage-unavailable'
        transitionId = 'usage-unavailable'
        usage = [ordered]@{
            state = 'unavailable'
            source = 'no-attributable-worker-stream'
            coverage = 'none'
            counters = $null
            reason = 'synthetic unavailable fixture'
            fallback = 'retain unknown usage'
        }
    }
    $usagePartialNoBaseline = New-EventVariant -Base $reviewStarted -Changes @{
        eventId = 'synthetic-usage-partial-no-baseline'
        usage = [ordered]@{
            state = 'partial'
            streamId = 'synthetic-review-stream-no-baseline'
            role = 'reviewer'
            source = 'synthetic_fixture'
            coverage = 'no exact start-boundary baseline'
            sampledAtUtc = '2026-10-10T10:11:00Z'
            baselineAtUtc = $null
            counters = [ordered]@{ inputTokens = 10 }
            counterSemantics = [ordered]@{
                cachedInput = 'unknown'
                reasoning = 'unknown'
            }
            reason = 'baseline was not available at the exact run boundary'
            fallback = 'retain raw sample with unknown delta'
        }
    }
    $validVariants = @(
        $implementationStarted, $taskReady, $reviewStarted, $reviewAccepted,
        $correctionStarted, $correctionReady, $finalReviewStarted, $finalFindings,
        $finalAccepted, $prReady, $waitStarted, $waitEnded, $usageUnavailable,
        $usagePartialNoBaseline
    )
    foreach ($variant in $validVariants) {
        $variantJson = Convert-EventToJson -Event $variant
        $result = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $externalRoot -RunId $runId -EventJson $variantJson
        Assert-True ($result.ExitCode -eq 0) "documented event '$($variant.eventType)' appends successfully"
        $variantLines = @(Get-Content -LiteralPath $ledgerPath)
        $variantRoundTrip = $variantLines[$variantLines.Count - 1] | ConvertFrom-Json -DateKind String
        Assert-True ((Convert-EventToJson -Event $variantRoundTrip) -ceq $variantJson) "event '$($variant.eventId)' round-trips unchanged"
    }
    $allLines = @(Get-Content -LiteralPath $ledgerPath)
    Assert-True ($allLines.Count -eq 15) 'documented event families append one complete record each'

    $beforeInvalid = [IO.File]::ReadAllText($ledgerPath)

    $wrongStoryRole = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'invalid-story-role'
        role = 'reviewer'
    }
    $missingReviewRevision = New-EventVariant -Base $reviewStarted -Changes @{
        eventId = 'invalid-review-revision'
        revision = $null
    }
    $missingPullRequest = New-EventVariant -Base $prReady -Changes @{
        eventId = 'invalid-pr-identity'
        pullRequest = $null
    }
    $missingWaitIdentity = New-EventVariant -Base $waitStarted -Changes @{
        eventId = 'invalid-wait-identity'
        waitId = $null
    }
    $forbiddenNestedPullRequest = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'invalid-non-pr-pull-request'
        pullRequest = [ordered]@{ prompt = 'never persist' }
    }
    $mismatchedPullRequestRevision = New-EventVariant -Base $prReady -Changes @{
        eventId = 'invalid-pr-revision-binding'
        revision = $revisionA
    }
    $usageMissingBinding = New-EventVariant -Base $reviewStarted -Changes @{
        eventId = 'invalid-usage-binding'
        usage = [ordered]@{
            state = 'measured'
            source = 'synthetic'
            coverage = 'direct'
            counters = [ordered]@{ inputTokens = 10 }
            counterSemantics = [ordered]@{
                cachedInput = 'included_in_output'
                reasoning = 'included_in_input'
            }
        }
    }
    $usageWrongRelationships = New-EventVariant -Base $reviewStarted -Changes @{
        eventId = 'invalid-usage-relationships'
        usage = [ordered]@{
            state = 'partial'
            streamId = 'synthetic-review-stream'
            role = 'reviewer'
            source = 'synthetic_fixture'
            coverage = 'partial'
            sampledAtUtc = '2026-10-10T10:10:00Z'
            baselineAtUtc = '2026-10-10T10:00:00Z'
            counters = [ordered]@{ inputTokens = 10 }
            counterSemantics = [ordered]@{
                cachedInput = 'included_in_output'
                reasoning = 'included_in_input'
            }
        }
    }
    $invalidCases = @(
        [pscustomobject]@{ Name = 'malformed JSON'; Json = '{not-json'; Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'schema type'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace '"schemaVersion":1', '"schemaVersion":"1"' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'non-ISO timestamp'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace '2026-10-10T10:00:00Z', '10/10/2026 10:00:00Z' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'run mismatch'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace 'synthetic-run-149-story-started', 'synthetic-run-149-other' -replace '"runId":"synthetic-run-149"', '"runId":"other-run"' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'metadata not allowlisted'; Json = (Convert-EventToJson ((Copy-Event $validEvent) | ForEach-Object { $_ | Add-Member -NotePropertyName prompt -NotePropertyValue 'never persist' -PassThru })); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'invalid event vocabulary'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace '"story_started"', '"not_a_transition"' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'story role identity'; Json = (Convert-EventToJson $wrongStoryRole); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'review revision identity'; Json = (Convert-EventToJson $missingReviewRevision); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'PR identity'; Json = (Convert-EventToJson $missingPullRequest); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'wait identity'; Json = (Convert-EventToJson $missingWaitIdentity); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'non-PR nested payload'; Json = (Convert-EventToJson $forbiddenNestedPullRequest); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'PR revision binding'; Json = (Convert-EventToJson $mismatchedPullRequestRevision); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'usage stream/sample binding'; Json = (Convert-EventToJson $usageMissingBinding); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'usage counter relationships'; Json = (Convert-EventToJson $usageWrongRelationships); Root = $externalRoot; Run = $runId }
    )

    foreach ($case in $invalidCases) {
        $result = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $case.Root -RunId $case.Run -EventJson $case.Json
        Assert-True ($result.ExitCode -ne 0) "$($case.Name) is rejected"
        Assert-True ([IO.File]::ReadAllText($ledgerPath) -ceq $beforeInvalid) "$($case.Name) leaves the ledger unchanged"
    }

    $sourceBoundRoot = Join-Path $repoRoot '.agents\skills\taiga-story-loop\synthetic-ledger'
    $sourceBound = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $sourceBoundRoot -RunId 'source-bound-run' -EventJson $validJson
    Assert-True ($sourceBound.ExitCode -ne 0) 'source-worktree storage path is rejected'
    Assert-True (-not (Test-Path -LiteralPath $sourceBoundRoot)) 'source-worktree rejection creates no directory'

    $nestedPrivacy = Copy-Event $validEvent
    $nestedPrivacy.provenance | Add-Member -NotePropertyName transcript -NotePropertyValue 'never persist'
    $privacy = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $externalRoot -RunId $runId -EventJson (Convert-EventToJson $nestedPrivacy)
    Assert-True ($privacy.ExitCode -ne 0) 'nested prompt/transcript metadata is rejected'
    Assert-True ([IO.File]::ReadAllText($ledgerPath) -ceq $beforeInvalid) 'nested privacy rejection leaves the ledger unchanged'

    $idempotencyRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-idempotency-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $idempotencyRoot
    $idempotencyRunId = 'synthetic-run-150-idempotency'
    $idempotencyLedgerPath = Join-Path (Join-Path $idempotencyRoot $idempotencyRunId) 'events.jsonl'
    $idempotencyEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-idempotency-event'
        runId = $idempotencyRunId
        transitionId = 'idempotency-first-write'
    }
    $idempotencyJson = Convert-EventToJson -Event $idempotencyEvent
    $idempotencyFirst = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $idempotencyRoot -RunId $idempotencyRunId -EventJson $idempotencyJson
    $idempotencyFirstResult = Get-RecorderResult -Invocation $idempotencyFirst -Context 'idempotency first write'
    Assert-True ($idempotencyFirst.ExitCode -eq 0 -and $idempotencyFirstResult.status -ceq 'appended') 'first stable-ID write appends'
    $beforeNoop = [IO.File]::ReadAllText($idempotencyLedgerPath)
    $reorderedEvent = [ordered]@{}
    foreach ($property in @($idempotencyEvent.PSObject.Properties | Sort-Object Name -Descending)) {
        $reorderedEvent[$property.Name] = $property.Value
    }
    $reordered = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $idempotencyRoot -RunId $idempotencyRunId -EventJson (Convert-EventToJson -Event $reorderedEvent)
    $reorderedResult = Get-RecorderResult -Invocation $reordered -Context 'canonicalized idempotency repeat'
    Assert-True ($reordered.ExitCode -eq 0 -and $reorderedResult.status -ceq 'noop') 'reordered JSON object keys are an idempotent replay'
    Assert-True ([IO.File]::ReadAllText($idempotencyLedgerPath) -ceq $beforeNoop) 'canonicalized replay does not append a duplicate line'
    $idempotencyRepeat = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $idempotencyRoot -RunId $idempotencyRunId -EventJson $idempotencyJson
    $idempotencyRepeatResult = Get-RecorderResult -Invocation $idempotencyRepeat -Context 'idempotency repeat'
    Assert-True ($idempotencyRepeat.ExitCode -eq 0 -and $idempotencyRepeatResult.status -ceq 'noop') 'identical stable-ID replay is a no-op'
    Assert-True ([IO.File]::ReadAllText($idempotencyLedgerPath) -ceq $beforeNoop) 'identical replay does not append a duplicate line'
    $conflictingEvent = New-EventVariant -Base $idempotencyEvent -Changes @{
        transitionId = 'idempotency-conflicting-write'
    }
    $conflicting = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $idempotencyRoot -RunId $idempotencyRunId -EventJson (Convert-EventToJson $conflictingEvent)
    $conflictingResult = Get-RecorderResult -Invocation $conflicting -Context 'conflicting duplicate'
    Assert-True ($conflicting.ExitCode -eq 3) 'conflicting stable-ID replay exits with a conflict result'
    Assert-True ($conflictingResult.status -ceq 'error' -and $conflictingResult.errorCategory -ceq 'conflicting_duplicate') 'conflicting stable-ID replay is reported safely'
    Assert-True (Test-Path -LiteralPath ([string] $conflictingResult.diagnosticPath) -PathType Leaf) 'conflicting replay writes a diagnostic sidecar'
    Assert-True ([IO.File]::ReadAllText([string] $conflictingResult.diagnosticPath) -match '"diagnosticType":"conflicting_duplicate"') 'conflict sidecar records the conflict type'
    Assert-True ([IO.File]::ReadAllText($idempotencyLedgerPath) -ceq $beforeNoop) 'conflicting replay does not mutate the event ledger'

    $foreignBindingRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-foreign-binding-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $foreignBindingRoot
    $foreignBindingRunId = 'synthetic-run-150-foreign-binding'
    $foreignSeedEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-foreign-binding-seed'
        runId = $foreignBindingRunId
        storyId = 730
        transitionId = 'foreign-binding-seed'
    }
    $foreignSeed = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $foreignBindingRoot -RunId $foreignBindingRunId -EventJson (Convert-EventToJson $foreignSeedEvent)
    Assert-True ($foreignSeed.ExitCode -eq 0) 'foreign-binding seed appends to its own story ledger'
    $foreignAttemptEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-foreign-binding-attempt'
        runId = $foreignBindingRunId
        storyId = 729
        transitionId = 'foreign-binding-attempt'
    }
    $foreignLedgerPath = Join-Path (Join-Path $foreignBindingRoot $foreignBindingRunId) 'events.jsonl'
    $foreignBefore = [IO.File]::ReadAllText($foreignLedgerPath)
    $foreignAttempt = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $foreignBindingRoot -RunId $foreignBindingRunId -EventJson (Convert-EventToJson $foreignAttemptEvent)
    $foreignAttemptResult = Get-RecorderResult -Invocation $foreignAttempt -Context 'foreign binding rejection'
    Assert-True ($foreignAttempt.ExitCode -eq 3 -and $foreignAttemptResult.errorCategory -ceq 'run_binding_conflict') 'foreign binding is rejected before append'
    $foreignRetry = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $foreignBindingRoot -RunId $foreignBindingRunId -EventJson (Convert-EventToJson $foreignAttemptEvent)
    $foreignRetryResult = Get-RecorderResult -Invocation $foreignRetry -Context 'foreign binding repeated rejection'
    Assert-True ($foreignRetry.ExitCode -eq 3 -and $foreignRetryResult.errorCategory -ceq 'run_binding_conflict') 'foreign binding remains rejected after retry'
    Assert-True ([IO.File]::ReadAllText($foreignLedgerPath) -ceq $foreignBefore) 'foreign binding rejection never advances or mutates the ledger'

    $lockRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-lock-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $lockRoot
    $lockRunId = 'synthetic-run-150-lock'
    $lockDirectory = Join-Path $lockRoot $lockRunId
    [IO.Directory]::CreateDirectory($lockDirectory) | Out-Null
    $lockPath = Join-Path $lockDirectory 'events.jsonl.lock'
    $lockHolder = $null
    try {
        $lockHolder = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $lockEvent = New-EventVariant -Base $validEvent -Changes @{
            eventId = 'synthetic-lock-timeout-event'
            runId = $lockRunId
            transitionId = 'lock-timeout'
        }
        $lockInvocation = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $lockRoot -RunId $lockRunId -EventJson (Convert-EventToJson $lockEvent) -LockTimeoutMilliseconds 0
        $lockResult = Get-RecorderResult -Invocation $lockInvocation -Context 'bounded lock timeout'
        Assert-True ($lockInvocation.ExitCode -eq 2) 'held ledger lock exits with a bounded failure'
        Assert-True ($lockResult.status -ceq 'error' -and $lockResult.errorCategory -ceq 'lock_timeout') 'held ledger lock returns a safe timeout category'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $lockDirectory 'events.jsonl'))) 'lock timeout does not fabricate a ledger record'
    }
    finally {
        if ($null -ne $lockHolder) {
            $lockHolder.Dispose()
        }
    }

    $lockBaselineEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-lock-baseline'
        runId = $lockRunId
        transitionId = 'lock-baseline'
    }
    $lockBaseline = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $lockRoot -RunId $lockRunId -EventJson (Convert-EventToJson $lockBaselineEvent)
    Assert-True ($lockBaseline.ExitCode -eq 0) 'lock safety baseline appends'
    $lockBaselineText = [IO.File]::ReadAllText((Join-Path $lockDirectory 'events.jsonl'))
    $reservedAliasEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-reserved-alias'
        runId = $lockRunId
        transitionId = 'reserved-alias'
    }
    $reservedAlias = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $lockRoot -RunId $lockRunId -EventJson (Convert-EventToJson $reservedAliasEvent) -LockReadyPath (Join-Path $lockDirectory 'events.jsonl')
    Assert-True ($reservedAlias.ExitCode -ne 0) 'ledger path is rejected as a readiness alias'
    Assert-True ([IO.File]::ReadAllText((Join-Path $lockDirectory 'events.jsonl')) -ceq $lockBaselineText) 'reserved ledger alias leaves the ledger byte-identical'
    $existingReadyPath = Join-Path $lockDirectory 'existing-ready.signal'
    [IO.File]::WriteAllText($existingReadyPath, 'existing', [Text.UTF8Encoding]::new($false))
    $existingReady = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $lockRoot -RunId $lockRunId -EventJson (Convert-EventToJson $reservedAliasEvent) -LockReadyPath $existingReadyPath
    Assert-True ($existingReady.ExitCode -ne 0) 'existing readiness target is rejected before mutation'
    Assert-True ([IO.File]::ReadAllText($existingReadyPath) -ceq 'existing') 'existing readiness target remains byte-identical'
    Assert-True ([IO.File]::ReadAllText((Join-Path $lockDirectory 'events.jsonl')) -ceq $lockBaselineText) 'existing readiness target rejection leaves the ledger byte-identical'
    $sourceReadyPath = Join-Path $repoRoot '.agents\skills\taiga-story-loop\synthetic-ready-signal'
    try {
        $sourceReady = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $lockRoot -RunId $lockRunId -EventJson (Convert-EventToJson $reservedAliasEvent) -LockReadyPath $sourceReadyPath
        Assert-True ($sourceReady.ExitCode -ne 0) 'source-worktree readiness target is rejected'
        Assert-True (-not (Test-Path -LiteralPath $sourceReadyPath)) 'source-worktree readiness rejection creates no file'
    }
    finally {
        if (Test-Path -LiteralPath $sourceReadyPath) {
            Remove-Item -LiteralPath $sourceReadyPath -Force
        }
    }

    $recoveryRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-recovery-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $recoveryRoot
    $recoveryRunId = 'synthetic-run-150-recovery'
    $recoveryLedgerPath = Join-Path (Join-Path $recoveryRoot $recoveryRunId) 'events.jsonl'
    $confirmedEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-confirmed-before-fault'
        runId = $recoveryRunId
        transitionId = 'confirmed-before-fault'
    }
    $confirmed = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $confirmedEvent)
    Assert-True ($confirmed.ExitCode -eq 0) 'confirmed event before fault appends'
    $interruptedEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-interrupted-write'
        runId = $recoveryRunId
        transitionId = 'interrupted-write'
    }
    $faulted = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $interruptedEvent) -FaultAfterBytes 32
    $faultedResult = Get-RecorderResult -Invocation $faulted -Context 'deterministic interrupted write'
    Assert-True ($faulted.ExitCode -eq 2) 'deterministic partial write never reports success'
    Assert-True ($faultedResult.status -ceq 'error' -and $faultedResult.errorCategory -ceq 'write_failed') 'partial write returns a safe write failure category'
    $faultedBytes = [IO.File]::ReadAllBytes($recoveryLedgerPath)
    Assert-True ($faultedBytes.Length -gt 0 -and $faultedBytes[$faultedBytes.Length - 1] -ne [byte] 0x0A) 'fault injection leaves an explicitly detectable incomplete tail'
    $recoveredEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-recovered-after-tail'
        runId = $recoveryRunId
        transitionId = 'recovered-after-tail'
    }
    $recovered = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $recoveredEvent)
    $recoveredResult = Get-RecorderResult -Invocation $recovered -Context 'incomplete-tail recovery'
    Assert-True ($recovered.ExitCode -eq 0 -and $recoveredResult.status -ceq 'appended') 'next append recovers after an interrupted tail'
    Assert-True ([bool] $recoveredResult.recoveredIncompleteTail) 'recovery result identifies the incomplete tail'
    Assert-True (Test-Path -LiteralPath ([string] $recoveredResult.diagnosticPath) -PathType Leaf) 'tail recovery writes a diagnostic sidecar'
    $recoveryDiagnostics = [IO.File]::ReadAllText([string] $recoveredResult.diagnosticPath)
    Assert-True ($recoveryDiagnostics -match '"diagnosticType":"incomplete_tail"') 'tail recovery preserves incomplete-tail evidence'
    $recoveryLedgerText = [IO.File]::ReadAllText($recoveryLedgerPath)
    Assert-True ($recoveryLedgerText -match [regex]::Escape([string] $confirmedEvent.eventId)) 'recovery preserves the confirmed complete event'
    Assert-True ($recoveryLedgerText -match [regex]::Escape([string] $recoveredEvent.eventId)) 'recovery appends the new complete event'

    $checkpointPath = [string] $recoveredResult.checkpointPath
    $indexPath = [string] $recoveredResult.indexPath
    Assert-True (Test-Path -LiteralPath $checkpointPath -PathType Leaf) 'normal recovery writes an external checkpoint'
    Assert-True (Test-Path -LiteralPath $indexPath -PathType Container) 'normal recovery writes an external event index'
    $staleLedgerEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-stale-checkpoint-catchup'
        runId = $recoveryRunId
        transitionId = 'stale-checkpoint-catchup'
    }
    $staleCheckpointBytes = [IO.File]::ReadAllBytes($checkpointPath)
    $staleAppend = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $staleLedgerEvent)
    Assert-True ($staleAppend.ExitCode -eq 0) 'stale checkpoint fixture appends through the active ledger format'
    [IO.File]::WriteAllBytes($checkpointPath, $staleCheckpointBytes)
    $catchUpEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-after-stale-checkpoint'
        runId = $recoveryRunId
        transitionId = 'after-stale-checkpoint'
    }
    $catchUp = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $catchUpEvent)
    $catchUpResult = Get-RecorderResult -Invocation $catchUp -Context 'stale checkpoint catch-up'
    Assert-True ($catchUp.ExitCode -eq 0 -and $catchUpResult.status -ceq 'appended') 'stale checkpoint catch-up appends safely'
    Assert-True ([string] $catchUpResult.scanMode -in @('incremental', 'cold_rebuild') -and [long] $catchUpResult.scannedBytes -gt 0) 'stale checkpoint catch-up scans the uncheckpointed suffix or safely rebuilds from the authoritative v2 head'
    $catchUpReplay = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $staleLedgerEvent)
    $catchUpReplayResult = Get-RecorderResult -Invocation $catchUpReplay -Context 'stale checkpoint replay'
    Assert-True ($catchUpReplay.ExitCode -eq 0 -and $catchUpReplayResult.status -ceq 'noop') 'stale checkpoint catch-up preserves replay idempotency'

    [IO.File]::Delete($checkpointPath)
    $missingCheckpointEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-missing-checkpoint-rebuild'
        runId = $recoveryRunId
        transitionId = 'missing-checkpoint-rebuild'
    }
    $missingCheckpoint = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $missingCheckpointEvent)
    $missingCheckpointResult = Get-RecorderResult -Invocation $missingCheckpoint -Context 'missing checkpoint recovery'
    Assert-True ($missingCheckpoint.ExitCode -eq 0 -and $missingCheckpointResult.status -ceq 'appended') 'missing checkpoint recovery appends safely'
    Assert-True ([string] $missingCheckpointResult.scanMode -ceq 'cold_rebuild') 'missing checkpoint recovery discloses a cold rebuild'

    [IO.File]::WriteAllText($checkpointPath, '{corrupt-checkpoint', [Text.UTF8Encoding]::new($false))
    $corruptCheckpointEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-corrupt-checkpoint-rebuild'
        runId = $recoveryRunId
        transitionId = 'corrupt-checkpoint-rebuild'
    }
    $corruptCheckpoint = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $corruptCheckpointEvent)
    $corruptCheckpointResult = Get-RecorderResult -Invocation $corruptCheckpoint -Context 'corrupt checkpoint recovery'
    Assert-True ($corruptCheckpoint.ExitCode -eq 0 -and $corruptCheckpointResult.status -ceq 'appended') 'corrupt checkpoint recovery appends safely'
    Assert-True ([string] $corruptCheckpointResult.scanMode -ceq 'cold_rebuild') 'corrupt checkpoint recovery discloses a cold rebuild'

    [IO.Directory]::Delete($indexPath, $true)
    $missingIndexEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-missing-index-rebuild'
        runId = $recoveryRunId
        transitionId = 'missing-index-rebuild'
    }
    $missingIndex = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $recoveryRoot -RunId $recoveryRunId -EventJson (Convert-EventToJson $missingIndexEvent)
    $missingIndexResult = Get-RecorderResult -Invocation $missingIndex -Context 'missing index recovery'
    Assert-True ($missingIndex.ExitCode -eq 0 -and $missingIndexResult.status -ceq 'appended') 'missing index recovery appends safely'
    Assert-True ([string] $missingIndexResult.scanMode -ceq 'cold_rebuild') 'missing index recovery discloses a cold rebuild'

    $individualIndexRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-individual-index-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $individualIndexRoot
    $individualIndexRunId = 'synthetic-run-150-individual-index'
    $individualIndexEvent = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-individual-index-replay'
        runId = $individualIndexRunId
        transitionId = 'individual-index-replay'
    }
    $individualIndexAppend = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $individualIndexRoot -RunId $individualIndexRunId -EventJson (Convert-EventToJson $individualIndexEvent)
    $individualIndexAppendResult = Get-RecorderResult -Invocation $individualIndexAppend -Context 'individual index append'
    $individualIndexDirectory = [string] $individualIndexAppendResult.indexPath
    $individualIndexLedger = [string] $individualIndexAppendResult.ledgerPath
    $individualIndexFiles = @(Get-ChildItem -LiteralPath $individualIndexDirectory -Filter '*.json' -File)
    Assert-True ($individualIndexFiles.Count -eq 1) 'individual index fixture creates one event marker'
    [IO.File]::Delete($individualIndexFiles[0].FullName)
    $missingIndividualIndexReplay = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $individualIndexRoot -RunId $individualIndexRunId -EventJson (Convert-EventToJson $individualIndexEvent)
    $missingIndividualIndexReplayResult = Get-RecorderResult -Invocation $missingIndividualIndexReplay -Context 'missing individual index replay'
    Assert-True ($missingIndividualIndexReplay.ExitCode -eq 0 -and $missingIndividualIndexReplayResult.status -ceq 'noop' -and [string] $missingIndividualIndexReplayResult.scanMode -ceq 'incremental') 'missing individual index replay repairs from bounded identity state and remains idempotent'
    Assert-True (@([IO.File]::ReadAllLines($individualIndexLedger)).Count -eq 1) 'missing individual index replay does not duplicate the ledger record'
    $restoredIndividualIndexFile = @(Get-ChildItem -LiteralPath $individualIndexDirectory -Filter '*.json' -File)[0]
    [IO.File]::WriteAllText($restoredIndividualIndexFile.FullName, '{broken-index', [Text.UTF8Encoding]::new($false))
    $corruptIndividualIndexReplay = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $individualIndexRoot -RunId $individualIndexRunId -EventJson (Convert-EventToJson $individualIndexEvent)
    $corruptIndividualIndexReplayResult = Get-RecorderResult -Invocation $corruptIndividualIndexReplay -Context 'corrupt individual index replay'
    Assert-True ($corruptIndividualIndexReplay.ExitCode -eq 0 -and $corruptIndividualIndexReplayResult.status -ceq 'noop' -and [string] $corruptIndividualIndexReplayResult.scanMode -ceq 'incremental') 'corrupt individual index replay repairs from bounded identity state and remains idempotent'
    $changedIndividualIndexEvent = New-EventVariant -Base $individualIndexEvent -Changes @{
        transitionId = 'individual-index-conflict'
    }
    $changedIndividualIndexReplay = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $individualIndexRoot -RunId $individualIndexRunId -EventJson (ConvertTo-Json -InputObject $changedIndividualIndexEvent -Compress -Depth 20)
    $changedIndividualIndexReplayResult = Get-RecorderResult -Invocation $changedIndividualIndexReplay -Context 'corrupt individual index conflict'
    Assert-True ($changedIndividualIndexReplay.ExitCode -eq 3 -and $changedIndividualIndexReplayResult.errorCategory -ceq 'conflicting_duplicate') 'corrupt individual index replay preserves conflict detection'
    Assert-True (@([IO.File]::ReadAllLines($individualIndexLedger)).Count -eq 1) 'corrupt individual index conflict does not mutate the ledger'

    $membershipDirectory = "$individualIndexLedger.membership"
    $membershipFiles = @(Get-ChildItem -LiteralPath $membershipDirectory -Filter '*.json' -File)
    Assert-True ($membershipFiles.Count -eq 1) 'individual membership fixture creates one exact membership marker'
    [IO.File]::Delete((Get-ChildItem -LiteralPath $individualIndexDirectory -Filter '*.json' -File)[0].FullName)
    [IO.File]::WriteAllText($membershipFiles[0].FullName, '{invalid-membership', [Text.UTF8Encoding]::new($false))
    $missingIndexCorruptMembershipReplay = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $individualIndexRoot -RunId $individualIndexRunId -EventJson (Convert-EventToJson $individualIndexEvent)
    $missingIndexCorruptMembershipReplayResult = Get-RecorderResult -Invocation $missingIndexCorruptMembershipReplay -Context 'missing index corrupt membership replay'
    Assert-True ($missingIndexCorruptMembershipReplay.ExitCode -eq 0 -and $missingIndexCorruptMembershipReplayResult.status -ceq 'noop' -and [string] $missingIndexCorruptMembershipReplayResult.scanMode -ceq 'incremental') 'missing index plus corrupt membership replay repairs from bounded identity state before deciding idempotency'
    Assert-True (@([IO.File]::ReadAllLines($individualIndexLedger)).Count -eq 1) 'missing index plus corrupt membership replay never duplicates the ledger record'

    [IO.File]::Delete((Get-ChildItem -LiteralPath $individualIndexDirectory -Filter '*.json' -File)[0].FullName)
    $membershipFiles = @(Get-ChildItem -LiteralPath $membershipDirectory -Filter '*.json' -File)
    Assert-True ($membershipFiles.Count -eq 1) 'recovery restores one exact membership marker'
    [IO.File]::WriteAllText($membershipFiles[0].FullName, '{invalid-membership-again', [Text.UTF8Encoding]::new($false))
    $missingIndexCorruptMembershipConflictEvent = New-EventVariant -Base $individualIndexEvent -Changes @{
        transitionId = 'missing-index-corrupt-membership-conflict'
    }
    $missingIndexCorruptMembershipConflict = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $individualIndexRoot -RunId $individualIndexRunId -EventJson (Convert-EventToJson $missingIndexCorruptMembershipConflictEvent)
    $missingIndexCorruptMembershipConflictResult = Get-RecorderResult -Invocation $missingIndexCorruptMembershipConflict -Context 'missing index corrupt membership conflict'
    Assert-True ($missingIndexCorruptMembershipConflict.ExitCode -eq 3 -and $missingIndexCorruptMembershipConflictResult.errorCategory -ceq 'conflicting_duplicate' -and [string] $missingIndexCorruptMembershipConflictResult.scanMode -ceq 'incremental') 'missing index plus corrupt membership conflict repairs from bounded identity state before rejecting a conflicting replay'
    Assert-True (@([IO.File]::ReadAllLines($individualIndexLedger)).Count -eq 1) 'missing index plus corrupt membership conflict does not mutate the ledger'

    $unicodeRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-unicode-tail-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $unicodeRoot
    $unicodeRunId = 'synthetic-run-150-unicode-tail'
    $unicodeLedgerPath = Join-Path (Join-Path $unicodeRoot $unicodeRunId) 'events.jsonl'
    $unicodeConfirmed = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-unicode-confirmed'
        runId = $unicodeRunId
        transitionId = 'unicode-confirmed'
    }
    $unicodeConfirmedResult = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $unicodeRoot -RunId $unicodeRunId -EventJson (Convert-EventToJson $unicodeConfirmed)
    Assert-True ($unicodeConfirmedResult.ExitCode -eq 0) 'confirmed event before a multibyte fault appends'
    $unicodeInterrupted = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-é-interrupted'
        runId = $unicodeRunId
        transitionId = 'unicode-interrupted'
    }
    $unicodeJson = Convert-EventToJson -Event $unicodeInterrupted
    $unicodeBytes = [Text.UTF8Encoding]::new($false).GetBytes($unicodeJson + [Environment]::NewLine)
    $accentOffset = -1
    for ($offset = 0; $offset -lt ($unicodeBytes.Length - 1); $offset++) {
        if ($unicodeBytes[$offset] -eq [byte] 0xC3 -and $unicodeBytes[$offset + 1] -eq [byte] 0xA9) {
            $accentOffset = $offset
            break
        }
    }
    Assert-True ($accentOffset -ge 0) 'Unicode fault fixture contains a UTF-8 multibyte sequence'
    $unicodeFaulted = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $unicodeRoot -RunId $unicodeRunId -EventJson $unicodeJson -FaultAfterBytes ($accentOffset + 1)
    $unicodeFaultedResult = Get-RecorderResult -Invocation $unicodeFaulted -Context 'multibyte interrupted write'
    Assert-True ($unicodeFaulted.ExitCode -eq 2 -and $unicodeFaultedResult.errorCategory -ceq 'write_failed') 'multibyte interrupted write never reports success'
    $unicodeRecovered = New-EventVariant -Base $validEvent -Changes @{
        eventId = 'synthetic-unicode-recovered'
        runId = $unicodeRunId
        transitionId = 'unicode-recovered'
    }
    $unicodeRecovery = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $unicodeRoot -RunId $unicodeRunId -EventJson (Convert-EventToJson $unicodeRecovered)
    $unicodeRecoveryResult = Get-RecorderResult -Invocation $unicodeRecovery -Context 'multibyte tail recovery'
    Assert-True ($unicodeRecovery.ExitCode -eq 0 -and [bool] $unicodeRecoveryResult.recoveredIncompleteTail) 'multibyte tail recovery preserves and reports the incomplete tail'
    Assert-True (Test-Path -LiteralPath ([string] $unicodeRecoveryResult.diagnosticPath) -PathType Leaf) 'multibyte tail recovery writes evidence'
    $unicodeDiagnostics = [IO.File]::ReadAllText([string] $unicodeRecoveryResult.diagnosticPath)
    Assert-True ($unicodeDiagnostics -match '"diagnosticType":"incomplete_tail"') 'multibyte tail recovery records incomplete-tail evidence'
    $unicodeLedgerText = [IO.File]::ReadAllText($unicodeLedgerPath)
    Assert-True ($unicodeLedgerText -match [regex]::Escape([string] $unicodeConfirmed.eventId)) 'multibyte-tail recovery preserves the earlier confirmed event'
    Assert-True ($unicodeLedgerText -match [regex]::Escape([string] $unicodeRecovered.eventId)) 'multibyte-tail recovery appends the next complete event'

    $concurrentRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-performance-event-concurrent-' + [guid]::NewGuid().ToString('N'))
    $disposableRoots += $concurrentRoot
    $concurrentRunId = 'synthetic-run-150-concurrent'
    $concurrentDirectory = Join-Path $concurrentRoot $concurrentRunId
    [IO.Directory]::CreateDirectory($concurrentDirectory) | Out-Null
    $concurrentLockPath = Join-Path $concurrentDirectory 'events.jsonl.lock'
    $concurrentLockHolder = $null
    $concurrentJobs = @()
    $sameIdJobs = @()
    $concurrentJobScript = {
        param(
            [string] $RecorderPath,
            [string] $RunRoot,
            [string] $RunName,
            [string] $Payload,
            [string] $ReadyPath
        )

        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
        $captured = @(& $pwshPath -NoProfile -File $RecorderPath `
            -ExternalRunRoot $RunRoot `
            -RunId $RunName `
            -EventJson $Payload `
            -LockTimeoutMilliseconds 30000 `
            -LockReadyPath $ReadyPath 2>&1 | ForEach-Object { [string] $_ })
        [pscustomobject]@{
            ExitCode = [int] $LASTEXITCODE
            Output = $captured
        }
    }
    try {
        $concurrentLockHolder = [IO.FileStream]::new($concurrentLockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $concurrentEventA = New-EventVariant -Base $validEvent -Changes @{
            eventId = 'synthetic-concurrent-a'
            runId = $concurrentRunId
            transitionId = 'concurrent-a'
        }
        $concurrentEventB = New-EventVariant -Base $validEvent -Changes @{
            eventId = 'synthetic-concurrent-b'
            runId = $concurrentRunId
            transitionId = 'concurrent-b'
        }
        $readyA = Join-Path $concurrentDirectory 'ready-a.signal'
        $readyB = Join-Path $concurrentDirectory 'ready-b.signal'
        $concurrentJobs += Start-Job -ScriptBlock $concurrentJobScript -ArgumentList $recorder, $concurrentRoot, $concurrentRunId, (Convert-EventToJson $concurrentEventA), $readyA
        $concurrentJobs += Start-Job -ScriptBlock $concurrentJobScript -ArgumentList $recorder, $concurrentRoot, $concurrentRunId, (Convert-EventToJson $concurrentEventB), $readyB
        Wait-ForFiles -Paths @($readyA, $readyB)
        $concurrentLockHolder.Dispose()
        $concurrentLockHolder = $null
        $completedConcurrentJobs = @(Wait-Job -Job $concurrentJobs -Timeout 60)
        Assert-True ($completedConcurrentJobs.Count -eq 2) 'concurrent recorder fixtures complete within the bounded wait'
        $concurrentResults = @($concurrentJobs | Receive-Job)
        Assert-True ($concurrentResults.Count -eq 2) 'both concurrent recorder fixtures return results'
        foreach ($concurrentResult in $concurrentResults) {
            Assert-True ($concurrentResult.ExitCode -eq 0) 'concurrent distinct event append exits zero'
            $concurrentOperation = Get-RecorderResult -Invocation $concurrentResult -Context 'concurrent distinct event'
            Assert-True ($concurrentOperation.status -ceq 'appended') 'concurrent distinct event reports append'
        }
        $concurrentLedgerPath = Join-Path $concurrentDirectory 'events.jsonl'
        $concurrentLines = @(Get-Content -LiteralPath $concurrentLedgerPath)
        $concurrentIds = @($concurrentLines | ForEach-Object {
                $parsed = $_ | ConvertFrom-Json -Depth 50 -DateKind String
                if ([int] $parsed.schemaVersion -eq 2 -and [string] $parsed.kind -ceq 'story_performance_event_frame') { $parsed = $parsed.event }
                [string] $parsed.eventId
            })
        Assert-True ($concurrentLines.Count -eq 2) 'concurrent distinct events persist as exactly two lines'
        Assert-True (@($concurrentIds | Sort-Object -Unique).Count -eq 2) 'concurrent distinct events persist once each'
        Assert-True ($concurrentIds -contains [string] $concurrentEventA.eventId) 'concurrent event A is present'
        Assert-True ($concurrentIds -contains [string] $concurrentEventB.eventId) 'concurrent event B is present'

        $concurrentLockHolder = [IO.FileStream]::new($concurrentLockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $sameIdEvent = New-EventVariant -Base $validEvent -Changes @{
            eventId = 'synthetic-concurrent-identical'
            runId = $concurrentRunId
            transitionId = 'concurrent-identical'
        }
        $sameIdReadyA = Join-Path $concurrentDirectory 'ready-identical-a.signal'
        $sameIdReadyB = Join-Path $concurrentDirectory 'ready-identical-b.signal'
        $sameIdPayload = Convert-EventToJson $sameIdEvent
        $sameIdJobs += Start-Job -ScriptBlock $concurrentJobScript -ArgumentList $recorder, $concurrentRoot, $concurrentRunId, $sameIdPayload, $sameIdReadyA
        $sameIdJobs += Start-Job -ScriptBlock $concurrentJobScript -ArgumentList $recorder, $concurrentRoot, $concurrentRunId, $sameIdPayload, $sameIdReadyB
        Wait-ForFiles -Paths @($sameIdReadyA, $sameIdReadyB)
        $concurrentLockHolder.Dispose()
        $concurrentLockHolder = $null
        $completedSameIdJobs = @(Wait-Job -Job $sameIdJobs -Timeout 60)
        Assert-True ($completedSameIdJobs.Count -eq 2) 'concurrent identical replay fixtures complete within the bounded wait'
        $sameIdResults = @($sameIdJobs | Receive-Job)
        Assert-True ($sameIdResults.Count -eq 2) 'both concurrent identical replay fixtures return results'
        $sameIdStatuses = @()
        foreach ($sameIdResult in $sameIdResults) {
            Assert-True ($sameIdResult.ExitCode -eq 0) 'concurrent identical replay exits zero'
            $sameIdStatuses += [string] (Get-RecorderResult -Invocation $sameIdResult -Context 'concurrent identical replay').status
        }
        Assert-True (@($sameIdStatuses | Where-Object { $_ -ceq 'appended' }).Count -eq 1) 'concurrent identical replay has one append'
        Assert-True (@($sameIdStatuses | Where-Object { $_ -ceq 'noop' }).Count -eq 1) 'concurrent identical replay has one no-op'
        $finalConcurrentLines = @(Get-Content -LiteralPath $concurrentLedgerPath)
        $finalConcurrentIds = @($finalConcurrentLines | ForEach-Object {
                $parsed = $_ | ConvertFrom-Json -Depth 50 -DateKind String
                if ([int] $parsed.schemaVersion -eq 2 -and [string] $parsed.kind -ceq 'story_performance_event_frame') { $parsed = $parsed.event }
                [string] $parsed.eventId
            })
        Assert-True ($finalConcurrentLines.Count -eq 3) 'concurrent identical replay persists one additional line'
        Assert-True (@($finalConcurrentIds | Where-Object { $_ -ceq [string] $sameIdEvent.eventId }).Count -eq 1) 'concurrent identical replay persists exactly one event'
    }
    finally {
        if ($null -ne $concurrentLockHolder) {
            $concurrentLockHolder.Dispose()
        }
        if ($concurrentJobs.Count -gt 0) {
            Remove-Job -Job $concurrentJobs -Force -ErrorAction SilentlyContinue
        }
        if ($sameIdJobs.Count -gt 0) {
            Remove-Job -Job $sameIdJobs -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Output 'Passed performance-event recorder fixtures: documented event-family round-trips, idempotent replay/conflict diagnostics, bounded lock timeout, interrupted-tail recovery, concurrent distinct appends, unavailable and source-backed usage validation, invalid schema/type/timestamp/identity/event/PR/usage cases, run/path binding, allowlisted metadata, privacy rejection, and unchanged-ledger safety; synthetic and non-live.'
    exit 0
}
finally {
    foreach ($disposableRoot in @($disposableRoots)) {
        if (Test-Path -LiteralPath $disposableRoot) {
            Remove-Item -LiteralPath $disposableRoot -Recurse -Force
        }
    }
}
