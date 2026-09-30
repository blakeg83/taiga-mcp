[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('initialize-session', 'inspect', 'claim-ticket', 'release-ticket', 'reserve-slot', 'release-slot', 'prepare-action', 'record-observation', 'consume-result', 'transition', 'pause-intent', 'cancel-intent', 'resume-session', 'set-heartbeat', 'validate-receipt')]
    [string] $Operation,
    [string] $InputPath,
    [string] $Json,
    [string] $StateRoot,
    [switch] $Pretty
)

$ErrorActionPreference = 'Stop'
$script:SchemaVersion = 1
$script:MaxEvents = 200

function New-UtcStamp { return [DateTime]::UtcNow.ToString('o') }

function Get-CanonicalRoot {
    param([string] $Requested)
    $base = if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $Requested
    } elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $env:LOCALAPPDATA 'TaigaMCP\agent-review-automation'
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        Join-Path $env:TEMP 'TaigaMCP\agent-review-automation'
    } else {
        Join-Path ([IO.Path]::GetTempPath()) 'TaigaMCP\agent-review-automation'
    }
    $full = [IO.Path]::GetFullPath($base)
    if ($full -match '[:\\/]$' -or $full.Length -lt 5) { throw 'StateRoot must identify a dedicated directory.' }
    return $full.TrimEnd('\', '/')
}

function Get-InputObject {
    if (-not [string]::IsNullOrWhiteSpace($InputPath) -and -not [string]::IsNullOrWhiteSpace($Json)) {
        throw 'Specify only one of InputPath or Json.'
    }
    $raw = if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }
        Get-Content -Raw -LiteralPath $InputPath
    } elseif (-not [string]::IsNullOrWhiteSpace($Json)) {
        $Json
    } else {
        '{}'
    }
    try { $value = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100; $value = Convert-ToHashtable $value } catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
    if ($null -eq $value -or $value -isnot [hashtable]) { throw 'Input JSON must be an object.' }
    Assert-NoSecrets $value
    return $value
}

function Convert-ToHashtable {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) { $result[[string]$key] = Convert-ToHashtable $Value[$key] }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Convert-ToHashtable $_ })
    }
    return $Value
}

function Assert-NoSecrets {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '(?i)(password|secret|token|credential|privatekey)') { throw "Credential-like field is not accepted: $key" }
            Assert-NoSecrets $Value[$key]
        }
    } elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) { Assert-NoSecrets $item }
    }
}

function Assert-AllowedKeys {
    param([hashtable] $Object, [string[]] $Allowed, [string] $Context)
    foreach ($key in $Object.Keys) {
        if ($Allowed -notcontains [string]$key -and [string]$key -notlike 'x-*') {
            throw "Unknown critical field '$key' in $Context. Extension fields must start with x-."
        }
    }
}

function Require-String {
    param([hashtable] $Object, [string] $Name, [string] $Context = 'input')
    if (-not $Object.ContainsKey($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) {
        throw "$Name is required in $Context."
    }
    return [string]$Object[$Name]
}

function Require-NonNegativeInt {
    param([hashtable] $Object, [string] $Name, [string] $Context = 'input')
    if (-not $Object.ContainsKey($Name) -or $null -eq $Object[$Name]) { throw "$Name is required in $Context." }
    $number = 0L
    if (-not [long]::TryParse([string]$Object[$Name], [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 0) {
        throw "$Name must be a nonnegative integer in $Context."
    }
    return $number
}

function Require-PositiveInt {
    param([hashtable] $Object, [string] $Name, [string] $Context = 'input')
    $number = Require-NonNegativeInt $Object $Name $Context
    if ($number -lt 1) { throw "$Name must be positive in $Context." }
    return $number
}

function Assert-Id {
    param([string] $Value, [string] $Name)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "$Name has an invalid format." }
}

function Get-TicketKey {
    param([hashtable] $InputObject)
    if ($InputObject.ContainsKey('ticketKey')) {
        $key = Require-String $InputObject 'ticketKey'
        Assert-Id ($key -replace ':', '-') 'ticketKey'
        return $key.ToLowerInvariant()
    }
    foreach ($field in @('projectId', 'kind', 'id')) { if (-not $InputObject.ContainsKey($field)) { throw "ticketKey or $field is required." } }
    $project = Require-PositiveInt $InputObject 'projectId'
    $kind = Require-String $InputObject 'kind'
    $id = Require-PositiveInt $InputObject 'id'
    if ($kind -notmatch '^(?i)(issue|task|story|user_story|epic)$') { throw "Unsupported work kind: $kind" }
    $kind = if ($kind -eq 'user_story') { 'story' } else { $kind.ToLowerInvariant() }
    return "project:${project}:${kind}:${id}"
}

function Get-Hash {
    param([object] $Value)
    $canonical = $Value | ConvertTo-Json -Depth 100 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

function New-Registry {
    [ordered]@{
        schemaVersion = $script:SchemaVersion
        revision = 0
        createdAt = New-UtcStamp
        updatedAt = New-UtcStamp
        sessions = @{}
        tickets = @{}
        repositories = @{}
        actions = @{}
        events = @()
    }
}

function Assert-Registry {
    param([hashtable] $State)
    if (-not $State.ContainsKey('schemaVersion') -or [int]$State.schemaVersion -ne $script:SchemaVersion) { throw 'Unsupported registry schema version.' }
    if (-not $State.ContainsKey('revision') -or [long]$State.revision -lt 0) { throw 'Registry revision is invalid.' }
    foreach ($field in @('sessions', 'tickets', 'repositories', 'actions')) {
        if (-not $State.ContainsKey($field) -or $State[$field] -isnot [System.Collections.IDictionary]) { throw "Registry field '$field' is invalid." }
    }
    if (-not $State.ContainsKey('events')) { $State.events = @() }
}

function Read-Registry {
    param([string] $Root)
    $statePath = Join-Path $Root 'registry.json'
    $backupPath = Join-Path $Root 'registry.json.bak'
    if (-not (Test-Path -LiteralPath $statePath)) {
        if (Test-Path -LiteralPath $backupPath) {
            try { $candidate = Convert-ToHashtable (ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $backupPath) -AsHashtable -Depth 100); Assert-Registry $candidate; return @{ State = $candidate; Recovered = $true } } catch { throw 'Registry primary is absent and backup is invalid; manual recovery is required.' }
        }
        throw "Registry is not initialized at $Root."
    }
    try {
        $candidate = Convert-ToHashtable (ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $statePath) -AsHashtable -Depth 100)
        Assert-Registry $candidate
        return @{ State = $candidate; Recovered = $false }
    } catch {
        if (Test-Path -LiteralPath $backupPath) {
            try { $candidate = Convert-ToHashtable (ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $backupPath) -AsHashtable -Depth 100); Assert-Registry $candidate; return @{ State = $candidate; Recovered = $true } } catch { }
        }
        throw "Registry is malformed and no valid backup is available: $($_.Exception.Message)"
    }
}

