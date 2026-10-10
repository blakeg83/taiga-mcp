<#
.SYNOPSIS
    Aggregate a version-1 story performance event ledger.

.DESCRIPTION
    This entry point is deliberately read-only. It consumes the append-only
    JSONL ledger written by write-performance-event.ps1 and emits one
    deterministic story_performance_report object. It does not infer missing
    boundaries, subtract overlapping phases, estimate usage, or persist a
    report. Report publication and source-backed usage reconciliation are
    owned by later story tasks.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('EventPath', 'LedgerPath', 'InputPath')]
    [string] $EventsPath,

    [ValidateSet('per_task', 'story_end_only')]
    [string] $ReviewMode,

    [Alias('TaskRef')]
    [int[]] $TaskRefs,

    [string] $OutputPath,

    [string] $MarkdownPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:EventTypes = @(
    'story_started', 'implementation_started', 'task_ready_for_review',
    'review_started', 'review_findings', 'review_accepted',
    'correction_started', 'correction_ready', 'final_review_started',
    'final_review_accepted', 'pr_ready', 'wait_started', 'wait_ended'
)
$script:ReviewStartEvents = @('review_started', 'final_review_started')
$script:ReviewCloseEvents = @('review_findings', 'review_accepted', 'final_review_accepted')
$script:TopLevelFields = @(
    'schemaVersion', 'kind', 'eventId', 'runId', 'projectId', 'storyId',
    'storyRef', 'taskRef', 'role', 'sessionId', 'workerId', 'transitionId',
    'scope', 'phaseId', 'correctionId', 'reviewRequestId', 'reviewAttemptId',
    'reviewKind', 'reviewAttemptOrdinal', 'supersedesReviewAttemptId',
    'eventType', 'occurredAtUtc', 'revision', 'reviewMode', 'provenance',
    'usage', 'waitId', 'waitKind', 'pullRequest'
)
$script:ProvenanceFields = @('source', 'observedBy', 'observer', 'coverage', 'synthetic')
$script:UsageFields = @(
    'state', 'streamId', 'role', 'sessionId', 'source', 'counterSemantics',
    'coverage', 'sampledAtUtc', 'baselineAtUtc', 'counters', 'reason', 'fallback'
)
$script:CounterSemanticsFields = @('cachedInput', 'reasoning')
$script:CounterFields = @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')
$script:PullRequestFields = @('provider', 'owner', 'repository', 'number', 'reviewedHead')

function Get-PropertyValue {
    param(
        [AllowNull()] [object] $Object,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-PropertyPresent {
    param(
        [AllowNull()] [object] $Object,
        [Parameter(Mandatory)] [string] $Name
    )

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-UnknownPropertyName {
    param(
        [AllowNull()] [object] $Object,
        [Parameter(Mandatory)] [string[]] $Allowed
    )

    if ($null -eq $Object) {
        return $null
    }
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -notin $Allowed) {
            return [string] $property.Name
        }
    }
    return $null
}

function Test-NonBlankSafeString {
    param([AllowNull()] [object] $Value)

    return $Value -is [string] -and
        -not [string]::IsNullOrWhiteSpace([string] $Value) -and
        [string] $Value -notmatch '[\x00-\x1F\x7F]'
}

function Test-PositiveIntegerValue {
    param([AllowNull()] [object] $Value)

    if (-not (Test-JsonIntegerValue -Value $Value)) {
        return $false
    }
    try {
        $decimal = [decimal] $Value
        return $decimal -gt 0
    }
    catch {
        return $false
    }
}

function Test-JsonIntegerValue {
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
        $decimal = [decimal] $Value
        return $decimal -eq [decimal]::Truncate($decimal)
    }
    catch {
        return $false
    }
}

function Test-NonNegativeIntegerValue {
    param([AllowNull()] [object] $Value)

    if (-not (Test-JsonIntegerValue -Value $Value)) {
        return $false
    }
    return [decimal] $Value -ge 0
}

function Test-FullRevision {
    param([AllowNull()] [object] $Value)

    return Test-NonBlankSafeString -Value $Value -and [string] $Value -match '^[0-9a-fA-F]{40}$'
}

function Get-UsageValidationError {
    param(
        [AllowNull()] [object] $Usage,
        [Parameter(Mandatory)] [string] $EventRole
    )

    if ($null -eq $Usage) {
        return $null
    }
    if ($Usage -isnot [System.Management.Automation.PSCustomObject]) {
        return 'usage must be an object or null'
    }
    $unknown = Get-UnknownPropertyName -Object $Usage -Allowed $script:UsageFields
    if ($null -ne $unknown) {
        return "unknown usage field '$unknown'"
    }
    foreach ($name in @('state', 'source', 'coverage')) {
        if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $Usage $name))) {
            return "usage.$name must be present when usage is supplied"
        }
    }
    $state = [string] (Get-PropertyValue $Usage 'state')
    if ($state -cnotin @('measured', 'partial', 'unavailable', 'not_applicable')) {
        return 'usage.state is unsupported'
    }
    foreach ($name in @('streamId', 'sessionId', 'reason', 'fallback')) {
        $value = Get-PropertyValue $Usage $name
        if ($null -ne $value -and -not (Test-NonBlankSafeString -Value $value)) {
            return "usage.$name must be null or a nonblank safe string"
        }
    }
    $usageRole = Get-PropertyValue $Usage 'role'
    if ($null -ne $usageRole -and [string] $usageRole -cnotin @('coordinator', 'implementer', 'reviewer')) {
        return 'usage.role is unsupported'
    }
    foreach ($name in @('sampledAtUtc', 'baselineAtUtc')) {
        $value = Get-PropertyValue $Usage $name
        if ($null -ne $value) {
            $parsed = [DateTimeOffset]::MinValue
            if (-not (Try-GetUtcTime -Value $value -Parsed ([ref] $parsed))) {
                return "usage.$name must be a UTC timestamp or null"
            }
        }
    }

    $counterSemantics = Get-PropertyValue $Usage 'counterSemantics'
    $counters = Get-PropertyValue $Usage 'counters'
    if ($null -ne $counterSemantics) {
        if ($counterSemantics -isnot [System.Management.Automation.PSCustomObject]) {
            return 'usage.counterSemantics must be an object or null'
        }
        $unknown = Get-UnknownPropertyName -Object $counterSemantics -Allowed $script:CounterSemanticsFields
        if ($null -ne $unknown) {
            return "unknown usage.counterSemantics field '$unknown'"
        }
        $cachedInput = Get-PropertyValue $counterSemantics 'cachedInput'
        $reasoning = Get-PropertyValue $counterSemantics 'reasoning'
        if ($null -ne $cachedInput -and [string] $cachedInput -cnotin @('included_in_input', 'disjoint_from_input', 'unknown')) {
            return 'usage.counterSemantics.cachedInput is unsupported'
        }
        if ($null -ne $reasoning -and [string] $reasoning -cnotin @('included_in_output', 'disjoint_from_output', 'unknown')) {
            return 'usage.counterSemantics.reasoning is unsupported'
        }
    }
    $hasNumericCounters = $false
    if ($null -ne $counters) {
        if ($counters -isnot [System.Management.Automation.PSCustomObject]) {
            return 'usage.counters must be an object or null'
        }
        $unknown = Get-UnknownPropertyName -Object $counters -Allowed $script:CounterFields
        if ($null -ne $unknown) {
            return "unknown usage.counters field '$unknown'"
        }
        $hasNumericCounters = @($counters.PSObject.Properties).Count -gt 0
        foreach ($property in $counters.PSObject.Properties) {
            if (-not (Test-NonNegativeIntegerValue -Value $property.Value)) {
                return "usage.counters.$($property.Name) must be a nonnegative integer"
            }
        }
    }
    if ($hasNumericCounters) {
        if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $Usage 'streamId')) -or
            $null -eq $usageRole -or $null -eq (Get-PropertyValue $Usage 'sampledAtUtc') -or
            $null -eq $counterSemantics) {
            return 'numeric usage samples require stream, role, sampledAtUtc, and counterSemantics'
        }
        if ([string] $usageRole -cne $EventRole) {
            return 'usage.role must match event role'
        }
        if ($null -eq (Get-PropertyValue $counterSemantics 'cachedInput') -or
            $null -eq (Get-PropertyValue $counterSemantics 'reasoning')) {
            return 'numeric usage samples require both counter semantics'
        }
        if ($state -eq 'measured' -and
            ($null -eq (Get-PropertyValue $Usage 'baselineAtUtc') -or
            [string] (Get-PropertyValue $counterSemantics 'cachedInput') -eq 'unknown' -or
            [string] (Get-PropertyValue $counterSemantics 'reasoning') -eq 'unknown')) {
            return 'measured usage requires a baseline and known counter semantics'
        }
    }
    elseif ($state -eq 'measured') {
        return 'measured usage requires nonempty counters'
    }
    return $null
}

function Get-BindingKey {
    param([Parameter(Mandatory)] [object] $Event)

    return @(
        [string] (Get-PropertyValue $Event 'runId')
        [string] (Get-PropertyValue $Event 'projectId')
        [string] (Get-PropertyValue $Event 'storyId')
        [string] (Get-PropertyValue $Event 'storyRef')
    ) -join '|'
}

function Get-SafePullRequest {
    param([AllowNull()] [object] $PullRequest)

    if ($null -eq $PullRequest) {
        return $null
    }
    return [pscustomobject][ordered]@{
        provider = Get-PropertyValue $PullRequest 'provider'
        owner = Get-PropertyValue $PullRequest 'owner'
        repository = Get-PropertyValue $PullRequest 'repository'
        number = Get-PropertyValue $PullRequest 'number'
        reviewedHead = Get-PropertyValue $PullRequest 'reviewedHead'
    }
}

