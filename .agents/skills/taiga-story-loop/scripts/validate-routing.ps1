[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$coordinator = 'coordinator-story-49'
$implementer = 'implementer-story-49'
$reviewer = 'reviewer-story-49'
$messages = [System.Collections.Generic.List[object]]::new()
$createdChats = [System.Collections.Generic.HashSet[string]]::new()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Routing assertion failed: $Message" }
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

Add-Chat $implementer
Add-Chat $reviewer
$initialChatCount = $createdChats.Count

# Task A: ready, finding, correction, and acceptance stay on the same pair.
Send-Message $implementer $reviewer 'ready' '#65' 'a1' 'review exact revision'
Send-Message $reviewer $implementer 'finding' '#65' 'a1' 'correct same branch' 'missing reviewer host evidence'
Send-Message $implementer $reviewer 'correction' '#65' 'a2' 're-review exact revision'
Send-Message $reviewer $implementer 'accepted' '#65' 'a2' 'advance ordered task'

# Task B: a second task has its own correction and the same final reviewer.
Send-Message $implementer $reviewer 'ready' '#66' 'b1' 'review exact revision'
Send-Message $reviewer $implementer 'finding' '#66' 'b1' 'correct same branch' 'route omitted coordinator context'
Send-Message $implementer $reviewer 'correction' '#66' 'b2' 're-review exact revision'
Send-Message $reviewer $implementer 'accepted' '#66' 'b2' 'complete ordered tasks'
Send-Message $reviewer $coordinator 'story_approval' 'story-49' 'b2' 'use exact reviewed HEAD'

# Exceptional routes are coordinator messages, not automatic retries or new chats.
Send-Message $implementer $coordinator 'blocked' '#67' 'c1' 'request decision' 'required capability unavailable'
Send-Message $reviewer $coordinator 'disagreement' '#67' 'c1' 'ask user for requirement decision' 'substantive requirement disagreement'
Send-Message $reviewer $coordinator 'stale_approval' 'story-49' 'b2' 're-review changed HEAD' 'current HEAD is b3'
Send-Message $coordinator $coordinator 'missing_destination' '#68' '' 'resolve worker identity' 'reviewer destination is unresolved'

Assert-True ($createdChats.Count -eq $initialChatCount) 'ordinary corrections must not create a new chat'
Assert-True ((Get-Messages 'correction' '#65').Count -eq 1) 'task A must have one correction'
Assert-True ((Get-Messages 'correction' '#66').Count -eq 1) 'task B must have one correction'
Assert-True ((Get-Messages 'correction' '#65')[0].destination -eq $reviewer) 'task A correction must return to the same reviewer'
Assert-True ((Get-Messages 'correction' '#66')[0].destination -eq $reviewer) 'task B correction must return to the same reviewer'
Assert-True ((Get-Messages 'story_approval' 'story-49')[0].destination -eq $coordinator) 'final approval must route to coordinator'
Assert-True (@($messages | Where-Object { $_.kind -in @('blocked','disagreement','stale_approval','missing_destination') -and $_.destination -ne $coordinator }).Count -eq 0) 'exceptional states must route to coordinator'
Assert-True (@($messages | Where-Object { $_.PSObject.Properties.Name -contains 'transcript' -or $_.PSObject.Properties.Name -contains 'receipt' }).Count -eq 0) 'messages must not relay full transcripts or structured receipts'
Assert-True ((Get-Messages 'stale_approval' 'story-49')[0].next -eq 're-review changed HEAD') 'stale approval must return to review'
Assert-True ($messages.Count -eq 13) 'fixture should cover the complete controlled route set'

Write-Output "Passed routing fixture: two tasks, correction rounds, final story review, stable pair, concise context, and coordinator escalation paths. No time or correction-count cutoff is used."
