[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('capture-context','validate-status-mappings','resolve-status-mapping','prepare-write','prepare-task-write','reconcile-write','reconcile-task-write','apply-reviewed-task-transition','reconcile-task-scope','finalize')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'receipt-contract.ps1')

$script:StateScript = Join-Path $PSScriptRoot 'workflow-state.ps1'
$script:ReviewScript = Join-Path $PSScriptRoot 'workflow-review.ps1'
$script:ProgressScript = Join-Path $PSScriptRoot 'workflow-progress.ps1'

function Invoke-JsonHelper {
    param([string] $ScriptPath, [string[]] $Arguments)
    $lines = & pwsh -NoProfile -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $raw = $lines -join [Environment]::NewLine
    try { $result = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 100 }
    catch { throw "Workflow helper returned invalid JSON: $raw" }
    if ($exitCode -ne 0 -or $result.ok -ne $true) {
        $message = if ($result -is [System.Collections.IDictionary] -and $result.Contains('error')) { [string]$result.error.message } else { $raw }
        throw $message
    }
    return $result
}

function Invoke-JsonHelperWithInput {
    param([string] $ScriptPath, [string[]] $Arguments, [System.Collections.IDictionary] $Value)
    $path = Join-Path ([IO.Path]::GetTempPath()) ('.taiga-finalize-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        return Invoke-JsonHelper $ScriptPath ($Arguments + @('-InputPath', $path))
    } finally {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}

function Get-RegistryInspection {
    param([string] $Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'stateRoot is required for persisted child evidence.' }
    $fullRoot = [IO.Path]::GetFullPath($Root)
    return Invoke-JsonHelper $script:StateScript @('-Operation', 'inspect', '-StateRoot', $fullRoot)
}

function Get-ProgressCheckpoint {
    param([string] $Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'progressRoot is required for persisted child evidence.' }
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $validation = Invoke-JsonHelperWithInput $script:ProgressScript @('-Operation', 'validate', '-StateRoot', $fullRoot) @{}
    $path = Join-Path $fullRoot 'task-progress.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'The validated progress checkpoint is missing.' }
    try { $checkpoint = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $path) -AsHashtable -Depth 100 }
    catch { throw "The validated progress checkpoint is not readable: $($_.Exception.Message)" }
    if ($checkpoint -isnot [System.Collections.IDictionary]) { throw 'The progress checkpoint must be an object.' }
    return [ordered]@{ validation = $validation.data; state = $checkpoint; path = $path }
}

function Get-ReviewReceiptFromAction {
    param([System.Collections.IDictionary] $Action, [string] $ReviewActionId, [object[]] $ExpectedCriteria)
    $reference = $null
    if ($Action.result -is [System.Collections.IDictionary] -and $Action.result.Contains('receiptReference')) { $reference = $Action.result.receiptReference }
    elseif ($Action.receipt -is [System.Collections.IDictionary] -and $Action.receipt.Contains('receiptReference')) { $reference = $Action.receipt.receiptReference }
    if ($reference -isnot [System.Collections.IDictionary] -or -not $reference.Contains('path') -or -not $reference.Contains('sha256')) { throw "Review action $ReviewActionId has no hash-verified receiptReference." }
    $path = [IO.Path]::GetFullPath([string]$reference.path)
    $hash = [string]$reference.sha256
    $request = [ordered]@{ receiptPath = $path; receiptSha256 = $hash; expectedCriteria = @($ExpectedCriteria) }
    $validated = Invoke-JsonHelperWithInput $script:ReviewScript @('-Operation', 'validate') $request
    return [ordered]@{ receipt = $validated.data.normalizedReceipt; reference = $validated.data.receiptReference; validation = $validated.data }
}

function Get-PersistedReviewAction {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Packet, [System.Collections.IDictionary] $Registry, [object[]] $ExpectedCriteria)
    $reviewActionId = if ($InputObject.Contains('reviewActionId')) { [string]$InputObject.reviewActionId } elseif ($InputObject.Contains('reviewActionReference') -and $InputObject.reviewActionReference -is [System.Collections.IDictionary]) { [string](Need $InputObject.reviewActionReference 'actionId') } else { throw 'reviewActionId is required for persisted child evidence.' }
    if ([string]::IsNullOrWhiteSpace($reviewActionId)) { throw 'reviewActionId cannot be blank.' }
    if (-not $Registry.actions.Contains($reviewActionId)) { throw "Review action was not found in the state registry: $reviewActionId." }
    $action = $Registry.actions[$reviewActionId]
    if ($action -isnot [System.Collections.IDictionary]) { throw "Review action is malformed in the state registry: $reviewActionId." }
    $ticketKey = "project:$($Packet.projectId):story:$($Packet.parentStoryId)"
    if ([string]$action.ticketKey -cne $ticketKey) { throw "Review action $reviewActionId is not bound to the selected story." }
    $target = if ($action.target -is [System.Collections.IDictionary]) { $action.target } else { @{} }
    foreach ($name in @('runId','packetHash','scopeHash')) {
        if ($target.Contains($name) -and [string]$target[$name] -cne [string]$Packet[$name]) { throw "Review action $reviewActionId is not bound to the selected run or packet." }
    }
    if ($target.Contains('ticketKey') -and [string]$target.ticketKey -cne $ticketKey) { throw "Review action $reviewActionId is bound to a different story." }
    $assignedReviewer = if ($target.Contains('reviewerId')) { [string]$target.reviewerId } elseif ($target.Contains('workerId')) { [string]$target.workerId } else { '' }
    if ([string]::IsNullOrWhiteSpace($assignedReviewer)) { throw "Review action $reviewActionId has no assigned reviewer." }
    $requestedReviewer = if ($InputObject.Contains('reviewerId')) { [string]$InputObject.reviewerId } elseif ($InputObject.Contains('assignedReviewerId')) { [string]$InputObject.assignedReviewerId } else { $assignedReviewer }
    if ([string]$requestedReviewer -cne $assignedReviewer) { throw "Review action $reviewActionId is assigned to a different reviewer." }
    $receiptSource = if ($action.result -is [System.Collections.IDictionary] -and $action.result.Contains('receiptReference')) { $action.result } elseif ($action.receipt -is [System.Collections.IDictionary] -and $action.receipt.Contains('receiptReference')) { $action.receipt } else { $null }
    if ($null -eq $receiptSource) { throw "Review action $reviewActionId has no recorded completed result." }
    if ([string]$action.status -eq 'uncertain' -or [bool]$action.reconcileRequired) { throw "Review action $reviewActionId is unresolved." }
    $validated = Get-ReviewReceiptFromAction $action $reviewActionId $ExpectedCriteria
    return [ordered]@{ actionId = $reviewActionId; action = $action; assignedReviewerId = $assignedReviewer; receipt = $validated.receipt; receiptReference = $validated.reference; validation = $validated.validation }
}

function Get-ReceiptTaskAcceptance {
    param([System.Collections.IDictionary] $Receipt, [long] $TaskId, [string[]] $ExpectedCriteria, [string] $CurrentSha, [string] $ReviewerId)
    $matches = @($Receipt.taskAcceptances | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('taskId') -and [long]$_.taskId -eq $TaskId })
    if ($matches.Count -ne 1) { throw "Review receipt must contain exactly one taskAcceptance for task $TaskId." }
    $acceptance = $matches[0]
    if ($acceptance.accepted -ne $true) { throw "Review receipt rejects selected task $TaskId." }
    if ([string]$acceptance.reviewedSha -cne $CurrentSha) { throw "Review receipt taskAcceptance for task $TaskId is stale." }
    $criteria = @($acceptance.criterionIds | ForEach-Object { [string]$_ })
    if (($criteria -join '|') -cne ($ExpectedCriteria -join '|')) { throw "Review receipt taskAcceptance criteria do not exactly match task $TaskId." }
    if ($acceptance.Contains('reviewerId') -and [string]$acceptance.reviewerId -cne $ReviewerId) { throw "Review receipt taskAcceptance for task $TaskId names a different reviewer." }
    return $acceptance
}

function Get-TaskWriteOutcome {
    param([System.Collections.IDictionary] $Action, [string] $ActionId)
    if ([string]$Action.status -in @('pending', 'uncertain') -or [bool]$Action.reconcileRequired) { throw "Task-write action $ActionId is pending or uncertain." }
    if ([string]$Action.status -ne 'observed') { throw "Task-write action $ActionId has no durable observed outcome." }
    $outcome = if ($Action.receipt -is [System.Collections.IDictionary]) { $Action.receipt } elseif ($Action.result -is [System.Collections.IDictionary]) { $Action.result } else { $null }
    if ($null -eq $outcome) { throw "Task-write action $ActionId has no recorded outcome." }
    $value = if ($outcome.Contains('outcome')) { [string]$outcome.outcome } elseif ($outcome.Contains('writeOutcome')) { [string]$outcome.writeOutcome } elseif ($outcome.Contains('state') -and [string]$outcome.state -eq 'confirmed') { 'reconciled' } else { '' }
    if ($value -notin @('applied','unchanged','reconciled')) { throw "Task-write action $ActionId has no durable applied, unchanged, or reconciled outcome." }
    return [ordered]@{ outcome = $value; record = $outcome }
}

