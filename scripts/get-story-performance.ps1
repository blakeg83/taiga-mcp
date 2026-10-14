<#
.SYNOPSIS
    Aggregate a versioned story performance event ledger.

.DESCRIPTION
    This entry point is deliberately read-only. It consumes the append-only
    JSONL ledger written by write-performance-event.ps1 and emits one
    deterministic story_performance_report object. It does not infer missing
    boundaries, subtract overlapping phases, estimate unavailable usage, or
    read transcripts or source text. Source-backed usage is reconciled only
    from explicit attributable boundary samples. When requested, JSON and
    Markdown artifacts are published atomically to immutable paths outside
    the repository; an existing different artifact is a conflict.
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

    [string] $MarkdownPath,

    [Alias('ReviewedRevision', 'HeadRevision')]
    [string] $ReviewedHead,

    [Alias('BaseSha', 'BaseCommit')]
    [string] $BaseRevision,

    [Alias('RepoPath', 'RepositoryRoot')]
    [string] $RepositoryPath,

    [Alias('SetupMetadataPath', 'AssignmentPath', 'ProfilesPath')]
    [string] $MetadataPath,

    [string] $UsageMetadataPath,

    [string] $CollectionAttemptPath,

    [string] $TaskOutcomePath,

    [Alias('ReportDirectory', 'ArtifactRoot')]
    [string] $ArtifactDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'story-performance-metrics.ps1')

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
$script:SetupMetadataFields = @('role', 'workerId', 'sessionId', 'model', 'effort', 'effectiveFromUtc', 'effectiveToUtc', 'changeId', 'provenance')
$script:SetupMetadataRootFields = @('schemaVersion', 'kind', 'runId', 'projectId', 'storyId', 'profiles', 'provenance')

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

    $runId = [string] (Get-PropertyValue $Event 'runId')
    $projectId = [string] (Get-PropertyValue $Event 'projectId')
    $storyId = [string] (Get-PropertyValue $Event 'storyId')
    $storyRef = [string] (Get-PropertyValue $Event 'storyRef')
    return ConvertTo-IdentityTupleKey $runId $projectId $storyId $storyRef
}

function Get-SafePullRequest {
    param([AllowNull()] [object] $PullRequest)

    if ($null -eq $PullRequest) {
        return $null
    }

    $provider = [string] (Get-PropertyValue $PullRequest 'provider')
    $owner = [string] (Get-PropertyValue $PullRequest 'owner')
    $repository = [string] (Get-PropertyValue $PullRequest 'repository')
    $number = Get-PropertyValue $PullRequest 'number'
    $url = $null
    switch ($provider.ToLowerInvariant()) {
        'github' {
            $url = "https://github.com/$owner/$repository/pull/$number"
        }
        'gitlab' {
            $url = "https://gitlab.com/$owner/$repository/-/merge_requests/$number"
        }
        'bitbucket' {
            $url = "https://bitbucket.org/$owner/$repository/pull-requests/$number"
        }
    }
    return [pscustomobject][ordered]@{
        provider = $provider
        owner = $owner
        repository = $repository
        number = $number
        url = $url
        reviewedHead = ([string] (Get-PropertyValue $PullRequest 'reviewedHead')).ToLowerInvariant()
    }
}

function Get-ValidatedSetupProvenance {
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Context
    )

    if ($null -eq $Value -or $Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw [System.ArgumentException]::new("setup_metadata_invalid: $Context.provenance must be an object")
    }
    $unknown = Get-UnknownPropertyName -Object $Value -Allowed $script:ProvenanceFields
    if ($null -ne $unknown) {
        throw [System.ArgumentException]::new("setup_metadata_invalid: unknown $Context.provenance field '$unknown'")
    }
    foreach ($name in @('source', 'coverage')) {
        if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $Value $name))) {
            throw [System.ArgumentException]::new("setup_metadata_invalid: $Context.provenance.$name must be a nonblank safe string")
        }
    }
    if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $Value 'observedBy')) -and
        -not (Test-NonBlankSafeString -Value (Get-PropertyValue $Value 'observer'))) {
        throw [System.ArgumentException]::new("setup_metadata_invalid: $Context.provenance requires observedBy or observer")
    }
    $synthetic = Get-PropertyValue $Value 'synthetic'
    if ($null -ne $synthetic -and $synthetic -isnot [bool]) {
        throw [System.ArgumentException]::new("setup_metadata_invalid: $Context.provenance.synthetic must be Boolean or null")
    }
    $result = [ordered]@{
        source = [string] (Get-PropertyValue $Value 'source')
        coverage = [string] (Get-PropertyValue $Value 'coverage')
    }
    foreach ($name in @('observedBy', 'observer', 'synthetic')) {
        if (Test-PropertyPresent -Object $Value -Name $name) {
            $result[$name] = Get-PropertyValue $Value $name
        }
    }
    return [pscustomobject] $result
}

function Get-SetupMetadata {
    param(
        [AllowNull()] [string] $Path,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [int] $ProjectId,
        [Parameter(Mandatory)] [int] $StoryId
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [pscustomobject][ordered]@{
            state = 'unavailable'
            records = @()
            source = 'setup assignment metadata'
            coverage = 'no metadata input supplied'
            missingData = 'validated role/model/effort metadata was not supplied'
        }
    }

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not [IO.File]::Exists($fullPath)) {
        throw [System.ArgumentException]::new('setup_metadata_invalid: metadata input file was not found')
    }
    try {
        $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
        $metadataJsonText = [IO.File]::ReadAllText($fullPath, $strictUtf8)
        $root = $metadataJsonText | ConvertFrom-Json -Depth 100 -DateKind String
        $jsonDocument = [Text.Json.JsonDocument]::Parse($metadataJsonText)
        try {
            $profilesWasArray = $jsonDocument.RootElement.GetProperty('profiles').ValueKind -eq [Text.Json.JsonValueKind]::Array
        }
        finally {
            $jsonDocument.Dispose()
        }
    }
    catch {
        throw [System.ArgumentException]::new('setup_metadata_invalid: metadata input is not valid UTF-8 JSON')
    }
    if ($null -eq $root -or $root -isnot [System.Management.Automation.PSCustomObject]) {
        throw [System.ArgumentException]::new('setup_metadata_invalid: metadata root must be an object')
    }
    $unknown = Get-UnknownPropertyName -Object $root -Allowed $script:SetupMetadataRootFields
    if ($null -ne $unknown) {
        throw [System.ArgumentException]::new("setup_metadata_invalid: unknown metadata field '$unknown'")
    }
    foreach ($name in $script:SetupMetadataRootFields) {
        if (-not (Test-PropertyPresent -Object $root -Name $name)) {
            throw [System.ArgumentException]::new("setup_metadata_invalid: metadata field '$name' is required")
        }
    }
    if (-not (Test-PositiveIntegerValue -Value (Get-PropertyValue $root 'schemaVersion')) -or
        [int] (Get-PropertyValue $root 'schemaVersion') -ne 1) {
        throw [System.ArgumentException]::new('setup_metadata_invalid: schemaVersion must be 1')
    }
    if ([string] (Get-PropertyValue $root 'kind') -cne 'story_performance_setup') {
        throw [System.ArgumentException]::new('setup_metadata_invalid: kind must be story_performance_setup')
    }
    $metadataRunId = Get-PropertyValue $root 'runId'
    $metadataProjectId = Get-PropertyValue $root 'projectId'
    $metadataStoryId = Get-PropertyValue $root 'storyId'
    if (-not (Test-NonBlankSafeString -Value $metadataRunId) -or
        -not (Test-PositiveIntegerValue -Value $metadataProjectId) -or
        [decimal] $metadataProjectId -gt [int]::MaxValue -or
        -not (Test-PositiveIntegerValue -Value $metadataStoryId) -or
        [decimal] $metadataStoryId -gt [int]::MaxValue) {
        throw [System.ArgumentException]::new('setup_metadata_invalid: runId, projectId, and storyId must be a safe run ID and positive 32-bit integers')
    }
    if ([string] $metadataRunId -cne $RunId -or
        [int] $metadataProjectId -ne $ProjectId -or
        [int] $metadataStoryId -ne $StoryId) {
        throw [System.ArgumentException]::new('setup_metadata_conflict: metadata run/project/story identity does not match the event ledger')
    }
    $rootProvenance = Get-ValidatedSetupProvenance -Value (Get-PropertyValue $root 'provenance') -Context 'metadata'
    $profilesProperty = $root.PSObject.Properties['profiles']
    $profiles = if ($null -eq $profilesProperty) { $null } else { $profilesProperty.Value }
    if (-not $profilesWasArray) {
        throw [System.ArgumentException]::new('setup_metadata_invalid: profiles must be a nonempty array')
    }
    if ($null -ne $profiles -and $profiles -isnot [System.Array]) {
        $profiles = @($profiles)
    }
    if ($null -eq $profiles -or $profiles.Count -eq 0) {
        throw [System.ArgumentException]::new('setup_metadata_invalid: profiles must be a nonempty array')
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($profile in @($profiles)) {
        if ($null -eq $profile -or $profile -isnot [System.Management.Automation.PSCustomObject]) {
            throw [System.ArgumentException]::new('setup_metadata_invalid: each profile must be an object')
        }
        $unknown = Get-UnknownPropertyName -Object $profile -Allowed $script:SetupMetadataFields
        if ($null -ne $unknown) {
            throw [System.ArgumentException]::new("setup_metadata_invalid: unknown profile field '$unknown'")
        }
        foreach ($name in @('role', 'workerId', 'model', 'effort', 'effectiveFromUtc', 'provenance')) {
            if (-not (Test-PropertyPresent -Object $profile -Name $name)) {
                throw [System.ArgumentException]::new("setup_metadata_invalid: profile field '$name' is required")
            }
        }
        $role = [string] (Get-PropertyValue $profile 'role')
        if ($role -notin @('coordinator', 'implementer', 'reviewer')) {
            throw [System.ArgumentException]::new('setup_metadata_invalid: profile.role is unsupported')
        }
        foreach ($name in @('workerId', 'model', 'effort')) {
            if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $profile $name))) {
                throw [System.ArgumentException]::new("setup_metadata_invalid: profile.$name must be a nonblank safe string")
            }
        }
        foreach ($name in @('sessionId', 'changeId')) {
            $value = Get-PropertyValue $profile $name
            if ($null -ne $value -and -not (Test-NonBlankSafeString -Value $value)) {
                throw [System.ArgumentException]::new("setup_metadata_invalid: profile.$name must be null or a nonblank safe string")
            }
        }
        $start = [DateTimeOffset]::MinValue
        if (-not (Try-GetUtcTime -Value (Get-PropertyValue $profile 'effectiveFromUtc') -Parsed ([ref] $start))) {
            throw [System.ArgumentException]::new('setup_metadata_invalid: profile.effectiveFromUtc must be a UTC timestamp')
        }
        $end = $null
        $endValue = Get-PropertyValue $profile 'effectiveToUtc'
        if ($null -ne $endValue) {
            $parsedEnd = [DateTimeOffset]::MinValue
            if (-not (Try-GetUtcTime -Value $endValue -Parsed ([ref] $parsedEnd)) -or $parsedEnd -lt $start) {
                throw [System.ArgumentException]::new('setup_metadata_invalid: profile.effectiveToUtc must be a UTC timestamp after effectiveFromUtc')
            }
            $end = [string] $endValue
        }
        $profileProvenance = Get-ValidatedSetupProvenance -Value (Get-PropertyValue $profile 'provenance') -Context 'profile'
        $record = [ordered]@{
            role = $role
            workerId = [string] (Get-PropertyValue $profile 'workerId')
            sessionId = Get-PropertyValue $profile 'sessionId'
            model = [string] (Get-PropertyValue $profile 'model')
            effort = [string] (Get-PropertyValue $profile 'effort')
            effectiveFromUtc = [string] (Get-PropertyValue $profile 'effectiveFromUtc')
            effectiveToUtc = $end
            changeId = Get-PropertyValue $profile 'changeId'
            provenance = $profileProvenance
        }
        [void] $records.Add([pscustomobject] $record)
    }
    $profileConflicts = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @(Group-ValuesLinear -Values @($records) -KeySelector {
                param($record)
                ConvertTo-IdentityTupleKey $record.role $record.workerId $record.sessionId
            })) {
        $orderedItems = @($group.Group | ForEach-Object {
                [pscustomobject]@{
                    profile = $_
                    start = [DateTimeOffset]::Parse([string] $_.effectiveFromUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                    end = if ([string]::IsNullOrWhiteSpace([string] $_.effectiveToUtc)) { [DateTimeOffset]::MaxValue } else { [DateTimeOffset]::Parse([string] $_.effectiveToUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
                }
            })
        $ordered = @(Sort-TimeWindowItemsLinear -Items $orderedItems)
        $cluster = [System.Collections.Generic.List[object]]::new()
        $clusterEnd = [DateTimeOffset]::MinValue
        $flush = {
            if ($cluster.Count -le 1) { return }
            $profiles = @($cluster | ForEach-Object { $_.profile })
            $signatures = @(Get-UniqueValuesLinear -Values @($profiles | ForEach-Object {
                        ConvertTo-IdentityTupleKey $_.model $_.effort
                    }))
            if ($signatures.Count -gt 1) {
                [void] $profileConflicts.Add([pscustomobject][ordered]@{
                        identity = "$($profiles[0].role)/$($profiles[0].workerId)/$($profiles[0].sessionId)"
                        leftChange = $profiles[0].changeId
                        rightChange = $profiles[-1].changeId
                    })
            }
        }
        foreach ($item in $ordered) {
            if ($cluster.Count -gt 0 -and $item.start -ge $clusterEnd) {
                & $flush
                $cluster = [System.Collections.Generic.List[object]]::new()
                $clusterEnd = [DateTimeOffset]::MinValue
            }
            [void] $cluster.Add($item)
            if ($item.end -gt $clusterEnd) { $clusterEnd = $item.end }
        }
        & $flush
    }
    if ($profileConflicts.Count -gt 0) {
        throw [System.InvalidOperationException]::new('setup_metadata_conflict: overlapping profile intervals disagree for the same role, worker, and session')
    }

    $requiredRoles = @('coordinator', 'implementer', 'reviewer')
    $presentRoles = @(Get-UniqueValuesLinear -Values @($records | ForEach-Object { [string] $_.role }))
    $missingRoles = @($requiredRoles | Where-Object { $_ -notin $presentRoles })
    $coverage = "validated $($records.Count) role profile record(s), including explicit changes"
    $missingData = $null
    $state = 'measured'
    if ($missingRoles.Count -gt 0) {
        $state = 'partial'
        $coverage = "$coverage; missing validated role profile(s): $($missingRoles -join ', ')"
        $missingData = "validated profile evidence is unavailable for role(s): $($missingRoles -join ', ')"
    }

    return [pscustomobject][ordered]@{
        state = $state
        records = @($records)
        source = [string] (Get-PropertyValue $rootProvenance 'source')
        coverage = $coverage
        missingData = $missingData
        missingRoles = @($missingRoles)
        provenance = $rootProvenance
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
            if (-not (Test-NonBlankSafeString -Value (Get-PropertyValue $pullRequest $name)) -or
                [string] (Get-PropertyValue $pullRequest $name) -match '\s') {
                return "pullRequest.$name is required"
            }
        }
        if (-not (Test-PositiveIntegerValue -Value (Get-PropertyValue $pullRequest 'number')) -or
            -not (Test-FullRevision -Value (Get-PropertyValue $pullRequest 'reviewedHead')) -or
            [string] (Get-PropertyValue $pullRequest 'reviewedHead') -ine [string] $revision) {
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

function New-OrdinalHashtable {
    return [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
}

function ConvertTo-IdentityTupleKey {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)] [AllowNull()] [AllowEmptyCollection()] [object[]] $Values
    )

    $normalized = [System.Collections.Generic.List[object]]::new()
    foreach ($value in $Values) {
        if ($null -eq $value) {
            [void] $normalized.Add($null)
        }
        else {
            [void] $normalized.Add([string] $value)
        }
    }
    return ConvertTo-CanonicalJson -Value $normalized
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

function Sort-RecordsByTimeLinear {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records)

    if ($Records.Count -le 1) {
        return @($Records)
    }

    # Records arrive from the ledger in physical line order. A stable eight-pass
    # radix sort of the nonnegative UTC tick value therefore preserves line order
    # for equal timestamps without a comparison sort.
    $source = [object[]] @($Records)
    $target = [object[]]::new($source.Length)
    for ($pass = 0; $pass -lt 8; $pass++) {
        $counts = [int[]]::new(256)
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $bucket = [int] ((([uint64] $source[$itemIndex].Time.Ticks) -shr ($pass * 8)) -band [uint64] 0xFF)
            $counts[$bucket]++
        }
        $positions = [int[]]::new(256)
        for ($bucket = 1; $bucket -lt 256; $bucket++) {
            $positions[$bucket] = $positions[$bucket - 1] + $counts[$bucket - 1]
        }
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $bucket = [int] ((([uint64] $source[$itemIndex].Time.Ticks) -shr ($pass * 8)) -band [uint64] 0xFF)
            $target[$positions[$bucket]] = $source[$itemIndex]
            $positions[$bucket]++
        }
        $temporary = $source
        $source = $target
        $target = $temporary
    }
    return @($source)
}

function Sort-RecordsByLineLinear {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records)

    if ($Records.Count -le 1) {
        return @($Records)
    }

    # Line numbers are nonnegative 32-bit values. Fixed four-pass radix sorting
    # keeps the original physical order for equal keys in linear time.
    $source = [object[]] @($Records)
    $target = [object[]]::new($source.Length)
    for ($pass = 0; $pass -lt 4; $pass++) {
        $counts = [int[]]::new(256)
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $bucket = [int] ((([uint64] $source[$itemIndex].Line) -shr ($pass * 8)) -band [uint64] 0xFF)
            $counts[$bucket]++
        }
        $positions = [int[]]::new(256)
        for ($bucket = 1; $bucket -lt 256; $bucket++) {
            $positions[$bucket] = $positions[$bucket - 1] + $counts[$bucket - 1]
        }
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $bucket = [int] ((([uint64] $source[$itemIndex].Line) -shr ($pass * 8)) -band [uint64] 0xFF)
            $target[$positions[$bucket]] = $source[$itemIndex]
            $positions[$bucket]++
        }
        $temporary = $source
        $source = $target
        $target = $temporary
    }
    return @($source)
}

