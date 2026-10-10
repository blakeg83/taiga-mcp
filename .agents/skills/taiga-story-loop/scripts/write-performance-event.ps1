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
    [string] $EventPath,

    [int] $LockTimeoutMilliseconds = 5000,

    [int] $FaultAfterBytes = -1,

    [string] $LockReadyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TopLevelFields = @(
    'schemaVersion', 'kind', 'eventId', 'runId', 'projectId', 'storyId',
    'storyRef', 'taskRef', 'role', 'sessionId', 'workerId', 'transitionId',
    'scope', 'phaseId', 'correctionId', 'reviewRequestId', 'reviewAttemptId',
    'reviewKind', 'reviewAttemptOrdinal', 'supersedesReviewAttemptId',
    'eventType', 'occurredAtUtc', 'revision', 'reviewMode', 'provenance',
    'usage', 'waitId', 'waitKind', 'pullRequest'
)

$script:NullableTopLevelFields = @(
    'taskRef', 'sessionId', 'workerId', 'phaseId', 'correctionId',
    'reviewRequestId', 'reviewAttemptId', 'reviewKind', 'reviewAttemptOrdinal',
    'supersedesReviewAttemptId', 'revision', 'usage', 'waitId', 'waitKind',
    'pullRequest'
)
$script:RequiredTopLevelFields = @($script:TopLevelFields | Where-Object { $_ -notin @('waitId', 'waitKind', 'pullRequest') })

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
$script:PullRequestFields = @('provider', 'owner', 'repository', 'number', 'reviewedHead')

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
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') {
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

