[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('initialize-run','capture','validate','summarize')]
    [string] $Operation,
    [string] $InputPath,
    [string] $EvidencePath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'

function Get-CanonicalRoot {
    param([string] $Requested)
    $base = $Requested
    if ([string]::IsNullOrWhiteSpace($base)) {
        $localAppData = $env:LOCALAPPDATA
        if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }
        if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'A durable local evidence directory is unavailable; specify StateRoot.' }
        $base = Join-Path $localAppData 'TaigaMCP\agent-review-automation'
    }
    $full = [IO.Path]::GetFullPath($base)
    if ($full -match '[:\\/]$' -or $full.Length -lt 5) { throw 'StateRoot must identify a dedicated directory.' }
    if (Test-Path -LiteralPath $full -PathType Leaf) { throw 'StateRoot must be a directory, not a file.' }
    return $full.TrimEnd('\', '/')
}

function Read-JsonObject {
    param([string] $Path, [string] $Name)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Name file was not found." }
    try {
        $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $Path) -AsHashtable -Depth 100
        if ($value -isnot [System.Collections.IDictionary]) { throw "$Name must be a JSON object." }
        return $value
    } catch { throw "$Name file is not valid JSON: $($_.Exception.Message)" }
}

function Need-String {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context)
    if (-not $Object.Contains($Name) -or $Object[$Name] -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Context.$Name must be a nonblank string." }
    return [string]$Object[$Name]
}

function Assert-Id {
    param([string] $Value, [string] $Name)
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "$Name has an invalid format." }
}

function Get-FileSha256 {
    param([string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($stream))).ToLowerInvariant() } finally { $sha.Dispose(); $stream.Dispose() }
}

function ConvertTo-CanonicalValue {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $names = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $canonical = [ordered]@{}
        foreach ($name in $names) { $canonical[$name] = ConvertTo-CanonicalValue $Value[$name] }
        return $canonical
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { [void]$items.Add((ConvertTo-CanonicalValue $item)) }
        return ,$items.ToArray()
    }
    return $Value
}

function Get-TextSha256 {
    param([string] $Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()) } finally { $sha.Dispose() }
}

function Get-OrderedJsonSha256 {
    param([object] $Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()) } finally { $sha.Dispose() }
}