function Write-Registry {
    param([string] $Root, [hashtable] $State)
    Assert-Registry $State
    $statePath = Join-Path $Root 'registry.json'
    $backupPath = Join-Path $Root 'registry.json.bak'
    $tempPath = Join-Path $Root ("registry.{0}.{1}.tmp" -f ([Guid]::NewGuid().ToString('N'), $PID))
    $json = $State | ConvertTo-Json -Depth 100
    $utf8 = [Text.UTF8Encoding]::new($false)
    try {
        [IO.File]::WriteAllText($tempPath, $json, $utf8)
        $stream = [IO.File]::Open($tempPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { $stream.Flush($true) } finally { $stream.Dispose() }
        if (Test-Path -LiteralPath $statePath) {
            try { [IO.File]::Replace($tempPath, $statePath, $backupPath, $true) } catch { Move-Item -LiteralPath $statePath -Destination $backupPath -Force; Move-Item -LiteralPath $tempPath -Destination $statePath -Force }
        } else {
            Move-Item -LiteralPath $tempPath -Destination $statePath -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

function Invoke-Locked {
    param([string] $Root, [scriptblock] $Body)
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    $lockPath = Join-Path $Root 'registry.lock'
    $stream = $null
    for ($attempt = 0; $attempt -lt 80 -and $null -eq $stream; $attempt++) {
        try { $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) } catch { Start-Sleep -Milliseconds 25 }
    }
    if ($null -eq $stream) { throw 'Could not acquire the local registry lock.' }
    try { & $Body } finally { $stream.Dispose() }
}

function Add-Event {
    param([hashtable] $State, [string] $Type, [hashtable] $Data = @{})
    $items = @($State.events)
    $items += [ordered]@{ at = New-UtcStamp; type = $Type; data = $Data }
    if ($items.Count -gt $script:MaxEvents) { $items = $items[($items.Count - $script:MaxEvents)..($items.Count - 1)] }
    $State.events = $items
}

function Assert-Revision {
    param([hashtable] $State, [hashtable] $InputObject)
    if ($InputObject.ContainsKey('expectedRevision') -and [long]$InputObject.expectedRevision -ne [long]$State.revision) { throw "Revision conflict: expected $($InputObject.expectedRevision), actual $($State.revision)." }
}

function Get-Session {
    param([hashtable] $State, [hashtable] $InputObject)
    $id = Require-String $InputObject 'sessionId'
    Assert-Id $id 'sessionId'
    if (-not $State.sessions.ContainsKey($id)) { throw "Session was not found: $id" }
    return $State.sessions[$id]
}

function Assert-SessionOwner {
    param([hashtable] $Session, [hashtable] $InputObject)
    if ($InputObject.ContainsKey('ownerGeneration') -and [long]$InputObject.ownerGeneration -ne [long]$Session.ownerGeneration) { throw 'Session ownership generation is stale.' }
}

function Get-ConfigValue {
    param([hashtable] $Session, [string] $Path, [object] $Default)
    $current = $Session.config
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $current -or $current -isnot [System.Collections.IDictionary] -or -not $current.ContainsKey($part)) { return $Default }
        $current = $current[$part]
    }
    return $current
}

function Assert-TicketOwner {
    param([hashtable] $State, [hashtable] $InputObject)
    $key = Get-TicketKey $InputObject
    if (-not $State.tickets.ContainsKey($key)) { throw "Ticket was not claimed: $key" }
    $ticket = $State.tickets[$key]
    $session = Get-Session $State $InputObject
    Assert-SessionOwner $session $InputObject
    if ($ticket.ownerSessionId -ne $session.sessionId -or [long]$ticket.ownerGeneration -ne [long]$session.ownerGeneration) { throw "Ticket is owned by another session: $key" }
    return $ticket
}

function New-Result {
    param([string] $Name, [hashtable] $Data, [bool] $Recovered = $false)
    [ordered]@{ ok = $true; operation = $Name; revision = $script:OutputRevision; recovered = $Recovered; data = $Data }
}

function Merge-Defaults {
    param([hashtable] $InputObject)
    $config = if ($InputObject.ContainsKey('config') -and $InputObject.config -is [System.Collections.IDictionary]) { $InputObject.config } else { @{} }
    $defaults = @{
        implementationProfile = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }
        reviewerProfile = @{ model = 'gpt-6.1-sol'; effort = 'high' }
        limits = @{ maxActiveTicketsPerRepository = 2; maxWorkerTurns = 8; maxCorrectionRounds = 3; elapsedMinutes = 120 }
        completion = @{ leafDonePolicy = 'merged'; epicDonePolicy = 'all_required_stories_merged_and_accepted' }
        branchPrefix = 'codex/'; dependencyPolicy = 'wait_for_merge'; autoPush = $true; autoCreatePr = $true; autoMerge = $false; allowForcePush = $false; useSubagents = $false
    }
    foreach ($name in $defaults.Keys) { if (-not $config.ContainsKey($name)) { $config[$name] = $defaults[$name] } }
    $config.useSubagents = $false
    if ($config.autoMerge -eq $true -or $config.allowForcePush -eq $true) { throw 'Automatic merge and force-push are disabled by contract.' }
    foreach ($profileName in @('implementationProfile', 'reviewerProfile')) {
        $profile = $config[$profileName]
        if ($profile -isnot [System.Collections.IDictionary] -or [string]::IsNullOrWhiteSpace([string]$profile.model) -or [string]::IsNullOrWhiteSpace([string]$profile.effort)) { throw "$profileName must include model and effort." }
    }
    if ($config.implementationProfile.model -ne 'gpt-5.6-luna' -or $config.implementationProfile.effort -ne 'xhigh') { throw 'The implementation profile must be gpt-5.6-luna/xhigh.' }
    $reviewerValid = $config.reviewerProfile.model -eq 'gpt-6.1-sol' -and $config.reviewerProfile.effort -eq 'high'
    if (-not $reviewerValid) { throw 'The reviewer profile must be gpt-6.1-sol/high.' }
    return $config
}

