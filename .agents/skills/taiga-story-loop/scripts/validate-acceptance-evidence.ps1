# SYNTHETIC ACCEPTANCE-EVIDENCE CHECK.
# This executable fixture tests evidence-shape and provenance rules only. It
# does not contact Taiga, GitHub, Codex, a browser, a database, or a live app.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Acceptance-evidence assertion failed: $Message" }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}

function Assert-CapabilityClaim {
    param(
        [System.Collections.IDictionary] $Claim,
        [System.Collections.IDictionary] $Observed
    )

    $name = [string]$Claim.name
    Assert-True (-not [string]::IsNullOrWhiteSpace($name)) 'capability claims require a name'
    Assert-True ($Observed.Contains($name)) "capability claim has no observed record: $name"
    $record = $Observed[$name]
    $status = [string]$Claim.status
    Assert-True ($status -in @('available', 'unavailable', 'unverified')) "unsupported capability status: $status"
    Assert-True ([string]$record.sourceType -in @('documentation', 'tool_schema', 'probe')) "observed capability $name has no valid source type"
    Assert-True ([string]$Claim.sourceType -ceq [string]$record.sourceType) "capability $name claim source type does not match the observed source"
    Assert-True ([string]$Claim.source -ceq [string]$record.source) "capability $name claim source does not match the observed source"
    if ($status -eq 'available') { Assert-True ($record.available -eq $true) "capability $name was declared available although the observation found it unavailable" }
    if ($status -eq 'unavailable') { Assert-True ($record.available -eq $false) "capability $name was declared unavailable although the authorized probe found it available" }
    if ($status -eq 'unavailable') {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$Claim.source)) "unavailable capability $name needs a source"
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$Claim.reason)) "unavailable capability $name needs a reason"
    }
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$Claim.source)) "capability $name needs a documentation or probe source"
    return $true
}

function Invoke-ProductionSearch {
    param(
        [string] $Query,
        [System.Collections.IDictionary] $EvidenceHints,
        [switch] $BypassValidation
    )

    if ($BypassValidation) { throw 'production validation was bypassed' }
    $validation = Invoke-ProductionValidation -Query $Query
    $script:eventLog += [ordered]@{ stage = 'production'; query = $Query }
    $script:productionCalls += [ordered]@{
        query = $Query
        evidenceHints = $EvidenceHints
        validationPassed = $validation.passed
        validationSequence = $validation.sequence
    }
    return [ordered]@{
        productionPathReached = $true
        query = $Query
        evidenceHints = $EvidenceHints
        validationPassed = $validation.passed
        validationSequence = $validation.sequence
        results = @('synthetic-result')
        resultSemantics = 'production-result'
    }
}

function Invoke-ProductionValidation {
    param([string] $Query)

    $sequence = @($script:validationCalls).Count + 1
    $script:validationCalls += [ordered]@{ query = $Query; sequence = $sequence }
    $script:eventLog += [ordered]@{ stage = 'validation'; query = $Query }
    if ([string]::IsNullOrWhiteSpace($Query)) { throw 'production validation rejected a blank query' }
    return [ordered]@{ passed = $true; sequence = $sequence }
}

function Invoke-ForwardingWrapper {
    param(
        [string] $Query,
        [System.Collections.IDictionary] $EvidenceHints,
        [switch] $DropEvidenceHints,
        [switch] $SkipValidation
    )

    $forwardedHints = if ($DropEvidenceHints) { [ordered]@{} } else { $EvidenceHints }
    return Invoke-ProductionSearch -Query $Query -EvidenceHints $forwardedHints -BypassValidation:$SkipValidation
}

function Invoke-BypassingWrapper {
    param([string] $Query, [System.Collections.IDictionary] $EvidenceHints)
    return [ordered]@{
        productionPathReached = $false
        query = $Query
        evidenceHints = [ordered]@{}
        results = @('wrapper-only-result')
        resultSemantics = 'stub-result'
    }
}

function Assert-ProductionEvidence {
    param(
        [System.Collections.IDictionary] $Result,
        [string] $ExpectedQuery,
        [System.Collections.IDictionary] $ExpectedHints
    )

    Assert-True ($Result.productionPathReached -eq $true) 'production-path control was not reached'
    Assert-True ([string]$Result.query -ceq $ExpectedQuery) 'wrapper changed the required production query'
    Assert-True ($Result.validationPassed -eq $true) 'production validation did not run'
    Assert-True ([int]$Result.validationSequence -gt 0) 'production validation has no observable call sequence'
    Assert-True ([string]$Result.resultSemantics -ceq 'production-result') 'wrapper returned non-production result semantics'
    foreach ($key in $ExpectedHints.Keys) {
        Assert-True ($Result.evidenceHints.Contains($key)) "wrapper dropped required evidence hint: $key"
        Assert-True ([string]$Result.evidenceHints[$key] -ceq [string]$ExpectedHints[$key]) "wrapper changed evidence hint: $key"
    }
}

