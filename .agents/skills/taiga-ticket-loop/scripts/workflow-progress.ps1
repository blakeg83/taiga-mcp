[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('record','consume','acknowledge','validate')]
    [string] $Operation,
    [string] $InputPath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'

function Read-InputObject {
    if ([string]::IsNullOrWhiteSpace($InputPath) -or -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw 'Input file was not found.' }
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw 'Input JSON must be an object.' }
    return $value
}

function Need {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }
    return $Object[$Name]
}

function Positive-Int {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    $value = 0L
    if (-not $Object.Contains($Name) -or -not [long]::TryParse([string]$Object[$Name], [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -lt 1) { throw "$Name must be a positive integer." }
    return $value
}

function Nonnegative-Int {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    $value = 0L
    if (-not $Object.Contains($Name) -or -not [long]::TryParse([string]$Object[$Name], [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -lt 0) { throw "$Name must be a nonnegative integer." }
    return $value
}

function Canonical {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $result[$key] = Canonical $Value[$key] }
        return ,$result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { [void]$items.Add((Canonical $item)) }
        return ,$items.ToArray()
    }
    return $Value
}

function Hash-Object {
    param([object] $Value)
    $json = ConvertTo-Json -InputObject (Canonical $Value) -Depth 100 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Hash-String {
    param([string] $Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-EventIdentityKey {
    param([System.Collections.IDictionary] $Record)
    $evidenceJson = ConvertTo-Json -InputObject $Record.evidence -Depth 100 -Compress
    return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}' -f $Record.runId,$Record.actionId,$Record.ticketKey,$Record.projectId,$Record.parentStoryId,$Record.taskId,$Record.sequence,$Record.currentSha,$Record.eventType,(@($Record.criterionIds) -join ','),$evidenceJson,$Record.blockedReason,$Record.packetHash,$Record.scopeHash,$Record.bindingDigest)
}

function Get-PacketBinding {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('packetBinding') -or $InputObject.packetBinding -isnot [System.Collections.IDictionary]) { throw 'Progress requires a validated packetBinding.' }
    $packet = $InputObject.packetBinding
    foreach ($name in @('runId','actionId','packetHash','scopeHash','projectId','parentStoryId','selectedTaskIds','criteriaByTask','tasksById','bindingDigest')) { if (-not $packet.Contains($name)) { throw "packetBinding.$name is required." } }
    foreach ($name in @('runId','actionId')) { if ([string]::IsNullOrWhiteSpace([string]$packet[$name])) { throw "packetBinding.$name cannot be blank." } }
    foreach ($name in @('packetHash','scopeHash','bindingDigest')) { if ([string]$packet[$name] -notmatch '^[0-9a-fA-F]{64}$') { throw "packetBinding.$name must be a SHA-256 digest." } }
    $projectId = Positive-Int $packet 'projectId'; $parentStoryId = Positive-Int $packet 'parentStoryId'
    if ($packet.selectedTaskIds -is [string] -or $packet.selectedTaskIds -isnot [System.Collections.IEnumerable]) { throw 'packetBinding.selectedTaskIds must be an array.' }
    $selected = @($packet.selectedTaskIds | ForEach-Object { $value = 0L; if (-not [long]::TryParse([string]$_,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or $value -lt 1) { throw 'packetBinding.selectedTaskIds must contain positive integers.' }; $value })
    if (@($selected | Select-Object -Unique).Count -ne $selected.Count) { throw 'packetBinding.selectedTaskIds must not contain duplicates.' }
    if ($packet.criteriaByTask -isnot [System.Collections.IDictionary] -or $packet.tasksById -isnot [System.Collections.IDictionary]) { throw 'packetBinding criteria and task bindings must be objects.' }
    $criteriaByTask = [ordered]@{}; $tasksById = [ordered]@{}
    foreach ($taskId in $selected) {
        $key = [string]$taskId
        if (-not $packet.criteriaByTask.Contains($key) -or -not $packet.tasksById.Contains($key)) { throw "packetBinding is missing selected task $taskId." }
        $criteria = @($packet.criteriaByTask[$key] | ForEach-Object { [string]$_ })
        if ($criteria.Count -eq 0 -or @($criteria | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or @($criteria | Select-Object -Unique).Count -ne $criteria.Count) { throw "packetBinding criteria for task $taskId must be unique and nonempty." }
        $task = $packet.tasksById[$key]
        if ($task -isnot [System.Collections.IDictionary]) { throw "packetBinding task binding for $taskId must be an object." }
        foreach ($name in @('taskId','alias','projectId','parentStoryId','baselineStatusId','version','criteria')) { if (-not $task.Contains($name)) { throw "packetBinding.tasksById.$taskId.$name is required." } }
        if ([long]$task.taskId -ne $taskId -or [long]$task.projectId -ne $projectId -or [long]$task.parentStoryId -ne $parentStoryId) { throw "packetBinding task identity does not match selected task $taskId." }
        if ([string]::IsNullOrWhiteSpace([string]$task.alias)) { throw "packetBinding task alias for $taskId cannot be blank." }
        if (($criteria -join '|') -cne (@($task.criteria | ForEach-Object { [string]$_ }) -join '|')) { throw "packetBinding criteria do not match task binding $taskId." }
        $criteriaByTask[$key] = @($criteria)
        $tasksById[$key] = [ordered]@{ taskId = $taskId; alias = [string]$task.alias; projectId = $projectId; parentStoryId = $parentStoryId; baselineStatusId = [long]$task.baselineStatusId; version = [long]$task.version; criteria = @($criteria) }
    }
    $normalized = [ordered]@{ runId = [string]$packet.runId; actionId = [string]$packet.actionId; packetHash = ([string]$packet.packetHash).ToLowerInvariant(); scopeHash = ([string]$packet.scopeHash).ToLowerInvariant(); projectId = $projectId; parentStoryId = $parentStoryId; selectedTaskIds = @($selected); criteriaByTask = $criteriaByTask; tasksById = $tasksById }
    $expectedDigest = Hash-Object $normalized
    if ([string]$packet.bindingDigest -cne $expectedDigest) { throw 'packetBinding.bindingDigest does not match its immutable contents.' }
    $normalized.bindingDigest = $expectedDigest
    return $normalized
}

function Compare-PacketBinding {
    param([System.Collections.IDictionary] $Left, [System.Collections.IDictionary] $Right)
    $leftDigest = [string]$Left.bindingDigest; $rightDigest = [string]$Right.bindingDigest
    if ([string]::IsNullOrWhiteSpace($leftDigest) -or $leftDigest -cne $rightDigest) { throw 'Progress packet binding changed after initialization.' }
}

function New-ProgressState {
    param([string] $RunId, [string] $ActionId, [System.Collections.IDictionary] $PacketBinding)
    return [ordered]@{
        schemaVersion = 1
        runId = $RunId
        actionId = $ActionId
        actionIds = @($ActionId)
        packetBinding = $PacketBinding
        bindingDigest = [string]$PacketBinding.bindingDigest
        nextSequence = 1
        events = @()
        taskEvidence = [ordered]@{}
        consumers = [ordered]@{}
    }
}

function Get-ProgressPath {
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { throw 'StateRoot is required.' }
    $root = [IO.Path]::GetFullPath($StateRoot)
    [IO.Directory]::CreateDirectory($root) | Out-Null
    return Join-Path $root 'task-progress.json'
}

function Read-Progress {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { $state = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $Path) -AsHashtable -Depth 100 } catch { throw "Progress checkpoint is not valid JSON: $($_.Exception.Message)" }
    if ($state -isnot [System.Collections.IDictionary] -or [int]$state.schemaVersion -ne 1) { throw 'Progress checkpoint schemaVersion is unsupported.' }
    foreach ($field in @('runId','actionId','nextSequence','events','taskEvidence','consumers','packetBinding','bindingDigest')) { if (-not $state.Contains($field)) { throw "Progress checkpoint is missing $field." } }
    return $state
}

function Write-Progress {
    param([string] $Path, [System.Collections.IDictionary] $State)
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { $stream.Flush($true) } finally { $stream.Dispose() }
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force } }
}

function Invoke-WithLock {
    param([string] $Path, [scriptblock] $Body)
    $lockPath = "$Path.lock"
    $stream = $null
    for ($attempt = 0; $attempt -lt 80 -and $null -eq $stream; $attempt++) {
        try { $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) } catch { Start-Sleep -Milliseconds 25 }
    }
    if ($null -eq $stream) { throw 'Could not acquire the progress checkpoint lock.' }
    try { & $Body } finally { $stream.Dispose() }
}

function Get-CriterionIds {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('criterionIds') -or $InputObject.criterionIds -is [string] -or $InputObject.criterionIds -isnot [System.Collections.IEnumerable]) { throw 'criterionIds must be an array.' }
    $ids = [System.Collections.Generic.List[string]]::new(); $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in $InputObject.criterionIds) {
        $id = [string]$value
        if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { throw 'criterionIds must contain unique nonblank values.' }
        [void]$ids.Add($id)
    }
    return ,$ids.ToArray()
}

