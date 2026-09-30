[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('validate','decide')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'receipt-contract.ps1')

function Read-Object { if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }; try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" } }
function Need { param([hashtable]$Object,[string]$Name); if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }; return [string]$Object[$Name] }

try {
    $input = Read-Object
    $null = Need $input 'receipt'
    $receipt = $input.receipt
    $expectedCriteria = if ($input.Contains('expectedCriteria')) { @($input.expectedCriteria) } else { @() }
    $validated = Get-ReviewReceiptValidation $receipt $expectedCriteria
    if (-not $validated.valid) { throw "Review receipt invalid: $($validated.errors -join '; ')" }
    $receipt = $validated.normalizedReceipt
    if ($Operation -eq 'validate') { $data = $validated }
    else {
        $currentSha = Need $input 'currentSha'; $currentScopeHash = Need $input 'currentScopeHash'; $currentBaseSha = Need $input 'currentBaseSha'; $expectedRunId = Need $input 'expectedRunId'; $expectedActionId = Need $input 'expectedActionId'; $expectedTicketKey = Need $input 'expectedTicketKey'; $round = [int]$input.correctionRound; $maxRounds = if ($input.Contains('maxCorrectionRounds')) { [int]$input.maxCorrectionRounds } else { 3 }; $remainingMinutes = if ($input.Contains('remainingMinutes')) { [int]$input.remainingMinutes } else { 1 }
        if ($receipt.runId -ne $expectedRunId -or $receipt.actionId -ne $expectedActionId -or $receipt.ticketKey -ne $expectedTicketKey -or $receipt.reviewedSha -ne $currentSha -or $receipt.scopeHash -ne $currentScopeHash -or $receipt.baseSha -ne $currentBaseSha) { $data = [ordered]@{ decision = 'needs_input'; reason = 'stale_or_mismatched_review_input'; reviewedSha = $receipt.reviewedSha; currentSha = $currentSha } }
        elseif ($receipt.verdict -eq 'pass' -and $validated.blockingFindingCount -eq 0) { $data = [ordered]@{ decision = 'publish'; reviewedSha = $currentSha } }
        elseif ($receipt.verdict -eq 'changes_requested' -and $round -lt $maxRounds -and $remainingMinutes -gt 0) { $data = [ordered]@{ decision = 'correct'; nextRound = $round + 1; findings = @($receipt.findings) } }
        elseif ($receipt.verdict -eq 'blocked') { $data = [ordered]@{ decision = 'needs_input'; reason = 'review_blocked' } }
        else { $data = [ordered]@{ decision = 'needs_input'; reason = if ($round -ge $maxRounds) { 'correction_round_limit' } else { 'elapsed_budget_or_unresolved_findings' } } }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch { [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_review'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1 }
