[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('plan','validate-plan','validate-smoke','reuse-evidence')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'

function Read-Object {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw 'Input file was not found.' }
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw 'Input JSON must be an object.' }
    return $value
}

function Need {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }
    return [string]$Object[$Name]
}

function Get-FileSha256 {
    param([string] $Path)
    $stream = [IO.File]::OpenRead($Path); $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($stream))).ToLowerInvariant() } finally { $sha.Dispose(); $stream.Dispose() }
}

function Resolve-Reference {
    param([System.Collections.IDictionary] $Reference, [string] $Name)
    $path = [IO.Path]::GetFullPath((Need $Reference 'path'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Name file was not found." }
    $hash = Get-FileSha256 $path
    if (-not $Reference.Contains('sha256') -or [string]$Reference.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [string]$Reference.sha256.ToLowerInvariant() -cne $hash) { throw "$Name sha256 does not match its file." }
    return [ordered]@{ path = $path; sha256 = $hash }
}

function Read-ReferenceJson {
    param([System.Collections.IDictionary] $Reference, [string] $Name)
    $resolved = Resolve-Reference $Reference $Name
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $resolved.path) -AsHashtable -Depth 100 } catch { throw "$Name is not valid JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw "$Name JSON must be an object." }
    return [ordered]@{ reference = $resolved; value = $value }
}

function Get-StringArray {
    param([System.Collections.IDictionary] $Object, [string] $Name, [switch] $AllowEmpty)
    if (-not $Object.Contains($Name) -or $Object[$Name] -is [string] -or $Object[$Name] -isnot [System.Collections.IEnumerable]) { throw "$Name must be an array." }
    $items = @($Object[$Name] | ForEach-Object { if ([string]::IsNullOrWhiteSpace([string]$_)) { throw "$Name entries must be nonblank." }; [string]$_ })
    if (-not $AllowEmpty -and $items.Count -eq 0) { throw "$Name must not be empty." }
    return $items
}

function Write-ImmutableJson {
    param([string] $Path, [object] $Value)
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ((Get-Content -Raw -LiteralPath $Path) -cne $json) { throw 'Immutable plan already exists with conflicting content.' }
        return [ordered]@{ path = $Path; sha256 = Get-FileSha256 $Path }
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try { [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false)); [IO.File]::Move($temporary, $Path, $false) } finally { if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force } }
    return [ordered]@{ path = $Path; sha256 = Get-FileSha256 $Path }
}

function Get-CheckPlan {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('checks') -or $InputObject.checks -is [string] -or $InputObject.checks -isnot [System.Collections.IEnumerable]) { throw 'checks must be an array.' }
    $checks = @(); $ids = @{}
    foreach ($check in @($InputObject.checks)) {
        if ($check -isnot [System.Collections.IDictionary]) { throw 'Each check must be an object.' }
        $id = Need $check 'id'; if ($ids.ContainsKey($id)) { throw "Duplicate check ID: $id" }; $ids[$id] = $true
        $command = Need $check 'command'; $criteria = if ($check.Contains('criterionIds')) { Get-StringArray $check 'criterionIds' -AllowEmpty } else { @() }
        $checks += [ordered]@{ id = $id; command = $command; criterionIds = $criteria; kind = if ($check.Contains('kind')) { [string]$check.kind } else { 'check' }; sharedOutput = ($check.sharedOutput -eq $true); serialGroup = if ($check.Contains('serialGroup')) { [string]$check.serialGroup } else { $null } }
    }
    if ($checks.Count -eq 0) { throw 'At least one verification check is required.' }
    return $checks
}

