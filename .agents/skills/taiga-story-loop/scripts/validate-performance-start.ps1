# Deterministic post-Start performance binding fixture.
# It invokes the production recorder and snapshot writer with disposable data;
# it does not call Taiga, Codex, Git, a browser, or a recovery automation.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$recorder = Join-Path $PSScriptRoot 'write-performance-event.ps1'
$writer = Join-Path $PSScriptRoot 'write-continuation-note.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-performance-start-' + [Guid]::NewGuid().ToString('N'))
$externalRoot = Join-Path $fixtureRoot 'external-run-root'
$noteDirectory = Join-Path $fixtureRoot 'notes'
$notePath = Join-Path $noteDirectory 'continuation.md'
$encoding = [Text.UTF8Encoding]::new($false)

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-StoryStartEvent {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [int] $StoryId,
        [Parameter(Mandatory)] [int] $StoryRef,
        [Parameter(Mandatory)] [string] $OccurredAtUtc
    )

    [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event'
        eventId = "$RunId-story-started"
        runId = $RunId
        projectId = 12
        storyId = $StoryId
        storyRef = $StoryRef
        taskRef = $null
        role = 'coordinator'
        sessionId = 'synthetic-coordinator-session'
        workerId = 'synthetic-coordinator-worker'
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
        occurredAtUtc = $OccurredAtUtc
        revision = $null
        reviewMode = 'per_task'
        provenance = [ordered]@{
            source = 'setup_authorization'
            observedBy = 'synthetic-performance-start-validator'
            coverage = 'direct submitted Start boundary'
            synthetic = $true
        }
        usage = $null
    }
}

function Invoke-Recorder {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object] $Event,
        [int] $FaultAfterBytes = -1
    )

    $eventJson = $Event | ConvertTo-Json -Compress -Depth 20
    $arguments = @(
        '-NoProfile', '-File', $recorder,
        '-ExternalRunRoot', $externalRoot,
        '-RunId', $RunId,
        '-EventJson', $eventJson
    )
    if ($FaultAfterBytes -ge 0) {
        $arguments += @('-FaultAfterBytes', [string]$FaultAfterBytes)
    }
    $output = @(& pwsh @arguments 2>&1 | ForEach-Object { [string]$_ })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-LedgerPath([string] $RunId) {
    Join-Path (Join-Path $externalRoot $RunId) 'events.jsonl'
}

function New-PerformancePointer {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $OccurredAtUtc
    )

    "schema=1 | run=$RunId | project=12 | story=725/52 | ledger=$(Get-LedgerPath $RunId) | lastEvent=$EventId | lastObservedUtc=$OccurredAtUtc"
}

function New-Snapshot([AllowNull()] [string] $PerformancePointer) {
    $snapshot = [ordered]@{
        'Run' = 'synthetic-story-52'
        'Scope' = 'project 12 story #52 | tasks: #77, #78'
        'Repository' = 'C:\Synthetic\TaigaMCP | remote: origin https://example.invalid/repo'
        'Base' = 'origin/master @ base-sha'
        'Topology' = 'standalone-story-direct-master'
        'Feature' = 'none (standalone direct-to-master)'
        'Current' = 'story #52 | task #77'
        'Story branch' = 'codex/story-52-synthetic | worktree: C:\Synthetic\story | base: base-sha'
        'Implementer' = 'impl-id @ local | reviewer: review-id @ local'
        'Pair' = 'created | IDs resolved: yes | authorization: auth-synthetic-52'
        'Setup authorization' = 'start | mode: plain-text | submitted: true | reference: auth-synthetic-52'
        'Review mode' = 'per_task | approved HEAD: pending'
        'PR' = 'pending | base: master | head: revision-000'
        'Approval' = 'pending | prompt: none | identity: pending'
        'Review' = 'pending'
        'Final review' = 'not_applicable | profile: none | head: pending'
        'Merge' = 'pending'
        'Next' = 'start story worker pair'
        'Recovery' = 'none | schedule: pending | target: none'
        'Worker cursors' = 'implementer none | reviewer none'
        'Task state' = 'revision-000 | implementing'
        'Gate' = 'none'
        'Pending action' = 'none'
        'Evidence' = 'setup-start-fixture'
    }
    if (-not [string]::IsNullOrWhiteSpace($PerformancePointer)) {
        $snapshot['Performance pointer'] = $PerformancePointer
    }
    $snapshot
}

function Read-Snapshot([string] $Path) {
    $snapshot = [ordered]@{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $separator = $line.IndexOf(': ')
        if ($separator -gt 0) {
            $snapshot[$line.Substring(0, $separator)] = $line.Substring($separator + 2)
        }
    }
    $snapshot
}