function Get-TaskWriteEvidence {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Packet, [System.Collections.IDictionary] $Mapping, [System.Collections.IDictionary] $Registry, [System.Collections.IDictionary] $Checkpoint, [long] $TaskId, [string] $CurrentSha, [string] $ReviewActionId, [string] $ReviewerId)
    $references = @($InputObject.selectedTaskEvidence | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('taskId') -and [long]$_.taskId -eq $TaskId })
    if ($references.Count -ne 1) { throw "Selected task $TaskId must provide exactly one persisted evidence reference." }
    $reference = $references[0]
    if (-not $reference.Contains('eventId') -or [string]::IsNullOrWhiteSpace([string]$reference.eventId)) { throw "Selected task $TaskId must provide a persisted eventId reference." }
    $writeActionId = if ($reference.Contains('taskWriteActionId')) { [string]$reference.taskWriteActionId } elseif ($reference.Contains('writeActionId')) { [string]$reference.writeActionId } elseif ($reference.Contains('statusActionId')) { [string]$reference.statusActionId } else { '' }
    if ([string]::IsNullOrWhiteSpace($writeActionId)) { throw "Selected task $TaskId must provide a persisted task-write action reference." }
    $events = @($Checkpoint.events | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_.eventId -ceq [string]$reference.eventId -and [long]$_.taskId -eq $TaskId })
    if ($events.Count -ne 1) { throw "Persisted progress event was not found for selected task ${TaskId}: $([string]$reference.eventId)." }
    $event = $events[0]
    $latest = @($Checkpoint.events | Where-Object { $_ -is [System.Collections.IDictionary] -and [long]$_.taskId -eq $TaskId } | Sort-Object { [long]$_.sequence } | Select-Object -Last 1)
    if ($latest.Count -ne 1 -or [string]$latest[0].eventId -cne [string]$event.eventId) { throw "Selected task $TaskId does not reference its latest persisted progress event." }
    $expectedCriteria = @($Packet.criteriaByTask[[string]$TaskId] | ForEach-Object { [string]$_ })
    if ([string]$event.runId -cne [string]$Packet.runId -or [long]$event.projectId -ne [long]$Packet.projectId -or [long]$event.parentStoryId -ne [long]$Packet.parentStoryId -or [string]$event.packetHash -cne [string]$Packet.packetHash -or [string]$event.scopeHash -cne [string]$Packet.scopeHash -or [long]$event.taskId -ne $TaskId) { throw "Persisted progress event for task $TaskId is outside the selected packet." }
    if ([string]$event.currentSha -cne $CurrentSha) { throw "Persisted progress event for task $TaskId is stale." }
    if ([string]$event.eventType -notin @('ready_for_review','accepted')) { throw "Persisted progress event for task $TaskId is not a final review milestone." }
    if ((@($event.criterionIds | ForEach-Object { [string]$_ }) -join '|') -cne ($expectedCriteria -join '|')) { throw "Persisted progress event criteria do not match task $TaskId." }
    if ($reference.Contains('progressActionId') -and [string]$reference.progressActionId -cne [string]$event.actionId) { throw "Persisted progress event action does not match task $TaskId reference." }
    if (-not $Registry.actions.Contains($writeActionId)) { throw "Task-write action was not found in the state registry: $writeActionId." }
    $writeAction = $Registry.actions[$writeActionId]
    if ($writeAction -isnot [System.Collections.IDictionary]) { throw "Task-write action is malformed in the state registry: $writeActionId." }
    if ([string]$writeAction.ticketKey -cne "project:$($Packet.projectId):story:$($Packet.parentStoryId)") { throw "Task-write action $writeActionId is bound to a different story." }
    if ([string]$writeAction.kind -notin @('taiga_task_update','task_write')) { throw "Task-write action $writeActionId is not a Taiga task update." }
    $target = if ($writeAction.target -is [System.Collections.IDictionary]) { $writeAction.target } else { @{} }
    $journal = if ($target.Contains('journal')) { $target.journal } elseif ($target.Contains('taskWriteJournal')) { $target.taskWriteJournal } else { $null }
    if ($journal -isnot [System.Collections.IDictionary]) { throw "Task-write action $writeActionId has no persisted journal." }
    foreach ($name in @('journalId','packetBinding','progressBinding','target','targetStatusId','currentSha','logicalState','runMarker','writer','blindRetry')) { if (-not $journal.Contains($name)) { throw "Task-write journal for $TaskId is missing $name." } }
    if ([string]$journal.writer -cne 'coordinator' -or $journal.blindRetry -eq $true) { throw "Task-write journal for $TaskId is not coordinator-owned and retry-safe." }
    if ([long]$journal.taskId -ne $TaskId -or [long]$journal.projectId -ne [long]$Packet.projectId -or [long]$journal.parentStoryId -ne [long]$Packet.parentStoryId) { throw "Task-write journal for $TaskId has the wrong task or story." }
    $runMarkerPattern = '^' + [regex]::Escape([string]$Packet.runId) + '(?:/|$)'
    if ([string]$journal.currentSha -cne $CurrentSha -or [string]$journal.runMarker -notmatch $runMarkerPattern) { throw "Task-write journal for $TaskId is stale or belongs to another run." }
    if ([string]$journal.logicalState -notin @('accepted','done')) { throw "Task-write journal for $TaskId does not request Done." }
    $targetStatusId = if ($journal.target -is [System.Collections.IDictionary] -and $journal.target.Contains('statusId')) { [long]$journal.target.statusId } else { [long]$journal.targetStatusId }
    if ($targetStatusId -ne [long]$Mapping.accepted -or [long]$journal.targetStatusId -ne [long]$Mapping.accepted) { throw "Task-write journal for $TaskId does not target the mapped Done status." }
    if ($journal.target -isnot [System.Collections.IDictionary] -or [long]$journal.target.taskId -ne $TaskId -or [long]$journal.target.projectId -ne [long]$Packet.projectId -or [long]$journal.target.parentStoryId -ne [long]$Packet.parentStoryId) { throw "Task-write journal target is not bound to task $TaskId." }
    $journalPacket = Get-ValidatedPacketBinding @{ packetBinding = $journal.packetBinding } $Packet.projectId $Packet.parentStoryId
    if ([string]$journalPacket.bindingDigest -cne [string]$Packet.bindingDigest) { throw "Task-write journal for $TaskId is bound to a different packet." }
    if ($journal.progressBinding -isnot [System.Collections.IDictionary] -or [string]$journal.progressBinding.eventId -cne [string]$event.eventId -or [string]$journal.progressBinding.currentSha -cne $CurrentSha) { throw "Task-write journal for $TaskId is not bound to the persisted progress event." }
    $review = $journal.reviewerAcceptance
    if ($review -isnot [System.Collections.IDictionary] -or $review.accepted -ne $true -or [long]$review.taskId -ne $TaskId -or [string]$review.actionId -cne $ReviewActionId -or [string]$review.reviewedSha -cne $CurrentSha -or [string]$review.runId -cne [string]$Packet.runId -or [string]$review.packetHash -cne [string]$Packet.packetHash -or [string]$review.scopeHash -cne [string]$Packet.scopeHash -or [string]$review.reviewerId -cne $ReviewerId -or (@($review.criterionIds | ForEach-Object { [string]$_ }) -join '|') -cne ($expectedCriteria -join '|')) { throw "Task-write journal for $TaskId is not bound to the persisted reviewer acceptance." }
    $digest = Hash-Object @{ packetBinding = $journal.packetBinding; progressBinding = $journal.progressBinding; projectId = [long]$journal.projectId; parentStoryId = [long]$journal.parentStoryId; taskId = [long]$journal.taskId; fromStatusId = [long]$journal.fromStatusId; targetStatusId = [long]$journal.targetStatusId; version = [long]$journal.expectedVersion; currentSha = [string]$journal.currentSha; logicalState = [string]$journal.logicalState; review = $journal.reviewerAcceptance; runMarker = [string]$journal.runMarker }
    if ([string]$journal.journalId -cne $digest) { throw "Task-write journal for $TaskId has an invalid journalId." }
    $outcome = Get-TaskWriteOutcome $writeAction $writeActionId
    if ($outcome.record.Contains('journalId') -and [string]$outcome.record.journalId -cne [string]$journal.journalId) { throw "Task-write outcome $writeActionId is bound to a different journal." }
    if ($outcome.record.Contains('taskId') -and [long]$outcome.record.taskId -ne $TaskId) { throw "Task-write outcome $writeActionId is bound to a different task." }
    if ($outcome.record.Contains('statusId') -and [long]$outcome.record.statusId -ne [long]$Mapping.accepted) { throw "Task-write outcome $writeActionId is not for the mapped Done status." }
    return [ordered]@{ taskId = $TaskId; accepted = $true; reviewAccepted = $true; criteriaComplete = $true; statusOutcome = $outcome.outcome; reviewedSha = $CurrentSha; currentSha = $CurrentSha; runId = [string]$Packet.runId; actionId = $ReviewActionId; packetHash = [string]$Packet.packetHash; scopeHash = [string]$Packet.scopeHash; sequence = [long]$event.sequence; eventId = [string]$event.eventId; eventType = 'accepted'; criterionIds = @($expectedCriteria); reviewActionId = $ReviewActionId; taskWriteActionId = $writeActionId; receiptReference = $null }
}