function Get-ShaProofDigest {
    param([System.Collections.IDictionary] $InputObject, [string[]] $CriterionIds, [object] $Evidence, [string] $CurrentSha)
    $proofPayload = [ordered]@{ runId = [string]$InputObject.runId; actionId = [string]$InputObject.actionId; ticketKey = [string]$InputObject.ticketKey; projectId = [long]$InputObject.projectId; parentStoryId = [long]$InputObject.parentStoryId; taskId = [long]$InputObject.taskId; sequence = [long]$InputObject.sequence; currentSha = $CurrentSha.ToLowerInvariant(); eventType = [string]$InputObject.eventType; criterionIds = @($CriterionIds); evidence = $Evidence; blockedReason = if ($InputObject.Contains('blockedReason')) { [string]$InputObject.blockedReason } else { $null }; packetHash = [string]$InputObject.packetHash; scopeHash = [string]$InputObject.scopeHash; bindingDigest = [string]$InputObject.bindingDigest }
    return Hash-Object $proofPayload
}

function Get-Event {
    param([System.Collections.IDictionary] $InputObject)
    $packet = Get-PacketBinding $InputObject
    $runId = [string](Need $InputObject 'runId'); $actionId = [string](Need $InputObject 'actionId'); $taskId = Positive-Int $InputObject 'taskId'; $sequence = Nonnegative-Int $InputObject 'sequence'
    if ($sequence -lt 1) { throw 'sequence must be positive.' }
    $currentSha = [string](Need $InputObject 'currentSha'); if ($currentSha -notmatch '^[0-9a-fA-F]{7,64}$') { throw 'currentSha must be a Git revision.' }
    $eventType = [string](Need $InputObject 'eventType'); if ($eventType -notin @('started','blocked','ready_for_review','accepted','reopen')) { throw 'eventType is unsupported.' }
    $criterionIds = Get-CriterionIds $InputObject
    $evidence = if ($InputObject.Contains('evidence')) { $InputObject.evidence } else { throw 'evidence is required.' }
    if ([string]$evidence -match '(?i)(password|token|secret|raw.?log)') { throw 'Credential or raw-log content is not allowed in progress evidence.' }
    if (-not $InputObject.Contains('ticketKey') -or [string]::IsNullOrWhiteSpace([string]$InputObject.ticketKey)) { throw 'ticketKey is required for a trusted progress event.' }
    if (-not $InputObject.Contains('projectId') -or -not $InputObject.Contains('parentStoryId')) { throw 'projectId and parentStoryId are required for a trusted progress event.' }
    $projectId = Positive-Int $InputObject 'projectId'; $parentStoryId = Positive-Int $InputObject 'parentStoryId'; $ticket = [string]$InputObject.ticketKey
    if ($ticket -notmatch '^project:\d+:story:\d+$' -or [long]($ticket -replace '^project:(\d+):story:(\d+)$','$1') -ne $projectId -or [long]($ticket -replace '^project:(\d+):story:(\d+)$','$2') -ne $parentStoryId) { throw 'ticketKey must match the trusted project and parent story identity.' }
    if ($runId -cne [string]$packet.runId -or $projectId -ne [long]$packet.projectId -or $parentStoryId -ne [long]$packet.parentStoryId -or $packet.selectedTaskIds -notcontains $taskId) { throw 'Progress event is outside the validated packet scope.' }
    $expectedCriteria = @($packet.criteriaByTask[[string]$taskId] | ForEach-Object { [string]$_ })
    if (($criterionIds -join '|') -cne ($expectedCriteria -join '|')) { throw "Progress event criteria do not match the selected task $taskId packet criteria." }
    if ($evidence -is [System.Collections.IDictionary]) { foreach ($name in @('currentSha','headSha')) { if ($evidence.Contains($name) -and [string]$evidence[$name] -cne $currentSha) { throw "Progress evidence $name does not match currentSha." } } }
    $proofDigest = if ($InputObject.Contains('shaDigest')) { [string]$InputObject.shaDigest } else { $null }
    if ($null -ne $proofDigest -and $proofDigest -cne (Get-ShaProofDigest $InputObject $criterionIds $evidence $currentSha)) { throw 'shaDigest does not match the trusted progress event payload.' }
    $event = [ordered]@{
        runId = $runId
        actionId = $actionId
        ticketKey = if ($InputObject.Contains('ticketKey')) { [string]$InputObject.ticketKey } else { $null }
        projectId = $projectId
        parentStoryId = $parentStoryId
        taskId = $taskId
        packetHash = [string]$packet.packetHash
        scopeHash = [string]$packet.scopeHash
        bindingDigest = [string]$packet.bindingDigest
        sequence = $sequence
        currentSha = $currentSha.ToLowerInvariant()
        eventType = $eventType
        criterionIds = @($criterionIds)
        evidence = $evidence
        blockedReason = if ($InputObject.Contains('blockedReason')) { [string]$InputObject.blockedReason } else { $null }
        shaDigest = $proofDigest
        continuationOfActionId = if ($InputObject.Contains('continuationOfActionId')) { [string]$InputObject.continuationOfActionId } else { $null }
        occurredAtUtc = if ($InputObject.Contains('occurredAtUtc')) { [string]$InputObject.occurredAtUtc } else { [DateTime]::UtcNow.ToString('o') }
    }
    $event.eventId = Hash-String (Get-EventIdentityKey $event)
    if ($InputObject.Contains('eventId') -and [string]$InputObject.eventId -cne $event.eventId) { throw 'eventId does not match the idempotent event identity.' }
    return $event
}

