# OFFLINE SETUP-AUTHORIZATION DECISION FIXTURE.
# This fixture models the setup gate without opening a UI or mutating a provider.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SetupState {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Scope,
        [Parameter(Mandatory)] [bool] $SupportsSelectableAuthorization,
        [Parameter(Mandatory)] [bool] $PermitsAuthorization,
        [Parameter(Mandatory)] [bool] $HasExplicitSubmissionEvidence,
        [Parameter(Mandatory)] [string] $CapabilitySource,
        [Parameter(Mandatory)] [string] $CapabilityContext,
        [Parameter(Mandatory)] [string] $SubmissionEvidence
    )

    $mode = if ($SupportsSelectableAuthorization -and
        $PermitsAuthorization -and $HasExplicitSubmissionEvidence) {
        'selectable'
    } else {
        'plain-text'
    }

    [pscustomobject]@{
        Name = $Name
        Scope = $Scope
        Mode = $mode
        Capability = [pscustomobject]@{
            Source = $CapabilitySource
            Context = $CapabilityContext
            SupportsSelectableAuthorization = $SupportsSelectableAuthorization
            PermitsAuthorization = $PermitsAuthorization
            HasExplicitSubmissionEvidence = $HasExplicitSubmissionEvidence
            SubmissionEvidence = $SubmissionEvidence
        }
        GateId = $null
        GateRevision = 0
        GateLifecycle = 'unrendered'
        GateRenderCount = 0
        GateReplacementCount = 0
        ActiveGateCount = 0
        Actions = [System.Collections.Generic.List[object]]::new()
        BlockedMutationAttempts = [System.Collections.Generic.List[object]]::new()
        ExternalMutations = [System.Collections.Generic.List[object]]::new()
        Authorization = $null
        Outcome = 'awaiting_confirmation'
    }
}

function Add-Action {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter(Mandatory)] [string] $Kind,
        [Parameter(Mandatory)] [string] $Outcome,
        [Parameter(Mandatory)] [hashtable] $Details
    )

    $record = [ordered]@{ Kind = $Kind; Outcome = $Outcome }
    foreach ($key in $Details.Keys) { $record[$key] = $Details[$key] }
    [void]$State.Actions.Add([pscustomobject]$record)
}

function Render-SetupGate {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    if ($State.GateLifecycle -eq 'open') {
        throw "$($State.Name): attempted to render a second active setup gate."
    }

    $State.GateRevision++
    $State.GateId = "gate-$($State.Name)-$($State.GateRevision)"
    $State.GateLifecycle = 'open'
    $State.GateRenderCount++
    $State.ActiveGateCount = 1
    Add-Action $State 'setup_gate_rendered' 'recorded' @{
        GateId = $State.GateId
        GateRevision = $State.GateRevision
        Scope = $State.Scope
        Choices = 'Start,Cancel'
        Default = 'none'
    }
}

function Invoke-Discovery {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Add-Action $State 'discovery' 'read_only' @{
        GateId = $State.GateId
        Scope = $State.Scope
    }
}

function Invoke-ExternalMutation {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter(Mandatory)] [string] $Operation
    )

    if ($State.Outcome -eq 'started') {
        $mutation = [pscustomobject]@{
            Operation = $Operation
            Scope = $State.Scope
            AuthorizationReference = $State.Authorization.Reference
        }
        [void]$State.ExternalMutations.Add($mutation)
        Add-Action $State 'external_mutation' 'applied' @{
            Operation = $Operation
            Scope = $State.Scope
            AuthorizationReference = $State.Authorization.Reference
            Phase = 'post-confirmation'
            Applied = $true
        }
        return $true
    }

    $blocked = [pscustomobject]@{
        Operation = $Operation
        Scope = $State.Scope
        Applied = $false
    }
    [void]$State.BlockedMutationAttempts.Add($blocked)
    Add-Action $State 'external_mutation' 'blocked_before_confirmation' @{
        Operation = $Operation
        Scope = $State.Scope
        Phase = 'pre-confirmation'
        Applied = $false
    }
    $false
}

