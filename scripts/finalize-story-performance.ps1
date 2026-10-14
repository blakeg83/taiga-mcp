# Finalize existing telemetry after confirmed exact-HEAD PR delivery. No provider writes.
[CmdletBinding(DefaultParameterSetName = 'Object')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Object')] [hashtable] $Delivery,
    [Parameter(Mandatory, ParameterSetName = 'File')] [string] $DeliveryPath,
    [Parameter(Mandatory)] [string] $ExternalRunRoot,
    [Parameter(Mandatory)] [string] $RunId,
    [Parameter(Mandatory)] [string] $ArtifactRoot,
    [Parameter(Mandatory)] [string] $BaseRevision,
    [Parameter(Mandatory)] [string] $RepositoryPath,
    [ValidateSet('per_task','story_end_only')] [string] $ReviewMode = 'per_task',
    [int[]] $TaskRefs = @(),
    [string] $MetadataPath,
    [string] $ObservedEvidencePath,
    [string] $TaskOutcomePath,
    [string] $Scope,
    [string] $OccurredAtUtc,
    [switch] $ArtifactsAccessibleToUser,
    [string] $RecorderPath = (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1'),
    [string] $AggregatorPath = (Join-Path $PSScriptRoot 'get-story-performance.ps1'),
    [string] $CollectorPath = (Join-Path $PSScriptRoot 'collect-role-token-usage.ps1')
)
# Compatibility entry point; preserve parameter binding for repository callers.
& (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/finalize-story-performance.ps1') @PSBoundParameters