function Assert-MetricRecord {
    param([System.Collections.IDictionary] $Metric)

    foreach ($field in @('operation', 'counter', 'unit', 'warmUp', 'conditions', 'baseline', 'limitations')) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$Metric[$field])) "metric is missing $field"
    }
    Assert-True ([int]$Metric.sampleSize -gt 0) 'metric sample size must be positive'
    if ([string]$Metric.event -eq 'cache_hit' -and [string]$Metric.claim -eq 'evidence_reuse') {
        throw 'an adjacent cache hit cannot be reported as intended evidence reuse'
    }
    if ([string]$Metric.claim -eq 'speedup') {
        Assert-True ($Metric.baselineComparable -eq $true) 'speedup requires a comparable baseline'
    }
}

function Assert-ScenarioCoverage {
    param(
        [System.Collections.IEnumerable] $Scenarios,
        [string[]] $RequiredIds
    )

    foreach ($requiredId in $RequiredIds) {
        $scenario = @($Scenarios | Where-Object { [string]$_.id -ceq $requiredId })
        Assert-True ($scenario.Count -eq 1) "required scenario is missing or duplicated: $requiredId"
        $record = $scenario[0]
        Assert-True ([string]$record.evidenceKind -in @('automated_assertion', 'visible_observation', 'unavailable')) "scenario $requiredId has no evidence classification"
        foreach ($field in @('setup', 'action', 'expected', 'observed', 'status')) {
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record[$field])) "scenario $requiredId is missing $field"
        }
        $evidenceKind = [string]$record.evidenceKind
        $status = [string]$record.status
        if ($evidenceKind -eq 'unavailable') {
            Assert-True ($status -in @('unavailable', 'not_run')) "unavailable scenario $requiredId cannot have status '$status'"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record.limitationSource)) "unavailable scenario $requiredId needs a capability source"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record.nextAction)) "unavailable scenario $requiredId needs a next action"
        } elseif ($evidenceKind -eq 'automated_assertion') {
            Assert-True ($status -in @('passed', 'failed', 'pending_review')) "automated scenario $requiredId has unsupported status '$status'"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record.evidence)) "scenario $requiredId needs evidence"
        } else {
            Assert-True ($status -in @('passed', 'failed', 'pending_host_observation')) "visible scenario $requiredId has unsupported status '$status'"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record.evidence)) "scenario $requiredId needs evidence"
        }
    }
}