function Assert-PullRequest {
    param([AllowNull()] [object] $PullRequest)

    Assert-JsonObject -Value $PullRequest -Name 'pullRequest'
    Assert-AllowlistedProperties -Object $PullRequest -Allowed $script:PullRequestFields -Context 'pullRequest'
    Assert-RequiredProperties -Object $PullRequest -Names $script:PullRequestFields -Context 'pullRequest'
    Assert-NonBlankString -Value $PullRequest.provider -Name 'pullRequest.provider'
    Assert-NonBlankString -Value $PullRequest.owner -Name 'pullRequest.owner'
    Assert-NonBlankString -Value $PullRequest.repository -Name 'pullRequest.repository'
    Assert-PositiveInteger -Value $PullRequest.number -Name 'pullRequest.number'
    Assert-Revision -Revision $PullRequest.reviewedHead
    if ($null -eq $PullRequest.reviewedHead) {
        Fail-Recorder "'pullRequest.reviewedHead' must be a full Git SHA"
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
    param(
        [AllowNull()] [object] $Usage,
        [AllowNull()] [string] $EventRole
    )

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
    $counters = Get-Property -Object $Usage -Name 'counters'
    $counterSemanticsValue = if ($null -eq $counterSemantics) { $null } else { $counterSemantics.Value }
    $countersValue = if ($null -eq $counters) { $null } else { $counters.Value }
    $hasCounterSemantics = $null -ne $counterSemanticsValue
    $hasNumericCounters = $null -ne $countersValue

    if ($hasCounterSemantics) {
        Assert-JsonObject -Value $counterSemanticsValue -Name 'usage.counterSemantics'
        Assert-AllowlistedProperties -Object $counterSemanticsValue -Allowed $script:CounterSemanticsFields -Context 'usage.counterSemantics'
        foreach ($property in $counterSemanticsValue.PSObject.Properties) {
            if ($property.Name -ceq 'cachedInput') {
                Assert-EnumValue -Value $property.Value -Name 'usage.counterSemantics.cachedInput' -Allowed @('included_in_input', 'disjoint_from_input', 'unknown')
            }
            elseif ($property.Name -ceq 'reasoning') {
                Assert-EnumValue -Value $property.Value -Name 'usage.counterSemantics.reasoning' -Allowed @('included_in_output', 'disjoint_from_output', 'unknown')
            }
        }
    }

    if ($hasNumericCounters) {
        Assert-JsonObject -Value $countersValue -Name 'usage.counters'
        Assert-AllowlistedProperties -Object $countersValue -Allowed $script:CounterFields -Context 'usage.counters'
        if (@($countersValue.PSObject.Properties).Count -eq 0) {
            $hasNumericCounters = $false
        }
        foreach ($property in $countersValue.PSObject.Properties) {
            Assert-NonNegativeInteger -Value $property.Value -Name "usage.counters.$($property.Name)"
        }
    }

    if ($hasNumericCounters) {
        $streamText = if ($null -eq $streamId) { $null } else { $streamId.Value }
        $roleText = if ($null -eq $usageRole) { $null } else { $usageRole.Value }
        $sampleText = if ($null -eq $sampledAtUtc) { $null } else { $sampledAtUtc.Value }
        $baselineText = if ($null -eq $baselineAtUtc) { $null } else { $baselineAtUtc.Value }
        Assert-NonBlankString -Value $streamText -Name 'usage.streamId'
        Assert-EnumValue -Value $roleText -Name 'usage.role' -Allowed $script:Roles
        if (-not [string]::IsNullOrWhiteSpace($EventRole) -and [string] $roleText -cne $EventRole) {
            Fail-Recorder "usage.role must match event role"
        }
        Assert-UtcTimestamp -Value $sampleText -Name 'usage.sampledAtUtc'
        if ([string] $Usage.state -ceq 'measured') {
            Assert-UtcTimestamp -Value $baselineText -Name 'usage.baselineAtUtc'
        }
        elseif ($null -ne $baselineText) {
            Assert-UtcTimestamp -Value $baselineText -Name 'usage.baselineAtUtc'
        }
        if (-not $hasCounterSemantics) {
            Fail-Recorder 'numeric usage samples require counterSemantics'
        }
        foreach ($name in @('cachedInput', 'reasoning')) {
            $property = Get-Property -Object $counterSemanticsValue -Name $name
            if ($null -eq $property -or $null -eq $property.Value) {
                Fail-Recorder "numeric usage samples require usage.counterSemantics.$name"
            }
        }
    }

    if ([string] $Usage.state -ceq 'measured') {
        if (-not $hasNumericCounters) {
            Fail-Recorder "measured usage requires nonempty counters"
        }
        $cachedSemantics = (Get-Property -Object $counterSemanticsValue -Name 'cachedInput').Value
        $reasoningSemantics = (Get-Property -Object $counterSemanticsValue -Name 'reasoning').Value
        if ([string] $cachedSemantics -ceq 'unknown' -or [string] $reasoningSemantics -ceq 'unknown') {
            Fail-Recorder "measured usage requires known counter semantics"
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
    Assert-RequiredProperties -Object $Event -Names $script:RequiredTopLevelFields -Context 'event'

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
    Assert-Usage -Usage $Event.usage -EventRole ([string] $Event.role)

    $eventType = [string] $Event.eventType
    $scope = [string] $Event.scope
    $role = [string] $Event.role
    $reviewEvents = @('review_started', 'review_findings', 'review_accepted', 'final_review_started', 'final_review_accepted')
    $correctionEvents = @('correction_started', 'correction_ready')
    $waitEvents = @('wait_started', 'wait_ended')

    if ($scope -ceq 'task' -and $null -eq $Event.taskRef) {
        Fail-Recorder "task-scoped events require a positive taskRef"
    }
    if ($scope -in @('story', 'final_story') -and $null -ne $Event.taskRef) {
        Fail-Recorder "story-scoped events require taskRef to be null"
    }

    $waitIdProperty = Get-Property -Object $Event -Name 'waitId'
    $waitKindProperty = Get-Property -Object $Event -Name 'waitKind'
    $pullRequestProperty = Get-Property -Object $Event -Name 'pullRequest'
    $waitId = if ($null -eq $waitIdProperty) { $null } else { $waitIdProperty.Value }
    $waitKind = if ($null -eq $waitKindProperty) { $null } else { $waitKindProperty.Value }
    $pullRequest = if ($null -eq $pullRequestProperty) { $null } else { $pullRequestProperty.Value }

    if ($eventType -in $waitEvents) {
        Assert-NonBlankString -Value $waitId -Name 'waitId'
        Assert-NonBlankString -Value $waitKind -Name 'waitKind'
        if ($null -ne $Event.phaseId) {
            Fail-Recorder "wait boundary events require phaseId to be null"
        }
        if ($null -ne $Event.revision) {
            Fail-Recorder "wait boundary events require revision to be null"
        }
    }
    elseif ($null -ne $waitId -or $null -ne $waitKind) {
        Fail-Recorder "wait identity fields are allowed only on wait boundary events"
    }

    if ($eventType -ceq 'story_started') {
        if ($scope -cne 'story' -or $role -cne 'coordinator') {
            Fail-Recorder "story_started requires story scope and coordinator role"
        }
        if ($null -ne $Event.phaseId -or $null -ne $Event.revision) {
            Fail-Recorder "story_started requires null phaseId and revision"
        }
    }
    if ($eventType -ceq 'pr_ready') {
        if ($scope -cne 'story' -or $role -cne 'coordinator') {
            Fail-Recorder "pr_ready requires story scope and coordinator role"
        }
        if ($null -ne $Event.phaseId -or $null -eq $Event.revision) {
            Fail-Recorder "pr_ready requires null phaseId and a full revision"
        }
        Assert-PullRequest -PullRequest $pullRequest
        if ([string] $pullRequest.reviewedHead -cne [string] $Event.revision) {
            Fail-Recorder "pullRequest.reviewedHead must match event revision"
        }
    }
    elseif ($null -ne $pullRequest) {
        Fail-Recorder "pullRequest is allowed only on pr_ready"
    }

    if ($eventType -ceq 'implementation_started') {
        if ($scope -cne 'task' -or $role -cne 'implementer' -or $null -eq $Event.phaseId) {
            Fail-Recorder "implementation_started requires task scope, implementer role and phaseId"
        }
    }
    elseif ($eventType -ceq 'task_ready_for_review') {
        if ($scope -cne 'task' -or $role -cne 'implementer' -or $null -eq $Event.phaseId -or $null -eq $Event.revision) {
            Fail-Recorder "task_ready_for_review requires task scope, implementer role, phaseId and full revision"
        }
    }

    if ($eventType -in $reviewEvents) {
        if ($scope -notin @('task', 'final_story') -or $role -cne 'reviewer' -or $null -eq $Event.phaseId -or $null -eq $Event.revision) {
            Fail-Recorder "review events require review scope, reviewer role, phaseId and full revision"
        }
        foreach ($name in @('reviewRequestId', 'reviewAttemptId', 'reviewKind', 'reviewAttemptOrdinal')) {
            $property = Get-Property -Object $Event -Name $name
            if ($null -eq $property -or $null -eq $property.Value) {
                Fail-Recorder "review events require '$name'"
            }
        }
        if ($scope -ceq 'task' -and [string] $Event.reviewKind -notin @('initial_task', 'correction_rereview')) {
            Fail-Recorder "task review events require an initial_task or correction_rereview kind"
        }
        if ($scope -ceq 'final_story' -and [string] $Event.reviewKind -notin @('final_story', 'final_story_rereview')) {
            Fail-Recorder "final-story review events require a final-story review kind"
        }
    }

    if ($eventType -in @('final_review_started', 'final_review_accepted') -and $scope -cne 'final_story') {
        Fail-Recorder "final review events require final_story scope"
    }

    if ($eventType -in $correctionEvents) {
        if ($scope -notin @('task', 'final_story') -or $role -cne 'implementer' -or $null -eq $Event.phaseId -or $null -eq $Event.correctionId -or $null -eq $Event.supersedesReviewAttemptId) {
            Fail-Recorder "correction events require correction scope, implementer role, phaseId, correctionId and supersedesReviewAttemptId"
        }
        if ($eventType -ceq 'correction_started' -and $null -ne $Event.revision) {
            Fail-Recorder "correction_started requires a null revision"
        }
        if ($eventType -ceq 'correction_ready' -and $null -eq $Event.revision) {
            Fail-Recorder "correction_ready requires a full revision"
        }
    }

    if ($eventType -notin $reviewEvents -and $eventType -notin $correctionEvents) {
        foreach ($name in @('reviewRequestId', 'reviewAttemptId', 'reviewKind', 'reviewAttemptOrdinal')) {
            $property = Get-Property -Object $Event -Name $name
            if ($null -ne $property -and $null -ne $property.Value) {
                Fail-Recorder "'$name' is allowed only on review events"
            }
        }
    }
    if ($eventType -notin $correctionEvents -and $null -ne $Event.correctionId) {
        Fail-Recorder "correctionId is allowed only on correction events"
    }
    if ($scope -ceq 'final_story' -and $eventType -in $correctionEvents -and $null -ne $Event.taskRef) {
        Fail-Recorder "final-story correction events require taskRef to be null"
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

function Assert-EventStoryBinding {
    param(
        [Parameter(Mandatory)] [object] $Event,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef
    )

    if ([int] $Event.projectId -ne $ExpectedProjectId -or
        [int] $Event.storyId -ne $ExpectedStoryId -or
        [int] $Event.storyRef -ne $ExpectedStoryRef) {
        Fail-Recorder 'event story binding does not match the selected external run'
    }
}

function Convert-ToCanonicalValue {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object { [string] $_ })) {
            $ordered[[string] $key] = Convert-ToCanonicalValue -Value $Value[$key]
        }
        return $ordered
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $ordered[$property.Name] = Convert-ToCanonicalValue -Value $property.Value
        }
        return $ordered
    }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { Convert-ToCanonicalValue -Value $_ })
    }
    return $Value
}

