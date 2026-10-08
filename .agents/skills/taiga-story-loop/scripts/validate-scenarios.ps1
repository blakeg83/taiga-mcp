# CONTRACT AND FOCUSED EVIDENCE CHECK.
# This file checks documented contract text against a small route matrix and
# runs the local synthetic acceptance-evidence fixture. It does not execute the
# skill, call Taiga/Git/Codex tools, or establish live browser evidence. See
# references/synthetic-walkthroughs.md for recorded synthetic walkthroughs.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$setupPath = Join-Path $skillRoot 'references/invocation-and-setup.md'
$topologyPath = Join-Path $skillRoot 'references/branch-topology.md'
$branchPath = Join-Path $skillRoot 'references/branch-and-continuation.md'
$continuationPath = Join-Path $skillRoot 'references/continuation-note.md'
$continuationScriptPath = Join-Path $PSScriptRoot 'validate-continuation-note.ps1'
$continuationWriterPath = Join-Path $PSScriptRoot 'write-continuation-note.ps1'
$promptPath = Join-Path $skillRoot 'assets/implementation-prompt.md'
$branchScenarioPath = Join-Path $PSScriptRoot 'validate-branch-scenarios.ps1'
$walkthroughPath = Join-Path $skillRoot 'references/synthetic-walkthroughs.md'
$contractsPath = Join-Path $skillRoot 'references/contracts.md'
$taskExecutionPath = Join-Path $skillRoot 'references/task-execution-walkthroughs.md'
$taskExecutionGuidancePath = Join-Path $skillRoot 'references/task-execution.md'
$taskExecutionScriptPath = Join-Path $PSScriptRoot 'validate-task-execution.ps1'
$workerPairPath = Join-Path $skillRoot 'references/worker-pair.md'
$conversationNamingPath = Join-Path $skillRoot 'references/conversation-naming.md'
$handoffPath = Join-Path $skillRoot 'references/worker-handoffs.md'
$reviewerPromptPath = Join-Path $skillRoot 'assets/reviewer-prompt.md'
$epicReviewerPromptPath = Join-Path $skillRoot 'assets/epic-reviewer-prompt.md'
$epicFixPromptPath = Join-Path $skillRoot 'assets/epic-fix-implementation-prompt.md'
$acceptancePath = Join-Path $skillRoot 'references/acceptance.md'
$routingPath = Join-Path $skillRoot 'references/routing-and-escalation.md'
$routingScriptPath = Join-Path $PSScriptRoot 'validate-routing.ps1'
$automaticFlowPath = Join-Path $skillRoot 'references/automatic-review-flow.md'
$automaticFlowScriptPath = Join-Path $PSScriptRoot 'validate-automatic-review-flow.ps1'
$prDeliveryPath = Join-Path $skillRoot 'references/pr-delivery.md'
$prDeliveryScriptPath = Join-Path $PSScriptRoot 'validate-pr-delivery.ps1'
$mergeApprovalPath = Join-Path $skillRoot 'references/merge-approval.md'
$mergeApprovalScriptPath = Join-Path $PSScriptRoot 'validate-merge-approval.ps1'
$finalEpicReviewPath = Join-Path $skillRoot 'references/final-epic-review.md'
$finalEpicReviewScriptPath = Join-Path $PSScriptRoot 'validate-final-epic-review.ps1'
$finalDeliveryPath = Join-Path $skillRoot 'references/final-delivery.md'
$finalDeliveryScriptPath = Join-Path $PSScriptRoot 'validate-final-delivery.ps1'
$revisionFreezePath = Join-Path $skillRoot 'references/revision-freeze.md'
$acceptanceEvidencePath = Join-Path $skillRoot 'references/acceptance-evidence.md'
$acceptanceEvidenceManifestPath = Join-Path $skillRoot 'assets/acceptance-evidence-scenarios.json'
$acceptanceEvidenceScriptPath = Join-Path $PSScriptRoot 'validate-acceptance-evidence.ps1'
$setupAuthorizationPath = Join-Path $skillRoot 'references/setup-authorization.md'
$setupAuthorizationScriptPath = Join-Path $PSScriptRoot 'validate-setup-authorization.ps1'

