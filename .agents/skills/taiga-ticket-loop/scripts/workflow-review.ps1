[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('validate','decide')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'

function Read-Object { if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }; try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" } }
function Need { param([hashtable]$Object,[string]$Name); if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }; return [string]$Object[$Name] }
function Validate-Receipt {
    param([hashtable] $Receipt)
    foreach ($name in @('runId','actionId','ticketKey','scopeHash','baseSha','reviewedSha','verdict')) { Need $Receipt $name | Out-Null }
    if ($Receipt.verdict -notin @('pass','changes_requested','blocked')) { throw 'Unsupported review verdict.' }
    if (-not $Receipt.Contains('criteria') -or -not $Receipt.Contains('checks')) { throw 'Criteria and checks are required.' }
    $findings = @($Receipt.findings)
    $ids = @{}
    foreach ($finding in $findings) {
        foreach ($name in @('id','severity','evidence','requestedChange')) { Need $finding $name | Out-Null }
        if ($ids.Contains([string]$finding.id)) { throw "Duplicate finding ID: $($finding.id)" }
        $ids[[string]$finding.id] = $true
    }
    $blocking = @($findings | Where-Object { $_.severity -in @('blocker','critical','high') -and $_.disposition -notin @('fixed','rejected_accepted') })
    if ($Receipt.verdict -eq 'pass' -and $blocking.Count -gt 0) { throw 'Pass contains unresolved blocking findings.' }
    return [ordered]@{ valid = $true; verdict = $Receipt.verdict; findingCount = $findings.Count; blockingFindingCount = $blocking.Count }
}

try {
    $input = Read-Object
    $receipt = Need $input 'receipt'; $receipt = $input.receipt
    $validated = Validate-Receipt $receipt
    if ($Operation -eq 'validate') { $data = $validated }
    else {
        $currentSha = Need $input 'currentSha'; $currentScopeHash = Need $input 'currentScopeHash'; $currentBaseSha = Need $input 'currentBaseSha'; $round = [int]$input.correctionRound; $maxRounds = if ($input.Contains('maxCorrectionRounds')) { [int]$input.maxCorrectionRounds } else { 3 }; $remainingMinutes = if ($input.Contains('remainingMinutes')) { [int]$input.remainingMinutes } else { 1 }
        if ($receipt.reviewedSha -ne $currentSha -or $receipt.scopeHash -ne $currentScopeHash -or $receipt.baseSha -ne $currentBaseSha) { $data = [ordered]@{ decision = 'needs_input'; reason = 'stale_review_input'; reviewedSha = $receipt.reviewedSha; currentSha = $currentSha } }
        elseif ($receipt.verdict -eq 'pass' -and $validated.blockingFindingCount -eq 0) { $data = [ordered]@{ decision = 'publish'; reviewedSha = $currentSha } }
        elseif ($receipt.verdict -eq 'changes_requested' -and $round -lt $maxRounds -and $remainingMinutes -gt 0) { $data = [ordered]@{ decision = 'correct'; nextRound = $round + 1; findings = @($receipt.findings) } }
        elseif ($receipt.verdict -eq 'blocked') { $data = [ordered]@{ decision = 'needs_input'; reason = 'review_blocked' } }
        else { $data = [ordered]@{ decision = 'needs_input'; reason = if ($round -ge $maxRounds) { 'correction_round_limit' } else { 'elapsed_budget_or_unresolved_findings' } } }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch { [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_review'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1 }
