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
    Assert-True $task.checklist.contract "task $TaskId contract checklist is required"
    Assert-True $task.checklist.verification "task $TaskId verification checklist is required"
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
    param([int] $TaskId)
    $task = Get-Task $TaskId
    $edits = @($task.humanEdits)
    Assert-True ($edits.Count -gt 0) "task $TaskId has no human edit to reconcile"
    $task.comments += "Human edit preserved during reconciliation | status: $($edits[-1].status) | version: $($edits[-1].version)"
    $null = Set-Status $TaskId $task.version 'in_progress'
}

$script:fixture = [ordered]@{
    tasks = @{}
    activeTaskId = $null
    storyComments = @()
}

try {
    Add-Task 901 @()
    Add-Task 902 @(901)
    Add-Task 903 @(902)

    Start-Task 901
    Fail-Check 901
    Assert-Throws { Complete-Task 901 'a901-failed' } 'failed verification cannot produce review-ready task'
    Assert-True ((Get-Task 901).status -eq 'in_progress') 'failed check keeps task in progress'
    Assert-True (-not (Get-Task 901).checklist.verification) 'failed check leaves verification unchecked'

    $task901 = Get-Task 901
    $task901.checklist.contract = $true
    $task901.checklist.verification = $true
    Complete-Task 901 'a901001'
    Assert-True ((Get-Task 902).status -eq 'not_started') 'dependent task remains untouched before acceptance'
    Assert-Throws { Start-Task 902 } 'unaccepted prerequisite blocks next task'
    Accept-Task 901 'a901001'

    Start-Task 902
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
    Reconcile-HumanEdit 902
    Assert-True (@((Get-Task 902).humanEdits | Where-Object { $_.status -eq 'needs_info' }).Count -eq 1) 'human edit remains after reconciliation'
    Assert-True (@((Get-Task 902).comments | Where-Object { $_ -like '*Human edit preserved during reconciliation*' }).Count -eq 1) 'human edit reconciliation is surfaced'
    $task902.checklist.contract = $true
    $task902.checklist.verification = $true
    Complete-Task 902 'a902001' -ReviewRejected
    Assert-True ((Get-Task 902).status -eq 'in_progress') 'review rejection reopens only affected task'
    $task902.checklist.verification = $true
    Complete-Task 902 'a902002'
    Assert-Throws { Accept-Task 902 'a902001' } 'superseded commit cannot be accepted'
    Assert-Throws { Start-Task 903 } 'task 903 waits for task 902 acceptance'
    Accept-Task 902 'a902002'

    Start-Task 903
    $task903 = Get-Task 903
    $task903.checklist.contract = $true
    $task903.checklist.verification = $true
    Complete-Task 903 'a903001'
    Assert-True ((Get-Task 903).status -eq 'awaiting_review') 'final task is ready for review, not done'

    $task901CommentCount = @((Get-Task 901).comments).Count
    Assert-True ($task901CommentCount -eq 3) 'task 901 retains failed-check, completion, and acceptance records'
    Assert-True ((Get-Task 902).commits -contains 'a902001') 'rejected revision is retained'
    Assert-True ((Get-Task 902).commits -contains 'a902002') 'corrected revision has a new commit'
    Assert-True (@((Get-Task 902).comments | Where-Object { $_ -like '*a902001*' }).Count -eq 2) 'correction evidence retains old and new revision records'
    Assert-True (@((Get-Task 903).comments | Where-Object { $_ -like '*a903001*' }).Count -eq 1) 'final task has one completion comment'
    Assert-True (@($script:fixture.storyComments | Where-Object { $_ -like '*Task #903*' }).Count -eq 1) 'no dependent story comment precedes task 903 start'

    Write-Output 'Passed synthetic ordered-task, failed-check, blocker, review-rejection, human-conflict, commit, and parent-comment assertions.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