function Prepare-Setup {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Render-SetupGate $State
    Invoke-Discovery $State
    Invoke-ExternalMutation $State 'create-worker-or-branch' | Out-Null
}

function New-SetupEvent {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter(Mandatory)] [string] $Kind,
        [AllowNull()] [string] $Choice,
        [AllowNull()] [string] $Text,
        [Parameter(Mandatory)] [bool] $Submitted,
        [AllowNull()] [string] $AuthorizationReference
    )

    [pscustomobject]@{
        Kind = $Kind
        Choice = $Choice
        Text = $Text
        Submitted = $Submitted
        AuthorizationReference = $AuthorizationReference
        GateId = $State.GateId
        GateRevision = $State.GateRevision
        Scope = $State.Scope
    }
}

function Resolve-SetupEvent {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter(Mandatory)] [pscustomobject] $Event
    )

    if ($Event.Kind -eq 'scope_changed') {
        if ([string]::IsNullOrWhiteSpace($Event.Scope)) {
            throw 'A scope change must carry the replacement resolved scope.'
        }

        $oldGateId = $State.GateId
        Add-Action $State 'setup_gate_replaced' 'invalidated' @{
            GateId = $oldGateId
            GateRevision = $State.GateRevision
            Scope = $State.Scope
        }
        $State.GateLifecycle = 'replaced'
        $State.ActiveGateCount = 0
        $State.GateReplacementCount++
        $State.Scope = $Event.Scope
        $State.Authorization = $null
        $State.Outcome = 'awaiting_confirmation'
        Render-SetupGate $State
        Invoke-Discovery $State
        Invoke-ExternalMutation $State 'create-worker-or-branch' | Out-Null
        return $State
    }

    $bindingMatches = $Event.GateId -eq $State.GateId -and
        $Event.GateRevision -eq $State.GateRevision -and
        $Event.Scope -eq $State.Scope
    if (-not $bindingMatches -or $State.GateLifecycle -ne 'open') {
        Add-Action $State 'decision_event' 'rejected_stale_or_closed_gate' @{
            EventGateId = $Event.GateId
            EventGateRevision = $Event.GateRevision
            EventScope = $Event.Scope
            ActiveGateId = $State.GateId
            ActiveGateRevision = $State.GateRevision
            ActiveScope = $State.Scope
        }
        return $State
    }

    if ($State.Mode -eq 'selectable') {
        if ($Event.Kind -ne 'submitted_choice' -or
            $Event.Choice -notin @('Start', 'Cancel') -or
            -not $Event.Submitted) {
            $State.Outcome = 'awaiting_confirmation'
            Add-Action $State 'decision_event' 'rejected_not_submitted' @{
                GateId = $State.GateId
                GateRevision = $State.GateRevision
            }
            return $State
        }

        $decision = $Event.Choice
    } else {
        if ($Event.Kind -ne 'typed_reply' -or
            [string]::IsNullOrWhiteSpace($Event.Text)) {
            $State.Outcome = 'awaiting_confirmation'
            Add-Action $State 'decision_event' 'rejected_blank_or_wrong_channel' @{
                GateId = $State.GateId
                GateRevision = $State.GateRevision
            }
            return $State
        }

        $decision = $Event.Text.Trim()
        if ($decision -notin @('Start', 'Cancel')) {
            $State.Outcome = 'awaiting_confirmation'
            Add-Action $State 'decision_event' 'rejected_invalid_text' @{
                GateId = $State.GateId
                GateRevision = $State.GateRevision
            }
            return $State
        }
    }

    if ($decision -eq 'Cancel') {
        $State.Authorization = $null
        $State.Outcome = 'cancelled'
        $State.GateLifecycle = 'closed'
        $State.ActiveGateCount = 0
        Add-Action $State 'decision_event' 'accepted_cancel' @{
            GateId = $State.GateId
            GateRevision = $State.GateRevision
        }
        return $State
    }

    if ([string]::IsNullOrWhiteSpace($Event.AuthorizationReference)) {
        throw 'A submitted Start decision must include a resolved authorization reference.'
    }

    $State.Authorization = [pscustomobject]@{
        Decision = 'start'
        Mode = $State.Mode
        Scope = $State.Scope
        Reference = $Event.AuthorizationReference
        Submitted = $true
        GateId = $State.GateId
        GateRevision = $State.GateRevision
    }
    $State.Outcome = 'started'
    $State.GateLifecycle = 'closed'
    $State.ActiveGateCount = 0
    Add-Action $State 'decision_event' 'accepted_start' @{
        GateId = $State.GateId
        GateRevision = $State.GateRevision
        AuthorizationReference = $Event.AuthorizationReference
    }
    return $State
}

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-CapabilityRecord {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-True (-not [string]::IsNullOrWhiteSpace($State.Capability.Source)) "$($State.Name): capability source is missing."
    Assert-True (-not [string]::IsNullOrWhiteSpace($State.Capability.Context)) "$($State.Name): capability context is missing."
    Assert-True (-not [string]::IsNullOrWhiteSpace($State.Capability.SubmissionEvidence)) "$($State.Name): submission evidence is missing."
    $expectedMode = if ($State.Capability.SupportsSelectableAuthorization -and
        $State.Capability.PermitsAuthorization -and
        $State.Capability.HasExplicitSubmissionEvidence) { 'selectable' } else { 'plain-text' }
    Assert-True ($State.Mode -eq $expectedMode) "$($State.Name): mode ignored capability/submission evidence."
}

