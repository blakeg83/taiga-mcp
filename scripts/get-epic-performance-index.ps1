# Format existing per-story finalization receipts; no new analytics or writes.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int[]] $StoryRefs,
    [Parameter(Mandatory)] [string] $StoryReportsPath
)
# Compatibility entry point; preserve parameter binding for repository callers.
& (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/get-epic-performance-index.ps1') @PSBoundParameters
