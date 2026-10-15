# Portable telemetry calls

Copy the entire `taiga-story-loop/` folder to `~/.codex/skills/taiga-story-loop/`.
Runtime telemetry requires PowerShell 7.5+ (`pwsh`, including `ConvertFrom-Json
-DateKind String`), Git, and writable external run/artifact directories. The
existing Taiga, GitHub, and worker-chat capabilities remain workflow prerequisites.
Local attributable token counters are optional; absent sources remain unavailable.
No clone of the original Taiga MCP repository is needed.

All `scripts/` paths in telemetry instructions are relative to this installed
skill folder, never to the target repository or current working directory.
Resolve the absolute folder containing the loaded `SKILL.md` once as `$skillRoot`
(the source-tree skill folder is also supported). Pass that absolute path and the
existing run pointer to workers. Do not search the target project for these files.

## Coordinator initialization and worker transitions

Load the constructor and UTC formatter from the installed folder. After the
authorized Start boundary, construct and submit a real event, not a call with
only `ExternalRunRoot` and `RunId`. Variables below come from resolved scope and
the actual boundary; they are not literal fixture values.

```powershell
. (Join-Path $skillRoot 'scripts/new-story-performance-event.ps1')
. (Join-Path $skillRoot 'scripts/format-story-performance-utc.ps1')
$boundaryUtc = Format-StoryPerformanceUtcTimestamp -Timestamp ([DateTimeOffset]::UtcNow)
$event = New-StoryPerformanceEvent -EventId "$runId/story-started" `
    -EventType story_started -OccurredAtUtc $boundaryUtc `
    -ProjectId $projectId -StoryId $storyId -StoryRef $storyRef -RunId $runId `
    -Scope story -Role coordinator -ReviewMode $reviewMode `
    -WorkerId $coordinatorWorkerId -SessionId $coordinatorSessionId `
    -Provenance ([ordered]@{ source = 'workflow_transition'; observedBy = 'coordinator'; coverage = 'authorized story start'; synthetic = $false })
$eventJson = $event | ConvertTo-Json -Depth 100 -Compress
$result = & (Join-Path $skillRoot 'scripts/record-story-performance-transition.ps1') `
    -ExternalRunRoot $externalRunRoot -RunId $runId -EventJson $eventJson `
    -TaskRefs $taskRefs
```

Immediately after creating the worker pair, call the installed
`scripts/initialize-story-performance-roles.ps1` with `ExternalRunRoot`, `RunId`,
`ProjectId`, `StoryId`, and `Profiles` (the three actual assignment objects).
Each profile supplies `role`, `workerId`, nullable `sessionId`, `model`, `effort`,
and the actual `effectiveFromUtc`. Include the coordinator. This helper creates
and validates `setup-metadata.json` with provenance and generates
`observed-role-token-usage.json`; do not hand-author either JSON file. Pass the
same `Scope` to initialization and finalization if using a custom story scope.
Missing sources produce diagnostics and do not block the workflow.

Discovery uses known session IDs (or worker IDs as candidates), narrows filenames
under `CODEX_HOME/sessions` and `CODEX_HOME/archived_sessions` (default `~/.codex`),
and verifies the bounded `session_meta` header. A unique embedded identity match
is required. Finalization retries discovery using saved profiles, or recorded
worker identities when setup is unavailable. It automatically loads the default
setup metadata path. An explicit binding file remains supported.

Pass validated `-MetadataPath` and `-ObservedEvidencePath` when available.
A worker chat ID is only a candidate local session ID until the embedded
`session_meta.payload.id` verifies it; unresolved identities stay unavailable. Supply explicit truthful provenance on every constructed event;
synthetic tests must explicitly supply synthetic provenance.

Workers use the same constructor/serialization/recorder sequence at actual
boundaries, changing these type-specific inputs:

| Boundary | Required constructor inputs beyond the common run/story/time fields |
| --- | --- |
| `implementation_started` | `Scope task`, `Role implementer`, `TaskRef`, stable `PhaseId`; null revision |
| `task_ready_for_review` | Same implementation identity, full frozen `Revision` |
| `review_started`, `review_findings`, `review_accepted` | `Scope task`, `Role reviewer`, `TaskRef`, `PhaseId`, `ReviewRequestId`, `ReviewAttemptId`, `ReviewKind`, `ReviewAttemptOrdinal`, full `Revision` |
| `final_review_started`, `final_review_accepted` or final findings | `Scope final_story`, `Role reviewer`, null task ref, full review identity and revision |
| `correction_started`, `correction_ready` | `Role implementer`, task/final-story scope, `PhaseId`, `CorrectionId`, `SupersedesReviewAttemptId`; full revision only at ready |

Supply actual worker/session identities and the selected review mode on each
event. Reuse start identities on matching ends and reuse the same event payload
on reconciliation; never generate replacement timestamps or token estimates.
The constructor keeps review fields null on corrections and correction fields
null on reviews. Serialize the constructed event to `-EventJson`, or persist it
and pass `-EventPath`; one of those inputs is mandatory on every recorder call.
Disclose recording diagnostics without blocking normal work.

## Confirmed PR finalization

Persist the actual confirmed provider delivery object including its exact
preflight `receipt` as JSON. The receipt and provider record fields are defined
in [PR delivery](pr-delivery.md); do not synthesize confirmation from a proposed
PR, worker report, or local branch. Then pass every mandatory argument:

```powershell
$parameters = @{
    DeliveryPath = $confirmedDeliveryPath
    ExternalRunRoot = $externalRunRoot
    RunId = $runId
    ArtifactRoot = $artifactRoot
    BaseRevision = $capturedReviewBaseSha
    RepositoryPath = $targetRepositoryPath
    ReviewMode = $reviewMode
    TaskRefs = $taskRefs
}
# Add MetadataPath, ObservedEvidencePath, TaskOutcomePath when available.
# Add ArtifactsAccessibleToUser = $true only for paths the user can reach.
$finalization = & (Join-Path $skillRoot 'scripts/finalize-story-performance.ps1') @parameters
```

The finalizer records the real `pr_ready` timestamp by default and derives the
reviewed HEAD from confirmed delivery. Preserve its returned response, artifact
references, coverage, and limitations in normal delivery. A failed measurement
does not undo confirmed delivery. Repository-root compatibility scripts are for
development callers only; portable execution uses the installed entry points.

## Counter coverage

The collector keeps verified counter samples, not transcript text. The reporter
re-reads declared sources through the collector before accepting phase samples;
agent-supplied event or metadata numbers do not establish numeric authority.
Initial implementation, corrections, task reviews, re-reviews, final reviews,
and explicit coordinator intervals use their existing paired phase identities.
Each phase uses its first and last samples **inside** the phase. Asynchronous
samples produce a partial inner-window delta with actual sampling times, never
an interpolated exact measurement. Fewer than two samples or a counter reset
leave the phase unavailable. Partial metric `knownSubtotal` is the covered
subtotal; unmeasured activity remains unknown. Cached input and reasoning are
components of input and output, respectively, and are never added again.

Reuse the original event ID and timestamp when reconciling a boundary. The
transition helper rejects a second implementation/correction boundary for the
same phase and a completion without a matching start before appending. Use a
distinct phase/correction ID for each correction. Record real coordinator wait
starts/ends; gaps are never reconstructed from elapsed story time.