function Assert-TraceBeforeConfirmation {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-CapabilityRecord $State
    $renderedGates = @($State.Actions | Where-Object Kind -eq 'setup_gate_rendered')
    Assert-True ($renderedGates.Count -ge 1) "$($State.Name): no setup gate was rendered through the trace."
    Assert-True ($State.ActiveGateCount -in @(0, 1)) "$($State.Name): active gate count is invalid."
    $currentGate = @($renderedGates | Where-Object GateId -eq $State.GateId | Select-Object -Last 1)
    Assert-True ($currentGate.Count -eq 1) "$($State.Name): current gate is not represented in the trace."
    Assert-True ($currentGate[0].Choices -eq 'Start,Cancel' -and $currentGate[0].Default -eq 'none') "$($State.Name): gate choices/default were not recorded safely."
    $appliedBeforeConfirmation = @($State.Actions | Where-Object {
        $_.Kind -eq 'external_mutation' -and $_.Phase -eq 'pre-confirmation' -and
        $_.Outcome -eq 'applied' -and $_.AuthorizationReference -ne $null
    })
    Assert-True ($appliedBeforeConfirmation.Count -eq 0) "$($State.Name): an external mutation was applied before confirmation."
    Assert-True ($State.BlockedMutationAttempts.Count -ge 1) "$($State.Name): the pre-confirmation mutation attempt was not recorded."
    Assert-True (@($State.BlockedMutationAttempts | Where-Object Applied).Count -eq 0) "$($State.Name): a blocked mutation was marked applied."
}

function Assert-Awaiting {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-TraceBeforeConfirmation $State
    Assert-True ($State.Outcome -eq 'awaiting_confirmation') "$($State.Name): non-submitted input authorized setup."
    Assert-True ($null -eq $State.Authorization) "$($State.Name): non-submitted input persisted authorization."
}

function Assert-Started {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter(Mandatory)] [string] $ExpectedMode,
        [Parameter(Mandatory)] [string] $ExpectedReference
    )

    Assert-TraceBeforeConfirmation $State
    Assert-True ($State.Outcome -eq 'started') "$($State.Name): explicit Start did not authorize setup."
    Assert-True ($State.ActiveGateCount -eq 0 -and $State.GateLifecycle -eq 'closed') "$($State.Name): accepted Start did not close its gate."
    Assert-True ($null -ne $State.Authorization) "$($State.Name): Start did not persist an authorization record."
    Assert-True ($State.Authorization.Decision -eq 'start') "$($State.Name): authorization decision is not Start."
    Assert-True ($State.Authorization.Mode -eq $ExpectedMode) "$($State.Name): authorization mode was not persisted."
    Assert-True ($State.Authorization.Reference -eq $ExpectedReference) "$($State.Name): authorization reference was not persisted."
    Assert-True ($State.Authorization.Submitted) "$($State.Name): authorization was not marked as submitted."
}

