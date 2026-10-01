[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('record','consume','validate')]
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
    return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}' -f $Record.runId,$Record.actionId,$Record.ticketKey,$Record.projectId,$Record.parentStoryId,$Record.taskId,$Record.sequence,$Record.currentSha,$Record.eventType,(@($Record.criterionIds) -join ','),$evidenceJson,$Record.blockedReason)
}

function New-ProgressState {
    param([string] $RunId, [string] $ActionId)
    return [ordered]@{
        schemaVersion = 1
        runId = $RunId
        actionId = $ActionId
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
    foreach ($field in @('runId','actionId','nextSequence','events','taskEvidence','consumers')) { if (-not $state.Contains($field)) { throw "Progress checkpoint is missing $field." } }
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

function Get-Event {
    param([System.Collections.IDictionary] $InputObject)
    $runId = [string](Need $InputObject 'runId'); $actionId = [string](Need $InputObject 'actionId'); $taskId = Positive-Int $InputObject 'taskId'; $sequence = Nonnegative-Int $InputObject 'sequence'
    if ($sequence -lt 1) { throw 'sequence must be positive.' }
    $currentSha = [string](Need $InputObject 'currentSha'); if ($currentSha -notmatch '^[0-9a-fA-F]{7,64}$') { throw 'currentSha must be a Git revision.' }
    $eventType = [string](Need $InputObject 'eventType'); if ($eventType -notin @('started','blocked','ready_for_review','accepted','reopen')) { throw 'eventType is unsupported.' }
    $criterionIds = Get-CriterionIds $InputObject
    $evidence = if ($InputObject.Contains('evidence')) { $InputObject.evidence } else { throw 'evidence is required.' }
    if ([string]$evidence -match '(?i)(password|token|secret|raw.?log)') { throw 'Credential or raw-log content is not allowed in progress evidence.' }
    $event = [ordered]@{
        runId = $runId
        actionId = $actionId
        ticketKey = if ($InputObject.Contains('ticketKey')) { [string]$InputObject.ticketKey } else { $null }
        projectId = if ($InputObject.Contains('projectId')) { Positive-Int $InputObject 'projectId' } else { $null }
        parentStoryId = if ($InputObject.Contains('parentStoryId')) { Positive-Int $InputObject 'parentStoryId' } else { $null }
        taskId = $taskId
        sequence = $sequence
        currentSha = $currentSha.ToLowerInvariant()
        eventType = $eventType
        criterionIds = @($criterionIds)
        evidence = $evidence
        blockedReason = if ($InputObject.Contains('blockedReason')) { [string]$InputObject.blockedReason } else { $null }
        occurredAtUtc = if ($InputObject.Contains('occurredAtUtc')) { [string]$InputObject.occurredAtUtc } else { [DateTime]::UtcNow.ToString('o') }
    }
    $event.eventId = Hash-String (Get-EventIdentityKey $event)
    if ($InputObject.Contains('eventId') -and [string]$InputObject.eventId -cne $event.eventId) { throw 'eventId does not match the idempotent event identity.' }
    return $event
}

function Assert-ProgressState {
    param([System.Collections.IDictionary] $State)
    $last = 0L
    foreach ($event in @($State.events)) {
        if ([long]$event.sequence -ne ($last + 1)) { throw 'Progress events must have contiguous increasing sequences.' }
        $expected = Hash-String (Get-EventIdentityKey $event)
        if ([string]$event.eventId -cne $expected -and [string]$event.eventId -notmatch '^[0-9a-fA-F]{64}$') { throw "Progress event identity is invalid: $($event.sequence)." }
        $last = [long]$event.sequence
    }
    if ([long]$State.nextSequence -ne ($last + 1)) { throw 'Progress nextSequence does not follow the event log.' }
}

function Invoke-Record {
    param([System.Collections.IDictionary] $InputObject, [string] $Path)
    $event = Get-Event $InputObject
    return (Invoke-WithLock $Path {
        $state = Read-Progress $Path
        if ($null -eq $state) { $state = New-ProgressState $event.runId $event.actionId }
        if ([string]$state.runId -cne $event.runId -or [string]$state.actionId -cne $event.actionId) { throw 'Progress checkpoint is bound to a different run/action.' }
        Assert-ProgressState $state
        $existing = @($state.events | Where-Object { [string]$_.eventId -ceq $event.eventId })
        if ($existing.Count -gt 0) { return [ordered]@{ recorded = $false; idempotent = $true; event = $existing[0]; nextSequence = [long]$state.nextSequence } }
        $sameSequence = @($state.events | Where-Object { [long]$_.sequence -eq [long]$event.sequence })
        if ($sameSequence.Count -gt 0) { throw "Stale progress evidence for sequence $($event.sequence) does not match the recorded event." }
        if ([long]$event.sequence -ne [long]$state.nextSequence) { throw "Stale or gapped progress sequence: expected $($state.nextSequence), received $($event.sequence)." }
        $state.events = @($state.events) + @($event)
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
        $items += [ordered]@{ eventId = [string]$event.eventId; sequence = [long]$event.sequence; taskId = [long]$event.taskId; logicalState = $logicalState; currentSha = [string]$event.currentSha; criterionIds = @($event.criterionIds); evidence = $event.evidence }
    }
    return $items
}

function Invoke-Consume {
    param([System.Collections.IDictionary] $InputObject, [string] $Path)
    $consumerId = [string](Need $InputObject 'consumerId')
    $cursor = if ($InputObject.Contains('cursor')) { Nonnegative-Int $InputObject 'cursor' } else { 0L }
    $advance = -not ($InputObject.Contains('advance') -and $InputObject.advance -eq $false)
    return (Invoke-WithLock $Path {
        $state = Read-Progress $Path; if ($null -eq $state) { throw 'Progress checkpoint was not found.' }; Assert-ProgressState $state
        if ($InputObject.Contains('runId') -and [string]$InputObject.runId -cne [string]$state.runId) { throw 'runId does not match the progress checkpoint.' }
        $events = @($state.events | Where-Object { [long]$_.sequence -gt $cursor })
        $transitions = @(Get-Transitions $events)
        $newCursor = if ($events.Count -gt 0) { [long]$events[-1].sequence } else { $cursor }
        $writes = @()
        $consumer = if ($state.consumers.Contains($consumerId)) { $state.consumers[$consumerId] } else { [ordered]@{ cursor = 0; taskStates = [ordered]@{} } }
        foreach ($transition in $transitions) {
            $taskKey = [string]$transition.taskId
            $prior = if ($consumer.taskStates.Contains($taskKey)) { [string]$consumer.taskStates[$taskKey] } else { $null }
            if ($prior -ne $transition.logicalState) { $writes += $transition }
            $consumer.taskStates[$taskKey] = $transition.logicalState
        }
        if ($advance) {
            $consumer.cursor = $newCursor; $state.consumers[$consumerId] = $consumer
            Write-Progress $Path $state
        }
        return [ordered]@{ consumerId = $consumerId; previousCursor = $cursor; cursor = $newCursor; unchanged = ($events.Count -eq 0); events = $events; transitions = $transitions; taigaWrites = @($writes); stateMutation = ($advance -and $newCursor -ne $cursor) }
    })
}

function Invoke-Validate {
    param([string] $Path)
    $state = Read-Progress $Path; if ($null -eq $state) { throw 'Progress checkpoint was not found.' }; Assert-ProgressState $state
    return [ordered]@{ valid = $true; runId = [string]$state.runId; actionId = [string]$state.actionId; eventCount = @($state.events).Count; nextSequence = [long]$state.nextSequence; consumers = @($state.consumers.Keys) }
}

try {
    $inputObject = Read-InputObject
    $path = Get-ProgressPath
    $data = switch ($Operation) {
        'record' { Invoke-Record $inputObject $path }
        'consume' { Invoke-Consume $inputObject $path }
        'validate' { Invoke-Validate $path }
    }
    [ordered]@{ ok = $true; operation = $Operation; path = $path; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_progress'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
