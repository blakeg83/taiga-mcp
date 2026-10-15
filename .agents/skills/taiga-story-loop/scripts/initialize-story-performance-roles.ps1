# Call once immediately after assigning the worker pair, using actual assignment profiles.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ExternalRunRoot,
    [Parameter(Mandatory)] [string] $RunId,
    [Parameter(Mandatory)] [int] $ProjectId,
    [Parameter(Mandatory)] [int] $StoryId,
    [Parameter(Mandatory)] [object[]] $Profiles,
    [string] $Scope = 'story',
    [string] $CodexHome
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $RunId -in @('.','..')) { throw 'invalid run identity' }
$runDirectory = Join-Path $ExternalRunRoot $RunId
$ledger = Join-Path $runDirectory 'events.jsonl'
$metadataPath = Join-Path $runDirectory 'setup-metadata.json'
if (Test-Path -LiteralPath $metadataPath) { throw 'setup metadata already exists; preserve explicit profile changes' }
$provenance = @{ source = 'worker_assignment'; observedBy = 'initialize-story-performance-roles'; coverage = 'actual assigned role profiles'; synthetic = $false }
$roles = @($Profiles | ForEach-Object { $_.role } | Sort-Object -Unique)
if (($roles -join ',') -cne 'coordinator,implementer,reviewer' -or $Profiles.Count -ne 3) { throw 'all three actual role profiles are required' }
$bindings = @($Profiles | ForEach-Object { @{ role = $_.role; workerId = $_.workerId; sessionId = $_.sessionId; scope = $Scope } })
$parameters = @{ Bindings = $bindings; OutputPath = (Join-Path $runDirectory 'observed-role-token-usage.json') }
if ($CodexHome) { $parameters.CodexHome = $CodexHome }
$discovery = (& (Join-Path $PSScriptRoot 'resolve-story-token-sources.ps1') @parameters) | ConvertFrom-Json -Depth 30

$normalized = @($Profiles | ForEach-Object {
    $profile = $_
    $verified = @($discovery.rows | Where-Object { $_.role -ceq $profile.role -and $_.workerId -ceq $profile.workerId })
    $sessionId = if ($verified.Count -eq 1) { $verified[0].sessionId } else { $profile.sessionId }
    @{ role = $_.role; workerId = $_.workerId; sessionId = $sessionId; model = $_.model; effort = $_.effort; effectiveFromUtc = $_.effectiveFromUtc; provenance = $provenance }
})
$metadata = @{ schemaVersion = 1; kind = 'story_performance_setup'; runId = $RunId; projectId = $ProjectId; storyId = $StoryId; profiles = $normalized; provenance = $provenance }
# Validate with the production validator before publishing assignment metadata.
$temporary = Join-Path $runDirectory ('setup-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    [IO.File]::WriteAllText($temporary, ($metadata | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    $report = (& (Join-Path $PSScriptRoot 'get-story-performance.ps1') -EventsPath $ledger -MetadataPath $temporary) | ConvertFrom-Json -Depth 100
    if ($report.metrics.modelsAndReasoning.state -ne 'measured') { throw 'setup role profiles are incomplete' }
    [IO.File]::Move($temporary, $metadataPath)
}
finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
$discovery | ConvertTo-Json -Depth 30
