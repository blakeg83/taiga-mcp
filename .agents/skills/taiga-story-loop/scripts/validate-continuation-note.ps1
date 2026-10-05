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

function Invoke-StaleSnapshotRecovery {
    param(
        [Parameter(Mandatory)] [string] $NotePath,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $StaleSnapshot,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Authoritative
    )

    $isStale = $StaleSnapshot['Current'] -cne $Authoritative['Current'] -or
        $StaleSnapshot['Task state'] -cne $Authoritative['Task state']
    if (-not $isStale) {
        return [pscustomobject]@{
            SnapshotChanged = $false
            Messages = $Authoritative['Messages'].Count
            TaigaWrites = $Authoritative['TaigaWrites'].Count
            Advancements = $Authoritative['Advancements'].Count
        }
    }

    # Recovery only replaces the stale pointer. The pair's confirmed messages,
    # Taiga writes, and task advancement are already authoritative and must not
    # be replayed while the coordinator refreshes its note.
    $refreshedSnapshot = [ordered]@{}
    foreach ($key in $StaleSnapshot.Keys) { $refreshedSnapshot[$key] = $StaleSnapshot[$key] }
    $refreshedSnapshot['Current'] = $Authoritative['Current']
    $refreshedSnapshot['Task state'] = $Authoritative['Task state']
    $refreshedSnapshot['Review'] = 'pending'
    $refreshedSnapshot['Next'] = $Authoritative['Next']
    $refreshedSnapshot['Evidence'] = $Authoritative['Evidence']
    $writeResult = & $writer -NotePath $NotePath -Snapshot $refreshedSnapshot

    [pscustomobject]@{
        SnapshotChanged = [bool]$writeResult.Changed
        Messages = $Authoritative['Messages'].Count
        TaigaWrites = $Authoritative['TaigaWrites'].Count
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
        foreach ($identity in @('synthetic-story-52', 'impl-id @ local', 'review-id @ local', 'automation-id', 'setup-message-ref')) {
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

    $authoritative = [ordered]@{
        Current = 'story #52 | task #78'
        'Task state' = 'revision-b1 | implementing'
        Next = 'send task #78 ready-for-review to reviewer'
        Evidence = 'task-77-accepted-ref | task-78-started-ref | reviewer-cursor-b1'
        Messages = [System.Collections.Generic.List[object]]::new()
        TaigaWrites = [System.Collections.Generic.List[object]]::new()
        Advancements = [System.Collections.Generic.List[object]]::new()
    }
    [void]$authoritative['Messages'].Add([pscustomobject]@{ Id = 'ready-task-77'; Route = 'implementer-to-reviewer' })
    [void]$authoritative['Messages'].Add([pscustomobject]@{ Id = 'accepted-task-77-revision-a2'; Route = 'reviewer-to-implementer' })
    [void]$authoritative['TaigaWrites'].Add([pscustomobject]@{ Id = 'task-77-accepted-revision-a2'; Kind = 'task-status' })
    [void]$authoritative['Advancements'].Add([pscustomobject]@{ Id = 'advance-task-78'; Kind = 'next-declared-task' })
    Assert-True ($staleSnapshot['Current'] -cne $authoritative['Current'] -and
        $authoritative['TaigaWrites'].Count -eq 1 -and
        $authoritative['Advancements'].Count -eq 1) 'worker pair advances independently before stale snapshot recovery'

    $beforeMessages = $authoritative['Messages'].Count
    $beforeTaigaWrites = $authoritative['TaigaWrites'].Count
    $beforeAdvancements = $authoritative['Advancements'].Count
    $firstRecovery = Invoke-StaleSnapshotRecovery -NotePath $recoveryPath -StaleSnapshot $staleSnapshot -Authoritative $authoritative
    Assert-True $firstRecovery.SnapshotChanged 'recovery replaces the obsolete task snapshot'
    $recoveredText = [IO.File]::ReadAllText($recoveryPath)
    Assert-True ($recoveredText.Contains('Current: story #52 | task #78') -and
        $recoveredText.Contains('Task state: revision-b1 | implementing') -and
        -not $recoveredText.Contains('Current: story #52 | task #77')) 'recovery records the authoritative current task and revision'
    Assert-True ($authoritative['Messages'].Count -eq $beforeMessages) 'recovery does not duplicate messages'
    Assert-True ($authoritative['TaigaWrites'].Count -eq $beforeTaigaWrites) 'recovery does not duplicate Taiga writes'
    Assert-True ($authoritative['Advancements'].Count -eq $beforeAdvancements) 'recovery does not duplicate task advancement'

    $reconciledSnapshot = [ordered]@{}
    foreach ($key in $staleSnapshot.Keys) { $reconciledSnapshot[$key] = $staleSnapshot[$key] }
    $reconciledSnapshot['Current'] = $authoritative['Current']
    $reconciledSnapshot['Task state'] = $authoritative['Task state']
    $reconciledSnapshot['Review'] = 'pending'
    $reconciledSnapshot['Next'] = $authoritative['Next']
    $reconciledSnapshot['Evidence'] = $authoritative['Evidence']
    $secondRecovery = Invoke-StaleSnapshotRecovery -NotePath $recoveryPath -StaleSnapshot $reconciledSnapshot -Authoritative $authoritative
    Assert-True (-not $secondRecovery.SnapshotChanged) 'repeated recovery of the reconciled snapshot is a no-op'
    Assert-True ($authoritative['Messages'].Count -eq $beforeMessages) 'repeated recovery keeps message count unchanged'
    Assert-True ($authoritative['TaigaWrites'].Count -eq $beforeTaigaWrites) 'repeated recovery keeps Taiga write count unchanged'
    Assert-True ($authoritative['Advancements'].Count -eq $beforeAdvancements) 'repeated recovery keeps advancement count unchanged'
    Assert-True (@($authoritative['Messages'] | ForEach-Object { $_.Id } | Select-Object -Unique).Count -eq $beforeMessages) 'recovery leaves message identities unique'
    Assert-True (@($authoritative['TaigaWrites'] | ForEach-Object { $_.Id } | Select-Object -Unique).Count -eq $beforeTaigaWrites) 'recovery leaves Taiga write identities unique'
    Assert-True (@($authoritative['Advancements'] | ForEach-Object { $_.Id } | Select-Object -Unique).Count -eq $beforeAdvancements) 'recovery leaves advancement identities unique'

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
    Write-Output 'Passed snapshot replacement, stale-snapshot recovery, no-duplicate external actions, no-growth, no-op, evidence preservation, gate preservation, and invalid-input checks.'
}
finally {
    # Delete only known fixture files in the exact temporary directory we created.
    foreach ($name in @('current.md', 'current.md.previous', 'recovery.md', 'recovery.md.previous', 'legacy.md')) {
        $fixtureFile = Join-Path $fixtureRoot $name
        if ([IO.File]::Exists($fixtureFile)) { [IO.File]::Delete($fixtureFile) }
    }
    if ([IO.Directory]::Exists($fixtureRoot)) { [IO.Directory]::Delete($fixtureRoot, $false) }
}
