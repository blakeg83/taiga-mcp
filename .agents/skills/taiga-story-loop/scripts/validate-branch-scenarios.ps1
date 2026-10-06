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
$standalonePath = Join-Path $tempRoot 'standalone-story-worktree'
$featurePath = Join-Path $tempRoot 'feature-worktree'
$storyOnePath = Join-Path $tempRoot 'story-one-worktree'
$storyTwoPath = Join-Path $tempRoot 'story-two-worktree'
$notePath = Join-Path $tempRoot 'continuation-note.json'
$featureBranch = 'codex/feature-synthetic-run'
$standaloneBranch = 'codex/story-standalone-synthetic-run'
$storyOneBranch = 'codex/story-1-synthetic-run'
$storyTwoBranch = 'codex/story-2-synthetic-run'
$storyThreeBranch = 'codex/story-3-synthetic-run'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
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

function Assert-CleanTrackedSource {
    param([string] $Repository)
    $trackedDiff = Invoke-Git $Repository @('diff', '--quiet', 'HEAD', '--') -AllowFailure
    $stagedDiff = Invoke-Git $Repository @('diff', '--cached', '--quiet') -AllowFailure
    $untrackedSource = Invoke-Git $Repository @('ls-files', '--others', '--exclude-standard')
    Assert-True ($trackedDiff.ExitCode -eq 0) "tracked source is clean: $Repository"
    Assert-True ($stagedDiff.ExitCode -eq 0) "staged source is clean: $Repository"
    Assert-True ($untrackedSource.Output.Count -eq 0) "no non-ignored source is untracked: $Repository"
}

function Assert-ReviewInput {
    param(
        [string] $Repository,
        [string] $Worktree,
        [string] $ExpectedBranch,
        [string] $BaseSha,
        [string] $ExpectedHead
    )
    $root = Invoke-Git $Worktree @('rev-parse', '--show-toplevel')
    $branch = Get-Branch $Worktree
    $head = Get-Head $Worktree
    Assert-True (([IO.Path]::GetFullPath(([string]$root.Output[-1]).Trim())) -eq [IO.Path]::GetFullPath($Worktree)) 'review worktree matches receipt'
    Assert-True ($branch -eq $ExpectedBranch) 'review branch matches receipt'
    Assert-True ($head -eq $ExpectedHead) 'review HEAD matches receipt'
    Assert-CleanTrackedSource $Worktree
    $diff = Invoke-Git $Worktree @('diff', '--name-status', "$BaseSha..$ExpectedHead")
    Assert-True ($diff.ExitCode -eq 0) 'review diff range resolves'
    [pscustomobject]@{
        repository = $Repository
        worktree = $Worktree
        branch = $branch
        baseSha = $BaseSha
        reviewedSha = $head
        diffRange = "$BaseSha..$head"
        sourceState = 'clean tracked source'
    }
}

function Assert-ExactReviewAccepted {
    param(
        [string] $Worktree,
        [string] $ExpectedBranch,
        [string] $BaseSha,
        [string] $ReviewedSha,
        [System.Collections.Generic.HashSet[string]] $ReviewedRevisions
    )
    [void](Assert-ReviewInput $Worktree $Worktree $ExpectedBranch $BaseSha $ReviewedSha)
    Assert-True $ReviewedRevisions.Contains($ReviewedSha) 'acceptance must name a reviewed exact revision'
}

function Assert-DeliveryReady {
    param(
        [string] $Worktree,
        [string] $ExpectedBranch,
        [string] $BaseSha,
        [string] $ReviewedSha,
        [System.Collections.Generic.HashSet[string]] $ReviewedRevisions
    )
    Assert-ExactReviewAccepted $Worktree $ExpectedBranch $BaseSha $ReviewedSha $ReviewedRevisions
}