function Get-ImmutableBoundaryCanonical {
    param([Parameter(Mandatory)] [object] $Event)

    $copy = [ordered]@{}
    foreach ($property in @($Event.PSObject.Properties | Where-Object { $_.Name -ne 'eventId' } | Sort-Object Name)) {
        $copy[$property.Name] = ConvertTo-CanonicalValue -Value $property.Value
    }
    return ConvertTo-CanonicalJson -Value ([pscustomobject] $copy)
}

function Get-EventValidationError {
    param([AllowNull()] [object] $Event)

    if ($null -eq $Event -or $Event -isnot [System.Management.Automation.PSCustomObject]) {
        return 'event must be a JSON object'
    }

    $unknown = Get-UnknownPropertyName -Object $Event -Allowed $script:TopLevelFields
    if ($null -ne $unknown) {
        return "unknown envelope field '$unknown'"
    }

    $required = @(
        'schemaVersion', 'kind', 'eventId', 'runId', 'projectId', 'storyId',
        'storyRef', 'taskRef', 'role', 'sessionId', 'workerId', 'transitionId',
        'scope', 'phaseId', 'correctionId', 'reviewRequestId', 'reviewAttemptId',
        'reviewKind', 'reviewAttemptOrdinal', 'supersedesReviewAttemptId',
        'eventType', 'occurredAtUtc', 'revision', 'reviewMode', 'provenance',
        'usage'
    )
    foreach ($name in $required) {
        if (-not (Test-PropertyPresent -Object $Event -Name $name)) {
            return "missing required envelope field '$name'"
        }
    }

    if (-not (Test-PositiveIntegerValue -Value (Get-PropertyValue $Event 'schemaVersion')) -or
        [int] (Get-PropertyValue $Event 'schemaVersion') -ne 1) {
        return 'schemaVersion must be 1'
    }
    if ([string] (Get-PropertyValue $Event 'kind') -cne 'story_performance_event') {
        return 'kind must be story_performance_event'
    }
    foreach ($name in @('eventId', 'runId', 'transitionId')) {
        if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $Event $name))) {
            return "$name must be a nonblank safe string"
        }
    }
    foreach ($name in @('projectId', 'storyId', 'storyRef')) {
        if (-not (Test-PositiveIntegerValue -Value (Get-PropertyValue $Event $name))) {
            return "$name must be a positive integer"
        }
    }

    $taskRef = Get-PropertyValue $Event 'taskRef'
    if ($null -ne $taskRef -and -not (Test-PositiveIntegerValue -Value $taskRef)) {
        return 'taskRef must be a positive integer or null'
    }
    if ([string] (Get-PropertyValue $Event 'role') -cnotin @('coordinator', 'implementer', 'reviewer')) {
        return 'role is unsupported'
    }
    if ([string] (Get-PropertyValue $Event 'scope') -cnotin @('task', 'final_story', 'story')) {
        return 'scope is unsupported'
    }
    if ([string] (Get-PropertyValue $Event 'reviewMode') -cnotin @('per_task', 'story_end_only')) {
        return 'reviewMode is unsupported'
    }
    $time = [DateTimeOffset]::MinValue
    if (-not (Try-GetUtcTime -Value (Get-PropertyValue $Event 'occurredAtUtc') -Parsed ([ref] $time))) {
        return 'occurredAtUtc must be a UTC timestamp ending in Z'
    }

    foreach ($name in @('sessionId', 'workerId', 'phaseId', 'correctionId', 'reviewRequestId', 'reviewAttemptId', 'reviewKind', 'supersedesReviewAttemptId')) {
        $value = Get-PropertyValue $Event $name
        if ($null -ne $value -and -not (Test-NonBlankSafeString -Value $value)) {
            return "$name must be null or a nonblank safe string"
        }
    }
    $ordinal = Get-PropertyValue $Event 'reviewAttemptOrdinal'
    if ($null -ne $ordinal -and -not (Test-PositiveIntegerValue -Value $ordinal)) {
        return 'reviewAttemptOrdinal must be a positive integer or null'
    }
    $revision = Get-PropertyValue $Event 'revision'
    if ($null -ne $revision -and -not (Test-FullRevision -Value $revision)) {
        return 'revision must be a full Git SHA or null'
    }

    $provenance = Get-PropertyValue $Event 'provenance'
    if ($provenance -isnot [System.Management.Automation.PSCustomObject]) {
        return 'provenance must be an object'
    }
    $unknown = Get-UnknownPropertyName -Object $provenance -Allowed $script:ProvenanceFields
    if ($null -ne $unknown) {
        return "unknown provenance field '$unknown'"
    }
    foreach ($name in @('source', 'coverage')) {
        if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $provenance $name))) {
            return "provenance.$name must be a nonblank safe string"
        }
    }
    if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $provenance 'observedBy')) -and
        -not (Test-NonBlankSafeString -Value (Get-PropertyValue $provenance 'observer'))) {
        return 'provenance requires observedBy or observer'
    }
    $synthetic = Get-PropertyValue $provenance 'synthetic'
    if ($null -ne $synthetic -and $synthetic -isnot [bool]) {
        return 'provenance.synthetic must be Boolean or null'
    }

    $usageError = Get-UsageValidationError -Usage (Get-PropertyValue $Event 'usage') -EventRole ([string] (Get-PropertyValue $Event 'role'))
    if ($null -ne $usageError) {
        return $usageError
    }

    $eventType = [string] (Get-PropertyValue $Event 'eventType')
    if ($eventType -notin $script:EventTypes) {
        return 'eventType is unsupported'
    }
    $scope = [string] (Get-PropertyValue $Event 'scope')
    $role = [string] (Get-PropertyValue $Event 'role')
    $phaseId = Get-PropertyValue $Event 'phaseId'
    $correctionId = Get-PropertyValue $Event 'correctionId'
    $reviewRequestId = Get-PropertyValue $Event 'reviewRequestId'
    $reviewAttemptId = Get-PropertyValue $Event 'reviewAttemptId'
    $reviewKind = Get-PropertyValue $Event 'reviewKind'
    $reviewOrdinal = Get-PropertyValue $Event 'reviewAttemptOrdinal'
    $pullRequest = Get-PropertyValue $Event 'pullRequest'
    $waitId = Get-PropertyValue $Event 'waitId'
    $waitKind = Get-PropertyValue $Event 'waitKind'

    if ($scope -eq 'task' -and $null -eq $taskRef) {
        return 'task-scoped event requires taskRef'
    }
    if ($scope -in @('story', 'final_story') -and $null -ne $taskRef) {
        return 'story-scoped event requires taskRef null'
    }
    if ($eventType -in @('wait_started', 'wait_ended')) {
        if (-not (Test-NonBlankSafeString -Value $waitId) -or -not (Test-NonBlankSafeString -Value $waitKind)) {
            return 'wait boundary requires waitId and waitKind'
        }
        if ($null -ne $phaseId -or $null -ne $revision) {
            return 'wait boundary requires phaseId and revision null'
        }
    }
    elseif ($null -ne $waitId -or $null -ne $waitKind) {
        return 'wait identity is only valid on wait boundaries'
    }

    if ($eventType -eq 'story_started') {
        if ($scope -ne 'story' -or $role -ne 'coordinator' -or $null -ne $phaseId -or $null -ne $revision) {
            return 'story_started has invalid scope, role, phaseId, or revision'
        }
    }
    elseif ($eventType -eq 'pr_ready') {
        if ($scope -ne 'story' -or $role -ne 'coordinator' -or $null -ne $phaseId -or -not (Test-FullRevision -Value $revision)) {
            return 'pr_ready has invalid scope, role, phaseId, or revision'
        }
        if ($pullRequest -isnot [System.Management.Automation.PSCustomObject]) {
            return 'pr_ready requires a pullRequest object'
        }
        $unknown = Get-UnknownPropertyName -Object $pullRequest -Allowed $script:PullRequestFields
        if ($null -ne $unknown) {
            return "unknown pullRequest field '$unknown'"
        }
        foreach ($name in $script:PullRequestFields) {
            if (-not (Test-PropertyPresent -Object $pullRequest -Name $name)) {
                return "pullRequest.$name is required"
            }
        }
        foreach ($name in @('provider', 'owner', 'repository')) {
            if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $pullRequest $name))) {
                return "pullRequest.$name is required"
            }
        }
        if (-not (Test-PositiveIntegerValue -Value (Get-PropertyValue $pullRequest 'number')) -or
            -not (Test-FullRevision -Value (Get-PropertyValue $pullRequest 'reviewedHead')) -or
            [string] (Get-PropertyValue $pullRequest 'reviewedHead') -cne [string] $revision) {
            return 'pullRequest identity must match pr_ready revision'
        }
    }
    elseif ($null -ne $pullRequest) {
        return 'pullRequest is only valid on pr_ready'
    }

    if ($eventType -eq 'implementation_started' -and
        ($scope -ne 'task' -or $role -ne 'implementer' -or $null -eq $phaseId)) {
        return 'implementation_started has invalid identity'
    }
    if ($eventType -eq 'task_ready_for_review' -and
        ($scope -ne 'task' -or $role -ne 'implementer' -or $null -eq $phaseId -or -not (Test-FullRevision -Value $revision))) {
        return 'task_ready_for_review has invalid identity'
    }

    $isReviewEvent = $eventType -in @('review_started', 'review_findings', 'review_accepted', 'final_review_started', 'final_review_accepted')
    if ($isReviewEvent) {
        if ($scope -notin @('task', 'final_story') -or $role -ne 'reviewer' -or $null -eq $phaseId -or -not (Test-FullRevision -Value $revision) -or
            -not (Test-NonBlankSafeString -Value $reviewRequestId) -or -not (Test-NonBlankSafeString -Value $reviewAttemptId) -or
            $null -eq $reviewKind -or $null -eq $reviewOrdinal) {
            return 'review event has incomplete identity'
        }
        if ($scope -eq 'task' -and [string] $reviewKind -notin @('initial_task', 'correction_rereview')) {
            return 'task review kind is unsupported'
        }
        if ($scope -eq 'final_story' -and [string] $reviewKind -notin @('final_story', 'final_story_rereview')) {
            return 'final-story review kind is unsupported'
        }
        if ($eventType -in @('final_review_started', 'final_review_accepted') -and $scope -ne 'final_story') {
            return 'final review event requires final_story scope'
        }
    }
    elseif ($null -ne $reviewRequestId -or $null -ne $reviewAttemptId -or $null -ne $reviewKind -or $null -ne $reviewOrdinal) {
        return 'review identity is only valid on review events'
    }

    $isCorrectionEvent = $eventType -in @('correction_started', 'correction_ready')
    if ($isCorrectionEvent) {
        if ($scope -notin @('task', 'final_story') -or $role -ne 'implementer' -or $null -eq $phaseId -or
            -not (Test-NonBlankSafeString -Value $correctionId) -or -not (Test-NonBlankSafeString -Value (Get-PropertyValue $Event 'supersedesReviewAttemptId'))) {
            return 'correction event has incomplete identity'
        }
        if ($eventType -eq 'correction_started' -and $null -ne $revision) {
            return 'correction_started requires revision null'
        }
        if ($eventType -eq 'correction_ready' -and -not (Test-FullRevision -Value $revision)) {
            return 'correction_ready requires a full revision'
        }
    }
    elseif ($null -ne $correctionId) {
        return 'correctionId is only valid on correction events'
    }
    if (-not $isCorrectionEvent -and $null -ne (Get-PropertyValue $Event 'supersedesReviewAttemptId')) {
        return 'supersedesReviewAttemptId is only valid on correction events'
    }

    return $null
}