function Write-ImmutableJson {
    param([string] $Path, [object] $Value)
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $json = ConvertTo-Json -InputObject $Value -Depth 100
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } catch {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { throw "Immutable evidence already exists: $Path" }
        throw
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Test-ChildPath {
    param([string] $Parent, [string] $Candidate)
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Parent), [IO.Path]::GetFullPath($Candidate))
    return (-not [IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and -not $relative.StartsWith(('..' + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase) -and -not $relative.StartsWith(('..' + [IO.Path]::AltDirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase))
}

function Invoke-GitMetadata {
    param([string] $Repository, [string[]] $Arguments, [string] $Name)
    $result = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not read $Name from the bound worktree." }
    return (($result -join [Environment]::NewLine).Trim())
}

function Read-TrustedActionContext {
    param([System.Collections.IDictionary] $Request, [string] $Root)
    $packetPath = [IO.Path]::GetFullPath((Need-String $Request 'packetPath' 'input'))
    $packet = Read-JsonObject $packetPath 'Assignment packet'
    $expectedPacketHash = Need-String $Request 'packetHash' 'input'
    if ($packet.packetHash -cne $expectedPacketHash) { throw 'packetHash does not match the supplied trusted packet reference.' }
    if ([int]$packet.schemaVersion -ne 1 -or $packet.criteria -is [string] -or $packet.criteria -isnot [System.Collections.IEnumerable]) { throw 'Assignment packet schema is invalid.' }
    $packetBody = [ordered]@{}
    foreach ($key in $packet.Keys) { if ([string]$key -cne 'packetHash') { $packetBody[[string]$key] = $packet[$key] } }
    $calculatedPacketHash = Get-OrderedJsonSha256 $packetBody
    if ($calculatedPacketHash -cne $expectedPacketHash) { throw "Assignment packet hash does not match its contents (stored $expectedPacketHash, calculated $calculatedPacketHash)." }
    if ($packet.fullContext -isnot [System.Collections.IDictionary] -or -not (Test-Path -LiteralPath ([string]$packet.fullContext.path) -PathType Leaf) -or (Get-FileSha256 ([string]$packet.fullContext.path)) -cne [string]$packet.fullContext.sha256) { throw 'Assignment packet full-context artifact is missing or changed.' }

    $actionId = Need-String $Request 'actionId' 'input'
    Assert-Id $actionId 'actionId'
    $registryPath = Join-Path $Root 'registry.json'
    $registry = Read-JsonObject $registryPath 'Workflow registry'
    if ([int]$registry.schemaVersion -ne 2 -or $registry.actions -isnot [System.Collections.IDictionary] -or -not $registry.actions.Contains($actionId)) { throw 'The action is missing from the current workflow registry.' }
    if ($registry.sessions -isnot [System.Collections.IDictionary] -or -not $registry.sessions.Contains([string]$packet.sessionId)) { throw 'The packet session is missing from the current workflow registry.' }
    $session = $registry.sessions[[string]$packet.sessionId]
    if ($session.config.implementationProfile.model -cne $packet.profiles.implementer.model -or $session.config.implementationProfile.effort -cne $packet.profiles.implementer.effort -or $session.config.reviewerProfile.model -cne $packet.profiles.reviewer.model -or $session.config.reviewerProfile.effort -cne $packet.profiles.reviewer.effort) { throw 'Packet worker profiles do not match the session profile configuration.' }
    $action = $registry.actions[$actionId]
    if ($action.sessionId -cne $packet.sessionId -or $action.ticketKey -cne $packet.ticket.ticketKey -or $action.status -notin @('pending','observed')) { throw 'The action is not active and bound to this packet.' }
    if ($action.evidenceContext -isnot [System.Collections.IDictionary]) { throw 'The prepared action has no trusted verification context.' }
    $evidenceKind = switch -Exact ([string]$action.kind) {
        'implementation_check' { 'check' }
        'review_check' { 'check' }
        'expected_red_fixture' { 'expected_red_fixture' }
        'assertion' { 'assertion' }
        'intentional_host_shutdown' { 'intentional_host_shutdown' }
        default { throw 'Action kind is not eligible for structured verification evidence.' }
    }
    $role = if ($action.kind -eq 'review_check') { 'reviewer' } else { 'implementer' }
    $profile = $packet.profiles[$role]
    if ($null -eq $profile) { throw "Packet has no $role profile." }
    $command = Need-String $action.evidenceContext 'command' 'action.evidenceContext'
    $workingDirectory = [IO.Path]::GetFullPath((Need-String $action.evidenceContext 'workingDirectory' 'action.evidenceContext'))
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) { throw 'The configured check working directory is missing.' }
    $worktree = [IO.Path]::GetFullPath([string]$packet.repository.worktreePath)
    if (-not (Test-ChildPath $worktree $workingDirectory)) { throw 'The configured check working directory is outside the packet worktree.' }
    $criterionIds = @()
    if ($action.evidenceContext.Contains('criterionIds')) {
        if ($action.evidenceContext.criterionIds -is [string] -or $action.evidenceContext.criterionIds -isnot [System.Collections.IEnumerable]) { throw 'action.evidenceContext.criterionIds must be an array.' }
        $packetIds = @($packet.criteria | ForEach-Object { [string]$_.id })
        $seenIds = @{}
        foreach ($criterionIdValue in $action.evidenceContext.criterionIds) {
            $criterionId = [string]$criterionIdValue
            if ($packetIds -cnotcontains $criterionId) { throw "Action references a criterion outside the packet: $criterionId" }
            if ($seenIds.ContainsKey($criterionId)) { throw "Action repeats criterion ID: $criterionId" }
            $seenIds[$criterionId] = $true
            $criterionIds += $criterionId
        }
    }
    $criteria = @($packet.criteria)
    if ($criteria.Count -eq 0) { throw 'The assignment packet has no acceptance criteria.' }
    $previousId = $null
    $packetIdSet = @{}
    foreach ($criterion in $criteria) {
        if ($criterion -isnot [System.Collections.IDictionary] -or [string]::IsNullOrWhiteSpace([string]$criterion.id) -or [string]::IsNullOrWhiteSpace([string]$criterion.text)) { throw 'The assignment packet contains a malformed criterion.' }
        $criterionId = [string]$criterion.id
        if ($packetIdSet.ContainsKey($criterionId)) { throw "The assignment packet repeats criterion ID: $criterionId" }
        if ($null -ne $previousId -and [StringComparer]::Ordinal.Compare($previousId, $criterionId) -ge 0) { throw 'Assignment packet criteria are not in stable ordinal order.' }
        $packetIdSet[$criterionId] = $true
        $previousId = $criterionId
    }
    $scopeHash = Get-OrderedJsonSha256 ([ordered]@{ ticket = $packet.ticket; contextSha256 = [string]$packet.fullContext.sha256; criteria = $criteria })
    if ($scopeHash -cne [string]$packet.scopeHash) { throw 'Assignment packet scope hash does not match its ticket, context, and criteria.' }

    $repository = [IO.Path]::GetFullPath([string]$packet.repository.worktreePath)
    $actualRoot = Invoke-GitMetadata $repository @('rev-parse','--show-toplevel') 'worktree root'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($actualRoot), $repository)) { throw 'The packet worktree does not match the Git root.' }
    $branch = Invoke-GitMetadata $repository @('rev-parse','--abbrev-ref','HEAD') 'branch'
    if ($branch -cne [string]$packet.repository.branch) { throw 'The checked-out branch no longer matches the assignment packet.' }
    $headSha = Invoke-GitMetadata $repository @('rev-parse','HEAD') 'HEAD SHA'
    if ($headSha -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'The current HEAD is not a full Git SHA.' }
    $status = Invoke-GitMetadata $repository @('status','--porcelain') 'worktree status'
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw 'Verification evidence requires a clean committed worktree.' }
    return [ordered]@{ root = $Root; packet = $packet; packetPath = $packetPath; action = $action; actionId = $actionId; actionKind = [string]$action.kind; evidenceKind = $evidenceKind; role = $role; profile = $profile; command = $command; workingDirectory = $workingDirectory; criterionIds = $criterionIds; branch = $branch; baseSha = [string]$packet.repository.baseSha; headSha = $headSha; ticketKey = [string]$packet.ticket.ticketKey; scopeHash = [string]$packet.scopeHash }
}

