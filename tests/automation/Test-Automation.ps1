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
        Assert-Equal 'needs_input' $expiredResult.data.decision 'wall-clock expiry must block new external work'
        $expiredPacketRequest = Copy-JsonObject $packetRequest; $expiredPacketRequest.packetId = 'packet-coordinate-expired'; $expiredPacketRequest.deadline.startedAtUtc = '1999-01-01T00:00:00Z'; $expiredPacketRequest.deadline.deadlineUtc = '2000-01-01T02:00:00Z'
        $expiredPacket = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $expiredPacketRequest 'coordinate-expired-packet-request'),'-StateRoot',$coordRoot)
        $expiredPacketDispatch = Copy-JsonObject $dispatch; $expiredPacketDispatch.actionId = 'dispatch-packet-expired'; $expiredPacketDispatch.packetReference = @{ path = $expiredPacket.data.packetPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $expiredPacket.data.packetPath).Hash.ToLowerInvariant() }; $expiredPacketDispatch.Remove('remainingMinutes')
        $expiredPacketResult = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $expiredPacketDispatch 'coordinate-packet-expired-dispatch'),'-StateRoot',$coordRoot)
        Assert-Equal 'needs_input' $expiredPacketResult.data.decision 'an expired packet must block dispatch even without a caller-supplied remainingMinutes'
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
    }

    Test-Case 'require trusted review acceptance before publication preparation' {
        $publishRoot = Join-Path $script:FixtureRoot 'publication-state'; $init = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$publishRoot); $claim = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; repositoryIdentity = 'publication-repo'; expectedRevision = $init.revision } 'publication-claim'),'-StateRoot',$publishRoot); $reserved = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; expectedRevision = $claim.revision } 'publication-reserve'),'-StateRoot',$publishRoot)
        $preparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'preparing'; expectedRevision = $reserved.revision } 'publication-preparing'),'-StateRoot',$publishRoot); $implementing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'implementing'; expectedRevision = $preparing.revision } 'publication-implementing'),'-StateRoot',$publishRoot); $reviewing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'reviewing'; expectedRevision = $implementing.revision } 'publication-reviewing'),'-StateRoot',$publishRoot)
        $contextPath = Join-Path $script:FixtureRoot 'publication-context.json'; [IO.File]::WriteAllText($contextPath, 'publication context', [Text.UTF8Encoding]::new($false)); $cleanWorktree = Join-Path $script:FixtureRoot 'publication-worktree'; $sourceRepository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path; & git clone --no-local $sourceRepository $cleanWorktree 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Could not create the clean publication worktree fixture.' }; $cleanBranch = ((& git -C $cleanWorktree rev-parse --abbrev-ref HEAD).Trim()); $cleanHead = ((& git -C $cleanWorktree rev-parse HEAD).Trim()); $packetRequest = @{ packetId = 'packet-publication'; sessionId = 'synthetic-session-01'; runId = 'publication-run'; ticket = @{ ticketKey = 'project:123:issue:802'; projectId = 123; kind = 'issue'; id = 802; ref = 802; title = 'Publication fixture' }; contextPath = $contextPath; criteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.' }); repository = @{ identity = 'publication-repo'; repositoryPath = $cleanWorktree; worktreePath = $cleanWorktree; branch = $cleanBranch; baseSha = $cleanHead }; requiredCommands = @('synthetic-check'); unresolvedRequirements = @(); authority = @{ authorizedActions = @('dispatch','publish'); excludedActions = @() }; deadline = @{ startedAtUtc = '2026-09-30T00:00:00Z'; deadlineUtc = '2099-09-30T00:00:00Z'; elapsedBudgetMinutes = 120 }; profiles = @{ coordinator = @{ model = 'gpt-6.1-sol'; effort = 'high' }; implementer = @{ model = 'gpt-5.6-luna'; effort = 'xhigh' }; reviewer = @{ model = 'gpt-6.1-sol'; effort = 'high' } } }; $packetCreated = Invoke-PsJson $script:PacketScript @('-Operation','create','-InputPath',(New-InputPath $packetRequest 'publication-packet-request'),'-StateRoot',$publishRoot); $packetPath = [string]$packetCreated.data.packetPath; $packetReference = @{ path = $packetPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packetPath).Hash.ToLowerInvariant() }
         $checkActionRequest = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'publish-check-action'; actionKind = 'implementation_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $reviewing.revision }; $preparedCheckAction = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath $checkActionRequest 'publication-check-action'),'-StateRoot',$publishRoot)
         $reviewPrompt = Join-Path $script:FixtureRoot 'publication-review-prompt.md'; [IO.File]::WriteAllText($reviewPrompt, 'Review {{reviewedSha}} with {{schemaPath}}.', [Text.UTF8Encoding]::new($false)); $reviewPromptReference = @{ path = $reviewPrompt; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reviewPrompt).Hash.ToLowerInvariant() }; $reviewDispatch = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'review-action'; workerId = 'reviewer-thread'; reviewedSha = $cleanHead; packetReference = $packetReference; promptReference = $reviewPromptReference }; $preparedReview = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $reviewDispatch 'publication-review-dispatch'),'-StateRoot',$publishRoot); Assert-Equal 'publish-check-action' $preparedReview.data.action.reviewCheckActionIds[0] 'review dispatch should auto-bind prepared verification actions'
        $earlyPublication = Copy-JsonObject $reviewDispatch; $earlyPublication.actionId = 'publication-before-review'; $earlyPublication.workerId = 'publisher-thread'; $earlyPublication.Remove('promptReference'); $earlyPublication.Remove('reviewedSha'); $earlyResult = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-publication','-InputPath',(New-InputPath $earlyPublication 'publication-before-review'),'-StateRoot',$publishRoot) $false; Assert-True (-not $earlyResult.ok) 'publication must be blocked before an accepted review'
         $evidenceRoot = $publishRoot; $metadataRequest = @{ packetPath = $packetCreated.data.packetPath; packetHash = $packetCreated.data.packetHash; actionId = 'publish-check-action' }; $metadata = Invoke-PsJson $script:EvidenceScript @('-Operation','initialize-run','-InputPath',(New-InputPath $metadataRequest 'publication-check-metadata'),'-StateRoot',$publishRoot); $logPath = Join-Path $script:FixtureRoot 'publication-check.log'; [IO.File]::WriteAllText($logPath, 'synthetic check passed', [Text.UTF8Encoding]::new($false)); $capture = Invoke-PsJson $script:EvidenceScript @('-Operation','capture','-InputPath',(New-InputPath @{ metadataPath = $metadata.data.metadataPath; actualExitCode = 0; logPath = $logPath } 'publication-check-capture'),'-StateRoot',$publishRoot); $evidencePath = $capture.data.evidencePath; $evidenceReference = @{ path = $evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $evidencePath).Hash.ToLowerInvariant(); evidenceId = $capture.data.evidenceId }; $record = Copy-JsonObject $capture.data.evidence
         $receiptPath = Join-Path $script:FixtureRoot 'publication-receipt.json'; $receipt = @{ schemaVersion = 1; kind = 'review'; runId = 'publication-run'; actionId = 'review-action'; ticketKey = 'project:123:issue:802'; scopeHash = $packetCreated.data.scopeHash; baseSha = $cleanHead; reviewedSha = $cleanHead; verdict = 'pass'; reviewerModel = 'gpt-6.1-sol'; reviewerEffort = 'high'; criteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.'; passed = $true; evidence = $capture.data.evidenceId }); checks = @(@{ checkId = 'publish-check'; command = 'synthetic-check'; exitCode = 0; passed = $true; evidence = $capture.data.evidenceId; evidenceId = $capture.data.evidenceId; criterionIds = @('criterion-1') }); findings = @() }; Write-JsonFile $receipt $receiptPath; $receiptReference = @{ path = $receiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant() }; $resultPath = Join-Path $script:FixtureRoot 'publication-result.json'; Write-JsonFile @{ resultId = 'review-action'; cursor = 'publication-cursor'; actionId = 'review-action'; workerId = 'reviewer-thread'; status = 'completed'; decision = 'publish'; nextPhase = 'publishing'; receiptReference = $receiptReference; evidenceReferences = @($evidenceReference); evidenceStateRoot = $publishRoot; reviewContext = @{ currentSha = 'attacker-controlled'; currentScopeHash = 'wrong-scope'; currentBaseSha = 'wrong-base'; expectedRunId = 'wrong-run'; expectedActionId = 'review-action'; expectedTicketKey = 'project:123:issue:802'; correctionRound = 99 } } $resultPath
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
         $shippedPrompt = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\assets\reviewer-prompt.md'; $shippedDispatch = Copy-JsonObject $reviewDispatch; $shippedDispatch.actionId = 'shipped-review-template'; $shippedDispatch.promptReference = @{ path = (Resolve-Path $shippedPrompt).Path; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shippedPrompt).Hash.ToLowerInvariant() }; $shipped = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $shippedDispatch 'publication-shipped-template'),'-StateRoot',$publishRoot); Assert-Equal $cleanHead $shipped.data.action.previousReviewedSha 'follow-up reviewer dispatch must freeze the latest accepted reviewed revision'; $shippedText = Get-Content -Raw -LiteralPath $shipped.data.action.prompt.path; Assert-True ($shippedText -notmatch [regex]::Escape($cleanWorktree + '\.agents')) 'shipped reviewer template must not depend on a target checkout .agents directory'; Assert-True ($shippedText -match [regex]::Escape((Resolve-Path (Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\references\review-receipt-v1.schema.json')).Path)) 'shipped reviewer template must use the durable skill schema path'
         $correctionRoot = Join-Path $script:FixtureRoot 'publication-correction-state'; $correctionInit = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$syntheticPath,'-StateRoot',$correctionRoot); $correctionClaim = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; repositoryIdentity = 'publication-repo'; expectedRevision = $correctionInit.revision } 'correction-claim'),'-StateRoot',$correctionRoot); $correctionReserve = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; expectedRevision = $correctionClaim.revision } 'correction-reserve'),'-StateRoot',$correctionRoot); $correctionPreparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'preparing'; expectedRevision = $correctionReserve.revision } 'correction-preparing'),'-StateRoot',$correctionRoot); $correctionImplementing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'implementing'; expectedRevision = $correctionPreparing.revision } 'correction-implementing'),'-StateRoot',$correctionRoot); $correctionReviewing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'reviewing'; expectedRevision = $correctionImplementing.revision } 'correction-reviewing'),'-StateRoot',$correctionRoot)
          $correctionCheck = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'correction-check-action'; actionKind = 'implementation_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $cleanHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $correctionReviewing.revision } 'correction-check'),'-StateRoot',$correctionRoot); $correctionMetadata = Invoke-PsJson $script:EvidenceScript @('-Operation','initialize-run','-InputPath',(New-InputPath @{ packetPath = $packetCreated.data.packetPath; packetHash = $packetCreated.data.packetHash; actionId = 'correction-check-action' } 'correction-metadata'),'-StateRoot',$correctionRoot); $correctionLog = Join-Path $script:FixtureRoot 'correction-check.log'; [IO.File]::WriteAllText($correctionLog, 'correction check failed before repair', [Text.UTF8Encoding]::new($false)); $correctionEvidence = Invoke-PsJson $script:EvidenceScript @('-Operation','capture','-InputPath',(New-InputPath @{ metadataPath = $correctionMetadata.data.metadataPath; actualExitCode = 1; logPath = $correctionLog } 'correction-capture'),'-StateRoot',$correctionRoot)
          $correctionReviewDispatch = Copy-JsonObject $reviewDispatch; $correctionReviewDispatch.actionId = 'correction-review'; $correctionReviewDispatch.reviewedSha = $cleanHead; $preparedCorrectionReview = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $correctionReviewDispatch 'correction-review-dispatch'),'-StateRoot',$correctionRoot)
         $changesReceipt = Copy-JsonObject $receipt; $changesReceipt.actionId = 'correction-review'; $changesReceipt.verdict = 'changes_requested'; $changesReceipt.criteria[0].passed = $false; $changesReceipt.criteria[0].evidence = 'Correction is required.'; $changesReceipt.checks[0].evidenceId = $correctionEvidence.data.evidenceId; $changesReceipt.checks[0].exitCode = 1; $changesReceipt.checks[0].passed = $false; $changesReceipt.findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'The initial implementation check failed.'; requestedChange = 'Correct the implementation and rerun the check.'; disposition = 'open' }); $changesReceiptPath = Join-Path $script:FixtureRoot 'correction-receipt.json'; Write-JsonFile $changesReceipt $changesReceiptPath; $changesResultPath = Join-Path $script:FixtureRoot 'correction-result.json'; Write-JsonFile @{ resultId = 'correction-review'; cursor = 'correction-cursor'; actionId = 'correction-review'; workerId = 'reviewer-thread'; status = 'completed'; decision = 'correct'; nextPhase = 'correcting'; receiptReference = @{ path = $changesReceiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $changesReceiptPath).Hash.ToLowerInvariant() }; evidenceReferences = @(@{ path = $correctionEvidence.data.evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $correctionEvidence.data.evidencePath).Hash.ToLowerInvariant(); evidenceId = $correctionEvidence.data.evidenceId }); evidenceStateRoot = $correctionRoot } $changesResultPath; $changesAccepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; packetReference = $packetReference; resultReference = @{ path = $changesResultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $changesResultPath).Hash.ToLowerInvariant() } } 'correction-accept'),'-StateRoot',$correctionRoot); Assert-Equal 'correct' $changesAccepted.data.decision 'changes_requested review should route to correction'; Assert-Equal 'correcting' $changesAccepted.data.phase 'changes_requested review should preserve the correction phase'
         $correctionImplementing2 = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'implementing'; expectedRevision = $changesAccepted.data.revision } 'correction-implementing-2'),'-StateRoot',$correctionRoot); $null = & git -C $cleanWorktree commit --allow-empty --quiet -m 'Apply synthetic correction'; Assert-Equal 0 $LASTEXITCODE 'synthetic correction should commit'; $correctionHead = ((& git -C $cleanWorktree rev-parse HEAD).Trim()); $correctionReviewing2 = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; toPhase = 'reviewing'; expectedRevision = $correctionImplementing2.revision } 'correction-reviewing-2'),'-StateRoot',$correctionRoot)
         $correctionCheck2 = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; actionId = 'correction-check-action-2'; actionKind = 'implementation_check'; input = @{ command = 'synthetic-check'; workingDirectory = $cleanWorktree; criterionIds = @('criterion-1'); coverage = @{ revision = $correctionHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; files = @('src/app.cs') } }; expectedRevision = $correctionReviewing2.revision } 'correction-check-2'),'-StateRoot',$correctionRoot); $correctionMetadata2 = Invoke-PsJson $script:EvidenceScript @('-Operation','initialize-run','-InputPath',(New-InputPath @{ packetPath = $packetCreated.data.packetPath; packetHash = $packetCreated.data.packetHash; actionId = 'correction-check-action-2' } 'correction-metadata-2'),'-StateRoot',$correctionRoot); $correctionLog2 = Join-Path $script:FixtureRoot 'correction-check-2.log'; [IO.File]::WriteAllText($correctionLog2, 'correction check passed', [Text.UTF8Encoding]::new($false)); $correctionEvidence2 = Invoke-PsJson $script:EvidenceScript @('-Operation','capture','-InputPath',(New-InputPath @{ metadataPath = $correctionMetadata2.data.metadataPath; actualExitCode = 0; logPath = $correctionLog2 } 'correction-capture-2'),'-StateRoot',$correctionRoot); $followupPrompt = Copy-JsonObject $reviewDispatch; $followupPrompt.actionId = 'correction-review-2'; $followupPrompt.reviewedSha = $correctionHead; $followup = Invoke-PsJson $script:CoordinateScript @('-Operation','prepare-dispatch','-InputPath',(New-InputPath $followupPrompt 'correction-followup-dispatch'),'-StateRoot',$correctionRoot); Assert-Equal $cleanHead $followup.data.action.previousReviewedSha 'correction re-review should derive the prior changes_requested revision'
         $followReceipt = Copy-JsonObject $receipt; $followReceipt.actionId = 'correction-review-2'; $followReceipt.reviewedSha = $correctionHead; $followReceipt.checks[0].evidenceId = $correctionEvidence2.data.evidenceId; $followReceipt.reviewDelta = @{ fromSha = $cleanHead; toSha = $correctionHead; changedPaths = @('src/app.cs'); documentationChanged = $false; documentationPaths = @(); documentationAssessment = 'No documentation changed in this correction.'; reusedCheckIds = @(); reuseJustification = '' }; $followCoverage = @{ revision = $correctionHead; baseSha = $cleanHead; environmentHash = 'env'; dependenciesHash = 'deps'; changedKind = 'code'; changedPaths = @('src/app.cs') }; $followReviewRequest = @{ receipt = $followReceipt; expectedCriteria = @(@{ id = 'criterion-1'; text = 'Publish only the reviewed revision.' }); currentSha = $correctionHead; currentScopeHash = $packetCreated.data.scopeHash; currentBaseSha = $cleanHead; expectedRunId = 'publication-run'; expectedActionId = 'correction-review-2'; expectedTicketKey = 'project:123:issue:802'; correctionRound = 1; remainingMinutes = 10; previousReviewedSha = $cleanHead; currentCoverage = $followCoverage; evidenceStateRoot = $correctionRoot; evidenceReferences = @(@{ path = $correctionEvidence2.data.evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $correctionEvidence2.data.evidencePath).Hash.ToLowerInvariant(); evidenceId = $correctionEvidence2.data.evidenceId }) }; $missingFollowDelta = Copy-JsonObject $followReviewRequest; $missingFollowDelta.receipt.Remove('reviewDelta'); $missingFollowDeltaDecision = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $missingFollowDelta 'correction-missing-delta')); Assert-Equal 'missing_review_delta_assessment' $missingFollowDeltaDecision.data.reason 'correction re-review must require reviewDelta'; $followReceiptPath = Join-Path $script:FixtureRoot 'correction-followup-receipt.json'; Write-JsonFile $followReceipt $followReceiptPath; $followResultPath = Join-Path $script:FixtureRoot 'correction-followup-result.json'; Write-JsonFile @{ resultId = 'correction-review-2'; cursor = 'correction-followup-cursor'; actionId = 'correction-review-2'; workerId = 'reviewer-thread'; status = 'completed'; decision = 'publish'; nextPhase = 'publishing'; receiptReference = @{ path = $followReceiptPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $followReceiptPath).Hash.ToLowerInvariant() }; evidenceReferences = @(@{ path = $correctionEvidence2.data.evidencePath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $correctionEvidence2.data.evidencePath).Hash.ToLowerInvariant(); evidenceId = $correctionEvidence2.data.evidenceId }); evidenceStateRoot = $correctionRoot; currentCoverage = $followCoverage } $followResultPath; $followAccepted = Invoke-PsJson $script:CoordinateScript @('-Operation','accept-result','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; ticketKey = 'project:123:issue:802'; packetReference = $packetReference; resultReference = @{ path = $followResultPath; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $followResultPath).Hash.ToLowerInvariant() } } 'correction-followup-accept'),'-StateRoot',$correctionRoot); Assert-Equal 'publish' $followAccepted.data.decision 'proper correction delta should publish after re-review'
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
        Assert-True (-not $quiet.data.waitThreadsArguments.targets[0].Contains('hostId')) 'absent native wait host IDs must be omitted rather than null'
        $noTarget = Copy-JsonObject $unchanged; $noTarget.Remove('threadId'); $noTarget.Remove('afterCursor'); $noTarget.Remove('targets'); $noTargetResult = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $noTarget 'wait-no-target'),'-StateRoot',$waitRoot) $false; Assert-True (-not $noTargetResult.ok) 'a native wait descriptor without targets must fail closed'
        $after = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$waitRoot)
        Assert-Equal $before.revision $after.revision 'unchanged wait must not advance the registry revision'
        $completed = Copy-JsonObject $unchanged; $completed.waitStatus = 'completed'
        $detail = Invoke-PsJson $script:CoordinateScript @('-Operation','observe-wait','-InputPath',(New-InputPath $completed 'wait-completed'),'-StateRoot',$waitRoot)
        Assert-Equal 'fetch_result' $detail.data.decision 'completion should trigger one detailed result read'
        Assert-Equal 'read_thread' $detail.data.nativeOperation 'completion should use read_thread only after a wake'
        $heartbeat = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; notificationPolicy = 'failed_runs_only' } 'heartbeat-create'),'-StateRoot',$waitRoot)
        Assert-Equal 'create_heartbeat' $heartbeat.data.decision 'first heartbeat plan should create one session heartbeat'
        $set = @{ sessionId = 'synthetic-session-01'; ownerGeneration = 1; expectedRevision = $after.revision; heartbeatId = 'heartbeat-1'; scheduleState = 'ACTIVE' }
        $setResult = Invoke-PsJson $script:StateScript @('-Operation','set-heartbeat','-InputPath',(New-InputPath $set 'heartbeat-set'),'-StateRoot',$waitRoot)
        $reuse = Invoke-PsJson $script:CoordinateScript @('-Operation','heartbeat-plan','-InputPath',(New-InputPath @{ sessionId = 'synthetic-session-01'; notificationPolicy = 'failed_runs_only' } 'heartbeat-reuse'),'-StateRoot',$waitRoot)
        Assert-Equal 'reuse_heartbeat' $reuse.data.decision 'later plans should reuse the existing session heartbeat'
        Assert-True $reuse.data.heartbeat.quietWhenUnchanged 'heartbeat should stay quiet when no worker state changed'
        Assert-True (-not $reuse.data.heartbeat.nestedSchedules) 'heartbeat plan must not create nested schedules'
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
        $stop = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $exhausted 'review-exhausted'))
        Assert-Equal 'needs_input' $stop.data.decision 'round limit should escalate'
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
        Assert-Equal 'needs_input' $expiredPassResult.data.decision 'a passing receipt must not bypass an exhausted wall-clock budget'
        Assert-Equal 'elapsed_budget' $expiredPassResult.data.reason 'deadline gate should be explicit'
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
        Assert-Equal 'needs_input' $budgetResult.data.decision 'repair must stop when the wall-clock budget is exhausted'

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
        $context = @{ kind = 'story'; projectId = 1; ref = 2; detailPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); taskPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); selectedTaskIds = @(3); linkedStoryKeys = @() }
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