function Assert-SmokePlan {
    param([System.Collections.IDictionary] $Smoke)

    foreach ($field in @('setup', 'start', 'cleanup', 'workingDirectory', 'dataScope')) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$Smoke[$field])) "smoke plan is missing $field"
    }
    Assert-True (@($Smoke.requiredCapabilities).Count -gt 0) 'smoke plan must name required capabilities'
    Assert-True (@($Smoke.actions).Count -gt 0) 'smoke plan needs executable actions'
    Assert-True (@($Smoke.expectedResults).Count -eq @($Smoke.actions).Count) 'smoke actions need one expected result each'
    Assert-True ($Smoke.disposable -eq $true) 'smoke data must be explicitly disposable'
    Assert-True ([string]$Smoke.dataScope -match '(?i)disposable|synthetic|authorized') 'smoke data scope must be safe and authorized'
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $skillRoot 'assets/acceptance-evidence-scenarios.json'
Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'acceptance-evidence manifest is present'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
Assert-True ([int]$manifest.schemaVersion -eq 1) 'manifest schema version is supported'
Assert-True ([string]$manifest.kind -ceq 'synthetic_acceptance_evidence') 'manifest identifies synthetic evidence'
Assert-True (-not [bool]$manifest.liveProvider) 'manifest must not claim live-provider evidence'
Assert-True (@($manifest.scenarios).Count -eq 5) 'manifest contains all five focused scenarios'
$requiredScenarioIds = @($manifest.requiredScenarioIds | ForEach-Object { [string]$_ })
Assert-True ($requiredScenarioIds.Count -eq 3 -and (@($requiredScenarioIds | Select-Object -Unique).Count -eq 3)) 'manifest must define three unique required scenario IDs'
$manifestCases = @{}
foreach ($manifestScenario in @($manifest.scenarios)) {
    $validation = [string]$manifestScenario.validation
    Assert-True ($validation -in @('capability', 'production_path', 'metrics', 'scenario_coverage', 'limitation')) "manifest has unsupported validation: $validation"
    Assert-True (-not $manifestCases.ContainsKey($validation)) "manifest repeats validation: $validation"
    $manifestCases[$validation] = $manifestScenario
}
foreach ($validation in @('capability', 'production_path', 'metrics', 'scenario_coverage', 'limitation')) {
    Assert-True ($manifestCases.ContainsKey($validation)) "manifest is missing validation case: $validation"
}
Assert-True (@($manifest.scenarioMatrix).Count -eq $requiredScenarioIds.Count) 'manifest scenario matrix must cover each required scenario ID'
$scenarioRecords = @()
foreach ($manifestScenario in @($manifest.scenarioMatrix)) {
    $scenarioRecord = [ordered]@{
        id = [string]$manifestScenario.id
        evidenceKind = [string]$manifestScenario.evidenceKind
        setup = [string]$manifestScenario.setup
        action = [string]$manifestScenario.action
        expected = [string]$manifestScenario.expected
        observed = [string]$manifestScenario.observed
        status = [string]$manifestScenario.status
    }
    foreach ($optionalField in @('evidence', 'limitationSource', 'nextAction')) {
        if ($manifestScenario.PSObject.Properties.Name -contains $optionalField) {
            $scenarioRecord[$optionalField] = [string]$manifestScenario.$optionalField
        }
    }
    $scenarioRecords += $scenarioRecord
}
Assert-True (@($scenarioRecords | ForEach-Object id | Select-Object -Unique).Count -eq $requiredScenarioIds.Count) 'manifest scenario matrix IDs must be unique'
foreach ($requiredScenarioId in $requiredScenarioIds) {
    Assert-True (@($scenarioRecords | Where-Object { $_.id -ceq $requiredScenarioId }).Count -eq 1) "manifest scenario matrix is missing $requiredScenarioId"
}
$automatedScenario = @($scenarioRecords | Where-Object evidenceKind -eq 'automated_assertion')[0]
$unavailableScenario = @($scenarioRecords | Where-Object evidenceKind -eq 'unavailable')[0]
Assert-True ($null -ne $automatedScenario -and $null -ne $unavailableScenario) 'manifest scenario matrix needs automated and unavailable cases'

$observedCapabilities = @{
    viewport = [ordered]@{ available = $true; source = 'synthetic host capability probe'; sourceType = 'probe' }
    console = [ordered]@{ available = $false; source = 'synthetic authorized capability probe'; sourceType = 'probe' }
}
Assert-Throws {
    Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'viewport'; status = 'unavailable'; source = 'wrapper convenience API'; sourceType = 'probe'; reason = 'wrapper has no viewport helper' })
} "$($manifestCases.capability.id) must reject a wrapper-based unavailable claim"
Assert-Throws {
    Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'viewport'; status = 'unavailable'; source = 'synthetic host capability probe'; sourceType = 'probe'; reason = 'capability reported missing' })
} "$($manifestCases.capability.id) must reject an unavailable claim when observed availability is true"
Assert-Throws {
    Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'console'; status = 'available'; source = 'synthetic authorized capability probe'; sourceType = 'probe' })
} 'an available claim must not contradict an unavailable observation'
Assert-Throws {
    Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'viewport'; status = 'available'; source = 'wrong documentation'; sourceType = 'documentation' })
} "$($manifestCases.capability.id) must require matching capability provenance"
Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'viewport'; status = 'available'; source = 'synthetic host capability probe'; sourceType = 'probe' }) | Out-Null
Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'console'; status = 'unavailable'; source = 'synthetic authorized capability probe'; sourceType = 'probe'; reason = 'console stream was not exposed' }) | Out-Null

