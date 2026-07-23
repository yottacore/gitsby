#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Safer, state-checked wrappers for everyday git.
.DESCRIPTION
    PowerShell port of gitsby. Every command verifies the repo state before
    acting (stash only if dirty, pull only with an upstream, push only if
    ahead), so each is idempotent and safe to re-run.
.PARAMETER Command
    scompul | mkbranch | chbranch | status | list | spush | spull | scommit | mtm
.PARAMETER CommandArg
    Message (scommit/scompul/spush/mtm) or branch name (mkbranch/chbranch).
.PARAMETER Message
    Commit or merge message (-m/-msg also work; or give it positionally).
.PARAMETER Quiet
    No prompts; if committing with no message, one is generated.
.EXAMPLE
    gitsby.ps1 scompul "fixed the frobnicator"
.EXAMPLE
    gitsby.ps1 mkbranch featx
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
$script:defaultBranchLabel = 'main/master'  ## for help text, before we know we're in a repo

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
    Write-PlainLine '  scompul [msg] ........: Commit all local changes and pull updates. Do frequently!'
    Write-PlainLine "  mkbranch <branch> ....: Create a new branch off ${script:defaultBranchLabel} (parks current work first)."
    Write-PlainLine '  chbranch [branch] ....: Switch to an existing branch (parks current work first).'
    Write-PlainLine "                          With no branch given, switches to ${script:defaultBranchLabel}."
    Write-PlainLine '  status ...............: Fetch and show current status.'
    Write-PlainLine '  list .................: Fetch and list branches.'
    Write-PlainLine 'Less common commands:'
    Write-PlainLine '  spush [msg] ..........: Commit, pull, and push. Do infrequently.'
    Write-PlainLine '  spull ................: Pull only (auto-stashes around it if dirty).'
    Write-PlainLine '  scommit [msg] ........: Commit all local changes (without pull).'
    Write-PlainLine 'Admin commands, e.g. for small solo projects:'
    Write-PlainLine "  mtm [msg] ............: Merge the current branch into ${script:defaultBranchLabel} (--no-ff),"
    Write-PlainLine '                          push, and delete the merged branch local + remote.'
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

function Invoke-Git {
    ## Announce and run a git command verbatim - argument array, no string re-parsing.
    param([Parameter(Mandatory)][string[]]$GitArgs)
    Write-PlainLine ''
    Write-StatusLine "git $($GitArgs -join ' ') ..."
    git @GitArgs
    if ($LASTEXITCODE -ne 0) { throw "'git $($GitArgs -join ' ')' failed (exit ${LASTEXITCODE})." }
    Clear-BlankCounter
}

function Show-RepoStatus {
    $remote = git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remote) { $remote = '(none)' }
    Write-PlainLine ''
    Write-PlainLine "Directory ....: $(Get-Location)"
    Write-PlainLine "Remote .......: ${remote}"
    Write-PlainLine "Branch .......: $(Get-CurrentBranch) (repo default: $(Get-DefaultBranch))"
    Write-PlainLine ''
    Write-PlainLine 'git status:'
    git status | ForEach-Object { Write-Host "    $_" }
    Clear-BlankCounter
}

