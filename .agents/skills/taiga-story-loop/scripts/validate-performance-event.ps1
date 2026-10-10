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

    return (Convert-EventToJson -Event $Event | ConvertFrom-Json)
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
    $beforeInvalid = [IO.File]::ReadAllText($ledgerPath)

    $invalidCases = @(
        [pscustomobject]@{ Name = 'malformed JSON'; Json = '{not-json'; Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'schema type'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace '"schemaVersion":1', '"schemaVersion":"1"' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'non-UTC timestamp'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace '2026-10-10T10:00:00Z', '2026-10-10T10:00:00-05:00' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'run mismatch'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace 'synthetic-run-149-story-started', 'synthetic-run-149-other' -replace '"runId":"synthetic-run-149"', '"runId":"other-run"' }); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'metadata not allowlisted'; Json = (Convert-EventToJson ((Copy-Event $validEvent) | ForEach-Object { $_ | Add-Member -NotePropertyName prompt -NotePropertyValue 'never persist' -PassThru })); Root = $externalRoot; Run = $runId },
        [pscustomobject]@{ Name = 'invalid event vocabulary'; Json = (Convert-EventToJson (Copy-Event $validEvent) | ForEach-Object { $_ -replace '"story_started"', '"not_a_transition"' }); Root = $externalRoot; Run = $runId }
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

    Write-Output 'Passed performance-event recorder fixtures: valid round-trip, invalid schema/type/timestamp/event, run binding, external path binding, allowlisted metadata, privacy rejection, and unchanged-ledger safety; synthetic and non-live.'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $externalRoot) {
        Remove-Item -LiteralPath $externalRoot -Recurse -Force
    }
}
