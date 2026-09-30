[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('validate')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'

function Read-Object {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw 'Preflight input file was not found.' }
    try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Preflight input is not valid JSON: $($_.Exception.Message)" }
}

function Need-Map {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $Object[$Name] -isnot [System.Collections.IDictionary]) { throw "$Name must be an object." }
    return $Object[$Name]
}

function Need-String {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required in $Context." }
    return [string]$Object[$Name]
}

function Get-StringArray {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context, [switch] $AllowEmpty)
    if (-not $Object.Contains($Name) -or $Object[$Name] -is [string] -or $Object[$Name] -isnot [System.Collections.IEnumerable]) { throw "$Name must be an array in $Context." }
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Object[$Name]) {
        if ([string]::IsNullOrWhiteSpace([string]$item)) { throw "$Name cannot contain a blank value in $Context." }
        [void]$items.Add([string]$item)
    }
    if (-not $AllowEmpty -and $items.Count -eq 0) { throw "$Name must contain at least one value in $Context." }
    return ,$items.ToArray()
}

function Read-Profile {
    param([System.Collections.IDictionary] $Object, [string] $Name)
    $profile = Need-Map $Object $Name
    return [ordered]@{ model = Need-String $profile 'model' "profiles.$Name"; effort = Need-String $profile 'effort' "profiles.$Name" }
}

function Test-ProfileAvailable {
    param([object[]] $Catalog, [System.Collections.IDictionary] $Profile)
    foreach ($candidate in $Catalog) {
        if ($candidate -isnot [System.Collections.IDictionary] -or $candidate.model -ne $Profile.model) { continue }
        if ($candidate.efforts -is [string] -or $candidate.efforts -isnot [System.Collections.IEnumerable]) { continue }
        if (@($candidate.efforts | ForEach-Object { [string]$_ }) -contains $Profile.effort) { return $true }
    }
    return $false
}

