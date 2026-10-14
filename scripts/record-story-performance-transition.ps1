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
    foreach ($item in @($Output)) {
        $message = if ($item -is [System.Management.Automation.ErrorRecord] -and $null -ne $item.Exception) {
            [string] $item.Exception.Message
        }
        else {
            [string] $item
        }
        foreach ($knownMessage in $knownMessages.Keys) {
            if ($message.IndexOf($knownMessage, [StringComparison]::Ordinal) -ge 0) {
                return "recorder_validation_rejected: $($knownMessages[$knownMessage])"
            }
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

try {
    if ($EventPath) { $EventJson = Get-Content -LiteralPath $EventPath -Raw }
    $event = $EventJson | ConvertFrom-Json -Depth 100 -DateKind String
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
catch { $diagnostics.Add($_.Exception.Message) }
$result.diagnostics = @($diagnostics)
$result | ConvertTo-Json -Depth 100