$script:productionCalls = @()
$script:validationCalls = @()
$script:eventLog = @()
$query = 'synthetic recipe query'
$hints = [ordered]@{ ingredientEvidence = 'hint-7'; requestedBy = 'acceptance-fixture' }
$forwarded = Invoke-ForwardingWrapper -Query $query -EvidenceHints $hints
Assert-ProductionEvidence -Result $forwarded -ExpectedQuery $query -ExpectedHints $hints
Assert-True (@($script:productionCalls).Count -eq 1) 'production call control should record exactly one call'
Assert-True (@($script:validationCalls).Count -eq 1) 'production validation control should record exactly one call'
Assert-True ([string]$script:eventLog[0].stage -ceq 'validation' -and [string]$script:eventLog[1].stage -ceq 'production') 'validation must be observed before the production call'
Assert-Throws { Invoke-ForwardingWrapper -Query ' ' -EvidenceHints $hints } 'production validation must reject blank input'
Assert-Throws { Invoke-ForwardingWrapper -Query $query -EvidenceHints $hints -SkipValidation } 'wrapper must not bypass production validation'
Assert-Throws {
    $dropped = Invoke-ForwardingWrapper -Query $query -EvidenceHints $hints -DropEvidenceHints
    Assert-ProductionEvidence -Result $dropped -ExpectedQuery $query -ExpectedHints $hints
} "$($manifestCases.production_path.id) must expose wrapper argument loss"
Assert-Throws {
    Assert-ProductionEvidence -Result (Invoke-BypassingWrapper -Query $query -EvidenceHints $hints) -ExpectedQuery $query -ExpectedHints $hints
} "$($manifestCases.production_path.id) must reject a production-path bypass"

$badMetric = [ordered]@{
    operation = 'ingredient evidence lookup'
    event = 'cache_hit'
    claim = 'evidence_reuse'
    counter = 'cache hits'
    unit = 'hits'
    sampleSize = 3
    warmUp = 'none'
    conditions = 'warm cache'
    baseline = 'none'
    baselineComparable = $false
    limitations = 'no upstream request baseline'
}
Assert-Throws { Assert-MetricRecord $badMetric } "$($manifestCases.metrics.id) must reject mislabeled cache evidence"
$goodMetric = [ordered]@{
    operation = 'ingredient evidence lookup'
    event = 'evidence_reuse'
    claim = 'intended evidence reuse'
    counter = 'reused evidence entries'
    unit = 'entries'
    sampleSize = 3
    warmUp = 'one synthetic warm-up'
    conditions = 'same revision and same evidence key'
    baseline = 'cold lookup of the same operation'
    baselineComparable = $true
    limitations = 'synthetic counts; no latency claim'
}
Assert-MetricRecord $goodMetric

$missingScenario = [ordered]@{}
foreach ($key in $automatedScenario.Keys) { $missingScenario[$key] = $automatedScenario[$key] }
$missingScenario.evidence = ''
Assert-Throws { Assert-ScenarioCoverage -Scenarios @($missingScenario) -RequiredIds @($automatedScenario.id) } "$($manifestCases.scenario_coverage.id) must reject missing evidence"
$unavailableWithPassedStatus = [ordered]@{}
foreach ($key in $unavailableScenario.Keys) { $unavailableWithPassedStatus[$key] = $unavailableScenario[$key] }
$unavailableWithPassedStatus.status = 'passed'
Assert-Throws { Assert-ScenarioCoverage -Scenarios @($unavailableWithPassedStatus) -RequiredIds @($unavailableScenario.id) } "$($manifestCases.limitation.id) must keep an unavailable case honest"
Assert-ScenarioCoverage -Scenarios $scenarioRecords -RequiredIds $requiredScenarioIds

$badSmoke = [ordered]@{
    setup = 'pwsh ./setup.ps1'; start = 'pwsh ./start.ps1'; cleanup = ''; workingDirectory = '.'; dataScope = 'live database'; disposable = $false
    requiredCapabilities = @('browser'); actions = @('open page'); expectedResults = @('page opens')
}
Assert-Throws { Assert-SmokePlan $badSmoke } 'unsafe or incomplete smoke instructions must be rejected'
$goodSmoke = [ordered]@{
    setup = 'pwsh ./setup-disposable.ps1'; start = 'pwsh ./start-local.ps1'; cleanup = 'pwsh ./cleanup-disposable.ps1'; workingDirectory = 'C:\Temp\acceptance-fixture'; dataScope = 'synthetic disposable data'; disposable = $true; requiredCapabilities = @('browser')
    actions = @('open the result', 'inspect the rendered state'); expectedResults = @('result is visible', 'layout matches the criterion')
}
Assert-SmokePlan $goodSmoke

Write-Output 'Passed acceptance-evidence fixture: capability discovery, production-path controls, metric provenance, scenario classification, honest limitation, and safe smoke-plan assertions; synthetic and non-live.'
exit 0