function ConvertTo-CanonicalValue {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object { [string] $_ })) {
            $ordered[[string] $key] = ConvertTo-CanonicalValue -Value $Value[$key]
        }
        return $ordered
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $ordered[$property.Name] = ConvertTo-CanonicalValue -Value $property.Value
        }
        return $ordered
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            [void] $items.Add((ConvertTo-CanonicalValue -Value $item))
        }
        return @($items)
    }

    return $Value
}

function ConvertTo-CanonicalJson {
    param([AllowNull()] [object] $Value)

    return (ConvertTo-CanonicalValue -Value $Value | ConvertTo-Json -Compress -Depth 100)
}

function New-Anomaly {
    param(
        [Parameter(Mandatory)] [string] $Code,
        [Parameter(Mandatory)] [string] $Message,
        [AllowNull()] [string] $Identity,
        [AllowNull()] [int] $Line,
        [AllowNull()] [string[]] $EventIds
    )

    $result = [ordered]@{
        code = $Code
        message = $Message
    }
    if (-not [string]::IsNullOrWhiteSpace($Identity)) {
        $result.identity = $Identity
    }
    if ($null -ne $Line) {
        $result.line = $Line
    }
    if ($null -ne $EventIds -and @($EventIds).Count -gt 0) {
        $result.eventIds = @($EventIds)
    }
    return [pscustomobject] $result
}

function Try-GetUtcTime {
    param(
        [AllowNull()] [object] $Value,
        [ref] $Parsed
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        return $false
    }

    $text = [string] $Value
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') {
        return $false
    }

    $candidate = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            $text,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref] $candidate)) {
        return $false
    }

    if ($candidate.Offset -ne [TimeSpan]::Zero) {
        return $false
    }

    $Parsed.Value = $candidate
    return $true
}

function Get-TaskText {
    param([AllowNull()] [object] $Event)

    $taskRef = Get-PropertyValue -Object $Event -Name 'taskRef'
    if ($null -eq $taskRef) {
        return $null
    }
    return [string] $taskRef
}

function Get-PhaseIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = [string] (Get-PropertyValue $Event 'scope')
    $task = Get-TaskText -Event $Event
    $phase = [string] (Get-PropertyValue $Event 'phaseId')
    $correction = [string] (Get-PropertyValue $Event 'correctionId')
    return ($scope, $task, $phase, $correction -join '|')
}

function Get-WaitIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = [string] (Get-PropertyValue $Event 'scope')
    $task = Get-TaskText -Event $Event
    $waitId = [string] (Get-PropertyValue $Event 'waitId')
    return ($scope, $task, $waitId -join '|')
}

function Get-ReviewIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = [string] (Get-PropertyValue $Event 'scope')
    $task = Get-TaskText -Event $Event
    $phase = [string] (Get-PropertyValue $Event 'phaseId')
    $request = [string] (Get-PropertyValue $Event 'reviewRequestId')
    $attempt = [string] (Get-PropertyValue $Event 'reviewAttemptId')
    $ordinal = [string] (Get-PropertyValue $Event 'reviewAttemptOrdinal')
    $kind = [string] (Get-PropertyValue $Event 'reviewKind')
    $revision = [string] (Get-PropertyValue $Event 'revision')
    return ($scope, $task, $phase, $request, $attempt, $ordinal, $kind, $revision -join '|')
}

function Get-ReviewAttemptIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = [string] (Get-PropertyValue $Event 'scope')
    $task = Get-TaskText -Event $Event
    $request = [string] (Get-PropertyValue $Event 'reviewRequestId')
    $attempt = [string] (Get-PropertyValue $Event 'reviewAttemptId')
    return ($scope, $task, $request, $attempt -join '|')
}

function Get-ReviewAttemptBindingIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = [string] (Get-PropertyValue $Event 'scope')
    $task = Get-TaskText -Event $Event
    $attempt = [string] (Get-PropertyValue $Event 'reviewAttemptId')
    return ($scope, $task, $attempt -join '|')
}

function Get-ReviewRequestBindingCanonical {
    param([Parameter(Mandatory)] [object] $Event)

    $binding = [ordered]@{
        scope = Get-PropertyValue $Event 'scope'
        taskRef = Get-PropertyValue $Event 'taskRef'
        revision = Get-PropertyValue $Event 'revision'
    }
    return ConvertTo-CanonicalJson -Value ([pscustomobject] $binding)
}

function Add-ToIndex {
    param(
        [Parameter(Mandatory)] [hashtable] $Index,
        [Parameter(Mandatory)] [string] $Key,
        [Parameter(Mandatory)] [object] $Value
    )

    if (-not $Index.ContainsKey($Key)) {
        $Index[$Key] = [System.Collections.ArrayList]::new()
    }
    [void] $Index[$Key].Add($Value)
}

function New-Metric {
    param(
        [Parameter(Mandatory)] [string] $State,
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Unit,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Calculation,
        [Parameter(Mandatory)] [string] $Coverage,
        [AllowNull()] [string] $MissingData
    )

    return [pscustomobject][ordered]@{
        state = $State
        value = $Value
        unit = $Unit
        source = $Source
        calculation = $Calculation
        coverage = $Coverage
        missingData = $MissingData
    }
}

function Get-IntervalResult {
    param(
        [AllowNull()] [object] $Starts,
        [AllowNull()] [object] $Ends,
        [Parameter(Mandatory)] [string] $Identity,
        [Parameter(Mandatory)] [string] $Kind,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    $startItems = @($Starts | Where-Object { $null -ne $_ })
    $endItems = @($Ends | Where-Object { $null -ne $_ })
    $startCount = $startItems.Count
    $endCount = $endItems.Count
    $start = if ($startCount -eq 1) { $startItems | Select-Object -First 1 } else { $null }
    $end = if ($endCount -eq 1) { $endItems | Select-Object -First 1 } else { $null }
    $state = 'measured'
    $elapsed = $null
    $missing = $null

    if ($startCount -eq 0 -and $endCount -eq 0) {
        $state = 'unavailable'
        $missing = 'no boundaries recorded'
        [void] $Anomalies.Add((New-Anomaly -Code 'missing_boundary' -Message "$Kind interval has no recorded boundaries" -Identity $Identity))
    }
    elseif ($startCount -eq 0 -or $endCount -eq 0) {
        $state = 'partial'
        $missing = if ($startCount -eq 0) { 'missing start boundary' } else { 'missing end boundary' }
        $ids = @($startItems + $endItems | ForEach-Object { $_.EventId })
        [void] $Anomalies.Add((New-Anomaly -Code 'missing_boundary' -Message "$Kind interval has an incomplete boundary" -Identity $Identity -EventIds $ids))
    }
    elseif ($startCount -ne 1 -or $endCount -ne 1) {
        $state = 'partial'
        $missing = 'ambiguous duplicate boundary'
        [void] $Anomalies.Add((New-Anomaly -Code 'conflicting_boundary' -Message "$Kind interval has more than one start or end boundary" -Identity $Identity -EventIds @($startItems + $endItems | ForEach-Object { $_.EventId })))
    }
    else {
        $waitConflict = $false
        if ($Kind -eq 'wait') {
            $startWaitKind = [string] (Get-PropertyValue $start.Event 'waitKind')
            $endWaitKind = [string] (Get-PropertyValue $end.Event 'waitKind')
            $startRole = [string] (Get-PropertyValue $start.Event 'role')
            $endRole = [string] (Get-PropertyValue $end.Event 'role')
            $waitConflict = $startWaitKind -cne $endWaitKind -or $startRole -cne $endRole
            if ($waitConflict) {
                $state = 'partial'
                $missing = 'wait kind or actor attribution changed between boundaries'
                [void] $Anomalies.Add((New-Anomaly -Code 'conflicting_boundary' -Message 'Wait boundaries disagree on immutable wait kind or actor attribution and were not paired' -Identity $Identity -EventIds @($start.EventId, $end.EventId)))
            }
        }
        if (-not $waitConflict) {
            $difference = $end.Time - $start.Time
        }
        if (-not $waitConflict -and $difference.TotalMilliseconds -lt 0) {
            $state = 'partial'
            $missing = 'end boundary precedes start boundary'
            [void] $Anomalies.Add((New-Anomaly -Code 'negative_interval' -Message "$Kind interval has a reversed UTC boundary" -Identity $Identity -EventIds @($start.EventId, $end.EventId)))
        }
        elseif (-not $waitConflict) {
            $elapsed = [long] [Math]::Round($difference.TotalMilliseconds, [MidpointRounding]::AwayFromZero)
        }
    }

    $task = $null
    $phaseId = $null
    if ($null -ne $start) {
        $taskValue = Get-PropertyValue $start.Event 'taskRef'
        $task = if ($null -ne $taskValue) { [int] $taskValue } else { $null }
        $phaseId = Get-PropertyValue $start.Event 'phaseId'
    }
    elseif ($null -ne $end) {
        $taskValue = Get-PropertyValue $end.Event 'taskRef'
        $task = if ($null -ne $taskValue) { [int] $taskValue } else { $null }
        $phaseId = Get-PropertyValue $end.Event 'phaseId'
    }

    return [pscustomobject][ordered]@{
        kind = $Kind
        identity = $Identity
        taskRef = $task
        phaseId = $phaseId
        startUtc = if ($null -ne $start) { [string] (Get-PropertyValue $start.Event 'occurredAtUtc') } else { $null }
        endUtc = if ($null -ne $end) { [string] (Get-PropertyValue $end.Event 'occurredAtUtc') } else { $null }
        startRole = if ($null -ne $start) { Get-PropertyValue $start.Event 'role' } else { $null }
        endRole = if ($null -ne $end) { Get-PropertyValue $end.Event 'role' } else { $null }
        waitKind = if ($null -ne $start) { Get-PropertyValue $start.Event 'waitKind' } elseif ($null -ne $end) { Get-PropertyValue $end.Event 'waitKind' } else { $null }
        elapsedMilliseconds = $elapsed
        state = $state
        missingData = $missing
    }
}

function Get-IntervalCollection {
    param(
        [Parameter(Mandatory)] [string] $Kind,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    $Starts = $script:IntervalStarts
    $Ends = $script:IntervalEnds
    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Starts.Keys) {
        $text = [string] $key
        if (-not $keys.Contains($text)) {
            [void] $keys.Add($text)
        }
    }
    foreach ($key in $Ends.Keys) {
        $text = [string] $key
        if (-not $keys.Contains($text)) {
            [void] $keys.Add($text)
        }
    }
    $keys = @($keys | Sort-Object)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $keys) {
        $startValues = if ($Starts.ContainsKey($key)) { @($Starts[$key]) } else { @() }
        $endValues = if ($Ends.ContainsKey($key)) { @($Ends[$key]) } else { @() }
        [void] $results.Add((Get-IntervalResult -Starts $startValues -Ends $endValues -Identity $key -Kind $Kind -Anomalies $Anomalies))
    }
    return @($results)
}