function Show-CommandPreview {
    ## Static per-command recipe; the command functions do the real state checks at run time.
    param([Parameter(Mandatory)][string]$CommandName)
    $pad = '    '
    $msgDisp = 'git commit'
    if ($script:commitMessage) { $msgDisp = "git commit -m `"$($script:commitMessage)`"" }
    switch ($CommandName) {
        'scommit' {
            Write-PlainLine "${pad}git add --all"
            Write-PlainLine "${pad}${msgDisp} *"
            break
        }
        'spull' {
            Write-PlainLine "${pad}git stash push --include-untracked *"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git stash pop *"
            break
        }
        'scompul' {
            Show-CommandPreview -CommandName 'scommit'
            Show-CommandPreview -CommandName 'spull'
            break
        }
        'spush' {
            Show-CommandPreview -CommandName 'scompul'
            Write-PlainLine "${pad}git push *"
            break
        }
        'mkbranch' {
            Show-CommandPreview -CommandName 'spush'
            Write-PlainLine "${pad}git checkout $(Get-DefaultBranch) *"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git checkout -b $($script:cmdArg)"
            Write-PlainLine "${pad}git push -u origin $($script:cmdArg) *"
            break
        }
        'chbranch' {
            Show-CommandPreview -CommandName 'spush'
            $target = if ($script:cmdArg) { $script:cmdArg } else { Get-DefaultBranch }
            Write-PlainLine "${pad}git checkout ${target}"
            Write-PlainLine "${pad}git pull --ff-only *"
            break
        }
        'mtm' {
            Show-CommandPreview -CommandName 'spush'
            Write-PlainLine "${pad}git checkout $(Get-DefaultBranch)"
            Write-PlainLine "${pad}git pull --ff-only *"
            Write-PlainLine "${pad}git merge --no-ff $(Get-CurrentBranch)"
            Write-PlainLine "${pad}git push *"
            Write-PlainLine "${pad}git branch -d $(Get-CurrentBranch)"
            Write-PlainLine "${pad}git push origin --delete $(Get-CurrentBranch) *"
            Write-PlainLine "${pad}git pull --ff-only *"
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
    if (-not $NewBranch) { throw "No branch name given. Syntax: ${script:meName} mkbranch <new branch name>" }
    git check-ref-format --branch $NewBranch *> $null
    if ($LASTEXITCODE -ne 0) { throw "'${NewBranch}' is not a valid branch name." }
    if (Test-GitBranchLocal -Branch $NewBranch) { throw "Branch '${NewBranch}' already exists; use: ${script:meName} chbranch ${NewBranch}" }
    if (Test-GitBranchRemote -Branch $NewBranch) { throw "Branch '${NewBranch}' already exists on origin; use: ${script:meName} chbranch ${NewBranch}" }
    $baseBranch = Get-DefaultBranch
    Invoke-GitsbyPush  ## park current work safely first
    if ((Get-CurrentBranch) -ne $baseBranch) { Invoke-Git -GitArgs @('checkout', $baseBranch) }
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
    Invoke-Git -GitArgs @('checkout', '-b', $NewBranch)
    if (Test-GitOrigin) { Invoke-Git -GitArgs @('push', '-u', 'origin', $NewBranch) }
}

function Invoke-GitsbyChangeBranch {
    param([string]$TargetBranch = '')
    if (-not $TargetBranch) { $TargetBranch = Get-DefaultBranch }
    if ((Get-CurrentBranch) -eq $TargetBranch) {
        Write-StatusLine "Already on '${TargetBranch}'."
        if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
        return
    }
    if (-not ((Test-GitBranchLocal -Branch $TargetBranch) -or (Test-GitBranchRemote -Branch $TargetBranch))) {
        throw "No branch '${TargetBranch}' locally or on origin. To create it: ${script:meName} mkbranch ${TargetBranch}"
    }
    Invoke-GitsbyPush  ## park current work safely first
    Invoke-Git -GitArgs @('checkout', $TargetBranch)  ## auto-creates a tracking branch if it only exists on origin
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
}

function Invoke-GitsbyMergeToMain {
    ## Merges the current branch into main/master - backwards from 'git merge', but saves a step.
    $mainBranch = Get-DefaultBranch
    $workBranch = Get-CurrentBranch
    if ($workBranch -eq $mainBranch) { throw "Already on '${mainBranch}'. Run this from the branch to merge in: ${script:meName} chbranch <branch>, then ${script:meName} mtm" }
    $mergeMessage = $script:commitMessage
    if (-not $mergeMessage) { $mergeMessage = "Merge ${workBranch}" }
    Invoke-GitsbyPush
    Invoke-Git -GitArgs @('checkout', $mainBranch)
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
    Invoke-Git -GitArgs @('merge', '--no-ff', $workBranch, '-m', $mergeMessage)
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('push') }
    Invoke-Git -GitArgs @('branch', '-d', $workBranch)
    if (Test-GitBranchRemote -Branch $workBranch) { Invoke-Git -GitArgs @('push', 'origin', '--delete', $workBranch) }
    if (Test-GitUpstream) { Invoke-Git -GitArgs @('pull', '--ff-only') }
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

    ## No tty = nobody to answer a prompt; behave as if -Quiet.
    if ([Console]::IsInputRedirected) { $script:doQuietly = $true }

    ## Sort commands, and route positional arg 2 (message vs branch name; -m wins for messages).
    $cmdName = $Command.ToLowerInvariant()
    $isMutating = $true
    switch ($cmdName) {
        { $_ -in 'status', 'list' } { $isMutating = $false; break }
        { $_ -in 'scommit', 'scompul', 'spush', 'mtm' } { if (-not $script:commitMessage) { $script:commitMessage = $CommandArg }; break }
        { $_ -in 'spull', 'mkbranch', 'chbranch' } { break }
        default { throw "Unknown command '${cmdName}'. Run '${script:meName}' with no arguments for a list." }
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

    ## Read-only commands
    if (-not $isMutating) {
        switch ($cmdName) {
            'status' { Show-RepoStatus; break }
            'list' { Write-StatusLine 'git branch -a -vv'; git branch -a -vv; Clear-BlankCounter; break }
        }
        Write-PlainLine ''
        exit 0
    }

    ## Mutating commands: show state and plan, confirm, execute, show state again.
    if (-not (Get-CurrentBranch)) { throw 'Detached HEAD (no current branch); resolve that manually first.' }
    Show-RepoStatus
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
        'scommit' { Invoke-GitsbyCommit; break }
        'spull' { Invoke-GitsbyPull; break }
        'scompul' { Invoke-GitsbyCommitPull; break }
        'spush' { Invoke-GitsbyPush; break }
        'mkbranch' { Invoke-GitsbyMakeBranch -NewBranch $CommandArg; break }
        'chbranch' { Invoke-GitsbyChangeBranch -TargetBranch $CommandArg; break }
        'mtm' { Invoke-GitsbyMergeToMain; break }
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
