[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('accept-result','prepare-dispatch','prepare-publication','record-external','reconcile-external','observe-wait','heartbeat-plan','check-progress','status','relay-task-progress','ack-task-progress')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'
$script:StateScript = Join-Path $PSScriptRoot 'workflow-state.ps1'
$script:ProgressScript = Join-Path $PSScriptRoot 'workflow-progress.ps1'

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

function Canonical {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $result[$key] = Canonical $Value[$key] }
        return ,$result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { $items = [System.Collections.Generic.List[object]]::new(); foreach ($item in $Value) { [void]$items.Add((Canonical $item)) }; return ,$items.ToArray() }
    return $Value
}

function Hash-Object {
    param([object] $Value)
    $json = ConvertTo-Json -InputObject (Canonical $Value) -Depth 100 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-ValidatedPacketBinding {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('packetBinding') -or $InputObject.packetBinding -isnot [System.Collections.IDictionary]) { throw 'Relay requires a validated packetBinding.' }
    $packet = $InputObject.packetBinding
    foreach ($name in @('runId','actionId','packetHash','scopeHash','projectId','parentStoryId','selectedTaskIds','criteriaByTask','tasksById','bindingDigest')) { if (-not $packet.Contains($name)) { throw "packetBinding.$name is required." } }
    $trustedRevisions = $null
    if ($packet.Contains('trustedRevisions')) {
        if ($packet.trustedRevisions -is [string] -or $packet.trustedRevisions -isnot [System.Collections.IEnumerable]) { throw 'packetBinding.trustedRevisions must be an array.' }
        $seenRevisions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $trustedRevisions = [System.Collections.Generic.List[string]]::new()
        foreach ($value in $packet.trustedRevisions) { $revision = [string]$value; if ($revision -notmatch '^[0-9a-fA-F]{7,64}$' -or -not $seenRevisions.Add($revision.ToLowerInvariant())) { throw 'packetBinding.trustedRevisions must contain unique Git revisions.' }; [void]$trustedRevisions.Add($revision.ToLowerInvariant()) }
        if ($trustedRevisions.Count -eq 0) { throw 'packetBinding.trustedRevisions cannot be empty when supplied.' }
    }
    $selected = @($packet.selectedTaskIds | ForEach-Object { [long]$_ }); if ($selected.Count -eq 0 -or @($selected | Select-Object -Unique).Count -ne $selected.Count) { throw 'packetBinding.selectedTaskIds must be nonempty and unique.' }
    if ($packet.criteriaByTask -isnot [System.Collections.IDictionary] -or $packet.tasksById -isnot [System.Collections.IDictionary]) { throw 'packetBinding criteria and task bindings must be objects.' }
    foreach ($taskId in $selected) { $key = [string]$taskId; if (-not $packet.criteriaByTask.Contains($key) -or -not $packet.tasksById.Contains($key)) { throw "packetBinding is missing selected task $taskId." }; $criteria = @($packet.criteriaByTask[$key] | ForEach-Object { [string]$_ }); $task = $packet.tasksById[$key]; if ($task -isnot [System.Collections.IDictionary] -or [long]$task.taskId -ne $taskId -or ($criteria -join '|') -cne (@($task.criteria | ForEach-Object { [string]$_ }) -join '|')) { throw "packetBinding task $taskId is inconsistent." } }
    $normalized = [ordered]@{ runId = [string]$packet.runId; actionId = [string]$packet.actionId; packetHash = ([string]$packet.packetHash).ToLowerInvariant(); scopeHash = ([string]$packet.scopeHash).ToLowerInvariant(); projectId = [long]$packet.projectId; parentStoryId = [long]$packet.parentStoryId; selectedTaskIds = @($selected); criteriaByTask = $packet.criteriaByTask; tasksById = $packet.tasksById }
    if ($null -ne $trustedRevisions) { $normalized.trustedRevisions = @($trustedRevisions) }
    $expected = Hash-Object $normalized
    if ([string]$packet.bindingDigest -cne $expected) { throw 'packetBinding.bindingDigest does not match its immutable contents.' }
    $normalized.bindingDigest = $expected
    return $normalized
}

