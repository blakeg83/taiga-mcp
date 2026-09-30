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
        $result = Invoke-PsJson $script:StateScript @('-Operation','validate-receipt','-Json','{"receipt":{"runId":"r","actionId":"a","ticketKey":"t","scopeHash":"s","baseSha":"b","reviewedSha":"c","verdict":"pass","findings":[],"criteria":[],"checks":[]}}')
        Assert-True $result.ok 'review receipt should validate'
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

    Test-Case 'claim ticket, reserve two slots, and reject overflow' {
        $claimA = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; repositoryIdentity = 'synthetic-repo'; expectedRevision = 1 }
        $claimAPath = New-InputPath $claimA 'claim-a'
        $a = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',$claimAPath,'-StateRoot',$stateRoot)
        $claimB = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:457'; repositoryIdentity = 'synthetic-repo'; expectedRevision = $a.revision }
        $b = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claimB 'claim-b'),'-StateRoot',$stateRoot)
        $reserveA = @{ sessionId = 'synthetic-session-01'; ticketKey = $claimA.ticketKey; expectedRevision = $b.revision }
        $ra = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath $reserveA 'reserve-a'),'-StateRoot',$stateRoot)
        $reserveB = @{ sessionId = 'synthetic-session-01'; ticketKey = $claimB.ticketKey; expectedRevision = $ra.revision }
        $rb = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath $reserveB 'reserve-b'),'-StateRoot',$stateRoot)
        $claimC = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:458'; repositoryIdentity = 'synthetic-repo'; expectedRevision = $rb.revision }
        $c = Invoke-PsJson $script:StateScript @('-Operation','claim-ticket','-InputPath',(New-InputPath $claimC 'claim-c'),'-StateRoot',$stateRoot)
        $reserveC = @{ sessionId = 'synthetic-session-01'; ticketKey = $claimC.ticketKey; expectedRevision = $c.revision }
        $overflow = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath $reserveC 'reserve-c'),'-StateRoot',$stateRoot) $false
        Assert-True (-not $overflow.ok) 'third repository slot must be rejected'
        $stale = Invoke-PsJson $script:StateScript @('-Operation','reserve-slot','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ticketKey = $claimA.ticketKey; expectedRevision = 1 }) 'stale'),'-StateRoot',$stateRoot) $false
        Assert-True (-not $stale.ok) 'stale revision must be rejected'
    }

    Test-Case 'enforce lifecycle, action reconciliation, and cursor uniqueness' {
        $inspect = Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$stateRoot); $revision = $inspect.revision
        $transition = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; toPhase = 'preparing'; expectedRevision = $revision }
        $preparing = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath $transition 'preparing'),'-StateRoot',$stateRoot)
        $implementing = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; toPhase = 'implementing'; expectedRevision = $preparing.revision }
        $impl = Invoke-PsJson $script:StateScript @('-Operation','transition','-InputPath',(New-InputPath $implementing 'implementing'),'-StateRoot',$stateRoot)
        $action = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; actionId = 'worker-message-01'; actionKind = 'send_worker_message'; target = @{ threadId = 'worker-a' }; input = @{ marker = 'synthetic' }; expectedRevision = $impl.revision }
        $prepared = Invoke-PsJson $script:StateScript @('-Operation','prepare-action','-InputPath',(New-InputPath $action 'action'),'-StateRoot',$stateRoot)
        $observed = @{ sessionId = 'synthetic-session-01'; actionId = 'worker-message-01'; observationStatus = 'uncertain'; reconcileRequired = $true; expectedRevision = $prepared.revision }
        $uncertain = Invoke-PsJson $script:StateScript @('-Operation','record-observation','-InputPath',(New-InputPath $observed 'uncertain'),'-StateRoot',$stateRoot)
        Assert-True $uncertain.data.reconciliationRequired 'uncertain outcome must require reconciliation'
        $consumed = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; cursor = 'cursor-1'; result = @{ completed = $false }; expectedRevision = $uncertain.revision }
        $result = Invoke-PsJson $script:StateScript @('-Operation','consume-result','-InputPath',(New-InputPath $consumed 'result'),'-StateRoot',$stateRoot)
        $duplicate = Invoke-PsJson $script:StateScript @('-Operation','consume-result','-InputPath',(New-InputPath (@{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; cursor = 'cursor-1'; expectedRevision = $result.revision }) 'duplicate'),'-StateRoot',$stateRoot) $false
        Assert-True (-not $duplicate.ok) 'duplicate worker result must be rejected'
        $pause = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; reason = 'fixture pause'; expectedRevision = $result.revision }
        $paused = Invoke-PsJson $script:StateScript @('-Operation','pause-intent','-InputPath',(New-InputPath $pause 'pause'),'-StateRoot',$stateRoot)
        $resume = @{ sessionId = 'synthetic-session-01'; ticketKey = 'project:123:issue:456'; expectedRevision = $paused.revision }
        $resumed = Invoke-PsJson $script:StateScript @('-Operation','resume-session','-InputPath',(New-InputPath $resume 'resume'),'-StateRoot',$stateRoot)
        Assert-Equal 'implementing' (Invoke-PsJson $script:StateScript @('-Operation','inspect','-StateRoot',$stateRoot)).data.registry.tickets.'project:123:issue:456'.phase 'resume phase'
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
        $receipt = @{ runId = 'run'; actionId = 'review-0'; ticketKey = 'project:1:issue:1'; scopeHash = 'scope'; baseSha = 'base'; reviewedSha = 'head'; verdict = 'changes_requested'; findings = @(@{ id = 'F1'; severity = 'high'; evidence = 'fixture'; requestedChange = 'fix' }); criteria = @('criterion-1'); checks = @('test') }
        $request = @{ receipt = $receipt; currentSha = 'head'; currentScopeHash = 'scope'; currentBaseSha = 'base'; correctionRound = 0; maxCorrectionRounds = 3; remainingMinutes = 10 }
        $correct = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $request 'review-correct'))
        Assert-Equal 'correct' $correct.data.decision 'changes requested should route to same worker'
        $exhausted = $request.Clone(); $exhausted.correctionRound = 3
        $stop = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $exhausted 'review-exhausted'))
        Assert-Equal 'needs_input' $stop.data.decision 'round limit should escalate'
        $stale = $request.Clone(); $stale.currentSha = 'new-head'
        $staleResult = Invoke-PsJson $script:ReviewScript @('-Operation','decide','-InputPath',(New-InputPath $stale 'review-stale'))
        Assert-Equal 'needs_input' $staleResult.data.decision 'stale approval must not publish'
    }

    Test-Case 'capture complete Taiga pages and reconcile uncertain writes' {
        $context = @{ kind = 'story'; projectId = 1; ref = 2; detailPages = @(@{ page = 1; hasMore = $false }); commentPages = @(@{ page = 1; nextPage = $null }); taskPages = @(@{ page = 1; hasMore = $false }); selectedTaskIds = @(3); linkedStoryKeys = @() }
        $captured = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $context 'taiga-context'))
        Assert-True $captured.data.complete 'complete Taiga pages should pass'
        $unknown = $context.Clone(); $unknown.commentPages = @(@{ page = 1 })
        $unknownResult = Invoke-PsJson $script:TaigaScript @('-Operation','capture-context','-InputPath',(New-InputPath $unknown 'taiga-unknown')) $false
        Assert-True (-not $unknownResult.ok) 'unknown pagination must be incomplete'
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
        $push = @{ repositoryPath = $repo; worktreePath = $worktree; branch = $branch.branch; expectedHeadSha = $head; remote = 'origin' }
        $pushed = Invoke-PsJson $script:GitScript @('-Operation','push','-InputPath',(New-InputPath $push 'push'))
        Assert-Equal $head $pushed.data.remoteHeadSha 'remote reviewed head'
    }

    if ($script:Failed -gt 0) { throw "$($script:Failed) automation fixture(s) failed." }
    Write-Output "Passed $($script:Passed) automation fixtures."
} finally {
    if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
}
