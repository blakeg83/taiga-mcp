[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('accept-result','prepare-dispatch','prepare-publication','record-external','reconcile-external','observe-wait','heartbeat-plan','status')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'
$script:StateScript = Join-Path $PSScriptRoot 'workflow-state.ps1'

function Read-Object {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw 'Input file was not found.' }
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 }
    catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw 'Input JSON must be an object.' }
    return $value
}

function Need {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }
    return [string]$Object[$Name]
}

function Get-FileSha256 {
    param([string] $Path)
    $stream = [IO.File]::OpenRead($Path); $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($stream))).ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Resolve-Reference {
    param([System.Collections.IDictionary] $Reference, [string] $Name)
    $path = [IO.Path]::GetFullPath((Need $Reference 'path'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Name file was not found." }
    $hash = Get-FileSha256 $path
    if (-not $Reference.Contains('sha256') -or [string]$Reference.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [string]$Reference.sha256.ToLowerInvariant() -cne $hash) { throw "$Name sha256 does not match its file." }
    return [ordered]@{ path = $path; sha256 = $hash }
}

function Read-ReferenceJson {
    param([System.Collections.IDictionary] $Reference, [string] $Name)
    $resolved = Resolve-Reference $Reference $Name
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $resolved.path) -AsHashtable -Depth 100 }
    catch { throw "$Name is not valid JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw "$Name JSON must be an object." }
    return [ordered]@{ reference = $resolved; value = $value }
}

function Write-ImmutableText {
    param([string] $Path, [string] $Text)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ((Get-Content -Raw -LiteralPath $Path) -cne $Text) { throw 'Immutable artifact already exists with conflicting content.' }
        return
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try { [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false)); [IO.File]::Move($temporary, $Path, $false) }
    finally { if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force } }
}

function Invoke-State {
    param([string] $StateOperation, [System.Collections.IDictionary] $Value)
    $root = [IO.Path]::GetFullPath($StateRoot)
    $inputPath = Join-Path $root ('.coordinate-input-' + [Guid]::NewGuid().ToString('N') + '.json')
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        [IO.File]::WriteAllText($inputPath, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $lines = & pwsh -NoProfile -File $script:StateScript -Operation $StateOperation -InputPath $inputPath -StateRoot $root 2>&1
        $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
        try { $result = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "State helper returned invalid JSON: $raw" }
        if ($exitCode -ne 0 -or $result.ok -ne $true) { throw [string]$result.error.message }
        return $result
    } finally { if (Test-Path -LiteralPath $inputPath -PathType Leaf) { Remove-Item -LiteralPath $inputPath -Force } }
}

function Get-Inspection {
    return Invoke-State 'inspect' @{}
}

function Get-OwnerValues {
    param([System.Collections.IDictionary] $InputObject)
    $sessionId = Need $InputObject 'sessionId'; $ownerGeneration = Need $InputObject 'ownerGeneration'; $ticketKey = Need $InputObject 'ticketKey'
    return [ordered]@{ sessionId = $sessionId; ownerGeneration = [long]$ownerGeneration; ticketKey = $ticketKey }
}

function Get-ArtifactSummary {
    param([System.Collections.IDictionary] $InputObject, [string] $Name)
    if (-not $InputObject.Contains($Name)) { return $null }
    if ($InputObject[$Name] -isnot [System.Collections.IDictionary]) { throw "$Name must be a file reference object." }
    return Resolve-Reference $InputObject[$Name] $Name
}

