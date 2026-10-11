# Focused v2 ledger controls. All state is disposable and local; no Taiga or Git
# provider is contacted.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$recorder = Join-Path $PSScriptRoot 'write-performance-event.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('taiga-performance-v2-' + [Guid]::NewGuid().ToString('N'))

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Performance-v2 assertion failed: $Message" }
}

function New-Event {
    param(
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $TransitionId,
        [int] $StoryId = 2,
        [string] $OccurredAtUtc = '2026-10-11T00:00:00.000Z'
    )
    return [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event'
        eventId = $EventId
        runId = $RunId
        projectId = 1
        storyId = $StoryId
        storyRef = $StoryId
        taskRef = $null
        role = 'coordinator'
        sessionId = 'v2-validator-session'
        workerId = 'v2-validator-worker'
        transitionId = $TransitionId
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
        provenance = [ordered]@{ source = 'v2-validator'; observedBy = 'validate-performance-v2.ps1'; coverage = 'synthetic control'; synthetic = $true }
        usage = $null
        pullRequest = $null
    }
}

function Invoke-Recorder {
    param(
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [object] $Event,
        [int] $FaultAfterBytes = -1
    )
    $args = @('-NoProfile', '-File', $recorder, '-ExternalRunRoot', $ExternalRoot, '-RunId', $RunId, '-EventJson', ($Event | ConvertTo-Json -Compress -Depth 30))
    if ($FaultAfterBytes -ge 0) { $args += @('-FaultAfterBytes', [string] $FaultAfterBytes) }
    $output = @(& pwsh @args 2>&1 | ForEach-Object { [string] $_ })
    $json = $null
    foreach ($line in @($output | Where-Object { $_ -match '^\s*\{' })) {
        try { $json = $line | ConvertFrom-Json -Depth 30 } catch { }
    }
    return [pscustomobject]@{ exitCode = $LASTEXITCODE; result = $json; output = $output }
}

function Get-RunDirectory([string] $ExternalRoot, [string] $RunId) { return Join-Path $ExternalRoot $RunId }
function Get-LedgerPath([string] $ExternalRoot, [string] $RunId) { return Join-Path (Get-RunDirectory $ExternalRoot $RunId) 'events.jsonl' }