function Convert-ToCanonicalJson {
    param([Parameter(Mandatory)] [object] $Value)

    return (Convert-ToCanonicalValue -Value $Value | ConvertTo-Json -Compress -Depth 50)
}

function Get-Sha256HexBytes {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes)

    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hash.Dispose()
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)] [string] $Text)

    return Get-Sha256HexBytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-UtcNowText {
    return [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Write-LockReadyMarker {
    param([Parameter(Mandatory)] [string] $ReadyPath)

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes('ready')
    $stream = $null
    try {
        $stream = [IO.FileStream]::new(
            $ReadyPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read,
            $bytes.Length,
            [IO.FileOptions]::WriteThrough)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Acquire-LedgerLock {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [int] $TimeoutMilliseconds,
        [AllowNull()] [string] $ReadyPath
    )

    $lockPath = "$LedgerPath.lock"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $readySignaled = $false
    while ($clock.ElapsedMilliseconds -le $TimeoutMilliseconds) {
        if (-not $readySignaled -and -not [string]::IsNullOrWhiteSpace($ReadyPath)) {
            Write-LockReadyMarker -ReadyPath $ReadyPath
            $readySignaled = $true
        }
        try {
            return [IO.FileStream]::new(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None,
                1,
                [IO.FileOptions]::WriteThrough)
        }
        catch [IO.IOException] {
            if ($TimeoutMilliseconds -eq 0 -or $clock.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
                throw [TimeoutException]::new('ledger lock wait exceeded the configured bound')
            }
            [Threading.Thread]::Yield() | Out-Null
        }
    }
    throw [TimeoutException]::new('ledger lock wait exceeded the configured bound')
}

function Copy-ByteRange {
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

function Read-FileByteRange {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [long] $StartOffset
    )

    $length = if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
        [IO.FileInfo]::new($LedgerPath).Length
    }
    else {
        0L
    }
    if ($StartOffset -lt 0 -or $StartOffset -gt $length) {
        throw [IO.InvalidDataException]::new('ledger checkpoint offset is outside the ledger')
    }
    $count = $length - $StartOffset
    if ($count -gt [int]::MaxValue) {
        throw [IO.InvalidDataException]::new('ledger scan range exceeds the bounded recorder buffer')
    }
    if ($count -eq 0) {
        return ,([byte[]]::new(0))
    }

    $bytes = [byte[]]::new([int] $count)
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($LedgerPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        [void] $stream.Seek($StartOffset, [IO.SeekOrigin]::Begin)
        $read = 0
        while ($read -lt $bytes.Length) {
            $chunk = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($chunk -le 0) {
                throw [IO.IOException]::new('ledger changed while it was being scanned')
            }
            $read += $chunk
        }
        return ,$bytes
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Read-LedgerChunk {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [long] $StartOffset,
        [Parameter(Mandatory)] [int] $StartLineNumber,
        [Parameter(Mandatory)] [string] $ExpectedRunId,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef
    )

    $physicalLength = if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
        [IO.FileInfo]::new($LedgerPath).Length
    }
    else {
        0L
    }
    $bytes = Read-FileByteRange -LedgerPath $LedgerPath -StartOffset $StartOffset
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $records = [System.Collections.Generic.List[object]]::new()
    $invalid = [System.Collections.Generic.List[object]]::new()
    $lineStart = 0
    $lineNumber = $StartLineNumber
    for ($offset = 0; $offset -lt $bytes.Length; $offset++) {
        if ($bytes[$offset] -ne [byte] 0x0A) {
            continue
        }

        $lineNumber++
        $lineLength = $offset - $lineStart
        $contentLength = $lineLength
        if ($contentLength -gt 0 -and $bytes[$offset - 1] -eq [byte] 0x0D) {
            $contentLength--
        }
        $lineBytes = Copy-ByteRange -Bytes $bytes -Offset $lineStart -Count $contentLength
        $globalStart = $StartOffset + $lineStart
        $globalEnd = $StartOffset + $offset + 1
        $lineStart = $offset + 1
        $diagnosticType = 'schema_invalid_record'
        try {
            $line = $encoding.GetString($lineBytes)
            if ([string]::IsNullOrWhiteSpace($line)) {
                throw [FormatException]::new('ledger record is blank')
            }
            $candidate = $line | ConvertFrom-Json -DateKind String
            $eventIdProperty = if ($null -eq $candidate) { $null } else { Get-Property -Object $candidate -Name 'eventId' }
            if ($null -eq $candidate -or $candidate -is [System.Array] -or
                $null -eq $eventIdProperty -or [string]::IsNullOrWhiteSpace([string] $eventIdProperty.Value)) {
                throw [FormatException]::new('ledger record is not an event object')
            }
            $recordRunId = Get-Property -Object $candidate -Name 'runId'
            $recordProjectId = Get-Property -Object $candidate -Name 'projectId'
            $recordStoryId = Get-Property -Object $candidate -Name 'storyId'
            $recordStoryRef = Get-Property -Object $candidate -Name 'storyRef'
            if (($null -ne $recordRunId -and [string] $recordRunId.Value -cne $ExpectedRunId) -or
                ($null -ne $recordProjectId -and [string] $recordProjectId.Value -cne [string] $ExpectedProjectId) -or
                ($null -ne $recordStoryId -and [string] $recordStoryId.Value -cne [string] $ExpectedStoryId) -or
                ($null -ne $recordStoryRef -and [string] $recordStoryRef.Value -cne [string] $ExpectedStoryRef)) {
                $diagnosticType = 'foreign_run'
            }
            Assert-Event -Event $candidate -ExpectedRunId $ExpectedRunId
            Assert-EventStoryBinding -Event $candidate -ExpectedProjectId $ExpectedProjectId -ExpectedStoryId $ExpectedStoryId -ExpectedStoryRef $ExpectedStoryRef
            [void] $records.Add([pscustomobject]@{
                    EventId = [string] $eventIdProperty.Value
                    CanonicalJson = Convert-ToCanonicalJson -Value $candidate
                    LineNumber = $lineNumber
                    StartOffset = [long] $globalStart
                    EndOffset = [long] $globalEnd
                })
        }
        catch {
            [void] $invalid.Add([pscustomobject]@{
                    diagnosticType = $diagnosticType
                    lineNumber = $lineNumber
                    byteLength = $contentLength
                    digest = Get-Sha256HexBytes -Bytes $lineBytes
                })
        }
    }

    $tailLength = $bytes.Length - $lineStart
    $incompleteTail = $null
    if ($tailLength -gt 0) {
        $tailBytes = Copy-ByteRange -Bytes $bytes -Offset $lineStart -Count $tailLength
        $incompleteTail = [pscustomobject]@{
            lineNumber = $lineNumber + 1
            byteLength = $tailLength
            digest = Get-Sha256HexBytes -Bytes $tailBytes
        }
    }

    return [pscustomobject]@{
        Records = @($records)
        InvalidRecords = @($invalid)
        IncompleteTail = $incompleteTail
        NeedsSeparator = $tailLength -gt 0
        StartOffset = $StartOffset
        LastCompleteOffset = [long] ($StartOffset + $lineStart)
        NextLineNumber = $lineNumber
        PhysicalLength = $physicalLength
        ScannedBytes = [long] $bytes.Length
    }
}

function Get-LedgerIndexDirectory {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.index"
}

function Get-LedgerCheckpointPath {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.checkpoint.json"
}

function Get-EventIndexPath {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    return (Join-Path $IndexDirectory ((Get-Sha256Hex -Text $EventId) + '.json'))
}

function Write-AtomicText {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Text
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Move($temporary, $Path, $true)
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Read-IndexEntry {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $path = Get-EventIndexPath -IndexDirectory $IndexDirectory -EventId $EventId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $entry = [IO.File]::ReadAllText($path) | ConvertFrom-Json -DateKind String
        if ($null -eq $entry -or [int] $entry.schemaVersion -ne 1 -or
            [string] $entry.kind -cne 'story_performance_event_index' -or
            [string] $entry.eventId -cne $EventId -or
            [string] $entry.state -notin @('pending', 'committed', 'conflict') -or
            [string]::IsNullOrWhiteSpace([string] $entry.canonicalJson)) {
            throw [IO.InvalidDataException]::new('event index entry is invalid')
        }
        return $entry
    }
    catch {
        throw [IO.InvalidDataException]::new('event index entry is invalid')
    }
}

function Write-IndexEntry {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [ValidateSet('pending', 'committed', 'conflict')] [string] $State,
        [Parameter(Mandatory)] [string] $CanonicalJson,
        [AllowNull()] [int] $LineNumber,
        [AllowNull()] [long] $StartOffset,
        [AllowNull()] [long] $EndOffset
    )

    $entry = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event_index'
        eventId = $EventId
        state = $State
        canonicalJson = $CanonicalJson
        lineNumber = $LineNumber
        startOffset = $StartOffset
        endOffset = $EndOffset
    }
    Write-AtomicText -Path (Get-EventIndexPath -IndexDirectory $IndexDirectory -EventId $EventId) -Text ($entry | ConvertTo-Json -Compress -Depth 20)
}