function Assert-ResumeReceipt {
    param([psobject] $Note)
    $repository = [string]$Note.repository
    $featureWorktree = [string]$Note.featureWorktree
    $featureBranch = [string]$Note.featureBranch
    $featureHead = [string]$Note.featureHead
    $storyWorktree = [string]$Note.storyWorktree
    $storyBranch = [string]$Note.storyBranch
    $storyHead = [string]$Note.pr.head
    $storyBase = [string]$Note.storyBaseSha

    Assert-True ($Note.pr.base -eq $featureBranch) 'resumed PR base matches the resumed feature branch'
    Assert-WorktreeReceipt $repository $featureWorktree $featureBranch $featureHead
    Assert-WorktreeReceipt $repository $storyWorktree $storyBranch $storyHead
    Assert-True ((Get-Head $storyWorktree "$storyBranch^") -eq $storyBase) 'resumed story base matches its recorded starting SHA'
    $inheritedStoryOne = Join-Path $storyWorktree 'story-one.txt'
    Assert-True (Test-Path -LiteralPath $inheritedStoryOne) 'resumed story worktree retains story-one content'
    Assert-True ((Get-Content -Raw -LiteralPath $inheritedStoryOne).Trim() -eq 'story one corrected') 'resumed corrected story-one content is authoritative'
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-Git $tempRoot @('init', '--bare', '--initial-branch=master', $remotePath) | Out-Null
    New-Item -ItemType Directory -Path $userPath -Force | Out-Null
    Invoke-Git $userPath @('init', '--initial-branch=master') | Out-Null
    Invoke-Git $userPath @('config', 'user.name', 'Taiga story-loop fixture') | Out-Null
    Invoke-Git $userPath @('config', 'user.email', 'story-loop@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $userPath 'README.md') -Value 'fixture base' -NoNewline
    Set-Content -LiteralPath (Join-Path $userPath '.gitignore') -Value "verification-output/`n" -NoNewline
    Invoke-Git $userPath @('add', 'README.md', '.gitignore') | Out-Null
    Invoke-Git $userPath @('commit', '-m', 'fixture base') | Out-Null
    Invoke-Git $userPath @('remote', 'add', 'origin', $remotePath) | Out-Null
    Invoke-Git $userPath @('push', '-u', 'origin', 'master') | Out-Null

    # An unrelated user edit is intentionally left in the user's checkout.
    Set-Content -LiteralPath (Join-Path $userPath 'unrelated.txt') -Value 'preserve me' -NoNewline
    Invoke-Git $userPath @('fetch', '--prune', 'origin') | Out-Null
    $baseSha = Get-Head $userPath 'origin/master'

    # A standalone story has exactly one branch from the captured base and a
    # direct-to-master PR. It must not create an integration feature branch.
    Invoke-Git $userPath @('worktree', 'add', '--detach', $standalonePath, $baseSha) | Out-Null
    Invoke-Git $standalonePath @('switch', '--create', $standaloneBranch) | Out-Null
    Set-Content -LiteralPath (Join-Path $standalonePath 'standalone.txt') -Value 'standalone story' -NoNewline
    Invoke-Git $standalonePath @('add', 'standalone.txt') | Out-Null
    Invoke-Git $standalonePath @('commit', '-m', 'standalone story') | Out-Null
    $standaloneHead = Get-Head $standalonePath
    Assert-WorktreeReceipt $userPath $standalonePath $standaloneBranch $standaloneHead
    Assert-True ((Get-Head $standalonePath "$standaloneBranch^") -eq $baseSha) 'standalone story starts at the captured master base'
    $standaloneNote = [ordered]@{
        topology = 'standalone-story-direct-master'
        featureBranch = 'none (standalone direct-to-master)'
        storyBranch = $standaloneBranch
        storyBaseSha = $baseSha
        pr = [ordered]@{ base = 'master'; head = $standaloneHead }
        finalReviewHead = $standaloneHead
    }
    Assert-True ($standaloneNote.topology -eq 'standalone-story-direct-master') 'standalone note records its topology'
    Assert-True ($standaloneNote.featureBranch -like 'none*') 'standalone note has no feature branch'
    Assert-True ($standaloneNote.pr.base -eq 'master') 'standalone PR targets master'
    Assert-True ($standaloneNote.finalReviewHead -eq $standaloneNote.pr.head) 'standalone direct PR uses the exact final reviewed HEAD'

    # Epic feature branch starts at the freshly captured base, in its own worktree.
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

    # Review input is the complete clean committed revision, not just a SHA.
    $reviewedStoryOneRevisions = [System.Collections.Generic.HashSet[string]]::new()
    $readyInput = Assert-ReviewInput $userPath $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $storyOneHead
    [void]$reviewedStoryOneRevisions.Add($readyInput.reviewedSha)
    $ignoredOutput = Join-Path $storyOnePath 'verification-output'
    New-Item -ItemType Directory -Path $ignoredOutput -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ignoredOutput 'test.log') -Value 'ignored test output' -NoNewline
    Assert-ReviewInput $userPath $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $storyOneHead | Out-Null
    Assert-True (@((Invoke-Git $storyOnePath @('status', '--short', '--ignored')).Output | Where-Object { $_ -like '!!*verification-output*' }).Count -gt 0) 'ignored verification output is present'

    # A tracked source edit during the pending review/handoff is preserved and blocks both acceptance and delivery.
    Set-Content -LiteralPath (Join-Path $storyOnePath 'story-one.txt') -Value 'dirty source during handoff' -NoNewline
    Assert-Throws { Assert-ReviewInput $userPath $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $storyOneHead } 'dirty source at handoff must block review input'
    Assert-Throws { Assert-DeliveryReady $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $storyOneHead $reviewedStoryOneRevisions } 'dirty source at handoff must hold delivery'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $storyOnePath 'story-one.txt')).Trim() -eq 'dirty source during handoff') 'dirty source is preserved'

    # The authorized correction commits a new revision; the previous review is stale.
    Set-Content -LiteralPath (Join-Path $storyOnePath 'story-one.txt') -Value 'story one corrected' -NoNewline
    Invoke-Git $storyOnePath @('add', 'story-one.txt') | Out-Null
    Invoke-Git $storyOnePath @('commit', '-m', 'correct story one review input') | Out-Null
    $correctedStoryOneHead = Get-Head $storyOnePath
    Assert-True ($correctedStoryOneHead -ne $storyOneHead) 'correction creates a new HEAD'
    Assert-Throws { Assert-ExactReviewAccepted $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $storyOneHead $reviewedStoryOneRevisions } 'old acceptance must not survive a changed HEAD'
    Assert-Throws { Assert-DeliveryReady $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $correctedStoryOneHead $reviewedStoryOneRevisions } 'delivery must wait for review of the correction'
    $correctionInput = Assert-ReviewInput $userPath $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $correctedStoryOneHead
    Assert-True ($correctionInput.diffRange -eq "$featureHeadBeforeStoryOne..$correctedStoryOneHead") 'correction records the new diff range'
    [void]$reviewedStoryOneRevisions.Add($correctedStoryOneHead)
    Assert-ExactReviewAccepted $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $correctedStoryOneHead $reviewedStoryOneRevisions
    Assert-DeliveryReady $storyOnePath $storyOneBranch $featureHeadBeforeStoryOne $correctedStoryOneHead $reviewedStoryOneRevisions

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
    Assert-True ((Get-Head $storyTwoPath) -eq $featureHeadForStoryTwo) 'story two starts at the current feature HEAD'
    $inheritedStoryOne = Join-Path $storyTwoPath 'story-one.txt'
    Assert-True (Test-Path -LiteralPath $inheritedStoryOne) 'story two inherits story-one content from the feature branch'
    Assert-True ((Get-Content -Raw -LiteralPath $inheritedStoryOne).Trim() -eq 'story one corrected') 'story two inherits the authoritative corrected story-one content'
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
        featureWorktree = $featurePath
        featureHead = $featureHeadBeforeFailedMerge
        currentStory = 2
        storyBranch = $storyTwoBranch
        storyWorktree = $storyTwoPath
        storyBaseSha = $featureHeadForStoryTwo
        stories = @(
            [ordered]@{ ref = 1; branch = $storyOneBranch; state = 'merged' }
            [ordered]@{ ref = 2; branch = $storyTwoBranch; state = 'current' }
        )
        pr = [ordered]@{ base = $featureBranch; head = $storyTwoHead; merge = 'unknown' }
        next = 'reconcile story-two merge before creating another story branch'
    }
    $note | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $notePath -NoNewline
    $resumed = Get-Content -Raw -LiteralPath $notePath | ConvertFrom-Json
    Assert-True ($resumed.featureBranch -eq $featureBranch) 'resume note retains feature branch'
    Assert-True ($resumed.stories.Count -eq 2) 'resume note retains ordered story scope'
    Assert-True ([int]$resumed.stories[0].ref -eq 1) 'resume note retains first story order'
    Assert-True ([int]$resumed.stories[1].ref -eq 2) 'resume note retains current story order'
    Assert-True ($resumed.storyWorktree -eq $storyTwoPath) 'resume note retains story worktree'
    Assert-True ($resumed.pr.base -eq $featureBranch) 'PR base is the integration feature branch'
    Assert-True ($resumed.pr.merge -eq 'unknown') 'unconfirmed merge remains unknown'
    Assert-True ($resumed.next -like '*reconcile*') 'unknown merge requires reconciliation before advancement'
    Assert-ResumeReceipt $resumed
    $resumedRepository = [string]$resumed.repository
    Assert-True (Test-Path -LiteralPath (Join-Path $resumedRepository 'unrelated.txt')) 'unrelated user edit survives resume'
    Assert-True ((Invoke-Git $resumedRepository @('branch', '--list', $storyThreeBranch)).Output.Count -eq 0) 'unknown merge does not create the next story branch'

    $mismatchedFeature = Get-Content -Raw -LiteralPath $notePath | ConvertFrom-Json
    $mismatchedFeature.featureHead = $baseSha
    Assert-Throws { Assert-ResumeReceipt $mismatchedFeature } 'incorrect saved feature lineage is rejected'
    $mismatchedStory = Get-Content -Raw -LiteralPath $notePath | ConvertFrom-Json
    $mismatchedStory.storyWorktree = $featurePath
    Assert-Throws { Assert-ResumeReceipt $mismatchedStory } 'incorrect saved story worktree lineage is rejected'

    Write-Output 'Passed disposable branch isolation, frozen clean revision, dirty-source/changed-HEAD conflict, ignored verification output, correction re-review, PR base, failed-merge, preservation, and continuation-note resume scenarios.'
    exit 0
}
finally {
    foreach ($worktree in @($storyTwoPath, $storyOnePath, $featurePath, $standalonePath)) {
        if (Test-Path -LiteralPath $worktree -PathType Container) {
            & git -C $userPath worktree remove --force $worktree 2>$null
        }
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
