[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('create', 'validate')]
    [string] $Operation,
    [string] $InputPath,
    [string] $PacketPath,
    [string] $ExpectedRunId,
    [string] $ExpectedTicketKey,
    [string] $ExpectedWorktreePath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'

function Get-CanonicalRoot {
    param([string] $Requested)
    $base = $Requested
    if ([string]::IsNullOrWhiteSpace($base)) {
        $localAppData = $env:LOCALAPPDATA
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        }
        if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'A durable local state directory is unavailable; specify StateRoot.' }
        $base = Join-Path $localAppData 'TaigaMCP\agent-review-automation'
    }
    $full = [IO.Path]::GetFullPath($base)
    if ($full -match '[:\\/]$' -or $full.Length -lt 5) { throw 'StateRoot must identify a dedicated directory.' }
    if (Test-Path -LiteralPath $full -PathType Leaf) { throw 'StateRoot must be a directory, not a file.' }
    return $full.TrimEnd('\', '/')
}

function Convert-JsonElement {
    param([System.Text.Json.JsonElement] $Element)
    switch ($Element.ValueKind.ToString()) {
        'Object' {
            $object = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) { $object[$property.Name] = Convert-JsonElement $property.Value }
            return $object
        }
        'Array' {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) { [void]$items.Add((Convert-JsonElement $item)) }
            return ,$items.ToArray()
        }
        'String' { return $Element.GetString() }
        'Number' { $integer = 0L; if ($Element.TryGetInt64([ref]$integer)) { return $integer }; return $Element.GetDouble() }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        default { throw "Unsupported JSON value kind: $($Element.ValueKind)." }
    }
}

function Read-JsonFile {
    param([string] $Path, [string] $Name)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Name file was not found." }
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($Path))
        $value = Convert-JsonElement $document.RootElement
        if ($value -isnot [System.Collections.IDictionary]) { throw "$Name JSON must be an object." }
        return $value
    } catch { throw "$Name file is not valid JSON: $($_.Exception.Message)" } finally { if ($null -ne $document) { $document.Dispose() } }
}

function Require-Map {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $Object[$Name] -isnot [System.Collections.IDictionary]) { throw "$Name must be an object." }
    return $Object[$Name]
}

function Require-String {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context = 'input')
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or $Object[$Name] -isnot [string] -or [string]::IsNullOrWhiteSpace($Object[$Name])) { throw "$Name must be a nonblank string in $Context." }
    return [string]$Object[$Name]
}

function Require-PositiveInt {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context = 'input')
    $number = 0L
    if (-not $Object.Contains($Name) -or -not [long]::TryParse([string]$Object[$Name], [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 1) { throw "$Name must be a positive integer in $Context." }
    return $number
}

function Assert-AllowedKeys {
    param([System.Collections.IDictionary] $Object, [string[]] $Allowed, [string] $Context)
    foreach ($key in $Object.Keys) {
        if ($Allowed -notcontains [string]$key) { throw "Unknown field '$key' in $Context." }
    }
}

function Get-StringArray {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context, [switch] $AllowEmpty)
    if (-not $Object.Contains($Name) -or $Object[$Name] -is [string] -or $Object[$Name] -isnot [System.Collections.IEnumerable]) { throw "$Name must be an array in $Context." }
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Object[$Name]) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { throw "$Name entries must be nonblank strings in $Context." }
        [void]$items.Add([string]$item)
    }
    if (-not $AllowEmpty -and $items.Count -eq 0) { throw "$Name must contain at least one entry in $Context." }
    return ,$items.ToArray()
}

function Get-Sha256Bytes {
    param([byte[]] $Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($Bytes))).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-FileSha256 {
    param([string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($stream))).ToLowerInvariant() } finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-JsonSha256 {
    param([object] $Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    return Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($json))
}

