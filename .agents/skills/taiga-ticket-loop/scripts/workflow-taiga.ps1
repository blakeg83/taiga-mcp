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
function Complete-Pages {
    param([object[]]$Pages,[string]$Name)
    if ($Pages.Count -eq 0) { throw "$Name has no captured pages." }
    $orderedPages = @($Pages | Sort-Object { [int]$_.page })
    for ($index = 0; $index -lt $orderedPages.Count; $index++) {
        $page = $orderedPages[$index]; if (-not $page.Contains('page')) { throw "$Name pagination is incomplete: page number missing." }
        $number = 0; if (-not [int]::TryParse([string]$page.page, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 1 -or $number -ne ($index + 1)) { throw "$Name pagination is incomplete: pages must be contiguous from page 1." }
        if (-not $page.Contains('hasMore') -or $null -eq $page.hasMore -or $page.hasMore -isnot [bool]) { throw "$Name pagination is incomplete: authoritative hasMore is required." }
        if (-not $page.Contains('nextPage')) { throw "$Name pagination is incomplete: authoritative nextPage is required." }
        $hasMore = [bool]$page.hasMore; $nextPage = $page.nextPage
        if ($hasMore) { if ($null -eq $nextPage -or [int]$nextPage -ne ($number + 1)) { throw "$Name pagination is incomplete: nextPage must identify the next page." }; if ($index -eq $orderedPages.Count - 1) { throw "$Name pagination is incomplete: page $($number + 1) was not fetched." } }
        else { if ($null -ne $nextPage) { throw "$Name pagination is contradictory: a terminal page cannot have nextPage." }; if ($index -ne $orderedPages.Count - 1) { throw "$Name pagination contains pages after its authoritative terminal page." } }
    }
    return $true
}

try {
    $input = Read-Object
    $data = switch ($Operation) {
        'capture-context' {
            $kind = [string](Need $input 'kind'); $projectId = [int](Need $input 'projectId'); $ref = [int](Need $input 'ref'); if ($projectId -lt 1 -or $ref -lt 1) { throw 'Project and ref must be positive.' }
            $null = Complete-Pages @($input.detailPages) 'detail'; $null = Complete-Pages @($input.commentPages) 'comments'
            if ($kind -eq 'story') { $null = Complete-Pages @($input.taskPages) 'tasks' }
            if ($kind -eq 'epic') { $null = Complete-Pages @($input.storyPages) 'epic membership'; if (@($input.storyPages).Count -eq 0) { throw 'Epic membership is incomplete.' } }
            [ordered]@{ complete = $true; projectId = $projectId; kind = $kind; ref = $ref; requirementsHash = Hash-Object @{ kind = $kind; projectId = $projectId; ref = $ref; detail = $input.detailPages; comments = $input.commentPages; tasks = $input.taskPages; stories = $input.storyPages }; selectedTaskIds = @($input.selectedTaskIds); linkedStoryKeys = @($input.linkedStoryKeys) }
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
