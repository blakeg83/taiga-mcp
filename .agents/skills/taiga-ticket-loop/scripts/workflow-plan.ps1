[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('validate-scope','ready-tickets','validate-epic','validate-pr')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'

function Read-Object {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }
    try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
}

function Require-Field { param([hashtable]$Object,[string]$Name); if (-not $Object.Contains($Name) -or $null -eq $Object[$Name]) { throw "$Name is required." }; return $Object[$Name] }
function Key-Of { param([hashtable]$Item); if ($Item.Contains('ticketKey')) { return [string]$Item.ticketKey }; return "project:$($Item.projectId):$($Item.kind):$($Item.id)" }

function Test-Cycle {
    param([hashtable] $Graph, [string] $Node, [hashtable] $Visiting, [hashtable] $Visited)
    if ($Visiting.Contains($Node)) { return $true }
    if ($Visited.Contains($Node)) { return $false }
    $Visiting[$Node] = $true
    if ($Graph.Contains($Node)) { foreach ($dependency in @($Graph[$Node])) { if (Test-Cycle $Graph ([string]$dependency) $Visiting $Visited) { return $true } } }
    $null = $Visiting.Remove($Node); $Visited[$Node] = $true; return $false
}

try {
    $input = Read-Object
    $output = switch ($Operation) {
        'validate-scope' {
            $scope = @((Require-Field $input 'scope')); $keys = @{}; $errors = @(); $repositories = @{}
            foreach ($item in $scope) {
                $key = Key-Of $item
                if ($keys.Contains($key)) { $errors += "Duplicate selected ticket: $key" } else { $keys[$key] = $true }
                if (-not $item.Contains('repository') -and -not $item.Contains('repositoryIdentity')) { $errors += "Unmapped repository: $key" }
                if ($item.kind -in @('task','child_task') -and -not $item.Contains('parentTicketKey')) { $errors += "Child task has no owning story: $key" }
                if ($item.Contains('repository')) { $repositories[[string]$item.repository] = $true }
            }
            $graph = @{}
            foreach ($edge in @($input.dependencies)) { $from = [string](Require-Field $edge 'ticketKey'); $to = [string](Require-Field $edge 'dependsOn'); if (-not $keys.Contains($from) -or -not $keys.Contains($to)) { $errors += "Dependency references missing selected ticket: $from -> $to" }; if (-not $graph.Contains($from)) { $graph[$from] = @() }; $graph[$from] = @($graph[$from]) + $to }
            $visiting = @{}; $visited = @{}; foreach ($node in $graph.Keys) { if (Test-Cycle $graph $node $visiting $visited) { $errors += "Dependency cycle includes $node"; break } }
            [ordered]@{ valid = ($errors.Count -eq 0); errors = $errors; selectedCount = $scope.Count; repositoryCount = $repositories.Count; keys = @($keys.Keys) }
        }
        'ready-tickets' {
            $scope = @((Require-Field $input 'scope')); $merged = @($input.mergedDependencies | ForEach-Object { [string]$_ }); $blocked = @($input.blocked | ForEach-Object { [string]$_ }); $capacity = if ($input.Contains('capacity')) { [int]$input.capacity } else { 2 }; $active = if ($input.Contains('active')) { [int]$input.active } else { 0 }
            $edges = @($input.dependencies); $ready = @(); $waiting = @()
            foreach ($item in $scope | Sort-Object @{Expression={ if ($_.priority -ne $null) { [int]$_.priority } else { 100000 } }}, @{Expression={ [string](Key-Of $_) }}) { $key = Key-Of $item; $deps = @($edges | Where-Object { [string]$_.ticketKey -eq $key } | ForEach-Object { [string]$_.dependsOn }); if ($blocked -contains $key -or ($deps | Where-Object { $merged -notcontains $_ }).Count -gt 0) { $waiting += $key } else { $ready += $item } }
            $selected = if ($active -ge $capacity) { @() } else { @($ready | Select-Object -First ($capacity - $active)) }
            [ordered]@{ ready = @($selected | ForEach-Object { Key-Of $_ }); waiting = $waiting; capacity = $capacity; active = $active; dispatchable = ($selected.Count -gt 0) }
        }
        'validate-epic' {
            $stories = @((Require-Field $input 'requiredStories')); $errors = @(); $seen = @{}
            foreach ($story in $stories) { $key = Key-Of $story; if ($seen.Contains($key)) { $errors += "Story appears more than once: $key" }; $seen[$key] = $true; if (-not $story.Contains('repository')) { $errors += "Story is unmapped: $key" }; if ($story.completion -notin @('merged','accepted_existing','in_progress')) { $errors += "Unsupported story evidence for $key" } }
            $complete = $stories.Count -gt 0 -and $errors.Count -eq 0 -and @($stories | Where-Object { $_.completion -notin @('merged','accepted_existing') }).Count -eq 0
            [ordered]@{ valid = ($errors.Count -eq 0); complete = $complete; errors = $errors; requiredStoryCount = $stories.Count; stories = @($seen.Keys) }
        }
        'validate-pr' {
            $prs = @((Require-Field $input 'pullRequests')); $repo = [string](Require-Field $input 'repository'); $head = [string](Require-Field $input 'head'); $base = [string](Require-Field $input 'base'); $matches = @($prs | Where-Object { $_.repository -eq $repo -and $_.head -eq $head -and $_.base -eq $base }); if ($matches.Count -gt 1) { throw 'Multiple matching pull requests require user reconciliation.' }; [ordered]@{ valid = $true; found = ($matches.Count -eq 1); pullRequest = if ($matches.Count -eq 1) { $matches[0] } else { $null } }
    }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $output } | ConvertTo-Json -Depth 100
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_plan'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
