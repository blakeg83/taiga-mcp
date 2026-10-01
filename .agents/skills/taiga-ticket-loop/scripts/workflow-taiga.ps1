[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('capture-context','validate-status-mappings','prepare-write','reconcile-write','finalize')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'

function Read-Object { if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }; try { return ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" } }
function Need { param([hashtable]$Object,[string]$Name); if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }; return $Object[$Name] }
function Convert-ToCanonicalValue {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $canonical = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $canonical[$key] = Convert-ToCanonicalValue $Value[$key] }
        return $canonical
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $converted = Convert-ToCanonicalValue $item
            [void]$items.Add($converted)
        }
        return ,$items.ToArray()
    }
    return $Value
}
function Hash-Object { param([object]$Value); $bytes = [Text.Encoding]::UTF8.GetBytes((Convert-ToCanonicalValue $Value | ConvertTo-Json -Depth 100 -Compress)); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }
function Read-OptionalInteger {
    param([System.Collections.IDictionary] $Object, [string] $Name, [string] $Context, [long] $Minimum = 0)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name]) { return [ordered]@{ present = $false; value = $null } }
    $number = 0L
    if (-not [long]::TryParse([string]$Object[$Name], [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt $Minimum) { throw "$Context pagination is invalid: $Name must be an integer at least $Minimum." }
    return [ordered]@{ present = $true; value = $number }
}
function Get-PageAlias {
    param([System.Collections.IDictionary] $Page, [string[]] $Names, [string] $Context)
    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $Names) { if ($Page.Contains($name)) { [void]$values.Add([ordered]@{ name = $name; value = $Page[$name] }) } }
    if ($values.Count -gt 1) {
        $expected = if ($null -eq $values[0].value) { '<null>' } else { [string]$values[0].value }
        foreach ($entry in $values | Select-Object -Skip 1) {
            $actual = if ($null -eq $entry.value) { '<null>' } else { [string]$entry.value }
            if ($actual -ne $expected) { throw "$Context pagination is contradictory: aliases $($values[0].name) and $($entry.name) disagree." }
        }
    }
    if ($values.Count -eq 0) { return [ordered]@{ present = $false; value = $null } }
    return [ordered]@{ present = $true; value = $values[0].value }
}
function Complete-Pages {
    param([object[]]$Pages,[string]$Name)
    if ($Pages.Count -eq 0) { throw "$Name has no captured pages." }
    $orderedPages = [System.Collections.Generic.List[object]]::new()
    $seenPages = [System.Collections.Generic.HashSet[long]]::new()
    $anyTotals = $false
    foreach ($page in $Pages) {
        if ($page -isnot [System.Collections.IDictionary]) { throw "$Name pagination is incomplete: page metadata must be an object." }
        $pageNumberField = Get-PageAlias $page @('page', 'currentPage', 'x-pagination-current') $Name
        if (-not $pageNumberField.present) { throw "$Name pagination is incomplete: page number missing." }
        $number = 0L
        if (-not [long]::TryParse([string]$pageNumberField.value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 1) { throw "$Name pagination is incomplete: page number must be positive." }
        if (-not $seenPages.Add($number)) { throw "$Name pagination is contradictory: duplicate page $number." }
        $hasMoreField = Get-PageAlias $page @('hasMore', 'has_more') $Name
        $hasMoreKnown = $hasMoreField.present -and $null -ne $hasMoreField.value
        if ($hasMoreKnown -and $hasMoreField.value -isnot [bool]) { throw "$Name pagination is invalid: hasMore must be boolean or null." }
        $nextField = Get-PageAlias $page @('nextPage', 'next_page', 'x-pagination-next') $Name
        $nextKnowledgeField = Get-PageAlias $page @('nextPageKnown', 'next_page_known') $Name
        if ($nextKnowledgeField.present -and $nextKnowledgeField.value -isnot [bool]) { throw "$Name pagination is invalid: nextPageKnown must be boolean." }
        if ($nextKnowledgeField.value -eq $true -and -not $nextField.present) { throw "$Name pagination is invalid: nextPageKnown requires a nextPage field." }
        if ($nextKnowledgeField.value -eq $false -and $nextField.present -and $null -ne $nextField.value) { throw "$Name pagination is contradictory: nextPage is present while nextPageKnown is false." }
        $nextPage = $null
        if ($nextField.present -and $null -ne $nextField.value) {
            $nextPage = 0L
            if (-not [long]::TryParse([string]$nextField.value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$nextPage) -or $nextPage -lt 1) { throw "$Name pagination is invalid: nextPage must be a positive page number or null." }
        }
        $nextKnown = ($null -ne $nextPage) -or ($nextKnowledgeField.present -and $nextKnowledgeField.value -eq $true)
        $totalField = Get-PageAlias $page @('totalCount', 'total', 'x-pagination-count') $Name
        $pageSizeField = Get-PageAlias $page @('pageSize', 'page_size', 'perPage', 'x-paginated-by') $Name
        $itemCountField = Get-PageAlias $page @('itemCount', 'item_count') $Name
        if (-not $itemCountField.present -and $page.Contains('items') -and $page.items -isnot [string] -and $page.items -is [System.Collections.IEnumerable]) { $itemCountField = [ordered]@{ present = $true; value = @($page.items).Count } }
        $normalizedCounts = [ordered]@{ totalCount = if ($totalField.present) { $totalField.value } else { $null }; pageSize = if ($pageSizeField.present) { $pageSizeField.value } else { $null }; itemCount = if ($itemCountField.present) { $itemCountField.value } else { $null } }
        $total = Read-OptionalInteger $normalizedCounts 'totalCount' $Name
        $pageSize = Read-OptionalInteger $normalizedCounts 'pageSize' $Name 1
        $itemCount = Read-OptionalInteger $normalizedCounts 'itemCount' $Name
        if ($total.present) { $anyTotals = $true }
        $itemIds = @()
        if ($page.Contains('itemIds')) {
            if ($page.itemIds -is [string] -or $page.itemIds -isnot [System.Collections.IEnumerable]) { throw "$Name pagination is invalid: itemIds must be an array." }
            $itemIds = @($page.itemIds | ForEach-Object { [string]$_ })
            if (@($itemIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw "$Name pagination is invalid: itemIds cannot contain blank values." }
        } elseif ($page.Contains('items') -and $page.items -isnot [string] -and $page.items -is [System.Collections.IEnumerable]) {
            $itemsWithIds = @($page.items | Where-Object { $_ -is [System.Collections.IDictionary] -and ($_.Contains('id') -or $_.Contains('user_story_id') -or $_.Contains('task_id')) })
            if ($itemsWithIds.Count -eq @($page.items).Count) {
                $itemIds = @($itemsWithIds | ForEach-Object { if ($_.Contains('id')) { [string]$_.id } elseif ($_.Contains('user_story_id')) { [string]$_.user_story_id } else { [string]$_.task_id } })
            }
        }
        [void]$orderedPages.Add([ordered]@{ number = $number; page = $page; hasMoreKnown = $hasMoreKnown; hasMore = if ($hasMoreKnown) { [bool]$hasMoreField.value } else { $null }; nextKnown = $nextKnown; nextPage = $nextPage; total = $total; pageSize = $pageSize; itemCount = $itemCount; itemIds = $itemIds })
    }
    $orderedPages.Sort([System.Collections.Generic.Comparer[object]]::Create([System.Comparison[object]]{ param($left, $right) [long]$left.number - [long]$right.number }))
    for ($index = 0; $index -lt $orderedPages.Count; $index++) { if ($orderedPages[$index].number -ne ($index + 1)) { throw "$Name pagination is incomplete: pages must be contiguous from page 1." } }

    if ($anyTotals) {
        foreach ($entry in $orderedPages) {
            if (-not $entry.total.present -or -not $entry.itemCount.present) { throw "$Name pagination is incomplete: totalCount and itemCount must be present on every page when total metadata is used." }
        }
        $totalCount = [long]$orderedPages[0].total.value
        $hasPageSize = $orderedPages[0].pageSize.present
        $pageSize = if ($hasPageSize) { [long]$orderedPages[0].pageSize.value } else { $null }
        foreach ($entry in $orderedPages) {
            if ($entry.total.value -ne $totalCount) { throw "$Name pagination is contradictory: totalCount changed between pages." }
            if ($entry.pageSize.present -ne $hasPageSize) { throw "$Name pagination is incomplete: pageSize must be present on every page or none." }
            if ($hasPageSize -and $entry.pageSize.value -ne $pageSize) { throw "$Name pagination is contradictory: pageSize changed between pages." }
        }
        $seenItemIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $cumulativeItemCount = 0L
        foreach ($entry in $orderedPages) {
            $cumulativeItemCount += [long]$entry.itemCount.value
            if ($hasPageSize -and $entry.itemCount.value -gt $pageSize) { throw "$Name pagination is contradictory: itemCount exceeds pageSize on page $($entry.number)." }
            if ($cumulativeItemCount -gt $totalCount) { throw "$Name pagination is contradictory: captured itemCount exceeds totalCount." }
            $expectedMore = $cumulativeItemCount -lt $totalCount
            if ($entry.hasMoreKnown -and $entry.hasMore -ne $expectedMore) { throw "$Name pagination is contradictory: hasMore disagrees with authoritative totals on page $($entry.number)." }
            if ($entry.nextKnown -and (($expectedMore -and $entry.nextPage -ne ($entry.number + 1)) -or (-not $expectedMore -and $null -ne $entry.nextPage))) { throw "$Name pagination is contradictory: nextPage disagrees with authoritative totals on page $($entry.number)." }
            if (-not $expectedMore -and $entry.number -ne $orderedPages.Count) { throw "$Name pagination contains pages after the authoritative total was reached." }
            if ($entry.itemIds.Count -gt 0) {
                if ($entry.itemCount.present -and $entry.itemIds.Count -ne $entry.itemCount.value) { throw "$Name pagination is contradictory: itemIds and itemCount differ on page $($entry.number)." }
                foreach ($itemId in $entry.itemIds) { if (-not $seenItemIds.Add($itemId)) { throw "$Name pagination is contradictory: duplicate item ID across pages: $itemId." } }
            }
        }
        if ($cumulativeItemCount -ne $totalCount) { throw "$Name pagination is incomplete: captured $cumulativeItemCount of $totalCount authoritative items." }
        return [ordered]@{ complete = $true; basis = 'authoritative_total_count'; pageCount = $orderedPages.Count; totalCount = $totalCount; pageSize = $pageSize }
    }

    $terminalSeen = $false
    $basisSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $orderedPages) {
        if ($terminalSeen) { throw "$Name pagination contains pages after its authoritative terminal page." }
        $moreKnown = $entry.hasMoreKnown -or $entry.nextKnown
        if (-not $moreKnown) { throw "$Name pagination is incomplete: hasMore, nextPage, and trustworthy totals are unavailable." }
        $moreFromNext = $entry.nextKnown -and $null -ne $entry.nextPage
        if ($entry.hasMoreKnown -and $entry.nextKnown -and $entry.hasMore -ne $moreFromNext) { throw "$Name pagination is contradictory: hasMore and nextPage disagree on page $($entry.number)." }
        $hasMore = if ($entry.hasMoreKnown) { $entry.hasMore } else { $moreFromNext }
        if ($entry.hasMoreKnown) { [void]$basisSet.Add('has_more') }
        if ($entry.nextKnown) { [void]$basisSet.Add('next_page') }
        if ($hasMore) {
            if (-not $entry.nextKnown -or $entry.nextPage -ne ($entry.number + 1)) { throw "$Name pagination is incomplete: nextPage must identify page $($entry.number + 1)." }
            if ($entry.number -eq $orderedPages.Count) { throw "$Name pagination is incomplete: page $($entry.number + 1) was not fetched." }
        } else {
            $terminalSeen = $true
            if ($entry.nextKnown -and $null -ne $entry.nextPage) { throw "$Name pagination is contradictory: a terminal page has a nextPage." }
            if ($entry.number -ne $orderedPages.Count) { throw "$Name pagination contains pages after its authoritative terminal page." }
        }
    }
    return [ordered]@{ complete = $true; basis = if ($basisSet.Count -gt 1) { 'combined_page_metadata' } elseif ($basisSet.Contains('has_more')) { 'has_more' } else { 'next_page' }; pageCount = $orderedPages.Count; totalCount = $null; pageSize = $null }
}

try {
    $input = Read-Object
    $data = switch ($Operation) {
        'capture-context' {
            $kind = [string](Need $input 'kind'); $projectId = [int](Need $input 'projectId'); $ref = [int](Need $input 'ref'); if ($projectId -lt 1 -or $ref -lt 1) { throw 'Project and ref must be positive.' }
            $pagination = [ordered]@{ detail = Complete-Pages @($input.detailPages) 'detail'; comments = Complete-Pages @($input.commentPages) 'comments' }
            if ($kind -eq 'story') { $pagination.tasks = Complete-Pages @($input.taskPages) 'tasks' }
            if ($kind -eq 'epic') { $pagination.stories = Complete-Pages @($input.storyPages) 'epic membership'; if (@($input.storyPages).Count -eq 0) { throw 'Epic membership is incomplete.' } }
            [ordered]@{ complete = $true; projectId = $projectId; kind = $kind; ref = $ref; pagination = $pagination; requirementsHash = Hash-Object @{ kind = $kind; projectId = $projectId; ref = $ref; detail = $input.detailPages; comments = $input.commentPages; tasks = $input.taskPages; stories = $input.storyPages }; selectedTaskIds = @($input.selectedTaskIds); linkedStoryKeys = @($input.linkedStoryKeys) }
        }
        'validate-status-mappings' {
            $mappings = Need $input 'statusMappings'; $errors = @()
            foreach ($kind in @('issue','task','story','epic')) { if (-not $mappings.Contains($kind)) { $errors += "Missing status mapping for $kind"; continue }; $map = $mappings[$kind]; foreach ($name in @('start','review','awaitingMerge','done')) { if (-not $map.Contains($name) -or [int]$map[$name] -lt 1) { $errors += "Missing $kind.$name status" } }; $ids = @($map.Values | ForEach-Object { [int]$_ }); if (($ids | Group-Object | Where-Object Count -gt 1).Count -gt 0) { $errors += "Ambiguous duplicate status IDs for $kind" } }
            [ordered]@{ valid = ($errors.Count -eq 0); errors = $errors }
        }
        'prepare-write' {
            $kind = [string](Need $input 'writeKind'); $target = Need $input 'target'; $version = [int](Need $input 'version'); if ($version -lt 0) { throw 'Version must be nonnegative.' }; $payload = Need $input 'payload'; $marker = Need $input 'runMarker'; if ([string]$payload -match '(?i)(password|token|secret)' -or [string]$payload -match '(?i)raw.?log') { throw 'Unsafe credential or raw-log content is not allowed in a milestone write.' }; [ordered]@{ actionKind = "taiga_$kind"; target = $target; version = $version; runMarker = $marker; payload = $payload; inputDigest = Hash-Object @{ target = $target; version = $version; payload = $payload } }
        }
        'reconcile-write' {
            if ($input.Contains('versionConflict') -and $input.versionConflict -eq $true) { [ordered]@{ state = 'conflict'; action = 'reread_and_evaluate'; blindRetry = $false } }
            elseif ($input.Contains('responseLost') -and $input.responseLost -eq $true) { [ordered]@{ state = 'uncertain'; action = 'inspect_detail_history_comments'; blindRetry = $false } }
            elseif ($input.Contains('observed') -and $input.observed -eq $true) { [ordered]@{ state = 'confirmed'; action = 'record_receipt'; blindRetry = $false } }
            else { [ordered]@{ state = 'needs_input'; action = 'reconcile_external_state'; blindRetry = $false } }
        }
        'finalize' {
            $errors = @(); if ((Need $input 'requirementsHash') -ne (Need $input 'currentRequirementsHash')) { $errors += 'Requirements changed.' }; if (-not $input.criteriaComplete) { $errors += 'Criteria are incomplete.' }; if (-not $input.checksPass) { $errors += 'Required checks did not pass.' }; if ($input.completionPolicy -eq 'merged' -and $input.prState -ne 'merged') { $errors += 'Observed PR is not merged.' }; if ($input.kind -eq 'epic' -and (-not $input.allStoriesMerged -or -not $input.epicAccepted)) { $errors += 'Epic requires all merged stories and integrated acceptance.' }; [ordered]@{ ready = ($errors.Count -eq 0); errors = $errors; taigaDoneMayBeSelected = ($errors.Count -eq 0) }
        }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $data } | ConvertTo-Json -Depth 100; exit 0
} catch { [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_taiga'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20; exit 1 }