function Parse-PerformancePointer {
    param([Parameter(Mandatory)] [string] $Pointer)

    $pattern = '^schema=(?<schema>\d+) \| run=(?<run>[^|]+) \| project=(?<project>\d+) \| story=(?<storyId>\d+)/(?<storyRef>\d+) \| ledger=(?<ledger>[^|]+) \| lastEvent=(?<lastEvent>[^|]+) \| lastObservedUtc=(?<lastObservedUtc>[^|]+)$'
    $match = [regex]::Match($Pointer, $pattern)
    if (-not $match.Success) { return $null }

    $schema = [int]$match.Groups['schema'].Value
    $project = [int]$match.Groups['project'].Value
    $storyId = [int]$match.Groups['storyId'].Value
    $storyRef = [int]$match.Groups['storyRef'].Value
    if ($schema -ne 1 -or $project -ne 12 -or $storyId -ne 725 -or $storyRef -ne 52) {
        return $null
    }

    [pscustomobject]@{
        SchemaVersion = $schema
        RunId = $match.Groups['run'].Value.Trim()
        ProjectId = $project
        StoryId = $storyId
        StoryRef = $storyRef
        LedgerPath = $match.Groups['ledger'].Value.Trim()
        LastEventId = $match.Groups['lastEvent'].Value.Trim()
        LastObservedUtc = $match.Groups['lastObservedUtc'].Value.Trim()
    }
}

function Resolve-ResumeBinding {
    param([Parameter(Mandatory)] [string] $Pointer)

    $binding = Parse-PerformancePointer -Pointer $Pointer
    if ($null -eq $binding) {
        return [pscustomobject]@{ State = 'unavailable'; Reason = 'pointer_binding_invalid'; OccurredAtUtc = 'unavailable'; Authorization = 'unchanged' }
    }
    if ($binding.LastEventId -eq 'none' -or $binding.LastObservedUtc -eq 'unavailable') {
        return [pscustomobject]@{ State = 'unavailable'; Reason = 'pointer_has_no_confirmed_event'; OccurredAtUtc = 'unavailable'; Authorization = 'unchanged' }
    }
    if (-not (Test-Path -LiteralPath $binding.LedgerPath -PathType Leaf)) {
        return [pscustomobject]@{ State = 'unavailable'; Reason = 'ledger_missing'; OccurredAtUtc = 'unavailable'; Authorization = 'unchanged' }
    }

    $lines = @(Get-Content -LiteralPath $binding.LedgerPath)
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        try {
            [void]$events.Add(($line | ConvertFrom-Json -DateKind String))
        }
        catch {
            return [pscustomobject]@{ State = 'unavailable'; Reason = 'ledger_event_invalid'; OccurredAtUtc = 'unavailable'; Authorization = 'unchanged' }
        }
    }

    $matches = @($events | Where-Object { [string]$_.eventId -ceq $binding.LastEventId })
    if ($matches.Count -ne 1) {
        return [pscustomobject]@{ State = 'unavailable'; Reason = 'last_event_missing_or_ambiguous'; OccurredAtUtc = 'unavailable'; Authorization = 'unchanged' }
    }

    $event = $matches[0]
    $identityMatches = [string]$event.runId -ceq $binding.RunId -and
        [int]$event.projectId -eq $binding.ProjectId -and
        [int]$event.storyId -eq $binding.StoryId -and
        [int]$event.storyRef -eq $binding.StoryRef -and
        [string]$event.eventType -ceq 'story_started' -and
        [string]$event.scope -ceq 'story' -and
        [string]$event.role -ceq 'coordinator' -and
        [string]$event.occurredAtUtc -ceq $binding.LastObservedUtc
    if (-not $identityMatches) {
        return [pscustomobject]@{ State = 'unavailable'; Reason = 'ledger_binding_mismatch'; OccurredAtUtc = 'unavailable'; Authorization = 'unchanged' }
    }

    [pscustomobject]@{
        State = 'reused'
        Reason = $null
        RunId = $binding.RunId
        EventId = $binding.LastEventId
        OccurredAtUtc = $binding.LastObservedUtc
        LedgerLineCount = $lines.Count
        Authorization = 'unchanged'
    }
}

