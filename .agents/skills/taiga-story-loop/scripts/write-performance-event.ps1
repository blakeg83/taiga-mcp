# Append one validated version-1 performance event to an external run ledger.
#
# This script is intentionally a recorder only. It does not aggregate events,
# attach workflow authority, read transcripts/source text, or infer telemetry.
# The event is validated before any directory or ledger mutation is attempted.

[CmdletBinding(DefaultParameterSetName = 'Json')]
param(
    [Parameter(Mandatory)]
    [Alias('ExternalRoot', 'LedgerRoot')]
    [string] $ExternalRunRoot,

    [Parameter(Mandatory)]
    [string] $RunId,

    [Parameter(Mandatory, ParameterSetName = 'Json')]
    [Alias('Event', 'Json')]
    [string] $EventJson,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string] $EventPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TopLevelFields = @(
    'schemaVersion', 'kind', 'eventId', 'runId', 'projectId', 'storyId',
    'storyRef', 'taskRef', 'role', 'sessionId', 'workerId', 'transitionId',
    'scope', 'phaseId', 'correctionId', 'reviewRequestId', 'reviewAttemptId',
    'reviewKind', 'reviewAttemptOrdinal', 'supersedesReviewAttemptId',
    'eventType', 'occurredAtUtc', 'revision', 'reviewMode', 'provenance',
    'usage'
)

$script:NullableTopLevelFields = @(
    'taskRef', 'sessionId', 'workerId', 'phaseId', 'correctionId',
    'reviewRequestId', 'reviewAttemptId', 'reviewKind', 'reviewAttemptOrdinal',
    'supersedesReviewAttemptId', 'revision', 'usage'
)

$script:EventTypes = @(
    'story_started', 'implementation_started', 'task_ready_for_review',
    'review_started', 'review_findings', 'review_accepted',
    'correction_started', 'correction_ready', 'final_review_started',
    'final_review_accepted', 'pr_ready', 'wait_started', 'wait_ended'
)

$script:Roles = @('coordinator', 'implementer', 'reviewer')
$script:Scopes = @('task', 'final_story', 'story')
$script:ReviewKinds = @('initial_task', 'correction_rereview', 'final_story', 'final_story_rereview')
$script:ReviewModes = @('per_task', 'story_end_only')
$script:ProvenanceFields = @('source', 'observedBy', 'observer', 'coverage', 'synthetic')
$script:UsageFields = @(
    'state', 'streamId', 'role', 'sessionId', 'source', 'counterSemantics',
    'coverage', 'sampledAtUtc', 'baselineAtUtc', 'counters', 'reason', 'fallback'
)
$script:CounterSemanticsFields = @('cachedInput', 'reasoning')
$script:CounterFields = @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')

function Fail-Recorder {
    param([Parameter(Mandatory)] [string] $Message)

    throw [System.ArgumentException]::new($Message)
}

function Get-Property {
    param(
        [Parameter(Mandatory)] [object] $Object,
        [Parameter(Mandatory)] [string] $Name
    )

    return $Object.PSObject.Properties[$Name]
}

function Assert-JsonObject {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $Value -or $Value -is [System.Array] -or
        $Value -isnot [System.Management.Automation.PSCustomObject]) {
        Fail-Recorder "'$Name' must be a JSON object"
    }
}

function Assert-AllowlistedProperties {
    param(
        [Parameter(Mandatory)] [object] $Object,
        [Parameter(Mandatory)] [string[]] $Allowed,
        [Parameter(Mandatory)] [string] $Context
    )

    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -notin $Allowed) {
            Fail-Recorder "'$Context.$($property.Name)' is not an allowlisted field"
        }
    }
}

function Assert-RequiredProperties {
    param(
        [Parameter(Mandatory)] [object] $Object,
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $Context
    )

    foreach ($name in $Names) {
        $property = Get-Property -Object $Object -Name $name
        if ($null -eq $property) {
            Fail-Recorder "'$Context.$name' is required"
        }
    }
}

function Assert-NonBlankString {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string] $Value) -or
        [string] $Value -match '[\x00-\x1F\x7F]') {
        Fail-Recorder "'$Name' must be a nonblank safe string"
    }
}

function Assert-NullableString {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -ne $Value) {
        Assert-NonBlankString -Value $Value -Name $Name
    }
}