function Invoke-Preflight {
    param([System.Collections.IDictionary] $InputObject)
    if ($InputObject.schemaVersion -ne 1) { throw 'Unsupported preflight schemaVersion.' }
    $ticketKey = Need-String $InputObject 'selectedTicketKey' 'preflight'
    $profilesInput = Need-Map $InputObject 'profiles'
    $coordinator = Read-Profile $profilesInput 'coordinator'
    $implementer = Read-Profile $profilesInput 'implementer'
    $reviewer = Read-Profile $profilesInput 'reviewer'
    $observedCoordinator = Need-Map $InputObject 'observedCoordinatorProfile'
    $catalog = @($InputObject.availableProfiles)
    $capabilities = Need-Map $InputObject 'capabilities'
    $requiredCapabilities = Get-StringArray $InputObject 'requiredCapabilities' 'preflight' -AllowEmpty
    $requiredActions = Get-StringArray $InputObject 'requiredActions' 'preflight' -AllowEmpty
    $blockers = [System.Collections.Generic.List[object]]::new()
    $profileResults = [ordered]@{}
    if ($observedCoordinator.model -ne $coordinator.model -or $observedCoordinator.effort -ne $coordinator.effort) {
        [void]$blockers.Add([ordered]@{ category = 'coordinator_profile_mismatch'; role = 'coordinator' })
        $profileResults.coordinator = [ordered]@{ available = $false; requestedModel = $coordinator.model; requestedEffort = $coordinator.effort; observedModel = $observedCoordinator.model; observedEffort = $observedCoordinator.effort }
    } else { $profileResults.coordinator = [ordered]@{ available = $true; model = $coordinator.model; effort = $coordinator.effort } }
    foreach ($role in @(@{ name = 'implementer'; profile = $implementer; model = 'gpt-5.6-luna'; effort = 'xhigh' }, @{ name = 'reviewer'; profile = $reviewer; model = 'gpt-6.1-sol'; effort = 'high' })) {
        if ($role.profile.model -ne $role.model -or $role.profile.effort -ne $role.effort) {
            [void]$blockers.Add([ordered]@{ category = 'unexpected_requested_profile'; role = $role.name; model = $role.profile.model; effort = $role.profile.effort })
            $profileResults[$role.name] = [ordered]@{ available = $false; reason = 'unexpected_requested_profile' }
        } elseif (-not (Test-ProfileAvailable $catalog $role.profile)) {
            [void]$blockers.Add([ordered]@{ category = 'exact_profile_unavailable'; role = $role.name; model = $role.profile.model; effort = $role.profile.effort })
            $profileResults[$role.name] = [ordered]@{ available = $false; reason = 'exact_profile_unavailable' }
        } else { $profileResults[$role.name] = [ordered]@{ available = $true; model = $role.profile.model; effort = $role.profile.effort } }
    }

    $capabilityMap = [ordered]@{
        ordinaryChats = 'ordinaryChats'
        workerMessaging = 'workerMessaging'
        boundedWait = 'boundedWait'
        managedWorktrees = 'managedWorktrees'
        heartbeat = 'heartbeat'
        gitProvider = 'gitProvider'
        githubProvider = 'githubProvider'
        taigaReader = 'taigaReader'
        taigaWriter = 'taigaWriter'
    }
    $browserProviders = @()
    if ($capabilities.Contains('browserProviders') -and $capabilities.browserProviders -isnot [string]) {
        $browserProviders = @($capabilities.browserProviders | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ -in @('iab', 'chrome', 'edge') } | Select-Object -Unique)
    }
    $missingCapabilities = [System.Collections.Generic.List[string]]::new()
    foreach ($required in $requiredCapabilities) {
        if ($required -eq 'browser') {
            if ($browserProviders.Count -eq 0) { [void]$missingCapabilities.Add('browser') }
            continue
        }
        if (-not $capabilityMap.Contains($required)) { throw "Unknown required capability: $required." }
        $property = [string]$capabilityMap[$required]
        if (-not $capabilities.Contains($property) -or $capabilities[$property] -ne $true) { [void]$missingCapabilities.Add($required) }
    }
    foreach ($missing in $missingCapabilities) { [void]$blockers.Add([ordered]@{ category = 'required_capability_unavailable'; capability = $missing }) }

    $authorization = if ($InputObject.Contains('authorization') -and $InputObject.authorization -is [System.Collections.IDictionary]) { $InputObject.authorization } else { $null }
    $authorizedActions = @()
    if ($null -ne $authorization) {
        if ($authorization.Contains('authorizedActions')) { $authorizedActions = Get-StringArray $authorization 'authorizedActions' 'authorization' -AllowEmpty }
        if ($authorization.granted -ne $true -or $authorization.ticketKey -ne $ticketKey) {
            [void]$blockers.Add([ordered]@{ category = 'operational_authority_missing'; ticketKey = $ticketKey })
        }
    } else { [void]$blockers.Add([ordered]@{ category = 'operational_authority_missing'; ticketKey = $ticketKey }) }
    $supportedActions = @('createOrReuseChats', 'messageWorkers', 'createWorktrees', 'writeTaiga', 'pushAndCreatePr', 'scheduleHeartbeat', 'observeMerge')
    foreach ($action in @($authorizedActions) + @($requiredActions)) {
        if ($supportedActions -notcontains $action) { throw "Unsupported or forbidden operational action: $action." }
    }
    $unapprovedActions = @($requiredActions | Where-Object { $authorizedActions -notcontains $_ })
    if ($unapprovedActions.Count -gt 0) { [void]$blockers.Add([ordered]@{ category = 'operational_authority_missing'; actions = $unapprovedActions }) }

    return [ordered]@{
        ready = ($blockers.Count -eq 0)
        ticketKey = $ticketKey
        profiles = $profileResults
        browserCapability = [ordered]@{ available = ($browserProviders.Count -gt 0); providers = $browserProviders; smokeTestPerformed = $false }
        missingCapabilities = @($missingCapabilities)
        missingAuthorizedActions = $unapprovedActions
        blockers = $blockers.ToArray()
    }
}

try {
    $input = Read-Object
    $data = Invoke-Preflight $input
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_preflight'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