function Initialize-RunMetadata {
    param([System.Collections.IDictionary] $Request, [string] $Root)
    $context = Read-TrustedActionContext $Request $Root
    $runId = [string]$context.packet.runId
    Assert-Id $runId 'runId'
    $directory = Join-Path (Join-Path (Join-Path $Root 'evidence') $runId) $context.actionId
    $metadataPath = Join-Path $directory 'run-metadata.json'
    $metadata = [ordered]@{
        schemaVersion = 1
        packetPath = $context.packetPath
        packetHash = $context.packet.packetHash
        runId = $runId
        actionId = $context.actionId
        ticketKey = $context.ticketKey
        scopeHash = $context.scopeHash
        criterionIds = @($context.packet.criteria | ForEach-Object { [string]$_.id })
        actionCriterionIds = @($context.criterionIds)
        criteria = @($context.packet.criteria | ForEach-Object { [ordered]@{ id = [string]$_.id; text = [string]$_.text } })
        actionKind = $context.actionKind
        evidenceKind = $context.evidenceKind
        repository = [ordered]@{ worktreePath = $context.packet.repository.worktreePath; branch = $context.branch; baseSha = $context.baseSha; headSha = $context.headSha }
        profile = [ordered]@{ role = $context.role; model = $context.profile.model; effort = $context.profile.effort }
        command = $context.command
        workingDirectory = $context.workingDirectory
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $metadataJson = ConvertTo-Json -InputObject $metadata -Depth 100 -Compress
    $wrapper = [ordered]@{ metadataJson = $metadataJson; metadataSha256 = Get-TextSha256 $metadataJson }
    Write-ImmutableJson $metadataPath $wrapper
    return [ordered]@{ metadataPath = $metadataPath; metadataSha256 = $wrapper.metadataSha256; metadata = $metadata }
}

function Read-RunMetadata {
    param([string] $Path, [string] $Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $evidenceRoot = Join-Path $Root 'evidence'
    if (-not (Test-ChildPath $evidenceRoot $fullPath)) { throw 'Run metadata path is outside the evidence store.' }
    $wrapper = Read-JsonObject $fullPath 'Run metadata'
    if ($wrapper.metadataJson -isnot [string]) { throw 'Run metadata body must be serialized JSON text.' }
    $calculatedMetadataHash = Get-TextSha256 $wrapper.metadataJson
    if ($wrapper.metadataSha256 -cne $calculatedMetadataHash) { throw "Run metadata hash does not match its contents (stored $($wrapper.metadataSha256), calculated $calculatedMetadataHash)." }
    try { $metadata = ConvertFrom-Json -InputObject $wrapper.metadataJson -AsHashtable -Depth 100 } catch { throw 'Run metadata payload is not valid JSON.' }
    if ($metadata -isnot [System.Collections.IDictionary]) { throw 'Run metadata payload must be an object.' }
    if ([int]$metadata.schemaVersion -ne 1) { throw 'Unsupported run metadata schema version.' }
    $request = @{ packetPath = [string]$metadata.packetPath; packetHash = [string]$metadata.packetHash; actionId = [string]$metadata.actionId }
    $current = Read-TrustedActionContext $request $Root
    if ($metadata.runId -cne $current.packet.runId -or $metadata.scopeHash -cne $current.scopeHash -or $metadata.ticketKey -cne $current.ticketKey -or $metadata.repository.headSha -cne $current.headSha -or $metadata.repository.branch -cne $current.branch) { throw 'Run metadata is stale or no longer matches the action and checkout.' }
    if ($metadata.evidenceKind -cne $current.evidenceKind -or $metadata.profile.model -cne $current.profile.model -or $metadata.profile.effort -cne $current.profile.effort) { throw 'Run metadata profile or evidence kind no longer matches the prepared action.' }
    return [ordered]@{ path = $fullPath; hash = [string]$wrapper.metadataSha256; metadata = $metadata; context = $current }
}

function Copy-LogArtifact {
    param([string] $SourcePath, [string] $Root)
    $source = [IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Check log file was not found.' }
    $hash = Get-FileSha256 $source
    $logDirectory = Join-Path (Join-Path $Root 'evidence') 'logs'
    [IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    $destination = Join-Path $logDirectory "$hash.log"
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if ((Get-FileSha256 $destination) -ne $hash) { throw 'Existing hash-addressed log has conflicting content.' }
    } else {
        $temporary = Join-Path $logDirectory ('.log-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::Copy($source, $temporary, $false)
            if ((Get-FileSha256 $temporary) -ne $hash) { throw 'Check log changed while it was being copied.' }
            try { [IO.File]::Move($temporary, $destination, $false) } catch [IO.IOException] {
                if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or (Get-FileSha256 $destination) -ne $hash) { throw }
            }
        } finally { if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force } }
    }
    return [ordered]@{ path = $destination; sha256 = $hash; bytes = ([IO.FileInfo]::new($destination)).Length }
}

function Get-Outcome {
    param([string] $Kind, [long] $ExitCode, [object] $AssertionPassed)
    switch -Exact ($Kind) {
        'check' { if ($ExitCode -eq 0) { return 'passed' }; return 'failed' }
        'expected_red_fixture' { if ($ExitCode -eq 0) { return 'unexpected_pass' }; return 'expected_red_failure' }
        'assertion' { if ($ExitCode -eq 0 -and $AssertionPassed -eq $true) { return 'assertion_passed' }; return 'assertion_failed' }
        'intentional_host_shutdown' { if ($ExitCode -eq 0) { return 'intentional_stop' }; return 'intentional_stop_failed' }
        default { throw "Unsupported evidence kind: $Kind" }
    }
}

function Capture-Evidence {
    param([System.Collections.IDictionary] $Request, [string] $Root)
    $metadataPath = [IO.Path]::GetFullPath((Need-String $Request 'metadataPath' 'input'))
    $metadataResult = Read-RunMetadata $metadataPath $Root
    $metadata = $metadataResult.metadata
    $exitValue = 0L
    if (-not $Request.Contains('actualExitCode') -or -not [long]::TryParse([string]$Request.actualExitCode, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$exitValue)) { throw 'actualExitCode must be a signed integer from the observed process result.' }
    $assertionPassed = $null
    if ($metadata.evidenceKind -eq 'assertion') {
        if (-not $Request.Contains('assertionPassed') -or $Request.assertionPassed -isnot [bool]) { throw 'assertionPassed must be supplied as a structured boolean result.' }
        $assertionPassed = $Request.assertionPassed
    } elseif ($Request.Contains('assertionPassed')) { throw 'assertionPassed is only valid for an assertion action.' }
    $log = Copy-LogArtifact (Need-String $Request 'logPath' 'input') $Root
    $evidenceId = 'ev-' + [Guid]::NewGuid().ToString('N')
    $record = [ordered]@{
        schemaVersion = 1
        evidenceId = $evidenceId
        runId = $metadata.runId
        actionId = $metadata.actionId
        originActionId = $metadata.actionId
        ticketKey = $metadata.ticketKey
        scopeHash = $metadata.scopeHash
        packetHash = $metadata.packetHash
        metadataSha256 = $metadataResult.hash
        criterionIds = @($metadata.actionCriterionIds)
        criteria = @($metadata.criteria | Where-Object { $metadata.actionCriterionIds -ccontains $_.id })
        evidenceKind = $metadata.evidenceKind
        outcome = Get-Outcome $metadata.evidenceKind $exitValue $assertionPassed
        acceptedAsCheckPass = ($metadata.evidenceKind -eq 'check' -and $exitValue -eq 0)
        repository = $metadata.repository
        checkedRevision = $metadata.repository.headSha
        profile = $metadata.profile
        command = $metadata.command
        workingDirectory = $metadata.workingDirectory
        actualExitCode = $exitValue
        assertionReportedPassed = $assertionPassed
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        log = $log
    }
    $recordJson = ConvertTo-Json -InputObject $record -Depth 100 -Compress
    $recordHash = Get-TextSha256 $recordJson
    $directory = Join-Path (Join-Path (Join-Path $Root 'evidence') $metadata.runId) $metadata.actionId
    $recordPath = Join-Path $directory "$evidenceId.json"
    Write-ImmutableJson $recordPath ([ordered]@{ recordJson = $recordJson; recordSha256 = $recordHash })
    return [ordered]@{ evidencePath = $recordPath; evidenceId = $evidenceId; evidenceSha256 = $recordHash; evidence = $record }
}

function Read-VerifiedEvidence {
    param([string] $Path, [string] $Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $evidenceRoot = Join-Path $Root 'evidence'
    if (-not (Test-ChildPath $evidenceRoot $fullPath)) { throw 'Evidence path is outside the evidence store.' }
    $wrapper = Read-JsonObject $fullPath 'Evidence record'
    if ($wrapper.recordJson -isnot [string]) { throw 'Evidence record body must be serialized JSON text.' }
    $calculatedRecordHash = Get-TextSha256 $wrapper.recordJson
    if ($wrapper.recordSha256 -cne $calculatedRecordHash) { throw "Evidence record hash does not match its contents (path '$fullPath'; stored $($wrapper.recordSha256), calculated $calculatedRecordHash)." }
    try { $record = ConvertFrom-Json -InputObject $wrapper.recordJson -AsHashtable -Depth 100 } catch { throw 'Evidence record payload is not valid JSON.' }
    if ($record -isnot [System.Collections.IDictionary]) { throw 'Evidence record payload must be an object.' }
    if ([int]$record.schemaVersion -ne 1) { throw 'Unsupported evidence record schema version.' }
    if ($record.acceptedAsCheckPass -ne ($record.evidenceKind -eq 'check' -and [long]$record.actualExitCode -eq 0)) { throw 'Evidence pass classification contradicts its raw exit code or kind.' }
    if ($record.outcome -cne (Get-Outcome ([string]$record.evidenceKind) ([long]$record.actualExitCode) $record.assertionReportedPassed)) { throw 'Evidence outcome contradicts its raw result.' }
    $logsRoot = Join-Path $evidenceRoot 'logs'
    $logPath = [IO.Path]::GetFullPath([string]$record.log.path)
    if (-not (Test-ChildPath $logsRoot $logPath) -or -not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw 'Evidence log reference is missing or unsafe.' }
    if ((Get-FileSha256 $logPath) -cne [string]$record.log.sha256 -or ([IO.FileInfo]::new($logPath)).Length -ne [long]$record.log.bytes) { throw 'Evidence log hash or length does not match.' }
    return [ordered]@{ path = $fullPath; sha256 = [string]$wrapper.recordSha256; record = $record }
}

function Get-ReportedOnlyValues {
    param([object[]] $Values)
    $reported = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Values) { return ,@() }
    foreach ($item in @($Values)) {
        if ($item -isnot [System.Collections.IDictionary]) { throw 'Each reportedOnly value must be an object.' }
        foreach ($name in @('name','value','source','reportedAtUtc')) { if (-not $item.Contains($name)) { throw "reportedOnly.$name is required." } }
        if ([string]::IsNullOrWhiteSpace([string]$item.name) -or [string]::IsNullOrWhiteSpace([string]$item.source)) { throw 'reportedOnly name and source must be nonblank.' }
        $reportedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$item.reportedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$reportedAt)) { throw "reportedOnly.$($item.name).reportedAtUtc is invalid." }
        [void]$reported.Add([ordered]@{ name = [string]$item.name; value = $item.value; source = [string]$item.source; reportedAtUtc = [string]$item.reportedAtUtc; status = 'reported_only' })
    }
    return ,$reported.ToArray()
}