function Test-JsonInteger {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value -or $Value -is [bool] -or
        $Value -isnot [byte] -and $Value -isnot [sbyte] -and
        $Value -isnot [short] -and $Value -isnot [ushort] -and
        $Value -isnot [int] -and $Value -isnot [uint] -and
        $Value -isnot [long] -and $Value -isnot [ulong] -and
        $Value -isnot [decimal] -and $Value -isnot [double] -and
        $Value -isnot [single]) {
        return $false
    }

    try {
        return ([decimal] $Value -eq [decimal]::Truncate([decimal] $Value))
    }
    catch {
        return $false
    }
}

function Assert-PositiveInteger {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not (Test-JsonInteger -Value $Value) -or [decimal] $Value -le 0) {
        Fail-Recorder "'$Name' must be a positive integer"
    }
}

function Assert-NonNegativeInteger {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not (Test-JsonInteger -Value $Value) -or [decimal] $Value -lt 0) {
        Fail-Recorder "'$Name' must be a nonnegative integer"
    }
}

function Assert-EnumValue {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string[]] $Allowed
    )

    Assert-NonBlankString -Value $Value -Name $Name
    if ([string] $Value -cnotin $Allowed) {
        Fail-Recorder "'$Name' has an unsupported value"
    }
}

function Assert-NullableEnumValue {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string[]] $Allowed
    )

    if ($null -ne $Value) {
        Assert-EnumValue -Value $Value -Name $Name -Allowed $Allowed
    }
}

function Assert-UtcTimestamp {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    Assert-NonBlankString -Value $Value -Name $Name
    $text = [string] $Value
    if (-not $text.EndsWith('Z', [System.StringComparison]::Ordinal)) {
        Fail-Recorder "'$Name' must be an ISO 8601 UTC timestamp ending in Z"
    }

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            $text,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref] $parsed) -or $parsed.Offset -ne [TimeSpan]::Zero) {
        Fail-Recorder "'$Name' must be an ISO 8601 UTC timestamp ending in Z"
    }
}

function Assert-NullableUtcTimestamp {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -ne $Value) {
        Assert-UtcTimestamp -Value $Value -Name $Name
    }
}

function Get-SourceWorktreeRoot {
    $candidate = [IO.Path]::GetFullPath($PSScriptRoot)
    while (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath (Join-Path $candidate '.git')) {
            return $candidate.TrimEnd('\', '/')
        }

        $parent = [IO.Directory]::GetParent($candidate)
        if ($null -eq $parent -or $parent.FullName -ceq $candidate) {
            break
        }

        $candidate = $parent.FullName
    }

    return $null
}

