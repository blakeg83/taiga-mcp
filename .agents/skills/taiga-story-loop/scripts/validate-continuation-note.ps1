# Offline checks of the production snapshot writer. No live chats, schedules,
# Taiga writes, or claim of executing a model's heartbeat decisions.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$writer = Join-Path $PSScriptRoot 'write-continuation-note.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-continuation-' + [Guid]::NewGuid().ToString('N'))
$path = Join-Path $fixtureRoot 'current.md'
$recoveryPath = Join-Path $fixtureRoot 'recovery.md'
$encoding = [Text.UTF8Encoding]::new($false)

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Rejected([System.Collections.IDictionary] $Candidate, [string] $Message) {
    $before = [IO.File]::ReadAllText($path)
    $backup = [IO.File]::ReadAllText($path + '.previous')
    $rejected = $false
    try { & $writer -NotePath $path -Snapshot $Candidate | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
    Assert-True ([IO.File]::ReadAllText($path) -ceq $before) "$Message preserves current snapshot"
    Assert-True ([IO.File]::ReadAllText($path + '.previous') -ceq $backup) "$Message preserves backup"
}

function Read-Snapshot([string] $NotePath) {
    $snapshot = [ordered]@{}
    foreach ($line in [IO.File]::ReadAllLines($NotePath)) {
        $separator = $line.IndexOf(': ')
        if ($separator -gt 0) {
            $snapshot[$line.Substring(0, $separator)] = $line.Substring($separator + 2)
        }
    }
    $snapshot
}

function New-AuthoritativePairState {
    $messages = [System.Collections.Generic.List[object]]::new()
    [void]$messages.Add([pscustomobject]@{ Id = 'ready-task-77'; Route = 'implementer-to-reviewer' })
    [void]$messages.Add([pscustomobject]@{ Id = 'accepted-task-77-revision-a2'; Route = 'reviewer-to-implementer' })

    $taigaWrites = [System.Collections.Generic.List[object]]::new()
    [void]$taigaWrites.Add([pscustomobject]@{
        OperationId = 'task-77-accepted-revision-a2'
        TaskId = 77
        Revision = 'revision-a2'
        Status = 'accepted'
        Outcome = 'confirmed'
        EvidenceRef = 'taiga-task-77-v4'
    })

    $advancements = [System.Collections.Generic.List[object]]::new()
    [void]$advancements.Add([pscustomobject]@{
        EventId = 'advance-task-78'
        FromTaskId = 77
        ToTaskId = 78
        Outcome = 'confirmed'
        EvidenceRef = 'progress-task-78'
    })

    [ordered]@{
        StoryRef = 52
        DeclaredTasks = @(77, 78)
        TaskAcceptances = @([pscustomobject]@{
            EventId = 'accepted-task-77-revision-a2'
            TaskId = 77
            ReviewedRevision = 'revision-a2'
            EvidenceRef = 'review-accept-77'
            Confirmed = $true
        })
        ConfirmedWrites = $taigaWrites
        WorkerStates = @(
            [pscustomobject]@{
                Role = 'implementer'
                TaskId = 78
                Revision = 'revision-b1'
                State = 'implementing'
                Cursor = 'impl-cursor-b1'
                Confirmed = $true
            }
            [pscustomobject]@{
                Role = 'reviewer'
                TaskId = 78
                Revision = 'none'
                State = 'waiting_for_implementation'
                Cursor = 'review-cursor-b1'
                Confirmed = $true
            }
        )
        Messages = $messages
        Advancements = $advancements
    }
}

function Get-AuthoritativeRecoveryState {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Authoritative
    )

    $declaredTasks = @($Authoritative['DeclaredTasks'])
    $acceptanceMatches = @($Authoritative['TaskAcceptances'] | Where-Object { $_.Confirmed -and $_.TaskId -gt 0 } | Select-Object -First 1)
    if ($acceptanceMatches.Count -eq 0) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing confirmed task acceptance' }
    }
    $acceptance = $acceptanceMatches[0]
    if ([string]::IsNullOrWhiteSpace([string]$acceptance.EvidenceRef)) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing task acceptance evidence reference' }
    }

    $acceptedIndex = [Array]::IndexOf([int[]]$declaredTasks, [int]$acceptance.TaskId)
    if ($acceptedIndex -lt 0 -or $acceptedIndex -ge ($declaredTasks.Count - 1)) {
        return [pscustomobject]@{ Ready = $false; Reason = 'task acceptance is not followed by a declared task' }
    }
    $expectedNextTask = [int]$declaredTasks[$acceptedIndex + 1]

    $writesForTask = @($Authoritative['ConfirmedWrites'] | Where-Object {
        $_.TaskId -eq $acceptance.TaskId -and $_.Status -eq 'accepted'
    })
    if ($writesForTask.Count -eq 0) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing confirmed Taiga write for accepted task' }
    }
    $conflictingWrites = @($writesForTask | Where-Object {
        $_.Outcome -eq 'confirmed' -and $_.Revision -cne $acceptance.ReviewedRevision
    })
    if ($conflictingWrites.Count -gt 0) {
        return [pscustomobject]@{ Ready = $false; Reason = 'conflicting confirmed Taiga write for accepted revision' }
    }
    $writeMatches = @($writesForTask | Where-Object {
        $_.Outcome -eq 'confirmed' -and $_.Revision -ceq $acceptance.ReviewedRevision
    } | Select-Object -First 1)
    if ($writeMatches.Count -eq 0) {
        if (@($writesForTask | Where-Object { $_.Outcome -ne 'confirmed' }).Count -gt 0) {
            return [pscustomobject]@{ Ready = $false; Reason = 'unknown Taiga write outcome' }
        }
        return [pscustomobject]@{ Ready = $false; Reason = 'missing confirmed Taiga write for accepted revision' }
    }
    $write = $writeMatches[0]
    if ([string]::IsNullOrWhiteSpace([string]$write.EvidenceRef)) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing Taiga write evidence reference' }
    }

    $advancementMatches = @($Authoritative['Advancements'] | Where-Object {
        $_.FromTaskId -eq $acceptance.TaskId -and $_.ToTaskId -eq $expectedNextTask
    } | Select-Object -First 1)
    if ($advancementMatches.Count -eq 0) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing advancement evidence for next declared task' }
    }
    $advancement = $advancementMatches[0]
    if ($advancement.Outcome -ne 'confirmed') {
        return [pscustomobject]@{ Ready = $false; Reason = 'conflicting advancement outcome for next declared task' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$advancement.EvidenceRef)) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing advancement evidence reference' }
    }

    $implementerMatches = @($Authoritative['WorkerStates'] | Where-Object {
        $_.Confirmed -and $_.Role -eq 'implementer'
    } | Select-Object -First 1)
    $reviewerMatches = @($Authoritative['WorkerStates'] | Where-Object {
        $_.Confirmed -and $_.Role -eq 'reviewer'
    } | Select-Object -First 1)
    if ($implementerMatches.Count -eq 0 -or $reviewerMatches.Count -eq 0) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing confirmed persistent worker state' }
    }
    $implementer = $implementerMatches[0]
    $reviewer = $reviewerMatches[0]
    if ($implementer.TaskId -ne $expectedNextTask -or $reviewer.TaskId -ne $expectedNextTask) {
        return [pscustomobject]@{ Ready = $false; Reason = 'conflicting worker task state for next declared task' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$implementer.Revision) -or
        [string]::IsNullOrWhiteSpace([string]$implementer.Cursor) -or
        [string]::IsNullOrWhiteSpace([string]$reviewer.Cursor)) {
        return [pscustomobject]@{ Ready = $false; Reason = 'missing worker revision or cursor evidence' }
    }

    $nextAction = if ($implementer.State -eq 'implementing') {
        "continue task #$expectedNextTask implementation"
    } else {
        "reconcile task #$expectedNextTask worker state"
    }
    [pscustomobject]@{
        Ready = $true
        Current = "story #$($Authoritative['StoryRef']) | task #$($implementer.TaskId)"
        TaskState = "$($implementer.Revision) | $($implementer.State)"
        Next = $nextAction
        Evidence = "acceptance:$($acceptance.EvidenceRef) | write:$($write.EvidenceRef) | advancement:$($advancement.EvidenceRef) | workers:$($implementer.Cursor),$($reviewer.Cursor)"
    }
}

