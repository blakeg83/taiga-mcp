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
$script:BloomHeader = [byte[]]@(0x54, 0x4D, 0x42, 0x4C, 0x4F, 0x4F, 0x4D, 0x31)
$script:BloomByteCount = 4096
$script:BloomHashCount = 4
$script:IntegrityDepth = 64
$script:IntegrityNodeReadCount = 0L
$script:IntegrityNodeReadBytes = 0L
$script:IntegrityNodeWriteCount = 0L
$script:IntegrityNodeWriteBytes = 0L
$script:LedgerV2FrameKind = 'story_performance_event_frame'
$script:LedgerV2CommitKind = 'story_performance_ledger_commit'
$script:LedgerV2MaxOrphanBytes = 16MB

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

    if ($eventType -notin $correctionEvents -and $null -ne $Event.supersedesReviewAttemptId) {
        Fail-Recorder 'supersedesReviewAttemptId is only valid on correction events'
    }

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

    if ($eventType -notin $reviewEvents) {
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

    return ([BitConverter]::ToString((Get-Sha256DigestBytes -Bytes $Bytes))).Replace('-', '').ToLowerInvariant()
}

function Get-Sha256DigestBytes {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes)

    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return ,$hash.ComputeHash($Bytes)
    }
    finally {
        $hash.Dispose()
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)] [string] $Text)

    return Get-Sha256HexBytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-V2GenesisCommitDigest {
    return Get-Sha256Hex -Text 'story_performance_ledger_v2_genesis'
}

function Get-LedgerPrefixDigestSeed {
    return Get-Sha256Hex -Text 'story_performance_ledger_prefix_v1'
}

function Update-LedgerPrefixDigest {
    param(
        [Parameter(Mandatory)] [string] $PreviousDigest,
        [Parameter(Mandatory)] [string] $CompleteLineDigest
    )

    if ($PreviousDigest -notmatch '^[0-9a-f]{64}$' -or $CompleteLineDigest -notmatch '^[0-9a-f]{64}$') {
        throw [IO.InvalidDataException]::new('ledger prefix digest is invalid')
    }
    return Get-Sha256Hex -Text ("story_performance_ledger_prefix_v1|$PreviousDigest|$CompleteLineDigest")
}

function Get-V2ContentChainDigest {
    param(
        [Parameter(Mandatory)] [string] $PreviousCommitDigest,
        [Parameter(Mandatory)] [string] $OrphanSuffixDigest,
        [Parameter(Mandatory)] [string] $EventDigest,
        [Parameter(Mandatory)] [long] $RecordCount
    )

    foreach ($digest in @($PreviousCommitDigest, $OrphanSuffixDigest, $EventDigest)) {
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw [IO.InvalidDataException]::new('v2 ledger digest is invalid')
        }
    }
    if ($RecordCount -le 0) {
        throw [IO.InvalidDataException]::new('v2 ledger record count is invalid')
    }
    return Get-Sha256Hex -Text ("story_performance_ledger_v2_chain_v1|$PreviousCommitDigest|$OrphanSuffixDigest|$EventDigest|$RecordCount")
}

function Get-V2EmptyOrphanDigest {
    return Get-Sha256HexBytes -Bytes ([byte[]]::new(0))
}

function New-V2CommitAnchorPayload {
    param(
        [Parameter(Mandatory)] [long] $FrameStartOffset,
        [Parameter(Mandatory)] [long] $PreviousFrameEndOffset,
        [Parameter(Mandatory)] [string] $PreviousCommitDigest,
        [Parameter(Mandatory)] [string] $OrphanSuffixDigest,
        [Parameter(Mandatory)] [string] $EventDigest,
        [Parameter(Mandatory)] [string] $ContentChainDigest,
        [Parameter(Mandatory)] [long] $RecordCount,
        [Parameter(Mandatory)] [string] $IntegrityRootHash,
        [Parameter(Mandatory)] [long] $FrameByteLength
    )

    if ($FrameStartOffset -lt 0 -or $PreviousFrameEndOffset -lt 0 -or $PreviousFrameEndOffset -gt $FrameStartOffset -or
        $PreviousCommitDigest -notmatch '^[0-9a-f]{64}$' -or $OrphanSuffixDigest -notmatch '^[0-9a-f]{64}$' -or
        $EventDigest -notmatch '^[0-9a-f]{64}$' -or $ContentChainDigest -notmatch '^[0-9a-f]{64}$' -or
        $IntegrityRootHash -notmatch '^[0-9a-f]{64}$' -or $RecordCount -le 0 -or $FrameByteLength -le 0) {
        throw [IO.InvalidDataException]::new('v2 ledger commit anchor is invalid')
    }
    return [ordered]@{
        schemaVersion = 2
        kind = $script:LedgerV2CommitKind
        frameStartOffset = $FrameStartOffset
        previousFrameEndOffset = $PreviousFrameEndOffset
        previousCommitDigest = $PreviousCommitDigest
        orphanSuffixDigest = $OrphanSuffixDigest
        eventDigest = $EventDigest
        contentChainDigest = $ContentChainDigest
        recordCount = $RecordCount
        integrityRootHash = $IntegrityRootHash
        frameByteLength = $FrameByteLength
    }
}

function Get-V2CommitDigest {
    param([Parameter(Mandatory)] [object] $AnchorPayload)

    return Get-Sha256Hex -Text ("story_performance_ledger_v2_commit_v1|$(Convert-ToCanonicalJson -Value $AnchorPayload)")
}

function New-V2LedgerFrame {
    param(
        [Parameter(Mandatory)] [object] $Event,
        [Parameter(Mandatory)] [long] $FrameStartOffset,
        [Parameter(Mandatory)] [long] $PreviousFrameEndOffset,
        [Parameter(Mandatory)] [string] $PreviousCommitDigest,
        [Parameter(Mandatory)] [string] $OrphanSuffixDigest,
        [Parameter(Mandatory)] [string] $ContentChainDigest,
        [Parameter(Mandatory)] [long] $RecordCount,
        [Parameter(Mandatory)] [string] $IntegrityRootHash
    )

    $eventDigest = Get-Sha256Hex -Text (Convert-ToCanonicalJson -Value $Event)
    # The anchor carries the exact UTF-8 frame length. Its decimal representation
    # is part of the frame, so solve the small length fixed point before computing
    # the commit digest. This remains acyclic: the length is derived from the
    # envelope bytes, while the digest covers the anchor payload without itself.
    $frameByteLength = 1L
    $line = $null
    $commitDigest = $null
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $anchorPayload = New-V2CommitAnchorPayload `
            -FrameStartOffset $FrameStartOffset `
            -PreviousFrameEndOffset $PreviousFrameEndOffset `
            -PreviousCommitDigest $PreviousCommitDigest `
            -OrphanSuffixDigest $OrphanSuffixDigest `
            -EventDigest $eventDigest `
            -ContentChainDigest $ContentChainDigest `
            -RecordCount $RecordCount `
            -IntegrityRootHash $IntegrityRootHash `
            -FrameByteLength $frameByteLength
        $anchor = [ordered]@{}
        foreach ($property in $anchorPayload.GetEnumerator()) {
            $anchor[$property.Key] = $property.Value
        }
        $commitDigest = Get-V2CommitDigest -AnchorPayload $anchorPayload
        $anchor.commitDigest = $commitDigest
        $frame = [ordered]@{
            schemaVersion = 2
            kind = $script:LedgerV2FrameKind
            event = $Event
            anchor = $anchor
        }
        $line = $frame | ConvertTo-Json -Compress -Depth 50
        $measuredLength = [long] ([Text.UTF8Encoding]::new($false).GetByteCount($line + [Environment]::NewLine))
        if ($measuredLength -eq $frameByteLength) {
            break
        }
        $frameByteLength = $measuredLength
    }
    if ($null -eq $line -or $frameByteLength -ne [long] ([Text.UTF8Encoding]::new($false).GetByteCount($line + [Environment]::NewLine))) {
        throw [IO.InvalidDataException]::new('v2 ledger frame length did not stabilize')
    }
    return [pscustomobject]@{
        Line = $line
        EventDigest = $eventDigest
        CommitDigest = $commitDigest
        FrameBytes = $frameByteLength
    }
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

function Read-FileBytePrefix {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [long] $MaximumBytes
    )

    if ($MaximumBytes -le 0 -or $MaximumBytes -gt [int]::MaxValue) {
        throw [IO.InvalidDataException]::new('ledger prefix bound is invalid')
    }
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
        return ,([byte[]]::new(0))
    }
    $length = [IO.FileInfo]::new($LedgerPath).Length
    $count = [int] [Math]::Min($length, $MaximumBytes)
    $bytes = [byte[]]::new($count)
    if ($count -eq 0) {
        return ,$bytes
    }
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($LedgerPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $read = 0
        while ($read -lt $bytes.Length) {
            $chunk = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($chunk -le 0) {
                throw [IO.IOException]::new('ledger changed while its format was being detected')
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
        [Parameter(Mandatory)] [int] $ExpectedStoryRef,
        [AllowNull()] [string] $StartingPrefixDigest
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
    $prefixDigest = if ([string]::IsNullOrWhiteSpace($StartingPrefixDigest)) { Get-LedgerPrefixDigestSeed } else { $StartingPrefixDigest }
    if ($prefixDigest -notmatch '^[0-9a-f]{64}$') {
        throw [IO.InvalidDataException]::new('ledger starting prefix digest is invalid')
    }
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
        $completeLineBytes = Copy-ByteRange -Bytes $bytes -Offset $lineStart -Count ($lineLength + 1)
        $completeLineDigest = Get-Sha256HexBytes -Bytes $completeLineBytes
        $prefixDigest = Update-LedgerPrefixDigest -PreviousDigest $prefixDigest -CompleteLineDigest $completeLineDigest
        $recordPrefixDigest = $prefixDigest
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
                    LedgerPrefixDigest = $recordPrefixDigest
                    CommitDigest = $null
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
        LedgerPrefixDigest = $prefixDigest
        ScannedBytes = [long] $bytes.Length
    }
}

function Get-LedgerFormat {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf) -or [IO.FileInfo]::new($LedgerPath).Length -eq 0) {
        return 'v2'
    }
    $bytes = Read-FileBytePrefix -LedgerPath $LedgerPath -MaximumBytes 128KB
    # A first v2 frame may be interrupted before its newline is published. Its
    # prefix still identifies the format, so route the retry through v2 orphan
    # recovery instead of treating the partial frame as legacy v1 history.
    $prefixText = ([Text.Encoding]::UTF8.GetString($bytes))
    if ($prefixText.StartsWith('{"schemaVersion":2,"kind":"', [StringComparison]::Ordinal)) {
        return 'v2'
    }
    $newline = [Array]::IndexOf($bytes, [byte] 0x0A)
    if ($newline -lt 0) {
        return 'v1'
    }
    $contentLength = $newline
    if ($contentLength -gt 0 -and $bytes[$newline - 1] -eq [byte] 0x0D) {
        $contentLength--
    }
    try {
        $line = ([Text.UTF8Encoding]::new($false, $true)).GetString((Copy-ByteRange -Bytes $bytes -Offset 0 -Count $contentLength))
        $candidate = $line | ConvertFrom-Json -Depth 50 -DateKind String
        if ([int] $candidate.schemaVersion -eq 2 -and [string] $candidate.kind -ceq $script:LedgerV2FrameKind) {
            return 'v2'
        }
    }
    catch {
    }
    return 'v1'
}

function Read-V2FrameRecord {
    param(
        [Parameter(Mandatory)] [object] $Frame,
        [Parameter(Mandatory)] [long] $FrameStartOffset,
        [Parameter(Mandatory)] [long] $FrameEndOffset,
        [Parameter(Mandatory)] [string] $ExpectedRunId,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef,
        [AllowNull()] [string] $ExpectedPreviousCommitDigest,
        [AllowNull()] [object] $OrphanBytes
    )

    if ($null -eq $Frame -or [int] $Frame.schemaVersion -ne 2 -or [string] $Frame.kind -cne $script:LedgerV2FrameKind -or
        $null -eq $Frame.event -or $null -eq $Frame.anchor) {
        throw [IO.InvalidDataException]::new('v2 ledger frame is invalid')
    }
    $event = $Frame.event
    $anchor = $Frame.anchor
    Assert-Event -Event $event -ExpectedRunId $ExpectedRunId
    Assert-EventStoryBinding -Event $event -ExpectedProjectId $ExpectedProjectId -ExpectedStoryId $ExpectedStoryId -ExpectedStoryRef $ExpectedStoryRef
    $eventDigest = Get-Sha256Hex -Text (Convert-ToCanonicalJson -Value $event)
    $anchorPayload = New-V2CommitAnchorPayload `
        -FrameStartOffset ([long] $anchor.frameStartOffset) `
        -PreviousFrameEndOffset ([long] $anchor.previousFrameEndOffset) `
        -PreviousCommitDigest ([string] $anchor.previousCommitDigest) `
        -OrphanSuffixDigest ([string] $anchor.orphanSuffixDigest) `
        -EventDigest $eventDigest `
        -ContentChainDigest ([string] $anchor.contentChainDigest) `
        -RecordCount ([long] $anchor.recordCount) `
        -IntegrityRootHash ([string] $anchor.integrityRootHash) `
        -FrameByteLength ([long] $anchor.frameByteLength)
    if ([long] $anchorPayload.frameStartOffset -ne $FrameStartOffset -or
        [long] $anchorPayload.frameStartOffset -ge $FrameEndOffset -or
        [long] $anchorPayload.previousFrameEndOffset -gt $FrameStartOffset -or
        [long] $anchorPayload.frameByteLength -ne ($FrameEndOffset - $FrameStartOffset) -or
        [string] $anchor.eventDigest -cne $eventDigest -or
        [string] $anchor.commitDigest -notmatch '^[0-9a-f]{64}$' -or
        [string] $anchor.commitDigest -cne (Get-V2CommitDigest -AnchorPayload $anchorPayload)) {
        throw [IO.InvalidDataException]::new('v2 ledger commit anchor digest is invalid')
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPreviousCommitDigest) -and [string] $anchor.previousCommitDigest -cne $ExpectedPreviousCommitDigest) {
        throw [IO.InvalidDataException]::new('v2 ledger commit chain is broken')
    }
    if ($null -ne $OrphanBytes) {
        $orphanArray = [byte[]] @($OrphanBytes)
        if ($orphanArray.Length -gt $script:LedgerV2MaxOrphanBytes -or
            [string] $anchor.orphanSuffixDigest -cne (Get-Sha256HexBytes -Bytes $orphanArray)) {
            throw [IO.InvalidDataException]::new('v2 ledger orphan suffix is invalid')
        }
    }
    $contentChainDigest = Get-V2ContentChainDigest `
        -PreviousCommitDigest ([string] $anchor.previousCommitDigest) `
        -OrphanSuffixDigest ([string] $anchor.orphanSuffixDigest) `
        -EventDigest $eventDigest `
        -RecordCount ([long] $anchor.recordCount)
    if ([string] $anchor.contentChainDigest -cne $contentChainDigest) {
        throw [IO.InvalidDataException]::new('v2 ledger content chain is invalid')
    }
    return [pscustomobject]@{
        EventId = [string] $event.eventId
        CanonicalJson = Convert-ToCanonicalJson -Value $event
        LineNumber = 0
        StartOffset = $FrameStartOffset
        EndOffset = $FrameEndOffset
        LedgerPrefixDigest = [string] $anchor.contentChainDigest
        Event = $event
        EventDigest = $eventDigest
        ContentChainDigest = [string] $anchor.contentChainDigest
        CommitDigest = [string] $anchor.commitDigest
        IntegrityRootHash = [string] $anchor.integrityRootHash
        RecordCount = [long] $anchor.recordCount
        FrameStartOffset = $FrameStartOffset
        FrameEndOffset = $FrameEndOffset
        PreviousFrameEndOffset = [long] $anchor.previousFrameEndOffset
    }
}

