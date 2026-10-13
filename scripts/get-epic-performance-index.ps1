# Format existing per-story finalization receipts; no new analytics or writes.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int[]] $StoryRefs,
    [Parameter(Mandatory)] [string] $StoryReportsPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$reports = @(Get-Content -LiteralPath $StoryReportsPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String)
$rows = @()
$lines = @('| Story | PR / reviewed HEAD | Publication | Collection | Coverage / limitations | Artifacts |', '| --- | --- | --- | --- | --- | --- |')
function Cell([object] $Value) { return ([string] $Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ') }
foreach ($storyRef in $StoryRefs) {
    if ($storyRef -le 0) { throw 'story refs must be positive' }
    $matches = @($reports | Where-Object storyRef -eq $storyRef)
    if ($matches.Count -gt 1) { throw "ambiguous finalization receipt for story #$storyRef; select its delivered HEAD" }
    if ($matches.Count -eq 0) {
        $row = [ordered]@{ storyRef = $storyRef; reportState = 'unavailable'; collection = 'skipped'; prUrl = $null; reviewedHead = $null; coverage = $null; limitations = @('story finalization receipt unavailable'); jsonReference = $null; markdownReference = $null }
    }
    else {
        $report = $matches[0]
        $row = [ordered]@{
            storyRef = $storyRef; reportState = $report.reportState
            collection = if ($null -ne $report.collectionAttempt) { $report.collectionAttempt.status } else { 'skipped' }
            prUrl = $report.prUrl; reviewedHead = $report.reviewedHead; coverage = $report.metricCoverage
            limitations = @($report.limitations)
            jsonReference = if ($report.artifactsAccessibleToUser) { $report.jsonPath } else { $null }
            markdownReference = if ($report.artifactsAccessibleToUser) { $report.markdownPath } else { $null }
        }
        if ($row.reportState -eq 'published' -and -not $report.artifactsAccessibleToUser) { $row.limitations += 'published locally; accessible user artifact references unavailable' }
    }
    $rows += $row
    $coverage = if ($null -eq $row.coverage) { 'unavailable' } else { @($row.coverage.PSObject.Properties | Where-Object Name -in @('timeToPr', 'implementationElapsed', 'observedTotalTokens', 'tasksCompleted') | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ' }
    $links = if ($null -ne $row.jsonReference -and $null -ne $row.markdownReference) { "[JSON](<$($row.jsonReference)>) / [Markdown](<$($row.markdownReference)>)" } else { 'unavailable' }
    $limited = @($row.limitations | Where-Object { $_ -notlike 'Unknown values*' -and $_ -notlike 'Implementation/review elapsed*' } | Select-Object -First 3)
    $lines += "| #$storyRef | $(Cell $row.prUrl) / $(Cell $row.reviewedHead) | $(Cell $row.reportState) | $(Cell $row.collection) | $(Cell $coverage); $(Cell ($limited -join '; ')) | $links |"
}
[ordered]@{ kind = 'epic_performance_report_index'; items = $rows; markdown = ($lines -join "`n") } | ConvertTo-Json -Depth 100
