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
        [Parameter(Mandatory)] [bool] $PermitsAuthorization
    )

    $mode = if ($SupportsSelectableAuthorization -and $PermitsAuthorization) {
        'selectable'
    } else {
        'plain-text'
    }

    [pscustomobject]@{
        Name = $Name
        Scope = $Scope
        Mode = $mode
        ActiveGateCount = 1
        GateRevision = 1
        ReplacedGateCount = 0
        PreConfirmationMutations = @()
        Authorization = $null
        Outcome = 'awaiting_confirmation'
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

        $State.Scope = $Event.Scope
        $State.GateRevision++
        $State.ReplacedGateCount++
        $State.Authorization = $null
        $State.Outcome = 'awaiting_confirmation'
        return $State
    }

    if ($State.Mode -eq 'selectable') {
        if ($Event.Kind -ne 'submitted_choice' -or
            $Event.Choice -notin @('Start', 'Cancel') -or
            -not $Event.Submitted) {
            $State.Outcome = 'awaiting_confirmation'
            return $State
        }

        $decision = $Event.Choice
    } else {
        if ($Event.Kind -ne 'typed_reply' -or
            [string]::IsNullOrWhiteSpace($Event.Text)) {
            $State.Outcome = 'awaiting_confirmation'
            return $State
        }

        $decision = $Event.Text.Trim()
        if ($decision -notin @('Start', 'Cancel')) {
            $State.Outcome = 'awaiting_confirmation'
            return $State
        }
    }

    if ($decision -eq 'Cancel') {
        $State.Authorization = $null
        $State.Outcome = 'cancelled'
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
    }
    $State.Outcome = 'started'
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

function Assert-NoPreConfirmationMutations {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-True ($State.PreConfirmationMutations.Count -eq 0) "$($State.Name): setup mutated an external system before confirmation."
    Assert-True ($State.ActiveGateCount -eq 1) "$($State.Name): setup did not retain exactly one active gate."
}

function Assert-Awaiting {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-NoPreConfirmationMutations $State
    Assert-True ($State.Outcome -eq 'awaiting_confirmation') "$($State.Name): non-submitted input authorized setup."
    Assert-True ($null -eq $State.Authorization) "$($State.Name): non-submitted input persisted authorization."
}

function Assert-Started {
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter(Mandatory)] [string] $ExpectedMode,
        [Parameter(Mandatory)] [string] $ExpectedReference
    )

    Assert-NoPreConfirmationMutations $State
    Assert-True ($State.Outcome -eq 'started') "$($State.Name): explicit Start did not authorize setup."
    Assert-True ($null -ne $State.Authorization) "$($State.Name): Start did not persist an authorization record."
    Assert-True ($State.Authorization.Decision -eq 'start') "$($State.Name): authorization decision is not Start."
    Assert-True ($State.Authorization.Mode -eq $ExpectedMode) "$($State.Name): authorization mode was not persisted."
    Assert-True ($State.Authorization.Reference -eq $ExpectedReference) "$($State.Name): authorization reference was not persisted."
    Assert-True ($State.Authorization.Submitted) "$($State.Name): authorization was not marked as submitted."
}

function Assert-Cancelled {
    param([Parameter(Mandatory)] [pscustomobject] $State)

    Assert-NoPreConfirmationMutations $State
    Assert-True ($State.Outcome -eq 'cancelled') "$($State.Name): explicit Cancel did not end setup."
    Assert-True ($null -eq $State.Authorization) "$($State.Name): Cancel persisted a Start authorization."
}

$results = [System.Collections.Generic.List[object]]::new()

$state = New-SetupState 'permitted-selectable-start' 'story-97' $true $true
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'submitted_choice'; Choice = 'Start'; Submitted = $true
    AuthorizationReference = 'auth-selectable-1'
}) | Out-Null
Assert-Started $state 'selectable' 'auth-selectable-1'
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'prohibited-selectable-tool' 'story-97' $true $false
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'typed_reply'; Text = 'Start'; Choice = $null; Submitted = $false
    AuthorizationReference = 'auth-plain-prohibited'
}) | Out-Null
Assert-Started $state 'plain-text' 'auth-plain-prohibited'
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'unavailable-selectable-tool' 'story-97' $false $false
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'typed_reply'; Text = 'Start'; Choice = $null; Submitted = $false
    AuthorizationReference = 'auth-plain-unavailable'
}) | Out-Null
Assert-Started $state 'plain-text' 'auth-plain-unavailable'
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'selectable-default-only' 'story-97' $true $true
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'default_only'; Choice = 'Start'; Submitted = $false; Text = $null
    AuthorizationReference = $null
}) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'selectable-empty-response' 'story-97' $true $true
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'submitted_choice'; Choice = $null; Submitted = $false; Text = ''
    AuthorizationReference = $null
}) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'plain-timeout' 'story-97' $false $false
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'timeout'; Choice = $null; Submitted = $false; Text = $null
    AuthorizationReference = $null
}) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'plain-worker-message' 'story-97' $false $false
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'worker_message'; Choice = $null; Submitted = $false; Text = 'Start'
    AuthorizationReference = $null
}) | Out-Null
Assert-Awaiting $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'plain-explicit-cancel' 'story-97' $false $false
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'typed_reply'; Text = 'Cancel'; Choice = $null; Submitted = $false
    AuthorizationReference = $null
}) | Out-Null
Assert-Cancelled $state
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$state = New-SetupState 'scope-change-invalidates-start' 'story-97/task-1' $true $true
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'submitted_choice'; Choice = 'Start'; Submitted = $true
    AuthorizationReference = 'auth-old-scope'
}) | Out-Null
Assert-Started $state 'selectable' 'auth-old-scope'
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'scope_changed'; Scope = 'story-97/task-2'; Choice = $null; Submitted = $false
    AuthorizationReference = $null
}) | Out-Null
Assert-Awaiting $state
Assert-True ($state.GateRevision -eq 2 -and $state.ReplacedGateCount -eq 1) 'scope change must replace the prior gate.'
Resolve-SetupEvent $state ([pscustomobject]@{
    Kind = 'submitted_choice'; Choice = 'Start'; Submitted = $true
    AuthorizationReference = 'auth-new-scope'
}) | Out-Null
Assert-Started $state 'selectable' 'auth-new-scope'
Assert-True ($state.Authorization.Scope -eq 'story-97/task-2') 'scope change must bind Start to the new scope.'
$results.Add([pscustomobject]@{ Name = $state.Name; Mode = $state.Mode; Outcome = $state.Outcome })

$results | Format-Table Name, Mode, Outcome -AutoSize | Out-String | Write-Output
Write-Output "Passed $($results.Count) setup-authorization decision scenarios; synthetic assertions only; no selectable UI or provider writes were performed."