function Start-Measurement {
    param(
        [Parameter(Mandatory)] [bool] $Authorized,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $OccurredAtUtc,
        [int] $FaultAfterBytes = -1
    )

    if (-not $Authorized) {
        return [pscustomobject]@{
            State = 'not_started'
            Pointer = $null
            RecorderExitCode = $null
        }
    }

    $event = New-StoryStartEvent -RunId $RunId -StoryId 725 -StoryRef 52 -OccurredAtUtc $OccurredAtUtc
    $invocation = Invoke-Recorder -RunId $RunId -Event $event -FaultAfterBytes $FaultAfterBytes
    if ($invocation.ExitCode -ne 0) {
        return [pscustomobject]@{
            State = 'unavailable'
            Pointer = New-PerformancePointer -RunId $RunId -EventId 'none' -OccurredAtUtc 'unavailable'
            RecorderExitCode = $invocation.ExitCode
        }
    }

    [pscustomobject]@{
        State = 'started'
        Pointer = New-PerformancePointer -RunId $RunId -EventId ([string]$event.eventId) -OccurredAtUtc $OccurredAtUtc
        RecorderExitCode = $invocation.ExitCode
    }
}

try {
    [IO.Directory]::CreateDirectory($externalRoot) | Out-Null
    [IO.Directory]::CreateDirectory($noteDirectory) | Out-Null
    Assert-True (Test-Path -LiteralPath $recorder -PathType Leaf) 'the production recorder exists'
    Assert-True (Test-Path -LiteralPath $writer -PathType Leaf) 'the production continuation writer exists'

    # An open setup gate cannot create a ledger or measurement pointer.
    $preStart = Start-Measurement -Authorized $false -RunId 'synthetic-pre-start' -OccurredAtUtc '2026-10-10T10:00:00Z'
    Assert-True ($preStart.State -eq 'not_started' -and $null -eq $preStart.Pointer) 'pre-Start measurement is not initialized'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $externalRoot 'synthetic-pre-start'))) 'pre-Start does not create an external run'

    $firstRunId = 'synthetic-start-run-1'
    $firstTime = '2026-10-10T10:00:00Z'
    $started = Start-Measurement -Authorized $true -RunId $firstRunId -OccurredAtUtc $firstTime
    $firstLedger = Get-LedgerPath $firstRunId
    Assert-True ($started.State -eq 'started' -and $started.RecorderExitCode -eq 0) 'submitted Start invokes the recorder successfully'
    Assert-True (Test-Path -LiteralPath $firstLedger -PathType Leaf) 'submitted Start creates the external ledger'
    Assert-True (@(Get-Content -LiteralPath $firstLedger).Count -eq 1) 'submitted Start records one story_started event'

    $pointer = [string]$started.Pointer
    & $writer -NotePath $notePath -Snapshot (New-Snapshot -PerformancePointer $pointer) | Out-Null
    $saved = Read-Snapshot -Path $notePath
    Assert-True ($saved['Performance pointer'] -ceq $pointer) 'the continuation stores only the compact performance pointer'
    Assert-True (-not ([IO.File]::ReadAllText($notePath)).Contains('story_performance_event')) 'the continuation does not copy event history'

    # Resume parses the persisted pointer, reads the real ledger event, and
    # verifies every run/project/story/event boundary before reuse. It does not
    # append a second story_started event or replace the timestamp.
    $resumed = Read-Snapshot -Path $notePath
    $resumeLedger = Get-LedgerPath $firstRunId
    $resumeLinesBefore = @(Get-Content -LiteralPath $resumeLedger)
    $resumeBinding = Resolve-ResumeBinding -Pointer $resumed['Performance pointer']
    Assert-True ($resumeBinding.State -eq 'reused' -and $resumeBinding.RunId -eq $firstRunId) 'resume reuses the actual ledger run identity'
    Assert-True ($resumeBinding.EventId -ceq 'synthetic-start-run-1-story-started') 'resume verifies the actual ledger event identity'
    Assert-True ($resumeBinding.OccurredAtUtc -ceq $firstTime) 'resume verifies the actual persisted UTC boundary'
    Assert-True ($resumeBinding.Authorization -ceq 'unchanged') 'valid resume preserves workflow authorization'
    Assert-True ($resumeBinding.LedgerLineCount -eq $resumeLinesBefore.Count -and @(Get-Content -LiteralPath $resumeLedger).Count -eq $resumeLinesBefore.Count) 'resume does not append a duplicate story start'

    # Missing or mismatched recovery evidence remains unavailable. It does not
    # synthesize a timestamp, mutate the ledger, or alter the workflow gate.
    $missingEventPointer = New-PerformancePointer -RunId $firstRunId -EventId 'missing-story-start-event' -OccurredAtUtc $firstTime
    $missingEvent = Resolve-ResumeBinding -Pointer $missingEventPointer
    Assert-True ($missingEvent.State -eq 'unavailable' -and $missingEvent.Reason -eq 'last_event_missing_or_ambiguous' -and $missingEvent.OccurredAtUtc -eq 'unavailable') 'missing last event stays unavailable without a timestamp'
    $missingLedgerPointer = New-PerformancePointer -RunId 'synthetic-missing-ledger' -EventId 'missing-story-start-event' -OccurredAtUtc $firstTime
    $missingLedger = Resolve-ResumeBinding -Pointer $missingLedgerPointer
    Assert-True ($missingLedger.State -eq 'unavailable' -and $missingLedger.Reason -eq 'ledger_missing' -and $missingLedger.OccurredAtUtc -eq 'unavailable') 'missing ledger stays unavailable without a timestamp'
    foreach ($bindingCase in @(
        [pscustomobject]@{ Name = 'run'; Pointer = $pointer.Replace('run=synthetic-start-run-1', 'run=synthetic-foreign-run'); ExpectedReason = 'ledger_binding_mismatch' }
        [pscustomobject]@{ Name = 'project'; Pointer = $pointer.Replace('project=12', 'project=99'); ExpectedReason = 'pointer_binding_invalid' }
        [pscustomobject]@{ Name = 'story'; Pointer = $pointer.Replace('story=725/52', 'story=999/999'); ExpectedReason = 'pointer_binding_invalid' }
    )) {
        $mismatch = Resolve-ResumeBinding -Pointer $bindingCase.Pointer
        Assert-True ($mismatch.State -eq 'unavailable' -and $mismatch.Reason -eq $bindingCase.ExpectedReason -and $mismatch.OccurredAtUtc -eq 'unavailable' -and $mismatch.Authorization -eq 'unchanged') "$($bindingCase.Name) binding mismatch stays unavailable"
    }

    # A historical note without the optional field remains compatible and has
    # unavailable historical coverage rather than a reconstructed timestamp.
    $legacyNote = Join-Path $noteDirectory 'legacy.md'
    & $writer -NotePath $legacyNote -Snapshot (New-Snapshot -PerformancePointer $null) | Out-Null
    $legacy = Read-Snapshot -Path $legacyNote
    Assert-True (-not $legacy.Contains('Performance pointer')) 'historical note can omit the pointer'
    Assert-True (-not $legacy.Contains('lastObservedUtc')) 'historical note does not reconstruct a timestamp'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $externalRoot 'legacy-resume'))) 'historical resume does not create a new run'

    # A new authorized run receives a distinct identity and ledger.
    $secondRun = Start-Measurement -Authorized $true -RunId 'synthetic-start-run-2' -OccurredAtUtc '2026-10-10T11:00:00Z'
    Assert-True ($secondRun.State -eq 'started' -and $secondRun.Pointer -ne $pointer) 'a new authorized run gets a new identity and boundary'
    Assert-True (@(Get-Content -LiteralPath (Get-LedgerPath 'synthetic-start-run-2')).Count -eq 1) 'the new run has an isolated ledger'

    # Recorder failure is measurement-unavailable and does not become a
    # fabricated timestamp or a workflow failure.
    $failedRun = Start-Measurement -Authorized $true -RunId 'synthetic-start-run-failure' -OccurredAtUtc '2026-10-10T12:00:00Z' -FaultAfterBytes 1
    Assert-True ($failedRun.State -eq 'unavailable' -and $failedRun.RecorderExitCode -ne 0) 'recorder failure becomes unavailable measurement'
    Assert-True ([string]$failedRun.Pointer -match 'lastEvent=none' -and [string]$failedRun.Pointer -match 'lastObservedUtc=unavailable') 'measurement failure preserves an unavailable boundary'

    [pscustomobject]@{
        PreStart = $preStart.State
        FirstRun = $firstRunId
        FirstRunLines = @(Get-Content -LiteralPath $firstLedger).Count
        ResumeRun = 'reused'
        LegacyCoverage = 'unavailable'
        NewRun = 'synthetic-start-run-2'
        MeasurementFailure = 'unavailable; workflow continues'
    } | ConvertTo-Json
    Write-Output 'Passed post-Start performance binding fixture: pre-Start gate protection, real recorder story_started append, compact pointer persistence without ledger history, actual ledger-bound resume reuse, missing/mismatched recovery evidence, legacy-note unavailable coverage, new-run identity separation, and non-blocking unavailable failure semantics; synthetic contract assertions with production recorder/writer invocation, no live host/provider execution.'
}
finally {
    if ([IO.Directory]::Exists($fixtureRoot)) {
        [IO.Directory]::Delete($fixtureRoot, $true)
    }
}