function Clear-LedgerIndex {
    param([Parameter(Mandatory)] [string] $IndexDirectory)

    [IO.Directory]::CreateDirectory($IndexDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($IndexDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Update-IndexFromRecords {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    [IO.Directory]::CreateDirectory($IndexDirectory) | Out-Null
    foreach ($record in @($Records | Sort-Object LineNumber, StartOffset)) {
        $entry = Read-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId)
        if ($null -eq $entry) {
            Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset)
            continue
        }
        if ([string] $entry.canonicalJson -cne [string] $record.CanonicalJson) {
            Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId) -State conflict -CanonicalJson ([string] $entry.canonicalJson) -LineNumber ([int] $entry.lineNumber) -StartOffset ([long] $entry.startOffset) -EndOffset ([long] $entry.endOffset)
        }
        elseif ([string] $entry.state -eq 'pending') {
            Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset)
        }
    }
}

function Write-LedgerCheckpoint {
    param(
        [Parameter(Mandatory)] [string] $CheckpointPath,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [int] $ProjectId,
        [Parameter(Mandatory)] [int] $StoryId,
        [Parameter(Mandatory)] [int] $StoryRef,
        [Parameter(Mandatory)] [long] $LastCompleteOffset,
        [Parameter(Mandatory)] [int] $NextLineNumber,
        [Parameter(Mandatory)] [long] $RecordCount,
        [Parameter(Mandatory)] [long] $PhysicalLength
    )

    $checkpoint = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_ledger_checkpoint'
        runId = $RunId
        projectId = $ProjectId
        storyId = $StoryId
        storyRef = $StoryRef
        lastCompleteOffset = $LastCompleteOffset
        nextLineNumber = $NextLineNumber
        recordCount = $RecordCount
        physicalLength = $PhysicalLength
        updatedAtUtc = Get-UtcNowText
    }
    Write-AtomicText -Path $CheckpointPath -Text ($checkpoint | ConvertTo-Json -Compress -Depth 20)
}