function Get-SortedCriteria {
    param([object] $Value)
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw 'criteria must be a nonempty array.' }
    $items = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($criterion in $Value) {
        if ($criterion -isnot [System.Collections.IDictionary]) { throw 'Each criterion must be an object.' }
        Assert-AllowedKeys $criterion @('id', 'text') 'criterion'
        $id = Require-String $criterion 'id' 'criterion'
        $text = Require-String $criterion 'text' "criterion $id"
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Criterion ID has an invalid format: $id." }
        if (-not $ids.Add($id)) { throw "Duplicate criterion ID: $id." }
        $entry = [ordered]@{ id = $id; text = $text }
        $insertAt = $items.Count
        for ($index = 0; $index -lt $items.Count; $index++) {
            if ([StringComparer]::Ordinal.Compare($id, [string]$items[$index].id) -lt 0) { $insertAt = $index; break }
        }
        $items.Insert($insertAt, $entry)
    }
    if ($items.Count -eq 0) { throw 'criteria must contain at least one item.' }
    return ,$items.ToArray()
}

function Normalize-Profile {
    param([System.Collections.IDictionary] $Profiles, [string] $Name)
    $profile = Require-Map $Profiles $Name
    Assert-AllowedKeys $profile @('model', 'effort') "profiles.$Name"
    return [ordered]@{ model = Require-String $profile 'model' "profiles.$Name"; effort = Require-String $profile 'effort' "profiles.$Name" }
}