function Read-V2LedgerHead {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $ExpectedRunId,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef
    )

    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
        return $null
    }
    $length = [IO.FileInfo]::new($LedgerPath).Length
    if ($length -eq 0) {
        return $null
    }
    $tailCount = [long] [Math]::Min($length, 128KB)
    $tail = Read-FileByteRange -LedgerPath $LedgerPath -StartOffset ($length - $tailCount)
    if ($tail.Length -eq 0 -or $tail[$tail.Length - 1] -ne [byte] 0x0A) {
        throw [IO.InvalidDataException]::new('v2 ledger has an incomplete tail')
    }
    $lastNewline = $tail.Length - 1
    while ($lastNewline -ge 0 -and $tail[$lastNewline] -ne [byte] 0x0A) { $lastNewline-- }
    $previousNewline = $lastNewline - 1
    while ($previousNewline -ge 0 -and $tail[$previousNewline] -ne [byte] 0x0A) { $previousNewline-- }
    $lineStartInTail = $previousNewline + 1
    if ($lineStartInTail -eq 0 -and $length -gt $tailCount) {
        throw [IO.InvalidDataException]::new('v2 ledger head exceeds the bounded tail read')
    }
    $lineLength = $lastNewline - $lineStartInTail
    if ($lineLength -gt 0 -and $tail[$lastNewline - 1] -eq [byte] 0x0D) { $lineLength-- }
    $lineBytes = Copy-ByteRange -Bytes $tail -Offset $lineStartInTail -Count $lineLength
    try {
        $line = ([Text.UTF8Encoding]::new($false, $true)).GetString($lineBytes)
        $frame = $line | ConvertFrom-Json -Depth 50 -DateKind String
        $frameStart = ($length - $tailCount) + $lineStartInTail
        $record = Read-V2FrameRecord `
            -Frame $frame `
            -FrameStartOffset $frameStart `
            -FrameEndOffset $length `
            -ExpectedRunId $ExpectedRunId `
            -ExpectedProjectId $ExpectedProjectId `
            -ExpectedStoryId $ExpectedStoryId `
            -ExpectedStoryRef $ExpectedStoryRef `
            -ExpectedPreviousCommitDigest $null `
            -OrphanBytes $null
        return [pscustomobject]@{
            Record = $record
            PhysicalLength = $length
            FrameEndOffset = $length
        }
    }
    catch {
        if ($_.Exception -is [IO.InvalidDataException]) { throw }
        throw [IO.InvalidDataException]::new('v2 ledger head is invalid')
    }
}

function Read-V2LedgerFull {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $ExpectedRunId,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef
    )

    $physicalLength = if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) { [IO.FileInfo]::new($LedgerPath).Length } else { 0L }
    $bytes = Read-FileByteRange -LedgerPath $LedgerPath -StartOffset 0
    $records = [System.Collections.Generic.List[object]]::new()
    $invalid = [System.Collections.Generic.List[object]]::new()
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $previousCommitDigest = Get-V2GenesisCommitDigest
    $previousFrameEndOffset = 0L
    $contentChainDigest = $previousCommitDigest
    $integrityRootHash = Get-IntegrityEmptyHash
    $lineStart = 0
    $lineNumber = 0
    for ($offset = 0; $offset -lt $bytes.Length; $offset++) {
        if ($bytes[$offset] -ne [byte] 0x0A) { continue }
        $lineNumber++
        $lineLength = $offset - $lineStart
        $contentLength = $lineLength
        if ($contentLength -gt 0 -and $bytes[$offset - 1] -eq [byte] 0x0D) { $contentLength-- }
        $frameStartOffset = [long] $lineStart
        $frameEndOffset = [long] ($offset + 1)
        $lineBytes = Copy-ByteRange -Bytes $bytes -Offset $lineStart -Count $contentLength
        $accepted = $false
        $frame = $null
        try {
            $frame = $utf8.GetString($lineBytes) | ConvertFrom-Json -Depth 50 -DateKind String
            $orphanBytes = Copy-ByteRange -Bytes $bytes -Offset ([int] $previousFrameEndOffset) -Count ([int] ($frameStartOffset - $previousFrameEndOffset))
            if ($orphanBytes.Length -gt $script:LedgerV2MaxOrphanBytes) { throw [IO.InvalidDataException]::new('v2 ledger orphan suffix exceeds the bounded recovery buffer') }
            $record = Read-V2FrameRecord `
                -Frame $frame `
                -FrameStartOffset $frameStartOffset `
                -FrameEndOffset $frameEndOffset `
                -ExpectedRunId $ExpectedRunId `
                -ExpectedProjectId $ExpectedProjectId `
                -ExpectedStoryId $ExpectedStoryId `
                -ExpectedStoryRef $ExpectedStoryRef `
                -ExpectedPreviousCommitDigest $previousCommitDigest `
                -OrphanBytes $orphanBytes
            $record.LineNumber = $lineNumber
            if ([long] $record.PreviousFrameEndOffset -ne $previousFrameEndOffset -or [long] $record.RecordCount -ne ([long] $records.Count + 1)) {
                throw [IO.InvalidDataException]::new('v2 ledger frame ordinal or offset is invalid')
            }
            [void] $records.Add($record)
            $previousCommitDigest = $record.CommitDigest
            $previousFrameEndOffset = $frameEndOffset
            $contentChainDigest = $record.ContentChainDigest
            $integrityRootHash = $record.IntegrityRootHash
            $accepted = $true
        }
        catch {
            $diagnosticType = 'orphan_ledger_frame'
            try {
                if ($null -ne $frame -and [int] $frame.schemaVersion -eq 2 -and
                    [string] $frame.kind -ceq $script:LedgerV2FrameKind -and $null -ne $frame.event -and
                    ([string] $frame.event.runId -cne $ExpectedRunId -or
                     [int] $frame.event.projectId -ne $ExpectedProjectId -or
                     [int] $frame.event.storyId -ne $ExpectedStoryId -or
                     [int] $frame.event.storyRef -ne $ExpectedStoryRef)) {
                    $diagnosticType = 'foreign_run'
                }
            }
            catch {
            }
            [void] $invalid.Add([pscustomobject]@{
                    diagnosticType = $diagnosticType
                    lineNumber = $lineNumber
                    byteLength = $contentLength
                    digest = Get-Sha256HexBytes -Bytes $lineBytes
                })
        }
        $lineStart = $offset + 1
    }
    $tailLength = $bytes.Length - $lineStart
    $incompleteTail = if ($tailLength -gt 0) {
        $tailBytes = Copy-ByteRange -Bytes $bytes -Offset $lineStart -Count $tailLength
        [pscustomobject]@{ lineNumber = $lineNumber + 1; byteLength = $tailLength; digest = Get-Sha256HexBytes -Bytes $tailBytes }
    } else { $null }
    return [pscustomobject]@{
        Records = @($records)
        InvalidRecords = @($invalid)
        IncompleteTail = $incompleteTail
        NeedsSeparator = $tailLength -gt 0
        StartOffset = 0L
        LastCompleteOffset = $previousFrameEndOffset
        NextLineNumber = $lineNumber
        PhysicalLength = $physicalLength
        LedgerPrefixDigest = $contentChainDigest
        ScannedBytes = [long] $bytes.Length
        HeadCommitDigest = $previousCommitDigest
        HeadFrameEndOffset = $previousFrameEndOffset
        HeadRecordCount = [long] $records.Count
        HeadIntegrityRootHash = $integrityRootHash
    }
}

function New-LedgerRangeReadException {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter(Mandatory)] [long] $BytesRead
    )

    $exception = [IO.InvalidDataException]::new($Message)
    $exception.Data['LedgerBytesRead'] = $BytesRead
    return $exception
}

