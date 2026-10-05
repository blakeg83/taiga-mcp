[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('validate','decide','route')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'receipt-contract.ps1')

function Read-Object {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }
    try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 }
    catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
}

function Get-FileSha256 {
    param([string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($stream))).ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Read-ReceiptReferences {
    param([hashtable] $InputObject)
    if (-not $InputObject.Contains('receiptPath')) { return $InputObject }
    $path = [IO.Path]::GetFullPath((Need $InputObject 'receiptPath'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'receiptPath does not identify an existing file.' }
    if ($InputObject.Contains('receiptSha256')) {
        $expectedHash = Need $InputObject 'receiptSha256'
        if ($expectedHash -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileSha256 $path) -cne $expectedHash.ToLowerInvariant()) { throw 'receiptPath hash does not match receiptSha256.' }
    }
    try { $receipt = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $path) -AsHashtable -Depth 100 }
    catch { throw "receiptPath is not valid JSON: $($_.Exception.Message)" }
    if ($receipt -isnot [System.Collections.IDictionary]) { throw 'receiptPath JSON must be an object.' }
    $copy = @{}
    foreach ($key in $InputObject.Keys) { if ($key -notin @('receiptPath','receiptSha256')) { $copy[$key] = $InputObject[$key] } }
    $copy.receipt = $receipt
    $copy.receiptReference = [ordered]@{ path = $path; sha256 = Get-FileSha256 $path }
    return $copy
}

