# Discover only filenames for known identities; read at most one bounded metadata header.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [object[]] $Bindings,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' })
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rows = [Collections.Generic.List[object]]::new()
$diagnostics = [Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($binding in $Bindings) {
    $role = [string] $binding.role
    $sessionId = [string] $binding.sessionId
    # A worker ID is a candidate identity, never proof of a local session.
    if (-not $sessionId) { $sessionId = [string] $binding.workerId }
    if ($role -notin @('coordinator','implementer','reviewer') -or $sessionId -notmatch '^[a-zA-Z0-9-]+$') {
        $diagnostics.Add(@{ role = $role; category = 'binding_invalid' }); continue
    }
    $key = @($role, [string] $binding.scope, [string] $binding.workerId, $sessionId) | ConvertTo-Json -Compress
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $candidates = @()
    $searchErrors = @()
    foreach ($directory in @('sessions','archived_sessions')) {
        $root = Join-Path $CodexHome $directory
        if (Test-Path -LiteralPath $root -PathType Container) {
            $candidates += @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter "rollout-*-$sessionId.jsonl" -ErrorAction SilentlyContinue -ErrorVariable +searchErrors)
        }
    }
    $verified = @()
    foreach ($candidate in $candidates) {
        $reader = $null
        $stream = $null
        try {
            $stream = [IO.FileStream]::new($candidate.FullName, 'Open', 'Read', [IO.FileShare]::ReadWrite)
            $reader = [IO.StreamReader]::new($stream)
            $header = [Text.StringBuilder]::new()
            while ($header.Length -lt 65536 -and ($character = $reader.Read()) -ge 0 -and $character -ne 10) { [void] $header.Append([char] $character) }
            if ($character -ne 10 -or $header.Length -ge 65536) { continue }
            $record = $header.ToString() | ConvertFrom-Json -Depth 20 -DateKind String
            if ($record.type -ceq 'session_meta' -and $record.payload.id -ceq $sessionId) { $verified += $candidate.FullName }
        }
        catch { $searchErrors += $_ }
        finally { if ($null -ne $reader) { $reader.Dispose() }; if ($null -ne $stream) { $stream.Dispose() } }
    }
    if ($verified.Count -ne 1 -or $searchErrors.Count -gt 0) {
        $category = if ($searchErrors.Count) { 'source_inaccessible' } elseif ($verified.Count -gt 1) { 'binding_ambiguous' } else { 'source_missing' }
        $diagnostics.Add(@{ role = $role; sessionId = $sessionId; category = $category }); continue
    }
    $rows.Add([pscustomobject][ordered]@{ role = $role; scope = [string] $binding.scope; workerId = [string] $binding.workerId; sessionId = $sessionId; sourcePath = $verified[0] })
}
# A single session cannot independently measure two different roles.
$conflicts = @($rows | Group-Object sessionId | Where-Object { @($_.Group.role | Select-Object -Unique).Count -gt 1 } | ForEach-Object Name)
$accepted = @($rows | Where-Object { $_.sessionId -notin $conflicts } | Sort-Object role,scope,sessionId -Unique)
foreach ($id in $conflicts) { $diagnostics.Add(@{ sessionId = $id; category = 'binding_conflict' }) }
$result = [ordered]@{ rows = $accepted; discoveryAttempted = $true; diagnostics = @($diagnostics) }
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))) | Out-Null
[IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 30
