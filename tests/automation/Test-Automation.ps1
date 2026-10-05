[CmdletBinding()]
param([string] $Only)

$ErrorActionPreference = 'Stop'
$script:Root = Join-Path ([IO.Path]::GetTempPath()) ("TaigaMCP automation {0}" -f ([Guid]::NewGuid().ToString('N')))
$script:StateScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-state.ps1'
$script:GitScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-git.ps1'
$script:PlanScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-plan.ps1'
$script:PacketScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-packet.ps1'
$script:PreflightScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-preflight.ps1'
$script:RoleTracePath = Join-Path $PSScriptRoot 'fixtures\ticket-loop-role-traces.json'
$script:CoordinationTracePath = Join-Path $PSScriptRoot 'fixtures\ticket-loop-coordination-traces.json'
$script:VerificationTracePath = Join-Path $PSScriptRoot 'fixtures\ticket-loop-verification-traces.json'
$script:ReviewScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-review.ps1'
$script:EvidenceScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-evidence.ps1'
$script:CoordinateScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-coordinate.ps1'
$script:VerificationScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-verification.ps1'
$script:MeasureScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-measure.ps1'
$script:AcceptanceScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-acceptance.ps1'
$script:AcceptanceScenarioPath = Join-Path $PSScriptRoot 'fixtures\ticket-loop-acceptance-scenario.json'
$script:TaigaScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-taiga.ps1'
$script:ProgressScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-progress.ps1'
$script:FixtureRoot = Join-Path $script:Root 'fixtures'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([object] $Expected, [object] $Actual, [string] $Message)
    if ([string]$Expected -ne [string]$Actual) { throw "$Message (expected '$Expected', actual '$Actual')" }
}

