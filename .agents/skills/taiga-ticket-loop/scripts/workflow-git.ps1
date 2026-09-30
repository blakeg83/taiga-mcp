[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('fetch-base','create-branch','verify','refresh','push')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath
)

$ErrorActionPreference = 'Stop'

function Read-Request {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input file was not found: $InputPath" }
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 50 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
    return $value
}

function Require-Value {
    param([hashtable] $Object, [string] $Name)
    if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }
    return [string]$Object[$Name]
}

function Assert-Path {
    param([string] $Path, [string] $Name)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -match '[:\\/]$') { throw "$Name must be a concrete directory." }
    return $full
}

function Invoke-Git {
    param([string] $Repository, [string[]] $Arguments)
    $output = & git -C $Repository @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed with exit code ${exitCode}: $($output -join ' ')" }
    return [ordered]@{ output = @($output | ForEach-Object { [string]$_ }); exitCode = $exitCode }
}

function Get-Head {
    param([string] $Repository, [string] $Revision = 'HEAD')
    $result = Invoke-Git $Repository @('rev-parse', '--verify', $Revision)
    return ([string]$result.output[-1]).Trim()
}

function Get-Branch {
    param([string] $Repository)
    $result = Invoke-Git $Repository @('branch', '--show-current')
    return ([string]$result.output[-1]).Trim()
}

