# Incrementally collect attributable role token counters for one story.
#
# The source is the local Codex session JSONL named by the observed-role evidence
# file. Only complete lines after the saved byte cursor are read on later runs;
# cumulative notifications are never summed. The output is metadata for
# get-story-performance.ps1 and contains counters/coverage, not transcript text.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ObservedEvidencePath,
    [string] $EventsPath,
    [Parameter(Mandatory)] [string] $StatePath,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $Scope,
    [switch] $SessionLifetime
)

# Compatibility entry point; preserve parameter binding for repository callers.
& (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/collect-role-token-usage.ps1') @PSBoundParameters