function Invoke-Plan {
    param([System.Collections.IDictionary] $InputObject)
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { throw 'StateRoot is required for durable verification plans.' }
    $packet = if ($InputObject.Contains('packetReference')) { Read-ReferenceJson $InputObject.packetReference 'packet' } else { $null }
    $criteria = if ($InputObject.Contains('criteria')) { @($InputObject.criteria) } elseif ($null -ne $packet) { @($packet.value.criteria) } else { throw 'criteria or packetReference is required.' }
    if ($criteria.Count -eq 0) { throw 'Verification planning requires acceptance criteria.' }
    $checks = Get-CheckPlan $InputObject
    $criterionIds = @($criteria | ForEach-Object { [string]$_.id })
    foreach ($check in $checks) { foreach ($criterionId in @($check.criterionIds)) { if ($criterionIds -notcontains $criterionId) { throw "Check $($check.id) references an unknown criterion: $criterionId" } } }
    $requirements = if ($InputObject.Contains('requirements')) { $InputObject.requirements } else { @{} }
    $ui = if ($InputObject.Contains('uiInteractions')) { @($InputObject.uiInteractions) } else { @() }
    if ($requirements.visibleBrowser -eq $true -and $ui.Count -eq 0) { throw 'A visible-browser requirement needs planned UI interactions.' }
    $role = Need $InputObject 'role'; if ($role -notin @('implementer','reviewer')) { throw 'role must be implementer or reviewer.' }
    $runId = Need $InputObject 'runId'; $actionId = Need $InputObject 'actionId'
    $plan = [ordered]@{ schemaVersion = 1; kind = 'verification_plan'; runId = $runId; actionId = $actionId; ownerRole = $role; packetReference = if ($null -ne $packet) { $packet.reference } else { $null }; criteria = $criteria; checks = $checks; requirements = $requirements; uiInteractions = $ui; smokeReference = if ($InputObject.Contains('smokeReference')) { $InputObject.smokeReference } else { $null }; createdAtUtc = [DateTime]::UtcNow.ToString('o') }
    $path = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ('verification-plans\' + $runId + '-' + $actionId + '.json')
    $artifact = Write-ImmutableJson $path $plan
    return [ordered]@{ planReference = $artifact; ownerRole = $role; runId = $runId; actionId = $actionId; checkIds = @($checks | ForEach-Object id); uiInteractionCount = $ui.Count; sharedOutputGroups = @($checks | Where-Object sharedOutput | ForEach-Object serialGroup | Sort-Object -Unique) }
}

function Invoke-ValidatePlan {
    param([System.Collections.IDictionary] $InputObject)
    $planRead = Read-ReferenceJson $InputObject.planReference 'verification plan'; $plan = $planRead.value
    if ([int]$plan.schemaVersion -ne 1 -or [string]$plan.kind -cne 'verification_plan') { throw 'Unsupported verification plan schema.' }
    if ($plan.ownerRole -cne 'implementer') { throw 'The verification plan must be authored by the implementer.' }
    $requirements = if ($InputObject.Contains('requirements')) { $InputObject.requirements } else { $plan.requirements }
    $errors = @()
    if ($requirements.fullSuite -eq $true -and @($plan.checks | Where-Object { $_.kind -eq 'full_suite' }).Count -eq 0) { $errors += 'requirements.fullSuite: no full_suite check is planned' }
    if ($requirements.tdd -eq $true -and @($plan.checks | Where-Object { $_.kind -eq 'tdd' }).Count -eq 0) { $errors += 'requirements.tdd: no tdd check is planned' }
    if ($requirements.visibleBrowser -eq $true -and @($plan.uiInteractions).Count -eq 0) { $errors += 'requirements.visibleBrowser: no UI interaction is planned' }
    if ($errors.Count -gt 0) { throw ($errors -join '; ') }
    return [ordered]@{ valid = $true; planReference = $planRead.reference; ownerRole = $plan.ownerRole; checks = @($plan.checks | ForEach-Object { [ordered]@{ id = $_.id; command = $_.command; criterionIds = @($_.criterionIds); serial = $_.sharedOutput } }); requiredUiInteractions = @($plan.uiInteractions); reviewerMustAssess = $true }
}

function Invoke-ValidateSmoke {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('smoke')) { throw 'smoke is required.' }
    $smoke = $InputObject.smoke; $command = Need $smoke 'command'; $workingDirectory = [IO.Path]::GetFullPath((Need $smoke 'workingDirectory'))
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) { throw 'smoke.workingDirectory is inaccessible.' }
    $setup = if ($smoke.Contains('setupCommand')) { Need $smoke 'setupCommand' } else { $null }; $cleanup = if ($smoke.Contains('cleanupCommand')) { Need $smoke 'cleanupCommand' } else { $null }
    if ($setup -and -not $cleanup) { throw 'A smoke setupCommand requires cleanupCommand.' }
    $capabilities = if ($smoke.Contains('requiredCapabilities')) { Get-StringArray $smoke 'requiredCapabilities' -AllowEmpty } else { @() }
    if ($smoke.Contains('disposable') -and $smoke.disposable -ne $true) { throw 'Smoke resources must be explicitly disposable.' }
    if ($InputObject.Contains('availableCapabilities')) { $available = Get-StringArray $InputObject 'availableCapabilities' -AllowEmpty; $missing = @($capabilities | Where-Object { $available -notcontains $_ }); if ($missing.Count -gt 0) { throw "Unavailable smoke capabilities: $($missing -join ', ')" } }
    if ($InputObject.Contains('observedSetupExitCode') -and [int]$InputObject.observedSetupExitCode -ne 0) { throw 'Observed smoke setup failed; cleanup remains the implementer responsibility.' }
    return [ordered]@{ valid = $true; command = $command; setupCommand = $setup; cleanupCommand = $cleanup; workingDirectory = $workingDirectory; requiredCapabilities = $capabilities; executes = $false; owner = 'implementer' }
}

