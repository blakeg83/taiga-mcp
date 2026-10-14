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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$maxLineBytes = 16MB
$script:BindingDiagnostics = [System.Collections.Generic.List[object]]::new()
. (Join-Path $PSScriptRoot 'format-story-performance-utc.ps1')

function Add-BindingDiagnostic {
    param(
        [Parameter(Mandatory)] [string] $Category,
        [AllowNull()] [string] $Role,
        [AllowNull()] [string] $SessionId,
        [AllowNull()] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $Reason
    )

    $diagnostic = [ordered]@{
        category = $Category
        role = $Role
        sessionId = $SessionId
        sourcePath = $SourcePath
        reason = $Reason
    }
    $key = ConvertTo-CanonicalJson $diagnostic
    foreach ($existing in @($script:BindingDiagnostics)) {
        if ((ConvertTo-CanonicalJson $existing) -ceq $key) { return }
    }
    [void] $script:BindingDiagnostics.Add([pscustomobject] $diagnostic)
}

function Get-Value {
    param([AllowNull()] [object] $Object, [Parameter(Mandatory)] [string] $Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-JsonFile {
    param([Parameter(Mandatory)] [string] $Path)
    $text = [IO.File]::ReadAllText($Path, $utf8)
    return $text | ConvertFrom-Json -Depth 100 -DateKind String
}

function Parse-Utc {
    param([AllowNull()] [object] $Value)
    $parsed = [DateTimeOffset]::MinValue
    if ($null -eq $Value -or -not [DateTimeOffset]::TryParse([string] $Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref] $parsed)) {
        return $null
    }
    return $parsed.ToUniversalTime()
}

function New-CounterMap {
    return [ordered]@{
        inputTokens = 0L
        cachedInputTokens = 0L
        outputTokens = 0L
        reasoningTokens = 0L
    }
}

function Get-CounterMap {
    param([AllowNull()] [object] $Usage)
    $map = New-CounterMap
    $input = Get-Value $Usage 'input_tokens'
    $cached = Get-Value $Usage 'cached_input_tokens'
    $output = Get-Value $Usage 'output_tokens'
    $reasoning = Get-Value $Usage 'reasoning_output_tokens'
    foreach ($pair in @(
            @{ name = 'inputTokens'; value = $input },
            @{ name = 'cachedInputTokens'; value = $cached },
            @{ name = 'outputTokens'; value = $output },
            @{ name = 'reasoningTokens'; value = $reasoning })) {
        if ($null -eq $pair.value -or $pair.value -is [bool] -or $pair.value -isnot [ValueType]) { return $null }
        try { $number = [long] $pair.value } catch { return $null }
        if ($number -lt 0) { return $null }
        $map[$pair.name] = $number
    }
    return $map
}

function Copy-CounterMap {
    param([Parameter(Mandatory)] [object] $Counters)
    $copy = New-CounterMap
    foreach ($name in @($copy.Keys)) { $copy[$name] = [long] (Get-Value $Counters $name) }
    return $copy
}

function New-Sample {
    param(
        [Parameter(Mandatory)] [DateTimeOffset] $Time,
        [Parameter(Mandatory)] [object] $Counters,
        [Parameter(Mandatory)] [int] $ResetCount
    )
    return [pscustomobject][ordered]@{
        sampledAtUtc = Format-StoryPerformanceUtcTimestamp -Timestamp $Time
        counters = Copy-CounterMap $Counters
        resetCount = $ResetCount
    }
}

function Convert-ToCanonicalValue {
    param([AllowNull()] [object] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object { [string] $_ })) { $ordered[[string] $key] = Convert-ToCanonicalValue $Value[$key] }
        return $ordered
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) { $ordered[$property.Name] = Convert-ToCanonicalValue $property.Value }
        return $ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Convert-ToCanonicalValue $_ })
    }
    return $Value
}

function Convert-ToCanonicalJson {
    param([AllowNull()] [object] $Value)
    return Convert-ToCanonicalValue $Value | ConvertTo-Json -Compress -Depth 100
}

