$script:ReviewReceiptSchema = $null

function Get-ReviewReceiptSchema {
    if ($null -eq $script:ReviewReceiptSchema) {
        $schemaPath = Join-Path $PSScriptRoot '..\references\review-receipt-v1.schema.json'
        try { $script:ReviewReceiptSchema = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $schemaPath) -AsHashtable -Depth 100 }
        catch { throw "Could not load review receipt schema: $($_.Exception.Message)" }
    }
    return $script:ReviewReceiptSchema
}

function Copy-ReceiptNode {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) { $copy[[string]$key] = Copy-ReceiptNode $Value[$key] }
        return $copy
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { [void]$items.Add((Copy-ReceiptNode $item)) }
        return ,$items.ToArray()
    }
    return $Value
}

function Get-ReceiptValueType {
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) { return 'object' }
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return 'string' }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) { return 'integer' }
    if ($Value -is [System.Collections.IEnumerable]) { return 'array' }
    return 'number'
}

function Test-ReceiptSchemaNode {
    param([object] $Value, [System.Collections.IDictionary] $Schema, [string] $Path, [System.Collections.Generic.List[string]] $Errors, [System.Collections.IDictionary] $RootSchema)
    if ($Schema.ContainsKey('$ref')) {
        $reference = [string]$Schema['$ref']
        if ($reference -notmatch '^#\/\$defs\/([A-Za-z0-9_-]+)$' -or -not $RootSchema['$defs'].Contains($Matches[1])) {
            [void]$Errors.Add("${Path}: schema reference is invalid")
            return
        }
        Test-ReceiptSchemaNode $Value $RootSchema['$defs'][$Matches[1]] $Path $Errors $RootSchema
        return
    }
    $actualType = Get-ReceiptValueType $Value
    if ($Schema.ContainsKey('type') -and $actualType -ne [string]$Schema.type) {
        [void]$Errors.Add("${Path}: expected $($Schema.type), got $actualType")
        return
    }
    if ($Schema.ContainsKey('const') -and (($Value -is [string] -and $Value -cne [string]$Schema['const']) -or ($Value -isnot [string] -and $Value -ne $Schema['const']))) { [void]$Errors.Add("${Path}: must equal '$($Schema['const'])'") }
    if ($Schema.ContainsKey('enum') -and @($Schema.enum) -cnotcontains $Value) { [void]$Errors.Add("${Path}: unsupported value '$Value'") }
    if ($actualType -eq 'string' -and $Schema.ContainsKey('minLength') -and $Value.Length -lt [int]$Schema.minLength) { [void]$Errors.Add("${Path}: must not be empty") }
    if ($actualType -eq 'integer' -and $Schema.ContainsKey('minimum') -and [decimal]$Value -lt [decimal]$Schema.minimum) { [void]$Errors.Add("${Path}: must be at least $($Schema.minimum)") }
    if ($actualType -eq 'object') {
        foreach ($requiredName in @($Schema.required)) {
            if (-not $Value.Contains([string]$requiredName)) { [void]$Errors.Add("${Path}.$($requiredName): is required") }
        }
        if ($Schema.ContainsKey('properties')) {
            foreach ($name in $Schema.properties.Keys) {
                if ($Value.Contains([string]$name)) { Test-ReceiptSchemaNode $Value[$name] $Schema.properties[$name] "$Path.$name" $Errors $RootSchema }
            }
        }
        if ($Schema.ContainsKey('additionalProperties') -and $Schema.additionalProperties -eq $false) {
            foreach ($name in $Value.Keys) {
                if (-not $Schema.properties.Contains([string]$name)) { [void]$Errors.Add("${Path}.$($name): is not an allowed field") }
            }
        }
    }
    if ($actualType -eq 'array') {
        if ($Schema.ContainsKey('minItems') -and @($Value).Count -lt [int]$Schema.minItems) { [void]$Errors.Add("${Path}: requires at least $($Schema.minItems) item(s)") }
        if ($Schema.ContainsKey('items')) {
            for ($index = 0; $index -lt @($Value).Count; $index++) { Test-ReceiptSchemaNode $Value[$index] $Schema.items "$Path[$index]" $Errors $RootSchema }
        }
    }
}

function Add-ReceiptNormalization {
    param([System.Collections.Generic.List[object]] $Normalizations, [string] $Path, [string] $From, [string] $To, [string] $Reason)
    [void]$Normalizations.Add([ordered]@{ path = $Path; from = $From; to = $To; reason = $Reason })
}