function Migrate-LegacyProgressState {
    param([System.Collections.IDictionary] $State)
    if ($State.Contains('actionIds')) { return $false }
    $changed = $false; $allActions = [System.Collections.Generic.List[string]]::new()
    foreach ($event in @($State.events)) {
        $action = [string]$event.actionId
        if (-not [string]::IsNullOrWhiteSpace($action) -and -not $allActions.Contains($action)) { [void]$allActions.Add($action) }
        $expected = Hash-String (Get-EventIdentityKey $event)
        if ([string]$event.eventId -cne $expected -and (-not $event.Contains('legacyContentDigest') -or [string]$event.legacyContentDigest -cne $expected)) { $event.legacyContentDigest = $expected; $changed = $true }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.actionId) -and -not $allActions.Contains([string]$State.actionId)) { [void]$allActions.Add([string]$State.actionId) }
    $State.actionIds = @($allActions); $State.legacyIdentityVersion = 1
    return $true
}

function Assert-ProgressState {
    param([System.Collections.IDictionary] $State)
    if ($State.packetBinding -isnot [System.Collections.IDictionary]) { throw 'Progress checkpoint is missing its immutable packet binding.' }
    $statePacketInput = [ordered]@{ packetBinding = $State.packetBinding }
    $statePacket = Get-PacketBinding $statePacketInput
    if ([string]$State.bindingDigest -cne [string]$statePacket.bindingDigest) { throw 'Progress checkpoint packet binding digest is invalid.' }
    $last = 0L
    $taskStates = @{}
    $actionIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($event in @($State.events)) {
        if ([long]$event.sequence -ne ($last + 1)) { throw 'Progress events must have contiguous increasing sequences.' }
        $expected = Hash-String (Get-EventIdentityKey $event)
        if ([string]$event.eventId -cne $expected -and (-not $event.Contains('legacyContentDigest') -or [string]$event.legacyContentDigest -cne $expected)) { throw "Progress event identity is invalid: $($event.sequence)." }
        if ($event.Contains('shaDigest') -and -not [string]::IsNullOrWhiteSpace([string]$event.shaDigest) -and [string]$event.shaDigest -cne (Get-ShaProofDigest $event @($event.criterionIds) $event.evidence ([string]$event.currentSha))) { throw "Progress event SHA proof is invalid: $($event.sequence)." }
        if ([string]$event.packetHash -cne [string]$statePacket.packetHash -or [string]$event.scopeHash -cne [string]$statePacket.scopeHash -or [string]$event.bindingDigest -cne [string]$statePacket.bindingDigest -or [long]$event.projectId -ne [long]$statePacket.projectId -or [long]$event.parentStoryId -ne [long]$statePacket.parentStoryId -or $statePacket.selectedTaskIds -notcontains [long]$event.taskId) { throw "Progress event $($event.sequence) is outside the immutable packet binding." }
        $expectedCriteria = @($statePacket.criteriaByTask[[string]$event.taskId] | ForEach-Object { [string]$_ }); $actualCriteria = @($event.criterionIds | ForEach-Object { [string]$_ }); if (($expectedCriteria -join '|') -cne ($actualCriteria -join '|')) { throw "Progress event $($event.sequence) criteria are not bound to its selected task." }
        if (-not $actionIds.Add([string]$event.actionId)) { }
        $taskKey = [string]$event.taskId; $prior = if ($taskStates.ContainsKey($taskKey)) { [string]$taskStates[$taskKey] } else { 'not_started' }; $next = switch ([string]$event.eventType) { 'started' { 'in_progress' }; 'blocked' { 'blocked' }; 'ready_for_review' { 'awaiting_review' }; 'reopen' { 'in_progress' }; 'accepted' { 'accepted' } }
        $allowed = @{ not_started = @('in_progress','blocked'); in_progress = @('in_progress','blocked','awaiting_review'); blocked = @('in_progress','blocked'); awaiting_review = @('in_progress','accepted'); accepted = @('accepted','in_progress') }
        if (-not $allowed.ContainsKey($prior) -or $allowed[$prior] -notcontains $next) { throw "Invalid progress transition for task ${taskKey}: $prior -> $next." }
        if ($next -eq 'accepted') { throw 'Worker progress cannot emit accepted; reviewer acceptance is separate.' }
        $taskStates[$taskKey] = $next
        $last = [long]$event.sequence
    }
    if ([long]$State.nextSequence -ne ($last + 1)) { throw 'Progress nextSequence does not follow the event log.' }
}