function Assert-PacketSemantics {
    param([System.Collections.IDictionary] $Packet)
    Assert-AllowedKeys $Packet @('schemaVersion', 'packetId', 'createdAtUtc', 'sessionId', 'runId', 'ticket', 'scopeHash', 'fullContext', 'criteria', 'repository', 'requiredCommands', 'unresolvedRequirements', 'authority', 'deadline', 'profiles', 'packetHash') 'packet'
    if ($Packet.schemaVersion -ne 1) { throw 'Unsupported scope packet schemaVersion.' }
    foreach ($name in @('packetId', 'sessionId', 'runId', 'createdAtUtc', 'scopeHash', 'packetHash')) { Require-String $Packet $name 'packet' | Out-Null }
    foreach ($name in @('packetId', 'sessionId')) { if ([string]$Packet[$name] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "$name has an invalid format." } }
    $created = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Packet.createdAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$created)) { throw 'createdAtUtc is invalid.' }
    $ticket = Require-Map $Packet 'ticket'; Assert-AllowedKeys $ticket @('ticketKey', 'projectId', 'kind', 'id', 'ref', 'title') 'ticket'
    foreach ($name in @('ticketKey', 'kind', 'title')) { Require-String $ticket $name 'ticket' | Out-Null }
    foreach ($name in @('projectId', 'id', 'ref')) { Require-PositiveInt $ticket $name 'ticket' | Out-Null }
    $context = Require-Map $Packet 'fullContext'; Assert-AllowedKeys $context @('path', 'sha256') 'fullContext'
    $contextPath = Require-String $context 'path' 'fullContext'; $contextHash = Require-String $context 'sha256' 'fullContext'
    if ($contextHash -notmatch '^[0-9a-f]{64}$') { throw 'fullContext.sha256 must be a lowercase SHA-256 hash.' }
    if (-not [IO.Path]::IsPathRooted($contextPath) -or -not (Test-Path -LiteralPath $contextPath -PathType Leaf)) { throw 'The full-context file reference is inaccessible.' }
    if ((Get-FileSha256 $contextPath) -ne $contextHash) { throw 'The full-context file hash does not match the packet.' }
    $criteria = Get-SortedCriteria $Packet.criteria
    if (@($criteria | ConvertTo-Json -Depth 100 -Compress) -ne @($Packet.criteria | ConvertTo-Json -Depth 100 -Compress)) { throw 'Criteria must be stored in stable ordinal ID order.' }
    $expectedScopeHash = Get-JsonSha256 ([ordered]@{ ticket = $ticket; contextSha256 = $contextHash; criteria = $criteria })
    if ($Packet.scopeHash -ne $expectedScopeHash) { throw 'scopeHash does not match the ticket, context, and criteria.' }
    $repository = Require-Map $Packet 'repository'; Assert-AllowedKeys $repository @('identity', 'repositoryPath', 'worktreePath', 'branch', 'baseSha') 'repository'
    foreach ($name in @('identity', 'repositoryPath', 'worktreePath', 'branch', 'baseSha')) { Require-String $repository $name 'repository' | Out-Null }
    foreach ($name in @('repositoryPath', 'worktreePath')) {
        if (-not [IO.Path]::IsPathRooted([string]$repository[$name])) { throw "repository.$name must be absolute." }
        if (-not (Test-Path -LiteralPath $repository[$name] -PathType Container)) { throw "repository.$name is inaccessible." }
    }
    if ($repository.baseSha -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'repository.baseSha must be a 40- or 64-character Git SHA.' }
    $commands = Get-StringArray $Packet 'requiredCommands' 'packet' -AllowEmpty
    $unresolved = Get-StringArray $Packet 'unresolvedRequirements' 'packet' -AllowEmpty
    $authority = Require-Map $Packet 'authority'; Assert-AllowedKeys $authority @('authorizedActions', 'excludedActions') 'authority'
    $null = Get-StringArray $authority 'authorizedActions' 'authority'
    $null = Get-StringArray $authority 'excludedActions' 'authority' -AllowEmpty
    $deadline = Require-Map $Packet 'deadline'; Assert-AllowedKeys $deadline @('startedAtUtc', 'deadlineUtc', 'elapsedBudgetMinutes') 'deadline'
    $startedAt = [DateTimeOffset]::MinValue; $deadlineAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse((Require-String $deadline 'startedAtUtc' 'deadline'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$startedAt)) { throw 'deadline.startedAtUtc is invalid.' }
    if (-not [DateTimeOffset]::TryParse((Require-String $deadline 'deadlineUtc' 'deadline'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$deadlineAt) -or $deadlineAt -le $startedAt) { throw 'deadline.deadlineUtc must be after startedAtUtc.' }
    Require-PositiveInt $deadline 'elapsedBudgetMinutes' 'deadline' | Out-Null
    $profiles = Require-Map $Packet 'profiles'; Assert-AllowedKeys $profiles @('coordinator', 'implementer', 'reviewer') 'profiles'
    $coordinator = Normalize-Profile $profiles 'coordinator'; $implementer = Normalize-Profile $profiles 'implementer'; $reviewer = Normalize-Profile $profiles 'reviewer'
    if ($implementer.model -ne 'gpt-5.6-luna' -or $implementer.effort -ne 'xhigh') { throw 'The packet implementation profile must be gpt-5.6-luna/xhigh.' }
    if ($reviewer.model -ne 'gpt-6.1-sol' -or $reviewer.effort -ne 'high') { throw 'The packet reviewer profile must be gpt-6.1-sol/high.' }
    $null = $commands; $null = $unresolved; $null = $coordinator
}

