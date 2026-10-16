# OFFLINE EXISTING-WORKER MESSAGE SETTINGS CHECK.
# Scans the portable skill's documented message examples and guidance. It does
# not send messages, create workers, or mutate a provider.

[CmdletBinding()]
param(
    [string] $SkillRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SkillRoot)) {
    $SkillRoot = Split-Path -Parent $PSScriptRoot
}

$requiredFiles = @(
    'SKILL.md',
    'assets/implementation-prompt.md',
    'assets/reviewer-prompt.md',
    'references/worker-pair.md',
    'references/worker-handoffs.md',
    'references/automatic-review-flow.md',
    'references/recovery-operations.md',
    'references/synthetic-walkthroughs.md'
)

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string] $Text,
        [string] $Needle,
        [string] $Label
    )

    $normalizedText = [regex]::Replace($Text, '\s+', ' ')
    $normalizedNeedle = [regex]::Replace($Needle, '\s+', ' ')
    Assert-True ($normalizedText.IndexOf($normalizedNeedle, [StringComparison]::OrdinalIgnoreCase) -ge 0) "$Label is missing '$Needle'."
}

function Assert-NoExistingWorkerOverrides {
    param(
        [string] $Text,
        [string] $Source
    )

    $callPattern = '(?s)mcp__codex_app__send_message_to_thread\(\{.*?\}\)'
    foreach ($match in [regex]::Matches($Text, $callPattern)) {
        if ($match.Value -match '(?i)(?:["''](?:model|thinking)["'']\s*:|\b(?:model|thinking)\s*:)' ) {
            throw "$Source contains a model/thinking override in an existing-worker message example."
        }
    }
}

$documents = @{}
foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $SkillRoot $relativePath
    Assert-True (Test-Path -LiteralPath $path) "Missing required skill document: $relativePath"
    $documents[$relativePath] = Get-Content -LiteralPath $path -Raw
}

$settingsContract = 'omit both the `model` and `thinking` arguments'
foreach ($relativePath in @(
        'references/worker-pair.md',
        'references/worker-handoffs.md',
        'references/automatic-review-flow.md',
        'references/recovery-operations.md',
        'assets/implementation-prompt.md',
        'assets/reviewer-prompt.md')) {
    Assert-Contains $documents[$relativePath] $settingsContract $relativePath
}

Assert-Contains $documents['references/worker-pair.md'] 'Creation-time profile selection is separate' 'creation-time profile boundary'
Assert-Contains $documents['references/worker-pair.md'] 'separately authorized user configuration' 'user configuration boundary'

foreach ($entry in $documents.GetEnumerator()) {
    Assert-NoExistingWorkerOverrides $entry.Value $entry.Key
}

foreach ($markdownPath in Get-ChildItem -LiteralPath $SkillRoot -Recurse -File -Filter '*.md') {
    Assert-NoExistingWorkerOverrides (Get-Content -LiteralPath $markdownPath.FullName -Raw) $markdownPath.FullName
}

# Negative control: prove the scanner rejects a documented-style call that
# tries to override an existing recipient. This never reaches a provider.
$overrideProbe = 'mcp__codex_app__send_message_to_thread({"threadId":"existing","prompt":"continue","model":"wrong"})'
$rejected = $false
try {
    Assert-NoExistingWorkerOverrides $overrideProbe 'negative-control'
}
catch {
    $rejected = $true
}
Assert-True $rejected 'negative control did not reject a model override.'

'worker-message-settings: passed'