function Invoke-Record {
    param([System.Collections.IDictionary] $InputObject, [string] $Path)
    $event = Get-Event $InputObject
    return (Invoke-WithLock $Path {
        $state = Read-Progress $Path
        if ($null -eq $state) { $state = New-ProgressState $event.runId $event.actionId (Get-PacketBinding $InputObject) }
        if ([string]$state.runId -cne $event.runId) { throw 'Progress checkpoint is bound to a different run.' }
        $eventPacket = Get-PacketBinding $InputObject; $statePacket = Get-PacketBinding ([ordered]@{ packetBinding = $state.packetBinding }); Compare-PacketBinding $eventPacket $statePacket
        $migrated = Migrate-LegacyProgressState $state
        $continuation = $InputObject.Contains('continuationOfActionId') -and [string]$InputObject.continuationOfActionId -ceq [string]$state.actionId
        if ([string]$state.actionId -cne $event.actionId -and -not $continuation -and (-not $state.Contains('actionIds') -or @($state.actionIds | ForEach-Object { [string]$_ }) -notcontains [string]$event.actionId)) { throw 'Progress checkpoint is bound to a different run/action without a declared continuation.' }
        Assert-ProgressState $state
        $existing = @($state.events | Where-Object { [string]$_.eventId -ceq $event.eventId })
        if ($existing.Count -gt 0) { return [ordered]@{ recorded = $false; idempotent = $true; event = $existing[0]; nextSequence = [long]$state.nextSequence } }
        if ([string]$event.eventType -eq 'accepted') { throw 'Worker progress cannot emit accepted; reviewer acceptance is separate.' }
        $prior = @($state.events | Where-Object { [long]$_.taskId -eq [long]$event.taskId } | Sort-Object sequence | Select-Object -Last 1)
        $priorState = if ($prior.Count -eq 0) { 'not_started' } else { switch ([string]$prior[0].eventType) { 'started' { 'in_progress' }; 'blocked' { 'blocked' }; 'ready_for_review' { 'awaiting_review' }; 'reopen' { 'in_progress' }; default { throw 'Progress checkpoint contains an unsupported task transition.' } } }
        $nextState = switch ([string]$event.eventType) { 'started' { 'in_progress' }; 'blocked' { 'blocked' }; 'ready_for_review' { 'awaiting_review' }; 'reopen' { 'in_progress' } }
        $allowedStates = @{ not_started = @('in_progress','blocked'); in_progress = @('in_progress','blocked','awaiting_review'); blocked = @('in_progress','blocked'); awaiting_review = @('in_progress') }
        if (-not $allowedStates.ContainsKey($priorState) -or $allowedStates[$priorState] -notcontains $nextState) { throw "Invalid progress transition for task $($event.taskId): $priorState -> $nextState." }
        $sameSequence = @($state.events | Where-Object { [long]$_.sequence -eq [long]$event.sequence })
        if ($sameSequence.Count -gt 0) { throw "Stale progress evidence for sequence $($event.sequence) does not match the recorded event." }
        if ([long]$event.sequence -ne [long]$state.nextSequence) { throw "Stale or gapped progress sequence: expected $($state.nextSequence), received $($event.sequence)." }
        $state.events = @($state.events) + @($event)
        if (-not $state.Contains('actionIds')) { $state.actionIds = @([string]$state.actionId) }
        if (@($state.actionIds | ForEach-Object { [string]$_ }) -notcontains [string]$event.actionId) { $state.actionIds = @($state.actionIds) + @([string]$event.actionId) }
        if ($continuation) { $state.actionId = [string]$event.actionId }
        $taskKey = [string]$event.taskId
        $state.taskEvidence[$taskKey] = [ordered]@{ taskId = $event.taskId; lastSequence = $event.sequence; lastEventType = $event.eventType; currentSha = $event.currentSha; criterionIds = @($event.criterionIds); evidence = $event.evidence; eventId = $event.eventId }
        $state.nextSequence = [long]$state.nextSequence + 1
        Write-Progress $Path $state
        return [ordered]@{ recorded = $true; idempotent = $false; event = $event; nextSequence = [long]$state.nextSequence }
    })
}