function Get-FullPath {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) {
        Fail-Recorder "'$Name' must be an absolute path"
    }

    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    }
    catch {
        Fail-Recorder "'$Name' is not a valid path"
    }
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory)] [string] $Child,
        [Parameter(Mandatory)] [string] $Parent
    )

    $childFull = $Child.TrimEnd('\', '/')
    $parentFull = $Parent.TrimEnd('\', '/')
    return $childFull.Equals($parentFull, [StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + '/', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ExternalRunRoot {
    param([Parameter(Mandatory)] [string] $Root)

    $sourceRoot = Get-SourceWorktreeRoot
    if ($null -ne $sourceRoot -and (Test-PathWithin -Child $Root -Parent $sourceRoot)) {
        Fail-Recorder "external run root must be outside the source worktree"
    }
}

function Assert-PathSafeRunId {
    param([Parameter(Mandatory)] [string] $Value)

    Assert-NonBlankString -Value $Value -Name 'runId'
    if ($Value.Length -gt 128 -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        Fail-Recorder "'runId' must be a path-safe stable identifier"
    }
}

function Assert-Usage {
    param([AllowNull()] [object] $Usage)

    if ($null -eq $Usage) {
        return
    }

    Assert-JsonObject -Value $Usage -Name 'usage'
    Assert-AllowlistedProperties -Object $Usage -Allowed $script:UsageFields -Context 'usage'
    Assert-RequiredProperties -Object $Usage -Names @('state', 'source', 'coverage') -Context 'usage'
    Assert-EnumValue -Value $Usage.state -Name 'usage.state' -Allowed @('measured', 'partial', 'unavailable', 'not_applicable')
    Assert-NonBlankString -Value $Usage.source -Name 'usage.source'
    Assert-NonBlankString -Value $Usage.coverage -Name 'usage.coverage'
    $streamId = Get-Property -Object $Usage -Name 'streamId'
    $usageRole = Get-Property -Object $Usage -Name 'role'
    $sessionId = Get-Property -Object $Usage -Name 'sessionId'
    $sampledAtUtc = Get-Property -Object $Usage -Name 'sampledAtUtc'
    $baselineAtUtc = Get-Property -Object $Usage -Name 'baselineAtUtc'
    $reason = Get-Property -Object $Usage -Name 'reason'
    $fallback = Get-Property -Object $Usage -Name 'fallback'
    Assert-NullableString -Value $(if ($null -eq $streamId) { $null } else { $streamId.Value }) -Name 'usage.streamId'
    Assert-NullableEnumValue -Value $(if ($null -eq $usageRole) { $null } else { $usageRole.Value }) -Name 'usage.role' -Allowed $script:Roles
    Assert-NullableString -Value $(if ($null -eq $sessionId) { $null } else { $sessionId.Value }) -Name 'usage.sessionId'
    Assert-NullableUtcTimestamp -Value $(if ($null -eq $sampledAtUtc) { $null } else { $sampledAtUtc.Value }) -Name 'usage.sampledAtUtc'
    Assert-NullableUtcTimestamp -Value $(if ($null -eq $baselineAtUtc) { $null } else { $baselineAtUtc.Value }) -Name 'usage.baselineAtUtc'
    Assert-NullableString -Value $(if ($null -eq $reason) { $null } else { $reason.Value }) -Name 'usage.reason'
    Assert-NullableString -Value $(if ($null -eq $fallback) { $null } else { $fallback.Value }) -Name 'usage.fallback'

    $counterSemantics = Get-Property -Object $Usage -Name 'counterSemantics'
    if ($null -ne $counterSemantics -and $null -ne $counterSemantics.Value) {
        Assert-JsonObject -Value $counterSemantics.Value -Name 'usage.counterSemantics'
        Assert-AllowlistedProperties -Object $counterSemantics.Value -Allowed $script:CounterSemanticsFields -Context 'usage.counterSemantics'
        foreach ($property in $counterSemantics.Value.PSObject.Properties) {
            Assert-EnumValue -Value $property.Value -Name "usage.counterSemantics.$($property.Name)" -Allowed @('included_in_input', 'disjoint_from_input', 'included_in_output', 'disjoint_from_output', 'unknown')
        }
    }

    $counters = Get-Property -Object $Usage -Name 'counters'
    if ($null -ne $counters -and $null -ne $counters.Value) {
        Assert-JsonObject -Value $counters.Value -Name 'usage.counters'
        Assert-AllowlistedProperties -Object $counters.Value -Allowed $script:CounterFields -Context 'usage.counters'
        foreach ($property in $counters.Value.PSObject.Properties) {
            Assert-NonNegativeInteger -Value $property.Value -Name "usage.counters.$($property.Name)"
        }
    }
}

function Assert-Provenance {
    param([AllowNull()] [object] $Provenance)

    Assert-JsonObject -Value $Provenance -Name 'provenance'
    Assert-AllowlistedProperties -Object $Provenance -Allowed $script:ProvenanceFields -Context 'provenance'
    Assert-RequiredProperties -Object $Provenance -Names @('source', 'coverage') -Context 'provenance'
    Assert-NonBlankString -Value $Provenance.source -Name 'provenance.source'
    Assert-NonBlankString -Value $Provenance.coverage -Name 'provenance.coverage'
    $observedBy = Get-Property -Object $Provenance -Name 'observedBy'
    $observer = Get-Property -Object $Provenance -Name 'observer'
    if (($null -eq $observedBy -or $null -eq $observedBy.Value) -and
        ($null -eq $observer -or $null -eq $observer.Value)) {
        Fail-Recorder "'provenance.observedBy' or 'provenance.observer' is required"
    }
    Assert-NullableString -Value $(if ($null -eq $observedBy) { $null } else { $observedBy.Value }) -Name 'provenance.observedBy'
    Assert-NullableString -Value $(if ($null -eq $observer) { $null } else { $observer.Value }) -Name 'provenance.observer'
    $synthetic = Get-Property -Object $Provenance -Name 'synthetic'
    if ($null -ne $synthetic -and $null -ne $synthetic.Value -and $synthetic.Value -isnot [bool]) {
        Fail-Recorder "'provenance.synthetic' must be a Boolean"
    }
}

function Assert-Revision {
    param([AllowNull()] [object] $Revision)

    if ($null -ne $Revision) {
        Assert-NonBlankString -Value $Revision -Name 'revision'
        if ([string] $Revision -notmatch '^[0-9a-fA-F]{40}$') {
            Fail-Recorder "'revision' must be a full Git SHA or null"
        }
    }
}

function Assert-Event {
    param(
        [Parameter(Mandatory)] [object] $Event,
        [Parameter(Mandatory)] [string] $ExpectedRunId
    )

    Assert-JsonObject -Value $Event -Name 'event'
    Assert-AllowlistedProperties -Object $Event -Allowed $script:TopLevelFields -Context 'event'
    Assert-RequiredProperties -Object $Event -Names $script:TopLevelFields -Context 'event'

    Assert-PositiveInteger -Value $Event.schemaVersion -Name 'schemaVersion'
    if ([int] $Event.schemaVersion -ne 1) {
        Fail-Recorder "'schemaVersion' must be 1"
    }

    Assert-NonBlankString -Value $Event.kind -Name 'kind'
    if ([string] $Event.kind -cne 'story_performance_event') {
        Fail-Recorder "'kind' must be story_performance_event"
    }

    Assert-NonBlankString -Value $Event.eventId -Name 'eventId'
    Assert-PathSafeRunId -Value $ExpectedRunId
    Assert-NonBlankString -Value $Event.runId -Name 'runId'
    if ([string] $Event.runId -cne $ExpectedRunId) {
        Fail-Recorder "event runId does not match the selected external run"
    }

    Assert-PositiveInteger -Value $Event.projectId -Name 'projectId'
    Assert-PositiveInteger -Value $Event.storyId -Name 'storyId'
    Assert-PositiveInteger -Value $Event.storyRef -Name 'storyRef'
    if ($null -ne $Event.taskRef) {
        Assert-PositiveInteger -Value $Event.taskRef -Name 'taskRef'
    }
    Assert-EnumValue -Value $Event.role -Name 'role' -Allowed $script:Roles
    Assert-NullableString -Value $Event.sessionId -Name 'sessionId'
    Assert-NullableString -Value $Event.workerId -Name 'workerId'
    Assert-NonBlankString -Value $Event.transitionId -Name 'transitionId'
    Assert-EnumValue -Value $Event.scope -Name 'scope' -Allowed $script:Scopes
    Assert-NullableString -Value $Event.phaseId -Name 'phaseId'
    Assert-NullableString -Value $Event.correctionId -Name 'correctionId'
    Assert-NullableString -Value $Event.reviewRequestId -Name 'reviewRequestId'
    Assert-NullableString -Value $Event.reviewAttemptId -Name 'reviewAttemptId'
    Assert-NullableEnumValue -Value $Event.reviewKind -Name 'reviewKind' -Allowed $script:ReviewKinds
    if ($null -ne $Event.reviewAttemptOrdinal) {
        Assert-PositiveInteger -Value $Event.reviewAttemptOrdinal -Name 'reviewAttemptOrdinal'
    }
    Assert-NullableString -Value $Event.supersedesReviewAttemptId -Name 'supersedesReviewAttemptId'
    Assert-EnumValue -Value $Event.eventType -Name 'eventType' -Allowed $script:EventTypes
    Assert-UtcTimestamp -Value $Event.occurredAtUtc -Name 'occurredAtUtc'
    Assert-Revision -Revision $Event.revision
    Assert-EnumValue -Value $Event.reviewMode -Name 'reviewMode' -Allowed $script:ReviewModes
    Assert-Provenance -Provenance $Event.provenance
    Assert-Usage -Usage $Event.usage

    if ([string] $Event.scope -ceq 'task' -and $null -eq $Event.taskRef) {
        Fail-Recorder "task-scoped events require a positive taskRef"
    }
    if ([string] $Event.scope -in @('story', 'final_story') -and $null -ne $Event.taskRef) {
        Fail-Recorder "story-scoped events require taskRef to be null"
    }

    if ([string] $Event.eventType -in @(
            'implementation_started', 'task_ready_for_review', 'review_started',
            'review_findings', 'review_accepted', 'correction_started',
            'correction_ready', 'final_review_started', 'final_review_accepted')) {
        if ($null -eq $Event.phaseId) {
            Fail-Recorder "phase-boundary events require a phaseId"
        }
    }
    if ([string] $Event.eventType -in @('story_started', 'pr_ready', 'wait_started', 'wait_ended') -and
        $null -ne $Event.phaseId) {
        Fail-Recorder "story and wait boundary events require phaseId to be null"
    }
    if ([string] $Event.eventType -in @('task_ready_for_review', 'correction_ready', 'final_review_started', 'final_review_accepted', 'pr_ready')) {
        if ($null -eq $Event.revision) {
            Fail-Recorder "this event type requires a full revision"
        }
    }
    if ([string] $Event.eventType -in @('review_started', 'review_findings', 'review_accepted', 'final_review_started', 'final_review_accepted')) {
        foreach ($name in @('reviewRequestId', 'reviewAttemptId', 'reviewKind', 'reviewAttemptOrdinal')) {
            if ($null -eq (Get-Property -Object $Event -Name $name).Value) {
                Fail-Recorder "review events require '$name'"
            }
        }
    }
    if ([string] $Event.eventType -in @('correction_started', 'correction_ready') -and $null -eq $Event.correctionId) {
        Fail-Recorder "correction events require a correctionId"
    }
}

function Read-EventJson {
    if (-not [string]::IsNullOrWhiteSpace($EventPath)) {
        if (-not [IO.Path]::IsPathRooted($EventPath)) {
            Fail-Recorder "'EventPath' must be an absolute path"
        }
        try {
            return [IO.File]::ReadAllText($EventPath)
        }
        catch {
            Fail-Recorder "event input could not be read"
        }
    }

    return $EventJson
}

function Parse-Event {
    param([Parameter(Mandatory)] [string] $Json)

    if ([string]::IsNullOrWhiteSpace($Json)) {
        Fail-Recorder 'event JSON must be nonblank'
    }

    try {
        # Keep timestamps as strings so validation rejects local DateTime
        # coercion and the persisted envelope retains the supplied UTC text.
        $event = $Json | ConvertFrom-Json -DateKind String
    }
    catch {
        Fail-Recorder 'event JSON is malformed'
    }

    if ($null -eq $event) {
        Fail-Recorder 'event JSON must contain one object'
    }
    return $event
}

function Write-LedgerLine {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $Line
    )

    $encoding = [Text.UTF8Encoding]::new($false)
    $bytes = $encoding.GetBytes($Line + [Environment]::NewLine)
    $stream = $null
    try {
        $stream = [IO.FileStream]::new(
            $LedgerPath,
            [IO.FileMode]::Append,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read,
            4096,
            [IO.FileOptions]::WriteThrough)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    catch {
        Fail-Recorder 'event ledger could not be written'
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

$expectedRoot = Get-FullPath -Path $ExternalRunRoot -Name 'ExternalRunRoot'
Assert-ExternalRunRoot -Root $expectedRoot
Assert-PathSafeRunId -Value $RunId

$eventText = Read-EventJson
$event = Parse-Event -Json $eventText
Assert-Event -Event $event -ExpectedRunId $RunId

$runDirectory = Join-Path $expectedRoot $RunId
$ledgerPath = Join-Path $runDirectory 'events.jsonl'
if (Test-Path -LiteralPath $runDirectory -PathType Leaf) {
    Fail-Recorder 'external run directory is not a directory'
}
if (Test-Path -LiteralPath $ledgerPath -PathType Container) {
    Fail-Recorder 'event ledger path is not a file'
}

try {
    [IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}
catch {
    Fail-Recorder 'external run directory could not be created'
}

$serializedEvent = $event | ConvertTo-Json -Compress -Depth 20
Write-LedgerLine -LedgerPath $ledgerPath -Line $serializedEvent

[ordered]@{
    status = 'appended'
    eventId = [string] $event.eventId
    runId = [string] $event.runId
    ledgerPath = $ledgerPath
} | ConvertTo-Json -Compress