function Validate-EvidenceReferences {
    param([hashtable] $InputObject)
    if (-not $InputObject.Contains('evidenceReferences')) { return @() }
    if ($InputObject.evidenceReferences -is [string] -or $InputObject.evidenceReferences -isnot [System.Collections.IEnumerable]) { throw 'evidenceReferences must be an array.' }
    $references = @(); $strictRoot = if ($InputObject.Contains('evidenceStateRoot')) { [IO.Path]::GetFullPath((Need $InputObject 'evidenceStateRoot')) } elseif (-not [string]::IsNullOrWhiteSpace($StateRoot)) { [IO.Path]::GetFullPath($StateRoot) } else { $null }
    foreach ($reference in @($InputObject.evidenceReferences)) {
        if ($reference -isnot [System.Collections.IDictionary]) { throw 'Each evidence reference must be an object.' }
        $path = [IO.Path]::GetFullPath((Need $reference 'path'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Evidence reference is missing: $path" }
        $hash = Get-FileSha256 $path
        if ($reference.Contains('sha256') -and ([string]$reference.sha256).ToLowerInvariant() -cne $hash) { throw "Evidence reference hash does not match: $path" }
        $declaredId = if ($reference.Contains('evidenceId')) { Need $reference 'evidenceId' } else { $null }
        if ($null -eq $strictRoot) {
            $references += [ordered]@{ path = $path; sha256 = $hash; evidenceId = $declaredId; validation = 'legacy_narrative_only' }
            continue
        }
        $lines = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'workflow-evidence.ps1') -Operation validate -EvidencePath $path -StateRoot $strictRoot 2>&1; $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
        try { $verified = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Evidence validator returned invalid JSON: $raw" }
        if ($exitCode -ne 0 -or $verified.ok -ne $true) { throw [string]$verified.error.message }
        $record = $verified.data.record
        if ($null -ne $declaredId -and [string]$record.evidenceId -cne [string]$declaredId) { throw "Evidence ID does not match the immutable record: $path" }
        $references += [ordered]@{ path = $path; sha256 = $hash; evidenceId = [string]$record.evidenceId; validation = 'immutable_record'; record = $record }
    }
    return $references
}

function Invoke-WorkerCoverageValidation {
    param([object[]] $EvidenceReferences, [System.Collections.IDictionary] $CurrentCoverage, [string] $RepositoryPath = '', [string] $FromRevision = '')
    if ($null -eq $CurrentCoverage) { return @() }
    $validationPath = Join-Path ([IO.Path]::GetTempPath()) ('.ticket-loop-reuse-' + [Guid]::NewGuid().ToString('N') + '.json')
    $references = @($EvidenceReferences | ForEach-Object { [ordered]@{ path = [string]$_.path; sha256 = [string]$_.sha256; evidenceId = [string]$_.evidenceId } })
    $current = [ordered]@{}; foreach ($key in $CurrentCoverage.Keys) { $current[$key] = $CurrentCoverage[$key] }
    if (-not [string]::IsNullOrWhiteSpace($RepositoryPath) -and -not [string]::IsNullOrWhiteSpace($FromRevision)) { $current.fromRevision = $FromRevision }
    $request = [ordered]@{ evidenceReferences = $references; current = $current }
    if (-not [string]::IsNullOrWhiteSpace($RepositoryPath)) { $request.repositoryPath = $RepositoryPath }
    try {
        [IO.File]::WriteAllText($validationPath, ($request | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $lines = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'workflow-verification.ps1') -Operation reuse-evidence -InputPath $validationPath 2>&1; $exitCode = $LASTEXITCODE; $raw = $lines -join [Environment]::NewLine
        try { $response = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 } catch { throw "Reuse validator returned invalid JSON: $raw" }
        if ($exitCode -ne 0 -or $response.ok -ne $true) { throw [string]$response.error.message }
        return @($response.data.evidence)
    } finally { if (Test-Path -LiteralPath $validationPath -PathType Leaf) { Remove-Item -LiteralPath $validationPath -Force } }
}

function Need {
    param([hashtable] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }
    return [string]$Object[$Name]
}

function Get-PathSet {
    param([object] $Value, [string] $Name)
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw "$Name must be an array." }
    return @($Value | ForEach-Object { if ([string]::IsNullOrWhiteSpace([string]$_)) { throw "$Name entries must be nonblank." }; [string]$_ } | Sort-Object -Unique)
}

function Test-SamePathSet {
    param([object[]] $Left, [object[]] $Right)
    return @(Compare-Object -ReferenceObject @($Left) -DifferenceObject @($Right)).Count -eq 0
}

function Get-PublicationCheckBindingErrors {
    param([System.Collections.IDictionary] $Receipt, [object[]] $EvidenceReferences, [string] $ExpectedRunId, [string] $ExpectedActionId, [string] $ExpectedTicketKey, [string] $CurrentSha, [string] $CurrentScopeHash, [string] $CurrentBaseSha, [string] $ExpectedPacketHash = '', [object[]] $AllowedEvidenceActions = @(), [string[]] $RequiredCommands = @(), [object[]] $ReuseValidation = @())
    $errors = [System.Collections.Generic.List[string]]::new(); $byId = @{}
    foreach ($reference in @($EvidenceReferences)) { if ($reference.validation -eq 'immutable_record' -and -not $byId.ContainsKey([string]$reference.evidenceId)) { $byId[[string]$reference.evidenceId] = $reference.record } }
    $coveredCriteria = @{}
    $passingCommands = @{}
    $checks = @($Receipt.checks)
    foreach ($check in $checks) {
        if ($check -isnot [System.Collections.IDictionary] -or -not $check.Contains('evidenceId') -or -not $byId.ContainsKey([string]$check.evidenceId)) { [void]$errors.Add('check evidenceId is not bound to an immutable evidence record'); continue }
        $record = $byId[[string]$check.evidenceId]
        $binding = @($AllowedEvidenceActions | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_.actionId -ceq [string]$record.actionId } | Select-Object -First 1)[0]
        $checkErrorCount = $errors.Count
        if ($null -eq $binding -and [string]$record.actionId -cne $ExpectedActionId) { [void]$errors.Add("check '$($check.evidenceId)' action is not a trusted verification action") }
        $delta = if ($Receipt.Contains('reviewDelta')) { $Receipt.reviewDelta } else { $null }
        $reuseIds = if ($null -ne $delta -and $delta -is [System.Collections.IDictionary]) { @($delta.reusedCheckIds | ForEach-Object { [string]$_ }) } else { @() }
        $reuseKey = if ($check.Contains('checkId')) { [string]$check.checkId } else { [string]$check.evidenceId }
        $isStale = [string]$record.checkedRevision -cne [string]$CurrentSha
        $reuseResult = @($ReuseValidation | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_.evidenceId -ceq [string]$record.evidenceId } | Select-Object -First 1)[0]
        $approvedReuse = $isStale -and $null -ne $binding -and $null -ne $delta -and $delta -is [System.Collections.IDictionary] -and $reuseIds -contains $reuseKey -and -not [string]::IsNullOrWhiteSpace([string]$delta.reuseJustification) -and $null -ne $reuseResult -and $reuseResult.reusable -eq $true
        if ([string]$record.evidenceKind -cne 'check' -or $record.acceptedAsCheckPass -ne $true -or [string]$record.outcome -cne 'passed') { [void]$errors.Add("check '$($check.evidenceId)' is not a passing check record") }
        if ([string]$record.command -cne [string]$check.command) { [void]$errors.Add("check '$($check.evidenceId)' command does not match its evidence") }
        if ([long]$record.actualExitCode -ne [long]$check.exitCode -or [long]$check.exitCode -ne 0 -or ($check.Contains('passed') -and $check.passed -ne $true)) { [void]$errors.Add("check '$($check.evidenceId)' exit/pass result does not match its evidence") }
        foreach ($name in @('runId','ticketKey','scopeHash')) { $expectedValue = switch -Exact ($name) { 'runId' { $ExpectedRunId }; 'ticketKey' { $ExpectedTicketKey }; 'scopeHash' { $CurrentScopeHash } }; if ([string]$record[$name] -cne [string]$expectedValue) { [void]$errors.Add("check '$($check.evidenceId)' $name is not bound to the reviewed input") } }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedPacketHash) -and [string]$record.packetHash -cne [string]$ExpectedPacketHash) { [void]$errors.Add("check '$($check.evidenceId)' packet hash is not bound to the reviewed assignment") }
        if (-not $approvedReuse -and [string]$record.checkedRevision -ceq [string]$CurrentSha -and $null -eq $binding -and [string]$record.actionId -cne $ExpectedActionId) { [void]$errors.Add("check '$($check.evidenceId)' action binding is not trusted") }
        if ($record.coverage -isnot [System.Collections.IDictionary] -or [string]$record.coverage.baseSha -cne $CurrentBaseSha -or (([string]$record.coverage.revision -cne $CurrentSha -or [string]$record.checkedRevision -cne $CurrentSha) -and -not $approvedReuse)) { [void]$errors.Add("check '$($check.evidenceId)' coverage is not bound to the reviewed revision and base") }
        $expectedProfile = if ($null -ne $binding) { $binding.profile } else { [ordered]@{ model = [string]$Receipt.reviewerModel; effort = [string]$Receipt.reviewerEffort } }
        if ($record.profile -isnot [System.Collections.IDictionary] -or [string]$record.profile.model -cne [string]$expectedProfile.model -or [string]$record.profile.effort -cne [string]$expectedProfile.effort) { [void]$errors.Add("check '$($check.evidenceId)' evidence profile is not bound to its trusted action") }
        if ($null -ne $binding -and [string]$record.command -cne [string]$binding.command) { [void]$errors.Add("check '$($check.evidenceId)' command is not bound to its trusted action") }
        $recordCriteria = @($record.criterionIds)
        if ($recordCriteria.Count -eq 0) { [void]$errors.Add("check '$($check.evidenceId)' has no criterion coverage") }
        foreach ($criterionId in $recordCriteria) { $coveredCriteria[[string]$criterionId] = $true }
        if ($check.Contains('criterionIds')) {
            $declaredCriteria = @($check.criterionIds | ForEach-Object { [string]$_ })
            if (@(Compare-Object -ReferenceObject $declaredCriteria -DifferenceObject $recordCriteria).Count -gt 0) { [void]$errors.Add("check '$($check.evidenceId)' criterion coverage does not match its evidence") }
        }
        if ($null -ne $binding -and @(Compare-Object -ReferenceObject @($binding.criterionIds) -DifferenceObject $recordCriteria).Count -gt 0) { [void]$errors.Add("check '$($check.evidenceId)' criterion coverage is not bound to its trusted action") }
        if ($null -ne $ReuseValidation -and @($ReuseValidation).Count -gt 0 -and ($null -eq $reuseResult -or $reuseResult.reusable -ne $true)) { [void]$errors.Add("check '$($check.evidenceId)' is not reusable under the trusted current worker coverage") }
        if ($isStale -and -not $approvedReuse) { [void]$errors.Add("check '$($check.evidenceId)' reuses stale evidence without validated current-input provenance") }
        if ($errors.Count -eq $checkErrorCount -and [string]$record.command -ne '') { $passingCommands[[string]$record.command] = $true }
    }
    foreach ($criterion in @($Receipt.criteria)) { if ($criterion -is [System.Collections.IDictionary] -and -not $coveredCriteria.ContainsKey([string]$criterion.id)) { [void]$errors.Add("criterion '$($criterion.id)' has no covered passing evidence") } }
    foreach ($requiredCommand in @($RequiredCommands)) { if (-not $passingCommands.ContainsKey([string]$requiredCommand)) { [void]$errors.Add("required command '$requiredCommand' has no bound passing evidence") } }
    return @($errors)
}