function Invoke-StaleSnapshotRecovery {
    param(
        [Parameter(Mandatory)] [string] $NotePath,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $StaleSnapshot,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Authoritative
    )

    $recoveryState = Get-AuthoritativeRecoveryState -Authoritative $Authoritative
    if (-not $recoveryState.Ready) {
        return [pscustomobject]@{
            SnapshotChanged = $false
            Held = $true
            Reason = $recoveryState.Reason
            Messages = $Authoritative['Messages'].Count
            TaigaWrites = $Authoritative['ConfirmedWrites'].Count
            Advancements = $Authoritative['Advancements'].Count
        }
    }

    $isStale = $StaleSnapshot['Current'] -cne $recoveryState.Current -or
        $StaleSnapshot['Task state'] -cne $recoveryState.TaskState -or
        $StaleSnapshot['Evidence'] -cne $recoveryState.Evidence
    if (-not $isStale) {
        return [pscustomobject]@{
            SnapshotChanged = $false
            Held = $false
            Reason = $null
            Messages = $Authoritative['Messages'].Count
            TaigaWrites = $Authoritative['ConfirmedWrites'].Count
            Advancements = $Authoritative['Advancements'].Count
        }
    }

    # Recovery only replaces the stale pointer. The pair's confirmed messages,
    # Taiga writes, and task advancement are already authoritative and must not
    # be replayed while the coordinator refreshes its note.
    $refreshedSnapshot = [ordered]@{}
    foreach ($key in $StaleSnapshot.Keys) { $refreshedSnapshot[$key] = $StaleSnapshot[$key] }
    $refreshedSnapshot['Current'] = $recoveryState.Current
    $refreshedSnapshot['Task state'] = $recoveryState.TaskState
    $refreshedSnapshot['Review'] = 'pending'
    $refreshedSnapshot['Next'] = $recoveryState.Next
    $refreshedSnapshot['Evidence'] = $recoveryState.Evidence
    $writeResult = & $writer -NotePath $NotePath -Snapshot $refreshedSnapshot

    [pscustomobject]@{
        SnapshotChanged = [bool]$writeResult.Changed
        Held = $false
        Reason = $null
        Messages = $Authoritative['Messages'].Count
        TaigaWrites = $Authoritative['ConfirmedWrites'].Count
        Advancements = $Authoritative['Advancements'].Count
    }
}

