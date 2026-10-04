# STATIC CONTRACT CHECK ONLY.
# This file checks documented contract text against a small route matrix. It
# does not execute the skill, call Taiga/Git/Codex tools, or establish
# behavioral evidence. See references/synthetic-walkthroughs.md for recorded
# synthetic walkthrough evidence.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$setupPath = Join-Path $skillRoot 'references/invocation-and-setup.md'
$branchPath = Join-Path $skillRoot 'references/branch-and-continuation.md'
$continuationPath = Join-Path $skillRoot 'references/continuation-note.md'
$promptPath = Join-Path $skillRoot 'assets/implementation-prompt.md'
$branchScenarioPath = Join-Path $PSScriptRoot 'validate-branch-scenarios.ps1'
$walkthroughPath = Join-Path $skillRoot 'references/synthetic-walkthroughs.md'
$taskExecutionPath = Join-Path $skillRoot 'references/task-execution-walkthroughs.md'
$taskExecutionGuidancePath = Join-Path $skillRoot 'references/task-execution.md'
$taskExecutionScriptPath = Join-Path $PSScriptRoot 'validate-task-execution.ps1'
$workerPairPath = Join-Path $skillRoot 'references/worker-pair.md'
$handoffPath = Join-Path $skillRoot 'references/worker-handoffs.md'
$reviewerPromptPath = Join-Path $skillRoot 'assets/reviewer-prompt.md'
$acceptancePath = Join-Path $skillRoot 'references/acceptance.md'
$routingPath = Join-Path $skillRoot 'references/routing-and-escalation.md'
$routingScriptPath = Join-Path $PSScriptRoot 'validate-routing.ps1'
$prDeliveryPath = Join-Path $skillRoot 'references/pr-delivery.md'
$prDeliveryScriptPath = Join-Path $PSScriptRoot 'validate-pr-delivery.ps1'
$mergeApprovalPath = Join-Path $skillRoot 'references/merge-approval.md'
$mergeApprovalScriptPath = Join-Path $PSScriptRoot 'validate-merge-approval.ps1'
$finalEpicReviewPath = Join-Path $skillRoot 'references/final-epic-review.md'
$finalEpicReviewScriptPath = Join-Path $PSScriptRoot 'validate-final-epic-review.ps1'

if (-not (Test-Path $walkthroughPath)) {
    throw 'Missing recorded synthetic walkthrough reference.'
}
if (-not (Test-Path $taskExecutionPath) -or -not (Test-Path $taskExecutionScriptPath)) {
    throw 'Missing ordered task execution scenario evidence.'
}
if (-not (Test-Path $workerPairPath)) {
    throw 'Missing persistent worker-pair contract.'
}
if (-not (Test-Path $handoffPath) -or -not (Test-Path $reviewerPromptPath)) {
    throw 'Missing direct worker handoff or reviewer prompt contract.'
}
if (-not (Test-Path $acceptancePath)) {
    throw 'Missing task/story acceptance contract.'
}
if (-not (Test-Path $routingPath) -or -not (Test-Path $routingScriptPath)) {
    throw 'Missing routing and escalation fixture.'
}
if (-not (Test-Path $prDeliveryPath) -or -not (Test-Path $prDeliveryScriptPath)) {
    throw 'Missing reviewed story PR delivery contract or fixture.'
}
if (-not (Test-Path $mergeApprovalPath) -or -not (Test-Path $mergeApprovalScriptPath)) {
    throw 'Missing Yes/No merge approval contract or fixture.'
}
if (-not (Test-Path $finalEpicReviewPath) -or -not (Test-Path $finalEpicReviewScriptPath)) {
    throw 'Missing final integrated epic review contract or fixture.'
}