function Normalize-LegacyReviewReceipt {
    param([System.Collections.IDictionary] $Receipt, [object[]] $ExpectedCriteria, [System.Collections.Generic.List[object]] $Normalizations, [System.Collections.Generic.List[string]] $Errors)
    $normalized = Copy-ReceiptNode $Receipt
    if (-not $Receipt.Contains('schemaVersion')) {
        $normalized.schemaVersion = 1
        Add-ReceiptNormalization $Normalizations 'schemaVersion' 'missing (legacy)' '1' 'legacy review adapter'
    }
    if (-not $Receipt.Contains('kind')) {
        $normalized.kind = 'review'
        Add-ReceiptNormalization $Normalizations 'kind' 'missing (legacy)' 'review' 'legacy review adapter'
    }
    $criteria = @($normalized.criteria)
    for ($index = 0; $index -lt $criteria.Count; $index++) {
        $criterion = $criteria[$index]
        if ($criterion -isnot [System.Collections.IDictionary]) { continue }
        if (-not $criterion.Contains('text') -and $index -lt $ExpectedCriteria.Count -and $ExpectedCriteria[$index] -is [System.Collections.IDictionary] -and $ExpectedCriteria[$index].Contains('text')) {
            $criterion.text = [string]$ExpectedCriteria[$index].text
            Add-ReceiptNormalization $Normalizations "criteria[$index].text" 'missing (legacy)' 'packet criterion text' 'filled from the trusted expected-criteria set'
        }
    }
    $findings = @($normalized.findings)
    for ($index = 0; $index -lt $findings.Count; $index++) {
        $finding = $findings[$index]
        if ($finding -isnot [System.Collections.IDictionary]) { continue }
        $path = "findings[$index].disposition"
        if ($finding.Contains('unresolved') -and $finding.unresolved -isnot [bool]) { [void]$Errors.Add("findings[$index].unresolved: expected boolean legacy evidence") }
        if ($finding.Contains('isUnresolved') -and $finding.isUnresolved -isnot [bool]) { [void]$Errors.Add("findings[$index].isUnresolved: expected boolean legacy evidence") }
        $status = if ($finding.Contains('status')) { ([string]$finding.status).ToLowerInvariant() } else { $null }
        if ($null -ne $status -and $status -notin @('open','unresolved','needs_work','not_fixed','fixed','closed','resolved')) {
            [void]$Errors.Add("findings[$index].status: unsupported legacy status '$status'")
        }
        $contradictory = ($finding.unresolved -eq $true) -or ($finding.isUnresolved -eq $true) -or ($status -in @('open','unresolved','needs_work','not_fixed'))
        if ($contradictory -and $finding.Contains('disposition') -and $finding.disposition -in @('fixed','rejected_accepted','resolved')) {
            [void]$Errors.Add("${path}: disposition conflicts with unresolved evidence")
        }
        if ($finding.Contains('disposition') -and $finding.disposition -ceq 'resolved') {
            if ($Receipt.Contains('schemaVersion')) {
                [void]$Errors.Add("${path}: 'resolved' is accepted only by the legacy adapter")
            } elseif ($contradictory) {
                [void]$Errors.Add("${path}: 'resolved' conflicts with unresolved evidence")
            } else {
                $finding.disposition = 'fixed'
                Add-ReceiptNormalization $Normalizations $path 'resolved' 'fixed' 'legacy alias with no contradictory unresolved evidence'
            }
        } elseif (-not $finding.Contains('disposition')) {
            $finding.disposition = 'open'
            Add-ReceiptNormalization $Normalizations $path 'missing (legacy)' 'open' 'legacy findings default to unresolved'
        }
        foreach ($legacyField in @('status','unresolved','isUnresolved')) {
            if ($finding.Contains($legacyField)) {
                $null = $finding.Remove($legacyField)
                Add-ReceiptNormalization $Normalizations "findings[$index].$legacyField" 'legacy evidence' 'preserved in source receipt' 'legacy-only field removed from normalized v1 view'
            }
        }
    }
    return $normalized
}