if (-not (Test-Path $walkthroughPath)) {
    throw 'Missing recorded synthetic walkthrough reference.'
}
if (-not (Test-Path $contractsPath)) {
    throw 'Missing story/task contract reference.'
}
if (-not (Test-Path $topologyPath)) {
    throw 'Missing scope-specific branch topology contract.'
}
if (-not (Test-Path $taskExecutionPath) -or -not (Test-Path $taskExecutionScriptPath)) {
    throw 'Missing ordered task execution scenario evidence.'
}
if (-not (Test-Path $workerPairPath)) {
    throw 'Missing persistent worker-pair contract.'
}
if (-not (Test-Path $conversationNamingPath)) {
    throw 'Missing work-item conversation-naming contract.'
}
if (-not (Test-Path $handoffPath) -or -not (Test-Path $reviewerPromptPath)) {
    throw 'Missing direct worker handoff or reviewer prompt contract.'
}
if (-not (Test-Path $epicReviewerPromptPath) -or -not (Test-Path $epicFixPromptPath)) {
    throw 'Missing integrated epic reviewer or epic-fix implementer prompt contract.'
}
if (-not (Test-Path $acceptancePath)) {
    throw 'Missing task/story acceptance contract.'
}
if (-not (Test-Path $routingPath) -or -not (Test-Path $routingScriptPath)) {
    throw 'Missing routing and escalation fixture.'
}
if (-not (Test-Path $automaticFlowPath) -or -not (Test-Path $automaticFlowScriptPath)) {
    throw 'Missing automatic review-flow contract or fixture.'
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
if (-not (Test-Path $finalDeliveryPath) -or -not (Test-Path $finalDeliveryScriptPath)) {
    throw 'Missing final feature-to-master delivery contract or fixture.'
}
if (-not (Test-Path $revisionFreezePath)) {
    throw 'Missing clean committed revision contract.'
}
if (-not (Test-Path $acceptanceEvidencePath) -or
    -not (Test-Path $acceptanceEvidenceManifestPath) -or
    -not (Test-Path $acceptanceEvidenceScriptPath)) {
    throw 'Missing acceptance-evidence contract, manifest, or executable fixture.'
}
if (-not (Test-Path $setupAuthorizationPath) -or
    -not (Test-Path $setupAuthorizationScriptPath)) {
    throw 'Missing setup-authorization contract or executable fixture.'
}

$setupText = Get-Content $setupPath -Raw
$normalizedSetup = [regex]::Replace($setupText, '\s+', ' ')
$topologyText = Get-Content $topologyPath -Raw
$normalizedTopology = [regex]::Replace($topologyText, '\s+', ' ')
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
$contractsText = Get-Content $contractsPath -Raw
$normalizedContracts = [regex]::Replace($contractsText, '\s+', ' ')
$taskExecutionText = Get-Content $taskExecutionPath -Raw
$normalizedTaskExecution = [regex]::Replace($taskExecutionText, '\s+', ' ')
$taskExecutionGuidanceText = Get-Content $taskExecutionGuidancePath -Raw
$normalizedTaskExecutionGuidance = [regex]::Replace($taskExecutionGuidanceText, '\s+', ' ')
$workerPairText = Get-Content $workerPairPath -Raw
$normalizedWorkerPair = [regex]::Replace($workerPairText, '\s+', ' ')
$conversationNamingText = Get-Content $conversationNamingPath -Raw
$normalizedConversationNaming = [regex]::Replace($conversationNamingText, '\s+', ' ')
$handoffText = Get-Content $handoffPath -Raw
$normalizedHandoff = [regex]::Replace($handoffText, '\s+', ' ')
$reviewerPromptText = Get-Content $reviewerPromptPath -Raw
$normalizedReviewerPrompt = [regex]::Replace($reviewerPromptText, '\s+', ' ')
$epicReviewerPromptText = Get-Content $epicReviewerPromptPath -Raw
$normalizedEpicReviewerPrompt = [regex]::Replace($epicReviewerPromptText, '\s+', ' ')
$epicFixPromptText = Get-Content $epicFixPromptPath -Raw
$normalizedEpicFixPrompt = [regex]::Replace($epicFixPromptText, '\s+', ' ')
$acceptanceText = Get-Content $acceptancePath -Raw
$normalizedAcceptance = [regex]::Replace($acceptanceText, '\s+', ' ')
$routingText = Get-Content $routingPath -Raw
$normalizedRouting = [regex]::Replace($routingText, '\s+', ' ')
$automaticFlowText = Get-Content $automaticFlowPath -Raw
$normalizedAutomaticFlow = [regex]::Replace($automaticFlowText, '\s+', ' ')
$prDeliveryText = Get-Content $prDeliveryPath -Raw
$normalizedPrDelivery = [regex]::Replace($prDeliveryText, '\s+', ' ')
$mergeApprovalText = Get-Content $mergeApprovalPath -Raw
$normalizedMergeApproval = [regex]::Replace($mergeApprovalText, '\s+', ' ')
$finalEpicReviewText = Get-Content $finalEpicReviewPath -Raw
$normalizedFinalEpicReview = [regex]::Replace($finalEpicReviewText, '\s+', ' ')
$finalDeliveryText = Get-Content $finalDeliveryPath -Raw
$normalizedFinalDelivery = [regex]::Replace($finalDeliveryText, '\s+', ' ')
$revisionFreezeText = Get-Content $revisionFreezePath -Raw
$normalizedRevisionFreeze = [regex]::Replace($revisionFreezeText, '\s+', ' ')
$acceptanceEvidenceText = Get-Content $acceptanceEvidencePath -Raw
$normalizedAcceptanceEvidence = [regex]::Replace($acceptanceEvidenceText, '\s+', ' ')
$acceptanceEvidenceScriptText = Get-Content $acceptanceEvidenceScriptPath -Raw
$acceptanceEvidenceManifestText = Get-Content $acceptanceEvidenceManifestPath -Raw
$setupAuthorizationText = Get-Content $setupAuthorizationPath -Raw
$normalizedSetupAuthorization = [regex]::Replace($setupAuthorizationText, '\s+', ' ')
$setupAuthorizationScriptText = Get-Content $setupAuthorizationScriptPath -Raw

function Assert-DocumentContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedSetup.Contains($Text)) {
        throw "Document assertion failed: $Label"
    }
}

function Assert-TopologyContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedTopology.Contains($Text)) {
        throw "Topology assertion failed: $Label"
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

function Assert-ContractsContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedContracts.Contains($Text)) {
        throw "Contract assertion failed: $Label"
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

function Assert-ConversationNamingContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedConversationNaming.Contains($Text)) {
        throw "Conversation-naming assertion failed: $Label"
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

function Assert-SetupAuthorizationContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedSetupAuthorization.Contains($Text)) {
        throw "Setup-authorization assertion failed: $Label"
    }
}