function Invoke-Initialize {
    param([hashtable] $InputObject, [string] $Root)
    Assert-AllowedKeys $InputObject @('schemaVersion','sessionId','coordinator','authorization','config','scope','dependencies','statusMappings') 'initialize-session'
    if ($InputObject.ContainsKey('schemaVersion') -and [int]$InputObject.schemaVersion -ne $script:SchemaVersion) { throw 'Unsupported input schema version.' }
    $sessionId = Require-String $InputObject 'sessionId'; Assert-Id $sessionId 'sessionId'
    if (-not $InputObject.ContainsKey('coordinator') -or $InputObject.coordinator -isnot [System.Collections.IDictionary]) { throw 'coordinator is required.' }
    $coordinator = $InputObject.coordinator
    Assert-AllowedKeys $coordinator @('threadId','hostId') 'coordinator'
    $threadId = Require-String $coordinator 'threadId'; $hostId = Require-String $coordinator 'hostId'
    $state = if (Test-Path -LiteralPath (Join-Path $Root 'registry.json')) { (Read-Registry $Root).State } else { New-Registry }
    if ($state.sessions.ContainsKey($sessionId)) { throw "Session already exists: $sessionId" }
    $config = Merge-Defaults $InputObject
    $scope = if ($InputObject.ContainsKey('scope')) { @($InputObject.scope) } else { @() }
    $deps = if ($InputObject.ContainsKey('dependencies')) { @($InputObject.dependencies) } else { @() }
    $session = [ordered]@{
        sessionId = $sessionId; coordinatorThreadId = $threadId; coordinatorHostId = $hostId; ownerGeneration = 1; state = 'running'; createdAt = New-UtcStamp; updatedAt = New-UtcStamp; config = $config; authorization = if ($InputObject.ContainsKey('authorization')) { $InputObject.authorization } else { [ordered]@{} }; scope = $scope; dependencies = $deps; statusMappings = if ($InputObject.ContainsKey('statusMappings')) { $InputObject.statusMappings } else { [ordered]@{} }; heartbeatId = $null; pauseIntent = $null; cancelIntent = $null
    }
    $state.sessions[$sessionId] = $session
    Add-Event $state 'session_initialized' @{ sessionId = $sessionId }
    return @{ State = $state; Data = @{ session = $session } }
}

