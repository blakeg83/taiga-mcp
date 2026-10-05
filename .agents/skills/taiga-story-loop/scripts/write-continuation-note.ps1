# Snapshot persistence only; no workflow state machine or provider operations.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $NotePath,
    [Parameter(Mandatory)] [System.Collections.IDictionary] $Snapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fields = @(
    'Run', 'Scope', 'Repository', 'Base', 'Topology', 'Feature', 'Current', 'Story branch',
    'Implementer', 'Pair', 'Review mode', 'PR', 'PR delivery', 'Approval',
    'Review', 'Integrated review', 'Final delivery', 'Merge', 'Next', 'Recovery',
    'Worker cursors', 'Task state', 'Gate', 'Pending action', 'Evidence'
)
$required = @(
    'Run', 'Scope', 'Repository', 'Base', 'Feature', 'Current', 'Story branch',
    'Implementer', 'Pair', 'Review mode', 'PR', 'Approval', 'Review', 'Merge',
    'Next', 'Recovery', 'Worker cursors', 'Task state', 'Gate', 'Pending action', 'Evidence'
)
foreach ($key in $Snapshot.Keys) {
    if ($key -cnotin $fields) { throw "Unknown continuation field: $key" }
    $value = $Snapshot[$key]
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or
        $value.IndexOfAny([char[]]"`r`n") -ge 0 -or $value.Length -gt 1024) {
        throw "Continuation field '$key' must be a nonblank single-line string of at most 1024 characters."
    }
}
foreach ($key in $required) {
    if ($key -cnotin @($Snapshot.Keys)) { throw "Missing continuation field: $key" }
}

$content = (@(foreach ($key in $fields) {
    if ($key -cin @($Snapshot.Keys)) { '{0}: {1}' -f $key, $Snapshot[$key] }
}) -join "`n") + "`n"
$encoding = [Text.UTF8Encoding]::new($false)
$bytes = $encoding.GetByteCount($content)
if ($bytes -gt 16384) { throw 'Continuation snapshot exceeds 16 KiB; shorten evidence to references without dropping unresolved facts.' }
if (-not [IO.Path]::IsPathFullyQualified($NotePath)) { throw 'NotePath must be absolute.' }
$path = [IO.Path]::GetFullPath($NotePath)
$directory = [IO.Path]::GetDirectoryName($path)
if (-not [IO.Directory]::Exists($directory)) { throw 'Continuation note directory must already exist.' }

if ([IO.File]::Exists($path) -and [IO.File]::ReadAllText($path, $encoding) -ceq $content) {
    return [pscustomobject]@{ Changed = $false; Bytes = $bytes; Lines = $Snapshot.Count }
}

# Single coordinator owns the note. A same-directory temporary file makes
# replacement atomic; the previous snapshot is never concatenated into it.
$temporary = Join-Path $directory ('.continuation-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::WriteAllText($temporary, $content, $encoding)
    if ([IO.File]::Exists($path)) {
        [IO.File]::Replace($temporary, $path, ($path + '.previous'))
    }
    else {
        [IO.File]::Move($temporary, $path)
    }
}
finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
}
[pscustomobject]@{ Changed = $true; Bytes = $bytes; Lines = $Snapshot.Count }
