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
        $difference = $end.Time - $start.Time
        if ($difference.TotalMilliseconds -lt 0) {
            $state = 'partial'
            $missing = 'end boundary precedes start boundary'
            [void] $Anomalies.Add((New-Anomaly -Code 'negative_interval' -Message "$Kind interval has a reversed UTC boundary" -Identity $Identity -EventIds @($start.EventId, $end.EventId)))
        }
        else {
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
            $leftEnd = [DateTimeOffset]::Parse($valid[$i].endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $rightStart = [DateTimeOffset]::Parse($valid[$j].startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $otherEnd = [DateTimeOffset]::Parse($valid[$j].endUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $otherStart = [DateTimeOffset]::Parse($valid[$i].startUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            if (($otherStart -lt $leftEnd) -and ($rightStart -lt $otherEnd)) {
                [void] $Anomalies.Add((New-Anomaly -Code 'overlapping_intervals' -Message 'Valid phase intervals overlap; totals remain separate and are not made additive wall-clock time' -Identity "$($valid[$i].identity)|$($valid[$j].identity)"))
            }
        }
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
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $lineNumber++
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
        $eventType = [string] (Get-PropertyValue $event 'eventType')
        if ($eventType -notin $script:EventTypes) {
            [void] $Anomalies.Add((New-Anomaly -Code 'unsupported_event_type' -Message 'An event with an unsupported eventType was excluded from aggregation' -Identity $eventId -Line $lineNumber -EventIds @($eventId)))
            continue
        }

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

$eventObjects = @($records | ForEach-Object { $_.Event })
$runIds = @($eventObjects | ForEach-Object { [string] (Get-PropertyValue $_ 'runId') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$projectIds = @($eventObjects | ForEach-Object { Get-PropertyValue $_ 'projectId' } | Where-Object { $null -ne $_ } | ForEach-Object { [int] $_ } | Sort-Object -Unique)
$storyIds = @($eventObjects | ForEach-Object { Get-PropertyValue $_ 'storyId' } | Where-Object { $null -ne $_ } | ForEach-Object { [int] $_ } | Sort-Object -Unique)
$storyRefs = @($eventObjects | ForEach-Object { Get-PropertyValue $_ 'storyRef' } | Where-Object { $null -ne $_ } | ForEach-Object { [int] $_ } | Sort-Object -Unique)
$eventModes = @($eventObjects | ForEach-Object { [string] (Get-PropertyValue $_ 'reviewMode') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

if ($runIds.Count -ne 1) { [void] $anomalies.Add((New-Anomaly -Code 'conflicting_run_identity' -Message 'Events from more than one runId cannot be combined into one report')) }
if ($projectIds.Count -ne 1 -or $storyIds.Count -ne 1 -or $storyRefs.Count -ne 1) { [void] $anomalies.Add((New-Anomaly -Code 'conflicting_story_identity' -Message 'Events from more than one project or story identity cannot be combined into one report')) }

$effectiveReviewMode = $ReviewMode
if ([string]::IsNullOrWhiteSpace($effectiveReviewMode)) {
    if ($eventModes.Count -eq 1) {
        $effectiveReviewMode = $eventModes[0]
    }
    else {
        $effectiveReviewMode = 'unavailable'
        [void] $anomalies.Add((New-Anomaly -Code 'missing_review_mode' -Message 'Review mode was not supplied and could not be established from one consistent event value; no mode was inferred'))
    }
}
elseif ($eventModes.Count -gt 0 -and @($eventModes | Where-Object { $_ -ne $effectiveReviewMode }).Count -gt 0) {
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
            $waitKey = ([string](Get-PropertyValue $event 'scope'), [string](Get-PropertyValue $event 'waitId') -join '|')
            Add-ToIndex -Index $waitStarts -Key $waitKey -Value $record
        }
        'wait_ended' {
            $waitKey = ([string](Get-PropertyValue $event 'scope'), [string](Get-PropertyValue $event 'waitId') -join '|')
            Add-ToIndex -Index $waitEnds -Key $waitKey -Value $record
        }
        { $_ -in $script:ReviewStartEvents } { Add-ToIndex -Index $reviewStarts -Key (Get-ReviewIdentity $event) -Value $record }
        { $_ -in $script:ReviewCloseEvents } { Add-ToIndex -Index $reviewEnds -Key (Get-ReviewIdentity $event) -Value $record }
    }
}

# A second observation of the same review attempt is diagnostic-only. It is
# never a second review count, even when it arrived under another eventId.
$reviewStartByAttempt = @{}
$dedupedReviewStarts = [System.Collections.Generic.List[object]]::new()
foreach ($key in @($reviewStarts.Keys)) {
    foreach ($record in @($reviewStarts[$key])) {
        $attemptKey = Get-ReviewAttemptIdentity -Event $record.Event
        if ($reviewStartByAttempt.ContainsKey($attemptKey)) {
            $first = $reviewStartByAttempt[$attemptKey]
            [void] $anomalies.Add((New-Anomaly -Code 'duplicate_or_stale_review' -Message 'A repeated review attempt identity was ignored for counting' -Identity $attemptKey -EventIds @($first.EventId, $record.EventId)))
            continue
        }
        $reviewStartByAttempt[$attemptKey] = $record
        [void] $dedupedReviewStarts.Add($record)
    }
}

# Keep one immutable closure per attempt. Distinct closure kinds or times are
# conflicting evidence, not a reason to choose whichever event was read first.
$reviewEndsByAttempt = @{}
foreach ($key in @($reviewEnds.Keys)) {
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
    if ($closures.Count -gt 0 -and $matchingClosures.Count -eq 0) {
        [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_identity' -Message 'Review closure identity does not match the recorded start; it cannot close that attempt' -Identity $attemptKey -EventIds @($record.EventId) + @($closures | ForEach-Object { $_.EventId })))
    }
    if ($matchingClosures.Count -gt 1) {
        $closureKinds = @($matchingClosures | ForEach-Object { $_.EventType } | Sort-Object -Unique)
        if ($closureKinds.Count -gt 1) {
            $ids = @($record.EventId) + @($matchingClosures | ForEach-Object { $_.EventId })
            [void] $anomalies.Add((New-Anomaly -Code 'conflicting_review_closure' -Message 'A review attempt has both findings and acceptance or otherwise conflicting closure evidence' -Identity $attemptKey -EventIds $ids))
            $matchingClosures = @()
        }
        else {
            $matchingClosures = @($matchingClosures | Sort-Object Time, Line | Select-Object -First 1)
            [void] $anomalies.Add((New-Anomaly -Code 'duplicate_review_closure' -Message 'Repeated closure evidence was reduced to the first authoritative closure' -Identity $attemptKey -EventIds @($matchingClosures | ForEach-Object { $_.EventId })))
        }
    }

    $closure = if ($matchingClosures.Count -eq 1) { $matchingClosures[0] } else { $null }
    $state = 'measured'
    $elapsed = $null
    $missing = $null
    $closureKind = $null
    if ($null -eq $closure) {
        $state = 'partial'
        $missing = 'missing or conflicting review closure'
        [void] $anomalies.Add((New-Anomaly -Code 'missing_boundary' -Message 'Review attempt has no authoritative closure' -Identity $attemptKey -EventIds @($record.EventId)))
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
    }
    [void] $reviewIntervals.Add($attemptResult)
}

# Any closure without a matching attempt is not allowed to close a different
# request, and is retained as an explicit anomaly.
foreach ($attemptKey in @($reviewEndsByAttempt.Keys)) {
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
Add-OverlapAnomalies -Intervals @($implementationIntervals + $correctionIntervals) -Anomalies $anomalies

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
$initialTaskRefs = @($initialAttempts | Where-Object { $null -ne $_.taskRef } | ForEach-Object { [string] $_.taskRef } | Sort-Object -Unique)
$acceptedFirst = 0
$firstPassIncomplete = 0
foreach ($taskRef in $initialTaskRefs) {
    $taskAttempts = @($initialAttempts | Where-Object { [string] $_.taskRef -eq $taskRef } | Sort-Object startUtc)
    $first = $taskAttempts[0]
    if ($first.state -ne 'measured') {
        $firstPassIncomplete++
        continue
    }
    if ([string] $first.closureEventType -eq 'review_accepted') {
        $acceptedFirst++
        $first.firstPass = $true
    }
}

if ($effectiveReviewMode -eq 'story_end_only') {
    $firstPassMetric = New-Metric -State 'not_applicable' -Value $null -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage 'story_end_only intentionally has no per-task review denominator' -MissingData 'not applicable'
}
elseif ($initialTaskRefs.Count -eq 0) {
    $firstPassMetric = New-Metric -State 'not_applicable' -Value $null -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage 'zero denominator in this event set' -MissingData 'not applicable'
}
elseif ($firstPassIncomplete -gt 0) {
    $firstPassMetric = New-Metric -State 'partial' -Value $null -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage "$acceptedFirst numerator of $($initialTaskRefs.Count) denominator task identities; $firstPassIncomplete outcome(s) remain open or ambiguous" -MissingData 'first-pass outcome is unknown until every initial attempt has an authoritative closure'
}
else {
    $firstPassMetric = New-Metric -State 'measured' -Value ([double] $acceptedFirst / [double] $initialTaskRefs.Count) -Unit 'ratio' -Source 'review request and acceptance identities' -Calculation 'accepted-on-first-attempt / tasks-with-initial-review' -Coverage "$acceptedFirst numerator of $($initialTaskRefs.Count) denominator task identities have authoritative outcomes" -MissingData $null
}
$firstPassMetric | Add-Member -NotePropertyName numerator -NotePropertyValue $acceptedFirst
$firstPassMetric | Add-Member -NotePropertyName denominator -NotePropertyValue $initialTaskRefs.Count

if ($effectiveReviewMode -eq 'story_end_only') {
    if ($initialAttempts.Count -gt 0 -or $correctionAttempts.Count -gt 0) {
        [void] $anomalies.Add((New-Anomaly -Code 'review_mode_violation' -Message 'story_end_only input contains per-task review attempts; those events are retained but the mode is not silently changed'))
    }
    $initialMetric = New-CountMetric -Value 0 -Unit 'task identities' -Source 'review request identities' -Coverage 'story_end_only explicitly excludes per-task reviews' -MissingData $null
    $correctionMetric = New-CountMetric -Value 0 -Unit 'review attempts' -Source 'review request identities' -Coverage 'story_end_only explicitly excludes correction re-reviews' -MissingData $null
}
else {
    $initialState = if ($effectiveReviewMode -eq 'per_task') { 'measured' } else { 'unavailable' }
    $initialMissingData = if ($initialState -eq 'unavailable') { 'review mode is unavailable' } else { $null }
    $initialMetric = New-CountMetric -Value $initialTaskRefs.Count -Unit 'task identities' -Source 'review request identities' -Coverage 'one count per distinct task with an initial_task attempt' -MissingData $initialMissingData -State $initialState
    $correctionMetric = New-CountMetric -Value $correctionAttempts.Count -Unit 'review attempts' -Source 'review request and attempt identities' -Coverage 'one count per distinct correction_rereview attempt' -MissingData $initialMissingData -State $initialState
}

$finalMetricState = if ($effectiveReviewMode -in @('per_task', 'story_end_only')) { 'measured' } else { 'unavailable' }
$finalMissingData = if ($finalMetricState -eq 'unavailable') { 'review mode is unavailable' } else { $null }
$finalMetric = New-CountMetric -Value $finalAttempts.Count -Unit 'review attempts' -Source 'final-story review attempt identities' -Coverage 'one count per distinct final-story attempt' -MissingData $finalMissingData -State $finalMetricState
$finalReMetric = New-CountMetric -Value $finalReReviews.Count -Unit 'review attempts' -Source 'final-story review attempt identities' -Coverage 'later final-story attempts only' -MissingData $finalMissingData -State $finalMetricState

$coordinationMetric = New-Metric -State 'unavailable' -Value $null -Unit 'milliseconds' -Source 'explicit coordinator lifecycle intervals' -Calculation 'sum explicit coordinator intervals only' -Coverage 'no coordinator-only interval event vocabulary is present' -MissingData 'coordination cannot be inferred from wall-clock gaps or reviewer/worker phases'
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
    pullRequest = if ($prReady.Count -eq 1) { Get-PropertyValue $prReady[0].Event 'pullRequest' } else { $null }
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
        duplicateAndConflictDiagnostics = @($anomalies | Where-Object { $_.code -in @('duplicate_event', 'event_identity_conflict', 'duplicate_or_stale_review') }).Count
        uncoveredBoundaryDiagnostics = @($anomalies | Where-Object { $_.code -in @('missing_boundary', 'conflicting_boundary', 'negative_interval', 'orphan_review_closure') }).Count
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