function Get-Status {
    param([string] $Repository)
    $result = Invoke-Git $Repository @('status', '--porcelain')
    return @($result.output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

try {
    $request = Read-Request
    $repository = Assert-Path (Require-Value $request 'repositoryPath') 'repositoryPath'
    if (-not (Test-Path -LiteralPath $repository -PathType Container)) { throw "Repository path does not exist: $repository" }
    $remote = if ($request.Contains('remote')) { Require-Value $request 'remote' } else { 'origin' }
    $baseBranch = if ($request.Contains('baseBranch')) { Require-Value $request 'baseBranch' } else { 'master' }
    $result = switch ($Operation) {
        'fetch-base' {
            Invoke-Git $repository @('fetch', '--prune', $remote) | Out-Null
            $ref = "$remote/$baseBranch"
            $sha = Get-Head $repository $ref
            [ordered]@{ fetched = $true; remote = $remote; baseBranch = $baseBranch; baseRef = $ref; baseSha = $sha; fetchedAt = [DateTime]::UtcNow.ToString('o') }
        }
        'create-branch' {
            $baseSha = Require-Value $request 'baseSha'
            $branch = Require-Value $request 'branch'
            if ($branch -notmatch '^codex/[A-Za-z0-9._/-]+$' -or $branch -match '(?:^|/)[.]{1,2}(?:/|$)') { throw 'Branch must be a safe codex/ feature branch.' }
            $worktree = Assert-Path (Require-Value $request 'worktreePath') 'worktreePath'
            if (Test-Path -LiteralPath $worktree) { throw "Worktree path already exists; refusing to reuse it: $worktree" }
            Invoke-Git $repository @('worktree', 'add', '--detach', $worktree, $baseSha) | Out-Null
            try {
                Invoke-Git $worktree @('switch', '--create', $branch) | Out-Null
                $head = Get-Head $worktree
                if ($head -ne $baseSha) { throw "Created branch HEAD $head does not match captured base $baseSha." }
                if ((Get-Status $worktree).Count -ne 0) { throw 'New worktree is not clean.' }
                [ordered]@{ repositoryPath = $repository; worktreePath = $worktree; branch = $branch; baseSha = $baseSha; headSha = $head; clean = $true }
            } catch { throw }
        }
        'verify' {
            $worktree = if ($request.Contains('worktreePath')) { Assert-Path $request.worktreePath 'worktreePath' } else { $repository }
            $expectedBranch = if ($request.Contains('branch')) { [string]$request.branch } else { $null }
            $expectedHead = if ($request.Contains('headSha')) { [string]$request.headSha } else { $null }
            $branch = Get-Branch $worktree; $head = Get-Head $worktree; $dirty = Get-Status $worktree
            if ($expectedBranch -and $branch -ne $expectedBranch) { throw "Branch mismatch: expected $expectedBranch, actual $branch." }
            if ($expectedHead -and $head -ne $expectedHead) { throw "HEAD mismatch: expected $expectedHead, actual $head." }
            if ($dirty.Count -gt 0 -and $request.requireClean -eq $true) { throw 'Source checkout is dirty.' }
            [ordered]@{ worktreePath = $worktree; branch = $branch; headSha = $head; clean = ($dirty.Count -eq 0); changes = $dirty }
        }
        'refresh' {
            $worktree = Assert-Path (Require-Value $request 'worktreePath') 'worktreePath'
            $targetRef = if ($request.Contains('targetRef')) { Require-Value $request 'targetRef' } else { "$remote/$baseBranch" }
            $recordedTarget = if ($request.Contains('recordedTargetSha')) { Require-Value $request 'recordedTargetSha' } elseif ($request.Contains('baseSha')) { Require-Value $request 'baseSha' } else { throw 'recordedTargetSha or baseSha is required for refresh approval comparison.' }
            $before = Get-Head $worktree
            Invoke-Git $worktree @('fetch', '--prune', $remote) | Out-Null
            $target = Get-Head $worktree $targetRef
            if ($target -eq $recordedTarget) { [ordered]@{ changed = $false; beforeSha = $before; recordedTargetSha = $recordedTarget; targetSha = $target; headSha = $before; approvalInvalidated = $false } } else {
                $merge = & git -C $worktree merge --no-edit $targetRef 2>&1; $mergeExit = $LASTEXITCODE
                if ($mergeExit -ne 0) { [ordered]@{ changed = $true; conflict = $true; beforeSha = $before; recordedTargetSha = $recordedTarget; targetSha = $target; output = @($merge | ForEach-Object { [string]$_ }); approvalInvalidated = $true } }
                else { [ordered]@{ changed = $true; conflict = $false; beforeSha = $before; recordedTargetSha = $recordedTarget; targetSha = $target; headSha = Get-Head $worktree; approvalInvalidated = $true } }
            }
        }
        'push' {
            $worktree = Assert-Path (Require-Value $request 'worktreePath') 'worktreePath'; $branch = Require-Value $request 'branch'; $expectedHead = Require-Value $request 'expectedHeadSha'
            if ($branch -notmatch '^codex/[A-Za-z0-9._/-]+$' -or $branch -match '(?:^|/)[.]{1,2}(?:/|$)') { throw 'Push branch must be a safe codex/ feature branch.' }
            if ($request.allowForcePush -eq $true) { throw 'Force-push is disabled by contract.' }
            $actualBranch = Get-Branch $worktree; if ($actualBranch -ne $branch) { throw "Push checkout branch does not match owned branch: expected $branch, actual $actualBranch." }
            $actualHead = Get-Head $worktree; if ($actualHead -ne $expectedHead) { throw "Push source does not match reviewed head: expected $expectedHead, actual $actualHead." }
            $localBranchHead = Get-Head $worktree "refs/heads/$branch"; if ($localBranchHead -ne $expectedHead) { throw "Owned local branch ref does not match reviewed head: expected $expectedHead, actual $localBranchHead." }
            Invoke-Git $worktree @('push', $remote, "refs/heads/$branch`:refs/heads/$branch") | Out-Null
            $remoteHeadResult = Invoke-Git $worktree @('ls-remote', $remote, "refs/heads/$branch")
            $line = @($remoteHeadResult.output | Where-Object { [string]$_ -match '^[0-9a-f]{40}\s' }) | Select-Object -First 1
            if (-not $line) { throw 'Remote branch was not observable after push.' }
            $remoteHead = ([string]$line).Split([char]9)[0].Trim()
            if ($remoteHead -ne $expectedHead) { throw "Remote head mismatch after push: expected $expectedHead, actual $remoteHead." }
            [ordered]@{ pushed = $true; remote = $remote; branch = $branch; localHeadSha = $actualHead; remoteHeadSha = $remoteHead }
        }
    }
    [ordered]@{ ok = $true; operation = $Operation; data = $result } | ConvertTo-Json -Depth 50
    exit 0
} catch {
    [ordered]@{ ok = $false; operation = $Operation; error = [ordered]@{ category = 'workflow_git'; message = $_.Exception.Message } } | ConvertTo-Json -Depth 20
    exit 1
}