function Sort-UsageSamplesLinear {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Samples)

    if ($Samples.Count -le 1) {
        return @($Samples)
    }

    # LSD passes sort the secondary physical line key first and the primary
    # sampledAtUtc key second. The result is sampleTime, then ledger line.
    $source = [object[]] @($Samples)
    $target = [object[]]::new($source.Length)
    for ($pass = 0; $pass -lt 12; $pass++) {
        $counts = [int[]]::new(256)
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $value = if ($pass -lt 4) { [uint64] $source[$itemIndex].record.Line } else { [uint64] $source[$itemIndex].sampleTime.Ticks }
            $shift = if ($pass -lt 4) { $pass * 8 } else { ($pass - 4) * 8 }
            $bucket = [int] (($value -shr $shift) -band [uint64] 0xFF)
            $counts[$bucket]++
        }
        $positions = [int[]]::new(256)
        for ($bucket = 1; $bucket -lt 256; $bucket++) {
            $positions[$bucket] = $positions[$bucket - 1] + $counts[$bucket - 1]
        }
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $value = if ($pass -lt 4) { [uint64] $source[$itemIndex].record.Line } else { [uint64] $source[$itemIndex].sampleTime.Ticks }
            $shift = if ($pass -lt 4) { $pass * 8 } else { ($pass - 4) * 8 }
            $bucket = [int] (($value -shr $shift) -band [uint64] 0xFF)
            $target[$positions[$bucket]] = $source[$itemIndex]
            $positions[$bucket]++
        }
        $temporary = $source
        $source = $target
        $target = $temporary
    }
    return @($source)
}

function Sort-UsageRangeItemsLinear {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Items,
        [Parameter(Mandatory)] [ValidateSet('start', 'end', 'startTime', 'endTime')] [string] $TimeProperty
    )

    if ($Items.Count -le 1) {
        return @($Items)
    }

    $source = [object[]] @($Items)
    $target = [object[]]::new($source.Length)
    for ($pass = 0; $pass -lt 8; $pass++) {
        $counts = [int[]]::new(256)
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $value = [uint64] $source[$itemIndex].$TimeProperty.Ticks
            $bucket = [int] (($value -shr ($pass * 8)) -band [uint64] 0xFF)
            $counts[$bucket]++
        }
        $positions = [int[]]::new(256)
        for ($bucket = 1; $bucket -lt 256; $bucket++) {
            $positions[$bucket] = $positions[$bucket - 1] + $counts[$bucket - 1]
        }
        for ($itemIndex = 0; $itemIndex -lt $source.Length; $itemIndex++) {
            $value = [uint64] $source[$itemIndex].$TimeProperty.Ticks
            $bucket = [int] (($value -shr ($pass * 8)) -band [uint64] 0xFF)
            $target[$positions[$bucket]] = $source[$itemIndex]
            $positions[$bucket]++
        }
        $temporary = $source
        $source = $target
        $target = $temporary
    }
    return @($source)
}

function Sort-TimeWindowItemsLinear {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Items)

    if ($Items.Count -le 1) {
        return @($Items)
    }

    # Stable LSD ordering makes start the primary key and end the secondary
    # key with two fixed-pass radix sweeps and no comparison sort.
    $byEnd = @(Sort-UsageRangeItemsLinear -Items $Items -TimeProperty 'end')
    return Sort-UsageRangeItemsLinear -Items $byEnd -TimeProperty 'start'
}

function Get-UniqueValuesLinear {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Values)

    $seen = New-OrdinalHashtable
    $unique = [System.Collections.Generic.List[object]]::new()
    foreach ($value in $Values) {
        $key = [string] $value
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void] $unique.Add($value)
        }
    }
    return @($unique)
}

function Group-ValuesLinear {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Values,
        [Parameter(Mandatory)] [scriptblock] $KeySelector
    )

    $buckets = New-OrdinalHashtable
    $keyOrder = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        $key = [string] (& $KeySelector $value)
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = [System.Collections.Generic.List[object]]::new()
            [void] $keyOrder.Add($key)
        }
        [void] $buckets[$key].Add($value)
    }
    foreach ($key in $keyOrder) {
        [pscustomobject][ordered]@{
            Name = $key
            Group = @($buckets[$key])
        }
    }
}

function Get-TaskText {
    param([AllowNull()] [object] $Event)

    $taskRef = Get-PropertyValue -Object $Event -Name 'taskRef'
    if ($null -eq $taskRef) {
        return $null
    }
    return [string] $taskRef
}

function Get-IdentityText {
    param(
        [Parameter(Mandatory)] [object] $Event,
        [Parameter(Mandatory)] [string] $Name
    )

    $value = Get-PropertyValue $Event $Name
    if ($null -eq $value) {
        return $null
    }
    return [string] $value
}

function Get-PhaseIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = Get-IdentityText -Event $Event -Name 'scope'
    $task = Get-TaskText -Event $Event
    $phase = Get-IdentityText -Event $Event -Name 'phaseId'
    $correction = Get-IdentityText -Event $Event -Name 'correctionId'
    return ConvertTo-IdentityTupleKey $scope $task $phase $correction
}

function Get-WaitIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = Get-IdentityText -Event $Event -Name 'scope'
    $task = Get-TaskText -Event $Event
    $waitId = Get-IdentityText -Event $Event -Name 'waitId'
    return ConvertTo-IdentityTupleKey $scope $task $waitId
}

function Get-ReviewIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = Get-IdentityText -Event $Event -Name 'scope'
    $task = Get-TaskText -Event $Event
    $phase = Get-IdentityText -Event $Event -Name 'phaseId'
    $request = Get-IdentityText -Event $Event -Name 'reviewRequestId'
    $attempt = Get-IdentityText -Event $Event -Name 'reviewAttemptId'
    $ordinal = Get-IdentityText -Event $Event -Name 'reviewAttemptOrdinal'
    $kind = Get-IdentityText -Event $Event -Name 'reviewKind'
    $revision = Get-IdentityText -Event $Event -Name 'revision'
    return ConvertTo-IdentityTupleKey $scope $task $phase $request $attempt $ordinal $kind $revision
}

function Get-ReviewAttemptIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = Get-IdentityText -Event $Event -Name 'scope'
    $task = Get-TaskText -Event $Event
    $request = Get-IdentityText -Event $Event -Name 'reviewRequestId'
    $attempt = Get-IdentityText -Event $Event -Name 'reviewAttemptId'
    return ConvertTo-IdentityTupleKey $scope $task $request $attempt
}