function Get-EvidenceSummary {
    param([System.Collections.IDictionary] $Request, [string] $Root)
    if (-not $Request.Contains('evidencePaths') -or $Request.evidencePaths -is [string] -or $Request.evidencePaths -isnot [System.Collections.IEnumerable]) { throw 'evidencePaths must be an array.' }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $Request.evidencePaths) { [void]$records.Add((Read-VerifiedEvidence ([string]$path) $Root)) }
    $items = @($records | ForEach-Object { $_.record })
    $computed = [ordered]@{
        evidenceRecords = $items.Count
        checkResults = @($items | Where-Object evidenceKind -eq 'check').Count
        checksPassed = @($items | Where-Object { $_.evidenceKind -eq 'check' -and $_.outcome -eq 'passed' }).Count
        checksFailed = @($items | Where-Object { $_.evidenceKind -eq 'check' -and $_.outcome -eq 'failed' }).Count
        expectedRedFailures = @($items | Where-Object outcome -eq 'expected_red_failure').Count
        expectedRedUnexpectedPasses = @($items | Where-Object outcome -eq 'unexpected_pass').Count
        assertionsPassed = @($items | Where-Object outcome -eq 'assertion_passed').Count
        assertionsFailed = @($items | Where-Object outcome -eq 'assertion_failed').Count
        intentionalShutdowns = @($items | Where-Object { $_.evidenceKind -eq 'intentional_host_shutdown' }).Count
        intentionalShutdownFailures = @($items | Where-Object outcome -eq 'intentional_stop_failed').Count
    }
    $reportedOnly = Get-ReportedOnlyValues $(if ($Request.Contains('reportedOnly')) { @($Request.reportedOnly) } else { @() })
    return [ordered]@{ computed = $computed; evidence = @($records | ForEach-Object { [ordered]@{ evidenceId = $_.record.evidenceId; path = $_.path; sha256 = $_.sha256; outcome = $_.record.outcome } }); reportedOnly = $reportedOnly }
}

try {
    $root = Get-CanonicalRoot $StateRoot
    if ($Operation -ne 'validate' -and [string]::IsNullOrWhiteSpace($InputPath)) { throw 'InputPath is required.' }
    $request = if ([string]::IsNullOrWhiteSpace($InputPath)) { @{} } else { Read-JsonObject $InputPath 'Input' }
    switch ($Operation) {
        'initialize-run' { $data = Initialize-RunMetadata $request $root }
        'capture' { $data = Capture-Evidence $request $root }
        'validate' { $data = Read-VerifiedEvidence $EvidencePath $root }
        'summarize' { $data = Get-EvidenceSummary $request $root }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_evidence'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