Assert-DocumentContains 'per-repository mapping' 'one row per resolved repository'
Assert-DocumentContains 'epic mapping guard' 'An epic setup must not collapse multiple repositories'
Assert-DocumentContains 'start gate' 'Reply Start or Cancel.'
Assert-DocumentContains 'setup authorization reference' 'setup authorization input contract'
Assert-DocumentContains 'read-only discovery' 'Discovery is read-only.'
Assert-DocumentContains 'cancel behavior' '`Cancel` leaves the external systems unchanged'
Assert-DocumentContains 'clarification behavior' 'Ask only for a missing or ambiguous'
Assert-DocumentContains 'behavioral evidence reference' 'synthetic-walkthroughs.md'
Assert-DocumentContains 'branch contract reference' 'branch and continuation'
Assert-DocumentContains 'durable acceptance evidence plan' 'Acceptance evidence plan (conditional on the real story/repository):'
Assert-DocumentContains 'acceptance production path intake' 'Production path and inputs:'
Assert-DocumentContains 'acceptance smoke intake' 'Smoke and limitations:'
Assert-DocumentContains 'fresh base capture' 'captures a fresh base SHA'
Assert-DocumentContains 'feature branch gate' 'creates one uniquely named feature branch'
Assert-DocumentContains 'story branch lineage' 'distinct managed worktree and story branch'
Assert-DocumentContains 'merge advancement gate' 'provider confirms the previous PR merged'
Assert-DocumentContains 'dirty checkout preservation' 'dirty user checkout'
if (-not $normalizedRevisionFreeze.Contains('Reviewed SHA: <full 40-character SHA copied from')) {
    throw 'Revision-freeze assertion failed: full Git SHA review input'
}
foreach ($marker in @(
        'clean tracked source'
        'git -C <worktree> diff --quiet HEAD --'
        'git -C <worktree> diff --cached --quiet'
        'git -C <worktree> ls-files --others --exclude-standard'
        'Ignored verification outputs'
        'expected branch'
        'relevant diff range'
        'Do not reset, clean, stash, force-push'
        'previous reviewed SHA'
        'new full SHA')) {
    if (-not $normalizedRevisionFreeze.Contains($marker)) {
        throw "Revision-freeze assertion failed: $marker"
    }
}
if (-not $normalizedHandoff.Contains('Worktree: <absolute story worktree>') -or
    -not $normalizedHandoff.Contains('Source state: clean tracked source') -or
    -not $normalizedHandoff.Contains('Review range: <base SHA>..<new revision>; paths: <relevant changed paths>') -or
    -not $normalizedHandoff.Contains('Correction delta: <previous reviewed SHA>..<new revision>; paths: <correction delta>')) {
    throw 'Handoff assertion failed: complete clean revision input'
}
if (-not $normalizedAcceptance.Contains('clean tracked-source state') -or
    -not $normalizedAcceptance.Contains('hold acceptance')) {
    throw 'Acceptance assertion failed: clean revision gate'
}
if (-not $normalizedPrDelivery.Contains('clean tracked source') -or
    -not $normalizedPrDelivery.Contains('relevant `<base SHA>..<reviewed SHA>` diff range')) {
    throw 'PR delivery assertion failed: clean revision preflight'
}
foreach ($marker in @(
        'dirty source at handoff'
        'tracked source edit during the pending review'
        'dirty source at handoff must hold delivery'
        'old acceptance must not survive a changed HEAD'
        'delivery must wait for review of the correction'
        'ignored verification output is present'
        'correction records the new diff range')) {
    if (-not $normalizedBranchScenario.Contains($marker)) {
        throw "Branch scenario assertion failed: $marker"
    }
}
Assert-DocumentContains 'persistent pair reference' 'persistent story worker pair'
Assert-DocumentContains 'pair resolution gate' 'resolves both results to usable'
Assert-DocumentContains 'pending ID guard' 'pending `clientThreadId` is never a message destination'
Assert-DocumentContains 'standalone topology setup' 'standalone-story-direct-master'
Assert-DocumentContains 'epic topology setup' 'epic-shared-feature'
Assert-DocumentContains 'legacy topology setup' 'legacy-standalone-feature'
Assert-ContractsContains 'reviewable endpoint template' '### Reviewable endpoint'
Assert-ContractsContains 'endpoint artifact' '- Artifact:'
Assert-ContractsContains 'endpoint revision input' '- Review input:'
Assert-ContractsContains 'expected outcome' '- Expected check outcome:'
Assert-ContractsContains 'deferred owner' '- Deferred criteria:'
Assert-ContractsContains 'advancement gate' '- Advancement gate:'
Assert-ContractsContains 'expected-red evidence' 'A nonzero command exit by itself is not evidence of a valid RED.'
Assert-ContractsContains 'exact expected-red reasons' 'exact permitted failure reason'
Assert-ContractsContains 'complete expected-red set' 'one-for-one'
Assert-ContractsContains 'ambiguous endpoint gate' 'missing or ambiguous artifact'
Assert-PromptContains 'ordered task acceptance gate' 'reviewer acceptance of the exact current task commit'
Assert-PromptContains 'acceptance before advancement' 'explicit reviewer acceptance of the exact current task commit recorded'
Assert-PromptContains 'human status decision' 'A human status is never replaced automatically'
Assert-PromptContains 'pair authorization' 'worker-to-worker and worker-to-coordinator messages'
Assert-PromptContains 'no peer creation' 'Never create another worker'
Assert-PromptContains 'handoff end point' 'the direct delivery to the required reviewer'
Assert-PromptContains 'last implementer action' 'That final response is the last action in the turn'
Assert-PromptContains 'unknown delivery escalation' 'A failed or unknown delivery is not a confirmed review wait'
Assert-PromptContains 'no implementer polling' 'Do not call `wait_threads`, poll/read the reviewer'
Assert-PromptContains 'per-task conditional gate' 'In `per_task` mode, do not start the next task'
Assert-PromptContains 'story-end conditional gate' 'In `story_end_only` mode, start the next ordered task'
Assert-PromptContains 'legacy resume route' 'For `legacy-standalone-feature`'
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
    -not $normalizedAcceptance.Contains('Final review request: <request ID>') -or
    -not $normalizedAcceptance.Contains('Reviewed HEAD: <exact full 40-character commit SHA>') -or
    -not $normalizedAcceptance.Contains('Exactly one explicit final whole-story review') -or
    -not $normalizedAcceptance.Contains('a task acceptance never closes or releases the story PR gate') -or
    -not $normalizedAcceptance.Contains('Independent verification:') -or
    -not $normalizedAcceptance.Contains('Inspected worker evidence:')) {
    throw 'Acceptance assertion failed: final story approval binding'
}
Assert-TaskExecutionContains 'explicit human status decision' 'A human status is never replaced automatically'
Assert-TaskExecutionContains 'preserve-or-replace decision' 'explicit decision to preserve the human status and stop, or to replace it'
Assert-TaskExecutionContains 'per-task advancement gate' 'In `per_task` mode, only an independent'
Assert-TaskExecutionContains 'story-end advancement gate' 'In `story_end_only` mode, implementation evidence may release'
Assert-TaskExecutionContains 'story-end accepted gate' 'cannot become `mapping.accepted`/Done until'
Assert-TaskExecutionContains 'no routine coordinator gate' 'there is no coordinator acknowledgement, next-task assignment, or reminder'
Assert-TaskExecutionContains 'acceptance journal' 'acceptance journal keyed by'
Assert-TaskExecutionContains 'advance after progress confirmation' 'advance only after both the task transition and comment are authoritative'
Assert-TaskExecutionContains 'response-loss recovery' 'Recovery resumes the same journal'
Assert-TopologyContains 'standalone direct branch' 'A standalone story has one managed story branch'
Assert-TopologyContains 'standalone master PR' 'its story PR targets `master`'
Assert-TopologyContains 'epic shared feature branch' 'An epic has one shared feature branch'
Assert-TopologyContains 'active-run migration' 'Preserve its recorded feature/story branches, worktrees, PR, worker, and recovery identities'
Assert-TopologyContains 'legacy resume delivery' 'before continuing to the legacy final feature-to-`master` delivery'
Assert-TopologyContains 'epic migration classification' 'If `Scope` identifies an epic or a set of ordered stories'
Assert-TopologyContains 'standalone migration classification' 'If `Scope` identifies one standalone story'
Assert-TopologyContains 'ambiguous migration guard' 'Feature fields alone are insufficient evidence for the legacy exception'
Assert-BranchContractContains 'managed worktree handoff' 'create_worktree({ name:'
Assert-BranchContractContains 'worker path receipt' 'The coordinator records the returned absolute path'
Assert-BranchContractContains 'implementer ownership' 'implementer may write source'
Assert-BranchContractContains 'reviewer read-only boundary' 'reviewer is read-only'
Assert-ContinuationContains 'minimal note fields' 'Review: <pending/approved/changes_requested>'
Assert-ContinuationContains 'legacy final review state' 'Final review: <not_applicable/pending/findings/accepted>'
Assert-ContinuationContains 'integrated review pair state' 'Integrated pair: <epic-fix implementer thread-id>'
Assert-ContinuationContains 'legacy snapshot compatibility' 'optional when reading or replacing an older snapshot'
Assert-ContinuationContains 'ordered story scope' 'stories: <ordered story refs>'
Assert-ContinuationContains 'submitted setup decision' 'Setup authorization: <pending/start/cancelled>'
if (-not (Get-Content $continuationWriterPath -Raw).Contains("'Setup authorization'")) {
    throw 'Continuation persistence assertion failed: setup authorization field is not accepted by the writer.'
}
Assert-ContinuationContains 'resume reconciliation' 'Inspect existing managed worktrees and branches'
Assert-ContinuationContains 'merge confirmation' 'provider reports the PR merged'
Assert-ContinuationContains 'snapshot ownership' 'The coordinator owns this compact snapshot'
Assert-ContinuationContains 'worker evidence ownership' 'The implementer owns current-version Taiga task and story progress writes'
Assert-ContinuationContains 'quiet review wait' 'implementer in `awaiting_review` after a confirmed'
Assert-ContinuationContains 'stale feature guard' 'Do not create the next story branch from a stale local feature checkout'
Assert-ContinuationContains 'epic migration classification' 'If the scope identifies an epic or multiple ordered stories'
Assert-ContinuationContains 'standalone migration classification' 'If the scope identifies one standalone story'
Assert-ContinuationContains 'ambiguous migration guard' 'feature fields alone do not select the legacy exception'
Assert-BranchScenarioContains 'story-two starting HEAD guard' 'story two starts at the current feature HEAD'
Assert-BranchScenarioContains 'story-one inheritance guard' 'story two inherits the authoritative corrected story-one content'
Assert-BranchScenarioContains 'reloaded resume receipt' 'Assert-ResumeReceipt $resumed'
Assert-BranchScenarioContains 'mismatched lineage guard' 'incorrect saved feature lineage is rejected'
Assert-BranchScenarioContains 'unknown outcome guard' 'unknown merge does not create the next story branch'
Assert-BranchScenarioContains 'standalone branch fixture' 'standalone story starts at the captured master base'
Assert-BranchScenarioContains 'standalone PR fixture' 'standalone PR targets master'
Assert-WorkerPairContains 'exact implementer profile' 'gpt-5.6-luna'
Assert-WorkerPairContains 'exact reviewer profile' 'gpt-6.1-sol'
Assert-WorkerPairContains 'pending thread guard' 'pending `clientThreadId`'
Assert-WorkerPairContains 'coordinator-owned pair' 'neither worker creates the other worker'
Assert-HandoffContains 'task-ready payload' 'Task #<ref> ready for review'
Assert-HandoffContains 'findings route' 'The reviewer sends routine findings directly to the implementer'
Assert-HandoffContains 'correction route' 'returns to the same reviewer chat'
Assert-HandoffContains 'stable branch gate' 'does not start the next ordered task'
Assert-HandoffContains 'no receipt requirement' 'Do not require a JSON receipt'
Assert-HandoffContains 'full revision handoff evidence' 'full revision, pair identities, authorization'
Assert-HandoffContains 'durable acceptance evidence handoff' 'Acceptance evidence: <plan reference'
Assert-HandoffContains 'end-of-turn endpoint' 'The final response is the last action in the turn'
Assert-HandoffContains 'failed delivery gate' 'An unsuccessful or unknown delivery is not a confirmed review dispatch'
Assert-WorkerPairContains 'direct routine pair' 'routine findings and corrections stay within the worker pair'
Assert-WorkerPairContains 'no routine relay' 'The coordinator is not a routine finding, correction, task-ready, or task-acceptance relay'
Assert-WorkerPairContains 'no task-ready relay' 'task-ready, or task-acceptance relay'
Assert-WorkerPairContains 'implementer owns advancement' 'implementer owns current-version Taiga checklist/status/'
Assert-ConversationNamingContains 'story coordinator title' 'User Story #<ref> Coordinator'
Assert-ConversationNamingContains 'story implementer title' 'User Story #<ref> Implementer'
Assert-ConversationNamingContains 'story reviewer title' 'User Story #<ref> Reviewer'
Assert-ConversationNamingContains 'epic coordinator title' 'Epic #<ref> Coordinator'
Assert-ConversationNamingContains 'epic implementer title' 'Epic #<ref> Implementer'
Assert-ConversationNamingContains 'epic reviewer title' 'Epic #<ref> Reviewer'
Assert-ConversationNamingContains 'current chat rename' 'set_thread_title'
Assert-ConversationNamingContains 'creation title field' 'title` field'
Assert-ConversationNamingContains 'stable subject-independent name' 'do not change when the work-item subject changes'
Assert-ConversationNamingContains 'task parent conversation' 'Tasks do not receive separate conversations'
Assert-ConversationNamingContains 'issue scope boundary' 'Issue conversations are not currently supported'
if ($normalizedHandoff.Contains('same reviewer and coordinator')) {
    throw 'Handoff assertion failed: routine corrections must not copy the coordinator'
}
if ($normalizedPrompt.Contains('correction-ready handoff to both reviewer and coordinator')) {
    throw 'Prompt assertion failed: correction-ready handoffs must stay direct'
}
if (-not $normalizedReviewerPrompt.Contains('Do not copy or restate routine findings to the coordinator')) {
    throw 'Reviewer prompt assertion failed: routine findings must not be relayed'
}
foreach ($marker in @(
        'fresh, read-only reviewer'
        'gpt-6.1-sol` with `high`'
        'fresh epic-review pair'
        'Do not reuse or ask to reuse a story reviewer chat'
        'Re-review through this same fresh epic-review pair')) {
    if (-not $normalizedEpicReviewerPrompt.Contains($marker)) {
        throw "Epic reviewer prompt assertion failed: $marker"
    }
}
foreach ($marker in @(
        'fresh correction implementer'
        'gpt-5.6-luna` with `xhigh`'
        'distinct from every story implementer chat'
        'Wait for a finding delivered directly by the assigned epic reviewer'
        'Verify the sender, scope, and exact reviewed HEAD'
        'reuse this fresh epic-fix implementer chat')) {
    if (-not $normalizedEpicFixPrompt.Contains($marker)) {
        throw "Epic-fix prompt assertion failed: $marker"
    }
}
if (-not $normalizedReviewerPrompt.Contains('only blocked verification') -or
    $normalizedReviewerPrompt.Contains('only blockers/check failures')) {
    throw 'Reviewer prompt assertion failed: routine check failures must not escalate automatically'
}
if (-not $normalizedAcceptance.Contains('The task-acceptance route is reviewer-to-implementer') -or
    -not $normalizedAcceptance.Contains('No coordinator acknowledgement, next-task assignment, or reminder')) {
    throw 'Acceptance assertion failed: direct task acceptance and implementer ownership must remain explicit'
}
if (-not $normalizedRouting.Contains('no arbitrary elapsed deadline') -or
    -not $normalizedRouting.Contains('fixed correction-count cutoff')) {
    throw 'Routing assertion failed: no arbitrary cutoff policy'
}
foreach ($marker in @('routine readiness, findings, corrections, and acceptance must not reach the coordinator', 'unknown delivery', 'revision conflict', 'routine finding must not be copied')) {
    if (-not (Get-Content $routingScriptPath -Raw).Contains($marker)) {
        throw "Routing assertion failed: $marker"
    }
}
if (-not (Get-Content $routingScriptPath -Raw).Contains('ordinary corrections must not create a new chat')) {
    throw 'Routing assertion failed: controlled fixture coverage'
}
foreach ($marker in @(
        'ready_for_review'
        'Send one direct review request to the persistent reviewer'
        'confirmed delivery to the required reviewer'
        'issue the concise final response and end the implementer turn'
        'changes_requested'
        'send the finding directly to the same implementer'
        'Implementer sends correction-ready'
        'confirmed delivery to that reviewer'
        'keep the coordinator out of the routine correction cycle'
        'Deliver acceptance directly to the implementer'
        'implementer applies the version-safe accepted/Done transition'
        'Reviewer accepts'
        'idle status, timeout, elapsed time, or implementation commit'
        'After a confirmed initial or correction-ready delivery, the implementer turn ends immediately'
        'does not call `wait_threads`, read or poll the reviewer chat'
        'A failed or unknown handoff delivery is an exceptional coordinator reconciliation'
        'A healthy idle `awaiting_review` worker is not woken by recovery'
        'Routine `changes_requested`, correction-ready, task-ready, and exact task-acceptance events stay worker-to-worker'
        'Unknown message delivery, missing destinations, revision conflicts, merge approval'
        'PR creation or update is already covered by `Start`'
        'Final task reaches the selected review-mode endpoint'
        'Reviewer accepts the final story review'
        'independent verification separately from inspected worker evidence')) {
    if (-not $normalizedAutomaticFlow.Contains($marker)) {
        throw "Automatic review-flow assertion failed: $marker"
    }
}