function Invoke-Claim {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','ref','repository','repositoryIdentity','repositoryPath','parentTicketKey','childTicketKeys','scopeHash','workType') 'claim-ticket'
    Assert-Revision $State $InputObject
    $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject
    $key = Get-TicketKey $InputObject
    $children = if ($InputObject.ContainsKey('childTicketKeys')) { @($InputObject.childTicketKeys | ForEach-Object { [string]$_ }) } else { @() }
    $allKeys = @($key) + $children
    foreach ($candidate in $allKeys) {
        if ($State.tickets.ContainsKey($candidate)) {
            $existing = $State.tickets[$candidate]
            if ($existing.ownerSessionId -ne $session.sessionId -or [long]$existing.ownerGeneration -ne [long]$session.ownerGeneration) { throw "Ticket identity is already owned: $candidate" }
        }
    }
    $repository = if ($InputObject.ContainsKey('repositoryIdentity')) { Require-String $InputObject 'repositoryIdentity' } elseif ($InputObject.ContainsKey('repository')) { Require-String $InputObject 'repository' } else { 'unmapped' }
    $workType = if ($InputObject.ContainsKey('workType')) { [string]$InputObject.workType } else { ($key.Split(':')[2]) }
    $ticket = [ordered]@{ ticketKey = $key; ownerSessionId = $session.sessionId; ownerGeneration = $session.ownerGeneration; workType = $workType; repositoryIdentity = $repository; repositoryPath = if ($InputObject.ContainsKey('repositoryPath')) { [IO.Path]::GetFullPath([string]$InputObject.repositoryPath) } else { $null }; parentTicketKey = if ($InputObject.ContainsKey('parentTicketKey')) { [string]$InputObject.parentTicketKey } else { $null }; ownedChildTicketKeys = $children; phase = 'queued'; resumePhase = $null; slotReserved = $false; hostTurnsReserved = 0; correctionRound = 0; implementation = $null; review = $null; evidence = @(); lastResultCursor = $null; claimedAt = New-UtcStamp; updatedAt = New-UtcStamp }
    foreach ($candidate in $allKeys) { if (-not $State.tickets.ContainsKey($candidate)) { $State.tickets[$candidate] = $ticket } }
    Add-Event $State 'ticket_claimed' @{ sessionId = $session.sessionId; ticketKey = $key; childTicketKeys = $children }
    return @{ Data = @{ ticket = $ticket; ticketKey = $key } }
}

function Invoke-Release {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','force') 'release-ticket'
    Assert-Revision $State $InputObject; $ticket = Assert-TicketOwner $State $InputObject
    if ($ticket.slotReserved -and -not ($InputObject.force -eq $true)) { throw 'Release the execution slot before releasing the ticket claim.' }
    $key = $ticket.ticketKey; $children = @($ticket.ownedChildTicketKeys)
    foreach ($candidate in @($key) + $children) { if ($State.tickets.ContainsKey($candidate) -and $State.tickets[$candidate].ownerSessionId -eq $ticket.ownerSessionId) { $State.tickets.Remove($candidate) } }
    Add-Event $State 'ticket_released' @{ sessionId = $ticket.ownerSessionId; ticketKey = $key }
    return @{ Data = @{ released = $key } }
}

function Invoke-ReserveSlot {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','repositoryIdentity','capacity','hostWorkerLimit','workerTurns') 'reserve-slot'
    Assert-Revision $State $InputObject; $ticket = Assert-TicketOwner $State $InputObject; $session = Get-Session $State $InputObject
    if ($ticket.slotReserved) { return @{ Data = @{ reserved = $true; ticketKey = $ticket.ticketKey; idempotent = $true } } }
    $repo = if ($InputObject.ContainsKey('repositoryIdentity')) { [string]$InputObject.repositoryIdentity } else { [string]$ticket.repositoryIdentity }
    if ([string]::IsNullOrWhiteSpace($repo) -or $repo -eq 'unmapped') { throw 'A mapped repository is required before reserving a slot.' }
    $capacity = if ($InputObject.ContainsKey('capacity')) { Require-PositiveInt $InputObject 'capacity' } else { [long](Get-ConfigValue $session 'limits.maxActiveTicketsPerRepository' 2) }
    $hostLimit = if ($InputObject.ContainsKey('hostWorkerLimit')) { Require-PositiveInt $InputObject 'hostWorkerLimit' } else { [long](Get-ConfigValue $session 'limits.maxWorkerTurns' 8) }
    $turns = if ($InputObject.ContainsKey('workerTurns')) { Require-PositiveInt $InputObject 'workerTurns' } else { 1L }
    if (-not $State.repositories.ContainsKey($repo)) { $State.repositories[$repo] = [ordered]@{ identity = $repo; capacity = $capacity; slotOwners = @() } }
    $record = $State.repositories[$repo]; $record.capacity = $capacity; $owners = @($record.slotOwners)
    if ($owners.Count -ge $capacity) { throw "Repository capacity is exhausted for $repo." }
    $hostUsed = (@($State.tickets.Values | Where-Object { $_.slotReserved } | Measure-Object -Property hostTurnsReserved -Sum).Sum)
    if ($null -eq $hostUsed) { $hostUsed = 0 }
    if ($hostUsed + $turns -gt $hostLimit) { throw 'Host worker-turn capacity is exhausted.' }
    if ($owners -contains $ticket.ticketKey) { throw 'Ticket already appears in repository slot owners.' }
    $record.slotOwners = @($owners + $ticket.ticketKey); $ticket.slotReserved = $true; $ticket.hostTurnsReserved = $turns; $ticket.repositoryIdentity = $repo; $ticket.updatedAt = New-UtcStamp
    Add-Event $State 'slot_reserved' @{ ticketKey = $ticket.ticketKey; repository = $repo; workerTurns = $turns }
    return @{ Data = @{ reserved = $true; repository = $repo; capacity = $capacity; hostWorkerLimit = $hostLimit; usedHostWorkerTurns = $hostUsed + $turns } }
}

