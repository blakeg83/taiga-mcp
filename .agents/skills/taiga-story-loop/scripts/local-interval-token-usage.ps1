# Loaded by the reporter. Samples come only from its freshly invoked local collector.
function Get-LocalIntervalUsage {
    param([System.Collections.IDictionary] $Result, [object] $StartEvent, [object] $EndEvent, [string] $Role)
    if ($StartEvent.workerId -cne $EndEvent.workerId -or $StartEvent.sessionId -cne $EndEvent.sessionId) { return $null }
    $expected = [string] $StartEvent.sessionId
    if (-not $expected) { $expected = [string] $StartEvent.workerId }
    $sessions = @($observedUsageMetadata.sessions | Where-Object { $_.role -ceq $Role -and $_.sessionId -ceq $expected -and (Get-PropertyValue $_ 'sourceSessionVerified') -eq $true })
    if ($sessions.Count -ne 1) { return $null }
    $session = $sessions[0]
    $startTime = [DateTimeOffset]::Parse($Result.startUtc)
    $endTime = [DateTimeOffset]::Parse($Result.endUtc)
    # Inner samples avoid charging tokens from a neighboring task to this phase.
    $samples = @($session.sourceSamples | Where-Object {
        $time = [DateTimeOffset]::Parse($_.sampledAtUtc)
        $time -ge $startTime -and $time -le $endTime
    } | Sort-Object { [DateTimeOffset]::Parse($_.sampledAtUtc) })
    if ($samples.Count -lt 2) {
        $Result.missingData = 'fewer than two verified samples inside the phase; no zero baseline was invented'
        return [pscustomobject] $Result
    }
    $first = $samples[0]; $last = $samples[-1]
    if ($first.resetCount -ne $last.resetCount) {
        $Result.missingData = 'counter reset within the phase; no delta across a reset'
        return [pscustomobject] $Result
    }
    # Equal-time contradictory samples cannot define an authoritative boundary.
    # Keep this check linear: the validator and production contract forbid hidden
    # grouping/sorting over the full sample input.
    $countersBySampleTime = @{}
    foreach ($sample in $samples) {
        $sampleTime = ([DateTimeOffset]::Parse($sample.sampledAtUtc)).ToUniversalTime().ToString('o')
        $counterJson = ConvertTo-CanonicalJson $sample.counters
        if ($countersBySampleTime.ContainsKey($sampleTime) -and $countersBySampleTime[$sampleTime] -cne $counterJson) { return $null }
        $countersBySampleTime[$sampleTime] = $counterJson
    }
    $delta = [ordered]@{}
    foreach ($name in @('inputTokens','cachedInputTokens','outputTokens','reasoningTokens')) {
        $value = [long] $last.counters.$name - [long] $first.counters.$name
        if ($value -lt 0) { return $null }
        $delta[$name] = $value
    }
    $Result.state = if ([DateTimeOffset]::Parse($first.sampledAtUtc) -eq $startTime -and [DateTimeOffset]::Parse($last.sampledAtUtc) -eq $endTime -and $session.invalidRecords -eq 0 -and $session.fileResetCount -eq 0) { 'measured' } else { 'partial' }
    $Result.value = [long] $delta.inputTokens + [long] $delta.outputTokens
    $Result.deltas = [pscustomobject] $delta
    $Result.components = [pscustomobject]@{
        input = $delta.inputTokens
        cachedInputSubset = $delta.cachedInputTokens
        output = $delta.outputTokens
        reasoningSubset = $delta.reasoningTokens
        total = $Result.value
    }
    $Result.streamId = $session.sessionId
    $Result.sessionId = $session.sessionId
    $Result.workerId = $StartEvent.workerId
    $Result.eventSessionId = $StartEvent.sessionId
    $Result.sessionBinding = @{ eventSessionId = $StartEvent.sessionId; usageSessionId = $session.sessionId }
    $Result.source = $session.sourcePath
    $Result.counterSemantics = @{ cachedInput = 'included_in_input'; reasoning = 'included_in_output' }
    $Result.baselineAtUtc = $first.sampledAtUtc
    $Result.startSampledAtUtc = $first.sampledAtUtc; $Result.endSampledAtUtc = $last.sampledAtUtc
    $Result.sampleWindow = [ordered]@{ startUtc = $first.sampledAtUtc; endUtc = $last.sampledAtUtc; requestedStartUtc = $Result.startUtc; requestedEndUtc = $Result.endUtc }
    $Result.startCounters = $first.counters; $Result.endCounters = $last.counters
    $Result.coverage = 'verified cumulative delta between inner phase samples; sampling times retained'
    $Result.missingData = if ($Result.state -eq 'partial') { 'activity between lifecycle boundaries and inner samples is unmeasured; no interpolation' } else { $null }
    return [pscustomobject] $Result
}