function Get-LedgerRangeReadBytes {
    param([Parameter(Mandatory)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    $data = $ErrorRecord.Exception.Data
    if ($null -ne $data -and $data.Contains('LedgerBytesRead')) {
        return [long] $data['LedgerBytesRead']
    }
    return 0L
}

function Read-LedgerRecordAtOffsets {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $ExpectedRunId,
        [Parameter(Mandatory)] [int] $ExpectedProjectId,
        [Parameter(Mandatory)] [int] $ExpectedStoryId,
        [Parameter(Mandatory)] [int] $ExpectedStoryRef,
        [Parameter(Mandatory)] [object] $Entry
    )

    $startOffset = [long] $Entry.startOffset
    $endOffset = [long] $Entry.endOffset
    $lineNumber = [int] $Entry.lineNumber
    if ($lineNumber -le 0 -or $startOffset -lt 0 -or $endOffset -le $startOffset) {
        throw [IO.InvalidDataException]::new('ledger identity range is invalid')
    }
    $rangeLength = $endOffset - $startOffset
    if ($rangeLength -gt [int] 16MB -or $rangeLength -gt [int]::MaxValue) {
        throw [IO.InvalidDataException]::new('ledger identity range exceeds the bounded record buffer')
    }
    $physicalLength = [IO.FileInfo]::new($LedgerPath).Length
    if ($endOffset -gt $physicalLength) {
        throw [IO.InvalidDataException]::new('ledger identity range is outside the complete ledger')
    }

    $bytes = [byte[]]::new([int] $rangeLength)
    $bytesRead = 0L
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($LedgerPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        [void] $stream.Seek($startOffset, [IO.SeekOrigin]::Begin)
        $read = 0
        while ($read -lt $bytes.Length) {
            $chunk = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($chunk -le 0) {
                throw (New-LedgerRangeReadException -Message 'ledger changed while identity range was being validated' -BytesRead $bytesRead)
            }
            $read += $chunk
            $bytesRead += [long] $chunk
        }
    }
    catch {
        if ($_.Exception -is [IO.InvalidDataException] -and $_.Exception.Data.Contains('LedgerBytesRead')) {
            throw
        }
        throw (New-LedgerRangeReadException -Message $_.Exception.Message -BytesRead $bytesRead)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    if ($bytes[$bytes.Length - 1] -ne [byte] 0x0A) {
        throw (New-LedgerRangeReadException -Message 'ledger identity range is not a complete line' -BytesRead $bytesRead)
    }
    $contentLength = $bytes.Length - 1
    if ($contentLength -gt 0 -and $bytes[$contentLength - 1] -eq [byte] 0x0D) {
        $contentLength--
    }
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    try {
        $line = $encoding.GetString((Copy-ByteRange -Bytes $bytes -Offset 0 -Count $contentLength))
        $candidate = $line | ConvertFrom-Json -DateKind String
        $frameCommitDigest = $null
        if ($null -ne $candidate -and [int] $candidate.schemaVersion -eq 2 -and [string] $candidate.kind -ceq $script:LedgerV2FrameKind) {
            $frame = $candidate
            $frameRecord = Read-V2FrameRecord `
                -Frame $frame `
                -FrameStartOffset $startOffset `
                -FrameEndOffset $endOffset `
                -ExpectedRunId $ExpectedRunId `
                -ExpectedProjectId $ExpectedProjectId `
                -ExpectedStoryId $ExpectedStoryId `
                -ExpectedStoryRef $ExpectedStoryRef `
                -ExpectedPreviousCommitDigest $null `
                -OrphanBytes $null
            $entryCommitDigest = Get-Property -Object $Entry -Name 'frameCommitDigest'
            if ($null -eq $entryCommitDigest -or [string] $entryCommitDigest.Value -notmatch '^[0-9a-f]{64}$' -or
                [string] $entryCommitDigest.Value -cne [string] $frameRecord.CommitDigest) {
                throw [IO.InvalidDataException]::new('v2 ledger range is not bound to a committed frame')
            }
            $frameCommitDigest = [string] $frameRecord.CommitDigest
            $candidate = $frame.event
        }
        $eventIdProperty = if ($null -eq $candidate) { $null } else { Get-Property -Object $candidate -Name 'eventId' }
        if ($null -eq $candidate -or $candidate -is [System.Array] -or
            $null -eq $eventIdProperty -or [string] $eventIdProperty.Value -cne $EventId) {
            throw [IO.InvalidDataException]::new('ledger identity range does not contain the expected event')
        }
        Assert-Event -Event $candidate -ExpectedRunId $ExpectedRunId
        Assert-EventStoryBinding -Event $candidate -ExpectedProjectId $ExpectedProjectId -ExpectedStoryId $ExpectedStoryId -ExpectedStoryRef $ExpectedStoryRef
        return [pscustomobject]@{
            EventId = $EventId
            CanonicalJson = Convert-ToCanonicalJson -Value $candidate
            LineNumber = $lineNumber
            StartOffset = $startOffset
            EndOffset = $endOffset
            BytesRead = [long] $rangeLength
            CommitDigest = $frameCommitDigest
        }
    }
    catch {
        throw (New-LedgerRangeReadException -Message 'ledger identity range is not a valid event' -BytesRead $bytesRead)
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

function Get-LedgerBloomPath {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.bloom"
}

function Get-EventIndexPath {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    return (Join-Path $IndexDirectory ((Get-Sha256Hex -Text $EventId) + '.json'))
}

function Get-LedgerMembershipDirectory {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.membership"
}

function Get-LedgerIdentityDirectory {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.identity"
}

function Get-LedgerAuthorityDirectory {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.authority"
}

function Get-LedgerCatalogDirectory {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.catalog"
}

function Get-LedgerIntegrityDirectory {
    param([Parameter(Mandatory)] [string] $LedgerPath)

    return "$LedgerPath.integrity"
}

function Get-IntegrityNodeDirectory {
    param([Parameter(Mandatory)] [string] $IntegrityDirectory)

    return (Join-Path $IntegrityDirectory 'nodes')
}

function Get-IntegrityNodePath {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $NodeHash
    )

    return (Join-Path (Get-IntegrityNodeDirectory -IntegrityDirectory $IntegrityDirectory) "$NodeHash.json")
}

function Get-EventMembershipPath {
    param(
        [Parameter(Mandatory)] [string] $MembershipDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    return (Join-Path $MembershipDirectory ((Get-Sha256Hex -Text $EventId) + '.json'))
}

function Get-EventIdentityPath {
    param(
        [Parameter(Mandatory)] [string] $IdentityDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    return (Join-Path $IdentityDirectory ((Get-Sha256Hex -Text $EventId) + '.json'))
}

function Get-EventAuthorityPath {
    param(
        [Parameter(Mandatory)] [string] $AuthorityDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    return (Join-Path $AuthorityDirectory ((Get-Sha256Hex -Text $EventId) + '.json'))
}

function Get-EventCatalogPath {
    param(
        [Parameter(Mandatory)] [string] $CatalogDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    return (Join-Path $CatalogDirectory ((Get-Sha256Hex -Text $EventId) + '.json'))
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

function Write-AtomicBytes {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [byte[]] $Bytes
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
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

function Get-IntegrityEmptyHash {
    $payload = [ordered]@{ nodeType = 'empty' }
    return Get-Sha256Hex -Text (Convert-ToCanonicalJson -Value $payload)
}

function New-IntegrityBranchPayload {
    param([Parameter(Mandatory)] [string[]] $Children)

    if ($Children.Count -ne 16) {
        throw [IO.InvalidDataException]::new('event integrity branch has an invalid child count')
    }
    return [ordered]@{
        nodeType = 'branch'
        children = @($Children)
    }
}

function New-IntegrityRootPayload {
    param(
        [Parameter(Mandatory)] [string[]] $Children,
        [Parameter(Mandatory)] [long] $RecordCount,
        [Parameter(Mandatory)] [long] $PhysicalLength,
        [Parameter(Mandatory)] [string] $LedgerPrefixDigest,
        [switch] $ExcludePhysicalLength
    )

    if ($RecordCount -lt 0 -or $PhysicalLength -lt 0 -or $LedgerPrefixDigest -notmatch '^[0-9a-f]{64}$') {
        throw [IO.InvalidDataException]::new('event integrity root state is invalid')
    }
    $payload = New-IntegrityBranchPayload -Children $Children
    $payload.nodeType = 'root'
    $payload.recordCount = $RecordCount
    $payload.physicalLength = $PhysicalLength
    $payload.ledgerPrefixDigest = $LedgerPrefixDigest
    return $payload
}

function New-IntegrityLeafPayload {
    param([Parameter(Mandatory)] [object[]] $Entries)

    return [ordered]@{
        nodeType = 'leaf'
        entries = @($Entries | ForEach-Object {
                [ordered]@{
                    eventId = [string] $_.eventId
                    eventIdDigest = [string] $_.eventIdDigest
                }
            })
    }
}

function Get-IntegrityNodeHash {
    param([Parameter(Mandatory)] [object] $Payload)

    return Get-Sha256Hex -Text (Convert-ToCanonicalJson -Value $Payload)
}

function Read-IntegrityNode {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $NodeHash
    )

    $emptyHash = Get-IntegrityEmptyHash
    if ($NodeHash -ceq $emptyHash) {
        return $null
    }
    if ($NodeHash -notmatch '^[0-9a-f]{64}$') {
        throw [IO.InvalidDataException]::new('event integrity node hash is invalid')
    }
    $path = Get-IntegrityNodePath -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw [IO.InvalidDataException]::new('event integrity node is missing')
    }
    try {
        $nodeText = [IO.File]::ReadAllText($path)
        $script:IntegrityNodeReadCount++
        $script:IntegrityNodeReadBytes += [long] [IO.FileInfo]::new($path).Length
        $node = $nodeText | ConvertFrom-Json -DateKind String
        if ($null -eq $node -or [int] $node.schemaVersion -ne 1 -or
            [string] $node.kind -cne 'story_performance_integrity_node' -or
            [string] $node.nodeHash -cne $NodeHash -or
            [string] $node.nodeType -notin @('root', 'branch', 'leaf')) {
            throw [IO.InvalidDataException]::new('event integrity node is invalid')
        }
        if ([string] $node.nodeType -in @('root', 'branch')) {
            $children = @($node.children | ForEach-Object { [string] $_ })
            if ($children.Count -ne 16 -or @($children | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
                throw [IO.InvalidDataException]::new('event integrity branch is invalid')
            }
            if ([string] $node.nodeType -ceq 'root') {
                if ($null -eq (Get-Property -Object $node -Name 'recordCount') -or
                    $null -eq (Get-Property -Object $node -Name 'physicalLength') -or
                    $null -eq (Get-Property -Object $node -Name 'ledgerPrefixDigest')) {
                    throw [IO.InvalidDataException]::new('event integrity root state is missing')
                }
                $payload = New-IntegrityRootPayload -Children $children -RecordCount ([long] $node.recordCount) -PhysicalLength ([long] $node.physicalLength) -LedgerPrefixDigest ([string] $node.ledgerPrefixDigest)
            }
            else {
                $payload = New-IntegrityBranchPayload -Children $children
            }
        }
        else {
            $entries = @($node.entries)
            if ($entries.Count -lt 1) {
                throw [IO.InvalidDataException]::new('event integrity leaf is empty')
            }
            $seenEventIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $normalizedEntries = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $entries) {
                if ($null -eq $entry -or [string]::IsNullOrWhiteSpace([string] $entry.eventId) -or
                    [string] $entry.eventId -match '[\x00-\x1F\x7F]' -or
                    [string] $entry.eventIdDigest -cne (Get-Sha256Hex -Text ([string] $entry.eventId)) -or
                    -not $seenEventIds.Add([string] $entry.eventId)) {
                    throw [IO.InvalidDataException]::new('event integrity leaf is invalid')
                }
                [void] $normalizedEntries.Add([ordered]@{
                        eventId = [string] $entry.eventId
                        eventIdDigest = [string] $entry.eventIdDigest
                    })
            }
            $payload = New-IntegrityLeafPayload -Entries @($normalizedEntries)
        }
        if ((Get-IntegrityNodeHash -Payload $payload) -cne $NodeHash) {
            throw [IO.InvalidDataException]::new('event integrity node digest is invalid')
        }
        return $node
    }
    catch {
        if ($_.Exception -is [IO.InvalidDataException]) {
            throw
        }
        throw [IO.InvalidDataException]::new('event integrity node is invalid')
    }
}

function Write-IntegrityNode {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [object] $Payload
    )

    $nodeHash = Get-IntegrityNodeHash -Payload $Payload
    $node = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_integrity_node'
        nodeType = [string] $Payload.nodeType
        nodeHash = $nodeHash
    }
    if ([string] $Payload.nodeType -in @('root', 'branch')) {
        $node.children = @($Payload.children | ForEach-Object { [string] $_ })
        if ([string] $Payload.nodeType -ceq 'root') {
            $node.recordCount = [long] $Payload.recordCount
            $node.physicalLength = [long] $Payload.physicalLength
            $node.ledgerPrefixDigest = [string] $Payload.ledgerPrefixDigest
        }
    }
    elseif ([string] $Payload.nodeType -ceq 'leaf') {
        $node.entries = @($Payload.entries | ForEach-Object {
                [ordered]@{
                    eventId = [string] $_.eventId
                    eventIdDigest = [string] $_.eventIdDigest
                }
            })
    }
    else {
        throw [IO.InvalidDataException]::new('event integrity node type is invalid')
    }

    $path = Get-IntegrityNodePath -IntegrityDirectory $IntegrityDirectory -NodeHash $nodeHash
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        [void] (Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $nodeHash)
    }
    else {
        $nodeText = $node | ConvertTo-Json -Compress -Depth 20
        Write-AtomicText -Path $path -Text $nodeText
        $script:IntegrityNodeWriteCount++
        $script:IntegrityNodeWriteBytes += [long] ([Text.UTF8Encoding]::new($false).GetByteCount($nodeText))
    }
    return $nodeHash
}

function Get-IntegrityNibble {
    param(
        [Parameter(Mandatory)] [string] $Digest,
        [Parameter(Mandatory)] [int] $Depth
    )

    if ($Depth -lt 0 -or $Depth -ge $script:IntegrityDepth -or $Digest.Length -ne $script:IntegrityDepth) {
        throw [IO.InvalidDataException]::new('event integrity key depth is invalid')
    }
    return [Convert]::ToInt32($Digest.Substring($Depth, 1), 16)
}

function Update-IntegrityNode {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $NodeHash,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventIdDigest,
        [Parameter(Mandatory)] [int] $Depth,
        [AllowNull()] [Nullable[long]] $RootRecordCount,
        [AllowNull()] [Nullable[long]] $RootPhysicalLength,
        [AllowNull()] [string] $RootLedgerPrefixDigest
    )

    $emptyHash = Get-IntegrityEmptyHash
    if ($Depth -eq $script:IntegrityDepth) {
        $entries = [System.Collections.Generic.List[object]]::new()
        if ($NodeHash -cne $emptyHash) {
            $node = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash
            if ([string] $node.nodeType -cne 'leaf') {
                throw [IO.InvalidDataException]::new('event integrity leaf path is invalid')
            }
            foreach ($entry in @($node.entries)) {
                if ([string] $entry.eventId -ceq $EventId) {
                    return $NodeHash
                }
                [void] $entries.Add([ordered]@{
                        eventId = [string] $entry.eventId
                        eventIdDigest = [string] $entry.eventIdDigest
                    })
            }
        }
        [void] $entries.Add([ordered]@{
                eventId = $EventId
                eventIdDigest = $EventIdDigest
            })
        $orderedEntries = @($entries | Sort-Object -Property eventId, eventIdDigest)
        return Write-IntegrityNode -IntegrityDirectory $IntegrityDirectory -Payload (New-IntegrityLeafPayload -Entries $orderedEntries)
    }

    $children = [string[]]::new(16)
    for ($index = 0; $index -lt $children.Length; $index++) {
        $children[$index] = $emptyHash
    }
    if ($NodeHash -cne $emptyHash) {
        $node = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash
        $expectedNodeType = if ($Depth -eq 0) { 'root' } else { 'branch' }
        if ([string] $node.nodeType -cne $expectedNodeType) {
            throw [IO.InvalidDataException]::new('event integrity branch path is invalid')
        }
        $children = @($node.children | ForEach-Object { [string] $_ })
    }
    $nibble = Get-IntegrityNibble -Digest $EventIdDigest -Depth $Depth
    $childHash = Update-IntegrityNode `
        -IntegrityDirectory $IntegrityDirectory `
        -NodeHash ([string] $children[$nibble]) `
        -EventId $EventId `
        -EventIdDigest $EventIdDigest `
        -Depth ($Depth + 1) `
        -RootRecordCount $RootRecordCount `
        -RootPhysicalLength $RootPhysicalLength `
        -RootLedgerPrefixDigest $RootLedgerPrefixDigest
    $rootStateUnchanged = $Depth -ne 0 -or ($null -ne $NodeHash -and $NodeHash -cne $emptyHash -and
        [long] (Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash).recordCount -eq [long] $RootRecordCount -and
        [long] (Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash).physicalLength -eq [long] $RootPhysicalLength -and
        [string] (Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash).ledgerPrefixDigest -ceq [string] $RootLedgerPrefixDigest)
    if ([string] $children[$nibble] -ceq $childHash -and $rootStateUnchanged) {
        return $NodeHash
    }
    $children[$nibble] = $childHash
    $payload = if ($Depth -eq 0) {
        New-IntegrityRootPayload -Children $children -RecordCount ([long] $RootRecordCount) -PhysicalLength ([long] $RootPhysicalLength) -LedgerPrefixDigest ([string] $RootLedgerPrefixDigest)
    }
    else {
        New-IntegrityBranchPayload -Children $children
    }
    return Write-IntegrityNode -IntegrityDirectory $IntegrityDirectory -Payload $payload
}

function Get-IntegrityNodeUpdatePlan {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $NodeHash,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [string] $EventIdDigest,
        [Parameter(Mandatory)] [int] $Depth,
        [Parameter(Mandatory)] [long] $RootRecordCount,
        [Parameter(Mandatory)] [long] $RootPhysicalLength,
        [Parameter(Mandatory)] [string] $RootLedgerPrefixDigest
    )

    $emptyHash = Get-IntegrityEmptyHash
    if ($Depth -eq $script:IntegrityDepth) {
        $entries = [System.Collections.Generic.List[object]]::new()
        if ($NodeHash -cne $emptyHash) {
            $node = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash
            if ([string] $node.nodeType -cne 'leaf') {
                throw [IO.InvalidDataException]::new('event integrity leaf path is invalid')
            }
            foreach ($entry in @($node.entries)) {
                if ([string] $entry.eventId -ceq $EventId) {
                    return [pscustomobject]@{ NodeHash = $NodeHash; Nodes = @() }
                }
                [void] $entries.Add([ordered]@{
                        eventId = [string] $entry.eventId
                        eventIdDigest = [string] $entry.eventIdDigest
                    })
            }
        }
        [void] $entries.Add([ordered]@{ eventId = $EventId; eventIdDigest = $EventIdDigest })
        $payload = New-IntegrityLeafPayload -Entries @($entries | Sort-Object -Property eventId, eventIdDigest)
        return [pscustomobject]@{
            NodeHash = Get-IntegrityNodeHash -Payload $payload
            Nodes = @([pscustomobject]@{ Payload = $payload })
        }
    }

    $children = [string[]]::new(16)
    for ($index = 0; $index -lt $children.Length; $index++) { $children[$index] = $emptyHash }
    if ($NodeHash -cne $emptyHash) {
        $node = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $NodeHash
        $expectedNodeType = if ($Depth -eq 0) { 'root' } else { 'branch' }
        if ([string] $node.nodeType -cne $expectedNodeType) {
            throw [IO.InvalidDataException]::new('event integrity branch path is invalid')
        }
        $children = @($node.children | ForEach-Object { [string] $_ })
    }
    $nibble = Get-IntegrityNibble -Digest $EventIdDigest -Depth $Depth
    $childPlan = Get-IntegrityNodeUpdatePlan `
        -IntegrityDirectory $IntegrityDirectory `
        -NodeHash ([string] $children[$nibble]) `
        -EventId $EventId `
        -EventIdDigest $EventIdDigest `
        -Depth ($Depth + 1) `
        -RootRecordCount $RootRecordCount `
        -RootPhysicalLength $RootPhysicalLength `
        -RootLedgerPrefixDigest $RootLedgerPrefixDigest
    if ([string] $children[$nibble] -ceq [string] $childPlan.NodeHash -and $Depth -ne 0) {
        return [pscustomobject]@{ NodeHash = $NodeHash; Nodes = @() }
    }
    $children[$nibble] = [string] $childPlan.NodeHash
    $payload = if ($Depth -eq 0) {
        New-IntegrityRootPayload -Children $children -RecordCount $RootRecordCount -PhysicalLength $RootPhysicalLength -LedgerPrefixDigest $RootLedgerPrefixDigest
    }
    else {
        New-IntegrityBranchPayload -Children $children
    }
    return [pscustomobject]@{
        NodeHash = Get-IntegrityNodeHash -Payload $payload
        Nodes = @($childPlan.Nodes) + @([pscustomobject]@{ Payload = $payload })
    }
}

function Set-IntegrityRootMetadata {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $RootHash,
        [Parameter(Mandatory)] [long] $RecordCount,
        [Parameter(Mandatory)] [long] $PhysicalLength,
        [Parameter(Mandatory)] [string] $LedgerPrefixDigest
    )

    $emptyHash = Get-IntegrityEmptyHash
    if ($RootHash -ceq $emptyHash) {
        $children = [string[]]::new(16)
        for ($index = 0; $index -lt $children.Length; $index++) {
            $children[$index] = $emptyHash
        }
        return Write-IntegrityNode -IntegrityDirectory $IntegrityDirectory -Payload (New-IntegrityRootPayload -Children $children -RecordCount $RecordCount -PhysicalLength $PhysicalLength -LedgerPrefixDigest $LedgerPrefixDigest)
    }
    $root = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $RootHash
    if ([string] $root.nodeType -cne 'root') {
        throw [IO.InvalidDataException]::new('event integrity root is invalid')
    }
    if ([long] $root.recordCount -eq $RecordCount -and
        [long] $root.physicalLength -eq $PhysicalLength -and
        [string] $root.ledgerPrefixDigest -ceq $LedgerPrefixDigest) {
        return $RootHash
    }
    return Write-IntegrityNode -IntegrityDirectory $IntegrityDirectory -Payload (New-IntegrityRootPayload -Children @($root.children | ForEach-Object { [string] $_ }) -RecordCount $RecordCount -PhysicalLength $PhysicalLength -LedgerPrefixDigest $LedgerPrefixDigest)
}

function Update-IntegrityFromRecords {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $RootHash,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records,
        [Parameter(Mandatory)] [long] $StartingRecordCount,
        [Parameter(Mandatory)] [long] $FinalRecordCount,
        [Parameter(Mandatory)] [long] $FinalPhysicalLength,
        [Parameter(Mandatory)] [string] $FinalLedgerPrefixDigest,
        [switch] $ExcludePhysicalLength
    )

    [IO.Directory]::CreateDirectory((Get-IntegrityNodeDirectory -IntegrityDirectory $IntegrityDirectory)) | Out-Null
    $root = $RootHash
    $recordOrdinal = 0L
    foreach ($record in @($Records)) {
        $eventId = [string] $record.EventId
        $eventIdDigest = Get-Sha256Hex -Text $eventId
        $recordPrefixDigest = [string] $record.LedgerPrefixDigest
        if ($recordPrefixDigest -notmatch '^[0-9a-f]{64}$') {
            throw [IO.InvalidDataException]::new('event record prefix digest is invalid')
        }
        $recordOrdinal++
        $recordPhysicalLength = if ($ExcludePhysicalLength) { 0L } else { [long] $record.EndOffset }
        $root = Update-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $root -EventId $eventId -EventIdDigest $eventIdDigest -Depth 0 -RootRecordCount ($StartingRecordCount + $recordOrdinal) -RootPhysicalLength $recordPhysicalLength -RootLedgerPrefixDigest $recordPrefixDigest
    }
    $rootPhysicalLength = if ($ExcludePhysicalLength) { 0L } else { $FinalPhysicalLength }
    return Set-IntegrityRootMetadata -IntegrityDirectory $IntegrityDirectory -RootHash $root -RecordCount $FinalRecordCount -PhysicalLength $rootPhysicalLength -LedgerPrefixDigest $FinalLedgerPrefixDigest
}

function Read-IntegrityMembership {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [string] $RootHash,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [long] $ExpectedRecordCount,
        [Parameter(Mandatory)] [long] $ExpectedPhysicalLength,
        [Parameter(Mandatory)] [string] $ExpectedLedgerPrefixDigest
    )

    $emptyHash = Get-IntegrityEmptyHash
    $eventIdDigest = Get-Sha256Hex -Text $EventId
    $nodeHash = $RootHash
    for ($depth = 0; $depth -lt $script:IntegrityDepth; $depth++) {
        if ($nodeHash -ceq $emptyHash) {
            if ($depth -eq 0 -and ($ExpectedRecordCount -ne 0 -or $ExpectedPhysicalLength -ne 0)) {
                throw [IO.InvalidDataException]::new('event integrity root is missing')
            }
            return [pscustomobject]@{ Present = $false; EventId = $EventId }
        }
        $node = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $nodeHash
        if ($depth -eq 0) {
            if ([long] $node.recordCount -ne $ExpectedRecordCount -or
                [long] $node.physicalLength -ne $ExpectedPhysicalLength -or
                [string] $node.ledgerPrefixDigest -cne $ExpectedLedgerPrefixDigest) {
                throw [IO.InvalidDataException]::new('event integrity root is not ledger-bound')
            }
        }
        $expectedNodeType = if ($depth -eq 0) { 'root' } else { 'branch' }
        if ([string] $node.nodeType -cne $expectedNodeType) {
            throw [IO.InvalidDataException]::new('event integrity proof reached a non-branch node')
        }
        $nibble = Get-IntegrityNibble -Digest $eventIdDigest -Depth $depth
        $nodeHash = [string] @($node.children)[$nibble]
    }
    if ($nodeHash -ceq $emptyHash) {
        return [pscustomobject]@{ Present = $false; EventId = $EventId }
    }
    $leaf = Read-IntegrityNode -IntegrityDirectory $IntegrityDirectory -NodeHash $nodeHash
    if ([string] $leaf.nodeType -cne 'leaf') {
        throw [IO.InvalidDataException]::new('event integrity proof did not end at a leaf')
    }
    foreach ($entry in @($leaf.entries)) {
        if ([string] $entry.eventId -ceq $EventId) {
            return [pscustomobject]@{ Present = $true; EventId = $EventId }
        }
    }
    return [pscustomobject]@{ Present = $false; EventId = $EventId }
}

function Write-IntegrityFromFullLedger {
    param(
        [Parameter(Mandatory)] [string] $IntegrityDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records,
        [Parameter(Mandatory)] [long] $PhysicalLength,
        [Parameter(Mandatory)] [string] $LedgerPrefixDigest,
        [switch] $ExcludePhysicalLength
    )

    Clear-LedgerIntegrity -IntegrityDirectory $IntegrityDirectory
    return Update-IntegrityFromRecords `
        -IntegrityDirectory $IntegrityDirectory `
        -RootHash (Get-IntegrityEmptyHash) `
        -Records $Records `
        -StartingRecordCount 0 `
        -FinalRecordCount ([long] $Records.Count) `
        -FinalPhysicalLength $PhysicalLength `
        -FinalLedgerPrefixDigest $LedgerPrefixDigest `
        -ExcludePhysicalLength:$ExcludePhysicalLength
}

function New-EmptyBloomFilter {
    $bytes = [byte[]]::new($script:BloomHeader.Length + $script:BloomByteCount)
    [Array]::Copy($script:BloomHeader, 0, $bytes, 0, $script:BloomHeader.Length)
    return ,$bytes
}

function Read-BloomFilter {
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [IO.InvalidDataException]::new('event bloom filter is missing')
    }
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ne $script:BloomHeader.Length + $script:BloomByteCount) {
            throw [IO.InvalidDataException]::new('event bloom filter has an invalid length')
        }
        for ($index = 0; $index -lt $script:BloomHeader.Length; $index++) {
            if ($bytes[$index] -ne $script:BloomHeader[$index]) {
                throw [IO.InvalidDataException]::new('event bloom filter has an invalid header')
            }
        }
        return ,$bytes
    }
    catch {
        throw [IO.InvalidDataException]::new('event bloom filter is invalid')
    }
}

function Get-BloomBitPositions {
    param([Parameter(Mandatory)] [string] $EventId)

    $digest = Get-Sha256DigestBytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($EventId))
    $positions = [System.Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $script:BloomHashCount; $index++) {
        $word = [BitConverter]::ToUInt32($digest, $index * 4)
        [void] $positions.Add([int] ([uint64] $word % [uint64] ($script:BloomByteCount * 8)))
    }
    return @($positions)
}

function Test-BloomEventId {
    param(
        [Parameter(Mandatory)] [byte[]] $Bytes,
        [Parameter(Mandatory)] [string] $EventId
    )

    foreach ($position in @(Get-BloomBitPositions -EventId $EventId)) {
        $byteIndex = $script:BloomHeader.Length + [int][math]::Floor($position / 8.0)
        $mask = [byte] (1 -shl ($position % 8))
        if (($Bytes[$byteIndex] -band $mask) -eq 0) {
            return $false
        }
    }
    return $true
}

function Add-BloomEventId {
    param(
        [Parameter(Mandatory)] [byte[]] $Bytes,
        [Parameter(Mandatory)] [string] $EventId
    )

    foreach ($position in @(Get-BloomBitPositions -EventId $EventId)) {
        $byteIndex = $script:BloomHeader.Length + [int][math]::Floor($position / 8.0)
        $mask = [byte] (1 -shl ($position % 8))
        $Bytes[$byteIndex] = [byte] ($Bytes[$byteIndex] -bor $mask)
    }
}

function Write-BloomFromRecords {
    param(
        [Parameter(Mandatory)] [string] $BloomPath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    $bytes = New-EmptyBloomFilter
    foreach ($record in @($Records)) {
        Add-BloomEventId -Bytes $bytes -EventId ([string] $record.EventId)
    }
    Write-AtomicBytes -Path $BloomPath -Bytes $bytes
    return ,$bytes
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
        [AllowNull()] [long] $EndOffset,
        [AllowNull()] [string] $FrameCommitDigest
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
        frameCommitDigest = $FrameCommitDigest
    }
    Write-AtomicText -Path (Get-EventIndexPath -IndexDirectory $IndexDirectory -EventId $EventId) -Text ($entry | ConvertTo-Json -Compress -Depth 20)
}

function Read-IdentityEntry {
    param(
        [Parameter(Mandatory)] [string] $IdentityDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $path = Get-EventIdentityPath -IdentityDirectory $IdentityDirectory -EventId $EventId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $entry = [IO.File]::ReadAllText($path) | ConvertFrom-Json -DateKind String
        if ($null -eq $entry -or [int] $entry.schemaVersion -ne 1 -or
            [string] $entry.kind -cne 'story_performance_event_identity' -or
            [string] $entry.eventId -cne $EventId -or
            [string] $entry.state -notin @('pending', 'committed', 'conflict') -or
            [string]::IsNullOrWhiteSpace([string] $entry.canonicalJson)) {
            throw [IO.InvalidDataException]::new('event identity entry is invalid')
        }
        return $entry
    }
    catch {
        throw [IO.InvalidDataException]::new('event identity entry is invalid')
    }
}

function Write-IdentityEntry {
    param(
        [Parameter(Mandatory)] [string] $IdentityDirectory,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [ValidateSet('pending', 'committed', 'conflict')] [string] $State,
        [Parameter(Mandatory)] [string] $CanonicalJson,
        [AllowNull()] [int] $LineNumber,
        [AllowNull()] [long] $StartOffset,
        [AllowNull()] [long] $EndOffset,
        [AllowNull()] [string] $FrameCommitDigest
    )

    $entry = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event_identity'
        eventId = $EventId
        state = $State
        canonicalJson = $CanonicalJson
        lineNumber = $LineNumber
        startOffset = $StartOffset
        endOffset = $EndOffset
        frameCommitDigest = $FrameCommitDigest
    }
    Write-AtomicText -Path (Get-EventIdentityPath -IdentityDirectory $IdentityDirectory -EventId $EventId) -Text ($entry | ConvertTo-Json -Compress -Depth 20)
}

function Read-AuthorityEntry {
    param(
        [Parameter(Mandatory)] [string] $AuthorityDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $path = Get-EventAuthorityPath -AuthorityDirectory $AuthorityDirectory -EventId $EventId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $entry = [IO.File]::ReadAllText($path) | ConvertFrom-Json -DateKind String
        if ($null -eq $entry -or [int] $entry.schemaVersion -ne 1 -or
            [string] $entry.kind -cne 'story_performance_event_authority' -or
            [string] $entry.eventId -cne $EventId -or
            [string] $entry.state -notin @('committed', 'conflict') -or
            [string]::IsNullOrWhiteSpace([string] $entry.canonicalJson)) {
            throw [IO.InvalidDataException]::new('event authority entry is invalid')
        }
        return $entry
    }
    catch {
        throw [IO.InvalidDataException]::new('event authority entry is invalid')
    }
}

function Write-AuthorityEntry {
    param(
        [Parameter(Mandatory)] [string] $AuthorityDirectory,
        [Parameter(Mandatory)] [string] $EventId,
        [Parameter(Mandatory)] [ValidateSet('committed', 'conflict')] [string] $State,
        [Parameter(Mandatory)] [string] $CanonicalJson,
        [Parameter(Mandatory)] [int] $LineNumber,
        [Parameter(Mandatory)] [long] $StartOffset,
        [Parameter(Mandatory)] [long] $EndOffset,
        [AllowNull()] [string] $FrameCommitDigest
    )

    $entry = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event_authority'
        eventId = $EventId
        state = $State
        canonicalJson = $CanonicalJson
        lineNumber = $LineNumber
        startOffset = $StartOffset
        endOffset = $EndOffset
        frameCommitDigest = $FrameCommitDigest
    }
    Write-AtomicText -Path (Get-EventAuthorityPath -AuthorityDirectory $AuthorityDirectory -EventId $EventId) -Text ($entry | ConvertTo-Json -Compress -Depth 20)
}

function Read-MembershipMarker {
    param(
        [Parameter(Mandatory)] [string] $MembershipDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $path = Get-EventMembershipPath -MembershipDirectory $MembershipDirectory -EventId $EventId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $marker = [IO.File]::ReadAllText($path) | ConvertFrom-Json -DateKind String
        if ($null -eq $marker -or [int] $marker.schemaVersion -ne 1 -or
            [string] $marker.kind -cne 'story_performance_event_membership' -or
            [string] $marker.eventId -cne $EventId) {
            throw [IO.InvalidDataException]::new('event membership marker is invalid')
        }
        return $marker
    }
    catch {
        throw [IO.InvalidDataException]::new('event membership marker is invalid')
    }
}

function Write-MembershipMarker {
    param(
        [Parameter(Mandatory)] [string] $MembershipDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $marker = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event_membership'
        eventId = $EventId
    }
    Write-AtomicText -Path (Get-EventMembershipPath -MembershipDirectory $MembershipDirectory -EventId $EventId) -Text ($marker | ConvertTo-Json -Compress -Depth 10)
}

function Read-CatalogEntry {
    param(
        [Parameter(Mandatory)] [string] $CatalogDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $path = Get-EventCatalogPath -CatalogDirectory $CatalogDirectory -EventId $EventId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $entry = [IO.File]::ReadAllText($path) | ConvertFrom-Json -DateKind String
        if ($null -eq $entry -or [int] $entry.schemaVersion -ne 1 -or
            [string] $entry.kind -cne 'story_performance_event_catalog' -or
            [string]::IsNullOrWhiteSpace([string] $entry.eventId) -or
            [string] $entry.eventId -match '[\x00-\x1F\x7F]' -or
            [string] $entry.eventId -cne $EventId -or
            [string] $entry.eventIdDigest -cne (Get-Sha256Hex -Text $EventId)) {
            throw [IO.InvalidDataException]::new('event catalog entry is invalid')
        }
        return $entry
    }
    catch {
        throw [IO.InvalidDataException]::new('event catalog entry is invalid')
    }
}

function Write-CatalogEntry {
    param(
        [Parameter(Mandatory)] [string] $CatalogDirectory,
        [Parameter(Mandatory)] [string] $EventId
    )

    $entry = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_event_catalog'
        eventId = $EventId
        eventIdDigest = Get-Sha256Hex -Text $EventId
    }
    Write-AtomicText -Path (Get-EventCatalogPath -CatalogDirectory $CatalogDirectory -EventId $EventId) -Text ($entry | ConvertTo-Json -Compress -Depth 10)
}

function Clear-LedgerCatalog {
    param([Parameter(Mandatory)] [string] $CatalogDirectory)

    [IO.Directory]::CreateDirectory($CatalogDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($CatalogDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Clear-LedgerIntegrity {
    param([Parameter(Mandatory)] [string] $IntegrityDirectory)

    $nodeDirectory = Get-IntegrityNodeDirectory -IntegrityDirectory $IntegrityDirectory
    [IO.Directory]::CreateDirectory($nodeDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($nodeDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Clear-LedgerMembership {
    param([Parameter(Mandatory)] [string] $MembershipDirectory)

    [IO.Directory]::CreateDirectory($MembershipDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($MembershipDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Update-MembershipFromRecords {
    param(
        [Parameter(Mandatory)] [string] $MembershipDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    [IO.Directory]::CreateDirectory($MembershipDirectory) | Out-Null
    foreach ($record in @($Records)) {
        Write-MembershipMarker -MembershipDirectory $MembershipDirectory -EventId ([string] $record.EventId)
    }
}

function Clear-LedgerIndex {
    param([Parameter(Mandatory)] [string] $IndexDirectory)

    [IO.Directory]::CreateDirectory($IndexDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($IndexDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Clear-LedgerIdentity {
    param([Parameter(Mandatory)] [string] $IdentityDirectory)

    [IO.Directory]::CreateDirectory($IdentityDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($IdentityDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Clear-LedgerAuthority {
    param([Parameter(Mandatory)] [string] $AuthorityDirectory)

    [IO.Directory]::CreateDirectory($AuthorityDirectory) | Out-Null
    foreach ($path in @([IO.Directory]::GetFiles($AuthorityDirectory, '*.json'))) {
        [IO.File]::Delete($path)
    }
}

function Update-IndexFromRecords {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [string] $MembershipDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    [IO.Directory]::CreateDirectory($IndexDirectory) | Out-Null
    [IO.Directory]::CreateDirectory($MembershipDirectory) | Out-Null
    foreach ($record in @($Records | Sort-Object LineNumber, StartOffset)) {
        Write-MembershipMarker -MembershipDirectory $MembershipDirectory -EventId ([string] $record.EventId)
        $entry = Read-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId)
        if ($null -eq $entry) {
            Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset) -FrameCommitDigest ([string] $record.CommitDigest)
            continue
        }
        if ([string] $entry.canonicalJson -cne [string] $record.CanonicalJson) {
            Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId) -State conflict -CanonicalJson ([string] $entry.canonicalJson) -LineNumber ([int] $entry.lineNumber) -StartOffset ([long] $entry.startOffset) -EndOffset ([long] $entry.endOffset) -FrameCommitDigest ([string] $entry.frameCommitDigest)
        }
        elseif ([string] $entry.state -eq 'pending') {
            Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset) -FrameCommitDigest ([string] $record.CommitDigest)
        }
    }
}

function Update-IdentityFromRecords {
    param(
        [Parameter(Mandatory)] [string] $IdentityDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    [IO.Directory]::CreateDirectory($IdentityDirectory) | Out-Null
    foreach ($record in @($Records | Sort-Object LineNumber, StartOffset)) {
        $entry = Read-IdentityEntry -IdentityDirectory $IdentityDirectory -EventId ([string] $record.EventId)
        if ($null -eq $entry) {
            Write-IdentityEntry -IdentityDirectory $IdentityDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset) -FrameCommitDigest ([string] $record.CommitDigest)
            continue
        }
        if ([string] $entry.canonicalJson -cne [string] $record.CanonicalJson) {
            Write-IdentityEntry -IdentityDirectory $IdentityDirectory -EventId ([string] $record.EventId) -State conflict -CanonicalJson ([string] $entry.canonicalJson) -LineNumber ([int] $entry.lineNumber) -StartOffset ([long] $entry.startOffset) -EndOffset ([long] $entry.endOffset) -FrameCommitDigest ([string] $entry.frameCommitDigest)
        }
        elseif ([string] $entry.state -eq 'pending') {
            Write-IdentityEntry -IdentityDirectory $IdentityDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset) -FrameCommitDigest ([string] $record.CommitDigest)
        }
    }
}

function Update-AuthorityFromRecords {
    param(
        [Parameter(Mandatory)] [string] $AuthorityDirectory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    [IO.Directory]::CreateDirectory($AuthorityDirectory) | Out-Null
    foreach ($record in @($Records | Sort-Object LineNumber, StartOffset)) {
        $entry = Read-AuthorityEntry -AuthorityDirectory $AuthorityDirectory -EventId ([string] $record.EventId)
        if ($null -eq $entry) {
            Write-AuthorityEntry -AuthorityDirectory $AuthorityDirectory -EventId ([string] $record.EventId) -State committed -CanonicalJson ([string] $record.CanonicalJson) -LineNumber ([int] $record.LineNumber) -StartOffset ([long] $record.StartOffset) -EndOffset ([long] $record.EndOffset) -FrameCommitDigest ([string] $record.CommitDigest)
            continue
        }
        if ([string] $entry.canonicalJson -cne [string] $record.CanonicalJson) {
            Write-AuthorityEntry -AuthorityDirectory $AuthorityDirectory -EventId ([string] $record.EventId) -State conflict -CanonicalJson ([string] $entry.canonicalJson) -LineNumber ([int] $entry.lineNumber) -StartOffset ([long] $entry.startOffset) -EndOffset ([long] $entry.endOffset) -FrameCommitDigest ([string] $entry.frameCommitDigest)
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
        [Parameter(Mandatory)] [long] $PhysicalLength,
        [Parameter(Mandatory)] [string] $IntegrityRootHash,
        [Parameter(Mandatory)] [string] $LedgerPrefixDigest
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
        ledgerPrefixDigest = $LedgerPrefixDigest
        integrityRootHash = $IntegrityRootHash
        updatedAtUtc = Get-UtcNowText
    }
    Write-AtomicText -Path $CheckpointPath -Text ($checkpoint | ConvertTo-Json -Compress -Depth 20)
}

function Test-LedgerCompleteBoundary {
    param(
        [Parameter(Mandatory)] [string] $LedgerPath,
        [Parameter(Mandatory)] [long] $Offset
    )

    if ($Offset -eq 0) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
        return $false
    }
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($LedgerPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        if ($stream.Length -lt $Offset) {
            return $false
        }
        [void] $stream.Seek($Offset - 1, [IO.SeekOrigin]::Begin)
        return $stream.ReadByte() -eq 0x0A
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
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
        $ledgerPrefixDigest = [string] $checkpoint.ledgerPrefixDigest
        $integrityRootHash = [string] $checkpoint.integrityRootHash
        if ([int] $checkpoint.schemaVersion -ne 1 -or
            [string] $checkpoint.kind -cne 'story_performance_ledger_checkpoint' -or
            [string] $checkpoint.runId -cne $ExpectedRunId -or
            [int] $checkpoint.projectId -ne $ExpectedProjectId -or
            [int] $checkpoint.storyId -ne $ExpectedStoryId -or
            [int] $checkpoint.storyRef -ne $ExpectedStoryRef -or
            $lastCompleteOffset -lt 0 -or $checkpointPhysicalLength -lt $lastCompleteOffset -or
            [int] $checkpoint.nextLineNumber -lt 0 -or [long] $checkpoint.recordCount -lt 0 -or
            $ledgerPrefixDigest -notmatch '^[0-9a-f]{64}$' -or
            $integrityRootHash -notmatch '^[0-9a-f]{64}$' -or
            $physicalLength -lt $lastCompleteOffset -or $physicalLength -lt $checkpointPhysicalLength) {
            return $null
        }
        if (-not (Test-LedgerCompleteBoundary -LedgerPath $LedgerPath -Offset $lastCompleteOffset)) {
            return $null
        }
        return [pscustomobject]@{
            LastCompleteOffset = $lastCompleteOffset
            NextLineNumber = [int] $checkpoint.nextLineNumber
            RecordCount = [long] $checkpoint.recordCount
            PhysicalLength = $checkpointPhysicalLength
            LedgerPrefixDigest = $ledgerPrefixDigest
            IntegrityRootHash = $integrityRootHash
            LedgerBytesRead = if ($lastCompleteOffset -gt 0) { 1L } else { 0L }
        }
    }
    catch {
        return $null
    }
}

function Write-IndexFromFullLedger {
    param(
        [Parameter(Mandatory)] [string] $IndexDirectory,
        [Parameter(Mandatory)] [string] $MembershipDirectory,
        [Parameter(Mandatory)] [string] $IdentityDirectory,
        [Parameter(Mandatory)] [string] $AuthorityDirectory,
        [Parameter(Mandatory)] [string] $CatalogDirectory,
        [Parameter(Mandatory)] [object] $LedgerState
    )

    Clear-LedgerIndex -IndexDirectory $IndexDirectory
    Clear-LedgerMembership -MembershipDirectory $MembershipDirectory
    Clear-LedgerIdentity -IdentityDirectory $IdentityDirectory
    Clear-LedgerAuthority -AuthorityDirectory $AuthorityDirectory
    Clear-LedgerCatalog -CatalogDirectory $CatalogDirectory
    $groupsByEventId = [System.Collections.Hashtable]::new([StringComparer]::Ordinal)
    $groupKeyOrder = [System.Collections.Generic.List[string]]::new()
    foreach ($record in @($LedgerState.Records)) {
        $eventId = [string] $record.EventId
        if (-not $groupsByEventId.ContainsKey($eventId)) {
            $groupsByEventId[$eventId] = [System.Collections.Generic.List[object]]::new()
            [void] $groupKeyOrder.Add($eventId)
        }
        [void] $groupsByEventId[$eventId].Add($record)
    }
    foreach ($eventId in $groupKeyOrder) {
        $ordered = @($groupsByEventId[$eventId] | Sort-Object LineNumber, StartOffset)
        $first = $ordered[0]
        $canonicalValues = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($record in $ordered) {
            [void] $canonicalValues.Add([string] $record.CanonicalJson)
        }
        $state = if ($canonicalValues.Count -gt 1) { 'conflict' } else { 'committed' }
        Write-IndexEntry -IndexDirectory $IndexDirectory -EventId ([string] $first.EventId) -State $state -CanonicalJson ([string] $first.CanonicalJson) -LineNumber ([int] $first.LineNumber) -StartOffset ([long] $first.StartOffset) -EndOffset ([long] $first.EndOffset) -FrameCommitDigest ([string] $first.CommitDigest)
        Write-MembershipMarker -MembershipDirectory $MembershipDirectory -EventId ([string] $first.EventId)
        Write-IdentityEntry -IdentityDirectory $IdentityDirectory -EventId ([string] $first.EventId) -State $state -CanonicalJson ([string] $first.CanonicalJson) -LineNumber ([int] $first.LineNumber) -StartOffset ([long] $first.StartOffset) -EndOffset ([long] $first.EndOffset) -FrameCommitDigest ([string] $first.CommitDigest)
        Write-AuthorityEntry -AuthorityDirectory $AuthorityDirectory -EventId ([string] $first.EventId) -State $state -CanonicalJson ([string] $first.CanonicalJson) -LineNumber ([int] $first.LineNumber) -StartOffset ([long] $first.StartOffset) -EndOffset ([long] $first.EndOffset) -FrameCommitDigest ([string] $first.CommitDigest)
        Write-CatalogEntry -CatalogDirectory $CatalogDirectory -EventId ([string] $first.EventId)
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
$membershipDirectory = Get-LedgerMembershipDirectory -LedgerPath $ledgerPath
$identityDirectory = Get-LedgerIdentityDirectory -LedgerPath $ledgerPath
$authorityDirectory = Get-LedgerAuthorityDirectory -LedgerPath $ledgerPath
$catalogDirectory = Get-LedgerCatalogDirectory -LedgerPath $ledgerPath
$integrityDirectory = Get-LedgerIntegrityDirectory -LedgerPath $ledgerPath
$checkpointPath = Get-LedgerCheckpointPath -LedgerPath $ledgerPath
$bloomPath = Get-LedgerBloomPath -LedgerPath $ledgerPath
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
        $membershipDirectory,
        $identityDirectory,
        $authorityDirectory,
        $catalogDirectory,
        $integrityDirectory,
        $checkpointPath,
        $bloomPath
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
$script:IntegrityNodeReadCount = 0L
$script:IntegrityNodeReadBytes = 0L
$script:IntegrityNodeWriteCount = 0L
$script:IntegrityNodeWriteBytes = 0L

try {
    $lock = Acquire-LedgerLock -LedgerPath $ledgerPath -TimeoutMilliseconds $LockTimeoutMilliseconds -ReadyPath $normalizedLockReadyPath
    $ledgerBytesRead = 0L
    $checkpoint = Read-LedgerCheckpoint `
        -CheckpointPath $checkpointPath `
        -LedgerPath $ledgerPath `
        -ExpectedRunId $RunId `
        -ExpectedProjectId ([int] $event.projectId) `
        -ExpectedStoryId ([int] $event.storyId) `
        -ExpectedStoryRef ([int] $event.storyRef)
    if ($null -ne $checkpoint) { $ledgerBytesRead += [long] $checkpoint.LedgerBytesRead }
    $ledgerLengthBeforeFormat = if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) { [IO.FileInfo]::new($ledgerPath).Length } else { 0L }
    $ledgerBytesRead += [long] [Math]::Min($ledgerLengthBeforeFormat, 128KB)
    $ledgerFormat = Get-LedgerFormat -LedgerPath $ledgerPath
    $v2Ledger = $ledgerFormat -ceq 'v2'
    $v2Head = $null
    $v2HeadReadFailed = $false
    if ($v2Ledger) {
        $ledgerHeadReadBytes = [long] [Math]::Min($ledgerLengthBeforeFormat, 128KB)
        try {
            $v2Head = Read-V2LedgerHead `
                -LedgerPath $ledgerPath `
                -ExpectedRunId $RunId `
                -ExpectedProjectId ([int] $event.projectId) `
                -ExpectedStoryId ([int] $event.storyId) `
                -ExpectedStoryRef ([int] $event.storyRef)
        }
        catch [IO.InvalidDataException] {
            $v2HeadReadFailed = $true
        }
        $ledgerBytesRead += $ledgerHeadReadBytes
    }
    $fullRebuild = $null -eq $checkpoint -or
        -not $v2Ledger -or
        $v2HeadReadFailed -or
        ($v2Ledger -and $null -eq $v2Head) -or
        ([long] $checkpoint.RecordCount -gt 0 -and
            (-not (Test-Path -LiteralPath $indexDirectory -PathType Container) -or
             -not (Test-Path -LiteralPath $membershipDirectory -PathType Container) -or
             -not (Test-Path -LiteralPath $identityDirectory -PathType Container) -or
             -not (Test-Path -LiteralPath $authorityDirectory -PathType Container) -or
             -not (Test-Path -LiteralPath $catalogDirectory -PathType Container) -or
             -not (Test-Path -LiteralPath $integrityDirectory -PathType Container)))
    if ($v2Ledger -and $null -ne $v2Head -and $null -ne $checkpoint -and
        ([long] $checkpoint.RecordCount -ne [long] $v2Head.Record.RecordCount -or
         [long] $checkpoint.PhysicalLength -ne [long] $v2Head.PhysicalLength -or
         [string] $checkpoint.IntegrityRootHash -cne [string] $v2Head.Record.IntegrityRootHash -or
         [string] $checkpoint.LedgerPrefixDigest -cne [string] $v2Head.Record.ContentChainDigest)) {
        $fullRebuild = $true
    }
    $bloomBytes = $null
    if (-not $fullRebuild) {
        try {
            $bloomBytes = Read-BloomFilter -Path $bloomPath
        }
        catch [IO.InvalidDataException] {
            $fullRebuild = $true
        }
    }
    $scanStartOffset = if ($fullRebuild) { 0L } elseif ($v2Ledger) { [long] $v2Head.FrameEndOffset } else { [long] $checkpoint.LastCompleteOffset }
    $scanStartLineNumber = if ($fullRebuild) { 0 } else { [int] $checkpoint.NextLineNumber }
    $startingPrefixDigest = if ($fullRebuild) { if ($v2Ledger) { Get-V2GenesisCommitDigest } else { Get-LedgerPrefixDigestSeed } } else { [string] $checkpoint.LedgerPrefixDigest }
    if ($v2Ledger -and $fullRebuild) {
        $ledgerState = Read-V2LedgerFull `
            -LedgerPath $ledgerPath `
            -ExpectedRunId $RunId `
            -ExpectedProjectId ([int] $event.projectId) `
            -ExpectedStoryId ([int] $event.storyId) `
            -ExpectedStoryRef ([int] $event.storyRef)
    }
    elseif ($v2Ledger) {
        $ledgerState = [pscustomobject]@{
            Records = @()
            InvalidRecords = @()
            IncompleteTail = $null
            NeedsSeparator = $false
            StartOffset = [long] $v2Head.FrameEndOffset
            LastCompleteOffset = [long] $v2Head.FrameEndOffset
            NextLineNumber = [int] $checkpoint.NextLineNumber
            PhysicalLength = [long] $v2Head.PhysicalLength
            LedgerPrefixDigest = [string] $v2Head.Record.ContentChainDigest
            ScannedBytes = 0L
            HeadCommitDigest = [string] $v2Head.Record.CommitDigest
            HeadFrameEndOffset = [long] $v2Head.FrameEndOffset
            HeadRecordCount = [long] $v2Head.Record.RecordCount
            HeadIntegrityRootHash = [string] $v2Head.Record.IntegrityRootHash
        }
    }
    else {
        $ledgerState = Read-LedgerChunk `
            -LedgerPath $ledgerPath `
            -StartOffset $scanStartOffset `
            -StartLineNumber $scanStartLineNumber `
            -ExpectedRunId $RunId `
            -ExpectedProjectId ([int] $event.projectId) `
            -ExpectedStoryId ([int] $event.storyId) `
            -ExpectedStoryRef ([int] $event.storyRef) `
            -StartingPrefixDigest $startingPrefixDigest
    }
    $ledgerBytesRead += [long] $ledgerState.ScannedBytes
    $integrityRootHash = Get-IntegrityEmptyHash
    $integrityRootPhysicalLength = if ($v2Ledger) { 0L } else { [long] $ledgerState.PhysicalLength }
    if ($fullRebuild) {
        Write-IndexFromFullLedger -IndexDirectory $indexDirectory -MembershipDirectory $membershipDirectory -IdentityDirectory $identityDirectory -AuthorityDirectory $authorityDirectory -CatalogDirectory $catalogDirectory -LedgerState $ledgerState
        $integrityRootHash = Write-IntegrityFromFullLedger -IntegrityDirectory $integrityDirectory -Records $ledgerState.Records -PhysicalLength $integrityRootPhysicalLength -LedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest) -ExcludePhysicalLength:$v2Ledger
        if ($v2Ledger -and [long] $ledgerState.HeadRecordCount -gt 0 -and [string] $integrityRootHash -cne [string] $ledgerState.HeadIntegrityRootHash) {
            throw [IO.InvalidDataException]::new('v2 ledger integrity root does not rebuild reproducibly')
        }
        $bloomBytes = Write-BloomFromRecords -BloomPath $bloomPath -Records $ledgerState.Records
        $recordCount = [long] $ledgerState.Records.Count
    }
    else {
        try {
            [void] (Read-IntegrityMembership `
                -IntegrityDirectory $integrityDirectory `
                -RootHash ([string] $checkpoint.IntegrityRootHash) `
                -EventId ([string] $event.eventId) `
                -ExpectedRecordCount ([long] $checkpoint.RecordCount) `
                -ExpectedPhysicalLength $integrityRootPhysicalLength `
                -ExpectedLedgerPrefixDigest ([string] $checkpoint.LedgerPrefixDigest))
            $integrityRootHash = Update-IntegrityFromRecords `
                -IntegrityDirectory $integrityDirectory `
                -RootHash ([string] $checkpoint.IntegrityRootHash) `
                -Records $ledgerState.Records `
                -StartingRecordCount ([long] $checkpoint.RecordCount) `
                -FinalRecordCount ([long] $checkpoint.RecordCount + [long] $ledgerState.Records.Count) `
                -FinalPhysicalLength $integrityRootPhysicalLength `
                -FinalLedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest) `
                -ExcludePhysicalLength:$v2Ledger
        }
        catch [IO.InvalidDataException] {
            $fullRebuild = $true
            $scanStartOffset = 0L
            $scanStartLineNumber = 0
            if ($v2Ledger) {
                $ledgerState = Read-V2LedgerFull `
                    -LedgerPath $ledgerPath `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef)
            }
            else {
                $ledgerState = Read-LedgerChunk `
                    -LedgerPath $ledgerPath `
                    -StartOffset $scanStartOffset `
                    -StartLineNumber $scanStartLineNumber `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef) `
                    -StartingPrefixDigest (Get-LedgerPrefixDigestSeed)
            }
            $ledgerBytesRead += [long] $ledgerState.ScannedBytes
            Write-IndexFromFullLedger -IndexDirectory $indexDirectory -MembershipDirectory $membershipDirectory -IdentityDirectory $identityDirectory -AuthorityDirectory $authorityDirectory -CatalogDirectory $catalogDirectory -LedgerState $ledgerState
            $integrityRootPhysicalLength = if ($v2Ledger) { 0L } else { [long] $ledgerState.PhysicalLength }
            $integrityRootHash = Write-IntegrityFromFullLedger -IntegrityDirectory $integrityDirectory -Records $ledgerState.Records -PhysicalLength $integrityRootPhysicalLength -LedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest) -ExcludePhysicalLength:$v2Ledger
            if ($v2Ledger -and [long] $ledgerState.HeadRecordCount -gt 0 -and [string] $integrityRootHash -cne [string] $ledgerState.HeadIntegrityRootHash) {
                throw [IO.InvalidDataException]::new('v2 ledger integrity root does not rebuild reproducibly')
            }
            $bloomBytes = Write-BloomFromRecords -BloomPath $bloomPath -Records $ledgerState.Records
            $recordCount = [long] $ledgerState.Records.Count
        }
        if ($fullRebuild) {
            # The integrity failure branch rebuilt all projections above; do not
            # run the incremental updates a second time.
        }
        else {
        Update-IndexFromRecords -IndexDirectory $indexDirectory -MembershipDirectory $membershipDirectory -Records $ledgerState.Records
        Update-IdentityFromRecords -IdentityDirectory $identityDirectory -Records $ledgerState.Records
        Update-AuthorityFromRecords -AuthorityDirectory $authorityDirectory -Records $ledgerState.Records
        foreach ($record in @($ledgerState.Records)) {
            Write-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $record.EventId)
        }
        foreach ($record in @($ledgerState.Records)) {
            Add-BloomEventId -Bytes $bloomBytes -EventId ([string] $record.EventId)
        }
        if (@($ledgerState.Records).Count -gt 0) {
            Write-AtomicBytes -Path $bloomPath -Bytes $bloomBytes
        }
        $recordCount = [long] $checkpoint.RecordCount + [long] $ledgerState.Records.Count
        }
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
    $indexEntry = $null
    $indexEntryNeedsRebuild = $false
    $identityEntry = $null
    $identityEntryNeedsRepair = $false
    $authorityEntry = $null
    $authorityEntryNeedsRepair = $false
    $pendingClaimNeedsRepair = $false
    $identityConflict = $false
    $membershipMarker = $null
    $membershipMarkerNeedsRepair = $false
    $catalogEntry = $null
    $catalogEntryNeedsRepair = $false
    $integrityMembership = $null
    $integrityNeedsRebuild = $false
    $mutableProjectionLoss = $false
    $bloomMayContainEvent = $false
    if ($foreignRecords.Count -eq 0) {
        try {
            $identityEntry = Read-IdentityEntry -IdentityDirectory $identityDirectory -EventId ([string] $event.eventId)
        }
        catch [IO.InvalidDataException] {
            $identityEntry = $null
            $identityEntryNeedsRepair = $true
        }
        try {
            $authorityEntry = Read-AuthorityEntry -AuthorityDirectory $authorityDirectory -EventId ([string] $event.eventId)
        }
        catch [IO.InvalidDataException] {
            $authorityEntry = $null
            $authorityEntryNeedsRepair = $true
        }
        try {
            $indexEntry = Read-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId)
        }
        catch [IO.InvalidDataException] {
            $indexEntryNeedsRebuild = $true
        }
        try {
            $membershipMarker = Read-MembershipMarker -MembershipDirectory $membershipDirectory -EventId ([string] $event.eventId)
        }
        catch [IO.InvalidDataException] {
            $membershipMarkerNeedsRepair = $true
        }
        try {
            $catalogEntry = Read-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $event.eventId)
        }
        catch [IO.InvalidDataException] {
            $catalogEntryNeedsRepair = $true
        }
        try {
            $integrityMembership = Read-IntegrityMembership `
                -IntegrityDirectory $integrityDirectory `
                -RootHash $integrityRootHash `
                -EventId ([string] $event.eventId) `
                -ExpectedRecordCount ([long] $recordCount) `
                -ExpectedPhysicalLength ([long] $integrityRootPhysicalLength) `
                -ExpectedLedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest)
        }
        catch [IO.InvalidDataException] {
            $integrityMembership = $null
            $integrityNeedsRebuild = $true
        }
        $mutableProjectionLoss = $null -eq $identityEntry -and $null -eq $indexEntry -and $null -eq $membershipMarker
        if (-not $fullRebuild -and -not $indexEntryNeedsRebuild) {
            $bloomMayContainEvent = Test-BloomEventId -Bytes $bloomBytes -EventId ([string] $event.eventId)
        }

        $identityRecord = $null
        $indexRecord = $null
        $authorityRecord = $null
        if ($null -ne $identityEntry -and [string] $identityEntry.state -in @('committed', 'conflict')) {
            try {
                $identityRecord = Read-LedgerRecordAtOffsets `
                    -LedgerPath $ledgerPath `
                    -EventId ([string] $event.eventId) `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef) `
                    -Entry $identityEntry
            }
            catch [IO.InvalidDataException] {
                $ledgerBytesRead += Get-LedgerRangeReadBytes -ErrorRecord $_
                $identityEntry = $null
                $identityEntryNeedsRepair = $true
            }
        }
        if ($null -ne $indexEntry -and [string] $indexEntry.state -in @('committed', 'conflict')) {
            try {
                $indexRecord = Read-LedgerRecordAtOffsets `
                    -LedgerPath $ledgerPath `
                    -EventId ([string] $event.eventId) `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef) `
                    -Entry $indexEntry
            }
            catch [IO.InvalidDataException] {
                $ledgerBytesRead += Get-LedgerRangeReadBytes -ErrorRecord $_
                $indexEntry = $null
                $indexEntryNeedsRebuild = $true
            }
        }
        if ($null -eq $identityRecord -and $null -eq $indexRecord -and $null -ne $authorityEntry) {
            try {
                $authorityRecord = Read-LedgerRecordAtOffsets `
                    -LedgerPath $ledgerPath `
                    -EventId ([string] $event.eventId) `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef) `
                    -Entry $authorityEntry
            }
            catch [IO.InvalidDataException] {
                $ledgerBytesRead += Get-LedgerRangeReadBytes -ErrorRecord $_
                $authorityEntryNeedsRepair = $true
            }
        }
        if ($null -ne $identityRecord) {
            $ledgerBytesRead += [long] $identityRecord.BytesRead
        }
        if ($null -ne $indexRecord) {
            $ledgerBytesRead += [long] $indexRecord.BytesRead
        }
        if ($null -ne $authorityRecord) {
            $ledgerBytesRead += [long] $authorityRecord.BytesRead
        }

        $authoritativeRecord = $identityRecord
        if ($null -eq $authoritativeRecord -or
            ($null -ne $indexRecord -and [long] $indexRecord.StartOffset -lt [long] $authoritativeRecord.StartOffset)) {
            $authoritativeRecord = $indexRecord
        }
        if ($null -ne $authorityRecord -and $null -eq $authoritativeRecord) {
            $authoritativeRecord = $authorityRecord
        }
        if ($null -ne $authoritativeRecord) {
            $authoritativeState = if (($null -ne $authorityEntry -and [string] $authorityEntry.state -eq 'conflict') -or
                ($null -ne $identityEntry -and [string] $identityEntry.state -eq 'conflict') -or
                ($null -ne $indexEntry -and [string] $indexEntry.state -eq 'conflict')) {
                'conflict'
            }
            else {
                'committed'
            }
            Write-AuthorityEntry -AuthorityDirectory $authorityDirectory -EventId ([string] $event.eventId) -State $authoritativeState -CanonicalJson ([string] $authoritativeRecord.CanonicalJson) -LineNumber ([int] $authoritativeRecord.LineNumber) -StartOffset ([long] $authoritativeRecord.StartOffset) -EndOffset ([long] $authoritativeRecord.EndOffset) -FrameCommitDigest ([string] $authoritativeRecord.CommitDigest)
            Write-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId) -State $authoritativeState -CanonicalJson ([string] $authoritativeRecord.CanonicalJson) -LineNumber ([int] $authoritativeRecord.LineNumber) -StartOffset ([long] $authoritativeRecord.StartOffset) -EndOffset ([long] $authoritativeRecord.EndOffset) -FrameCommitDigest ([string] $authoritativeRecord.CommitDigest)
            Write-IdentityEntry -IdentityDirectory $identityDirectory -EventId ([string] $event.eventId) -State $authoritativeState -CanonicalJson ([string] $authoritativeRecord.CanonicalJson) -LineNumber ([int] $authoritativeRecord.LineNumber) -StartOffset ([long] $authoritativeRecord.StartOffset) -EndOffset ([long] $authoritativeRecord.EndOffset) -FrameCommitDigest ([string] $authoritativeRecord.CommitDigest)
            $authorityEntry = Read-AuthorityEntry -AuthorityDirectory $authorityDirectory -EventId ([string] $event.eventId)
            $indexEntry = Read-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId)
            $identityEntry = Read-IdentityEntry -IdentityDirectory $identityDirectory -EventId ([string] $event.eventId)
            $authorityEntryNeedsRepair = $false
            $indexEntryNeedsRebuild = $false
            $identityEntryNeedsRepair = $false
        }
        if ($null -ne $authoritativeRecord -and $null -eq $catalogEntry -and -not $catalogEntryNeedsRepair) {
            Write-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $event.eventId)
            $catalogEntry = Read-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $event.eventId)
        }
        elseif (($null -ne $identityEntry -and [string] $identityEntry.state -eq 'pending') -or
            ($null -ne $indexEntry -and [string] $indexEntry.state -eq 'pending')) {
            $pendingClaimNeedsRepair = $true
        }
        if ($null -ne $indexEntry -and [string] $indexEntry.state -in @('committed', 'conflict') -and
            ($null -eq $membershipMarker -or $membershipMarkerNeedsRepair)) {
            Write-MembershipMarker -MembershipDirectory $membershipDirectory -EventId ([string] $event.eventId)
            $membershipMarker = [pscustomobject]@{ eventId = [string] $event.eventId }
            $membershipMarkerNeedsRepair = $false
        }
        $membershipConfirmsExisting = $null -ne $membershipMarker
        # The Bloom result is only a diagnostic hint. Exact sidecar absence is
        # the bounded negative lookup for an unseen ID; a committed sidecar is
        # accepted only after its stored range is checked against the complete
        # ledger record. A catalog-witnessed ID with no mutable projection is
        # instead cold-rebuilt, which keeps healthy Bloom collisions appendable
        # while making loss, malformed claims, and stale projections explicit.
        if (-not $fullRebuild -and ($integrityNeedsRebuild -or $indexEntryNeedsRebuild -or $identityEntryNeedsRepair -or $authorityEntryNeedsRepair -or $catalogEntryNeedsRepair -or $pendingClaimNeedsRepair -or $membershipMarkerNeedsRepair -or ($null -eq $indexEntry -and $membershipConfirmsExisting) -or ($null -ne $catalogEntry -and $mutableProjectionLoss) -or ($null -ne $integrityMembership -and [bool] $integrityMembership.Present -and $mutableProjectionLoss))) {
            $fullRebuild = $true
            $scanStartOffset = 0L
            $scanStartLineNumber = 0
            if ($v2Ledger) {
                $ledgerState = Read-V2LedgerFull `
                    -LedgerPath $ledgerPath `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef)
            }
            else {
                $ledgerState = Read-LedgerChunk `
                    -LedgerPath $ledgerPath `
                    -StartOffset $scanStartOffset `
                    -StartLineNumber $scanStartLineNumber `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef) `
                    -StartingPrefixDigest (Get-LedgerPrefixDigestSeed)
            }
            $ledgerBytesRead += [long] $ledgerState.ScannedBytes
            Write-IndexFromFullLedger -IndexDirectory $indexDirectory -MembershipDirectory $membershipDirectory -IdentityDirectory $identityDirectory -AuthorityDirectory $authorityDirectory -CatalogDirectory $catalogDirectory -LedgerState $ledgerState
            $integrityRootPhysicalLength = if ($v2Ledger) { 0L } else { [long] $ledgerState.PhysicalLength }
            $integrityRootHash = Write-IntegrityFromFullLedger -IntegrityDirectory $integrityDirectory -Records $ledgerState.Records -PhysicalLength $integrityRootPhysicalLength -LedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest) -ExcludePhysicalLength:$v2Ledger
            if ($v2Ledger -and [long] $ledgerState.HeadRecordCount -gt 0 -and [string] $integrityRootHash -cne [string] $ledgerState.HeadIntegrityRootHash) {
                throw [IO.InvalidDataException]::new('v2 ledger integrity root does not rebuild reproducibly')
            }
            $bloomBytes = Write-BloomFromRecords -BloomPath $bloomPath -Records $ledgerState.Records
            $recordCount = [long] $ledgerState.Records.Count
            $checkpointPhysicalLength = [long] $ledgerState.PhysicalLength
            $checkpointLastCompleteOffset = [long] $ledgerState.LastCompleteOffset
            $checkpointLineNumber = [int] $ledgerState.NextLineNumber
            $foreignRecords = @($ledgerState.InvalidRecords | Where-Object { $_.diagnosticType -ceq 'foreign_run' })
            if ($foreignRecords.Count -eq 0) {
                $identityEntryNeedsRepair = $false
                $authorityEntryNeedsRepair = $false
                $pendingClaimNeedsRepair = $false
                $indexEntry = Read-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId)
                $identityEntry = Read-IdentityEntry -IdentityDirectory $identityDirectory -EventId ([string] $event.eventId)
                $authorityEntry = Read-AuthorityEntry -AuthorityDirectory $authorityDirectory -EventId ([string] $event.eventId)
                $catalogEntry = Read-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $event.eventId)
                 $integrityMembership = Read-IntegrityMembership -IntegrityDirectory $integrityDirectory -RootHash $integrityRootHash -EventId ([string] $event.eventId) -ExpectedRecordCount ([long] $recordCount) -ExpectedPhysicalLength ([long] $integrityRootPhysicalLength) -ExpectedLedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest)
                foreach ($recoveredEntry in @($identityEntry, $indexEntry)) {
                    if ($null -ne $recoveredEntry -and [string] $recoveredEntry.state -in @('committed', 'conflict')) {
                        $recoveredRecord = Read-LedgerRecordAtOffsets `
                            -LedgerPath $ledgerPath `
                            -EventId ([string] $event.eventId) `
                            -ExpectedRunId $RunId `
                            -ExpectedProjectId ([int] $event.projectId) `
                            -ExpectedStoryId ([int] $event.storyId) `
                            -ExpectedStoryRef ([int] $event.storyRef) `
                            -Entry $recoveredEntry
                        $ledgerBytesRead += [long] $recoveredRecord.BytesRead
                    }
                }
            }
        }
    }
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
        $identityUnavailable = -not $fullRebuild -and
            ($identityEntryNeedsRepair -or $authorityEntryNeedsRepair -or $pendingClaimNeedsRepair) -and
            $null -eq $indexEntry -and $null -eq $identityEntry
        if ($identityConflict) {
            $identityDiagnosticPath = Write-Diagnostic `
                -LedgerPath $ledgerPath `
                -RunId $RunId `
                -DiagnosticType 'identity_conflict' `
                -EventId ([string] $event.eventId) `
                -ExistingDigest (Get-Sha256Hex -Text ([string] $identityEntry.canonicalJson)) `
                -IncomingDigest (Get-Sha256Hex -Text ([string] $indexEntry.canonicalJson)) `
                -LineNumber ([int] $indexEntry.lineNumber) `
                -ByteLength $null
            $operationResult = [ordered]@{
                status = 'error'
                errorCategory = 'identity_conflict'
                eventId = [string] $event.eventId
                runId = $RunId
                ledgerPath = $ledgerPath
                diagnosticPath = $identityDiagnosticPath
            }
            $operationExitCode = 2
        }
        elseif ($identityUnavailable) {
            $identityDiagnosticPath = Write-Diagnostic `
                -LedgerPath $ledgerPath `
                -RunId $RunId `
                -DiagnosticType 'identity_unavailable' `
                -EventId ([string] $event.eventId) `
                -ExistingDigest $null `
                -IncomingDigest $incomingDigest `
                -LineNumber $null `
                -ByteLength $null
            $operationResult = [ordered]@{
                status = 'error'
                errorCategory = 'identity_unavailable'
                eventId = [string] $event.eventId
                runId = $RunId
                ledgerPath = $ledgerPath
                diagnosticPath = $identityDiagnosticPath
            }
            $operationExitCode = 2
        }
        elseif ($null -eq $indexEntry -and -not $v2Ledger) {
            Write-IndexEntry -IndexDirectory $indexDirectory -EventId ([string] $event.eventId) -State pending -CanonicalJson $incomingCanonical -LineNumber $null -StartOffset $null -EndOffset $null
            Write-IdentityEntry -IdentityDirectory $identityDirectory -EventId ([string] $event.eventId) -State pending -CanonicalJson $incomingCanonical -LineNumber $null -StartOffset $null -EndOffset $null
            Add-BloomEventId -Bytes $bloomBytes -EventId ([string] $event.eventId)
            Write-AtomicBytes -Path $bloomPath -Bytes $bloomBytes
        }

        if ($null -ne $operationResult) {
        }
        elseif ($null -ne $indexEntry -and [string] $indexEntry.state -eq 'conflict') {
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
            if ($v2Ledger) {
                $currentLength = [long] $ledgerState.PhysicalLength
                $previousFrameEndOffset = if ($fullRebuild) { [long] $ledgerState.HeadFrameEndOffset } else { [long] $v2Head.FrameEndOffset }
                $previousCommitDigest = if ($fullRebuild) { [string] $ledgerState.HeadCommitDigest } else { [string] $v2Head.Record.CommitDigest }
                $previousRecordCount = if ($fullRebuild) { [long] $ledgerState.HeadRecordCount } else { [long] $checkpoint.RecordCount }
                if ($currentLength -gt 0) { $lastByte = (Read-FileByteRange -LedgerPath $ledgerPath -StartOffset ($currentLength - 1))[0]; $ledgerBytesRead++ } else { $lastByte = [byte] 0x0A }
                $prependNewline = $currentLength -gt 0 -and $lastByte -ne [byte] 0x0A
                $orphanBytes = [byte[]]::new(0)
                if ($currentLength -gt $previousFrameEndOffset) {
                    $orphanBytes = Read-FileByteRange -LedgerPath $ledgerPath -StartOffset $previousFrameEndOffset
                    $ledgerBytesRead += [long] $orphanBytes.Length
                }
                if ($prependNewline) {
                    $separatorBytes = [Text.UTF8Encoding]::new($false).GetBytes([Environment]::NewLine)
                    $withSeparator = [byte[]]::new($orphanBytes.Length + $separatorBytes.Length)
                    if ($orphanBytes.Length -gt 0) { [Array]::Copy($orphanBytes, $withSeparator, $orphanBytes.Length) }
                    [Array]::Copy($separatorBytes, 0, $withSeparator, $orphanBytes.Length, $separatorBytes.Length)
                    $orphanBytes = $withSeparator
                }
                if ($orphanBytes.Length -gt $script:LedgerV2MaxOrphanBytes) {
                    throw [IO.InvalidDataException]::new('v2 ledger orphan suffix exceeds the bounded recovery buffer')
                }
                $orphanSuffixDigest = Get-Sha256HexBytes -Bytes $orphanBytes
                $postRecordCount = $previousRecordCount + 1L
                $separatorLength = if ($prependNewline) { [long] ([Text.UTF8Encoding]::new($false).GetByteCount([Environment]::NewLine)) } else { 0L }
                $eventDigest = Get-Sha256Hex -Text $incomingCanonical
                $contentChainDigest = Get-V2ContentChainDigest `
                    -PreviousCommitDigest $previousCommitDigest `
                    -OrphanSuffixDigest $orphanSuffixDigest `
                    -EventDigest $eventDigest `
                    -RecordCount $postRecordCount
                $integrityPlan = Get-IntegrityNodeUpdatePlan `
                    -IntegrityDirectory $integrityDirectory `
                    -NodeHash $integrityRootHash `
                    -EventId ([string] $event.eventId) `
                    -EventIdDigest (Get-Sha256Hex -Text ([string] $event.eventId)) `
                    -Depth 0 `
                    -RootRecordCount $postRecordCount `
                    -RootPhysicalLength 0 `
                    -RootLedgerPrefixDigest $contentChainDigest
                $frameStartOffset = $currentLength + $separatorLength
                $frame = New-V2LedgerFrame `
                    -Event $event `
                    -FrameStartOffset $frameStartOffset `
                    -PreviousFrameEndOffset $previousFrameEndOffset `
                    -PreviousCommitDigest $previousCommitDigest `
                    -OrphanSuffixDigest $orphanSuffixDigest `
                    -ContentChainDigest $contentChainDigest `
                    -RecordCount $postRecordCount `
                    -IntegrityRootHash ([string] $integrityPlan.NodeHash)
                Write-LedgerLine `
                    -LedgerPath $ledgerPath `
                    -Line $frame.Line `
                    -PrependNewline:$prependNewline `
                    -FaultAfterBytes $FaultAfterBytes
                $writtenFrameBytes = Read-FileByteRange -LedgerPath $ledgerPath -StartOffset $frameStartOffset
                $ledgerBytesRead += [long] $writtenFrameBytes.Length
                foreach ($plannedNode in @($integrityPlan.Nodes)) {
                    [void] (Write-IntegrityNode -IntegrityDirectory $integrityDirectory -Payload $plannedNode.Payload)
                }
                $postPhysicalLength = $frameStartOffset + [long] $frame.FrameBytes
                $postRecord = [pscustomobject]@{
                    EventId = [string] $event.eventId
                    CanonicalJson = $incomingCanonical
                    LineNumber = [int] $postRecordCount
                    StartOffset = $frameStartOffset
                    EndOffset = $postPhysicalLength
                    LedgerPrefixDigest = $contentChainDigest
                    CommitDigest = [string] $frame.CommitDigest
                }
                $postWriteState = [pscustomobject]@{
                    Records = @($postRecord)
                    InvalidRecords = @()
                    IncompleteTail = $null
                    NeedsSeparator = $false
                    StartOffset = $frameStartOffset
                    LastCompleteOffset = $postPhysicalLength
                    NextLineNumber = [int] $postRecordCount
                    PhysicalLength = $postPhysicalLength
                    LedgerPrefixDigest = $contentChainDigest
                    ScannedBytes = [long] ($postPhysicalLength - $currentLength)
                }
                $integrityRootHash = [string] $integrityPlan.NodeHash
                Update-IndexFromRecords -IndexDirectory $indexDirectory -MembershipDirectory $membershipDirectory -Records $postWriteState.Records
                Update-IdentityFromRecords -IdentityDirectory $identityDirectory -Records $postWriteState.Records
                Update-AuthorityFromRecords -AuthorityDirectory $authorityDirectory -Records $postWriteState.Records
                Write-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $event.eventId)
                Add-BloomEventId -Bytes $bloomBytes -EventId ([string] $event.eventId)
                Write-AtomicBytes -Path $bloomPath -Bytes $bloomBytes
                Write-LedgerCheckpoint `
                    -CheckpointPath $checkpointPath `
                    -RunId $RunId `
                    -ProjectId ([int] $event.projectId) `
                    -StoryId ([int] $event.storyId) `
                    -StoryRef ([int] $event.storyRef) `
                    -LastCompleteOffset $postPhysicalLength `
                    -NextLineNumber ([int] $postRecordCount) `
                    -RecordCount $postRecordCount `
                    -PhysicalLength $postPhysicalLength `
                    -IntegrityRootHash $integrityRootHash `
                    -LedgerPrefixDigest $contentChainDigest
                $operationResult = [ordered]@{
                    status = 'appended'
                    eventId = [string] $event.eventId
                    runId = $RunId
                    ledgerPath = $ledgerPath
                    recoveredIncompleteTail = $orphanBytes.Length -gt 0
                    scanMode = if ($fullRebuild) { 'cold_rebuild' } else { 'incremental' }
                    scannedBytes = [long] $postWriteState.ScannedBytes
                    checkpointPath = $checkpointPath
                    indexPath = $indexDirectory
                    bloomPath = $bloomPath
                    diagnosticPath = if ($diagnosticPaths.Count -gt 0) { $diagnosticPaths[0] } else { $null }
                }
            }
            else {
                Write-LedgerLine `
                    -LedgerPath $ledgerPath `
                    -Line $serializedEvent `
                    -PrependNewline:([bool] $ledgerState.NeedsSeparator) `
                    -FaultAfterBytes $FaultAfterBytes
                $postStartingRecordCount = if ($fullRebuild) { 0L } else { [long] $checkpoint.RecordCount }
                $postStartingPrefixDigest = if ($fullRebuild) { Get-LedgerPrefixDigestSeed } else { [string] $checkpoint.LedgerPrefixDigest }
                $postWriteState = Read-LedgerChunk `
                    -LedgerPath $ledgerPath `
                    -StartOffset $scanStartOffset `
                    -StartLineNumber $scanStartLineNumber `
                    -ExpectedRunId $RunId `
                    -ExpectedProjectId ([int] $event.projectId) `
                    -ExpectedStoryId ([int] $event.storyId) `
                    -ExpectedStoryRef ([int] $event.storyRef) `
                    -StartingPrefixDigest $postStartingPrefixDigest
                $ledgerBytesRead += [long] $postWriteState.ScannedBytes
                $postRecordCount = if ($fullRebuild) { [long] $postWriteState.Records.Count } else { [long] $checkpoint.RecordCount + [long] $postWriteState.Records.Count }
                $integrityRootHash = Update-IntegrityFromRecords `
                    -IntegrityDirectory $integrityDirectory `
                    -RootHash $integrityRootHash `
                    -Records $postWriteState.Records `
                    -StartingRecordCount $postStartingRecordCount `
                    -FinalRecordCount $postRecordCount `
                    -FinalPhysicalLength ([long] $postWriteState.PhysicalLength) `
                    -FinalLedgerPrefixDigest ([string] $postWriteState.LedgerPrefixDigest)
                Update-IndexFromRecords -IndexDirectory $indexDirectory -MembershipDirectory $membershipDirectory -Records $postWriteState.Records
                Update-IdentityFromRecords -IdentityDirectory $identityDirectory -Records $postWriteState.Records
                Update-AuthorityFromRecords -AuthorityDirectory $authorityDirectory -Records $postWriteState.Records
                foreach ($record in @($postWriteState.Records)) {
                    Write-CatalogEntry -CatalogDirectory $catalogDirectory -EventId ([string] $record.EventId)
                }
                $incomingRecord = @($postWriteState.Records | Where-Object { $_.EventId -ceq [string] $event.eventId } | Select-Object -Last 1)
                if ($incomingRecord.Count -eq 0) {
                    throw [IO.InvalidDataException]::new('appended event was not found in the complete ledger range')
                }
                Write-LedgerCheckpoint `
                    -CheckpointPath $checkpointPath `
                    -RunId $RunId `
                    -ProjectId ([int] $event.projectId) `
                    -StoryId ([int] $event.storyId) `
                    -StoryRef ([int] $event.storyRef) `
                    -LastCompleteOffset ([long] $postWriteState.LastCompleteOffset) `
                    -NextLineNumber ([int] $postWriteState.NextLineNumber) `
                    -RecordCount $postRecordCount `
                    -PhysicalLength ([long] $postWriteState.PhysicalLength) `
                    -IntegrityRootHash $integrityRootHash `
                    -LedgerPrefixDigest ([string] $postWriteState.LedgerPrefixDigest)
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
                    bloomPath = $bloomPath
                    diagnosticPath = if ($diagnosticPaths.Count -gt 0) { $diagnosticPaths[0] } else { $null }
                }
            }
        }
    }
    if ($null -ne $operationResult) {
        $operationResult.scanMode = if ($fullRebuild) { 'cold_rebuild' } else { 'incremental' }
        $operationResult.scannedBytes = if ($operationResult.Contains('scannedBytes')) {
            [long] $operationResult.scannedBytes
        }
        else {
            [long] $ledgerBytesRead
        }
        $operationResult.ledgerReadBytes = [long] $ledgerBytesRead
        $operationResult.bloomMayContainEvent = [bool] $bloomMayContainEvent
        $operationResult.checkpointPath = $checkpointPath
        $operationResult.indexPath = $indexDirectory
        $operationResult.identityPath = $identityDirectory
        $operationResult.authorityPath = $authorityDirectory
        $operationResult.integrityPath = $integrityDirectory
        $operationResult.bloomPath = $bloomPath
        $operationResult.integrityNodeReadCount = [long] $script:IntegrityNodeReadCount
        $operationResult.integrityNodeReadBytes = [long] $script:IntegrityNodeReadBytes
        $operationResult.integrityNodeWriteCount = [long] $script:IntegrityNodeWriteCount
        $operationResult.integrityNodeWriteBytes = [long] $script:IntegrityNodeWriteBytes
    }
    if ($foreignRecords.Count -eq 0 -and ($null -eq $operationResult -or [string] $operationResult.status -ne 'appended')) {
        Write-LedgerCheckpoint `
            -CheckpointPath $checkpointPath `
            -RunId $RunId `
            -ProjectId ([int] $event.projectId) `
            -StoryId ([int] $event.storyId) `
            -StoryRef ([int] $event.storyRef) `
            -LastCompleteOffset ([long] $checkpointLastCompleteOffset) `
            -NextLineNumber $checkpointLineNumber `
            -RecordCount $recordCount `
            -PhysicalLength $checkpointPhysicalLength `
            -IntegrityRootHash $integrityRootHash `
            -LedgerPrefixDigest ([string] $ledgerState.LedgerPrefixDigest)
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