function Invoke-ReleaseSlot {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id') 'release-slot'
    Assert-Revision $State $InputObject; $ticket = Assert-TicketOwner $State $InputObject
    if (-not $ticket.slotReserved) { return @{ Data = @{ released = $false; idempotent = $true } } }
    $repo = [string]$ticket.repositoryIdentity
    if ($State.repositories.ContainsKey($repo)) { $State.repositories[$repo].slotOwners = @($State.repositories[$repo].slotOwners | Where-Object { $_ -ne $ticket.ticketKey }) }
    $ticket.slotReserved = $false; $ticket.hostTurnsReserved = 0; $ticket.updatedAt = New-UtcStamp
    Add-Event $State 'slot_released' @{ ticketKey = $ticket.ticketKey; repository = $repo }
    return @{ Data = @{ released = $true; repository = $repo } }
}

function Invoke-PrepareAction {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','actionId','ticketKey','projectId','kind','id','actionKind','target','input','inputDigest','leaseSeconds') 'prepare-action'
    Assert-Revision $State $InputObject; $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject
    $actionId = Require-String $InputObject 'actionId'; Assert-Id $actionId 'actionId'
    if ($State.actions.ContainsKey($actionId)) { throw "Action already exists; reconcile it instead of preparing again: $actionId" }
    $actionKind = Require-String $InputObject 'actionKind'; $target = if ($InputObject.ContainsKey('target')) { $InputObject.target } else { [ordered]@{} }
    $payload = if ($InputObject.ContainsKey('input')) { $InputObject.input } else { [ordered]@{} }
    $digest = if ($InputObject.ContainsKey('inputDigest')) { Require-String $InputObject 'inputDigest' } else { Get-Hash $payload }
    $ticketKey = if ($InputObject.ContainsKey('ticketKey') -or $InputObject.ContainsKey('projectId')) { Get-TicketKey $InputObject } else { $null }
    $leaseSeconds = if ($InputObject.ContainsKey('leaseSeconds')) { [double]$InputObject.leaseSeconds } else { 900.0 }
    $action = [ordered]@{ actionId = $actionId; sessionId = $session.sessionId; ownerGeneration = $session.ownerGeneration; ticketKey = $ticketKey; kind = $actionKind; target = $target; inputDigest = $digest; status = 'pending'; preparedAt = New-UtcStamp; leaseUntil = [DateTime]::UtcNow.AddSeconds($leaseSeconds).ToString('o'); receipt = $null }
    $State.actions[$actionId] = $action; Add-Event $State 'action_prepared' @{ actionId = $actionId; kind = $actionKind; ticketKey = $ticketKey }
    return @{ Data = @{ action = $action } }
}

function Invoke-RecordObservation {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','actionId','observationStatus','receipt','externalState','reconcileRequired') 'record-observation'
    Assert-Revision $State $InputObject; $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject
    $actionId = Require-String $InputObject 'actionId'; if (-not $State.actions.ContainsKey($actionId)) { throw "Action was not found: $actionId" }
    $action = $State.actions[$actionId]; $status = Require-String $InputObject 'observationStatus'
    if ($status -notin @('observed','uncertain','failed')) { throw 'observationStatus must be observed, uncertain, or failed.' }
    if ($action.status -eq 'observed' -and $status -ne 'observed') { throw 'An observed action cannot be downgraded.' }
    $action.status = $status; $action.receipt = if ($InputObject.ContainsKey('receipt')) { $InputObject.receipt } else { $null }; $action.externalState = if ($InputObject.ContainsKey('externalState')) { $InputObject.externalState } else { $null }; $action.reconcileRequired = ($status -eq 'uncertain') -or ($InputObject.reconcileRequired -eq $true); $action.observedAt = New-UtcStamp
    Add-Event $State 'action_observed' @{ actionId = $actionId; status = $status; reconcileRequired = $action.reconcileRequired }
    return @{ Data = @{ action = $action; reconciliationRequired = $action.reconcileRequired } }
}

