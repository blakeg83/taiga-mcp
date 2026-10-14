# Record/check telemetry at an existing authorized transition. Diagnostics never
# authorize or block implementation, review, advancement, or provider delivery.
[CmdletBinding(DefaultParameterSetName = 'Json')]
param(
    [Parameter(Mandatory)] [string] $ExternalRunRoot,
    [Parameter(Mandatory)] [string] $RunId,
    [Parameter(Mandatory, ParameterSetName = 'Json')] [string] $EventJson,
    [Parameter(Mandatory, ParameterSetName = 'File')] [string] $EventPath,
    [int[]] $TaskRefs = @(),
    [string] $MetadataPath,
    [string] $ObservedEvidencePath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$diagnostics = [Collections.Generic.List[string]]::new()
$result = [ordered]@{ status = 'unavailable'; telemetryState = 'limited'; diagnostics = @(); recorder = $null }

function Get-RecorderValidationDiagnostic {
    param([AllowNull()] [object[]] $Output)

    $knownMessages = [ordered]@{
        "'occurredAtUtc' must be an ISO 8601 UTC timestamp ending in Z" = 'occurredAtUtc must be an ISO 8601 UTC timestamp ending in Z'
        'correctionId is allowed only on correction events' = 'correctionId is allowed only on correction events'
    }
    $knownFieldPattern = '(?:schemaVersion|kind|eventId|runId|projectId|storyId|storyRef|taskRef|role|sessionId|workerId|transitionId|scope|phaseId|correctionId|reviewRequestId|reviewAttemptId|reviewKind|reviewAttemptOrdinal|supersedesReviewAttemptId|eventType|occurredAtUtc|revision|reviewMode|provenance|usage|waitId|waitKind|pullRequest|usage\.streamId|usage\.role|usage\.sampledAtUtc|usage\.baselineAtUtc|usage\.counterSemantics\.cachedInput|usage\.counterSemantics\.reasoning|provenance\.observedBy|provenance\.observer|provenance\.source|provenance\.coverage|provenance\.synthetic|pullRequest\.owner|pullRequest\.repository|pullRequest\.number|pullRequest\.reviewedHead)'
    $knownFieldReasonPattern = '(?:must be a JSON object|is required|must be a nonblank safe string|must be a positive integer|must be a nonnegative integer|has an unsupported value|must be an ISO 8601 UTC timestamp ending in Z|must be a full Git SHA|must be a full Git SHA or null|must be an absolute path|is not a valid path|must be a Boolean|is allowed only on review events|is allowed only on correction events)'
    $knownStaticMessages = @(
        'external run root must be outside the source worktree',
        "'pullRequest.reviewedHead' must be a full Git SHA",
        "'provenance.observedBy' or 'provenance.observer' is required",
        'usage.role must match event role',
        'numeric usage samples require counterSemantics',
        'numeric usage samples require usage.counterSemantics.cachedInput',
        'numeric usage samples require usage.counterSemantics.reasoning',
        'measured usage requires nonempty counters',
        'measured usage requires known counter semantics',
        "'revision' must be a full Git SHA or null",
        'supersedesReviewAttemptId is only valid on correction events',
        'task-scoped events require a positive taskRef',
        'story-scoped events require taskRef to be null',
        'wait boundary events require phaseId to be null',
        'wait boundary events require revision to be null',
        'wait identity fields are allowed only on wait boundary events',
        'story_started requires story scope and coordinator role',
        'story_started requires null phaseId and revision',
        'pr_ready requires story scope and coordinator role',
        'pr_ready requires null phaseId and a full revision',
        'pullRequest.reviewedHead must match event revision',
        'pullRequest is allowed only on pr_ready',
        'implementation_started requires task scope, implementer role and phaseId',
        'task_ready_for_review requires task scope, implementer role, phaseId and full revision',
        'review events require review scope, reviewer role and phaseId',
        'task review events require an initial_task or correction_rereview kind',
        'final-story review events require a final-story review kind',
        'final review events require final_story scope',
        'correction events require correction scope, implementer role, phaseId, correctionId and supersedesReviewAttemptId',
        'correction_started requires a null revision',
        'correction_ready requires a full revision',
        'final-story correction events require taskRef to be null',
        'event runId does not match the selected external run',
        'event story binding does not match the selected external run',
        "'runId' must be a path-safe stable identifier"
    )
    foreach ($item in @($Output)) {
        $message = if ($item -is [System.Management.Automation.ErrorRecord] -and $null -ne $item.Exception) {
            [string] $item.Exception.Message
        }
        else {
            [string] $item
        }
        $candidate = $null
        if ($message -match '(?m)^\s*\|\s*(?<candidate>[^\r\n]{1,240})\s*$') {
            $candidate = $matches['candidate'].Trim()
        }
        foreach ($knownMessage in $knownMessages.Keys) {
            if ($message.IndexOf($knownMessage, [StringComparison]::Ordinal) -ge 0) {
                return "recorder_validation_rejected: $($knownMessages[$knownMessage])"
            }
        }
        if ($candidate -and $candidate -match "^'(?<field>$knownFieldPattern)' $knownFieldReasonPattern$") {
            return "recorder_validation_rejected: $candidate"
        }
        if ($candidate -and $candidate -match "^'[A-Za-z][A-Za-z0-9_.]{0,96}' is not an allowlisted field$") {
            return 'recorder_validation_rejected: event contains a non-allowlisted field'
        }
        if ($candidate -and $candidate -in $knownStaticMessages) {
            return "recorder_validation_rejected: $candidate"
        }
    }
    return $null
}

function Get-RecorderFailureDiagnostic {
    param(
        [AllowNull()] [object[]] $Output,
        [Parameter(Mandatory)] [int] $ExitCode
    )

    $validationDiagnostic = Get-RecorderValidationDiagnostic -Output $Output
    if ($validationDiagnostic) { return $validationDiagnostic }
    return "recorder_execution_failed: recorder exited with code $ExitCode; validation reason unavailable"
}

function Get-TransitionFailureDiagnostic {
    param([Parameter(Mandatory)] [string] $Message)

    if ($Message -match '^input_invalid:') { return 'input_invalid: event JSON could not be parsed' }
    if ($Message -match '^input_unavailable:') { return 'input_unavailable: event input could not be read' }
    if ($Message -match '^recorder_validation_rejected:') { return $Message }
    if ($Message -match '^recorder_unavailable:') { return 'recorder_unavailable: pwsh executable is unavailable' }
    if ($Message -match '^recorder_execution_failed:') {
        if ($Message -match 'process could not be started') { return 'recorder_execution_failed: recorder process could not be started' }
        if ($Message -match 'exited with code -?\d{1,10}; validation reason unavailable') { return $Message }
    }
    return 'recorder_execution_failed: transition recording failed; diagnostic detail unavailable'
}

try {
    if ($EventPath) {
        try { $EventJson = Get-Content -LiteralPath $EventPath -Raw }
        catch { throw 'input_unavailable: event input could not be read' }
    }
    try { $event = $EventJson | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw 'input_invalid: event JSON could not be parsed' }
    $recorder = Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1'
    if ($null -eq (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        throw 'recorder_unavailable: pwsh executable is unavailable'
    }
    try {
        $output = @(& pwsh -NoProfile -File $recorder -ExternalRunRoot $ExternalRunRoot -RunId $RunId -EventJson $EventJson 2>&1)
    }
    catch {
        throw 'recorder_execution_failed: recorder process could not be started'
    }
    if ($LASTEXITCODE -ne 0) {
        throw (Get-RecorderFailureDiagnostic -Output $output -ExitCode $LASTEXITCODE)
    }
    $result.recorder = ($output -join "`n") | ConvertFrom-Json
    $result.status = $result.recorder.status
    if ($result.status -notin @('appended', 'noop')) { throw 'recording outcome is unconfirmed; reconcile telemetry without blocking workflow' }
    $records = @(Get-Content -LiteralPath $result.recorder.ledgerPath | ForEach-Object {
        $item = $_ | ConvertFrom-Json -Depth 100 -DateKind String
        if ($item.kind -ceq 'story_performance_event_frame') { $item.event } else { $item }
    })
    $starts = @($records | Where-Object eventType -eq 'story_started')
    if ($starts.Count -ne 1) { $diagnostics.Add('story initialization boundary is missing or ambiguous') }
    if ([string]::IsNullOrWhiteSpace($event.workerId) -or [string]::IsNullOrWhiteSpace($event.sessionId)) {
        $diagnostics.Add('worker/session identity is unavailable; thread IDs must not be assumed to be local session IDs')
    }
    $pairs = @{ task_ready_for_review = 'implementation_started'; correction_ready = 'correction_started'; review_findings = 'review_started'; review_accepted = 'review_started'; final_review_accepted = 'final_review_started'; wait_ended = 'wait_started' }
    if ($pairs.ContainsKey($event.eventType)) {
        $candidates = @($records | Where-Object {
            $_.eventType -eq $pairs[$event.eventType] -and $_.scope -ceq $event.scope -and $_.taskRef -eq $event.taskRef -and
            $_.phaseId -ceq $event.phaseId -and $_.correctionId -ceq $event.correctionId -and
            $_.reviewRequestId -ceq $event.reviewRequestId -and $_.reviewAttemptId -ceq $event.reviewAttemptId -and
            $_.reviewKind -ceq $event.reviewKind -and $_.reviewAttemptOrdinal -eq $event.reviewAttemptOrdinal -and
            $_.supersedesReviewAttemptId -ceq $event.supersedesReviewAttemptId -and $_.waitId -ceq $event.waitId -and $_.waitKind -ceq $event.waitKind
        })
        if ($candidates.Count -ne 1) { $diagnostics.Add("missing/ambiguous matching $($pairs[$event.eventType]) boundary for $($event.eventId)") }
        elseif ([DateTimeOffset]::Parse($candidates[0].occurredAtUtc) -gt [DateTimeOffset]::Parse($event.occurredAtUtc) -or
            $candidates[0].workerId -cne $event.workerId -or $candidates[0].sessionId -cne $event.sessionId -or
            ($event.eventType -in @('review_findings', 'review_accepted', 'final_review_accepted') -and $candidates[0].revision -cne $event.revision)) {
            $diagnostics.Add('boundary time, worker/session attribution, or reviewed revision conflicts')
        }
    }
    if ($event.eventType -in @('correction_started', 'correction_ready')) {
        $findings = @($records | Where-Object { $_.eventType -eq 'review_findings' -and $_.reviewAttemptId -ceq $event.supersedesReviewAttemptId -and $_.scope -ceq $event.scope -and $_.taskRef -eq $event.taskRef })
        if ($findings.Count -ne 1) { $diagnostics.Add('correction supersedesReviewAttemptId lacks one attributable review-findings closure') }
    }
    if ($event.eventType -in @('implementation_started', 'final_review_started')) {
        $required = @($TaskRefs)
        if ($event.eventType -eq 'implementation_started') {
            $index = [Array]::IndexOf([int[]] $TaskRefs, [int] $event.taskRef)
            $required = if ($index -gt 0) { @($TaskRefs[0..($index - 1)]) } else { @() }
        }
        foreach ($taskRef in $required) {
            if (@($records | Where-Object { $_.eventType -eq 'task_ready_for_review' -and $_.taskRef -eq $taskRef }).Count -eq 0) { $diagnostics.Add("task #$taskRef implementation-end evidence is missing at advancement/final review") }
            if ($event.reviewMode -eq 'per_task' -and @($records | Where-Object { $_.eventType -eq 'review_accepted' -and $_.taskRef -eq $taskRef }).Count -eq 0) { $diagnostics.Add("task #$taskRef acceptance evidence is missing at advancement/final review") }
        }
    }
    if ($event.eventType -eq 'story_started') {
        # Validate profiles with the same validator used by production reports.
        $parameters = @{ EventsPath = $result.recorder.ledgerPath; TaskRefs = $TaskRefs }
        if ($MetadataPath) { $parameters.MetadataPath = $MetadataPath }
        $setupReport = (& (Join-Path $PSScriptRoot 'get-story-performance.ps1') @parameters) | ConvertFrom-Json -Depth 100
        if ($setupReport.metrics.modelsAndReasoning.state -ne 'measured') { $diagnostics.Add('validated role/model/reasoning setup coverage is unavailable or partial') }
        if (-not $ObservedEvidencePath) { $ObservedEvidencePath = Join-Path (Join-Path $ExternalRunRoot $RunId) 'observed-role-token-usage.json' }
        if (-not (Test-Path -LiteralPath $ObservedEvidencePath -PathType Leaf)) { $diagnostics.Add('observed role/session/source binding file is unavailable; collection cannot yet be attributed') }
        else {
            $evidence = Get-Content -LiteralPath $ObservedEvidencePath -Raw | ConvertFrom-Json -Depth 100
            foreach ($role in @('coordinator', 'implementer', 'reviewer')) {
                $rows = @($evidence.rows | Where-Object role -eq $role)
                if ($rows.Count -eq 0) { $diagnostics.Add("$role local session binding unavailable") }
                foreach ($row in $rows) {
                    $profiles = @($setupReport.metrics.modelsAndReasoning.value | Where-Object { $_.role -eq $role -and $_.sessionId -ceq $row.sessionId })
                    if ($profiles.Count -eq 0) { $diagnostics.Add("$role local source binding lacks matching validated setup profile") }
                    if ([string]::IsNullOrWhiteSpace($row.sessionId) -or -not (Test-Path -LiteralPath $row.sourcePath -PathType Leaf)) { $diagnostics.Add("$role selected session source unavailable"); continue }
                    # Inspect only bounded first-line identity metadata, not transcript content.
                    $reader = [IO.StreamReader]::new($row.sourcePath)
                    try {
                        $chars = [Collections.Generic.List[char]]::new()
                        while ($chars.Count -lt 65536 -and ($value = $reader.Read()) -ge 0 -and $value -ne 10) { $chars.Add([char] $value) }
                        if ($chars.Count -ge 65536) { throw 'session metadata header exceeds bound' }
                        $header = (-join $chars) | ConvertFrom-Json -Depth 20
                        if ($header.type -cne 'session_meta' -or $header.payload.id -cne $row.sessionId) { $diagnostics.Add("$role local session_meta identity does not match binding") }
                    }
                    catch { $diagnostics.Add("$role selected local session source could not be verified") }
                    finally { $reader.Dispose() }
                }
            }
        }
    }
    $result.telemetryState = if ($diagnostics.Count -eq 0) { 'verified' } else { 'limited' }
}
catch { $diagnostics.Add((Get-TransitionFailureDiagnostic -Message ([string] $_.Exception.Message))) }
$result.diagnostics = @($diagnostics)
$result | ConvertTo-Json -Depth 100
