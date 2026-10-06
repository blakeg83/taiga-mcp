# SYNTHETIC TASK EXECUTION CHECK.
# This file exercises the documented ordered-task state rules only. It does
# not contact Taiga, GitHub, Codex, or a live repository.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}

function Add-Task {
    param([int] $Id, [int[]] $DependsOn)
    $script:fixture.tasks[[string]$Id] = [ordered]@{
        id = $Id
        dependsOn = @($DependsOn)
        status = 'not_started'
        version = 1
        isBlocked = $false
        blockedNote = ''
        reviewableCommit = $null
        endpointEvidence = $false
        reviewableArtifact = ''
        expectedOutcome = ''
        expectedRedTests = @()
        permittedExpectedRedReasons = @{}
        observedExpectedRedFailures = @()
        safetyEvidence = @()
        expectedRedEvidence = $false
        expectedRedResolved = $false
        resolvedExpectedRedEvidence = @()
        unexpectedFailures = @()
        deferredCriteria = @()
        deferredEvidence = @()
        advancementGate = ''
        humanEdits = @()
        checklist = [ordered]@{ contract = $false; verification = $false }
        commits = @()
        comments = @()
    }
}

function Get-Task {
    param([int] $Id)
    $task = $script:fixture.tasks[[string]$Id]
    if ($null -eq $task) { throw "Unknown synthetic task: $Id" }
    return $task
}

function Set-ReviewableEndpoint {
    param(
        [int] $TaskId,
        [string] $Artifact,
        [ValidateSet('pass', 'expected_red')] [string] $ExpectedOutcome,
        [string[]] $ExpectedRedTests = @(),
        [hashtable] $ExpectedRedReasons = @{},
        [string[]] $DeferredCriteria = @(),
        [string] $AdvancementGate
    )

    $task = Get-Task $TaskId
    if ([string]::IsNullOrWhiteSpace($Artifact)) { throw "task $TaskId requires a reviewable artifact" }
    if ([string]::IsNullOrWhiteSpace($AdvancementGate)) { throw "task $TaskId requires an advancement gate" }
    foreach ($criterion in @($DeferredCriteria)) {
        if ([string]::IsNullOrWhiteSpace($criterion) -or $criterion -notlike '*owner:*') {
            throw "task $TaskId deferred criteria require a named owner"
        }
    }

    $task.endpointEvidence = $true
    $task.reviewableArtifact = $Artifact
    $task.expectedOutcome = $ExpectedOutcome
    $task.expectedRedTests = @($ExpectedRedTests)
    $task.permittedExpectedRedReasons = @{}
    foreach ($testName in @($ExpectedRedTests)) {
        if (-not $ExpectedRedReasons.ContainsKey($testName) -or [string]::IsNullOrWhiteSpace([string]$ExpectedRedReasons[$testName])) {
            throw "task $TaskId expected RED requires a permitted reason for $testName"
        }
        $task.permittedExpectedRedReasons[$testName] = [string]$ExpectedRedReasons[$testName]
    }
    $task.deferredCriteria = @($DeferredCriteria)
    $task.advancementGate = $AdvancementGate
    $task.checklist.contract = $true
}

function Record-PassingCheck {
    param([int] $TaskId, [string] $Evidence)
    $task = Get-Task $TaskId
    Assert-True $task.endpointEvidence "task $TaskId endpoint must be defined before recording a check"
    Assert-True ($task.expectedOutcome -eq 'pass') "task $TaskId does not expect a passing check"
    Assert-True ($Evidence -like '*exit 0*') "task $TaskId passing evidence must record exit 0"
    $task.safetyEvidence = @($Evidence)
    $task.checklist.verification = $true
}