function Write-JsonFile {
    param([object] $Value, [string] $Path)
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Copy-JsonObject {
    param([object] $Value)
    return ConvertFrom-Json -InputObject ($Value | ConvertTo-Json -Depth 100) -AsHashtable -Depth 100
}

function Invoke-PsJson {
    param([string] $ScriptPath, [string[]] $Arguments, [bool] $ExpectSuccess = $true)
    $lines = & pwsh -NoProfile -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($lines -join [Environment]::NewLine)
    try { $value = ConvertFrom-Json -InputObject $text -AsHashtable -Depth 100 } catch { throw "Helper returned non-JSON output: $text" }
    if ($ExpectSuccess -and $exitCode -ne 0) { throw "Expected helper success but received ${exitCode}: $text" }
    if (-not $ExpectSuccess -and $exitCode -eq 0) { throw "Expected helper failure: $text" }
    return $value
}

function New-InputPath {
    param([object] $Value, [string] $Name)
    $path = Join-Path $script:Root "$Name.json"
    Write-JsonFile $Value $path
    return $path
}

$script:ReviewCriteria = @(@{ id = 'criterion-1'; text = 'Preserve the selected ticket behavior.' })

function New-ReviewReceipt {
    param([string] $Verdict = 'pass')
    return @{
        schemaVersion = 1; kind = 'review'; runId = 'run'; actionId = 'review-0'; ticketKey = 'project:1:issue:1'
        scopeHash = 'scope'; baseSha = 'base'; reviewedSha = 'head'; verdict = $Verdict
        reviewerModel = 'gpt-6.1-sol'; reviewerEffort = 'high'
        criteria = @(@{ id = 'criterion-1'; text = 'Preserve the selected ticket behavior.'; passed = $true; evidence = 'criterion evidence' })
        checks = @(@{ command = 'test'; exitCode = 0; passed = $true; evidence = 'check evidence' })
        findings = @()
    }
}

function Test-Case {
    param([string] $Name, [scriptblock] $Body)
    if (-not [string]::IsNullOrWhiteSpace($Only) -and $Name -notlike "*$Only*") { return }
    try { & $Body; $script:Passed++; Write-Output "PASS $Name" } catch { $script:Failed++; Write-Output "FAIL $Name :: $($_.Exception.Message)" }
}

try {
    New-Item -ItemType Directory -Path $script:FixtureRoot -Force | Out-Null
    $stateRoot = Join-Path $script:FixtureRoot 'state with spaces'
    $syntheticPath = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\assets\synthetic-run.json'
    $fixtureBranch = ((& git rev-parse --abbrev-ref HEAD).Trim())
    $fixtureHead = ((& git rev-parse HEAD).Trim())

    Test-Case 'share versioned receipt schema and legacy compatibility' {
        $receipt = New-ReviewReceipt
        $request = @{ receipt = $receipt; expectedCriteria = $script:ReviewCriteria }
        $stateResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $request 'receipt-v1-state'))
        Assert-True $stateResult.ok 'state helper should accept canonical v1 receipt'
        Assert-Equal 1 $stateResult.data.schemaVersion 'state helper should report the shared schema version'
        $reviewResult = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $request 'receipt-v1-review'))
        Assert-True $reviewResult.data.valid 'review helper should accept the same canonical receipt'
        Assert-Equal 'head' $reviewResult.data.normalizedReceipt.reviewedSha 'review helper should use the shared normalized result'

        $legacy = New-ReviewReceipt
        $legacy.Remove('schemaVersion'); $legacy.Remove('kind')
        $legacy.criteria[0].Remove('text')
        $legacy.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'verified repair'; requestedChange = 'fix'; disposition = 'resolved' })
        $legacyExpected = @{ receipt = $legacy; expectedCriteria = $script:ReviewCriteria }
        $legacyResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $legacyExpected 'receipt-legacy-resolved'))
        Assert-True $legacyResult.ok 'legacy resolved should map to fixed when no conflicting evidence exists'
        Assert-Equal 'fixed' $legacyResult.data.normalizedReceipt.findings[0].disposition 'legacy alias should be normalized to fixed'
        Assert-Equal 'resolved' $legacyResult.data.sourceReceipt.findings[0].disposition 'source receipt should remain preserved'
        Assert-True (@($legacyResult.data.normalizations | Where-Object { $_.from -eq 'resolved' -and $_.to -eq 'fixed' }).Count -eq 1) 'alias normalization should be recorded'

        $contradiction = Copy-JsonObject $legacyExpected
        $contradiction.receipt.findings[0].status = 'open'
        $contradictionResult = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $contradiction 'receipt-resolved-open')) $false
        Assert-True (-not $contradictionResult.ok) 'resolved alias with open status must be rejected'
        Assert-True ($contradictionResult.error.message.Contains('findings[0].disposition')) 'contradiction should identify its field'

        $unknownAlias = Copy-JsonObject $request
        $unknownAlias.receipt.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix'; disposition = 'completed' })
        $unknownResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $unknownAlias 'receipt-unknown-disposition')) $false
        Assert-True (-not $unknownResult.ok) 'unknown disposition alias must be rejected'
        Assert-True ($unknownResult.error.message.Contains('receipt.findings[0].disposition')) 'unknown alias error should identify the field'

        $missing = Copy-JsonObject $request
        $missing.receipt.criteria = @()
        $missingResult = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $missing 'receipt-missing-criterion')) $false
        Assert-True (-not $missingResult.ok) 'missing expected criterion must not pass'
        Assert-True ($missingResult.error.message.Contains('criteria')) 'missing criterion error should identify criteria'

        $wrongModel = Copy-JsonObject $request
        $wrongModel.receipt.reviewerModel = 'gpt-6-sol'
        $wrongModelResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $wrongModel 'receipt-wrong-model')) $false
        Assert-True (-not $wrongModelResult.ok) 'wrong exact reviewer model must be rejected'

        $changedMeaning = Copy-JsonObject $request
        $changedMeaning.receipt.criteria[0].text = 'A different criterion with the same identifier.'
        $meaningResult = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $changedMeaning 'receipt-changed-criterion')) $false
        Assert-True (-not $meaningResult.ok) 'criterion meaning changes must be rejected'
        Assert-True ($meaningResult.error.message.Contains('criteria[0].text')) 'criterion mismatch should identify its field'

        $orderedExpected = @(
            @{ id = 'criterion-1'; text = 'Preserve the selected ticket behavior.' }
            @{ id = 'criterion-2'; text = 'Keep the result bound to the reviewed revision.' }
        )
        $orderedReceipt = New-ReviewReceipt
        $orderedReceipt.criteria += @{ id = 'criterion-2'; text = 'Keep the result bound to the reviewed revision.'; passed = $true; evidence = 'sha-bound evidence' }
        $orderedRequest = @{ receipt = $orderedReceipt; expectedCriteria = $orderedExpected }
        $orderedValid = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $orderedRequest 'receipt-ordered-criteria'))
        Assert-True $orderedValid.data.valid 'the full packet criterion sequence should validate'
        $reordered = Copy-JsonObject $orderedRequest
        $reordered.receipt.criteria = @($reordered.receipt.criteria[1], $reordered.receipt.criteria[0])
        $reorderedResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $reordered 'receipt-reordered-criteria')) $false
        Assert-True (-not $reorderedResult.ok) 'criterion order changes must be rejected'
        Assert-True ($reorderedResult.error.message.Contains('criteria[0].id')) 'order mismatch should identify the criterion position'

        $unbound = @{ receipt = $receipt }
        $unboundResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $unbound 'receipt-unbound-criteria')) $false
        Assert-True (-not $unboundResult.ok) 'review receipt without a trusted expected criterion set must be rejected'

        $v1Resolved = Copy-JsonObject $request
        $v1Resolved.receipt.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix'; disposition = 'resolved' })
        $v1ResolvedResult = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $v1Resolved 'receipt-v1-resolved')) $false
        Assert-True (-not $v1ResolvedResult.ok) 'canonical v1 receipts cannot use the legacy resolved alias'

        $passingOpenFinding = Copy-JsonObject $request
        $passingOpenFinding.receipt.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix'; disposition = 'open' })
        $openResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $passingOpenFinding 'receipt-pass-open-high')) $false
        Assert-True (-not $openResult.ok) 'passing receipt with a genuinely open high finding must fail'

        $badConfig = @{ sessionId = 'wrong-profile'; coordinator = @{ threadId = 't'; hostId = 'local' }; config = @{ reviewerProfile = @{ model = 'gpt-6-sol'; effort = 'high' } } }
        $badPath = New-InputPath $badConfig 'bad-profile'
        $bad = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$badPath,'-StateRoot',(Join-Path $script:FixtureRoot 'bad-profile')) $false
        Assert-True (-not $bad.ok) 'unsupported reviewer profile must be rejected'
    }

    Test-Case 'preserve failed review criteria and checks as correction evidence' {
        $correction = New-ReviewReceipt 'changes_requested'
        $correction.schemaVersion = 1
        $correction.criteria[0].passed = $false
        $correction.checks[0].exitCode = 1
        $correction.checks[0].passed = $false
        $correction.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix'; disposition = 'open' })
        $request = @{ receipt = $correction; expectedCriteria = $script:ReviewCriteria }
        $result = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $request 'receipt-correction-evidence'))
        Assert-Equal 1 $result.data.criterionFailureCount 'failed criteria should remain review evidence'
        Assert-Equal 1 $result.data.checkFailureCount 'failed checks should remain review evidence'
        $passingFailure = Copy-JsonObject $request
        $passingFailure.receipt.verdict = 'pass'
        $passingResult = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath $passingFailure 'receipt-pass-failed-check')) $false
        Assert-True (-not $passingResult.ok) 'passing review must reject failed checks'
    }

    Test-Case 'ingest immutable receipt and evidence references from files' {
        $receiptPath = Join-Path $script:FixtureRoot 'receipt-file.json'
        $evidencePath = Join-Path $script:FixtureRoot 'evidence-file.json'
        $receipt = New-ReviewReceipt
        Write-JsonFile $receipt $receiptPath
        Write-JsonFile @{ evidenceId = 'ev-file'; checkedRevision = 'head'; outcome = 'passed' } $evidencePath
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant()
        $request = @{ receiptPath = $receiptPath; receiptSha256 = $hash; evidenceReferences = @(@{ path = $evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $evidencePath).Hash.ToLowerInvariant(); evidenceId = 'ev-file' }); expectedCriteria = $script:ReviewCriteria }
        $result = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $request 'receipt-file-reference'))
        Assert-True $result.data.valid 'file receipt should validate through the shared contract'
        Assert-Equal $receiptPath $result.data.receiptReference.path 'receipt reference should preserve its source path'
        Assert-Equal 'ev-file' @($result.data.evidenceReferences)[0].evidenceId 'evidence reference should retain its identity'
        $publishAttempt = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath ($request + @{ currentSha = 'head'; currentScopeHash = 'scope'; currentBaseSha = 'base'; expectedRunId = 'run'; expectedActionId = 'review-0'; expectedTicketKey = 'project:1:issue:1'; correctionRound = 0; remainingMinutes = 10 }) 'arbitrary-evidence-publish'))
        Assert-Equal 'needs_input' $publishAttempt.data.decision 'a hashed narrative file must not authorize publication'
        Assert-Equal 'durable_evidence_required_for_publication' $publishAttempt.data.reason 'publication must identify why durable evidence is missing'
        [IO.File]::AppendAllText($receiptPath, "`n")
        $tampered = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $request 'receipt-file-tampered')) $false
        Assert-True (-not $tampered.ok) 'tampered receipt files must be rejected by their hash'
        $missing = Copy-JsonObject $request
        $missing.evidenceReferences[0].path = Join-Path $script:FixtureRoot 'missing-evidence.json'
        $missingResult = Invoke-PsJson $script:ReviewScript @('-Operation','validate','-InputPath',(New-InputPath $missing 'receipt-missing-evidence')) $false
        Assert-True (-not $missingResult.ok) 'missing evidence references must be rejected'
    }

    Test-Case 'coordinate compact file-based dispatch and result operations' {
        $coordRoot = Join-Path $script:FixtureRoot 'coordinate-state'
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$coordRoot)
        $claim = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:800'; repositoryIdentity = 'coordinate-repo'; expectedRevision = $init.revision }
        $claimed = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claim 'coordinate-claim'),'-StateRoot',$coordRoot)
        $packetContextPath = Join-Path $script:FixtureRoot 'coordinate-context.json'; [IO.File]::WriteAllText($packetContextPath, 'coordinate context', [Text.UTF8Encoding]::new($false)); $fixtureBranch = ((& git rev-parse --abbrev-ref HEAD).Trim()); $fixtureHead = ((& git rev-parse HEAD).Trim())
        $packetRequest = @{ packetId = 'packet-coordinate'; sessionId = 'synthetic-session-01'; runId = 'coordinate-run'; ticket = @{ ticketKey = 'project:123:issue:800'; projectId = 123; kind = 'issue'; id = 800; ref = 800; title = 'Coordinate fixture' }; contextPath = $packetContextPath; criteria = @(@{ id = 'criterion-1'; text = 'Dispatch from a durable packet.' }); repository = @{ identity = 'coordinate-repo'; repositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path; worktreePath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path; branch = $fixtureBranch; baseSha = $fixtureHead }; requiredCommands = @('synthetic-check'); unresolvedRequirements = @(); authority = @{ authorizedActions = @('dispatch'); excludedActions = @() }; deadline = @{ startedAtUtc = '2026-09-30T00:00:00Z'; deadlineUtc = '2099-09-30T00:00:00Z'; elapsedBudgetMinutes = 120 }; profiles = @{ coordinator = @{ model = 'gpt-6.1-sol'; effort = 'high' }; implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } } }
        $packetCreated = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $packetRequest 'coordinate-packet-request'),'-StateRoot',$coordRoot)
        $packetPath = [string]$packetCreated.data.packetPath
        $noDeadlinePacketRequest = Copy-JsonObject $packetRequest; $noDeadlinePacketRequest.packetId = 'packet-coordinate-no-deadline'; $noDeadlinePacketRequest.Remove('deadline')
        $noDeadlinePacket = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $noDeadlinePacketRequest 'coordinate-no-deadline-packet-request'),'-StateRoot',$coordRoot)
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$noDeadlinePacket.data.packetPath)) 'assignment packets must not require an elapsed deadline'
        $promptPath = Join-Path $script:FixtureRoot 'coordinate-prompt.md'; [IO.File]::WriteAllText($promptPath, 'Use packet {{packetPath}} with hash {{packetHash}} for {{workerId}}.', [Text.UTF8Encoding]::new($false))
        $dispatch = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:800'; actionId = 'dispatch-1'; workerId = 'worker-1'; packetReference = @{ path = $packetPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packetPath).Hash.ToLowerInvariant() }; promptReference = @{ path = $promptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $promptPath).Hash.ToLowerInvariant() } }
        $prepared = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $dispatch 'coordinate-dispatch'),'-StateRoot',$coordRoot)
        Assert-Equal 'dispatch' $prepared.data.decision 'dispatch operation should return a compact action decision'
        Assert-Equal 'worker-1' $prepared.data.workerId 'dispatch descriptor should preserve worker identity'
        Assert-True ($prepared.data.action.operation -eq 'create_or_message_worker') 'helper should return a native action descriptor rather than call a desktop API'
        Assert-True ([string]$prepared.data.action.prompt.path -ne '') 'constructed prompt should be durable'
        $duplicate = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $dispatch 'coordinate-duplicate-dispatch'),'-StateRoot',$coordRoot)
        Assert-Equal 'reconcile' $duplicate.data.decision 'duplicate preparation must reconcile instead of redispatching'
        $expired = Copy-JsonObject $dispatch; $expired.actionId = 'dispatch-expired'; $expired.remainingMinutes = 0
        $expiredResult = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $expired 'coordinate-expired-dispatch'),'-StateRoot',$coordRoot)
        Assert-Equal 'dispatch' $expiredResult.data.decision 'wall-clock expiry must not block new external work'
        $expiredPacketRequest = Copy-JsonObject $packetRequest; $expiredPacketRequest.packetId = 'packet-coordinate-expired'; $expiredPacketRequest.deadline.startedAtUtc = '1999-01-01T00:00:00Z'; $expiredPacketRequest.deadline.deadlineUtc = '2000-01-01T02:00:00Z'
        $expiredPacket = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $expiredPacketRequest 'coordinate-expired-packet-request'),'-StateRoot',$coordRoot)
        $expiredPacketDispatch = Copy-JsonObject $dispatch; $expiredPacketDispatch.actionId = 'dispatch-packet-expired'; $expiredPacketDispatch.packetReference = @{ path = $expiredPacket.data.packetPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $expiredPacket.data.packetPath).Hash.ToLowerInvariant() }; $expiredPacketDispatch.Remove('remainingMinutes')
        $expiredPacketResult = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $expiredPacketDispatch 'coordinate-packet-expired-dispatch'),'-StateRoot',$coordRoot)
        Assert-Equal 'dispatch' $expiredPacketResult.data.decision 'an expired packet must not impose a wall-clock dispatch deadline'
        $allPlaceholderPrompt = Join-Path $script:FixtureRoot 'coordinate-all-placeholders.md'; [IO.File]::WriteAllText($allPlaceholderPrompt, '{{packetId}} {{reviewedSha}} {{repositoryPath}} {{schemaPath}} {{packetHash}}', [Text.UTF8Encoding]::new($false))
        $renderedDispatch = Copy-JsonObject $dispatch; $renderedDispatch.actionId = 'dispatch-rendered'; $renderedDispatch.workerId = 'reviewer-1'; $renderedDispatch.reviewedSha = $fixtureHead; $renderedDispatch.promptReference = @{ path = $allPlaceholderPrompt; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $allPlaceholderPrompt).Hash.ToLowerInvariant() }
        $rendered = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $renderedDispatch 'coordinate-rendered-dispatch'),'-StateRoot',$coordRoot)
        $renderedPrompt = Get-Content -Raw -LiteralPath $rendered.data.action.prompt.path
        Assert-True ($renderedPrompt -notmatch '\{\{[^}]+\}\}') 'all trusted prompt placeholders must be resolved'
        Assert-True ([string]$rendered.data.action.packet.packetHash -ne [string]$rendered.data.action.packet.sha256) 'packet body hash must remain distinct from packet file hash'
        $resultPath = Join-Path $script:FixtureRoot 'coordinate-result.json'; Write-JsonFile @{ resultId = 'result-1'; cursor = 'cursor-1'; actionId = 'dispatch-1'; workerId = 'worker-1'; status = 'completed'; decision = 'review'; nextPhase = 'preparing'; summary = 'Worker completed the assigned action.' } $resultPath
        $accept = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:800'; resultReference = @{ path = $resultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultPath).Hash.ToLowerInvariant() } }
        $accepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath $accept 'coordinate-accept'),'-StateRoot',$coordRoot)
        Assert-Equal 'review' $accepted.data.decision 'accepted worker result should choose the next route'
        Assert-Equal 'preparing' $accepted.data.phase 'accepted result should apply its requested local phase transition'
        Assert-True (@($accepted.data.requiredReferences).Count -lt 6) 'result relay should remain compact'
        $partialDispatch = Copy-JsonObject $dispatch; $partialDispatch.actionId = 'dispatch-partial'; $partial = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $partialDispatch 'coordinate-partial-dispatch'),'-StateRoot',$coordRoot)
        $partialResultPath = Join-Path $script:FixtureRoot 'coordinate-partial-result.json'; Write-JsonFile @{ resultId = 'result-partial'; cursor = 'cursor-partial'; actionId = 'dispatch-partial'; workerId = 'worker-1'; status = 'completed'; decision = 'review'; nextPhase = 'invalid-phase' } $partialResultPath
        $partialRequest = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:800'; resultReference = @{ path = $partialResultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $partialResultPath).Hash.ToLowerInvariant() } }
        $partialFirst = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath $partialRequest 'coordinate-partial-first'),'-StateRoot',$coordRoot) $false
        $partialRetry = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath $partialRequest 'coordinate-partial-retry'),'-StateRoot',$coordRoot) $false
        Assert-True (-not $partialFirst.ok -and -not $partialRetry.ok) 'a failed transition validation must be retryable without redispatching'
        $partialState = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$coordRoot)
        Assert-True ([string]$partialState.data.registry.tickets['project:123:issue:800'].lastResultCursor -cne 'cursor-partial') 'failed transition validation must not consume the worker cursor'
        $status = Invoke-PsJson $script:CoordinateScript @('-Operation','status','-InputPath',(New-InputPath @{ ticketKey = 'project:123:issue:800' } 'coordinate-status'),'-StateRoot',$coordRoot)
        Assert-Equal 'preparing' $status.data.phase 'status should report the local phase without source inspection'
        $externalPath = Join-Path $script:FixtureRoot 'coordinate-pending.json'; Write-JsonFile @{ provider = 'desktop'; clientThreadId = 'client-pending-1' } $externalPath
        $external = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:800'; actionId = 'dispatch-1'; observationStatus = 'observed'; externalReference = @{ path = $externalPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $externalPath).Hash.ToLowerInvariant() } }
        $pending = Invoke-PsJson $script:CoordinateScript @('-Operation','reconcile-external','-InputPath',(New-InputPath $external 'coordinate-pending-observation'),'-StateRoot',$coordRoot)
        Assert-Equal 'needs_input' $pending.data.decision 'a pending client ID must remain uncertain until a real thread ID is observed'
        Assert-Equal 'pending_client_id_requires_reconciliation' $pending.data.reason 'pending client IDs must not be treated as completed threads'
        $bad = Copy-JsonObject $accept; $bad.resultReference.path = Join-Path $script:FixtureRoot 'missing-coordinate-result.json'
        $badResult = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath $bad 'coordinate-bad-result'),'-StateRoot',$coordRoot) $false
        Assert-True (-not $badResult.ok) 'missing result files must fail before state mutation'
        $blockedDispatch = Copy-JsonObject $dispatch; $blockedDispatch.actionId = 'dispatch-blocked'; $blockedPrepared = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $blockedDispatch 'coordinate-blocked-dispatch'),'-StateRoot',$coordRoot)
        $blockedResultPath = Join-Path $script:FixtureRoot 'coordinate-blocked-result.json'; Write-JsonFile @{ resultId = 'result-blocked'; cursor = 'cursor-blocked'; actionId = 'dispatch-blocked'; workerId = 'worker-1'; status = 'blocked'; decision = 'needs_input'; nextPhase = 'needs_input'; receiptReference = @{ path = $resultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultPath).Hash.ToLowerInvariant() } } $blockedResultPath
        $blockedAccepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:800'; resultReference = @{ path = $blockedResultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $blockedResultPath).Hash.ToLowerInvariant() } } 'coordinate-blocked-accept'),'-StateRoot',$coordRoot)
        Assert-Equal 'needs_input' $blockedAccepted.data.decision 'blocked worker results with receipt references should route to needs_input'
        $blockedState = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$coordRoot)
        Assert-True (-not $blockedState.data.registry.actions['dispatch-blocked'].result.Contains('reviewVerdict')) 'blocked results must not persist review metadata when no assessment ran'
    }

    Test-Case 'require trusted review acceptance before publication preparation' {
        $publishRoot = Join-Path $script:FixtureRoot 'publication-state'; $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$publishRoot); $claim = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; repositoryIdentity = 'publication-repo'; expectedRevision = $init.revision } 'publication-claim'),'-StateRoot',$publishRoot); $reserved = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; expectedRevision = $claim.revision } 'publication-reserve'),'-StateRoot',$publishRoot)
        $preparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'preparing'; expectedRevision = $reserved.revision } 'publication-preparing'),'-StateRoot',$publishRoot); $implementing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'implementing'; expectedRevision = $preparing.revision } 'publication-implementing'),'-StateRoot',$publishRoot); $reviewing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'reviewing'; expectedRevision = $implementing.revision } 'publication-reviewing'),'-StateRoot',$publishRoot)
        $contextPath = Join-Path $script:FixtureRoot 'publication-context.json'; [IO.File]::WriteAllText($contextPath, 'publication context', [Text.UTF8Encoding]::new($false)); $cleanWorktree = Join-Path $script:FixtureRoot 'publication-worktree'; $sourceRepository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path; & git clone --no-local $sourceRepository $cleanWorktree 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Could not create the clean publication worktree fixture.' }; $cleanBranch = ((& git -C $cleanWorktree rev-parse --abbrev-ref HEAD).Trim()); $cleanHead = ((& git -C $cleanWorktree rev-parse HEAD).Trim()); $packetRequest = @{ packetId = 'packet-publication'; sessionId = 'synthetic-session-01'; runId = 'publication-run'; ticket = @{ ticketKey = 'project:123:issue:802'; projectId = 123; kind = 'issue'; id = 802; ref = 802; title = 'Publication fixture' }; contextPath = $contextPath; criteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.' }); repository = @{ identity = 'publication-repo'; repositoryPath = $cleanWorktree; worktreePath = $cleanWorktree; branch = $cleanBranch; baseSha = $cleanHead }; requiredCommands = @('synthetic-check'); unresolvedRequirements = @(); authority = @{ authorizedActions = @('dispatch','publish'); excludedActions = @() }; deadline = @{ startedAtUtc = '2026-09-30T00:00:00Z'; deadlineUtc = '2099-09-30T00:00:00Z'; elapsedBudgetMinutes = 120 }; profiles = @{ coordinator = @{ model = 'gpt-6.1-sol'; effort = 'high' }; implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } } }; $packetCreated = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $packetRequest 'publication-packet-request'),'-StateRoot',$publishRoot); $packetPath = [string]$packetCreated.data.packetPath; $packetReference = @{ path = $packetPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packetPath).Hash.ToLowerInvariant() }
         $checkActionRequest = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'publish-check-action'; actionKind = 'implementation_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $reviewing.revision }; $preparedCheckAction = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath $checkActionRequest 'publication-check-action'),'-StateRoot',$publishRoot)
         $reviewPrompt = Join-Path $script:FixtureRoot 'publication-review-prompt.md'; [IO.File]::WriteAllText($reviewPrompt, 'Review {{reviewedSha}} with {{schemaPath}}.', [Text.UTF8Encoding]::new($false)); $reviewPromptReference = @{ path = $reviewPrompt; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reviewPrompt).Hash.ToLowerInvariant() }; $reviewDispatch = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'review-action'; workerId = 'reviewer-thread'; reviewedSha = $cleanHead; packetReference = $packetReference; promptReference = $reviewPromptReference }; $preparedReview = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $reviewDispatch 'publication-review-dispatch'),'-StateRoot',$publishRoot); Assert-Equal 'publish-check-action' $preparedReview.data.action.reviewCheckActionIds[0] 'review dispatch should auto-bind prepared verification actions'; $lateCheckAction = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'late-review-check'; actionKind = 'review_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $preparedReview.data.revision } 'publication-late-review-check'),'-StateRoot',$publishRoot)
        $earlyPublication = Copy-JsonObject $reviewDispatch; $earlyPublication.actionId = 'publication-before-review'; $earlyPublication.workerId = 'publisher-thread'; $earlyPublication.Remove('promptReference'); $earlyPublication.Remove('reviewedSha'); $earlyResult = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-publication','-InputPath',(New-InputPath $earlyPublication 'publication-before-review'),'-StateRoot',$publishRoot) $false; Assert-True (-not $earlyResult.ok) 'publication must be blocked before an accepted review'
         $evidenceRoot = $publishRoot; $metadataRequest = @{ packetPath = $packetCreated.data.packetPath; packetHash = $packetCreated.data.packetHash; actionId = 'publish-check-action' }; $metadata = Invoke-PsJson $script:EvidenceScript @('-Operation','initialize-run','-InputPath',(New-InputPath $metadataRequest 'publication-check-metadata'),'-StateRoot',$publishRoot); $logPath = Join-Path $script:FixtureRoot 'publication-check.log'; [IO.File]::WriteAllText($logPath, 'synthetic check passed', [Text.UTF8Encoding]::new($false)); $capture = Invoke-PsJson $script:EvidenceScript @('-Operation','capture','-InputPath',(New-InputPath @{ metadataPath = $metadata.data.metadataPath; actualExitCode = 0; logPath = $logPath } 'publication-check-capture'),'-StateRoot',$publishRoot); $evidencePath = $capture.data.evidencePath; $evidenceReference = @{ path = $evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $evidencePath).Hash.ToLowerInvariant(); evidenceId = $capture.data.evidenceId }; $record = Copy-JsonObject $capture.data.evidence
          $receiptPath = Join-Path $script:FixtureRoot 'publication-receipt.json'; $receipt = @{ schemaVersion = 1; kind = 'review'; runId = 'publication-run'; actionId = 'review-action'; ticketKey = 'project:123:issue:802'; scopeHash = $packetCreated.data.scopeHash; baseSha = $cleanHead; reviewedSha = $cleanHead; verdict = 'pass'; reviewerModel = 'gpt-6.1-sol'; reviewerEffort = 'high'; criteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.'; passed = $true; evidence = $capture.data.evidenceId }); checks = @(@{ checkId = 'publish-check'; command = 'synthetic-check'; exitCode = 0; passed = $true; evidence = $capture.data.evidenceId; evidenceId = $capture.data.evidenceId; criterionIds = @('criterion-1') }); findings = @() }; Write-JsonFile $receipt $receiptPath; $receiptReference = @{ path = $receiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant() }; $resultPath = Join-Path $script:FixtureRoot 'publication-result.json'; Write-JsonFile @{ resultId = 'review-action'; cursor = 'publication-cursor'; actionId = 'review-action'; workerId = 'reviewer-thread'; status = 'completed'; decision = 'publish'; nextPhase = 'publishing'; reviewCheckActionIds = @('late-review-check'); receiptReference = $receiptReference; evidenceReferences = @($evidenceReference); evidenceStateRoot = $publishRoot; reviewContext = @{ currentSha = 'attacker-controlled'; currentScopeHash = 'wrong-scope'; currentBaseSha = 'wrong-base'; expectedRunId = 'wrong-run'; expectedActionId = 'review-action'; expectedTicketKey = 'project:123:issue:802'; correctionRound = 99 } } $resultPath
          $alternatePacketRequest = Copy-JsonObject $packetRequest; $alternatePacketRequest.packetId = 'packet-publication-alternate'; $alternatePacketRequest.requiredCommands = @(); $alternatePacket = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $alternatePacketRequest 'publication-alternate-packet'),'-StateRoot',$publishRoot); $alternateReference = @{ path = $alternatePacket.data.packetPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $alternatePacket.data.packetPath).Hash.ToLowerInvariant() }; $packetMismatch = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; packetReference = $alternateReference; resultReference = @{ path = $resultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultPath).Hash.ToLowerInvariant() } } 'publication-packet-mismatch'),'-StateRoot',$publishRoot) $false; Assert-True ($packetMismatch.error.message -match 'packet') 'acceptance must reject a packet replacement under a prepared reviewer action'
          $accepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; packetReference = $packetReference; resultReference = @{ path = $resultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultPath).Hash.ToLowerInvariant() } } 'publication-accept'),'-StateRoot',$publishRoot); Assert-Equal 'publish' $accepted.data.decision 'trusted review evidence should authorize the publishing transition'; $status = Invoke-PsJson $script:CoordinateScript @('-Operation','status','-InputPath',(New-InputPath @{ ticketKey = 'project:123:issue:802' } 'publication-status'),'-StateRoot',$publishRoot); Assert-Equal 'publishing' $status.data.phase 'accepted review should enter publishing'
         $recordWrapperBytes = [IO.File]::ReadAllBytes($evidencePath); $recordLogPath = [string]$record.log.path; $missingLogPath = $recordLogPath + '.offline-missing'; Move-Item -LiteralPath $recordLogPath -Destination $missingLogPath; $missingLogPublication = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-publication','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'publication-missing-log'; workerId = 'publisher-thread'; packetReference = $packetReference } 'publication-missing-log'),'-StateRoot',$publishRoot) $false; Move-Item -LiteralPath $missingLogPath -Destination $recordLogPath
         [IO.File]::WriteAllText($evidencePath, '{"recordJson":"tampered","recordSha256":"tampered"}', [Text.UTF8Encoding]::new($false)); $tamperedPublication = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-publication','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'publication-tampered-evidence'; workerId = 'publisher-thread'; packetReference = $packetReference } 'publication-tampered-evidence'),'-StateRoot',$publishRoot) $false; [IO.File]::WriteAllBytes($evidencePath, $recordWrapperBytes)
        $publication = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'publication-action'; workerId = 'publisher-thread'; packetReference = $packetReference }; $preparedPublication = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-publication','-InputPath',(New-InputPath $publication 'publication-prepare'),'-StateRoot',$publishRoot); Assert-Equal 'dispatch' $preparedPublication.data.decision 'publication should emit a descriptor only after review acceptance'; Assert-Equal 'review-action' $preparedPublication.data.action.approvedReviewActionId 'publication descriptor should bind to the accepted review action'
        $mutations = @(@{ name = 'wrong-run'; field = 'runId'; value = 'other-run' }, @{ name = 'wrong-action'; field = 'actionId'; value = 'other-action' }, @{ name = 'wrong-ticket'; field = 'ticketKey'; value = 'project:123:issue:999' }, @{ name = 'wrong-scope'; field = 'scopeHash'; value = 'other-scope' }, @{ name = 'wrong-revision'; field = 'checkedRevision'; value = 'other-head' }, @{ name = 'wrong-base'; field = 'coverageBaseSha'; value = 'other-base' }, @{ name = 'wrong-command'; field = 'command'; value = 'other-check' }, @{ name = 'wrong-criteria'; field = 'criterionIds'; value = @() }, @{ name = 'wrong-profile'; field = 'profile'; value = @{ model = 'gpt-6-sol'; effort = 'medium' } }, @{ name = 'failed-outcome'; field = 'actualExitCode'; value = 1 })
         foreach ($mutation in $mutations) { $mutant = Copy-JsonObject $record; $mutant.evidenceId = 'ev-' + $mutation.name; switch ($mutation.field) { 'coverageBaseSha' { $mutant.coverage.baseSha = $mutation.value }; 'profile' { $mutant.profile = $mutation.value }; 'criterionIds' { $mutant.criterionIds = @() }; 'actualExitCode' { $mutant.actualExitCode = 1; $mutant.outcome = 'failed'; $mutant.acceptedAsCheckPass = $false }; default { $mutant[$mutation.field] = $mutation.value } }; $mutantJson = $mutant | ConvertTo-Json -Depth 100 -Compress; $mutantHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($mutantJson))) -Algorithm SHA256).Hash.ToLowerInvariant(); $mutantPath = Join-Path $evidenceRoot ('evidence\publication-run\publish-check-action\' + $mutant.evidenceId + '.json'); Write-JsonFile @{ recordJson = $mutantJson; recordSha256 = $mutantHash } $mutantPath; $mutantReceipt = Copy-JsonObject $receipt; $mutantReceipt.checks[0].evidenceId = $mutant.evidenceId; $mutantRequest = @{ receipt = $mutantReceipt; expectedCriteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.' }); currentSha = $cleanHead; currentScopeHash = $packetCreated.data.scopeHash; currentBaseSha = $cleanHead; expectedRunId = 'publication-run'; expectedActionId = 'review-action'; expectedTicketKey = 'project:123:issue:802'; correctionRound = 0; remainingMinutes = 10; evidenceStateRoot = $evidenceRoot; evidenceReferences = @(@{ path = $mutantPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $mutantPath).Hash.ToLowerInvariant(); evidenceId = $mutant.evidenceId }) }; $mutantDecision = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $mutantRequest ('publication-binding-' + $mutation.name))); Assert-Equal 'needs_input' $mutantDecision.data.decision "publication binding mutation must fail closed: $($mutation.name)" }
         $reuseRecord = Copy-JsonObject $record; $reuseRecord.evidenceId = 'ev-approved-reuse'; $reuseRecord.checkedRevision = 'prior-head'; $reuseRecord.coverage.revision = 'prior-head'; $reuseRecordJson = $reuseRecord | ConvertTo-Json -Depth 100 -Compress; $reuseRecordHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($reuseRecordJson))) -Algorithm SHA256).Hash.ToLowerInvariant(); $reusePath = Join-Path $evidenceRoot 'evidence\publication-run\publish-check-action\ev-approved-reuse.json'; Write-JsonFile @{ recordJson = $reuseRecordJson; recordSha256 = $reuseRecordHash } $reusePath; $reuseReceipt = Copy-JsonObject $receipt; $reuseReceipt.checks[0].evidenceId = 'ev-approved-reuse'; $reuseReceipt.reviewDelta = @{ fromSha = 'prior-head'; toSha = $cleanHead; changedPaths = @('docs/guide.md'); documentationChanged = $true; documentationPaths = @('docs/guide.md'); documentationAssessment = 'Reviewed the documentation-only amendment.'; reusedCheckIds = @('publish-check'); reuseJustification = 'The implementation inputs are unchanged.' }; $reuseRequest = @{ receipt = $reuseReceipt; expectedCriteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.' }); requiredCommands = @('synthetic-check'); allowedEvidenceActions = @(@{ actionId = 'publish-check-action'; actionKind = 'implementation_check'; role = 'implementer'; profile = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; command = 'synthetic-check'; criterionIds = @('criterion-1'); coverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }); currentCoverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'documentation_only'; changedPaths = @('docs/guide.md') }; currentSha = $cleanHead; currentScopeHash = $packetCreated.data.scopeHash; currentBaseSha = $cleanHead; expectedRunId = 'publication-run'; expectedActionId = 'review-action'; expectedTicketKey = 'project:123:issue:802'; correctionRound = 0; remainingMinutes = 10; previousReviewedSha = 'prior-head'; evidenceStateRoot = $evidenceRoot; evidenceReferences = @(@{ path = $reusePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reusePath).Hash.ToLowerInvariant(); evidenceId = 'ev-approved-reuse' }) }; $reuseDecision = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $reuseRequest 'publication-approved-reuse')); Assert-Equal 'publish' $reuseDecision.data.decision 'explicitly justified unchanged-input evidence reuse should remain publishable'
          $reuseOverlap = Copy-JsonObject $reuseRequest; $reuseOverlap.receipt.reviewDelta.changedPaths = @('src/app.cs'); $reuseOverlap.currentCoverage.changedKind = 'code'; $reuseOverlap.currentCoverage.changedPaths = @('src/app.cs'); $reuseOverlapResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $reuseOverlap 'publication-reuse-overlap')); Assert-Equal 'needs_input' $reuseOverlapResult.data.decision 'reused evidence must be invalidated when a covered source file changes'; $environmentDrift = Copy-JsonObject $reuseRequest; $environmentDrift.currentCoverage.environmentHash = 'changed-environment'; $environmentDriftResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $environmentDrift 'publication-reuse-environment-drift')); Assert-Equal 'needs_input' $environmentDriftResult.data.decision 'reused evidence must be invalidated when environment inputs drift'; $mixedReuse = Copy-JsonObject $reuseRequest; $mixedReuse.currentCoverage.changedKind = 'code'; $mixedReuse.currentCoverage.changedPaths = @('docs/guide.md','other-production.cs'); $mixedReuse.receipt.reviewDelta.changedPaths = @('docs/guide.md','other-production.cs'); $mixedReuseResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $mixedReuse 'publication-reuse-mixed')); Assert-Equal 'needs_input' $mixedReuseResult.data.decision 'mixed documentation and production changes must not be treated as documentation-only'
          $missingRequired = Copy-JsonObject $reuseRequest; $missingRequired.requiredCommands = @('synthetic-check','full-suite'); $missingRequiredResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $missingRequired 'publication-required-command')); Assert-Equal 'needs_input' $missingRequiredResult.data.decision 'every trusted packet command must have passing evidence'
          $docsAmendmentB = Copy-JsonObject $reuseRequest; $docsAmendmentB.currentSha = 'docs-head-b'; $docsAmendmentB.currentCoverage.revision = 'docs-head-b'; $docsAmendmentB.currentCoverage.changedPaths = @('docs/first.md'); $docsAmendmentB.receipt.reviewedSha = 'docs-head-b'; $docsAmendmentB.receipt.reviewDelta = @{ fromSha = 'prior-head'; toSha = 'docs-head-b'; changedPaths = @('docs/first.md'); documentationChanged = $true; documentationPaths = @('docs/first.md'); documentationAssessment = 'Reviewed the first documentation-only amendment.'; reusedCheckIds = @('publish-check'); reuseJustification = 'The implementation inputs are unchanged.' }; $docsAmendmentBResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $docsAmendmentB 'publication-successive-docs-b')); Assert-Equal 'publish' $docsAmendmentBResult.data.decision 'a documentation amendment should reuse the original check'
          $docsAmendmentC = Copy-JsonObject $docsAmendmentB; $docsAmendmentC.currentSha = 'docs-head-c'; $docsAmendmentC.previousReviewedSha = 'docs-head-b'; $docsAmendmentC.currentCoverage.revision = 'docs-head-c'; $docsAmendmentC.currentCoverage.changedPaths = @('docs/second.md'); $docsAmendmentC.receipt.reviewedSha = 'docs-head-c'; $docsAmendmentC.receipt.reviewDelta = @{ fromSha = 'docs-head-b'; toSha = 'docs-head-c'; changedPaths = @('docs/second.md'); documentationChanged = $true; documentationPaths = @('docs/second.md'); documentationAssessment = 'Reviewed the successive documentation-only amendment.'; reusedCheckIds = @('publish-check'); reuseJustification = 'The implementation inputs remain unchanged.' }; $docsAmendmentCResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $docsAmendmentC 'publication-successive-docs-c')); Assert-Equal 'publish' $docsAmendmentCResult.data.decision 'successive documentation amendments should retain the original evidence provenance'
          $docsChainWorktree = Join-Path $script:FixtureRoot 'publication-docs-chain-worktree'; & git clone --no-local $sourceRepository $docsChainWorktree 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Could not create the documentation evidence chain fixture.' }; $docsChainBase = ((& git -C $docsChainWorktree rev-parse HEAD).Trim()); [IO.Directory]::CreateDirectory((Join-Path $docsChainWorktree 'docs')) | Out-Null; [IO.File]::WriteAllText((Join-Path $docsChainWorktree 'docs/evidence-origin-one.md'), 'first docs amendment'); & git -C $docsChainWorktree add docs/evidence-origin-one.md; & git -C $docsChainWorktree commit --quiet -m 'documentation evidence chain one'; [IO.File]::WriteAllText((Join-Path $docsChainWorktree 'docs/evidence-origin-two.md'), 'second docs amendment'); & git -C $docsChainWorktree add docs/evidence-origin-two.md; & git -C $docsChainWorktree commit --quiet -m 'documentation evidence chain two'; $docsChainHead = ((& git -C $docsChainWorktree rev-parse HEAD).Trim()); $docsChainRequest = @{ evidenceReferences = @($evidenceReference); repositoryPath = $docsChainWorktree; current = @{ fromRevision = $docsChainBase; revision = $docsChainHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'documentation_only'; changedPaths = @('docs/evidence-origin-one.md','docs/evidence-origin-two.md') } }; $docsChainResult = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath $docsChainRequest 'publication-docs-chain-reuse')); Assert-True $docsChainResult.data.reusable 'A documentation-only A-to-B-to-C chain should retain reusable evidence provenance'
           $mixedChainWorktree = Join-Path $script:FixtureRoot 'publication-mixed-chain-worktree'; & git clone --no-local $sourceRepository $mixedChainWorktree 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Could not create the mixed evidence chain fixture.' }; $mixedChainBase = ((& git -C $mixedChainWorktree rev-parse HEAD).Trim()); [IO.File]::WriteAllText((Join-Path $mixedChainWorktree 'app.txt'), 'source correction'); & git -C $mixedChainWorktree add app.txt; & git -C $mixedChainWorktree commit --quiet -m 'source evidence chain correction'; $mixedChainSource = ((& git -C $mixedChainWorktree rev-parse HEAD).Trim()); [IO.Directory]::CreateDirectory((Join-Path $mixedChainWorktree 'docs')) | Out-Null; [IO.File]::WriteAllText((Join-Path $mixedChainWorktree 'docs/evidence-origin.md'), 'documentation after source correction'); & git -C $mixedChainWorktree add docs/evidence-origin.md; & git -C $mixedChainWorktree commit --quiet -m 'documentation after source correction'; $mixedChainHead = ((& git -C $mixedChainWorktree rev-parse HEAD).Trim()); $mixedChainRequest = @{ evidenceReferences = @($evidenceReference); repositoryPath = $mixedChainWorktree; current = @{ fromRevision = $mixedChainSource; revision = $mixedChainHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'documentation_only'; changedPaths = @('docs/evidence-origin.md') } }; $mixedChainResult = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath $mixedChainRequest 'publication-mixed-chain-reuse')); Assert-True (-not $mixedChainResult.data.reusable) 'evidence from before a covered source correction must not be revived by a later docs-only review'; Assert-Equal 'mixed_change_set' $mixedChainResult.data.evidence[0].reason 'mixed source and documentation history should explain evidence rejection'
          $incompleteCoverage = Copy-JsonObject $reuseRequest; $incompleteCoverage.currentCoverage.changedPaths = @('docs/guide.md'); $incompleteCoverage.currentCoverage.changedKind = 'documentation_only'; $incompleteCoverage.receipt.reviewDelta.changedPaths = @('docs/guide.md','src/app.cs'); $incompleteCoverage.receipt.reviewDelta.documentationPaths = @('docs/guide.md'); $incompleteCoverageResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $incompleteCoverage 'publication-incomplete-current-coverage')); Assert-Equal 'needs_input' $incompleteCoverageResult.data.decision 'currentCoverage must not omit a source path preserved by reviewDelta'
         $shippedPrompt = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\assets\reviewer-prompt.md'; $shippedDispatch = Copy-JsonObject $reviewDispatch; $shippedDispatch.actionId = 'shipped-review-template'; $shippedDispatch.promptReference = @{ path = (Resolve-Path $shippedPrompt).Path; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shippedPrompt).Hash.ToLowerInvariant() }; $shipped = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $shippedDispatch 'publication-shipped-template'),'-StateRoot',$publishRoot); Assert-Equal $cleanHead $shipped.data.action.previousReviewedSha 'follow-up reviewer dispatch must freeze the latest accepted reviewed revision'; $shippedText = Get-Content -Raw -LiteralPath $shipped.data.action.prompt.path; Assert-True ($shippedText -notmatch [regex]::Escape($cleanWorktree + '\.agents')) 'shipped reviewer template must not depend on a target checkout .agents directory'; Assert-True ($shippedText -match [regex]::Escape((Resolve-Path (Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\references\review-receipt-v1.schema.json')).Path)) 'shipped reviewer template must use the durable skill schema path'
         $correctionRoot = Join-Path $script:FixtureRoot 'publication-correction-state'; $correctionInit = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$correctionRoot); $correctionClaim = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; repositoryIdentity = 'publication-repo'; expectedRevision = $correctionInit.revision } 'correction-claim'),'-StateRoot',$correctionRoot); $correctionReserve = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; expectedRevision = $correctionClaim.revision } 'correction-reserve'),'-StateRoot',$correctionRoot); $correctionPreparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'preparing'; expectedRevision = $correctionReserve.revision } 'correction-preparing'),'-StateRoot',$correctionRoot); $correctionImplementing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'implementing'; expectedRevision = $correctionPreparing.revision } 'correction-implementing'),'-StateRoot',$correctionRoot); $correctionReviewing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'reviewing'; expectedRevision = $correctionImplementing.revision } 'correction-reviewing'),'-StateRoot',$correctionRoot)
          $correctionCheck = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'correction-check-action'; actionKind = 'implementation_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $correctionReviewing.revision } 'correction-check'),'-StateRoot',$correctionRoot); $correctionMetadata = Invoke-PsJson $script:EvidenceScript @('-Operation','initialize-run','-InputPath',(New-InputPath @{ packetPath = $packetCreated.data.packetPath; packetHash = $packetCreated.data.packetHash; actionId = 'correction-check-action' } 'correction-metadata'),'-StateRoot',$correctionRoot); $correctionLog = Join-Path $script:FixtureRoot 'correction-check.log'; [IO.File]::WriteAllText($correctionLog, 'correction check failed before repair', [Text.UTF8Encoding]::new($false)); $correctionEvidence = Invoke-PsJson $script:EvidenceScript @('-Operation','capture','-InputPath',(New-InputPath @{ metadataPath = $correctionMetadata.data.metadataPath; actualExitCode = 1; logPath = $correctionLog } 'correction-capture'),'-StateRoot',$correctionRoot)
          $correctionReviewDispatch = Copy-JsonObject $reviewDispatch; $correctionReviewDispatch.actionId = 'correction-review'; $correctionReviewDispatch.reviewedSha = $cleanHead; $preparedCorrectionReview = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $correctionReviewDispatch 'correction-review-dispatch'),'-StateRoot',$correctionRoot)
         $changesReceipt = Copy-JsonObject $receipt; $changesReceipt.actionId = 'correction-review'; $changesReceipt.verdict = 'changes_requested'; $changesReceipt.criteria[0].passed = $false; $changesReceipt.criteria[0].evidence = 'Correction is required.'; $changesReceipt.checks[0].evidenceId = $correctionEvidence.data.evidenceId; $changesReceipt.checks[0].exitCode = 1; $changesReceipt.checks[0].passed = $false; $changesReceipt.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'The initial implementation check failed.'; requestedChange = 'Correct the implementation and rerun the check.'; disposition = 'open' }); $changesReceiptPath = Join-Path $script:FixtureRoot 'correction-receipt.json'; Write-JsonFile $changesReceipt $changesReceiptPath; $changesResultPath = Join-Path $script:FixtureRoot 'correction-result.json'; Write-JsonFile @{ resultId = 'correction-review'; cursor = 'correction-cursor'; actionId = 'correction-review'; workerId = 'reviewer-thread'; status = 'completed'; decision = 'correct'; nextPhase = 'correcting'; receiptReference = @{ path = $changesReceiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $changesReceiptPath).Hash.ToLowerInvariant() }; evidenceReferences = @(@{ path = $correctionEvidence.data.evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $correctionEvidence.data.evidencePath).Hash.ToLowerInvariant(); evidenceId = $correctionEvidence.data.evidenceId }); evidenceStateRoot = $correctionRoot } $changesResultPath; $changesAccepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; packetReference = $packetReference; resultReference = @{ path = $changesResultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $changesResultPath).Hash.ToLowerInvariant() } } 'correction-accept'),'-StateRoot',$correctionRoot); Assert-Equal 'correct' $changesAccepted.data.decision 'changes_requested review should route to correction'; Assert-Equal 'correcting' $changesAccepted.data.phase 'changes_requested review should preserve the correction phase'
          $correctionImplementing2 = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'implementing'; expectedRevision = $changesAccepted.data.revision } 'correction-implementing-2'),'-StateRoot',$correctionRoot); [IO.Directory]::CreateDirectory((Join-Path $cleanWorktree 'src')) | Out-Null; [IO.File]::WriteAllText((Join-Path $cleanWorktree 'src/app.cs'), 'synthetic correction'); & git -C $cleanWorktree add src/app.cs; $null = & git -C $cleanWorktree commit --quiet -m 'Apply synthetic correction'; Assert-Equal 0 $LASTEXITCODE 'synthetic correction should commit'; $correctionHead = ((& git -C $cleanWorktree rev-parse HEAD).Trim()); $correctionReviewing2 = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'reviewing'; expectedRevision = $correctionImplementing2.revision } 'correction-reviewing-2'),'-StateRoot',$correctionRoot)
         $correctionCheck2 = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'correction-check-action-2'; actionKind = 'implementation_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $correctionHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $correctionReviewing2.revision } 'correction-check-2'),'-StateRoot',$correctionRoot); $correctionMetadata2 = Invoke-PsJson $script:EvidenceScript @('-Operation','initialize-run','-InputPath',(New-InputPath @{ packetPath = $packetCreated.data.packetPath; packetHash = $packetCreated.data.packetHash; actionId = 'correction-check-action-2' } 'correction-metadata-2'),'-StateRoot',$correctionRoot); $correctionLog2 = Join-Path $script:FixtureRoot 'correction-check-2.log'; [IO.File]::WriteAllText($correctionLog2, 'correction check passed', [Text.UTF8Encoding]::new($false)); $correctionEvidence2 = Invoke-PsJson $script:EvidenceScript @('-Operation','capture','-InputPath',(New-InputPath @{ metadataPath = $correctionMetadata2.data.metadataPath; actualExitCode = 0; logPath = $correctionLog2 } 'correction-capture-2'),'-StateRoot',$correctionRoot); $followupPrompt = Copy-JsonObject $reviewDispatch; $followupPrompt.actionId = 'correction-review-2'; $followupPrompt.reviewedSha = $correctionHead; $followup = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $followupPrompt 'correction-followup-dispatch'),'-StateRoot',$correctionRoot); Assert-Equal $cleanHead $followup.data.action.previousReviewedSha 'correction re-review should derive the prior changes_requested revision'
         $followReceipt = Copy-JsonObject $receipt; $followReceipt.actionId = 'correction-review-2'; $followReceipt.reviewedSha = $correctionHead; $followReceipt.checks[0].evidenceId = $correctionEvidence2.data.evidenceId; $followReceipt.reviewDelta = @{ fromSha = $cleanHead; toSha = $correctionHead; changedPaths = @('src/app.cs'); documentationChanged = $false; documentationPaths = @(); documentationAssessment = 'No documentation changed in this correction.'; reusedCheckIds = @(); reuseJustification = '' }; $followCoverage = @{ revision = $correctionHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'code'; changedPaths = @('src/app.cs') }; $followReviewRequest = @{ receipt = $followReceipt; expectedCriteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.' }); currentSha = $correctionHead; currentScopeHash = $packetCreated.data.scopeHash; currentBaseSha = $cleanHead; expectedRunId = 'publication-run'; expectedActionId = 'correction-review-2'; expectedTicketKey = 'project:123:issue:802'; correctionRound = 1; remainingMinutes = 10; previousReviewedSha = $cleanHead; currentCoverage = $followCoverage; evidenceStateRoot = $correctionRoot; evidenceReferences = @(@{ path = $correctionEvidence2.data.evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $correctionEvidence2.data.evidencePath).Hash.ToLowerInvariant(); evidenceId = $correctionEvidence2.data.evidenceId }) }; $missingFollowDelta = Copy-JsonObject $followReviewRequest; $missingFollowDelta.receipt.Remove('reviewDelta'); $missingFollowDeltaDecision = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $missingFollowDelta 'correction-missing-delta')); Assert-Equal 'missing_review_delta_assessment' $missingFollowDeltaDecision.data.reason 'correction re-review must require reviewDelta'; $followReceiptPath = Join-Path $script:FixtureRoot 'correction-followup-receipt.json'; Write-JsonFile $followReceipt $followReceiptPath; $followResultPath = Join-Path $script:FixtureRoot 'correction-followup-result.json'; Write-JsonFile @{ resultId = 'correction-review-2'; cursor = 'correction-followup-cursor'; actionId = 'correction-review-2'; workerId = 'reviewer-thread'; status = 'completed'; decision = 'publish'; nextPhase = 'publishing'; receiptReference = @{ path = $followReceiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $followReceiptPath).Hash.ToLowerInvariant() }; evidenceReferences = @(@{ path = $correctionEvidence2.data.evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $correctionEvidence2.data.evidencePath).Hash.ToLowerInvariant(); evidenceId = $correctionEvidence2.data.evidenceId }); evidenceStateRoot = $correctionRoot } $followResultPath; $followAccepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; packetReference = $packetReference; currentCoverage = $followCoverage; resultReference = @{ path = $followResultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $followResultPath).Hash.ToLowerInvariant() } } 'correction-followup-accept'),'-StateRoot',$correctionRoot); Assert-Equal 'publish' $followAccepted.data.decision 'proper correction delta should publish after re-review'; $correctionAcceptedState = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$correctionRoot); Assert-True $correctionAcceptedState.data.registry.actions['correction-review-2'].result.Contains('currentCoverage') 'accepted input currentCoverage must be persisted'; $fallbackPublication = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-publication','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'correction-publication'; workerId = 'publisher-thread'; packetReference = $packetReference } 'correction-publication'),'-StateRoot',$correctionRoot); Assert-Equal 'dispatch' $fallbackPublication.data.decision 'accepted input currentCoverage must survive final publication revalidation'
    }

    Test-Case 'keep unchanged waits quiet and reuse one heartbeat' {
        $waitRoot = Join-Path $script:FixtureRoot 'wait-state'
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$waitRoot)
        $claim = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:801'; repositoryIdentity = 'wait-repo'; expectedRevision = $init.revision }
        $claimed = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claim 'wait-claim'),'-StateRoot',$waitRoot)
        $before = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$waitRoot)
        $unchanged = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:801'; waitStatus = 'unchanged'; afterCursor = 'cursor-1'; threadId = 'thread-1'; timeoutMs = 30000 }
        $quiet = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $unchanged 'wait-unchanged'),'-StateRoot',$waitRoot)
        Assert-Equal 'continue_wait' $quiet.data.decision 'unchanged wait should continue the bounded native wait'
        Assert-Equal 'wait_threads' $quiet.data.nativeOperation 'unchanged wait should use wait_threads'
        Assert-Equal 0 @($quiet.data.changedFields).Count 'unchanged wait should not mutate state'
        Assert-True (-not $quiet.data.notifyUser) 'unchanged wait should not notify the user'
        Assert-Equal 'compact_worker_and_wait_state_only' $quiet.data.contextRead 'unchanged wait should read only compact state'
        Assert-Equal 0 $quiet.data.contextFootprint.heavyweightReads 'healthy ticks should not load heavyweight context'
        Assert-True (-not $quiet.data.contextFootprint.sourceRead) 'healthy ticks should not reread source'
        Assert-True (-not $quiet.data.contextFootprint.ticketReread) 'healthy ticks should not reread tickets'
        Assert-True (-not $quiet.data.waitThreadsArguments.targets[0].Contains('hostId')) 'absent native wait host IDs must be omitted rather than null'
        $noTarget = Copy-JsonObject $unchanged; $noTarget.Remove('threadId'); $noTarget.Remove('afterCursor'); $noTarget.Remove('targets'); $noTargetResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $noTarget 'wait-no-target'),'-StateRoot',$waitRoot) $false; Assert-True (-not $noTargetResult.ok) 'a native wait descriptor without targets must fail closed'
        $after = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$waitRoot)
        Assert-Equal $before.revision $after.revision 'unchanged wait must not advance the registry revision'
        $active = Copy-JsonObject $unchanged; $active.waitStatus = 'active'; $active.compactStatus = @{ workerStatus = 'active'; waitState = 'expected_progress'; elapsedMinutes = 999 }
        $activeResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $active 'wait-active'),'-StateRoot',$waitRoot)
        Assert-Equal 'continue_wait' $activeResult.data.decision 'active work should remain a quiet wait'
        Assert-Equal 'wait_threads' $activeResult.data.nativeOperation 'active work should not trigger a detailed read'
        Assert-True (-not $activeResult.data.notifyUser) 'active work should not notify the user'
        Assert-True (-not $activeResult.data.detailFetch) 'active work should not fetch heavyweight detail'
        $blocked = Copy-JsonObject $unchanged; $blocked.waitStatus = 'blocked'; $blocked.compactStatus = @{ workerStatus = 'active'; waitState = 'expected_progress' }
        $blockedResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $blocked 'wait-blocked-active-worker'),'-StateRoot',$waitRoot)
        Assert-Equal 'fetch_blocker' $blockedResult.data.decision 'a blocked event must outrank a healthy worker observation'
        Assert-Equal 'read_thread' $blockedResult.data.nativeOperation 'a blocked event should fetch the blocker detail'
        Assert-True $blockedResult.data.notifyUser 'a blocked event should notify the user'
        Assert-True $blockedResult.data.detailFetch 'a blocked event should request detail'
        $completedActive = Copy-JsonObject $unchanged; $completedActive.waitStatus = 'completed'; $completedActive.compactStatus = @{ workerStatus = 'active'; waitState = 'expected_progress' }
        $completedActiveResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $completedActive 'wait-completed-active-worker'),'-StateRoot',$waitRoot)
        Assert-Equal 'fetch_result' $completedActiveResult.data.decision 'a completed event must outrank a healthy worker observation'
        Assert-True $completedActiveResult.data.notifyUser 'a completed event should notify the user'
        $approval = Copy-JsonObject $unchanged; $approval.waitStatus = 'awaiting_approval'; $approval.compactStatus = @{ workerStatus = 'waiting_user'; waitState = 'user_approval'; elapsedMinutes = 999 }
        $approvalResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $approval 'wait-approval'),'-StateRoot',$waitRoot)
        Assert-Equal 'heartbeat_quiet' $approvalResult.data.decision 'pending user approval should remain quiet'
        Assert-Equal 'wait_threads' $approvalResult.data.nativeOperation 'pending approval should not trigger a detailed read'
        Assert-True (-not $approvalResult.data.notifyUser) 'pending approval should not duplicate notifications'
        Assert-True (-not $approvalResult.data.detailFetch) 'pending approval should not fetch heavyweight detail'
        $interrupted = Copy-JsonObject $unchanged; $interrupted.waitStatus = 'interrupted'; $interrupted.compactStatus = @{ workerStatus = 'interrupted'; waitState = 'unknown' }
        $interruptedResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $interrupted 'wait-interrupted'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_recovery' $interruptedResult.data.decision 'interrupted work should require evidence-based recovery'
        Assert-Equal 'read_thread' $interruptedResult.data.nativeOperation 'interrupted work should fetch the recent worker result'
        Assert-True $interruptedResult.data.notifyUser 'meaningful recovery should notify the user'
        Assert-True $interruptedResult.data.recovery.reconciliationRequired 'interrupted work should require external reconciliation'
        Assert-True (-not $interruptedResult.data.recovery.retryAllowed) 'interrupted work must not replay an ambiguous action'
        $missingHandoff = Copy-JsonObject $unchanged; $missingHandoff.waitStatus = 'completed'; $missingHandoff.compactStatus = @{ workerStatus = 'completed'; waitState = 'missing_handoff' }
        $missingHandoffResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $missingHandoff 'wait-missing-handoff'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_recovery' $missingHandoffResult.data.decision 'a completed worker with a missing handoff should require recovery'
        Assert-True $missingHandoffResult.data.notifyUser 'a missing handoff should notify the user'
        $manual = Invoke-PsJson $script:CoordinateScript @('-Operation','check-progress','-InputPath',(New-InputPath @{ runId = 'synthetic-session-01'; coordinatorThreadId = 'coordinator-thread'; continuation = @{ state = 'active'; heartbeatId = 'heartbeat-1'; scheduleState = 'ACTIVE' } } 'manual-check-progress'),'-StateRoot',$waitRoot)
        Assert-Equal 'check_progress' $manual.data.decision 'manual check-progress should inspect the existing run'
        Assert-True $manual.data.manual 'manual check-progress should not dispatch work'
        Assert-True ($manual.data.resumeInstruction -like '*heartbeat-plan*') 'manual check-progress should expose the native resume instruction'
        Assert-True ($manual.data.resumeInstruction -notlike '*workflow-state.ps1*') 'manual check-progress should not require the custom workflow-state application'
        Assert-Equal 'wait_threads' $manual.data.nativeOperation 'healthy manual check-progress should use native waiting'
        Assert-True (-not $manual.data.stateMutation) 'manual check-progress should not mutate state'
        $manualNativeOnly = Invoke-PsJson $script:CoordinateScript @('-Operation','check-progress','-InputPath',(New-InputPath @{ runId = 'synthetic-session-01'; coordinatorThreadId = 'coordinator-thread'; continuation = @{ state = 'active'; heartbeatId = 'heartbeat-1'; scheduleState = 'ACTIVE' } } 'manual-check-progress-native-only'))
        Assert-Equal 'check_progress' $manualNativeOnly.data.decision 'manual check-progress must work without a workflow-state registry'
        $concurrent = Copy-JsonObject $unchanged; $concurrent.Remove('threadId'); $concurrent.Remove('afterCursor'); $concurrent.targets = @(@{ threadId = 'worker-1'; afterCursor = 'cursor-1' }, @{ threadId = 'worker-2'; hostId = 'local'; afterCursor = 'cursor-2' })
        $concurrentResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $concurrent 'wait-concurrent'),'-StateRoot',$waitRoot)
        Assert-Equal 2 @($concurrentResult.data.waitThreadsArguments.targets).Count 'concurrent message and tick waits should preserve both targets'
        Assert-Equal 'cursor-2' $concurrentResult.data.waitThreadsArguments.targets[1].afterCursor 'concurrent waits should preserve each cursor'
        Assert-True (-not $concurrentResult.data.stateMutation) 'concurrent waits should not mutate state'
        $completed = Copy-JsonObject $unchanged; $completed.waitStatus = 'completed'
        $detail = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $completed 'wait-completed'),'-StateRoot',$waitRoot)
        Assert-Equal 'fetch_result' $detail.data.decision 'completion should trigger one detailed result read'
        Assert-Equal 'read_thread' $detail.data.nativeOperation 'completion should use read_thread only after a wake'
        $heartbeatInput = @{ runId = 'synthetic-session-01'; coordinatorThreadId = 'coordinator-thread'; scope = @{ story = 51; tasks = @(73,74,75,76) }; notificationPolicy = 'failed_runs_only' }
        $heartbeat = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $heartbeatInput 'heartbeat-reserve'),'-StateRoot',$waitRoot)
        Assert-Equal 'reserve_heartbeat' $heartbeat.data.decision 'first heartbeat plan should reserve before external creation'
        Assert-True ($null -eq $heartbeat.data.automationRequest) 'reservation must not issue an external create request'
        Assert-Equal 'create_reserved' $heartbeat.data.continuation.state 'reservation should be persisted as continuation context'
        $nativeOnlyHeartbeat = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $heartbeatInput 'heartbeat-native-only'))
        Assert-Equal 'reserve_heartbeat' $nativeOnlyHeartbeat.data.decision 'heartbeat setup must work without a workflow-state registry'
        $repeatReservation = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $heartbeatInput 'heartbeat-repeat-reserve'),'-StateRoot',$waitRoot)
        Assert-Equal 'reserve_heartbeat' $repeatReservation.data.decision 'a second uncommitted plan must remain a reservation'
        Assert-True ($null -eq $repeatReservation.data.automationRequest) 'duplicate plans must not create before the reservation is recorded'
        Assert-Equal 30 $heartbeat.data.heartbeat.intervalMinutes 'heartbeat should use a 30-minute interval'
        Assert-Equal 30 $heartbeat.data.heartbeat.rrule.intervalMinutes 'heartbeat should expose the supported interval rule'
        Assert-Equal 'coordinator-thread' $heartbeat.data.heartbeat.targetThreadId 'heartbeat should target the coordinator thread'
        Assert-Equal 'synthetic-session-01' $heartbeat.data.heartbeat.runId 'heartbeat should bind to the coordinator run'
        Assert-True ($heartbeat.data.heartbeat.prompt -like '*Recovery-only check*') 'heartbeat prompt should be recovery-only'
        Assert-True ($heartbeat.data.heartbeat.prompt -like '*Do not treat elapsed time as failure*') 'heartbeat prompt should reject elapsed-time failure'
        $reservedInput = Copy-JsonObject $heartbeatInput; $reservedInput.continuation = $heartbeat.data.continuation
        $reconcile = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $reservedInput 'heartbeat-reconcile'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_heartbeat_creation' $reconcile.data.decision 'a recorded reservation must reconcile before any create retry'
        Assert-True ($null -eq $reconcile.data.automationRequest) 'unresolved creation must not issue a duplicate create request'
        Assert-True (-not $reconcile.data.reservation.createAllowed) 'reconciliation must explicitly prohibit creation'
        $legacyReconciled = Copy-JsonObject $reservedInput; $legacyReconciled.creationReconciled = $true
        $legacyCreate = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $legacyReconciled 'heartbeat-legacy-reconciled'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_heartbeat_creation' $legacyCreate.data.decision 'the obsolete boolean reconciliation flag must not authorize creation'
        Assert-True ($null -eq $legacyCreate.data.automationRequest) 'the obsolete reconciliation flag must not issue a create request'
        $createInput = Copy-JsonObject $reservedInput; $createInput.creationReconciliation = @{ reservationId = [string]$heartbeat.data.continuation.reservationId; outcome = 'not_found'; checkedAtUtc = '2026-10-04T00:00:00Z' }
        $create = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $createInput 'heartbeat-create'),'-StateRoot',$waitRoot)
        Assert-Equal 'create_heartbeat' $create.data.decision 'creation should require an explicit fresh no-existing-monitor reconciliation'
        Assert-Equal 'create' $create.data.automationRequest.mode 'reconciled reservation should issue one create operation'
        Assert-True (-not $create.data.automationRequest.Contains('reservationId')) 'unsupported reservation fields must not be sent to the automation provider'
        Assert-True (-not $create.data.automationRequest.Contains('idempotencyKey')) 'unsupported idempotency fields must not be sent to the automation provider'
        Assert-Equal 'create_pending' $create.data.continuation.state 'a create request must be persisted as pending before the external call'
        Assert-Equal 'thread' $create.data.automationRequest.destination 'heartbeat should be thread-scoped'
        $createRetryInput = Copy-JsonObject $createInput; $createRetryInput.continuation = $create.data.continuation; $createRetryInput.Remove('creationReconciliation')
        $createRetry = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $createRetryInput 'heartbeat-create-retry'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_heartbeat_creation' $createRetry.data.decision 'an interrupted create must require fresh reconciliation before another attempt'
        Assert-True ($null -eq $createRetry.data.automationRequest) 'an interrupted create must not immediately issue a second create'
        $cancelPendingInput = Copy-JsonObject $createRetryInput; $cancelPendingInput.lifecycle = 'cancelled'
        $cancelPending = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $cancelPendingInput 'heartbeat-cancel-pending'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_heartbeat_creation' $cancelPending.data.decision 'cancellation must reconcile an unresolved creation before cleanup'
        Assert-Equal 'create_pending' $cancelPending.data.continuation.state 'cancellation must retain the unresolved creation continuation'
        Assert-True ($null -eq $cancelPending.data.automationRequest) 'cancellation must not forget a possibly-created heartbeat'
        $cancelFoundInput = Copy-JsonObject $cancelPendingInput; $cancelFoundInput.creationReconciliation = @{ reservationId = [string]$cancelPending.data.continuation.reservationId; outcome = 'found'; heartbeatId = 'late-heartbeat'; checkedAtUtc = '2026-10-04T00:01:00Z' }
        $cancelFound = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $cancelFoundInput 'heartbeat-cancel-found'),'-StateRoot',$waitRoot)
        Assert-Equal 'remove_heartbeat' $cancelFound.data.decision 'cancellation should delete a heartbeat found during creation reconciliation'
        Assert-Equal 'late-heartbeat' $cancelFound.data.automationRequest.id 'cleanup must use the reconciled heartbeat ID'
        $cancelNotFoundInput = Copy-JsonObject $cancelPendingInput; $cancelNotFoundInput.creationReconciliation = @{ reservationId = [string]$cancelPending.data.continuation.reservationId; outcome = 'not_found'; checkedAtUtc = '2026-10-04T00:02:00Z' }
        $cancelNotFound = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $cancelNotFoundInput 'heartbeat-cancel-not-found'),'-StateRoot',$waitRoot)
        Assert-Equal 'no_heartbeat' $cancelNotFound.data.decision 'definitive cancellation reconciliation should finish cleanup'
        Assert-Equal 'absent' $cancelNotFound.data.continuation.state 'definitive cancellation reconciliation should clear the creation continuation'
        Assert-True ($null -eq $cancelNotFound.data.reservation) 'definitive cancellation reconciliation should release its reservation'
        $completedNotFoundInput = Copy-JsonObject $cancelNotFoundInput; $completedNotFoundInput.lifecycle = 'completed'
        $completedNotFound = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $completedNotFoundInput 'heartbeat-completed-not-found'),'-StateRoot',$waitRoot)
        Assert-Equal 'no_heartbeat' $completedNotFound.data.decision 'definitive completion reconciliation should finish cleanup'
        Assert-Equal 'absent' $completedNotFound.data.continuation.state 'definitive completion reconciliation should clear the creation continuation'
        $activeContinuation = @{ state = 'active'; heartbeatId = 'heartbeat-1'; scheduleState = 'ACTIVE'; runId = 'synthetic-session-01'; coordinatorThreadId = 'coordinator-thread'; scopeHash = [string]$heartbeat.data.heartbeat.scopeHash }
        $activeInput = @{ runId = 'synthetic-session-01'; coordinatorThreadId = 'coordinator-thread'; scopeHash = [string]$heartbeat.data.heartbeat.scopeHash; continuation = $activeContinuation; notificationPolicy = 'failed_runs_only' }
        $wrongRun = Copy-JsonObject $activeInput; $wrongRun.runId = 'synthetic-session-02'
        $wrongRunResult = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $wrongRun 'heartbeat-wrong-run'),'-StateRoot',$waitRoot) $false
        Assert-True (-not $wrongRunResult.ok) 'a continuation from another run must be rejected before using its heartbeat ID'
        $absentHeartbeat = @{ runId = 'synthetic-session-02'; coordinatorThreadId = 'coordinator-thread'; scopeHash = [string]$heartbeat.data.heartbeat.scopeHash; lifecycle = 'cancelled'; continuation = @{ state = 'absent'; heartbeatId = 'heartbeat-1' } }
        $absentHeartbeatResult = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $absentHeartbeat 'heartbeat-absent-id'),'-StateRoot',$waitRoot) $false
        Assert-True (-not $absentHeartbeatResult.ok) 'an absent continuation must not carry a heartbeat ID across runs'
        $reuse = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $activeInput 'heartbeat-reuse'),'-StateRoot',$waitRoot)
        Assert-Equal 'reuse_heartbeat' $reuse.data.decision 'later plans should reuse the existing session heartbeat'
        Assert-Equal 'view' $reuse.data.automationRequest.mode 'duplicate heartbeat plans should view and reuse the existing automation'
        Assert-Equal 'heartbeat-1' $reuse.data.automationRequest.id 'duplicate heartbeat plans should retain the existing automation ID'
        Assert-True $reuse.data.heartbeat.quietWhenUnchanged 'heartbeat should stay quiet when no worker state changed'
        Assert-True (-not $reuse.data.heartbeat.nestedSchedules) 'heartbeat plan must not create nested schedules'
        $pausedInput = Copy-JsonObject $activeInput; $pausedInput.lifecycle = 'paused'
        $pausedHeartbeat = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $pausedInput 'heartbeat-paused-plan'),'-StateRoot',$waitRoot)
        Assert-Equal 'disable_heartbeat' $pausedHeartbeat.data.decision 'paused runs should disable the heartbeat'
        Assert-Equal 'update' $pausedHeartbeat.data.automationRequest.mode 'paused runs should pause the existing automation'
        Assert-Equal 'PAUSED' $pausedHeartbeat.data.automationRequest.status 'paused runs should pause the existing automation'
        Assert-True $pausedHeartbeat.data.noTickRestart 'paused runs must not restart on a tick'
        Assert-Equal 'ACTIVE' $pausedHeartbeat.data.continuation.scheduleState 'a pause request must retain the last confirmed schedule state'
        Assert-Equal 'PAUSED' $pausedHeartbeat.data.continuation.pendingScheduleState 'a pause request must record its unconfirmed target separately'
        $pauseRetryInput = Copy-JsonObject $pausedInput; $pauseRetryInput.continuation = $pausedHeartbeat.data.continuation
        $pauseRetry = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $pauseRetryInput 'heartbeat-paused-reconcile'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_heartbeat_schedule' $pauseRetry.data.decision 'an unconfirmed pause must reconcile before planning again'
        Assert-True ($null -eq $pauseRetry.data.automationRequest) 'an unconfirmed pause must not be treated as already paused'
        $pauseUnchangedInput = Copy-JsonObject $pauseRetryInput; $pauseUnchangedInput.scheduleConfirmation = @{ confirmed = $true; status = 'ACTIVE'; outcome = 'unchanged' }
        $pauseUnchanged = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $pauseUnchangedInput 'heartbeat-paused-unchanged'),'-StateRoot',$waitRoot)
        Assert-Equal 'confirm_heartbeat_schedule' $pauseUnchanged.data.decision 'a confirmed unchanged pause must clear the pending transition'
        Assert-Equal 'ACTIVE' $pauseUnchanged.data.continuation.scheduleState 'an unchanged pause must retain the provider state'
        Assert-True (-not $pauseUnchanged.data.continuation.Contains('pendingScheduleState')) 'an unchanged pause must clear the stale pending transition'
        Assert-True ($null -eq $pauseUnchanged.data.automationRequest) 'a confirmed failed pause must not replay the update in the confirmation plan'
        $pauseRetryAfterUnchangedInput = Copy-JsonObject $pausedInput; $pauseRetryAfterUnchangedInput.continuation = $pauseUnchanged.data.continuation
        $pauseRetryAfterUnchanged = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $pauseRetryAfterUnchangedInput 'heartbeat-paused-retry-after-unchanged'),'-StateRoot',$waitRoot)
        Assert-Equal 'disable_heartbeat' $pauseRetryAfterUnchanged.data.decision 'a failed pause must be retryable from the confirmed provider state'
        $pauseConfirmInput = Copy-JsonObject $pauseRetryInput; $pauseConfirmInput.scheduleConfirmation = @{ confirmed = $true; status = 'PAUSED' }
        $pauseConfirmed = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $pauseConfirmInput 'heartbeat-paused-confirm'),'-StateRoot',$waitRoot)
        Assert-Equal 'PAUSED' $pauseConfirmed.data.continuation.scheduleState 'a confirmed pause must advance the saved schedule state'
        Assert-True (-not $pauseConfirmed.data.continuation.Contains('pendingScheduleState')) 'a confirmed pause must clear the pending transition'
        $resumedInput = Copy-JsonObject $activeInput; $resumedInput.continuation = $pauseConfirmed.data.continuation; $resumedInput.lifecycle = 'active'
        $resumed = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $resumedInput 'heartbeat-resume'),'-StateRoot',$waitRoot)
        Assert-Equal 'reactivate_heartbeat' $resumed.data.decision 'resuming a run should reactivate the existing paused heartbeat'
        Assert-Equal 'ACTIVE' $resumed.data.automationRequest.status 'resume should issue an ACTIVE update'
        Assert-Equal 'PAUSED' $resumed.data.continuation.scheduleState 'a resume request must retain the last confirmed paused state'
        Assert-Equal 'ACTIVE' $resumed.data.continuation.pendingScheduleState 'a resume request must record its unconfirmed target separately'
        $resumeRetryInput = Copy-JsonObject $resumedInput; $resumeRetryInput.continuation = $resumed.data.continuation
        $resumeRetry = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $resumeRetryInput 'heartbeat-resume-reconcile'),'-StateRoot',$waitRoot)
        Assert-Equal 'reconcile_heartbeat_schedule' $resumeRetry.data.decision 'an unconfirmed resume must reconcile before planning again'
        $resumeConfirmInput = Copy-JsonObject $resumeRetryInput; $resumeConfirmInput.scheduleConfirmation = @{ confirmed = $true; status = 'ACTIVE' }
        $resumeConfirmed = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $resumeConfirmInput 'heartbeat-resume-confirm'),'-StateRoot',$waitRoot)
        Assert-Equal 'ACTIVE' $resumeConfirmed.data.continuation.scheduleState 'a confirmed resume must advance the saved schedule state'
        $completedInput = Copy-JsonObject $activeInput; $completedInput.lifecycle = 'completed'
        $completedHeartbeat = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $completedInput 'heartbeat-completed'),'-StateRoot',$waitRoot)
        Assert-Equal 'remove_heartbeat' $completedHeartbeat.data.decision 'completed runs should remove the existing heartbeat'
    }

    Test-Case 'keep heartbeat lifecycle verification self-contained' {
        $continuation = @{ state = 'active'; runId = 'isolated-run'; coordinatorThreadId = 'isolated-coordinator'; scopeHash = 'isolated-scope'; heartbeatId = 'isolated-heartbeat'; scheduleState = 'ACTIVE' }
        $pausedInput = @{ runId = 'isolated-run'; coordinatorThreadId = 'isolated-coordinator'; scopeHash = 'isolated-scope'; lifecycle = 'paused'; continuation = $continuation }
        $paused = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $pausedInput 'heartbeat-isolated-pause'))
        Assert-Equal 'disable_heartbeat' $paused.data.decision 'isolated lifecycle fixture should plan a pause'
        Assert-Equal 'ACTIVE' $paused.data.continuation.scheduleState 'isolated pause should retain confirmed state'
        Assert-Equal 'PAUSED' $paused.data.continuation.pendingScheduleState 'isolated pause should expose pending state'
        $retryInput = Copy-JsonObject $pausedInput; $retryInput.continuation = $paused.data.continuation
        $retry = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $retryInput 'heartbeat-isolated-reconcile'))
        Assert-Equal 'reconcile_heartbeat_schedule' $retry.data.decision 'isolated pause retry should reconcile before another update'
        $confirmInput = Copy-JsonObject $retryInput; $confirmInput.scheduleConfirmation = @{ confirmed = $true; status = 'PAUSED' }
        $confirmed = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath $confirmInput 'heartbeat-isolated-confirm'))
        Assert-Equal 'PAUSED' $confirmed.data.continuation.scheduleState 'isolated confirmation should advance the schedule state'
        Assert-True (-not $confirmed.data.continuation.Contains('pendingScheduleState')) 'isolated confirmation should clear pending state'
    }

    Test-Case 'preserve sibling dependency epic and pause coordination traces' {
        $traces = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $script:CoordinationTracePath) -AsHashtable -Depth 100
        Assert-Equal 1 $traces.schemaVersion 'coordination trace schema version'
        Assert-Equal 4 @($traces.scenarios).Count 'all coordination regressions should be represented'
        $siblings = @($traces.scenarios | Where-Object name -eq 'two-independent-tickets')[0]
        Assert-True $siblings.expected.siblingsContinue 'one blocked ticket must not stop an independent sibling'
        Assert-Equal 2 $siblings.expected.maxRepositorySlots 'repository capacity must remain bounded'
        $dependency = @($traces.scenarios | Where-Object name -eq 'dependent-ticket')[0]
        Assert-True $dependency.expected.dependencyBlocksChild 'dependent work must wait for its prerequisite'
        Assert-True $dependency.expected.childDispatchAfterParent 'dependent work may dispatch after verified parent acceptance'
        $epic = @($traces.scenarios | Where-Object name -eq 'epic-observer')[0]
        Assert-True $epic.expected.combinedAcceptanceRequired 'epic observation must retain integrated acceptance'
        $pause = @($traces.scenarios | Where-Object name -eq 'pause-and-publication-recovery')[0]
        Assert-True (-not $pause.expected.newDispatchAfterPause) 'pause reconciliation must stop new dispatch'
        Assert-True $pause.expected.uncertainPublicationDoesNotRestartImplementation 'uncertain publication must reconcile rather than restart implementation'
        Assert-True $pause.expected.operationCountIsDescriptive 'operation counts must remain descriptive measurements'
    }

    Test-Case 'delegate verification planning and preserve repository requirements' {
        $verificationRoot = Join-Path $script:FixtureRoot 'verification-state'
        $plan = @{ runId = 'verification-run'; actionId = 'implementation-check'; role = 'implementer'; criteria = @(@{ id = 'criterion-1'; text = 'Preserve behavior.' }); checks = @(@{ id = 'full'; command = 'dotnet test'; criterionIds = @('criterion-1'); kind = 'full_suite'; sharedOutput = $true; serialGroup = 'build-output' }, @{ id = 'ui'; command = 'browser smoke'; criterionIds = @('criterion-1'); kind = 'browser'; sharedOutput = $false }); requirements = @{ fullSuite = $true; visibleBrowser = $true }; uiInteractions = @('Open the saved result and verify the rendered state.') }
        $created = Invoke-PsJson $script:VerificationScript @('-Operation','plan','-InputPath',(New-InputPath $plan 'verification-plan'),'-StateRoot',$verificationRoot)
        Assert-Equal 'implementer' $created.data.ownerRole 'implementer must own verification planning'
        Assert-Equal 2 @($created.data.checkIds).Count 'all planned checks should be durable'
        Assert-Equal 'build-output' @($created.data.sharedOutputGroups)[0] 'shared-output checks should be marked for serialization'
        $validated = Invoke-PsJson $script:VerificationScript @('-Operation','validate-plan','-InputPath',(New-InputPath @{ planReference = $created.data.planReference; requirements = $plan.requirements } 'verification-plan-review'))
        Assert-True $validated.data.valid 'reviewer should be able to assess an adequate worker plan'
        $missingUi = Copy-JsonObject $plan; $missingUi.actionId = 'implementation-check-missing-ui'; $missingUi.uiInteractions = @()
        $missingUiResult = Invoke-PsJson $script:VerificationScript @('-Operation','plan','-InputPath',(New-InputPath $missingUi 'verification-plan-missing-ui'),'-StateRoot',$verificationRoot) $false
        Assert-True (-not $missingUiResult.ok) 'visible-browser requirements must not be silently waived'
        $missingFull = Copy-JsonObject $plan; $missingFull.actionId = 'implementation-check-missing-full'; $missingFull.checks = @(@{ id = 'unit'; command = 'dotnet test --filter Unit'; criterionIds = @('criterion-1') }); $missingFull.requirements = @{ fullSuite = $true }; $missingFull.uiInteractions = @()
        $missingFullCreated = Invoke-PsJson $script:VerificationScript @('-Operation','plan','-InputPath',(New-InputPath $missingFull 'verification-plan-missing-full'),'-StateRoot',$verificationRoot)
        $missingFullReview = Invoke-PsJson $script:VerificationScript @('-Operation','validate-plan','-InputPath',(New-InputPath @{ planReference = $missingFullCreated.data.planReference } 'verification-plan-review-missing-full')) $false
        Assert-True (-not $missingFullReview.ok) 'reviewer adequacy checks must retain mandatory full-suite requirements'
    }

    Test-Case 'validate optional repository-owned smoke entry points' {
        $validSmoke = @{ smoke = @{ command = 'pwsh ./smoke.ps1'; setupCommand = 'pwsh ./setup.ps1'; cleanupCommand = 'pwsh ./cleanup.ps1'; workingDirectory = $script:FixtureRoot; requiredCapabilities = @('browser'); disposable = $true }; availableCapabilities = @('browser','https') }
        $valid = Invoke-PsJson $script:VerificationScript @('-Operation','validate-smoke','-InputPath',(New-InputPath $validSmoke 'smoke-valid'))
        Assert-True $valid.data.valid 'existing smoke entry point should validate'
        Assert-True (-not $valid.data.executes) 'generic validation must not start application services'
        $missingCleanup = Copy-JsonObject $validSmoke; $null = $missingCleanup.smoke.Remove('cleanupCommand')
        $missingCleanupResult = Invoke-PsJson $script:VerificationScript @('-Operation','validate-smoke','-InputPath',(New-InputPath $missingCleanup 'smoke-missing-cleanup')) $false
        Assert-True (-not $missingCleanupResult.ok) 'setup without cleanup must be rejected'
        $missingCapability = Copy-JsonObject $validSmoke; $missingCapability.availableCapabilities = @('https')
        $missingCapabilityResult = Invoke-PsJson $script:VerificationScript @('-Operation','validate-smoke','-InputPath',(New-InputPath $missingCapability 'smoke-missing-capability')) $false
        Assert-True (-not $missingCapabilityResult.ok) 'unavailable smoke capability must remain a worker blocker'
        $failedSetup = Copy-JsonObject $validSmoke; $failedSetup.observedSetupExitCode = 1
        $failedSetupResult = Invoke-PsJson $script:VerificationScript @('-Operation','validate-smoke','-InputPath',(New-InputPath $failedSetup 'smoke-failed-setup')) $false
        Assert-True (-not $failedSetupResult.ok) 'failed setup must be reported rather than treated as smoke success'
    }

    Test-Case 'reuse verification evidence only with matching provenance' {
        $evidencePath = Join-Path $script:FixtureRoot 'reuse-evidence.json'
        $reuseLogPath = Join-Path $script:FixtureRoot 'reuse-evidence.log'; [IO.File]::WriteAllText($reuseLogPath, 'validated reuse log', [Text.UTF8Encoding]::new($false)); $reuseLogHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $reuseLogPath).Hash.ToLowerInvariant()
        $record = @{ schemaVersion = 1; evidenceId = 'ev-reuse'; actionId = 'check-1'; runId = 'run-reuse'; ticketKey = 'project:1:issue:1'; scopeHash = 'scope-reuse'; checkedRevision = 'head-1'; capturedAtUtc = '2026-09-30T00:00:00Z'; evidenceKind = 'check'; outcome = 'passed'; actualExitCode = 0; assertionReportedPassed = $null; acceptedAsCheckPass = $true; log = @{ path = $reuseLogPath; sha256 = $reuseLogHash; bytes = ([IO.FileInfo]::new($reuseLogPath)).Length }; coverage = @{ revision = 'head-1'; baseSha = 'base-1'; environmentHash = 'env-1'; dependenciesHash = 'deps-1'; files = @('src/app.cs') } }
        $recordJson = $record | ConvertTo-Json -Depth 100 -Compress
        $recordHashBytes = [Security.Cryptography.SHA256]::Create(); try { $recordHash = ([Convert]::ToHexString($recordHashBytes.ComputeHash([Text.Encoding]::UTF8.GetBytes($recordJson)))).ToLowerInvariant() } finally { $recordHashBytes.Dispose() }
        Write-JsonFile @{ recordJson = $recordJson; recordSha256 = $recordHash } $evidencePath
        $reference = @{ path = $evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $evidencePath).Hash.ToLowerInvariant() }
        $current = @{ revision = 'head-1'; baseSha = 'base-1'; environmentHash = 'env-1'; dependenciesHash = 'deps-1'; changedKind = 'code'; changedPaths = @('src/app.cs') }
        $exact = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ evidenceReferences = @($reference); current = $current } 'reuse-exact'))
        Assert-True $exact.data.reusable 'exact revision evidence should be reusable'
        Assert-True ([string](@($exact.data.evidence)[0].capturedAtUtc) -match '2026') 'reused evidence must preserve its original timestamp'
        $docs = Copy-JsonObject $current; $docs.revision = 'head-2'; $docs.changedKind = 'documentation_only'; $docs.changedPaths = @('docs/readme.md')
        $docsResult = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ evidenceReferences = @($reference); current = $docs } 'reuse-docs'))
        Assert-Equal 'documentation_only_inputs_unchanged' @($docsResult.data.evidence)[0].reason 'docs-only reuse should identify its justification'
        $code = Copy-JsonObject $docs; $code.changedKind = 'code'; $code.changedPaths = @('src/app.cs')
        $codeResult = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ evidenceReferences = @($reference); current = $code } 'reuse-code'))
        Assert-True (-not $codeResult.data.reusable) 'changed source inputs must invalidate reuse'
        $unchanged = Copy-JsonObject $current; $unchanged.changedKind = 'unchanged'; $unchanged.changedPaths = @(); $unchangedResult = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ evidenceReferences = @($reference); current = $unchanged } 'reuse-unchanged'))
        Assert-True $unchangedResult.data.reusable 'exact-revision reuse must allow an explicit empty changed-path set'
    }

    Test-Case 'classify documentation conservatively and preserve Unicode Git paths' {
        $repo = Join-Path $script:FixtureRoot 'documentation-classifier-repo'; New-Item -ItemType Directory -Path $repo -Force | Out-Null; $null = & git init -b master $repo; & git -C $repo config user.name 'Synthetic Test'; & git -C $repo config user.email 'test@example.invalid'
        [IO.File]::WriteAllText((Join-Path $repo 'app.txt'), 'base', [Text.UTF8Encoding]::new($false)); & git -C $repo add --all; $null = & git -C $repo commit --quiet -m 'classifier base'; $base = ((& git -C $repo rev-parse HEAD).Trim())
        New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $repo 'docs/runtime.cs'), 'public static class Runtime {}', [Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText((Join-Path $repo 'docs/README.json'), '{"runtime":true}', [Text.UTF8Encoding]::new($false)); & git -C $repo add --all; $null = & git -C $repo commit --quiet -m 'classifier source and config'; $codeHead = ((& git -C $repo rev-parse HEAD).Trim())
        [IO.File]::WriteAllText((Join-Path $repo 'docs/guía.md'), '# guide', [Text.UTF8Encoding]::new($false)); & git -C $repo add --all; $null = & git -C $repo commit --quiet -m 'classifier Unicode documentation'; $docsHead = ((& git -C $repo rev-parse HEAD).Trim())
        function New-ClassifierEvidence {
            param([string] $EvidencePath, [string] $EvidenceId, [string] $CheckedRevision, [string] $BaseSha, [string[]] $Files)
            $logPath = [IO.Path]::ChangeExtension($EvidencePath, '.log'); [IO.File]::WriteAllText($logPath, 'synthetic classifier evidence', [Text.UTF8Encoding]::new($false)); $logHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $logPath).Hash.ToLowerInvariant()
            $record = @{ schemaVersion = 1; evidenceId = $EvidenceId; actionId = 'classifier-check'; runId = 'classifier-run'; ticketKey = 'project:1:issue:1'; scopeHash = 'classifier-scope'; checkedRevision = $CheckedRevision; capturedAtUtc = '2026-09-30T00:00:00Z'; evidenceKind = 'check'; outcome = 'passed'; actualExitCode = 0; assertionReportedPassed = $null; acceptedAsCheckPass = $true; log = @{ path = $logPath; sha256 = $logHash; bytes = ([IO.FileInfo]::new($logPath)).Length }; coverage = @{ revision = $CheckedRevision; baseSha = $BaseSha; environmentHash = 'env'; dependenciesHash = 'deps'; files = $Files } }
            $recordJson = $record | ConvertTo-Json -Depth 100 -Compress; $hashAlgorithm = [Security.Cryptography.SHA256]::Create(); try { $recordHash = ([Convert]::ToHexString($hashAlgorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($recordJson)))).ToLowerInvariant() } finally { $hashAlgorithm.Dispose() }; Write-JsonFile @{ recordJson = $recordJson; recordSha256 = $recordHash } $EvidencePath
            return @{ path = $EvidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $EvidencePath).Hash.ToLowerInvariant(); evidenceId = $EvidenceId }
        }
        $staleReference = New-ClassifierEvidence (Join-Path $script:FixtureRoot 'classifier-stale.json') 'ev-classifier-stale' $base $base @('app.txt')
        $codeCurrent = @{ fromRevision = $base; revision = $codeHead; baseSha = $base; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'code'; changedPaths = @('docs/runtime.cs','docs/README.json') }
        $staleCode = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ repositoryPath = $repo; evidenceReferences = @($staleReference); current = $codeCurrent } 'classifier-stale-code'))
        Assert-True (-not $staleCode.data.reusable) 'stale evidence must not be reused after source or config changes inside docs'
        Assert-Equal 'changed_inputs' @($staleCode.data.evidence)[0].reason 'honest code changes inside docs must not be mislabeled as documentation'
        $misclassifiedCode = Copy-JsonObject $codeCurrent; $misclassifiedCode.changedKind = 'documentation_only'; $misclassified = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ repositoryPath = $repo; evidenceReferences = @($staleReference); current = $misclassifiedCode } 'classifier-misclassified-code'))
        Assert-Equal 'current_change_set_mismatch' @($misclassified.data.evidence)[0].reason 'source and config files inside docs must invalidate a documentation-only claim'
        $freshReference = New-ClassifierEvidence (Join-Path $script:FixtureRoot 'classifier-fresh.json') 'ev-classifier-fresh' $codeHead $base @('app.txt','docs/runtime.cs','docs/README.json')
        $freshCode = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ repositoryPath = $repo; evidenceReferences = @($freshReference); current = $codeCurrent } 'classifier-fresh-code'))
        Assert-True $freshCode.data.reusable 'fresh evidence for an honest code change inside docs should be accepted'
        $docsCurrent = @{ fromRevision = $codeHead; revision = $docsHead; baseSha = $base; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'documentation_only'; changedPaths = @('docs/guía.md') }
        $unicodeDocs = Invoke-PsJson $script:VerificationScript @('-Operation','reuse-evidence','-InputPath',(New-InputPath @{ repositoryPath = $repo; evidenceReferences = @($freshReference); current = $docsCurrent } 'classifier-unicode-docs'))
        Assert-True $unicodeDocs.data.reusable 'NUL-delimited Git paths must preserve non-ASCII documentation names'
        Assert-Equal 'docs/guía.md' @($unicodeDocs.data.evidence)[0].intervalPaths[0] 'Git interval output must retain the original Unicode path'
    }

    Test-Case 'verify worker-owned validation handoff regressions' {
        $traces = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $script:VerificationTracePath) -AsHashtable -Depth 100
        Assert-Equal 1 $traces.schemaVersion 'verification trace schema version'
        $handoff = @($traces.scenarios | Where-Object name -eq 'implementation-review-correction')[0]
        Assert-Equal 0 $handoff.expected.coordinatorEngineeringActions 'coordinator must not execute engineering actions'
        Assert-True $handoff.expected.sameWorkerIds 'corrections must remain in the same worker chats'
        Assert-True $handoff.expected.technicalFindingBlocks 'technical findings must remain blocking'
        $ui = @($traces.scenarios | Where-Object name -eq 'seeded-ui-is-not-a-click')[0]
        Assert-True (-not $ui.expected.freshUiEvidence) 'seeded state must not be relabeled as a click'
        Assert-True $ui.expected.requiresActualInteraction 'missing UI interaction must return to the worker'
        $stop = @($traces.scenarios | Where-Object name -eq 'intentional-host-stop')[0]
        Assert-True (-not $stop.expected.countsAsCheckPass) 'intentional host stop must never become a check pass'
        Assert-True $stop.expected.rawExitPreserved 'raw host exit must remain evidence'
        $sequencing = @($traces.scenarios | Where-Object name -eq 'shared-output-sequencing')[0]
        Assert-True $sequencing.expected.buildsSerialized 'checks sharing outputs must serialize'
        Assert-True $sequencing.expected.independentReadMayBatch 'independent reads may be batched'
    }

    Test-Case 'record phase timing with an injected clock' {
        $measureRoot = Join-Path $script:FixtureRoot 'measure-state'
        $base = '2026-09-30T00:00:00Z'
        $events = @(
            @{ eventId = 'evt-dispatch'; runId = 'measure-run'; eventKind = 'dispatch'; phase = 'implementing'; atUtc = $base; workerReportedDurationSeconds = $null },
            @{ eventId = 'evt-observed'; runId = 'measure-run'; eventKind = 'result_observed'; phase = 'implementing'; atUtc = '2026-09-30T00:00:10Z'; workerReportedDurationSeconds = 5 },
            @{ eventId = 'evt-receipt'; runId = 'measure-run'; eventKind = 'receipt_accepted'; phase = 'reviewing'; atUtc = '2026-09-30T00:00:20Z' }
        )
        $expectedRegistryEventCount = 0; foreach ($event in $events) { $record = Copy-JsonObject $event; $record.stallAfterMinutes = 0.1; $saved = Invoke-PsJson $script:MeasureScript @('-Operation','record-phase','-InputPath',(New-InputPath $record "measure-$($event.eventId)"),'-StateRoot',$measureRoot); $expectedRegistryEventCount++; Assert-Equal $expectedRegistryEventCount $saved.data.registryEventCount 'record-phase must report the actual retained registry event count' }
        $summary = Invoke-PsJson $script:MeasureScript @('-Operation','summarize-timing','-InputPath',(New-InputPath @{ runId = 'measure-run' } 'measure-summary'),'-StateRoot',$measureRoot)
        Assert-Equal 10 $summary.data.dispatchToObservationSeconds 'observation latency should use supplied event times'
        Assert-Equal 10 $summary.data.observationToReceiptSeconds 'receipt latency should be separate from worker duration'
        Assert-Equal 5 @($summary.data.workerReportedDurations)[0].seconds 'worker-reported duration must remain separate'
        Assert-True ($summary.data.unknownWorkerDurationCount -gt 0) 'unreported worker duration must remain unknown'
        Assert-True (Test-Path -LiteralPath (Join-Path $measureRoot 'measurement-audit.ndjson')) 'append-only measurement audit should be retained'
        $stallRoot = Join-Path $script:FixtureRoot 'measure-stall-state'; $stallEvents = @(@{ eventId = 'stall-dispatch'; runId = 'stall-run'; eventKind = 'dispatch'; phase = 'implementing'; actionId = 'action-a'; atUtc = '2026-09-30T00:00:00Z' }, @{ eventId = 'stall-wait-1'; runId = 'stall-run'; eventKind = 'wait'; phase = 'implementing'; actionId = 'action-a'; atUtc = '2026-09-30T00:01:00Z' }, @{ eventId = 'stall-wait-2'; runId = 'stall-run'; eventKind = 'wait'; phase = 'implementing'; actionId = 'action-a'; atUtc = '2026-09-30T00:02:00Z' }, @{ eventId = 'stall-wait-3'; runId = 'stall-run'; eventKind = 'wait'; phase = 'implementing'; actionId = 'action-a'; atUtc = '2026-09-30T00:03:00Z' }); $lastStall = $null; foreach($event in $stallEvents){$record=Copy-JsonObject $event;$record.stallAfterMinutes=2;$lastStall=Invoke-PsJson $script:MeasureScript @('-Operation','record-phase','-InputPath',(New-InputPath $record "stall-$($event.eventId)"),'-StateRoot',$stallRoot)}; Assert-True (@($lastStall.data.alerts).Count -gt 0) 'unchanged waits must not reset the actual-progress stall clock'
    }

    Test-Case 'import cumulative usage without inventing deltas or cost' {
        $snapshots = @(
            @{ streamId = 'implementer-1'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-29T23:50:00Z'; counters = @{ inputTokens = 100; cachedInputTokens = 40; outputTokens = 20; reasoningTokens = 5 } },
            @{ streamId = 'implementer-1'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-30T00:00:00Z'; counters = @{ inputTokens = 150; cachedInputTokens = 60; outputTokens = 30; reasoningTokens = 8 } },
            @{ streamId = 'implementer-1'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-30T00:00:10Z'; counters = @{ inputTokens = 150; cachedInputTokens = 60; outputTokens = 30; reasoningTokens = 8 } },
            @{ streamId = 'implementer-1'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-30T00:00:20Z'; counters = @{ inputTokens = 10; cachedInputTokens = 2; outputTokens = 3; reasoningTokens = 1 } },
            @{ streamId = 'implementer-1'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-30T00:10:00Z'; counters = @{ inputTokens = 20; cachedInputTokens = 4; outputTokens = 5; reasoningTokens = 2 } },
            @{ streamId = 'implementer-1'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-10-01T00:00:00Z'; counters = @{ inputTokens = 40; cachedInputTokens = 8; outputTokens = 9; reasoningTokens = 3 } }
        )
        $input = @{ startedAtUtc = '2026-09-30T00:00:00Z'; endedAtUtc = '2026-09-30T00:20:00Z'; source = 'synthetic-usage-export'; snapshots = $snapshots }
        $imported = Invoke-PsJson $script:MeasureScript @('-Operation','import-usage','-InputPath',(New-InputPath $input 'usage-import'))
        Assert-Equal 0 $imported.data.duplicateSnapshots 'snapshots at distinct times must not be conflated as duplicates'
        Assert-Equal '00:00:10' ([DateTime]::Parse([string]@($imported.data.roles[0].deltas)[0].atUtc).ToString('HH:mm:ss')) 'the exact start sample must be a baseline, not a pre-run delta'
        $straddling = @{ startedAtUtc = '2026-09-30T00:00:00Z'; endedAtUtc = '2026-09-30T00:10:00Z'; snapshots = @(@{ streamId = 's'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-29T23:50:00Z'; counters = @{ inputTokens = 100; cachedInputTokens = 40; outputTokens = 20; reasoningTokens = 5 } }, @{ streamId = 's'; role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-30T00:05:00Z'; counters = @{ inputTokens = 200; cachedInputTokens = 80; outputTokens = 40; reasoningTokens = 10 } }) }; $straddlingResult = Invoke-PsJson $script:MeasureScript @('-Operation','import-usage','-InputPath',(New-InputPath $straddling 'usage-straddling')); Assert-True $straddlingResult.data.roles[0].unknown 'a boundary-straddling interval without an exact start sample must remain unknown'; Assert-Equal 1 $straddlingResult.data.boundarySamplesUnknown 'boundary uncertainty must be explicit'
        $legacySnapshots = @{ startedAtUtc = '2026-09-30T00:00:00Z'; endedAtUtc = '2026-09-30T00:10:00Z'; snapshots = @(@{ role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; atUtc = '2026-09-30T00:00:00Z'; counters = @{ inputTokens = 1; cachedInputTokens = 0; outputTokens = 1; reasoningTokens = 0 } }) }; $legacyResult = Invoke-PsJson $script:MeasureScript @('-Operation','import-usage','-InputPath',(New-InputPath $legacySnapshots 'usage-legacy')); Assert-Equal 'legacy-single-stream' $legacyResult.data.streamIdAdapter 'unambiguous old exports may use the explicit legacy adapter'; $ambiguousLegacy = Copy-JsonObject $legacySnapshots; $ambiguousLegacy.snapshots += @{ role = 'reviewer'; model = 'gpt-6.1-sol'; effort = 'high'; atUtc = '2026-09-30T00:00:01Z'; counters = @{ inputTokens = 1; cachedInputTokens = 0; outputTokens = 1; reasoningTokens = 0 } }; $ambiguousResult = Invoke-PsJson $script:MeasureScript @('-Operation','import-usage','-InputPath',(New-InputPath $ambiguousLegacy 'usage-legacy-ambiguous')) $false; Assert-True (-not $ambiguousResult.ok) 'ambiguous legacy usage exports must fail closed'
        Assert-Equal 1 $imported.data.postRunSnapshots 'post-run samples must be flagged, not attributed'
        Assert-True (@($imported.data.roles)[0].segments -gt 1) 'counter reset must start a new segment'
        Assert-True $imported.data.missingUsageIsUnknown 'missing usage is not zero'
        $usage = @{ role = 'implementer'; model = 'gpt-5.6-luna'; effort = 'xhigh'; inputTokens = 1000; cachedInputTokens = 400; outputTokens = 100; reasoningIncludedInOutput = $true }
        $cost = Invoke-PsJson $script:MeasureScript @('-Operation','cost-report','-InputPath',(New-InputPath @{ usage = @($usage); rates = @{ 'gpt-5.6-luna' = @{ effectiveAtUtc = '2026-09-30T00:00:00Z'; inputPerMillion = 1; cachedInputPerMillion = 0.5; outputPerMillion = 2; reasoningIncludedInOutput = $true; source = 'synthetic-2026-09-30' } } } 'cost-report'))
        Assert-True ($null -ne @($cost.data.usage)[0].apiEstimateUsd) 'explicit dated rates may produce an API estimate'
        Assert-True $cost.data.rawTokensAreNotCost 'raw processing volume must not be presented as cost'
        Assert-True (-not $cost.data.actualCostAvailable) 'unattributed actual consumption must remain unavailable'
    }

    Test-Case 'compare equivalent runs without a raw-token optimization gate' {
        $common = @{ scopeHash = 'scope'; repositoryRequirementsHash = 'requirements'; profilesHash = 'profiles' }
        $manual = Copy-JsonObject $common; $manual.name = 'manual'; $manual.quality = 'accepted'; $manual.acceptedDefects = 0; $manual.wallClockSeconds = 120; $manual.totalTokens = 200; $manual.usage = @{ implementer = 150; coordinator = 50 }; $manual.coordinationActions = 20; $manual.repairCounts = @{ format = 1 }; $manual.actualCost = $null
        $automated = Copy-JsonObject $common; $automated.name = 'automated'; $automated.quality = 'accepted'; $automated.acceptedDefects = 0; $automated.wallClockSeconds = 100; $automated.totalTokens = 300; $automated.usage = @{ implementer = 250; coordinator = 50 }; $automated.coordinationActions = 8; $automated.repairCounts = @{ format = 0 }
        $report = Invoke-PsJson $script:MeasureScript @('-Operation','comparison-report','-InputPath',(New-InputPath @{ runs = @($manual,$automated) } 'comparison-report'))
        Assert-True $report.data.comparable 'equivalent scope and profiles should allow comparison'
        Assert-Equal 100 $report.data.rawTokenDifference 'report may show raw usage without making it a gate'
        Assert-True $report.data.rawTokenReductionIsNotAReleaseGate 'higher raw usage must not fail acceptance'
        $different = Copy-JsonObject $automated; $different.profilesHash = 'different-profile'
        $incomparable = Invoke-PsJson $script:MeasureScript @('-Operation','comparison-report','-InputPath',(New-InputPath @{ runs = @($manual,$different) } 'comparison-incomparable'))
        Assert-True (-not $incomparable.data.comparable) 'different worker profiles must be disclosed as incomparable'
    }

    Test-Case 'replay sanitized ticket-loop audit regressions offline' {
        $scenario = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $script:AcceptanceScenarioPath) -AsHashtable -Depth 100
        $scenarioReference = @{ path = $script:AcceptanceScenarioPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:AcceptanceScenarioPath).Hash.ToLowerInvariant() }
        $replay = Invoke-PsJson $script:AcceptanceScript @('-Operation','replay','-InputPath',(New-InputPath @{ scenarioReference = $scenarioReference } 'acceptance-replay'))
        Assert-True $replay.data.offline 'audit replay must be fixture-only'
        Assert-Equal 0 $replay.data.coordinatorEngineeringActions 'replay must prove coordinator-only orchestration'
        Assert-True $replay.data.publicationBlockedByMaterialEvidence 'unresolved material evidence must block publication'
        Assert-Equal 0 $replay.data.unchangedWaitMutations 'unchanged waits must remain quiet'
        $bad = Copy-JsonObject $scenario; $bad.events += @{ kind = 'prompt'; fullReceiptCopied = $true }
        $badResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','replay','-InputPath',(New-InputPath $bad 'acceptance-replay-bad')) $false
        Assert-True (-not $badResult.ok) 'full receipt copying must fail replay acceptance'
        $unstable = Copy-JsonObject $scenario; $unstable.actions += @{ actor = 'implementer'; class = 'engineering'; operation = 'correct'; workerId = 'replacement-implementer' }
        $unstableResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','replay','-InputPath',(New-InputPath $unstable 'acceptance-replay-unstable')) $false
        Assert-True (-not $unstableResult.ok) 'replay must derive worker identity stability from actual actions'
        $badEnum = Copy-JsonObject $scenario; $badEnum.events += @{ kind = 'finding'; findingId = 'F3'; severity = 'high'; disposition = 'resolved' }
        $badEnumResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','replay','-InputPath',(New-InputPath $badEnum 'acceptance-replay-enum')) $false
        Assert-True (-not $badEnumResult.ok) 'replay must reject receipt enum mismatches instead of trusting declared flags'
    }

    Test-Case 'verify legacy compatibility and deliberate trial plan' {
        $records = @{ records = @(@{ schemaVersion = 1; ticketKey = 'project:1:issue:1'; phase = 'paused'; receipt = @{ recordId = 'receipt-1'; verdict = 'blocked' }; evidence = @(@{ evidenceId = 'ev-1'; outcome = 'failed' }); uncertainAction = $true; actionReconciled = $false }, @{ schemaVersion = 2; ticketKey = 'project:1:issue:2'; phase = 'reviewing'; receipt = @{ recordId = 'receipt-2'; verdict = 'pass' }; evidence = @(@{ evidenceId = 'ev-2'; outcome = 'passed' }) }) }
        $compatible = Invoke-PsJson $script:AcceptanceScript @('-Operation','compatibility','-InputPath',(New-InputPath $records 'acceptance-compatibility'))
        Assert-True $compatible.data.compatible 'supported v1 and v2 records should remain compatible'
        Assert-True ($compatible.data.actualRunMigrated -eq $false) 'compatibility tests must not migrate the actual audited run'
        $unsupported = @{ records = @(@{ schemaVersion = 99; ticketKey = 'project:1:issue:3'; phase = 'queued' }) }
        $unsupportedResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','compatibility','-InputPath',(New-InputPath $unsupported 'acceptance-unsupported')) $false
        Assert-True (-not $unsupportedResult.ok) 'unsupported records must fail closed'
        $trial = @{ ticketKey = 'project:1:issue:42'; repository = 'TaigaMCP'; workerProfiles = @{ implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } }; authorization = @{ createChats = $true; messageWorkers = $true }; stopConditions = @('pause before publication unless separately authorized') }
        $trialResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','trial-plan','-InputPath',(New-InputPath $trial 'acceptance-trial-plan'))
        Assert-True $trialResult.data.ready 'future trial plan should be explicit and executable by native tools'
        Assert-True (-not $trialResult.data.executes) 'reading or validating a trial plan must not start operations'
        Assert-True (-not $trialResult.data.automaticMerge) 'automatic merge must remain disabled'
    }

    Test-Case 'report offline acceptance separately from host and publication gates' {
        $report = Invoke-PsJson $script:AcceptanceScript @('-Operation','acceptance-report','-InputPath',(New-InputPath @{ offlineGates = @($true,$true,$true); actualHostVerified = $false; publicationVerified = $false; qualityEvidence = 'synthetic'; costEvidence = 'unknown' } 'acceptance-report'))
        Assert-True $report.data.offlineAccepted 'all offline gates should be accepted'
        Assert-True (-not $report.data.actualHostVerified) 'actual host should remain visibly pending'
        Assert-True (-not $report.data.overallOperationalAcceptance) 'pending host/publication gates must prevent operational acceptance'
        Assert-True $report.data.rawTokensAreNotAcceptanceGate 'raw tokens must not be a release gate'
    }

    Test-Case 'capture immutable verification evidence and classify outcomes' {
        $evidenceRoot = Join-Path $script:FixtureRoot 'evidence state'
        $worktree = Join-Path $script:FixtureRoot 'evidence worktree'
        New-Item -ItemType Directory -Path $worktree -Force | Out-Null
        $null = & git -C $worktree init --quiet
        Assert-Equal 0 $LASTEXITCODE 'fixture worktree should initialize'
        $null = & git -C $worktree config user.name 'Automation Fixture'
        $null = & git -C $worktree config user.email 'automation@example.invalid'
        [IO.File]::WriteAllText((Join-Path $worktree 'fixture.txt'), 'synthetic committed source', [Text.UTF8Encoding]::new($false))
        $null = & git -C $worktree add --all
        $null = & git -C $worktree commit --quiet -m 'Create evidence fixture'
        Assert-Equal 0 $LASTEXITCODE 'fixture source should commit'
        $null = & git -C $worktree branch -M 'codex/evidence-fixture'
        Assert-Equal 0 $LASTEXITCODE 'fixture branch should be set'
        $baseSha = (& git -C $worktree rev-parse HEAD).Trim()

        $contextPath = Join-Path $script:FixtureRoot 'evidence ticket context.md'
        [IO.File]::WriteAllText($contextPath, 'Synthetic evidence packet context.', [Text.UTF8Encoding]::new($false))
        $packetRequest = @{
            packetId = 'evidence-packet'; sessionId = 'synthetic-session-01'; runId = 'evidence-run-01'
            ticket = @{ ticketKey = 'project:123:issue:456'; projectId = 123; kind = 'issue'; id = 456; ref = 7; title = 'Evidence fixture' }
            contextPath = $contextPath
            criteria = @(@{ id = 'criterion-01'; text = 'Keep evidence tied to the committed result.' })
            repository = @{ identity = 'evidence-repo'; repositoryPath = $worktree; worktreePath = $worktree; branch = 'codex/evidence-fixture'; baseSha = $baseSha }
            requiredCommands = @('dotnet test -c Debug'); unresolvedRequirements = @()
            authority = @{ authorizedActions = @('run local checks'); excludedActions = @('publish') }
            deadline = @{ startedAtUtc = '2026-09-30T12:00:00Z'; deadlineUtc = '2026-09-30T14:00:00Z'; elapsedBudgetMinutes = 120 }
            profiles = @{ coordinator = @{ model = 'gpt-6.1-sol'; effort = 'high' }; implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } }
        }
        $packetCreated = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $packetRequest 'evidence-packet-create'),'-StateRoot',$evidenceRoot)
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$evidenceRoot)
        $claimRequest = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; repositoryIdentity = 'evidence-repo'; repositoryPath = $worktree; scopeHash = $packetCreated.data.scopeHash; expectedRevision = $init.revision }
        $claimed = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claimRequest 'evidence-ticket-claim'),'-StateRoot',$evidenceRoot)
        $revision = [pscustomobject]@{ value = $claimed.revision }
        $stateScriptPath = $script:StateScript
        $evidenceScriptPath = $script:EvidenceScript
        $fixtureDirectory = $script:FixtureRoot
        $packetData = $packetCreated.data
        $prepareAction = {
            param([string] $ActionId, [string] $ActionKind, [string] $Command)
            $request = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; actionId = $ActionId; actionKind = $ActionKind; input = @{ command = $Command; workingDirectory = $worktree; criterionIds = @('criterion-01') }; expectedRevision = $revision.value }
            $prepared = Invoke-PsJson $stateScriptPath @('-Operation','prepare-action','-InputPath',(New-InputPath $request "evidence-$ActionId"),'-StateRoot',$evidenceRoot)
            $revision.value = $prepared.revision
            return $prepared
        }.GetNewClosure()
        $captureAction = {
            param([string] $ActionId, [string] $ActionKind, [long] $ExitCode, [bool] $AssertionPassed = $true)
            $action = & $prepareAction $ActionId $ActionKind 'dotnet test -c Debug'
            $metadataRequest = @{ packetPath = $packetData.packetPath; packetHash = $packetData.packetHash; actionId = $ActionId }
            $metadata = Invoke-PsJson $evidenceScriptPath @('-Operation','initialize-run','-InputPath',(New-InputPath $metadataRequest "metadata-$ActionId"),'-StateRoot',$evidenceRoot)
            $logPath = Join-Path $fixtureDirectory "${ActionId}.log"
            [IO.File]::WriteAllText($logPath, "Synthetic log for $ActionId with result $ExitCode.", [Text.UTF8Encoding]::new($false))
            $captureRequest = @{ metadataPath = $metadata.data.metadataPath; actualExitCode = $ExitCode; logPath = $logPath }
            if ($action.data.action.kind -eq 'assertion') { $captureRequest.assertionPassed = $AssertionPassed }
            return Invoke-PsJson $evidenceScriptPath @('-Operation','capture','-InputPath',(New-InputPath $captureRequest "capture-$ActionId"),'-StateRoot',$evidenceRoot)
        }.GetNewClosure()

        $shutdown = & $captureAction 'shutdown-action' 'intentional_host_shutdown' 1
        Assert-Equal 1 $shutdown.data.evidence.actualExitCode 'intentional shutdown must retain raw exit 1'
        Assert-Equal 'intentional_stop_failed' $shutdown.data.evidence.outcome 'shutdown failure must remain separate from test pass'
        Assert-True (-not $shutdown.data.evidence.acceptedAsCheckPass) 'intentional stop cannot become a passing check'
        Assert-Equal 'gpt-5.6-luna' $shutdown.data.evidence.profile.model 'profile must come from the packet'
        Assert-Equal 'shutdown-action' $shutdown.data.evidence.actionId 'action ID must come from the prepared registry action'
        Assert-Equal 'criterion-01' $shutdown.data.evidence.criterionIds[0] 'criterion IDs must be checked against packet metadata'
        Assert-Equal 'Keep evidence tied to the committed result.' $shutdown.data.evidence.criteria[0].text 'criterion text must come from the packet'
        Assert-Equal 'codex/evidence-fixture' $shutdown.data.evidence.repository.branch 'branch must come from Git metadata'
        Assert-Equal $baseSha $shutdown.data.evidence.repository.baseSha 'base SHA must come from the assignment packet'
        Assert-Equal $baseSha $shutdown.data.evidence.checkedRevision 'checked SHA must come from the committed worktree'
        Assert-Equal $packetCreated.data.packetHash $shutdown.data.evidence.packetHash 'packet binding must be copied from trusted metadata'
        $capturedAt = [DateTimeOffset]::MinValue
        Assert-True ([DateTimeOffset]::TryParse($shutdown.data.evidence.capturedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$capturedAt)) 'timestamp must be generated from the helper clock'
        Assert-True (Test-Path -LiteralPath $shutdown.data.evidence.log.path -PathType Leaf) 'large log should live in the external evidence store'

        $failedCheck = & $captureAction 'failed-check-action' 'implementation_check' 1
        Assert-Equal 'failed' $failedCheck.data.evidence.outcome 'genuine nonzero check must be a failure'
        $expectedRed = & $captureAction 'expected-red-failure-action' 'expected_red_fixture' 1
        Assert-Equal 'expected_red_failure' $expectedRed.data.evidence.outcome 'expected-red fixture failure must be classified separately'
        $unexpectedRedPass = & $captureAction 'expected-red-pass-action' 'expected_red_fixture' 0
        Assert-Equal 'unexpected_pass' $unexpectedRedPass.data.evidence.outcome 'an expected-red fixture that passes must be visible as unexpected'
        $assertion = & $captureAction 'assertion-action' 'assertion' 0 $true
        Assert-Equal 'assertion_passed' $assertion.data.evidence.outcome 'structured passing assertions have their own outcome'
        $passedCheck = & $captureAction 'passing-check-action' 'implementation_check' 0
        Assert-Equal 'passed' $passedCheck.data.evidence.outcome 'zero-exit checks should count as passed'

        $summaryRequest = @{
            evidencePaths = @($shutdown.data.evidencePath, $failedCheck.data.evidencePath, $expectedRed.data.evidencePath, $unexpectedRedPass.data.evidencePath, $assertion.data.evidencePath, $passedCheck.data.evidencePath)
            reportedOnly = @(@{ name = 'workerReportedTestCount'; value = $null; source = 'worker summary'; reportedAtUtc = '2026-09-30T13:00:00Z' })
        }
        $summary = Invoke-PsJson $script:EvidenceScript @('-Operation','summarize','-InputPath',(New-InputPath $summaryRequest 'evidence-summary'),'-StateRoot',$evidenceRoot)
        Assert-Equal 1 $summary.data.computed.checksPassed 'summary should count structured passing checks'
        Assert-Equal 1 $summary.data.computed.checksFailed 'summary should count structured failing checks'
        Assert-Equal 1 $summary.data.computed.expectedRedFailures 'expected-red results must have their own count'
        Assert-Equal 1 $summary.data.computed.expectedRedUnexpectedPasses 'unexpected expected-red passes must have their own count'
        Assert-Equal 1 $summary.data.computed.intentionalShutdownFailures 'intentional stop errors must remain visible'
        Assert-Equal 'reported_only' $summary.data.reportedOnly[0].status 'unknown counts must remain reported-only'
        Assert-Equal 'worker summary' $summary.data.reportedOnly[0].source 'reported count provenance must be preserved'

        $shutdownLogPath = $shutdown.data.evidence.log.path
        $originalLog = [IO.File]::ReadAllText($shutdownLogPath)
        [IO.File]::WriteAllText($shutdownLogPath, $originalLog + 'tampered', [Text.UTF8Encoding]::new($false))
        $tamperedLog = Invoke-PsJson $script:EvidenceScript @('-Operation','validate','-EvidencePath',$shutdown.data.evidencePath,'-StateRoot',$evidenceRoot) $false
        Assert-True (-not $tamperedLog.ok) 'tampered external log must fail its content hash'
        [IO.File]::WriteAllText($shutdownLogPath, $originalLog, [Text.UTF8Encoding]::new($false))

        $missingLogBackup = Join-Path $script:FixtureRoot 'missing-log-backup.tmp'
        [IO.File]::Copy($shutdownLogPath, $missingLogBackup, $false)
        Remove-Item -LiteralPath $shutdownLogPath -Force
        $missingLog = Invoke-PsJson $script:EvidenceScript @('-Operation','validate','-EvidencePath',$shutdown.data.evidencePath,'-StateRoot',$evidenceRoot) $false
        [IO.File]::Copy($missingLogBackup, $shutdownLogPath, $false)
        Remove-Item -LiteralPath $missingLogBackup -Force
        Assert-True (-not $missingLog.ok) 'missing external log must block evidence validation'

        $missingResult = Invoke-PsJson $script:EvidenceScript @('-Operation','validate','-EvidencePath',(Join-Path $script:FixtureRoot 'missing-evidence.json'),'-StateRoot',$evidenceRoot) $false
        Assert-True (-not $missingResult.ok) 'missing evidence files must fail validation'
        $tamperedEnvelope = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $failedCheck.data.evidencePath) -AsHashtable -Depth 100
        $tamperedRecord = ConvertFrom-Json -InputObject $tamperedEnvelope.recordJson -AsHashtable -Depth 100
        $tamperedRecord.actualExitCode = 0
        $tamperedEnvelope.recordJson = ConvertTo-Json -InputObject $tamperedRecord -Depth 100 -Compress
        Write-JsonFile $tamperedEnvelope $failedCheck.data.evidencePath
        $tamperedResult = Invoke-PsJson $script:EvidenceScript @('-Operation','validate','-EvidencePath',$failedCheck.data.evidencePath,'-StateRoot',$evidenceRoot) $false
        Assert-True (-not $tamperedResult.ok) 'tampered evidence record must fail hash verification'
        $registryText = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'registry.json')
        Assert-True (-not $registryText.Contains('Synthetic log for')) 'large log content must stay outside the registry'
    }

    Test-Case 'create immutable scope packets bound to context and checkout' {
        $packetStateRoot = Join-Path $script:FixtureRoot 'packet-state'
        $packetWorktree = Join-Path $script:FixtureRoot 'packet worktree'
        New-Item -ItemType Directory -Path $packetWorktree -Force | Out-Null
        $contextPath = Join-Path $script:FixtureRoot 'long ticket context.md'
        $contextText = 'Synthetic full ticket context. ' + ('long-description ' * 12000)
        [IO.File]::WriteAllText($contextPath, $contextText, [Text.UTF8Encoding]::new($false))
        $request = @{
            packetId = 'packet-01'; sessionId = 'session-packet-01'; runId = 'run-packet-01'
            ticket = @{ ticketKey = 'project:123:issue:456'; projectId = 123; kind = 'issue'; id = 456; ref = 7; title = 'Synthetic scoped work' }
            contextPath = $contextPath
            criteria = @(@{ id = 'criterion-02'; text = 'Preserve an explicit null distinction.' }, @{ id = 'criterion-01'; text = 'Keep the selected ticket identity.' })
            repository = @{ identity = 'synthetic-repo'; repositoryPath = $packetWorktree; worktreePath = $packetWorktree; branch = 'codex/issue-7-fixture'; baseSha = ('a' * 40) }
            requiredCommands = @('dotnet test -c Debug')
            unresolvedRequirements = @()
            authority = @{ authorizedActions = @('create worker chats'); excludedActions = @('automatic merge') }
            deadline = @{ startedAtUtc = '2026-09-30T12:00:00Z'; deadlineUtc = '2026-09-30T14:00:00Z'; elapsedBudgetMinutes = 120 }
            profiles = @{ coordinator = @{ model = 'gpt-6.1-sol'; effort = 'high' }; implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } }
        }
        $requestPath = New-InputPath $request 'packet-create'
        $created = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',$requestPath,'-StateRoot',$packetStateRoot)
        $packet = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $created.data.packetPath) -AsHashtable -Depth 100
        Assert-Equal 1 $packet.schemaVersion 'packet schema version'
        Assert-Equal 'criterion-01' $packet.criteria[0].id 'criteria must be sorted by stable ordinal ID'
        Assert-Equal 'criterion-02' $packet.criteria[1].id 'all criteria must be retained'
        Assert-True (Test-Path -LiteralPath $created.data.fullContextPath -PathType Leaf) 'full context must be copied to the durable state root'
        Assert-Equal $packet.fullContext.sha256 (Get-FileHash -LiteralPath $created.data.fullContextPath -Algorithm SHA256 | ForEach-Object { $_.Hash.ToLowerInvariant() }) 'context artifact hash'
        $packetText = Get-Content -Raw -LiteralPath $created.data.packetPath
        Assert-True (-not $packetText.Contains('long-description long-description')) 'packet must reference rather than embed the full context'
        Assert-True (-not ([IO.Path]::GetFullPath($created.data.packetPath).StartsWith([IO.Path]::GetFullPath($packetWorktree), [StringComparison]::OrdinalIgnoreCase))) 'packet must remain outside source changes'
        $verified = Invoke-PsJson $script:PacketScript @('-Operation','validate','-PacketPath',$created.data.packetPath,'-ExpectedRunId','run-packet-01','-ExpectedTicketKey','project:123:issue:456','-ExpectedWorktreePath',$packetWorktree)
        Assert-True $verified.data.valid 'packet should validate against its exact checkout'
        $wrongCheckout = Invoke-PsJson $script:PacketScript @('-Operation','validate','-PacketPath',$created.data.packetPath,'-ExpectedWorktreePath',$script:FixtureRoot) $false
        Assert-True (-not $wrongCheckout.ok) 'packet must reject a different checkout binding'
        $unresolvedRequest = Copy-JsonObject $request; $unresolvedRequest.packetId = 'packet-unresolved'; $unresolvedRequest.unresolvedRequirements = @('Confirm whether the legacy status remains selectable.')
        $unresolved = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $unresolvedRequest 'packet-unresolved'),'-StateRoot',$packetStateRoot)
        $unresolvedPacket = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $unresolved.data.packetPath) -AsHashtable -Depth 100
        Assert-Equal 'Confirm whether the legacy status remains selectable.' $unresolvedPacket.unresolvedRequirements[0] 'unresolved product requirements must be preserved for clarification'
        $duplicate = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',$requestPath,'-StateRoot',$packetStateRoot) $false
        Assert-True (-not $duplicate.ok) 'packet IDs must be immutable and not overwritten'
        $missingCriteria = Copy-JsonObject $request; $missingCriteria.packetId = 'packet-no-criteria'; $missingCriteria.criteria = @()
        $missing = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $missingCriteria 'packet-missing-criteria'),'-StateRoot',$packetStateRoot) $false
        Assert-True (-not $missing.ok) 'packet creation must reject missing criteria'
        $missingTicket = Copy-JsonObject $request; $missingTicket.packetId = 'packet-no-ticket-id'; $null = $missingTicket.ticket.Remove('id')
        $missingTicketResult = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $missingTicket 'packet-missing-ticket-id'),'-StateRoot',$packetStateRoot) $false
        Assert-True (-not $missingTicketResult.ok) 'packet creation must reject incomplete ticket scope'
        $wrongProfile = Copy-JsonObject $request; $wrongProfile.packetId = 'packet-wrong-profile'; $wrongProfile.profiles.reviewer.model = 'gpt-6-sol'
        $profileResult = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $wrongProfile 'packet-wrong-profile'),'-StateRoot',$packetStateRoot) $false
        Assert-True (-not $profileResult.ok) 'packet creation must reject a substituted reviewer profile'
        $missingContext = Copy-JsonObject $request; $missingContext.packetId = 'packet-missing-context'; $missingContext.contextPath = Join-Path $script:FixtureRoot 'inaccessible-context.md'
        $contextResult = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $missingContext 'packet-missing-context'),'-StateRoot',$packetStateRoot) $false
        Assert-True (-not $contextResult.ok) 'packet creation must reject inaccessible context'
        $blockedRoot = Join-Path $script:FixtureRoot 'packet-root-is-a-file'; [IO.File]::WriteAllText($blockedRoot, 'fixture')
        $inaccessible = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',$requestPath,'-StateRoot',$blockedRoot) $false
        Assert-True (-not $inaccessible.ok) 'packet creation must reject an inaccessible durable output root'
        $inaccessiblePacket = Invoke-PsJson $script:PacketScript @('-Operation','validate','-PacketPath',(Join-Path $packetStateRoot 'missing-packet.json')) $false
        Assert-True (-not $inaccessiblePacket.ok) 'packet validation must reject an inaccessible packet path'
        $tampered = Copy-JsonObject $packet; $tampered.ticket.title = 'Changed after creation'
        Write-JsonFile $tampered $created.data.packetPath
        $tamperedResult = Invoke-PsJson $script:PacketScript @('-Operation','validate','-PacketPath',$created.data.packetPath) $false
        Assert-True (-not $tamperedResult.ok) 'packet validation must reject edited contents'
    }

    Test-Case 'preflight exact profiles, equivalent browser capability, and authority' {
        $ticketKey = 'project:123:issue:456'
        $preflight = @{
            schemaVersion = 1; selectedTicketKey = $ticketKey
            profiles = @{ coordinator = @{ model = 'gpt-6.1-sol'; effort = 'high' }; implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } }
            observedCoordinatorProfile = @{ model = 'gpt-6.1-sol'; effort = 'high' }
            availableProfiles = @(@{ model = 'gpt-5.6-luna'; efforts = @('xhigh') }, @{ model = 'gpt-6.1-sol'; efforts = @('high') })
            capabilities = @{ ordinaryChats = $true; workerMessaging = $true; boundedWait = $true; managedWorktrees = $true; browserProviders = @('edge') }
            requiredCapabilities = @('ordinaryChats','workerMessaging','boundedWait','managedWorktrees','browser')
            authorization = @{ granted = $true; ticketKey = $ticketKey; authorizedActions = @('createOrReuseChats','messageWorkers','createWorktrees','writeTaiga','pushAndCreatePr') }
            requiredActions = @('createOrReuseChats','messageWorkers','createWorktrees','writeTaiga','pushAndCreatePr')
        }
        $ready = Invoke-PsJson $script:PreflightScript @('-Operation','validate','-InputPath',(New-InputPath $preflight 'preflight-ready'))
        Assert-True $ready.data.ready 'available exact profiles and required capabilities should pass preflight'
        Assert-Equal 'edge' $ready.data.browserCapability.providers[0] 'an equivalent available browser should satisfy the generic browser requirement'
        Assert-True (-not $ready.data.browserCapability.smokeTestPerformed) 'coordinator preflight must not run a browser smoke test'
        $unavailableProfile = Copy-JsonObject $preflight; $unavailableProfile.availableProfiles = @(@{ model = 'gpt-5.6-luna'; efforts = @('xhigh') })
        $unavailable = Invoke-PsJson $script:PreflightScript @('-Operation','validate','-InputPath',(New-InputPath $unavailableProfile 'preflight-profile-unavailable'))
        Assert-True (-not $unavailable.data.ready) 'an unavailable exact reviewer profile must block without fallback'
        Assert-Equal 'exact_profile_unavailable' $unavailable.data.blockers[0].category 'missing exact profile reason'
        $missingAuthority = Copy-JsonObject $preflight; $null = $missingAuthority.Remove('authorization')
        $authorityResult = Invoke-PsJson $script:PreflightScript @('-Operation','validate','-InputPath',(New-InputPath $missingAuthority 'preflight-authority'))
        Assert-True (-not $authorityResult.data.ready) 'missing operational authority must block the requested actions'
        Assert-Equal 5 $authorityResult.data.missingAuthorizedActions.Count 'all missing external actions should be reported'
    }

    Test-Case 'coordinator role traces keep engineering work with workers' {
        $traceDocument = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $script:RoleTracePath) -AsHashtable -Depth 100
        Assert-Equal 1 $traceDocument.schemaVersion 'role trace schema version'
        $coordinatorClasses = @('metadata_read','provider_read','worker_request','bounded_wait','receipt_read','scope_capture','correction_route','authorization_block')
        foreach ($scenario in $traceDocument.scenarios) {
            Assert-True (@($scenario.actions).Count -gt 0) "scenario must have actions: $($scenario.name)"
            foreach ($action in $scenario.actions) {
                if ($action.actor -eq 'coordinator') {
                    Assert-True ($coordinatorClasses -contains $action.class) "coordinator action must be orchestration-only: $($scenario.name)/$($action.operation)"
                    Assert-True ($action.operation -notmatch '(?i)read_source|inspect_diff|review_code|run_test|diagnos|smoke_test|technical_finding') "coordinator trace must not require engineering work: $($scenario.name)/$($action.operation)"
                }
                if ($action.class -eq 'engineering') { Assert-True ($action.actor -in @('implementer','reviewer')) "engineering operation must belong to a worker: $($scenario.name)/$($action.operation)" }
            }
        }
        $normal = @($traceDocument.scenarios | Where-Object name -eq 'normal-review-correction-and-user-scope-change')[0]
        Assert-Equal 'gpt-5.6-luna' $normal.workers.implementerModel 'implementer profile must stay exact through correction'
        Assert-Equal 'xhigh' $normal.workers.implementerEffort 'implementer effort must stay exact through correction'
        Assert-Equal 'gpt-6.1-sol' $normal.workers.reviewerModel 'reviewer profile must stay exact through correction'
        Assert-Equal 'high' $normal.workers.reviewerEffort 'reviewer effort must stay exact through correction'
        $implementationTargets = @($normal.actions | Where-Object { $_.operation -in @('dispatch_implementation','route_review_finding','route_new_scope_to_same_implementer') } | ForEach-Object { $_.workerId } | Select-Object -Unique)
        $reviewTargets = @($normal.actions | Where-Object { $_.operation -in @('dispatch_review','dispatch_updated_revision_for_review') } | ForEach-Object { $_.workerId } | Select-Object -Unique)
        Assert-Equal 1 $implementationTargets.Count 'implementation thread must remain stable across corrections'
        Assert-Equal $normal.workers.implementerThreadId $implementationTargets[0] 'implementation actions must target the original thread'
        Assert-Equal 1 $reviewTargets.Count 'reviewer thread must remain stable across review rounds'
        Assert-Equal $normal.workers.reviewerThreadId $reviewTargets[0] 'review actions must target the original thread'
        $actions = @($normal.actions)
        $userChangeIndex = -1; $newScopeIndex = -1; $newRouteIndex = -1; $oldScopePacketId = $null
        for ($index = 0; $index -lt $actions.Count; $index++) {
            if ($actions[$index].operation -eq 'clarify_changed_requirement') { $userChangeIndex = $index }
            if ($actions[$index].operation -eq 'capture_scope' -and $actions[$index].scopeHash -eq 'scope-v1') { $oldScopePacketId = $actions[$index].packetId }
            if ($actions[$index].operation -eq 'capture_scope' -and $actions[$index].scopeHash -eq 'scope-v2') { $newScopeIndex = $index }
            if ($actions[$index].operation -eq 'route_new_scope_to_same_implementer') { $newRouteIndex = $index }
        }
        Assert-True ($userChangeIndex -ge 0 -and $newScopeIndex -gt $userChangeIndex -and $newRouteIndex -gt $newScopeIndex) 'changed requirements must be captured before correction dispatch'
        Assert-True ($actions[$newScopeIndex].packetId -ne $oldScopePacketId) 'a changed scope must use a new immutable packet'
        $blocked = @($traceDocument.scenarios | Where-Object name -eq 'blocked-unavailable-exact-review-profile')[0]
        Assert-Equal 0 @($blocked.actions | Where-Object { $_.class -eq 'worker_request' }).Count 'unavailable exact profile must block dispatch without fallback'
        $failedCheck = @($traceDocument.scenarios | Where-Object name -eq 'blocked-failed-check-routed-to-producing-worker')[0]
        Assert-True (@($failedCheck.actions | Where-Object operation -eq 'route_failed_check_to_producer' | ForEach-Object workerId) -contains $failedCheck.workers.implementerThreadId) 'failed check evidence must route to its producing implementer'
    }

    Test-Case 'initialize and recover a Unicode state registry' {
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$stateRoot)
        Assert-Equal 1 $init.revision 'initial revision'
        Assert-Equal 'gpt-6.1-sol' $init.data.session.config.reviewerProfile.model 'reviewer model'
        $inspect = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$stateRoot)
        Assert-True $inspect.ok 'inspect should succeed'
        [IO.File]::AppendAllText((Join-Path $stateRoot 'notes.txt'), '✓ λ')
    }

    Test-Case 'migrate legacy duplicated ticket claims safely' {
        $legacyRoot = Join-Path $script:FixtureRoot 'legacy-state'
        New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
        $legacyTicket = [ordered]@{ ticketKey = 'project:1:story:10'; ownerSessionId = 'legacy-session'; ownerGeneration = 1; phase = 'queued'; ownedChildTicketKeys = @('project:1:task:11'); repositoryIdentity = 'legacy-repo' }
        $legacy = [ordered]@{ schemaVersion = 1; revision = 4; createdAt = '2026-01-01T00:00:00Z'; updatedAt = '2026-01-01T00:00:00Z'; sessions = @{}; tickets = [ordered]@{ 'project:1:story:10' = $legacyTicket; 'project:1:task:11' = (Copy-JsonObject $legacyTicket) }; repositories = [ordered]@{ 'legacy-repo' = @{ slotOwners = @('project:1:task:11') } }; actions = [ordered]@{ 'legacy-action' = @{ ticketKey = 'project:1:task:11'; status = 'observed' } }; events = @() }
        [IO.File]::WriteAllText((Join-Path $legacyRoot 'registry.json'), ($legacy | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $migrated = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$legacyRoot)
        Assert-Equal 2 $migrated.data.registry.schemaVersion 'legacy registry schema should migrate'
        Assert-Equal 1 @($migrated.data.registry.tickets.Keys).Count 'legacy duplicate tickets should collapse'
        Assert-Equal 'project:1:story:10' $migrated.data.registry.ticketAliases.'project:1:task:11' 'legacy child alias should resolve'
        Assert-Equal 'project:1:story:10' $migrated.data.registry.actions.'legacy-action'.ticketKey 'legacy action should resolve through the canonical ticket'
        Assert-Equal 'project:1:story:10' $migrated.data.registry.repositories.'legacy-repo'.slotOwners[0] 'legacy slot owner should resolve through the canonical ticket'
        $persisted = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath (Join-Path $legacyRoot 'registry.json')) -AsHashtable -Depth 100
        Assert-Equal 2 $persisted.schemaVersion 'migration should persist the new schema'
        $divergentRoot = Join-Path $script:FixtureRoot 'legacy-divergent'
        New-Item -ItemType Directory -Path $divergentRoot -Force | Out-Null
        $divergent = Copy-JsonObject $legacy; $divergent.tickets.'project:1:task:11'.phase = 'implementing'
        [IO.File]::WriteAllText((Join-Path $divergentRoot 'registry.json'), ($divergent | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $divergentRoot 'registry.json.bak'), ($legacy | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $divergentResult = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$divergentRoot) $false
        Assert-True (-not $divergentResult.ok) 'divergent legacy duplicates must require manual recovery'
        $primaryAfterConflict = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath (Join-Path $divergentRoot 'registry.json')) -AsHashtable -Depth 100
        Assert-Equal 1 $primaryAfterConflict.schemaVersion 'migration conflict must preserve the primary snapshot'
    }

    Test-Case 'claim ticket, reserve two slots, and reject overflow' {
        $claimA = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; repositoryIdentity = 'synthetic-repo'; expectedRevision = 1 }
        $claimAPath = New-InputPath $claimA 'claim-a'
        $a = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',$claimAPath,'-StateRoot',$stateRoot)
        $claimB = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:457'; repositoryIdentity = 'synthetic-repo'; expectedRevision = $a.revision }
        $b = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claimB 'claim-b'),'-StateRoot',$stateRoot)
        $reserveA = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = $claimA.ticketKey; expectedRevision = $b.revision }
        $ra = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath $reserveA 'reserve-a'),'-StateRoot',$stateRoot)
        $reserveB = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = $claimB.ticketKey; expectedRevision = $ra.revision }
        $rb = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath $reserveB 'reserve-b'),'-StateRoot',$stateRoot)
        $claimC = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:458'; repositoryIdentity = 'synthetic-repo'; expectedRevision = $rb.revision }
        $c = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claimC 'claim-c'),'-StateRoot',$stateRoot)
        $reserveC = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = $claimC.ticketKey; expectedRevision = $c.revision }
        $overflow = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath $reserveC 'reserve-c'),'-StateRoot',$stateRoot) $false
        Assert-True (-not $overflow.ok) 'third repository slot must be rejected'
        $stale = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = $claimA.ticketKey; expectedRevision = 1 }) 'stale'),'-StateRoot',$stateRoot) $false
        Assert-True (-not $stale.ok) 'stale revision must be rejected'
    }

    Test-Case 'enforce lifecycle, action reconciliation, and cursor uniqueness' {
        $inspect = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$stateRoot); $revision = $inspect.revision
        $transition = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; toPhase = 'preparing'; expectedRevision = $revision }
        $preparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath $transition 'preparing'),'-StateRoot',$stateRoot)
        $implementing = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; toPhase = 'implementing'; expectedRevision = $preparing.revision }
        $impl = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath $implementing 'implementing'),'-StateRoot',$stateRoot)
        $action = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; actionId = 'worker-message-01'; actionKind = 'send_worker_message'; target = @{ threadId = 'worker-a' }; input = @{ marker = 'synthetic' }; expectedRevision = $impl.revision }
        $prepared = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath $action 'action'),'-StateRoot',$stateRoot)
        $observed = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'worker-message-01'; observationStatus = 'uncertain'; reconcileRequired = $true; expectedRevision = $prepared.revision }
        $uncertain = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath $observed 'uncertain'),'-StateRoot',$stateRoot)
        Assert-True $uncertain.data.reconciliationRequired 'uncertain outcome must require reconciliation'
        $consumed = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; cursor = 'cursor-1'; result = @{ completed = $false }; expectedRevision = $uncertain.revision }
        $result = Invoke-PsJson $script:StateScript @('-Operation','consume-result','-InputPath',(New-InputPath $consumed 'result'),'-StateRoot',$stateRoot)
        $duplicate = Invoke-PsJson $script:StateScript @('-Operation','consume-result','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; cursor = 'cursor-1'; expectedRevision = $result.revision }) 'duplicate'),'-StateRoot',$stateRoot) $false
        Assert-True (-not $duplicate.ok) 'duplicate worker result must be rejected'
        $pause = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; reason = 'fixture pause'; expectedRevision = $result.revision }
        $paused = Invoke-PsJson $script:StateScript @('-Operation','pause-intent','-InputPath',(New-InputPath $pause 'pause'),'-StateRoot',$stateRoot)
        $resume = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; expectedRevision = $paused.revision }
        $resumed = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath $resume 'resume'),'-StateRoot',$stateRoot)
        Assert-Equal 'implementing' (Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$stateRoot)).data.registry.tickets.'project:123:issue:456'.phase 'resume phase'
        $hashA = [ordered]@{ first = 1; nested = [ordered]@{ b = 2; a = 1 } }
        $hashB = [ordered]@{ nested = [ordered]@{ a = 1; b = 2 }; first = 1 }
        $digestA = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; actionId = 'hash-action-a'; actionKind = 'hash-test'; input = $hashA; expectedRevision = $resumed.revision }) 'hash-action-a'),'-StateRoot',$stateRoot)
        $digestB = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; actionId = 'hash-action-b'; actionKind = 'hash-test'; input = $hashB; expectedRevision = $digestA.revision }) 'hash-action-b'),'-StateRoot',$stateRoot)
        Assert-Equal $digestA.data.action.inputDigest $digestB.data.action.inputDigest 'equivalent input must hash identically across helper processes'
        $shapeArray = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; actionId = 'shape-action-array'; actionKind = 'hash-test'; input = @{ items = @('a') }; expectedRevision = $digestB.revision }) 'shape-action-array'),'-StateRoot',$stateRoot)
        $shapeScalar = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:456'; actionId = 'shape-action-scalar'; actionKind = 'hash-test'; input = @{ items = 'a' }; expectedRevision = $shapeArray.revision }) 'shape-action-scalar'),'-StateRoot',$stateRoot)
        Assert-True ($shapeArray.data.action.inputDigest -ne $shapeScalar.data.action.inputDigest) 'array and scalar payloads must hash differently'
        $observedA = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'hash-action-a'; observationStatus = 'observed'; expectedRevision = $shapeScalar.revision }) 'hash-observed-a'),'-StateRoot',$stateRoot)
        $observedB = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'hash-action-b'; observationStatus = 'observed'; expectedRevision = $observedA.revision }) 'hash-observed-b'),'-StateRoot',$stateRoot)
        $observedC = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'shape-action-array'; observationStatus = 'observed'; expectedRevision = $observedB.revision }) 'shape-observed-array'),'-StateRoot',$stateRoot)
        $null = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'shape-action-scalar'; observationStatus = 'observed'; expectedRevision = $observedC.revision }) 'shape-observed-scalar'),'-StateRoot',$stateRoot)
    }

    Test-Case 'enforce canonical aliases, fencing, and quiescent controls' {
        $controlRoot = Join-Path $script:FixtureRoot 'control-state'
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$controlRoot)
        $missingPrecondition = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ticketKey = 'project:1:story:10'; repositoryIdentity = 'control-repo'; expectedRevision = $init.revision }) 'missing-owner-generation'),'-StateRoot',$controlRoot) $false
        Assert-True (-not $missingPrecondition.ok) 'owner generation is mandatory for mutations'
        $claim = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:story:10'; childTicketKeys = @('project:1:task:11'); repositoryIdentity = 'control-repo'; expectedRevision = $init.revision }
        $claimed = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claim 'canonical-claim'),'-StateRoot',$controlRoot)
        $snapshot = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$controlRoot)
        Assert-Equal 1 @($snapshot.data.registry.tickets.Keys).Count 'parent ticket must be stored once'
        Assert-Equal 'project:1:story:10' $snapshot.data.registry.ticketAliases.'project:1:task:11' 'child alias must resolve to parent'
        $reserved = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; expectedRevision = $claimed.revision }) 'canonical-reserve'),'-StateRoot',$controlRoot)
        $pause = Invoke-PsJson $script:StateScript @('-Operation','pause-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; reason = 'fixture'; expectedRevision = $reserved.revision }) 'canonical-pause'),'-StateRoot',$controlRoot)
        $dispatchBlocked = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; expectedRevision = $pause.revision }) 'paused-reserve'),'-StateRoot',$controlRoot) $false
        Assert-True (-not $dispatchBlocked.ok) 'pause intent must block slot dispatch'
        $notQuiescent = Invoke-PsJson $script:StateScript @('-Operation','reconcile-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; intent = 'pause'; quiescent = $false; expectedRevision = $pause.revision }) 'not-quiescent'),'-StateRoot',$controlRoot) $false
        Assert-True (-not $notQuiescent.ok) 'pause must wait for quiescence'
        $reconciled = Invoke-PsJson $script:StateScript @('-Operation','reconcile-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; intent = 'pause'; quiescent = $true; expectedRevision = $pause.revision }) 'reconcile-pause'),'-StateRoot',$controlRoot)
        $pausedSnapshot = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$controlRoot)
        Assert-Equal 'paused' $pausedSnapshot.data.registry.tickets.'project:1:story:10'.phase 'reconcile must set the canonical phase'
        Assert-True (-not $pausedSnapshot.data.registry.tickets.'project:1:story:10'.slotReserved) 'reconcile must release a quiescent slot'
        $resumed = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; expectedRevision = $reconciled.revision }) 'canonical-resume'),'-StateRoot',$controlRoot)
        $released = Invoke-PsJson $script:StateScript @('-Operation','release-ticket','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:task:11'; expectedRevision = $resumed.revision }) 'canonical-release'),'-StateRoot',$controlRoot)
        $releasedSnapshot = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$controlRoot)
        Assert-True (-not $releasedSnapshot.data.registry.ticketAliases.ContainsKey('project:1:task:11')) 'release must remove child aliases'
    }

    Test-Case 'retain reservations until uncertain actions reconcile' {
        $actionRoot = Join-Path $script:FixtureRoot 'action-control'
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$actionRoot)
        $claim = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:20'; repositoryIdentity = 'action-repo'; expectedRevision = $init.revision }) 'action-claim'),'-StateRoot',$actionRoot)
        $reserved = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:20'; expectedRevision = $claim.revision }) 'action-reserve'),'-StateRoot',$actionRoot)
        $prepared = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:20'; actionId = 'uncertain-01'; actionKind = 'provider-write'; input = @{ marker = 'pending' }; expectedRevision = $reserved.revision }) 'action-prepare'),'-StateRoot',$actionRoot)
        $pause = Invoke-PsJson $script:StateScript @('-Operation','pause-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:20'; expectedRevision = $prepared.revision }) 'action-pause'),'-StateRoot',$actionRoot)
        $blocked = Invoke-PsJson $script:StateScript @('-Operation','reconcile-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:20'; intent = 'pause'; quiescent = $true; expectedRevision = $pause.revision }) 'action-reconcile-blocked'),'-StateRoot',$actionRoot) $false
        Assert-True (-not $blocked.ok) 'pending action must block reconciliation'
        $pendingSnapshot = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$actionRoot)
        Assert-True $pendingSnapshot.data.registry.tickets.'project:1:issue:20'.slotReserved 'pending action must retain its slot'
        $wrongOwner = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 2; actionId = 'uncertain-01'; observationStatus = 'observed'; expectedRevision = $pause.revision }) 'wrong-action-owner'),'-StateRoot',$actionRoot) $false
        Assert-True (-not $wrongOwner.ok) 'stale action observation must be rejected'
        $observed = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'uncertain-01'; observationStatus = 'observed'; expectedRevision = $pause.revision }) 'action-observed'),'-StateRoot',$actionRoot)
        $reconciled = Invoke-PsJson $script:StateScript @('-Operation','reconcile-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:20'; intent = 'pause'; quiescent = $true; expectedRevision = $observed.revision }) 'action-reconcile'),'-StateRoot',$actionRoot)
        $final = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$actionRoot)
        Assert-Equal 'paused' $final.data.registry.tickets.'project:1:issue:20'.phase 'reconciled action should permit pause'
        Assert-True (-not $final.data.registry.tickets.'project:1:issue:20'.slotReserved) 'reconciled action should release the slot'
    }

    Test-Case 'keep session controls during ticket-scoped resume' {
        $sessionControlRoot = Join-Path $script:FixtureRoot 'session-control'
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$sessionControlRoot)
        $claimA = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:30'; repositoryIdentity = 'session-repo'; expectedRevision = $init.revision }) 'session-claim-a'),'-StateRoot',$sessionControlRoot)
        $claimB = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:31'; repositoryIdentity = 'session-repo'; expectedRevision = $claimA.revision }) 'session-claim-b'),'-StateRoot',$sessionControlRoot)
        $pause = Invoke-PsJson $script:StateScript @('-Operation','pause-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; reason = 'session pause'; expectedRevision = $claimB.revision }) 'session-pause'),'-StateRoot',$sessionControlRoot)
        $ticketResumeDuringPause = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:30'; expectedRevision = $pause.revision }) 'ticket-resume-during-pause'),'-StateRoot',$sessionControlRoot) $false
        Assert-True (-not $ticketResumeDuringPause.ok) 'ticket resume must not clear session pause'
        $siblingActionDuringPause = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:31'; actionId = 'session-pause-sibling'; actionKind = 'worker-message'; expectedRevision = $pause.revision }) 'sibling-action-during-pause'),'-StateRoot',$sessionControlRoot) $false
        Assert-True (-not $siblingActionDuringPause.ok) 'session pause must block sibling actions'
        $resumed = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; expectedRevision = $pause.revision }) 'session-resume'),'-StateRoot',$sessionControlRoot)
        $cancel = Invoke-PsJson $script:StateScript @('-Operation','cancel-intent','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; reason = 'session cancel'; expectedRevision = $resumed.revision }) 'session-cancel'),'-StateRoot',$sessionControlRoot)
        $ticketResumeDuringCancel = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:30'; expectedRevision = $cancel.revision }) 'ticket-resume-during-cancel'),'-StateRoot',$sessionControlRoot) $false
        Assert-True (-not $ticketResumeDuringCancel.ok) 'ticket resume must not clear session cancellation'
        $siblingActionDuringCancel = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:31'; actionId = 'session-cancel-sibling'; actionKind = 'worker-message'; expectedRevision = $cancel.revision }) 'sibling-action-during-cancel'),'-StateRoot',$sessionControlRoot) $false
        Assert-True (-not $siblingActionDuringCancel.ok) 'session cancellation must block sibling actions'
        $null = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; expectedRevision = $cancel.revision }) 'session-resume-after-cancel'),'-StateRoot',$sessionControlRoot)
    }

    Test-Case 'recover from a truncated primary snapshot' {
        $statePath = Join-Path $stateRoot 'registry.json'; [IO.File]::WriteAllText($statePath, '{"schemaVersion":')
        $recovered = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$stateRoot)
        Assert-True $recovered.recovered 'backup should be used after primary truncation'
    }

    Test-Case 'validate dependency and epic planning rules' {
        $plan = @{ scope = @(@{ projectId = 1; kind = 'story'; id = 10; repository = 'r' }, @{ projectId = 1; kind = 'story'; id = 11; repository = 'r' }); dependencies = @(@{ ticketKey = 'project:1:story:11'; dependsOn = 'project:1:story:10' }) }
        $valid = Invoke-PsJson $script:PlanScript @('-Operation','validate-scope','-InputPath',(New-InputPath $plan 'scope'))
        Assert-True $valid.data.valid 'valid scope should pass'
        $cycle = @{ scope = $plan.scope; dependencies = @(@{ ticketKey = 'project:1:story:10'; dependsOn = 'project:1:story:11' }, @{ ticketKey = 'project:1:story:11'; dependsOn = 'project:1:story:10' }) }
        $cycleResult = Invoke-PsJson $script:PlanScript @('-Operation','validate-scope','-InputPath',(New-InputPath $cycle 'cycle'))
        Assert-True (-not $cycleResult.data.valid) 'cycle should be blocked'
        $epic = @{ requiredStories = @(@{ projectId = 1; kind = 'story'; id = 10; repository = 'r'; completion = 'merged' }) }
        $epicResult = Invoke-PsJson $script:PlanScript @('-Operation','validate-epic','-InputPath',(New-InputPath $epic 'epic'))
        Assert-True $epicResult.data.complete 'merged required story should complete synthetic epic'
    }

    Test-Case 'bound review corrections and reject stale approvals' {
        $receipt = New-ReviewReceipt 'changes_requested'
        $receipt.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix'; disposition = 'open' })
        $request = @{ receipt = $receipt; expectedCriteria = $script:ReviewCriteria; currentSha = 'head'; currentScopeHash = 'scope'; currentBaseSha = 'base'; expectedRunId = 'run'; expectedActionId = 'review-0'; expectedTicketKey = 'project:1:issue:1'; correctionRound = 0; maxCorrectionRounds = 3; remainingMinutes = 10 }
        $correct = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $request 'review-correct'))
        Assert-Equal 'correct' $correct.data.decision 'changes requested should route to same worker'
        $exhausted = $request.Clone(); $exhausted.correctionRound = 3
        $stop = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $exhausted 'review-unbounded-correction'))
        Assert-Equal 'correct' $stop.data.decision 'correction rounds must not be capped at a fixed budget'
        $stale = $request.Clone(); $stale.currentSha = 'new-head'
        $staleResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $stale 'review-stale'))
        Assert-Equal 'needs_input' $staleResult.data.decision 'stale approval must not publish'
        $mismatched = $request.Clone(); $mismatched.expectedRunId = 'other-run'
        $mismatchedResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $mismatched 'review-mismatched'))
        Assert-Equal 'stale_or_mismatched_review_input' $mismatchedResult.data.reason 'receipt identity must bind to the expected run'
        $failedCriteria = Copy-JsonObject $request; $failedCriteria.receipt.criteria[0].passed = $false; $failedCriteria.receipt.criteria[0].evidence = 'failed fixture'
        $failedCriteriaResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $failedCriteria 'review-failed-criteria'))
        Assert-Equal 'correct' $failedCriteriaResult.data.decision 'failed criteria should route a correction'
        $failedCheck = Copy-JsonObject $request; $failedCheck.receipt.checks = @(@{ command = 'test'; exitCode = 1; evidence = 'failed fixture'; passed = $false })
        $failedCheckResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $failedCheck 'review-failed-check'))
        Assert-Equal 'correct' $failedCheckResult.data.decision 'failed checks should route a correction'
        $passingFailure = Copy-JsonObject $request; $passingFailure.receipt.verdict = 'pass'; $passingFailure.receipt.checks = @(@{ command = 'test'; exitCode = 1; evidence = 'failed fixture'; passed = $false })
        $passingFailureResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $passingFailure 'review-passing-failure')) $false
        Assert-True (-not $passingFailureResult.ok) 'a pass with failed checks must remain blocked'

        $docAmendment = New-ReviewReceipt
        $reviewEvidenceRoot = Join-Path $script:FixtureRoot 'review-evidence'; $reviewLogPath = Join-Path $reviewEvidenceRoot 'evidence\logs\doc-check.log'; New-Item -ItemType Directory -Path (Split-Path -Parent $reviewLogPath) -Force | Out-Null; [IO.File]::WriteAllText($reviewLogPath, 'documentation review check passed', [Text.UTF8Encoding]::new($false)); $reviewLogHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $reviewLogPath).Hash.ToLowerInvariant(); $reviewEvidenceRecord = @{ schemaVersion = 1; evidenceId = 'ev-doc'; runId = 'run'; actionId = 'review-0'; ticketKey = 'project:1:issue:1'; scopeHash = 'scope'; checkedRevision = 'head'; evidenceKind = 'check'; outcome = 'passed'; actualExitCode = 0; assertionReportedPassed = $true; acceptedAsCheckPass = $true; criterionIds = @('criterion-1'); command = 'test'; profile = @{ model = 'gpt-6.1-sol'; effort = 'high' }; coverage = @{ revision = 'head'; baseSha = 'base'; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') }; log = @{ path = $reviewLogPath; sha256 = $reviewLogHash; bytes = ([IO.FileInfo]::new($reviewLogPath)).Length } }; $reviewEvidenceJson = $reviewEvidenceRecord | ConvertTo-Json -Depth 100 -Compress; $reviewEvidenceHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($reviewEvidenceJson))) -Algorithm SHA256).Hash.ToLowerInvariant()
        $reviewEvidencePath = Join-Path $reviewEvidenceRoot 'evidence\run\review-0\ev-doc.json'; New-Item -ItemType Directory -Path (Split-Path -Parent $reviewEvidencePath) -Force | Out-Null; Write-JsonFile @{ recordJson = $reviewEvidenceJson; recordSha256 = $reviewEvidenceHash } $reviewEvidencePath
        $docAmendment.checks[0].evidenceId = 'ev-doc'
        $docAmendment.reviewDelta = @{
            fromSha = 'prior-head'; toSha = 'head'; changedPaths = @('docs/guide.md')
            documentationChanged = $true; documentationPaths = @('docs/guide.md')
            documentationAssessment = 'Reviewed the updated operator guidance against the requested scope.'
            reusedCheckIds = @('check-evidence-1'); reuseJustification = 'The amendment changes documentation only; implementation files and inputs are unchanged.'
        }
         $docRequest = @{ receipt = $docAmendment; expectedCriteria = $script:ReviewCriteria; requiredCommands = @('test'); allowedEvidenceActions = @(@{ actionId = 'review-0'; actionKind = 'review_check'; role = 'reviewer'; profile = @{ model = 'gpt-6.1-sol'; effort = 'high' }; command = 'test'; criterionIds = @('criterion-1'); coverage = @{ revision = 'head'; baseSha = 'base'; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }); currentCoverage = @{ revision = 'head'; baseSha = 'base'; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'documentation_only'; changedPaths = @('docs/guide.md') }; currentSha = 'head'; currentScopeHash = 'scope'; currentBaseSha = 'base'; expectedRunId = 'run'; expectedActionId = 'review-0'; expectedTicketKey = 'project:1:issue:1'; correctionRound = 0; remainingMinutes = 10; previousReviewedSha = 'prior-head'; evidenceStateRoot = $reviewEvidenceRoot; evidenceReferences = @(@{ path = $reviewEvidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reviewEvidencePath).Hash.ToLowerInvariant(); evidenceId = 'ev-doc' }) }
        $docDecision = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $docRequest 'review-documentation-amendment'))
        Assert-Equal 'publish' $docDecision.data.decision 'a newly committed documentation delta must be assessed before publish'
        $expiredPass = Copy-JsonObject $request; $expiredPass.receipt = New-ReviewReceipt; $expiredPass.remainingMinutes = 0
        $expiredPassResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $expiredPass 'review-pass-after-deadline'))
        Assert-Equal 'needs_input' $expiredPassResult.data.decision 'a passing receipt may still require durable evidence, but not an elapsed-time gate'
        Assert-Equal 'durable_evidence_required_for_publication' $expiredPassResult.data.reason 'an exhausted wall-clock budget must not be the review reason'
        $missingDocAssessment = Copy-JsonObject $docRequest; $missingDocAssessment.receipt.reviewDelta.documentationAssessment = ''
        $missingDocAssessmentResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $missingDocAssessment 'review-documentation-unassessed')) $false
        Assert-True (-not $missingDocAssessmentResult.ok) 'documentation delta without reviewer assessment must not pass'
        $sameDocRevision = Copy-JsonObject $docRequest; $sameDocRevision.receipt.reviewDelta.toSha = 'prior-head'; $sameDocRevision.receipt.reviewedSha = 'prior-head'; $sameDocRevision.currentSha = 'prior-head'
        $sameDocResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $sameDocRevision 'review-documentation-no-commit')) $false
        Assert-True (-not $sameDocResult.ok) 'documentation amendment requires a new committed revision'
        $unjustifiedReuse = Copy-JsonObject $docRequest; $unjustifiedReuse.receipt.reviewDelta.reuseJustification = ''
        $unjustifiedReuseResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $unjustifiedReuse 'review-check-reuse-unjustified')) $false
        Assert-True (-not $unjustifiedReuseResult.ok) 'reused checks require an explicit justification'
        $missingDelta = Copy-JsonObject $docRequest; $missingDelta.receipt.Remove('reviewDelta')
        $missingDeltaResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $missingDelta 'review-delta-missing'))
        Assert-Equal 'missing_review_delta_assessment' $missingDeltaResult.data.reason 're-review without a bound delta must request input'
    }

    Test-Case 'route bounded receipt repairs and keep counters separate' {
        $legacy = New-ReviewReceipt
        $legacy.Remove('schemaVersion'); $legacy.Remove('kind')
        $legacy.criteria[0].Remove('text')
        $legacy.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'reviewed fix'; requestedChange = 'fix'; disposition = 'resolved' })
        $routeRequest = @{ resultId = 'review-0'; expectedActionId = 'review-0'; receipt = $legacy; expectedCriteria = $script:ReviewCriteria; repairAttempts = 0; remainingMinutes = 10 }
        $local = Invoke-PsJson $script:ReviewScript @('-Operation','route','-InputPath',(New-InputPath $routeRequest 'repair-local-normalization'))
        Assert-Equal 'local_deterministic' $local.data.route 'lossless legacy normalization should be handled locally'
        Assert-Equal 'format' $local.data.repairKind 'lossless normalization must remain a metadata repair'
        Assert-True (-not $local.data.requiresIndependentReview) 'lossless normalization must not pretend to amend technical evidence'
        $localExhausted = Copy-JsonObject $routeRequest; $localExhausted.repairAttempts = 2
        $localExhaustedResult = Invoke-PsJson $script:ReviewScript @('-Operation','route','-InputPath',(New-InputPath $localExhausted 'repair-local-exhausted'))
        Assert-Equal 'needs_input' $localExhaustedResult.data.decision 'repair exhaustion must stop'
        Assert-Equal 'receipt_repair_limit' $localExhaustedResult.data.reason 'repair exhaustion should be explicit'
        $unboundRoute = Copy-JsonObject $routeRequest; $unboundRoute.resultId = 'untrusted-result'
        $unboundRouteResult = Invoke-PsJson $script:ReviewScript @('-Operation','route','-InputPath',(New-InputPath $unboundRoute 'repair-unbound-result')) $false
        Assert-True (-not $unboundRouteResult.ok) 'repair result identity must come from the trusted original review action'

        $contradictory = New-ReviewReceipt
        $contradictory.schemaVersion = 0
        $contradictory.Remove('schemaVersion'); $contradictory.Remove('kind')
        $contradictory.actionId = 'untrusted-action-id'
        $contradictory.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'still unresolved'; requestedChange = 'fix'; disposition = 'resolved'; unresolved = $true })
        $contradictionRequest = @{ resultId = 'review-0'; expectedActionId = 'review-0'; receipt = $contradictory; expectedCriteria = $script:ReviewCriteria; repairAttempts = 0; remainingMinutes = 10 }
        $authorRoute = Invoke-PsJson $script:ReviewScript @('-Operation','route','-InputPath',(New-InputPath $contradictionRequest 'repair-evidence-contradiction'))
        Assert-Equal 'original_author' $authorRoute.data.route 'contradictory evidence must go back to the original receipt author'
        Assert-Equal 'evidence' $authorRoute.data.repairKind 'contradictory evidence must be treated as semantic'
        Assert-Equal 'review-0' $authorRoute.data.targetActionId 'repair must target the original reviewer action'
        Assert-True $authorRoute.data.requiresIndependentReview 'evidence repair must return through independent review'
        $budgetExpired = Copy-JsonObject $contradictionRequest; $budgetExpired.remainingMinutes = 0
        $budgetResult = Invoke-PsJson $script:ReviewScript @('-Operation','route','-InputPath',(New-InputPath $budgetExpired 'repair-budget-expired'))
        Assert-Equal 'repair' $budgetResult.data.decision 'receipt repair must not stop solely because a wall-clock budget elapsed'

        $repairRoot = Join-Path $script:FixtureRoot 'receipt-repair-state'
        $repairInit = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$repairRoot)
        $claimed = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; repositoryIdentity = 'repair-repo'; expectedRevision = $repairInit.revision }) 'repair-claim'),'-StateRoot',$repairRoot)
        $reserved = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; expectedRevision = $claimed.revision }) 'repair-reserve'),'-StateRoot',$repairRoot)
        $preparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; toPhase = 'preparing'; expectedRevision = $reserved.revision }) 'repair-preparing'),'-StateRoot',$repairRoot)
        $implementing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; toPhase = 'implementing'; expectedRevision = $preparing.revision }) 'repair-implementing'),'-StateRoot',$repairRoot)
        $reviewing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; toPhase = 'reviewing'; expectedRevision = $implementing.revision }) 'repair-reviewing'),'-StateRoot',$repairRoot)
        $reviewAction = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; actionId = 'review-result-action'; actionKind = 'reviewer-message'; target = @{ threadId = 'reviewer-fixture' }; expectedRevision = $reviewing.revision }) 'repair-review-action'),'-StateRoot',$repairRoot)
        $reviewResult = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; actionId = 'review-result-action'; observationStatus = 'observed'; expectedRevision = $reviewAction.revision }) 'repair-review-result'),'-StateRoot',$repairRoot)
        $repairInput = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:1:issue:70'; resultId = 'review-result-action'; repairId = 'repair-attempt-1'; repairKind = 'format'; route = 'local_deterministic'; remainingMinutes = 10; expectedRevision = $reviewResult.revision }
        $wrongAuthor = $repairInput.Clone(); $wrongAuthor.repairId = 'repair-wrong-author'; $wrongAuthor.repairKind = 'evidence'; $wrongAuthor.route = 'original_author'; $wrongAuthor.targetActionId = 'other-review-action'
        $wrongAuthorResult = Invoke-PsJson $script:StateScript @('-Operation','record-receipt-repair','-InputPath',(New-InputPath $wrongAuthor 'repair-ledger-wrong-author'),'-StateRoot',$repairRoot) $false
        Assert-True (-not $wrongAuthorResult.ok) 'repair must not be routed to an action other than the original author'
        $repairOne = Invoke-PsJson $script:StateScript @('-Operation','record-receipt-repair','-InputPath',(New-InputPath $repairInput 'repair-ledger-one'),'-StateRoot',$repairRoot)
        Assert-Equal 0 $repairOne.data.correctionRound 'metadata repair must not increment production correction rounds'
        $unboundRepair = $repairInput.Clone(); $unboundRepair.resultId = 'unprepared-result'; $unboundRepair.repairId = 'repair-attempt-unbound'; $unboundRepair.expectedRevision = $repairOne.revision
        $unboundRepairResult = Invoke-PsJson $script:StateScript @('-Operation','record-receipt-repair','-InputPath',(New-InputPath $unboundRepair 'repair-ledger-unbound'),'-StateRoot',$repairRoot) $false
        Assert-True (-not $unboundRepairResult.ok) 'state must reject an unprepared result ID that could reset the repair counter'
        $repairTwoInput = $repairInput.Clone(); $repairTwoInput.repairId = 'repair-attempt-2'; $repairTwoInput.repairKind = 'evidence'; $repairTwoInput.route = 'original_author'; $repairTwoInput.targetActionId = 'review-result-action'; $repairTwoInput.expectedRevision = $repairOne.revision
        $repairTwo = Invoke-PsJson $script:StateScript @('-Operation','record-receipt-repair','-InputPath',(New-InputPath $repairTwoInput 'repair-ledger-two'),'-StateRoot',$repairRoot)
        Assert-Equal 0 $repairTwo.data.correctionRound 'evidence repair must not increment production correction rounds'
        $repairThreeInput = $repairTwoInput.Clone(); $repairThreeInput.repairId = 'repair-attempt-3'; $repairThreeInput.expectedRevision = $repairTwo.revision
        $repairThree = Invoke-PsJson $script:StateScript @('-Operation','record-receipt-repair','-InputPath',(New-InputPath $repairThreeInput 'repair-ledger-three'),'-StateRoot',$repairRoot)
        Assert-Equal 'needs_input' $repairThree.data.decision 'third repair attempt should exhaust the default limit of two'
        Assert-Equal 2 $repairThree.data.repairAttempts 'blocked repair must not increment the attempt count'
        Assert-Equal 0 $repairThree.data.correctionRound 'exhausting receipt repairs must leave code rounds unchanged'
        $snapshot = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$repairRoot)
        Assert-Equal 2 @($snapshot.data.registry.tickets.'project:1:issue:70'.receiptRepairs.'review-result-action'.attempts).Count 'repair attempts must persist separately in state'
    }

    Test-Case 'capture complete Taiga pages and reconcile uncertain writes' {
        $context = @{ kind = 'story'; projectId = 1; ref = 2; detailPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); taskPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); selectedTaskIds = @(); linkedStoryKeys = @() }
        $captured = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $context 'taiga-context'))
        Assert-True $captured.data.complete 'complete Taiga pages should pass'
        $unknown = $context.Clone(); $unknown.commentPages = @(@{ page = 1 })
        $unknownResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $unknown 'taiga-unknown')) $false
        Assert-True (-not $unknownResult.ok) 'unknown pagination must be incomplete'
        $unknownNull = $context.Clone(); $unknownNull.commentPages = @(@{ page = 1; has_more = $null; next_page = $null; total = $null; items = @() })
        $unknownNullResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $unknownNull 'taiga-unknown-null')) $false
        Assert-True (-not $unknownNullResult.ok) 'null has_more and next_page without totals must remain unknown'
        $observedTerminal = $context.Clone(); $observedTerminal.commentPages = @(@{ page = 1; has_more = $null; next_page = $null; next_page_known = $true })
        $observedTerminalResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $observedTerminal 'taiga-observed-terminal'))
        Assert-Equal 'next_page' $observedTerminalResult.data.pagination.comments.basis 'only an observed null next-page source can prove terminal state'
        $incomplete = $context.Clone(); $incomplete.commentPages = @(@{ page = 1; hasMore = $true; nextPage = 2 })
        $incompleteResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $incomplete 'taiga-incomplete')) $false
        Assert-True (-not $incompleteResult.ok) 'hasMore=true without a captured next page must be incomplete'
        $totalsComplete = $context.Clone(); $totalsComplete.commentPages = @(@{ page = 1; hasMore = $null; nextPage = 2; totalCount = 12; pageSize = 10; itemCount = 10 }, @{ page = 2; hasMore = $null; nextPage = $null; totalCount = 12; pageSize = 10; itemCount = 2 })
        $totalsResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $totalsComplete 'taiga-total-complete'))
        Assert-Equal 'authoritative_total_count' $totalsResult.data.pagination.comments.basis 'complete totals should resolve null hasMore'
        Assert-Equal 12 $totalsResult.data.pagination.comments.totalCount 'captured trustworthy total'
        $envelopeTotals = $context.Clone(); $envelopeTotals.commentPages = @(@{ page = 1; has_more = $null; next_page = 2; total = 3; items = @(@{ id = 31 }, @{ id = 32 }) }, @{ page = 2; has_more = $null; next_page = $null; total = 3; items = @(@{ id = 33 }) })
        $envelopeResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $envelopeTotals 'taiga-envelope-totals'))
        Assert-Equal 'authoritative_total_count' $envelopeResult.data.pagination.comments.basis 'MCP page-envelope names should normalize to authoritative total evidence'
        Assert-Equal 3 $envelopeResult.data.pagination.comments.totalCount 'page-envelope total'
        $totalsIncomplete = $context.Clone(); $totalsIncomplete.commentPages = @(@{ page = 1; hasMore = $null; nextPage = $null; totalCount = 12; pageSize = 10; itemCount = 10 })
        $totalsIncompleteResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $totalsIncomplete 'taiga-total-incomplete')) $false
        Assert-True (-not $totalsIncompleteResult.ok) 'null hasMore with an incomplete total-page set must stay incomplete'
        $duplicatePages = $context.Clone(); $duplicatePages.commentPages = @(@{ page = 1; hasMore = $true; nextPage = 2 }, @{ page = 1; hasMore = $false; nextPage = $null })
        $duplicateResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $duplicatePages 'taiga-duplicate-pages')) $false
        Assert-True (-not $duplicateResult.ok) 'duplicate page observations must be rejected'
        $contradictory = $context.Clone(); $contradictory.commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null; totalCount = 12; pageSize = 10; itemCount = 10 }, @{ page = 2; hasMore = $false; nextPage = $null; totalCount = 12; pageSize = 10; itemCount = 2 })
        $contradictoryResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $contradictory 'taiga-contradictory-pagination')) $false
        Assert-True (-not $contradictoryResult.ok) 'contradictory hasMore and total evidence must be rejected'
        $orderedA = [ordered]@{ kind = 'story'; projectId = 1; ref = 2; detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ b = 2; a = 1 } }); commentPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null }); taskPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null }) }
        $orderedB = [ordered]@{ taskPages = @([ordered]@{ nextPage = $null; hasMore = $false; page = 1 }); commentPages = @([ordered]@{ nextPage = $null; hasMore = $false; page = 1 }); detailPages = @([ordered]@{ extra = [ordered]@{ a = 1; b = 2 }; nextPage = $null; hasMore = $false; page = 1 }); ref = 2; projectId = 1; kind = 'story' }
        $orderedResultA = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $orderedA 'taiga-order-a'))
        $orderedResultB = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $orderedB 'taiga-order-b'))
        Assert-Equal $orderedResultA.data.requirementsHash $orderedResultB.data.requirementsHash 'equivalent context must hash identically across helper processes'
        $emptyShape = Copy-JsonObject $orderedA; $emptyShape.detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ items = @() } })
        $nullShape = Copy-JsonObject $orderedA; $nullShape.detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ items = $null } })
        $emptyHash = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $emptyShape 'taiga-empty-array'))
        $nullHash = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $nullShape 'taiga-null-array'))
        Assert-True ($emptyHash.data.requirementsHash -ne $nullHash.data.requirementsHash) 'empty arrays and null must hash differently'
        $arrayShape = Copy-JsonObject $orderedA; $arrayShape.detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ items = @('a') } })
        $scalarShape = Copy-JsonObject $orderedA; $scalarShape.detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ items = 'a' } })
        $arrayHash = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $arrayShape 'taiga-single-array'))
        $scalarHash = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $scalarShape 'taiga-single-scalar'))
        Assert-True ($arrayHash.data.requirementsHash -ne $scalarHash.data.requirementsHash) 'singleton arrays and scalars must hash differently'
        $nestedShape = Copy-JsonObject $orderedA; $nestedShape.detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ items = @(, @('a', 'b')) } })
        $flatShape = Copy-JsonObject $orderedA; $flatShape.detailPages = @([ordered]@{ page = 1; hasMore = $false; nextPage = $null; extra = [ordered]@{ items = @('a', 'b') } })
        $nestedHash = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $nestedShape 'taiga-nested-array'))
        $flatHash = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $flatShape 'taiga-flat-array'))
        Assert-True ($nestedHash.data.requirementsHash -ne $flatHash.data.requirementsHash) 'nested arrays and flat arrays must hash differently'
        $mappings = @{ statusMappings = @{ issue = @{ start = 1; review = 2; awaitingMerge = 3; done = 4 }; task = @{ start = 5; review = 6; awaitingMerge = 7; done = 8 }; story = @{ start = 9; review = 10; awaitingMerge = 11; done = 12 }; epic = @{ start = 13; review = 14; awaitingMerge = 15; done = 16 } } }
        $status = Invoke-PsJson $script:TaigaScript @('-Operation','validate-status-mappings','-InputPath',(New-InputPath $mappings 'taiga-status'))
        Assert-True $status.data.valid 'resource-specific status mapping should pass'
        $write = @{ writeKind = 'comment'; target = @{ projectId = 1; kind = 'story'; id = 2 }; version = 4; runMarker = 'run/action'; payload = 'Ready for review; head abc' }
        $preparedWrite = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-write','-InputPath',(New-InputPath $write 'taiga-write'))
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$preparedWrite.data.inputDigest)) 'write should have a reconciliation digest'
        $uncertainWrite = Invoke-PsJson $script:TaigaScript @('-Operation','reconcile-write','-InputPath',(New-InputPath (@{ responseLost = $true } ) 'taiga-uncertain'))
        Assert-Equal 'uncertain' $uncertainWrite.data.state 'response loss should require inspection'
        $final = @{ kind = 'issue'; requirementsHash = 'h'; currentRequirementsHash = 'h'; criteriaComplete = $true; checksPass = $true; completionPolicy = 'merged'; prState = 'merged'; allStoriesMerged = $true; epicAccepted = $true }
        $finalResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $final 'taiga-final'))
        Assert-True $finalResult.data.ready 'merged leaf should be finalizable'
    }

    Test-Case 'bind story child task identities and durable progress events' {
        $taskContext = @{
            kind = 'story'; projectId = 12; storyId = 642; ref = 1
            detailPages = @(@{ page = 1; hasMore = $false; nextPage = $null })
            commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null })
            taskPages = @(
                @{ page = 1; hasMore = $true; nextPage = 2; total = 2; pageSize = 1; items = @(@{ id = 540; ref = 5; projectId = 12; user_story_id = 642; status_id = 56; version = 1; criteria = @('AC01'); closed = $false }) }
                @{ page = 2; hasMore = $false; nextPage = $null; total = 2; pageSize = 1; items = @(@{ id = 541; ref = 6; projectId = 12; user_story_id = 642; status_id = 57; version = 4; criteria = @('AC02'); closed = $true }) }
            )
            selectedTaskIds = @(540, 541)
            packetBinding = @{ runId = 'run-child'; actionId = 'action-child'; packetHash = ('a' * 64); scopeHash = ('b' * 64); trustedRevisions = @('abcdef1','abcdef2','abcdef3'); criteriaByTask = @{ '540' = @('AC01'); '541' = @('AC02') } }
        }
         $capturedTasks = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $taskContext 'child-task-context'))
         Assert-Equal 2 @($capturedTasks.data.taskScope.bindings).Count 'open and closed child tasks should both be bound'
         Assert-Equal 541 $capturedTasks.data.taskScope.bindings[1].taskId 'task IDs should remain bound to source pages'
         Assert-Equal 4 $capturedTasks.data.taskScope.bindings[1].version 'baseline task version should be captured'
         $packetBinding = $capturedTasks.data.taskScope.packetBinding
        $noChildren = Copy-JsonObject $taskContext; $noChildren.taskPages = @(@{ page = 1; hasMore = $false; nextPage = $null; total = 0; pageSize = 1; items = @() }); $noChildren.selectedTaskIds = @()
        $empty = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $noChildren 'child-task-empty'))
        Assert-Equal 0 @($empty.data.taskScope.bindings).Count 'a complete empty task page is a valid no-children scope'
        $emptySelected = Copy-JsonObject $noChildren; $emptySelected.selectedTaskIds = @(540)
        $emptySelectedResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $emptySelected 'child-task-empty-selected')) $false
        Assert-True (-not $emptySelectedResult.ok) 'a selected ID must not be certified from an empty capture'
        $missingPacket = Copy-JsonObject $taskContext; $missingPacket.Remove('packetBinding')
        $missingPacketResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $missingPacket 'child-task-missing-packet')) $false
        Assert-True (-not $missingPacketResult.ok) 'selected tasks must bind to the immutable packet and scope hashes'
        $absentParent = Copy-JsonObject $taskContext; $absentParent.taskPages[0].items[0].Remove('user_story_id')
        $absentParentResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $absentParent 'child-task-absent-parent')) $false
        Assert-True (-not $absentParentResult.ok) 'raw task DTOs without an authoritative user_story parent must be rejected'
        $emptyCriteria = Copy-JsonObject $taskContext; $emptyCriteria.taskPages[0].items[0].criteria = @(); $emptyCriteria.packetBinding.criteriaByTask.'540' = @()
        $emptyCriteriaResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $emptyCriteria 'child-task-empty-criteria')) $false
        Assert-True (-not $emptyCriteriaResult.ok) 'selected tasks must carry nonempty authoritative criteria'
        $wrongParent = Copy-JsonObject $taskContext; $wrongParent.taskPages[0].items[0].user_story_id = 999
        $wrongParentResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $wrongParent 'child-task-wrong-parent')) $false
        Assert-True (-not $wrongParentResult.ok) 'wrong parent tasks must remain unresolved'
        $duplicateAlias = Copy-JsonObject $taskContext; $duplicateAlias.taskPages[1].items[0].ref = 5
        $duplicateAliasResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $duplicateAlias 'child-task-duplicate-alias')) $false
        Assert-True (-not $duplicateAliasResult.ok) 'duplicate task aliases must be rejected'
        $missingMapping = Copy-JsonObject $taskContext; $missingMapping.taskPages[0].items[0].Remove('status_id')
        $missingMappingResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $missingMapping 'child-task-missing-mapping')) $false
        Assert-True (-not $missingMappingResult.ok) 'missing task status mapping must be rejected'
        $changedScope = Copy-JsonObject $taskContext; $changedScope.taskPages[1].items[0].version = 5
        $changedCapture = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $changedScope 'child-task-changed-scope'))
        Assert-True ($capturedTasks.data.requirementsHash -ne $changedCapture.data.requirementsHash) 'changed child scope must change the context hash'
        $statusRequest = @{ projectId = 12; resource = 'task'; statusMetadata = @(@{ id = 56; project = 12; resource = 'task'; name = 'New' }, @{ id = 58; project = 12; resource = 'task'; name = 'In Progress' }, @{ id = 59; project = 12; resource = 'task'; name = 'Done' }, @{ id = 60; project = 12; resource = 'task'; name = 'Blocked' }); mapping = @{ not_started = 56; in_progress = 58; accepted = 59; blocked = 60 } }
        $statusResult = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $statusRequest 'child-status-resolve'))
        Assert-Equal 58 $statusResult.data.in_progress 'mapping must use discovered task status IDs'
        Assert-True $statusResult.data.reviewFallback 'missing review status must use the documented in-progress fallback'
        $wrongResource = Copy-JsonObject $statusRequest; $wrongResource.statusMetadata[0].resource = 'story'
        $wrongResourceResult = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $wrongResource 'child-status-wrong-resource')) $false
        Assert-True (-not $wrongResourceResult.ok) 'status metadata from another resource must not be accepted'
        $arbitraryDuplicate = Copy-JsonObject $statusRequest; $arbitraryDuplicate.mapping.awaiting_review = 58; $arbitraryDuplicate.mapping.blocked = 58
        $arbitraryDuplicateResult = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $arbitraryDuplicate 'child-status-arbitrary-duplicate')) $false
        Assert-True (-not $arbitraryDuplicateResult.ok) 'unrelated duplicate task statuses must not be accepted as a review fallback'
         $progressRoot = Join-Path $script:FixtureRoot 'child-progress'; $started = @{ runId = 'run-child'; actionId = 'action-child'; ticketKey = 'project:12:story:642'; projectId = 12; parentStoryId = 642; taskId = 540; sequence = 1; currentSha = 'abcdef1'; eventType = 'started'; criterionIds = @('AC01'); packetBinding = $packetBinding; evidence = @{ milestone = 'implementation started' } }
         $recorded = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $started 'child-progress-started'),'-StateRoot',$progressRoot)
         Assert-True $recorded.data.recorded 'started event should be durable'
         $wrongAction = $started.Clone(); $wrongAction.actionId = 'unassigned-action'; $wrongAction.sequence = 2; $wrongAction.eventType = 'ready_for_review'; $wrongAction.evidence = @{ milestone = 'wrong action' }
         $wrongActionResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $wrongAction 'child-progress-wrong-action'),'-StateRoot',$progressRoot) $false
         Assert-True (-not $wrongActionResult.ok) 'progress must reject an action outside the immutable assignment'
         $emptyCriteria = $started.Clone(); $emptyCriteria.sequence = 2; $emptyCriteria.eventType = 'ready_for_review'; $emptyCriteria.criterionIds = @(); $emptyCriteria.evidence = @{ milestone = 'empty criteria' }
         $emptyCriteriaResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $emptyCriteria 'child-progress-empty-criteria'),'-StateRoot',$progressRoot) $false
         Assert-True (-not $emptyCriteriaResult.ok) 'progress must reject an empty criterion set'
         $foreignCriteria = $started.Clone(); $foreignCriteria.sequence = 2; $foreignCriteria.eventType = 'ready_for_review'; $foreignCriteria.criterionIds = @('AC99'); $foreignCriteria.evidence = @{ milestone = 'foreign criteria' }
         $foreignCriteriaResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $foreignCriteria 'child-progress-foreign-criteria'),'-StateRoot',$progressRoot) $false
         Assert-True (-not $foreignCriteriaResult.ok) 'progress must reject criteria outside the selected task assignment'
         $unselectedTask = $started.Clone(); $unselectedTask.sequence = 2; $unselectedTask.taskId = 999999; $unselectedTask.eventType = 'started'; $unselectedTask.evidence = @{ milestone = 'unselected task' }
         $unselectedTaskResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $unselectedTask 'child-progress-unselected-task'),'-StateRoot',$progressRoot) $false
         Assert-True (-not $unselectedTaskResult.ok) 'progress must reject an unselected task ID'
         $trustedContext = Copy-JsonObject $taskContext; $trustedContext.packetBinding.trustedRevisions = @('abcdef1')
         $trustedCapture = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $trustedContext 'child-task-trusted-revision'))
         $untrustedRevision = $started.Clone(); $untrustedRevision.packetBinding = $trustedCapture.data.taskScope.packetBinding; $untrustedRevision.currentSha = 'abcdef9'; $untrustedRevision.sequence = 1; $untrustedRevision.eventType = 'started'; $untrustedRevision.evidence = @{ milestone = 'untrusted revision' }
         $untrustedRevisionResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $untrustedRevision 'child-progress-untrusted-revision'),'-StateRoot',(Join-Path $script:FixtureRoot 'child-progress-untrusted-revision')) $false
         Assert-True (-not $untrustedRevisionResult.ok) 'progress must reject revisions outside the trusted assignment'
         $ready = $started.Clone(); $ready.sequence = 2; $ready.currentSha = 'abcdef2'; $ready.eventType = 'ready_for_review'; $ready.evidence = @{ milestone = 'ready for review'; aggregateReceipt = 'receipt-child' }
        $readyResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $ready 'child-progress-ready'),'-StateRoot',$progressRoot)
        $ready.eventId = $readyResult.data.event.eventId
        $duplicate = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $ready 'child-progress-duplicate'),'-StateRoot',$progressRoot)
        Assert-True $duplicate.data.idempotent 'repeated event identity should be idempotent'
        $workerAccepted = $ready.Clone(); $workerAccepted.sequence = 3; $workerAccepted.eventType = 'accepted'; $workerAccepted.evidence = @{ milestone = 'worker tried to accept' }
        $workerAcceptedResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $workerAccepted 'child-progress-worker-accepted'),'-StateRoot',$progressRoot) $false
        Assert-True (-not $workerAcceptedResult.ok) 'workers must not emit an accepted task state'
        $correction = $ready.Clone(); $correction.Remove('eventId'); $correction.sequence = 3; $correction.actionId = 'action-child-correction'; $correction.continuationOfActionId = 'action-child'; $correction.eventType = 'reopen'; $correction.currentSha = 'abcdef3'; $correction.evidence = @{ milestone = 'correction started' }
         $correctionResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $correction 'child-progress-correction'),'-StateRoot',$progressRoot)
         Assert-True ($correctionResult.data.recorded) 'a correction must continue with a new action without rewriting prior events'
         $correctionMilestone = $correction.Clone(); $correctionMilestone.Remove('eventId'); $correctionMilestone.Remove('continuationOfActionId'); $correctionMilestone.sequence = 4; $correctionMilestone.eventType = 'ready_for_review'; $correctionMilestone.evidence = @{ milestone = 'correction ready for review' }
         $correctionMilestoneResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $correctionMilestone 'child-progress-correction-milestone'),'-StateRoot',$progressRoot)
         Assert-True ($correctionMilestoneResult.data.recorded) 'subsequent milestones may remain within the active correction action'
         $reusedAction = $correction.Clone(); $reusedAction.Remove('eventId'); $reusedAction.sequence = 5; $reusedAction.actionId = 'action-child'; $reusedAction.continuationOfActionId = 'action-child-correction'; $reusedAction.eventType = 'started'; $reusedAction.evidence = @{ milestone = 'reused action' }
         $reusedActionResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $reusedAction 'child-progress-reused-action'),'-StateRoot',$progressRoot) $false
         Assert-True (-not $reusedActionResult.ok) 'a prior progress action must not be reused after continuation'
         $upgradeRoot = Join-Path $script:FixtureRoot 'child-progress-upgrade'; $legacyRecorded = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $started 'child-progress-upgrade-started'),'-StateRoot',$upgradeRoot); $legacyCheckpointPath = Join-Path $upgradeRoot 'task-progress.json'; $legacyCheckpoint = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $legacyCheckpointPath) -AsHashtable -Depth 100; $legacyEventId = [string]$legacyCheckpoint.events[0].eventId; $legacyCheckpoint.Remove('actionIds'); if ($legacyCheckpoint.Contains('legacyIdentityVersion')) { $legacyCheckpoint.Remove('legacyIdentityVersion') }; Write-JsonFile $legacyCheckpoint $legacyCheckpointPath
         $upgradeValidation = Invoke-PsJson $script:ProgressScript @('-Operation','validate','-InputPath',(New-InputPath @{} 'child-progress-upgrade-validate'),'-StateRoot',$upgradeRoot); $upgradedCheckpoint = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $legacyCheckpointPath) -AsHashtable -Depth 100
         Assert-True $upgradeValidation.data.valid 'legacy progress checkpoint should upgrade successfully'
         Assert-Equal $legacyEventId ([string]$upgradedCheckpoint.events[0].eventId) 'checkpoint upgrade must preserve existing event identities'
         Assert-True $upgradedCheckpoint.Contains('actionIds') 'checkpoint upgrade should add action history without rewriting events'
         $interimRoot = Join-Path $script:FixtureRoot 'child-progress-interim-upgrade'; New-Item -ItemType Directory -Path $interimRoot -Force | Out-Null; $interimCheckpoint = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $legacyCheckpointPath) -AsHashtable -Depth 100; $interimEvent = $interimCheckpoint.events[0]; $interimEvidenceJson = ConvertTo-Json -InputObject $interimEvent.evidence -Depth 100 -Compress; $interimKey = ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}' -f $interimEvent.runId,$interimEvent.actionId,$interimEvent.ticketKey,$interimEvent.projectId,$interimEvent.parentStoryId,$interimEvent.taskId,$interimEvent.sequence,$interimEvent.currentSha,$interimEvent.eventType,(@($interimEvent.criterionIds) -join ','),$interimEvidenceJson,$interimEvent.blockedReason,$interimEvent.packetHash,$interimEvent.scopeHash,$interimEvent.bindingDigest,$interimEvent.continuationOfActionId); $interimHash = [Security.Cryptography.SHA256]::Create(); try { $interimEvent.eventId = ([Convert]::ToHexString($interimHash.ComputeHash([Text.Encoding]::UTF8.GetBytes($interimKey)))).ToLowerInvariant() } finally { $interimHash.Dispose() }; $interimCheckpoint.Remove('actionIds'); Write-JsonFile $interimCheckpoint (Join-Path $interimRoot 'task-progress.json')
         $interimRetry = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $started 'child-progress-interim-retry'),'-StateRoot',$interimRoot)
         Assert-True $interimRetry.data.idempotent 'idempotent retry must survive upgrade from the interim event identity format'
         Assert-Equal ([string]$interimCheckpoint.events[0].eventId) ([string](ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath (Join-Path $interimRoot 'task-progress.json')) -AsHashtable -Depth 100).events[0].eventId) 'idempotent upgrade retry must preserve the interim event identity'
         $tampered = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath (Join-Path $progressRoot 'task-progress.json')) -AsHashtable -Depth 100; $tampered.events[0].currentSha = 'abcdef9'; Write-JsonFile $tampered (Join-Path $progressRoot 'task-progress.json')
        # The helper must reject the retained event digest even when its replacement is a valid-looking Git prefix.
        $tamperedValidation = Invoke-PsJson $script:ProgressScript @('-Operation','validate','-InputPath',(New-InputPath @{} 'child-progress-tampered-validate'),'-StateRoot',$progressRoot) $false
        Assert-True (-not $tamperedValidation.ok) 'tampering with a retained event SHA must invalidate the checkpoint'
        $stale = @{ runId = 'run-child'; actionId = 'action-child'; ticketKey = 'project:12:story:642'; projectId = 12; parentStoryId = 642; taskId = 540; sequence = 1; currentSha = 'abcdef3'; eventType = 'blocked'; criterionIds = @('AC01'); evidence = @{ milestone = 'stale' }; blockedReason = 'stale fixture' }
        $staleResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $stale 'child-progress-stale'),'-StateRoot',$progressRoot) $false
        Assert-True (-not $staleResult.ok) 'stale sequence evidence must be rejected'
    }

    Test-Case 'relay bounded child progress without starting untouched tasks' {
        $progressRoot = Join-Path $script:FixtureRoot 'relay-progress'; $relayRoot = Join-Path $script:FixtureRoot 'relay-state'; New-Item -ItemType Directory -Path $relayRoot -Force | Out-Null
        $relayContext = @{ kind = 'story'; projectId = 12; storyId = 642; ref = 1; detailPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); taskPages = @(@{ page = 1; hasMore = $true; nextPage = 2; total = 2; pageSize = 1; items = @(@{ id = 540; ref = 5; projectId = 12; user_story_id = 642; status_id = 56; version = 1; criteria = @('AC10') }) }, @{ page = 2; hasMore = $false; nextPage = $null; total = 2; pageSize = 1; items = @(@{ id = 541; ref = 6; projectId = 12; user_story_id = 642; status_id = 56; version = 1; criteria = @('AC11') }) }); selectedTaskIds = @(540,541); packetBinding = @{ runId = 'run-relay'; actionId = 'action-relay'; packetHash = ('a' * 64); scopeHash = ('b' * 64); trustedRevisions = @('abcdef1','abcdef2'); criteriaByTask = @{ '540' = @('AC10'); '541' = @('AC11') } } }
        $relayCapture = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $relayContext 'relay-task-context'))
        $relayPacket = $relayCapture.data.taskScope.packetBinding
        $statusRequest = @{ projectId = 12; resource = 'task'; statusMetadata = @(@{ id = 56; project = 12; resource = 'task'; name = 'New' }, @{ id = 58; project = 12; resource = 'task'; name = 'In Progress' }, @{ id = 59; project = 12; resource = 'task'; name = 'Done' }, @{ id = 60; project = 12; resource = 'task'; name = 'Blocked' }); mapping = @{ not_started = 56; in_progress = 58; accepted = 59; blocked = 60 }; packetBinding = $relayPacket }
        $statusResult = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $statusRequest 'relay-status-resolve'))
        $baseEvent = @{ runId = 'run-relay'; actionId = 'action-relay'; ticketKey = 'project:12:story:642'; projectId = 12; parentStoryId = 642; taskId = 540; currentSha = 'abcdef1'; criterionIds = @('AC10'); packetBinding = $relayPacket; evidence = @{ source = 'milestone' } }
        $started = $baseEvent.Clone(); $started.sequence = 1; $started.eventType = 'started'; $startedResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $started 'relay-started'),'-StateRoot',$progressRoot)
        $review = $baseEvent.Clone(); $review.sequence = 2; $review.currentSha = 'abcdef2'; $review.eventType = 'ready_for_review'; $review.evidence = @{ source = 'implementation receipt' }; $reviewResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $review 'relay-ready'),'-StateRoot',$progressRoot); $review.eventId = $reviewResult.data.event.eventId
        $second = $baseEvent.Clone(); $second.sequence = 3; $second.taskId = 541; $second.currentSha = 'abcdef2'; $second.eventType = 'started'; $second.criterionIds = @('AC11'); $second.evidence = @{ source = 'overlapping task milestone' }; $secondResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $second 'relay-second'),'-StateRoot',$progressRoot)
        $blocked = $second.Clone(); $blocked.sequence = 4; $blocked.eventType = 'blocked'; $blocked.blockedReason = 'synthetic dependency'; $blocked.occurredAtUtc = '2026-10-01T20:00:00.0000000Z'; $blocked.evidence = @{ source = 'blocked milestone' }; $blockedResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $blocked 'relay-blocked'),'-StateRoot',$progressRoot)
        $relayInput = @{ progressRoot = $progressRoot; consumerId = 'coordinator-story-642'; runId = 'run-relay'; cursor = 0; packetBinding = $relayPacket; statusMapping = $statusResult.data }
        $cursorDrift = $relayInput.Clone(); $cursorDrift.cursor = 4
        $cursorDriftResult = Invoke-PsJson $script:CoordinateScript @('-Operation','relay-task-progress','-InputPath',(New-InputPath $cursorDrift 'relay-cursor-drift'),'-StateRoot',$relayRoot) $false
        Assert-True (-not $cursorDriftResult.ok) 'a caller-supplied cursor must not override the persisted consumer cursor'
        $firstRelay = Invoke-PsJson $script:CoordinateScript @('-Operation','relay-task-progress','-InputPath',(New-InputPath $relayInput 'relay-first'),'-StateRoot',$relayRoot)
        Assert-Equal 4 @($firstRelay.data.taskTransitions).Count 'relay should expose each real milestone in order'
        Assert-Equal 58 $firstRelay.data.taskTransitions[0].statusId 'only started task should be mapped to in-progress'
        Assert-Equal 58 $firstRelay.data.taskTransitions[1].statusId 'ready-for-review should use the validated in-progress fallback'
        Assert-Equal 541 $firstRelay.data.taskTransitions[2].taskId 'overlapping progress must preserve task identity'
        Assert-Equal $relayPacket.bindingDigest $firstRelay.data.taskTransitions[0].bindingDigest 'relay transitions must preserve the packet binding digest'
        Assert-Equal $relayPacket.bindingDigest $firstRelay.data.taskTransitions[0].progressBinding.bindingDigest 'relay transitions must preserve the full progress binding'
        $blockedTransition = @($firstRelay.data.taskTransitions | Where-Object { $_.eventId -eq $blockedResult.data.event.eventId })[0]
        Assert-Equal 'synthetic dependency' $blockedTransition.progressBinding.blockedReason 'relay must preserve optional event fields'
        Assert-Equal ([string]$blockedResult.data.event.occurredAtUtc) ([string]$blockedTransition.progressBinding.occurredAtUtc) 'relay must preserve the complete event timestamp'
        $retryInput = $relayInput.Clone(); $retryInput.Remove('cursor')
        $retry = Invoke-PsJson $script:CoordinateScript @('-Operation','relay-task-progress','-InputPath',(New-InputPath $retryInput 'relay-retry-before-ack'),'-StateRoot',$relayRoot)
        Assert-True (-not $retry.data.unchanged -and @($retry.data.pending).Count -eq 4) 'failed or interrupted writes must leave durable pending transitions for retry'
        $ackOutcomes = @($firstRelay.data.pending | ForEach-Object { @{ eventId = $_.eventId; outcome = 'applied' } })
        $ackInput = @{ progressRoot = $progressRoot; consumerId = 'coordinator-story-642'; outcomes = $ackOutcomes }
        $ackResult = Invoke-PsJson $script:CoordinateScript @('-Operation','ack-task-progress','-InputPath',(New-InputPath $ackInput 'relay-ack'),'-StateRoot',$relayRoot)
        Assert-Equal 0 @($ackResult.data.pending).Count 'durable acknowledgement should clear only reconciled pending work'
        $unchangedInput = $relayInput.Clone(); $unchangedInput.cursor = 4
        $unchanged = Invoke-PsJson $script:CoordinateScript @('-Operation','relay-task-progress','-InputPath',(New-InputPath $unchangedInput 'relay-unchanged'),'-StateRoot',$relayRoot)
        Assert-True ($unchanged.data.stateMutation -eq $false) ("unchanged observations must not mutate task status state: " + ($unchanged.data | ConvertTo-Json -Depth 10 -Compress))
        Assert-Equal 0 @($unchanged.data.taigaWrites).Count 'unchanged observations must not propose Taiga writes'
        $duplicate = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $review 'relay-duplicate'),'-StateRoot',$progressRoot)
        Assert-True $duplicate.data.idempotent 'repeated progress events must remain idempotent after relay'
        $stale = $second.Clone(); $stale.currentSha = 'abcdef3'; $stale.eventType = 'blocked'; $stale.sequence = 3; $stale.blockedReason = 'stale'; $stale.evidence = @{ source = 'stale evidence' }
        $staleRelayEvent = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $stale 'relay-stale'),'-StateRoot',$progressRoot) $false
        Assert-True (-not $staleRelayEvent.ok) 'stale overlapping evidence must be rejected'
    }

    Test-Case 'journal reviewed child transitions and reconcile partial writes safely' {
        $writeContext = @{ kind = 'story'; projectId = 12; storyId = 642; ref = 1; detailPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); taskPages = @(@{ page = 1; hasMore = $false; nextPage = $null; total = 2; pageSize = 2; items = @(@{ id = 540; ref = 5; projectId = 12; user_story_id = 642; status_id = 59; version = 3; criteria = @('AC10') }, @{ id = 541; ref = 6; projectId = 12; user_story_id = 642; status_id = 56; version = 1; criteria = @('AC11') }) }); selectedTaskIds = @(540,541); packetBinding = @{ runId = 'run-relay'; actionId = 'action-review'; packetHash = ('a' * 64); scopeHash = ('b' * 64); trustedRevisions = @('abcdef2'); criteriaByTask = @{ '540' = @('AC10'); '541' = @('AC11') } } }
        $writeCapture = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $writeContext 'task-write-context'))
        $writePacket = $writeCapture.data.taskScope.packetBinding
        $writeStatusRequest = @{ projectId = 12; resource = 'task'; statusMetadata = @(@{ id = 56; project = 12; resource = 'task'; name = 'New' }, @{ id = 58; project = 12; resource = 'task'; name = 'In Progress' }, @{ id = 59; project = 12; resource = 'task'; name = 'Done' }, @{ id = 60; project = 12; resource = 'task'; name = 'Blocked' }); mapping = @{ not_started = 56; in_progress = 58; accepted = 59; blocked = 60 } }
        $writeStatus = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $writeStatusRequest 'task-write-status'))
        $writeProgressRoot = Join-Path $script:FixtureRoot 'task-write-progress'
        $writeProgressBase = @{ runId = 'run-relay'; actionId = 'action-review'; ticketKey = 'project:12:story:642'; projectId = 12; parentStoryId = 642; taskId = 540; sequence = 1; packetBinding = $writePacket; currentSha = 'abcdef2'; eventType = 'started'; criterionIds = @('AC10'); evidence = @{ source = 'implementation started' } }
        $writeStarted = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $writeProgressBase 'task-write-progress-started'),'-StateRoot',$writeProgressRoot)
        $writeReadyInput = $writeProgressBase.Clone(); $writeReadyInput.sequence = 2; $writeReadyInput.eventType = 'ready_for_review'; $writeReadyInput.evidence = @{ source = 'implementation receipt' }
        $writeReady = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $writeReadyInput 'task-write-progress-ready'),'-StateRoot',$writeProgressRoot)
        $writeSecond = $writeProgressBase.Clone(); $writeSecond.taskId = 541; $writeSecond.sequence = 3; $writeSecond.eventType = 'started'; $writeSecond.criterionIds = @('AC11'); $writeSecond.evidence = @{ source = 'second task milestone' }
        $writeSecondResult = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $writeSecond 'task-write-progress-second'),'-StateRoot',$writeProgressRoot)
        $accepted = @{ taskId = 540; projectId = 12; parentStoryId = 642; currentStatusId = 59; version = 3; targetStatusId = 59; logicalState = 'accepted'; currentSha = 'abcdef2'; runMarker = 'run-relay/action-review'; selectedTaskIds = @(540,541); requiredCriterionIds = @('AC10'); packetBinding = $writePacket; progressBinding = $writeReady.data.event; statusMapping = $writeStatus.data; reviewAcceptance = @{ accepted = $true; taskId = 540; reviewedSha = 'abcdef2'; reviewerId = 'reviewer-thread'; runId = 'run-relay'; actionId = 'review-action'; packetHash = $writePacket.packetHash; scopeHash = $writePacket.scopeHash; criterionIds = @('AC10'); evidence = 'accepted criterion evidence' } }
          $journal = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $accepted 'task-write-accepted'))
          Assert-Equal 3 $journal.data.expectedVersion 'task write must bind the current authoritative version'
          Assert-Equal 'coordinator' $journal.data.writer 'only the coordinator may own the Taiga write'
          $humanPrepare = Copy-JsonObject $accepted; $humanPrepare.currentStatusId = 56; $humanPrepare.baselineStatusId = 59
          $humanPrepareResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $humanPrepare 'task-write-human-change')) $false
          Assert-True (-not $humanPrepareResult.ok) 'single-task planning must preserve a human status edit'
          $humanRevert = Copy-JsonObject $accepted; $humanRevert.currentStatusId = 58; $humanRevert.baselineStatusId = 58; $humanRevert.lastCoordinatorStatusId = 59
          $humanRevertResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $humanRevert 'task-write-human-revert')) $false
          Assert-True (-not $humanRevertResult.ok) 'single-task planning must preserve a human edit back to the baseline status'
          $correctionProgressRoot = Join-Path $script:FixtureRoot 'task-write-correction-progress'; $correctionOrigin = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $writeProgressBase 'task-write-correction-origin'),'-StateRoot',$correctionProgressRoot); $correctionBase = $writeProgressBase.Clone(); $correctionBase.sequence = 2; $correctionBase.actionId = 'action-correction'; $correctionBase.continuationOfActionId = 'action-review'; $correctionBase.eventType = 'reopen'; $correctionBase.evidence = @{ source = 'correction started' }
         $correctionStarted = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $correctionBase 'task-write-correction-started'),'-StateRoot',$correctionProgressRoot)
         $correctionReadyInput = $correctionBase.Clone(); $correctionReadyInput.Remove('eventId'); $correctionReadyInput.Remove('continuationOfActionId'); $correctionReadyInput.sequence = 3; $correctionReadyInput.eventType = 'started'; $correctionReadyInput.evidence = @{ source = 'correction resumed' }
         $correctionReady = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $correctionReadyInput 'task-write-correction-ready'),'-StateRoot',$correctionProgressRoot)
          $correctionWrite = Copy-JsonObject $accepted; $correctionWrite.currentStatusId = 56; $correctionWrite.lastCoordinatorStatusId = 56; $correctionWrite.targetStatusId = 58; $correctionWrite.logicalState = 'in_progress'; $correctionWrite.progressBinding = $correctionReady.data.event; $correctionWrite.Remove('reviewAcceptance')
         $correctionJournal = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $correctionWrite 'task-write-correction-milestone'))
         Assert-Equal 58 $correctionJournal.data.targetStatusId 'task writes must accept subsequent milestones within a correction action'
         $fabricatedProgress = Copy-JsonObject $accepted; $fabricatedProgress.progressBinding.eventId = ('d' * 64)
        $fabricatedProgressResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $fabricatedProgress 'task-write-fabricated-progress')) $false
        Assert-True (-not $fabricatedProgressResult.ok) 'task writes must reject a fabricated progress event identity'
        $missingProgressEvidence = Copy-JsonObject $accepted; $missingProgressEvidence.progressBinding.Remove('evidence')
        $missingProgressEvidenceResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $missingProgressEvidence 'task-write-missing-progress-evidence')) $false
        Assert-True (-not $missingProgressEvidenceResult.ok) 'task writes must require captured progress evidence'
        $reviewReceipt = New-ReviewReceipt; $reviewReceipt.taskAcceptances = @(@{ taskId = 540; accepted = $true; reviewedSha = 'head'; criterionIds = @('criterion-1'); evidence = 'task acceptance evidence' })
        $reviewWithTasks = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath @{ receipt = $reviewReceipt; expectedCriteria = $script:ReviewCriteria } 'task-review-acceptance'))
        Assert-True $reviewWithTasks.data.valid 'review receipts should carry explicit per-task acceptance evidence'
        $rejectedReceipt = New-ReviewReceipt 'changes_requested'; $rejectedReceipt.taskAcceptances = @(@{ taskId = 540; accepted = $false; reviewedSha = 'head'; criterionIds = @('criterion-1'); evidence = 'criterion needs correction'; rejectionReason = 'criterion is incomplete'; routedActionId = 'implementer-correction-1' })
        $rejectedReview = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath @{ receipt = $rejectedReceipt; expectedCriteria = $script:ReviewCriteria } 'task-review-rejection'))
        Assert-True $rejectedReview.data.valid 'changes_requested receipts must persist an individual rejected task decision'
        $unroutedReceipt = Copy-JsonObject $rejectedReceipt; $unroutedReceipt.taskAcceptances[0].Remove('routedActionId')
        $unroutedReview = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-InputPath',(New-InputPath @{ receipt = $unroutedReceipt; expectedCriteria = $script:ReviewCriteria } 'task-review-unrouted')) $false
        Assert-True (-not $unroutedReview.ok) 'rejected child tasks must carry a same-worker correction route'
        $missingReview = $accepted.Clone(); $missingReview.Remove('reviewAcceptance')
        $missingReviewResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $missingReview 'task-write-missing-review')) $false
        Assert-True (-not $missingReviewResult.ok) 'Done transitions without explicit review acceptance must be rejected'
        $staleReview = Copy-JsonObject $accepted; $staleReview.reviewAcceptance.reviewedSha = 'abcdef1'
        $staleReviewResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $staleReview 'task-write-stale-review')) $false
        Assert-True (-not $staleReviewResult.ok) 'stale reviewed SHAs must be rejected'
        $logicalBypass = Copy-JsonObject $accepted; $logicalBypass.logicalState = 'in_progress'; $logicalBypass.targetStatusId = 59
        $logicalBypassResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $logicalBypass 'task-write-logical-bypass')) $false
        Assert-True (-not $logicalBypassResult.ok) 'a caller must not reach Done by combining an in-progress logical state with an accepted target ID'
        $milestoneMismatch = Copy-JsonObject $accepted; $milestoneMismatch.logicalState = 'in_progress'; $milestoneMismatch.targetStatusId = 58; $milestoneMismatch.Remove('reviewAcceptance')
        $milestoneMismatchResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $milestoneMismatch 'task-write-milestone-mismatch')) $false
        Assert-True (-not $milestoneMismatchResult.ok) 'requested task status must match the worker progress milestone'
        $unrelatedReview = Copy-JsonObject $accepted; $unrelatedReview.requiredCriterionIds = @('AC10'); $unrelatedReview.reviewAcceptance.criterionIds = @('AC99')
        $unrelatedReviewResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $unrelatedReview 'task-write-unrelated-review')) $false
        Assert-True (-not $unrelatedReviewResult.ok) 'review acceptance must exactly cover the selected task criteria'
        $responseLost = Invoke-PsJson $script:TaigaScript @('-Operation','reconcile-task-write','-InputPath',(New-InputPath @{ responseLost = $true } 'task-write-response-lost'))
        Assert-Equal 'reread_task_detail_history' $responseLost.data.action 'response loss must reconcile by rereading'
        $versionConflict = Invoke-PsJson $script:TaigaScript @('-Operation','reconcile-task-write','-InputPath',(New-InputPath @{ versionConflict = $true } 'task-write-version-conflict'))
        Assert-True (-not $versionConflict.data.blindRetry) 'version conflicts must never blind retry'
        $sameVersionNoMarker = Invoke-PsJson $script:TaigaScript @('-Operation','reconcile-task-write','-InputPath',(New-InputPath @{ journal = $journal.data; currentTask = @{ taskId = 540; projectId = 12; parentStoryId = 642; currentStatusId = 59; version = 3 } } 'task-write-same-version-no-marker'))
        Assert-Equal 'human_change_preserved' $sameVersionNoMarker.data.state 'same-version target status without coordinator marker must remain unresolved'
        $wrongSibling = Invoke-PsJson $script:TaigaScript @('-Operation','reconcile-task-write','-InputPath',(New-InputPath @{ journal = $journal.data; currentTask = @{ taskId = 541; projectId = 12; parentStoryId = 642; currentStatusId = 59; version = 4; lastCoordinatorRunMarker = 'run-relay/action-review' } } 'task-write-wrong-sibling')) $false
        Assert-True (-not $wrongSibling.ok) 'a reread of a sibling task must not confirm the journal'
         $batch = @{ projectId = 12; parentStoryId = 642; currentSha = 'abcdef2'; runMarker = 'run-relay/action-review'; selectedTaskIds = @(540,541); packetBinding = $writePacket; scopeReconciliation = 'preserve_scope'; statusMapping = $accepted.statusMapping; tasks = @(
             @{ taskId = 540; projectId = 12; parentStoryId = 642; currentStatusId = 56; lastCoordinatorStatusId = 56; version = 3; targetStatusId = 59; logicalState = 'accepted'; requiredCriterionIds = @('AC10'); progressBinding = $accepted.progressBinding; reviewAcceptance = $accepted.reviewAcceptance }
            @{ taskId = 541; projectId = 12; parentStoryId = 642; currentStatusId = 56; version = 1; targetStatusId = 58; logicalState = 'in_progress'; requiredCriterionIds = @('AC11'); progressBinding = $writeSecondResult.data.event }
            @{ taskId = 542; projectId = 12; parentStoryId = 642; currentStatusId = 57; baselineStatusId = 56; version = 2; targetStatusId = 58; logicalState = 'in_progress'; humanChanged = $true }
        ) }
         $batchResult = Invoke-PsJson $script:TaigaScript @('-Operation','apply-reviewed-task-transition','-InputPath',(New-InputPath $batch 'task-write-batch'))
         Assert-Equal 2 @($batchResult.data.writes).Count 'successful task journals should survive a sibling conflict'
         Assert-Equal 1 @($batchResult.data.unresolved).Count 'human edits should remain unresolved and preserved'
          Assert-True $batchResult.data.taskDoneRequiresReviewAcceptance 'batch planner must keep the Done gate explicit'
         $humanBatch = Copy-JsonObject $batch; $humanBatch.tasks[0].currentStatusId = 56; $humanBatch.tasks[0].baselineStatusId = 56; $humanBatch.tasks[0].lastCoordinatorStatusId = 59
         $humanBatchResult = Invoke-PsJson $script:TaigaScript @('-Operation','apply-reviewed-task-transition','-InputPath',(New-InputPath $humanBatch 'task-write-human-revert'))
         Assert-True (@($humanBatchResult.data.writes | Where-Object { [long]$_.taskId -eq 540 }).Count -eq 0) 'batch planning must not overwrite a human status edit'
         Assert-Equal 'human_changed' (@($humanBatchResult.data.unresolved | Where-Object { [long]$_.taskId -eq 540 })[0].outcome) 'batch planning must surface the preserved human edit'
         $incompleteBatch = Copy-JsonObject $batch; $incompleteBatch.tasks = @($batch.tasks | Select-Object -First 1)
        $incompleteBatchResult = Invoke-PsJson $script:TaigaScript @('-Operation','apply-reviewed-task-transition','-InputPath',(New-InputPath $incompleteBatch 'task-write-incomplete')) $false
        Assert-True (-not $incompleteBatchResult.ok) 'reviewed writes must bind every selected child before planning any write'
        $scope = @{ projectId = 12; parentStoryId = 642; baselineTaskIds = @(540,541); currentTaskIds = @(540,542); reparentedTaskIds = @(542) }
        $scopeResult = Invoke-PsJson $script:TaigaScript @('-Operation','reconcile-task-scope','-InputPath',(New-InputPath $scope 'task-write-scope'))
        Assert-Equal 542 $scopeResult.data.addedTaskIds[0] 'new child tasks require scope reconciliation'
        Assert-Equal 541 $scopeResult.data.removedTaskIds[0] 'removed child tasks are not silently discarded'
        Assert-Equal 'reconcile_scope_before_writes' $scopeResult.data.decision 'scope changes must precede writes'
    }

    Test-Case 'verify synthetic story lifecycle recovery and parent gating' {
        $scenario = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures\child-task-story-lifecycle.json')) -AsHashtable -Depth 100
        $lifecycle = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $scenario 'child-story-lifecycle'))
        Assert-True $lifecycle.data.accepted 'end-to-end story lifecycle should be accepted offline'
        Assert-True $lifecycle.data.restartRecovered 'restart cursor should be reconciled without replay'
        Assert-Equal 2 @($lifecycle.data.selectedTaskIds).Count 'story completion must retain every selected child'
        Assert-Equal 0 $lifecycle.data.independentChildBranches 'child tasks must not create extra branches'
        Assert-Equal 'merged' $lifecycle.data.parentCompletionPolicy 'parent completion policy remains separate'
        $missingChildAcceptance = Copy-JsonObject $scenario; $missingChildAcceptance.taskAcceptances = @($scenario.taskAcceptances | Select-Object -First 1)
        $missingChildAcceptanceResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $missingChildAcceptance 'child-story-missing-acceptance')) $false
        Assert-True (-not $missingChildAcceptanceResult.ok) 'parent completion must fail when any selected child acceptance is missing'
        $wrongLifecycleStatus = Copy-JsonObject $scenario; $wrongLifecycleStatus.events[1].statusId = 58
        $wrongLifecycleStatusResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $wrongLifecycleStatus 'child-story-wrong-status')) $false
        Assert-True (-not $wrongLifecycleStatusResult.ok) 'story lifecycle must validate child status IDs against the task mapping'
        $missingHelperEvidence = Copy-JsonObject $scenario; $missingHelperEvidence.helperIntegration = @()
        $missingHelperEvidenceResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $missingHelperEvidence 'child-story-no-helper-evidence')) $false
        Assert-True (-not $missingHelperEvidenceResult.ok) 'story lifecycle acceptance must not rely on a narrative without helper execution evidence'
        $missing = Copy-JsonObject $scenario; $missing.parent.acceptedTaskIds = @(540)
         $missingResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $missing 'child-story-missing-acceptance')) $false
         Assert-True (-not $missingResult.ok) 'parent completion must not hide missing selected-task evidence'
         $finalizeInput = @($scenario.helperIntegration | Where-Object { $_.name -eq 'finalize-selected-child-evidence' })[0].input
         $nonAcceptanceEvidence = Copy-JsonObject $finalizeInput; $nonAcceptanceEvidence.selectedTaskEvidence[0].eventType = 'ready_for_review'
         $nonAcceptanceResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $nonAcceptanceEvidence 'child-story-non-acceptance-evidence'))
         Assert-True (-not $nonAcceptanceResult.data.ready) 'parent completion must reject a non-acceptance child event as final evidence'
         $workerWrite = Copy-JsonObject $scenario; $workerWrite.operations += @{ actor = 'implementer'; kind = 'taiga_task_write'; taskId = 540; statusId = 60 }
        $workerWriteResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $workerWrite 'child-story-worker-write')) $false
        Assert-True (-not $workerWriteResult.ok) 'implementer and reviewer must never write Taiga'
        $duplicate = Copy-JsonObject $scenario; $duplicate.events += $duplicate.events[0]; $duplicate.restart.persistedCursor = 8; $duplicate.restart.resumeCursor = 8
        $duplicateResult = Invoke-PsJson $script:AcceptanceScript @('-Operation','story-lifecycle','-InputPath',(New-InputPath $duplicate 'child-story-duplicate-event')) $false
        Assert-True (-not $duplicateResult.ok) 'repeated lifecycle events must be rejected'
        $captureInput = Copy-JsonObject $scenario.helperIntegration[0].input
        $captured = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $captureInput 'child-story-write-capture'))
        $statusInput = Copy-JsonObject $scenario.helperIntegration[2].input; $statusInput.Remove('packetBinding')
        $resolvedStatus = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $statusInput 'child-story-write-status'))
        $packet = $captured.data.taskScope.packetBinding
        $probeProgressRoot = Join-Path $script:FixtureRoot 'child-story-write-progress'
        $probeProgress = @{ runId = [string]$packet.runId; actionId = [string]$packet.actionId; ticketKey = 'project:12:story:642'; projectId = 12; parentStoryId = 642; taskId = 540; sequence = 1; currentSha = 'abcdef2'; eventType = 'started'; criterionIds = @('AC01'); packetBinding = $packet; evidence = @{ milestone = 'write probe' } }
        $probeEvent = Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $probeProgress 'child-story-write-progress'),'-StateRoot',$probeProgressRoot)
        $writeProbe = @{
            projectId = 12; parentStoryId = 642; selectedTaskIds = @(540, 541); packetBinding = $packet; statusMapping = $resolvedStatus.data
            task = @{ taskId = 540; projectId = 12; parentStoryId = 642; currentStatusId = 56; version = 1 }
            requiredCriterionIds = @('AC01'); logicalState = 'in_progress'; currentSha = 'abcdef2'; runMarker = 'synthetic-story-run/probe'
            progressBinding = $probeEvent.data.event
        }
        $fabricatedMapping = Copy-JsonObject $writeProbe; $fabricatedMapping.statusMapping.mappingDigest = ('c' * 64)
        $fabricatedMappingResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $fabricatedMapping 'child-story-fabricated-mapping')) $false
        Assert-True (-not $fabricatedMappingResult.ok) 'task writes must reject a fabricated status mapping digest'
        $missingCriteria = Copy-JsonObject $writeProbe; $missingCriteria.Remove('requiredCriterionIds')
        $missingCriteriaResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $missingCriteria 'child-story-missing-criteria')) $false
        Assert-True (-not $missingCriteriaResult.ok) 'task writes must require packet-bound criterion IDs'
        $missingPacket = Copy-JsonObject $writeProbe; $missingPacket.Remove('packetBinding')
        $missingPacketResult = Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $missingPacket 'child-story-missing-packet')) $false
        Assert-True (-not $missingPacketResult.ok) 'task writes must require a validated packet reference'
    }

    Test-Case 'finalize resolves persisted reviewer and task-write evidence' {
        $finalizeRegistryRoot = Join-Path $script:FixtureRoot 'finalize-persisted-registry'
        $finalizeProgressRoot = Join-Path $script:FixtureRoot 'finalize-persisted-progress'
        $scenario = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures\child-task-story-lifecycle.json')) -AsHashtable -Depth 100
        $capture = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $scenario.helperIntegration[0].input 'finalize-capture'))
        $packet = $capture.data.taskScope.packetBinding
        $status = Invoke-PsJson $script:TaigaScript @('-Operation','resolve-status-mapping','-InputPath',(New-InputPath $scenario.helperIntegration[2].input 'finalize-status'))
        $statusMapping = $status.data
        $initValue = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $syntheticPath) -AsHashtable -Depth 100
        $initValue.sessionId = 'finalize-session'
        $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',(New-InputPath $initValue 'finalize-init'),'-StateRoot',$finalizeRegistryRoot)
        $ticketKey = 'project:12:story:642'
        $claim = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath @{ sessionId = 'finalize-session'; ownerGeneration = 1; expectedRevision = $init.revision; ticketKey = $ticketKey; repositoryIdentity = 'finalize-repo'; workType = 'story' } 'finalize-claim'),'-StateRoot',$finalizeRegistryRoot)

        function Add-FinalizeRegistryAction {
            param([string] $ActionId, [string] $ActionKind, [hashtable] $Target, [hashtable] $Receipt, [string] $ObservationStatus = 'observed', [bool] $ReconcileRequired = $false)
            $inspection = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$finalizeRegistryRoot)
            $prepared = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'finalize-session'; ownerGeneration = 1; expectedRevision = $inspection.revision; ticketKey = $ticketKey; actionId = $ActionId; actionKind = $ActionKind; target = $Target; input = @{} } ('finalize-prepare-' + $ActionId)),'-StateRoot',$finalizeRegistryRoot)
            $observed = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath @{ sessionId = 'finalize-session'; ownerGeneration = 1; expectedRevision = $prepared.revision; actionId = $ActionId; observationStatus = $ObservationStatus; reconcileRequired = $ReconcileRequired; receipt = $Receipt } ('finalize-observe-' + $ActionId)),'-StateRoot',$finalizeRegistryRoot)
            return $observed
        }

        $receipt = @{ schemaVersion = 1; kind = 'review'; runId = 'synthetic-story-run'; actionId = 'review-action'; ticketKey = $ticketKey; scopeHash = $packet.scopeHash; baseSha = 'abcdef1'; reviewedSha = 'abcdef2'; verdict = 'pass'; reviewerModel = 'gpt-6.1-sol'; reviewerEffort = 'high'; criteria = @(@{ id = 'story-criterion'; text = 'Persisted child evidence is required.'; passed = $true; evidence = 'reviewed story criterion' }); checks = @(@{ command = 'synthetic-check'; exitCode = 0; passed = $true; evidence = 'check passed' }); findings = @(); taskAcceptances = @(@{ taskId = 540; accepted = $true; reviewedSha = 'abcdef2'; reviewerId = 'reviewer-story-642'; criterionIds = @('AC01'); evidence = 'accepted AC01' }, @{ taskId = 541; accepted = $true; reviewedSha = 'abcdef2'; reviewerId = 'reviewer-story-642'; criterionIds = @('AC02'); evidence = 'accepted AC02' }) }
        $receiptPath = Join-Path $script:FixtureRoot 'finalize-review-receipt.json'; Write-JsonFile $receipt $receiptPath
        $receiptReference = @{ path = $receiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant() }
        $reviewObserved = Add-FinalizeRegistryAction 'review-action' 'worker_dispatch' @{ workerId = 'reviewer-story-642'; runId = $packet.runId; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; ticketKey = $ticketKey } @{ receiptReference = $receiptReference }

        function Add-FinalizeProgressEvent {
            param([long] $TaskId, [long] $Sequence, [string] $EventType, [string] $Sha, [string[]] $Criteria, [string] $Evidence)
            $eventInput = @{ runId = $packet.runId; actionId = $packet.actionId; ticketKey = $ticketKey; projectId = 12; parentStoryId = 642; taskId = $TaskId; sequence = $Sequence; currentSha = $Sha; eventType = $EventType; criterionIds = $Criteria; packetBinding = $packet; evidence = @{ source = $Evidence } }
            return Invoke-PsJson $script:ProgressScript @('-Operation','record','-InputPath',(New-InputPath $eventInput ('finalize-progress-' + $TaskId + '-' + $Sequence)),'-StateRoot',$finalizeProgressRoot)
        }
        $task540Start = Add-FinalizeProgressEvent 540 1 'started' 'abcdef1' @('AC01') 'task 540 started'
        $task540Ready = Add-FinalizeProgressEvent 540 2 'ready_for_review' 'abcdef2' @('AC01') 'task 540 ready'
        $task541Start = Add-FinalizeProgressEvent 541 3 'started' 'abcdef1' @('AC02') 'task 541 started'
        $task541Ready = Add-FinalizeProgressEvent 541 4 'ready_for_review' 'abcdef2' @('AC02') 'task 541 ready'

        function New-FinalizeJournal {
            param([long] $TaskId, [object] $ProgressEvent)
            $journalInput = @{ projectId = 12; parentStoryId = 642; selectedTaskIds = @(540,541); packetBinding = $packet; statusMapping = $statusMapping; task = @{ taskId = $TaskId; projectId = 12; parentStoryId = 642; currentStatusId = 56; version = 1 }; requiredCriterionIds = @($packet.criteriaByTask[[string]$TaskId]); logicalState = 'accepted'; currentSha = 'abcdef2'; runMarker = 'synthetic-story-run/finalize'; progressBinding = $ProgressEvent; reviewAcceptance = @{ accepted = $true; taskId = $TaskId; reviewedSha = 'abcdef2'; reviewerId = 'reviewer-story-642'; runId = $packet.runId; actionId = 'review-action'; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; criterionIds = @($packet.criteriaByTask[[string]$TaskId]); evidence = 'persisted reviewer acceptance' } }
            return (Invoke-PsJson $script:TaigaScript @('-Operation','prepare-task-write','-InputPath',(New-InputPath $journalInput ('finalize-journal-' + $TaskId)))).data
        }
        $batchPlan = @{ projectId = 12; parentStoryId = 642; currentSha = 'abcdef2'; runMarker = 'synthetic-story-run/finalize'; selectedTaskIds = @(540,541); packetBinding = $packet; scopeReconciliation = 'preserve_scope'; statusMapping = $statusMapping; tasks = @(
            @{ taskId = 540; projectId = 12; parentStoryId = 642; currentStatusId = 56; version = 1; logicalState = 'accepted'; targetStatusId = 59; requiredCriterionIds = @('AC01'); progressBinding = $task540Ready.data.event; reviewAcceptance = @{ accepted = $true; taskId = 540; reviewedSha = 'abcdef2'; reviewerId = 'reviewer-story-642'; runId = $packet.runId; actionId = 'review-action'; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; criterionIds = @('AC01'); evidence = 'persisted reviewer acceptance' } },
            @{ taskId = 541; projectId = 12; parentStoryId = 642; currentStatusId = 56; version = 1; logicalState = 'accepted'; targetStatusId = 59; requiredCriterionIds = @('AC02'); progressBinding = $task541Ready.data.event; reviewAcceptance = @{ accepted = $true; taskId = 541; reviewedSha = 'abcdef2'; reviewerId = 'reviewer-story-642'; runId = $packet.runId; actionId = 'review-action'; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; criterionIds = @('AC02'); evidence = 'persisted reviewer acceptance' } }
        ) }
        $batchPlanResult = Invoke-PsJson $script:TaigaScript @('-Operation','apply-reviewed-task-transition','-InputPath',(New-InputPath $batchPlan 'finalize-batch-plan'))
        Assert-Equal 2 @($batchPlanResult.data.writes).Count 'batch planner should produce both persisted task journals'
        $journal540 = @($batchPlanResult.data.writes | Where-Object { [long]$_.taskId -eq 540 })[0]
        $journal541 = @($batchPlanResult.data.writes | Where-Object { [long]$_.taskId -eq 541 })[0]
        $write540 = Add-FinalizeRegistryAction 'write-540' 'taiga_task_update' @{ journal = $journal540; runId = $packet.runId; taskId = 540 } @{ outcome = 'reconciled'; journalId = $journal540.journalId; taskId = 540; statusId = 59 }
        $write541 = Add-FinalizeRegistryAction 'write-541' 'taiga_task_update' @{ journal = $journal541; runId = $packet.runId; taskId = 541 } @{ outcome = 'reconciled'; journalId = $journal541.journalId; taskId = 541; statusId = 59 }
        $finalizeBase = @{ kind = 'story'; projectId = 12; requirementsHash = 'scope-hash'; currentRequirementsHash = 'scope-hash'; criteriaComplete = $true; checksPass = $true; completionPolicy = 'merged'; prState = 'merged'; selectedTaskIds = @(540,541); packetBinding = $packet; currentSha = 'abcdef2'; expectedCriteria = @(@{ id = 'story-criterion'; text = 'Persisted child evidence is required.' }); statusMapping = $statusMapping; stateRoot = $finalizeRegistryRoot; progressRoot = $finalizeProgressRoot; reviewActionId = 'review-action'; reviewerId = 'reviewer-story-642'; selectedTaskEvidence = @(@{ taskId = 540; eventId = $task540Ready.data.event.eventId; taskWriteActionId = 'write-540'; accepted = $true; reviewAccepted = $true }, @{ taskId = 541; eventId = $task541Ready.data.event.eventId; taskWriteActionId = 'write-541'; accepted = $true; reviewAccepted = $true }) }
        $valid = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $finalizeBase 'finalize-persisted-valid'))
        Assert-True $valid.data.ready ("actual persisted reviewer and write records must authorize finalization: " + ($valid.data.errors -join '; '))
        Assert-Equal 'reconciled' $valid.data.selectedTaskEvidence[0].statusOutcome 'final evidence must derive its outcome from the persisted write record'

        $fabricated = Copy-JsonObject $finalizeBase; $fabricated.reviewActionId = 'invented-review-action'; $fabricated.selectedTaskEvidence[0].eventId = 'invented-event'; $fabricated.selectedTaskEvidence[0].taskWriteActionId = 'invented-write'; $fabricated.selectedTaskEvidence[0].accepted = $true
        $fabricatedResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $fabricated 'finalize-fabricated-references'))
        Assert-True (-not $fabricatedResult.data.ready) 'invented review, event, and write references must fail despite true labels'

        [IO.File]::AppendAllText($receiptPath, 'tampered', [Text.UTF8Encoding]::new($false))
        $tamperedResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $finalizeBase 'finalize-tampered-receipt'))
        Assert-True (-not $tamperedResult.data.ready) 'tampering with the persisted receipt must block finalization'
        [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))

        $wrongTask = Copy-JsonObject $finalizeBase; $wrongTask.selectedTaskEvidence[0].eventId = $task541Ready.data.event.eventId
        $wrongTaskResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $wrongTask 'finalize-wrong-task'))
        Assert-True (-not $wrongTaskResult.data.ready) 'a sibling progress event must not satisfy the selected task'
        $wrongRunReceipt = Copy-JsonObject $receipt; $wrongRunReceipt.actionId = 'review-wrong-run'; $wrongRunReceipt.runId = 'wrong-run'; $wrongRunReceiptPath = Join-Path $script:FixtureRoot 'finalize-wrong-run-receipt.json'; Write-JsonFile $wrongRunReceipt $wrongRunReceiptPath
        $wrongRunReference = @{ path = $wrongRunReceiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $wrongRunReceiptPath).Hash.ToLowerInvariant() }
        $null = Add-FinalizeRegistryAction 'review-wrong-run' 'worker_dispatch' @{ workerId = 'reviewer-story-642'; runId = 'wrong-run'; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; ticketKey = $ticketKey } @{ receiptReference = $wrongRunReference }
        $wrongRun = Copy-JsonObject $finalizeBase; $wrongRun.reviewActionId = 'review-wrong-run'
        $wrongRunResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $wrongRun 'finalize-wrong-run'))
        Assert-True (-not $wrongRunResult.data.ready) 'a receipt from another run must block finalization'
        $wrongCriteriaReceipt = Copy-JsonObject $receipt; $wrongCriteriaReceipt.actionId = 'review-wrong-criteria'; $wrongCriteriaReceipt.taskAcceptances[0].criterionIds = @('AC99'); $wrongCriteriaReceiptPath = Join-Path $script:FixtureRoot 'finalize-wrong-criteria-receipt.json'; Write-JsonFile $wrongCriteriaReceipt $wrongCriteriaReceiptPath
        $wrongCriteriaReference = @{ path = $wrongCriteriaReceiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $wrongCriteriaReceiptPath).Hash.ToLowerInvariant() }
        $null = Add-FinalizeRegistryAction 'review-wrong-criteria' 'worker_dispatch' @{ workerId = 'reviewer-story-642'; runId = $packet.runId; packetHash = $packet.packetHash; scopeHash = $packet.scopeHash; ticketKey = $ticketKey } @{ receiptReference = $wrongCriteriaReference }
        $wrongCriteria = Copy-JsonObject $finalizeBase; $wrongCriteria.reviewActionId = 'review-wrong-criteria'
        $wrongCriteriaResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $wrongCriteria 'finalize-wrong-criteria'))
        Assert-True (-not $wrongCriteriaResult.data.ready) 'receipt criteria unrelated to the selected task must block finalization'
        $wrongSha = Copy-JsonObject $finalizeBase; $wrongSha.currentSha = 'abcdef1'
        $wrongShaResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $wrongSha 'finalize-wrong-sha'))
        Assert-True (-not $wrongShaResult.data.ready) 'a stale final SHA must block finalization'

        $pendingJournal = New-FinalizeJournal 540 $task540Ready.data.event
        # Keep the action pending after its journal is prepared; finalize must not infer success from the journal alone.
        $pendingInspection = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$finalizeRegistryRoot)
        $pendingAction = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'finalize-session'; ownerGeneration = 1; expectedRevision = $pendingInspection.revision; ticketKey = $ticketKey; actionId = 'write-pending-only'; actionKind = 'taiga_task_update'; target = @{ journal = $pendingJournal; runId = $packet.runId; taskId = 540 }; input = @{} } 'finalize-pending-only'),'-StateRoot',$finalizeRegistryRoot)
        $pendingProbe = Copy-JsonObject $finalizeBase; $pendingProbe.selectedTaskEvidence[0].taskWriteActionId = 'write-pending-only'
        $pendingResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $pendingProbe 'finalize-pending-write'))
        Assert-True (-not $pendingResult.data.ready) 'pending task writes must block finalization'

        $uncertainJournal = New-FinalizeJournal 540 $task540Ready.data.event
        $uncertain = Add-FinalizeRegistryAction 'write-uncertain' 'taiga_task_update' @{ journal = $uncertainJournal; runId = $packet.runId; taskId = 540 } @{ state = 'uncertain' } 'uncertain' $true
        $uncertainProbe = Copy-JsonObject $finalizeBase; $uncertainProbe.selectedTaskEvidence[0].taskWriteActionId = 'write-uncertain'
        $uncertainResult = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $uncertainProbe 'finalize-response-lost-write'))
        Assert-True (-not $uncertainResult.data.ready) 'response-lost or uncertain task writes must block finalization'

        $null = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$finalizeRegistryRoot)
        $null = Invoke-PsJson $script:ProgressScript @('-Operation','validate','-InputPath',(New-InputPath @{} 'finalize-restart-validate'),'-StateRoot',$finalizeProgressRoot)
        $restarted = Invoke-PsJson $script:TaigaScript @('-Operation','finalize','-InputPath',(New-InputPath $finalizeBase 'finalize-after-restart'))
        Assert-True $restarted.data.ready 'valid persisted evidence must survive a fresh inspection and restart path'
    }

    Test-Case 'create and push a fresh branch using a local bare remote' {
        $repo = Join-Path $script:FixtureRoot 'repo'; $remote = Join-Path $script:FixtureRoot 'remote.git'; $worktree = Join-Path $script:FixtureRoot 'worktree'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git init -b master $repo | Out-Null; & git -C $repo config user.email 'automation@example.invalid'; & git -C $repo config user.name 'Automation Fixture'
        [IO.File]::WriteAllText((Join-Path $repo 'README.txt'), 'fixture')
        & git -C $repo add README.txt; & git -C $repo commit -m 'fixture base' | Out-Null
        & git init --bare $remote | Out-Null; & git -C $repo remote add origin $remote; & git -C $repo push -u origin master | Out-Null
        $fetch = Invoke-PsJson $script:GitScript @('-Operation','fetch-base','-InputPath',(New-InputPath (@{ repositoryPath = $repo; remote = 'origin'; baseBranch = 'master' }) 'fetch'))
        $branch = @{ repositoryPath = $repo; baseSha = $fetch.data.baseSha; branch = 'codex/issue-7-fixture-run'; worktreePath = $worktree }
        $created = Invoke-PsJson $script:GitScript @('-Operation','create-branch','-InputPath',(New-InputPath $branch 'branch'))
        Assert-Equal $fetch.data.baseSha $created.data.headSha 'fresh branch base'
        [IO.File]::WriteAllText((Join-Path $worktree 'change.txt'), 'change')
        & git -C $worktree add change.txt; & git -C $worktree commit -m 'fixture change' | Out-Null
        $head = (& git -C $worktree rev-parse HEAD).Trim()
        $refresh = @{ repositoryPath = $repo; worktreePath = $worktree; remote = 'origin'; baseBranch = 'master'; recordedTargetSha = $fetch.data.baseSha }
        $refreshed = Invoke-PsJson $script:GitScript @('-Operation','refresh','-InputPath',(New-InputPath $refresh 'refresh'))
        Assert-True (-not $refreshed.data.changed) 'unchanged integration target must not invalidate approval because feature HEAD differs'
        $push = @{ repositoryPath = $repo; worktreePath = $worktree; branch = $branch.branch; expectedHeadSha = $head; remote = 'origin' }
        $wrongBranch = $push.Clone(); $wrongBranch.branch = 'codex/other-owned-branch'
        $wrongBranchResult = Invoke-PsJson $script:GitScript @('-Operation','push','-InputPath',(New-InputPath $wrongBranch 'wrong-branch')) $false
        Assert-True (-not $wrongBranchResult.ok) 'push must reject a checkout/branch ownership mismatch before network use'
        $pushed = Invoke-PsJson $script:GitScript @('-Operation','push','-InputPath',(New-InputPath $push 'push'))
        Assert-Equal $head $pushed.data.remoteHeadSha 'remote reviewed head'
    }

    if ($script:Failed -gt 0) { throw "$($script:Failed) automation fixture(s) failed." }
    Write-Output "Passed $($script:Passed) automation fixtures."
} finally {
    if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
}