$setupText = Get-Content $setupPath -Raw
$normalizedSetup = [regex]::Replace($setupText, '\s+', ' ')
$promptText = Get-Content $promptPath -Raw
$normalizedPrompt = [regex]::Replace($promptText, '\s+', ' ')
$branchText = Get-Content $branchPath -Raw
$normalizedBranch = [regex]::Replace($branchText, '\s+', ' ')
$continuationText = Get-Content $continuationPath -Raw
$normalizedContinuation = [regex]::Replace($continuationText, '\s+', ' ')
$branchScenarioText = Get-Content $branchScenarioPath -Raw
$normalizedBranchScenario = [regex]::Replace($branchScenarioText, '\s+', ' ')
$walkthroughText = Get-Content $walkthroughPath -Raw
$normalizedWalkthrough = [regex]::Replace($walkthroughText, '\s+', ' ')
$taskExecutionText = Get-Content $taskExecutionPath -Raw
$normalizedTaskExecution = [regex]::Replace($taskExecutionText, '\s+', ' ')
$taskExecutionGuidanceText = Get-Content $taskExecutionGuidancePath -Raw
$normalizedTaskExecutionGuidance = [regex]::Replace($taskExecutionGuidanceText, '\s+', ' ')
$workerPairText = Get-Content $workerPairPath -Raw
$normalizedWorkerPair = [regex]::Replace($workerPairText, '\s+', ' ')
$handoffText = Get-Content $handoffPath -Raw
$normalizedHandoff = [regex]::Replace($handoffText, '\s+', ' ')
$reviewerPromptText = Get-Content $reviewerPromptPath -Raw
$normalizedReviewerPrompt = [regex]::Replace($reviewerPromptText, '\s+', ' ')
$acceptanceText = Get-Content $acceptancePath -Raw
$normalizedAcceptance = [regex]::Replace($acceptanceText, '\s+', ' ')
$routingText = Get-Content $routingPath -Raw
$normalizedRouting = [regex]::Replace($routingText, '\s+', ' ')
$prDeliveryText = Get-Content $prDeliveryPath -Raw
$normalizedPrDelivery = [regex]::Replace($prDeliveryText, '\s+', ' ')
$mergeApprovalText = Get-Content $mergeApprovalPath -Raw
$normalizedMergeApproval = [regex]::Replace($mergeApprovalText, '\s+', ' ')
$finalEpicReviewText = Get-Content $finalEpicReviewPath -Raw
$normalizedFinalEpicReview = [regex]::Replace($finalEpicReviewText, '\s+', ' ')

function Assert-DocumentContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedSetup.Contains($Text)) {
        throw "Document assertion failed: $Label"
    }
}

function Assert-PromptContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedPrompt.Contains($Text)) {
        throw "Prompt assertion failed: $Label"
    }
}

function Assert-TaskExecutionContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedTaskExecutionGuidance.Contains($Text)) {
        throw "Task execution assertion failed: $Label"
    }
}

function Assert-BranchContractContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedBranch.Contains($Text)) {
        throw "Branch contract assertion failed: $Label"
    }
}

function Assert-ContinuationContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedContinuation.Contains($Text)) {
        throw "Continuation note assertion failed: $Label"
    }
}

function Assert-BranchScenarioContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedBranchScenario.Contains($Text)) {
        throw "Branch scenario assertion failed: $Label"
    }
}

function Assert-WorkerPairContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedWorkerPair.Contains($Text)) {
        throw "Worker-pair assertion failed: $Label"
    }
}

function Assert-HandoffContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedHandoff.Contains($Text)) {
        throw "Handoff assertion failed: $Label"
    }
}

