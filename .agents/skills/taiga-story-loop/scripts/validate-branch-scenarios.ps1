# DISPOSABLE GIT SCENARIO CHECK.
# This script uses a temporary local repository and bare remote. It does not
# contact Taiga, GitHub, or a live repository.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('taiga-story-loop-' + [Guid]::NewGuid().ToString('N'))
$remotePath = Join-Path $tempRoot 'remote.git'
$userPath = Join-Path $tempRoot 'user'
$featurePath = Join-Path $tempRoot 'feature-worktree'
$storyOnePath = Join-Path $tempRoot 'story-one-worktree'
$storyTwoPath = Join-Path $tempRoot 'story-two-worktree'
$notePath = Join-Path $tempRoot 'continuation-note.json'
$featureBranch = 'codex/feature-synthetic-run'
$storyOneBranch = 'codex/story-1-synthetic-run'
$storyTwoBranch = 'codex/story-2-synthetic-run'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Git writes normal progress (for example, push destinations) to
        # stderr. Capture it as text without treating successful progress as
        # a PowerShell exception.
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $Repository @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git -C $Repository $($Arguments -join ' ') failed ($exitCode): $($output -join ' ')"
    }
    [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Get-Head {
    param([string] $Repository, [string] $Revision = 'HEAD')
    $result = Invoke-Git $Repository @('rev-parse', '--verify', $Revision)
    ([string]$result.Output[-1]).Trim()
}

function Get-Branch {
    param([string] $Repository)
    $result = Invoke-Git $Repository @('branch', '--show-current')
    ([string]$result.Output[-1]).Trim()
}

function Assert-WorktreeReceipt {
    param([string] $Repository, [string] $Path, [string] $Branch, [string] $ExpectedHead)
    $result = Invoke-Git $Repository @('worktree', 'list', '--porcelain')
    $text = ($result.Output -join "`n").Replace('\', '/')
    $normalizedPath = ([IO.Path]::GetFullPath($Path)).Replace('\', '/')
    Assert-True $text.Contains("worktree $normalizedPath") "worktree path is recorded: $Path"
    Assert-True $text.Contains("branch refs/heads/$Branch") "worktree branch is recorded: $Branch"
    Assert-True ((Get-Head $Path) -eq $ExpectedHead) "worktree HEAD matches receipt: $Path"
    Assert-True ((Get-Branch $Path) -eq $Branch) "worktree branch matches receipt: $Path"
    Assert-True ((Invoke-Git $Path @('status', '--porcelain')).Output.Count -eq 0) "worktree is clean: $Path"
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-Git $tempRoot @('init', '--bare', '--initial-branch=master', $remotePath) | Out-Null
    New-Item -ItemType Directory -Path $userPath -Force | Out-Null
    Invoke-Git $userPath @('init', '--initial-branch=master') | Out-Null
    Invoke-Git $userPath @('config', 'user.name', 'Taiga story-loop fixture') | Out-Null
    Invoke-Git $userPath @('config', 'user.email', 'story-loop@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $userPath 'README.md') -Value 'fixture base' -NoNewline
    Invoke-Git $userPath @('add', 'README.md') | Out-Null
    Invoke-Git $userPath @('commit', '-m', 'fixture base') | Out-Null
    Invoke-Git $userPath @('remote', 'add', 'origin', $remotePath) | Out-Null
    Invoke-Git $userPath @('push', '-u', 'origin', 'master') | Out-Null

    # An unrelated user edit is intentionally left in the user's checkout.
    Set-Content -LiteralPath (Join-Path $userPath 'unrelated.txt') -Value 'preserve me' -NoNewline
    Invoke-Git $userPath @('fetch', '--prune', 'origin') | Out-Null
    $baseSha = Get-Head $userPath 'origin/master'

    # Feature branch starts at the freshly captured base, in its own worktree.
    Invoke-Git $userPath @('worktree', 'add', '--detach', $featurePath, $baseSha) | Out-Null
    Invoke-Git $featurePath @('switch', '--create', $featureBranch) | Out-Null
    Assert-WorktreeReceipt $userPath $featurePath $featureBranch $baseSha
    Assert-True (Test-Path -LiteralPath (Join-Path $userPath 'unrelated.txt')) 'unrelated user edit survives feature setup'

    # First story is based on the feature HEAD and does not move the feature ref.
    $featureHeadBeforeStoryOne = Get-Head $featurePath
    Invoke-Git $userPath @('worktree', 'add', '--detach', $storyOnePath, $featureHeadBeforeStoryOne) | Out-Null
    Invoke-Git $storyOnePath @('switch', '--create', $storyOneBranch) | Out-Null
    Set-Content -LiteralPath (Join-Path $storyOnePath 'story-one.txt') -Value 'story one' -NoNewline
    Invoke-Git $storyOnePath @('add', 'story-one.txt') | Out-Null
    Invoke-Git $storyOnePath @('commit', '-m', 'story one') | Out-Null
    $storyOneHead = Get-Head $storyOnePath
    Assert-True ((Get-Head $featurePath) -eq $featureHeadBeforeStoryOne) 'feature ref does not move from story-one work'
    Assert-WorktreeReceipt $userPath $storyOnePath $storyOneBranch $storyOneHead

    # A confirmed merge advances the feature branch, which becomes story two's base.
    Invoke-Git $featurePath @('merge', '--no-ff', $storyOneBranch, '-m', 'merge story one') | Out-Null
    $featureHeadAfterStoryOne = Get-Head $featurePath
    Assert-True ($featureHeadAfterStoryOne -ne $featureHeadBeforeStoryOne) 'confirmed story-one merge advances feature HEAD'
    Invoke-Git $featurePath @('push', 'origin', "$featureBranch`:$featureBranch") | Out-Null

    # Make a shared file so the next story can demonstrate a failed merge.
    Set-Content -LiteralPath (Join-Path $featurePath 'merge-conflict.txt') -Value 'feature base' -NoNewline
    Invoke-Git $featurePath @('add', 'merge-conflict.txt') | Out-Null
    Invoke-Git $featurePath @('commit', '-m', 'prepare merge conflict') | Out-Null
    $featureHeadForStoryTwo = Get-Head $featurePath
    Invoke-Git $userPath @('worktree', 'add', '--detach', $storyTwoPath, $featureHeadForStoryTwo) | Out-Null
    Invoke-Git $storyTwoPath @('switch', '--create', $storyTwoBranch) | Out-Null
    Set-Content -LiteralPath (Join-Path $storyTwoPath 'merge-conflict.txt') -Value 'story two' -NoNewline
    Invoke-Git $storyTwoPath @('add', 'merge-conflict.txt') | Out-Null
    Invoke-Git $storyTwoPath @('commit', '-m', 'story two') | Out-Null
    $storyTwoHead = Get-Head $storyTwoPath

    Set-Content -LiteralPath (Join-Path $featurePath 'merge-conflict.txt') -Value 'feature correction' -NoNewline
    Invoke-Git $featurePath @('add', 'merge-conflict.txt') | Out-Null
    Invoke-Git $featurePath @('commit', '-m', 'feature correction') | Out-Null
    $featureHeadBeforeFailedMerge = Get-Head $featurePath
    $failedMerge = Invoke-Git $featurePath @('merge', '--no-ff', $storyTwoBranch, '-m', 'merge story two') -AllowFailure
    Assert-True ($failedMerge.ExitCode -ne 0) 'conflicting story-two merge is rejected'
    Invoke-Git $featurePath @('merge', '--abort') | Out-Null
    Assert-True ((Get-Head $featurePath) -eq $featureHeadBeforeFailedMerge) 'failed merge does not advance feature HEAD'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $featurePath 'story-two.txt'))) 'failed story is not integrated'

    # The note is enough to resume by reusing matching worktrees; no state machine is needed.
    $note = [ordered]@{
        run = 'synthetic-run'
        repository = $userPath
        remote = $remotePath
        baseSha = $baseSha
        featureBranch = $featureBranch
        featureHead = $featureHeadBeforeFailedMerge
        currentStory = 2
        storyBranch = $storyTwoBranch
        storyWorktree = $storyTwoPath
        storyBaseSha = $featureHeadForStoryTwo
        pr = [ordered]@{ base = $featureBranch; head = $storyTwoHead; merge = 'unknown' }
        next = 'reconcile story-two merge before creating another story branch'
    }
    $note | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $notePath -NoNewline
    $resumed = Get-Content -Raw -LiteralPath $notePath | ConvertFrom-Json
    Assert-True ($resumed.featureBranch -eq $featureBranch) 'resume note retains feature branch'
    Assert-True ($resumed.storyWorktree -eq $storyTwoPath) 'resume note retains story worktree'
    Assert-True ($resumed.pr.base -eq $featureBranch) 'PR base is the integration feature branch'
    Assert-True ($resumed.pr.merge -eq 'unknown') 'unconfirmed merge remains unknown'
    Assert-WorktreeReceipt $userPath $featurePath $featureBranch $featureHeadBeforeFailedMerge
    Assert-WorktreeReceipt $userPath $storyTwoPath $storyTwoBranch $storyTwoHead
    Assert-True (Test-Path -LiteralPath (Join-Path $userPath 'unrelated.txt')) 'unrelated user edit survives resume'

    Write-Output 'Passed disposable branch isolation, PR base, failed-merge, preservation, and continuation-note resume scenarios.'
    exit 0
}
finally {
    foreach ($worktree in @($storyTwoPath, $storyOnePath, $featurePath)) {
        if (Test-Path -LiteralPath $worktree -PathType Container) {
            & git -C $userPath worktree remove --force $worktree 2>$null
        }
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
