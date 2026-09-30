[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('accept-result','prepare-dispatch','prepare-publication','record-external','status')]
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

function Invoke-AcceptResult {
    param([System.Collections.IDictionary] $InputObject)
    $owner = Get-OwnerValues $InputObject
    $resultRead = Read-ReferenceJson $InputObject.resultReference 'result'
    $result = $resultRead.value
    foreach ($name in @('cursor','actionId','workerId','status')) { Need $result $name | Out-Null }
    $inspection = Get-Inspection; $revision = [long]$inspection.revision
    $consume = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = $revision; ticketKey = $owner.ticketKey; cursor = [string]$result.cursor; actionId = [string]$result.actionId; result = [ordered]@{ resultId = if ($result.Contains('resultId')) { [string]$result.resultId } else { [string]$result.cursor }; workerId = [string]$result.workerId; status = [string]$result.status; resultReference = $resultRead.reference; summary = if ($result.Contains('summary')) { [string]$result.summary } else { $null } } }
    $consumed = Invoke-State 'consume-result' $consume
    $decision = if ($result.Contains('decision')) { [string]$result.decision } elseif ($result.status -eq 'blocked') { 'needs_input' } elseif ($result.status -eq 'completed') { 'review' } else { 'wait' }
    $reason = if ($result.Contains('reason')) { [string]$result.reason } else { "worker_$($result.status)" }
    $changed = @('lastResultCursor')
    $phase = if ($result.Contains('nextPhase')) { [string]$result.nextPhase } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($phase)) {
        $transition = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = [long]$consumed.revision; ticketKey = $owner.ticketKey; toPhase = $phase; reason = $reason }
        $transitionResult = Invoke-State 'transition' $transition
        $changed += 'phase'; $phase = [string]$transitionResult.data.to
        $revision = [long]$transitionResult.revision
    } else { $revision = [long]$consumed.revision }
    return [ordered]@{ phase = $phase; decision = $decision; reason = $reason; actionId = [string]$result.actionId; workerId = [string]$result.workerId; requiredReferences = @($resultRead.reference) + @($result.receiptReference) + @($result.evidenceReferences); changedFields = $changed; revision = $revision }
}

function Invoke-PrepareExternal {
    param([System.Collections.IDictionary] $InputObject, [string] $ActionKind, [string] $ExternalOperation)
    $owner = Get-OwnerValues $InputObject
    $packet = Resolve-Reference $InputObject.packetReference 'packet'
    $actionId = Need $InputObject 'actionId'; $workerId = Need $InputObject 'workerId'
    $promptReference = $null
    if ($InputObject.Contains('promptReference')) {
        $promptReference = Resolve-Reference $InputObject.promptReference 'prompt'
        $template = Get-Content -Raw -LiteralPath $promptReference.path
    } else { $template = '' }
    $prompt = $template.Replace('{{packetPath}}', $packet.path).Replace('{{packetHash}}', $packet.sha256).Replace('{{actionId}}', $actionId).Replace('{{workerId}}', $workerId)
    $promptPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('prompts\' + $actionId + '.md')
    if (-not [string]::IsNullOrWhiteSpace($prompt)) { Write-ImmutableText $promptPath $prompt }
    $inspection = Get-Inspection
    $payload = [ordered]@{ packetReference = $packet; promptReference = if ($promptReference) { [ordered]@{ path = $promptPath; sha256 = Get-FileSha256 $promptPath } } else { $null }; workerId = $workerId; operation = $ExternalOperation }
    $request = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = [long]$inspection.revision; actionId = $actionId; ticketKey = $owner.ticketKey; actionKind = $ActionKind; target = [ordered]@{ workerId = $workerId; operation = $ExternalOperation }; input = $payload; inputDigest = (Get-FileSha256 $packet.path) }
    $prepared = Invoke-State 'prepare-action' $request
    return [ordered]@{ phase = 'preparing'; decision = 'dispatch'; reason = 'prepared_external_action'; actionId = $actionId; workerId = $workerId; requiredReferences = @($packet) + @($payload.promptReference); changedFields = @('actions'); revision = [long]$prepared.revision; action = [ordered]@{ operation = $ExternalOperation; actionId = $actionId; workerId = $workerId; packet = $packet; prompt = $payload.promptReference } }
}

function Invoke-RecordExternal {
    param([System.Collections.IDictionary] $InputObject)
    $owner = Get-OwnerValues $InputObject; $actionId = Need $InputObject 'actionId'; $status = Need $InputObject 'observationStatus'
    if ($status -notin @('observed','uncertain','failed')) { throw 'observationStatus must be observed, uncertain, or failed.' }
    $external = if ($InputObject.Contains('externalReference')) { Resolve-Reference $InputObject.externalReference 'external state' } else { $null }
    $inspection = Get-Inspection
    $request = [ordered]@{ sessionId = $owner.sessionId; ownerGeneration = $owner.ownerGeneration; expectedRevision = [long]$inspection.revision; actionId = $actionId; observationStatus = $status; reconcileRequired = ($status -eq 'uncertain'); externalState = $external }
    $observed = Invoke-State 'record-observation' $request
    return [ordered]@{ phase = $null; decision = if ($status -eq 'observed') { 'continue' } else { 'needs_input' }; reason = if ($status -eq 'observed') { 'external_outcome_recorded' } else { 'external_outcome_uncertain' }; actionId = $actionId; workerId = if ($InputObject.Contains('workerId')) { [string]$InputObject.workerId } else { $null }; requiredReferences = @($external); changedFields = @('action.status','action.externalState'); revision = [long]$observed.revision }
}

function Invoke-Status {
    param([System.Collections.IDictionary] $InputObject)
    $inspection = Get-Inspection; $registry = $inspection.data.registry
    $tickets = @($registry.tickets.Values)
    if ($InputObject.Contains('ticketKey')) { $tickets = @($tickets | Where-Object { $_.ticketKey -eq [string]$InputObject.ticketKey }) }
    $actions = @($registry.actions.Values | Where-Object { $null -ne $_.ticketKey -and $tickets.ticketKey -contains $_.ticketKey })
    return [ordered]@{ phase = if ($tickets.Count -eq 1) { [string]$tickets[0].phase } else { $null }; decision = 'status'; reason = 'local_registry_snapshot'; actionId = $null; workerId = $null; requiredReferences = @(); changedFields = @(); revision = [long]$inspection.revision; tickets = @($tickets | ForEach-Object { [ordered]@{ ticketKey = $_.ticketKey; phase = $_.phase; controlState = $_.controlState; correctionRound = $_.correctionRound } }); actions = @($actions | ForEach-Object { [ordered]@{ actionId = $_.actionId; kind = $_.kind; status = $_.status; reconcileRequired = $_.reconcileRequired } }) }
}

try {
    $inputObject = Read-Object
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { throw 'StateRoot is required.' }
    $data = switch ($Operation) {
        'accept-result' { Invoke-AcceptResult $inputObject }
        'prepare-dispatch' { Invoke-PrepareExternal $inputObject 'worker_dispatch' 'create_or_message_worker' }
        'prepare-publication' { Invoke-PrepareExternal $inputObject 'publication' 'push_or_create_pr' }
        'record-external' { Invoke-RecordExternal $inputObject }
        'status' { Invoke-Status $inputObject }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_coordinate'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