function Get-ReviewAttemptBindingIdentity {
    param([Parameter(Mandatory)] [object] $Event)

    $scope = Get-IdentityText -Event $Event -Name 'scope'
    $task = Get-TaskText -Event $Event
    $attempt = Get-IdentityText -Event $Event -Name 'reviewAttemptId'
    return ConvertTo-IdentityTupleKey $scope $task $attempt
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
        [Parameter(Mandatory)] [object] $Value,
        [AllowNull()] [System.Collections.Generic.List[string]] $KeyOrder,
        [AllowNull()] [object] $KeySeen
    )

    if (-not $Index.ContainsKey($Key)) {
        $Index[$Key] = [System.Collections.ArrayList]::new()
        if ($null -ne $KeyOrder -and $null -ne $KeySeen -and $KeySeen.Add($Key)) {
            [void] $KeyOrder.Add($Key)
        }
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
        startEventId = if ($null -ne $start) { $start.EventId } else { $null }
        endEventId = if ($null -ne $end) { $end.EventId } else { $null }
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
    if ($null -ne $script:IntervalKeyOrder) {
        foreach ($key in $script:IntervalKeyOrder) {
            [void] $keys.Add([string] $key)
        }
    }
    else {
        $fallbackKeySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($key in $Starts.Keys) {
            $text = [string] $key
            if ($fallbackKeySeen.Add($text)) {
                [void] $keys.Add($text)
            }
        }
        foreach ($key in $Ends.Keys) {
            $text = [string] $key
            if ($fallbackKeySeen.Add($text)) {
                [void] $keys.Add($text)
            }
        }
    }
    $keys = @($keys)
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

    $orderedItems = @($Intervals | Where-Object { $_.state -eq 'measured' -and $null -ne $_.startUtc -and $null -ne $_.endUtc } | ForEach-Object {
            [pscustomobject]@{
                interval = $_
                start = [DateTimeOffset]::Parse([string] $_.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                end = [DateTimeOffset]::Parse([string] $_.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            }
        } | Where-Object { $_.start -lt $_.end })
    $ordered = @(Sort-TimeWindowItemsLinear -Items $orderedItems)
    $cluster = [System.Collections.Generic.List[object]]::new()
    $clusterEnd = [DateTimeOffset]::MinValue
    foreach ($item in $ordered) {
        if ($cluster.Count -gt 0 -and $item.start -ge $clusterEnd) {
            if ($cluster.Count -gt 1) {
                $identity = @($cluster | ForEach-Object { [string] $_.interval.identity }) -join '|'
                [void] $Anomalies.Add((New-Anomaly -Code 'overlapping_intervals' -Message 'Valid phase intervals overlap; totals remain separate and are not made additive wall-clock time' -Identity $identity))
            }
            $cluster = [System.Collections.Generic.List[object]]::new()
            $clusterEnd = [DateTimeOffset]::MinValue
        }
        [void] $cluster.Add($item)
        if ($item.end -gt $clusterEnd) {
            $clusterEnd = $item.end
        }
    }
    if ($cluster.Count -gt 1) {
        $identity = @($cluster | ForEach-Object { [string] $_.interval.identity }) -join '|'
        [void] $Anomalies.Add((New-Anomaly -Code 'overlapping_intervals' -Message 'Valid phase intervals overlap; totals remain separate and are not made additive wall-clock time' -Identity $identity))
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
    $segmentItems = @($Intervals | Where-Object { $_.state -eq 'measured' -and $null -ne $_.startUtc -and $null -ne $_.endUtc } | ForEach-Object {
        $start = [DateTimeOffset]::Parse([string] $_.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $end = [DateTimeOffset]::Parse([string] $_.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($end -gt $spanStart -and $start -lt $spanEnd) {
            [pscustomobject]@{
                start = if ($start -lt $spanStart) { $spanStart } else { $start }
                end = if ($end -gt $spanEnd) { $spanEnd } else { $end }
            }
        }
    })
    $segments = @(Sort-TimeWindowItemsLinear -Items $segmentItems)

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

function Get-Sha256HexBytes {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes)

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($hasher.ComputeHash($Bytes)).ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

function Get-V2ContentChainDigest {
    param(
        [Parameter(Mandatory)] [string] $PreviousCommitDigest,
        [Parameter(Mandatory)] [string] $OrphanSuffixDigest,
        [Parameter(Mandatory)] [string] $EventDigest,
        [Parameter(Mandatory)] [long] $RecordCount
    )

    return Get-Sha256Hex -Content ("story_performance_ledger_v2_chain_v1|$PreviousCommitDigest|$OrphanSuffixDigest|$EventDigest|$RecordCount")
}

function Get-V2FrameValidationError {
    param(
        [Parameter(Mandatory)] [object] $Frame,
        [Parameter(Mandatory)] [string] $Line,
        [Parameter(Mandatory)] [long] $FrameStartOffset,
        [Parameter(Mandatory)] [long] $FrameEndOffset,
        [Parameter(Mandatory)] [long] $PreviousFrameEndOffset,
        [Parameter(Mandatory)] [string] $PreviousCommitDigest,
        [Parameter(Mandatory)] [long] $PreviousRecordCount,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $OrphanBytes
    )

    try {
        if ([int] (Get-PropertyValue $Frame 'schemaVersion') -ne 2 -or
            [string] (Get-PropertyValue $Frame 'kind') -cne 'story_performance_event_frame') { return 'unsupported v2 frame envelope' }
        $event = Get-PropertyValue $Frame 'event'
        $anchor = Get-PropertyValue $Frame 'anchor'
        if ($null -eq $event -or $null -eq $anchor) { return 'v2 frame event or anchor is missing' }
        $eventDigest = Get-Sha256Hex -Content (ConvertTo-CanonicalJson -Value $event)
        $anchorPayload = [ordered]@{
            schemaVersion = [int] (Get-PropertyValue $anchor 'schemaVersion')
            kind = [string] (Get-PropertyValue $anchor 'kind')
            frameStartOffset = [long] (Get-PropertyValue $anchor 'frameStartOffset')
            previousFrameEndOffset = [long] (Get-PropertyValue $anchor 'previousFrameEndOffset')
            previousCommitDigest = [string] (Get-PropertyValue $anchor 'previousCommitDigest')
            orphanSuffixDigest = [string] (Get-PropertyValue $anchor 'orphanSuffixDigest')
            eventDigest = [string] (Get-PropertyValue $anchor 'eventDigest')
            contentChainDigest = [string] (Get-PropertyValue $anchor 'contentChainDigest')
            recordCount = [long] (Get-PropertyValue $anchor 'recordCount')
            integrityRootHash = [string] (Get-PropertyValue $anchor 'integrityRootHash')
            frameByteLength = [long] (Get-PropertyValue $anchor 'frameByteLength')
        }
        foreach ($digest in @($anchorPayload.previousCommitDigest, $anchorPayload.orphanSuffixDigest, $anchorPayload.eventDigest, $anchorPayload.contentChainDigest, $anchorPayload.integrityRootHash, [string] (Get-PropertyValue $anchor 'commitDigest'))) {
            if ($digest -notmatch '^[0-9a-f]{64}$') { return 'v2 frame digest is invalid' }
        }
        if ($anchorPayload.kind -cne 'story_performance_ledger_commit' -or
            $anchorPayload.schemaVersion -ne 2 -or
            $anchorPayload.frameStartOffset -ne $FrameStartOffset -or
            $anchorPayload.previousFrameEndOffset -ne $PreviousFrameEndOffset -or
            $anchorPayload.previousCommitDigest -cne $PreviousCommitDigest -or
            $anchorPayload.recordCount -ne ($PreviousRecordCount + 1L) -or
            $anchorPayload.frameByteLength -ne ($FrameEndOffset - $FrameStartOffset) -or
            $anchorPayload.frameByteLength -ne ([Text.UTF8Encoding]::new($false).GetByteCount($Line + [Environment]::NewLine)) -or
            $anchorPayload.eventDigest -cne $eventDigest -or
            $anchorPayload.orphanSuffixDigest -cne (Get-Sha256HexBytes -Bytes $OrphanBytes)) {
            return 'v2 frame anchor does not bind the exact committed bytes'
        }
        $expectedCommitDigest = Get-Sha256Hex -Content ("story_performance_ledger_v2_commit_v1|$(ConvertTo-CanonicalJson -Value $anchorPayload)")
        if ([string] (Get-PropertyValue $anchor 'commitDigest') -cne $expectedCommitDigest) { return 'v2 frame commit digest is invalid' }
        $expectedChainDigest = Get-V2ContentChainDigest -PreviousCommitDigest $PreviousCommitDigest -OrphanSuffixDigest $anchorPayload.orphanSuffixDigest -EventDigest $eventDigest -RecordCount $anchorPayload.recordCount
        if ($anchorPayload.contentChainDigest -cne $expectedChainDigest) { return 'v2 frame content chain is invalid' }
        return $null
    }
    catch {
        return 'v2 frame anchor could not be validated'
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

    $byEventId = New-OrdinalHashtable
    $records = [System.Collections.Generic.List[object]]::new()
    $ledgerBytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $allLines = [System.Collections.Generic.List[object]]::new()
    $allLineStarts = [System.Collections.Generic.List[long]]::new()
    $allLineEnds = [System.Collections.Generic.List[long]]::new()
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
        [void] $allLineStarts.Add([long] $lineStart)
        [void] $allLineEnds.Add([long] ($offset + 1))
        $lineStart = $offset + 1
    }

    $tailLength = $ledgerBytes.Length - $lineStart
    $hasCompleteFinalNewline = $tailLength -eq 0
    $v2Mode = $false
    $v2PreviousCommitDigest = Get-Sha256Hex -Content 'story_performance_ledger_v2_genesis'
    $v2PreviousFrameEndOffset = 0L
    $v2PreviousRecordCount = 0L
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

        if ([int] (Get-PropertyValue $event 'schemaVersion') -eq 2 -and
            [string] (Get-PropertyValue $event 'kind') -ceq 'story_performance_event_frame') {
            $frameEvent = Get-PropertyValue $event 'event'
            $frameAnchor = Get-PropertyValue $event 'anchor'
            if ($null -eq $frameEvent -or $null -eq $frameAnchor) {
                [void] $Anomalies.Add((New-Anomaly -Code 'invalid_event_frame' -Message 'A v2 ledger frame without an event and commit anchor was excluded from aggregation' -Line $lineNumber))
                continue
            }
            $v2Mode = $true
            $frameStartOffset = [long] $allLineStarts[$lineIndex]
            $frameEndOffset = [long] $allLineEnds[$lineIndex]
            $orphanBytes = Get-ByteSlice -Bytes $ledgerBytes -Offset ([int] $v2PreviousFrameEndOffset) -Count ([int] ($frameStartOffset - $v2PreviousFrameEndOffset))
            $frameError = Get-V2FrameValidationError `
                -Frame $event `
                -Line $line `
                -FrameStartOffset $frameStartOffset `
                -FrameEndOffset $frameEndOffset `
                -PreviousFrameEndOffset $v2PreviousFrameEndOffset `
                -PreviousCommitDigest $v2PreviousCommitDigest `
                -PreviousRecordCount $v2PreviousRecordCount `
                -OrphanBytes $orphanBytes
            if ($null -ne $frameError) {
                [void] $Anomalies.Add((New-Anomaly -Code 'invalid_event_frame' -Message "$frameError; orphan frame was excluded from aggregation" -Line $lineNumber))
                continue
            }
            $event = $frameEvent
            $v2PreviousCommitDigest = [string] (Get-PropertyValue $frameAnchor 'commitDigest')
            $v2PreviousFrameEndOffset = $frameEndOffset
            $v2PreviousRecordCount = [long] (Get-PropertyValue $frameAnchor 'recordCount')
        }
        elseif ($v2Mode -or ([string] $line -like '{"schemaVersion":2,"kind":"*')) {
            [void] $Anomalies.Add((New-Anomaly -Code 'invalid_event_frame' -Message 'A v2 ledger orphan or unknown frame was excluded from aggregation' -Line $lineNumber))
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

    return Sort-RecordsByTimeLinear -Records @($records)
}

function Get-ObservedRoleUsageMetadata {
    param(
        [AllowNull()] [string] $Path,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [int] $ProjectId,
        [Parameter(Mandatory)] [int] $StoryId
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.ArgumentException]::new('usage_metadata_invalid: observed role token metadata was not found')
    }
    try {
        $metadata = ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -Depth 100 -DateKind String)
    }
    catch {
        throw [System.ArgumentException]::new('usage_metadata_invalid: observed role token metadata is not valid UTF-8 JSON')
    }
    if ($null -eq $metadata -or [int] (Get-PropertyValue $metadata 'schemaVersion') -ne 1 -or
        [string] (Get-PropertyValue $metadata 'kind') -cne 'story_performance_role_token_usage') {
        throw [System.ArgumentException]::new('usage_metadata_invalid: unsupported observed role token metadata envelope')
    }
    if ([string] (Get-PropertyValue $metadata 'runId') -cne $RunId -or
        [int] (Get-PropertyValue $metadata 'projectId') -ne $ProjectId -or
        [int] (Get-PropertyValue $metadata 'storyId') -ne $StoryId) {
        throw [System.ArgumentException]::new('usage_metadata_conflict: observed role token metadata identity does not match the event ledger')
    }
    $semantics = Get-PropertyValue $metadata 'counterSemantics'
    if ($null -eq $semantics -or [string]::IsNullOrWhiteSpace([string] (Get-PropertyValue $semantics 'aggregation'))) {
        throw [System.ArgumentException]::new('usage_metadata_invalid: cumulative counter semantics are required')
    }
    return $metadata
}

function New-ObservedRoleUsageMetric {
    param(
        [Parameter(Mandatory)] [object] $Metadata,
        [Parameter(Mandatory)] [string] $Role
    )

    $sessions = @((Get-PropertyValue $Metadata 'sessions') | Where-Object { [string] (Get-PropertyValue $_ 'role') -ceq $Role })
    $measured = @($sessions | Where-Object { [string] (Get-PropertyValue $_ 'state') -ceq 'measured' })
    $partial = @($sessions | Where-Object { [string] (Get-PropertyValue $_ 'state') -ceq 'partial' })
    $unavailable = @($sessions | Where-Object { [string] (Get-PropertyValue $_ 'state') -eq 'unavailable' })
    $totals = Get-PropertyValue (Get-PropertyValue $Metadata 'roleTotals') $Role
    if ($null -eq $totals -or $measured.Count -eq 0) {
        $state = if ($partial.Count -gt 0 -or $unavailable.Count -gt 0) { 'partial' } else { 'unavailable' }
        $missing = if ($unavailable.Count -gt 0) { "$($unavailable.Count) bound session(s) had no attributable boundary delta" } else { 'complete attributable cumulative counter boundaries were not available for this role' }
        $metric = New-Metric -State $state -Value $null -Unit 'tokens' -Source 'incremental observed Codex session counters' -Calculation 'subtract one story-start boundary counter from one confirmed-PR boundary counter per bound session' -Coverage ([string] (Get-PropertyValue $Metadata 'coverage')) -MissingData $missing
    }
    else {
        $counters = [ordered]@{}
        foreach ($name in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')) { $counters[$name] = [long] (Get-PropertyValue $totals $name) }
        $counters.uncachedInputTokens = [long] $counters.inputTokens - [long] $counters.cachedInputTokens
        $counters.totalTokens = [long] $counters.inputTokens + [long] $counters.outputTokens
        $incompleteCount = $partial.Count + $unavailable.Count
        $state = if ($incompleteCount -gt 0) { 'partial' } else { 'measured' }
        $missingData = if ($partial.Count -gt 0 -and $unavailable.Count -gt 0) { "$($partial.Count) partial and $($unavailable.Count) unavailable bound session(s) remain outside the complete role total" } elseif ($partial.Count -gt 0) { "$($partial.Count) bound session(s) used nearest complete-line boundaries" } elseif ($unavailable.Count -gt 0) { "$($unavailable.Count) bound session(s) had no attributable boundary delta" } else { $null }
        $value = if ($state -eq 'measured') { [long] $counters.totalTokens } else { $null }
        $metric = New-Metric -State $state -Value $value -Unit 'tokens' -Source 'incremental observed Codex session counters' -Calculation 'subtract cumulative counters at one story-start boundary from one confirmed-PR boundary per bound session' -Coverage ([string] (Get-PropertyValue $Metadata 'coverage')) -MissingData $missingData
        $metric | Add-Member -NotePropertyName counters -NotePropertyValue $counters -Force
    }
    $metric | Add-Member -NotePropertyName role -NotePropertyValue $Role -Force
    $metric | Add-Member -NotePropertyName sessionCount -NotePropertyValue $sessions.Count -Force
    return $metric
}

function New-ObservedTotalUsageMetric {
    param([Parameter(Mandatory)] [object[]] $RoleMetrics)
    $measured = @($RoleMetrics | Where-Object { $_.state -eq 'measured' })
    $partial = @($RoleMetrics | Where-Object { $_.state -eq 'partial' })
    if ($measured.Count -eq 0) {
        $state = if ($partial.Count -gt 0) { 'partial' } else { 'unavailable' }
        return New-Metric -State $state -Value $null -Unit 'tokens' -Source 'observed role token totals' -Calculation 'sum disjoint bound-session deltas without summing cumulative notifications' -Coverage 'no complete observed role total is available' -MissingData 'observed role token metadata is unavailable or incomplete'
    }
    if ($measured.Count -ne $RoleMetrics.Count) {
        return New-Metric -State 'partial' -Value $null -Unit 'tokens' -Source 'observed role token totals' -Calculation 'sum disjoint bound-session deltas without summing cumulative notifications' -Coverage "$($measured.Count) of $($RoleMetrics.Count) observed role totals are measured" -MissingData 'unavailable role totals are not treated as zero'
    }
    $value = [long] ($measured | ForEach-Object { [long] $_.value } | Measure-Object -Sum).Sum
    return New-Metric -State 'measured' -Value $value -Unit 'tokens' -Source 'observed role token totals' -Calculation 'sum disjoint bound-session deltas without summing cumulative notifications' -Coverage 'all observed role totals are measured' -MissingData $null
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

function Get-ReportIdentity {
    param(
        [AllowNull()] [string] $RunId,
        [AllowNull()] [Nullable[int]] $ProjectId,
        [AllowNull()] [Nullable[int]] $StoryId,
        [AllowNull()] [object] $PullRequest
    )

    if ([string]::IsNullOrWhiteSpace($RunId) -or $null -eq $ProjectId -or
        $null -eq $StoryId -or $null -eq $PullRequest) {
        return $null
    }

    $parts = @(
        (ConvertTo-CanonicalIdentityComponent -Value $RunId),
        "project-$ProjectId",
        "story-$StoryId",
        "pr-$(ConvertTo-CanonicalIdentityComponent -Value (Get-PropertyValue $PullRequest 'provider') -CaseInsensitive)",
        "owner-$(ConvertTo-CanonicalIdentityComponent -Value (Get-PropertyValue $PullRequest 'owner') -CaseInsensitive)",
        "repository-$(ConvertTo-CanonicalIdentityComponent -Value (Get-PropertyValue $PullRequest 'repository') -CaseInsensitive)",
        "number-$([string] (Get-PropertyValue $PullRequest 'number'))",
        "head-$((([string] (Get-PropertyValue $PullRequest 'reviewedHead')).ToLowerInvariant()))"
    )
    return ($parts -join '/')
}

function ConvertTo-CanonicalIdentityComponent {
    param(
        [Parameter(Mandatory)] [object] $Value,
        [switch] $CaseInsensitive
    )

    if (-not (Test-NonBlankSafeString -Value $Value) -or [string] $Value -match '\s') {
        throw [System.ArgumentException]::new('report_identity_invalid: PR identity components must be nonblank safe strings without whitespace')
    }
    $text = [string] $Value
    if ($CaseInsensitive) {
        $text = $text.ToLowerInvariant()
    }
    return [Uri]::EscapeDataString($text)
}

function ConvertTo-MarkdownCell {
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        return 'unknown'
    }
    return ([string] $Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Get-ContainerValue {
    param(
        [AllowNull()] [object] $Container,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $Container) {
        return $null
    }
    if ($Container -is [System.Collections.IDictionary] -and $Container.Contains($Name)) {
        return $Container[$Name]
    }
    return Get-PropertyValue -Object $Container -Name $Name
}

function Get-MarkdownMetricValue {
    param([AllowNull()] [object] $Metric)

    if ($null -eq $Metric) {
        return 'unknown'
    }
    $recordCount = Get-PropertyValue -Object $Metric -Name 'recordCount'
    if ($null -ne $recordCount) {
        $changeCount = Get-PropertyValue -Object $Metric -Name 'changeCount'
        return "$recordCount profile record(s); $changeCount explicit change(s)"
    }
    $value = Get-PropertyValue -Object $Metric -Name 'value'
    if ($null -eq $value) {
        return 'unknown'
    }
    if ($value -is [System.Array]) {
        return "$(@($value).Count) record(s)"
    }
    return [string] $value
}

function Get-MarkdownMetricSummary {
    param([AllowNull()] [object] $Metric)

    if ($null -eq $Metric) {
        return 'unknown'
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    [void] $parts.Add((Get-MarkdownMetricValue -Metric $Metric))
    [void] $parts.Add("state=$(ConvertTo-MarkdownCell (Get-PropertyValue -Object $Metric -Name 'state'))")
    [void] $parts.Add("coverage=$(ConvertTo-MarkdownCell (Get-PropertyValue -Object $Metric -Name 'coverage'))")
    $missingData = Get-PropertyValue -Object $Metric -Name 'missingData'
    if (-not [string]::IsNullOrWhiteSpace([string] $missingData)) {
        [void] $parts.Add("limitation=$(ConvertTo-MarkdownCell $missingData)")
    }
    return ($parts -join '; ')
}

function ConvertTo-Markdown {
    param([Parameter(Mandatory)] [object] $Report)

    $lines = [System.Collections.Generic.List[string]]::new()
    [void] $lines.Add('# Story performance report')
    [void] $lines.Add('')
    [void] $lines.Add("- Report identity: $(ConvertTo-MarkdownCell $Report.reportId)")
    [void] $lines.Add("- Run: $(ConvertTo-MarkdownCell $Report.runId)")
    [void] $lines.Add("- Project/story: $(ConvertTo-MarkdownCell $Report.projectId)/$(ConvertTo-MarkdownCell $Report.storyId) (#$(ConvertTo-MarkdownCell $Report.storyRef))")
    [void] $lines.Add("- Review mode: $(ConvertTo-MarkdownCell $Report.reviewMode)")
    $pullRequest = $Report.pullRequest
    if ($null -eq $pullRequest) {
        [void] $lines.Add('- Pull request: unknown')
    }
    else {
        $pullRequestLabel = "$(ConvertTo-MarkdownCell $pullRequest.provider)/$(ConvertTo-MarkdownCell $pullRequest.owner)/$(ConvertTo-MarkdownCell $pullRequest.repository)#$($pullRequest.number)"
        $pullRequestUrl = Get-PropertyValue $pullRequest 'url'
        if ([string]::IsNullOrWhiteSpace([string] $pullRequestUrl)) {
            [void] $lines.Add("- Pull request: $(ConvertTo-MarkdownCell $pullRequestLabel)")
        }
        else {
            [void] $lines.Add("- Pull request: [$([string] $pullRequestLabel)]($([string] $pullRequestUrl))")
        }
    }
    [void] $lines.Add("- Reviewed HEAD: $(ConvertTo-MarkdownCell $Report.comparison.reviewedHead)")
    [void] $lines.Add("- Base revision: $(ConvertTo-MarkdownCell $Report.comparison.baseRevision)")
    [void] $lines.Add('')
    [void] $lines.Add('| Metric | State | Value | Unit | Source | Coverage | Limitation |')
    [void] $lines.Add('| --- | --- | ---: | --- | --- | --- | --- |')
    $metricProperties = if ($Report.metrics -is [System.Collections.IDictionary]) {
        @($Report.metrics.Keys | ForEach-Object { [pscustomobject][ordered]@{ Name = [string] $_; Value = $Report.metrics[$_] } })
    }
    else {
        @($Report.metrics.PSObject.Properties)
    }
    foreach ($property in $metricProperties) {
        $metric = $property.Value
        $value = Get-MarkdownMetricValue -Metric $metric
        [void] $lines.Add("| $(ConvertTo-MarkdownCell $property.Name) | $(ConvertTo-MarkdownCell $metric.state) | $(ConvertTo-MarkdownCell $value) | $(ConvertTo-MarkdownCell $metric.unit) | $(ConvertTo-MarkdownCell $metric.source) | $(ConvertTo-MarkdownCell $metric.coverage) | $(ConvertTo-MarkdownCell $metric.missingData) |")
    }
    [void] $lines.Add('')
    [void] $lines.Add('## Comparison')
    [void] $lines.Add('')
    [void] $lines.Add("- Changed files: $(Get-MarkdownMetricSummary (Get-ContainerValue -Container $Report.comparison -Name 'changedFiles'))")
    [void] $lines.Add("- Lines added: $(Get-MarkdownMetricSummary (Get-ContainerValue -Container $Report.comparison -Name 'linesAdded'))")
    [void] $lines.Add("- Lines deleted: $(Get-MarkdownMetricSummary (Get-ContainerValue -Container $Report.comparison -Name 'linesDeleted'))")
    $modelsMetric = Get-ContainerValue -Container $Report.metrics -Name 'modelsAndReasoning'
    $modelsValue = if ($null -eq $modelsMetric) { $null } else { Get-PropertyValue -Object $modelsMetric -Name 'value' }
    if ($null -ne $modelsValue -and @($modelsValue).Count -gt 0) {
        [void] $lines.Add('')
        [void] $lines.Add('## Role profiles')
        [void] $lines.Add('')
        foreach ($profile in @($modelsValue)) {
            $change = if ([string]::IsNullOrWhiteSpace([string] $profile.changeId)) { 'initial' } else { [string] $profile.changeId }
            $range = if ([string]::IsNullOrWhiteSpace([string] $profile.effectiveToUtc)) { "from $($profile.effectiveFromUtc)" } else { "$($profile.effectiveFromUtc) to $($profile.effectiveToUtc)" }
            $profileProvenance = Get-PropertyValue -Object $profile -Name 'provenance'
            [void] $lines.Add("- $(ConvertTo-MarkdownCell $profile.role): worker=$(ConvertTo-MarkdownCell $profile.workerId), model=$(ConvertTo-MarkdownCell $profile.model), effort=$(ConvertTo-MarkdownCell $profile.effort), change=$(ConvertTo-MarkdownCell $change), $range, source=$(ConvertTo-MarkdownCell (Get-PropertyValue -Object $profileProvenance -Name 'source'))")
        }
    }
    [void] $lines.Add('')
    [void] $lines.Add('## Provenance and limitations')
    [void] $lines.Add('')
    [void] $lines.Add("- Token collection attempt: $(ConvertTo-MarkdownCell $Report.provenance.collectionAttempt.status); $(ConvertTo-MarkdownCell $Report.provenance.collectionAttempt.reason)")
    [void] $lines.Add('')
    foreach ($source in @($Report.provenance.sources)) {
        [void] $lines.Add("- Source: $(ConvertTo-MarkdownCell $source)")
    }
    foreach ($limitation in @($Report.provenance.limitations)) {
        [void] $lines.Add("- Limitation: $(ConvertTo-MarkdownCell $limitation)")
    }
    [void] $lines.Add('')
    [void] $lines.Add("Anomalies: $(@($Report.anomalies).Count)")
    foreach ($anomaly in @($Report.anomalies)) {
        [void] $lines.Add("- [$([string] $anomaly.code)] $([string] $anomaly.message)")
    }
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Get-WorktreeRootCandidates {
    param([AllowNull()] [string] $RepositoryPath)

    $roots = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RepositoryPath)) {
        [void] $roots.Add([IO.Path]::GetFullPath($RepositoryPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    }

    $gitRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    $gitExitCode = if (Test-Path variable:LASTEXITCODE) { [int] $LASTEXITCODE } else { 1 }
    if ($gitExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string] $gitRoot)) {
        $gitRootFull = [IO.Path]::GetFullPath(([string] $gitRoot).Trim())
        if ($roots -notcontains $gitRootFull) {
            [void] $roots.Add($gitRootFull.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
        }
    }
    return @($roots)
}

function Assert-ExternalArtifactPath {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [AllowNull()] [string] $RepositoryPath
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    foreach ($root in @(Get-WorktreeRootCandidates -RepositoryPath $RepositoryPath)) {
        $rootWithSeparator = $root + [IO.Path]::DirectorySeparatorChar
        if ($fullPath.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
            throw [System.ArgumentException]::new("report artifacts must be outside the source worktree: $fullPath")
        }
    }
    return $fullPath
}

function Test-ExactUtf8ArtifactContent {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content
    )

    if (-not [IO.File]::Exists($Path)) {
        return $false
    }
    $expected = [Text.UTF8Encoding]::new($false).GetBytes($Content)
    $actual = [IO.File]::ReadAllBytes($Path)
    if ($actual.Length -ne $expected.Length) {
        return $false
    }
    for ($index = 0; $index -lt $expected.Length; $index++) {
        if ($actual[$index] -ne $expected[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-ArtifactCanPublish {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content
    )

    if ([IO.Directory]::Exists($Path)) {
        throw [System.InvalidOperationException]::new("report_artifact_conflict: artifact destination is a directory '$Path'")
    }
    if ([IO.File]::Exists($Path) -and -not (Test-ExactUtf8ArtifactContent -Path $Path -Content $Content)) {
        throw [System.InvalidOperationException]::new("report_artifact_conflict: refusing to replace existing artifact '$Path'")
    }
}

function Get-ArtifactFileStem {
    param([Parameter(Mandatory)] [string] $ReportId)

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $hasher.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($ReportId))
    }
    finally {
        $hasher.Dispose()
    }
    return "story-performance-$([Convert]::ToHexString($digest).ToLowerInvariant())"
}

function Get-CompletionManifestPath {
    param([Parameter(Mandatory)] [string] $AnchorPath)

    return "$AnchorPath.complete.json"
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)] [string] $Content)

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $hasher.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Content))
    }
    finally {
        $hasher.Dispose()
    }
    return [Convert]::ToHexString($digest).ToLowerInvariant()
}

function New-ArtifactSetManifestContent {
    param(
        [AllowNull()] [string] $ReportId,
        [Parameter(Mandatory)] [object[]] $Artifacts
    )

    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_report_artifact_set'
        reportId = $ReportId
        confirmed = -not [string]::IsNullOrWhiteSpace($ReportId)
        artifacts = @($Artifacts)
    }
    return ($manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine
}

function Publish-ImmutableArtifact {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content
    )

    if (Test-ExactUtf8ArtifactContent -Path $Path -Content $Content) {
        return 'reused'
    }

    $directory = [IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $temporaryPath = "$Path.tmp.$([Guid]::NewGuid().ToString('N'))"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Content)
    try {
        $stream = [IO.File]::Open($temporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
        try {
            [IO.File]::Move($temporaryPath, $Path)
            return 'created'
        }
        catch [IO.IOException] {
            if (Test-ExactUtf8ArtifactContent -Path $Path -Content $Content) {
                return 'reused'
            }
            throw [System.InvalidOperationException]::new("report_artifact_conflict: another artifact already occupies '$Path'")
        }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
    }
}

$resolvedEventsPath = [IO.Path]::GetFullPath($EventsPath)
$anomalies = [System.Collections.Generic.List[object]]::new()
$records = @(Read-EventLedger -Path $resolvedEventsPath -Anomalies $anomalies)

if ($records.Count -eq 0) {
    throw [System.ArgumentException]::new('The events ledger contains no valid events')
}

$ledgerOrder = @(Sort-RecordsByLineLinear -Records @($records))
$bindingKey = Get-BindingKey -Event $ledgerOrder[0].Event
$foreignRecords = @($records | Where-Object { (Get-BindingKey -Event $_.Event) -cne $bindingKey })
foreach ($foreign in $foreignRecords) {
    [void] $anomalies.Add((New-Anomaly -Code 'foreign_binding' -Message 'An event from another run/project/story binding was quarantined and excluded from aggregation' -Identity $foreign.EventId -Line $foreign.Line -EventIds @($foreign.EventId)))
}
$records = @($records | Where-Object { (Get-BindingKey -Event $_.Event) -ceq $bindingKey })

$eventObjects = @($records | ForEach-Object { $_.Event })
$runIds = @(Get-UniqueValuesLinear -Values @($eventObjects | ForEach-Object { [string] (Get-PropertyValue $_ 'runId') }))
$projectIds = @(Get-UniqueValuesLinear -Values @($eventObjects | ForEach-Object { [int] (Get-PropertyValue $_ 'projectId') }))
$storyIds = @(Get-UniqueValuesLinear -Values @($eventObjects | ForEach-Object { [int] (Get-PropertyValue $_ 'storyId') }))
$storyRefs = @(Get-UniqueValuesLinear -Values @($eventObjects | ForEach-Object { [int] (Get-PropertyValue $_ 'storyRef') }))
$eventModes = @(Get-UniqueValuesLinear -Values @($eventObjects | ForEach-Object { [string] (Get-PropertyValue $_ 'reviewMode') }))

$declaredTaskRefs = [System.Collections.Generic.List[int]]::new()
$declaredTaskRefSet = [System.Collections.Generic.HashSet[int]]::new()
foreach ($candidateTaskRef in @($TaskRefs)) {
    if (Test-PositiveIntegerValue -Value $candidateTaskRef) {
        $candidateTaskRefInt = [int] $candidateTaskRef
        if ($declaredTaskRefSet.Add($candidateTaskRefInt)) {
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
$observedTaskRefs = @(Get-UniqueValuesLinear -Values @($taskEventsBeforeFiltering | ForEach-Object { [int] (Get-PropertyValue $_.Event 'taskRef') }))
$observedTaskRefSet = [System.Collections.Generic.HashSet[int]]::new()
foreach ($observedTaskRef in $observedTaskRefs) {
    [void] $observedTaskRefSet.Add([int] $observedTaskRef)
}
$missingDeclaredTaskRefs = @(
    if ($taskSetWasDeclared) { $declaredTaskRefs | Where-Object { -not $observedTaskRefSet.Contains([int] $_) } }
)
$undeclaredTaskRefs = @(
    if ($taskSetWasDeclared) { $observedTaskRefs | Where-Object { -not $declaredTaskRefSet.Contains([int] $_) } }
)
if ($missingDeclaredTaskRefs.Count -gt 0) {
    [void] $anomalies.Add((New-Anomaly -Code 'missing_task_evidence' -Message 'Declared task identities have no attributable task events; affected review coverage is partial' -Identity ($missingDeclaredTaskRefs -join ',')))
}
if ($undeclaredTaskRefs.Count -gt 0) {
    [void] $anomalies.Add((New-Anomaly -Code 'undeclared_task_evidence' -Message 'Task events outside the declared ordered task set were quarantined from task review counts and phase totals' -Identity ($undeclaredTaskRefs -join ',')))
    $records = @($records | Where-Object {
        [string] (Get-PropertyValue $_.Event 'scope') -ne 'task' -or
        $declaredTaskRefSet.Contains([int] (Get-PropertyValue $_.Event 'taskRef'))
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

$recordsByEventId = New-OrdinalHashtable
foreach ($record in @($records)) {
    $recordsByEventId[[string] $record.EventId] = $record
}

$storyStarts = @($records | Where-Object { $_.EventType -eq 'story_started' -and [string](Get-PropertyValue $_.Event 'scope') -eq 'story' })
$prReady = @($records | Where-Object { $_.EventType -eq 'pr_ready' -and [string](Get-PropertyValue $_.Event 'scope') -eq 'story' })
if ($storyStarts.Count -eq 0 -and $prReady.Count -eq 1) {
    [void] $anomalies.Add((New-Anomaly -Code 'missing_story_start' -Message 'story_started boundary is absent; timeToPr is unavailable while coherent event measurements are retained' -Identity 'story|story_started' -EventIds @($prReady[0].EventId)))
    $timeToPrInterval = [pscustomobject][ordered]@{
        state = 'unavailable'
        elapsedMilliseconds = $null
        startUtc = $null
        endUtc = $null
        missingData = 'story_started boundary is absent; confirmed pr_ready evidence is present'
    }
}
else {
    $timeToPrInterval = Get-IntervalResult -Starts $storyStarts -Ends $prReady -Identity 'story|time_to_pr' -Kind 'story_to_pr' -Anomalies $anomalies
}

$implementationStarts = New-OrdinalHashtable
$implementationEnds = New-OrdinalHashtable
$implementationKeyOrder = [System.Collections.Generic.List[string]]::new()
$implementationKeySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$correctionStarts = New-OrdinalHashtable
$correctionEnds = New-OrdinalHashtable
$correctionKeyOrder = [System.Collections.Generic.List[string]]::new()
$correctionKeySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$waitStarts = New-OrdinalHashtable
$waitEnds = New-OrdinalHashtable
$waitKeyOrder = [System.Collections.Generic.List[string]]::new()
$waitKeySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$reviewStarts = New-OrdinalHashtable
$reviewEnds = New-OrdinalHashtable
$reviewEndKeyOrder = [System.Collections.Generic.List[string]]::new()
$reviewEndKeySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

foreach ($record in $records) {
    $event = $record.Event
    switch ($record.EventType) {
        'implementation_started' { Add-ToIndex -Index $implementationStarts -Key (Get-PhaseIdentity $event) -Value $record -KeyOrder $implementationKeyOrder -KeySeen $implementationKeySeen }
        'task_ready_for_review' { Add-ToIndex -Index $implementationEnds -Key (Get-PhaseIdentity $event) -Value $record -KeyOrder $implementationKeyOrder -KeySeen $implementationKeySeen }
        'correction_started' { Add-ToIndex -Index $correctionStarts -Key (Get-PhaseIdentity $event) -Value $record -KeyOrder $correctionKeyOrder -KeySeen $correctionKeySeen }
        'correction_ready' { Add-ToIndex -Index $correctionEnds -Key (Get-PhaseIdentity $event) -Value $record -KeyOrder $correctionKeyOrder -KeySeen $correctionKeySeen }
        'wait_started' {
            $waitKey = Get-WaitIdentity -Event $event
            Add-ToIndex -Index $waitStarts -Key $waitKey -Value $record -KeyOrder $waitKeyOrder -KeySeen $waitKeySeen
        }
        'wait_ended' {
            $waitKey = Get-WaitIdentity -Event $event
            Add-ToIndex -Index $waitEnds -Key $waitKey -Value $record -KeyOrder $waitKeyOrder -KeySeen $waitKeySeen
        }
        { $_ -in $script:ReviewStartEvents } { Add-ToIndex -Index $reviewStarts -Key (Get-ReviewIdentity $event) -Value $record }
        { $_ -in $script:ReviewCloseEvents } { Add-ToIndex -Index $reviewEnds -Key (Get-ReviewIdentity $event) -Value $record -KeyOrder $reviewEndKeyOrder -KeySeen $reviewEndKeySeen }
    }
}

# A second observation of the same review attempt is diagnostic-only. It is
# never a second review count, even when it arrived under another eventId.
# Immutable payload differences are conflicts, not stale duplicates.
$reviewStartByAttempt = New-OrdinalHashtable
$reviewAttemptBindingById = New-OrdinalHashtable
$reviewRequestBindingById = New-OrdinalHashtable
$reviewStartConflicts = New-OrdinalHashtable
$dedupedReviewStarts = [System.Collections.Generic.List[object]]::new()
foreach ($record in (Sort-RecordsByLineLinear -Records @($records | Where-Object { $_.EventType -in $script:ReviewStartEvents }))) {
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
$reviewEndsByAttempt = New-OrdinalHashtable
$reviewEndsByAttemptKeyOrder = [System.Collections.Generic.List[string]]::new()
foreach ($key in $reviewEndKeyOrder) {
    foreach ($record in @($reviewEnds[$key])) {
        $attemptKey = Get-ReviewAttemptIdentity -Event $record.Event
        if (-not $reviewEndsByAttempt.ContainsKey($attemptKey)) {
            $reviewEndsByAttempt[$attemptKey] = [System.Collections.ArrayList]::new()
            [void] $reviewEndsByAttemptKeyOrder.Add($attemptKey)
        }
        [void] $reviewEndsByAttempt[$attemptKey].Add($record)
    }
}

$reviewIntervals = [System.Collections.Generic.List[object]]::new()
foreach ($record in (Sort-RecordsByTimeLinear -Records @($dedupedReviewStarts))) {
    $attemptKey = Get-ReviewAttemptIdentity -Event $record.Event
    $closures = @(if ($reviewEndsByAttempt.ContainsKey($attemptKey)) { @($reviewEndsByAttempt[$attemptKey]) })
    $matchingClosures = @($closures | Where-Object { (Get-ReviewIdentity $_.Event) -ceq (Get-ReviewIdentity $record.Event) })
    $mismatchedClosures = @($closures | Where-Object { (Get-ReviewIdentity $_.Event) -cne (Get-ReviewIdentity $record.Event) })
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
        $closurePayloads = @(Get-UniqueValuesLinear -Values @($matchingClosures | ForEach-Object { Get-ImmutableBoundaryCanonical -Event $_.Event }))
        $closureKinds = @(Get-UniqueValuesLinear -Values @($matchingClosures | ForEach-Object { $_.EventType }))
        if ($closurePayloads.Count -gt 1 -or $closureKinds.Count -gt 1) {
            $closureConflict = $true
            $ids = @($record.EventId) + @($matchingClosures | ForEach-Object { $_.EventId })
            [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_closure' -Message 'A review attempt has changed or conflicting closure evidence; no closure was selected' -Identity $attemptKey -EventIds $ids))
            $matchingClosures = @()
        }
        else {
            $authoritativeClosure = @(Sort-RecordsByLineLinear -Records @($matchingClosures) | Select-Object -First 1)
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
        startEventId = $record.EventId
        endEventId = if ($null -ne $closure) { $closure.EventId } else { $null }
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
foreach ($attemptKey in $reviewEndsByAttemptKeyOrder) {
    if (-not $reviewStartByAttempt.ContainsKey($attemptKey)) {
        foreach ($record in @($reviewEndsByAttempt[$attemptKey])) {
            [void] $anomalies.Add((New-Anomaly -Code 'orphan_review_closure' -Message 'Review closure has no matching review start and was excluded from pairing' -Identity $attemptKey -EventIds @($record.EventId)))
        }
    }
}

$script:IntervalStarts = $implementationStarts
$script:IntervalEnds = $implementationEnds
$script:IntervalKeyOrder = $implementationKeyOrder
$implementationIntervals = @(Get-IntervalCollection -Kind 'implementation' -Anomalies $anomalies)
$script:IntervalStarts = $correctionStarts
$script:IntervalEnds = $correctionEnds
$script:IntervalKeyOrder = $correctionKeyOrder
$correctionIntervals = @(Get-IntervalCollection -Kind 'correction' -Anomalies $anomalies)
$script:IntervalStarts = $waitStarts
$script:IntervalEnds = $waitEnds
$script:IntervalKeyOrder = $waitKeyOrder
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

function Get-UsageCounter {
    param(
        [AllowNull()] [object] $Usage,
        [Parameter(Mandatory)] [string] $Name
    )

    $counters = Get-PropertyValue $Usage 'counters'
    $property = if ($null -ne $counters) { $counters.PSObject.Properties[$Name] } else { $null }
    return [pscustomobject][ordered]@{
        present = $null -ne $property
        value = if ($null -ne $property) { [long] $property.Value } else { $null }
    }
}

function Get-UsageSampleKey {
    param(
        [Parameter(Mandatory)] [string] $Role,
        [Parameter(Mandatory)] [string] $StreamId,
        [Parameter(Mandatory)] [string] $Source
    )

    return ConvertTo-IdentityTupleKey $Role $StreamId $Source
}

function New-UsageSampleIndex {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records)

    $index = New-OrdinalHashtable
    foreach ($record in $Records) {
        $usage = Get-PropertyValue $record.Event 'usage'
        $counters = if ($null -ne $usage) { Get-PropertyValue $usage 'counters' } else { $null }
        if ($null -eq $usage -or $null -eq $counters -or @($counters.PSObject.Properties).Count -eq 0) { continue }
        $role = [string] (Get-PropertyValue $usage 'role')
        $streamId = [string] (Get-PropertyValue $usage 'streamId')
        $source = [string] (Get-PropertyValue $usage 'source')
        $sampleTime = [DateTimeOffset]::MinValue
        if ([string]::IsNullOrWhiteSpace($role) -or [string]::IsNullOrWhiteSpace($streamId) -or
            [string]::IsNullOrWhiteSpace($source) -or
            -not (Try-GetUtcTime -Value (Get-PropertyValue $usage 'sampledAtUtc') -Parsed ([ref] $sampleTime))) {
            continue
        }
        $sessionId = [string] (Get-PropertyValue $usage 'sessionId')
        if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = [string] (Get-PropertyValue $record.Event 'sessionId') }
        $key = Get-UsageSampleKey -Role $role -StreamId $streamId -Source $source
        if (-not $index.ContainsKey($key)) {
            $index[$key] = [System.Collections.Generic.List[object]]::new()
        }
        [void] $index[$key].Add([pscustomobject][ordered]@{
                record = $record
                usage = $usage
                sampleTime = $sampleTime
                sessionId = $sessionId
                workerId = [string] (Get-PropertyValue $record.Event 'workerId')
                semantics = Get-PropertyValue $usage 'counterSemantics'
                counters = $counters
            })
    }
    foreach ($key in @($index.Keys)) {
        $samples = @(Sort-UsageSamplesLinear -Samples @($index[$key]))
        $sameTimeConflict = [bool[]]::new($samples.Count)
        $edgeStreamIssue = [bool[]]::new($samples.Count)
        $edgeSemanticsIssue = [bool[]]::new($samples.Count)
        $edgeResetIssue = [bool[]]::new($samples.Count)
        $missingInputIssue = [bool[]]::new($samples.Count)
        $missingCachedInputIssue = [bool[]]::new($samples.Count)
        $missingOutputIssue = [bool[]]::new($samples.Count)
        $missingReasoningIssue = [bool[]]::new($samples.Count)
        $groupStart = 0
        while ($groupStart -lt $samples.Count) {
            $groupEnd = $groupStart + 1
            $canonical = ConvertTo-CanonicalJson -Value ([ordered]@{
                    sessionId = $samples[$groupStart].sessionId
                    workerId = $samples[$groupStart].workerId
                    semantics = $samples[$groupStart].semantics
                    counters = $samples[$groupStart].counters
                })
            $conflict = $false
            while ($groupEnd -lt $samples.Count -and $samples[$groupEnd].sampleTime -eq $samples[$groupStart].sampleTime) {
                $candidateCanonical = ConvertTo-CanonicalJson -Value ([ordered]@{
                        sessionId = $samples[$groupEnd].sessionId
                        workerId = $samples[$groupEnd].workerId
                        semantics = $samples[$groupEnd].semantics
                        counters = $samples[$groupEnd].counters
                    })
                if ($candidateCanonical -cne $canonical) {
                    $conflict = $true
                }
                $groupEnd++
            }
            if ($conflict) {
                for ($groupIndex = $groupStart; $groupIndex -lt $groupEnd; $groupIndex++) {
                    $sameTimeConflict[$groupIndex] = $true
                }
            }
            $groupStart = $groupEnd
        }

        for ($sampleIndex = 0; $sampleIndex -lt $samples.Count; $sampleIndex++) {
            $streamEdge = $false
            $semanticsEdge = $false
            $resetEdge = $false
            if ($sampleIndex -gt 0) {
                $previous = $samples[$sampleIndex - 1]
                $current = $samples[$sampleIndex]
                $streamEdge = $previous.sessionId -cne $current.sessionId -or $previous.workerId -cne $current.workerId
                $previousCached = [string] (Get-PropertyValue $previous.semantics 'cachedInput')
                $currentCached = [string] (Get-PropertyValue $current.semantics 'cachedInput')
                $previousReasoning = [string] (Get-PropertyValue $previous.semantics 'reasoning')
                $currentReasoning = [string] (Get-PropertyValue $current.semantics 'reasoning')
                $semanticsEdge = $previousCached -cne $currentCached -or $previousReasoning -cne $currentReasoning
                foreach ($counterName in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')) {
                    $previousCounter = Get-UsageCounter -Usage $previous.usage -Name $counterName
                    $currentCounter = Get-UsageCounter -Usage $current.usage -Name $counterName
                    if ($previousCounter.present -and $currentCounter.present -and $currentCounter.value -lt $previousCounter.value) {
                        $resetEdge = $true
                    }
                }
            }
            $inputMissing = -not (Get-UsageCounter -Usage $samples[$sampleIndex].usage -Name 'inputTokens').present
            $cachedInputMissing = -not (Get-UsageCounter -Usage $samples[$sampleIndex].usage -Name 'cachedInputTokens').present
            $outputMissing = -not (Get-UsageCounter -Usage $samples[$sampleIndex].usage -Name 'outputTokens').present
            $reasoningMissing = -not (Get-UsageCounter -Usage $samples[$sampleIndex].usage -Name 'reasoningTokens').present
            $edgeStreamIssue[$sampleIndex] = $streamEdge
            $edgeSemanticsIssue[$sampleIndex] = $semanticsEdge
            $edgeResetIssue[$sampleIndex] = $resetEdge
            $missingInputIssue[$sampleIndex] = $inputMissing
            $missingCachedInputIssue[$sampleIndex] = $cachedInputMissing
            $missingOutputIssue[$sampleIndex] = $outputMissing
            $missingReasoningIssue[$sampleIndex] = $reasoningMissing
        }
        $sameTimeConflictNext = New-NextIssueIndex -Flags $sameTimeConflict
        $edgeStreamNext = New-NextIssueIndex -Flags $edgeStreamIssue
        $edgeSemanticsNext = New-NextIssueIndex -Flags $edgeSemanticsIssue
        $edgeResetNext = New-NextIssueIndex -Flags $edgeResetIssue
        $missingInputNext = New-NextIssueIndex -Flags $missingInputIssue
        $missingCachedInputNext = New-NextIssueIndex -Flags $missingCachedInputIssue
        $missingOutputNext = New-NextIssueIndex -Flags $missingOutputIssue
        $missingReasoningNext = New-NextIssueIndex -Flags $missingReasoningIssue
        $index[$key] = [pscustomobject][ordered]@{
            samples = $samples
            sameTimeConflictNext = $sameTimeConflictNext
            edgeStreamNext = $edgeStreamNext
            edgeSemanticsNext = $edgeSemanticsNext
            edgeResetNext = $edgeResetNext
            missingInputNext = $missingInputNext
            missingCachedInputNext = $missingCachedInputNext
            missingOutputNext = $missingOutputNext
            missingReasoningNext = $missingReasoningNext
        }
    }
    return $index
}

function New-NextIssueIndex {
    param([Parameter(Mandatory)] [bool[]] $Flags)

    $next = [int[]]::new($Flags.Count + 1)
    $next[$Flags.Count] = -1
    $candidate = -1
    for ($index = $Flags.Count - 1; $index -ge 0; $index--) {
        if ($Flags[$index]) {
            $candidate = $index
        }
        $next[$index] = $candidate
    }
    return $next
}

function Find-FirstUsageIssueIndex {
    param(
        [Parameter(Mandatory)] [int[]] $NextIssue,
        [Parameter(Mandatory)] [int] $StartIndex,
        [Parameter(Mandatory)] [int] $EndIndex
    )

    if ($StartIndex -gt $EndIndex) {
        return -1
    }
    $candidate = $NextIssue[$StartIndex]
    if ($candidate -lt 0 -or $candidate -gt $EndIndex) {
        return -1
    }
    return $candidate
}

function New-UsageRangePlan {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Intervals,
        [Parameter(Mandatory)] [hashtable] $RecordsByEventId,
        [Parameter(Mandatory)] [hashtable] $UsageIndex
    )

    $itemsByKey = New-OrdinalHashtable
    for ($intervalIndex = 0; $intervalIndex -lt $Intervals.Count; $intervalIndex++) {
        $interval = $Intervals[$intervalIndex]
        $startRecord = if ($null -ne $interval.startEventId -and $RecordsByEventId.ContainsKey([string] $interval.startEventId)) { $RecordsByEventId[[string] $interval.startEventId] } else { $null }
        $startUsage = if ($null -ne $startRecord) { Get-PropertyValue $startRecord.Event 'usage' } else { $null }
        $startTime = [DateTimeOffset]::MinValue
        $endTime = [DateTimeOffset]::MinValue
        $role = if ($null -ne $startUsage) { [string] (Get-PropertyValue $startUsage 'role') } else { $null }
        $streamId = if ($null -ne $startUsage) { [string] (Get-PropertyValue $startUsage 'streamId') } else { $null }
        $source = if ($null -ne $startUsage) { [string] (Get-PropertyValue $startUsage 'source') } else { $null }
        $key = if ($null -ne $startUsage) { Get-UsageSampleKey -Role $role -StreamId $streamId -Source $source } else { $null }
        if ((Try-GetUtcTime -Value $interval.startUtc -Parsed ([ref] $startTime)) -and
            (Try-GetUtcTime -Value $interval.endUtc -Parsed ([ref] $endTime)) -and
            -not [string]::IsNullOrWhiteSpace($role) -and
            -not [string]::IsNullOrWhiteSpace($streamId) -and
            -not [string]::IsNullOrWhiteSpace($source) -and
            $UsageIndex.ContainsKey($key)) {
            if (-not $itemsByKey.ContainsKey($key)) {
                $itemsByKey[$key] = [System.Collections.Generic.List[object]]::new()
            }
            [void] $itemsByKey[$key].Add([pscustomobject][ordered]@{
                    intervalIndex = $intervalIndex
                    startTime = $startTime
                    endTime = $endTime
                })
        }
    }

    $plan = New-OrdinalHashtable
    foreach ($key in @($itemsByKey.Keys)) {
        $bucket = $UsageIndex[$key]
        $samples = @($bucket.samples)
        $items = @($itemsByKey[$key])
        $firstIndexes = New-OrdinalHashtable
        $lastExclusiveIndexes = New-OrdinalHashtable

        $startCursor = 0
        foreach ($item in (Sort-UsageRangeItemsLinear -Items $items -TimeProperty 'startTime')) {
            while ($startCursor -lt $samples.Count -and $samples[$startCursor].sampleTime -lt $item.startTime) {
                $startCursor++
            }
            $firstIndexes[[string] $item.intervalIndex] = $startCursor
        }

        $endCursor = 0
        foreach ($item in (Sort-UsageRangeItemsLinear -Items $items -TimeProperty 'endTime')) {
            while ($endCursor -lt $samples.Count -and $samples[$endCursor].sampleTime -le $item.endTime) {
                $endCursor++
            }
            $lastExclusiveIndexes[[string] $item.intervalIndex] = $endCursor
        }

        foreach ($item in $items) {
            $first = [int] $firstIndexes[[string] $item.intervalIndex]
            $lastExclusive = [int] $lastExclusiveIndexes[[string] $item.intervalIndex]
            $plan[[string] $item.intervalIndex] = [pscustomobject][ordered]@{
                bucket = $bucket
                samples = $samples
                firstIndex = $first
                lastIndex = $lastExclusive - 1
                count = [Math]::Max(0, $lastExclusive - $first)
            }
        }
    }
    return $plan
}

function Get-UsageBoundaryResult {
    param(
        [Parameter(Mandatory)] [object] $Interval,
        [AllowNull()] [object] $StartRecord,
        [AllowNull()] [object] $EndRecord,
        [Parameter(Mandatory)] [string] $Role,
        [Parameter(Mandatory)] [hashtable] $UsageIndex,
        [AllowNull()] [object] $UsageRange,
        [AllowNull()] [object] $StorySpan,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    $identity = [string] $Interval.identity
    $startEvent = if ($null -ne $StartRecord) { $StartRecord.Event } else { $null }
    $endEvent = if ($null -ne $EndRecord) { $EndRecord.Event } else { $null }
    $startUsage = if ($null -ne $startEvent) { Get-PropertyValue $startEvent 'usage' } else { $null }
    $endUsage = if ($null -ne $endEvent) { Get-PropertyValue $endEvent 'usage' } else { $null }
    $startState = if ($null -ne $startUsage) { [string] (Get-PropertyValue $startUsage 'state') } else { $null }
    $endState = if ($null -ne $endUsage) { [string] (Get-PropertyValue $endUsage 'state') } else { $null }

    $result = [ordered]@{
        identity = $identity
        role = $Role
        intervalState = [string] $Interval.state
        startUtc = $Interval.startUtc
        endUtc = $Interval.endUtc
        state = 'unavailable'
        value = $null
        streamId = $null
        sessionId = $null
        eventSessionId = $null
        sessionBinding = $null
        source = $null
        workerId = $null
        counterSemantics = $null
        baselineAtUtc = $null
        startSampledAtUtc = if ($null -ne $startUsage) { Get-PropertyValue $startUsage 'sampledAtUtc' } else { $null }
        endSampledAtUtc = if ($null -ne $endUsage) { Get-PropertyValue $endUsage 'sampledAtUtc' } else { $null }
        startCounters = if ($null -ne $startUsage) { Get-PropertyValue $startUsage 'counters' } else { $null }
        endCounters = if ($null -ne $endUsage) { Get-PropertyValue $endUsage 'counters' } else { $null }
        deltas = $null
        components = $null
        coverage = 'no attributable numeric usage samples at both interval boundaries'
        missingData = $null
    }

    if ($null -eq $startUsage -and $null -eq $endUsage) {
        $result.missingData = 'usage is unavailable at both interval boundaries'
        return [pscustomobject] $result
    }
    if ($null -eq $startUsage -or $null -eq $endUsage) {
        $result.state = 'partial'
        $result.coverage = 'only one interval boundary has a usage sample'
        $result.missingData = 'both exact interval-boundary usage samples are required'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_missing_boundary' -Message 'A source-backed usage interval is missing one exact boundary sample' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }

    $startCounters = Get-PropertyValue $startUsage 'counters'
    $endCounters = Get-PropertyValue $endUsage 'counters'
    $startNumeric = $null -ne $startCounters -and @($startCounters.PSObject.Properties).Count -gt 0
    $endNumeric = $null -ne $endCounters -and @($endCounters.PSObject.Properties).Count -gt 0
    if (-not $startNumeric -or -not $endNumeric) {
        $result.missingData = 'numeric counters are unavailable at one or both interval boundaries'
        $result.coverage = 'usage provenance exists but numeric counters are not attributable at both boundaries'
        if ($startState -ne 'unavailable' -or $endState -ne 'unavailable') {
            $result.state = 'partial'
        }
        return [pscustomobject] $result
    }

    $rawBoundaryDeltas = [ordered]@{}
    foreach ($counterName in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')) {
        $startCounter = Get-UsageCounter -Usage $startUsage -Name $counterName
        $endCounter = Get-UsageCounter -Usage $endUsage -Name $counterName
        if ($startCounter.present -and $endCounter.present -and $endCounter.value -ge $startCounter.value) {
            $rawBoundaryDeltas[$counterName] = $endCounter.value - $startCounter.value
        }
    }
    $result.deltas = [pscustomobject] $rawBoundaryDeltas

    $startRole = [string] (Get-PropertyValue $startUsage 'role')
    $endRole = [string] (Get-PropertyValue $endUsage 'role')
    $startWorker = [string] (Get-PropertyValue $startEvent 'workerId')
    $endWorker = [string] (Get-PropertyValue $endEvent 'workerId')
    $startEventSession = [string] (Get-PropertyValue $startEvent 'sessionId')
    $endEventSession = [string] (Get-PropertyValue $endEvent 'sessionId')
    $startStream = [string] (Get-PropertyValue $startUsage 'streamId')
    $endStream = [string] (Get-PropertyValue $endUsage 'streamId')
    $startSource = [string] (Get-PropertyValue $startUsage 'source')
    $endSource = [string] (Get-PropertyValue $endUsage 'source')
    $startUsageSession = [string] (Get-PropertyValue $startUsage 'sessionId')
    $endUsageSession = [string] (Get-PropertyValue $endUsage 'sessionId')
    $startSession = $startUsageSession
    $endSession = $endUsageSession
    if ([string]::IsNullOrWhiteSpace($startSession) -and $null -ne $startEvent) {
        $startSession = [string] (Get-PropertyValue $startEvent 'sessionId')
    }
    if ([string]::IsNullOrWhiteSpace($endSession) -and $null -ne $endEvent) {
        $endSession = $endEventSession
    }
    $startSemantics = Get-PropertyValue $startUsage 'counterSemantics'
    $endSemantics = Get-PropertyValue $endUsage 'counterSemantics'
    $cachedInput = [string] (Get-PropertyValue $startSemantics 'cachedInput')
    $reasoning = [string] (Get-PropertyValue $startSemantics 'reasoning')
    $startCachedInput = [string] (Get-PropertyValue $startSemantics 'cachedInput')
    $endCachedInput = [string] (Get-PropertyValue $endSemantics 'cachedInput')
    $startReasoning = [string] (Get-PropertyValue $startSemantics 'reasoning')
    $endReasoning = [string] (Get-PropertyValue $endSemantics 'reasoning')
    $result.streamId = if ($startStream -eq $endStream) { $startStream } else { $null }
    $result.sessionId = if ($startSession -eq $endSession) { $startSession } else { $null }
    $result.eventSessionId = if ($startEventSession -eq $endEventSession) { $startEventSession } else { $null }
    $result.sessionBinding = [pscustomobject][ordered]@{
        eventSessionId = $result.eventSessionId
        usageSessionId = $result.sessionId
    }
    $result.source = if ($startSource -eq $endSource) { $startSource } else { $null }
    $result.workerId = if ($startWorker -eq $endWorker) { $startWorker } else { $null }
    $result.counterSemantics = [pscustomobject][ordered]@{ cachedInput = $cachedInput; reasoning = $reasoning }
    $result.baselineAtUtc = Get-PropertyValue $startUsage 'baselineAtUtc'

    $startSynthetic = Get-PropertyValue (Get-PropertyValue $startEvent 'provenance') 'synthetic'
    $endSynthetic = Get-PropertyValue (Get-PropertyValue $endEvent 'provenance') 'synthetic'
    if ($startSynthetic -ne $true -or $endSynthetic -ne $true) {
        $result.state = if ($startSynthetic -eq $true -or $endSynthetic -eq $true) { 'partial' } else { 'unavailable' }
        $result.missingData = 'usage authority was not established by an explicitly classified synthetic fixture or an authorized source capability'
        $result.coverage = 'numeric counters were retained as raw evidence but not treated as authoritative usage'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_source_unavailable' -Message 'Numeric usage from an unproven or unavailable source capability was not treated as authoritative' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }

    $bindingConflict = $startRole -cne $Role -or $endRole -cne $Role -or
        $startRole -cne $endRole -or $startStream -cne $endStream -or
        $startUsageSession -cne $endUsageSession -or
        $startEventSession -cne $endEventSession -or
        [string]::IsNullOrWhiteSpace($startUsageSession) -or
        [string]::IsNullOrWhiteSpace($endUsageSession) -or
        [string]::IsNullOrWhiteSpace($startEventSession) -or
        [string]::IsNullOrWhiteSpace($endEventSession) -or
        $startSource -cne $endSource -or
        $startWorker -cne $endWorker -or
        $startSession -cne $endSession
    $semanticsConflict = $startCachedInput -cne $endCachedInput -or $startReasoning -cne $endReasoning
    if ($bindingConflict) {
        $result.state = 'partial'
        $result.missingData = 'usage role, worker, stream, session, source, or event-session provenance changed or was missing between exact boundaries'
        $result.coverage = 'boundary samples do not share one attributable source worker stream and stable event-session binding'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_stream_conflict' -Message 'Usage boundary samples changed or omitted their attributable role, worker, stream, session, source, or event-session provenance' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }
    if ($semanticsConflict) {
        $result.state = 'partial'
        $result.missingData = 'counter semantics changed between exact boundaries'
        $result.coverage = 'boundary samples do not share one counter interpretation'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_semantics_conflict' -Message 'Usage boundary samples changed cached-input or reasoning semantics' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }
    if ($cachedInput -eq 'unknown' -or $reasoning -eq 'unknown') {
        $result.state = 'partial'
        $result.missingData = 'counter semantics are unknown'
        $result.coverage = 'raw counters retained but the subtotal interpretation is unknown'
        return [pscustomobject] $result
    }

    $startTime = [DateTimeOffset]::MinValue
    $endTime = [DateTimeOffset]::MinValue
    $startSampleTime = [DateTimeOffset]::MinValue
    $endSampleTime = [DateTimeOffset]::MinValue
    $startBaselineTime = [DateTimeOffset]::MinValue
    $endBaselineTime = [DateTimeOffset]::MinValue
    $timesValid = (Try-GetUtcTime -Value $Interval.startUtc -Parsed ([ref] $startTime)) -and
        (Try-GetUtcTime -Value $Interval.endUtc -Parsed ([ref] $endTime)) -and
        (Try-GetUtcTime -Value (Get-PropertyValue $startUsage 'sampledAtUtc') -Parsed ([ref] $startSampleTime)) -and
        (Try-GetUtcTime -Value (Get-PropertyValue $endUsage 'sampledAtUtc') -Parsed ([ref] $endSampleTime)) -and
        (Try-GetUtcTime -Value (Get-PropertyValue $startUsage 'baselineAtUtc') -Parsed ([ref] $startBaselineTime)) -and
        (Try-GetUtcTime -Value (Get-PropertyValue $endUsage 'baselineAtUtc') -Parsed ([ref] $endBaselineTime))
    $requiredCounters = [System.Collections.Generic.List[string]]::new()
    [void] $requiredCounters.Add('inputTokens')
    [void] $requiredCounters.Add('outputTokens')
    if ($cachedInput -eq 'disjoint_from_input') { [void] $requiredCounters.Add('cachedInputTokens') }
    if ($reasoning -eq 'disjoint_from_output') { [void] $requiredCounters.Add('reasoningTokens') }
    $boundaryDeltas = [ordered]@{}
    foreach ($counterName in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')) {
        $startCounter = Get-UsageCounter -Usage $startUsage -Name $counterName
        $endCounter = Get-UsageCounter -Usage $endUsage -Name $counterName
        if ($startCounter.present -and $endCounter.present -and $endCounter.value -ge $startCounter.value) {
            $boundaryDeltas[$counterName] = $endCounter.value - $startCounter.value
        }
    }
    $result.deltas = [pscustomobject] $boundaryDeltas
    $intermediateProblem = $false
    $intermediateProblemMessage = $null
    if ($timesValid) {
        if ($null -ne $usageRange -and [int] $usageRange.count -gt 0) {
            $bucket = $usageRange.bucket
            $samples = $usageRange.samples
            $firstSample = $samples[$usageRange.firstIndex]
            $firstEventId = [string] $firstSample.record.EventId
            if ($firstSample.sessionId -cne $startSession -or $firstSample.workerId -cne $startWorker) {
                $intermediateProblem = $true
                $intermediateProblemMessage = 'worker or session provenance changed within the attributable window'
                [void] $Anomalies.Add((New-Anomaly -Code 'usage_stream_conflict' -Message 'An intermediate usage sample changed worker or session provenance' -Identity $identity -EventIds @($firstEventId)))
            }
            if ([string] (Get-PropertyValue $firstSample.semantics 'cachedInput') -cne $cachedInput -or
                [string] (Get-PropertyValue $firstSample.semantics 'reasoning') -cne $reasoning) {
                $intermediateProblem = $true
                $intermediateProblemMessage = 'counter semantics changed within the attributable window'
                [void] $Anomalies.Add((New-Anomaly -Code 'usage_intermediate_conflict' -Message 'An intermediate usage sample changed counter semantics' -Identity $identity -EventIds @($firstEventId)))
            }

            $issueIndex = Find-FirstUsageIssueIndex -NextIssue $bucket.sameTimeConflictNext -StartIndex $usageRange.firstIndex -EndIndex $usageRange.lastIndex
            if ($issueIndex -ge 0) {
                $intermediateProblem = $true
                $intermediateProblemMessage = 'same-time usage snapshots disagree on worker, session, semantics, or counters'
                [void] $Anomalies.Add((New-Anomaly -Code 'usage_intermediate_conflict' -Message 'Same-time usage snapshots disagree and cannot establish one cumulative sequence' -Identity $identity -EventIds @([string] $samples[$issueIndex].record.EventId)))
            }
            $edgeStartIndex = $usageRange.firstIndex + 1
            $issueIndex = Find-FirstUsageIssueIndex -NextIssue $bucket.edgeStreamNext -StartIndex $edgeStartIndex -EndIndex $usageRange.lastIndex
            if ($issueIndex -ge 0) {
                $intermediateProblem = $true
                $intermediateProblemMessage = 'worker or session provenance changed within the attributable window'
                [void] $Anomalies.Add((New-Anomaly -Code 'usage_stream_conflict' -Message 'An intermediate usage sample changed worker or session provenance' -Identity $identity -EventIds @([string] $samples[$issueIndex - 1].record.EventId, [string] $samples[$issueIndex].record.EventId)))
            }
            $issueIndex = Find-FirstUsageIssueIndex -NextIssue $bucket.edgeSemanticsNext -StartIndex $edgeStartIndex -EndIndex $usageRange.lastIndex
            if ($issueIndex -ge 0) {
                $intermediateProblem = $true
                $intermediateProblemMessage = 'counter semantics changed within the attributable window'
                [void] $Anomalies.Add((New-Anomaly -Code 'usage_intermediate_conflict' -Message 'An intermediate usage sample changed counter semantics' -Identity $identity -EventIds @([string] $samples[$issueIndex - 1].record.EventId, [string] $samples[$issueIndex].record.EventId)))
            }
            $issueIndex = Find-FirstUsageIssueIndex -NextIssue $bucket.edgeResetNext -StartIndex $edgeStartIndex -EndIndex $usageRange.lastIndex
            if ($issueIndex -ge 0) {
                $intermediateProblem = $true
                $intermediateProblemMessage = 'a cumulative counter decreased at an intermediate usage sample'
                [void] $Anomalies.Add((New-Anomaly -Code 'usage_counter_reset' -Message 'An intermediate cumulative usage sample decreased; the whole window crosses a reset segment' -Identity $identity -EventIds @([string] $samples[$issueIndex - 1].record.EventId, [string] $samples[$issueIndex].record.EventId)))
            }
            foreach ($requiredCounter in @($requiredCounters)) {
                $nextIssue = switch ($requiredCounter) {
                    'inputTokens' { $bucket.missingInputNext }
                    'cachedInputTokens' { $bucket.missingCachedInputNext }
                    'outputTokens' { $bucket.missingOutputNext }
                    'reasoningTokens' { $bucket.missingReasoningNext }
                }
                $issueIndex = Find-FirstUsageIssueIndex -NextIssue $nextIssue -StartIndex $usageRange.firstIndex -EndIndex $usageRange.lastIndex
                if ($issueIndex -ge 0) {
                    $intermediateProblem = $true
                    $intermediateProblemMessage = 'a required counter is absent from an intermediate usage sample'
                    [void] $Anomalies.Add((New-Anomaly -Code 'usage_missing_intermediate_counter' -Message 'An intermediate usage sample omitted a counter required by the declared semantics' -Identity $identity -EventIds @([string] $samples[$issueIndex].record.EventId)))
                }
            }
        }
    }
    if ($intermediateProblem) {
        $result.state = 'partial'
        $result.missingData = $intermediateProblemMessage
        $result.coverage = 'ordered intermediate usage samples prevent a complete attributable cumulative delta'
        return [pscustomobject] $result
    }
    $storyWindowValid = $false
    $storyStartTime = [DateTimeOffset]::MinValue
    $storyEndTime = [DateTimeOffset]::MinValue
    $runWindowProblem = $false
    $runWindowProblemMessage = $null
    if ($null -ne $StorySpan -and [string] $StorySpan.state -eq 'measured') {
        $storyWindowValid = (Try-GetUtcTime -Value $StorySpan.startUtc -Parsed ([ref] $storyStartTime)) -and
            (Try-GetUtcTime -Value $StorySpan.endUtc -Parsed ([ref] $storyEndTime))
    }
    if (-not $storyWindowValid) {
        $runWindowProblem = $true
        $runWindowProblemMessage = 'story run boundaries are unavailable for source-backed usage attribution'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_run_window_unavailable' -Message 'Source-backed usage was not attributed without measured story start and confirmed PR boundaries' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
    }
    if ($storyWindowValid -and ($startTime -lt $storyStartTime -or $endTime -gt $storyEndTime)) {
        $runWindowProblem = $true
        $runWindowProblemMessage = 'usage interval straddles the story run start or confirmed PR boundary'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_interval_outside_run' -Message 'A usage interval crosses the measured story run window and was excluded from the numeric total' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
    }
    if ($storyWindowValid -and ($startSampleTime -gt $storyEndTime -or $endSampleTime -gt $storyEndTime)) {
        $runWindowProblem = $true
        $runWindowProblemMessage = 'usage sample occurs after the confirmed PR boundary'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_sample_after_run' -Message 'A usage sample after the confirmed PR boundary was excluded from the story total' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
    }
    if ($timesValid -and ($startSampleTime -gt $endTime -or $endSampleTime -gt $endTime)) {
        $result.state = 'partial'
        $result.missingData = 'usage sample occurs after the attributable interval'
        $result.coverage = 'post-boundary samples were excluded'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_sample_after_boundary' -Message 'A usage sample after the attributable interval was excluded' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }
    if (-not $timesValid -or $startSampleTime -ne $startTime -or $endSampleTime -ne $endTime -or
        $startBaselineTime -ne $startTime -or $endBaselineTime -ne $startTime) {
        $result.state = 'partial'
        $result.missingData = 'usage samples must have exact interval boundaries and one exact baselineAtUtc'
        $result.coverage = 'numeric samples exist but boundary attribution is not exact'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_boundary_mismatch' -Message 'Usage samples were not observed at the exact interval boundaries or shared exact baseline' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }
    $deltas = [ordered]@{}
    $reset = $false
    $missingCounter = $false
    foreach ($counterName in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens')) {
        $startCounter = Get-UsageCounter -Usage $startUsage -Name $counterName
        $endCounter = Get-UsageCounter -Usage $endUsage -Name $counterName
        if ($startCounter.present -and $endCounter.present) {
            if ($endCounter.value -lt $startCounter.value) {
                $reset = $true
            }
            else {
                $deltas[$counterName] = $endCounter.value - $startCounter.value
            }
        }
        elseif ($counterName -in $requiredCounters) {
            $missingCounter = $true
        }
    }
    $result.deltas = [pscustomobject] $deltas
    if ($reset) {
        $result.state = 'partial'
        $result.missingData = 'a cumulative counter decreased between exact boundaries; reset segment is unknown'
        $result.coverage = 'counter reset was not clamped to zero'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_counter_reset' -Message 'A cumulative usage counter decreased between exact boundaries; the affected segment is unknown' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }
    if ($missingCounter) {
        $result.state = 'partial'
        $result.missingData = 'one or more counters required by the declared semantics are missing at a boundary'
        $result.coverage = 'known raw counter deltas are retained but the role subtotal is incomplete'
        [void] $Anomalies.Add((New-Anomaly -Code 'usage_missing_counter' -Message 'A required usage counter was absent at one exact boundary' -Identity $identity -EventIds @($Interval.startEventId, $Interval.endEventId | Where-Object { $null -ne $_ })))
        return [pscustomobject] $result
    }
    if ($runWindowProblem) {
        $result.state = 'partial'
        $result.missingData = $runWindowProblemMessage
        $result.coverage = 'numeric usage exists but cannot be fully bounded to the story run window'
        return [pscustomobject] $result
    }
    if ($Interval.state -ne 'measured' -or $startState -ne 'measured' -or $endState -ne 'measured') {
        $result.state = 'partial'
        $result.missingData = if ($Interval.state -ne 'measured') { [string] $Interval.missingData } else { 'one or both source usage samples are partial' }
        $result.coverage = 'numeric usage exists but the interval or source sample is not fully measured'
        return [pscustomobject] $result
    }

    $inputComponent = [long] $deltas.inputTokens
    if ($cachedInput -eq 'disjoint_from_input') { $inputComponent += [long] $deltas.cachedInputTokens }
    $outputComponent = [long] $deltas.outputTokens
    if ($reasoning -eq 'disjoint_from_output') { $outputComponent += [long] $deltas.reasoningTokens }
    $total = $inputComponent + $outputComponent
    $result.state = 'measured'
    $result.value = $total
    $result.components = [pscustomobject][ordered]@{
        input = $inputComponent
        output = $outputComponent
        total = $total
    }
    $result.coverage = 'both exact interval boundaries have attributable cumulative samples with stable semantics'
    $result.missingData = $null
    return [pscustomobject] $result
}

function Get-UsageAttributionKey {
    param([Parameter(Mandatory)] [object] $Evidence)

    return ConvertTo-IdentityTupleKey ([string] $Evidence.role) ([string] $Evidence.workerId) ([string] $Evidence.sessionId)
}

function Get-UsageEvidenceWindowKey {
    param([Parameter(Mandatory)] [object] $Evidence)

    return ConvertTo-IdentityTupleKey `
        ([string] $Evidence.startUtc) `
        ([string] $Evidence.endUtc) `
        (ConvertTo-CanonicalJson -Value ([ordered]@{
                source = $Evidence.source
                streamId = $Evidence.streamId
                deltas = $Evidence.deltas
                components = $Evidence.components
                counterSemantics = $Evidence.counterSemantics
            }))
}

function Set-UsageEvidenceConflict {
    param(
        [Parameter(Mandatory)] [object[]] $Entries,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies,
        [Parameter(Mandatory)] [string] $Message
    )

    foreach ($entry in $Entries) {
        $entry.state = 'partial'
        $entry.countable = $false
        $entry.missingData = $Message
    }
    [void] $Anomalies.Add((New-Anomaly -Code 'overlapping_usage_window' -Message 'Overlapping source-backed usage windows were not summed because their attribution may double-count cumulative counters' -Identity (@($Entries | ForEach-Object { [string] $_.identity }) -join '|')))
}

function Resolve-UsageStreamOverlapClusters {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    $orderedItems = @($Entries | ForEach-Object {
            [pscustomobject]@{
                evidence = $_
                start = [DateTimeOffset]::Parse([string] $_.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                end = [DateTimeOffset]::Parse([string] $_.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            }
        } | Where-Object { $_.start -lt $_.end })
    $ordered = @(Sort-TimeWindowItemsLinear -Items $orderedItems)
    $cluster = [System.Collections.Generic.List[object]]::new()
    $clusterEnd = [DateTimeOffset]::MinValue
    $flush = {
        if ($cluster.Count -le 1) { return }
        $clusterEvidence = @($cluster | ForEach-Object { $_.evidence })
        $windowKeys = @(Get-UniqueValuesLinear -Values @($clusterEvidence | ForEach-Object { Get-UsageEvidenceWindowKey -Evidence $_ }))
        if ($windowKeys.Count -eq 1) {
            $first = $clusterEvidence[0]
            for ($duplicateIndex = 1; $duplicateIndex -lt $clusterEvidence.Count; $duplicateIndex++) {
                $duplicate = $clusterEvidence[$duplicateIndex]
                $duplicate.countable = $false
                $duplicate | Add-Member -NotePropertyName duplicateOf -NotePropertyValue $first.identity -Force
                [void] $Anomalies.Add((New-Anomaly -Code 'duplicate_usage_window' -Message 'An identical source-backed usage window was retained once for token totals' -Identity "$($first.identity)|$($duplicate.identity)"))
            }
        }
        else {
            Set-UsageEvidenceConflict -Entries $clusterEvidence -Anomalies $Anomalies -Message 'overlapping source-backed usage windows are ambiguous and were not summed'
        }
    }
    foreach ($item in $ordered) {
        if ($cluster.Count -gt 0 -and $item.start -ge $clusterEnd) {
            & $flush
            $cluster = [System.Collections.Generic.List[object]]::new()
            $clusterEnd = [DateTimeOffset]::MinValue
        }
        [void] $cluster.Add($item)
        if ($item.end -gt $clusterEnd) { $clusterEnd = $item.end }
    }
    & $flush
}

function Resolve-UsageEvidence {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[object]] $Evidence,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    foreach ($item in $Evidence) {
        $item | Add-Member -NotePropertyName countable -NotePropertyValue $true -Force
    }
    $eligible = @($Evidence | Where-Object {
            $_.state -ne 'unavailable' -and
            -not [string]::IsNullOrWhiteSpace([string] $_.startUtc) -and
            -not [string]::IsNullOrWhiteSpace([string] $_.endUtc) -and
            $null -ne $_.deltas
        })
    foreach ($attributionGroup in @(Group-ValuesLinear -Values $eligible -KeySelector { param($evidence) Get-UsageAttributionKey -Evidence $evidence })) {
        $orderedItems = @($attributionGroup.Group | ForEach-Object {
                [pscustomobject]@{
                    evidence = $_
                    start = [DateTimeOffset]::Parse([string] $_.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                    end = [DateTimeOffset]::Parse([string] $_.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                }
            })
        $ordered = @(Sort-TimeWindowItemsLinear -Items $orderedItems | ForEach-Object { $_.evidence })
        $cluster = [System.Collections.Generic.List[object]]::new()
        $clusterEnd = [DateTimeOffset]::MinValue
        $flush = {
            if ($cluster.Count -le 1) { return }
            $clusterEvidence = @($cluster)
            $sourceKeys = @(Get-UniqueValuesLinear -Values @($clusterEvidence | ForEach-Object { [string] $_.source }))
            if ($sourceKeys.Count -gt 1) {
                Set-UsageEvidenceConflict -Entries $clusterEvidence -Anomalies $Anomalies -Message 'overlapping source-backed usage windows have multiple sources and were not summed'
                return
            }
            foreach ($streamGroup in @(Group-ValuesLinear -Values $clusterEvidence -KeySelector { param($evidence) [string] $evidence.streamId })) {
                Resolve-UsageStreamOverlapClusters -Entries @($streamGroup.Group) -Anomalies $Anomalies
            }
        }
        foreach ($entry in $ordered) {
            $start = [DateTimeOffset]::Parse([string] $entry.startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $end = [DateTimeOffset]::Parse([string] $entry.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            if ($start -ge $end) { continue }
            if ($cluster.Count -gt 0 -and $start -ge $clusterEnd) {
                & $flush
                $cluster = [System.Collections.Generic.List[object]]::new()
                $clusterEnd = [DateTimeOffset]::MinValue
            }
            [void] $cluster.Add($entry)
            if ($end -gt $clusterEnd) { $clusterEnd = $end }
        }
        & $flush
    }
    return $Evidence
}

function Get-UsageMetric {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Intervals,
        [Parameter(Mandatory)] [string] $Role,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $NoDataMessage,
        [Parameter(Mandatory)] [hashtable] $RecordsByEventId,
        [Parameter(Mandatory)] [hashtable] $UsageIndex,
        [AllowNull()] [object] $StorySpan,
        [Parameter(Mandatory)] [AllowNull()] [object] $Anomalies
    )

    $evidence = [System.Collections.Generic.List[object]]::new()
    $usageRangePlan = New-UsageRangePlan -Intervals @($Intervals) -RecordsByEventId $RecordsByEventId -UsageIndex $UsageIndex
    for ($intervalIndex = 0; $intervalIndex -lt $Intervals.Count; $intervalIndex++) {
        $interval = $Intervals[$intervalIndex]
        $startRecord = if ($null -ne $interval.startEventId -and $RecordsByEventId.ContainsKey([string] $interval.startEventId)) { $RecordsByEventId[[string] $interval.startEventId] } else { $null }
        $endRecord = if ($null -ne $interval.endEventId -and $RecordsByEventId.ContainsKey([string] $interval.endEventId)) { $RecordsByEventId[[string] $interval.endEventId] } else { $null }
        $usageRange = if ($usageRangePlan.ContainsKey([string] $intervalIndex)) { $usageRangePlan[[string] $intervalIndex] } else { $null }
        [void] $evidence.Add((Get-UsageBoundaryResult -Interval $interval -StartRecord $startRecord -EndRecord $endRecord -Role $Role -UsageIndex $UsageIndex -UsageRange $usageRange -StorySpan $StorySpan -Anomalies $Anomalies))
    }
    [void] (Resolve-UsageEvidence -Evidence $evidence -Anomalies $Anomalies)

    if ($evidence.Count -eq 0) {
        $metric = New-Metric -State 'unavailable' -Value $null -Unit 'tokens' -Source $Source -Calculation 'sum source-backed cumulative deltas by attributable stream' -Coverage 'no attributable intervals for this role' -MissingData $NoDataMessage
    }
    else {
        $countableEvidence = @($evidence | Where-Object { $_.countable -ne $false })
        $measured = @($countableEvidence | Where-Object { $_.state -eq 'measured' })
        $partial = @($evidence | Where-Object { $_.state -eq 'partial' })
        $unavailable = @($evidence | Where-Object { $_.state -eq 'unavailable' })
        if ($partial.Count -gt 0 -or ($unavailable.Count -gt 0 -and $measured.Count -gt 0)) {
            $metric = New-Metric -State 'partial' -Value $null -Unit 'tokens' -Source $Source -Calculation 'sum source-backed cumulative deltas by attributable stream' -Coverage "$($measured.Count) of $($evidence.Count) intervals have complete source-backed deltas" -MissingData "$($partial.Count) partial and $($unavailable.Count) unavailable interval(s) lack complete boundary, semantic, or counter evidence"
        }
        elseif ($measured.Count -eq 0) {
            $metric = New-Metric -State 'unavailable' -Value $null -Unit 'tokens' -Source $Source -Calculation 'sum source-backed cumulative deltas by attributable stream' -Coverage 'intervals exist but no complete source-backed delta is available' -MissingData 'source-backed usage is unavailable at the required boundaries'
        }
        else {
            $sum = [long] (($measured | Measure-Object -Property value -Sum).Sum)
            $metric = New-Metric -State 'measured' -Value $sum -Unit 'tokens' -Source $Source -Calculation 'sum source-backed cumulative deltas by attributable stream' -Coverage "all $($evidence.Count) intervals have complete source-backed deltas" -MissingData $null
        }
    }
    $metric | Add-Member -NotePropertyName role -NotePropertyValue $Role -Force
    $metric | Add-Member -NotePropertyName evidence -NotePropertyValue @($evidence) -Force
    return $metric
}

function Get-TotalUsageMetric {
    param(
        [Parameter(Mandatory)] [object[]] $RoleMetrics
    )

    $measured = @($RoleMetrics | Where-Object { $_.state -eq 'measured' })
    $partial = @($RoleMetrics | Where-Object { $_.state -eq 'partial' })
    if ($measured.Count -eq $RoleMetrics.Count -and $RoleMetrics.Count -gt 0) {
        $value = [long] (($measured | Measure-Object -Property value -Sum).Sum)
        $state = 'measured'
        $coverage = 'all attributable role totals are measured'
        $missing = $null
    }
    elseif ($measured.Count -gt 0 -or $partial.Count -gt 0) {
        $value = $null
        $state = 'partial'
        $coverage = "$($measured.Count) of $($RoleMetrics.Count) role totals are measured"
        $missing = 'one or more attributable role totals are partial or unavailable; unavailable is not treated as zero'
    }
    else {
        $value = $null
        $state = 'unavailable'
        $coverage = 'no attributable role total is measured'
        $missing = 'source-backed role usage is unavailable'
    }
    $metric = New-Metric -State $state -Value $value -Unit 'tokens' -Source 'implementationTokens + reviewTokens + coordinationTokens' -Calculation 'sum attributable role totals without treating unavailable roles as zero' -Coverage $coverage -MissingData $missing
    $metric | Add-Member -NotePropertyName roleStates -NotePropertyValue @($RoleMetrics | ForEach-Object { [pscustomobject][ordered]@{ role = $_.role; state = $_.state; value = $_.value } }) -Force
    return $metric
}

function New-UnavailableMetadataMetric {
    return New-Metric -State 'unavailable' -Value $null -Unit 'metadata records' -Source 'setup/host provenance' -Calculation 'copy exact role/model/reasoning profile records' -Coverage 'the v1 event envelope exposes no model or reasoning-effort profile fields' -MissingData 'models and reasoning profiles were not source-backed for this run'
}

function New-SetupMetadataMetric {
    param([Parameter(Mandatory)] [object] $SetupMetadata)

    if ([string] $SetupMetadata.state -eq 'unavailable') {
        return New-UnavailableMetadataMetric
    }
    $records = @($SetupMetadata.records)
    $roles = @(Get-UniqueValuesLinear -Values @($records | ForEach-Object { [string] $_.role }))
    $changes = @($records | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_.changeId) })
    $metric = New-Metric -State ([string] $SetupMetadata.state) -Value $records -Unit 'metadata records' -Source ([string] $SetupMetadata.source) -Calculation 'retain exact role/worker/model/effort records and ordered profile changes' -Coverage ([string] $SetupMetadata.coverage) -MissingData ([string] $SetupMetadata.missingData)
    $metric | Add-Member -NotePropertyName roleCount -NotePropertyValue $roles.Count -Force
    $metric | Add-Member -NotePropertyName changeCount -NotePropertyValue $changes.Count -Force
    $metric | Add-Member -NotePropertyName missingRoles -NotePropertyValue @((Get-PropertyValue $SetupMetadata 'missingRoles')) -Force
    return $metric
}

function Get-TasksCompletedMetric {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[int]] $DeclaredTaskRefs,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $ReviewIntervals,
        [string] $Mode,
        [AllowEmptyCollection()] [object[]] $ImplementationIntervals = @(),
        [AllowEmptyCollection()] [object[]] $TaskOutcomes = @()
    )

    $acceptedTaskRefs = @(Get-UniqueValuesLinear -Values @($ReviewIntervals |
        Where-Object {
            [string] $_.scope -eq 'task' -and
            $null -ne $_.taskRef -and
            [string] $_.closureEventType -eq 'review_accepted' -and
            $_.state -eq 'measured'
        } |
        ForEach-Object { [int] $_.taskRef }))
    $outcomeTaskRefs = @($TaskOutcomes | ForEach-Object { [int] $_.taskRef })
    $acceptedTaskRefs = @($acceptedTaskRefs | Where-Object { $_ -in $DeclaredTaskRefs -and $_ -notin $outcomeTaskRefs })
    $acceptedTaskRefs = @(Get-UniqueValuesLinear -Values @($acceptedTaskRefs + @($TaskOutcomes | Where-Object { $_.accepted -or $_.isDone } | ForEach-Object { [int] $_.taskRef })))
    $readyTaskRefs = @(Get-UniqueValuesLinear -Values @($ImplementationIntervals | Where-Object { $_.kind -eq 'implementation' -and $null -ne $_.endEventId -and $_.taskRef -in $DeclaredTaskRefs } | ForEach-Object { [int] $_.taskRef }))
    $acceptedTaskRefSet = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($acceptedTaskRef in $acceptedTaskRefs) {
        [void] $acceptedTaskRefSet.Add([int] $acceptedTaskRef)
    }
    $allDeclaredTasksAccepted = $true
    foreach ($declaredTaskRef in $DeclaredTaskRefs) {
        if (-not $acceptedTaskRefSet.Contains([int] $declaredTaskRef)) {
            $allDeclaredTasksAccepted = $false
            break
        }
    }
    $metric = $null
    if ($DeclaredTaskRefs.Count -eq 0) {
        $metric = New-Metric -State 'unavailable' -Value $null -Unit 'tasks' -Source 'declared ordered task identities and authoritative acceptance events' -Calculation 'count accepted task identities in the declared ordered task set' -Coverage 'no ordered task set was supplied' -MissingData 'task completion cannot be attributed without the declared ordered task set'
    }
    elseif ($acceptedTaskRefs.Count -eq $DeclaredTaskRefs.Count -and $acceptedTaskRefs.Count -gt 0 -and $allDeclaredTasksAccepted) {
        $metric = New-Metric -State 'measured' -Value $acceptedTaskRefs.Count -Unit 'tasks' -Source 'declared ordered task identities and authoritative acceptance events' -Calculation 'count accepted task identities in the declared ordered task set' -Coverage "all $($DeclaredTaskRefs.Count) declared task identities have authoritative acceptance/Done evidence" -MissingData $null
    }
    else {
        $metric = New-Metric -State 'partial' -Value $null -Unit 'tasks' -Source 'declared ordered task identities and authoritative acceptance events' -Calculation 'count accepted task identities in the declared ordered task set' -Coverage "$($acceptedTaskRefs.Count) of $($DeclaredTaskRefs.Count) declared task identities have authoritative acceptance/Done evidence" -MissingData 'ordered task set or acceptance evidence is incomplete'
    }
    $knownTaskRefs = @($acceptedTaskRefs + $outcomeTaskRefs)
    $unknownTaskRefs = @($DeclaredTaskRefs | Where-Object { $_ -notin $knownTaskRefs })
    if ($DeclaredTaskRefs.Count -gt 0 -and $unknownTaskRefs.Count -eq 0) {
        $metric = New-Metric -State 'measured' -Value $acceptedTaskRefs.Count -Unit 'tasks' -Source 'declared tasks and authoritative status/acceptance evidence' -Calculation 'count explicit accepted/Done tasks; current task outcomes supersede historical acceptance' -Coverage 'all declared task outcomes are known; a known non-Done task contributes zero' -MissingData $null
    }
    elseif ($Mode -eq 'story_end_only' -and $acceptedTaskRefs.Count -eq 0 -and $outcomeTaskRefs.Count -eq 0) {
        $metric = New-Metric -State 'unavailable' -Value $null -Unit 'tasks' -Source 'authoritative task status/acceptance evidence' -Calculation 'count declared tasks with explicit accepted or Done evidence' -Coverage 'story_end_only has no task-scoped reviews; final-story approval does not imply individual task acceptance' -MissingData 'task outcomes were not observed; absence of per-task reviews does not establish incomplete tasks'
    }
    $metric | Add-Member -NotePropertyName implementationReadyTaskRefs -NotePropertyValue @($readyTaskRefs) -Force
    $metric | Add-Member -NotePropertyName taskOutcomes -NotePropertyValue @($TaskOutcomes) -Force
    $metric | Add-Member -NotePropertyName acceptedTaskRefs -NotePropertyValue @($acceptedTaskRefs) -Force
    return $metric
}

function Get-ComparisonMetrics {
    param(
        [AllowNull()] [string] $BaseRevision,
        [AllowNull()] [string] $ReviewedHead,
        [AllowNull()] [string] $RepositoryPath
    )

    $source = 'exact base-to-reviewed-HEAD Git diff'
    $unavailable = {
        param([string] $MissingData)
        return [pscustomobject][ordered]@{
            changedFiles = New-Metric -State 'unavailable' -Value $null -Unit 'files' -Source $source -Calculation 'count changed paths in exact Git diff' -Coverage 'base or reviewed HEAD is unavailable' -MissingData $MissingData
            linesAdded = New-Metric -State 'unavailable' -Value $null -Unit 'lines' -Source $source -Calculation 'sum added lines from exact Git numstat' -Coverage 'base or reviewed HEAD is unavailable' -MissingData $MissingData
            linesDeleted = New-Metric -State 'unavailable' -Value $null -Unit 'lines' -Source $source -Calculation 'sum deleted lines from exact Git numstat' -Coverage 'base or reviewed HEAD is unavailable' -MissingData $MissingData
        }
    }
    if ([string]::IsNullOrWhiteSpace($BaseRevision) -or [string]::IsNullOrWhiteSpace($ReviewedHead)) {
        return & $unavailable 'base revision or reviewed HEAD was not supplied'
    }
    if (-not (Test-FullRevision $BaseRevision) -or -not (Test-FullRevision $ReviewedHead)) {
        return & $unavailable 'base revision or reviewed HEAD is not a full Git SHA'
    }
    $repository = if ([string]::IsNullOrWhiteSpace($RepositoryPath)) { (Get-Location).Path } else { $RepositoryPath }
    try {
        $repository = [IO.Path]::GetFullPath($repository)
    }
    catch {
        return & $unavailable 'repository path could not be resolved'
    }
    if (-not (Test-Path -LiteralPath $repository -PathType Container)) {
        return & $unavailable 'repository path is not available'
    }

    $diffOutput = @(& git -C $repository --no-pager diff --numstat --no-renames --no-ext-diff $BaseRevision $ReviewedHead -- 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return & $unavailable 'Git could not resolve or compare the supplied base and reviewed HEAD'
    }
    $changedFiles = 0
    $added = [long] 0
    $deleted = [long] 0
    $binary = $false
    foreach ($line in @($diffOutput)) {
        if ([string]::IsNullOrWhiteSpace([string] $line)) { continue }
        $parts = [string] $line -split "`t", 3
        if ($parts.Count -lt 3) {
            return & $unavailable 'Git returned an unparseable numstat record'
        }
        $changedFiles++
        if ($parts[0] -eq '-' -or $parts[1] -eq '-') {
            $binary = $true
            continue
        }
        if ($parts[0] -notmatch '^\d+$' -or $parts[1] -notmatch '^\d+$') {
            return & $unavailable 'Git returned a nonnumeric numstat record'
        }
        try {
            $added += [long] $parts[0]
            $deleted += [long] $parts[1]
        }
        catch {
            return & $unavailable 'Git numstat exceeded the supported integer range'
        }
    }
    $changedMetric = New-Metric -State 'measured' -Value $changedFiles -Unit 'files' -Source $source -Calculation 'count changed paths in exact Git diff' -Coverage "exact $BaseRevision..$ReviewedHead diff" -MissingData $null
    $lineState = if ($binary) { 'partial' } else { 'measured' }
    $lineMissing = if ($binary) { 'one or more binary paths have no line count in Git numstat' } else { $null }
    $lineCoverage = if ($binary) { "exact diff contains $changedFiles path(s); binary line counts are unknown" } else { "exact $BaseRevision..$ReviewedHead diff" }
    return [pscustomobject][ordered]@{
        changedFiles = $changedMetric
        linesAdded = New-Metric -State $lineState -Value $(if ($binary) { $null } else { $added }) -Unit 'lines' -Source $source -Calculation 'sum added lines from exact Git numstat' -Coverage $lineCoverage -MissingData $lineMissing
        linesDeleted = New-Metric -State $lineState -Value $(if ($binary) { $null } else { $deleted }) -Unit 'lines' -Source $source -Calculation 'sum deleted lines from exact Git numstat' -Coverage $lineCoverage -MissingData $lineMissing
    }
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
$initialTaskRefs = @(Get-UniqueValuesLinear -Values @($initialAttempts | Where-Object { $null -ne $_.taskRef } | ForEach-Object { [string] $_.taskRef }))
$recordsByTaskRef = New-OrdinalHashtable
foreach ($record in @($records)) {
    $taskRefValue = Get-PropertyValue $record.Event 'taskRef'
    if ($null -eq $taskRefValue) { continue }
    $taskRefKey = [string] $taskRefValue
    if (-not $recordsByTaskRef.ContainsKey($taskRefKey)) {
        $recordsByTaskRef[$taskRefKey] = [System.Collections.Generic.List[object]]::new()
    }
    [void] $recordsByTaskRef[$taskRefKey].Add($record)
}
foreach ($taskRefKey in @($recordsByTaskRef.Keys)) {
    $recordsByTaskRef[$taskRefKey] = @(Sort-RecordsByTimeLinear -Records @($recordsByTaskRef[$taskRefKey]))
}
$initialAttemptsByTaskRef = New-OrdinalHashtable
foreach ($attempt in @($initialAttempts)) {
    $taskRefKey = [string] $attempt.taskRef
    if (-not $initialAttemptsByTaskRef.ContainsKey($taskRefKey)) {
        $initialAttemptsByTaskRef[$taskRefKey] = [System.Collections.Generic.List[object]]::new()
    }
    [void] $initialAttemptsByTaskRef[$taskRefKey].Add($attempt)
}
foreach ($taskRefKey in @($initialAttemptsByTaskRef.Keys)) {
    $initialAttemptsByTaskRef[$taskRefKey] = @($initialAttemptsByTaskRef[$taskRefKey])
}
$missingInitialReviewTaskRefs = @()
if ($effectiveReviewMode -eq 'per_task' -and $taskSetWasDeclared) {
    $initialTaskRefValues = @($initialTaskRefs | ForEach-Object { [int] $_ })
    $initialTaskRefSet = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($initialTaskRefValue in $initialTaskRefValues) {
        [void] $initialTaskRefSet.Add([int] $initialTaskRefValue)
    }
    $missingInitialReviewTaskRefs = @($declaredTaskRefs | Where-Object { -not $initialTaskRefSet.Contains([int] $_) })
    if ($missingInitialReviewTaskRefs.Count -gt 0) {
        [void] $anomalies.Add((New-Anomaly -Code 'missing_initial_review_evidence' -Message 'Declared per-task identities have no authoritative initial review attempt; observed review denominators remain based on actual initial attempts' -Identity ($missingInitialReviewTaskRefs -join ',')))
        $taskCoverageState = 'partial'
    }
}
$acceptedFirst = 0
$firstPassIncomplete = 0
$firstPassRejected = 0
foreach ($taskRef in $initialTaskRefs) {
    $taskAttempts = if ($initialAttemptsByTaskRef.ContainsKey($taskRef)) { $initialAttemptsByTaskRef[$taskRef] } else { @() }
    $first = $taskAttempts[0]
    if ($first.state -ne 'measured') {
        $firstPassIncomplete++
        continue
    }
    if ([string] $first.closureEventType -eq 'review_accepted') {
        $endTime = [DateTimeOffset]::Parse([string] $first.endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $taskRecords = if ($recordsByTaskRef.ContainsKey($taskRef)) { $recordsByTaskRef[$taskRef] } else { @() }
        $priorFindingOrCorrection = @($taskRecords | Where-Object {
            $_.Time -le $endTime -and $_.EventType -in @('review_findings', 'correction_started')
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

$usageSampleIndex = New-UsageSampleIndex -Records $records
$implementationTokenMetric = Get-UsageMetric -Intervals @($implementationIntervals + $correctionIntervals) -Role 'implementer' -Source 'source-backed implementer usage at implementation/correction boundaries' -NoDataMessage 'no attributable implementer usage interval was recorded' -RecordsByEventId $recordsByEventId -UsageIndex $usageSampleIndex -StorySpan $timeToPrInterval -Anomalies $anomalies
$reviewTokenMetric = Get-UsageMetric -Intervals @($reviewIntervals) -Role 'reviewer' -Source 'source-backed reviewer usage at review-attempt boundaries' -NoDataMessage 'no attributable reviewer usage interval was recorded' -RecordsByEventId $recordsByEventId -UsageIndex $usageSampleIndex -StorySpan $timeToPrInterval -Anomalies $anomalies
$coordinationTokenMetric = Get-UsageMetric -Intervals @($coordinationIntervals) -Role 'coordinator' -Source 'source-backed coordinator usage at coordinator-attributable wait boundaries' -NoDataMessage 'no attributable coordinator usage interval was recorded' -RecordsByEventId $recordsByEventId -UsageIndex $usageSampleIndex -StorySpan $timeToPrInterval -Anomalies $anomalies
$totalTokenMetric = Get-TotalUsageMetric -RoleMetrics @($implementationTokenMetric, $reviewTokenMetric, $coordinationTokenMetric)
$metadataRunId = if ($runIds.Count -eq 1) { [string] $runIds[0] } else { $null }
$metadataProjectId = if ($projectIds.Count -eq 1) { [int] $projectIds[0] } else { $null }
$metadataStoryId = if ($storyIds.Count -eq 1) { [int] $storyIds[0] } else { $null }
if (-not [string]::IsNullOrWhiteSpace($MetadataPath) -and ($null -eq $metadataRunId -or $null -eq $metadataProjectId -or $null -eq $metadataStoryId)) {
    throw [System.ArgumentException]::new('setup_metadata_conflict: metadata requires one unambiguous run/project/story binding')
}
if (-not [string]::IsNullOrWhiteSpace($UsageMetadataPath) -and ($null -eq $metadataRunId -or $null -eq $metadataProjectId -or $null -eq $metadataStoryId)) {
    throw [System.ArgumentException]::new('usage_metadata_conflict: observed role token metadata requires one unambiguous run/project/story binding')
}
$setupMetadata = if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
    Get-SetupMetadata -Path $null -RunId ([string] $metadataRunId) -ProjectId ([int] $metadataProjectId) -StoryId ([int] $metadataStoryId)
}
else {
    Get-SetupMetadata -Path $MetadataPath -RunId $metadataRunId -ProjectId $metadataProjectId -StoryId $metadataStoryId
}
$modelsAndReasoningMetric = New-SetupMetadataMetric -SetupMetadata $setupMetadata
$observedUsageMetadata = Get-ObservedRoleUsageMetadata -Path $UsageMetadataPath -RunId ([string] $metadataRunId) -ProjectId ([int] $metadataProjectId) -StoryId ([int] $metadataStoryId)
$observedImplementerTokenMetric = if ($null -eq $observedUsageMetadata) { New-Metric -State 'unavailable' -Value $null -Unit 'tokens' -Source 'incremental observed Codex session counters' -Calculation 'subtract cumulative counters at story boundaries' -Coverage 'no observed role token metadata was supplied' -MissingData 'run collect-role-token-usage.ps1 and pass UsageMetadataPath' } else { New-ObservedRoleUsageMetric -Metadata $observedUsageMetadata -Role 'implementer' }
$observedReviewerTokenMetric = if ($null -eq $observedUsageMetadata) { New-Metric -State 'unavailable' -Value $null -Unit 'tokens' -Source 'incremental observed Codex session counters' -Calculation 'subtract cumulative counters at story boundaries' -Coverage 'no observed role token metadata was supplied' -MissingData 'run collect-role-token-usage.ps1 and pass UsageMetadataPath' } else { New-ObservedRoleUsageMetric -Metadata $observedUsageMetadata -Role 'reviewer' }
$observedCoordinatorTokenMetric = if ($null -eq $observedUsageMetadata) { New-Metric -State 'unavailable' -Value $null -Unit 'tokens' -Source 'incremental observed Codex session counters' -Calculation 'subtract cumulative counters at story boundaries' -Coverage 'no observed role token metadata was supplied' -MissingData 'run collect-role-token-usage.ps1 and pass UsageMetadataPath' } else { New-ObservedRoleUsageMetric -Metadata $observedUsageMetadata -Role 'coordinator' }
$observedTotalTokenMetric = New-ObservedTotalUsageMetric -RoleMetrics @($observedImplementerTokenMetric, $observedReviewerTokenMetric, $observedCoordinatorTokenMetric)


$eventReviewedHeadCandidates = @(Get-UniqueValuesLinear -Values @($prReady | ForEach-Object { [string] (Get-PropertyValue $_.Event.pullRequest 'reviewedHead') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
if ($eventReviewedHeadCandidates.Count -gt 1) {
    throw [System.InvalidOperationException]::new('report_identity_conflict: multiple pr_ready events carry different reviewed HEADs')
}
$explicitReviewedHead = if ([string]::IsNullOrWhiteSpace($ReviewedHead)) { $null } else { [string] $ReviewedHead }
if ($null -ne $explicitReviewedHead -and -not (Test-FullRevision -Value $explicitReviewedHead)) {
    throw [System.ArgumentException]::new('report_identity_invalid: explicit ReviewedHead must be a full Git SHA')
}
if ($null -ne $explicitReviewedHead -and $eventReviewedHeadCandidates.Count -eq 1 -and
    $explicitReviewedHead -ine [string] $eventReviewedHeadCandidates[0]) {
    throw [System.InvalidOperationException]::new('report_identity_conflict: explicit ReviewedHead disagrees with pr_ready reviewedHead')
}
$frozenReviewedHead = if ($eventReviewedHeadCandidates.Count -eq 1) {
    ([string] $eventReviewedHeadCandidates[0]).ToLowerInvariant()
}
elseif ($null -ne $explicitReviewedHead) {
    $explicitReviewedHead.ToLowerInvariant()
}
else {
    $null
}
$reviewedHeadForDiff = $frozenReviewedHead
$taskOutcomes = @()
try {
    $taskOutcomes = @(Get-TaskOutcomeEvidence -Path $TaskOutcomePath -RunId $metadataRunId -ProjectId $metadataProjectId -StoryId $metadataStoryId -Head $reviewedHeadForDiff -TaskRefs @($declaredTaskRefs))
}
catch {
    [void] $anomalies.Add((New-Anomaly -Code 'invalid_task_outcomes' -Message 'Task status/acceptance evidence is invalid and was not counted'))
}
$collectionAttempt = Get-CollectionAttempt -Path $CollectionAttemptPath -RunId $metadataRunId -ProjectId $metadataProjectId -StoryId $metadataStoryId -Head $reviewedHeadForDiff
$elapsedSemantics = Get-ElapsedSemantics -StorySpan $timeToPrInterval -Implementation @($implementationIntervals + $correctionIntervals) -Waits @($waitIntervals)
$tasksCompletedMetric = Get-TasksCompletedMetric -DeclaredTaskRefs $declaredTaskRefs -ReviewIntervals @($reviewIntervals) -Mode $effectiveReviewMode -ImplementationIntervals @($implementationIntervals) -TaskOutcomes $taskOutcomes
$comparisonMetrics = Get-ComparisonMetrics -BaseRevision $BaseRevision -ReviewedHead $reviewedHeadForDiff -RepositoryPath $RepositoryPath
$reportPullRequest = if ($prReady.Count -eq 1) { Get-SafePullRequest -PullRequest (Get-PropertyValue $prReady[0].Event 'pullRequest') } else { $null }
$reportRunId = if ($runIds.Count -eq 1) { [string] $runIds[0] } else { $null }
$reportProjectId = if ($projectIds.Count -eq 1) { [int] $projectIds[0] } else { $null }
$reportStoryId = if ($storyIds.Count -eq 1) { [int] $storyIds[0] } else { $null }
$reportIdentityPullRequest = if ($prReady.Count -eq 1) { Get-PropertyValue $prReady[0].Event 'pullRequest' } else { $null }
$reportId = Get-ReportIdentity -RunId $reportRunId -ProjectId $reportProjectId -StoryId $reportStoryId -PullRequest $reportIdentityPullRequest
$hasSyntheticEvidence = @($eventObjects | Where-Object { (Get-PropertyValue (Get-PropertyValue $_ 'provenance') 'synthetic') -eq $true }).Count -gt 0
$hasNonSyntheticEvidence = @($eventObjects | Where-Object { (Get-PropertyValue (Get-PropertyValue $_ 'provenance') 'synthetic') -ne $true }).Count -gt 0
$sourceCoverage = if ($hasSyntheticEvidence -and $hasNonSyntheticEvidence) { 'mixed synthetic and source-backed provenance' } elseif ($hasSyntheticEvidence) { 'synthetic provenance explicitly classified per event' } else { 'source provenance retained per event; numeric usage requires attributable authority' }
$reportLimitations = @(
    'Unknown values remain null; unavailable evidence is never treated as zero.'
    'Implementation/review elapsed are summed phase durations, including overlapping phases and inactivity; they are not wall-clock or active execution time.'
    if ($collectionAttempt.status -notin @('measured')) { "Token collection outcome: $($collectionAttempt.status); $($collectionAttempt.reason)" }
    if ($storyStarts.Count -eq 0 -and $prReady.Count -eq 1) { 'story_started boundary is absent; timeToPr remains unavailable while coherent implementation and review measurements are retained.' }
    if ($null -ne (Get-PropertyValue $collectionAttempt 'setupMetadataLimitation')) { [string] (Get-PropertyValue $collectionAttempt 'setupMetadataLimitation') }
    if ([string] $setupMetadata.state -eq 'partial') { "Role model and reasoning-effort profile coverage is partial; missing roles: $((Get-PropertyValue $setupMetadata 'missingRoles') -join ', ')." }
    if ([string] $setupMetadata.state -eq 'unavailable') { 'Role model and reasoning-effort profiles are unavailable because no validated setup metadata input was supplied.' }
    if ($comparisonMetrics.changedFiles.state -eq 'unavailable' -or $comparisonMetrics.linesAdded.state -eq 'unavailable' -or $comparisonMetrics.linesDeleted.state -eq 'unavailable') { 'Git comparison metrics require an explicit valid base revision, reviewed HEAD, and repository path.' }
    if ($null -eq $observedUsageMetadata) { 'Observed role token totals require the incremental collector output; event-level usage remains separately reported.' }
)

$report = [ordered]@{
    schemaVersion = 1
    kind = 'story_performance_report'
    reportId = $reportId
    runId = if ($runIds.Count -eq 1) { $runIds[0] } else { $null }
    projectId = if ($projectIds.Count -eq 1) { $projectIds[0] } else { $null }
    storyId = if ($storyIds.Count -eq 1) { $storyIds[0] } else { $null }
    storyRef = if ($storyRefs.Count -eq 1) { $storyRefs[0] } else { $null }
    reviewMode = $effectiveReviewMode
    pullRequest = $reportPullRequest
    metrics = [ordered]@{
        timeToPr = $timeToPrMetric
        implementationElapsed = $implementationMetric
        implementationWallClock = $elapsedSemantics.implementationWallClock
        quotaBlockedElapsed = $elapsedSemantics.quotaBlockedElapsed
        quotaAdjustedElapsed = $elapsedSemantics.quotaAdjustedElapsed
        activeExecutionElapsed = $elapsedSemantics.activeExecutionElapsed
        reviewElapsed = $reviewMetric
        coordinationElapsed = $coordinationMetric
        waitingElapsed = $waitMetric
        implementationTokens = $implementationTokenMetric
        reviewTokens = $reviewTokenMetric
        coordinationTokens = $coordinationTokenMetric
        totalTokens = $totalTokenMetric
        observedImplementerTokens = $observedImplementerTokenMetric
        observedReviewerTokens = $observedReviewerTokenMetric
        observedCoordinatorTokens = $observedCoordinatorTokenMetric
        observedTotalTokens = $observedTotalTokenMetric
        tasksCompleted = $tasksCompletedMetric
        initialTaskReviews = $initialMetric
        correctionReReviews = $correctionMetric
        finalStoryReviews = $finalMetric
        finalStoryReReviews = $finalReMetric
        firstPassAcceptanceRate = $firstPassMetric
        reviewMode = $reviewModeMetric
        modelsAndReasoning = $modelsAndReasoningMetric
        changedFiles = $comparisonMetrics.changedFiles
        linesAdded = $comparisonMetrics.linesAdded
        linesDeleted = $comparisonMetrics.linesDeleted
    }
    comparison = [ordered]@{
        baseRevision = if ([string]::IsNullOrWhiteSpace($BaseRevision)) { $null } else { [string] $BaseRevision }
        reviewedHead = $reviewedHeadForDiff
        changedFiles = $comparisonMetrics.changedFiles
        linesAdded = $comparisonMetrics.linesAdded
        linesDeleted = $comparisonMetrics.linesDeleted
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
    provenance = [ordered]@{
        collectionAttempt = $collectionAttempt
        eventSchemaVersion = 1
        sourceCoverage = $sourceCoverage
        sources = @('versioned story performance event ledger', 'Git revision comparison when an explicit valid base and reviewed HEAD are supplied') + $(if ([string] $setupMetadata.state -ne 'unavailable') { @('validated setup assignment metadata') } else { @() }) + $(if ($null -ne $observedUsageMetadata) { @('incremental observed role token metadata') } else { @() })
        setupMetadata = [ordered]@{
            state = [string] $setupMetadata.state
            recordCount = @($setupMetadata.records).Count
            coverage = [string] $setupMetadata.coverage
            missingRoles = @((Get-PropertyValue $setupMetadata 'missingRoles'))
        }
        observedRoleTokenUsage = if ($null -eq $observedUsageMetadata) { [ordered]@{ state = 'unavailable'; coverage = 'collector output was not supplied' } } else { [ordered]@{ state = [string] $observedUsageMetadata.coverage; boundary = $observedUsageMetadata.boundary; source = [string] $observedUsageMetadata.source } }
        limitations = @($reportLimitations)
    }
}

$json = $report | ConvertTo-Json -Depth 100
$resolvedOutputPath = $OutputPath
$resolvedMarkdownPath = $MarkdownPath
if (-not [string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
    if (-not [string]::IsNullOrWhiteSpace($OutputPath) -or -not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
        throw [System.ArgumentException]::new('report_artifact_invalid: ArtifactDirectory cannot be combined with OutputPath or MarkdownPath')
    }
    if ([string]::IsNullOrWhiteSpace($reportId)) {
        throw [System.InvalidOperationException]::new('report_identity_unavailable: ArtifactDirectory publication requires one confirmed PR identity and reviewed HEAD')
    }
    $artifactDirectoryFullPath = [IO.Path]::GetFullPath($ArtifactDirectory)
    [void] (Assert-ExternalArtifactPath -Path (Join-Path $artifactDirectoryFullPath '.report-artifact-path-check') -RepositoryPath $RepositoryPath)
    $artifactStem = Get-ArtifactFileStem -ReportId $reportId
    $resolvedOutputPath = Join-Path $artifactDirectoryFullPath "$artifactStem.json"
    $resolvedMarkdownPath = Join-Path $artifactDirectoryFullPath "$artifactStem.md"
}

$outputFullPath = $null
$outputContent = $null
$markdownFullPath = $null
$markdownContent = $null
$manifestFullPath = $null
$manifestContent = $null
$artifactEntries = [System.Collections.Generic.List[object]]::new()
if (-not [string]::IsNullOrWhiteSpace($resolvedOutputPath)) {
    $outputFullPath = Assert-ExternalArtifactPath -Path $resolvedOutputPath -RepositoryPath $RepositoryPath
    $outputContent = $json + [Environment]::NewLine
    Assert-ArtifactCanPublish -Path $outputFullPath -Content $outputContent
    [void] $artifactEntries.Add([ordered]@{ kind = 'json'; path = $outputFullPath; sha256 = Get-Sha256Hex -Content $outputContent })
}
if (-not [string]::IsNullOrWhiteSpace($resolvedMarkdownPath)) {
    $markdownFullPath = Assert-ExternalArtifactPath -Path $resolvedMarkdownPath -RepositoryPath $RepositoryPath
    $markdownContent = ConvertTo-Markdown -Report ([pscustomobject] $report)
    Assert-ArtifactCanPublish -Path $markdownFullPath -Content $markdownContent
    [void] $artifactEntries.Add([ordered]@{ kind = 'markdown'; path = $markdownFullPath; sha256 = Get-Sha256Hex -Content $markdownContent })
}
if ($artifactEntries.Count -gt 1 -and $outputFullPath.Equals($markdownFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw [System.InvalidOperationException]::new('report_artifact_conflict: JSON and Markdown destinations must differ')
}
if ($artifactEntries.Count -gt 0) {
    $manifestAnchor = if ($null -ne $outputFullPath) { $outputFullPath } else { $markdownFullPath }
    $manifestFullPath = Assert-ExternalArtifactPath -Path (Get-CompletionManifestPath -AnchorPath $manifestAnchor) -RepositoryPath $RepositoryPath
    $manifestContent = New-ArtifactSetManifestContent -ReportId $reportId -Artifacts @($artifactEntries)
    Assert-ArtifactCanPublish -Path $manifestFullPath -Content $manifestContent
}
if ($null -ne $outputFullPath) {
    [void] (Publish-ImmutableArtifact -Path $outputFullPath -Content $outputContent)
}
if ($null -ne $markdownFullPath) {
    [void] (Publish-ImmutableArtifact -Path $markdownFullPath -Content $markdownContent)
}
if ($null -ne $manifestFullPath) {
    [void] (Publish-ImmutableArtifact -Path $manifestFullPath -Content $manifestContent)
}

Write-Output $json