function Read-EvidenceReference {
    param([System.Collections.IDictionary] $Reference)
    $read = Read-ReferenceJson $Reference 'evidence'; $wrapper = $read.value
    if (-not $wrapper.Contains('recordJson') -or -not $wrapper.Contains('recordSha256')) { throw 'Evidence reference is not an immutable evidence record.' }
    $sha = [Security.Cryptography.SHA256]::Create(); try { $recordHash = ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$wrapper.recordJson)))).ToLowerInvariant() } finally { $sha.Dispose() }
    if ([string]$wrapper.recordSha256 -cne $recordHash) { throw 'Evidence record body hash is invalid.' }
    try { $record = ConvertFrom-Json -InputObject ([string]$wrapper.recordJson) -AsHashtable -Depth 100 -DateKind String } catch { throw 'Evidence record body is not valid JSON.' }
    $timestampMatch = [regex]::Match([string]$wrapper.recordJson, '"capturedAtUtc"\s*:\s*"([^"]+)"')
    return [ordered]@{ reference = $read.reference; record = $record; capturedAtUtcRaw = if ($timestampMatch.Success) { $timestampMatch.Groups[1].Value } else { $null } }
}

function Invoke-ReuseEvidence {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('evidenceReferences') -or $InputObject.evidenceReferences -is [string]) { throw 'evidenceReferences must be an array.' }
    if (-not $InputObject.Contains('current')) { throw 'current input coverage is required.' }
    $current = $InputObject.current; $results = @(); $reusable = $true
    foreach ($reference in @($InputObject.evidenceReferences)) {
        $item = Read-EvidenceReference $reference; $record = $item.record; $coverage = if ($record.Contains('coverage')) { $record.coverage } else { $null }; $reason = 'exact_revision'; $canReuse = $false
        if ($null -ne $coverage -and [string]$coverage.revision -ceq [string]$current.revision -and [string]$coverage.baseSha -ceq [string]$current.baseSha -and [string]$coverage.environmentHash -ceq [string]$current.environmentHash -and [string]$coverage.dependenciesHash -ceq [string]$current.dependenciesHash) { $canReuse = $true }
        elseif ($null -ne $coverage -and $current.changedKind -eq 'documentation_only' -and [string]$coverage.baseSha -ceq [string]$current.baseSha -and [string]$coverage.environmentHash -ceq [string]$current.environmentHash -and [string]$coverage.dependenciesHash -ceq [string]$current.dependenciesHash) { $overlap = @($current.changedPaths | Where-Object { @($coverage.files) -contains [string]$_ }); if ($overlap.Count -eq 0) { $canReuse = $true; $reason = 'documentation_only_inputs_unchanged' } }
        if (-not $canReuse) { $reusable = $false; $reason = if ($null -eq $coverage) { 'missing_provenance' } else { 'changed_inputs' } }
        $results += [ordered]@{ evidenceId = [string]$record.evidenceId; reusable = $canReuse; reason = $reason; originalActionId = [string]$record.actionId; checkedRevision = [string]$record.checkedRevision; capturedAtUtc = if ($null -ne $item.capturedAtUtcRaw) { $item.capturedAtUtcRaw } else { [string]$record.capturedAtUtc }; provenance = $coverage }
    }
    return [ordered]@{ reusable = $reusable; evidence = $results; reviewerApprovalRequired = $true; freshlyExecuted = $false }
}

try {
    $inputObject = Read-Object
    $data = switch ($Operation) { 'plan' { Invoke-Plan $inputObject }; 'validate-plan' { Invoke-ValidatePlan $inputObject }; 'validate-smoke' { Invoke-ValidateSmoke $inputObject }; 'reuse-evidence' { Invoke-ReuseEvidence $inputObject } }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_verification'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1
}