foreach ($marker in @(
        'Capability intake'
        'Supports selectable authorization'
        'Permits authorization'
        'explicit-submission evidence'
        'preference-only or optional-question input tool is not an authorization capability'
        'selectable = supportsSelectableAuthorization'
        'exactly one setup gate'
        'A displayed default'
        'awaiting_confirmation'
        'resolved authorization reference'
        'scope change'
        'active gate identity, revision, and resolved scope'
        'duplicate, stale, or post-Cancel events are rejected'
        'Actual selectable UI behavior requires a separately authorized host observation')) {
    Assert-SetupAuthorizationContains "contract marker: $marker" $marker
}
foreach ($marker in @(
        'New-SetupState'
        'HasExplicitSubmissionEvidence'
        'GateId'
        'rejected_stale_or_closed_gate'
        'blocked_before_confirmation'
        'setup_gate_replaced'
        'Resolve-SetupEvent'
        'permitted-selectable-start'
        'prohibited-selectable-tool'
        'unavailable-selectable-tool'
        'missing-submission-evidence'
        'selectable-default-only'
        'plain-timeout'
        'plain-blank-reply'
        'plain-invalid-reply'
        'plain-worker-message'
        'selectable-explicit-cancel'
        'plain-explicit-cancel'
        'duplicate-start-event'
        'start-after-cancel'
        'scope-change-invalidates-start'
        'Passed $($results.Count) setup-authorization decision scenarios')) {
    if (-not $setupAuthorizationScriptText.Contains($marker)) {
        throw "Setup-authorization fixture assertion failed: $marker"
    }
}
if (-not (Get-Content $automaticFlowScriptPath -Raw).Contains('Passed automatic review-flow fixture')) {
    throw 'Automatic review-flow assertion failed: offline fixture coverage'
}
foreach ($marker in @(
        'per-task review dispatch is not available in story_end_only'
        'story_end_only should reject per-task review dispatch'
        'coordinator reconciliation is required before resuming'
        'End-ImplementerReviewTurn'
        'Resume-ImplementerOnReviewerMessage'
        'Observe-HealthyReviewRecovery'
        'turnStatus = ''active'''
        'Authorize-ImplementerResume'
        'must terminate from the exact action trace'
        'source_edit'
        'coordinator_copy'
        'reconcile_required'
        'healthyAfterReconciliation'
        'failed handoff delivery must escalate to the coordinator'
        'duplicate acceptance must not resume or write again'
        'ready-next-task-per_task'
        'accepted task should allow next task review handoff'
        'next task handoff must validate the terminal handoff suffix')) {
    if (-not (Get-Content $automaticFlowScriptPath -Raw).Contains($marker)) {
        throw "Automatic review-flow fixture assertion failed: $marker"
    }
}
foreach ($marker in @(
        'Acceptance reconciliation transaction'
        'reviewer message is not a Taiga write result'
        'marker-bearing parent-story progress comment'
        'story_end_only'
        'merge/release as separate gates'
        'exactly one final whole-story review'
        'fresh final-review request')) {
    if (-not $normalizedAutomaticFlow.Contains($marker)) {
        throw "Automatic review-flow contract assertion failed: $marker"
    }
}
foreach ($marker in @(
        'New-ReconciliationState'
        'Reconcile-TaskAcceptance'
        'Reconcile-FinalStoryAcceptance'
        'humanBeforeTaskWrite'
        'taskResponseLost'
        'acceptanceMarkers'
        'confirmed_after_response_loss'
        'interrupted task/comment sequence'
        'duplicate acceptance with a new message id'
        'final story acceptance must preserve separate merge and release gates')) {
    if (-not (Get-Content $automaticFlowScriptPath -Raw).Contains($marker)) {
        throw "Automatic review-flow reconciliation fixture assertion failed: $marker"
    }
}
foreach ($marker in @(
        'exact current HEAD'
        'Find an existing PR by repository, exact head branch, topology-specific base, and reviewed head commit'
        'Reuse a PR only when all of those identities match and the provider reports it open and unclosed'
        'A PR from another branch, an incorrect base, a closed/unmerged PR'
        'If an exact-match PR has missing or null provider state, return an unknown/reconcile outcome'
        'The story PR must target the topology-specific base'
        'active `legacy-standalone-feature` run is the explicit compatibility exception'
        'state: pr_ready_for_approval'
        'never blindly retry a write or create a duplicate PR'
        'one explicit final whole-story review'
        'task acceptance records alone are insufficient'
        'Independent verification:'
        'Inspected worker evidence:')) {
    if (-not $normalizedPrDelivery.Contains($marker)) {
        throw "PR delivery assertion failed: $marker"
    }
}
if (-not (Get-Content $prDeliveryScriptPath -Raw).Contains('Passed offline PR delivery fixture')) {
    throw 'PR delivery assertion failed: offline fixture coverage'
}
foreach ($marker in @('unknownState', 'provider_state_unknown', 'should-not-create', 'unknown-state reconciliation')) {
    if (-not (Get-Content $prDeliveryScriptPath -Raw).Contains($marker)) {
        throw "PR delivery assertion failed: unknown-state fixture marker $marker"
    }
}
foreach ($marker in @('Resolve-MigrationTopology', 'resolvedLegacyTopology', 'resolvedEpicTopology', 'needs-reconciliation', 'epic scope preserves the epic feature topology')) {
    if (-not (Get-Content $continuationScriptPath -Raw).Contains($marker)) {
        throw "Continuation migration fixture assertion failed: $marker"
    }
}
foreach ($marker in @(
        'Invoke-StaleSnapshotRecovery'
        'Get-AuthoritativeRecoveryState'
        'TaskAcceptances'
        'ConfirmedWrites'
        'WorkerStates'
        'acceptanceMatches.Count -eq 0'
        'writeMatches.Count -eq 0'
        'advancementMatches.Count -eq 0'
        'implementerMatches.Count -eq 0'
        'worker pair advances independently before stale snapshot recovery'
        'authoritative acceptance, confirmed write, advancement, and worker state are sufficient for recovery'
        'recovery does not duplicate messages'
        'recovery does not duplicate Taiga writes'
        'recovery does not duplicate task advancement'
        'repeated recovery of the reconciled snapshot is a no-op'
        'recovery holds when authoritative evidence is missing'
        'recovery holds when authoritative evidence conflicts'
        'empty acceptance lookup holds recovery'
        'unknown write outcome holds recovery'
        'unconfirmed implementer lookup holds recovery'
        'schedule: PAUSED'
        'confirmed provider schedule state'
        'next ordered story actually begins')) {
    if (-not (Get-Content $continuationScriptPath -Raw).Contains($marker)) {
        throw "Continuation recovery fixture assertion failed: $marker"
    }
}
foreach ($marker in @(
        'Yes — merge and continue to the next ordered story'
        'No — hold for feedback'
        'Yes`, PR URL/repository/base/scope/head still match, provider confirms merged'
        'An empty response, timeout, unrelated text, or a worker message is `no_response`'
        'Only a verified provider merge unlocks the next epic story'
        'Legacy standalone: Yes — merge this exact PR and continue to final release'
        'legacy standalone run has no next-story dispatch'
        'Do not dispatch workers or send repeated notifications'
        'pause the existing recovery automation'
        'same automation ID'
        'reactivate the same automation ID'
        'final story merge in an epic'
        'An approval is bound to the PR URL, repository, expected worktree/branch, base and diff range, clean tracked-source state, full reviewed head, and story scope')) {
    if (-not $normalizedMergeApproval.Contains($marker)) {
        throw "Merge approval assertion failed: $marker"
    }
}
if (-not (Get-Content $mergeApprovalScriptPath -Raw).Contains('Passed offline merge-gate fixture')) {
    throw 'Merge approval assertion failed: offline fixture coverage'
}
foreach ($marker in @('CurrentPrUrl', 'CurrentRepository', 'CurrentBase', 'CurrentScope', 'Resolve-HeartbeatSchedule', 'approval-gate pause', 'same-heartbeat epic reactivation', 'terminal standalone/final-epic/legacy pause', 'changed PR URL', 'changed repository', 'changed base', 'changed story scope')) {
    if (-not (Get-Content $mergeApprovalScriptPath -Raw).Contains($marker)) {
        throw "Merge approval assertion failed: identity fixture marker $marker"
    }
}
foreach ($marker in @(
        '`gpt-6.1-sol` with `high` effort'
        'fresh relative to every story-level pair'
        'creates a new ordinary implementer/reviewer pair'
        'reviewer begins work immediately'
        'implementer receives the same scope-bound assignment but remains idle'
        'The fresh pair is reused for ordinary correction and exact-HEAD re-review rounds'
        'every linked story in authoritative order'
        'combined behavior across stories'
        'cross-story state transitions'
        'sends it directly to the fresh epic-fix implementer on an isolated integration-correction branch'
        'The coordinator does not relay findings'
        'resulting exact feature HEAD again')) {
    if (-not $normalizedFinalEpicReview.Contains($marker)) {
        throw "Final epic review assertion failed: $marker"
    }
}
if (-not (Get-Content $finalEpicReviewScriptPath -Raw).Contains('Passed offline final epic review fixture')) {
    throw 'Final epic review assertion failed: offline fixture coverage'
}
foreach ($marker in @(
        'This contract applies to an epic or to an active legacy standalone run'
        'an epic run requires the integrated epic acceptance'
        'creates or reuses one final PR with the feature branch as head and `master` as base'
        'An active `legacy-standalone-feature` run is the compatibility exception'
        'obtain a separate final legacy review acceptance'
        'only after the final legacy review has accepted'
        'New standalone runs never use this exception'
        'Final master merge: pending separate user approval; not automatic'
        'Story integration, final review, final PR creation, and master release remain distinct facts')) {
    if (-not $normalizedFinalDelivery.Contains($marker)) {
        throw "Final delivery assertion failed: $marker"
    }
}
if (-not (Get-Content $finalDeliveryScriptPath -Raw).Contains('Passed offline final delivery fixture')) {
    throw 'Final delivery assertion failed: offline fixture coverage'
}
foreach ($marker in @('Resolve-FinalHeartbeat', 'terminal heartbeat pause and identity preservation', 'final delivery must pause an accidentally active heartbeat')) {
    if (-not (Get-Content $finalDeliveryScriptPath -Raw).Contains($marker)) {
        throw "Final delivery assertion failed: heartbeat fixture marker $marker"
    }
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'validate-branch-scenarios.ps1'))) {
    throw 'Missing disposable branch scenario check.'
}