function Assert-Cancelled {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-TraceBeforeConfirmation $State
    Assert-True ($State.Outcome -eq 'cancelled') "$($State.Name): explicit Cancel did not end setup."
    Assert-True ($State.ActiveGateCount -eq 0 -and $State.GateLifecycle -eq 'closed') "$($State.Name): Cancel did not close the gate."
    Assert-True ($null -eq $State.Authorization) "$($State.Name): Cancel persisted a Start authorization."
    Assert-True ($State.ExternalMutations.Count -eq 0) "$($State.Name): Cancel applied an external mutation."
}

function Assert-AuthorizedDispatch {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [int] $ExpectedCount = 1
    )

    Invoke-ExternalMutation $State 'create-worker-or-branch' | Out-Null
    Assert-True ($State.ExternalMutations.Count -eq $ExpectedCount) "$($State.Name): authorized dispatch was not recorded."
    Assert-True (@($State.Actions | Where-Object {
        $_.Kind -eq 'external_mutation' -and $_.Outcome -eq 'blocked_before_confirmation'
    }).Count -ge 1) "$($State.Name): blocked pre-confirmation trace was lost after Start."
}

function Prepare-Scenario {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Prepare-Setup $State
    Assert-TraceBeforeConfirmation $State
}

$commonCapability = @{
    CapabilitySource = 'synthetic authorized capability probe'
    CapabilityContext = 'offline setup gate provider'
}
$results = [System.Collections.Generic.List[object]]::new()

