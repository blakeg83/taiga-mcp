<#
.SYNOPSIS
    Aggregate a versioned story performance event ledger.

.DESCRIPTION
    This entry point is deliberately read-only. It consumes the append-only
    JSONL ledger written by write-performance-event.ps1 and emits one
    deterministic story_performance_report object. It does not infer missing
    boundaries, subtract overlapping phases, estimate unavailable usage, or
    read transcripts or source text. Source-backed usage is reconciled only
    from explicit attributable boundary samples. When requested, JSON and
    Markdown artifacts are published atomically to immutable paths outside
    the repository; an existing different artifact is a conflict.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('EventPath', 'LedgerPath', 'InputPath')]
    [string] $EventsPath,

    [ValidateSet('per_task', 'story_end_only')]
    [string] $ReviewMode,

    [Alias('TaskRef')]
    [int[]] $TaskRefs,

    [string] $OutputPath,

    [string] $MarkdownPath,

    [Alias('ReviewedRevision', 'HeadRevision')]
    [string] $ReviewedHead,

    [Alias('BaseSha', 'BaseCommit')]
    [string] $BaseRevision,

    [Alias('RepoPath', 'RepositoryRoot')]
    [string] $RepositoryPath,

    [Alias('SetupMetadataPath', 'AssignmentPath', 'ProfilesPath')]
    [string] $MetadataPath,

    [string] $UsageMetadataPath,

    [string] $CollectionAttemptPath,

    [string] $TaskOutcomePath,

    [Alias('ReportDirectory', 'ArtifactRoot')]
    [string] $ArtifactDirectory
)

# Compatibility entry point; preserve parameter binding for repository callers.
& (Join-Path $PSScriptRoot '../.agents/skills/taiga-story-loop/scripts/get-story-performance.ps1') @PSBoundParameters
