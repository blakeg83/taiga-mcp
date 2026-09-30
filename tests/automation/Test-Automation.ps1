[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Root = Join-Path ([IO.Path]::GetTempPath()) ("TaigaMCP automation {0}" -f ([Guid]::NewGuid().ToString('N')))
$script:StateScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-state.ps1'
$script:GitScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-git.ps1'
$script:PlanScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-plan.ps1'
$script:ReviewScript = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\scripts\workflow-review.ps1'
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

function Test-Case {
    param([string] $Name, [scriptblock] $Body)
    try { & $Body; $script:Passed++; Write-Output "PASS $Name" } catch { $script:Failed++; Write-Output "FAIL $Name :: $($_.Exception.Message)" }
}

try {
    New-Item -ItemType Directory -Path $script:FixtureRoot -Force | Out-Null
    $stateRoot = Join-Path $script:FixtureRoot 'state with spaces'
    $syntheticPath = Join-Path $PSScriptRoot '..\..\.agents\skills\taiga-ticket-loop\assets\synthetic-run.json'

    Test-Case 'validate exact reviewer profile' {
        $result = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-Json','{"receipt":{"runId":"r","actionId":"a","ticketKey":"t","scopeHash":"s","baseSha":"b","reviewedSha":"c","verdict":"pass","reviewerModel":"gpt-6.1-sol","reviewerEffort":"high","findings":[],"criteria":[{"id":"criterion-1","passed":true,"evidence":"fixture"}],"checks":[{"command":"test","exitCode":0,"evidence":"fixture","passed":true}]}}')
        Assert-True $result.ok 'review receipt should validate'
        $correction = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-Json','{"receipt":{"runId":"r","actionId":"a","ticketKey":"t","scopeHash":"s","baseSha":"b","reviewedSha":"c","verdict":"changes_requested","reviewerModel":"gpt-6.1-sol","reviewerEffort":"high","findings":[{"id":"F1","severity":"high","evidence":"fixture","requestedChange":"fix"}],"criteria":[{"id":"criterion-1","passed":false,"evidence":"failed fixture"}],"checks":[{"command":"test","exitCode":1,"evidence":"failed fixture","passed":false}]}}')
        Assert-Equal 1 $correction.data.criterionFailures 'failed criteria should remain review evidence'
        Assert-Equal 1 $correction.data.checkFailures 'failed checks should remain review evidence'
        $passingFailure = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-Json','{"receipt":{"runId":"r","actionId":"a","ticketKey":"t","scopeHash":"s","baseSha":"b","reviewedSha":"c","verdict":"pass","reviewerModel":"gpt-6.1-sol","reviewerEffort":"high","findings":[],"criteria":[{"id":"criterion-1","passed":true,"evidence":"fixture"}],"checks":[{"command":"test","exitCode":1,"evidence":"failed fixture","passed":false}]}}') $false
        Assert-True (-not $passingFailure.ok) 'passing review must reject failed checks'
        $badConfig = @{ sessionId = 'wrong-profile'; coordinator = @{ threadId = 't'; hostId = 'local' }; config = @{ reviewerProfile = @{ model = 'gpt-6-sol'; effort = 'high' } } }
        $badPath = New-InputPath $badConfig 'bad-profile'
        $bad = Invoke-PsJson $script:StateScript @('-Operation','initialize-session','-InputPath',$badPath,'-StateRoot',(Join-Path $script:FixtureRoot 'bad-profile')) $false
        Assert-True (-not $bad.ok) 'unsupported reviewer profile must be rejected'
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
        $receipt = @{ runId = 'run'; actionId = 'review-0'; ticketKey = 'project:1:issue:1'; scopeHash = 'scope'; baseSha = 'base'; reviewedSha = 'head'; verdict = 'changes_requested'; reviewerModel = 'gpt-6.1-sol'; reviewerEffort = 'high'; findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix' }); criteria = @(@{ id = 'criterion-1'; passed = $true; evidence = 'criterion evidence' }); checks = @(@{ command = 'test'; exitCode = 0; passed = $true; evidence = 'check evidence' }) }
        $request = @{ receipt = $receipt; currentSha = 'head'; currentScopeHash = 'scope'; currentBaseSha = 'base'; expectedRunId = 'run'; expectedActionId = 'review-0'; expectedTicketKey = 'project:1:issue:1'; expectedCriteriaIds = @('criterion-1'); correctionRound = 0; maxCorrectionRounds = 3; remainingMinutes = 10 }
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
        $failedCriteria = $request.Clone(); $failedCriteria.receipt = $receipt.Clone(); $failedCriteria.receipt.criteria = @(@{ id = 'criterion-1'; passed = $false; evidence = 'failed fixture' })
        $failedCriteriaResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $failedCriteria 'review-failed-criteria'))
        Assert-Equal 'correct' $failedCriteriaResult.data.decision 'failed criteria should route a correction'
        $failedCheck = $request.Clone(); $failedCheck.receipt = $receipt.Clone(); $failedCheck.receipt.checks = @(@{ command = 'test'; exitCode = 1; evidence = 'failed fixture'; passed = $false })
        $failedCheckResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $failedCheck 'review-failed-check'))
        Assert-Equal 'correct' $failedCheckResult.data.decision 'failed checks should route a correction'
        $passingFailure = $request.Clone(); $passingFailure.receipt = $receipt.Clone(); $passingFailure.receipt.verdict = 'pass'; $passingFailure.receipt.checks = @(@{ command = 'test'; exitCode = 1; evidence = 'failed fixture'; passed = $false })
        $passingFailureResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $passingFailure 'review-passing-failure')) $false
        Assert-True (-not $passingFailureResult.ok) 'a pass with failed checks must remain blocked'
    }

    Test-Case 'capture complete Taiga pages and reconcile uncertain writes' {
        $context = @{ kind = 'story'; projectId = 1; ref = 2; detailPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); commentPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); taskPages = @(@{ page = 1; hasMore = $false; nextPage = $null }); selectedTaskIds = @(3); linkedStoryKeys = @() }
        $captured = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $context 'taiga-context'))
        Assert-True $captured.data.complete 'complete Taiga pages should pass'
        $unknown = $context.Clone(); $unknown.commentPages = @(@{ page = 1 })
        $unknownResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $unknown 'taiga-unknown')) $false
        Assert-True (-not $unknownResult.ok) 'unknown pagination must be incomplete'
        $incomplete = $context.Clone(); $incomplete.commentPages = @(@{ page = 1; hasMore = $true; nextPage = 2 })
        $incompleteResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $incomplete 'taiga-incomplete')) $false
        Assert-True (-not $incompleteResult.ok) 'hasMore=true without a captured next page must be incomplete'
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