function New-Packet {
    param([System.Collections.IDictionary] $InputObject)
    Assert-AllowedKeys $InputObject @('packetId', 'sessionId', 'runId', 'ticket', 'contextPath', 'criteria', 'repository', 'requiredCommands', 'unresolvedRequirements', 'authority', 'deadline', 'profiles') 'create request'
    $packetId = Require-String $InputObject 'packetId'; $sessionId = Require-String $InputObject 'sessionId'; $runId = Require-String $InputObject 'runId'
    foreach ($name in @('packetId', 'sessionId')) { if ($InputObject[$name] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "$name has an invalid format." } }
    $ticketInput = Require-Map $InputObject 'ticket'; Assert-AllowedKeys $ticketInput @('ticketKey', 'projectId', 'kind', 'id', 'ref', 'title') 'ticket'
    $ticket = [ordered]@{ ticketKey = Require-String $ticketInput 'ticketKey' 'ticket'; projectId = Require-PositiveInt $ticketInput 'projectId' 'ticket'; kind = Require-String $ticketInput 'kind' 'ticket'; id = Require-PositiveInt $ticketInput 'id' 'ticket'; ref = Require-PositiveInt $ticketInput 'ref' 'ticket'; title = Require-String $ticketInput 'title' 'ticket' }
    $sourceContextPath = [IO.Path]::GetFullPath((Require-String $InputObject 'contextPath'))
    if (-not (Test-Path -LiteralPath $sourceContextPath -PathType Leaf)) { throw 'contextPath is inaccessible.' }
    $contextHash = Get-FileSha256 $sourceContextPath
    $criteria = Get-SortedCriteria $InputObject.criteria
    $scopeHash = Get-JsonSha256 ([ordered]@{ ticket = $ticket; contextSha256 = $contextHash; criteria = $criteria })
    $repositoryInput = Require-Map $InputObject 'repository'; Assert-AllowedKeys $repositoryInput @('identity', 'repositoryPath', 'worktreePath', 'branch', 'baseSha') 'repository'
    $repository = [ordered]@{ identity = Require-String $repositoryInput 'identity' 'repository'; repositoryPath = [IO.Path]::GetFullPath((Require-String $repositoryInput 'repositoryPath' 'repository')); worktreePath = [IO.Path]::GetFullPath((Require-String $repositoryInput 'worktreePath' 'repository')); branch = Require-String $repositoryInput 'branch' 'repository'; baseSha = Require-String $repositoryInput 'baseSha' 'repository' }
    $commandInput = [ordered]@{ requiredCommands = $InputObject.requiredCommands }
    $commands = Get-StringArray $commandInput 'requiredCommands' 'create request' -AllowEmpty
    $unresolvedInput = [ordered]@{ unresolvedRequirements = $InputObject.unresolvedRequirements }
    $unresolved = Get-StringArray $unresolvedInput 'unresolvedRequirements' 'create request' -AllowEmpty
    $authorityInput = Require-Map $InputObject 'authority'; Assert-AllowedKeys $authorityInput @('authorizedActions', 'excludedActions') 'authority'
    $authority = [ordered]@{ authorizedActions = Get-StringArray $authorityInput 'authorizedActions' 'authority'; excludedActions = Get-StringArray $authorityInput 'excludedActions' 'authority' -AllowEmpty }
    $deadlineInput = Require-Map $InputObject 'deadline'; Assert-AllowedKeys $deadlineInput @('startedAtUtc', 'deadlineUtc', 'elapsedBudgetMinutes') 'deadline'
    $deadline = [ordered]@{ startedAtUtc = Require-String $deadlineInput 'startedAtUtc' 'deadline'; deadlineUtc = Require-String $deadlineInput 'deadlineUtc' 'deadline'; elapsedBudgetMinutes = Require-PositiveInt $deadlineInput 'elapsedBudgetMinutes' 'deadline' }
    $profileInput = Require-Map $InputObject 'profiles'
    Assert-AllowedKeys $profileInput @('coordinator', 'implementer', 'reviewer') 'profiles'
    $profiles = [ordered]@{ coordinator = Normalize-Profile $profileInput 'coordinator'; implementer = Normalize-Profile $profileInput 'implementer'; reviewer = Normalize-Profile $profileInput 'reviewer' }

    $root = Get-CanonicalRoot $StateRoot
    $packetDirectory = Join-Path (Join-Path $root 'packets') $sessionId
    $contextDirectory = Join-Path (Join-Path $root 'packet-context') $sessionId
    [IO.Directory]::CreateDirectory($packetDirectory) | Out-Null
    [IO.Directory]::CreateDirectory($contextDirectory) | Out-Null
    $fullContextPath = Join-Path $contextDirectory "$contextHash.context"
    if (Test-Path -LiteralPath $fullContextPath -PathType Leaf) {
        if ((Get-FileSha256 $fullContextPath) -ne $contextHash) { throw 'An existing full-context artifact has conflicting content.' }
    } else {
        $tempContextPath = Join-Path $contextDirectory ('.context-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::Copy($sourceContextPath, $tempContextPath, $false)
            if ((Get-FileSha256 $tempContextPath) -ne $contextHash) { throw 'Full-context content changed while the packet was being created.' }
            try { [IO.File]::Move($tempContextPath, $fullContextPath, $false) } catch [IO.IOException] {
                if (-not (Test-Path -LiteralPath $fullContextPath -PathType Leaf) -or (Get-FileSha256 $fullContextPath) -ne $contextHash) { throw }
            }
        } finally { if (Test-Path -LiteralPath $tempContextPath) { Remove-Item -LiteralPath $tempContextPath -Force } }
    }

    $packetPath = Join-Path $packetDirectory "$packetId.json"
    if (Test-Path -LiteralPath $packetPath) { throw 'Scope packets are immutable; packetId already exists. Use the existing packet or a new packetId for changed scope.' }
    $packet = [ordered]@{
        schemaVersion = 1
        packetId = $packetId
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        sessionId = $sessionId
        runId = $runId
        ticket = $ticket
        scopeHash = $scopeHash
        fullContext = [ordered]@{ path = $fullContextPath; sha256 = $contextHash }
        criteria = $criteria
        repository = $repository
        requiredCommands = $commands
        unresolvedRequirements = $unresolved
        authority = $authority
        deadline = $deadline
        profiles = $profiles
    }
    $packet.packetHash = Get-JsonSha256 $packet
    Assert-PacketSemantics $packet
    $json = ConvertTo-Json -InputObject $packet -Depth 100
    $tempPacketPath = Join-Path $packetDirectory ('.packet-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tempPacketPath, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tempPacketPath, $packetPath, $false)
    } finally { if (Test-Path -LiteralPath $tempPacketPath) { Remove-Item -LiteralPath $tempPacketPath -Force } }
    return [ordered]@{ packetPath = $packetPath; packetId = $packetId; packetHash = $packet.packetHash; scopeHash = $scopeHash; fullContextPath = $fullContextPath; criteriaIds = @($criteria | ForEach-Object { $_.id }) }
}