Assert-DocumentContains 'per-repository mapping' 'one row per resolved repository'
Assert-DocumentContains 'epic mapping guard' 'An epic setup must not collapse multiple repositories'
Assert-DocumentContains 'start gate' 'Reply Start or Cancel.'
Assert-DocumentContains 'read-only discovery' 'Discovery is read-only.'
Assert-DocumentContains 'cancel behavior' '`Cancel` leaves the external systems unchanged'
Assert-DocumentContains 'clarification behavior' 'Ask only for a missing or ambiguous'
Assert-DocumentContains 'behavioral evidence reference' 'synthetic-walkthroughs.md'
Assert-DocumentContains 'branch contract reference' 'branch and continuation'
Assert-DocumentContains 'fresh base capture' 'captures a fresh base SHA'
Assert-DocumentContains 'feature branch gate' 'creates one uniquely named feature branch'
Assert-DocumentContains 'story branch lineage' 'distinct managed worktree and story branch'
Assert-DocumentContains 'merge advancement gate' 'provider confirms the previous PR merged'
Assert-DocumentContains 'dirty checkout preservation' 'dirty user checkout'
Assert-DocumentContains 'persistent pair reference' 'persistent story worker pair'
Assert-DocumentContains 'pair resolution gate' 'resolves both results to usable'
Assert-DocumentContains 'pending ID guard' 'pending `clientThreadId` is never a message destination'
Assert-PromptContains 'ordered task acceptance gate' 'reviewer acceptance of the exact current task commit'
Assert-PromptContains 'acceptance before advancement' 'explicit reviewer acceptance of the exact current task commit recorded'
Assert-PromptContains 'human status decision' 'A human status is never replaced automatically'
Assert-PromptContains 'pair authorization' 'worker-to-worker and worker-to-coordinator messages'
Assert-PromptContains 'no peer creation' 'Never create another worker'
Assert-PromptContains 'per-task conditional gate' 'In `per_task` mode, do not start the next task'
Assert-PromptContains 'story-end conditional gate' 'In `story_end_only` mode, start the next ordered task'
if (-not $normalizedReviewerPrompt.Contains('read-only reviewer')) {
    throw 'Reviewer prompt assertion failed: read-only role'
}
if (-not $normalizedReviewerPrompt.Contains('gpt-6.1-sol')) {
    throw 'Reviewer prompt assertion failed: exact reviewer profile'
}
if (-not $normalizedAcceptance.Contains('per_task (default)') -or
    -not $normalizedAcceptance.Contains('story_end_only')) {
    throw 'Acceptance assertion failed: review mode choices'
}
if (-not $normalizedAcceptance.Contains('Story #<ref> approved') -or
    -not $normalizedAcceptance.Contains('Reviewed HEAD: <exact commit SHA>')) {
    throw 'Acceptance assertion failed: final story approval binding'
}
Assert-TaskExecutionContains 'explicit human status decision' 'A human status is never replaced automatically'
Assert-TaskExecutionContains 'preserve-or-replace decision' 'explicit decision to preserve the human status and stop, or to replace it'
Assert-TaskExecutionContains 'per-task advancement gate' 'In `per_task` mode, only an independent'
Assert-TaskExecutionContains 'story-end advancement gate' 'In `story_end_only` mode, implementation evidence may release'
Assert-TaskExecutionContains 'story-end accepted gate' 'cannot become `mapping.accepted`/Done until'
Assert-BranchContractContains 'managed worktree handoff' 'create_worktree({ name:'
Assert-BranchContractContains 'worker path receipt' 'The coordinator records the returned absolute path'
Assert-BranchContractContains 'implementer ownership' 'implementer may write source'
Assert-BranchContractContains 'reviewer read-only boundary' 'reviewer is read-only'
Assert-ContinuationContains 'minimal note fields' 'Review: <pending/approved/changes_requested>'
Assert-ContinuationContains 'ordered story scope' 'stories: <ordered story refs>'
Assert-ContinuationContains 'resume reconciliation' 'Inspect existing managed worktrees and branches'
Assert-ContinuationContains 'merge confirmation' 'provider reports the PR merged'
Assert-ContinuationContains 'stale feature guard' 'Do not create the next story branch from a stale local feature checkout'
Assert-BranchScenarioContains 'story-two starting HEAD guard' 'story two starts at the current feature HEAD'
Assert-BranchScenarioContains 'story-one inheritance guard' 'story two inherits story-one content'
Assert-BranchScenarioContains 'reloaded resume receipt' 'Assert-ResumeReceipt $resumed'
Assert-BranchScenarioContains 'mismatched lineage guard' 'incorrect saved feature lineage is rejected'
Assert-BranchScenarioContains 'unknown outcome guard' 'unknown merge does not create the next story branch'
Assert-WorkerPairContains 'exact implementer profile' 'gpt-5.6-luna'
Assert-WorkerPairContains 'exact reviewer profile' 'gpt-6.1-sol'
Assert-WorkerPairContains 'pending thread guard' 'pending `clientThreadId`'
Assert-WorkerPairContains 'coordinator-owned pair' 'neither worker creates the other worker'
Assert-HandoffContains 'task-ready payload' 'Task #<ref> ready for review'
Assert-HandoffContains 'findings route' 'reviewer sends findings directly to the implementer'
Assert-HandoffContains 'correction route' 'returns to the same reviewer chat'
Assert-HandoffContains 'stable branch gate' 'does not start the next ordered task'
Assert-HandoffContains 'no receipt requirement' 'Do not require a JSON receipt'
if (-not $normalizedRouting.Contains('no arbitrary elapsed deadline') -or
    -not $normalizedRouting.Contains('fixed correction-count cutoff')) {
    throw 'Routing assertion failed: no arbitrary cutoff policy'
}
if (-not (Get-Content $routingScriptPath -Raw).Contains('ordinary corrections must not create a new chat')) {
    throw 'Routing assertion failed: controlled fixture coverage'
}
foreach ($marker in @(
        'exact current HEAD'
        'Find an existing PR by repository, head branch, and the recorded feature base'
        'Reuse a PR only when its base branch and head commit match'
        'state: pr_ready_for_approval'
        'never blindly retry a write or create a duplicate PR')) {
    if (-not $normalizedPrDelivery.Contains($marker)) {
        throw "PR delivery assertion failed: $marker"
    }
}
if (-not (Get-Content $prDeliveryScriptPath -Raw).Contains('Passed offline PR delivery fixture')) {
    throw 'PR delivery assertion failed: offline fixture coverage'
}
foreach ($marker in @(
        'Yes — merge and continue to the next ordered story'
        'No — hold for feedback'
        'An empty response, timeout, unrelated text, or a worker message is `no_response`'
        'Only a verified provider merge unlocks the next story'
        'Do not dispatch workers or send repeated notifications')) {
    if (-not $normalizedMergeApproval.Contains($marker)) {
        throw "Merge approval assertion failed: $marker"
    }
}
if (-not (Get-Content $mergeApprovalScriptPath -Raw).Contains('Passed offline merge-gate fixture')) {
    throw 'Merge approval assertion failed: offline fixture coverage'
}
foreach ($marker in @(
        '`gpt-6.1-sol` with `high` effort'
        'every linked story in authoritative order'
        'combined behavior across stories'
        'cross-story state transitions'
        'routes it to an appropriate implementer on an isolated integration-correction branch'
        'resulting exact feature HEAD again')) {
    if (-not $normalizedFinalEpicReview.Contains($marker)) {
        throw "Final epic review assertion failed: $marker"
    }
}
if (-not (Get-Content $finalEpicReviewScriptPath -Raw).Contains('Passed offline final epic review fixture')) {
    throw 'Final epic review assertion failed: offline fixture coverage'
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'validate-branch-scenarios.ps1'))) {
    throw 'Missing disposable branch scenario check.'
}