function Read-ValidatedPacket {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Owner)
    $read = Read-ReferenceJson $InputObject.packetReference 'packet'
    $packet = $read.value
    $packetScript = Join-Path $PSScriptRoot 'workflow-packet.ps1'
    $arguments = @('-NoProfile','-File',$packetScript,'-Operation','validate','-PacketPath',$read.reference.path,'-ExpectedTicketKey',$Owner.ticketKey)
    if ($InputObject.Contains('runId')) { $arguments += @('-ExpectedRunId',(Need $InputObject 'runId')) }
    if ($InputObject.Contains('worktreePath')) { $arguments += @('-ExpectedWorktreePath',(Need $InputObject 'worktreePath')) }
    $lines = & pwsh @arguments 2>&1; $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
    try { $validated = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Packet validator returned invalid JSON: $raw" }
    if ($exitCode -ne 0 -or $validated.ok -ne $true) { throw [string]$validated.error.message }
    if ([string]$packet.sessionId -cne [string]$Owner.sessionId) { throw 'Packet sessionId is not bound to the owned session.' }
    if ([string]$packet.ticket.ticketKey -cne [string]$Owner.ticketKey) { throw 'Packet ticketKey is not bound to the owned ticket.' }
    $now = if ($InputObject.Contains('nowUtc')) { [DateTimeOffset]::Parse((Need $InputObject 'nowUtc'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } else { [DateTimeOffset]::UtcNow }
    $deadline = [DateTimeOffset]::Parse([string]$packet.deadline.deadlineUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    return [ordered]@{ reference = $read.reference; value = $packet; validation = $validated.data; expired = ($now -ge $deadline); nowUtc = $now.ToString('o') }
}

function Invoke-ReviewDecision {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Owner, [System.Collections.IDictionary] $Result, [System.Collections.IDictionary] $Packet)
    if (-not $Result.Contains('receiptReference')) { throw 'A publication result must include an immutable receiptReference.' }
    if (-not $Result.Contains('reviewContext') -or $Result.reviewContext -isnot [System.Collections.IDictionary]) { throw 'A publication result must include coordinator reviewContext.' }
    $receipt = Resolve-Reference $Result.receiptReference 'review receipt'
    $context = $Result.reviewContext
    foreach ($name in @('currentSha','currentScopeHash','currentBaseSha','expectedRunId','expectedActionId','expectedTicketKey','correctionRound')) { Need $context $name | Out-Null }
    if ([string]$context.expectedRunId -cne [string]$Packet.runId -or [string]$context.expectedTicketKey -cne [string]$Owner.ticketKey -or [string]$context.expectedActionId -cne [string]$Result.actionId) { throw 'Review context is not bound to the packet, ticket, or result action.' }
    $review = [ordered]@{ receiptPath = $receipt.path; receiptSha256 = $receipt.sha256; expectedCriteria = @($Packet.criteria); currentSha = [string]$context.currentSha; currentScopeHash = [string]$context.currentScopeHash; currentBaseSha = [string]$context.currentBaseSha; expectedRunId = [string]$context.expectedRunId; expectedActionId = [string]$context.expectedActionId; expectedTicketKey = [string]$context.expectedTicketKey; correctionRound = [int]$context.correctionRound; remainingMinutes = if ($context.Contains('remainingMinutes')) { [int]$context.remainingMinutes } else { 1 }; maxCorrectionRounds = if ($context.Contains('maxCorrectionRounds')) { [int]$context.maxCorrectionRounds } else { 3 } }
    if ($Result.Contains('previousReviewedSha')) { $review.previousReviewedSha = [string]$Result.previousReviewedSha }
    if ($Result.Contains('evidenceReferences')) { $review.evidenceReferences = $Result.evidenceReferences; if ($Result.Contains('evidenceStateRoot')) { $review.evidenceStateRoot = [string]$Result.evidenceStateRoot } }
    $reviewPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('.review-input-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($reviewPath, ($review | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $lines = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'workflow-review.ps1') -Operation decide -InputPath $reviewPath 2>&1; $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
        try { $response = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Review helper returned invalid JSON: $raw" }
        if ($exitCode -ne 0 -or $response.ok -ne $true) { throw [string]$response.error.message }
        return $response.data
    } finally { if (Test-Path -LiteralPath $reviewPath -PathType Leaf) { Remove-Item -LiteralPath $reviewPath -Force } }
}

function Invoke-AcceptResult {
    param([System.Collections.IDictionary] $InputObject)
    $owner = Get-OwnerValues $InputObject
    $resultRead = Read-ReferenceJson $InputObject.resultReference 'result'
    $result = $resultRead.value
    foreach ($name in @('cursor','actionId','workerId','status')) { Need $result $name | Out-Null }
    $inspection = Get-Inspection; $revision = [long]$inspection.revision
    $action = $inspection.data.registry.actions[[string]$result.actionId]
    if ($null -eq $action) { throw 'Worker result action was not prepared for this ticket.' }
    if ([string]$action.ticketKey -cne [string]$owner.ticketKey -or [string]$action.sessionId -cne [string]$owner.sessionId -or [string]$action.target.workerId -cne [string]$result.workerId) { throw 'Worker result is not bound to the prepared ticket action and worker.' }
    if ($result.status -eq 'blocked') { $decision = 'needs_input' }
    elseif ($result.status -ne 'completed') { $decision = 'wait' }
    elseif ($result.Contains('receiptReference')) {
        if (-not $InputObject.Contains('packetReference')) { throw 'A publication result must include its validated packetReference.' }
        $resultPacket = Read-ValidatedPacket $InputObject $owner
        $review = Invoke-ReviewDecision $InputObject $owner $result $resultPacket.value
        $decision = [string]$review.decision
    }
    else { $decision = 'review' }
    if ($result.Contains('decision') -and [string]$result.decision -eq 'publish' -and $decision -ne 'publish') { throw 'Worker result cannot authorize publication without a validated review decision.' }
    if ($result.Contains('nextPhase') -and -not [string]::IsNullOrWhiteSpace([string]$result.nextPhase)) {
        $requestedPhase = [string]$result.nextPhase
        $allowedRequested = if ($decision -eq 'review') { @('preparing','implementing','reviewing') } elseif ($decision -eq 'publish') { @('publishing') } elseif ($decision -eq 'correct') { @('correcting') } else { @('needs_input') }
        if ($allowedRequested -notcontains $requestedPhase) { throw 'Worker result requested a phase outside its validated route.' }
    }
    $reason = if ($result.Contains('reason')) { [string]$result.reason } else { "worker_$($result.status)" }
    $phase = switch ($decision) { 'publish' { 'publishing' }; 'correct' { 'correcting' }; 'needs_input' { if ($result.Contains('nextPhase')) { [string]$result.nextPhase } else { 'needs_input' } }; default { if ($decision -eq 'review' -and $result.Contains('nextPhase') -and [string]$result.nextPhase -in @('preparing','implementing','reviewing')) { [string]$result.nextPhase } else { $null } } }
    if ($decision -eq 'needs_input' -and $null -ne $phase -and $phase -ne 'needs_input') { $phase = 'needs_input' }
    $stateResult = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = $revision; ticketKey = $owner.ticketKey; cursor = [string]$result.cursor; actionId = [string]$result.actionId; workerId = [string]$result.workerId; decision = $decision; toPhase = $phase; reason = $reason; routeValidated = if ($decision -eq 'publish') { 'review_publish' } else { 'derived_from_validated_result' }; result = [ordered]@{ resultId = if ($result.Contains('resultId')) { [string]$result.resultId } else { [string]$result.cursor }; workerId = [string]$result.workerId; status = [string]$result.status; resultReference = $resultRead.reference; summary = if ($result.Contains('summary')) { [string]$result.summary } else { $null }; decision = $decision } }
    $accepted = Invoke-State 'accept-result' $stateResult
    return [ordered]@{ phase = $phase; decision = $decision; reason = $reason; actionId = [string]$result.actionId; workerId = [string]$result.workerId; requiredReferences = @($resultRead.reference) + @($result.receiptReference) + @($result.evidenceReferences); changedFields = @($accepted.data.changedFields); revision = [long]$accepted.revision }
}

function Invoke-PrepareExternal {
    param([System.Collections.IDictionary] $InputObject, [string] $ActionKind, [string] $ExternalOperation)
    $owner = Get-OwnerValues $InputObject
    $actionId = Need $InputObject 'actionId'; $workerId = Need $InputObject 'workerId'
    if ($InputObject.Contains('remainingMinutes') -and [int]$InputObject.remainingMinutes -le 0) {
        $packet = Resolve-Reference $InputObject.packetReference 'packet'
        return [ordered]@{ phase = 'needs_input'; decision = 'needs_input'; reason = 'elapsed_budget'; actionId = $actionId; workerId = $workerId; requiredReferences = @($packet); changedFields = @(); revision = [long](Get-Inspection).revision }
    }
    $packetRead = Read-ValidatedPacket $InputObject $owner; $packet = $packetRead.reference; $packetValue = $packetRead.value
    if ($packetRead.expired) { return [ordered]@{ phase = 'needs_input'; decision = 'needs_input'; reason = 'elapsed_budget'; actionId = $actionId; workerId = $workerId; requiredReferences = @($packet); changedFields = @(); revision = [long](Get-Inspection).revision } }
    $authorized = @($packetValue.authority.authorizedActions); $excluded = @($packetValue.authority.excludedActions); $authorityAlternatives = if ($ActionKind -eq 'publication') { @($ExternalOperation,'publish') } else { @($ExternalOperation,'dispatch') }
    if ($excluded -contains $ExternalOperation -or @($authorityAlternatives | Where-Object { $authorized -contains $_ }).Count -eq 0) { throw "Packet authority does not authorize $ExternalOperation." }
    $existingInspection = Get-Inspection
    $existingAction = $existingInspection.data.registry.actions[$actionId]
    if ($null -ne $existingAction) {
        if ([string]$existingAction.ticketKey -ne [string]$owner.ticketKey -or [string]$existingAction.sessionId -ne [string]$owner.sessionId) { throw 'Action ID is owned by another ticket or session; reconcile manually.' }
        return [ordered]@{ phase = 'reconciling'; decision = 'reconcile'; reason = 'action_already_prepared'; actionId = $actionId; workerId = $workerId; requiredReferences = @($packet); changedFields = @(); revision = [long]$existingInspection.revision; action = [ordered]@{ operation = $ExternalOperation; actionId = $actionId; workerId = $workerId; status = $existingAction.status; reconcileRequired = if ($existingAction.Contains('reconcileRequired')) { $existingAction.reconcileRequired } else { $false } } }
    }
    $promptReference = $null
    if ($InputObject.Contains('promptReference')) {
        $promptReference = Resolve-Reference $InputObject.promptReference 'prompt'
        $template = Get-Content -Raw -LiteralPath $promptReference.path
    } else { $template = '' }
    $repositoryPath = [string]$packetValue.repository.repositoryPath
    $reviewedSha = if ($InputObject.Contains('reviewedSha')) { [string]$InputObject.reviewedSha } else { [string]$packetValue.repository.baseSha }
    $schemaPath = Join-Path $PSScriptRoot '..\references\review-receipt-v1.schema.json'
    $replacements = @{ packetPath = $packet.path; packetHash = [string]$packetValue.packetHash; packetFileSha256 = $packet.sha256; packetId = [string]$packetValue.packetId; actionId = $actionId; workerId = $workerId; repositoryPath = $repositoryPath; reviewedSha = $reviewedSha; schemaPath = [IO.Path]::GetFullPath($schemaPath) }
    $prompt = $template
    foreach ($name in $replacements.Keys) { $prompt = $prompt.Replace('{{' + $name + '}}', [string]$replacements[$name]) }
    if ($prompt -match '\{\{[^}]+\}\}') { throw 'Prompt contains unresolved placeholders after trusted packet rendering.' }
    $promptPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('prompts\' + $actionId + '.md')
    if (-not [string]::IsNullOrWhiteSpace($prompt)) { Write-ImmutableText $promptPath $prompt }
    $inspection = Get-Inspection
    $payload = [ordered]@{ packetReference = [ordered]@{ path = $packet.path; sha256 = $packet.sha256; packetHash = [string]$packetValue.packetHash; packetId = [string]$packetValue.packetId }; promptReference = if ($promptReference) { [ordered]@{ path = $promptPath; sha256 = Get-FileSha256 $promptPath } } else { $null }; workerId = $workerId; operation = $ExternalOperation }
    $request = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = [long]$inspection.revision; actionId = $actionId; ticketKey = $owner.ticketKey; actionKind = $ActionKind; target = [ordered]@{ workerId = $workerId; operation = $ExternalOperation }; input = $payload; inputDigest = [string]$packetValue.packetHash; packetDeadlineUtc = [string]$packetValue.deadline.deadlineUtc; packetNowUtc = [string]$packetRead.nowUtc }
    $prepared = Invoke-State 'prepare-action' $request
    return [ordered]@{ phase = 'preparing'; decision = 'dispatch'; reason = 'prepared_external_action'; actionId = $actionId; workerId = $workerId; requiredReferences = @($packet) + @($payload.promptReference); changedFields = @('actions'); revision = [long]$prepared.revision; action = [ordered]@{ operation = $ExternalOperation; actionId = $actionId; workerId = $workerId; packet = $payload.packetReference; prompt = $payload.promptReference } }
}

function Invoke-RecordExternal {
    param([System.Collections.IDictionary] $InputObject)
    $owner = Get-OwnerValues $InputObject; $actionId = Need $InputObject 'actionId'; $status = Need $InputObject 'observationStatus'
    if ($status -notin @('observed','uncertain','failed')) { throw 'observationStatus must be observed, uncertain, or failed.' }
    $external = $null; $externalValue = $null
    if ($InputObject.Contains('externalReference')) {
        $externalRead = Read-ReferenceJson $InputObject.externalReference 'external state'; $external = $externalRead.reference; $externalValue = $externalRead.value
    }
    $effectiveStatus = $status
    $pendingClient = $false
    if ($null -ne $externalValue -and $externalValue.Contains('clientThreadId') -and -not $externalValue.Contains('threadId')) { $pendingClient = $true; $effectiveStatus = 'uncertain' }
    $inspection = Get-Inspection
    $externalSummary = if ($null -eq $external) { $null } else { [ordered]@{ reference = $external; provider = if ($externalValue.Contains('provider')) { [string]$externalValue.provider } else { $null }; threadId = if ($externalValue.Contains('threadId')) { [string]$externalValue.threadId } else { $null }; clientThreadId = if ($externalValue.Contains('clientThreadId')) { [string]$externalValue.clientThreadId } else { $null }; remoteHeadSha = if ($externalValue.Contains('remoteHeadSha')) { [string]$externalValue.remoteHeadSha } else { $null }; prUrl = if ($externalValue.Contains('prUrl')) { [string]$externalValue.prUrl } else { $null } } }
    $request = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = [long]$inspection.revision; actionId = $actionId; observationStatus = $effectiveStatus; reconcileRequired = ($effectiveStatus -eq 'uncertain'); externalState = $externalSummary }
    $observed = Invoke-State 'record-observation' $request
    return [ordered]@{ phase = $null; decision = if ($effectiveStatus -eq 'observed') { 'continue' } else { 'needs_input' }; reason = if ($pendingClient) { 'pending_client_id_requires_reconciliation' } elseif ($effectiveStatus -eq 'observed') { 'external_outcome_recorded' } else { 'external_outcome_uncertain' }; actionId = $actionId; workerId = if ($InputObject.Contains('workerId')) { [string]$InputObject.workerId } else { $null }; requiredReferences = @($external); changedFields = @('action.status','action.externalState'); revision = [long]$observed.revision }
}

function Invoke-Status {
    param([System.Collections.IDictionary] $InputObject)
    $inspection = Get-Inspection; $registry = $inspection.data.registry
    $tickets = @($registry.tickets.Values)
    if ($InputObject.Contains('ticketKey')) { $tickets = @($tickets | Where-Object { $_.ticketKey -eq [string]$InputObject.ticketKey }) }
    $actions = @($registry.actions.Values | Where-Object { $null -ne $_.ticketKey -and $tickets.ticketKey -contains $_.ticketKey })
    return [ordered]@{ phase = if ($tickets.Count -eq 1) { [string]$tickets[0].phase } else { $null }; decision = 'status'; reason = 'local_registry_snapshot'; actionId = $null; workerId = $null; requiredReferences = @(); changedFields = @(); revision = [long]$inspection.revision; tickets = @($tickets | ForEach-Object { [ordered]@{ ticketKey = $_.ticketKey; phase = $_.phase; controlState = $_.controlState; correctionRound = $_.correctionRound } }); actions = @($actions | ForEach-Object { [ordered]@{ actionId = $_.actionId; kind = $_.kind; status = $_.status; reconcileRequired = $_.reconcileRequired } }) }
}

function Invoke-ObserveWait {
    param([System.Collections.IDictionary] $InputObject)
    $status = Need $InputObject 'waitStatus'
    if ($status -notin @('unchanged','changed','completed','blocked','user_input','paused')) { throw 'waitStatus is not supported.' }
    $timeout = if ($InputObject.Contains('timeoutMs')) { [int]$InputObject.timeoutMs } else { 30000 }
    if ($timeout -lt 0 -or $timeout -gt 60000) { throw 'timeoutMs must be between 0 and 60000.' }
    $targets = @()
    if ($InputObject.Contains('targets')) {
        if ($InputObject.targets -is [string] -or $InputObject.targets -isnot [System.Collections.IEnumerable]) { throw 'targets must be an array.' }
        $targetValues = @($InputObject.targets); if ($targetValues.Count -lt 1 -or $targetValues.Count -gt 8) { throw 'targets must contain between one and eight threads.' }
        foreach ($target in $targetValues) {
            if ($target -isnot [System.Collections.IDictionary]) { throw 'Each wait target must be an object.' }
            $targetId = Need $target 'threadId'
            $targets += [ordered]@{ threadId = $targetId; hostId = if ($target.Contains('hostId')) { Need $target 'hostId' } else { $null }; afterCursor = if ($target.Contains('afterCursor')) { Need $target 'afterCursor' } else { $null } }
        }
    } elseif ($InputObject.Contains('threadId')) {
        $targets += [ordered]@{ threadId = Need $InputObject 'threadId'; hostId = if ($InputObject.Contains('hostId')) { Need $InputObject 'hostId' } else { $null }; afterCursor = if ($InputObject.Contains('afterCursor')) { Need $InputObject 'afterCursor' } else { $null } }
    }
    $decision = switch ($status) {
        'unchanged' { 'continue_wait' }
        'completed' { 'fetch_result' }
        'changed' { 'inspect_changed_state' }
        'blocked' { 'fetch_blocker' }
        'user_input' { 'needs_input' }
        'paused' { 'heartbeat_quiet' }
    }
    $nativeOperation = switch ($status) {
        'unchanged' { 'wait_threads' }
        'completed' { 'read_thread' }
        'changed' { 'read_thread' }
        'blocked' { 'read_thread' }
        'user_input' { 'surface_user_input' }
        'paused' { 'wait_threads' }
    }
    if ($status -eq 'unchanged' -and $InputObject.Contains('resultReference')) { throw 'Unchanged waits cannot reopen result evidence.' }
    return [ordered]@{ phase = $null; decision = $decision; reason = if ($status -eq 'unchanged') { 'no_state_change' } else { "wait_$status" }; actionId = $null; workerId = if ($InputObject.Contains('workerId')) { [string]$InputObject.workerId } else { $null }; requiredReferences = @(); changedFields = @(); revision = $null; stateMutation = $false; nativeOperation = $nativeOperation; waitThreadsArguments = [ordered]@{ targets = $targets; timeoutMs = $timeout }; detailFetch = ($status -in @('completed','changed','blocked')) }
}

function Invoke-HeartbeatPlan {
    param([System.Collections.IDictionary] $InputObject)
    $inspection = Get-Inspection; $sessionId = Need $InputObject 'sessionId'; $session = $inspection.data.registry.sessions[$sessionId]
    if ($null -eq $session) { throw "Session was not found: $sessionId" }
    $requestedPolicy = if ($InputObject.Contains('notificationPolicy')) { [string]$InputObject.notificationPolicy } else { $null }
    $existing = if ($session.Contains('heartbeatId')) { [string]$session.heartbeatId } else { '' }
    return [ordered]@{ phase = [string]$session.state; decision = if ([string]::IsNullOrWhiteSpace($existing)) { 'create_heartbeat' } else { 'reuse_heartbeat' }; reason = if ([string]::IsNullOrWhiteSpace($existing)) { 'one_session_heartbeat' } else { 'existing_session_heartbeat' }; actionId = $null; workerId = $null; requiredReferences = @(); changedFields = @(); revision = [long]$inspection.revision; stateMutation = $false; nativeOperation = 'automation_update'; heartbeat = [ordered]@{ heartbeatId = if ([string]::IsNullOrWhiteSpace($existing)) { $null } else { $existing }; notificationPolicy = $requestedPolicy; nestedSchedules = $false; quietWhenUnchanged = $true } }
}

try {
    $inputObject = Read-Object
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { throw 'StateRoot is required.' }
    $data = switch ($Operation) {
        'accept-result' { Invoke-AcceptResult $inputObject }
        'prepare-dispatch' { Invoke-PrepareExternal $inputObject 'worker_dispatch' 'create_or_message_worker' }
        'prepare-publication' { Invoke-PrepareExternal $inputObject 'publication' 'push_or_create_pr' }
        'record-external' { Invoke-RecordExternal $inputObject }
        'reconcile-external' { Invoke-RecordExternal $inputObject }
        'observe-wait' { Invoke-ObserveWait $inputObject }
        'heartbeat-plan' { Invoke-HeartbeatPlan $inputObject }
        'status' { Invoke-Status $inputObject }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_coordinate'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