function Read-LedgerCheckpoint {
    param(
        [Parameter(Mandatory)] [string] $CheckpointPath,
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $ExpectedRunId,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef
    )

    if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) {
        return $null
    }
    try {
        $checkpoint = [IO.File]::ReadAllText($CheckpointPath) | ConvertFrom-Json -DateKind String
        $physicalLength = if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) { [IO.FileInfo]::new($LedgerPath).Length } else { 0L }
        $lastCompleteOffset = [long] $checkpoint.lastCompleteOffset
        $checkpointPhysicalLength = [long] $checkpoint.physicalLength
        if ([int] $checkpoint.schemaVersion -ne 1 -or
            [string] $checkpoint.kind -cne 'story_performance_ledger_checkpoint' -or
            [string] $checkpoint.runId -cne $ExpectedRunId -or
            [int] $checkpoint.projectId -ne $ExpectedProjectId -or
            [int] $checkpoint.storyId -ne $ExpectedStoryId -or
            [int] $checkpoint.storyRef -ne $ExpectedStoryRef -or
            $lastCompleteOffset -lt 0 -or $checkpointPhysicalLength -lt $lastCompleteOffset -or
            $physicalLength -lt $lastCompleteOffset -or $physicalLength -lt $checkpointPhysicalLength) {
            return $null
        }
        return [pscustomobject]@{
            LastCompleteOffset = $lastCompleteOffset
            NextLineNumber = [int] $checkpoint.nextLineNumber
            RecordCount = [long] $checkpoint.recordCount
            PhysicalLength = $checkpointPhysicalLength
        }
    }
    catch {
        return $null
    }
}