function Resolve-MigrationTopology([System.Collections.IDictionary] $Snapshot) {
    if ($Snapshot.Contains('Topology') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot['Topology'])) {
        return [string]$Snapshot['Topology']
    }

    $scope = [string]$Snapshot['Scope']
    if ($scope -match '(?i)\bepic\b' -or $scope -match '(?i)\bstories?\b[^|]*(?:[,;]|\band\b)') {
        return 'epic-shared-feature'
    }
    if ($scope -match '(?i)\bstory\b') {
        return 'legacy-standalone-feature'
    }
    'needs-reconciliation'
}

try {
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $snapshot = [ordered]@{
        'Run' = 'synthetic-story-52'
        'Scope' = 'project 12 epic #45 | stories: #52, #53 | tasks: #77, #78'
        'Repository' = 'C:\Synthetic\TaigaMCP | remote: origin https://example.invalid/repo'
        'Base' = 'origin/master @ base-sha'
        'Topology' = 'epic-shared-feature'
        'Feature' = 'codex/feature-synthetic | worktree: C:\Synthetic\feature | head: feature-sha'
        'Current' = 'story #52 | task #77'
        'Story branch' = 'codex/story-52-synthetic | worktree: C:\Synthetic\story | base: feature-sha'
        'Implementer' = 'impl-id @ local | reviewer: review-id @ local'
        'Pair' = 'reused | IDs resolved: yes | authorization: setup-message-ref'
        'Setup authorization' = 'start | mode: selectable | submitted: true | reference: auth-synthetic-52'
        'Review mode' = 'per_task | approved HEAD: pending'
        'PR' = 'pending | base: codex/feature-synthetic | head: revision-000'
        'Approval' = 'pending | prompt: none | identity: pending'
        'Review' = 'changes_requested'
        'Final review' = 'not_applicable | profile: none | head: pending'
        'Merge' = 'pending'
        'Next' = 'wait for correction of task #77'
        'Recovery' = 'automation-id | current note: current.md'
        'Worker cursors' = 'implementer cursor-000 | reviewer cursor-000'
        'Task state' = 'revision-000 | implementing'
        'Gate' = 'none'
        'Pending action' = 'none'
        'Evidence' = 'worker-handoff-ref | review-ref | legacy.md'
    }

    $created = & $writer -NotePath $path -Snapshot $snapshot
    Assert-True $created.Changed 'creates initial complete snapshot'
    Assert-True (-not [IO.File]::Exists($path + '.previous')) 'initial creation has no invented previous snapshot'

    # Existing snapshots predate the optional legacy final-review field and
    # must remain writable while the coordinator reconciles them.
    $compatSnapshot = [ordered]@{}
    foreach ($key in $snapshot.Keys) {
        if ($key -cne 'Final review') { $compatSnapshot[$key] = $snapshot[$key] }
    }
    $compatResult = & $writer -NotePath $path -Snapshot $compatSnapshot
    Assert-True $compatResult.Changed 'older snapshot without Final review remains writable'
    Assert-True (-not [IO.File]::ReadAllText($path).Contains('Final review:')) 'compatibility write does not invent an unobserved final-review state'
    & $writer -NotePath $path -Snapshot $snapshot | Out-Null

    # Existing active runs may omit Topology. Resolve the recorded scope before
    # interpreting their shared feature fields.
    $legacySnapshot = [ordered]@{}
    foreach ($key in $snapshot.Keys) {
        if ($key -cne 'Topology') { $legacySnapshot[$key] = $snapshot[$key] }
    }
    $legacySnapshot['Scope'] = 'project 12 story #52 | tasks: #77, #78'
    $resolvedLegacyTopology = Resolve-MigrationTopology $legacySnapshot
    Assert-True ($resolvedLegacyTopology -eq 'legacy-standalone-feature') 'standalone scope selects the legacy feature-based topology'
    $legacySnapshot['Topology'] = $resolvedLegacyTopology
    $legacySnapshot['PR'] = 'pending | base: codex/feature-synthetic | head: revision-000'
    $legacyResult = & $writer -NotePath $path -Snapshot $legacySnapshot
    Assert-True $legacyResult.Changed 'standalone legacy snapshot without topology remains writable'
    $legacyText = [IO.File]::ReadAllText($path)
    Assert-True ($legacyText.Contains('legacy-standalone-feature') -and
        $legacyText.Contains('codex/feature-synthetic') -and
        $legacyText.Contains('base: codex/feature-synthetic')) 'standalone legacy topology and feature PR base are recorded'

    $epicResumeSnapshot = [ordered]@{}
    foreach ($key in $snapshot.Keys) {
        if ($key -cne 'Topology') { $epicResumeSnapshot[$key] = $snapshot[$key] }
    }
    $resolvedEpicTopology = Resolve-MigrationTopology $epicResumeSnapshot
    Assert-True ($resolvedEpicTopology -eq 'epic-shared-feature') 'epic scope preserves the epic feature topology'
    $epicResumeSnapshot['Topology'] = $resolvedEpicTopology
    $epicResumeResult = & $writer -NotePath $path -Snapshot $epicResumeSnapshot
    Assert-True $epicResumeResult.Changed 'epic legacy snapshot without topology remains writable'
    $epicResumeText = [IO.File]::ReadAllText($path)
    Assert-True ($epicResumeText.Contains('epic-shared-feature') -and
        $epicResumeText.Contains('codex/feature-synthetic') -and
        $epicResumeText.Contains('stories: #52, #53')) 'epic topology and feature lineage are preserved during migration'

    $ambiguousSnapshot = [ordered]@{}
    foreach ($key in $snapshot.Keys) {
        if ($key -cne 'Topology') { $ambiguousSnapshot[$key] = $snapshot[$key] }
    }
    $ambiguousSnapshot['Scope'] = 'project 12 | active run without declared scope'
    Assert-True ((Resolve-MigrationTopology $ambiguousSnapshot) -eq 'needs-reconciliation') 'feature fields without recorded scope require reconciliation'

    $standaloneSnapshot = [ordered]@{}
    foreach ($key in $snapshot.Keys) { $standaloneSnapshot[$key] = $snapshot[$key] }
    $standaloneSnapshot['Scope'] = 'project 12 story #52 | tasks: #77, #78'
    $standaloneSnapshot['Topology'] = 'standalone-story-direct-master'
    $standaloneSnapshot['Feature'] = 'none (standalone direct-to-master)'
    $standaloneSnapshot['PR'] = 'pending | base: master | head: revision-000'
    $standaloneResult = & $writer -NotePath $path -Snapshot $standaloneSnapshot
    Assert-True $standaloneResult.Changed 'standalone snapshot is writable'
    $standaloneText = [IO.File]::ReadAllText($path)
    Assert-True ($standaloneText.Contains('standalone-story-direct-master') -and $standaloneText.Contains('base: master')) 'standalone topology and direct PR base are preserved'

    & $writer -NotePath $path -Snapshot $snapshot | Out-Null

    # Reproduce accumulation, then migrate it without throwing away history.
    $legacy = "Run: synthetic-story-52`n" + ((1..40 | ForEach-Object {
        "Task #77 correction $_ : " + ('historical review findings and check transcripts; ' * 8) + "`nNext: review revision $_"
    }) -join "`n") + "`n"
    [IO.File]::WriteAllText($path, $legacy, $encoding)
    [IO.File]::Copy($path, (Join-Path $fixtureRoot 'legacy.md'))
    $first = & $writer -NotePath $path -Snapshot $snapshot
    Assert-True $first.Changed 'migration replaces accumulated note'
    Assert-True ([IO.File]::ReadAllText($path + '.previous') -ceq $legacy) 'previous accumulated note remains recoverable'
    $baselineBytes = $first.Bytes
    $baselineLines = $first.Lines

    # Exercise the real writer through repeated fixed-width revisions/cursors.
    for ($iteration = 1; $iteration -le 100; $iteration++) {
        $prior = [IO.File]::ReadAllText($path)
        $revision = 'revision-{0:D3}' -f $iteration
        $snapshot['Task state'] = "$revision | implementing"
        $snapshot['PR'] = "pending | base: codex/feature-synthetic | head: $revision"
        $snapshot['Worker cursors'] = 'implementer cursor-{0:D3} | reviewer cursor-{0:D3}' -f $iteration
        $result = & $writer -NotePath $path -Snapshot $snapshot
        Assert-True $result.Changed 'new correction replaces snapshot'
        Assert-True ($result.Bytes -eq $baselineBytes -and $result.Lines -eq $baselineLines) 'correction count does not increase current context'
        Assert-True ([IO.File]::ReadAllText($path + '.previous') -ceq $prior) 'backup is exactly one previous snapshot'
        $text = [IO.File]::ReadAllText($path)
        Assert-True (-not $text.Contains('historical review findings')) 'history is absent from routine snapshot'
        Assert-True (@($text -split "`n" | Where-Object { $_.StartsWith('Next: ') }).Count -eq 1) 'only one next action'
        foreach ($identity in @('synthetic-story-52', 'impl-id @ local', 'review-id @ local', 'automation-id', 'setup-message-ref', 'auth-synthetic-52')) {
            Assert-True ($text.Contains($identity)) "preserves $identity"
        }
    }

    # Preserve actionable uncertainty and approvals instead of truncating them.
    $snapshot['Approval'] = 'pending | PR: https://example.invalid/pr/1 | base: feature | head: revision-100 | prompt: decision-ref'
    $snapshot['Pending action'] = 'comment-operation-id | outcome: unknown | reconcile before retry'
    $snapshot['Gate'] = 'trial | user-selected trial refs required | question: trial-input-ref'
    & $writer -NotePath $path -Snapshot $snapshot | Out-Null
    $saved = [IO.File]::ReadAllText($path)
    Assert-True ($saved.Contains($snapshot['Approval']) -and $saved.Contains($snapshot['Pending action']) -and $saved.Contains($snapshot['Gate'])) 'preserves approval identity, unknown operation, and trial gate'

    # Identical observations cannot add tick history, rewrite the note, or rotate backup.
    $fixedTime = [DateTime]::SpecifyKind([DateTime]'2020-01-01', [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($path, $fixedTime)
    $previous = [IO.File]::ReadAllText($path + '.previous')
    for ($tick = 1; $tick -le 100; $tick++) {
        $result = & $writer -NotePath $path -Snapshot $snapshot
        Assert-True (-not $result.Changed) 'unchanged tick is a no-op'
    }
    Assert-True ([IO.File]::GetLastWriteTimeUtc($path) -eq $fixedTime) 'healthy observations do not rewrite snapshot'
    Assert-True ([IO.File]::ReadAllText($path) -ceq $saved) 'healthy observations do not grow snapshot'
    Assert-True ([IO.File]::ReadAllText($path + '.previous') -ceq $previous) 'healthy observations do not rotate backup'
    Assert-True ([IO.File]::ReadAllText((Join-Path $fixtureRoot 'legacy.md')) -ceq $legacy) 'historical evidence remains accessible separately'

    # The pair can advance after the coordinator's last snapshot and before a
    # scheduled resume. Reconcile that stale pointer without replaying any
    # already-confirmed worker message, Taiga write, or task advancement.
    $staleSnapshot = [ordered]@{}
    foreach ($key in $snapshot.Keys) { $staleSnapshot[$key] = $snapshot[$key] }
    $staleSnapshot['Current'] = 'story #52 | task #77'
    $staleSnapshot['Task state'] = 'revision-a1 | reviewing'
    $staleSnapshot['Review'] = 'pending'
    $staleSnapshot['Next'] = 'resume task #77 review'
    $staleSnapshot['Evidence'] = 'task-77-ready-ref | reviewer-cursor-a1'
    $staleResult = & $writer -NotePath $recoveryPath -Snapshot $staleSnapshot
    Assert-True $staleResult.Changed 'creates the stale recovery snapshot'

    $authoritative = New-AuthoritativePairState
    $derivedState = Get-AuthoritativeRecoveryState -Authoritative $authoritative
    Assert-True $derivedState.Ready 'authoritative acceptance, confirmed write, advancement, and worker state are sufficient for recovery'
    Assert-True ($staleSnapshot['Current'] -cne $derivedState.Current -and
        $staleSnapshot['Task state'] -cne $derivedState.TaskState -and
        $staleSnapshot['Evidence'] -cne $derivedState.Evidence -and
        $authoritative['ConfirmedWrites'].Count -eq 1 -and
        $authoritative['Advancements'].Count -eq 1) 'worker pair advances independently before stale snapshot recovery'

    $beforeMessages = $authoritative['Messages'].Count
    $beforeTaigaWrites = $authoritative['ConfirmedWrites'].Count
    $beforeAdvancements = $authoritative['Advancements'].Count
    $firstRecovery = Invoke-StaleSnapshotRecovery -NotePath $recoveryPath -StaleSnapshot $staleSnapshot -Authoritative $authoritative
    Assert-True $firstRecovery.SnapshotChanged 'recovery replaces the obsolete task snapshot'
    $recoveredText = [IO.File]::ReadAllText($recoveryPath)
    Assert-True ($recoveredText.Contains($derivedState.Current) -and
        $recoveredText.Contains($derivedState.TaskState) -and
        $recoveredText.Contains($derivedState.Evidence) -and
        -not $recoveredText.Contains('Current: story #52 | task #77')) 'recovery records derived authoritative task, revision, and evidence'
    Assert-True ($authoritative['Messages'].Count -eq $beforeMessages) 'recovery does not duplicate messages'
    Assert-True ($authoritative['ConfirmedWrites'].Count -eq $beforeTaigaWrites) 'recovery does not duplicate Taiga writes'
    Assert-True ($authoritative['Advancements'].Count -eq $beforeAdvancements) 'recovery does not duplicate task advancement'

    $reconciledSnapshot = Read-Snapshot -NotePath $recoveryPath
    $secondRecovery = Invoke-StaleSnapshotRecovery -NotePath $recoveryPath -StaleSnapshot $reconciledSnapshot -Authoritative $authoritative
    Assert-True (-not $secondRecovery.SnapshotChanged) 'repeated recovery of the reconciled snapshot is a no-op'
    Assert-True ($authoritative['Messages'].Count -eq $beforeMessages) 'repeated recovery keeps message count unchanged'
    Assert-True ($authoritative['ConfirmedWrites'].Count -eq $beforeTaigaWrites) 'repeated recovery keeps Taiga write count unchanged'
    Assert-True ($authoritative['Advancements'].Count -eq $beforeAdvancements) 'repeated recovery keeps advancement count unchanged'
    Assert-True (@($authoritative['Messages'] | ForEach-Object { $_.Id } | Select-Object -Unique).Count -eq $beforeMessages) 'recovery leaves message identities unique'
    Assert-True (@($authoritative['ConfirmedWrites'] | ForEach-Object { $_.OperationId } | Select-Object -Unique).Count -eq $beforeTaigaWrites) 'recovery leaves Taiga write identities unique'
    Assert-True (@($authoritative['Advancements'] | ForEach-Object { $_.EventId } | Select-Object -Unique).Count -eq $beforeAdvancements) 'recovery leaves advancement identities unique'

    $missingEvidenceState = New-AuthoritativePairState
    [void]$missingEvidenceState['ConfirmedWrites'].Clear()
    $missingEvidencePath = Join-Path $fixtureRoot 'recovery-missing.md'
    & $writer -NotePath $missingEvidencePath -Snapshot $staleSnapshot | Out-Null
    $missingBefore = [IO.File]::ReadAllText($missingEvidencePath)
    $missingMessages = $missingEvidenceState['Messages'].Count
    $missingAdvancements = $missingEvidenceState['Advancements'].Count
    $missingRecovery = Invoke-StaleSnapshotRecovery -NotePath $missingEvidencePath -StaleSnapshot $staleSnapshot -Authoritative $missingEvidenceState
    Assert-True ($missingRecovery.Held -and $missingRecovery.Reason -eq 'missing confirmed Taiga write for accepted task') 'recovery holds when authoritative evidence is missing'
    Assert-True ([IO.File]::ReadAllText($missingEvidencePath) -ceq $missingBefore) 'missing evidence does not rewrite the stale snapshot'
    Assert-True ($missingEvidenceState['Messages'].Count -eq $missingMessages -and
        $missingEvidenceState['ConfirmedWrites'].Count -eq 0 -and
        $missingEvidenceState['Advancements'].Count -eq $missingAdvancements) 'missing evidence does not replay external actions'

    $conflictingEvidenceState = New-AuthoritativePairState
    $conflictingEvidenceState['ConfirmedWrites'][0].Revision = 'revision-conflict'
    $conflictingEvidencePath = Join-Path $fixtureRoot 'recovery-conflicting.md'
    & $writer -NotePath $conflictingEvidencePath -Snapshot $staleSnapshot | Out-Null
    $conflictingBefore = [IO.File]::ReadAllText($conflictingEvidencePath)
    $conflictingMessages = $conflictingEvidenceState['Messages'].Count
    $conflictingWrites = $conflictingEvidenceState['ConfirmedWrites'].Count
    $conflictingAdvancements = $conflictingEvidenceState['Advancements'].Count
    $conflictingRecovery = Invoke-StaleSnapshotRecovery -NotePath $conflictingEvidencePath -StaleSnapshot $staleSnapshot -Authoritative $conflictingEvidenceState
    Assert-True ($conflictingRecovery.Held -and $conflictingRecovery.Reason -eq 'conflicting confirmed Taiga write for accepted revision') 'recovery holds when authoritative evidence conflicts'
    Assert-True ([IO.File]::ReadAllText($conflictingEvidencePath) -ceq $conflictingBefore) 'conflicting evidence does not rewrite the stale snapshot'
    Assert-True ($conflictingEvidenceState['Messages'].Count -eq $conflictingMessages -and
        $conflictingEvidenceState['ConfirmedWrites'].Count -eq $conflictingWrites -and
        $conflictingEvidenceState['Advancements'].Count -eq $conflictingAdvancements) 'conflicting evidence does not replay external actions'

    $missingAcceptanceState = New-AuthoritativePairState
    $missingAcceptanceState['TaskAcceptances'] = @()
    $missingAcceptancePath = Join-Path $fixtureRoot 'recovery-missing-acceptance.md'
    & $writer -NotePath $missingAcceptancePath -Snapshot $staleSnapshot | Out-Null
    $missingAcceptanceBefore = [IO.File]::ReadAllText($missingAcceptancePath)
    $missingAcceptanceRecovery = Invoke-StaleSnapshotRecovery -NotePath $missingAcceptancePath -StaleSnapshot $staleSnapshot -Authoritative $missingAcceptanceState
    Assert-True ($missingAcceptanceRecovery.Held -and $missingAcceptanceRecovery.Reason -eq 'missing confirmed task acceptance') 'empty acceptance lookup holds recovery'
    Assert-True ([IO.File]::ReadAllText($missingAcceptancePath) -ceq $missingAcceptanceBefore) 'missing acceptance does not rewrite the stale snapshot'
    Assert-True ($missingAcceptanceState['Messages'].Count -eq 2 -and
        $missingAcceptanceState['ConfirmedWrites'].Count -eq 1 -and
        $missingAcceptanceState['Advancements'].Count -eq 1) 'missing acceptance does not replay external actions'

    $unknownWriteState = New-AuthoritativePairState
    $unknownWriteState['ConfirmedWrites'][0].Outcome = 'unknown'
    $unknownWritePath = Join-Path $fixtureRoot 'recovery-unknown-write.md'
    & $writer -NotePath $unknownWritePath -Snapshot $staleSnapshot | Out-Null
    $unknownWriteBefore = [IO.File]::ReadAllText($unknownWritePath)
    $unknownWriteRecovery = Invoke-StaleSnapshotRecovery -NotePath $unknownWritePath -StaleSnapshot $staleSnapshot -Authoritative $unknownWriteState
    Assert-True ($unknownWriteRecovery.Held -and $unknownWriteRecovery.Reason -eq 'unknown Taiga write outcome') 'unknown write outcome holds recovery'
    Assert-True ([IO.File]::ReadAllText($unknownWritePath) -ceq $unknownWriteBefore) 'unknown write outcome does not rewrite the stale snapshot'
    Assert-True ($unknownWriteState['Messages'].Count -eq 2 -and
        $unknownWriteState['ConfirmedWrites'].Count -eq 1 -and
        $unknownWriteState['Advancements'].Count -eq 1) 'unknown write outcome does not replay external actions'

    $unconfirmedWorkerState = New-AuthoritativePairState
    $unconfirmedWorkerState['WorkerStates'][0].Confirmed = $false
    $unconfirmedWorkerPath = Join-Path $fixtureRoot 'recovery-unconfirmed-worker.md'
    & $writer -NotePath $unconfirmedWorkerPath -Snapshot $staleSnapshot | Out-Null
    $unconfirmedWorkerBefore = [IO.File]::ReadAllText($unconfirmedWorkerPath)
    $unconfirmedWorkerRecovery = Invoke-StaleSnapshotRecovery -NotePath $unconfirmedWorkerPath -StaleSnapshot $staleSnapshot -Authoritative $unconfirmedWorkerState
    Assert-True ($unconfirmedWorkerRecovery.Held -and $unconfirmedWorkerRecovery.Reason -eq 'missing confirmed persistent worker state') 'unconfirmed implementer lookup holds recovery'
    Assert-True ([IO.File]::ReadAllText($unconfirmedWorkerPath) -ceq $unconfirmedWorkerBefore) 'unconfirmed worker state does not rewrite the stale snapshot'
    Assert-True ($unconfirmedWorkerState['Messages'].Count -eq 2 -and
        $unconfirmedWorkerState['ConfirmedWrites'].Count -eq 1 -and
        $unconfirmedWorkerState['Advancements'].Count -eq 1) 'unconfirmed worker state does not replay external actions'

    $bad = [ordered]@{}; foreach ($key in $snapshot.Keys) { $bad[$key] = $snapshot[$key] }
    $bad['History'] = 'obsolete transcript'
    Assert-Rejected $bad 'rejects history field'
    $bad.Remove('History'); $bad.Remove('Gate')
    Assert-Rejected $bad 'rejects missing user gate'
    $bad['Gate'] = "trial`nNext: bypass approval"
    Assert-Rejected $bad 'rejects multiline append injection'
    $bad['Gate'] = 'x' * 1025
    Assert-Rejected $bad 'rejects oversized field'
    foreach ($key in $bad.Keys | ForEach-Object { $_ }) { $bad[$key] = [string]::new([char]0x754c, 1024) }
    Assert-Rejected $bad 'enforces byte bound for Unicode'
    Assert-True (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter '*.tmp').Count -eq 0) 'leaves no temporary output'

    [pscustomobject]@{
        Scenario = 'synthetic accumulated note to current snapshot'
        BeforeBytes = $encoding.GetByteCount($legacy)
        BeforeLines = @($legacy.TrimEnd("`n") -split "`n").Count
        AfterBytes = $baselineBytes
        AfterLines = $baselineLines
        Corrections = 100
        UnchangedObservations = 100
        AttributableUsage = 'unknown'
        LiveHeartbeatBehavior = 'not exercised'
    } | ConvertTo-Json
    Write-Output 'Passed snapshot replacement, setup-authorization persistence, authoritative stale-snapshot recovery, missing/conflicting evidence holds, no-duplicate external actions, no-growth, no-op, evidence preservation, gate preservation, and invalid-input checks.'
}
finally {
    # Delete only known fixture files in the exact temporary directory we created.
    foreach ($name in @('current.md', 'current.md.previous', 'recovery.md', 'recovery.md.previous', 'recovery-missing.md', 'recovery-missing.md.previous', 'recovery-conflicting.md', 'recovery-conflicting.md.previous', 'recovery-missing-acceptance.md', 'recovery-missing-acceptance.md.previous', 'recovery-unknown-write.md', 'recovery-unknown-write.md.previous', 'recovery-unconfirmed-worker.md', 'recovery-unconfirmed-worker.md.previous', 'legacy.md')) {
        $fixtureFile = Join-Path $fixtureRoot $name
        if ([IO.File]::Exists($fixtureFile)) { [IO.File]::Delete($fixtureFile) }
    }
    if ([IO.Directory]::Exists($fixtureRoot)) { [IO.Directory]::Delete($fixtureRoot, $false) }
}