function Get-ReviewReceiptValidation {
    param([object] $Receipt, [object[]] $ExpectedCriteria)
    $schema = Get-ReviewReceiptSchema
    $errors = [System.Collections.Generic.List[string]]::new()
    $normalizations = [System.Collections.Generic.List[object]]::new()
    if ($Receipt -isnot [System.Collections.IDictionary]) {
        return [ordered]@{ valid = $false; errors = @('receipt: expected object'); normalizations = @() }
    }
    $legacy = -not $Receipt.Contains('schemaVersion')
    $sourceReceipt = Copy-ReceiptNode $Receipt
    $normalized = if ($legacy) { Normalize-LegacyReviewReceipt $Receipt @($ExpectedCriteria) $normalizations $errors } else { Copy-ReceiptNode $Receipt }
    Test-ReceiptSchemaNode $normalized $schema['$defs']['review'] 'receipt' $errors $schema

    if ($normalized.Contains('reviewDelta') -and $normalized.reviewDelta -is [System.Collections.IDictionary]) {
        $delta = $normalized.reviewDelta
        if ($delta.documentationChanged -eq $true) {
            if ($delta.fromSha -ceq $delta.toSha) { [void]$errors.Add('receipt.reviewDelta.toSha: documentation amendments require a new committed revision') }
            if ([string]::IsNullOrWhiteSpace([string]$delta.documentationAssessment)) { [void]$errors.Add('receipt.reviewDelta.documentationAssessment: required when documentation changed') }
            if (@($delta.documentationPaths).Count -eq 0) { [void]$errors.Add('receipt.reviewDelta.documentationPaths: required when documentation changed') }
        }
        if (@($delta.reusedCheckIds).Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$delta.reuseJustification)) {
            [void]$errors.Add('receipt.reviewDelta.reuseJustification: required when verification checks are reused')
        }
    }

    $taskAcceptanceIds = @{}
    $taskAcceptances = if ($normalized.Contains('taskAcceptances')) { @($normalized.taskAcceptances) } else { @() }
    foreach ($acceptance in $taskAcceptances) {
        if ($acceptance -isnot [System.Collections.IDictionary]) { [void]$errors.Add('receipt.taskAcceptances: expected task acceptance objects'); continue }
        $taskId = 0L
        if (-not $acceptance.Contains('taskId') -or -not [long]::TryParse([string]$acceptance.taskId,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$taskId) -or $taskId -lt 1) { [void]$errors.Add('receipt.taskAcceptances.taskId: must be positive') }
        elseif ($taskAcceptanceIds.ContainsKey([string]$taskId)) { [void]$errors.Add("receipt.taskAcceptances.taskId: duplicate task '$taskId'") }
        else { $taskAcceptanceIds[[string]$taskId] = $true }
        if ($acceptance.accepted -ne $true -and [string]$normalized.verdict -notin @('changes_requested','blocked')) { [void]$errors.Add("receipt.taskAcceptances[$taskId].accepted: rejection is valid only for changes_requested or blocked receipts") }
        if ([string]$acceptance.reviewedSha -cne [string]$normalized.reviewedSha) { [void]$errors.Add("receipt.taskAcceptances[$taskId].reviewedSha: stale task review SHA") }
        if ($acceptance.criterionIds -is [string] -or $acceptance.criterionIds -isnot [System.Collections.IEnumerable] -or @($acceptance.criterionIds).Count -eq 0) { [void]$errors.Add("receipt.taskAcceptances[$taskId].criterionIds: at least one criterion is required") }
        if ([string]::IsNullOrWhiteSpace([string]$acceptance.evidence)) { [void]$errors.Add("receipt.taskAcceptances[$taskId].evidence: evidence is required") }
        if ($acceptance.accepted -ne $true) {
            if (-not $acceptance.Contains('rejectionReason') -or [string]::IsNullOrWhiteSpace([string]$acceptance.rejectionReason)) { [void]$errors.Add("receipt.taskAcceptances[$taskId].rejectionReason: required for a rejected task") }
            if (-not $acceptance.Contains('routedActionId') -or [string]::IsNullOrWhiteSpace([string]$acceptance.routedActionId)) { [void]$errors.Add("receipt.taskAcceptances[$taskId].routedActionId: same-worker correction action is required") }
        }
    }

    if ($null -eq $ExpectedCriteria -or @($ExpectedCriteria).Count -eq 0) {
        [void]$errors.Add('expectedCriteria: required trusted packet criteria with id and text')
    } else {
        $expected = @($ExpectedCriteria)
        for ($index = 0; $index -lt $expected.Count; $index++) {
            if ($expected[$index] -isnot [System.Collections.IDictionary]) {
                [void]$errors.Add("expectedCriteria[$index]: expected object with id and text")
                continue
            }
            foreach ($field in @('id','text')) {
                if (-not $expected[$index].Contains($field) -or [string]::IsNullOrWhiteSpace([string]$expected[$index][$field])) { [void]$errors.Add("expectedCriteria[$index].$($field): is required") }
            }
        }
        $expectedIds = @{}
        foreach ($index in 0..($expected.Count - 1)) {
            if ($expected[$index] -is [System.Collections.IDictionary] -and $expected[$index].Contains('id')) {
                $expectedId = [string]$expected[$index].id
                if ($expectedIds.ContainsKey($expectedId)) { [void]$errors.Add("expectedCriteria[$index].id: duplicate criterion '$expectedId'") }
                $expectedIds[$expectedId] = $true
            }
        }
        $actualCriteria = @($normalized.criteria)
        if ($actualCriteria.Count -ne $expected.Count) { [void]$errors.Add("receipt.criteria: expected $($expected.Count) packet criteria in packet order, got $($actualCriteria.Count)") }
        $actualIds = @{}
        for ($index = 0; $index -lt $actualCriteria.Count; $index++) {
            $actual = $actualCriteria[$index]
            if ($actual -is [System.Collections.IDictionary] -and $actual.Contains('id')) {
                $actualId = [string]$actual.id
                if ($actualIds.ContainsKey($actualId)) { [void]$errors.Add("receipt.criteria[$index].id: duplicate criterion '$actualId'") }
                $actualIds[$actualId] = $true
            }
        }
        for ($index = 0; $index -lt [Math]::Min($actualCriteria.Count, $expected.Count); $index++) {
            $actual = $actualCriteria[$index]
            $wanted = $expected[$index]
            if ($actual -isnot [System.Collections.IDictionary] -or $wanted -isnot [System.Collections.IDictionary]) { continue }
            if ($actual.id -cne $wanted.id) { [void]$errors.Add("receipt.criteria[$index].id: expected '$($wanted.id)' in packet order, got '$($actual.id)'") }
            if ($actual.text -cne $wanted.text) { [void]$errors.Add("receipt.criteria[$index].text: does not match the trusted packet text for '$($wanted.id)'") }
        }
    }

    $criterionFailures = @($normalized.criteria | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.passed -eq $false })
    $checkFailures = @($normalized.checks | Where-Object { $_ -is [System.Collections.IDictionary] -and ($_.exitCode -ne 0 -or ($_.Contains('passed') -and $_.passed -ne $true)) })
    $blocking = @($normalized.findings | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.severity -in @('blocker','critical','high') -and $_.disposition -notin @('fixed','rejected_accepted') })
    $findingIds = @{}
    for ($index = 0; $index -lt @($normalized.findings).Count; $index++) {
        $finding = $normalized.findings[$index]
        if ($finding -is [System.Collections.IDictionary] -and $finding.Contains('id')) {
            $findingId = [string]$finding.id
            if ($findingIds.ContainsKey($findingId)) { [void]$errors.Add("receipt.findings[$index].id: duplicate finding '$findingId'") }
            $findingIds[$findingId] = $true
        }
    }
    if ($normalized.verdict -eq 'pass' -and $criterionFailures.Count -gt 0) { [void]$errors.Add('receipt.verdict: pass requires every criterion to pass') }
    if ($normalized.verdict -eq 'pass' -and $checkFailures.Count -gt 0) { [void]$errors.Add('receipt.verdict: pass requires zero-exit passing checks') }
    if ($normalized.verdict -eq 'pass' -and $blocking.Count -gt 0) { [void]$errors.Add('receipt.findings: pass cannot retain unresolved blocker, critical, or high findings') }
    return [ordered]@{
        valid = ($errors.Count -eq 0)
        kind = 'review'
        schemaVersion = 1
        verdict = $normalized.verdict
        reviewedSha = $normalized.reviewedSha
        blockingFindingCount = $blocking.Count
        criterionFailureCount = $criterionFailures.Count
        checkFailureCount = $checkFailures.Count
        sourceReceipt = $sourceReceipt
        normalizedReceipt = $normalized
        normalizations = @($normalizations)
        errors = @($errors)
    }
}