function Add-OverlapAnomalies {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Intervals,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    $valid = @($Intervals | Where-Object { $_.state -eq 'measured' -and $null -ne $_.startUtc -and $null -ne $_.endUtc })
    for ($i = 0; $i -lt $valid.Count; $i++) {
        for ($j = $i + 1; $j -lt $valid.Count; $j++) {
            $leftStart = [DateTimeOffset]::Parse($valid[$i].startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $leftEnd = [DateTimeOffset]::Parse($valid[$i].endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $rightStart = [DateTimeOffset]::Parse($valid[$j].startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $rightEnd = [DateTimeOffset]::Parse($valid[$j].endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            if (($leftStart -lt $leftEnd) -and ($rightStart -lt $rightEnd) -and
                ($leftStart -lt $rightEnd) -and ($rightStart -lt $leftEnd)) {
                [void] $Anomalies.Add((New-Anomaly -Code 'overlapping_intervals' -Message 'Valid phase intervals overlap; totals remain separate and are not made additive wall-clock time' -Identity "$($valid[$i].identity)|$($valid[$j].identity)"))
            }
        }
    }
}

function Get-ByteSlice {
    param(
        [Parameter(Mandatory)] [byte[]] $Bytes,
        [Parameter(Mandatory)] [int] $Offset,
        [Parameter(Mandatory)] [int] $Count
    )

    $result = [byte[]]::new($Count)
    if ($Count -gt 0) {
        [Array]::Copy($Bytes, $Offset, $result, 0, $Count)
    }
    return ,$result
}

function Get-UncoveredStorySpan {
    param(
        [Parameter(Mandatory)] [object] $StorySpan,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Intervals
    )

    if ($StorySpan.state -ne 'measured' -or $null -eq $StorySpan.startUtc -or $null -eq $StorySpan.endUtc) {
        return [pscustomobject][ordered]@{
            state = 'unavailable'
            value = $null
            unit = 'milliseconds'
            startUtc = $null
            endUtc = $null
            calculation = 'explicit union of valid phase, review, and wait intervals within story boundaries'
            coverage = 'story boundaries are not both measured'
            missingData = 'story start or confirmed PR readiness is unavailable'
        }
    }

    $spanStart = [DateTimeOffset]::Parse([string] $StorySpan.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $spanEnd = [DateTimeOffset]::Parse([string] $StorySpan.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $segments = @($Intervals | Where-Object { $_.state -eq 'measured' -and $null -ne $_.startUtc -and $null -ne $_.endUtc } | ForEach-Object {
        $start = [DateTimeOffset]::Parse([string] $_.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $end = [DateTimeOffset]::Parse([string] $_.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($end -gt $spanStart -and $start -lt $spanEnd) {
            [pscustomobject]@{
                start = if ($start -lt $spanStart) { $spanStart } else { $start }
                end = if ($end -gt $spanEnd) { $spanEnd } else { $end }
            }
        }
    } | Sort-Object start, end)

    $gaps = [System.Collections.Generic.List[object]]::new()
    $cursor = $spanStart
    foreach ($segment in $segments) {
        if ($segment.start -gt $cursor) {
            [void] $gaps.Add([pscustomobject][ordered]@{
                startUtc = $cursor.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
                endUtc = $segment.start.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
                durationMilliseconds = [long] [Math]::Round(($segment.start - $cursor).TotalMilliseconds, [MidpointRounding]::AwayFromZero)
            })
        }
        if ($segment.end -gt $cursor) {
            $cursor = $segment.end
        }
    }
    if ($cursor -lt $spanEnd) {
        [void] $gaps.Add([pscustomobject][ordered]@{
            startUtc = $cursor.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
            endUtc = $spanEnd.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
            durationMilliseconds = [long] [Math]::Round(($spanEnd - $cursor).TotalMilliseconds, [MidpointRounding]::AwayFromZero)
        })
    }

    return [pscustomobject][ordered]@{
        state = if ($gaps.Count -eq 0) { 'measured' } else { 'partial' }
        value = @($gaps)
        unit = 'milliseconds'
        startUtc = [string] $StorySpan.startUtc
        endUtc = [string] $StorySpan.endUtc
        calculation = 'explicit union of valid phase, review, and wait intervals within story boundaries'
        coverage = "explicit intervals cover the story span with $($gaps.Count) uncovered gap(s); gaps are not inferred activity"
        missingData = if ($gaps.Count -eq 0) { $null } else { 'no attributable event interval covers the listed story-span gaps' }
    }
}

function Read-EventLedger {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("Events ledger was not found: $Path")
    }

    $byEventId = @{}
    $records = [System.Collections.Generic.List[object]]::new()
    $ledgerBytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $allLines = [System.Collections.Generic.List[object]]::new()
    $lineStart = 0
    for ($offset = 0; $offset -lt $ledgerBytes.Length; $offset++) {
        if ($ledgerBytes[$offset] -ne [byte] 0x0A) {
            continue
        }
        $lineLength = $offset - $lineStart
        $contentLength = $lineLength
        if ($contentLength -gt 0 -and $ledgerBytes[$offset - 1] -eq [byte] 0x0D) {
            $contentLength--
        }
        $lineBytes = Get-ByteSlice -Bytes $ledgerBytes -Offset $lineStart -Count $contentLength
        try {
            $line = $utf8.GetString($lineBytes)
            if ($allLines.Count -eq 0 -and $line.Length -gt 0 -and $line[0] -eq [char] 0xFEFF) {
                $line = $line.Substring(1)
            }
        }
        catch {
            [void] $Anomalies.Add((New-Anomaly -Code 'invalid_utf8' -Message 'A ledger line was not valid UTF-8 and was excluded from aggregation' -Line ($allLines.Count + 1)))
            $line = $null
        }
        [void] $allLines.Add($line)
        $lineStart = $offset + 1
    }

    $tailLength = $ledgerBytes.Length - $lineStart
    $hasCompleteFinalNewline = $tailLength -eq 0
    for ($lineIndex = 0; $lineIndex -lt $allLines.Count; $lineIndex++) {
        $line = $allLines[$lineIndex]
        $lineNumber = $lineIndex + 1
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json -Depth 100 -DateKind String
        }
        catch {
            [void] $Anomalies.Add((New-Anomaly -Code 'malformed_event' -Message 'A ledger line was not valid JSON and was excluded from aggregation' -Line $lineNumber))
            continue
        }

        $eventIdValue = Get-PropertyValue $event 'eventId'
        if ($null -eq $eventIdValue -or [string]::IsNullOrWhiteSpace([string] $eventIdValue)) {
            [void] $Anomalies.Add((New-Anomaly -Code 'missing_event_identity' -Message 'An event without a stable eventId was excluded from aggregation' -Line $lineNumber))
            continue
        }

        $eventId = [string] $eventIdValue
        $validationError = Get-EventValidationError -Event $event
        if ($null -ne $validationError) {
            [void] $Anomalies.Add((New-Anomaly -Code 'invalid_event' -Message $validationError -Identity $eventId -Line $lineNumber -EventIds @($eventId)))
            continue
        }

        $eventType = [string] (Get-PropertyValue $event 'eventType')
        $time = [DateTimeOffset]::MinValue
        if (-not (Try-GetUtcTime -Value (Get-PropertyValue $event 'occurredAtUtc') -Parsed ([ref] $time))) {
            [void] $Anomalies.Add((New-Anomaly -Code 'invalid_timestamp' -Message 'An event without a valid UTC occurredAtUtc was excluded from aggregation' -Identity $eventId -Line $lineNumber -EventIds @($eventId)))
            continue
        }

        $canonical = ConvertTo-CanonicalJson -Value $event
        if ($byEventId.ContainsKey($eventId)) {
            $existing = $byEventId[$eventId]
            if ($existing.canonical -ceq $canonical) {
                [void] $Anomalies.Add((New-Anomaly -Code 'duplicate_event' -Message 'An exact event replay was ignored' -Identity $eventId -Line $lineNumber -EventIds @($eventId)))
            }
            else {
                [void] $Anomalies.Add((New-Anomaly -Code 'event_identity_conflict' -Message 'A stable eventId was observed with a different immutable payload; the first record remains authoritative' -Identity $eventId -Line $lineNumber -EventIds @($eventId, $existing.EventId)))
            }
            continue
        }

        $record = [pscustomobject][ordered]@{
            Event = $event
            EventId = $eventId
            EventType = $eventType
            Time = $time
            Line = $lineNumber
            Canonical = $canonical
        }
        $byEventId[$eventId] = $record
        [void] $records.Add($record)
    }

    if (-not $hasCompleteFinalNewline) {
        [void] $Anomalies.Add((New-Anomaly -Code 'incomplete_tail' -Message 'The final ledger fragment has no terminating newline and was excluded as an interrupted tail' -Line ($allLines.Count + 1)))
    }

    return @($records | Sort-Object Time, Line)
}

function New-CountMetric {
    param(
        [Parameter(Mandatory)] [int] $Value,
        [Parameter(Mandatory)] [string] $Unit,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Coverage,
        [AllowNull()] [string] $MissingData,
        [string] $State = 'measured'
    )

    return New-Metric -State $State -Value $Value -Unit $Unit -Source $Source -Calculation 'count distinct authoritative identities' -Coverage $Coverage -MissingData $MissingData
}

function ConvertTo-Markdown {
    param([Parameter(Mandatory)] [object] $Report)

    $lines = [System.Collections.Generic.List[string]]::new()
    [void] $lines.Add('# Story performance report')
    [void] $lines.Add('')
    [void] $lines.Add("- Run: $($Report.runId)")
    [void] $lines.Add("- Story: $($Report.projectId)/$($Report.storyId) (#$($Report.storyRef))")
    [void] $lines.Add("- Review mode: $($Report.reviewMode)")
    [void] $lines.Add('')
    [void] $lines.Add('| Metric | State | Value | Coverage |')
    [void] $lines.Add('| --- | --- | ---: | --- |')
    foreach ($property in @($Report.metrics.PSObject.Properties)) {
        $metric = $property.Value
        $value = if ($null -eq $metric.value) { 'unknown' } else { [string] $metric.value }
        [void] $lines.Add("| $($property.Name) | $($metric.state) | $value | $($metric.coverage) |")
    }
    [void] $lines.Add('')
    [void] $lines.Add("Anomalies: $(@($Report.anomalies).Count)")
    foreach ($anomaly in @($Report.anomalies)) {
        [void] $lines.Add("- [$($anomaly.code)] $($anomaly.message)")
    }
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

$resolvedEventsPath = [IO.Path]::GetFullPath($EventsPath)
$anomalies = [System.Collections.Generic.List[object]]::new()
$records = @(Read-EventLedger -Path $resolvedEventsPath -Anomalies $anomalies)

if ($records.Count -eq 0) {
    throw [System.ArgumentException]::new('The events ledger contains no valid events')
}

$ledgerOrder = @($records | Sort-Object Line)
$bindingKey = Get-BindingKey -Event $ledgerOrder[0].Event
$foreignRecords = @($records | Where-Object { (Get-BindingKey -Event $_.Event) -cne $bindingKey })
foreach ($foreign in $foreignRecords) {
    [void] $anomalies.Add((New-Anomaly -Code 'foreign_binding' -Message 'An event from another run/project/story binding was quarantined and excluded from aggregation' -Identity $foreign.EventId -Line $foreign.Line -EventIds @($foreign.EventId)))
}
$records = @($records | Where-Object { (Get-BindingKey -Event $_.Event) -ceq $bindingKey })

$eventObjects = @($records | ForEach-Object { $_.Event })
$runIds = @($eventObjects | ForEach-Object { [string] (Get-PropertyValue $_ 'runId') } | Sort-Object -Unique)
$projectIds = @($eventObjects | ForEach-Object { [int] (Get-PropertyValue $_ 'projectId') } | Sort-Object -Unique)
$storyIds = @($eventObjects | ForEach-Object { [int] (Get-PropertyValue $_ 'storyId') } | Sort-Object -Unique)
$storyRefs = @($eventObjects | ForEach-Object { [int] (Get-PropertyValue $_ 'storyRef') } | Sort-Object -Unique)
$eventModes = @($eventObjects | ForEach-Object { [string] (Get-PropertyValue $_ 'reviewMode') } | Sort-Object -Unique)

$declaredTaskRefs = [System.Collections.Generic.List[int]]::new()
foreach ($candidateTaskRef in @($TaskRefs)) {
    if (Test-PositiveIntegerValue -Value $candidateTaskRef) {
        $candidateTaskRefInt = [int] $candidateTaskRef
        if (-not $declaredTaskRefs.Contains($candidateTaskRefInt)) {
            [void] $declaredTaskRefs.Add($candidateTaskRefInt)
        }
    }
}
$taskSetWasDeclared = $PSBoundParameters.ContainsKey('TaskRefs') -and $declaredTaskRefs.Count -gt 0
if (-not $taskSetWasDeclared) {
    [void] $anomalies.Add((New-Anomaly -Code 'missing_task_set' -Message 'No declared ordered task set was supplied; task review coverage is partial and observed tasks are not presented as complete'))
}
if ($PSBoundParameters.ContainsKey('TaskRefs') -and @($TaskRefs | Where-Object { -not (Test-PositiveIntegerValue -Value $_) }).Count -gt 0) {
    [void] $anomalies.Add((New-Anomaly -Code 'invalid_task_set' -Message 'One or more declared task references were not positive integers'))
}
$taskEventsBeforeFiltering = @($records | Where-Object { [string] (Get-PropertyValue $_.Event 'scope') -eq 'task' })
$observedTaskRefs = @($taskEventsBeforeFiltering | ForEach-Object { [int] (Get-PropertyValue $_.Event 'taskRef') } | Sort-Object -Unique)
$missingDeclaredTaskRefs = @(
    if ($taskSetWasDeclared) { $declaredTaskRefs | Where-Object { $_ -notin $observedTaskRefs } }
)
$undeclaredTaskRefs = @(
    if ($taskSetWasDeclared) { $observedTaskRefs | Where-Object { $_ -notin $declaredTaskRefs } }
)
if ($missingDeclaredTaskRefs.Count -gt 0) {
    [void] $anomalies.Add((New-Anomaly -Code 'missing_task_evidence' -Message 'Declared task identities have no attributable task events; affected review coverage is partial' -Identity ($missingDeclaredTaskRefs -join ',')))
}
if ($undeclaredTaskRefs.Count -gt 0) {
    [void] $anomalies.Add((New-Anomaly -Code 'undeclared_task_evidence' -Message 'Task events outside the declared ordered task set were quarantined from task review counts and phase totals' -Identity ($undeclaredTaskRefs -join ',')))
    $records = @($records | Where-Object {
        [string] (Get-PropertyValue $_.Event 'scope') -ne 'task' -or
        [int] (Get-PropertyValue $_.Event 'taskRef') -in $declaredTaskRefs
    })
}
$taskCoverageState = if (-not $taskSetWasDeclared) { 'unavailable' } elseif ($missingDeclaredTaskRefs.Count -gt 0 -or $undeclaredTaskRefs.Count -gt 0) { 'partial' } else { 'measured' }

$effectiveReviewMode = $ReviewMode
$reviewModeConflict = $false
if ([string]::IsNullOrWhiteSpace($effectiveReviewMode)) {
    if ($eventModes.Count -eq 1) {
        $effectiveReviewMode = $eventModes[0]
    }
    else {
        $effectiveReviewMode = 'unavailable'
        $reviewModeConflict = $eventModes.Count -gt 1
        $modeCode = if ($reviewModeConflict) { 'conflicting_review_mode' } else { 'missing_review_mode' }
        $modeMessage = if ($reviewModeConflict) { 'Review mode was not supplied and event values conflict; no mode was inferred' } else { 'Review mode was not supplied and could not be established from one consistent event value; no mode was inferred' }
        [void] $anomalies.Add((New-Anomaly -Code $modeCode -Message $modeMessage))
    }
}
elseif ($eventModes.Count -gt 0 -and @($eventModes | Where-Object { $_ -ne $effectiveReviewMode }).Count -gt 0) {
    $reviewModeConflict = $true
    [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_mode' -Message 'The supplied review mode conflicts with one or more event values'))
}

if ($effectiveReviewMode -notin @('per_task', 'story_end_only')) {
    $effectiveReviewMode = $null
}

$storyStarts = @($records | Where-Object { $_.EventType -eq 'story_started' -and [string](Get-PropertyValue $_.Event 'scope') -eq 'story' })
$prReady = @($records | Where-Object { $_.EventType -eq 'pr_ready' -and [string](Get-PropertyValue $_.Event 'scope') -eq 'story' })
$timeToPrInterval = Get-IntervalResult -Starts $storyStarts -Ends $prReady -Identity 'story|time_to_pr' -Kind 'story_to_pr' -Anomalies $anomalies

$implementationStarts = @{}
$implementationEnds = @{}
$correctionStarts = @{}
$correctionEnds = @{}
$waitStarts = @{}
$waitEnds = @{}
$reviewStarts = @{}
$reviewEnds = @{}

foreach ($record in $records) {
    $event = $record.Event
    switch ($record.EventType) {
        'implementation_started' { Add-ToIndex -Index $implementationStarts -Key (Get-PhaseIdentity $event) -Value $record }
        'task_ready_for_review' { Add-ToIndex -Index $implementationEnds -Key (Get-PhaseIdentity $event) -Value $record }
        'correction_started' { Add-ToIndex -Index $correctionStarts -Key (Get-PhaseIdentity $event) -Value $record }
        'correction_ready' { Add-ToIndex -Index $correctionEnds -Key (Get-PhaseIdentity $event) -Value $record }
        'wait_started' {
            $waitKey = Get-WaitIdentity -Event $event
            Add-ToIndex -Index $waitStarts -Key $waitKey -Value $record
        }
        'wait_ended' {
            $waitKey = Get-WaitIdentity -Event $event
            Add-ToIndex -Index $waitEnds -Key $waitKey -Value $record
        }
        { $_ -in $script:ReviewStartEvents } { Add-ToIndex -Index $reviewStarts -Key (Get-ReviewIdentity $event) -Value $record }
        { $_ -in $script:ReviewCloseEvents } { Add-ToIndex -Index $reviewEnds -Key (Get-ReviewIdentity $event) -Value $record }
    }
}

# A second observation of the same review attempt is diagnostic-only. It is
# never a second review count, even when it arrived under another eventId.
# Immutable payload differences are conflicts, not stale duplicates.
$reviewStartByAttempt = @{}
$reviewAttemptBindingById = @{}
$reviewRequestBindingById = @{}
$reviewStartConflicts = @{}
$dedupedReviewStarts = [System.Collections.Generic.List[object]]::new()
foreach ($record in @($records | Where-Object { $_.EventType -in $script:ReviewStartEvents } | Sort-Object Line)) {
    $attemptKey = Get-ReviewAttemptIdentity -Event $record.Event
    $attemptBindingKey = Get-ReviewAttemptBindingIdentity -Event $record.Event
    $requestBindingKey = [string] (Get-PropertyValue $record.Event 'reviewRequestId')
    $requestBindingCanonical = Get-ReviewRequestBindingCanonical -Event $record.Event
    if ($reviewRequestBindingById.ContainsKey($requestBindingKey) -and
        $reviewRequestBindingById[$requestBindingKey].Canonical -cne $requestBindingCanonical) {
        $firstRequest = $reviewRequestBindingById[$requestBindingKey]
        $firstRequestAttemptKey = Get-ReviewAttemptIdentity -Event $firstRequest.Event
        $reviewStartConflicts[$firstRequestAttemptKey] = $true
        [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_request' -Message 'A review request identity was rebound to a different target or revision; the first ledger record remains authoritative' -Identity $requestBindingKey -EventIds @($firstRequest.Event.EventId, $record.EventId)))
        continue
    }
    if ($reviewAttemptBindingById.ContainsKey($attemptBindingKey)) {
        $first = $reviewAttemptBindingById[$attemptBindingKey]
        $firstAttemptKey = Get-ReviewAttemptIdentity -Event $first.Event
        if ($firstAttemptKey -cne $attemptKey) {
            $reviewStartConflicts[$firstAttemptKey] = $true
            [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_attempt' -Message 'A review attempt identity was rebound to another request; real retries must use a distinct reviewAttemptId' -Identity $attemptBindingKey -EventIds @($first.EventId, $record.EventId)))
        }
        elseif ((Get-ImmutableBoundaryCanonical -Event $first.Event) -ceq (Get-ImmutableBoundaryCanonical -Event $record.Event)) {
            [void] $anomalies.Add((New-Anomaly -Code 'duplicate_or_stale_review' -Message 'A repeated review attempt identity with the same immutable payload was ignored for counting' -Identity $attemptKey -EventIds @($first.EventId, $record.EventId)))
        }
        else {
            $reviewStartConflicts[$attemptKey] = $true
            [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_start' -Message 'A repeated review attempt identity carried a changed immutable payload; the first ledger record remains authoritative and coverage is partial' -Identity $attemptKey -EventIds @($first.EventId, $record.EventId)))
        }
        continue
    }
    if (-not $reviewRequestBindingById.ContainsKey($requestBindingKey)) {
        $reviewRequestBindingById[$requestBindingKey] = [pscustomobject]@{ Event = $record.Event; Canonical = $requestBindingCanonical }
    }
    $reviewAttemptBindingById[$attemptBindingKey] = $record
    if ($reviewStartByAttempt.ContainsKey($attemptKey)) {
        $first = $reviewStartByAttempt[$attemptKey]
        if ((Get-ImmutableBoundaryCanonical -Event $first.Event) -ceq (Get-ImmutableBoundaryCanonical -Event $record.Event)) {
            [void] $anomalies.Add((New-Anomaly -Code 'duplicate_or_stale_review' -Message 'A repeated review attempt identity with the same immutable payload was ignored for counting' -Identity $attemptKey -EventIds @($first.EventId, $record.EventId)))
        }
        else {
            $reviewStartConflicts[$attemptKey] = $true
            [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_start' -Message 'A repeated review attempt identity carried a changed immutable payload; the first ledger record remains authoritative and coverage is partial' -Identity $attemptKey -EventIds @($first.EventId, $record.EventId)))
        }
        continue
    }
    $reviewStartByAttempt[$attemptKey] = $record
    [void] $dedupedReviewStarts.Add($record)
}

# Keep one immutable closure per attempt. Distinct closure kinds or times are
# conflicting evidence, not a reason to choose whichever event was read first.
$reviewEndsByAttempt = @{}
foreach ($key in @($reviewEnds.Keys | Sort-Object)) {
    foreach ($record in @($reviewEnds[$key])) {
        $attemptKey = Get-ReviewAttemptIdentity -Event $record.Event
        if (-not $reviewEndsByAttempt.ContainsKey($attemptKey)) {
            $reviewEndsByAttempt[$attemptKey] = [System.Collections.ArrayList]::new()
        }
        [void] $reviewEndsByAttempt[$attemptKey].Add($record)
    }
}

$reviewIntervals = [System.Collections.Generic.List[object]]::new()
foreach ($record in @($dedupedReviewStarts | Sort-Object Time, Line)) {
    $attemptKey = Get-ReviewAttemptIdentity -Event $record.Event
    $closures = if ($reviewEndsByAttempt.ContainsKey($attemptKey)) { @($reviewEndsByAttempt[$attemptKey]) } else { @() }
    $matchingClosures = @($closures | Where-Object { (Get-ReviewIdentity $_.Event) -eq (Get-ReviewIdentity $record.Event) })
    $mismatchedClosures = @($closures | Where-Object { (Get-ReviewIdentity $_.Event) -ne (Get-ReviewIdentity $record.Event) })
    $closureConflict = $false
    if ($mismatchedClosures.Count -gt 0) {
        $closureConflict = $true
        $closureIds = @($record.EventId) + @($mismatchedClosures | ForEach-Object { $_.EventId })
        [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_identity' -Message 'A review attempt has incompatible closure evidence; matching evidence is not accepted alongside a mismatched closure' -Identity $attemptKey -EventIds $closureIds))
        $matchingClosures = @()
    }
    elseif ($closures.Count -gt 0 -and $matchingClosures.Count -eq 0) {
        $closureConflict = $true
        $closureIds = @($record.EventId) + @($closures | ForEach-Object { $_.EventId })
        [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_identity' -Message 'Review closure identity does not match the recorded start; it cannot close that attempt' -Identity $attemptKey -EventIds $closureIds))
    }
    if ($matchingClosures.Count -gt 1) {
        $closurePayloads = @($matchingClosures | ForEach-Object { Get-ImmutableBoundaryCanonical -Event $_.Event } | Sort-Object -Unique)
        $closureKinds = @($matchingClosures | ForEach-Object { $_.EventType } | Sort-Object -Unique)
        if ($closurePayloads.Count -gt 1 -or $closureKinds.Count -gt 1) {
            $closureConflict = $true
            $ids = @($record.EventId) + @($matchingClosures | ForEach-Object { $_.EventId })
            [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_closure' -Message 'A review attempt has changed or conflicting closure evidence; no closure was selected' -Identity $attemptKey -EventIds $ids))
            $matchingClosures = @()
        }
        else {
            $authoritativeClosure = @($matchingClosures | Sort-Object Line | Select-Object -First 1)
            [void] $anomalies.Add((New-Anomaly -Code 'duplicate_review_closure' -Message 'Repeated review closure evidence with the same immutable payload was reduced to the first ledger record' -Identity $attemptKey -EventIds @($matchingClosures | ForEach-Object { $_.EventId })))
            $matchingClosures = $authoritativeClosure
        }
    }

    $closure = if ($matchingClosures.Count -eq 1) { $matchingClosures[0] } else { $null }
    $state = 'measured'
    $elapsed = $null
    $missing = $null
    $closureKind = $null
    if ($reviewStartConflicts.ContainsKey($attemptKey)) {
        $state = 'partial'
        $missing = 'conflicting review start observations'
        $closureConflict = $true
    }
    elseif ($closureConflict -or $null -eq $closure) {
        $state = 'partial'
        $missing = 'missing or conflicting review closure'
        if (-not $closureConflict) {
            [void] $anomalies.Add((New-Anomaly -Code 'missing_boundary' -Message 'Review attempt has no authoritative closure' -Identity $attemptKey -EventIds @($record.EventId)))
        }
    }
    else {
        $closureKind = $closure.EventType
        $difference = $closure.Time - $record.Time
        if ($difference.TotalMilliseconds -lt 0) {
            $state = 'partial'
            $missing = 'review closure precedes review start'
            [void] $anomalies.Add((New-Anomaly -Code 'negative_interval' -Message 'Review closure occurred before review start' -Identity $attemptKey -EventIds @($record.EventId, $closure.EventId)))
        }
        else {
            $elapsed = [long] [Math]::Round($difference.TotalMilliseconds, [MidpointRounding]::AwayFromZero)
        }
    }

    $attemptResult = [pscustomobject][ordered]@{
        kind = 'review'
        identity = $attemptKey
        scope = Get-PropertyValue $record.Event 'scope'
        taskRef = if ($null -ne (Get-PropertyValue $record.Event 'taskRef')) { [int] (Get-PropertyValue $record.Event 'taskRef') } else { $null }
        reviewRequestId = Get-PropertyValue $record.Event 'reviewRequestId'
        reviewAttemptId = Get-PropertyValue $record.Event 'reviewAttemptId'
        reviewAttemptOrdinal = Get-PropertyValue $record.Event 'reviewAttemptOrdinal'
        reviewKind = Get-PropertyValue $record.Event 'reviewKind'
        phaseId = Get-PropertyValue $record.Event 'phaseId'
        revision = Get-PropertyValue $record.Event 'revision'
        startUtc = Get-PropertyValue $record.Event 'occurredAtUtc'
        endUtc = if ($null -ne $closure) { Get-PropertyValue $closure.Event 'occurredAtUtc' } else { $null }
        closureEventType = $closureKind
        elapsedMilliseconds = $elapsed
        state = $state
        missingData = $missing
        firstPass = $false
        startRole = Get-PropertyValue $record.Event 'role'
        endRole = if ($null -ne $closure) { Get-PropertyValue $closure.Event 'role' } else { $null }
    }
    [void] $reviewIntervals.Add($attemptResult)
}

# Any closure without a matching attempt is not allowed to close a different
# request, and is retained as an explicit anomaly.
foreach ($attemptKey in @($reviewEndsByAttempt.Keys | Sort-Object)) {
    if (-not $reviewStartByAttempt.ContainsKey($attemptKey)) {
        foreach ($record in @($reviewEndsByAttempt[$attemptKey])) {
            [void] $anomalies.Add((New-Anomaly -Code 'orphan_review_closure' -Message 'Review closure has no matching review start and was excluded from pairing' -Identity $attemptKey -EventIds @($record.EventId)))
        }
    }
}

$script:IntervalStarts = $implementationStarts
$script:IntervalEnds = $implementationEnds
$implementationIntervals = @(Get-IntervalCollection -Kind 'implementation' -Anomalies $anomalies)
$script:IntervalStarts = $correctionStarts
$script:IntervalEnds = $correctionEnds
$correctionIntervals = @(Get-IntervalCollection -Kind 'correction' -Anomalies $anomalies)
$script:IntervalStarts = $waitStarts
$script:IntervalEnds = $waitEnds
$waitIntervals = @(Get-IntervalCollection -Kind 'wait' -Anomalies $anomalies)
Add-OverlapAnomalies -Intervals @($implementationIntervals + $correctionIntervals + $reviewIntervals + $waitIntervals) -Anomalies $anomalies

function Get-IntervalMetric {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Intervals,
        [Parameter(Mandatory)] [string] $Unit,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Calculation,
        [Parameter(Mandatory)] [string] $NoDataMessage
    )

    if (@($Intervals).Count -eq 0) {
        return New-Metric -State 'unavailable' -Value $null -Unit $Unit -Source $Source -Calculation $Calculation -Coverage 'no attributable boundaries' -MissingData $NoDataMessage
    }

    $valid = @($Intervals | Where-Object { $_.state -eq 'measured' -and $null -ne $_.elapsedMilliseconds })
    $invalid = @($Intervals | Where-Object { $_.state -ne 'measured' })
    $sum = if ($valid.Count -gt 0) { [long] (($valid | Measure-Object -Property elapsedMilliseconds -Sum).Sum) } else { $null }
    if ($invalid.Count -gt 0) {
        return New-Metric -State 'partial' -Value $sum -Unit $Unit -Source $Source -Calculation $Calculation -Coverage "$($valid.Count) of $($Intervals.Count) intervals have valid paired boundaries" -MissingData "$($invalid.Count) interval(s) are missing, conflicting, reversed, or ambiguous"
    }
    return New-Metric -State 'measured' -Value $sum -Unit $Unit -Source $Source -Calculation $Calculation -Coverage "all $($Intervals.Count) intervals have valid paired boundaries" -MissingData $null
}

$implementationMetric = Get-IntervalMetric -Intervals @($implementationIntervals + $correctionIntervals) -Unit 'milliseconds' -Source 'paired implementation_started/task_ready_for_review and correction_started/correction_ready events' -Calculation 'sum valid implementation and correction UTC intervals without subtracting overlap' -NoDataMessage 'no implementation or correction boundary pair was recorded'
$reviewMetric = Get-IntervalMetric -Intervals @($reviewIntervals) -Unit 'milliseconds' -Source 'paired review attempt start and authoritative closure events' -Calculation 'sum valid elapsed time by distinct review attempt' -NoDataMessage 'no review attempt was recorded'
$waitMetric = Get-IntervalMetric -Intervals @($waitIntervals) -Unit 'milliseconds' -Source 'paired explicit wait_started/wait_ended events' -Calculation 'sum valid explicit wait UTC intervals' -NoDataMessage 'no explicit wait boundary was recorded'
$coordinationIntervals = @($waitIntervals | Where-Object { $_.startRole -eq 'coordinator' -or $_.endRole -eq 'coordinator' })
$coordinationMetric = Get-IntervalMetric -Intervals $coordinationIntervals -Unit 'milliseconds' -Source 'explicit waits with coordinator-attributable boundaries' -Calculation 'sum valid coordinator-attributable wait UTC intervals without inferring gaps' -NoDataMessage 'no attributable coordinator-owned interval was recorded'
$uncoveredStorySpan = Get-UncoveredStorySpan -StorySpan $timeToPrInterval -Intervals @($implementationIntervals + $correctionIntervals + $reviewIntervals + $waitIntervals)

if ($timeToPrInterval.state -eq 'measured') {
    $timeToPrMetric = New-Metric -State 'measured' -Value $timeToPrInterval.elapsedMilliseconds -Unit 'milliseconds' -Source 'story_started -> pr_ready' -Calculation 'direct UTC difference' -Coverage 'both story boundaries are uniquely present' -MissingData $null
}
elseif ($timeToPrInterval.state -eq 'partial') {
    $timeToPrMetric = New-Metric -State 'partial' -Value $null -Unit 'milliseconds' -Source 'story_started -> pr_ready' -Calculation 'direct UTC difference' -Coverage 'story boundary evidence is incomplete or ambiguous' -MissingData $timeToPrInterval.missingData
}
else {
    $timeToPrMetric = New-Metric -State 'unavailable' -Value $null -Unit 'milliseconds' -Source 'story_started -> pr_ready' -Calculation 'direct UTC difference' -Coverage 'no paired story boundaries' -MissingData 'story start or confirmed PR readiness is unavailable'
}

$initialAttempts = @($reviewIntervals | Where-Object { [string] $_.scope -eq 'task' -and [string] $_.reviewKind -eq 'initial_task' })
$correctionAttempts = @($reviewIntervals | Where-Object { [string] $_.scope -eq 'task' -and [string] $_.reviewKind -eq 'correction_rereview' })
$finalAttempts = @($reviewIntervals | Where-Object { [string] $_.scope -eq 'final_story' -and [string] $_.reviewKind -in @('final_story', 'final_story_rereview') })
$finalReReviews = @($finalAttempts | Where-Object { [string] $_.reviewKind -eq 'final_story_rereview' })
$initialEvidencePartial = @($initialAttempts | Where-Object { $_.state -ne 'measured' }).Count -gt 0
$correctionEvidencePartial = @($correctionAttempts | Where-Object { $_.state -ne 'measured' }).Count -gt 0
$finalEvidencePartial = @($finalAttempts | Where-Object { $_.state -ne 'measured' }).Count -gt 0
$initialTaskRefs = @($initialAttempts | Where-Object { $null -ne $_.taskRef } | ForEach-Object { [string] $_.taskRef } | Sort-Object -Unique)
$missingInitialReviewTaskRefs = @()
if ($effectiveReviewMode -eq 'per_task' -and $taskSetWasDeclared) {
    $initialTaskRefValues = @($initialTaskRefs | ForEach-Object { [int] $_ })
    $missingInitialReviewTaskRefs = @($declaredTaskRefs | Where-Object { $_ -notin $initialTaskRefValues })
    if ($missingInitialReviewTaskRefs.Count -gt 0) {
        [void] $anomalies.Add((New-Anomaly -Code 'missing_initial_review_evidence' -Message 'Declared per-task identities have no authoritative initial review attempt; observed review denominators remain based on actual initial attempts' -Identity ($missingInitialReviewTaskRefs -join ',')))
        $taskCoverageState = 'partial'
    }
}
$acceptedFirst = 0
$firstPassIncomplete = 0
$firstPassRejected = 0
foreach ($taskRef in $initialTaskRefs) {
    $taskAttempts = @($initialAttempts | Where-Object { [string] $_.taskRef -eq $taskRef } | Sort-Object startUtc)
    $first = $taskAttempts[0]
    if ($first.state -ne 'measured') {
        $firstPassIncomplete++
        continue
    }
    if ([string] $first.closureEventType -eq 'review_accepted') {
        $endTime = [DateTimeOffset]::Parse([string] $first.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $priorFindingOrCorrection = @($records | Where-Object {
            [string] (Get-PropertyValue $_.Event 'taskRef') -eq $taskRef -and
            $_.Time -le $endTime -and
            $_.EventType -in @('review_findings', 'correction_started')
        })
        if ($priorFindingOrCorrection.Count -gt 0) {
            $firstPassRejected++
            [void] $anomalies.Add((New-Anomaly -Code 'first_pass_invalidated' -Message 'An initial acceptance followed a finding or correction boundary for the same task; it is not first-pass acceptance' -Identity ([string] $taskRef) -EventIds (@($first.reviewAttemptId) + @($priorFindingOrCorrection | ForEach-Object { $_.EventId }))))
        }
        else {
            $acceptedFirst++
            $first.firstPass = $true
        }
    }
}

if ($effectiveReviewMode -eq 'story_end_only') {
    $firstPassMetric = New-Metric -State 'not_applicable' -Value $null -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage 'story_end_only intentionally has no per-task review denominator' -MissingData 'not applicable'
}
elseif ($initialTaskRefs.Count -eq 0) {
    $firstPassMetric = New-Metric -State 'not_applicable' -Value $null -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage 'zero denominator in this event set' -MissingData 'not applicable'
}
elseif ($firstPassIncomplete -gt 0 -or $taskCoverageState -ne 'measured' -or $reviewModeConflict) {
    $firstPassMetric = New-Metric -State 'partial' -Value $null -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage "$acceptedFirst numerator of $($initialTaskRefs.Count) denominator task identities; incomplete=$firstPassIncomplete, rejected=$firstPassRejected, taskCoverage=$taskCoverageState" -MissingData 'task-set, mode, or initial-attempt closure evidence is incomplete'
}
else {
    $firstPassMetric = New-Metric -State 'measured' -Value ([double] $acceptedFirst / [double] $initialTaskRefs.Count) -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage "$acceptedFirst numerator of $($initialTaskRefs.Count) denominator task identities have authoritative outcomes; rejected=$firstPassRejected" -MissingData $null
}
$firstPassMetric | Add-Member -NotePropertyName numerator -NotePropertyValue $acceptedFirst
$firstPassMetric | Add-Member -NotePropertyName denominator -NotePropertyValue $initialTaskRefs.Count

if ($effectiveReviewMode -eq 'story_end_only') {
    if ($initialAttempts.Count -gt 0 -or $correctionAttempts.Count -gt 0) {
        [void] $anomalies.Add((New-Anomaly -Code 'review_mode_violation' -Message 'story_end_only input contains per-task review attempts; those events are retained but the mode is not silently changed'))
    }
    $modeCountState = if ($reviewModeConflict) { 'partial' } else { 'measured' }
    $modeCountMissing = if ($reviewModeConflict) { 'reviewMode evidence conflicts' } else { $null }
    $initialMetric = New-CountMetric -Value 0 -Unit 'task identities' -Source 'review request identities' -Coverage 'story_end_only explicitly excludes per-task reviews' -MissingData $modeCountMissing -State $modeCountState
    $correctionMetric = New-CountMetric -Value 0 -Unit 'review attempts' -Source 'review request identities' -Coverage 'story_end_only explicitly excludes correction re-reviews' -MissingData $modeCountMissing -State $modeCountState
}
else {
    $initialState = if ($effectiveReviewMode -eq 'per_task') { if ($taskCoverageState -eq 'measured' -and -not $reviewModeConflict -and -not $initialEvidencePartial) { 'measured' } else { 'partial' } } else { 'unavailable' }
    $initialMissingData = if ($initialState -eq 'unavailable') { 'review mode is unavailable' } elseif ($taskCoverageState -ne 'measured') { 'declared task coverage is incomplete' } elseif ($reviewModeConflict) { 'review mode evidence conflicts' } elseif ($initialEvidencePartial) { 'one or more initial review attempts are open, reversed, or ambiguous' } else { $null }
    $initialMetric = New-CountMetric -Value $initialTaskRefs.Count -Unit 'task identities' -Source 'review request identities' -Coverage "one count per distinct declared task with an initial_task attempt; taskCoverage=$taskCoverageState" -MissingData $initialMissingData -State $initialState
    $correctionState = if ($effectiveReviewMode -eq 'per_task') { if ($taskCoverageState -eq 'measured' -and -not $reviewModeConflict -and -not $correctionEvidencePartial) { 'measured' } else { 'partial' } } else { 'unavailable' }
    $correctionMissingData = if ($correctionState -eq 'unavailable') { 'review mode is unavailable' } elseif ($taskCoverageState -ne 'measured') { 'declared task coverage is incomplete' } elseif ($reviewModeConflict) { 'review mode evidence conflicts' } elseif ($correctionEvidencePartial) { 'one or more correction re-reviews are open, reversed, or ambiguous' } else { $null }
    $correctionMetric = New-CountMetric -Value $correctionAttempts.Count -Unit 'review attempts' -Source 'review request and attempt identities' -Coverage "one count per distinct declared correction_rereview attempt; taskCoverage=$taskCoverageState" -MissingData $correctionMissingData -State $correctionState
}

$finalMetricState = if ($effectiveReviewMode -in @('per_task', 'story_end_only')) { if ($reviewModeConflict -or $finalEvidencePartial) { 'partial' } else { 'measured' } } else { 'unavailable' }
$finalMissingData = if ($finalMetricState -eq 'unavailable') { 'review mode is unavailable' } elseif ($reviewModeConflict) { 'review mode evidence conflicts' } elseif ($finalEvidencePartial) { 'one or more final-story review attempts are open, reversed, or ambiguous' } else { $null }
$finalMetric = New-CountMetric -Value $finalAttempts.Count -Unit 'review attempts' -Source 'final-story review attempt identities' -Coverage 'one count per distinct final-story attempt' -MissingData $finalMissingData -State $finalMetricState
$finalReMetric = New-CountMetric -Value $finalReReviews.Count -Unit 'review attempts' -Source 'final-story review attempt identities' -Coverage 'later final-story attempts only' -MissingData $finalMissingData -State $finalMetricState

$reviewModeMetric = if ($null -eq $effectiveReviewMode) {
    New-Metric -State 'unavailable' -Value $null -Unit 'enum' -Source 'setup authorization' -Calculation 'copy selected review mode' -Coverage 'review mode was not established' -MissingData 'review mode is required and is never inferred from event order'
} else {
    New-Metric -State 'measured' -Value $effectiveReviewMode -Unit 'enum' -Source 'setup authorization or explicit input' -Calculation 'copy selected review mode' -Coverage 'one consistent review mode' -MissingData $null
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'story_performance_report'
    runId = if ($runIds.Count -eq 1) { $runIds[0] } else { $null }
    projectId = if ($projectIds.Count -eq 1) { $projectIds[0] } else { $null }
    storyId = if ($storyIds.Count -eq 1) { $storyIds[0] } else { $null }
    storyRef = if ($storyRefs.Count -eq 1) { $storyRefs[0] } else { $null }
    reviewMode = $effectiveReviewMode
    pullRequest = if ($prReady.Count -eq 1) { Get-SafePullRequest -PullRequest (Get-PropertyValue $prReady[0].Event 'pullRequest') } else { $null }
    metrics = [ordered]@{
        timeToPr = $timeToPrMetric
        implementationElapsed = $implementationMetric
        reviewElapsed = $reviewMetric
        coordinationElapsed = $coordinationMetric
        waitingElapsed = $waitMetric
        initialTaskReviews = $initialMetric
        correctionReReviews = $correctionMetric
        finalStoryReviews = $finalMetric
        finalStoryReReviews = $finalReMetric
        firstPassAcceptanceRate = $firstPassMetric
    }
    phases = @($implementationIntervals + $correctionIntervals)
    reviewAttempts = @($reviewIntervals)
    waits = @($waitIntervals)
    anomalies = @($anomalies)
    coverage = [ordered]@{
        validEventCount = $records.Count
        duplicateAndConflictDiagnostics = @($anomalies | Where-Object { $_.code -in @('duplicate_event', 'event_identity_conflict', 'duplicate_or_stale_review', 'conflicting_review_start', 'conflicting_review_closure', 'conflicting_review_identity', 'conflicting_review_attempt', 'conflicting_review_request') }).Count
        uncoveredBoundaryDiagnostics = @($anomalies | Where-Object { $_.code -in @('missing_boundary', 'conflicting_boundary', 'negative_interval', 'orphan_review_closure', 'incomplete_tail') }).Count
        taskSet = [ordered]@{
            state = $taskCoverageState
            declaredTaskRefs = @($declaredTaskRefs)
            observedTaskRefs = @($observedTaskRefs)
            missingDeclaredTaskRefs = @($missingDeclaredTaskRefs)
            missingInitialReviewTaskRefs = @($missingInitialReviewTaskRefs)
            undeclaredTaskRefs = @($undeclaredTaskRefs)
        }
        uncoveredStorySpan = $uncoveredStorySpan
        note = 'Synthetic and source-backed evidence are aggregated only when their explicit identities and UTC boundaries are valid; unknown values remain null.'
    }
}

$json = $report | ConvertTo-Json -Depth 100
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputFullPath = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = [IO.Path]::GetDirectoryName($outputFullPath)
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    }
    [IO.File]::WriteAllText($outputFullPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
if (-not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
    $markdownFullPath = [IO.Path]::GetFullPath($MarkdownPath)
    $markdownDirectory = [IO.Path]::GetDirectoryName($markdownFullPath)
    if (-not [string]::IsNullOrWhiteSpace($markdownDirectory)) {
        [IO.Directory]::CreateDirectory($markdownDirectory) | Out-Null
    }
    [IO.File]::WriteAllText($markdownFullPath, (ConvertTo-Markdown -Report ([pscustomobject] $report)), [Text.UTF8Encoding]::new($false))
}

Write-Output $json