function Record-ExpectedRedCheckpoint {
    param(
        [int] $TaskId,
        [string[]] $ObservedFailures,
        [string[]] $SafetyChecks
    )

    $task = Get-Task $TaskId
    Assert-True $task.endpointEvidence "task $TaskId endpoint must be defined before recording expected RED"
    Assert-True ($task.expectedOutcome -eq 'expected_red') "task $TaskId is not an expected-red checkpoint"
    Assert-True (@($task.expectedRedTests).Count -gt 0) "task $TaskId expected RED must name a behavior/test"
    Assert-True (@($ObservedFailures).Count -gt 0) "task $TaskId expected RED must record an observed failure"
    Assert-True (@($SafetyChecks).Count -gt 0) "task $TaskId expected RED must record safety evidence"

    Assert-True (@($ObservedFailures).Count -eq @($task.expectedRedTests).Count) "task $TaskId expected RED must record the complete failure set"
    $observedByTest = @{}
    foreach ($failure in @($ObservedFailures)) {
        $separator = $failure.IndexOf(':')
        Assert-True ($separator -gt 0 -and $separator -lt ($failure.Length - 1)) "task $TaskId expected RED failure entries require a test and reason"
        $testName = $failure.Substring(0, $separator).Trim()
        $reason = $failure.Substring($separator + 1).Trim()
        Assert-True (-not $observedByTest.ContainsKey($testName)) "task $TaskId expected RED cannot repeat $testName"
        $observedByTest[$testName] = $reason
    }
    foreach ($testName in @($task.expectedRedTests)) {
        Assert-True ($observedByTest.ContainsKey($testName)) "task $TaskId must record the observed reason for $testName"
        Assert-True ([string]$observedByTest[$testName] -ceq [string]$task.permittedExpectedRedReasons[$testName]) "task $TaskId observed reason for $testName is outside the permitted RED contract"
    }
    foreach ($observedTest in @($observedByTest.Keys)) {
        Assert-True ($task.expectedRedTests -contains $observedTest) "task $TaskId observed undeclared RED failure $observedTest"
    }
    foreach ($safetyCheck in @($SafetyChecks)) {
        Assert-True ($safetyCheck -like '*exit 0*') "task $TaskId safety evidence must pass"
    }

    $task.observedExpectedRedFailures = @($ObservedFailures)
    $task.safetyEvidence = @($SafetyChecks)
    $task.expectedRedEvidence = $true
    $task.checklist.verification = $true
}

function Record-UnexpectedFailure {
    param([int] $TaskId, [string] $TestName, [string] $Reason)
    $task = Get-Task $TaskId
    if ([string]::IsNullOrWhiteSpace($TestName) -or [string]::IsNullOrWhiteSpace($Reason)) {
        throw "task $TaskId unexpected failure requires a test and reason"
    }
    $task.unexpectedFailures += "${TestName}: $Reason"
}

function Resolve-ExpectedRedCheckpoint {
    param([int] $TaskId, [string[]] $Evidence)
    $task = Get-Task $TaskId
    Assert-True ($task.expectedOutcome -eq 'expected_red') "task $TaskId has no expected-red checkpoint to resolve"
    Assert-True (@($Evidence).Count -eq @($task.expectedRedTests).Count) "task $TaskId RED resolution must cover every declared regression"
    $resolvedByTest = @{}
    foreach ($result in @($Evidence)) {
        $separator = $result.IndexOf(':')
        Assert-True ($separator -gt 0 -and $separator -lt ($result.Length - 1)) "task $TaskId RED resolution entries require a test and result"
        $testName = $result.Substring(0, $separator).Trim()
        $outcome = $result.Substring($separator + 1).Trim()
        Assert-True (-not $resolvedByTest.ContainsKey($testName)) "task $TaskId RED resolution cannot repeat $testName"
        $resolvedByTest[$testName] = $outcome
    }
    foreach ($testName in @($task.expectedRedTests)) {
        Assert-True ($resolvedByTest.ContainsKey($testName)) "task $TaskId RED resolution is missing $testName"
        Assert-True ([string]$resolvedByTest[$testName] -like '*exit 0*') "task $TaskId RED resolution for $testName must record exit 0"
    }
    foreach ($resolvedTest in @($resolvedByTest.Keys)) {
        Assert-True ($task.expectedRedTests -contains $resolvedTest) "task $TaskId RED resolution contains undeclared regression $resolvedTest"
    }
    $task.expectedRedResolved = $true
    $task.resolvedExpectedRedEvidence = @($Evidence)
    $task.safetyEvidence += @($Evidence)
}