function Read-Object { if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }; try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" } }
function Need { param([hashtable]$Object,[string]$Name); if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }; return $Object[$Name] }
function Convert-ToCanonicalValue {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $canonical = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $canonical[$key] = Convert-ToCanonicalValue $Value[$key] }
        return $canonical
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $converted = Convert-ToCanonicalValue $item
            [void]$items.Add($converted)
        }
        return ,$items.ToArray()
    }
    return $Value
}
function Hash-Object { param([object]$Value); $bytes = [Text.Encoding]::UTF8.GetBytes((Convert-ToCanonicalValue $Value | ConvertTo-Json -Depth 100 -Compress)); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }
function Hash-Text { param([string]$Value); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }
function Get-ProgressEventIdentityKey {
    param([System.Collections.IDictionary] $Record)
    $evidenceJson = ConvertTo-Json -InputObject $Record.evidence -Depth 100 -Compress
    return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}' -f $Record.runId,$Record.actionId,$Record.ticketKey,$Record.projectId,$Record.parentStoryId,$Record.taskId,$Record.sequence,$Record.currentSha,$Record.eventType,(@($Record.criterionIds) -join ','),$evidenceJson,$Record.blockedReason,$Record.packetHash,$Record.scopeHash,$Record.bindingDigest)
}
function Get-InterimProgressEventIdentityKey {
    param([System.Collections.IDictionary] $Record)
    $evidenceJson = ConvertTo-Json -InputObject $Record.evidence -Depth 100 -Compress
    return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}' -f $Record.runId,$Record.actionId,$Record.ticketKey,$Record.projectId,$Record.parentStoryId,$Record.taskId,$Record.sequence,$Record.currentSha,$Record.eventType,(@($Record.criterionIds) -join ','),$evidenceJson,$Record.blockedReason,$Record.packetHash,$Record.scopeHash,$Record.bindingDigest,$Record.continuationOfActionId)
}
function Get-ProgressShaProofDigest {
    param([System.Collections.IDictionary] $Record)
    $proofPayload = [ordered]@{ runId = [string]$Record.runId; actionId = [string]$Record.actionId; ticketKey = [string]$Record.ticketKey; projectId = [long]$Record.projectId; parentStoryId = [long]$Record.parentStoryId; taskId = [long]$Record.taskId; sequence = [long]$Record.sequence; currentSha = ([string]$Record.currentSha).ToLowerInvariant(); eventType = [string]$Record.eventType; criterionIds = @($Record.criterionIds); evidence = $Record.evidence; blockedReason = if ($Record.Contains('blockedReason')) { [string]$Record.blockedReason } else { $null }; packetHash = [string]$Record.packetHash; scopeHash = [string]$Record.scopeHash; bindingDigest = [string]$Record.bindingDigest }
    return Hash-Object $proofPayload
}
function Read-OptionalInteger {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context, [long] $Minimum = 0)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name]) { return [ordered]@{ present = $false; value = $null } }
    $number = 0L
    if (-not [long]::TryParse([string]$Object[$Name], [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt $Minimum) { throw "$Context pagination is invalid: $Name must be an integer at least $Minimum." }
    return [ordered]@{ present = $true; value = $number }
}
function Get-PageAlias {
    param([System.Collections.IDictionary] $Page, [string[]] $Names, [string] $Context)
    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $Names) { if ($Page.Contains($name)) { [void]$values.Add([ordered]@{ name = $name; value = $Page[$name] }) } }
    if ($values.Count -gt 1) {
        $expected = if ($null -eq $values[0].value) { '<null>' } else { [string]$values[0].value }
        foreach ($entry in $values | Select-Object -Skip 1) {
            $actual = if ($null -eq $entry.value) { '<null>' } else { [string]$entry.value }
            if ($actual -ne $expected) { throw "$Context pagination is contradictory: aliases $($values[0].name) and $($entry.name) disagree." }
        }
    }
    if ($values.Count -eq 0) { return [ordered]@{ present = $false; value = $null } }
    return [ordered]@{ present = $true; value = $values[0].value }
}
function Complete-Pages {
    param([object[]]$Pages,[string]$Name)
    if ($Pages.Count -eq 0) { throw "$Name has no captured pages." }
    $orderedPages = [System.Collections.Generic.List[object]]::new()
    $seenPages = [System.Collections.Generic.HashSet[long]]::new()
    $anyTotals = $false
    foreach ($page in $Pages) {
        if ($page -isnot [System.Collections.IDictionary]) { throw "$Name pagination is incomplete: page metadata must be an object." }
        $pageNumberField = Get-PageAlias $page @('page', 'currentPage', 'x-pagination-current') $Name
        if (-not $pageNumberField.present) { throw "$Name pagination is incomplete: page number missing." }
        $number = 0L
        if (-not [long]::TryParse([string]$pageNumberField.value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 1) { throw "$Name pagination is incomplete: page number must be positive." }
        if (-not $seenPages.Add($number)) { throw "$Name pagination is contradictory: duplicate page $number." }
        $hasMoreField = Get-PageAlias $page @('hasMore', 'has_more') $Name
        $hasMoreKnown = $hasMoreField.present -and $null -ne $hasMoreField.value
        if ($hasMoreKnown -and $hasMoreField.value -isnot [bool]) { throw "$Name pagination is invalid: hasMore must be boolean or null." }
        $nextField = Get-PageAlias $page @('nextPage', 'next_page', 'x-pagination-next') $Name
        $nextKnowledgeField = Get-PageAlias $page @('nextPageKnown', 'next_page_known') $Name
        if ($nextKnowledgeField.present -and $nextKnowledgeField.value -isnot [bool]) { throw "$Name pagination is invalid: nextPageKnown must be boolean." }
        if ($nextKnowledgeField.value -eq $true -and -not $nextField.present) { throw "$Name pagination is invalid: nextPageKnown requires a nextPage field." }
        if ($nextKnowledgeField.value -eq $false -and $nextField.present -and $null -ne $nextField.value) { throw "$Name pagination is contradictory: nextPage is present while nextPageKnown is false." }
        $nextPage = $null
        if ($nextField.present -and $null -ne $nextField.value) {
            $nextPage = 0L
            if (-not [long]::TryParse([string]$nextField.value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$nextPage) -or $nextPage -lt 1) { throw "$Name pagination is invalid: nextPage must be a positive page number or null." }
        }
        $nextKnown = ($null -ne $nextPage) -or ($nextKnowledgeField.present -and $nextKnowledgeField.value -eq $true)
        $totalField = Get-PageAlias $page @('totalCount', 'total', 'x-pagination-count') $Name
        $pageSizeField = Get-PageAlias $page @('pageSize', 'page_size', 'perPage', 'x-paginated-by') $Name
        $itemCountField = Get-PageAlias $page @('itemCount', 'item_count') $Name
        if (-not $itemCountField.present -and $page.Contains('items') -and $page.items -isnot [string] -and $page.items -is [System.Collections.IEnumerable]) { $itemCountField = [ordered]@{ present = $true; value = @($page.items).Count } }
        $normalizedCounts = [ordered]@{ totalCount = if ($totalField.present) { $totalField.value } else { $null }; pageSize = if ($pageSizeField.present) { $pageSizeField.value } else { $null }; itemCount = if ($itemCountField.present) { $itemCountField.value } else { $null } }
        $total = Read-OptionalInteger $normalizedCounts 'totalCount' $Name
        $pageSize = Read-OptionalInteger $normalizedCounts 'pageSize' $Name 1
        $itemCount = Read-OptionalInteger $normalizedCounts 'itemCount' $Name
        if ($total.present) { $anyTotals = $true }
        $itemIds = @()
        if ($page.Contains('itemIds')) {
            if ($page.itemIds -is [string] -or $page.itemIds -isnot [System.Collections.IEnumerable]) { throw "$Name pagination is invalid: itemIds must be an array." }
            $itemIds = @($page.itemIds | ForEach-Object { [string]$_ })
            if (@($itemIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw "$Name pagination is invalid: itemIds cannot contain blank values." }
        } elseif ($page.Contains('items') -and $page.items -isnot [string] -and $page.items -is [System.Collections.IEnumerable]) {
            $itemsWithIds = @($page.items | Where-Object { $_ -is [System.Collections.IDictionary] -and ($_.Contains('id') -or $_.Contains('user_story_id') -or $_.Contains('task_id')) })
            if ($itemsWithIds.Count -eq @($page.items).Count) {
                $itemIds = @($itemsWithIds | ForEach-Object { if ($_.Contains('id')) { [string]$_.id } elseif ($_.Contains('user_story_id')) { [string]$_.user_story_id } else { [string]$_.task_id } })
            }
        }
        [void]$orderedPages.Add([ordered]@{ number = $number; page = $page; hasMoreKnown = $hasMoreKnown; hasMore = if ($hasMoreKnown) { [bool]$hasMoreField.value } else { $null }; nextKnown = $nextKnown; nextPage = $nextPage; total = $total; pageSize = $pageSize; itemCount = $itemCount; itemIds = $itemIds })
    }
    $orderedPages.Sort([System.Collections.Generic.Comparer[object]]::Create([System.Comparison[object]]{ param($left, $right) [long]$left.number - [long]$right.number }))
    for ($index = 0; $index -lt $orderedPages.Count; $index++) { if ($orderedPages[$index].number -ne ($index + 1)) { throw "$Name pagination is incomplete: pages must be contiguous from page 1." } }

    if ($anyTotals) {
        foreach ($entry in $orderedPages) {
            if (-not $entry.total.present -or -not $entry.itemCount.present) { throw "$Name pagination is incomplete: totalCount and itemCount must be present on every page when total metadata is used." }
        }
        $totalCount = [long]$orderedPages[0].total.value
        $hasPageSize = $orderedPages[0].pageSize.present
        $pageSize = if ($hasPageSize) { [long]$orderedPages[0].pageSize.value } else { $null }
        foreach ($entry in $orderedPages) {
            if ($entry.total.value -ne $totalCount) { throw "$Name pagination is contradictory: totalCount changed between pages." }
            if ($entry.pageSize.present -ne $hasPageSize) { throw "$Name pagination is incomplete: pageSize must be present on every page or none." }
            if ($hasPageSize -and $entry.pageSize.value -ne $pageSize) { throw "$Name pagination is contradictory: pageSize changed between pages." }
        }
        $seenItemIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $cumulativeItemCount = 0L
        foreach ($entry in $orderedPages) {
            $cumulativeItemCount += [long]$entry.itemCount.value
            if ($hasPageSize -and $entry.itemCount.value -gt $pageSize) { throw "$Name pagination is contradictory: itemCount exceeds pageSize on page $($entry.number)." }
            if ($cumulativeItemCount -gt $totalCount) { throw "$Name pagination is contradictory: captured itemCount exceeds totalCount." }
            $expectedMore = $cumulativeItemCount -lt $totalCount
            if ($entry.hasMoreKnown -and $entry.hasMore -ne $expectedMore) { throw "$Name pagination is contradictory: hasMore disagrees with authoritative totals on page $($entry.number)." }
            if ($entry.nextKnown -and (($expectedMore -and $entry.nextPage -ne ($entry.number + 1)) -or (-not $expectedMore -and $null -ne $entry.nextPage))) { throw "$Name pagination is contradictory: nextPage disagrees with authoritative totals on page $($entry.number)." }
            if (-not $expectedMore -and $entry.number -ne $orderedPages.Count) { throw "$Name pagination contains pages after the authoritative total was reached." }
            if ($entry.itemIds.Count -gt 0) {
                if ($entry.itemCount.present -and $entry.itemIds.Count -ne $entry.itemCount.value) { throw "$Name pagination is contradictory: itemIds and itemCount differ on page $($entry.number)." }
                foreach ($itemId in $entry.itemIds) { if (-not $seenItemIds.Add($itemId)) { throw "$Name pagination is contradictory: duplicate item ID across pages: $itemId." } }
            }
        }
        if ($cumulativeItemCount -ne $totalCount) { throw "$Name pagination is incomplete: captured $cumulativeItemCount of $totalCount authoritative items." }
        return [ordered]@{ complete = $true; basis = 'authoritative_total_count'; pageCount = $orderedPages.Count; totalCount = $totalCount; pageSize = $pageSize }
    }

    $terminalSeen = $false
    $basisSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $orderedPages) {
        if ($terminalSeen) { throw "$Name pagination contains pages after its authoritative terminal page." }
        $moreKnown = $entry.hasMoreKnown -or $entry.nextKnown
        if (-not $moreKnown) { throw "$Name pagination is incomplete: hasMore, nextPage, and trustworthy totals are unavailable." }
        $moreFromNext = $entry.nextKnown -and $null -ne $entry.nextPage
        if ($entry.hasMoreKnown -and $entry.nextKnown -and $entry.hasMore -ne $moreFromNext) { throw "$Name pagination is contradictory: hasMore and nextPage disagree on page $($entry.number)." }
        $hasMore = if ($entry.hasMoreKnown) { $entry.hasMore } else { $moreFromNext }
        if ($entry.hasMoreKnown) { [void]$basisSet.Add('has_more') }
        if ($entry.nextKnown) { [void]$basisSet.Add('next_page') }
        if ($hasMore) {
            if (-not $entry.nextKnown -or $entry.nextPage -ne ($entry.number + 1)) { throw "$Name pagination is incomplete: nextPage must identify page $($entry.number + 1)." }
            if ($entry.number -eq $orderedPages.Count) { throw "$Name pagination is incomplete: page $($entry.number + 1) was not fetched." }
        } else {
            $terminalSeen = $true
            if ($entry.nextKnown -and $null -ne $entry.nextPage) { throw "$Name pagination is contradictory: a terminal page has a nextPage." }
            if ($entry.number -ne $orderedPages.Count) { throw "$Name pagination contains pages after its authoritative terminal page." }
        }
    }
    return [ordered]@{ complete = $true; basis = if ($basisSet.Count -gt 1) { 'combined_page_metadata' } elseif ($basisSet.Contains('has_more')) { 'has_more' } else { 'next_page' }; pageCount = $orderedPages.Count; totalCount = $null; pageSize = $null }
}

function Get-OptionalTaskValue {
    param([System.Collections.IDictionary] $Item, [string[]] $Names)
    foreach ($name in $Names) { if ($Item.Contains($name)) { return [ordered]@{ present = $true; value = $Item[$name]; name = $name } } }
    return [ordered]@{ present = $false; value = $null; name = $null }
}

function Get-TaskInteger {
    param([System.Collections.IDictionary] $Item, [string[]] $Names, [string] $Field, [bool] $Required = $false)
    $found = Get-OptionalTaskValue $Item $Names
    if (-not $found.present) { if ($Required) { throw "Child task is missing $Field." }; return $null }
    $raw = $found.value
    if ($raw -is [System.Collections.IDictionary]) {
        $nested = $null
        foreach ($nestedName in @('id','pk','value')) { if ($raw.Contains($nestedName)) { $nested = $raw[$nestedName]; break } }
        if ($null -eq $nested) { throw "Child task $Field must contain a numeric nested ID." }
        $raw = $nested
    }
    $value = 0L
    if (-not [long]::TryParse([string]$raw, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -lt 1) { throw "Child task $Field must be a positive integer." }
    return $value
}

function Get-TaskPacketBinding {
    param([System.Collections.IDictionary] $InputObject, [long[]] $SelectedTaskIds, [object[]] $Bindings)
    if ($SelectedTaskIds.Count -eq 0) { return $null }
    if (-not $InputObject.Contains('packetBinding') -or $InputObject.packetBinding -isnot [System.Collections.IDictionary]) { throw 'Selected child tasks require an immutable packetBinding.' }
    $packet = $InputObject.packetBinding
    foreach ($name in @('runId','actionId','packetHash','scopeHash','criteriaByTask')) { if (-not $packet.Contains($name)) { throw "packetBinding.$name is required." } }
    foreach ($name in @('runId','actionId','packetHash','scopeHash')) { if ([string]::IsNullOrWhiteSpace([string]$packet[$name])) { throw "packetBinding.$name cannot be blank." } }
    foreach ($name in @('packetHash','scopeHash')) { if ([string]$packet[$name] -notmatch '^[0-9a-fA-F]{64}$') { throw "packetBinding.$name must be a SHA-256 digest." } }
    $trustedRevisions = $null
    if ($packet.Contains('trustedRevisions')) {
        if ($packet.trustedRevisions -is [string] -or $packet.trustedRevisions -isnot [System.Collections.IEnumerable]) { throw 'packetBinding.trustedRevisions must be an array.' }
        $seenRevisions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $trustedRevisions = [System.Collections.Generic.List[string]]::new()
        foreach ($value in $packet.trustedRevisions) { $revision = [string]$value; if ($revision -notmatch '^[0-9a-fA-F]{7,64}$' -or -not $seenRevisions.Add($revision.ToLowerInvariant())) { throw 'packetBinding.trustedRevisions must contain unique Git revisions.' }; [void]$trustedRevisions.Add($revision.ToLowerInvariant()) }
        if ($trustedRevisions.Count -eq 0) { throw 'packetBinding.trustedRevisions cannot be empty when supplied.' }
    }
    if ($packet.criteriaByTask -isnot [System.Collections.IDictionary]) { throw 'packetBinding.criteriaByTask must be an object.' }
    $normalized = [ordered]@{}
    foreach ($taskId in $SelectedTaskIds) {
        $key = [string]$taskId
        if (-not $packet.criteriaByTask.Contains($key)) { throw "packetBinding.criteriaByTask is missing selected task $taskId." }
        $criteria = @($packet.criteriaByTask[$key])
        if ($criteria.Count -eq 0 -or $criteria -contains $null -or @($criteria | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { throw "packetBinding criteria for task $taskId must be nonempty." }
        $normalized[$key] = @($criteria | ForEach-Object { [string]$_ } | Select-Object -Unique)
        $binding = @($Bindings | Where-Object { [long]$_.taskId -eq $taskId })[0]
        $captured = @($binding.criteria | ForEach-Object { [string]$_ } | Sort-Object)
        $bound = @($normalized[$key] | Sort-Object)
        if (($captured -join '|') -cne ($bound -join '|')) { throw "packetBinding criteria do not match captured criteria for task $taskId." }
    }
    $taskBindings = [ordered]@{}
    foreach ($taskId in $SelectedTaskIds) {
        $binding = @($Bindings | Where-Object { [long]$_.taskId -eq $taskId })[0]
        $taskBindings[[string]$taskId] = [ordered]@{
            taskId = [long]$binding.taskId
            alias = [string]$binding.alias
            projectId = [long]$binding.projectId
            parentStoryId = [long]$binding.parentStoryId
            baselineStatusId = [long]$binding.baselineStatusId
            version = [long]$binding.version
            criteria = @($normalized[[string]$taskId])
        }
    }
    $result = [ordered]@{
        runId = [string]$packet.runId
        actionId = [string]$packet.actionId
        packetHash = ([string]$packet.packetHash).ToLowerInvariant()
        scopeHash = ([string]$packet.scopeHash).ToLowerInvariant()
        projectId = [long]$ProjectId
        parentStoryId = [long]$storyId
        selectedTaskIds = @($SelectedTaskIds)
        criteriaByTask = $normalized
        tasksById = $taskBindings
    }
    if ($null -ne $trustedRevisions) { $result.trustedRevisions = @($trustedRevisions) }
    $result.bindingDigest = Hash-Object $result
    return $result
}

function Get-ValidatedPacketBinding {
    param([System.Collections.IDictionary] $InputObject, [long] $ExpectedProjectId = 0, [long] $ExpectedParentStoryId = 0)
    if (-not $InputObject.Contains('packetBinding') -or $InputObject.packetBinding -isnot [System.Collections.IDictionary]) { throw 'A validated packetBinding is required.' }
    $packet = $InputObject.packetBinding
    foreach ($name in @('runId','actionId','packetHash','scopeHash','projectId','parentStoryId','selectedTaskIds','criteriaByTask','tasksById','bindingDigest')) { if (-not $packet.Contains($name)) { throw "packetBinding.$name is required." } }
    foreach ($name in @('runId','actionId')) { if ([string]::IsNullOrWhiteSpace([string]$packet[$name])) { throw "packetBinding.$name cannot be blank." } }
    foreach ($name in @('packetHash','scopeHash','bindingDigest')) { if ([string]$packet[$name] -notmatch '^[0-9a-fA-F]{64}$') { throw "packetBinding.$name must be a SHA-256 digest." } }
    $trustedRevisions = $null
    if ($packet.Contains('trustedRevisions')) {
        if ($packet.trustedRevisions -is [string] -or $packet.trustedRevisions -isnot [System.Collections.IEnumerable]) { throw 'packetBinding.trustedRevisions must be an array.' }
        $seenRevisions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $trustedRevisions = [System.Collections.Generic.List[string]]::new()
        foreach ($value in $packet.trustedRevisions) { $revision = [string]$value; if ($revision -notmatch '^[0-9a-fA-F]{7,64}$' -or -not $seenRevisions.Add($revision.ToLowerInvariant())) { throw 'packetBinding.trustedRevisions must contain unique Git revisions.' }; [void]$trustedRevisions.Add($revision.ToLowerInvariant()) }
        if ($trustedRevisions.Count -eq 0) { throw 'packetBinding.trustedRevisions cannot be empty when supplied.' }
    }
    $projectId = Get-TaskInteger $packet @('projectId') 'packetBinding.projectId' $true
    $parentStoryId = Get-TaskInteger $packet @('parentStoryId') 'packetBinding.parentStoryId' $true
    if ($ExpectedProjectId -gt 0 -and $projectId -ne $ExpectedProjectId) { throw "packetBinding is not bound to project $ExpectedProjectId." }
    if ($ExpectedParentStoryId -gt 0 -and $parentStoryId -ne $ExpectedParentStoryId) { throw "packetBinding is not bound to story $ExpectedParentStoryId." }
    if ($packet.selectedTaskIds -is [string] -or $packet.selectedTaskIds -isnot [System.Collections.IEnumerable]) { throw 'packetBinding.selectedTaskIds must be an array.' }
    $selected = @($packet.selectedTaskIds | ForEach-Object { $value = 0L; if (-not [long]::TryParse([string]$_,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or $value -lt 1) { throw 'packetBinding.selectedTaskIds must contain positive integers.' }; $value })
    if (@($selected | Select-Object -Unique).Count -ne $selected.Count) { throw 'packetBinding.selectedTaskIds must not contain duplicates.' }
    if ($packet.criteriaByTask -isnot [System.Collections.IDictionary] -or $packet.tasksById -isnot [System.Collections.IDictionary]) { throw 'packetBinding criteria and task bindings must be objects.' }
    $criteriaByTask = [ordered]@{}
    $taskBindings = [ordered]@{}
    foreach ($taskId in $selected) {
        $key = [string]$taskId
        if (-not $packet.criteriaByTask.Contains($key) -or -not $packet.tasksById.Contains($key)) { throw "packetBinding is missing selected task $taskId." }
        $criteria = @($packet.criteriaByTask[$key] | ForEach-Object { [string]$_ })
        if ($criteria.Count -eq 0 -or @($criteria | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or @($criteria | Select-Object -Unique).Count -ne $criteria.Count) { throw "packetBinding criteria for task $taskId must be unique and nonempty." }
        $taskBinding = $packet.tasksById[$key]
        if ($taskBinding -isnot [System.Collections.IDictionary]) { throw "packetBinding task binding for $taskId must be an object." }
        foreach ($name in @('taskId','alias','projectId','parentStoryId','baselineStatusId','version','criteria')) { if (-not $taskBinding.Contains($name)) { throw "packetBinding.tasksById.$taskId.$name is required." } }
        if ([long]$taskBinding.taskId -ne $taskId -or [long]$taskBinding.projectId -ne $projectId -or [long]$taskBinding.parentStoryId -ne $parentStoryId) { throw "packetBinding task identity does not match selected task $taskId." }
        if ([string]::IsNullOrWhiteSpace([string]$taskBinding.alias)) { throw "packetBinding task alias for $taskId cannot be blank." }
        $baselineStatusId = 0L; $version = 0L
        if (-not [long]::TryParse([string]$taskBinding.baselineStatusId,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$baselineStatusId) -or $baselineStatusId -lt 1) { throw "packetBinding baseline status for task $taskId must be positive." }
        if (-not [long]::TryParse([string]$taskBinding.version,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$version) -or $version -lt 0) { throw "packetBinding version for task $taskId must be nonnegative." }
        $boundCriteria = @($taskBinding.criteria | ForEach-Object { [string]$_ })
        if (($boundCriteria -join '|') -cne ($criteria -join '|')) { throw "packetBinding criteria do not match task binding $taskId." }
        $criteriaByTask[$key] = @($criteria)
        $taskBindings[$key] = [ordered]@{ taskId = $taskId; alias = [string]$taskBinding.alias; projectId = $projectId; parentStoryId = $parentStoryId; baselineStatusId = $baselineStatusId; version = $version; criteria = @($criteria) }
    }
    $normalized = [ordered]@{ runId = [string]$packet.runId; actionId = [string]$packet.actionId; packetHash = ([string]$packet.packetHash).ToLowerInvariant(); scopeHash = ([string]$packet.scopeHash).ToLowerInvariant(); projectId = $projectId; parentStoryId = $parentStoryId; selectedTaskIds = @($selected); criteriaByTask = $criteriaByTask; tasksById = $taskBindings }
    if ($null -ne $trustedRevisions) { $normalized.trustedRevisions = @($trustedRevisions) }
    $expectedDigest = Hash-Object $normalized
    if ([string]$packet.bindingDigest -cne $expectedDigest) { throw 'packetBinding.bindingDigest does not match its immutable contents.' }
    $normalized.bindingDigest = $expectedDigest
    return $normalized
}

function Assert-SelectedTaskCriteria {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Packet, [long] $TaskId)
    if (-not $InputObject.Contains('requiredCriterionIds') -or $InputObject.requiredCriterionIds -is [string] -or $InputObject.requiredCriterionIds -isnot [System.Collections.IEnumerable]) { throw "Task $TaskId requires requiredCriterionIds from the validated packet." }
    $required = @($InputObject.requiredCriterionIds | ForEach-Object { [string]$_ })
    $expected = @($Packet.criteriaByTask[[string]$TaskId] | ForEach-Object { [string]$_ })
    if ($required.Count -eq 0 -or @($required | Select-Object -Unique).Count -ne $required.Count -or ($required -join '|') -cne ($expected -join '|')) { throw "Task $TaskId requiredCriterionIds do not exactly match the validated packet." }
    return $required
}

function Get-ValidatedProgressBinding {
    param([System.Collections.IDictionary] $InputObject, [System.Collections.IDictionary] $Packet, [long] $TaskId, [string] $CurrentSha, [string[]] $RequiredCriteria, [string] $RequestedLogicalState)
    if (-not $InputObject.Contains('progressBinding') -or $InputObject.progressBinding -isnot [System.Collections.IDictionary]) { throw "Task $TaskId requires a validated progressBinding." }
    $progress = $InputObject.progressBinding
    foreach ($name in @('runId','actionId','packetHash','scopeHash','bindingDigest','taskId','sequence','eventId','eventType','currentSha','criterionIds','ticketKey','projectId','parentStoryId','evidence')) { if (-not $progress.Contains($name)) { throw "progressBinding.$name is required for task $TaskId." } }
    if ([string]$progress.runId -cne [string]$Packet.runId -or [string]$progress.packetHash -cne [string]$Packet.packetHash -or [string]$progress.scopeHash -cne [string]$Packet.scopeHash -or [string]$progress.bindingDigest -cne [string]$Packet.bindingDigest -or [long]$progress.taskId -ne $TaskId) { throw "progressBinding is not bound to task $TaskId and its packet." }
    if ([string]$progress.currentSha -cne $CurrentSha) { throw "progressBinding revision does not match currentSha for task $TaskId." }
    $projectId = 0L; $parentStoryId = 0L
    if (-not [long]::TryParse([string]$progress.projectId,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$projectId) -or $projectId -ne [long]$Packet.projectId -or -not [long]::TryParse([string]$progress.parentStoryId,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$parentStoryId) -or $parentStoryId -ne [long]$Packet.parentStoryId) { throw "progressBinding identity does not match the packet for task $TaskId." }
    $ticketKey = [string]$progress.ticketKey
    if ($ticketKey -notmatch '^project:\d+:story:\d+$' -or [long]($ticketKey -replace '^project:(\d+):story:(\d+)$','$1') -ne $projectId -or [long]($ticketKey -replace '^project:(\d+):story:(\d+)$','$2') -ne $parentStoryId) { throw "progressBinding ticket identity is invalid for task $TaskId." }
    $sequence = 0L; if (-not [long]::TryParse([string]$progress.sequence,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$sequence) -or $sequence -lt 1) { throw "progressBinding.sequence must be positive for task $TaskId." }
    if ([string]::IsNullOrWhiteSpace([string]$progress.actionId) -or [string]::IsNullOrWhiteSpace([string]$progress.eventId)) { throw "progressBinding action and event identities cannot be blank for task $TaskId." }
    if ([string]$progress.currentSha -notmatch '^[0-9a-fA-F]{7,64}$' -or [string]$progress.bindingDigest -notmatch '^[0-9a-fA-F]{64}$') { throw "progressBinding provenance digests are invalid for task $TaskId." }
    if ([string]$progress.eventType -notin @('started','blocked','ready_for_review','reopen')) { throw "progressBinding.eventType is not a worker milestone for task $TaskId." }
    $criteria = @($progress.criterionIds | ForEach-Object { [string]$_ })
    if ($criteria.Count -eq 0 -or @($criteria | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or @($criteria | Select-Object -Unique).Count -ne $criteria.Count -or ($criteria -join '|') -cne ($RequiredCriteria -join '|')) { throw "progressBinding criteria do not match required criteria for task $TaskId." }
    if ([string]$progress.actionId -ceq [string]$Packet.actionId -and $progress.Contains('continuationOfActionId') -and -not [string]::IsNullOrWhiteSpace([string]$progress.continuationOfActionId)) {
        throw "progressBinding packet action cannot declare a continuation for task $TaskId."
    }
    if ($Packet.Contains('trustedRevisions') -and @($Packet.trustedRevisions | ForEach-Object { [string]$_ }) -notcontains ([string]$progress.currentSha).ToLowerInvariant()) { throw "progressBinding revision is outside the trusted assignment for task $TaskId." }
    if ([string]$progress.evidence -match '(?i)(password|token|secret|raw.?log)') { throw "progressBinding evidence is unsafe for task $TaskId." }
    $event = [ordered]@{ runId = [string]$progress.runId; actionId = [string]$progress.actionId; ticketKey = $ticketKey; projectId = $projectId; parentStoryId = $parentStoryId; taskId = $TaskId; packetHash = [string]$progress.packetHash; scopeHash = [string]$progress.scopeHash; bindingDigest = [string]$progress.bindingDigest; sequence = $sequence; currentSha = ([string]$progress.currentSha).ToLowerInvariant(); eventType = [string]$progress.eventType; criterionIds = @($criteria); evidence = $progress.evidence; blockedReason = if ($progress.Contains('blockedReason')) { [string]$progress.blockedReason } else { $null }; shaDigest = if ($progress.Contains('shaDigest')) { [string]$progress.shaDigest } else { $null }; continuationOfActionId = if ($progress.Contains('continuationOfActionId')) { [string]$progress.continuationOfActionId } else { $null }; occurredAtUtc = if ($progress.Contains('occurredAtUtc')) { [string]$progress.occurredAtUtc } else { $null }; eventId = [string]$progress.eventId }
    $stableEventId = Hash-Text (Get-ProgressEventIdentityKey $event); $interimEventId = Hash-Text (Get-InterimProgressEventIdentityKey $event)
    if ([string]$progress.eventId -cne $stableEventId -and [string]$progress.eventId -cne $interimEventId) { throw "progressBinding.eventId is not the deterministic identity of the captured event for task $TaskId." }
    if (-not [string]::IsNullOrWhiteSpace([string]$event.shaDigest) -and [string]$event.shaDigest -cne (Get-ProgressShaProofDigest $event)) { throw "progressBinding.shaDigest does not match the captured event for task $TaskId." }
    $milestoneState = switch ($event.eventType) { 'started' { 'in_progress' }; 'blocked' { 'blocked' }; 'ready_for_review' { 'awaiting_review' }; 'reopen' { 'in_progress' } }
    $allowedRequestedStates = if ($RequestedLogicalState -in @('accepted','done')) { @('awaiting_review') } else { @($RequestedLogicalState) }
    if ($allowedRequestedStates -notcontains $milestoneState) { throw "Task $TaskId requested logical state '$RequestedLogicalState' does not match progress milestone '$($event.eventType)' ($milestoneState)." }
    return $event
}

function Get-TaskItems {
    param([object[]] $Pages)
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($page in $Pages) {
        if ($page -isnot [System.Collections.IDictionary]) { continue }
        $candidate = if ($page.Contains('items')) { $page['items'] } elseif ($page.Contains('tasks')) { $page['tasks'] } else { @() }
        if ($null -eq $candidate) { $candidate = @() }
        if ($candidate -is [string] -or $candidate -isnot [System.Collections.IEnumerable]) { throw "tasks page items must be an array when present (type: $($candidate.GetType().FullName))." }
        foreach ($item in $candidate) { if ($item -isnot [System.Collections.IDictionary]) { throw 'Each child task item must be an object.' }; [void]$items.Add($item) }
    }
    return $items.ToArray()
}

function Get-TaskBindings {
    param([hashtable] $InputObject, [long] $ProjectId)
    $items = @(Get-TaskItems @($InputObject.taskPages)); $bindings = [System.Collections.Generic.List[object]]::new(); $seenIds = [System.Collections.Generic.HashSet[long]]::new(); $seenAliases = [System.Collections.Generic.HashSet[string]]::new()
    $storyId = $null
    foreach ($name in @('storyId','parentStoryId','id')) { if ($InputObject.Contains($name)) { $storyId = Get-TaskInteger $InputObject @($name) $name; break } }
    foreach ($item in $items) {
        $taskId = Get-TaskInteger $item @('id','taskId','task_id') 'id' $true
        if (-not $seenIds.Add($taskId)) { throw "Child task ID is duplicated across captured pages: $taskId." }
        $itemProject = Get-TaskInteger $item @('projectId','project_id','project') 'projectId' $true
        if ($itemProject -ne $ProjectId) { throw "Child task $taskId belongs to project $itemProject, not $ProjectId." }
        $parent = Get-TaskInteger $item @('parentStoryId','parent_story_id','userStoryId','user_story_id','userStory','user_story') 'parentStoryId' $true
        if ($null -ne $storyId -and $parent -ne $storyId) { throw "Child task $taskId is parented by story $parent, not $storyId." }
        $status = Get-TaskInteger $item @('statusId','status_id','status') 'statusId' $true
        $versionValue = Get-OptionalTaskValue $item @('version','entityVersion'); if (-not $versionValue.present) { throw "Child task $taskId is missing version." }; $version = 0L; if (-not [long]::TryParse([string]$versionValue.value,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$version) -or $version -lt 0) { throw "Child task $taskId version must be nonnegative." }
        $aliasValue = Get-OptionalTaskValue $item @('alias','ref','taskRef')
        $alias = if ($aliasValue.present) { [string]$aliasValue.value } else { "id:$taskId" }
        if ([string]::IsNullOrWhiteSpace($alias) -or -not $seenAliases.Add($alias.ToLowerInvariant())) { throw "Child task alias is duplicated or blank: $alias." }
        $criteria = if ($item.Contains('criterionIds')) { @($item.criterionIds) } elseif ($item.Contains('criteria')) { @($item.criteria) } else { @() }
        if ($criteria.Count -eq 0 -and $InputObject.Contains('taskCriteria') -and $InputObject.taskCriteria -is [System.Collections.IDictionary] -and $InputObject.taskCriteria.Contains([string]$taskId)) { $criteria = @($InputObject.taskCriteria[[string]$taskId]) }
        if ($criteria -contains $null -or @($criteria | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { throw "Child task $taskId has invalid criteria." }
        [void]$bindings.Add([ordered]@{ taskId = $taskId; alias = $alias; projectId = $itemProject; parentStoryId = $parent; ref = if ($aliasValue.present) { $aliasValue.value } else { $null }; subject = if ($item.Contains('subject')) { [string]$item.subject } elseif ($item.Contains('title')) { [string]$item.title } else { $null }; criteria = @($criteria); baselineStatusId = $status; version = $version; closed = if ($item.Contains('closed')) { [bool]$item.closed } elseif ($item.Contains('isClosed')) { [bool]$item.isClosed } else { $null } })
    }
    $selected = if ($InputObject.Contains('selectedTaskIds')) { @($InputObject.selectedTaskIds | ForEach-Object { $value = 0L; if (-not [long]::TryParse([string]$_, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -lt 1) { throw 'selectedTaskIds must contain positive integers.' }; $value }) } else { @($bindings | ForEach-Object taskId) }
    if (@($selected | Select-Object -Unique).Count -ne $selected.Count) { throw 'selectedTaskIds must not contain duplicates.' }
    foreach ($id in $selected) {
        $captured = @($bindings | Where-Object { [long]$_.taskId -eq [long]$id })
        if ($captured.Count -eq 0) { throw "Selected child task was not captured: $id." }
        if (@($captured[0].criteria).Count -eq 0) { throw "Selected child task has no authoritative criteria: $id." }
    }
    if ($selected.Count -gt 0 -and $null -eq $storyId) { throw 'Selected child tasks require an authoritative parent story ID.' }
    $packetBinding = Get-TaskPacketBinding $InputObject @($selected) @($bindings)
    $selectedCriteria = [ordered]@{}
    foreach ($id in $selected) { $selectedCriteria[[string]$id] = @((@($bindings | Where-Object { [long]$_.taskId -eq $id })[0]).criteria) }
    return [ordered]@{ storyId = $storyId; selectedTaskIds = @($selected); bindings = @($bindings); complete = $true; itemCount = $items.Count; selectedCriteria = $selectedCriteria; packetBinding = $packetBinding }
}

function Resolve-StatusId {
    param([object] $Value, [object[]] $Metadata, [string] $LogicalName)
    $id = $null; $label = $null
    if ($Value -is [System.Collections.IDictionary]) { if ($Value.Contains('statusId')) { $id = $Value.statusId } elseif ($Value.Contains('id')) { $id = $Value.id }; if ($Value.Contains('name')) { $label = [string]$Value.name } }
    elseif ($Value -is [int] -or $Value -is [long] -or [string]$Value -match '^\d+$') { $id = $Value }
    else { $label = [string]$Value }
    if ($null -eq $id -and [string]::IsNullOrWhiteSpace($label)) { throw "Mapping for $LogicalName is empty." }
    if ($null -eq $id) {
        $matches = @($Metadata | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('name') -and [string]$_.name -ceq $label })
        if ($matches.Count -ne 1) { throw "Mapping for $LogicalName does not resolve to exactly one discovered status ID." }
        $id = if ($matches[0].Contains('id')) { $matches[0].id } elseif ($matches[0].Contains('statusId')) { $matches[0].statusId } else { $null }
    }
    $number = 0L; if ($null -eq $id -or -not [long]::TryParse([string]$id, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 1) { throw "Mapping for $LogicalName must resolve to a positive status ID." }
    if (@($Metadata).Count -gt 0 -and @($Metadata | Where-Object { $_ -is [System.Collections.IDictionary] -and (($_.Contains('id') -and [long]$_.id -eq $number) -or ($_.Contains('statusId') -and [long]$_.statusId -eq $number) ) }).Count -ne 1) { throw "Mapped status ID $number for $LogicalName was not found in discovered metadata." }
    return $number
}

function Resolve-LogicalStatusMapping {
    param([hashtable] $InputObject)
    $projectId = Get-TaskInteger $InputObject @('projectId') 'projectId' $true
    $resource = [string](Need $InputObject 'resource'); if ($resource -notin @('task','story','issue','epic')) { throw 'resource must be task, story, issue, or epic.' }
    $metadata = if ($InputObject.Contains('statusMetadata')) { @($InputObject.statusMetadata) } elseif ($InputObject.Contains('statuses')) { @($InputObject.statuses) } else { @() }
    if ($metadata.Count -eq 0) { throw 'Discovered status metadata is required for a task mapping.' }
    $metadataIds = [System.Collections.Generic.HashSet[long]]::new()
    foreach ($statusMetadata in $metadata) {
        if ($statusMetadata -isnot [System.Collections.IDictionary]) { throw 'Each discovered status metadata item must be an object.' }
        $metadataIdValue = if ($statusMetadata.Contains('id')) { $statusMetadata.id } elseif ($statusMetadata.Contains('statusId')) { $statusMetadata.statusId } else { $null }
        $metadataId = 0L
        if ($null -eq $metadataIdValue -or -not [long]::TryParse([string]$metadataIdValue,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$metadataId) -or $metadataId -lt 1 -or -not $metadataIds.Add($metadataId)) { throw 'Discovered status metadata must contain unique positive IDs.' }
        $metadataProjectValue = if ($statusMetadata.Contains('projectId')) { $statusMetadata.projectId } elseif ($statusMetadata.Contains('project_id')) { $statusMetadata.project_id } elseif ($statusMetadata.Contains('project')) { $statusMetadata.project } else { $null }
        if ($metadataProjectValue -is [System.Collections.IDictionary]) { $metadataProjectValue = if ($metadataProjectValue.Contains('id')) { $metadataProjectValue.id } elseif ($metadataProjectValue.Contains('pk')) { $metadataProjectValue.pk } else { $null } }
        $metadataProject = 0L
        if ($null -eq $metadataProjectValue -or -not [long]::TryParse([string]$metadataProjectValue,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$metadataProject) -or $metadataProject -ne $projectId) { throw "Discovered status metadata $metadataId is not bound to project $projectId." }
        if (-not $statusMetadata.Contains('resource') -or [string]::IsNullOrWhiteSpace([string]$statusMetadata.resource) -or [string]$statusMetadata.resource -cne $resource) { throw "Discovered status metadata $metadataId is not bound to resource $resource." }
    }
    $raw = if ($InputObject.Contains('mapping')) { $InputObject.mapping } elseif ($InputObject.Contains('statusMapping')) { $InputObject.statusMapping } else { throw 'mapping is required.' }
    if ($raw -isnot [System.Collections.IDictionary]) { throw 'mapping must be an object.' }
    $aliases = [ordered]@{ not_started = @('not_started','notStarted','new','start'); in_progress = @('in_progress','inProgress','started'); awaiting_review = @('awaiting_review','awaitingReview','review'); accepted = @('accepted','done'); blocked = @('blocked') }
    $resolved = [ordered]@{ projectId = $projectId; resource = $resource; not_started = $null; in_progress = $null; awaiting_review = $null; accepted = $null; blocked = $null; reviewFallback = $false }
    foreach ($logical in $aliases.Keys) { foreach ($alias in $aliases[$logical]) { if ($raw.Contains($alias)) { $resolved[$logical] = Resolve-StatusId $raw[$alias] $metadata $logical; break } } }
    foreach ($required in @('not_started','in_progress','accepted')) { if ($null -eq $resolved[$required]) { throw "Missing required logical status mapping: $required." } }
    if ($null -eq $resolved.awaiting_review) { $resolved.awaiting_review = $resolved.in_progress; $resolved.reviewFallback = $true }
    $ids = @($resolved.not_started,$resolved.in_progress,$resolved.awaiting_review,$resolved.accepted,$resolved.blocked | Where-Object { $null -ne $_ })
    $duplicates = @($ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    $allowedFallbackDuplicate = $resolved.reviewFallback -and $duplicates.Count -eq 1 -and [string]$duplicates[0] -ceq [string]$resolved.in_progress -and [long]$resolved.awaiting_review -eq [long]$resolved.in_progress
    if ($duplicates.Count -gt 0 -and -not $allowedFallbackDuplicate) { throw "Logical status mapping reuses status IDs: $($duplicates -join ', ')." }
    $resolved.validated = $true
    $resolved.metadataProjectId = $projectId
    $resolved.metadataResource = $resource
    $resolved.metadataIds = @($metadataIds | Sort-Object)
    $resolved.statusMetadata = @($metadata)
    $resolved.metadataDigest = Hash-Object @($metadata)
    $resolved.mappingDigest = Hash-Object [ordered]@{
        projectId = $projectId
        resource = $resource
        statusMetadata = @($metadata)
        mapping = [ordered]@{ not_started = $resolved.not_started; in_progress = $resolved.in_progress; awaiting_review = $resolved.awaiting_review; accepted = $resolved.accepted; blocked = $resolved.blocked; reviewFallback = $resolved.reviewFallback }
    }
    return $resolved
}

function Get-ValidatedTaskMapping {
    param([System.Collections.IDictionary] $InputObject)
    if (-not $InputObject.Contains('statusMapping') -or $InputObject.statusMapping -isnot [System.Collections.IDictionary]) { throw 'A validated statusMapping is required.' }
    $mapping = $InputObject.statusMapping
    foreach ($name in @('projectId','resource','metadataProjectId','metadataResource','not_started','in_progress','awaiting_review','accepted','validated','metadataIds','statusMetadata','metadataDigest','mappingDigest')) { if (-not $mapping.Contains($name)) { throw "statusMapping.$name is required." } }
    if ($mapping.validated -ne $true -or [string]$mapping.resource -cne 'task') { throw 'statusMapping must be a validated task mapping.' }
    $projectId = Get-TaskInteger $InputObject @('projectId') 'projectId' $true
    if ([long]$mapping.projectId -ne $projectId -or [long]$mapping.metadataProjectId -ne $projectId -or [string]$mapping.metadataResource -cne 'task') { throw 'statusMapping metadata does not match the task write project/resource.' }
    $metadata = @($mapping.statusMetadata)
    if ($metadata.Count -eq 0) { throw 'statusMapping.statusMetadata cannot be empty.' }
    $metadataIdsSet = [System.Collections.Generic.HashSet[long]]::new()
    foreach ($statusMetadata in $metadata) {
        if ($statusMetadata -isnot [System.Collections.IDictionary]) { throw 'statusMapping.statusMetadata must contain objects.' }
        $metadataIdValue = if ($statusMetadata.Contains('id')) { $statusMetadata.id } elseif ($statusMetadata.Contains('statusId')) { $statusMetadata.statusId } else { $null }
        $metadataId = 0L
        if ($null -eq $metadataIdValue -or -not [long]::TryParse([string]$metadataIdValue,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$metadataId) -or $metadataId -lt 1 -or -not $metadataIdsSet.Add($metadataId)) { throw 'statusMapping.statusMetadata must contain unique positive IDs.' }
        $metadataProjectValue = if ($statusMetadata.Contains('projectId')) { $statusMetadata.projectId } elseif ($statusMetadata.Contains('project_id')) { $statusMetadata.project_id } elseif ($statusMetadata.Contains('project')) { $statusMetadata.project } else { $null }
        if ($metadataProjectValue -is [System.Collections.IDictionary]) { $metadataProjectValue = if ($metadataProjectValue.Contains('id')) { $metadataProjectValue.id } elseif ($metadataProjectValue.Contains('pk')) { $metadataProjectValue.pk } else { $null } }
        $metadataProject = 0L
        if ($null -eq $metadataProjectValue -or -not [long]::TryParse([string]$metadataProjectValue,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$metadataProject) -or $metadataProject -ne $projectId) { throw "statusMapping metadata $metadataId is not bound to project $projectId." }
        if (-not $statusMetadata.Contains('resource') -or [string]$statusMetadata.resource -cne 'task') { throw "statusMapping metadata $metadataId is not bound to resource task." }
    }
    $metadataIds = @($metadataIdsSet | Sort-Object)
    if (($metadataIds -join ',') -cne (@($mapping.metadataIds | ForEach-Object { [long]$_ } | Sort-Object) -join ',') -or [string]$mapping.metadataDigest -notmatch '^[0-9a-fA-F]{64}$' -or [string]$mapping.mappingDigest -notmatch '^[0-9a-fA-F]{64}$') { throw 'statusMapping metadata identity is incomplete.' }
    if ([string]$mapping.metadataDigest -cne (Hash-Object @($metadata))) { throw 'statusMapping.metadataDigest does not match captured status metadata.' }
    $ids = @($mapping.not_started,$mapping.in_progress,$mapping.awaiting_review,$mapping.accepted) + @($mapping.blocked)
    foreach ($id in $ids | Where-Object { $null -ne $_ }) { if (-not $metadataIdsSet.Contains([long]$id)) { throw "statusMapping contains an undiscovered status ID: $id." } }
    $duplicates = @($ids | Where-Object { $null -ne $_ } | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    $allowedFallbackDuplicate = $mapping.reviewFallback -eq $true -and $duplicates.Count -eq 1 -and [string]$duplicates[0] -ceq [string]$mapping.in_progress -and [long]$mapping.awaiting_review -eq [long]$mapping.in_progress
    if ($duplicates.Count -gt 0 -and -not $allowedFallbackDuplicate) { throw 'statusMapping has an invalid duplicate status ID.' }
    $mappingDigest = Hash-Object [ordered]@{ projectId = $projectId; resource = 'task'; statusMetadata = @($metadata); mapping = [ordered]@{ not_started = [long]$mapping.not_started; in_progress = [long]$mapping.in_progress; awaiting_review = [long]$mapping.awaiting_review; accepted = [long]$mapping.accepted; blocked = if ($null -eq $mapping.blocked) { $null } else { [long]$mapping.blocked }; reviewFallback = ($mapping.reviewFallback -eq $true) } }
    if ([string]$mapping.mappingDigest -cne $mappingDigest) { throw 'statusMapping.mappingDigest does not match captured status metadata and logical mapping.' }
    return $mapping
}

function Require-TaskIdentity {
    param([System.Collections.IDictionary] $Task, [long] $ExpectedProjectId = 0, [long] $ExpectedParentStoryId = 0)
    $taskId = Get-TaskInteger $Task @('taskId','id','task_id') 'taskId' $true
    $projectId = Get-TaskInteger $Task @('projectId','project_id','project') 'projectId' $true
    $parentStoryId = Get-TaskInteger $Task @('parentStoryId','parent_story_id','userStoryId','user_story_id','userStory','user_story') 'parentStoryId' $true
    $versionValue = Get-OptionalTaskValue $Task @('version','entityVersion'); if (-not $versionValue.present) { throw 'Child task is missing version.' }; $version = 0L; if (-not [long]::TryParse([string]$versionValue.value,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$version) -or $version -lt 0) { throw 'Child task version must be nonnegative.' }
    $statusId = Get-TaskInteger $Task @('currentStatusId','statusId','status_id') 'currentStatusId' $true
    if ($ExpectedProjectId -gt 0 -and $projectId -ne $ExpectedProjectId) { throw "Task $taskId is not in project $ExpectedProjectId." }
    if ($ExpectedParentStoryId -gt 0 -and $parentStoryId -ne $ExpectedParentStoryId) { throw "Task $taskId is not owned by story $ExpectedParentStoryId." }
    return [ordered]@{ taskId = $taskId; projectId = $projectId; parentStoryId = $parentStoryId; currentStatusId = $statusId; version = $version }
}

function Test-TaskHumanStatusChange {
    param([System.Collections.IDictionary] $Task, [long] $CurrentStatusId, [long] $FallbackBaselineStatusId = 0)
    if ($Task.Contains('humanChanged') -and $Task.humanChanged -eq $true) { return $true }
    $lastCoordinatorStatusId = Get-TaskInteger $Task @('lastCoordinatorStatusId') 'lastCoordinatorStatusId'
    if ($null -ne $lastCoordinatorStatusId) { return $lastCoordinatorStatusId -ne $CurrentStatusId }
    $baselineStatusId = Get-TaskInteger $Task @('baselineStatusId') 'baselineStatusId'
    if ($null -eq $baselineStatusId -and $FallbackBaselineStatusId -gt 0) { $baselineStatusId = $FallbackBaselineStatusId }
    return $null -ne $baselineStatusId -and $baselineStatusId -ne $CurrentStatusId
}

function Require-ReviewAcceptance {
    param([System.Collections.IDictionary] $InputObject, [long] $TaskId, [string] $CurrentSha, [System.Collections.IDictionary] $Packet, [string[]] $RequiredCriteria)
    if (-not $InputObject.Contains('reviewAcceptance') -or $InputObject.reviewAcceptance -isnot [System.Collections.IDictionary]) { throw "Task $TaskId requires explicit reviewer acceptance before Done." }
    $acceptance = $InputObject.reviewAcceptance
    if ($acceptance.accepted -ne $true) { throw "Task $TaskId is not reviewer-accepted." }
    if (-not $acceptance.Contains('taskId') -or [long]$acceptance.taskId -ne $TaskId) { throw "Reviewer acceptance is bound to a different task: $TaskId." }
    if (-not $acceptance.Contains('reviewedSha') -or [string]$acceptance.reviewedSha -cne $CurrentSha) { throw "Task $TaskId reviewer acceptance is stale for the current revision." }
    if (-not $acceptance.Contains('criterionIds') -or $acceptance.criterionIds -is [string] -or $acceptance.criterionIds -isnot [System.Collections.IEnumerable] -or @($acceptance.criterionIds).Count -eq 0) { throw "Task $TaskId reviewer acceptance must identify criteria." }
    $actual = @($acceptance.criterionIds | ForEach-Object { [string]$_ } | Select-Object -Unique)
    if (($actual -join '|') -cne ($RequiredCriteria -join '|')) { throw "Task $TaskId reviewer acceptance does not exactly cover the validated packet criteria." }
    foreach ($name in @('runId','actionId','packetHash','scopeHash','reviewerId')) { if (-not $acceptance.Contains($name) -or [string]::IsNullOrWhiteSpace([string]$acceptance[$name])) { throw "Task $TaskId reviewer acceptance.$name is required." } }
    if ([string]$acceptance.runId -cne [string]$Packet.runId -or [string]$acceptance.packetHash -cne [string]$Packet.packetHash -or [string]$acceptance.scopeHash -cne [string]$Packet.scopeHash) { throw "Task $TaskId reviewer acceptance is not bound to the validated packet." }
    if (-not $acceptance.Contains('evidence') -or [string]::IsNullOrWhiteSpace([string]$acceptance.evidence)) { throw "Task $TaskId reviewer acceptance must include evidence." }
    return [ordered]@{ taskId = $TaskId; reviewerId = [string]$acceptance.reviewerId; runId = [string]$acceptance.runId; actionId = [string]$acceptance.actionId; packetHash = [string]$acceptance.packetHash; scopeHash = [string]$acceptance.scopeHash; reviewedSha = [string]$acceptance.reviewedSha; criterionIds = @($actual); evidence = $acceptance.evidence; accepted = $true }
}

function Get-TaskWriteJournal {
    param([hashtable] $InputObject)
    $projectId = Get-TaskInteger $InputObject @('projectId') 'projectId' $true; $parentStoryId = Get-TaskInteger $InputObject @('parentStoryId','storyId') 'parentStoryId' $true
    $task = if ($InputObject.Contains('task')) { $InputObject.task } else { $InputObject }
    if ($task -isnot [System.Collections.IDictionary]) { throw 'task must be an object.' }
    $identity = Require-TaskIdentity $task $projectId $parentStoryId
    $packet = Get-ValidatedPacketBinding $InputObject $projectId $parentStoryId
    $packetTask = $packet.tasksById[[string]$identity.taskId]
    $baselineStatusId = if ($null -ne $packetTask) { [long]$packetTask.baselineStatusId } else { 0L }
    if (Test-TaskHumanStatusChange $task $identity.currentStatusId $baselineStatusId) { throw "Task $($identity.taskId) has an authoritative human status change (current=$($identity.currentStatusId), baseline=$baselineStatusId); preserve it and surface the task as unresolved." }
    $mapping = Get-ValidatedTaskMapping $InputObject
    $selected = if ($InputObject.Contains('selectedTaskIds')) { @($InputObject.selectedTaskIds | ForEach-Object { [long]$_ }) } else { throw 'selectedTaskIds is required for a task write.' }
    if (($selected -join ',') -cne (@($packet.selectedTaskIds) -join ',')) { throw 'selectedTaskIds must exactly match the validated packet scope.' }
    if ($selected -notcontains $identity.taskId) { throw "Task $($identity.taskId) is outside the selected task scope." }
    $requiredCriteria = Assert-SelectedTaskCriteria $InputObject $packet $identity.taskId
    $logicalState = if ($InputObject.Contains('logicalState')) { [string]$InputObject.logicalState } else { throw 'logicalState is required for a task write.' }
    if ($logicalState -notin @('not_started','in_progress','awaiting_review','blocked','accepted','done')) { throw 'logicalState is unsupported.' }
    $targetStatusId = switch ($logicalState) { 'not_started' { [long]$mapping.not_started }; 'in_progress' { [long]$mapping.in_progress }; 'awaiting_review' { [long]$mapping.awaiting_review }; 'blocked' { if ($null -eq $mapping.blocked) { throw 'Blocked status is not configured.' }; [long]$mapping.blocked }; 'accepted' { [long]$mapping.accepted }; 'done' { [long]$mapping.accepted } }
    if ($InputObject.Contains('targetStatusId') -and [long]$InputObject.targetStatusId -ne $targetStatusId) { throw 'Caller targetStatusId does not match the validated logical mapping.' }
    $currentSha = [string](Need $InputObject 'currentSha'); if ($currentSha -notmatch '^[0-9a-fA-F]{7,64}$') { throw 'currentSha must be a Git revision.' }
    $progress = Get-ValidatedProgressBinding $InputObject $packet $identity.taskId $currentSha $requiredCriteria $logicalState
    $review = $null
    if ($targetStatusId -eq [long]$mapping.accepted -or $logicalState -in @('accepted','done') -or $InputObject.Contains('reviewAcceptance')) { $review = Require-ReviewAcceptance $InputObject $identity.taskId $currentSha $packet $requiredCriteria }
    $runMarker = [string](Need $InputObject 'runMarker')
    $journal = [ordered]@{ journalId = Hash-Object @{ packetBinding = $packet; progressBinding = $progress; projectId = $identity.projectId; parentStoryId = $identity.parentStoryId; taskId = $identity.taskId; fromStatusId = $identity.currentStatusId; targetStatusId = $targetStatusId; version = $identity.version; currentSha = $currentSha; logicalState = $logicalState; review = $review; runMarker = $runMarker }; taskId = $identity.taskId; projectId = $identity.projectId; parentStoryId = $identity.parentStoryId; actionKind = 'taiga_task_update'; packetBinding = $packet; progressBinding = $progress; target = [ordered]@{ projectId = $identity.projectId; parentStoryId = $identity.parentStoryId; taskId = $identity.taskId; statusId = $targetStatusId }; expectedVersion = $identity.version; fromStatusId = $identity.currentStatusId; targetStatusId = $targetStatusId; logicalState = $logicalState; currentSha = $currentSha; runMarker = $runMarker; reviewerAcceptance = $review; writer = 'coordinator'; blindRetry = $false }
    return $journal
}

function Invoke-TaskScopeReconciliation {
    param([hashtable] $InputObject)
    $projectId = Get-TaskInteger $InputObject @('projectId') 'projectId' $true; $parentStoryId = Get-TaskInteger $InputObject @('parentStoryId','storyId') 'parentStoryId' $true
    foreach ($field in @('baselineTaskIds','currentTaskIds')) { if (-not $InputObject.Contains($field) -or $InputObject[$field] -is [string] -or $InputObject[$field] -isnot [System.Collections.IEnumerable]) { throw "$field must be an array." } }
    $baseline = @($InputObject.baselineTaskIds | ForEach-Object { $v = 0L; if (-not [long]::TryParse([string]$_,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$v) -or $v -lt 1) { throw 'baselineTaskIds must contain positive integers.' }; $v } | Select-Object -Unique)
    $current = @($InputObject.currentTaskIds | ForEach-Object { $v = 0L; if (-not [long]::TryParse([string]$_,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$v) -or $v -lt 1) { throw 'currentTaskIds must contain positive integers.' }; $v } | Select-Object -Unique)
    $added = @($current | Where-Object { $baseline -notcontains $_ }); $removed = @($baseline | Where-Object { $current -notcontains $_ }); $reparented = @()
    if ($InputObject.Contains('reparentedTaskIds')) { $reparented = @($InputObject.reparentedTaskIds | ForEach-Object { [long]$_ }) }
    return [ordered]@{ projectId = $projectId; parentStoryId = $parentStoryId; unchanged = ($added.Count -eq 0 -and $removed.Count -eq 0 -and $reparented.Count -eq 0); addedTaskIds = $added; removedTaskIds = $removed; reparentedTaskIds = $reparented; decision = if ($added.Count -eq 0 -and $removed.Count -eq 0 -and $reparented.Count -eq 0) { 'preserve_scope' } else { 'reconcile_scope_before_writes' }; writes = @() }
}

try {
    $input = Read-Object
    $data = switch ($Operation) {
        'capture-context' {
            $kind = [string](Need $input 'kind'); $projectId = [int](Need $input 'projectId'); $ref = [int](Need $input 'ref'); if ($projectId -lt 1 -or $ref -lt 1) { throw 'Project and ref must be positive.' }
            $pagination = [ordered]@{ detail = Complete-Pages @($input.detailPages) 'detail'; comments = Complete-Pages @($input.commentPages) 'comments' }
            $taskScope = $null
            if ($kind -eq 'story') { $pagination.tasks = Complete-Pages @($input.taskPages) 'tasks'; $taskScope = Get-TaskBindings $input $projectId }
            if ($kind -eq 'epic') { $pagination.stories = Complete-Pages @($input.storyPages) 'epic membership'; if (@($input.storyPages).Count -eq 0) { throw 'Epic membership is incomplete.' } }
            [ordered]@{ complete = $true; projectId = $projectId; kind = $kind; ref = $ref; pagination = $pagination; taskScope = $taskScope; requirementsHash = Hash-Object @{ kind = $kind; projectId = $projectId; ref = $ref; detail = $input.detailPages; comments = $input.commentPages; tasks = $input.taskPages; stories = $input.storyPages; taskScope = $taskScope }; selectedTaskIds = @($input.selectedTaskIds); linkedStoryKeys = @($input.linkedStoryKeys) }
        }
        'validate-status-mappings' {
            $mappings = Need $input 'statusMappings'; $errors = @()
            foreach ($kind in @('issue','task','story','epic')) { if (-not $mappings.Contains($kind)) { $errors += "Missing status mapping for $kind"; continue }; $map = $mappings[$kind]; foreach ($name in @('start','review','awaitingMerge','done')) { if (-not $map.Contains($name) -or [int]$map[$name] -lt 1) { $errors += "Missing $kind.$name status" } }; $ids = @($map.Values | ForEach-Object { [int]$_ }); if (($ids | Group-Object | Where-Object Count -gt 1).Count -gt 0) { $errors += "Ambiguous duplicate status IDs for $kind" } }
            [ordered]@{ valid = ($errors.Count -eq 0); errors = $errors }
        }
        'resolve-status-mapping' { Resolve-LogicalStatusMapping $input }
        'prepare-task-write' { Get-TaskWriteJournal $input }
        'prepare-write' {
            $kind = [string](Need $input 'writeKind'); $target = Need $input 'target'; $version = [int](Need $input 'version'); if ($version -lt 0) { throw 'Version must be nonnegative.' }; $payload = Need $input 'payload'; $marker = Need $input 'runMarker'; if ([string]$payload -match '(?i)(password|token|secret)' -or [string]$payload -match '(?i)raw.?log') { throw 'Unsafe credential or raw-log content is not allowed in a milestone write.' }; [ordered]@{ actionKind = "taiga_$kind"; target = $target; version = $version; runMarker = $marker; payload = $payload; inputDigest = Hash-Object @{ target = $target; version = $version; payload = $payload } }
        }
        'reconcile-write' {
            if ($input.Contains('versionConflict') -and $input.versionConflict -eq $true) { [ordered]@{ state = 'conflict'; action = 'reread_and_evaluate'; blindRetry = $false } }
            elseif ($input.Contains('responseLost') -and $input.responseLost -eq $true) { [ordered]@{ state = 'uncertain'; action = 'inspect_detail_history_comments'; blindRetry = $false } }
            elseif ($input.Contains('observed') -and $input.observed -eq $true) { [ordered]@{ state = 'confirmed'; action = 'record_receipt'; blindRetry = $false } }
            else { [ordered]@{ state = 'needs_input'; action = 'reconcile_external_state'; blindRetry = $false } }
        }
        'reconcile-task-write' {
            if ($input.Contains('versionConflict') -and $input.versionConflict -eq $true) { [ordered]@{ state = 'conflict'; action = 'reread_task_detail_history'; blindRetry = $false; preserveHumanChange = $true } }
            elseif ($input.Contains('responseLost') -and $input.responseLost -eq $true) { [ordered]@{ state = 'uncertain'; action = 'reread_task_detail_history'; blindRetry = $false; preserveHumanChange = $true } }
            elseif ($input.Contains('currentTask') -and $input.currentTask -is [System.Collections.IDictionary] -and $input.Contains('journal')) {
                $journal = $input.journal; $current = Require-TaskIdentity $input.currentTask ([long]$journal.target.projectId) ([long]$journal.target.parentStoryId)
                if ($current.taskId -ne [long]$journal.target.taskId) { throw "Authoritative reread task $($current.taskId) does not match journal target $($journal.target.taskId)." }
                if ($current.version -lt [long]$journal.expectedVersion) { throw 'Authoritative task version moved backwards.' }
                $markerProof = $false
                if ($input.currentTask.Contains('lastCoordinatorRunMarker') -and [string]$input.currentTask.lastCoordinatorRunMarker -ceq [string]$journal.runMarker) { $markerProof = $true }
                if ($input.currentTask.Contains('historyRunMarkers') -and @($input.currentTask.historyRunMarkers | ForEach-Object { [string]$_ }) -contains [string]$journal.runMarker) { $markerProof = $true }
                if ($current.currentStatusId -eq [long]$journal.targetStatusId -and $markerProof -and $current.version -gt [long]$journal.expectedVersion) { [ordered]@{ state = 'confirmed'; action = 'record_receipt'; blindRetry = $false; applied = $true; authoritativeVersion = $current.version; taskId = $current.taskId; runMarker = [string]$journal.runMarker } }
                elseif ($current.currentStatusId -eq [long]$journal.targetStatusId -and $markerProof) { [ordered]@{ state = 'confirmed'; action = 'record_receipt'; blindRetry = $false; applied = $true; authoritativeVersion = $current.version; taskId = $current.taskId; runMarker = [string]$journal.runMarker } }
                else { [ordered]@{ state = 'human_change_preserved'; action = 'surface_unresolved'; blindRetry = $false; applied = $false; authoritativeVersion = $current.version; taskId = $current.taskId; currentStatusId = $current.currentStatusId; reason = if (-not $markerProof) { 'missing_coordinator_run_marker' } else { 'authoritative_status_does_not_match_journal' } } }
            }
            elseif ($input.Contains('observed') -and $input.observed -eq $true) { throw 'An unbound observed boolean cannot confirm a task write.' }
            else { [ordered]@{ state = 'needs_input'; action = 'reread_task_detail_history'; blindRetry = $false } }
        }
        'apply-reviewed-task-transition' {
            if (-not $input.Contains('tasks') -or $input.tasks -is [string] -or $input.tasks -isnot [System.Collections.IEnumerable]) { throw 'tasks must be an array.' }
            $projectId = Get-TaskInteger $input @('projectId') 'projectId' $true; $parentStoryId = Get-TaskInteger $input @('parentStoryId','storyId') 'parentStoryId' $true; $currentSha = [string](Need $input 'currentSha'); $packet = Get-ValidatedPacketBinding $input $projectId $parentStoryId; $mapping = Get-ValidatedTaskMapping $input; $selected = if ($input.Contains('selectedTaskIds')) { @($input.selectedTaskIds | ForEach-Object { $value = 0L; if (-not [long]::TryParse([string]$_,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or $value -lt 1) { throw 'selectedTaskIds must contain positive integers.' }; $value }) } else { throw 'selectedTaskIds is required for reviewed task transitions.' }; if (@($selected | Select-Object -Unique).Count -ne $selected.Count) { throw 'selectedTaskIds must not contain duplicates.' }; if (($selected -join ',') -cne (@($packet.selectedTaskIds) -join ',')) { throw 'selectedTaskIds must exactly match the validated packet scope.' }; $scopeDecision = if ($input.Contains('scopeReconciliation')) { [string]$input.scopeReconciliation } else { 'preserve_scope' }; if ($scopeDecision -ne 'preserve_scope') { throw 'Task scope must be reconciled before reviewed writes.' }; $writes = @(); $unchanged = @(); $unresolved = @(); $outcomes = @(); $seen = [System.Collections.Generic.HashSet[long]]::new()
            foreach ($taskInput in @($input.tasks)) {
                if ($taskInput -isnot [System.Collections.IDictionary]) { $unresolved += [ordered]@{ taskId = $null; outcome = 'failed'; reason = 'task_not_object' }; continue }
                try {
                    $identity = Require-TaskIdentity $taskInput $projectId $parentStoryId; if (-not $seen.Add($identity.taskId)) { throw "Reviewed task is duplicated: $($identity.taskId)." }; if ($selected -notcontains $identity.taskId) { throw "Reviewed task $($identity.taskId) is outside the selected task scope." }; $requiredCriteria = Assert-SelectedTaskCriteria $taskInput $packet $identity.taskId
                    $logical = if ($taskInput.Contains('logicalState')) { [string]$taskInput.logicalState } else { throw "Task $($identity.taskId) logicalState is required." }
                    $progress = Get-ValidatedProgressBinding $taskInput $packet $identity.taskId $currentSha $requiredCriteria $logical
                    $target = switch ($logical) { 'not_started' { [long]$mapping.not_started }; 'in_progress' { [long]$mapping.in_progress }; 'awaiting_review' { [long]$mapping.awaiting_review }; 'blocked' { if ($null -eq $mapping.blocked) { throw 'Blocked status is not configured.' }; [long]$mapping.blocked }; 'accepted' { [long]$mapping.accepted }; 'done' { [long]$mapping.accepted }; default { throw "Task $($identity.taskId) logicalState is unsupported." } }
                    if ($taskInput.Contains('targetStatusId') -and [long]$taskInput.targetStatusId -ne $target) { throw "Task $($identity.taskId) target status does not match mapping." }
                    if ($target -eq [long]$mapping.accepted -or $logical -in @('accepted','done') -or $taskInput.Contains('reviewAcceptance')) { $review = Require-ReviewAcceptance $taskInput $identity.taskId $currentSha $packet $requiredCriteria } else { $review = $null }
                    $journal = [ordered]@{ journalId = Hash-Object @{ packetBinding = $packet; progressBinding = $progress; projectId = $identity.projectId; parentStoryId = $identity.parentStoryId; taskId = $identity.taskId; version = $identity.version; targetStatusId = $target; currentSha = $currentSha; runMarker = $input.runMarker; review = $review }; taskId = $identity.taskId; projectId = $identity.projectId; parentStoryId = $identity.parentStoryId; packetBinding = $packet; progressBinding = $progress; target = [ordered]@{ projectId = $identity.projectId; parentStoryId = $identity.parentStoryId; taskId = $identity.taskId; statusId = $target }; fromStatusId = $identity.currentStatusId; targetStatusId = $target; expectedVersion = $identity.version; currentSha = $currentSha; runMarker = [string](Need $input 'runMarker'); logicalState = $logical; reviewerAcceptance = $review; writer = 'coordinator'; blindRetry = $false }
                    $packetTask = $packet.tasksById[[string]$identity.taskId]
                    $baselineStatusId = if ($null -ne $packetTask) { [long]$packetTask.baselineStatusId } else { 0L }
                    if (Test-TaskHumanStatusChange $taskInput $identity.currentStatusId $baselineStatusId) { $unresolved += [ordered]@{ taskId = $identity.taskId; outcome = 'human_changed'; reason = 'authoritative status differs from the last coordinator status or baseline'; currentStatusId = $identity.currentStatusId; targetStatusId = $target; version = $identity.version }; $outcomes += [ordered]@{ taskId = $identity.taskId; outcome = 'human_changed'; journalId = $journal.journalId } }
                    elseif ($identity.currentStatusId -eq $target) { $unchanged += [ordered]@{ taskId = $identity.taskId; statusId = $target; version = $identity.version; preserved = $true }; $outcomes += [ordered]@{ taskId = $identity.taskId; outcome = 'unchanged'; journalId = $journal.journalId } }
                    else { $writes += $journal; $outcomes += [ordered]@{ taskId = $identity.taskId; outcome = 'planned'; journalId = $journal.journalId } }
                } catch { $unresolved += [ordered]@{ taskId = if ($taskInput.Contains('taskId')) { [long]$taskInput.taskId } else { $null }; outcome = 'failed'; reason = $_.Exception.Message }; $outcomes += [ordered]@{ taskId = if ($taskInput.Contains('taskId')) { [long]$taskInput.taskId } else { $null }; outcome = 'failed' } }
            }
            $missing = @($selected | Where-Object { -not $seen.Contains([long]$_) }); if ($missing.Count -gt 0) { throw "Reviewed task set is incomplete; missing selected tasks: $($missing -join ', ')." }
            [ordered]@{ projectId = $projectId; parentStoryId = $parentStoryId; currentSha = $currentSha; runMarker = [string]$input.runMarker; writes = $writes; unchanged = $unchanged; unresolved = $unresolved; outcomes = $outcomes; successfulUpdatesPreserved = $true; onlyCoordinatorWrites = $true; taskDoneRequiresReviewAcceptance = $true; scopeReconciled = ($scopeDecision -eq 'preserve_scope') }
        }
        'reconcile-task-scope' { Invoke-TaskScopeReconciliation $input }
        'finalize' {
            $errors = @(); if ((Need $input 'requirementsHash') -ne (Need $input 'currentRequirementsHash')) { $errors += 'Requirements changed.' }; if (-not $input.criteriaComplete) { $errors += 'Criteria are incomplete.' }; if (-not $input.checksPass) { $errors += 'Required checks did not pass.' }; if ($input.completionPolicy -eq 'merged' -and $input.prState -ne 'merged') { $errors += 'Observed PR is not merged.' }; if ($input.kind -eq 'epic' -and (-not $input.allStoriesMerged -or -not $input.epicAccepted)) { $errors += 'Epic requires all merged stories and integrated acceptance.' }
            $packet = $null
            if ($input.Contains('packetBinding')) {
                try { $packet = Get-ValidatedPacketBinding $input } catch { $errors += $_.Exception.Message }
            }
            $packetTaskIds = if ($null -ne $packet) { @($packet.selectedTaskIds | ForEach-Object { [long]$_ }) } else { @() }
            $callerTaskIds = if ($input.Contains('selectedTaskIds')) { @($input.selectedTaskIds | ForEach-Object { $value = 0L; if (-not [long]::TryParse([string]$_,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or $value -lt 1) { $errors += 'selectedTaskIds must contain positive integers.' }; $value }) } else { $null }
            if ($null -ne $callerTaskIds -and @($callerTaskIds | Select-Object -Unique).Count -ne $callerTaskIds.Count) { $errors += 'selectedTaskIds contains duplicates.' }
            if ($null -ne $packet -and $null -ne $callerTaskIds -and ($callerTaskIds -join ',') -cne ($packetTaskIds -join ',')) { $errors += 'selectedTaskIds do not exactly match the validated packet scope.' }
            if ($null -ne $packet -and $input.Contains('projectId') -and [long]$input.projectId -ne [long]$packet.projectId) { $errors += 'projectId does not match the validated packet.' }
            if ($null -ne $packet -and $input.Contains('parentStoryId') -and [long]$input.parentStoryId -ne [long]$packet.parentStoryId) { $errors += 'parentStoryId does not match the validated packet.' }
            $selectedTaskIds = if ($null -ne $packet) { $packetTaskIds } elseif ($null -ne $callerTaskIds) { @($callerTaskIds) } else { @() }
            if ($selectedTaskIds.Count -gt 0 -and $null -eq $packet) { $errors += 'Selected child tasks require a validated packetBinding.' }
            $taskEvidence = @(); $reviewAction = $null
            if ($selectedTaskIds.Count -gt 0) {
                if (-not $input.Contains('selectedTaskEvidence') -or $input.selectedTaskEvidence -is [string] -or $input.selectedTaskEvidence -isnot [System.Collections.IEnumerable]) { $errors += 'Every selected child requires persisted evidence references.' }
                else {
                    $providedEvidence = @($input.selectedTaskEvidence)
                    if ($providedEvidence.Count -ne $selectedTaskIds.Count) { $errors += 'Persisted evidence references must contain exactly one entry per selected child.' }
                    $providedTaskIds = @($providedEvidence | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('taskId') } | ForEach-Object { [long]$_.taskId })
                    if (@($providedTaskIds | Select-Object -Unique).Count -ne $providedTaskIds.Count -or @($providedTaskIds | Where-Object { $selectedTaskIds -notcontains $_ }).Count -gt 0) { $errors += 'Persisted evidence references contain a duplicate or unselected task.' }
                }
                $currentSha = if ($input.Contains('currentSha')) { [string]$input.currentSha } else { $null }
                if ([string]::IsNullOrWhiteSpace($currentSha) -or $currentSha -notmatch '^[0-9a-fA-F]{7,64}$') { $errors += 'currentSha must be a Git revision.' }
                $registry = $null; $checkpoint = $null; $mapping = $null
                $registryRoot = if ($input.Contains('stateRoot')) { [string]$input.stateRoot } elseif ($input.Contains('registryRoot')) { [string]$input.registryRoot } else { '' }
                $progressRoot = if ($input.Contains('progressRoot')) { [string]$input.progressRoot } elseif ($input.Contains('taskProgressRoot')) { [string]$input.taskProgressRoot } else { '' }
                try { $registry = (Get-RegistryInspection $registryRoot).data.registry } catch { $errors += "Persisted state registry could not be inspected: $($_.Exception.Message)" }
                try { $checkpoint = (Get-ProgressCheckpoint $progressRoot).state } catch { $errors += "Persisted task progress could not be validated: $($_.Exception.Message)" }
                try { $mapping = Get-ValidatedTaskMapping $input } catch { $errors += "Persisted task-write status mapping is invalid: $($_.Exception.Message)" }
                $expectedCriteria = if ($input.Contains('expectedCriteria')) { @($input.expectedCriteria) } elseif ($input.Contains('reviewCriteria')) { @($input.reviewCriteria) } else { @() }
                if ($expectedCriteria.Count -eq 0) { $errors += 'expectedCriteria is required to validate the persisted review receipt.' }
                if ($null -ne $registry -and $expectedCriteria.Count -gt 0) {
                    try {
                        $reviewAction = Get-PersistedReviewAction $input $packet $registry $expectedCriteria
                        $receipt = $reviewAction.receipt
                        if ([string]$receipt.verdict -cne 'pass') { throw 'Persisted review receipt is not a pass.' }
                        $ticketKey = "project:$($packet.projectId):story:$($packet.parentStoryId)"
                        if ([string]$receipt.runId -cne [string]$packet.runId -or [string]$receipt.actionId -cne [string]$reviewAction.actionId -or [string]$receipt.ticketKey -cne $ticketKey -or [string]$receipt.scopeHash -cne [string]$packet.scopeHash -or [string]$receipt.reviewedSha -cne $currentSha) { throw 'Persisted review receipt is not bound to the selected story, run, action, scope, and final SHA.' }
                        $receiptAcceptances = @($receipt.taskAcceptances)
                        if ($receiptAcceptances.Count -ne $selectedTaskIds.Count) { throw 'Persisted review receipt does not contain exactly one acceptance per selected task.' }
                        foreach ($acceptance in $receiptAcceptances) { if ($acceptance -isnot [System.Collections.IDictionary] -or -not $acceptance.Contains('taskId') -or $selectedTaskIds -notcontains [long]$acceptance.taskId) { throw 'Persisted review receipt contains an acceptance for an unselected task.' } }
                        foreach ($taskId in $selectedTaskIds) { Get-ReceiptTaskAcceptance $receipt ([long]$taskId) @($packet.criteriaByTask[[string]$taskId] | ForEach-Object { [string]$_ }) $currentSha $reviewAction.assignedReviewerId | Out-Null }
                    } catch { $errors += "Persisted review evidence is invalid: $($_.Exception.Message)" }
                }
                if ($null -ne $registry -and $null -ne $checkpoint -and $null -ne $mapping -and $null -ne $reviewAction -and $errors.Count -eq 0) {
                    foreach ($taskId in $selectedTaskIds) { try { $taskEvidence += Get-TaskWriteEvidence $input $packet $mapping $registry $checkpoint ([long]$taskId) $currentSha $reviewAction.actionId $reviewAction.assignedReviewerId } catch { $errors += "Persisted child evidence is invalid: $($_.Exception.Message)" } }
                }
            }
            [ordered]@{ ready = ($errors.Count -eq 0); errors = $errors; selectedTaskIds = $selectedTaskIds; selectedTaskEvidence = $taskEvidence; reviewActionId = if ($null -ne $reviewAction) { $reviewAction.actionId } else { $null }; receiptReference = if ($null -ne $reviewAction) { $reviewAction.receiptReference } else { $null }; selectedChildrenVerified = ($selectedTaskIds.Count -eq 0 -or $errors.Count -eq 0); taigaDoneMayBeSelected = ($errors.Count -eq 0) }
        }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch { [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_taiga'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1 }