foreach ($marker in @(
        'Capability discovery comes before a limitation claim'
        'production arguments, evidence hints, validation, and result semantics'
        'production entry point and a control'
        'cache hit is not evidence reuse'
        'automated_assertion'
        'visible_observation'
        '`unavailable`'
        'setup, start, actions, expected results, and cleanup'
        'synthetic fixtures do not become browser execution')) {
    if (-not $normalizedAcceptanceEvidence.Contains($marker)) {
        throw "Acceptance-evidence contract assertion failed: $marker"
    }
}
foreach ($marker in @(
        'false-unavailable-claim'
        'wrapper-bypass'
        'mislabeled-metric'
        'missing-scenario-evidence'
        'honest-limitation'
        'scenarioMatrix'
        'liveProvider')) {
    if (-not $acceptanceEvidenceManifestText.Contains($marker)) {
        throw "Acceptance-evidence manifest assertion failed: $marker"
    }
}
foreach ($marker in @(
        'Assert-CapabilityClaim'
        'observed availability is true'
        'production-path control'
        'Invoke-BypassingWrapper'
        'Assert-MetricRecord'
        'Assert-ScenarioCoverage'
        'Assert-SmokePlan'
        'Passed acceptance-evidence fixture')) {
    if (-not $acceptanceEvidenceScriptText.Contains($marker)) {
        throw "Acceptance-evidence fixture assertion failed: $marker"
    }
}

