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
    if ($status -eq 'unavailable' -and $record.available -eq $true) {
        throw "capability $name was declared unavailable although the authorized probe found it available"
    }
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
        [bool] $ValidationPassed
    )

    if (-not $ValidationPassed) { throw 'production validation was bypassed' }
    if ([string]::IsNullOrWhiteSpace($Query)) { throw 'production validation rejected a blank query' }
    $script:productionCalls += [ordered]@{
        query = $Query
        evidenceHints = $EvidenceHints
        validationPassed = $ValidationPassed
    }
    return [ordered]@{
        productionPathReached = $true
        query = $Query
        evidenceHints = $EvidenceHints
        results = @('synthetic-result')
        resultSemantics = 'production-result'
    }
}

function Invoke-ForwardingWrapper {
    param(
        [string] $Query,
        [System.Collections.IDictionary] $EvidenceHints,
        [switch] $DropEvidenceHints,
        [switch] $SkipValidation
    )

    $forwardedHints = if ($DropEvidenceHints) { [ordered]@{} } else { $EvidenceHints }
    return Invoke-ProductionSearch -Query $Query -EvidenceHints $forwardedHints -ValidationPassed (-not $SkipValidation)
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
        if ([string]$record.evidenceKind -eq 'unavailable') {
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record.limitationSource)) "unavailable scenario $requiredId needs a capability source"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$record.nextAction)) "unavailable scenario $requiredId needs a next action"
        } else {
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

$observedCapabilities = @{
    viewport = [ordered]@{ available = $true; source = 'synthetic host capability probe' }
    console = [ordered]@{ available = $false; source = 'synthetic authorized capability probe' }
}
Assert-Throws {
    Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'viewport'; status = 'unavailable'; source = 'wrapper convenience API'; reason = 'wrapper has no viewport helper' })
} 'a wrapper limitation must not become a false host-unavailable claim'
Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'viewport'; status = 'available'; source = 'synthetic host capability probe' }) | Out-Null
Assert-CapabilityClaim -Observed $observedCapabilities -Claim ([ordered]@{ name = 'console'; status = 'unavailable'; source = 'synthetic authorized capability probe'; reason = 'console stream was not exposed' }) | Out-Null

$script:productionCalls = @()
$query = 'synthetic recipe query'
$hints = [ordered]@{ ingredientEvidence = 'hint-7'; requestedBy = 'acceptance-fixture' }
$forwarded = Invoke-ForwardingWrapper -Query $query -EvidenceHints $hints
Assert-ProductionEvidence -Result $forwarded -ExpectedQuery $query -ExpectedHints $hints
Assert-True (@($script:productionCalls).Count -eq 1) 'production call control should record exactly one call'
Assert-Throws { Invoke-ForwardingWrapper -Query ' ' -EvidenceHints $hints } 'production validation must reject blank input'
Assert-Throws { Invoke-ForwardingWrapper -Query $query -EvidenceHints $hints -SkipValidation } 'wrapper must not bypass production validation'
Assert-Throws {
    $dropped = Invoke-ForwardingWrapper -Query $query -EvidenceHints $hints -DropEvidenceHints
    Assert-ProductionEvidence -Result $dropped -ExpectedQuery $query -ExpectedHints $hints
} 'wrapper argument loss must be visible in the production-path assertion'
Assert-Throws {
    Assert-ProductionEvidence -Result (Invoke-BypassingWrapper -Query $query -EvidenceHints $hints) -ExpectedQuery $query -ExpectedHints $hints
} 'a wrapper bypass must not count as production-path evidence'

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
Assert-Throws { Assert-MetricRecord $badMetric } 'mislabeled cache metric must be rejected'
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

$missingScenario = @([ordered]@{
    id = 'normal-search'
    evidenceKind = 'automated_assertion'
    setup = 'synthetic data'
    action = 'invoke production path'
    expected = 'result is returned'
    observed = 'assertion passed'
    status = 'passed'
    evidence = ''
})
Assert-Throws { Assert-ScenarioCoverage -Scenarios $missingScenario -RequiredIds @('normal-search') } 'missing scenario evidence must not pass coverage'
$scenarioRecords = @(
    [ordered]@{ id = 'normal-search'; evidenceKind = 'automated_assertion'; setup = 'synthetic data'; action = 'invoke production path'; expected = 'result is returned'; observed = 'assertion passed'; status = 'passed'; evidence = 'synthetic assertion output' }
    [ordered]@{ id = 'responsive-observation'; evidenceKind = 'visible_observation'; setup = 'authorized disposable page'; action = 'resize and inspect layout'; expected = 'content remains usable'; observed = 'observation required on host'; status = 'pending_host_observation'; evidence = 'visible observation record' }
    [ordered]@{ id = 'console-check'; evidenceKind = 'unavailable'; setup = 'authorized host'; action = 'inspect console'; expected = 'no unexpected errors'; observed = 'not run'; status = 'unavailable'; limitationSource = 'synthetic authorized capability probe'; nextAction = 'report limitation and request a host with console access' }
)
Assert-ScenarioCoverage -Scenarios $scenarioRecords -RequiredIds @('normal-search', 'responsive-observation', 'console-check')

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