$state = New-SetupState 'permitted-selectable-start' 'story-97' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'submitted_choice' 'Start' $null $true 'auth-selectable-1') | Out-Null
Assert-Started $state 'selectable' 'auth-selectable-1'
Assert-AuthorizedDispatch $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'prohibited-selectable-tool' 'story-97' $true $false $false 'tool_schema' 'current Codex optional-question route' 'permission submission prohibited; typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'typed_reply' $null 'Start' $false 'auth-plain-prohibited') | Out-Null
Assert-Started $state 'plain-text' 'auth-plain-prohibited'
Assert-AuthorizedDispatch $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'unavailable-selectable-tool' 'story-97' $false $false $false 'documentation' 'host exposes no authorization selector' 'selectable authorization unavailable; typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'typed_reply' $null 'Start' $false 'auth-plain-unavailable') | Out-Null
Assert-Started $state 'plain-text' 'auth-plain-unavailable'
Assert-AuthorizedDispatch $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'missing-submission-evidence' 'story-97' $true $true $false 'tool_schema' 'selector is advertised but submission event is undocumented' 'submission evidence unverified; typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'typed_reply' $null 'Start' $false 'auth-plain-unverified') | Out-Null
Assert-Started $state 'plain-text' 'auth-plain-unverified'
Assert-AuthorizedDispatch $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'selectable-default-only' 'story-97' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'default_only' 'Start' $null $false $null) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'selectable-empty-response' 'story-97' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'submitted_choice' $null '' $false $null) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'plain-blank-reply' 'story-97' $false $false $false 'documentation' 'host exposes no authorization selector' 'typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'typed_reply' $null '   ' $false $null) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'plain-invalid-reply' 'story-97' $false $false $false 'documentation' 'host exposes no authorization selector' 'typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'typed_reply' $null 'Maybe' $false $null) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'plain-timeout' 'story-97' $false $false $false 'documentation' 'host exposes no authorization selector' 'typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'timeout' $null $null $false $null) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'plain-worker-message' 'story-97' $false $false $false 'documentation' 'host exposes no authorization selector' 'typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'worker_message' $null 'Start' $false $null) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'selectable-explicit-cancel' 'story-97' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'submitted_choice' 'Cancel' $null $true $null) | Out-Null
Assert-Cancelled $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'plain-explicit-cancel' 'story-97' $false $false $false 'documentation' 'host exposes no authorization selector' 'typed fallback required'
Prepare-Scenario $state
Resolve-SetupEvent $state (New-SetupEvent $state 'typed_reply' $null 'Cancel' $false $null) | Out-Null
Assert-Cancelled $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'duplicate-start-event' 'story-97' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
$duplicateEvent = New-SetupEvent $state 'submitted_choice' 'Start' $null $true 'auth-duplicate'
Resolve-SetupEvent $state $duplicateEvent | Out-Null
Assert-Started $state 'selectable' 'auth-duplicate'
Assert-AuthorizedDispatch $state
Resolve-SetupEvent $state $duplicateEvent | Out-Null
Assert-Started $state 'selectable' 'auth-duplicate'
Assert-True ($state.ExternalMutations.Count -eq 1) 'duplicate Start must not dispatch twice.'
Assert-True (@($state.Actions | Where-Object Outcome -eq 'rejected_stale_or_closed_gate').Count -eq 1) 'duplicate Start must be recorded as a closed-gate rejection.'
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'start-after-cancel' 'story-97' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
$cancelEvent = New-SetupEvent $state 'submitted_choice' 'Cancel' $null $true $null
Resolve-SetupEvent $state $cancelEvent | Out-Null
Assert-Cancelled $state
$startAfterCancel = New-SetupEvent $state 'submitted_choice' 'Start' $null $true 'auth-after-cancel'
Resolve-SetupEvent $state $startAfterCancel | Out-Null
Assert-Cancelled $state
Assert-True (@($state.Actions | Where-Object Outcome -eq 'rejected_stale_or_closed_gate').Count -eq 1) 'Start after Cancel must be rejected by the closed gate.'
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$state = New-SetupState 'scope-change-invalidates-start' 'story-97/task-1' $true $true $true $commonCapability.CapabilitySource $commonCapability.CapabilityContext 'submitted choice event with gate identity'
Prepare-Scenario $state
$staleStart = New-SetupEvent $state 'submitted_choice' 'Start' $null $true 'auth-old-scope'
$staleCancel = New-SetupEvent $state 'submitted_choice' 'Cancel' $null $true $null
Resolve-SetupEvent $state $staleStart | Out-Null
Assert-Started $state 'selectable' 'auth-old-scope'
Assert-AuthorizedDispatch $state
$scopeChange = New-SetupEvent $state 'scope_changed' $null $null $false $null
$scopeChange.Scope = 'story-97/task-2'
Resolve-SetupEvent $state $scopeChange | Out-Null
Assert-Awaiting $state
Assert-True ($state.GateRevision -eq 2 -and $state.GateReplacementCount -eq 1 -and $state.GateRenderCount -eq 2) 'scope change must replace and re-render exactly one active gate.'
$mutationsAfterReplacement = $state.ExternalMutations.Count
Resolve-SetupEvent $state $staleStart | Out-Null
Resolve-SetupEvent $state $staleCancel | Out-Null
Assert-Awaiting $state
Assert-True ($state.ExternalMutations.Count -eq $mutationsAfterReplacement) 'stale scope-A decisions must not dispatch on scope-B.'
Assert-True (@($state.Actions | Where-Object Outcome -eq 'rejected_stale_or_closed_gate').Count -eq 2) 'stale Start and Cancel must be recorded as rejected.'
Resolve-SetupEvent $state (New-SetupEvent $state 'submitted_choice' 'Start' $null $true 'auth-new-scope') | Out-Null
Assert-Started $state 'selectable' 'auth-new-scope'
Assert-True ($state.Authorization.Scope -eq 'story-97/task-2' -and $state.Authorization.GateRevision -eq 2) 'scope change must bind Start to the new gate and scope.'
Assert-AuthorizedDispatch $state 2
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome; GateRenders = $state.GateRenderCount; BlockedAttempts = $state.BlockedMutationAttempts.Count })

$results | Format-Table Name, Mode, Outcome, GateRenders, BlockedAttempts -AutoSize | Out-String | Write-Output
Write-Output "Passed $($results.Count) setup-authorization decision scenarios; synthetic assertions only; no selectable UI or provider writes were performed."
