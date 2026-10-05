[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$coordinator = 'coordinator-story-49'
$implementer = 'implementer-story-49'
$reviewer = 'reviewer-story-49'
$messages = [System.Collections.Generic.List[object]]::new()
$createdChats = [System.Collections.Generic.HashSet[string]]::new()
$reviewedTaskRevisions = @{}
$reviewedStoryHeads = [System.Collections.Generic.HashSet[string]]::new()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Routing assertion failed: $Message" }
}

function Assert-Throws {
    param([scriptblock] $ScriptBlock, [string] $Message)
    $threw = $false
    try { & $ScriptBlock } catch { $threw = $true }
    Assert-True $threw $Message
}

function Add-Chat {
    param([string] $WorkerId)
    [void]$createdChats.Add($WorkerId)
}

function Send-Message {
    param(
        [string] $Sender,
        [string] $Destination,
        [string] $Kind,
        [string] $Task,
        [string] $Revision,
        [string] $Next,
        [string] $Reason = ''
    )

    Assert-True (-not [string]::IsNullOrWhiteSpace($Destination)) "$Kind must have a destination"
    Assert-True ($Destination -in @($coordinator, $implementer, $reviewer)) "$Kind destination must be known"
    $directDestination = @{
        finding = $implementer
        correction = $reviewer
        story_approval = $coordinator
        blocked = $coordinator
        disagreement = $coordinator
        stale_approval = $coordinator
        missing_destination = $coordinator
        unknown_delivery = $coordinator
        revision_conflict = $coordinator
    }
    if ($directDestination.ContainsKey($Kind)) {
        Assert-True ($Destination -eq $directDestination[$Kind]) "$Kind must use its contract destination"
    }
    $message = [ordered]@{
        sender = $Sender
        destination = $Destination
        kind = $Kind
        task = $Task
        revision = $Revision
        next = $Next
    }
    if ($Reason) { $message.reason = $Reason }
    [void]$messages.Add([pscustomobject]$message)
}

function Get-Messages {
    param([string] $Kind, [string] $Task)
    @($messages | Where-Object { $_.kind -eq $Kind -and $_.task -eq $Task })
}

function Record-Task-Review {
    param([string] $Task, [string] $Revision)
    $reviewedTaskRevisions["$Task|$Revision"] = $true
}

function Accept-Task {
    param([string] $Task, [string] $Revision)
    Assert-True $reviewedTaskRevisions.ContainsKey("$Task|$Revision") "task $Task acceptance must name an inspected revision"
    Send-Message $reviewer $implementer 'accepted' $Task $Revision 'advance ordered task'
}

function Record-Story-Review {
    param([string] $Head)
    [void]$reviewedStoryHeads.Add($Head)
}

function Approve-Story {
    param([string] $ReviewedHead, [string] $CurrentHead)
    Assert-True ($reviewedStoryHeads.Contains($ReviewedHead) -and $ReviewedHead -eq $CurrentHead) 'story approval must name the reviewed current HEAD'
    Send-Message $reviewer $coordinator 'story_approval' 'story-49' $ReviewedHead 'use exact reviewed HEAD'
}

Add-Chat $implementer
Add-Chat $reviewer
$initialChatCount = $createdChats.Count

# Task A: ready, finding, correction, and acceptance stay on the same pair.
Send-Message $implementer $reviewer 'ready' '#65' 'a1' 'review exact revision'
Send-Message $reviewer $implementer 'finding' '#65' 'a1' 'correct same branch' 'missing reviewer host evidence'
Send-Message $implementer $reviewer 'correction' '#65' 'a2' 're-review exact revision'
Record-Task-Review '#65' 'a2'
Assert-Throws { Accept-Task '#65' 'a1' } 'unreviewed task revision must be rejected'
Accept-Task '#65' 'a2'