function Write-IndexFromFullLedger {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [object] $LedgerState
    )

    Clear-LedgerIndex -IndexDirectory $IndexDirectory
    $groups = @($LedgerState.Records | Group-Object EventId)
    foreach ($group in $groups) {
        $ordered = @($group.Group | Sort-Object LineNumber, StartOffset)
        $first = $ordered[0]
        $canonicalValues = @($ordered | ForEach-Object { [string] $_.CanonicalJson } | Sort-Object -Unique)
        $state = if ($canonicalValues.Count -gt 1) { 'conflict' } else { 'committed' }
        Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $first.EventId) -State $state -CanonicalJson ([string] $first.CanonicalJson) -LineNumber ([int] $first.LineNumber) -StartOffset ([long] $first.StartOffset) -EndOffset ([long] $first.EndOffset)
    }
}

function Write-Diagnostic {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [string] $DiagnosticType,
        [AllowNull()] [string] $EventId,
        [AllowNull()] [string] $ExistingDigest,
        [AllowNull()] [string] $IncomingDigest,
        [AllowNull()] [int] $LineNumber,
        [AllowNull()] [int] $ByteLength
    )

    $diagnosticPath = "$LedgerPath.diagnostics.jsonl"
    $diagnostic = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_diagnostic'
        diagnosticType = $DiagnosticType
        runId = $RunId
        eventId = $EventId
        existingDigest = $ExistingDigest
        incomingDigest = $IncomingDigest
        lineNumber = $LineNumber
        byteLength = $ByteLength
        recordedAtUtc = Get-UtcNowText
    }
    Write-LedgerLine -LedgerPath $diagnosticPath -Line ($diagnostic | ConvertTo-Json -Compress -Depth 10)
    return $diagnosticPath
}