function Satisfy-DeferredCriterion {
    param([int] $TaskId, [string] $Criterion, [int] $OwnerTaskId)
    $task = Get-Task $TaskId
    $owner = Get-Task $OwnerTaskId
    Assert-True (@($task.deferredCriteria | Where-Object { $_ -like "${Criterion}*" }).Count -eq 1) "task $TaskId has no deferred criterion '$Criterion'"
    Assert-True ($owner.status -eq 'accepted') "task $OwnerTaskId must be accepted before supplying deferred evidence"
    $task.deferredEvidence += "${Criterion} | owner: task #$OwnerTaskId | evidence: accepted task"
}

function Complete-StoryReview {
    Assert-True (@($script:fixture.storyScope).Count -gt 0) 'story review requires a declared story scope'
    foreach ($taskId in @($script:fixture.storyScope)) {
        $task = Get-Task $taskId
        if ($task.expectedOutcome -eq 'expected_red') {
            Assert-True $task.expectedRedResolved "final story review cannot approve unresolved RED in task $taskId"
        }
        foreach ($criterion in @($task.deferredCriteria)) {
            Assert-True (@($task.deferredEvidence | Where-Object { $_ -like "$criterion*" }).Count -eq 1) "final story review lacks evidence for deferred criterion '$criterion'"
        }
    }
    $script:fixture.storyReviewApproved = $true
}

function Add-ProgressComment {
    param([int] $TaskId, [string] $Kind, [string] $Commit, [string] $Next)
    $task = Get-Task $TaskId
    $comment = "Task #$TaskId $Kind | commit: $Commit | checklist: contract=$($task.checklist.contract), verification=$($task.checklist.verification) | checks: exit 0 | review: $($task.status) | next: $Next"
    $task.comments += $comment
    $script:fixture.storyComments += $comment
}

function Set-Status {
    param([int] $TaskId, [int] $ExpectedVersion, [string] $Status)
    $task = Get-Task $TaskId
    if ($task.version -ne $ExpectedVersion) {
        throw "version_conflict task $TaskId expected $ExpectedVersion actual $($task.version)"
    }
    $task.status = $Status
    $task.version++
    return $task.version
}

function Start-Task {
    param([int] $TaskId)
    $task = Get-Task $TaskId
    if ($null -ne $script:fixture.activeTaskId -and $script:fixture.activeTaskId -ne $TaskId) {
        throw "ordered_gate active task $($script:fixture.activeTaskId) is not accepted"
    }
    foreach ($dependencyId in @($task.dependsOn)) {
        if ((Get-Task $dependencyId).status -ne 'accepted') {
            throw "prerequisite_gate task $TaskId depends on unaccepted task $dependencyId"
        }
    }
    $null = Set-Status $TaskId $task.version 'in_progress'
    $script:fixture.activeTaskId = $TaskId
}

function Fail-Check {
    param([int] $TaskId)
    $task = Get-Task $TaskId
    $task.checklist.verification = $false
    $task.comments += "Task #$TaskId check failed | exit: 1 | status: in_progress"
}

function Complete-Task {
    param([int] $TaskId, [string] $Commit, [switch] $ReviewRejected)
    $task = Get-Task $TaskId
    Assert-True ($task.status -eq 'in_progress') "task $TaskId must be in progress before completion"
    Assert-True $task.endpointEvidence "task $TaskId reviewable endpoint is required"
    Assert-True $task.checklist.contract "task $TaskId contract checklist is required"
    Assert-True $task.checklist.verification "task $TaskId verification checklist is required"
    Assert-True (@($task.unexpectedFailures).Count -eq 0) "task $TaskId has unexpected failures"
    if ($task.expectedOutcome -eq 'expected_red') {
        Assert-True $task.expectedRedEvidence "task $TaskId expected-red evidence is incomplete"
    }
    $task.commits += $Commit
    $task.reviewableCommit = $Commit
    $null = Set-Status $TaskId $task.version 'awaiting_review'
    Add-ProgressComment $TaskId 'complete' $Commit 'independent review'
    if ($ReviewRejected) {
        $null = Set-Status $TaskId $task.version 'in_progress'
        Add-ProgressComment $TaskId 'reopened' $Commit 'correction and new review'
    }
}

function Block-Task {
    param([int] $TaskId, [string] $Note)
    $task = Get-Task $TaskId
    $null = Set-Status $TaskId $task.version 'blocked'
    $task.isBlocked = $true
    $task.blockedNote = $Note
    $task.comments += "Task #$TaskId blocked | obstacle: $Note | dependent tasks: not started"
    $script:fixture.storyComments += $task.comments[-1]
}

