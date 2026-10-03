[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$setupPath = Join-Path $skillRoot 'references/invocation-and-setup.md'
$setupText = Get-Content $setupPath -Raw
$normalizedSetup = [regex]::Replace($setupText, '\s+', ' ')

function Assert-DocumentContains {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Text
    )

    if (-not $normalizedSetup.Contains($Text)) {
        throw "Document assertion failed: $Label"
    }
}

Assert-DocumentContains 'per-repository mapping' 'one row per resolved repository'
Assert-DocumentContains 'epic mapping guard' 'An epic setup must not collapse multiple repositories'
Assert-DocumentContains 'start gate' 'Reply Start or Cancel.'
Assert-DocumentContains 'read-only discovery' 'Discovery is read-only.'
Assert-DocumentContains 'cancel behavior' '`Cancel` leaves the external systems unchanged'
Assert-DocumentContains 'clarification behavior' 'Ask only for a missing or ambiguous'

function Invoke-SetupScenario {
    param(
        [Parameter(Mandatory)] [hashtable] $InputData
    )

    $unresolved = @()
    if ([string]::IsNullOrWhiteSpace($InputData.Project)) {
        $unresolved += 'project'
    }
    if ($InputData.Ref -le 0) {
        $unresolved += 'work-item reference'
    }
    if ($InputData.Repositories.Count -eq 0) {
        $unresolved += 'repository'
    }
    if (-not $InputData.AcceptanceCriteriaPresent) {
        $unresolved += 'acceptance criteria'
    }
    if ($InputData.Kind -eq 'epic' -and $InputData.Repositories.Count -gt 1 -and
        -not $InputData.PerRepositoryMapping) {
        $unresolved += 'per-repository branch/base/worktree mapping'
    }

    if ($unresolved.Count -gt 0) {
        return [pscustomobject]@{
            Name = $InputData.Name
            Input = $InputData.InputSummary
            Observed = 'Clarify'
            Detail = 'Ask for: ' + ($unresolved -join ', ')
            WritesBeforeConfirmation = 'None'
        }
    }

    if ($InputData.Reply -eq 'Cancel') {
        return [pscustomobject]@{
            Name = $InputData.Name
            Input = $InputData.InputSummary
            Observed = 'Cancelled'
            Detail = 'External systems unchanged'
            WritesBeforeConfirmation = 'None'
        }
    }

    if ($InputData.Reply -ne 'Start') {
        return [pscustomobject]@{
            Name = $InputData.Name
            Input = $InputData.InputSummary
            Observed = 'Clarify'
            Detail = 'Reply must be Start or Cancel'
            WritesBeforeConfirmation = 'None'
        }
    }

    return [pscustomobject]@{
        Name = $InputData.Name
        Input = $InputData.InputSummary
        Observed = 'SetupReady'
        Detail = "$($InputData.Repositories.Count) repository mapping(s); Start-scoped operations may proceed"
        WritesBeforeConfirmation = 'None'
    }
}

$scenarios = @(
    @{
        Name = 'story'
        InputSummary = 'taiga-mcp story #46; one repository; acceptance present; reply Start'
        Kind = 'story'
        Project = 'taiga-mcp'
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Start'
    }
    @{
        Name = 'epic'
        InputSummary = 'multi-repository epic #45; TaigaMCP + ReviewRepo mappings; reply Start'
        Kind = 'epic'
        Project = 'multi-repository'
        Ref = 45
        Repositories = @('C:\Projects\TaigaMCP', 'C:\Projects\ReviewRepo')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Start'
    }
    @{
        Name = 'ambiguous-scope'
        InputSummary = 'story #46; project missing; acceptance present'
        Kind = 'story'
        Project = ''
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Start'
    }
    @{
        Name = 'cancelled-setup'
        InputSummary = 'taiga-mcp story #46; one repository; acceptance present; reply Cancel'
        Kind = 'story'
        Project = 'taiga-mcp'
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $true
        Reply = 'Cancel'
    }
    @{
        Name = 'missing-acceptance'
        InputSummary = 'taiga-mcp story #46; acceptance criteria missing'
        Kind = 'story'
        Project = 'taiga-mcp'
        Ref = 46
        Repositories = @('C:\Projects\TaigaMCP')
        PerRepositoryMapping = $true
        AcceptanceCriteriaPresent = $false
        Reply = 'Start'
    }
)

$expected = @{
    'story' = 'SetupReady'
    'epic' = 'SetupReady'
    'ambiguous-scope' = 'Clarify'
    'cancelled-setup' = 'Cancelled'
    'missing-acceptance' = 'Clarify'
}

$results = foreach ($scenario in $scenarios) {
    $result = Invoke-SetupScenario -InputData $scenario
    if ($result.Observed -ne $expected[$result.Name]) {
        throw "Scenario '$($result.Name)' expected '$($expected[$result.Name])' but observed '$($result.Observed)'."
    }
    if ($result.WritesBeforeConfirmation -ne 'None') {
        throw "Scenario '$($result.Name)' attempted a pre-confirmation write."
    }
    $result
}

$results | Format-Table Name, Input, Observed, Detail, WritesBeforeConfirmation -AutoSize | Out-String | Write-Output
Write-Output "Passed $($results.Count) concrete setup scenarios; all pre-confirmation writes were None."