function Write-LedgerLine {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $Line,
        [switch] $PrependNewline,
        [int] $FaultAfterBytes = -1
    )

    $encoding = [Text.UTF8Encoding]::new($false)
    $prefix = if ($PrependNewline) { [Environment]::NewLine } else { '' }
    $bytes = $encoding.GetBytes($prefix + $Line + [Environment]::NewLine)
    $stream = $null
    try {
        $stream = [IO.FileStream]::new(
            $LedgerPath,
            [IO.FileMode]::Append,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read,
            4096,
            [IO.FileOptions]::WriteThrough)
        $writeLength = if ($FaultAfterBytes -ge 0) { [Math]::Min($FaultAfterBytes, $bytes.Length) } else { $bytes.Length }
        if ($writeLength -gt 0) {
            $stream.Write($bytes, 0, $writeLength)
        }
        $stream.Flush($true)
        if ($writeLength -lt $bytes.Length) {
            throw [IO.IOException]::new('deterministic write fault injected')
        }
    }
    catch {
        if ($FaultAfterBytes -ge 0) {
            throw [InvalidOperationException]::new('deterministic write fault injected')
        }
        throw [IO.IOException]::new('event ledger could not be written')
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
if ($LockTimeoutMilliseconds -lt 0) {
    Fail-Recorder "'LockTimeoutMilliseconds' must be nonnegative"
}
if ($FaultAfterBytes -lt -1) {
    Fail-Recorder "'FaultAfterBytes' must be -1 or nonnegative"
}
$eventText = Read-EventJson
$event = Parse-Event -Json $eventText
Assert-Event -Event $event -ExpectedRunId $RunId

$runDirectory = Join-Path $expectedRoot $RunId
$ledgerPath = Join-Path $runDirectory 'events.jsonl'
$indexDirectory = Get-LedgerIndexDirectory -LedgerPath $ledgerPath
$checkpointPath = Get-LedgerCheckpointPath -LedgerPath $ledgerPath
$normalizedLockReadyPath = $null
if (-not [string]::IsNullOrWhiteSpace($LockReadyPath)) {
    $normalizedLockReadyPath = Get-FullPath -Path $LockReadyPath -Name 'LockReadyPath'
    Assert-ExternalRunRoot -Root $normalizedLockReadyPath
    if (-not (Test-PathWithin -Child $normalizedLockReadyPath -Parent $runDirectory)) {
        Fail-Recorder "'LockReadyPath' must be within the external run directory"
    }
    $reservedPaths = @(
        $runDirectory,
        $ledgerPath,
        "$ledgerPath.lock",
        "$ledgerPath.diagnostics.jsonl",
        $indexDirectory,
        $checkpointPath
    ) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\', '/') }
    if (@($reservedPaths | Where-Object { $_.Equals($normalizedLockReadyPath, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        Fail-Recorder "'LockReadyPath' aliases a reserved external run path"
    }
    if (Test-Path -LiteralPath $normalizedLockReadyPath) {
        Fail-Recorder "'LockReadyPath' must not already exist"
    }
}
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
$incomingCanonical = Convert-ToCanonicalJson -Value $event
$incomingDigest = Get-Sha256Hex -Text $incomingCanonical
$lock = $null
$operationResult = $null
$operationExitCode = 0
$diagnosticPaths = @()
$conflictDiagnosticPath = $null

try {
    $lock = Acquire-LedgerLock -LedgerPath $ledgerPath -TimeoutMilliseconds $LockTimeoutMilliseconds -ReadyPath $normalizedLockReadyPath
    $checkpoint = Read-LedgerCheckpoint `
        -CheckpointPath $checkpointPath `
        -LedgerPath $ledgerPath `
        -ExpectedRunId $RunId `
        -ExpectedProjectId ([int] $event.projectId) `
        -ExpectedStoryId ([int] $event.storyId) `
        -ExpectedStoryRef ([int] $event.storyRef)
    $fullRebuild = $null -eq $checkpoint -or
        ([long] $checkpoint.RecordCount -gt 0 -and -not (Test-Path -LiteralPath $indexDirectory -PathType Container))
    $scanStartOffset = if ($fullRebuild) { 0L } else { [long] $checkpoint.LastCompleteOffset }
    $scanStartLineNumber = if ($fullRebuild) { 0 } else { [int] $checkpoint.NextLineNumber }
    $ledgerState = Read-LedgerChunk `
        -LedgerPath $ledgerPath `
        -StartOffset $scanStartOffset `
        -StartLineNumber $scanStartLineNumber `
        -ExpectedRunId $RunId `
        -ExpectedProjectId ([int] $event.projectId) `
        -ExpectedStoryId ([int] $event.storyId) `
        -ExpectedStoryRef ([int] $event.storyRef)
    if ($fullRebuild) {
        Write-IndexFromFullLedger -IndexDirectory $indexDirectory -LedgerState $ledgerState
        $recordCount = [long] $ledgerState.Records.Count
    }
    else {
        Update-IndexFromRecords -IndexDirectory $indexDirectory -Records $ledgerState.Records
        $recordCount = [long] $checkpoint.RecordCount + [long] $ledgerState.Records.Count
    }

    foreach ($invalidRecord in @($ledgerState.InvalidRecords)) {
        $diagnosticPaths += Write-Diagnostic `
            -LedgerPath $ledgerPath `
            -RunId $RunId `
            -DiagnosticType $invalidRecord.diagnosticType `
            -EventId $null `
            -ExistingDigest $invalidRecord.digest `
            -IncomingDigest $null `
            -LineNumber $invalidRecord.lineNumber `
            -ByteLength $invalidRecord.byteLength
    }
    if ($null -ne $ledgerState.IncompleteTail) {
        $diagnosticPaths += Write-Diagnostic `
            -LedgerPath $ledgerPath `
            -RunId $RunId `
            -DiagnosticType 'incomplete_tail' `
            -EventId $null `
            -ExistingDigest $ledgerState.IncompleteTail.digest `
            -IncomingDigest $null `
            -LineNumber $ledgerState.IncompleteTail.lineNumber `
            -ByteLength $ledgerState.IncompleteTail.byteLength
    }

    $checkpointPhysicalLength = [long] $ledgerState.PhysicalLength
    $checkpointLastCompleteOffset = [long] $ledgerState.LastCompleteOffset
    $checkpointLineNumber = [int] $ledgerState.NextLineNumber

    $foreignRecords = @($ledgerState.InvalidRecords | Where-Object { $_.diagnosticType -ceq 'foreign_run' })
    if ($foreignRecords.Count -gt 0) {
        $operationResult = [ordered]@{
            status = 'error'
            errorCategory = 'run_binding_conflict'
            eventId = [string] $event.eventId
            runId = $RunId
            ledgerPath = $ledgerPath
            diagnosticPath = $diagnosticPaths[0]
        }
        $operationExitCode = 3
    }
    else {
        $indexEntry = Read-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId)
        if ($null -eq $indexEntry) {
            Write-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId) -State pending -CanonicalJson $incomingCanonical -LineNumber $null -StartOffset $null -EndOffset $null
        }

        if ($null -ne $indexEntry -and [string] $indexEntry.state -eq 'conflict') {
            $conflictDiagnosticPath = Write-Diagnostic `
                -LedgerPath $ledgerPath `
                -RunId $RunId `
                -DiagnosticType 'conflicting_duplicate' `
                -EventId ([string] $event.eventId) `
                -ExistingDigest (Get-Sha256Hex -Text ([string] $indexEntry.canonicalJson)) `
                -IncomingDigest $incomingDigest `
                -LineNumber ([int] $indexEntry.lineNumber) `
                -ByteLength $null
            $operationResult = [ordered]@{
                status = 'error'
                errorCategory = 'conflicting_duplicate'
                eventId = [string] $event.eventId
                runId = $RunId
                ledgerPath = $ledgerPath
                diagnosticPath = $conflictDiagnosticPath
            }
            $operationExitCode = 3
        }
        elseif ($null -ne $indexEntry -and [string] $indexEntry.canonicalJson -cne $incomingCanonical) {
            $conflictDiagnosticPath = Write-Diagnostic `
                -LedgerPath $ledgerPath `
                -RunId $RunId `
                -DiagnosticType 'conflicting_duplicate' `
                -EventId ([string] $event.eventId) `
                -ExistingDigest (Get-Sha256Hex -Text ([string] $indexEntry.canonicalJson)) `
                -IncomingDigest $incomingDigest `
                -LineNumber ([int] $indexEntry.lineNumber) `
                -ByteLength $null
            $operationResult = [ordered]@{
                status = 'error'
                errorCategory = 'conflicting_duplicate'
                eventId = [string] $event.eventId
                runId = $RunId
                ledgerPath = $ledgerPath
                diagnosticPath = $conflictDiagnosticPath
            }
            $operationExitCode = 3
        }
        elseif ($null -ne $indexEntry -and [string] $indexEntry.state -eq 'committed') {
            $operationResult = [ordered]@{
                status = 'noop'
                eventId = [string] $event.eventId
                runId = $RunId
                ledgerPath = $ledgerPath
                diagnosticPath = if ($diagnosticPaths.Count -gt 0) { $diagnosticPaths[0] } else { $null }
            }
        }
        else {
            Write-LedgerLine `
                -LedgerPath $ledgerPath `
                -Line $serializedEvent `
                -PrependNewline:([bool] $ledgerState.NeedsSeparator) `
                -FaultAfterBytes $FaultAfterBytes
            $postWriteState = Read-LedgerChunk `
                -LedgerPath $ledgerPath `
                -StartOffset $scanStartOffset `
                -StartLineNumber $scanStartLineNumber `
                -ExpectedRunId $RunId `
                -ExpectedProjectId ([int] $event.projectId) `
                -ExpectedStoryId ([int] $event.storyId) `
                -ExpectedStoryRef ([int] $event.storyRef)
            Update-IndexFromRecords -IndexDirectory $indexDirectory -Records $postWriteState.Records
            $incomingRecord = @($postWriteState.Records | Where-Object { $_.EventId -ceq [string] $event.eventId } | Select-Object -Last 1)
            if ($incomingRecord.Count -eq 0) {
                throw [IO.InvalidDataException]::new('appended event was not found in the complete ledger range')
            }
            $postRecordCount = if ($fullRebuild) { [long] $postWriteState.Records.Count } else { [long] $checkpoint.RecordCount + [long] $postWriteState.Records.Count }
            Write-LedgerCheckpoint `
                -CheckpointPath $checkpointPath `
                -RunId $RunId `
                -ProjectId ([int] $event.projectId) `
                -StoryId ([int] $event.storyId) `
                -StoryRef ([int] $event.storyRef) `
                -LastCompleteOffset ([long] $postWriteState.LastCompleteOffset) `
                -NextLineNumber ([int] $postWriteState.NextLineNumber) `
                -RecordCount $postRecordCount `
                -PhysicalLength ([long] $postWriteState.PhysicalLength)
            $operationResult = [ordered]@{
                status = 'appended'
                eventId = [string] $event.eventId
                runId = $RunId
                ledgerPath = $ledgerPath
                recoveredIncompleteTail = $null -ne $ledgerState.IncompleteTail
                scanMode = if ($fullRebuild) { 'cold_rebuild' } else { 'incremental' }
                scannedBytes = [long] $postWriteState.ScannedBytes
                checkpointPath = $checkpointPath
                indexPath = $indexDirectory
                diagnosticPath = if ($diagnosticPaths.Count -gt 0) { $diagnosticPaths[0] } else { $null }
            }
        }
    }
    if ($null -eq $operationResult -or [string] $operationResult.status -ne 'appended') {
        Write-LedgerCheckpoint `
            -CheckpointPath $checkpointPath `
            -RunId $RunId `
            -ProjectId ([int] $event.projectId) `
            -StoryId ([int] $event.storyId) `
            -StoryRef ([int] $event.storyRef) `
            -LastCompleteOffset ([long] $checkpointLastCompleteOffset) `
            -NextLineNumber $checkpointLineNumber `
            -RecordCount $recordCount `
            -PhysicalLength $checkpointPhysicalLength
        $operationResult.scanMode = if ($fullRebuild) { 'cold_rebuild' } else { 'incremental' }
        $operationResult.scannedBytes = [long] $ledgerState.ScannedBytes
        $operationResult.checkpointPath = $checkpointPath
        $operationResult.indexPath = $indexDirectory
    }
}
catch [TimeoutException] {
    $operationResult = [ordered]@{
        status = 'error'
        errorCategory = 'lock_timeout'
        eventId = [string] $event.eventId
        runId = $RunId
        ledgerPath = $ledgerPath
    }
    $operationExitCode = 2
}
catch {
    $operationResult = [ordered]@{
        status = 'error'
        errorCategory = 'write_failed'
        eventId = [string] $event.eventId
        runId = $RunId
        ledgerPath = $ledgerPath
    }
    $operationExitCode = 2
}
finally {
    if ($null -ne $lock) {
        $lock.Dispose()
    }
}

$operationResult | ConvertTo-Json -Compress -Depth 20
exit $operationExitCode