function Resolve-Blocker {
    param([int] $TaskId)
    $task = Get-Task $TaskId
    Assert-True $task.isBlocked "task $TaskId must be blocked before resolution"
    $null = Set-Status $TaskId $task.version 'in_progress'
    $task.isBlocked = $false
    $task.blockedNote = ''
}

function Accept-Task {
    param([int] $TaskId, [string] $ReviewedCommit)
    $task = Get-Task $TaskId
    Assert-True ($task.status -eq 'awaiting_review') "task $TaskId is not ready for review"
    Assert-True ($task.reviewableCommit -eq $ReviewedCommit) "reviewed SHA is superseded or is not the current reviewable commit"
    $null = Set-Status $TaskId $task.version 'accepted'
    $task.comments += "Task #$TaskId accepted | reviewed commit: $ReviewedCommit"
    $task.reviewableCommit = $null
    $script:fixture.activeTaskId = $null
}

function Apply-HumanEdit {
    param([int] $TaskId, [string] $Status)
    $task = Get-Task $TaskId
    $task.status = $Status
    $task.version++
    $task.humanEdits += [ordered]@{ status = $Status; version = $task.version; source = 'human' }
    $task.comments += "Human edit preserved | status: $Status | version: $($task.version)"
}

function Reconcile-HumanEdit {
    param([int] $TaskId, [string] $Decision)
    $task = Get-Task $TaskId
    $edits = @($task.humanEdits)
    Assert-True ($edits.Count -gt 0) "task $TaskId has no human edit to reconcile"
    if ([string]::IsNullOrWhiteSpace($Decision)) {
        throw "task $TaskId requires an explicit human-status reconciliation decision"
    }
    if (@('preserve_human_status', 'replace_after_decision') -notcontains $Decision) {
        throw "task $TaskId has unsupported human-status reconciliation decision: $Decision"
    }

    $lastEdit = $edits[-1]
    if ($Decision -eq 'preserve_human_status') {
        $task.comments += "Human edit preserved; decision: preserve_human_status | status: $($lastEdit.status) | version: $($lastEdit.version)"
        return
    }

    $task.comments += "Human edit preserved during reconciliation; decision: replace_after_decision | prior status: $($lastEdit.status) | prior version: $($lastEdit.version)"
    $null = Set-Status $TaskId $task.version 'in_progress'
}

$script:fixture = [ordered]@{
    tasks = @{}
    activeTaskId = $null
    storyComments = @()
    storyScope = @()
    storyReviewApproved = $false
}