try {
    [IO.Directory]::CreateDirectory($root) | Out-Null

    # New v2 frame, exact replay, and changed duplicate semantics.
    $basicRoot = Join-Path $root 'basic'
    $basicRun = 'v2-basic'
    $basicEvent = New-Event -RunId $basicRun -EventId 'v2-basic-event' -TransitionId 'aaaa'
    $first = Invoke-Recorder -ExternalRoot $basicRoot -RunId $basicRun -Event $basicEvent
    Assert-True ($first.exitCode -eq 0 -and $first.result.status -ceq 'appended') 'new runs append a v2 frame'
    $basicLedger = Get-LedgerPath $basicRoot $basicRun
    $frame = @(Get-Content -LiteralPath $basicLedger)[0] | ConvertFrom-Json -Depth 50
    $frameBytes = [IO.FileInfo]::new($basicLedger).Length
    Assert-True ([int] $frame.schemaVersion -eq 2 -and [string] $frame.kind -ceq 'story_performance_event_frame') 'new ledger line is a v2 event frame'
    Assert-True ([string] $frame.event.eventId -ceq $basicEvent.eventId -and [long] $frame.anchor.frameByteLength -eq $frameBytes) 'frame preserves canonical event and exact byte length anchor'
    $exact = Invoke-Recorder -ExternalRoot $basicRoot -RunId $basicRun -Event $basicEvent
    $changedEvent = New-Event -RunId $basicRun -EventId 'v2-basic-event' -TransitionId 'bbbb'
    $changed = Invoke-Recorder -ExternalRoot $basicRoot -RunId $basicRun -Event $changedEvent
    Assert-True ($exact.exitCode -eq 0 -and $exact.result.status -ceq 'noop') 'exact v2 replay is a no-op'
    Assert-True ($changed.exitCode -eq 3 -and $changed.result.errorCategory -ceq 'conflicting_duplicate') 'changed v2 replay is a conflict'

    # A fault immediately before the published LF must retain the exact CRLF
    # orphan suffix and recover without accepting a duplicate or malformed
    # frame boundary.
    $boundaryReferenceRoot = Join-Path $root 'delimiter-reference'
    $boundaryRoot = Join-Path $root 'delimiter-boundary'
    $boundaryRun = 'v2-delimiter-boundary'
    $boundaryEvent = New-Event -RunId $boundaryRun -EventId 'delimiter-event' -TransitionId 'aaaa'
    $boundaryReference = Invoke-Recorder $boundaryReferenceRoot $boundaryRun $boundaryEvent
    $boundaryFrameBytes = [IO.FileInfo]::new((Get-LedgerPath $boundaryReferenceRoot $boundaryRun)).Length
    $boundaryFault = Invoke-Recorder $boundaryRoot $boundaryRun $boundaryEvent -FaultAfterBytes ($boundaryFrameBytes - 1)
    $boundaryChanged = New-Event -RunId $boundaryRun -EventId 'delimiter-event' -TransitionId 'bbbb' -OccurredAtUtc '2026-10-11T00:00:01.000Z'
    $boundaryRepair = Invoke-Recorder $boundaryRoot $boundaryRun $boundaryChanged
    Assert-True ($boundaryFault.exitCode -eq 2 -and $boundaryRepair.exitCode -eq 0 -and $boundaryRepair.result.status -ceq 'appended' -and [bool] $boundaryRepair.result.recoveredIncompleteTail) 'a one-byte-before-LF interruption recovers across the exact CRLF delimiter'
    $boundaryLedger = Get-LedgerPath $boundaryRoot $boundaryRun
    $boundaryAfterRepair = [IO.File]::ReadAllBytes($boundaryLedger)
    $boundaryReplay = Invoke-Recorder $boundaryRoot $boundaryRun $boundaryChanged
    Assert-True ($boundaryReplay.exitCode -eq 0 -and $boundaryReplay.result.status -ceq 'noop') 'a repaired delimiter-boundary frame replays idempotently'
    Assert-True ([Convert]::ToBase64String($boundaryAfterRepair) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($boundaryLedger))) 'delimiter-boundary exact replay does not append again'

    # Coherent checkpoint/trie swap between same-size alternate histories.
    $targetRoot = Join-Path $root 'swap-target'
    $sourceRoot = Join-Path $root 'swap-source'
    $swapRun = 'v2-coherent-swap'
    $targetEvent = New-Event -RunId $swapRun -EventId 'swap-event' -TransitionId 'aaaa'
    $sourceEvent = New-Event -RunId $swapRun -EventId 'swap-event' -TransitionId 'bbbb'
    Assert-True ((Invoke-Recorder $targetRoot $swapRun $targetEvent).exitCode -eq 0) 'swap target seed appends'
    Assert-True ((Invoke-Recorder $sourceRoot $swapRun $sourceEvent).exitCode -eq 0) 'swap source seed appends'
    $targetDir = Get-RunDirectory $targetRoot $swapRun
    $sourceDir = Get-RunDirectory $sourceRoot $swapRun
    Assert-True ([IO.FileInfo]::new((Get-LedgerPath $targetRoot $swapRun)).Length -eq [IO.FileInfo]::new((Get-LedgerPath $sourceRoot $swapRun)).Length) 'swap histories have equal physical frame length'
    foreach ($name in @('index', 'membership', 'identity', 'authority', 'catalog')) { Remove-Item -LiteralPath (Join-Path $targetDir "events.jsonl.$name") -Recurse -Force }
    Copy-Item -LiteralPath (Join-Path $sourceDir 'events.jsonl.checkpoint.json') -Destination (Join-Path $targetDir 'events.jsonl.checkpoint.json') -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir 'events.jsonl.integrity') -Destination (Join-Path $targetDir 'events.jsonl.integrity') -Recurse -Force
    $swapBefore = [IO.File]::ReadAllBytes((Get-LedgerPath $targetRoot $swapRun))
    $swapReplay = Invoke-Recorder $targetRoot $swapRun (New-Event -RunId $swapRun -EventId 'swap-event' -TransitionId 'cccc')
    Assert-True ($swapReplay.exitCode -eq 3 -and $swapReplay.result.errorCategory -ceq 'conflicting_duplicate' -and $swapReplay.result.scanMode -ceq 'cold_rebuild') 'coherent alternate checkpoint/trie swap is rejected after rebuild'
    Assert-True ([Convert]::ToBase64String($swapBefore) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-LedgerPath $targetRoot $swapRun)))) 'coherent swap conflict does not append'

    # Restore an old checkpoint after a later committed frame.
    $rollbackRoot = Join-Path $root 'rollback'
    $rollbackRun = 'v2-old-anchor-rollback'
    $rollbackA = New-Event -RunId $rollbackRun -EventId 'rollback-a' -TransitionId 'aaaa'
    $rollbackB = New-Event -RunId $rollbackRun -EventId 'rollback-b' -TransitionId 'bbbb'
    Assert-True ((Invoke-Recorder $rollbackRoot $rollbackRun $rollbackA).exitCode -eq 0) 'rollback first frame appends'
    $rollbackCheckpoint = Join-Path (Get-RunDirectory $rollbackRoot $rollbackRun) 'events.jsonl.checkpoint.json'
    $oldCheckpoint = [IO.File]::ReadAllBytes($rollbackCheckpoint)
    Assert-True ((Invoke-Recorder $rollbackRoot $rollbackRun $rollbackB).exitCode -eq 0) 'rollback later frame appends'
    [IO.File]::WriteAllBytes($rollbackCheckpoint, $oldCheckpoint)
    $rollbackReplay = Invoke-Recorder $rollbackRoot $rollbackRun (New-Event -RunId $rollbackRun -EventId 'rollback-b' -TransitionId 'cccc')
    Assert-True ($rollbackReplay.exitCode -eq 3 -and $rollbackReplay.result.scanMode -ceq 'cold_rebuild') 'old checkpoint rollback with a later committed frame is rebuilt safely'

    # Interrupted frame, incomplete tail, then malformed complete orphan suffix.
    $faultRoot = Join-Path $root 'fault'
    $faultRun = 'v2-fault'
    $faultEvent = New-Event -RunId $faultRun -EventId 'fault-event' -TransitionId 'fault'
    $fault = Invoke-Recorder $faultRoot $faultRun $faultEvent -FaultAfterBytes 50
    Assert-True ($fault.exitCode -eq 2) 'deterministic interruption fails before checkpoint publication'
    $faultRetry = Invoke-Recorder $faultRoot $faultRun $faultEvent
    Assert-True ($faultRetry.exitCode -eq 0 -and $faultRetry.result.status -ceq 'appended' -and [bool] $faultRetry.result.recoveredIncompleteTail) 'next append binds and recovers an incomplete orphan suffix'
    $faultFrame = @(Get-Content -LiteralPath (Get-LedgerPath $faultRoot $faultRun) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1) | ConvertFrom-Json -Depth 50
    Assert-True ([int] $faultFrame.schemaVersion -eq 2 -and [string] $faultFrame.kind -ceq 'story_performance_event_frame') 'an interrupted first v2 frame retries as v2 rather than falling back to a raw v1 line'
    $malformedRoot = Join-Path $root 'malformed'
    $malformedRun = 'v2-malformed'
    Assert-True ((Invoke-Recorder $malformedRoot $malformedRun (New-Event $malformedRun 'malformed-a' 'aaaa')).exitCode -eq 0) 'malformed fixture seed appends'
    $malformedLedger = Get-LedgerPath $malformedRoot $malformedRun
    [IO.File]::AppendAllText($malformedLedger, '{"schemaVersion":2,"kind":"unknown_frame"}' + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $malformedNext = Invoke-Recorder $malformedRoot $malformedRun (New-Event $malformedRun 'malformed-b' 'bbbb')
    Assert-True ($malformedNext.exitCode -eq 0 -and $malformedNext.result.status -ceq 'appended' -and $malformedNext.result.scanMode -ceq 'cold_rebuild') 'malformed complete suffix is retained and followed by a bound v2 frame'
    Assert-True ((Invoke-Recorder $malformedRoot $malformedRun (New-Event $malformedRun 'malformed-b' 'bbbb')).result.status -ceq 'noop') 'orphan recovery replay is idempotent'

    # Missing node and saturated Bloom remain safe/ordinary.
    $nodeRoot = Join-Path $root 'node-loss'
    $nodeRun = 'v2-node-loss'
    Assert-True ((Invoke-Recorder $nodeRoot $nodeRun (New-Event $nodeRun 'node-event' 'aaaa')).exitCode -eq 0) 'node-loss seed appends'
    $nodePath = Get-ChildItem -LiteralPath (Join-Path (Get-RunDirectory $nodeRoot $nodeRun) 'events.jsonl.integrity\nodes') -Filter '*.json' | Select-Object -First 1
    Remove-Item -LiteralPath $nodePath.FullName -Force
    $nodeReplay = Invoke-Recorder $nodeRoot $nodeRun (New-Event $nodeRun 'node-event' 'aaaa')
    Assert-True ($nodeReplay.exitCode -eq 0 -and $nodeReplay.result.status -ceq 'noop' -and $nodeReplay.result.scanMode -ceq 'cold_rebuild') 'missing trie node triggers reconstruction and exact replay remains a no-op'
    $bloomRoot = Join-Path $root 'saturated-bloom'
    $bloomRun = 'v2-saturated-bloom'
    Assert-True ((Invoke-Recorder $bloomRoot $bloomRun (New-Event $bloomRun 'bloom-a' 'aaaa')).exitCode -eq 0) 'Bloom seed appends'
    $bloomPath = Join-Path (Get-RunDirectory $bloomRoot $bloomRun) 'events.jsonl.bloom'
    $bloomBytes = [IO.File]::ReadAllBytes($bloomPath); for ($index = 8; $index -lt $bloomBytes.Length; $index++) { $bloomBytes[$index] = 0xFF }; [IO.File]::WriteAllBytes($bloomPath, $bloomBytes)
    $bloomNext = Invoke-Recorder $bloomRoot $bloomRun (New-Event $bloomRun 'bloom-b' 'bbbb')
    Assert-True ($bloomNext.exitCode -eq 0 -and $bloomNext.result.status -ceq 'appended' -and [bool] $bloomNext.result.bloomMayContainEvent -and $bloomNext.result.scanMode -ceq 'incremental') 'healthy saturated Bloom collision stays on the ordinary append path'

    # Legacy v1 routing is readable, append-compatible, and cold-only.
    $v1Root = Join-Path $root 'v1'
    $v1Run = 'legacy-v1'
    $v1Dir = Get-RunDirectory $v1Root $v1Run
    [IO.Directory]::CreateDirectory($v1Dir) | Out-Null
    $v1Event = New-Event $v1Run 'legacy-a' 'aaaa'
    $v1Ledger = Get-LedgerPath $v1Root $v1Run
    [IO.File]::WriteAllText($v1Ledger, ($v1Event | ConvertTo-Json -Compress -Depth 30) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $v1Append = Invoke-Recorder $v1Root $v1Run (New-Event $v1Run 'legacy-b' 'bbbb')
    Assert-True ($v1Append.exitCode -eq 0 -and $v1Append.result.status -ceq 'appended' -and $v1Append.result.scanMode -ceq 'cold_rebuild') 'legacy v1 history remains cold-only without implicit migration'
    Assert-True (@(Get-Content -LiteralPath $v1Ledger).Count -eq 2) 'legacy v1 append preserves raw history and adds one raw event line'

    Write-Output 'Passed v2 ledger controls: framed commit anchors with exact lengths, canonical event preservation, coherent checkpoint/trie swap rejection, old-anchor rollback, interrupted and malformed orphan recovery, node-loss reconstruction, saturated Bloom append, exact/changed replay, and legacy v1 cold-only routing.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
