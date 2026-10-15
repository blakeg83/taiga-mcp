# Helpers used by the existing aggregator; no workflow or persistence authority.
function Get-CollectionAttempt {
    param([string] $Path, [string] $RunId, [int] $ProjectId, [int] $StoryId, [string] $Head)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{ status = 'skipped'; discoveryAttempted = $false; collectorInvoked = $false; reason = 'mandatory collection/discovery step was not supplied' }
    }
    $attempt = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    if ($attempt.kind -cne 'story_performance_collection_attempt' -or $attempt.schemaVersion -ne 1 -or
        $attempt.runId -cne $RunId -or $attempt.projectId -ne $ProjectId -or $attempt.storyId -ne $StoryId -or
        $attempt.reviewedHead -cne $Head -or $attempt.status -notin @('measured', 'partial', 'source_unavailable', 'failed', 'skipped') -or
        $attempt.discoveryAttempted -isnot [bool] -or $attempt.collectorInvoked -isnot [bool] -or
        ($attempt.status -in @('measured', 'partial') -and (-not $attempt.collectorInvoked))) {
        throw 'collection_attempt_invalid: identity or outcome is invalid'
    }
    return $attempt
}

function Get-TaskOutcomeEvidence {
    param([string] $Path, [string] $RunId, [int] $ProjectId, [int] $StoryId, [string] $Head, [int[]] $TaskRefs)
    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    $evidence = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    if ($evidence.kind -cne 'story_performance_task_outcomes' -or $evidence.schemaVersion -ne 1 -or
        $evidence.runId -cne $RunId -or $evidence.projectId -ne $ProjectId -or $evidence.storyId -ne $StoryId -or
        $evidence.reviewedHead -cne $Head) { throw 'task_outcome_invalid: evidence identity mismatch' }
    $seen = [Collections.Generic.HashSet[int]]::new()
    foreach ($task in @($evidence.tasks)) {
        $observed = [DateTimeOffset]::MinValue
        if ($task.taskRef -notin $TaskRefs -or -not $seen.Add([int] $task.taskRef) -or
            $task.accepted -isnot [bool] -or $task.isDone -isnot [bool] -or
            $task.source -notin @('taiga_task_status', 'task_acceptance') -or
            -not [DateTimeOffset]::TryParse([string] $task.observedAtUtc, [ref] $observed) -or $observed.Offset -ne [TimeSpan]::Zero -or
            [string]::IsNullOrWhiteSpace([string] $task.evidenceReference)) {
            throw 'task_outcome_invalid: explicit declared task status/acceptance evidence is required'
        }
    }
    return @($evidence.tasks)
}

function Get-ElapsedSemantics {
    param([object] $StorySpan, [object[]] $Implementation, [object[]] $Waits)
    # Union prevents overlapping phases and quota waits from double counting.
    function Get-UnionMilliseconds {
        param([object[]] $Intervals, [DateTimeOffset] $Start, [DateTimeOffset] $End)
        $segments = @($Intervals | Where-Object state -eq 'measured' | ForEach-Object {
            $a = [DateTimeOffset]::Parse($_.startUtc)
            $b = [DateTimeOffset]::Parse($_.endUtc)
            if ($b -gt $Start -and $a -lt $End) {
                [pscustomobject]@{ start = $(if ($a -lt $Start) { $Start } else { $a }); end = $(if ($b -gt $End) { $End } else { $b }) }
            }
        } | Sort-Object start, end)
        $cursor = $Start
        $total = 0L
        foreach ($segment in $segments) {
            $a = if ($segment.start -lt $cursor) { $cursor } else { $segment.start }
            if ($segment.end -gt $a) { $total += [long] ($segment.end - $a).TotalMilliseconds }
            if ($segment.end -gt $cursor) { $cursor = $segment.end }
        }
        return $total
    }
    $spanMeasured = $StorySpan.state -eq 'measured'
    $quota = @($Waits | Where-Object waitKind -eq 'quota_blocked')
    $quotaComplete = $quota.Count -gt 0 -and @($quota | Where-Object state -ne 'measured').Count -eq 0
    $start = if ($spanMeasured) { [DateTimeOffset]::Parse($StorySpan.startUtc) } else { [DateTimeOffset]::MinValue }
    $end = if ($spanMeasured) { [DateTimeOffset]::Parse($StorySpan.endUtc) } else { [DateTimeOffset]::MaxValue }
    $quotaState = if ($quota.Count -eq 0) { 'unavailable' } elseif ($quotaComplete -and $spanMeasured) { 'measured' } else { 'partial' }
    $blocked = if ($quotaComplete -and $spanMeasured) { Get-UnionMilliseconds -Intervals $quota -Start $start -End $end } else { $null }
    $quotaMetric = New-Metric -State $quotaState -Value $blocked -Unit 'milliseconds' -Source 'explicit quota_blocked wait boundaries' -Calculation 'union of confirmed quota waits clipped to story boundaries' -Coverage 'only observed interruption/resumption pairs; no quota-window inference' -MissingData $(if ($quotaState -ne 'measured') { 'quota or story boundaries are absent/incomplete; no zero or blocked-duration estimate is inferred' } else { $null })
    if ($quotaState -eq 'partial' -and $spanMeasured) {
        if (@($quota | Where-Object state -eq 'measured').Count -gt 0) {
            $quotaMetric | Add-Member -NotePropertyName knownSubtotal -NotePropertyValue (Get-UnionMilliseconds -Intervals $quota -Start $start -End $end)
        }
        if (@($Waits | Where-Object waitKind -eq 'manual_resume').Count -gt 0) {
            $quotaMetric.missingData = 'quota availability is not fully evidenced across manual resumption; manual authorization and unknown capacity time cannot be treated as proven quota blocking'
        }
    }
    $adjusted = New-Metric -State $quotaState -Value $(if ($null -ne $blocked) { [long] $StorySpan.elapsedMilliseconds - $blocked } else { $null }) -Unit 'milliseconds' -Source 'story boundaries and explicit quota waits' -Calculation 'story wall-clock elapsed minus confirmed quota-blocked overlap' -Coverage 'quota-adjusted elapsed includes other inactivity; it is not active execution time' -MissingData $quotaMetric.missingData
    $implementationState = if ($Implementation.Count -eq 0 -or -not $spanMeasured) { 'unavailable' } elseif (@($Implementation | Where-Object state -ne 'measured').Count -gt 0) { 'partial' } else { 'measured' }
    $implementationWall = New-Metric -State $implementationState -Value $(if ($implementationState -eq 'measured') { Get-UnionMilliseconds -Intervals $Implementation -Start $start -End $end } else { $null }) -Unit 'milliseconds' -Source 'paired implementation and correction boundaries' -Calculation 'union of phase intervals within story boundaries' -Coverage 'overlap counted once; includes idle and interruption time' -MissingData $(if ($implementationState -ne 'measured') { 'implementation or story boundary coverage is incomplete' } else { $null })
    return [ordered]@{
        implementationWallClock = $implementationWall
        quotaBlockedElapsed = $quotaMetric
        quotaAdjustedElapsed = $adjusted
        activeExecutionElapsed = (New-Metric -State 'unavailable' -Value $null -Unit 'milliseconds' -Source 'independent activity evidence' -Calculation 'requires independently attributable execution activity' -Coverage 'phase elapsed and quota-adjusted elapsed cannot establish active execution' -MissingData 'no independent activity evidence is available')
    }
}