try {
    Add-Task 901 @()
    Add-Task 902 @(901)
    Add-Task 903 @(902)

    Start-Task 901
    Set-ReviewableEndpoint -TaskId 901 -Artifact 'shared task contract' -ExpectedOutcome 'pass' -AdvancementGate 'reviewer accepts exact commit before task #902'
    Fail-Check 901
    Assert-Throws { Complete-Task 901 'a901-failed' } 'failed verification cannot produce review-ready task'
    Assert-True ((Get-Task 901).status -eq 'in_progress') 'failed check keeps task in progress'
    Assert-True (-not (Get-Task 901).checklist.verification) 'failed check leaves verification unchecked'

    $task901 = Get-Task 901
    Record-PassingCheck 901 'contract fixture check | exit 0'
    Complete-Task 901 'a901001'
    Assert-True ((Get-Task 902).status -eq 'not_started') 'dependent task remains untouched before acceptance'
    Assert-Throws { Start-Task 902 } 'unaccepted prerequisite blocks next task'
    Accept-Task 901 'a901001'

    Start-Task 902
    Set-ReviewableEndpoint -TaskId 902 -Artifact 'consumer implementation' -ExpectedOutcome 'pass' -AdvancementGate 'reviewer accepts exact commit before task #903'
    Block-Task 902 'required provider decision is missing'
    Assert-True ((Get-Task 902).isBlocked) 'blocked task records isBlocked'
    Assert-True ((Get-Task 902).blockedNote -like '*provider decision*') 'blocked task records note'
    Assert-Throws { Start-Task 903 } 'blocked prerequisite stops dependent task'
    Resolve-Blocker 902

    $task902 = Get-Task 902
    $plannedVersion = $task902.version
    Apply-HumanEdit 902 'needs_info'
    Assert-Throws { Set-Status 902 $plannedVersion 'awaiting_review' } 'human edit causes version conflict'
    Assert-True ((Get-Task 902).status -eq 'needs_info') 'human status is preserved after conflict'
    Assert-True (@((Get-Task 902).humanEdits | Where-Object { $_.status -eq 'needs_info' }).Count -eq 1) 'human edit is retained as history'
    Assert-Throws { Reconcile-HumanEdit 902 } 'human status replacement requires explicit decision'
    Assert-True ((Get-Task 902).status -eq 'needs_info') 'missing decision leaves human status unchanged'
    Reconcile-HumanEdit 902 'preserve_human_status'
    Assert-True ((Get-Task 902).status -eq 'needs_info') 'preserve decision leaves human status unchanged'
    Reconcile-HumanEdit 902 'replace_after_decision'
    Assert-True ((Get-Task 902).status -eq 'in_progress') 'replace decision records the intended status transition'
    Assert-True (@((Get-Task 902).humanEdits | Where-Object { $_.status -eq 'needs_info' }).Count -eq 1) 'human edit remains after reconciliation'
    Assert-True (@((Get-Task 902).comments | Where-Object { $_ -like '*decision: replace_after_decision*' }).Count -eq 1) 'human edit reconciliation decision is surfaced'
    Record-PassingCheck 902 'consumer fixture check | exit 0'
    Complete-Task 902 'a902001' -ReviewRejected
    Assert-True ((Get-Task 902).status -eq 'in_progress') 'review rejection reopens only affected task'
    $task902.checklist.verification = $true
    Complete-Task 902 'a902002'
    Assert-Throws { Accept-Task 902 'a902001' } 'superseded commit cannot be accepted'
    Assert-Throws { Start-Task 903 } 'task 903 waits for task 902 acceptance'
    Accept-Task 902 'a902002'

    Start-Task 903
    Set-ReviewableEndpoint -TaskId 903 -Artifact 'integrated behavior' -ExpectedOutcome 'pass' -AdvancementGate 'reviewer accepts exact final task commit before story review'
    $task903 = Get-Task 903
    Record-PassingCheck 903 'integrated fixture check | exit 0'
    Complete-Task 903 'a903001'
    Assert-True ((Get-Task 903).status -eq 'awaiting_review') 'final task is ready for review, not done'

    $task901CommentCount = @((Get-Task 901).comments).Count
    Assert-True ($task901CommentCount -eq 3) 'task 901 retains failed-check, completion, and acceptance records'
    Assert-True ((Get-Task 902).commits -contains 'a902001') 'rejected revision is retained'
    Assert-True ((Get-Task 902).commits -contains 'a902002') 'corrected revision has a new commit'
    Assert-True (@((Get-Task 902).comments | Where-Object { $_ -like '*a902001*' }).Count -eq 2) 'correction evidence retains old and new revision records'
    Assert-True (@((Get-Task 903).comments | Where-Object { $_ -like '*a903001*' }).Count -eq 1) 'final task has one completion comment'
    Assert-True (@($script:fixture.storyComments | Where-Object { $_ -like '*Task #903*' }).Count -eq 1) 'no dependent story comment precedes task 903 start'

    # A named expected-red checkpoint is reviewable when its observed failure
    # and safety evidence match the endpoint contract.
    $script:fixture = [ordered]@{ tasks = @{}; activeTaskId = $null; storyComments = @(); storyScope = @(); storyReviewApproved = $false }
    Add-Task 904 @()
    Start-Task 904
    Set-ReviewableEndpoint -TaskId 904 -Artifact 'declared behavior regression' -ExpectedOutcome 'expected_red' -ExpectedRedTests @('test_declared_behavior') -ExpectedRedReasons @{ test_declared_behavior = 'endpoint not implemented' } -AdvancementGate 'reviewer accepts the checkpoint before dependent work'
    Record-ExpectedRedCheckpoint -TaskId 904 -ObservedFailures @('test_declared_behavior: endpoint not implemented') -SafetyChecks @('test_safety: exit 0')
    Complete-Task 904 'a904001'
    Assert-True ((Get-Task 904).status -eq 'awaiting_review') 'legitimate expected RED can become review-ready'
    Accept-Task 904 'a904001'
    Assert-True ((Get-Task 904).observedExpectedRedFailures[0] -like 'test_declared_behavior:*') 'expected RED records the named observed failure'
    Assert-True ((Get-Task 904).safetyEvidence[0] -like '*exit 0*') 'expected RED records passing safety evidence'
    Assert-Throws { Record-ExpectedRedCheckpoint -TaskId 904 -ObservedFailures @('test_declared_behavior: authentication crash') -SafetyChecks @('test_safety: exit 0') } 'unpermitted RED reason is rejected'
    Assert-Throws { Record-ExpectedRedCheckpoint -TaskId 904 -ObservedFailures @('test_declared_behavior: endpoint not implemented', 'test_data_integrity: data corruption') -SafetyChecks @('test_safety: exit 0') } 'undeclared RED failure is rejected'

    # An incomplete artifact/advancement endpoint requires clarification before
    # task start and leaves dependent work untouched.
    $script:fixture = [ordered]@{ tasks = @{}; activeTaskId = $null; storyComments = @(); storyScope = @(); storyReviewApproved = $false }
    Add-Task 913 @()
    Add-Task 914 @(913)
    Assert-Throws { Set-ReviewableEndpoint -TaskId 913 -Artifact '' -ExpectedOutcome 'pass' -AdvancementGate '' } 'ambiguous endpoint requires clarification'
    Assert-Throws { Start-Task 914 } 'ambiguous endpoint blocks the dependent task'
    Assert-True ((Get-Task 914).status -eq 'not_started') 'ambiguous endpoint leaves dependent task untouched'

    # An unrelated failure cannot be relabeled as the permitted RED and cannot
    # release a dependent task.
    $script:fixture = [ordered]@{ tasks = @{}; activeTaskId = $null; storyComments = @(); storyScope = @(); storyReviewApproved = $false }
    Add-Task 905 @()
    Add-Task 906 @(905)
    Start-Task 905
    Set-ReviewableEndpoint -TaskId 905 -Artifact 'declared behavior regression' -ExpectedOutcome 'expected_red' -ExpectedRedTests @('test_declared_behavior') -ExpectedRedReasons @{ test_declared_behavior = 'endpoint not implemented' } -AdvancementGate 'reviewer accepts the checkpoint before task #906'
    Record-UnexpectedFailure 905 'test_unrelated_behavior' 'unexpected state transition'
    (Get-Task 905).checklist.verification = $true
    Assert-Throws { Complete-Task 905 'a905001' } 'unexpected failure cannot become review-ready'
    Assert-True ((Get-Task 905).status -eq 'in_progress') 'unexpected failure keeps task in progress'
    Assert-Throws { Start-Task 906 } 'unexpected failure blocks the dependent task'
    Assert-True ((Get-Task 906).status -eq 'not_started') 'blocked dependent task remains untouched'

    # Expected-red work without named regression evidence cannot become
    # review-ready, even when a task endpoint exists.
    $script:fixture = [ordered]@{ tasks = @{}; activeTaskId = $null; storyComments = @(); storyScope = @(); storyReviewApproved = $false }
    Add-Task 907 @()
    Start-Task 907
    Set-ReviewableEndpoint -TaskId 907 -Artifact 'missing regression fixture' -ExpectedOutcome 'expected_red' -ExpectedRedTests @('test_missing_regression') -ExpectedRedReasons @{ test_missing_regression = 'endpoint not implemented' } -AdvancementGate 'reviewer accepts only after named regression evidence'
    Assert-Throws { Record-ExpectedRedCheckpoint -TaskId 907 -ObservedFailures @() -SafetyChecks @('test_safety: exit 0') } 'missing regression coverage is rejected'
    Assert-Throws { Complete-Task 907 'a907001' } 'missing regression coverage cannot become review-ready'
    Assert-True (-not (Get-Task 907).expectedRedEvidence) 'missing regression evidence remains unrecorded'

    # Deferred criteria stay attached to the originating task until the named
    # later owner supplies evidence.
    $script:fixture = [ordered]@{ tasks = @{}; activeTaskId = $null; storyComments = @(); storyScope = @(); storyReviewApproved = $false }
    Add-Task 907 @()
    Add-Task 908 @(907)
    Set-ReviewableEndpoint -TaskId 907 -Artifact 'deferred contract' -ExpectedOutcome 'pass' -DeferredCriteria @('final regression green | owner: task #908') -AdvancementGate 'reviewer accepts task #907, then task #908 supplies the deferred evidence'
    Start-Task 907
    Record-PassingCheck 907 'deferred contract check | exit 0'
    Complete-Task 907 'a907002'
    Accept-Task 907 'a907002'
    Assert-True ((Get-Task 907).deferredEvidence.Count -eq 0) 'deferred criterion remains visible after source task acceptance'
    Start-Task 908
    Set-ReviewableEndpoint -TaskId 908 -Artifact 'final regression evidence' -ExpectedOutcome 'pass' -AdvancementGate 'final story review'
    Record-PassingCheck 908 'final regression check | exit 0'
    Complete-Task 908 'a908002'
    Accept-Task 908 'a908002'
    Satisfy-DeferredCriterion -TaskId 907 -Criterion 'final regression green' -OwnerTaskId 908
    Assert-True ((Get-Task 907).deferredEvidence.Count -eq 1) 'later owner supplies deferred evidence'

    # Final story approval rejects unresolved RED first, then rejects missing
    # deferred evidence, and succeeds only after both are resolved.
    $script:fixture = [ordered]@{ tasks = @{}; activeTaskId = $null; storyComments = @(); storyScope = @(); storyReviewApproved = $false }
    Add-Task 910 @()
    Add-Task 911 @()
    Add-Task 912 @(911)
    $script:fixture.storyScope = @(910, 911, 912)
    Start-Task 910
    Set-ReviewableEndpoint -TaskId 910 -Artifact 'final regression checkpoint' -ExpectedOutcome 'expected_red' -ExpectedRedTests @('test_final_regression', 'test_final_filter_regression') -ExpectedRedReasons @{ test_final_regression = 'endpoint not implemented'; test_final_filter_regression = 'endpoint not implemented' } -AdvancementGate 'final story review requires every formerly red test to pass'
    Record-ExpectedRedCheckpoint -TaskId 910 -ObservedFailures @('test_final_regression: endpoint not implemented', 'test_final_filter_regression: endpoint not implemented') -SafetyChecks @('test_safety: exit 0')
    Complete-Task 910 'a910001'
    Accept-Task 910 'a910001'
    Start-Task 911
    Set-ReviewableEndpoint -TaskId 911 -Artifact 'story-level deferred criterion' -ExpectedOutcome 'pass' -DeferredCriteria @('final regression green | owner: task #912') -AdvancementGate 'final story review'
    Record-PassingCheck 911 'story deferred check | exit 0'
    Complete-Task 911 'a911001'
    Accept-Task 911 'a911001'
    Start-Task 912
    Set-ReviewableEndpoint -TaskId 912 -Artifact 'deferred owner evidence' -ExpectedOutcome 'pass' -AdvancementGate 'final story review'
    Record-PassingCheck 912 'owner evidence check | exit 0'
    Complete-Task 912 'a912001'
    Accept-Task 912 'a912001'
    Assert-Throws { Complete-StoryReview } 'final story review rejects unresolved expected RED'
    Assert-Throws { Resolve-ExpectedRedCheckpoint -TaskId 910 -Evidence @('test_unrelated: exit 0') } 'unrelated green evidence cannot resolve a RED checkpoint'
    Assert-Throws { Resolve-ExpectedRedCheckpoint -TaskId 910 -Evidence @('test_final_regression: exit 0') } 'partial green evidence cannot resolve every RED regression'
    Resolve-ExpectedRedCheckpoint -TaskId 910 -Evidence @('test_final_regression: exit 0', 'test_final_filter_regression: exit 0')
    Assert-Throws { Complete-StoryReview } 'final story review rejects missing deferred evidence'
    Satisfy-DeferredCriterion -TaskId 911 -Criterion 'final regression green' -OwnerTaskId 912
    Complete-StoryReview
    Assert-True $script:fixture.storyReviewApproved 'final story review succeeds only after RED and deferred evidence resolve'

    Write-Output 'Passed synthetic ordered-task, failed-check, blocker, review-rejection, human-conflict, reviewable-endpoint, expected-red, deferred-criteria, final-review, commit, and parent-comment assertions.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