function Invoke-ConsumeResult {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','cursor','result','actionId') 'consume-result'
    Assert-Revision $State $InputObject; $ticket = Assert-TicketOwner $State $InputObject
    $cursor = Require-String $InputObject 'cursor'
    if ($ticket.lastResultCursor -eq $cursor) { throw 'Worker result cursor was already consumed.' }
    $ticket.lastResultCursor = $cursor; $ticket.lastResult = if ($InputObject.ContainsKey('result')) { $InputObject.result } else { $null }; $ticket.lastResultActionId = if ($InputObject.ContainsKey('actionId')) { $InputObject.actionId } else { $null }; $ticket.updatedAt = New-UtcStamp
    Add-Event $State 'worker_result_consumed' @{ ticketKey = $ticket.ticketKey; cursor = $cursor }
    return @{ Data = @{ consumed = $true; cursor = $cursor } }
}

$script:LeafTransitions = @{
    queued = @('waiting_dependency','preparing','paused','cancelled','needs_input'); waiting_dependency = @('preparing','paused','cancelled','needs_input'); preparing = @('implementing','needs_input','paused','cancelled'); implementing = @('reviewing','correcting','needs_input','paused','cancelled'); reviewing = @('correcting','publishing','needs_input','paused','cancelled'); correcting = @('implementing','reviewing','needs_input','paused','cancelled'); publishing = @('awaiting_merge','finalizing','needs_input','paused','cancelled'); awaiting_merge = @('finalizing','correcting','needs_input','paused','cancelled'); finalizing = @('complete','needs_input','paused','cancelled'); paused = @('queued','waiting_dependency','preparing','implementing','correcting','reviewing','publishing','awaiting_merge','finalizing','needs_input','cancelled'); needs_input = @('queued','waiting_dependency','preparing','implementing','correcting','reviewing','publishing','awaiting_merge','finalizing','paused','cancelled')
}
$script:ParentTransitions = @{ planning = @('waiting_children','needs_input','paused','cancelled'); waiting_children = @('verifying_epic','needs_input','paused','cancelled'); verifying_epic = @('finalizing','needs_input','paused','cancelled'); finalizing = @('complete','needs_input','paused','cancelled'); paused = @('planning','waiting_children','verifying_epic','finalizing','needs_input','cancelled'); needs_input = @('planning','waiting_children','verifying_epic','finalizing','paused','cancelled') }

function Invoke-Transition {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','toPhase','resumePhase','reason','evidence') 'transition'
    Assert-Revision $State $InputObject; $ticket = Assert-TicketOwner $State $InputObject; $to = Require-String $InputObject 'toPhase'; $from = [string]$ticket.phase
    $map = if ($ticket.workType -eq 'epic') { $script:ParentTransitions } else { $script:LeafTransitions }
    if (-not $map.ContainsKey($from) -or $map[$from] -notcontains $to) { throw "Invalid transition $from -> $to for $($ticket.ticketKey)." }
    if ($to -in @('implementing','correcting','reviewing','publishing') -and -not $ticket.slotReserved) { throw 'An execution slot must be reserved before an active worker phase.' }
    $ticket.phase = $to; $ticket.updatedAt = New-UtcStamp; if ($InputObject.ContainsKey('resumePhase')) { $ticket.resumePhase = $InputObject.resumePhase }
    if ($InputObject.ContainsKey('reason')) { $ticket.lastTransitionReason = $InputObject.reason }
    if ($InputObject.ContainsKey('evidence')) { $ticket.evidence = @($ticket.evidence) + @($InputObject.evidence) }
    if ($to -eq 'correcting') { $ticket.correctionRound = [int]$ticket.correctionRound + 1; $limit = [int](Get-ConfigValue (Get-Session $State $InputObject) 'limits.maxCorrectionRounds' 3); if ($ticket.correctionRound -gt $limit) { throw "Correction round limit exhausted: $limit" } }
    Add-Event $State 'phase_transitioned' @{ ticketKey = $ticket.ticketKey; from = $from; to = $to }
    return @{ Data = @{ ticketKey = $ticket.ticketKey; from = $from; to = $to; correctionRound = $ticket.correctionRound } }
}

function Invoke-PauseIntent {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','reason') 'pause-intent'; Assert-Revision $State $InputObject
    $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject; $now = New-UtcStamp
    $ticketKey = if ($InputObject.ContainsKey('ticketKey') -or $InputObject.ContainsKey('projectId')) { (Assert-TicketOwner $State $InputObject).ticketKey } else { $null }
    if ($null -eq $ticketKey) { $session.pauseIntent = [ordered]@{ requestedAt = $now; reason = if ($InputObject.ContainsKey('reason')) { $InputObject.reason } else { $null }; quiescent = $false }; $session.state = 'pausing' } else { $ticket = $State.tickets[$ticketKey]; $ticket.pauseIntent = [ordered]@{ requestedAt = $now; reason = if ($InputObject.ContainsKey('reason')) { $InputObject.reason } else { $null }; quiescent = $false }; if ($ticket.phase -notin @('complete','cancelled')) { $ticket.resumePhase = $ticket.phase; $ticket.phase = 'paused' } }
    Add-Event $State 'pause_requested' @{ sessionId = $session.sessionId; ticketKey = $ticketKey }
    return @{ Data = @{ requested = $true; ticketKey = $ticketKey; state = if ($null -eq $ticketKey) { $session.state } else { $State.tickets[$ticketKey].phase } } }
}

