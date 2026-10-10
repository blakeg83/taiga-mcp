# Synthetic validation for the task #149 external event recorder.
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
        [Parameter(Mandatory)] [string] $EventJson
    )

    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $output = & $pwsh -NoProfile -File $Recorder `
        -ExternalRunRoot $ExternalRunRoot `
        -RunId $RunId `
        -EventJson $EventJson 2>&1
    return [pscustomobject]@{
        ExitCode = [int] $LASTEXITCODE
        Output = @($output | ForEach-Object { [string] $_ })
    }
}

function Convert-EventToJson {
    param([Parameter(Mandatory)] [object] $Event)

    return ($Event | ConvertTo-Json -Compress -Depth 20)
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
    Assert-True ($first.ExitCode -eq 0) ("valid event append exits zero; exit=$($first.ExitCode); output=$($first.Output -join ' | ')")
    Assert-True (Test-Path -LiteralPath $ledgerPath -PathType Leaf) 'valid append creates the external ledger'

    $lines = @(Get-Content -LiteralPath $ledgerPath)
    Assert-True ($lines.Count -eq 1) 'one valid event creates one ledger line'
    $roundTrip = $lines[0] | ConvertFrom-Json -DateKind String
    $roundTripJson = Convert-EventToJson -Event $roundTrip
    Assert-True ($roundTripJson -ceq $validJson) 'valid event round-trips unchanged'

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
    $validVariants = @(
        $implementationStarted, $taskReady, $reviewStarted, $reviewAccepted,
        $correctionStarted, $correctionReady, $finalReviewStarted, $finalFindings,
        $finalAccepted, $prReady, $waitStarted, $waitEnded, $usageUnavailable
    )
    foreach ($variant in $validVariants) {
        $variantJson = Convert-EventToJson -Event $variant
        $result = Invoke-Recorder -Recorder $recorder -ExternalRunRoot $externalRoot -RunId $runId -EventJson $variantJson
        Assert-True ($result.ExitCode -eq 0) "documented event '$($variant.eventType)' appends successfully"
    }
    $allLines = @(Get-Content -LiteralPath $ledgerPath)
    Assert-True ($allLines.Count -eq 14) 'documented event families append one complete record each'

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

    Write-Output 'Passed performance-event recorder fixtures: documented event-family round-trips, unavailable and source-backed usage validation, invalid schema/type/timestamp/identity/event/PR/usage cases, run/path binding, allowlisted metadata, privacy rejection, and unchanged-ledger safety; synthetic and non-live.'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $externalRoot) {
        Remove-Item -LiteralPath $externalRoot -Recurse -Force
    }
}
