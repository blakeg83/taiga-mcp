# SYNTHETIC BOUNDED-OVERHEAD CHECK.
# This fixture runs every other checked-in story-loop validator, then executes
# the existing automatic-review state machine with instrumentation disabled and
# enabled. It reports measured local control/helper timings and source-backed
# recorder bounds without claiming a production performance threshold.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Performance-overhead assertion failed: $Message"
    }
}

function Copy-JsonObject {
    param([Parameter(Mandatory)] [object] $Value)

    return ($Value | ConvertTo-Json -Compress -Depth 40 | ConvertFrom-Json -Depth 40 -DateKind String)
}

function Get-Median {
    param([Parameter(Mandatory)] [double[]] $Values)

    $sorted = @($Values | Sort-Object)
    return [double]$sorted[[int][math]::Floor($sorted.Count / 2)]
}

function Invoke-ValidatorSuite {
    param([Parameter(Mandatory)] [string] $ScriptRoot)

    $validatorFiles = @(Get-ChildItem -LiteralPath $ScriptRoot -Filter 'validate-*.ps1' -File |
            Where-Object { $_.Name -ne 'validate-performance-overhead.ps1' } |
            Sort-Object Name)
    Assert-True ($validatorFiles.Count -gt 0) 'the story-loop validator suite must not be empty'
    return @($validatorFiles | ForEach-Object {
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $output = & pwsh -NoProfile -File $_.FullName 2>&1
            $exitCode = [int]$LASTEXITCODE
            $timer.Stop()
            $lines = @($output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $diagnostic = if ($lines.Count -gt 3) {
                ($lines | Select-Object -Last 3) -join [Environment]::NewLine
            } else {
                $lines -join [Environment]::NewLine
            }
            Assert-True ($exitCode -eq 0) "validator $($_.Name) failed with exit ${exitCode}: $diagnostic"
            [ordered]@{
                name = $_.Name
                exitCode = $exitCode
                durationMilliseconds = [math]::Round($timer.Elapsed.TotalMilliseconds, 3)
                outputTail = $diagnostic
            }
        })
}

function Invoke-WorkflowControl {
    param(
        [Parameter(Mandatory)] [string] $AutomaticReviewPath,
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $RunId,
        [Parameter(Mandatory)] [ValidateSet('disabled', 'enabled')] [string] $Mode,
        [Parameter(Mandatory)] [string] $TracePath
    )

    $arguments = @(
        '-NoProfile'
        '-File', $AutomaticReviewPath
        '-MeasurementExternalRunRoot', $ExternalRoot
        '-MeasurementRunId', $RunId
        '-MeasurementTracePath', $TracePath
        '-MeasurementMode', $Mode
    )
    $output = & pwsh @arguments 2>&1
    $exitCode = [int]$LASTEXITCODE
    $diagnostic = [string]($output -join [Environment]::NewLine)
    Assert-True ($exitCode -eq 0) "workflow control $Mode/$RunId failed with exit ${exitCode}: $diagnostic"
    Assert-True (Test-Path -LiteralPath $TracePath -PathType Leaf) "workflow control $Mode/$RunId must write its observed trace"
    return [IO.File]::ReadAllText($TracePath) | ConvertFrom-Json -Depth 50 -DateKind String
}

function Invoke-Aggregator {
    param(
        [Parameter(Mandatory)] [string] $AggregatorPath,
        [Parameter(Mandatory)] [string] $LedgerPath
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $failed = $false
    try {
        $output = & $AggregatorPath -EventsPath $LedgerPath -ReviewMode per_task -TaskRefs @(65) 2>&1
    }
    catch {
        $failed = $true
        $output = @($_)
    }
    $timer.Stop()
    $exitCode = if ($failed) { 1 } else { 0 }
    $text = [string]($output -join [Environment]::NewLine)
    Assert-True ($exitCode -eq 0) "candidate aggregator failed: $text"
    return [ordered]@{
        report = $text | ConvertFrom-Json -Depth 100 -DateKind String
        reportText = $text
        durationMilliseconds = [math]::Round($timer.Elapsed.TotalMilliseconds, 3)
        invocationCount = 1
    }
}

function Invoke-ControlSample {
    param(
        [Parameter(Mandatory)] [string] $SampleId,
        [Parameter(Mandatory)] [ValidateSet('disabled', 'enabled')] [string] $Mode,
        [Parameter(Mandatory)] [string] $ExternalRoot,
        [Parameter(Mandatory)] [string] $AutomaticReviewPath,
        [Parameter(Mandatory)] [string] $AggregatorPath
    )

    $runId = "overhead-$Mode-$SampleId"
    $tracePath = Join-Path $ExternalRoot "$runId-trace.json"
    $controlTimer = [Diagnostics.Stopwatch]::StartNew()
    $trace = Invoke-WorkflowControl -AutomaticReviewPath $AutomaticReviewPath -ExternalRoot $ExternalRoot -RunId $runId -Mode $Mode -TracePath $tracePath
    $aggregator = $null
    $eventBytes = 0
    $eventCount = 0
    $reportBytes = 0
    $reportState = 'not_run'
    if ($Mode -eq 'enabled') {
        $ledgerPath = Join-Path (Join-Path $ExternalRoot $runId) 'events.jsonl'
        Assert-True (Test-Path -LiteralPath $ledgerPath -PathType Leaf) 'enabled workflow control must persist its production ledger'
        $eventBytes = [IO.File]::ReadAllBytes($ledgerPath).Length
        $eventCount = @([IO.File]::ReadAllLines($ledgerPath)).Count
        $aggregator = Invoke-Aggregator -AggregatorPath $AggregatorPath -LedgerPath $ledgerPath
        $reportBytes = [Text.UTF8Encoding]::new($false).GetByteCount([string]$aggregator.reportText)
        $reportState = 'measured'
        Assert-True ([int]$aggregator.report.coverage.validEventCount -eq $eventCount) 'candidate report must account for every persisted event'
    }
    $controlTimer.Stop()
    $workflow = $trace.workflow
    $recorderInvocationCount = [int]$trace.measurement.recorderInvocationCount
    $aggregationInvocationCount = if ($null -eq $aggregator) { 0 } else { [int]$aggregator.invocationCount }
    return [ordered]@{
        sampleId = $SampleId
        mode = $Mode
        workloadId = 'synthetic-ready-review-workload-1'
        outcomeFingerprint = [string]$workflow.outcomeFingerprint
        transitionCount = [int]$workflow.transitionCount
        normalMessageCount = [int]$workflow.normalMessageCount
        agentCount = [int]$workflow.agentCount
        pollingEventCount = [int]$workflow.pollingEventCount
        measurementOnlyMessageCount = [int]$workflow.measurementOnlyMessageCount
        helperInvocations = $recorderInvocationCount + $aggregationInvocationCount
        recorderInvocationCount = $recorderInvocationCount
        aggregationInvocationCount = $aggregationInvocationCount
        eventCount = $eventCount
        eventBytes = $eventBytes
        reportBytes = $reportBytes
        reportState = $reportState
        usageState = 'unavailable'
        controlDurationMilliseconds = [math]::Round($controlTimer.Elapsed.TotalMilliseconds, 3)
        helperDurationMilliseconds = if ($null -eq $aggregator) {
            $null
        } else {
            [math]::Round([double]$trace.measurement.recorderDurationMilliseconds + [double]$aggregator.durationMilliseconds, 3)
        }
        trace = $trace
    }
}

function Get-ControlSummary {
    param(
        [Parameter(Mandatory)] [object[]] $Samples,
        [Parameter(Mandatory)] [ValidateSet('disabled', 'enabled')] [string] $Mode
    )

    $controlDurations = @($Samples | ForEach-Object { [double]$_.controlDurationMilliseconds })
    $helperDurations = @($Samples | Where-Object { $null -ne $_.helperDurationMilliseconds } | ForEach-Object { [double]$_.helperDurationMilliseconds })
    $sample = $Samples[0]
    return [ordered]@{
        mode = $Mode
        workloadId = [string]$sample.workloadId
        outcomeFingerprint = [string]$sample.outcomeFingerprint
        transitionCount = [int]$sample.transitionCount
        normalMessageCount = [int]$sample.normalMessageCount
        agentCount = [int]$sample.agentCount
        pollingEventCount = [int]$sample.pollingEventCount
        measurementOnlyMessageCount = [int]$sample.measurementOnlyMessageCount
        helperInvocations = [int](@($Samples | ForEach-Object { [int]$_.helperInvocations } | Measure-Object -Average).Average)
        recorderInvocationCount = [int](@($Samples | ForEach-Object { [int]$_.recorderInvocationCount } | Measure-Object -Average).Average)
        aggregationInvocationCount = [int](@($Samples | ForEach-Object { [int]$_.aggregationInvocationCount } | Measure-Object -Average).Average)
        eventCount = [int](@($Samples | ForEach-Object { [int]$_.eventCount } | Measure-Object -Average).Average)
        eventBytes = [int](@($Samples | ForEach-Object { [int]$_.eventBytes } | Measure-Object -Average).Average)
        reportBytes = [int](@($Samples | ForEach-Object { [int]$_.reportBytes } | Measure-Object -Average).Average)
        reportState = if ($Mode -eq 'enabled') { 'measured' } else { 'not_run' }
        usageState = 'unavailable'
        controlDuration = [ordered]@{
            state = 'measured'
            unit = 'milliseconds'
            sampleCount = $controlDurations.Count
            warmUp = 0
            samples = @($controlDurations | Sort-Object)
            minimum = [math]::Round(($controlDurations | Measure-Object -Minimum).Minimum, 3)
            median = [math]::Round((Get-Median $controlDurations), 3)
            maximum = [math]::Round(($controlDurations | Measure-Object -Maximum).Maximum, 3)
            source = 'local monotonic Stopwatch around the matched workflow control process and enabled aggregation entry point'
            conditions = 'three cold child-process samples; same automatic-review state machine; no timing sleeps'
        }
        helperDuration = if ($helperDurations.Count -eq 0) {
            [ordered]@{ state = 'not_run'; value = $null; sampleCount = 0; source = 'no instrumentation helper was invoked in the disabled control' }
        } else {
            [ordered]@{
                state = 'measured'
                unit = 'milliseconds'
                sampleCount = $helperDurations.Count
                warmUp = 0
                samples = @($helperDurations | Sort-Object)
                minimum = [math]::Round(($helperDurations | Measure-Object -Minimum).Minimum, 3)
                median = [math]::Round((Get-Median $helperDurations), 3)
                maximum = [math]::Round(($helperDurations | Measure-Object -Maximum).Maximum, 3)
                source = 'local monotonic Stopwatch around the production recorder child process and aggregator entry point'
                conditions = 'three cold candidate samples; one recorder append and one aggregation entry point per sample'
            }
        }
        samples = @($Samples | ForEach-Object {
                [ordered]@{
                    sampleId = $_.sampleId
                    transitionCount = $_.transitionCount
                    normalMessageCount = $_.normalMessageCount
                    agentCount = $_.agentCount
                    pollingEventCount = $_.pollingEventCount
                    measurementOnlyMessageCount = $_.measurementOnlyMessageCount
                    helperInvocations = $_.helperInvocations
                    recorderInvocationCount = $_.recorderInvocationCount
                    aggregationInvocationCount = $_.aggregationInvocationCount
                    eventCount = $_.eventCount
                    eventBytes = $_.eventBytes
                    reportBytes = $_.reportBytes
                    controlDurationMilliseconds = $_.controlDurationMilliseconds
                    helperDurationMilliseconds = $_.helperDurationMilliseconds
                }
            })
    }
}

function Test-OverheadAcceptance {
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Baseline,
        [Parameter(Mandatory)] [AllowNull()] [object] $Candidate,
        [Parameter(Mandatory)] [object] $Budget
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Baseline -or $null -eq $Candidate) {
        [void]$reasons.Add('comparable observed baseline and candidate evidence are required')
        return [ordered]@{
            state = 'unavailable'
            sameOutcome = $false
            sameWorkload = $false
            observedCountDelta = $null
            measuredControlDurationDeltaMilliseconds = $null
            withinBudget = $false
            reasons = @($reasons)
        }
    }
    if ([string]$Baseline.workloadId -cne [string]$Candidate.workloadId) { [void]$reasons.Add('workload identity changed') }
    if ([string]$Baseline.outcomeFingerprint -cne [string]$Candidate.outcomeFingerprint) { [void]$reasons.Add('observed workflow outcome changed') }
    foreach ($field in @('transitionCount', 'normalMessageCount', 'agentCount', 'pollingEventCount', 'measurementOnlyMessageCount')) {
        if ([int]$Baseline.$field -ne [int]$Candidate.$field) { [void]$reasons.Add("observed workflow count changed: $field") }
    }
    $addedTransitions = [int]$Candidate.transitionCount - [int]$Baseline.transitionCount
    $addedNormalMessages = [int]$Candidate.normalMessageCount - [int]$Baseline.normalMessageCount
    $addedAgents = [int]$Candidate.agentCount - [int]$Baseline.agentCount
    $addedPolling = [int]$Candidate.pollingEventCount - [int]$Baseline.pollingEventCount
    $addedMeasurementOnly = [int]$Candidate.measurementOnlyMessageCount - [int]$Baseline.measurementOnlyMessageCount
    if ($addedTransitions -gt [int]$Budget.maxAddedTransitions) { [void]$reasons.Add('added transition count exceeded the declared budget') }
    if ($addedNormalMessages -gt [int]$Budget.maxAddedNormalMessages) { [void]$reasons.Add('added normal-message count exceeded the declared budget') }
    if ($addedAgents -gt [int]$Budget.maxAddedAgents) { [void]$reasons.Add('candidate added an agent') }
    if ($addedPolling -gt [int]$Budget.maxPollingEvents) { [void]$reasons.Add('candidate added polling') }
    if ($addedMeasurementOnly -gt [int]$Budget.maxMeasurementOnlyMessages) { [void]$reasons.Add('candidate added a measurement-only message') }
    if ([int]$Candidate.helperInvocations -gt [int]$Budget.maxHelperInvocations) { [void]$reasons.Add('helper invocation count exceeded the declared budget') }
    $controlDelta = [double]$Candidate.controlDuration.median - [double]$Baseline.controlDuration.median
    if ($controlDelta -gt [double]$Budget.maxControlDurationDeltaMilliseconds) { [void]$reasons.Add('measured control duration delta exceeded the declared environment budget') }
    if ([int]$Candidate.eventCount -gt [int]$Budget.maxCandidateEvents) { [void]$reasons.Add('candidate persisted event count exceeded the declared boundary budget') }
    if ([string]$Candidate.usageState -notin @('unavailable', 'partial')) { [void]$reasons.Add('unknown usage must remain unavailable or partial') }
    return [ordered]@{
        state = if ($reasons.Count -eq 0) { 'pass' } else { 'fail' }
        sameOutcome = ([string]$Baseline.outcomeFingerprint -ceq [string]$Candidate.outcomeFingerprint)
        sameWorkload = ([string]$Baseline.workloadId -ceq [string]$Candidate.workloadId)
        observedCountDelta = [ordered]@{
            transitions = $addedTransitions
            normalMessages = $addedNormalMessages
            agents = $addedAgents
            pollingEvents = $addedPolling
            measurementOnlyMessages = $addedMeasurementOnly
        }
        measuredControlDurationDeltaMilliseconds = [math]::Round($controlDelta, 3)
        withinBudget = ($reasons.Count -eq 0)
        reasons = @($reasons)
    }
}

function Get-SourceBoundAnalysis {
    param(
        [Parameter(Mandatory)] [string] $RecorderPath,
        [Parameter(Mandatory)] [string] $AggregatorPath
    )

    $recorderLines = @(Get-Content -LiteralPath $RecorderPath)
    $aggregatorLines = @(Get-Content -LiteralPath $AggregatorPath)
    $readAllBytesLine = @($recorderLines | Select-String -Pattern '\[IO\.File\]::ReadAllBytes\(\$LedgerPath\)' | Select-Object -First 1)
    $aggregateReadLine = @($aggregatorLines | Select-String -Pattern 'Read-EventLedger -Path \$resolvedEventsPath' | Select-Object -First 1)
    Assert-True ($readAllBytesLine.Count -eq 1) 'source analysis must find the recorder full-ledger read'
    Assert-True ($aggregateReadLine.Count -eq 1) 'source analysis must find the aggregator ledger read'
    return [ordered]@{
        state = 'limited'
        evidence = 'automated_source_assertion'
        recorder = [ordered]@{
            path = $RecorderPath
            fullLedgerRead = $true
            line = [int]$readAllBytesLine[0].LineNumber
            complexity = 'O(existing ledger bytes + appended event bytes) per append; the recorder rereads the complete ledger before writing'
            constantHookWorkClaim = 'not_claimed'
        }
        aggregator = [ordered]@{
            path = $AggregatorPath
            ledgerRead = $true
            line = [int]$aggregateReadLine[0].LineNumber
            complexity = 'O(ledger bytes and records) per aggregation invocation'
        }
        productionThreshold = 'unavailable_without an authorized production workload and environment-controlled benchmark'
        limitation = 'fixed transition counts and helper invocation counts do not imply constant recorder CPU/I/O work'
    }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-performance-overhead-' + [Guid]::NewGuid().ToString('N'))
$externalRoot = Join-Path $fixtureRoot 'external-run-root'
$automaticReviewPath = Join-Path $PSScriptRoot 'validate-automatic-review-flow.ps1'
$recorderPath = Join-Path $PSScriptRoot 'write-performance-event.ps1'
$aggregatorPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..\scripts\get-story-performance.ps1'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))

[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
Push-Location -LiteralPath $repositoryRoot
try {
    $validatorResults = Invoke-ValidatorSuite -ScriptRoot $PSScriptRoot
    $baselineSamples = @(1..3 | ForEach-Object {
            Invoke-ControlSample -SampleId ("sample-{0}" -f $_) -Mode disabled -ExternalRoot $externalRoot -AutomaticReviewPath $automaticReviewPath -AggregatorPath $aggregatorPath
        })
    $candidateSamples = @(1..3 | ForEach-Object {
            Invoke-ControlSample -SampleId ("sample-{0}" -f $_) -Mode enabled -ExternalRoot $externalRoot -AutomaticReviewPath $automaticReviewPath -AggregatorPath $aggregatorPath
        })
    $baseline = Get-ControlSummary -Samples $baselineSamples -Mode disabled
    $candidate = Get-ControlSummary -Samples $candidateSamples -Mode enabled
    Assert-True ([string]$baseline.outcomeFingerprint -ceq [string]$candidate.outcomeFingerprint) 'actual disabled/enabled workflow controls must produce the same observed outcome'
    Assert-True ([int]$baseline.transitionCount -eq [int]$candidate.transitionCount -and
        [int]$baseline.normalMessageCount -eq [int]$candidate.normalMessageCount -and
        [int]$baseline.agentCount -eq [int]$candidate.agentCount -and
        [int]$baseline.pollingEventCount -eq [int]$candidate.pollingEventCount -and
        [int]$baseline.measurementOnlyMessageCount -eq [int]$candidate.measurementOnlyMessageCount) 'actual disabled/enabled workflow traces must preserve operation counts'
    Assert-True ([int]$baseline.helperInvocations -eq 0 -and [int]$candidate.helperInvocations -eq 2) 'helper invocation counts must come from the observed disabled/enabled controls'
    Assert-True ([int]$candidate.eventCount -gt 0 -and [int]$candidate.eventBytes -gt 0 -and [int]$candidate.reportBytes -gt 0) 'enabled control must retain actual event and report byte evidence'
    Assert-True ([string]$baseline.reportState -ceq 'not_run' -and [string]$candidate.reportState -ceq 'measured') 'report coverage must distinguish disabled and enabled controls'

    $budget = [ordered]@{
        maxAddedTransitions = 0
        maxAddedNormalMessages = 0
        maxAddedAgents = 0
        maxPollingEvents = 0
        maxMeasurementOnlyMessages = 0
        maxHelperInvocations = 2
        maxCandidateEvents = 1
        maxControlDurationDeltaMilliseconds = 120000
    }
    $acceptance = Test-OverheadAcceptance -Baseline $baseline -Candidate $candidate -Budget $budget
    Assert-True ([string]$acceptance.state -ceq 'pass') 'observed disabled/enabled workflow controls must satisfy bounded-operation acceptance'

    $sourceBounds = Get-SourceBoundAnalysis -RecorderPath $recorderPath -AggregatorPath $aggregatorPath
    Assert-True ([string]$sourceBounds.recorder.constantHookWorkClaim -ceq 'not_claimed' -and [string]$sourceBounds.state -ceq 'limited') 'source bounds must not claim constant recorder work'

    $negativeControls = @()
    $changedOutcome = Copy-JsonObject $candidate
    $changedOutcome.outcomeFingerprint = 'bypassed-workflow-outcome'
    $negativeControls += [ordered]@{ case = 'bypassed-workflow-trace'; result = Test-OverheadAcceptance -Baseline $baseline -Candidate $changedOutcome -Budget $budget }
    $extraAction = Copy-JsonObject $candidate
    $extraAction.normalMessageCount = [int]$extraAction.normalMessageCount + 1
    $negativeControls += [ordered]@{ case = 'instrumentation-extra-message'; result = Test-OverheadAcceptance -Baseline $baseline -Candidate $extraAction -Budget $budget }
    $extraAgent = Copy-JsonObject $candidate
    $extraAgent.agentCount = [int]$extraAgent.agentCount + 1
    $negativeControls += [ordered]@{ case = 'instrumentation-extra-agent'; result = Test-OverheadAcceptance -Baseline $baseline -Candidate $extraAgent -Budget $budget }
    $extraEvent = Copy-JsonObject $candidate
    $extraEvent.eventCount = [int]$extraEvent.eventCount + 1
    $negativeControls += [ordered]@{ case = 'instrumentation-extra-event'; result = Test-OverheadAcceptance -Baseline $baseline -Candidate $extraEvent -Budget $budget }
    $missingBaseline = Test-OverheadAcceptance -Baseline $null -Candidate $candidate -Budget $budget
    $negativeControls += [ordered]@{ case = 'missing-comparable-evidence'; result = $missingBaseline }
    foreach ($control in $negativeControls) {
        Assert-True ([string]$control.result.state -in @('fail', 'unavailable')) "negative control $($control.case) must not pass"
    }

    $scenarioEvidence = @(
        [ordered]@{ scenario = 'validator-suite'; setup = 'all checked-in validate-*.ps1 files except this orchestrator'; action = 'run from repository root in fresh PowerShell processes'; expected = 'every validator exits 0'; observed = "$($validatorResults.Count) validators exited 0"; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'matched workflow controls'; setup = 'same automatic-review state machine, three disabled and three enabled cold samples'; action = 'derive transitions/messages/agents/polling/measurement-only counts from actual traces'; expected = 'same outcome and operation counts; only declared instrumentation helpers appear'; observed = 'observed traces matched; enabled recorder/aggregator calls and bytes recorded'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'helper duration'; setup = 'local monotonic Stopwatch, three samples per control, no sleeps'; action = 'measure control and enabled helper durations'; expected = 'actual samples with conditions, not a fixed-clock percentage'; observed = 'baseline/candidate control durations and candidate helper samples recorded'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'processing bounds'; setup = 'source inspection of recorder and aggregator ledger reads'; action = 'report algorithmic bounds and limitations'; expected = 'no constant-hook claim when append rereads the full ledger'; observed = 'recorder O(existing ledger bytes + event bytes) per append; aggregator O(ledger bytes); production threshold unavailable'; evidence = 'automated_assertion'; status = 'passed' },
        [ordered]@{ scenario = 'attributable usage'; setup = 'current host capability matrix'; action = 'retain explicit unavailable state'; expected = 'no token estimate from account limits, text length, file size, event count, or timing'; observed = 'baseline/candidate usageState=unavailable'; evidence = 'unavailable'; status = 'not_run' },
        [ordered]@{ scenario = 'negative controls'; setup = 'bypassed trace, extra message/agent/event, and missing baseline mutations'; action = 'evaluate observed-evidence contract'; expected = 'unsafe or incomparable evidence never passes'; observed = "all $($negativeControls.Count) controls rejected"; evidence = 'automated_assertion'; status = 'passed' }
    )
    Write-Output 'Scenario evidence (synthetic unless explicitly marked unavailable):'
    foreach ($scenario in $scenarioEvidence) {
        Write-Output (($scenario.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' | ')
    }
    Write-Output 'PASS: observed workflow compatibility and bounded-overhead evidence; no fabricated elapsed percentage or constant recorder-work claim.'
    [ordered]@{
        schemaVersion = 1
        kind = 'synthetic_performance_overhead_report'
        evidenceClass = 'synthetic_fixture'
        validatorResults = $validatorResults
        baseline = $baseline
        candidate = $candidate
        budget = $budget
        overhead = [ordered]@{
            state = 'measured'
            controlDurationDeltaMilliseconds = $acceptance.measuredControlDurationDeltaMilliseconds
            controlDurationDeltaSource = 'matched disabled/enabled local Stopwatch samples'
            helperDuration = $candidate.helperDuration
            usageState = 'unavailable'
            sourceBounds = $sourceBounds
        }
        acceptance = $acceptance
        negativeControls = $negativeControls
        scenarioEvidence = $scenarioEvidence
    } | ConvertTo-Json -Depth 60
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
