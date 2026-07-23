#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Safer, state-checked wrappers for everyday git.
.DESCRIPTION
    PowerShell port of gitsby. Every command verifies the repo state before
    acting (stash only if dirty, pull only with an upstream, push only if
    ahead), so each is idempotent and safe to re-run.
.PARAMETER Command
    saveup | newbr | gobr | status | listbr | sync | pull | commit | land | pr | release
    (old names scompul/mkbranch/chbranch/list/spush/spull/scommit/mtm still work)
.PARAMETER CommandArg
    Message (commit/saveup/sync/land), branch name (newbr/gobr), version (release),
    or PR number / 'ok' (pr).
.PARAMETER CommandArg2
    PR number, for 'pr ok <n>'.
.PARAMETER Message
    Commit or merge message (-m/-msg also work; or give it positionally).
.PARAMETER Quiet
    No prompts; if committing with no message, one is generated.
.EXAMPLE
    gitsby.ps1 saveup "fixed the frobnicator"
.EXAMPLE
    gitsby.ps1 newbr featx
.NOTES
    History at bottom of script. Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ).
    Licensed under The MIT License (MIT): https://mit-license.org/
    SPDX-License-Identifier: MIT
#>

## Console-only UI tool; everything written is for the human at the terminal.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console tool; output is UI, not pipeline data.')]
## No BOM: the shebang must be the first two bytes for direct execution on *nix.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'BOM would break the shebang; file is UTF-8 without BOM.')]
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(Position = 1)][string]$CommandArg = '',
    [Parameter(Position = 2)][string]$CommandArg2 = '',
    [Alias('m', 'msg')][string]$Message = '',
    [Alias('q')][switch]$Quiet,
    [Alias('h')][switch]$Help,
    [Alias('v', 'ver')][switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:thisVersion = '2.0.0-beta1'
$script:thisCopyrightYear = '2026'
$script:thisAuthor = 'Jim Collier'
$script:meName = Split-Path -Leaf -Path $PSCommandPath
$script:doQuietly = [bool]$Quiet
$script:commitMessage = $Message
$script:cmdArg = $CommandArg
$script:wasLastEchoBlank = $false
$script:wasShownCopyright = $false
$script:wasShownAbout = $false
$script:wasShownSyntax = $false
$script:mergeTargetLabel = 'dev/main'  ## for help text, before we know we're in a repo

## Never pop a merge-message editor mid-flow.
$env:GIT_MERGE_AUTOEDIT = 'no'


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Output helpers (same contract as the Bash fEcho family)

function Write-PlainLine {
    param([string]$Text = '')
    if ('' -ne $Text) {
        Write-Host $Text
        $script:wasLastEchoBlank = $false
    } elseif (-not $script:wasLastEchoBlank) {
        Write-Host ''
        $script:wasLastEchoBlank = $true
    }
}

function Write-StatusLine {
    param([string]$Text = '')
    if ('' -ne $Text) { Write-PlainLine "[ ${Text} ]" } else { Write-PlainLine '' }
}

function Clear-BlankCounter {
    $script:wasLastEchoBlank = $false
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Copyright, about, & syntax

function Show-Copyright {
    if ($script:doQuietly -or $script:wasShownCopyright) { return }
    $script:wasShownCopyright = $true
    Write-PlainLine ''
    Write-PlainLine "${script:meName} v${script:thisVersion}, Copyright © ${script:thisCopyrightYear} ${script:thisAuthor}."
    Write-PlainLine 'Licensed under The MIT License (MIT). Full text at:'
    Write-PlainLine '  https://mit-license.org/'
    Write-PlainLine 'No Warranty.'
    Write-PlainLine ''
}

function Show-About {
    if ($script:doQuietly -or $script:wasShownAbout) { return }
    $script:wasShownAbout = $true
    Write-PlainLine ''
    Write-PlainLine 'Safer, state-checked wrappers for everyday git. Every command verifies the'
    Write-PlainLine 'repo state before acting (stash only if dirty, pull only with an upstream,'
    Write-PlainLine 'push only if ahead), so each is idempotent and safe to re-run.'
    Write-PlainLine ''
}

function Show-Syntax {
    if ($script:doQuietly -or $script:wasShownSyntax) { return }
    $script:wasShownSyntax = $true
    Write-PlainLine ''
    Write-PlainLine 'Common commands:'
    Write-PlainLine '  saveup [msg] ...: Commit all local changes and pull updates. Do frequently!'
    Write-PlainLine "  newbr <branch> .: Create a new branch off ${script:mergeTargetLabel} (parks current work first)."
    Write-PlainLine "  gobr [branch] ..: Switch to a branch (parks current work first). No arg: back to ${script:mergeTargetLabel}."
    Write-PlainLine '  status .........: Fetch and show current status.'
    Write-PlainLine '  listbr .........: Fetch and list branches.'
    Write-PlainLine 'Less common commands:'
    Write-PlainLine '  sync [msg] .....: Commit, pull, and push. Do infrequently.'
    Write-PlainLine '  pull ...........: Pull only (auto-stashes around it if dirty).'
    Write-PlainLine '  commit [msg] ...: Commit all local changes (without pull).'
    Write-PlainLine 'Admin commands, e.g. for small solo projects:'
    Write-PlainLine "  land [msg] .....: Merge current branch into ${script:mergeTargetLabel} (--no-ff), push, delete it local + remote."
    Write-PlainLine '  pr [n | ok n] ..: List, review, or accept a pull request (needs gh).'
    Write-PlainLine '  release [ver] ..: Cut a release: merge dev into main, tag, push. No ver: bump patch.'
    Write-PlainLine 'Options:'
    Write-PlainLine '  -m, -Message MSG .....: Commit or merge message (or give it positionally).'
    Write-PlainLine '  -q, -Quiet ...........: No prompts; if committing with no message, one is generated.'
    Write-PlainLine '  -h, -Help  /  -v, -Version'
    Write-PlainLine ''
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Git-state helpers (each verifies, assumes nothing)

function Get-CurrentBranch {
    $branch = git branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $branch) { return '' }
    return [string]$branch
}

function Test-GitOrigin {
    git remote get-url origin *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitUpstream {
    git rev-parse --abbrev-ref '@{u}' *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitAhead {
    $ahead = git log '@{u}..' --oneline 2>$null
    return (($LASTEXITCODE -eq 0) -and ($null -ne $ahead) -and (@($ahead).Count -gt 0))
}

function Test-GitBranchLocal {
    param([Parameter(Mandatory)][string]$Branch)
    git show-ref --verify --quiet "refs/heads/${Branch}" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitBranchRemote {
    param([Parameter(Mandatory)][string]$Branch)
    git show-ref --verify --quiet "refs/remotes/origin/${Branch}" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Test-GitDirty {
    $dirty = git status --porcelain 2>$null
    return (($null -ne $dirty) -and (@($dirty).Count -gt 0))
}

function Get-DefaultBranch {
    ## Prefer origin's HEAD; fall back to whichever of main/master exists locally.
    $originHead = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $originHead) { return (([string]$originHead) -replace '^origin/', '') }
    if (Test-GitBranchLocal -Branch 'main') { return 'main' }
    if (Test-GitBranchLocal -Branch 'master') { return 'master' }
    return 'main'
}

function Get-MergeTarget {
    ## Feature branches come off of - and land on - dev when the repo has one; else the default branch.
    if ((Test-GitBranchLocal -Branch 'dev') -or (Test-GitBranchRemote -Branch 'dev')) { return 'dev' }
    return (Get-DefaultBranch)
}

function Get-BranchSync {
    ## Ahead/behind for the branch line; empty when in sync, so a quiet line means "nothing pending".
    if (-not (Test-GitUpstream)) { return '(no upstream)' }
    $counts = git rev-list --left-right --count '@{u}...HEAD' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $counts) { return '' }
    $parts = ([string]$counts) -split '\s+'
    $behind = [int]$parts[0]
    $ahead = [int]$parts[1]
    $bits = @()
    if ($ahead) { $bits += "ahead ${ahead}" }
    if ($behind) { $bits += "behind ${behind}" }
    if (-not $bits) { return '' }
    return '[{0}]' -f ($bits -join ', ')
}

function Get-CommitIdentity {
    ## What actually gets stamped on commits (config or GIT_AUTHOR_*) - and shown to everyone on the remote.
    $ident = git var GIT_AUTHOR_IDENT 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $ident) { return '(unset)' }
    ## Drop the trailing "timestamp timezone".
    return (([string]$ident) -replace '\s+\S+\s+\S+$', '')
}

function Get-SshTarget {
    ## Host to ask ssh about, pulled out of a remote URL. Empty for https and local-path remotes.
    param([string]$Url)
    if (-not $Url) { return '' }
    if ($Url -match '^ssh://(?:[^@/]+@)?([^:/]+)') { return $Matches[1] }
    if ($Url -match '^[a-z][a-z0-9+.-]*://') { return '' }   ## https/git/file: no ssh identity involved
    if ($Url -match '^(?:[^@/]+@)?([^/:]+):') { return $Matches[1] }  ## scp-like: [user@]host:path
    return ''
}

function Get-ReleaseVersion {
    ## Resolve the release tag: validate the given version, or bump patch on the latest v* tag.
    $ver = $script:cmdArg -replace '^v', ''
    if ($ver) {
        if ($ver -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$') {
            throw "'${ver}' is not a version (want X.Y.Z, optional -suffix). Syntax: ${script:meName} release [version]"
        }
    } else {
        $latest = @(git tag --list 'v[0-9]*' --sort=-v:refname 2>$null) | Select-Object -First 1
        if ($latest) {
            $plain = (([string]$latest) -replace '^v', '') -replace '-.*$', ''
            $parts = $plain -split '\.'
            $ver = '{0}.{1}.{2}' -f $parts[0], $parts[1], ([int]$parts[2] + 1)
        } else {
            $ver = '0.1.0'  ## first release ever
        }
    }
    return "v${ver}"
}

function Invoke-Git {
    ## Announce and run a git command verbatim - argument array, no string re-parsing.
    param([Parameter(Mandatory)][string[]]$GitArgs)
    Write-PlainLine ''
    Write-StatusLine "git $($GitArgs -join ' ') ..."
    git @GitArgs
    if ($LASTEXITCODE -ne 0) { throw "'git $($GitArgs -join ' ')' failed (exit ${LASTEXITCODE})." }
    Clear-BlankCounter
}

function Show-CappedList {
    ## Indent and print a command's output, truncated to the terminal so nothing wraps and capped so a
    ## huge working tree can't scroll the prompt off-screen - the 'less -FX' idea without a pager.
    ## Returns the untruncated line count.
    param([Parameter(Mandatory)][string[]]$GitArgs)
    $maxLines = 25
    $termWidth = 100
    if ($Host.UI.RawUI -and $Host.UI.RawUI.WindowSize.Width -ge 40) { $termWidth = $Host.UI.RawUI.WindowSize.Width }
    $outLines = @(git @GitArgs 2>$null)
    $shown = 0
    foreach ($line in $outLines) {
        if ($shown -ge $maxLines) { break }
        $text = [string]$line
        if ($text.Length -gt $termWidth - 4) { $text = $text.Substring(0, $termWidth - 7) + '...' }
        Write-PlainLine "    ${text}"
        $shown++
    }
    if ($outLines.Count -gt $shown) { Write-PlainLine "    ... and $($outLines.Count - $shown) more" }
    return $outLines.Count
}

function Show-LocalChangeList {
    ## Short form on purpose: git status's long form buries the file list under paragraphs of hints.
    Write-PlainLine 'Local changes:'
    $count = Show-CappedList -GitArgs @('status', '--short')
    if (-not $count) { Write-PlainLine '    (working tree clean)' }
}

function Show-Incoming {
    ## The other half of "what's going to change": what a pull would bring down on top of your work.
    if (-not (Test-GitUpstream)) { return }
    $behind = git rev-list --count 'HEAD..@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $behind -or [int]$behind -eq 0) { return }
    Write-PlainLine ''
    Write-PlainLine "Incoming (${behind} commit(s) to pull):"
    $null = Show-CappedList -GitArgs @('diff', '--name-status', 'HEAD..@{u}')
}

function Show-Identity {
    ## Who a remote-touching command will act as. Host aliases in ~/.ssh/config hide this, and with more
    ## than one account configured it is easy to push as the wrong person.
    param([string]$RemoteUrl)
    $sshHostAlias = Get-SshTarget -Url $RemoteUrl
    if ($sshHostAlias -and (Get-Command ssh -ErrorAction SilentlyContinue)) {
        $sshUser = ''; $sshHost = ''; $keyFile = ''
        foreach ($line in @(ssh -G $sshHostAlias 2>$null)) {
            $key, $value = ([string]$line) -split '\s+', 2
            switch ($key) {
                'user' { if (-not $sshUser) { $sshUser = $value } }
                'hostname' { if (-not $sshHost) { $sshHost = $value } }
                'identityfile' {
                    if (-not $keyFile) {
                        $expanded = $value -replace '^~', $HOME
                        if (Test-Path -LiteralPath $expanded) { $keyFile = $value }
                    }
                }
            }
        }
        if ($sshHost) {
            $sshLine = '{0}@{1}' -f $(if ($sshUser) { $sshUser } else { '?' }), $sshHost
            if ($sshHostAlias -ne $sshHost) { $sshLine += " (alias '${sshHostAlias}')" }
            if ($keyFile) { $sshLine += ", key ${keyFile}" }
            Write-PlainLine "SSH ..........: ${sshLine}"
        }
    }
    Write-PlainLine "Author .......: $(Get-CommitIdentity)"
}

function Show-RepoStatus {
    ## -WithIdentity: also show who we'll be on the remote - pre-flight and 'status', but not the after-shot.
    param([switch]$WithIdentity)
    $remote = git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remote) { $remote = '(none)' }
    Write-PlainLine ''
    Write-PlainLine "Directory ....: $(Get-Location)"
    Write-PlainLine "Remote .......: ${remote}"
    if ($WithIdentity) { Show-Identity -RemoteUrl ([string]$remote) }
    $branchLine = "$(Get-CurrentBranch) (repo default: $(Get-DefaultBranch)) $(Get-BranchSync)"
    Write-PlainLine "Branch .......: $($branchLine.TrimEnd())"
    Write-PlainLine ''
    Show-LocalChangeList
    if ($WithIdentity) { Show-Incoming }
    Clear-BlankCounter
}

function Show-CommandPreview {
    ## Static per-command recipe; the command functions do the real state checks at run time.
    param([Parameter(Mandatory)][string]$CommandName)
    $pad = '    '
    $msgDisp = 'git commit'
    if ($script:commitMessage) { $msgDisp = "git commit -m `"$($script:commitMessage)`"" }
    switch ($CommandName) {
        'commit' {
            Write-PlainLine "${pad}git add --all"
            Write-PlainLine "${pad}${msgDisp} *"
            break
        }
        'pull' {
            Write-PlainLine "${pad}git stash push --include-untracked *"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git stash pop *"
            break
        }
        'saveup' {
            Show-CommandPreview -CommandName 'commit'
            Show-CommandPreview -CommandName 'pull'
            break
        }
        'sync' {
            Show-CommandPreview -CommandName 'saveup'
            Write-PlainLine "${pad}git push *"
            break
        }
        'newbr' {
            Show-CommandPreview -CommandName 'sync'
            Write-PlainLine "${pad}git checkout $(Get-MergeTarget) *"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git checkout -b $($script:cmdArg)"
            Write-PlainLine "${pad}git push -u origin $($script:cmdArg) *"
            break
        }
        'gobr' {
            Show-CommandPreview -CommandName 'sync'
            $target = if ($script:cmdArg) { $script:cmdArg } else { Get-MergeTarget }
            Write-PlainLine "${pad}git checkout ${target}"
            Write-PlainLine "${pad}git pull --ff-only *"
            break
        }
        'land' {
            Show-CommandPreview -CommandName 'sync'
            Write-PlainLine "${pad}git checkout $(Get-MergeTarget)"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git merge --no-ff $(Get-CurrentBranch)"
            Write-PlainLine "${pad}git push *"
            Write-PlainLine "${pad}git branch -d $(Get-CurrentBranch)"
            Write-PlainLine "${pad}git push origin --delete $(Get-CurrentBranch) *"
            Write-PlainLine "${pad}git pull --ff-only *"
            break
        }
        'pr' {
            Write-PlainLine "${pad}gh pr review $($script:prNum) --approve *"
            Write-PlainLine "${pad}gh pr merge $($script:prNum) --merge --delete-branch"
            Write-PlainLine "${pad}git pull --ff-only *"
            break
        }
        'release' {
            Show-CommandPreview -CommandName 'sync'
            if ((Get-MergeTarget) -eq 'dev') {
                Write-PlainLine "${pad}git checkout dev *"
                Write-PlainLine "${pad}git pull --ff-only *"
            }
            Write-PlainLine "${pad}git checkout $(Get-DefaultBranch) *"
            Write-PlainLine "${pad}git pull --ff-only *"
            if ((Get-MergeTarget) -eq 'dev') { Write-PlainLine "${pad}git merge --no-ff dev" }
            Write-PlainLine "${pad}git tag -a $($script:releaseTag)"
            Write-PlainLine "${pad}git push *"
            Write-PlainLine "${pad}git push origin $($script:releaseTag) *"
            Write-PlainLine "${pad}git checkout $(Get-CurrentBranch) *"
            break
        }
    }
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Commands

function Invoke-GitsbyCommit {
    Invoke-Git -GitArgs @('add', '--all')
    if (-not (Test-GitDirty)) {
        Write-StatusLine 'Nothing to commit.'
    } elseif ($script:commitMessage) {
        Invoke-Git -GitArgs @('commit', '-m', $script:commitMessage)
    } elseif ($script:doQuietly) {
        ## quiet mode can't open an editor
        Invoke-Git -GitArgs @('commit', '-m', "${script:meName} $(Get-Date -Format 'yyyyMMdd-HHmmss')")
    } else {
        Invoke-Git -GitArgs @('commit')
    }
}

function Invoke-GitsbyPull {
    $didStash = $false
    if (Test-GitDirty) {
        $preCount = @(git stash list 2>$null).Count
        Invoke-Git -GitArgs @('stash', 'push', '--include-untracked', '-m', "${script:meName} autostash")
        $postCount = @(git stash list 2>$null).Count
        $didStash = ($postCount -gt $preCount)  ## push can no-op; only pop what we pushed
    }
    if (Test-GitUpstream) {
        Invoke-Git -GitArgs @('pull', '--ff-only')
    } else {
        Write-StatusLine 'No upstream configured for this branch; nothing to pull.'
    }
    if ($didStash) { Invoke-Git -GitArgs @('stash', 'pop') }
}

function Invoke-GitsbyCommitPull {
    Invoke-GitsbyCommit
    Invoke-GitsbyPull
}

function Invoke-GitsbyPush {
    Invoke-GitsbyCommitPull
    if (-not (Test-GitOrigin)) {
        Write-StatusLine "No 'origin' remote; nothing to push."
    } elseif (-not (Test-GitUpstream)) {
        Invoke-Git -GitArgs @('push', '-u', 'origin', 'HEAD')  ## first publish of this branch
    } elseif (Test-GitAhead) {
        Invoke-Git -GitArgs @('push')
    } else {
        Write-StatusLine 'Nothing to push.'
    }
}

function Invoke-GitsbyMakeBranch {
    param([string]$NewBranch = '')
    if (-not $NewBranch) { throw "No branch name given. Syntax: ${script:meName} newbr <new branch name>" }
    git check-ref-format --branch $NewBranch *> $null
    if ($LASTEXITCODE -ne 0) { throw "'${NewBranch}' is not a valid branch name." }
    if (Test-GitBranchLocal -Branch $NewBranch) { throw "Branch '${NewBranch}' already exists; use: ${script:meName} gobr ${NewBranch}" }
    if (Test-GitBranchRemote -Branch $NewBranch) { throw "Branch '${NewBranch}' already exists on origin; use: ${script:meName} gobr ${NewBranch}" }
    $baseBranch = Get-MergeTarget
    Invoke-GitsbyPush  ## park current work safely first
    if ((Get-CurrentBranch) -ne $baseBranch) { Invoke-Git -GitArgs @('checkout', $baseBranch) }
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
    Invoke-Git -GitArgs @('checkout', '-b', $NewBranch)
    if (Test-GitOrigin) { Invoke-Git -GitArgs @('push', '-u', 'origin', $NewBranch) }
}

function Invoke-GitsbyChangeBranch {
    param([string]$TargetBranch = '')
    if (-not $TargetBranch) { $TargetBranch = Get-MergeTarget }
    if ((Get-CurrentBranch) -eq $TargetBranch) {
        Write-StatusLine "Already on '${TargetBranch}'."
        if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
        return
    }
    if (-not ((Test-GitBranchLocal -Branch $TargetBranch) -or (Test-GitBranchRemote -Branch $TargetBranch))) {
        throw "No branch '${TargetBranch}' locally or on origin. To create it: ${script:meName} newbr ${TargetBranch}"
    }
    Invoke-GitsbyPush  ## park current work safely first
    Invoke-Git -GitArgs @('checkout', $TargetBranch)  ## auto-creates a tracking branch if it only exists on origin
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
}

function Invoke-GitsbyLand {
    ## Merges the current branch into dev (or main/master) - backwards from 'git merge', but saves a step.
    $targetBranch = Get-MergeTarget
    $workBranch = Get-CurrentBranch
    if ($workBranch -eq $targetBranch) { throw "Already on '${targetBranch}'. Run this from the branch to merge in: ${script:meName} gobr <branch>, then ${script:meName} land" }
    if ($workBranch -eq (Get-DefaultBranch)) { throw "'${workBranch}' is the default branch; landing it on '${targetBranch}' is backwards. To cut a release: ${script:meName} release" }
    $mergeMessage = $script:commitMessage
    if (-not $mergeMessage) { $mergeMessage = "Merge ${workBranch}" }
    Invoke-GitsbyPush
    Invoke-Git -GitArgs @('checkout', $targetBranch)
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
    Invoke-Git -GitArgs @('merge', '--no-ff', $workBranch, '-m', $mergeMessage)
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('push') }
    Invoke-Git -GitArgs @('branch', '-d', $workBranch)
    if (Test-GitBranchRemote -Branch $workBranch) { Invoke-Git -GitArgs @('push', 'origin', '--delete', $workBranch) }
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
}

function Invoke-GitsbyPrView {
    ## Bare: list open PRs. With a number: view it plus its diff.
    param([string]$PrNumber = '')
    if (-not $PrNumber) {
        Write-PlainLine ''
        Write-StatusLine 'gh pr list ...'
        gh pr list
    } else {
        Write-PlainLine ''
        Write-StatusLine "gh pr view ${PrNumber} ..."
        gh pr view $PrNumber
        Write-PlainLine ''
        Write-StatusLine "gh pr diff ${PrNumber} ..."
        gh pr diff $PrNumber
    }
    if ($LASTEXITCODE -ne 0) { throw "gh failed (exit ${LASTEXITCODE})." }
    Clear-BlankCounter
}

function Invoke-GitsbyPrAccept {
    param([Parameter(Mandatory)][string]$PrNumber)
    Write-PlainLine ''
    Write-StatusLine "gh pr review ${PrNumber} --approve ..."
    ## Best-effort: gh refuses to approve your own PR; merging is the part that matters.
    gh pr review $PrNumber --approve
    if ($LASTEXITCODE -ne 0) { Write-StatusLine 'Could not approve (own PR?); merging anyway.' }
    Clear-BlankCounter
    Write-PlainLine ''
    Write-StatusLine "gh pr merge ${PrNumber} --merge --delete-branch ..."
    gh pr merge $PrNumber --merge --delete-branch
    if ($LASTEXITCODE -ne 0) { throw "gh pr merge failed (exit ${LASTEXITCODE})." }
    Clear-BlankCounter
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
}

function Invoke-GitsbyRelease {
    ## Cuts a release: merge dev into main/master --no-ff (if the repo has a dev), tag, push both.
    $mainBranch = Get-DefaultBranch
    $devBranch = ''
    if ((Test-GitBranchLocal -Branch 'dev') -or (Test-GitBranchRemote -Branch 'dev')) { $devBranch = 'dev' }
    git rev-parse -q --verify "refs/tags/$($script:releaseTag)" *> $null
    if ($LASTEXITCODE -eq 0) { throw "Tag '$($script:releaseTag)' already exists." }
    $startBranch = Get-CurrentBranch
    Invoke-GitsbyPush  ## park current work safely first
    if ($devBranch -and ((Get-CurrentBranch) -ne $devBranch)) {
        Invoke-Git -GitArgs @('checkout', $devBranch)  ## freshen dev so the release has all of it
        if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
    }
    if ((Get-CurrentBranch) -ne $mainBranch) { Invoke-Git -GitArgs @('checkout', $mainBranch) }
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
    if ($devBranch) {
        $mergeMessage = $script:commitMessage
        if (-not $mergeMessage) { $mergeMessage = "Release $($script:releaseTag)" }
        Invoke-Git -GitArgs @('merge', '--no-ff', $devBranch, '-m', $mergeMessage)
    }
    Invoke-Git -GitArgs @('tag', '-a', $script:releaseTag, '-m', $script:releaseTag)
    if (Test-GitOrigin) {
        if (Test-GitUpstream) { Invoke-Git -GitArgs @('push') }
        Invoke-Git -GitArgs @('push', 'origin', $script:releaseTag)
    }
    ## Don't leave the user parked on main.
    if ($startBranch -and ($startBranch -ne $mainBranch)) { Invoke-Git -GitArgs @('checkout', $startBranch) }
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Script entry point

try {
    ## pwsh doesn't bind '--help'-style tokens as parameters; they land positionally.
    if ($Command -match '^-{1,2}(h|help)$') { $Help = $true; $Command = '' }
    if ($Command -match '^-{1,2}(v|ver|version)$') { $Version = $true; $Command = '' }

    if ($Help) { Show-Copyright; Show-About; Show-Syntax; exit 0 }
    if ($Version) { Show-Copyright; exit 0 }
    if (-not $Command) { Show-Copyright; Show-About; Show-Syntax; exit 1 }

    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) { throw 'Not found in path: git' }

    ## Anything else option-shaped in the positional slots is a mistake, not data.
    if ($Command -match '^--?[^ -]') { throw "Unexpected option in this context: '${Command}'." }
    if ($CommandArg -match '^--$|^--?[^ -]') { throw "Unexpected option in this context: '${CommandArg}'." }
    if ($CommandArg2 -match '^--$|^--?[^ -]') { throw "Unexpected option in this context: '${CommandArg2}'." }

    ## No tty = nobody to answer a prompt; behave as if -Quiet.
    if ([Console]::IsInputRedirected) { $script:doQuietly = $true }

    ## Old command names still work as hidden aliases (muscle memory), but stay out of the help.
    $cmdName = $Command.ToLowerInvariant()
    $cmdName = switch ($cmdName) {
        'scommit' { 'commit'; break }
        'spull' { 'pull'; break }
        'scompul' { 'saveup'; break }
        'spush' { 'sync'; break }
        'mkbranch' { 'newbr'; break }
        'chbranch' { 'gobr'; break }
        'mtm' { 'land'; break }
        'list' { 'listbr'; break }
        default { $cmdName }
    }

    ## Sort commands, and route positional arg 2 (message vs branch name; -m wins for messages).
    $isMutating = $true
    switch ($cmdName) {
        { $_ -in 'status', 'listbr' } { $isMutating = $false; break }
        'pr' { if ($CommandArg.ToLowerInvariant() -ne 'ok') { $isMutating = $false }; break }
        { $_ -in 'commit', 'saveup', 'sync', 'land' } { if (-not $script:commitMessage) { $script:commitMessage = $CommandArg }; break }
        { $_ -in 'pull', 'newbr', 'gobr', 'release' } { break }
        default { throw "Unknown command '${cmdName}'. Run '${script:meName}' with no arguments for a list." }
    }

    ## pr needs gh and a valid number (except the bare list form).
    $script:prNum = ''
    if ($cmdName -eq 'pr') {
        if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) { throw 'Not found in path: gh' }
        if ($CommandArg.ToLowerInvariant() -eq 'ok') {
            $script:prNum = $CommandArg2
            if ($script:prNum -notmatch '^[0-9]+$') { throw "Syntax: ${script:meName} pr ok <number>" }
        } elseif ($CommandArg) {
            $script:prNum = $CommandArg
            if ($script:prNum -notmatch '^[0-9]+$') { throw "Syntax: ${script:meName} pr [<number> | ok <number>]" }
        }
    }

    ## Every command needs a repo.
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Not inside a git repository. Change to a git project directory first.' }

    ## Freshen remote refs so status/ahead-behind info is current. Never fatal - offline still works locally.
    if (Test-GitOrigin) {
        Write-StatusLine 'git fetch ...'
        git fetch --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { Write-StatusLine 'WARNING: git fetch failed (offline?); remote info may be stale.' }
    }

    ## Release version resolves up front so preview and command agree (and bad input dies early).
    $script:releaseTag = ''
    if ($cmdName -eq 'release') { $script:releaseTag = Get-ReleaseVersion }

    ## Read-only commands
    if (-not $isMutating) {
        switch ($cmdName) {
            'status' { Show-RepoStatus -WithIdentity; break }
            'listbr' { Write-StatusLine 'git branch -a -vv'; git branch -a -vv; Clear-BlankCounter; break }
            'pr' { Invoke-GitsbyPrView -PrNumber $script:prNum; break }
        }
        Write-PlainLine ''
        exit 0
    }

    ## Mutating commands: show state and plan, confirm, execute, show state again.
    if (-not (Get-CurrentBranch)) { throw 'Detached HEAD (no current branch); resolve that manually first.' }
    Show-RepoStatus -WithIdentity
    Write-PlainLine ''
    Write-PlainLine 'Going to do (steps marked * only if needed, based on repo state):'
    Show-CommandPreview -CommandName $cmdName
    if (-not $script:doQuietly) {
        Write-PlainLine ''
        $answer = Read-Host -Prompt 'Continue? (y|n)'
        Clear-BlankCounter
        if ($answer -ne 'y') { Write-StatusLine 'User aborted.'; exit 1 }
    }

    switch ($cmdName) {
        'commit' { Invoke-GitsbyCommit; break }
        'pull' { Invoke-GitsbyPull; break }
        'saveup' { Invoke-GitsbyCommitPull; break }
        'sync' { Invoke-GitsbyPush; break }
        'newbr' { Invoke-GitsbyMakeBranch -NewBranch $CommandArg; break }
        'gobr' { Invoke-GitsbyChangeBranch -TargetBranch $CommandArg; break }
        'land' { Invoke-GitsbyLand; break }
        'pr' { Invoke-GitsbyPrAccept -PrNumber $script:prNum; break }
        'release' { Invoke-GitsbyRelease; break }
    }

    Write-PlainLine ''
    Show-RepoStatus
    Write-StatusLine ''
    Write-StatusLine 'Done.'
    Write-PlainLine ''
} catch {
    Write-PlainLine ''
    [Console]::Error.WriteLine("${script:meName}: $($_.Exception.Message)")
    Write-PlainLine ''
    exit 1
}


##  History:
##      - 20260722 JC: Created; port of bin/gitsby (same commands, checks, and flow).
##      - 20260722 JC: Command renames (old names stay as hidden aliases), dev-aware merge target, pr and release commands - in step with bin/gitsby.
##      - 20260723 JC: Pre-flight display (SSH identity, commit author, ahead/behind, incoming files) and the capped short-form change list - in step with bin/gitsby.