function Get-RepairRoute {
    param([hashtable] $InputObject, [object] $Validation)

    $resultId = Need $InputObject 'resultId'
    if ($resultId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'resultId has an invalid format.' }
    $expectedActionId = Need $InputObject 'expectedActionId'
    if ($expectedActionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'expectedActionId has an invalid format.' }
    if ($resultId -cne $expectedActionId) { throw 'resultId must be the trusted original review action ID.' }
    $attempts = [int](Need $InputObject 'repairAttempts')
    $maximum = if ($InputObject.Contains('maxRepairAttempts')) { [int]$InputObject.maxRepairAttempts } else { 2 }
    $remainingMinutes = [int](Need $InputObject 'remainingMinutes')
    if ($attempts -lt 0) { throw 'repairAttempts must not be negative.' }
    if ($maximum -lt 1 -or $maximum -gt 2) { throw 'maxRepairAttempts must be between 1 and 2.' }

    $normalizations = @($Validation.normalizations)
    $normalizedReceipt = $Validation.normalizedReceipt
    $actionBound = $normalizedReceipt -is [System.Collections.IDictionary] -and $normalizedReceipt.Contains('actionId') -and [string]$normalizedReceipt.actionId -ceq $expectedActionId
    $routingErrors = @($Validation.errors)
    if (-not $actionBound) { $routingErrors += 'receipt.actionId: does not match the trusted original review action' }
    $hasLosslessNormalization = $Validation.valid -and $normalizations.Count -gt 0 -and $actionBound
    if ($Validation.valid -and -not $hasLosslessNormalization -and $actionBound) {
        return [ordered]@{ decision = 'validated'; resultId = $resultId; receipt = $Validation.normalizedReceipt }
    }

    $repairKind = 'format'
    $route = 'original_author'
    $targetActionId = $expectedActionId
    if ($hasLosslessNormalization) {
        $route = 'local_deterministic'
        $targetActionId = $null
    } else {
        $semanticPatterns = @(
            'conflicts with unresolved evidence',
            'does not match the trusted packet text',
            'in packet order',
            'duplicate criterion',
            'duplicate finding',
            'pass requires',
            'expected [0-9]+ packet criteria'
        )
        if (@($Validation.errors | Where-Object { $error = [string]$_; @($semanticPatterns | Where-Object { $error -match $_ }).Count -gt 0 }).Count -gt 0) { $repairKind = 'evidence' }
    }

    if ($attempts -ge $maximum) {
        return [ordered]@{ decision = 'needs_input'; reason = 'receipt_repair_limit'; resultId = $resultId; repairAttempts = $attempts; maxRepairAttempts = $maximum; errors = $routingErrors }
    }
    $nextAttempt = $attempts + 1
    return [ordered]@{
        decision = 'repair'
        resultId = $resultId
        route = $route
        repairKind = $repairKind
        attempt = $nextAttempt
        maxAttempts = $maximum
        targetActionId = $targetActionId
        requiresIndependentReview = ($repairKind -eq 'evidence' -or $route -eq 'original_author')
        receipt = if ($hasLosslessNormalization) { $Validation.normalizedReceipt } else { $null }
        normalizations = $normalizations
        errors = $routingErrors
    }
}