foreach ($recordMarker in @(
        '## 1. Single-repository story'
        '## 2. Multi-repository epic'
        '## 3. Ambiguous scope'
        '## 4. Valid scope'
        '## 5. Missing acceptance criteria'
        'Synthetic user reply and trace:'
        'Start'
        'Cancel'
        'mcp__codex_app__list_projects('
        'mcp__taiga__resolve_project('
        'mcp__taiga__get_task('
        'mcp__codex_app__create_worktree('
        'mcp__codex_app__create_thread({"title":"story-46 reviewer"'
        'mcp__codex_app__send_message_to_thread('
        'synthetic-review-46'
        'mcp__codex_app__automation_update('
        'git ls-remote --symref origin HEAD'
        'Mutation calls before Start: []'
        'Mutation calls after Cancel: []'
        '`ClarifyRequired(project)`'
        '`ClarifyRequired(acceptance criteria)`')) {
    if (-not $normalizedWalkthrough.Contains($recordMarker)) {
        throw "Walkthrough record assertion failed: $recordMarker"
    }
}

$worktreeMarker = 'mcp__codex_app__create_worktree({"name":"story-46-worker"'
$implementationThreadMarker = 'mcp__codex_app__create_thread({"title":"story-46 implementation"'
$worktreeIndex = $normalizedWalkthrough.IndexOf($worktreeMarker, [StringComparison]::Ordinal)
$implementationThreadIndex = $normalizedWalkthrough.IndexOf($implementationThreadMarker, [StringComparison]::Ordinal)
if ($worktreeIndex -lt 0 -or $implementationThreadIndex -lt 0 -or $worktreeIndex -gt $implementationThreadIndex) {
    throw 'Walkthrough order assertion failed: worktree must be created before worker chats.'
}
if ($normalizedWalkthrough.Contains('[synthetic-impl-46] mcp__codex_app__create_thread')) {
    throw 'Walkthrough ownership assertion failed: implementer must not create reviewer chat.'
}