function Get-Transitions {
    param([object[]] $Events)
    $items = @()
    foreach ($event in $Events) {
        $logicalState = switch ([string]$event.eventType) { 'started' { 'in_progress' }; 'ready_for_review' { 'awaiting_review' }; 'blocked' { 'blocked' }; 'accepted' { 'accepted' }; 'reopen' { 'in_progress' } }
        $items += [ordered]@{ eventId = [string]$event.eventId; actionId = [string]$event.actionId; sequence = [long]$event.sequence; ticketKey = [string]$event.ticketKey; projectId = [long]$event.projectId; parentStoryId = [long]$event.parentStoryId; taskId = [long]$event.taskId; eventType = [string]$event.eventType; logicalState = $logicalState; currentSha = [string]$event.currentSha; packetHash = [string]$event.packetHash; scopeHash = [string]$event.scopeHash; bindingDigest = [string]$event.bindingDigest; criterionIds = @($event.criterionIds); evidence = $event.evidence }
    }
    return $items
}

function Invoke-Consume {
    param([System.Collections.IDictionary] $InputObject, [string] $Path)
    $consumerId = [string](Need $InputObject 'consumerId')
    $advance = -not ($InputObject.Contains('advance') -and $InputObject.advance -eq $false)
    return (Invoke-WithLock $Path {
        $state = Read-Progress $Path; if ($null -eq $state) { throw 'Progress checkpoint was not found.' }; $migrated = Migrate-LegacyProgressState $state; if ($migrated) { Write-Progress $Path $state }; Assert-ProgressState $state
        if ($InputObject.Contains('packetBinding')) { Compare-PacketBinding (Get-PacketBinding $InputObject) (Get-PacketBinding ([ordered]@{ packetBinding = $state.packetBinding })) }
        if ($InputObject.Contains('runId') -and [string]$InputObject.runId -cne [string]$state.runId) { throw 'runId does not match the progress checkpoint.' }
        $consumerId = [string]$InputObject.consumerId
        $consumer = if ($state.consumers.Contains($consumerId)) { $state.consumers[$consumerId] } else { [ordered]@{ cursor = 0; taskStates = [ordered]@{}; pending = @() } }
        $persistedCursor = [long]$consumer.cursor
        $cursor = if ($InputObject.Contains('cursor')) { Nonnegative-Int $InputObject 'cursor' } else { $persistedCursor }
        if ($cursor -ne $persistedCursor) { throw "Consumer cursor must equal the persisted cursor $persistedCursor." }
        $events = @($state.events | Where-Object { [long]$_.sequence -gt $cursor })
        $transitions = @(Get-Transitions $events)
        $newCursor = if ($events.Count -gt 0) { [long]$events[-1].sequence } else { $cursor }
        $writes = @()
        $pending = @($consumer.pending)
        foreach ($transition in $transitions) {
            $taskKey = [string]$transition.taskId
            $prior = if ($consumer.taskStates.Contains($taskKey)) { [string]$consumer.taskStates[$taskKey] } else { $null }
            if ($prior -ne $transition.logicalState) { $writes += $transition }
            if (@($pending | Where-Object { [string]$_.eventId -ceq [string]$transition.eventId }).Count -eq 0) { $pending += $transition }
        }
        if ($advance) {
            $consumer.cursor = $newCursor; $consumer.pending = @($pending); $state.consumers[$consumerId] = $consumer
            Write-Progress $Path $state
        }
        $pendingWrites = @($pending | Where-Object { if ($consumer.taskStates.Contains([string]$_.taskId)) { [string]$consumer.taskStates[[string]$_.taskId] -ne [string]$_.logicalState } else { $true } })
        return [ordered]@{ consumerId = $consumerId; previousCursor = $cursor; cursor = $newCursor; packetBinding = $state.packetBinding; unchanged = ($events.Count -eq 0 -and $pending.Count -eq 0); events = $events; transitions = $transitions; pending = @($pending); taigaWrites = @($writes + $pendingWrites | Sort-Object sequence -Unique); stateMutation = ($advance -and ($newCursor -ne $cursor -or $events.Count -gt 0)) }
    })
}