foreach ($recordMarker in @(
        '## 1. Single-repository story'
        '## 2. Multi-repository epic'
        '## 3. Ambiguous scope'
        '## 4. Valid scope'
        '## 5. Missing acceptance criteria'
        '## 6. Setup authorization input decisions'
        'Synthetic user reply and trace:'
        'Start'
        'Cancel'
        'mcp__codex_app__list_projects('
        'mcp__taiga__resolve_project('
        'mcp__taiga__get_task('
        'mcp__codex_app__create_worktree('
        'mcp__codex_app__set_thread_title({"title":"User Story #46 Coordinator"})'
        'mcp__codex_app__create_thread({"title":"User Story #46 Reviewer"'
        'mcp__codex_app__send_message_to_thread('
        'synthetic-review-46'
        'mcp__codex_app__automation_update('
        'git ls-remote --symref origin HEAD'
        'Mutation calls before Start: []'
        'Mutation calls after Cancel: []'
        'Each confirmed ready or correction-ready delivery is the end of that'
        'no implementer `wait_threads`'
        'failed or unknown delivery remains a coordinator reconciliation'
        '`ClarifyRequired(project)`'
        '`ClarifyRequired(acceptance criteria)`'
        'request_user_input'
        'Permitted selectable'
        'Missing submission evidence'
        'Default-only'
        'Empty/blank'
        'Explicit cancel'
        'Scope change'
        'mcp__codex_app__set_thread_title({"title":"Epic #45 Coordinator"})'
        'mcp__codex_app__create_thread({"title":"Epic #45 Implementer"'
        'mcp__codex_app__create_thread({"title":"Epic #45 Reviewer"'
        'synthetic-epic-45-review'
        'reviewer active'
        'implementer waiting for a finding')) {
    if (-not $normalizedWalkthrough.Contains($recordMarker)) {
        throw "Walkthrough record assertion failed: $recordMarker"
    }
}