function Test-Packet {
    param([string] $Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $packet = Read-JsonFile $fullPath 'Packet'
    Assert-PacketSemantics $packet
    $body = [ordered]@{}
    foreach ($key in $packet.Keys) { if ([string]$key -ne 'packetHash') { $body[[string]$key] = $packet[$key] } }
    if ((Get-JsonSha256 $body) -ne $packet.packetHash) { throw 'packetHash does not match packet contents.' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedRunId) -and $packet.runId -ne $ExpectedRunId) { throw 'Packet runId does not match the expected run.' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedTicketKey) -and $packet.ticket.ticketKey -ne $ExpectedTicketKey) { throw 'Packet ticket does not match the expected ticket.' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedWorktreePath)) {
        $expected = [IO.Path]::GetFullPath($ExpectedWorktreePath).TrimEnd('\', '/')
        $actual = [IO.Path]::GetFullPath([string]$packet.repository.worktreePath).TrimEnd('\', '/')
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($expected, $actual)) { throw 'Packet worktree does not match the expected checkout.' }
    }
    return [ordered]@{ valid = $true; packetPath = $fullPath; packetId = $packet.packetId; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; runId = $packet.runId; ticketKey = $packet.ticket.ticketKey; worktreePath = $packet.repository.worktreePath; criterionIds = @($packet.criteria | ForEach-Object { $_.id }) }
}

try {
    if ($Operation -eq 'create') {
        $input = Read-JsonFile $InputPath 'Input'
        $data = New-Packet $input
    } else {
        if ([string]::IsNullOrWhiteSpace($PacketPath)) { throw 'PacketPath is required for validation.' }
        $data = Test-Packet $PacketPath
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_packet'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