function Assert-StatusMappingProvenance {
    param([System.Collections.IDictionary] $Mapping, [long] $ProjectId)
    foreach ($name in @('projectId','resource','metadataProjectId','metadataResource','metadataIds','statusMetadata','metadataDigest','mappingDigest','not_started','in_progress','awaiting_review','accepted','validated')) { if (-not $Mapping.Contains($name)) { throw "statusMapping.$name is required." } }
    if ($Mapping.validated -ne $true -or [string]$Mapping.resource -cne 'task' -or [string]$Mapping.metadataResource -cne 'task' -or [long]$Mapping.projectId -ne $ProjectId -or [long]$Mapping.metadataProjectId -ne $ProjectId) { throw 'statusMapping is not bound to the task project/resource.' }
    $metadata = @($Mapping.statusMetadata); $ids = [System.Collections.Generic.HashSet[long]]::new()
    foreach ($status in $metadata) { if ($status -isnot [System.Collections.IDictionary]) { throw 'statusMapping.statusMetadata must contain objects.' }; $id = if ($status.Contains('id')) { [long]$status.id } elseif ($status.Contains('statusId')) { [long]$status.statusId } else { 0L }; if ($id -lt 1 -or -not $ids.Add($id)) { throw 'statusMapping.statusMetadata must contain unique positive IDs.' }; $project = if ($status.Contains('project')) { $status.project } elseif ($status.Contains('projectId')) { $status.projectId } elseif ($status.Contains('project_id')) { $status.project_id } else { 0L }; if ($project -is [System.Collections.IDictionary]) { $project = if ($project.Contains('id')) { $project.id } else { $project.pk } }; if ([long]$project -ne $ProjectId -or -not $status.Contains('resource') -or [string]$status.resource -cne 'task') { throw "statusMapping metadata $id is not bound to the task project/resource." } }
    $metadataIds = @($ids | Sort-Object); if (($metadataIds -join ',') -cne (@($Mapping.metadataIds | ForEach-Object { [long]$_ } | Sort-Object) -join ',') -or [string]$Mapping.metadataDigest -cne (Hash-Object $metadata)) { throw 'statusMapping metadata provenance does not match the captured metadata.' }
    $mapped = [ordered]@{ not_started = [long]$Mapping.not_started; in_progress = [long]$Mapping.in_progress; awaiting_review = [long]$Mapping.awaiting_review; accepted = [long]$Mapping.accepted; blocked = if ($null -eq $Mapping.blocked) { $null } else { [long]$Mapping.blocked }; reviewFallback = ($Mapping.reviewFallback -eq $true) }
    $mappedIds = @($mapped.not_started,$mapped.in_progress,$mapped.awaiting_review,$mapped.accepted,$mapped.blocked | Where-Object { $null -ne $_ })
    foreach ($id in $mappedIds) { if (-not $ids.Contains([long]$id)) { throw "statusMapping contains an undiscovered status ID: $id." } }
    $duplicates = @($mappedIds | Group-Object | Where-Object Count -gt 1); $fallback = $Mapping.reviewFallback -eq $true -and $duplicates.Count -eq 1 -and [long]$Mapping.awaiting_review -eq [long]$Mapping.in_progress; if ($duplicates.Count -gt 0 -and -not $fallback) { throw 'statusMapping contains an unauthorized duplicate status ID.' }
    $expectedDigest = Hash-Object [ordered]@{ projectId = $ProjectId; resource = 'task'; statusMetadata = $metadata; mapping = $mapped }; if ([string]$Mapping.mappingDigest -cne $expectedDigest) { throw 'statusMapping.mappingDigest does not match the captured metadata and mapping.' }
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

function Invoke-GitMetadata {
    param([string] $Repository, [string[]] $Arguments, [string] $Name)
    $value = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not read $Name from the bound worktree." }
    return (($value -join [Environment]::NewLine).Trim())
}

function Get-TrustedRepositoryContext {
    param([System.Collections.IDictionary] $Packet, [switch] $RequireClean)
    $repository = [IO.Path]::GetFullPath([string]$Packet.repository.worktreePath)
    $root = [IO.Path]::GetFullPath((Invoke-GitMetadata $repository @('rev-parse','--show-toplevel') 'worktree root'))
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($root.TrimEnd('\','/'), $repository.TrimEnd('\','/'))) { throw 'Packet worktree does not match the Git root.' }
    $branch = Invoke-GitMetadata $repository @('rev-parse','--abbrev-ref','HEAD') 'branch'
    if ($branch -cne [string]$Packet.repository.branch) { throw 'The checked-out branch no longer matches the assignment packet.' }
    $head = Invoke-GitMetadata $repository @('rev-parse','HEAD') 'HEAD SHA'
    if ($head -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'The current HEAD is not a full Git SHA.' }
    $base = Invoke-GitMetadata $repository @('rev-parse',([string]$Packet.repository.baseSha + '^{commit}')) 'packet base SHA'
    if ($base -cne [string]$Packet.repository.baseSha) { throw 'The packet base SHA does not resolve to the trusted base commit.' }
    $status = Invoke-GitMetadata $repository @('status','--porcelain') 'worktree status'
    if ($RequireClean -and -not [string]::IsNullOrWhiteSpace($status)) { throw 'The reviewed worktree must be clean and committed.' }
    return [ordered]@{ repository = $repository; branch = $branch; currentSha = $head; baseSha = [string]$Packet.repository.baseSha; clean = [string]::IsNullOrWhiteSpace($status) }
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
    return [ordered]@{ reference = $read.reference; value = $packet; validation = $validated.data }
}

function Get-TrustedEvidenceBindings {
    param([System.Collections.IDictionary] $Action, [System.Collections.IDictionary] $Inspection, [System.Collections.IDictionary] $Owner, [System.Collections.IDictionary] $Packet, [System.Collections.IDictionary] $Result = $null)
    $targetIds = if ($Action.target -is [System.Collections.IDictionary] -and $Action.target.Contains('reviewCheckActionIds')) { @($Action.target.reviewCheckActionIds) } else { @() }
    $resultIds = if ($null -ne $Result -and $Result.Contains('reviewCheckActionIds')) { @($Result.reviewCheckActionIds) } else { @() }
    if ($Action.target -is [System.Collections.IDictionary] -and $Action.target.Contains('reviewCheckActionIds') -and $Action.target.reviewCheckActionIds -is [string]) { throw 'reviewCheckActionIds must be an array.' }
    if ($null -ne $Result -and $Result.Contains('reviewCheckActionIds') -and $Result.reviewCheckActionIds -is [string]) { throw 'Worker reviewCheckActionIds must be an array.' }
    $actionIds = @()
    if ($targetIds.Count -gt 0) { $actionIds = @($targetIds) + @($resultIds | Where-Object { @($targetIds | ForEach-Object { [string]$_ }) -notcontains [string]$_ }) } else { $actionIds = @($resultIds) }
    if ($actionIds.Count -eq 0) { return @() }
    if ($actionIds -is [string] -or $actionIds -isnot [System.Collections.IEnumerable]) { throw 'reviewCheckActionIds must be an array.' }
    $session = $Inspection.data.registry.sessions[[string]$Owner.sessionId]
    $bindings = @()
    foreach ($actionIdValue in @($actionIds)) {
        $actionId = [string]$actionIdValue
        if ([string]::IsNullOrWhiteSpace($actionId)) { throw 'reviewCheckActionIds cannot contain blank values.' }
        $checkAction = $Inspection.data.registry.actions[$actionId]
        if ($null -eq $checkAction -or [string]$checkAction.sessionId -cne [string]$Owner.sessionId -or [long]$checkAction.ownerGeneration -ne [long]$Owner.ownerGeneration -or [string]$checkAction.ticketKey -cne [string]$Owner.ticketKey -or [string]$checkAction.status -notin @('pending','observed')) { throw "reviewCheckActionId is not a current owned verification action: $actionId" }
        if ([string]$checkAction.kind -notin @('implementation_check','review_check')) { throw "reviewCheckActionId is not an implementation or review check: $actionId" }
        if ($checkAction.evidenceContext -isnot [System.Collections.IDictionary]) { throw "reviewCheckActionId has no trusted evidence context: $actionId" }
        $role = if ([string]$checkAction.kind -eq 'review_check') { 'reviewer' } else { 'implementer' }
        $profile = $Packet.profiles[$role]
        $profileName = if ($role -eq 'reviewer') { 'reviewerProfile' } else { 'implementationProfile' }
        if ($null -eq $profile -or $session.config[$profileName].model -cne [string]$profile.model -or $session.config[$profileName].effort -cne [string]$profile.effort) { throw "Verification action profile is not bound to the packet: $actionId" }
        $bindings += [ordered]@{ actionId = $actionId; actionKind = [string]$checkAction.kind; role = $role; profile = [ordered]@{ model = [string]$profile.model; effort = [string]$profile.effort }; command = [string]$checkAction.evidenceContext.command; criterionIds = @($checkAction.evidenceContext.criterionIds | ForEach-Object { [string]$_ }); coverage = if ($checkAction.evidenceContext.Contains('coverage')) { $checkAction.evidenceContext.coverage } else { $null } }
    }
    return @($bindings)
}

function Invoke-ReviewDecision {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Owner, [System.Collections.IDictionary] $Result, [System.Collections.IDictionary] $PacketInfo, [System.Collections.IDictionary] $Action)
    if (-not $Result.Contains('receiptReference')) { throw 'A publication result must include an immutable receiptReference.' }
    $receipt = Resolve-Reference $Result.receiptReference 'review receipt'
    if ($Action.target -isnot [System.Collections.IDictionary] -or -not $Action.target.Contains('reviewedSha')) { throw 'The prepared reviewer action has no frozen reviewed SHA.' }
    $trustedRepository = Get-TrustedRepositoryContext $PacketInfo.value -RequireClean
    $reviewedSha = Need $Action.target 'reviewedSha'
    if ($reviewedSha -cne [string]$trustedRepository.currentSha) { throw 'The prepared reviewer action is stale because the committed HEAD changed.' }
    $inspection = Get-Inspection
    $ticket = $inspection.data.registry.tickets[[string]$Owner.ticketKey]
    if ($null -eq $ticket) { throw 'The owned ticket was not found in the trusted registry.' }
    $targetPacketBindings = [ordered]@{ packetId = [string]$PacketInfo.value.packetId; packetHash = [string]$PacketInfo.value.packetHash; scopeHash = [string]$PacketInfo.value.scopeHash; baseSha = [string]$PacketInfo.value.repository.baseSha }
    foreach ($name in @('packetId','packetHash','scopeHash','baseSha')) { if ($Action.target -isnot [System.Collections.IDictionary] -or -not $Action.target.Contains($name) -or [string]$Action.target[$name] -cne [string]$targetPacketBindings[$name]) { throw "The prepared reviewer action is not bound to the supplied packet $name." } }
    $evidenceBindings = Get-TrustedEvidenceBindings $Action $inspection $Owner $PacketInfo.value $Result
    $currentCoverage = if ($Result.Contains('currentCoverage')) { $Result.currentCoverage } elseif ($InputObject.Contains('currentCoverage')) { $InputObject.currentCoverage } else { $null }
    if ($null -ne $currentCoverage) {
        if ($currentCoverage -isnot [System.Collections.IDictionary]) { throw 'currentCoverage must be an object.' }
        foreach ($name in @('revision','baseSha','environmentHash','dependenciesHash','changedKind','changedPaths')) { if (-not $currentCoverage.Contains($name)) { throw "currentCoverage.$name is required." } }
        if ([string]$currentCoverage.revision -cne [string]$trustedRepository.currentSha -or [string]$currentCoverage.baseSha -cne [string]$PacketInfo.value.repository.baseSha) { throw 'currentCoverage is not bound to the reviewed checkout.' }
        if ([string]$currentCoverage.changedKind -notin @('unchanged','documentation_only','code')) { throw 'currentCoverage.changedKind is not supported.' }
        if ($currentCoverage.changedPaths -is [string] -or $currentCoverage.changedPaths -isnot [System.Collections.IEnumerable]) { throw 'currentCoverage.changedPaths must be an array.' }
        $coveragePaths = @($currentCoverage.changedPaths | ForEach-Object { if ([string]::IsNullOrWhiteSpace([string]$_)) { throw 'currentCoverage.changedPaths entries must be nonblank.' }; [string]$_ })
        if ($currentCoverage.changedKind -eq 'documentation_only' -and $coveragePaths.Count -eq 0) { throw 'documentation_only currentCoverage must identify changed paths.' }
        if ([string]::IsNullOrWhiteSpace([string]$currentCoverage.environmentHash) -or [string]::IsNullOrWhiteSpace([string]$currentCoverage.dependenciesHash)) { throw 'currentCoverage environment and dependency hashes must be nonblank.' }
    }
    $review = [ordered]@{ receiptPath = $receipt.path; receiptSha256 = $receipt.sha256; expectedCriteria = @($PacketInfo.value.criteria); requiredCommands = @($PacketInfo.value.requiredCommands); unresolvedRequirements = @($PacketInfo.value.unresolvedRequirements); packetHash = [string]$PacketInfo.value.packetHash; allowedEvidenceActions = $evidenceBindings; currentSha = [string]$trustedRepository.currentSha; currentScopeHash = [string]$PacketInfo.value.scopeHash; currentBaseSha = [string]$trustedRepository.baseSha; expectedRunId = [string]$PacketInfo.value.runId; expectedActionId = [string]$Result.actionId; expectedTicketKey = [string]$Owner.ticketKey; repositoryPath = [string]$trustedRepository.repository; correctionRound = [int]$ticket.correctionRound }
    if ($null -ne $currentCoverage) { $review.currentCoverage = $currentCoverage }
    if ($Action.target.Contains('previousReviewedSha') -and -not [string]::IsNullOrWhiteSpace([string]$Action.target.previousReviewedSha)) { $review.previousReviewedSha = [string]$Action.target.previousReviewedSha }
    if ($Result.Contains('previousReviewedSha') -and $Action.target.Contains('previousReviewedSha') -and [string]$Result.previousReviewedSha -cne [string]$Action.target.previousReviewedSha) { throw 'Worker previousReviewedSha does not match the frozen reviewer action.' }
    if ($Result.Contains('evidenceReferences')) { $review.evidenceReferences = $Result.evidenceReferences; if ($Result.Contains('evidenceStateRoot')) { $review.evidenceStateRoot = [string]$Result.evidenceStateRoot } }
    $reviewPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('.review-input-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($reviewPath, ($review | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $lines = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'workflow-review.ps1') -Operation decide -InputPath $reviewPath 2>&1; $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
        try { $response = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Review helper returned invalid JSON: $raw" }
        if ($exitCode -ne 0 -or $response.ok -ne $true) { throw [string]$response.error.message }
        if ($null -ne $currentCoverage) { $response.data.currentCoverage = $currentCoverage }
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
    if ($null -eq $action) { throw "Worker result action was not prepared for this ticket: $([string]$result.actionId)." }
    if ([string]$action.ticketKey -cne [string]$owner.ticketKey -or [string]$action.sessionId -cne [string]$owner.sessionId -or [string]$action.target.workerId -cne [string]$result.workerId) { throw 'Worker result is not bound to the prepared ticket action and worker.' }
    $reviewRan = $false
    if ($result.status -eq 'blocked') { $decision = 'needs_input' }
    elseif ($result.status -ne 'completed') { $decision = 'wait' }
    elseif ($result.Contains('receiptReference')) {
        if (-not $InputObject.Contains('packetReference')) { throw 'A publication result must include its validated packetReference.' }
        $resultPacket = Read-ValidatedPacket $InputObject $owner
        $review = Invoke-ReviewDecision $InputObject $owner $result $resultPacket $action
        $reviewRan = $true
        $decision = [string]$review.decision
        if ($result.Contains('taskAcceptances')) {
            $rejectedTasks = @($result.taskAcceptances | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.accepted -ne $true })
            if ($rejectedTasks.Count -gt 0 -and $decision -ne 'correct') { throw 'Rejected child-task decisions require the bounded correction route.' }
            foreach ($rejected in $rejectedTasks) {
                if (-not $rejected.Contains('routedActionId') -or [string]::IsNullOrWhiteSpace([string]$rejected.routedActionId)) { throw "Rejected child task $($rejected.taskId) requires a same-worker routed correction action." }
                $routeAction = $inspection.data.registry.actions[[string]$rejected.routedActionId]
                if ($null -eq $routeAction -or [string]$routeAction.ticketKey -cne [string]$owner.ticketKey -or [string]$routeAction.sessionId -cne [string]$owner.sessionId -or [string]$routeAction.target.workerId -eq [string]$result.workerId -or [string]$routeAction.target.workerId -eq '') { throw "Correction route for child task $($rejected.taskId) is not bound to the same implementer." }
                if ([string]$routeAction.kind -notin @('worker_dispatch','implementation_check')) { throw "Correction route for child task $($rejected.taskId) is not an implementation action." }
                $sameImplementer = @($inspection.data.registry.actions.Values | Where-Object { $_.ticketKey -ceq $owner.ticketKey -and [string]$_.target.workerId -ceq [string]$routeAction.target.workerId -and [string]$_.target.workerId -ne [string]$result.workerId -and [string]$_.kind -in @('worker_dispatch','implementation_check') })
                if ($sameImplementer.Count -eq 0) { throw "Correction route for child task $($rejected.taskId) does not identify the previously assigned implementer." }
            }
        }
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
    $hasReview = $reviewRan
    $routeValidated = if ($decision -eq 'publish') { 'review_publish' } elseif ($hasReview) { 'review_verdict' } else { 'derived_from_validated_result' }
    $stateResultPayload = [ordered]@{ resultId = if ($result.Contains('resultId')) { [string]$result.resultId } else { [string]$result.cursor }; actionId = [string]$result.actionId; workerId = [string]$result.workerId; status = [string]$result.status; resultReference = $resultRead.reference; summary = if ($result.Contains('summary')) { [string]$result.summary } else { $null }; decision = $decision; routeValidated = $routeValidated }
    if ($hasReview) {
        $stateResultPayload.reviewedSha = [string]$review.reviewedSha
        $stateResultPayload.reviewAssessmentBound = ([string]$review.reviewedSha -cne '' -and [string]$review.reviewedSha -ceq [string]$review.currentSha)
        $stateResultPayload.reviewVerdict = [string]$review.verdict
        $stateResultPayload.scopeHash = [string]$resultPacket.value.scopeHash
        $stateResultPayload.baseSha = [string]$resultPacket.value.repository.baseSha
        $stateResultPayload.packetHash = [string]$resultPacket.value.packetHash
        $stateResultPayload.receiptReference = $result.receiptReference
        $stateResultPayload.evidenceReferences = if ($result.Contains('evidenceReferences')) { $result.evidenceReferences } else { @() }
        $stateResultPayload.evidenceStateRoot = if ($result.Contains('evidenceStateRoot')) { [string]$result.evidenceStateRoot } else { $null }
        if ($result.Contains('reviewCheckActionIds')) { $stateResultPayload.reviewCheckActionIds = @($result.reviewCheckActionIds | ForEach-Object { [string]$_ }) }
        if ($review.Contains('currentCoverage')) { $stateResultPayload.currentCoverage = $review.currentCoverage }
    }
    if ($result.Contains('taskAcceptances')) {
        $stateResultPayload.taskAcceptances = @($result.taskAcceptances | ForEach-Object {
            if ($_ -isnot [System.Collections.IDictionary] -or -not $_.Contains('taskId') -or -not $_.Contains('accepted') -or -not $_.Contains('reviewedSha') -or -not $_.Contains('criterionIds') -or -not $_.Contains('evidence')) { throw 'Worker taskAcceptances must contain taskId, accepted, reviewedSha, criterionIds, and evidence.' }
            [ordered]@{ taskId = [long]$_.taskId; accepted = [bool]$_.accepted; reviewedSha = [string]$_.reviewedSha; criterionIds = @($_.criterionIds); evidence = [string]$_.evidence; rejectionReason = if ($_.Contains('rejectionReason')) { [string]$_.rejectionReason } else { $null }; routedActionId = if ($_.Contains('routedActionId')) { [string]$_.routedActionId } else { $null } }
        })
    }
    $stateResult = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = $revision; ticketKey = $owner.ticketKey; cursor = [string]$result.cursor; actionId = [string]$result.actionId; workerId = [string]$result.workerId; decision = $decision; toPhase = $phase; reason = $reason; routeValidated = $routeValidated; result = $stateResultPayload }
    $accepted = Invoke-State 'accept-result' $stateResult
    return [ordered]@{ phase = $phase; decision = $decision; reason = $reason; actionId = [string]$result.actionId; workerId = [string]$result.workerId; requiredReferences = @($resultRead.reference) + @($result.receiptReference) + @($result.evidenceReferences); changedFields = @($accepted.data.changedFields); revision = [long]$accepted.revision }
}

function Get-PreviousReviewedSha {
    param([System.Collections.IDictionary] $Inspection, [System.Collections.IDictionary] $Owner)
    $prior = @($Inspection.data.registry.actions.Values | Where-Object {
        $_.ticketKey -ceq $Owner.ticketKey -and $_.sessionId -ceq $Owner.sessionId -and [long]$_.ownerGeneration -eq [long]$Owner.ownerGeneration -and $_.result -is [System.Collections.IDictionary] -and [string]$_.result.routeValidated -in @('review_publish','review_verdict') -and $_.result.reviewAssessmentBound -eq $true -and [string]$_.result.reviewVerdict -in @('pass','changes_requested','blocked') -and -not [string]::IsNullOrWhiteSpace([string]$_.result.reviewedSha)
    } | Sort-Object observedAt -Descending | Select-Object -First 1)[0]
    if ($null -eq $prior) { return $null }
    return [string]$prior.result.reviewedSha
}

function Invoke-PrepareExternal {
    param([System.Collections.IDictionary] $InputObject, [string] $ActionKind, [string] $ExternalOperation)
    $owner = Get-OwnerValues $InputObject
    $actionId = Need $InputObject 'actionId'; $workerId = Need $InputObject 'workerId'
    $packetRead = Read-ValidatedPacket $InputObject $owner; $packet = $packetRead.reference; $packetValue = $packetRead.value
    $authorized = @($packetValue.authority.authorizedActions); $excluded = @($packetValue.authority.excludedActions); $authorityAlternatives = if ($ActionKind -eq 'publication') { @($ExternalOperation,'publish') } else { @($ExternalOperation,'dispatch') }
    if ($excluded -contains $ExternalOperation -or @($authorityAlternatives | Where-Object { $authorized -contains $_ }).Count -eq 0) { throw "Packet authority does not authorize $ExternalOperation." }
    $existingInspection = Get-Inspection
    $ticket = $existingInspection.data.registry.tickets[[string]$owner.ticketKey]
    if ($ActionKind -eq 'publication') {
        if ($null -eq $ticket -or [string]$ticket.phase -cne 'publishing') { throw 'Publication preparation requires the owned ticket to be in publishing.' }
        $approvedReview = @($existingInspection.data.registry.actions.Values | Where-Object {
            $_.ticketKey -ceq $owner.ticketKey -and $_.sessionId -ceq $owner.sessionId -and [long]$_.ownerGeneration -eq [long]$owner.ownerGeneration -and $_.result -is [System.Collections.IDictionary] -and [string]$_.result.decision -ceq 'publish' -and [string]$_.result.routeValidated -ceq 'review_publish'
        } | Sort-Object observedAt -Descending | Select-Object -First 1)[0]
        $trustedRepository = Get-TrustedRepositoryContext $packetValue -RequireClean
        if ($null -eq $approvedReview -or -not $approvedReview.result.Contains('receiptReference') -or @($approvedReview.result.evidenceReferences).Count -eq 0 -or [string]$approvedReview.result.reviewedSha -cne [string]$trustedRepository.currentSha -or [string]$approvedReview.result.scopeHash -cne [string]$packetValue.scopeHash -or [string]$approvedReview.result.baseSha -cne [string]$packetValue.repository.baseSha -or [string]$approvedReview.result.packetHash -cne [string]$packetValue.packetHash) { throw 'Publication requires a current accepted review bound to this packet, committed HEAD, scope, and base.' }
        $revalidationResult = [ordered]@{}
        foreach ($key in $approvedReview.result.Keys) { $revalidationResult[$key] = $approvedReview.result[$key] }
        $revalidationResult.actionId = [string]$approvedReview.actionId
        $revalidated = Invoke-ReviewDecision $InputObject $owner $revalidationResult $packetRead $approvedReview
        if ([string]$revalidated.decision -cne 'publish') { throw 'Publication requires the accepted review to pass final receipt and evidence revalidation.' }
        $InputObject.approvedReviewActionId = [string]$approvedReview.actionId
        $InputObject.approvedReview = $approvedReview.result
    }
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
    $requiresReviewedSha = $template -match '\{\{reviewedSha\}\}'
    $reviewedSha = if ($InputObject.Contains('reviewedSha')) { [string]$InputObject.reviewedSha } else { $null }
    $previousReviewedSha = Get-PreviousReviewedSha $existingInspection $owner
    if ($requiresReviewedSha) {
        if ([string]::IsNullOrWhiteSpace($reviewedSha)) { throw 'Reviewer dispatch must name the frozen reviewed SHA.' }
        $trustedRepository = Get-TrustedRepositoryContext $packetValue
        if ($reviewedSha -cne [string]$trustedRepository.currentSha) { throw 'Reviewer dispatch reviewedSha must match the current committed HEAD.' }
        if ($InputObject.Contains('previousReviewedSha') -and -not [string]::IsNullOrWhiteSpace([string]$InputObject.previousReviewedSha)) {
            if ([string]::IsNullOrWhiteSpace($previousReviewedSha) -or [string]$InputObject.previousReviewedSha -cne $previousReviewedSha) { throw 'previousReviewedSha must match the latest trusted accepted review.' }
            $previousReviewedSha = [string]$InputObject.previousReviewedSha
        }
    } elseif ($InputObject.Contains('previousReviewedSha') -and -not [string]::IsNullOrWhiteSpace([string]$InputObject.previousReviewedSha)) {
        throw 'previousReviewedSha is only valid for a reviewer dispatch.'
    }
    $reviewCheckActionIds = @()
    if ($InputObject.Contains('reviewCheckActionIds')) {
        if ($InputObject.reviewCheckActionIds -is [string] -or $InputObject.reviewCheckActionIds -isnot [System.Collections.IEnumerable]) { throw 'reviewCheckActionIds must be an array.' }
        $reviewCheckActionIds = @($InputObject.reviewCheckActionIds | ForEach-Object { [string]$_ })
        if (@($reviewCheckActionIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'reviewCheckActionIds cannot contain blank values.' }
    } elseif ($ActionKind -eq 'worker_dispatch' -and $requiresReviewedSha) {
        $reviewCheckActionIds = @($existingInspection.data.registry.actions.Values | Where-Object {
            $_.ticketKey -ceq $owner.ticketKey -and $_.sessionId -ceq $owner.sessionId -and [long]$_.ownerGeneration -eq [long]$owner.ownerGeneration -and [string]$_.status -in @('pending','observed') -and [string]$_.kind -in @('implementation_check','review_check')
        } | ForEach-Object { [string]$_.actionId } | Sort-Object)
    }
    $schemaPath = Join-Path $PSScriptRoot '..\references\review-receipt-v1.schema.json'
    $replacements = @{ packetPath = $packet.path; packetHash = [string]$packetValue.packetHash; packetFileSha256 = $packet.sha256; packetId = [string]$packetValue.packetId; actionId = $actionId; workerId = $workerId; repositoryPath = $repositoryPath; reviewedSha = $reviewedSha; reviewCheckActionIds = ($reviewCheckActionIds -join ','); schemaPath = [IO.Path]::GetFullPath($schemaPath) }
    $prompt = $template
    foreach ($name in $replacements.Keys) { $prompt = $prompt.Replace('{{' + $name + '}}', [string]$replacements[$name]) }
    if ($prompt -match '\{\{[^}]+\}\}') { throw 'Prompt contains unresolved placeholders after trusted packet rendering.' }
    $promptPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('prompts\' + $actionId + '.md')
    if (-not [string]::IsNullOrWhiteSpace($prompt)) { Write-ImmutableText $promptPath $prompt }
    $inspection = Get-Inspection
    $payload = [ordered]@{ packetReference = [ordered]@{ path = $packet.path; sha256 = $packet.sha256; packetHash = [string]$packetValue.packetHash; packetId = [string]$packetValue.packetId }; promptReference = if ($promptReference) { [ordered]@{ path = $promptPath; sha256 = Get-FileSha256 $promptPath } } else { $null }; workerId = $workerId; operation = $ExternalOperation; reviewedSha = $reviewedSha; previousReviewedSha = $previousReviewedSha; reviewCheckActionIds = $reviewCheckActionIds; scopeHash = [string]$packetValue.scopeHash; baseSha = [string]$packetValue.repository.baseSha; approvedReviewActionId = if ($InputObject.Contains('approvedReviewActionId')) { [string]$InputObject.approvedReviewActionId } else { $null } }
    $target = [ordered]@{ workerId = $workerId; operation = $ExternalOperation; reviewedSha = $reviewedSha; previousReviewedSha = $previousReviewedSha; reviewCheckActionIds = $reviewCheckActionIds; packetId = [string]$packetValue.packetId; packetHash = [string]$packetValue.packetHash; scopeHash = [string]$packetValue.scopeHash; baseSha = [string]$packetValue.repository.baseSha }
    $request = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = [long]$inspection.revision; actionId = $actionId; ticketKey = $owner.ticketKey; actionKind = $ActionKind; target = $target; input = $payload; inputDigest = [string]$packetValue.packetHash }
    $prepared = Invoke-State 'prepare-action' $request
    return [ordered]@{ phase = if ($ActionKind -eq 'publication') { 'publishing' } else { 'preparing' }; decision = 'dispatch'; reason = 'prepared_external_action'; actionId = $actionId; workerId = $workerId; requiredReferences = @($packet) + @($payload.promptReference); changedFields = @('actions'); revision = [long]$prepared.revision; action = [ordered]@{ operation = $ExternalOperation; actionId = $actionId; workerId = $workerId; packet = $payload.packetReference; prompt = $payload.promptReference; reviewedSha = $payload.reviewedSha; previousReviewedSha = $payload.previousReviewedSha; reviewCheckActionIds = $payload.reviewCheckActionIds; approvedReviewActionId = $payload.approvedReviewActionId } }
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

function Invoke-CheckProgress {
    param([System.Collections.IDictionary] $InputObject)
    $runId = if ($InputObject.Contains('runId')) { Need $InputObject 'runId' } elseif ($InputObject.Contains('sessionId')) { Need $InputObject 'sessionId' } else { throw 'runId is required.' }
    $coordinatorThreadId = if ($InputObject.Contains('coordinatorThreadId')) { Need $InputObject 'coordinatorThreadId' } elseif ($InputObject.Contains('targetThreadId')) { Need $InputObject 'targetThreadId' } else { $null }
    $continuation = if ($InputObject.Contains('continuation')) { $InputObject.continuation } elseif ($InputObject.Contains('continuationContext')) { $InputObject.continuationContext } else { [ordered]@{ state = 'absent' } }
    if ($continuation -isnot [System.Collections.IDictionary]) { throw 'continuation must be an object.' }
    $waitStatus = if ($InputObject.Contains('waitStatus')) { [string]$InputObject.waitStatus } else { 'unchanged' }
    $workerStatus = if ($InputObject.Contains('workerStatus')) { [string]$InputObject.workerStatus } else { $null }
    $waitState = if ($InputObject.Contains('waitState')) { [string]$InputObject.waitState } else { $null }
    $recovery = $waitStatus -in @('interrupted','failed','missing_handoff','blocked') -or $workerStatus -in @('interrupted','failed','blocked') -or $waitState -eq 'missing_handoff'
    $targets = @()
    if ($InputObject.Contains('targets')) {
        if ($InputObject.targets -is [string] -or $InputObject.targets -isnot [System.Collections.IEnumerable]) { throw 'targets must be an array.' }
        foreach ($target in @($InputObject.targets)) {
            if ($target -isnot [System.Collections.IDictionary]) { throw 'Each progress target must be an object.' }
            $targetValue = [ordered]@{ threadId = Need $target 'threadId' }
            foreach ($name in @('hostId','afterCursor')) { if ($target.Contains($name)) { $targetValue[$name] = Need $target $name } }
            $targets += $targetValue
        }
    } elseif ($null -ne $coordinatorThreadId) {
        $targetValue = [ordered]@{ threadId = $coordinatorThreadId }
        foreach ($name in @('hostId','afterCursor')) { if ($InputObject.Contains($name)) { $targetValue[$name] = Need $InputObject $name } }
        $targets += $targetValue
    }
    if ($targets.Count -lt 1) { throw 'A native progress check must contain at least one target thread.' }
    $unresolved = @()
    if ($continuation.Contains('state') -and [string]$continuation.state -eq 'create_reserved') { $unresolved += [string]$continuation.reservationId }
    $resumeInstruction = "After reconciling the observed chat, checkout/branch, provider PR, and Taiga state, rerun heartbeat-plan with runId '$runId', the same coordinator thread, and the saved continuation context. Use native automation lookup to reconcile any reserved creation before retrying; do not create a second monitor or replay an ambiguous external action."
    return [ordered]@{
        phase = if ($recovery) { 'recovery_required' } else { 'observing' }
        decision = if ($recovery -or $unresolved.Count -gt 0) { 'reconcile_external_state' } else { 'check_progress' }
        reason = if ($recovery) { 'observed_failure_or_missing_handoff' } elseif ($unresolved.Count -gt 0) { 'heartbeat_creation_requires_reconciliation' } else { 'manual_progress_check' }
        actionId = $null; workerId = $null; requiredReferences = @(); changedFields = @(); revision = $null; stateMutation = $false; nativeOperation = if ($recovery) { 'read_thread' } else { 'wait_threads' }
        notifyUser = $recovery; manual = $true; runId = $runId; continuation = $continuation; waitThreadsArguments = [ordered]@{ targets = $targets; timeoutMs = 0 }; unresolvedActionIds = @($unresolved)
        recoveryChecklist = @('read compact recent worker/coordinator chat status', 'inspect the actual repository branch/worktree and committed HEAD', 'inspect provider/PR state', 'read current Taiga story/task state', 'reconcile every pending or uncertain action before retrying')
        resumeInstruction = $resumeInstruction
    }
}

function Invoke-ObserveWait {
    param([System.Collections.IDictionary] $InputObject)
    $status = Need $InputObject 'waitStatus'
    if ($status -notin @('unchanged','active','progressing','awaiting_approval','waiting_user','pending_approval','changed','completed','blocked','interrupted','failed','missing_handoff','user_input','paused')) { throw 'waitStatus is not supported.' }
    $compactStatus = if ($InputObject.Contains('compactStatus')) { $InputObject.compactStatus } else { $null }
    if ($null -ne $compactStatus -and $compactStatus -isnot [System.Collections.IDictionary]) { throw 'compactStatus must be an object.' }
    $workerStatus = if ($null -ne $compactStatus -and $compactStatus.Contains('workerStatus')) { [string]$compactStatus.workerStatus } elseif ($InputObject.Contains('workerStatus')) { [string]$InputObject.workerStatus } else { $null }
    $waitState = if ($null -ne $compactStatus -and $compactStatus.Contains('waitState')) { [string]$compactStatus.waitState } elseif ($InputObject.Contains('waitState')) { [string]$InputObject.waitState } else { $null }
    if ($null -ne $workerStatus -and $workerStatus -notin @('active','progressing','completed','interrupted','failed','blocked','waiting_user','unknown')) { throw 'workerStatus is not supported.' }
    if ($null -ne $waitState -and $waitState -notin @('none','expected_progress','user_approval','pending_approval','missing_handoff','unknown')) { throw 'waitState is not supported.' }
    $timeout = if ($InputObject.Contains('timeoutMs')) { [int]$InputObject.timeoutMs } else { 30000 }
    if ($timeout -lt 0 -or $timeout -gt 60000) { throw 'timeoutMs must be between 0 and 60000.' }
    $targets = @()
    if ($InputObject.Contains('targets')) {
        if ($InputObject.targets -is [string] -or $InputObject.targets -isnot [System.Collections.IEnumerable]) { throw 'targets must be an array.' }
        $targetValues = @($InputObject.targets); if ($targetValues.Count -lt 1 -or $targetValues.Count -gt 8) { throw 'targets must contain between one and eight threads.' }
        foreach ($target in $targetValues) {
            if ($target -isnot [System.Collections.IDictionary]) { throw 'Each wait target must be an object.' }
            $targetId = Need $target 'threadId'; $targetValue = [ordered]@{ threadId = $targetId }
            if ($target.Contains('hostId')) { $targetValue.hostId = Need $target 'hostId' }; if ($target.Contains('afterCursor')) { $targetValue.afterCursor = Need $target 'afterCursor' }
            $targets += $targetValue
        }
    } elseif ($InputObject.Contains('threadId')) {
        $targetValue = [ordered]@{ threadId = Need $InputObject 'threadId' }; if ($InputObject.Contains('hostId')) { $targetValue.hostId = Need $InputObject 'hostId' }; if ($InputObject.Contains('afterCursor')) { $targetValue.afterCursor = Need $InputObject 'afterCursor' }; $targets += $targetValue
    }
    if ($targets.Count -lt 1) { throw 'A native wait descriptor must contain at least one target thread.' }
    $recovery = $status -in @('interrupted','failed','missing_handoff') -or $workerStatus -in @('interrupted','failed') -or $waitState -eq 'missing_handoff'
    $blockedSignal = $status -eq 'blocked' -or $workerStatus -eq 'blocked'
    $completedSignal = $status -eq 'completed' -or $workerStatus -eq 'completed'
    $meaningful = $recovery -or $blockedSignal -or $completedSignal -or $status -eq 'changed'
    $healthy = -not $meaningful -and ($status -in @('unchanged','active','progressing') -or $workerStatus -in @('active','progressing') -or $waitState -eq 'expected_progress')
    $awaitingApproval = -not $meaningful -and ($status -in @('awaiting_approval','waiting_user','pending_approval') -or $waitState -in @('user_approval','pending_approval') -or ($status -eq 'user_input' -and $waitState -eq 'user_approval'))
    $quiet = $healthy -or $awaitingApproval -or $status -eq 'paused'
    $decision = if ($recovery) { 'reconcile_recovery' } elseif ($blockedSignal) { 'fetch_blocker' } elseif ($completedSignal) { 'fetch_result' } elseif ($status -eq 'changed') { 'inspect_changed_state' } elseif ($healthy) { 'continue_wait' } elseif ($awaitingApproval) { 'heartbeat_quiet' } elseif ($status -eq 'user_input') { 'needs_input' } elseif ($status -eq 'paused') { 'heartbeat_quiet' } else { throw 'waitStatus could not be classified.' }
    $nativeOperation = if ($recovery -or $blockedSignal -or $completedSignal -or $status -eq 'changed') { 'read_thread' } elseif ($quiet) { 'wait_threads' } elseif ($status -eq 'user_input') { 'surface_user_input' } elseif ($status -eq 'paused') { 'wait_threads' } else { throw 'waitStatus native operation could not be classified.' }
    if ($status -eq 'unchanged' -and $InputObject.Contains('resultReference')) { throw 'Unchanged waits cannot reopen result evidence.' }
    return [ordered]@{ phase = $null; decision = $decision; reason = if ($recovery) { 'observed_failure_or_missing_handoff_requires_reconciliation' } elseif ($blockedSignal) { 'blocked_event_requires_detail' } elseif ($completedSignal) { 'completed_event_requires_detail' } elseif ($status -eq 'changed') { 'meaningful_state_change' } elseif ($healthy) { 'healthy_or_expected_progress' } elseif ($awaitingApproval) { 'awaiting_user_approval' } elseif ($status -eq 'unchanged') { 'no_state_change' } else { "wait_$status" }; actionId = $null; workerId = if ($InputObject.Contains('workerId')) { [string]$InputObject.workerId } else { $null }; requiredReferences = @(); changedFields = @(); stateMutation = $false; nativeOperation = $nativeOperation; waitThreadsArguments = [ordered]@{ targets = $targets; timeoutMs = $timeout }; detailFetch = ($meaningful -and -not $quiet); notifyUser = if ($quiet) { $false } else { $true }; notification = if ($quiet) { 'none' } elseif ($recovery) { 'recovery_requires_attention' } else { 'meaningful_state_change' }; contextRead = 'compact_worker_and_wait_state_only'; contextFootprint = [ordered]@{ fields = @('workerStatus','waitState'); heavyweightReads = 0; sourceRead = $false; ticketReread = $false; diffReview = $false; testRerun = $false }; compactStatus = [ordered]@{ workerStatus = $workerStatus; waitState = $waitState }; recovery = if ($recovery) { [ordered]@{ required = $true; retryAllowed = $false; reconciliationRequired = $true; checklist = @('read the recent worker/coordinator chat state', 'inspect the actual repository branch/worktree and committed HEAD', 'inspect provider/PR state', 'read current Taiga story/task state', 'reconcile the observed outcome before any authorized retry') } } else { $null } }
}

function Invoke-HeartbeatPlan {
    param([System.Collections.IDictionary] $InputObject)
    # Heartbeat planning is deliberately stateless. The caller persists only this
    # small continuation record; the workflow-state registry is not part of the
    # heartbeat's setup, recovery, or idempotency protocol.
    $runId = if ($InputObject.Contains('runId')) { Need $InputObject 'runId' } elseif ($InputObject.Contains('sessionId')) { Need $InputObject 'sessionId' } else { throw 'runId is required.' }
    $targetThreadId = if ($InputObject.Contains('coordinatorThreadId')) { Need $InputObject 'coordinatorThreadId' } elseif ($InputObject.Contains('targetThreadId')) { Need $InputObject 'targetThreadId' } else { throw 'coordinatorThreadId is required.' }
    $scopeHash = if ($InputObject.Contains('scopeHash')) { Need $InputObject 'scopeHash' } elseif ($InputObject.Contains('scope') -and $null -ne $InputObject.scope) { Hash-Object $InputObject.scope } else { Hash-Object @($runId,$targetThreadId) }
    $lifecycle = if ($InputObject.Contains('lifecycle')) { [string]$InputObject.lifecycle } else { 'active' }
    if ($lifecycle -notin @('active','pausing','paused','cancelling','cancelled','completed')) { throw 'lifecycle is not supported.' }
    $requestedPolicy = if ($InputObject.Contains('notificationPolicy')) { [string]$InputObject.notificationPolicy } else { 'failed_runs_only' }
    if ($requestedPolicy -notin @('failed_runs_only','')) { throw 'notificationPolicy must be failed_runs_only or null.' }
    $continuation = if ($InputObject.Contains('continuation')) { $InputObject.continuation } elseif ($InputObject.Contains('continuationContext')) { $InputObject.continuationContext } else { [ordered]@{ state = 'absent' } }
    if ($continuation -isnot [System.Collections.IDictionary]) { throw 'continuation must be an object.' }
    $continuationState = if ($continuation.Contains('state')) { [string]$continuation.state } else { 'absent' }
    if ($continuationState -notin @('absent','create_reserved','create_pending','active')) { throw 'continuation.state is not supported.' }
    if ($continuationState -ne 'absent') {
        $identityMap = [ordered]@{ runId = $runId; coordinatorThreadId = $targetThreadId; scopeHash = $scopeHash }
        foreach ($identity in $identityMap.GetEnumerator()) {
            if (-not $continuation.Contains($identity.Key) -or [string]$continuation[$identity.Key] -cne [string]$identity.Value) { throw "continuation.$($identity.Key) does not match this run." }
        }
    }
    $existing = if ($continuation.Contains('heartbeatId')) { [string]$continuation.heartbeatId } elseif ($InputObject.Contains('heartbeatId')) { [string]$InputObject.heartbeatId } else { '' }
    $scheduleState = if ($continuation.Contains('scheduleState')) { [string]$continuation.scheduleState } elseif ($InputObject.Contains('scheduleState')) { [string]$InputObject.scheduleState } elseif (-not [string]::IsNullOrWhiteSpace($existing)) { 'ACTIVE' } else { $null }
    if ($scheduleState -is [string] -and $scheduleState -notin @('ACTIVE','PAUSED','UNKNOWN')) { throw 'scheduleState is not supported.' }
    $pendingScheduleState = if ($continuation.Contains('pendingScheduleState')) { [string]$continuation.pendingScheduleState } else { $null }
    if ($null -ne $pendingScheduleState -and $pendingScheduleState -notin @('ACTIVE','PAUSED')) { throw 'pendingScheduleState is not supported.' }
    if ($continuationState -eq 'active' -and [string]::IsNullOrWhiteSpace($existing)) { throw 'An active heartbeat continuation requires heartbeatId.' }
    if ($continuationState -in @('create_reserved','create_pending') -and $continuation.Contains('heartbeatId') -and -not [string]::IsNullOrWhiteSpace([string]$continuation.heartbeatId)) { throw 'A heartbeat creation continuation cannot already contain heartbeatId.' }
    if ($continuationState -eq 'absent' -and $InputObject.Contains('heartbeatId')) { throw 'heartbeatId requires an identity-bound continuation.' }
    $name = if ($continuation.Contains('name')) { Need $continuation 'name' } else { "taiga-recovery-$runId" }
    $prompt = "Recovery-only check for scoped coordinator run $runId (scope $scopeHash). Inspect compact worker and continuation status only. Stay quiet when unchanged, active, progressing, or awaiting user approval. Do not treat elapsed time as failure. Investigate only observed interruption, failed action, completed work with a missing handoff, or another meaningful recovery signal; reconcile actual chat, Git, provider, and Taiga state before an authorized retry, and never replay an ambiguous write or create a nested schedule. Normal worker messages and user approvals remain the workflow triggers."
    $creationAttempt = if ($continuation.Contains('creationAttempt')) { [int]$continuation.creationAttempt } else { 0 }
    if ($creationAttempt -lt 0) { throw 'creationAttempt must be nonnegative.' }
    $reservationId = if ($continuation.Contains('reservationId')) { Need $continuation 'reservationId' } else { "heartbeat-reservation-$((Hash-Object @($runId,$scopeHash,$creationAttempt)).Substring(0,16))" }
    $creationReconciliation = $null
    if ($InputObject.Contains('creationReconciliation')) {
        if ($InputObject.creationReconciliation -isnot [System.Collections.IDictionary]) { throw 'creationReconciliation must be an object.' }
        $creationReconciliation = $InputObject.creationReconciliation
        foreach ($key in @('reservationId','outcome','checkedAtUtc')) { if (-not $creationReconciliation.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$creationReconciliation[$key])) { throw "creationReconciliation.$key is required." } }
        if ([string]$creationReconciliation.reservationId -cne $reservationId) { throw 'creationReconciliation.reservationId does not match the continuation reservation.' }
        if ([string]$creationReconciliation.outcome -notin @('not_found','found')) { throw 'creationReconciliation.outcome must be not_found or found.' }
        if ([string]$creationReconciliation.outcome -eq 'found') {
            if (-not $creationReconciliation.Contains('heartbeatId') -or [string]::IsNullOrWhiteSpace([string]$creationReconciliation.heartbeatId)) { throw 'A found creation reconciliation requires heartbeatId.' }
            if ($continuationState -notin @('create_reserved','create_pending')) { throw 'A found creation reconciliation requires a creation continuation.' }
            $existing = [string]$creationReconciliation.heartbeatId
            $scheduleState = if ($creationReconciliation.Contains('scheduleState')) { [string]$creationReconciliation.scheduleState } else { 'ACTIVE' }
            if ($scheduleState -notin @('ACTIVE','PAUSED','UNKNOWN')) { throw 'creationReconciliation.scheduleState is not supported.' }
        }
    }
    $hasFreshCreationReconciliation = $null -ne $creationReconciliation
    $scheduleConfirmation = $null
    $scheduleConfirmed = $false
    if ($InputObject.Contains('scheduleConfirmation')) {
        if ($InputObject.scheduleConfirmation -isnot [System.Collections.IDictionary]) { throw 'scheduleConfirmation must be an object.' }
        $scheduleConfirmation = $InputObject.scheduleConfirmation
        if ($scheduleConfirmation.Contains('confirmed') -and [bool]$scheduleConfirmation.confirmed) {
            if (-not $scheduleConfirmation.Contains('status') -or [string]$scheduleConfirmation.status -notin @('ACTIVE','PAUSED')) { throw 'A confirmed scheduleConfirmation requires status ACTIVE or PAUSED.' }
            if ($null -eq $pendingScheduleState -or [string]$scheduleConfirmation.status -cne $pendingScheduleState) { throw 'scheduleConfirmation does not match the pending schedule transition.' }
            $scheduleState = [string]$scheduleConfirmation.status
            $pendingScheduleState = $null
            $scheduleConfirmed = $true
        }
    }
    $baseContinuation = [ordered]@{ runId = $runId; coordinatorThreadId = $targetThreadId; scopeHash = $scopeHash; name = $name }
    $heartbeat = [ordered]@{
        heartbeatId = if ([string]::IsNullOrWhiteSpace($existing)) { $null } else { $existing }
        runId = $runId
        coordinatorThreadId = $targetThreadId
        scopeHash = $scopeHash
        name = $name
        intervalMinutes = 30
        rrule = [ordered]@{ intervalMinutes = 30 }
        prompt = $prompt
        notificationPolicy = if ([string]::IsNullOrWhiteSpace($requestedPolicy)) { $null } else { $requestedPolicy }
        destination = 'thread'
        targetThreadId = $targetThreadId
        nestedSchedules = $false
        quietWhenUnchanged = $true
    }
    foreach ($key in @('name','notificationPolicy','targetThreadId')) {
        if ($continuation.Contains($key)) { $heartbeat[$key] = $continuation[$key] }
    }
    $scheduleReconciliationRequired = $null -ne $pendingScheduleState -and -not $scheduleConfirmed
    $automationRequest = if ($scheduleReconciliationRequired) {
        $null
    } elseif ($lifecycle -in @('pausing','cancelling')) {
        $null
    } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_reserved' -and $hasFreshCreationReconciliation -and [string]$creationReconciliation.outcome -eq 'not_found') {
        $request = [ordered]@{ kind = 'heartbeat'; mode = 'create'; name = [string]$heartbeat.name; prompt = [string]$heartbeat.prompt; rrule = $heartbeat.rrule; status = 'ACTIVE'; destination = 'thread'; targetThreadId = [string]$heartbeat.targetThreadId }
        if (-not [string]::IsNullOrWhiteSpace([string]$heartbeat.notificationPolicy)) { $request.notificationPolicy = [string]$heartbeat.notificationPolicy }
        $request
    } elseif (-not [string]::IsNullOrWhiteSpace($existing) -and $lifecycle -eq 'paused' -and $scheduleState -ne 'PAUSED') {
        [ordered]@{ kind = 'heartbeat'; mode = 'update'; id = $existing; status = 'PAUSED' }
    } elseif (-not [string]::IsNullOrWhiteSpace($existing) -and $lifecycle -in @('cancelled','completed')) {
        [ordered]@{ kind = 'heartbeat'; mode = 'delete'; id = $existing }
    } elseif (-not [string]::IsNullOrWhiteSpace($existing) -and $lifecycle -eq 'active' -and $scheduleState -eq 'PAUSED') {
        [ordered]@{ kind = 'heartbeat'; mode = 'update'; id = $existing; status = 'ACTIVE' }
    } elseif (-not [string]::IsNullOrWhiteSpace($existing) -and $lifecycle -eq 'active') {
        [ordered]@{ mode = 'view'; id = $existing }
    } else {
        $null
    }
    $decision = if ($scheduleReconciliationRequired) { 'reconcile_heartbeat_schedule' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'absent') { 'reserve_heartbeat' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_reserved' -and -not $hasFreshCreationReconciliation) { 'reconcile_heartbeat_creation' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_reserved' -and [string]$creationReconciliation.outcome -eq 'found') { 'adopt_heartbeat' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_reserved') { 'create_heartbeat' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_pending' -and $hasFreshCreationReconciliation -and [string]$creationReconciliation.outcome -eq 'found') { 'adopt_heartbeat' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_pending' -and $hasFreshCreationReconciliation) { 'rearm_heartbeat_creation' } elseif ($lifecycle -eq 'active' -and $continuationState -eq 'create_pending') { 'reconcile_heartbeat_creation' } elseif ($scheduleConfirmed) { 'confirm_heartbeat_schedule' } elseif ($lifecycle -in @('pausing','cancelling')) { 'wait_for_quiescence' } elseif ($lifecycle -eq 'paused' -and $null -ne $automationRequest) { 'disable_heartbeat' } elseif ($lifecycle -eq 'paused' -and -not [string]::IsNullOrWhiteSpace($existing)) { 'heartbeat_paused' } elseif ($lifecycle -in @('cancelled','completed') -and $null -ne $automationRequest) { 'remove_heartbeat' } elseif ($lifecycle -eq 'active' -and $scheduleState -eq 'PAUSED' -and $null -ne $automationRequest) { 'reactivate_heartbeat' } elseif ($lifecycle -eq 'active' -and -not [string]::IsNullOrWhiteSpace($existing)) { 'reuse_heartbeat' } else { 'no_heartbeat' }
    $nextContinuation = $baseContinuation
    if ($decision -eq 'rearm_heartbeat_creation') { $nextAttempt = $creationAttempt + 1; $nextContinuation.state = 'create_reserved'; $nextContinuation.creationAttempt = $nextAttempt; $nextContinuation.reservationId = "heartbeat-reservation-$((Hash-Object @($runId,$scopeHash,$nextAttempt)).Substring(0,16))" }
    elseif ($decision -eq 'create_heartbeat') { $nextContinuation.state = 'create_pending'; $nextContinuation.creationAttempt = $creationAttempt; $nextContinuation.reservationId = $reservationId }
    elseif ($decision -in @('reserve_heartbeat','reconcile_heartbeat_creation')) { $nextContinuation.state = $continuationState -eq 'create_pending' ? 'create_pending' : 'create_reserved'; $nextContinuation.creationAttempt = $creationAttempt; $nextContinuation.reservationId = $reservationId }
    elseif (-not [string]::IsNullOrWhiteSpace($existing)) { $nextContinuation.state = 'active'; $nextContinuation.heartbeatId = $existing; $nextContinuation.scheduleState = $scheduleState; if ($null -ne $pendingScheduleState) { $nextContinuation.pendingScheduleState = $pendingScheduleState } }
    else { $nextContinuation.state = 'absent' }
    if ($null -ne $pendingScheduleState -and $nextContinuation.state -eq 'active') { $nextContinuation.pendingScheduleState = $pendingScheduleState }
    $reason = if ($decision -eq 'reserve_heartbeat') { 'reserve_before_external_creation' } elseif ($decision -eq 'reconcile_heartbeat_creation') { 'creation_reserved_reconcile_before_retry' } elseif ($decision -eq 'rearm_heartbeat_creation') { 'interrupted_creation_requires_a_new_reservation' } elseif ($decision -eq 'create_heartbeat') { 'fresh_reconciliation_allows_one_pending_creation' } elseif ($decision -eq 'reconcile_heartbeat_schedule') { 'schedule_update_requires_external_confirmation' } elseif ($decision -eq 'confirm_heartbeat_schedule') { 'schedule_update_confirmed' } elseif ($decision -eq 'adopt_heartbeat') { 'reconcile_existing_heartbeat' } elseif ($lifecycle -in @('pausing','cancelling')) { 'wait_for_quiescent_pause_or_cancel' } elseif ($lifecycle -eq 'paused') { 'paused_run_does_not_tick' } elseif ($lifecycle -in @('cancelled','completed')) { 'terminal_run_does_not_tick' } elseif ($decision -eq 'reactivate_heartbeat') { 'resume_existing_paused_heartbeat' } elseif ($decision -eq 'reuse_heartbeat') { 'existing_scoped_heartbeat' } else { 'no_heartbeat_required' }
    $nativeOperation = if ($decision -in @('reconcile_heartbeat_creation','reconcile_heartbeat_schedule')) { 'reconcile_automation' } elseif ($null -eq $automationRequest) { 'none' } else { 'automation_update' }
    return [ordered]@{ phase = $lifecycle; decision = $decision; reason = $reason; actionId = $null; workerId = $null; requiredReferences = @(); changedFields = @(); revision = $null; stateMutation = $false; nativeOperation = $nativeOperation; automationRequest = $automationRequest; heartbeat = $heartbeat; lifecycle = $lifecycle; continuation = $nextContinuation; reservation = if ($decision -in @('reconcile_heartbeat_creation','rearm_heartbeat_creation')) { [ordered]@{ id = [string]$nextContinuation.reservationId; action = 'find_existing_by_reservation_or_scope'; createAllowed = $false; requiresFreshReconciliation = $true } } else { $null }; scheduleReconciliation = if ($decision -eq 'reconcile_heartbeat_schedule') { [ordered]@{ currentState = $scheduleState; requestedState = $pendingScheduleState; confirmed = $false } } elseif ($decision -in @('disable_heartbeat','reactivate_heartbeat')) { [ordered]@{ currentState = $scheduleState; requestedState = [string]$automationRequest.status; confirmed = $false } } else { $null }; noTickRestart = ($lifecycle -ne 'active') }
}

function Invoke-RelayTaskProgress {
    param([System.Collections.IDictionary] $InputObject)
    $progressRoot = [IO.Path]::GetFullPath((Need $InputObject 'progressRoot')); if (-not (Test-Path -LiteralPath $progressRoot -PathType Container)) { throw 'progressRoot is inaccessible.' }
    $consumerId = Need $InputObject 'consumerId'; if ($InputObject.Contains('cursor') -and [long]$InputObject.cursor -lt 0) { throw 'cursor must be nonnegative.' }
    if (-not $InputObject.Contains('statusMapping') -or $InputObject.statusMapping -isnot [System.Collections.IDictionary] -or $InputObject.statusMapping.validated -ne $true) { throw 'relay requires a validated task statusMapping.' }
    $packet = Get-ValidatedPacketBinding $InputObject; $mapping = $InputObject.statusMapping; Assert-StatusMappingProvenance $mapping ([long]$packet.projectId)
    $request = [ordered]@{ consumerId = $consumerId; advance = if ($InputObject.Contains('advance')) { [bool]$InputObject.advance } else { $true } }
    if ($InputObject.Contains('cursor')) { $request.cursor = [long]$InputObject.cursor }
    if ($InputObject.Contains('runId')) { $request.runId = [string]$InputObject.runId }
    $request.packetBinding = $packet
    $inputPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('.progress-relay-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($inputPath, ($request | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $lines = & pwsh -NoProfile -File $script:ProgressScript -Operation consume -InputPath $inputPath -StateRoot $progressRoot 2>&1
        $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
        try { $progress = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Progress helper returned invalid JSON: $raw" }
        if ($exitCode -ne 0 -or $progress.ok -ne $true) { throw [string]$progress.error.message }
    } finally { if (Test-Path -LiteralPath $inputPath -PathType Leaf) { Remove-Item -LiteralPath $inputPath -Force } }
    $mapping = $InputObject.statusMapping
    $proposals = @($progress.data.transitions | ForEach-Object {
        $logical = [string]$_.logicalState
        if ($logical -eq 'accepted') { throw 'Worker progress cannot accept a task; explicit reviewer acceptance is required.' }
        $event = if ($_.Contains('event') -and $_.event -is [System.Collections.IDictionary]) { $_.event } else { throw "Progress transition $($_.eventId) did not carry its complete event." }
        [ordered]@{ eventId = [string]$_.eventId; actionId = [string]$_.actionId; sequence = [long]$_.sequence; ticketKey = [string]$_.ticketKey; projectId = [long]$_.projectId; parentStoryId = [long]$_.parentStoryId; taskId = [long]$_.taskId; packetHash = [string]$_.packetHash; scopeHash = [string]$_.scopeHash; bindingDigest = [string]$_.bindingDigest; eventType = [string]$_.eventType; logicalState = $logical; statusId = if ($mapping -is [System.Collections.IDictionary] -and $mapping.Contains($logical)) { [long]$mapping[$logical] } else { $null }; currentSha = [string]$_.currentSha; criterionIds = @($_.criterionIds); evidence = $_.evidence; progressBinding = $event }
    })
    return [ordered]@{ phase = $null; decision = if ($progress.data.unchanged) { 'continue_wait' } else { 'relay_task_status_observations' }; reason = if ($progress.data.unchanged) { 'no_new_task_progress' } else { if (@($progress.data.pending).Count -gt 0) { 'pending_task_actions_require_reconciliation' } else { 'new_task_progress' } }; actionId = $null; workerId = $null; requiredReferences = @(); changedFields = if ($progress.data.stateMutation) { @('progress.cursor','task.evidence.pending') } else { @() }; revision = $null; stateMutation = [bool]$progress.data.stateMutation; nativeOperation = 'bounded_progress_observation'; consumerId = $consumerId; cursor = [long]$progress.data.cursor; packetBinding = $packet; statusMappingDigest = [string]$mapping.mappingDigest; events = @($progress.data.events); pending = @($progress.data.pending); taskTransitions = $proposals; taigaWrites = @($progress.data.taigaWrites) }
}

function Invoke-AcknowledgeTaskProgress {
    param([System.Collections.IDictionary] $InputObject)
    $progressRoot = [IO.Path]::GetFullPath((Need $InputObject 'progressRoot')); if (-not (Test-Path -LiteralPath $progressRoot -PathType Container)) { throw 'progressRoot is inaccessible.' }
    $request = [ordered]@{ consumerId = Need $InputObject 'consumerId'; outcomes = @($InputObject.outcomes) }
    $inputPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('.progress-ack-' + [Guid]::NewGuid().ToString('N') + '.json')
    try { [IO.File]::WriteAllText($inputPath, ($request | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false)); $lines = & pwsh -NoProfile -File $script:ProgressScript -Operation acknowledge -InputPath $inputPath -StateRoot $progressRoot 2>&1; $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine; try { $response = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Progress helper returned invalid JSON: $raw" }; if ($exitCode -ne 0 -or $response.ok -ne $true) { throw [string]$response.error.message } } finally { if (Test-Path -LiteralPath $inputPath -PathType Leaf) { Remove-Item -LiteralPath $inputPath -Force } }
    return [ordered]@{ phase = $null; decision = if (@($response.data.pending).Count -eq 0) { 'task_progress_acknowledged' } else { 'task_progress_partially_acknowledged' }; reason = 'durable_task_outcomes_recorded'; actionId = $null; workerId = $null; requiredReferences = @(); changedFields = @('progress.pending','progress.taskStates'); revision = $null; stateMutation = $true; consumerId = [string]$response.data.consumerId; cursor = [long]$response.data.cursor; acknowledged = @($response.data.acknowledged); pending = @($response.data.pending) }
}

try {
    $inputObject = Read-Object
    if ([string]::IsNullOrWhiteSpace($StateRoot) -and $Operation -notin @('observe-wait','heartbeat-plan','check-progress')) { throw 'StateRoot is required for this operation.' }
    $data = switch ($Operation) {
        'accept-result' { Invoke-AcceptResult $inputObject }
        'prepare-dispatch' { Invoke-PrepareExternal $inputObject 'worker_dispatch' 'create_or_message_worker' }
        'prepare-publication' { Invoke-PrepareExternal $inputObject 'publication' 'push_or_create_pr' }
        'record-external' { Invoke-RecordExternal $inputObject }
        'reconcile-external' { Invoke-RecordExternal $inputObject }
        'observe-wait' { Invoke-ObserveWait $inputObject }
        'heartbeat-plan' { Invoke-HeartbeatPlan $inputObject }
        'check-progress' { Invoke-CheckProgress $inputObject }
        'status' { Invoke-Status $inputObject }
        'relay-task-progress' { Invoke-RelayTaskProgress $inputObject }
        'ack-task-progress' { Invoke-AcknowledgeTaskProgress $inputObject }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_coordinate'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