foreach ($endpointMarker in @(
        'Legitimate expected-red checkpoint'
        'Unexpected failure'
        'Ambiguous endpoint'
        'Missing regression coverage'
        'Deferred criterion later satisfied'
        'Final review with unresolved RED/deferred evidence'
        'mandatory receipt schema')) {
    if (-not $normalizedTaskExecution.Contains($endpointMarker)) {
        throw "Task endpoint walkthrough assertion failed: $endpointMarker"
    }
}
foreach ($fixtureMarker in @(
        'Record-ExpectedRedCheckpoint'
        'unpermitted RED reason is rejected'
        'undeclared RED failure is rejected'
        'Record-UnexpectedFailure'
        'missing regression coverage cannot become review-ready'
        'Satisfy-DeferredCriterion'
        'Complete-StoryReview'
        'unrelated green evidence cannot resolve a RED checkpoint'
        'partial green evidence cannot resolve every RED regression'
        'final story review rejects unresolved expected RED')) {
    if (-not (Get-Content $taskExecutionScriptPath -Raw).Contains($fixtureMarker)) {
        throw "Task endpoint fixture assertion failed: $fixtureMarker"
    }
}

$worktreeMarker = 'mcp__codex_app__create_worktree({"name":"story-46-worker"'
$implementationThreadMarker = 'mcp__codex_app__create_thread({"title":"User Story #46 Implementer"'
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
$acceptanceOutput = @(& pwsh -NoProfile -File $acceptanceEvidenceScriptPath 2>&1 | ForEach-Object { [string]$_ })
$acceptanceExit = $LASTEXITCODE
if ($acceptanceExit -ne 0) {
    throw "Acceptance-evidence fixture exited ${acceptanceExit}: $($acceptanceOutput -join [Environment]::NewLine)"
}
$acceptanceOutput | Write-Output
$authorizationOutput = @(& pwsh -NoProfile -File $setupAuthorizationScriptPath 2>&1 | ForEach-Object { [string]$_ })
$authorizationExit = $LASTEXITCODE
if ($authorizationExit -ne 0) {
    throw "Setup-authorization fixture exited ${authorizationExit}: $($authorizationOutput -join [Environment]::NewLine)"
}
$authorizationOutput | Write-Output
Write-Output "Passed $($results.Count) static setup scenarios plus setup-authorization, contract, endpoint-walkthrough, recorded-walkthrough, and executable acceptance-evidence assertions; no live browser/provider evidence was claimed."