function Invoke-CancelIntent {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','reason') 'cancel-intent'; Assert-Revision $State $InputObject
    $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject; $now = New-UtcStamp
    $ticketKey = if ($InputObject.ContainsKey('ticketKey') -or $InputObject.ContainsKey('projectId')) { (Assert-TicketOwner $State $InputObject).ticketKey } else { $null }
    if ($null -eq $ticketKey) { $session.cancelIntent = [ordered]@{ requestedAt = $now; reason = if ($InputObject.ContainsKey('reason')) { $InputObject.reason } else { $null }; reconciled = $false }; $session.state = 'cancelling' } else { $ticket = $State.tickets[$ticketKey]; $ticket.cancelIntent = [ordered]@{ requestedAt = $now; reason = if ($InputObject.ContainsKey('reason')) { $InputObject.reason } else { $null }; reconciled = $false }; if ($ticket.phase -notin @('complete','cancelled')) { $ticket.resumePhase = $ticket.phase; $ticket.phase = 'cancelled' } }
    Add-Event $State 'cancel_requested' @{ sessionId = $session.sessionId; ticketKey = $ticketKey }
    return @{ Data = @{ requested = $true; ticketKey = $ticketKey; state = if ($null -eq $ticketKey) { $session.state } else { $State.tickets[$ticketKey].phase } } }
}

function Invoke-Resume {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','ticketKey','projectId','kind','id','reason') 'resume-session'; Assert-Revision $State $InputObject
    $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject; $session.state = 'running'; $session.pauseIntent = $null; $session.cancelIntent = $null
    $changed = @(); if ($InputObject.ContainsKey('ticketKey') -or $InputObject.ContainsKey('projectId')) { $ticket = Assert-TicketOwner $State $InputObject; if ($ticket.phase -eq 'paused') { $ticket.phase = if ($ticket.resumePhase) { $ticket.resumePhase } else { 'queued' }; $ticket.resumePhase = $null; $changed += $ticket.ticketKey } } else { foreach ($ticket in @($State.tickets.Values | Where-Object { $_.ownerSessionId -eq $session.sessionId -and $_.phase -eq 'paused' })) { $ticket.phase = if ($ticket.resumePhase) { $ticket.resumePhase } else { 'queued' }; $ticket.resumePhase = $null; $changed += $ticket.ticketKey } }
    Add-Event $State 'session_resumed' @{ sessionId = $session.sessionId; tickets = $changed }
    return @{ Data = @{ state = $session.state; resumedTickets = $changed } }
}