# Task B: a second task has its own correction and the same final reviewer.
Send-Message $implementer $reviewer 'ready' '#66' 'b1' 'review exact revision'
Send-Message $reviewer $implementer 'finding' '#66' 'b1' 'correct same branch' 'route omitted coordinator context'
Send-Message $implementer $reviewer 'correction' '#66' 'b2' 're-review exact revision'
Record-Task-Review '#66' 'b2'
Assert-Throws { Accept-Task '#66' 'b1' } 'second unreviewed task revision must be rejected'
Accept-Task '#66' 'b2'
Record-Story-Review 'b2'
Assert-Throws { Approve-Story 'b2' 'b3' } 'changed HEAD must invalidate final approval'
Approve-Story 'b2' 'b2'

# Exceptional routes are coordinator messages, not automatic retries or new chats.
Send-Message $implementer $coordinator 'blocked' '#67' 'c1' 'request decision' 'required capability unavailable'
Send-Message $reviewer $coordinator 'disagreement' '#67' 'c1' 'ask user for requirement decision' 'substantive requirement disagreement'
Send-Message $reviewer $coordinator 'stale_approval' 'story-49' 'b2' 're-review changed HEAD' 'current HEAD is b3'
Send-Message $reviewer $coordinator 'missing_destination' '#68' '' 'resolve worker identity' 'reviewer destination is unresolved'
Send-Message $reviewer $coordinator 'unknown_delivery' '#68' 'c2' 'reconcile before retry' 'reviewer delivery result is unknown'
Send-Message $implementer $coordinator 'revision_conflict' '#68' 'c2' 'reconcile current review binding' 'branch HEAD conflicts with the pending reviewed revision'

# Routine finding/correction copies to the coordinator are forbidden.
Assert-Throws { Send-Message $reviewer $coordinator 'finding' '#65' 'a1' 'correct same branch' 'routine finding copy' } 'routine finding must not be copied to the coordinator'
Assert-Throws { Send-Message $implementer $coordinator 'correction' '#65' 'a2' 're-review exact revision' 'routine correction copy' } 'routine correction must not be copied to the coordinator'

Assert-True ($createdChats.Count -eq $initialChatCount) 'ordinary corrections must not create a new chat'
$taskACorrections = @(Get-Messages 'correction' '#65')
$taskBCorrections = @(Get-Messages 'correction' '#66')
$storyApprovals = @(Get-Messages 'story_approval' 'story-49')
$staleApprovals = @(Get-Messages 'stale_approval' 'story-49')
Assert-True ($taskACorrections.Count -eq 1) 'task A must have one correction'
Assert-True ($taskBCorrections.Count -eq 1) 'task B must have one correction'
Assert-True ($taskACorrections[0].destination -eq $reviewer) 'task A correction must return to the same reviewer'
Assert-True ($taskBCorrections[0].destination -eq $reviewer) 'task B correction must return to the same reviewer'
Assert-True (@($messages | Where-Object { $_.kind -in @('finding', 'correction') -and $_.destination -eq $coordinator }).Count -eq 0) 'routine findings and corrections must not reach the coordinator'
Assert-True ($storyApprovals.Count -eq 1 -and $storyApprovals[0].destination -eq $coordinator) 'final approval must route to coordinator'
Assert-True (@($messages | Where-Object { $_.kind -in @('blocked','disagreement','stale_approval','missing_destination','unknown_delivery','revision_conflict') -and $_.destination -ne $coordinator }).Count -eq 0) 'exceptional states must route to coordinator'
Assert-True (@($messages | Where-Object { $_.PSObject.Properties.Name -contains 'transcript' -or $_.PSObject.Properties.Name -contains 'receipt' }).Count -eq 0) 'messages must not relay full transcripts or structured receipts'
Assert-True ($staleApprovals.Count -eq 1 -and $staleApprovals[0].next -eq 're-review changed HEAD') 'stale approval must return to review'
Assert-True ((Get-Messages 'unknown_delivery' '#68').Count -eq 1) 'unknown delivery must escalate once'
Assert-True ((Get-Messages 'revision_conflict' '#68').Count -eq 1) 'revision conflict must escalate once'
Assert-True ($messages.Count -eq 15) 'fixture should cover the complete controlled route set'

Write-Output "Passed routing fixture: two tasks, direct correction rounds, stable pair, no routine coordinator relay, concise context, and coordinator escalation paths. No time or correction-count cutoff is used."
