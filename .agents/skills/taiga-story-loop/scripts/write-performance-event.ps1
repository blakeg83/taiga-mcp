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