try {
    $inputObject = Read-ReceiptReferences (Read-Object)
    $null = Need $inputObject 'receipt'
    $evidenceReferences = @(Validate-EvidenceReferences $inputObject)
    $expectedCriteria = if ($inputObject.Contains('expectedCriteria')) { @($inputObject.expectedCriteria) } else { @() }
    $validation = Get-ReviewReceiptValidation $inputObject.receipt $expectedCriteria
    $strictEvidence = $evidenceReferences.Count -gt 0 -and @($evidenceReferences | Where-Object { $_.validation -eq 'immutable_record' }).Count -eq $evidenceReferences.Count
    $evidenceIds = @($evidenceReferences | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace([string]$_.evidenceId)) { [string]$_.evidenceId } })
    if ($Operation -eq 'route') {
        $data = Get-RepairRoute $inputObject $validation
    } elseif (-not $validation.valid) {
        throw "Review receipt invalid: $($validation.errors -join '; ')"
    } elseif ($Operation -eq 'validate') {
        $data = $validation
    } else {
        $receipt = $validation.normalizedReceipt
        $currentSha = Need $inputObject 'currentSha'; $currentScopeHash = Need $inputObject 'currentScopeHash'; $currentBaseSha = Need $inputObject 'currentBaseSha'; $expectedRunId = Need $inputObject 'expectedRunId'; $expectedActionId = Need $inputObject 'expectedActionId'; $expectedTicketKey = Need $inputObject 'expectedTicketKey'; $round = [int]$inputObject.correctionRound; $allowedEvidenceActions = if ($inputObject.Contains('allowedEvidenceActions')) { @($inputObject.allowedEvidenceActions) } else { @() }; $requiredCommands = if ($inputObject.Contains('requiredCommands')) { @($inputObject.requiredCommands | ForEach-Object { [string]$_ }) } else { @() }; $unresolvedRequirements = if ($inputObject.Contains('unresolvedRequirements')) { @($inputObject.unresolvedRequirements | ForEach-Object { [string]$_ }) } else { @() }; $expectedPacketHash = if ($inputObject.Contains('packetHash')) { [string]$inputObject.packetHash } else { '' }; $bindingErrors = @()
        $reuseValidation = @()
        $deltaError = $null
        $coverageError = $null
        if ($inputObject.Contains('previousReviewedSha')) {
            $previousReviewedSha = Need $inputObject 'previousReviewedSha'
            if (-not $receipt.Contains('reviewDelta')) { $deltaError = 'missing_review_delta_assessment' }
            elseif ($receipt.reviewDelta.fromSha -cne $previousReviewedSha -or $receipt.reviewDelta.toSha -cne $currentSha -or $receipt.reviewDelta.toSha -cne $receipt.reviewedSha) { $deltaError = 'stale_or_mismatched_review_delta' }
        } elseif ($receipt.Contains('reviewDelta')) {
            $deltaError = 'unbound_review_delta'
        }
        if ($inputObject.Contains('currentCoverage')) {
            $currentCoverage = $inputObject.currentCoverage
            if ($currentCoverage -isnot [System.Collections.IDictionary]) { $coverageError = 'currentCoverage must be an object.' }
            else {
                foreach ($name in @('revision','baseSha','environmentHash','dependenciesHash','changedKind')) { if (-not $currentCoverage.Contains($name)) { $coverageError = "currentCoverage.$name is required."; break } }
                if ($null -eq $coverageError -and ([string]$currentCoverage.revision -cne $currentSha -or [string]$currentCoverage.baseSha -cne $currentBaseSha)) { $coverageError = 'currentCoverage is not bound to the reviewed revision and base.' }
                if ($null -eq $coverageError) {
                    try { $coveragePaths = Get-PathSet $currentCoverage.changedPaths 'currentCoverage.changedPaths' } catch { $coverageError = $_.Exception.Message }
                }
                if ($null -eq $coverageError -and $receipt.Contains('reviewDelta') -and $inputObject.Contains('previousReviewedSha')) {
                    try {
                        $deltaPaths = Get-PathSet $receipt.reviewDelta.changedPaths 'reviewDelta.changedPaths'
                        $documentationPaths = Get-PathSet $receipt.reviewDelta.documentationPaths 'reviewDelta.documentationPaths'
                        if (-not (Test-SamePathSet $coveragePaths $deltaPaths)) { $coverageError = 'currentCoverage.changedPaths do not match reviewDelta.changedPaths.' }
                        else {
                            $expectedKind = if ($deltaPaths.Count -eq 0) { 'unchanged' } elseif ($receipt.reviewDelta.documentationChanged -eq $true -and (Test-SamePathSet $deltaPaths $documentationPaths)) { 'documentation_only' } else { 'code' }
                            if ([string]$currentCoverage.changedKind -cne $expectedKind) { $coverageError = 'currentCoverage.changedKind contradicts the reviewed change set.' }
                        }
                    } catch { $coverageError = $_.Exception.Message }
                }
            }
        }
        if ($null -eq $coverageError -and $inputObject.Contains('currentCoverage')) {
            $repositoryPath = if ($inputObject.Contains('repositoryPath')) { [string]$inputObject.repositoryPath } else { '' }
            $fromRevision = if ($receipt.Contains('reviewDelta')) { [string]$receipt.reviewDelta.fromSha } else { '' }
            $reuseValidation = @(Invoke-WorkerCoverageValidation $evidenceReferences $inputObject.currentCoverage $repositoryPath $fromRevision)
        }

        if ($receipt.runId -ne $expectedRunId -or $receipt.actionId -ne $expectedActionId -or $receipt.ticketKey -ne $expectedTicketKey -or $receipt.reviewedSha -ne $currentSha -or $receipt.scopeHash -ne $currentScopeHash -or $receipt.baseSha -ne $currentBaseSha) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'stale_or_mismatched_review_input'; reviewedSha = $receipt.reviewedSha; currentSha = $currentSha }
        } elseif ($null -ne $deltaError) {
            $data = [ordered]@{ decision = 'needs_input'; reason = $deltaError; reviewedSha = $currentSha; previousReviewedSha = if ($inputObject.Contains('previousReviewedSha')) { $inputObject.previousReviewedSha } else { $null } }
        } elseif ($null -ne $coverageError) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'inconsistent_current_coverage'; detail = $coverageError; reviewedSha = $currentSha }
        } elseif ($receipt.verdict -eq 'pass' -and $validation.blockingFindingCount -eq 0 -and -not $strictEvidence) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'durable_evidence_required_for_publication'; reviewedSha = $currentSha }
        } elseif ($receipt.verdict -eq 'pass' -and $validation.blockingFindingCount -eq 0 -and $unresolvedRequirements.Count -gt 0) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'unresolved_requirements'; reviewedSha = $currentSha; unresolvedRequirements = $unresolvedRequirements }
        } elseif ($receipt.verdict -eq 'pass' -and $validation.blockingFindingCount -eq 0 -and $strictEvidence -and (($bindingErrors = @(Get-PublicationCheckBindingErrors $receipt $evidenceReferences $expectedRunId $expectedActionId $expectedTicketKey $currentSha $currentScopeHash $currentBaseSha $expectedPacketHash $allowedEvidenceActions $requiredCommands $reuseValidation)).Count -gt 0)) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'review_checks_are_not_bound_to_passing_review_evidence'; reviewedSha = $currentSha; bindingErrors = $bindingErrors }
        } elseif ($receipt.verdict -eq 'pass' -and $validation.blockingFindingCount -eq 0) {
            $data = [ordered]@{ decision = 'publish'; reviewedSha = $currentSha }
        } elseif ($receipt.verdict -eq 'changes_requested') {
            $data = [ordered]@{ decision = 'correct'; nextRound = $round + 1; findings = @($receipt.findings); reviewedSha = $currentSha }
        } elseif ($receipt.verdict -eq 'blocked') {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'review_blocked'; reviewedSha = $currentSha }
        } else {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'unresolved_findings' }
        }
    }
    if ($Operation -eq 'decide' -and $data -is [System.Collections.IDictionary]) { $data.verdict = [string]$receipt.verdict; $data.currentSha = $currentSha }
    if ($data -is [System.Collections.IDictionary]) {
        $data.evidenceReferences = $evidenceReferences
        if ($inputObject.Contains('receiptReference')) { $data.receiptReference = $inputObject.receiptReference }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_review'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1
}
