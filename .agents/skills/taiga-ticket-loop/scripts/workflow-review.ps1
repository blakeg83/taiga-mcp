[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('validate','decide','route')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
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
    $references = @()
    foreach ($reference in @($InputObject.evidenceReferences)) {
        if ($reference -isnot [System.Collections.IDictionary]) { throw 'Each evidence reference must be an object.' }
        $path = [IO.Path]::GetFullPath((Need $reference 'path'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Evidence reference is missing: $path" }
        $hash = Get-FileSha256 $path
        if ($reference.Contains('sha256') -and ([string]$reference.sha256).ToLowerInvariant() -cne $hash) { throw "Evidence reference hash does not match: $path" }
        $references += [ordered]@{ path = $path; sha256 = $hash; evidenceId = if ($reference.Contains('evidenceId')) { [string]$reference.evidenceId } else { $null } }
    }
    return $references
}

function Need {
    param([hashtable] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }
    return [string]$Object[$Name]
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

    if ($remainingMinutes -le 0) {
        return [ordered]@{ decision = 'needs_input'; reason = 'elapsed_budget'; resultId = $resultId; repairAttempts = $attempts; maxRepairAttempts = $maximum; errors = $routingErrors }
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
    $evidenceReferences = Validate-EvidenceReferences $inputObject
    $expectedCriteria = if ($inputObject.Contains('expectedCriteria')) { @($inputObject.expectedCriteria) } else { @() }
    $validation = Get-ReviewReceiptValidation $inputObject.receipt $expectedCriteria
    if ($Operation -eq 'route') {
        $data = Get-RepairRoute $inputObject $validation
    } elseif (-not $validation.valid) {
        throw "Review receipt invalid: $($validation.errors -join '; ')"
    } elseif ($Operation -eq 'validate') {
        $data = $validation
    } else {
        $receipt = $validation.normalizedReceipt
        $currentSha = Need $inputObject 'currentSha'; $currentScopeHash = Need $inputObject 'currentScopeHash'; $currentBaseSha = Need $inputObject 'currentBaseSha'; $expectedRunId = Need $inputObject 'expectedRunId'; $expectedActionId = Need $inputObject 'expectedActionId'; $expectedTicketKey = Need $inputObject 'expectedTicketKey'; $round = [int]$inputObject.correctionRound; $maxRounds = if ($inputObject.Contains('maxCorrectionRounds')) { [int]$inputObject.maxCorrectionRounds } else { 3 }; $remainingMinutes = if ($inputObject.Contains('remainingMinutes')) { [int]$inputObject.remainingMinutes } else { 1 }
        $deltaError = $null
        if ($inputObject.Contains('previousReviewedSha')) {
            $previousReviewedSha = Need $inputObject 'previousReviewedSha'
            if (-not $receipt.Contains('reviewDelta')) { $deltaError = 'missing_review_delta_assessment' }
            elseif ($receipt.reviewDelta.fromSha -cne $previousReviewedSha -or $receipt.reviewDelta.toSha -cne $currentSha -or $receipt.reviewDelta.toSha -cne $receipt.reviewedSha) { $deltaError = 'stale_or_mismatched_review_delta' }
        } elseif ($receipt.Contains('reviewDelta')) {
            $deltaError = 'unbound_review_delta'
        }

        if ($receipt.runId -ne $expectedRunId -or $receipt.actionId -ne $expectedActionId -or $receipt.ticketKey -ne $expectedTicketKey -or $receipt.reviewedSha -ne $currentSha -or $receipt.scopeHash -ne $currentScopeHash -or $receipt.baseSha -ne $currentBaseSha) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'stale_or_mismatched_review_input'; reviewedSha = $receipt.reviewedSha; currentSha = $currentSha }
        } elseif ($null -ne $deltaError) {
            $data = [ordered]@{ decision = 'needs_input'; reason = $deltaError; reviewedSha = $currentSha; previousReviewedSha = if ($inputObject.Contains('previousReviewedSha')) { $inputObject.previousReviewedSha } else { $null } }
        } elseif ($remainingMinutes -le 0) {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'elapsed_budget'; reviewedSha = $currentSha }
        } elseif ($receipt.verdict -eq 'pass' -and $validation.blockingFindingCount -eq 0) {
            $data = [ordered]@{ decision = 'publish'; reviewedSha = $currentSha }
        } elseif ($receipt.verdict -eq 'changes_requested' -and $round -lt $maxRounds -and $remainingMinutes -gt 0) {
            $data = [ordered]@{ decision = 'correct'; nextRound = $round + 1; findings = @($receipt.findings) }
        } elseif ($receipt.verdict -eq 'blocked') {
            $data = [ordered]@{ decision = 'needs_input'; reason = 'review_blocked' }
        } else {
            $data = [ordered]@{ decision = 'needs_input'; reason = if ($round -ge $maxRounds) { 'correction_round_limit' } else { 'elapsed_budget_or_unresolved_findings' } }
        }
    }
    if ($data -is [System.Collections.IDictionary]) {
        $data.evidenceReferences = $evidenceReferences
        if ($inputObject.Contains('receiptReference')) { $data.receiptReference = $inputObject.receiptReference }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_review'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1
}