function Get-Sha256HexText {
    param([Parameter(Mandatory)] [string] $Text)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($hash.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))).ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-Sha256HexBytes {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($hash.ComputeHash($Bytes)).ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-V2BoundaryFrameError {
    param(
        [Parameter(Mandatory)] [object] $Frame,
        [Parameter(Mandatory)] [string] $Line,
        [Parameter(Mandatory)] [long] $FrameStartOffset,
        [Parameter(Mandatory)] [long] $FrameEndOffset,
        [Parameter(Mandatory)] [long] $PreviousFrameEndOffset,
        [Parameter(Mandatory)] [string] $PreviousCommitDigest,
        [Parameter(Mandatory)] [long] $PreviousRecordCount,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $OrphanBytes
    )
    try {
        $event = Get-Value $Frame 'event'; $anchor = Get-Value $Frame 'anchor'
        if ([int] (Get-Value $Frame 'schemaVersion') -ne 2 -or [string] (Get-Value $Frame 'kind') -cne 'story_performance_event_frame' -or $null -eq $event -or $null -eq $anchor) { return 'invalid v2 frame envelope' }
        $payload = [ordered]@{
            schemaVersion = [int] (Get-Value $anchor 'schemaVersion')
            kind = [string] (Get-Value $anchor 'kind')
            frameStartOffset = [long] (Get-Value $anchor 'frameStartOffset')
            previousFrameEndOffset = [long] (Get-Value $anchor 'previousFrameEndOffset')
            previousCommitDigest = [string] (Get-Value $anchor 'previousCommitDigest')
            orphanSuffixDigest = [string] (Get-Value $anchor 'orphanSuffixDigest')
            eventDigest = [string] (Get-Value $anchor 'eventDigest')
            contentChainDigest = [string] (Get-Value $anchor 'contentChainDigest')
            recordCount = [long] (Get-Value $anchor 'recordCount')
            integrityRootHash = [string] (Get-Value $anchor 'integrityRootHash')
            frameByteLength = [long] (Get-Value $anchor 'frameByteLength')
        }
        $eventDigest = Get-Sha256HexText (Convert-ToCanonicalJson $event)
        foreach ($digest in @($payload.previousCommitDigest, $payload.orphanSuffixDigest, $payload.eventDigest, $payload.contentChainDigest, $payload.integrityRootHash, [string] (Get-Value $anchor 'commitDigest'))) { if ($digest -notmatch '^[0-9a-f]{64}$') { return 'invalid v2 frame digest' } }
        if ($payload.kind -cne 'story_performance_ledger_commit' -or $payload.schemaVersion -ne 2 -or $payload.frameStartOffset -ne $FrameStartOffset -or $payload.previousFrameEndOffset -ne $PreviousFrameEndOffset -or $payload.previousCommitDigest -cne $PreviousCommitDigest -or $payload.recordCount -ne ($PreviousRecordCount + 1L) -or $payload.frameByteLength -ne ($FrameEndOffset - $FrameStartOffset) -or $payload.frameByteLength -ne ([Text.UTF8Encoding]::new($false).GetByteCount($Line + [Environment]::NewLine)) -or $payload.eventDigest -cne $eventDigest -or $payload.orphanSuffixDigest -cne (Get-Sha256HexBytes $OrphanBytes)) { return 'v2 frame anchor does not bind exact committed bytes' }
        $expectedCommit = Get-Sha256HexText ("story_performance_ledger_v2_commit_v1|$(Convert-ToCanonicalJson $payload)")
        if ([string] (Get-Value $anchor 'commitDigest') -cne $expectedCommit) { return 'invalid v2 commit digest' }
        $expectedChain = Get-Sha256HexText ("story_performance_ledger_v2_chain_v1|$PreviousCommitDigest|$($payload.orphanSuffixDigest)|$eventDigest|$($payload.recordCount)")
        if ($payload.contentChainDigest -cne $expectedChain) { return 'invalid v2 content chain' }
        return $null
    }
    catch { return 'v2 frame validation failed' }
}

function Get-Boundaries {
    param([Parameter(Mandatory)] [string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $events = [System.Collections.Generic.List[object]]::new()
    $utf8Strict = [Text.UTF8Encoding]::new($false, $true)
    $lineStart = 0L
    $v2Mode = $false
    $previousCommitDigest = Get-Sha256HexText 'story_performance_ledger_v2_genesis'
    $previousFrameEndOffset = 0L
    $previousRecordCount = 0L
    for ($offset = 0; $offset -lt $bytes.Length; $offset++) {
        if ($bytes[$offset] -ne [byte] 0x0A) { continue }
        $contentLength = [int] ($offset - $lineStart)
        if ($contentLength -gt 0 -and $bytes[$offset - 1] -eq [byte] 0x0D) { $contentLength-- }
        $lineBytes = [byte[]]::new($contentLength)
        if ($contentLength -gt 0) { [Array]::Copy($bytes, [int] $lineStart, $lineBytes, 0, $contentLength) }
        try { $line = $utf8Strict.GetString($lineBytes); $candidate = $line | ConvertFrom-Json -Depth 100 -DateKind String }
        catch { $lineStart = $offset + 1L; continue }
        $frameKind = [int] (Get-Value $candidate 'schemaVersion') -eq 2 -and [string] (Get-Value $candidate 'kind') -ceq 'story_performance_event_frame'
        if ($frameKind) {
            $v2Mode = $true
            $frameStartOffset = [long] $lineStart
            $frameEndOffset = [long] ($offset + 1L)
            $orphanBytes = [byte[]]::new([int] ($frameStartOffset - $previousFrameEndOffset))
            if ($orphanBytes.Length -gt 0) { [Array]::Copy($bytes, [int] $previousFrameEndOffset, $orphanBytes, 0, $orphanBytes.Length) }
            $error = Get-V2BoundaryFrameError -Frame $candidate -Line $line -FrameStartOffset $frameStartOffset -FrameEndOffset $frameEndOffset -PreviousFrameEndOffset $previousFrameEndOffset -PreviousCommitDigest $previousCommitDigest -PreviousRecordCount $previousRecordCount -OrphanBytes $orphanBytes
            if ($null -eq $error) {
                $event = Get-Value $candidate 'event'; [void] $events.Add($event)
                $previousCommitDigest = [string] (Get-Value (Get-Value $candidate 'anchor') 'commitDigest')
                $previousFrameEndOffset = $frameEndOffset
                $previousRecordCount = [long] (Get-Value (Get-Value $candidate 'anchor') 'recordCount')
            }
        }
        elseif ($v2Mode -or $line -like '{"schemaVersion":2,"kind":"*') {
            # Complete unknown/malformed v2 lines are orphan bytes, not lifecycle events.
        }
        else {
            [void] $events.Add($candidate)
        }
        $lineStart = $offset + 1L
    }
    $starts = @($events | Where-Object { [string] (Get-Value $_ 'eventType') -ceq 'story_started' })
    $ends = @($events | Where-Object { [string] (Get-Value $_ 'eventType') -ceq 'pr_ready' })
    $start = $starts | Sort-Object { Parse-Utc (Get-Value $_ 'occurredAtUtc') } | Select-Object -First 1
    $end = $ends | Sort-Object { Parse-Utc (Get-Value $_ 'occurredAtUtc') } | Select-Object -Last 1
    $startUtc = if ($null -ne $start) { Parse-Utc (Get-Value $start 'occurredAtUtc') } else { $null }
    $endUtc = if ($null -ne $end) { Parse-Utc (Get-Value $end 'occurredAtUtc') } else { $null }
    if ($null -eq $startUtc -or $null -eq $endUtc -or $endUtc -lt $startUtc) {
        throw [InvalidOperationException]::new('story_usage_boundary_unavailable: story_started and pr_ready UTC boundaries are required')
    }
    $identities = @($events | ForEach-Object { [pscustomobject]@{
                runId = [string] (Get-Value $_ 'runId')
                projectId = [int] (Get-Value $_ 'projectId')
                storyId = [int] (Get-Value $_ 'storyId')
            } } | Sort-Object runId, projectId, storyId -Unique)
    if ($identities.Count -ne 1) { throw [InvalidOperationException]::new('story_usage_boundary_conflict: event ledger identity is not singular') }
    return [pscustomobject]@{
        runId = $identities[0].runId
        projectId = $identities[0].projectId
        storyId = $identities[0].storyId
        startUtc = $startUtc
        endUtc = $endUtc
    }
}

function Resolve-ObservedSourcePath {
    param([Parameter(Mandatory)] [object] $Evidence)

    $declaredPath = [string] (Get-Value $Evidence 'sourcePath')
    if (Test-Path -LiteralPath $declaredPath -PathType Leaf) { return $declaredPath }
    $sessionId = [string] (Get-Value $Evidence 'sessionId')
    if ([string]::IsNullOrWhiteSpace($sessionId)) { return $declaredPath }
    $fileName = [IO.Path]::GetFileName($declaredPath)
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $declaredPath }
    $match = [regex]::Match($declaredPath, '^(?<root>.*?)[\\/](?:sessions|archived_sessions)(?:[\\/]|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $declaredPath }
    $sessionRoot = Join-Path $match.Groups['root'].Value 'sessions'
    $archivedRoot = Join-Path $match.Groups['root'].Value 'archived_sessions'
    $candidates = @()
    foreach ($root in @($sessionRoot, $archivedRoot)) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            $candidates += @(Get-ChildItem -LiteralPath $root -Filter $fileName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
    }
    $exact = @($candidates | Where-Object {
            [IO.Path]::GetFileNameWithoutExtension($_).EndsWith("-$sessionId", [StringComparison]::OrdinalIgnoreCase)
        })
    if ($exact.Count -eq 1) { return [string] $exact[0] }
    return $declaredPath
}

function New-SessionState {
    param([Parameter(Mandatory)] [object] $Evidence)
    return [pscustomobject][ordered]@{
        role = [string] (Get-Value $Evidence 'role')
        scope = [string] (Get-Value $Evidence 'scope')
        sessionId = [string] (Get-Value $Evidence 'sessionId')
        sourcePath = [string] (Get-Value $Evidence 'sourcePath')
        byteOffset = 0L
        completeLines = 0L
        invalidRecords = 0L
        resetCount = 0
        fileResetCount = 0
        sourceSessionVerified = $false
        tokenStream = $null
        boundaryStartUtc = $null
        boundaryEndUtc = $null
        latestSample = $null
        startExact = $null
        startAfter = $null
        startBefore = $null
        endExact = $null
        endBefore = $null
        endAfter = $null
    }
}

function Update-BoundarySample {
    param(
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [object] $Sample,
        [Parameter(Mandatory)] [DateTimeOffset] $StartUtc,
        [Parameter(Mandatory)] [DateTimeOffset] $EndUtc
    )
    $time = Parse-Utc (Get-Value $Sample 'sampledAtUtc')
    if ($null -eq $time) { return }
    if ($time -eq $StartUtc) { $State.startExact = $Sample }
    elseif ($time -gt $StartUtc -and $null -eq $State.startAfter) { $State.startAfter = $Sample }
    elseif ($time -lt $StartUtc) { $State.startBefore = $Sample }
    if ($time -eq $EndUtc) { $State.endExact = $Sample }
    elseif ($time -lt $EndUtc) { $State.endBefore = $Sample }
    elseif ($time -gt $EndUtc -and $null -eq $State.endAfter) { $State.endAfter = $Sample }
}

function Read-SessionIncrement {
    param(
        [Parameter(Mandatory)] [object] $State,
        [AllowNull()] [object] $StartUtc,
        [AllowNull()] [object] $EndUtc,
        [switch] $SessionLifetime
    )
    $path = [string] $State.sourcePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $State.invalidRecords++
        Add-BindingDiagnostic -Category 'source_unavailable' -Role ([string] (Get-Value $State 'role')) -SessionId ([string] (Get-Value $State 'sessionId')) -SourcePath $path -Reason 'bound local session source file is inaccessible'
        return
    }
    if ($SessionLifetime -and [bool] (Get-Value $State 'sourceSessionVerified') -and [string]::IsNullOrWhiteSpace([string] (Get-Value $State 'tokenStream'))) {
        # Rebuild once when a cursor produced by the pre-stream-selection
        # collector is reused; its latest sample may have mixed two streams.
        $State.byteOffset = 0L
        $State.completeLines = 0L
        $State.invalidRecords = 0L
        $State.resetCount = 0
        $State.latestSample = $null
        $State.tokenStream = $null
    }
    if (-not $SessionLifetime) {
        $startBinding = Format-StoryPerformanceUtcTimestamp -Timestamp $StartUtc
        $endBinding = Format-StoryPerformanceUtcTimestamp -Timestamp $EndUtc
        if ([string] (Get-Value $State 'boundaryStartUtc') -cne $startBinding -or [string] (Get-Value $State 'boundaryEndUtc') -cne $endBinding) {
            $State.startExact = $null; $State.startAfter = $null; $State.startBefore = $null
            $State.endExact = $null; $State.endBefore = $null; $State.endAfter = $null
            $State.boundaryStartUtc = $startBinding
            $State.boundaryEndUtc = $endBinding
        }
    }
    $length = [IO.FileInfo]::new($path).Length
    if ($length -lt [long] $State.byteOffset) {
        $State.byteOffset = 0L
        $State.fileResetCount++
        $State.resetCount++
        $State.sourceSessionVerified = $false
    }
    $stream = $null
    $reader = $null
    try {
        $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        [void] $stream.Seek([long] $State.byteOffset, [IO.SeekOrigin]::Begin)
        $reader = [IO.StreamReader]::new($stream, $utf8, $true, 65536, $true)
        $sourceLength = [long] $length
        $sourceHasFinalNewline = $sourceLength -eq 0
        if (-not $sourceHasFinalNewline) {
            [void] $stream.Seek(-1L, [IO.SeekOrigin]::End)
            $sourceHasFinalNewline = $stream.ReadByte() -eq 0x0A
            [void] $stream.Seek([long] $State.byteOffset, [IO.SeekOrigin]::Begin)
            $reader.Dispose()
            $reader = [IO.StreamReader]::new($stream, $utf8, $true, 65536, $true)
        }
        $cursor = [long] $State.byteOffset
        $completeOffset = [long] $State.byteOffset
        while ($null -ne ($text = $reader.ReadLine())) {
            $lineByteCount = [long] $utf8.GetByteCount($text)
            $lineEnd = $cursor + $lineByteCount
            $complete = $lineEnd -lt $sourceLength -or ($sourceHasFinalNewline -and $lineEnd -eq ($sourceLength - 1L))
            if (-not $complete) { break }
            $cursor = $lineEnd + 1L
            if ($lineByteCount -gt $maxLineBytes) { $State.invalidRecords++; $completeOffset = $cursor; continue }
            try {
                $record = $text | ConvertFrom-Json -Depth 50 -DateKind String
                $recordType = [string] (Get-Value $record 'type')
                $payload = Get-Value $record 'payload'
                if ($recordType -ceq 'session_meta') {
                    $observedSessionId = [string] (Get-Value $payload 'id')
                    if ([string]::IsNullOrWhiteSpace($observedSessionId) -or $observedSessionId -cne [string] $State.sessionId) {
                        $State.sourceSessionVerified = $false
                        $State.invalidRecords++
                        Add-BindingDiagnostic -Category 'binding_invalid' -Role ([string] (Get-Value $State 'role')) -SessionId ([string] (Get-Value $State 'sessionId')) -SourcePath $path -Reason 'session_meta.payload.id does not match the declared session binding'
                    }
                    else {
                        if ($SessionLifetime) {
                            if ([string] (Get-Value $State 'tokenStream') -ceq 'token_usage_record') {
                                $State.latestSample = $null
                                $State.completeLines = 0L
                                $State.resetCount = 0
                            }
                            $State.tokenStream = 'event_msg/token_count'
                        }
                        $State.sourceSessionVerified = $true
                    }
                    $completeOffset = $cursor
                    continue
                }
                $isActualTokenRecord = $recordType -ceq 'event_msg' -and [string] (Get-Value $payload 'type') -ceq 'token_count'
                $isAcceptedSyntheticRecord = $recordType -ceq 'token_usage_record'
                if (-not $isActualTokenRecord -and -not $isAcceptedSyntheticRecord) { $completeOffset = $cursor; continue }
                if ($SessionLifetime -and $isActualTokenRecord) {
                    $tokenStream = [string] (Get-Value $State 'tokenStream')
                    if (-not [string]::IsNullOrWhiteSpace($tokenStream) -and $tokenStream -cne 'event_msg/token_count') { $completeOffset = $cursor; continue }
                    $State.tokenStream = 'event_msg/token_count'
                }
                if ($isAcceptedSyntheticRecord) {
                    if ($SessionLifetime) {
                        if ([bool] (Get-Value $State 'sourceSessionVerified')) { $completeOffset = $cursor; continue }
                        $tokenStream = [string] (Get-Value $State 'tokenStream')
                        if (-not [string]::IsNullOrWhiteSpace($tokenStream) -and $tokenStream -cne 'token_usage_record') { $completeOffset = $cursor; continue }
                        $State.tokenStream = 'token_usage_record'
                    }
                    $sessionId = [string] (Get-Value $payload 'session_id')
                    if ([string]::IsNullOrWhiteSpace($sessionId) -or $sessionId -cne [string] $State.sessionId) { $State.invalidRecords++; $completeOffset = $cursor; continue }
                }
                if ($isActualTokenRecord -and -not [bool] (Get-Value $State 'sourceSessionVerified')) {
                    $State.invalidRecords++
                    Add-BindingDiagnostic -Category 'binding_unverified' -Role ([string] (Get-Value $State 'role')) -SessionId ([string] (Get-Value $State 'sessionId')) -SourcePath $path -Reason 'event_msg/token_count was ignored before the local session identity was verified'
                    $completeOffset = $cursor
                    continue
                }
                $usage = if ($isActualTokenRecord) { Get-Value (Get-Value $payload 'info') 'total_token_usage' } else { Get-Value $payload 'thread_token_usage' }
                if ($null -eq $usage) { $usage = Get-Value $payload 'usage' }
                $counters = Get-CounterMap -Usage $usage
                $time = Parse-Utc (Get-Value $record 'timestamp')
                if ($null -eq $counters -or $null -eq $time) {
                    $State.invalidRecords++
                    Add-BindingDiagnostic -Category 'source_invalid' -Role ([string] (Get-Value $State 'role')) -SessionId ([string] (Get-Value $State 'sessionId')) -SourcePath $path -Reason 'bound source contained a token record with invalid timestamp or counters'
                    $completeOffset = $cursor
                    continue
                }
                $previous = if ($null -ne $State.latestSample) { Get-Value $State.latestSample 'counters' } else { $null }
                if ($null -ne $previous) {
                    foreach ($name in @((New-CounterMap).Keys)) {
                        if ([long] $counters[$name] -lt [long] (Get-Value $previous $name)) { $State.resetCount++; break }
                    }
                }
                $sample = New-Sample -Time $time -Counters $counters -ResetCount ([int] $State.resetCount)
                $State.latestSample = $sample
                if (-not $SessionLifetime) {
                    Update-BoundarySample -State $State -Sample $sample -StartUtc $StartUtc -EndUtc $EndUtc
                }
                $State.completeLines++
            }
            catch { $State.invalidRecords++ }
            $completeOffset = $cursor
        }
        $State.byteOffset = $completeOffset
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Select-BoundarySample {
    param([Parameter(Mandatory)] [object] $State, [Parameter(Mandatory)] [string] $Name)
    $exact = Get-Value $State ($Name + 'Exact')
    if ($null -ne $exact) { return [pscustomobject]@{ sample = $exact; coverage = 'exact complete-line boundary sample' } }
    $preferred = if ($Name -ceq 'start') { Get-Value $State 'startAfter' } else { Get-Value $State 'endBefore' }
    if ($null -ne $preferred) { return [pscustomobject]@{ sample = $preferred; coverage = 'nearest complete-line boundary sample on the attributable side' } }
    $fallback = if ($Name -ceq 'start') { Get-Value $State 'startBefore' } else { Get-Value $State 'endAfter' }
    if ($null -ne $fallback) { return [pscustomobject]@{ sample = $fallback; coverage = 'nearest complete-line boundary sample outside the attributable side' } }
    return [pscustomobject]@{ sample = $null; coverage = 'no complete-line boundary sample' }
}

function Get-Delta {
    param([AllowNull()] [object] $Start, [AllowNull()] [object] $End, [Parameter(Mandatory)] [int] $StartResetCount, [Parameter(Mandatory)] [int] $EndResetCount)
    if ($null -eq $Start -or $null -eq $End -or $StartResetCount -ne $EndResetCount) { return $null }
    $delta = New-CounterMap
    foreach ($name in @($delta.Keys)) {
        $value = [long] (Get-Value (Get-Value $End 'counters') $name) - [long] (Get-Value (Get-Value $Start 'counters') $name)
        if ($value -lt 0) { return $null }
        $delta[$name] = $value
    }
    return $delta
}

function Get-SessionLifetimeCounters {
    param([AllowNull()] [object] $Sample)

    if ($null -eq $Sample) { return $null }
    $counters = Copy-CounterMap (Get-Value $Sample 'counters')
    $counters.uncachedInputTokens = [long] $counters.inputTokens - [long] $counters.cachedInputTokens
    $counters.totalTokens = [long] $counters.inputTokens + [long] $counters.outputTokens
    return $counters
}

function Get-SessionLifetimeState {
    param([Parameter(Mandatory)] [object] $State)

    $sample = Get-Value $State 'latestSample'
    if ($null -eq $sample) { return 'unavailable' }
    if ([int] (Get-Value $State 'resetCount') -gt 0 -or [long] (Get-Value $State 'invalidRecords') -gt 0) { return 'partial' }
    return 'measured'
}

function Get-LifetimeRoleState {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Sessions)

    $available = @($Sessions | Where-Object { [string] (Get-Value $_ 'state') -ne 'unavailable' })
    if ($available.Count -eq 0) { return 'unavailable' }
    if (@($Sessions | Where-Object { [string] (Get-Value $_ 'state') -ne 'measured' }).Count -gt 0) { return 'partial' }
    return 'measured'
}

function Add-CounterMap {
    param(
        [Parameter(Mandatory)] [object] $Target,
        [Parameter(Mandatory)] [object] $Source
    )

    foreach ($name in @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens', 'uncachedInputTokens', 'totalTokens')) {
        if (-not $Target.Contains($name)) { $Target[$name] = 0L }
        $Target[$name] += [long] (Get-Value $Source $name)
    }
}

if (-not (Test-Path -LiteralPath $ObservedEvidencePath -PathType Leaf)) {
    throw [IO.FileNotFoundException]::new('role usage evidence or event ledger was not found')
}
$evidence = Read-JsonFile -Path $ObservedEvidencePath
$allRows = @((Get-Value $evidence 'rows') | Where-Object { $null -ne $_ })

if ($SessionLifetime) {
    if ([string]::IsNullOrWhiteSpace($Scope)) {
        throw [InvalidOperationException]::new('story_usage_scope_required: session lifetime mode requires a selected story scope')
    }

    # A coordinator row is scoped to the overall run; pair it with the selected
    # story rows without inventing a lifecycle boundary or a zero baseline.
    $rows = @($allRows | Where-Object {
            [string] (Get-Value $_ 'scope') -ceq $Scope -or
            ([string] (Get-Value $_ 'role') -ceq 'coordinator' -and [string] (Get-Value $_ 'scope') -ceq 'run')
        })
    if ($rows.Count -eq 0) {
        throw [InvalidOperationException]::new('story_usage_binding_unavailable: no observed role rows match the selected story scope')
    }

    $state = if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        Read-JsonFile -Path $StatePath
    }
    else {
        [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'story_performance_usage_cursor'; mode = 'session_lifetime'; sessions = @() }
    }
    $savedSessions = @((Get-Value $state 'sessions') | Where-Object { $null -ne $_ })
    $sessionStates = [System.Collections.Generic.List[object]]::new()
    $seenSessions = @{}
    foreach ($row in $rows) {
        $declaredSourcePath = [string] (Get-Value $row 'sourcePath')
        $sessionId = [string] (Get-Value $row 'sessionId')
        $role = [string] (Get-Value $row 'role')
        $scope = [string] (Get-Value $row 'scope')
        if ([string]::IsNullOrWhiteSpace($declaredSourcePath) -or [string]::IsNullOrWhiteSpace($sessionId) -or $role -notin @('coordinator', 'implementer', 'reviewer')) {
            Add-BindingDiagnostic -Category 'binding_invalid' -Role $role -SessionId $sessionId -SourcePath $declaredSourcePath -Reason 'observed role binding requires a supported role, nonblank sessionId, and sourcePath'
            continue
        }
        if ($seenSessions.ContainsKey($sessionId)) {
            if ([string] $seenSessions[$sessionId] -cne $role) {
                Add-BindingDiagnostic -Category 'binding_conflict' -Role $role -SessionId $sessionId -SourcePath $declaredSourcePath -Reason 'one sessionId is bound to multiple roles'
                throw [InvalidOperationException]::new("story_usage_binding_conflict: one session is bound to multiple roles ($sessionId)")
            }
            continue
        }
        $seenSessions[$sessionId] = $role
        $sourcePath = Resolve-ObservedSourcePath -Evidence $row
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Add-BindingDiagnostic -Category 'source_unavailable' -Role $role -SessionId $sessionId -SourcePath $sourcePath -Reason 'declared local session source file is inaccessible'
        }
        $existing = @($savedSessions | Where-Object {
                [string] (Get-Value $_ 'sessionId') -ceq $sessionId -and
                [string] (Get-Value $_ 'role') -ceq $role
            }) | Select-Object -First 1
        if ($null -eq $existing) {
            $boundRow = [pscustomobject][ordered]@{
                role = $role
                scope = $scope
                sessionId = $sessionId
                sourcePath = $sourcePath
            }
            $session = New-SessionState -Evidence $boundRow
        }
        else {
            $session = $existing
            # Evidence paths may move from the active-session directory to the
            # archive. Keep the saved cursor while following the exact binding.
            if ([string] (Get-Value $session 'sourcePath') -cne $sourcePath -and (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $session.sourcePath = $sourcePath
            }
        }
        if ($null -eq $session.PSObject.Properties['tokenStream']) {
            Add-Member -InputObject $session -MemberType NoteProperty -Name tokenStream -Value $null
        }
        Read-SessionIncrement -State $session -StartUtc $null -EndUtc $null -SessionLifetime
        [void] $sessionStates.Add($session)
    }

    $roleTotals = [ordered]@{}
    $sampleOutput = [System.Collections.Generic.List[object]]::new()
    foreach ($session in @($sessionStates)) {
        $latest = Get-Value $session 'latestSample'
        $counters = Get-SessionLifetimeCounters -Sample $latest
        $sampleState = Get-SessionLifetimeState -State $session
        $missingData = if ($null -eq $latest) { 'no valid cumulative token_count sample was available from the bound source file' } elseif ($sampleState -eq 'partial') { 'latest cumulative sample is usable, but the source contained a reset or invalid record' } else { $null }
        [void] $sampleOutput.Add([ordered]@{
                role = [string] (Get-Value $session 'role')
                scope = [string] (Get-Value $session 'scope')
                sessionId = [string] (Get-Value $session 'sessionId')
                sourcePath = [string] (Get-Value $session 'sourcePath')
                reportingScope = 'SESSION LIFETIME'
                tokenStream = [string] (Get-Value $session 'tokenStream')
                state = $sampleState
                latest = $latest
                counters = $counters
                missingData = $missingData
                completeLines = [long] (Get-Value $session 'completeLines')
                invalidRecords = [long] (Get-Value $session 'invalidRecords')
                resetCount = [int] (Get-Value $session 'resetCount')
                fileResetCount = [int] (Get-Value $session 'fileResetCount')
            })
        if ($null -ne $counters) {
            $role = [string] (Get-Value $session 'role')
            if (-not $roleTotals.Contains($role)) {
                $roleTotals[$role] = [ordered]@{
                    inputTokens = 0L
                    cachedInputTokens = 0L
                    outputTokens = 0L
                    reasoningTokens = 0L
                    uncachedInputTokens = 0L
                    totalTokens = 0L
                }
            }
            Add-CounterMap -Target $roleTotals[$role] -Source $counters
        }
    }

    $roleCoverage = [ordered]@{}
    foreach ($role in @('coordinator', 'implementer', 'reviewer')) {
        $roleSessions = @($sampleOutput | Where-Object { [string] (Get-Value $_ 'role') -ceq $role })
        $roleState = Get-LifetimeRoleState -Sessions $roleSessions
        $roleEntry = [ordered]@{
            state = $roleState
            sessions = $roleSessions.Count
            measuredSessions = @($roleSessions | Where-Object { [string] (Get-Value $_ 'state') -ceq 'measured' }).Count
            partialSessions = @($roleSessions | Where-Object { [string] (Get-Value $_ 'state') -ceq 'partial' }).Count
            unavailableSessions = @($roleSessions | Where-Object { [string] (Get-Value $_ 'state') -ceq 'unavailable' }).Count
            counters = if ($roleTotals.Contains($role)) { $roleTotals[$role] } else { $null }
            missingData = if ($roleState -eq 'unavailable') { 'no valid bound source file or token_count sample was available for this role' } elseif ($roleState -eq 'partial') { 'role has a valid lifetime sample with incomplete source evidence' } else { $null }
        }
        $roleCoverage[$role] = $roleEntry
    }
    $missingRoles = @($roleCoverage.Keys | Where-Object { [string] (Get-Value $roleCoverage[$_] 'state') -eq 'unavailable' })
    $coverage = if (@($roleCoverage.Keys | Where-Object { [string] (Get-Value $roleCoverage[$_] 'state') -eq 'measured' }).Count -eq $roleCoverage.Count) { 'measured' } elseif (@($roleCoverage.Values | Where-Object { [string] (Get-Value $_ 'state') -in @('measured', 'partial') }).Count -gt 0) { 'partial' } else { 'unavailable' }

    $stateOut = [ordered]@{ schemaVersion = 1; kind = 'story_performance_usage_cursor'; mode = 'session_lifetime'; updatedAtUtc = Format-StoryPerformanceUtcTimestamp -Timestamp ([DateTimeOffset]::UtcNow); sessions = @($sessionStates) }
    $stateParent = Split-Path -Parent $StatePath
    if (-not [string]::IsNullOrWhiteSpace($stateParent)) { [IO.Directory]::CreateDirectory($stateParent) | Out-Null }
    [IO.File]::WriteAllText($StatePath, ($stateOut | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))

    $output = [ordered]@{
        schemaVersion = 1
        kind = 'story_performance_role_token_usage'
        mode = 'session_lifetime'
        reportingScope = 'SESSION LIFETIME'
        selectedScope = $Scope
        runId = $null
        projectId = $null
        storyId = $null
        source = 'observed local Codex App session token_count cumulative counters'
        counterSemantics = [ordered]@{
            input = 'latest cumulative input_tokens per unique bound session'
            cachedInput = 'cached_input_tokens is included in input_tokens'
            output = 'latest cumulative output_tokens per unique bound session'
            reasoning = 'reasoning_output_tokens is included in output_tokens'
            total = 'input_tokens plus output_tokens; SESSION LIFETIME, not a PR-boundary delta'
            authoritativeStream = 'verified sessions use event_msg/token_count/info.total_token_usage; token_usage_record is compatibility-only when no session_meta verifies a real session'
            aggregation = 'one latest cumulative counter per unique bound session; never sum cumulative notifications'
        }
        boundary = $null
        sessions = @($sampleOutput)
        roleTotals = $roleTotals
        roleCoverage = $roleCoverage
        missingRoles = $missingRoles
        bindingDiagnostics = @($script:BindingDiagnostics)
        coverage = $coverage
        limitations = @('lifecycle event history is not required for SESSION LIFETIME mode', 'session binding is required for every accepted token record', 'counter decreases and file truncation are reported as resets; no zero baseline or fabricated lifecycle marker is used', 'account limits and cumulative notification counts are not used as usage evidence')
    }
    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) { [IO.Directory]::CreateDirectory($outputParent) | Out-Null }
    [IO.File]::WriteAllText($OutputPath, ($output | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    $output | ConvertTo-Json -Depth 100
    return
}

if (-not (Test-Path -LiteralPath $EventsPath -PathType Leaf)) {
    throw [IO.FileNotFoundException]::new('role usage evidence or event ledger was not found')
}
$boundaries = Get-Boundaries -Path $EventsPath
$rows = $allRows
if (-not [string]::IsNullOrWhiteSpace($Scope)) {
    $rows = @($rows | Where-Object { [string] (Get-Value $_ 'scope') -ceq $Scope })
}
if ($rows.Count -eq 0) { throw [InvalidOperationException]::new('story_usage_binding_unavailable: no observed role rows match the selected story scope') }
$state = if (Test-Path -LiteralPath $StatePath -PathType Leaf) { Read-JsonFile -Path $StatePath } else { [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'story_performance_usage_cursor'; sessions = @() } }
$sessionStates = [System.Collections.Generic.List[object]]::new()
$seenBindings = @{}
foreach ($row in $rows) {
    $sourcePath = [string] (Get-Value $row 'sourcePath')
    $sessionId = [string] (Get-Value $row 'sessionId')
    $role = [string] (Get-Value $row 'role')
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or [string]::IsNullOrWhiteSpace($sessionId) -or $role -notin @('coordinator', 'implementer', 'reviewer')) {
        Add-BindingDiagnostic -Category 'binding_invalid' -Role $role -SessionId $sessionId -SourcePath $sourcePath -Reason 'observed role binding requires a supported role, nonblank sessionId, and sourcePath'
        continue
    }
    $bindingKey = "$sourcePath`n$sessionId"
    if ($seenBindings.ContainsKey($bindingKey)) {
        if ([string] $seenBindings[$bindingKey] -cne $role) {
            Add-BindingDiagnostic -Category 'binding_conflict' -Role $role -SessionId $sessionId -SourcePath $sourcePath -Reason 'one sourcePath/sessionId binding is assigned to multiple roles'
            throw [InvalidOperationException]::new("story_usage_binding_conflict: one session source is bound to multiple roles ($sourcePath)")
        }
        continue
    }
    $seenBindings[$bindingKey] = $role
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Add-BindingDiagnostic -Category 'source_unavailable' -Role $role -SessionId $sessionId -SourcePath $sourcePath -Reason 'declared local session source file is inaccessible'
    }
    $existing = @((Get-Value $state 'sessions') | Where-Object { [string] (Get-Value $_ 'sourcePath') -ceq $sourcePath -and [string] (Get-Value $_ 'sessionId') -ceq $sessionId }) | Select-Object -First 1
    $session = if ($null -ne $existing) { $existing } else { New-SessionState -Evidence $row }
    Read-SessionIncrement -State $session -StartUtc $boundaries.startUtc -EndUtc $boundaries.endUtc
    [void] $sessionStates.Add($session)
}

$roleTotals = [ordered]@{}
$sampleOutput = [System.Collections.Generic.List[object]]::new()
foreach ($session in @($sessionStates)) {
    $startSelection = Select-BoundarySample -State $session -Name 'start'
    $endSelection = Select-BoundarySample -State $session -Name 'end'
    $startSample = $startSelection.sample
    $endSample = $endSelection.sample
    $startReset = if ($null -ne $startSample) { [int] (Get-Value $startSample 'resetCount') } else { -1 }
    $endReset = if ($null -ne $endSample) { [int] (Get-Value $endSample 'resetCount') } else { -1 }
    $delta = Get-Delta -Start $startSample -End $endSample -StartResetCount $startReset -EndResetCount $endReset
    $coverage = if ($null -eq $delta) { 'unavailable: missing boundary sample or cumulative counter reset' } elseif ($startSelection.coverage -eq 'exact complete-line boundary sample' -and $endSelection.coverage -eq 'exact complete-line boundary sample') { 'measured exact complete-line story boundaries' } else { 'partial nearest complete-line story boundary coverage' }
    $sampleStatus = if ($null -eq $delta) { 'unavailable' } elseif ($coverage.StartsWith('measured')) { 'measured' } else { 'partial' }
    [void] $sampleOutput.Add([ordered]@{
            role = [string] $session.role
            scope = [string] $session.scope
            sessionId = [string] $session.sessionId
            sourcePath = [string] $session.sourcePath
            state = $sampleStatus
            start = $startSample
            end = $endSample
            counters = $delta
            coverage = $coverage
            completeLines = [long] $session.completeLines
            invalidRecords = [long] $session.invalidRecords
            resetCount = [int] $session.resetCount
            fileResetCount = [int] $session.fileResetCount
        })
    if ($null -ne $delta) {
        if (-not $roleTotals.Contains($session.role)) { $roleTotals[$session.role] = New-CounterMap }
        foreach ($name in @($roleTotals[$session.role].Keys)) { $roleTotals[$session.role][$name] += [long] $delta[$name] }
    }
}

$stateOut = [ordered]@{ schemaVersion = 1; kind = 'story_performance_usage_cursor'; updatedAtUtc = Format-StoryPerformanceUtcTimestamp -Timestamp ([DateTimeOffset]::UtcNow); sessions = @($sessionStates) }
$stateParent = Split-Path -Parent $StatePath
if (-not [string]::IsNullOrWhiteSpace($stateParent)) { [IO.Directory]::CreateDirectory($stateParent) | Out-Null }
[IO.File]::WriteAllText($StatePath, ($stateOut | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))

$output = [ordered]@{
    schemaVersion = 1
    kind = 'story_performance_role_token_usage'
    runId = $boundaries.runId
    projectId = $boundaries.projectId
    storyId = $boundaries.storyId
    source = 'observed local Codex App session token_count cumulative counters'
    counterSemantics = [ordered]@{ input = 'cumulative input_tokens'; cachedInput = 'cached_input_tokens is included in input_tokens'; output = 'cumulative output_tokens'; reasoning = 'reasoning_output_tokens is included in output_tokens'; aggregation = 'subtract one start boundary from one end boundary per bound session; never sum cumulative notifications' }
    boundary = [ordered]@{ startUtc = Format-StoryPerformanceUtcTimestamp -Timestamp $boundaries.startUtc; endUtc = Format-StoryPerformanceUtcTimestamp -Timestamp $boundaries.endUtc; sampling = 'complete JSONL lines only; exact boundary when present, otherwise explicit nearest-line coverage' }
    sessions = @($sampleOutput)
    roleTotals = $roleTotals
    bindingDiagnostics = @($script:BindingDiagnostics)
    coverage = if (@($sampleOutput | Where-Object state -eq 'measured').Count -eq $sampleOutput.Count -and $sampleOutput.Count -gt 0) { 'measured' } elseif (@($sampleOutput | Where-Object state -in @('measured','partial')).Count -gt 0) { 'partial' } else { 'unavailable' }
    limitations = @('session binding is required for every accepted token record', 'counter decreases and file truncation are reported as resets and do not produce a delta across the reset', 'account limits and cumulative notification counts are not used as usage evidence')
}
$outputParent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputParent)) { [IO.Directory]::CreateDirectory($outputParent) | Out-Null }
[IO.File]::WriteAllText($OutputPath, ($output | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
$output | ConvertTo-Json -Depth 100
