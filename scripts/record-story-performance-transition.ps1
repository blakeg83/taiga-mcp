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
# Compatibility entry point; preserve parameter binding for repository callers.
& (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/record-story-performance-transition.ps1') @PSBoundParameters