foreach ($recordMarker in @(
        '## Fixture'
        '## Ordered execution trace'
        'failed check'
        'prerequisite blocker'
        'reviewer rejects'
        'human changes the status'
        'task #902 cannot start'
        'no dependent task receives a status')) {
    if (-not $normalizedTaskExecution.Contains($recordMarker)) {
        throw "Task execution walkthrough assertion failed: $recordMarker"
    }
}

function Get-StaticContractOutcome {
    param(
        [Parameter(Mandatory)] [hashtable] $InputData
    )

    $unresolved = @()
    if ([string]::IsNullOrWhiteSpace($InputData.Project)) {
        $unresolved += 'project'
    }
    if ($InputData.Ref -le 0) {
        $unresolved += 'work-item reference'
    }
    if ($InputData.Repositories.Count -eq 0) {
        $unresolved += 'repository'
    }
    if (-not $InputData.AcceptanceCriteriaPresent) {
        $unresolved += 'acceptance criteria'
    }
    if ($InputData.Kind -eq 'epic' -and $InputData.Repositories.Count -gt 1 -and
        -not $InputData.PerRepositoryMapping) {
        $unresolved += 'per-repository branch/base/worktree mapping'
    }

    if ($unresolved.Count -gt 0) {
        return [pscustomobject]@{
            Name = $InputData.Name
            Input = $InputData.InputSummary
            Observed = 'Clarify'
            Detail = 'Ask for: ' + ($unresolved -join ', ')
        }
    }

    if ($InputData.Reply -eq 'Cancel') {
        return [pscustomobject]@{
            Name = $InputData.Name
            Input = $InputData.InputSummary
            Observed = 'Cancelled'
            Detail = 'External systems unchanged'
        }
    }

    if ($InputData.Reply -ne 'Start') {
        return [pscustomobject]@{
            Name = $InputData.Name
            Input = $InputData.InputSummary
            Observed = 'Clarify'
            Detail = 'Reply must be Start or Cancel'
        }
    }

    return [pscustomobject]@{
        Name = $InputData.Name
        Input = $InputData.InputSummary
        Observed = 'SetupReady'
        Detail = "$($InputData.Repositories.Count) repository mapping(s); Start-scoped operations may proceed"
    }
}

$scenarios = @(
    @{
        Name = 'story'
        InputSummary = 'taiga-mcp story #46; one repository; acceptance present; reply Start'
        Kind = 'story'
        Project = 'taiga-mcp'
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Start'
    }
    @{
        Name = 'epic'
        InputSummary = 'multi-repository epic #45; TaigaMCP + ReviewRepo mappings; reply Start'
        Kind = 'epic'
        Project = 'multi-repository'
        Ref = 45
        Repositories = @('C:\Projects\TaigaMCP', 'C:\Projects\ReviewRepo')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Start'
    }
    @{
        Name = 'ambiguous-scope'
        InputSummary = 'story #46; project missing; acceptance present'
        Kind = 'story'
        Project = ''
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Start'
    }
    @{
        Name = 'cancelled-setup'
        InputSummary = 'taiga-mcp story #46; one repository; acceptance present; reply Cancel'
        Kind = 'story'
        Project = 'taiga-mcp'
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Cancel'
    }
    @{
        Name = 'missing-acceptance'
        InputSummary = 'taiga-mcp story #46; acceptance criteria missing'
        Kind = 'story'
        Project = 'taiga-mcp'
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $false
        Reply = 'Start'
    }
)

$expected = @{
    'story' = 'SetupReady'
    'epic' = 'SetupReady'
    'ambiguous-scope' = 'Clarify'
    'cancelled-setup' = 'Cancelled'
    'missing-acceptance' = 'Clarify'
}

$results = foreach ($scenario in $scenarios) {
    $result = Get-StaticContractOutcome -InputData $scenario
    if ($result.Observed -ne $expected[$result.Name]) {
        throw "Scenario '$($result.Name)' expected '$($expected[$result.Name])' but observed '$($result.Observed)'."
    }
    $result
}

$results | Format-Table Name, Input, Observed, Detail -AutoSize | Out-String | Write-Output
Write-Output "Passed $($results.Count) static contract route assertions and 13 walkthrough-record completeness assertions; this is not behavioral evidence."