function Invoke-Acknowledge {
    param([System.Collections.IDictionary] $InputObject, [string] $Path)
    $consumerId = [string](Need $InputObject 'consumerId')
    return (Invoke-WithLock $Path {
        $state = Read-Progress $Path; if ($null -eq $state) { throw 'Progress checkpoint was not found.' }; $migrated = Migrate-LegacyProgressState $state; if ($migrated) { Write-Progress $Path $state }; Assert-ProgressState $state
        if (-not $state.consumers.Contains($consumerId)) { throw 'Consumer has no persisted progress state.' }
        $consumer = $state.consumers[$consumerId]; $pending = @($consumer.pending); $outcomes = if ($InputObject.Contains('outcomes')) { @($InputObject.outcomes) } else { throw 'outcomes is required.' }
        foreach ($outcome in $outcomes) {
            if ($outcome -isnot [System.Collections.IDictionary] -or -not $outcome.Contains('eventId') -or -not $outcome.Contains('outcome')) { throw 'Each acknowledgement outcome requires eventId and outcome.' }
            $match = @($pending | Where-Object { [string]$_.eventId -ceq [string]$outcome.eventId }); if ($match.Count -ne 1) { throw "Acknowledgement event is not pending: $($outcome.eventId)." }
            if ([string]$outcome.outcome -notin @('applied','unchanged','reconciled')) { throw 'Only applied, unchanged, or reconciled outcomes can acknowledge progress.' }
            $taskKey = [string]$match[0].taskId; $consumer.taskStates[$taskKey] = [string]$match[0].logicalState; $pending = @($pending | Where-Object { [string]$_.eventId -cne [string]$outcome.eventId })
        }
        $consumer.pending = @($pending); $state.consumers[$consumerId] = $consumer; Write-Progress $Path $state
        return [ordered]@{ consumerId = $consumerId; acknowledged = @($outcomes | ForEach-Object eventId); pending = @($pending); cursor = [long]$consumer.cursor; stateMutation = $true }
    })
}

function Invoke-Validate {
    param([string] $Path)
    $state = Read-Progress $Path; if ($null -eq $state) { throw 'Progress checkpoint was not found.' }; $migrated = Migrate-LegacyProgressState $state; if ($migrated) { Write-Progress $Path $state }; Assert-ProgressState $state
    return [ordered]@{ valid = $true; runId = [string]$state.runId; actionId = [string]$state.actionId; actionIds = @($state.actionIds); packetBinding = $state.packetBinding; eventCount = @($state.events).Count; nextSequence = [long]$state.nextSequence; consumers = @($state.consumers.Keys) }
}

try {
    $inputObject = Read-InputObject
    $path = Get-ProgressPath
    $data = switch ($Operation) {
        'record' { Invoke-Record $inputObject $path }
        'consume' { Invoke-Consume $inputObject $path }
        'acknowledge' { Invoke-Acknowledge $inputObject $path }
        'validate' { Invoke-Validate $path }
    }
    [ordered]@{ ok = $true; operation = $Operation; path = $path; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_progress'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