function Invoke-Heartbeat {
    param([hashtable] $State, [hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('sessionId','ownerGeneration','expectedRevision','heartbeatId','scheduleState','reason') 'set-heartbeat'; Assert-Revision $State $InputObject
    $session = Get-Session $State $InputObject; Assert-SessionOwner $session $InputObject; $id = if ($InputObject.ContainsKey('heartbeatId')) { Require-String $InputObject 'heartbeatId' } else { $null }; $session.heartbeatId = $id; $session.heartbeatState = if ($InputObject.ContainsKey('scheduleState')) { $InputObject.scheduleState } else { $null }; $session.heartbeatUpdatedAt = New-UtcStamp
    Add-Event $State 'heartbeat_recorded' @{ sessionId = $session.sessionId; heartbeatId = $id; scheduleState = $session.heartbeatState }
    return @{ Data = @{ heartbeatId = $id; scheduleState = $session.heartbeatState } }
}

function Validate-ImplementationReceipt {
    param([hashtable] $Receipt)
    Assert-AllowedKeys $Receipt @('runId','actionId','ticketKey','scopeHash','baseSha','currentSha','checkout','branch','clean','criteria','checks','documentation','commits','blockers','noChange') 'implementation receipt'
    foreach ($name in @('runId','actionId','ticketKey','scopeHash','baseSha','currentSha','checkout','branch')) { Require-String $Receipt $name 'implementation receipt' | Out-Null }
    if ($Receipt.clean -ne $true -and $Receipt.noChange -ne $true) { throw 'Implementation receipt must prove clean committed source.' }
    if (-not $Receipt.ContainsKey('checks') -or $Receipt.checks -isnot [System.Collections.IEnumerable]) { throw 'Implementation receipt must include checks.' }
    if (-not $Receipt.ContainsKey('criteria')) { throw 'Implementation receipt must include criteria coverage.' }
    return [ordered]@{ valid = $true; kind = 'implementation'; currentSha = $Receipt.currentSha }
}

function Validate-ReviewReceipt {
    param([hashtable] $Receipt)
    Assert-AllowedKeys $Receipt @('runId','actionId','ticketKey','scopeHash','baseSha','reviewedSha','verdict','findings','criteria','checks','reviewerModel','reviewerEffort') 'review receipt'
    foreach ($name in @('runId','actionId','ticketKey','scopeHash','baseSha','reviewedSha','verdict')) { Require-String $Receipt $name 'review receipt' | Out-Null }
    if ($Receipt.verdict -notin @('pass','changes_requested','blocked')) { throw 'Review verdict must be pass, changes_requested, or blocked.' }
    if (-not $Receipt.ContainsKey('criteria') -or -not $Receipt.ContainsKey('checks')) { throw 'Review receipt must include criteria and checks.' }
    $blocking = @($Receipt.findings | Where-Object { $_.severity -in @('blocker','critical','high') -and $_.disposition -notin @('fixed','rejected_accepted') })
    if ($Receipt.verdict -eq 'pass' -and $blocking.Count -gt 0) { throw 'A passing review cannot retain unresolved blocking findings.' }
    return [ordered]@{ valid = $true; kind = 'review'; verdict = $Receipt.verdict; reviewedSha = $Receipt.reviewedSha; blockingFindings = $blocking.Count }
}

function Invoke-ValidateReceipt {
    param([hashtable] $InputObject)
    Assert-AllowedKeys $InputObject @('receipt','receiptKind') 'validate-receipt'
    if (-not $InputObject.ContainsKey('receipt') -or $InputObject.receipt -isnot [System.Collections.IDictionary]) { throw 'receipt is required.' }
    $kind = if ($InputObject.ContainsKey('receiptKind')) { [string]$InputObject.receiptKind } elseif ($InputObject.receipt.ContainsKey('verdict')) { 'review' } else { 'implementation' }
    $result = if ($kind -eq 'review') { Validate-ReviewReceipt $InputObject.receipt } elseif ($kind -eq 'implementation') { Validate-ImplementationReceipt $InputObject.receipt } else { throw 'receiptKind must be implementation or review.' }
    return @{ Data = $result; ReadOnly = $true }
}

function Invoke-Mutation {
    param([hashtable] $State, [hashtable] $InputObject)
    switch ($Operation) {
        'claim-ticket' { return Invoke-Claim $State $InputObject }
        'release-ticket' { return Invoke-Release $State $InputObject }
        'reserve-slot' { return Invoke-ReserveSlot $State $InputObject }
        'release-slot' { return Invoke-ReleaseSlot $State $InputObject }
        'prepare-action' { return Invoke-PrepareAction $State $InputObject }
        'record-observation' { return Invoke-RecordObservation $State $InputObject }
        'consume-result' { return Invoke-ConsumeResult $State $InputObject }
        'transition' { return Invoke-Transition $State $InputObject }
        'pause-intent' { return Invoke-PauseIntent $State $InputObject }
        'cancel-intent' { return Invoke-CancelIntent $State $InputObject }
        'resume-session' { return Invoke-Resume $State $InputObject }
        'set-heartbeat' { return Invoke-Heartbeat $State $InputObject }
        default { throw "Operation is not a mutation: $Operation" }
    }
}

try {
    $root = Get-CanonicalRoot $StateRoot
    $inputObject = Get-InputObject
    if ($Operation -eq 'validate-receipt') {
        $result = Invoke-ValidateReceipt $inputObject
        $script:OutputRevision = 0
        $output = New-Result $Operation $result.Data
    } elseif ($Operation -eq 'initialize-session') {
        Invoke-Locked $root {
            $result = Invoke-Initialize $inputObject $root
            $result.State.revision = [long]$result.State.revision + 1; $result.State.updatedAt = New-UtcStamp; Write-Registry $root $result.State; $script:OutputRevision = $result.State.revision; $script:Output = New-Result $Operation $result.Data
        }
        $output = $script:Output
    } elseif ($Operation -eq 'inspect') {
        $loaded = Read-Registry $root; $script:OutputRevision = $loaded.State.revision; $output = New-Result $Operation @{ registry = $loaded.State } $loaded.Recovered
    } else {
        Invoke-Locked $root {
            $loaded = Read-Registry $root; $state = $loaded.State; $result = Invoke-Mutation $state $inputObject; $state.revision = [long]$state.revision + 1; $state.updatedAt = New-UtcStamp; if ($state.sessions.ContainsKey([string]$inputObject.sessionId)) { $state.sessions[[string]$inputObject.sessionId].updatedAt = New-UtcStamp }; Write-Registry $root $state; $script:OutputRevision = $state.revision; $script:Output = New-Result $Operation $result.Data $loaded.Recovered
        }
        $output = $script:Output
    }
    $depth = if ($Pretty) { 100 } else { 100 }
    $output | ConvertTo-Json -Depth $depth
    exit 0
} catch {
    $errorOutput = [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_state'; message = $_.Exception.Message } }
    $errorOutput | ConvertTo-Json -Depth 20
    exit 1
}
