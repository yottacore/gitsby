<#
.SYNOPSIS
    Windows-native local CI/CD pipeline for gitsby.
.DESCRIPTION
    A PowerShell port of cicd/cicd.bash, running the same six stages natively on
    Windows. Does not touch cicd.bash - that stays the Linux pipeline.

    Stages (fail-fast; any error aborts before the next stage):
      0. sync       fast-forward from origin before anything is built or tested
      1. lint       bash -n + shellcheck, gating; markdownlint, py_compile and
                    PSScriptAnalyzer when their tools are installed
      2. tests      cicd/test.bash
      3. fuzz       cicd/fuzz.bash (skipped by -Quick)
      4. dogfood    copy bin/gitsby and bin/gitsby.ps1 to the util dirs
      5. demo gif   render and compare, never overwrite (skipped by -Quick)
      6. publish    stash, pull, commit, push - a native port of
                    cicd/utility/n8git_backup-and-publish

    Differences from the Linux engine, and why:
      - No rar version archive. Skipped by request; git carries the history.
      - The demo gif is compared, never regenerated. Reproducing it byte for byte
        is a Linux contract (fontconfig, the installed font versions, the pinned
        gifsicle), so a Windows render would land a different file that the next
        Linux run would flip straight back. In practice the stage warn-skips:
        gen-demo-gif.py picks its font through fc-match, which Windows has no
        equivalent of.
      - Stages whose tool is absent warn and skip, exactly as they do on Linux.
        On a stock Windows box that is usually markdownlint (needs node) and the
        demo gif.

    Settings live in the Configuration section below rather than in config.bash.
    Only the dogfood destinations genuinely differ; keep the rest in step.
.PARAMETER Quiet
    Quiet and unattended: no prompt, and the publish step runs quiet too.
.PARAMETER Yes
    Unattended (no prompt), but not quiet.
.PARAMETER Message
    Publish hands-off with this commit message, so git never opens an editor.
.PARAMETER Quick
    Skip the slow stages (fuzz, demo gif).
.PARAMETER NoLint
    Skip the lint stage.
.PARAMETER NoTest
    Skip the regression test stage.
.PARAMETER NoFuzz
    Skip the fuzz and security stage.
.PARAMETER NoDogfood
    Skip installing the scripts locally.
.PARAMETER NoDemoGif
    Skip the demo gif check.
.PARAMETER NoPublish
    Skip the git backup and publish stage.
.PARAMETER Help
    Show this help.
.EXAMPLE
    pwsh cicd/cicd-win.ps1
.EXAMPLE
    pwsh cicd/cicd-win.ps1 -Quick -Quiet -Message "tidy"
.NOTES
    History at bottom of script. Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞).
    Licensed under The MIT License (MIT): https://mit-license.org/
    SPDX-License-Identifier: MIT
#>

## Console-only pipeline; everything written is for the human watching the run.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console tool; output is UI, not pipeline data.')]
## No BOM, matching the other .ps1 files in this repo (see the 20260728 BOM fix).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'Repo convention is UTF-8 without BOM.')]
[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Yes,
    [string]$Message = "",
    [switch]$Quick,
    [switch]$NoSync,
    [switch]$NoLint,
    [switch]$NoTest,
    [switch]$NoFuzz,
    [switch]$NoDogfood,
    [switch]$NoDemoGif,
    [switch]$NoPublish,
    [switch]$Help
)

## PowerShell 7+ only. Windows PowerShell 5.1 has no $IsWindows, so the guard
## below would throw something cryptic instead of saying what to run.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Error "cicd-win.ps1 needs PowerShell 7+ (pwsh); you're on Windows PowerShell $($PSVersionTable.PSVersion). Run: pwsh -File cicd/cicd-win.ps1"
    exit 1
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
## We drive native tools by hand and read $LASTEXITCODE - several probes (git
## diff --quiet, shellcheck) return non-zero on purpose. Keep a non-zero native
## exit from throwing, whatever the caller's shell preference is.
$PSNativeCommandUseErrorActionPreference = $false

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed
    exit 0
}

## Windows-only: this pipeline writes into Windows dogfood dirs and resolves Git
## Bash by Windows path. Everywhere else, cicd.bash is the pipeline.
if (-not $IsWindows) {
    Write-Error "cicd-win.ps1: this pipeline only runs on Windows (use cicd/cicd.bash elsewhere)."
    exit 1
}

## -Quiet implies unattended; both suppress the preflight prompt.
$Unattended = ($Yes -or $Quiet)
$Stamp      = Get-Date -Format "yyyyMMdd-HHmmss"

## -Quick and the -No* switches, folded into the same booleans the bash engine
## keeps, so the two read the same way.
$DoSync    = -not $NoSync
$DoLint    = -not $NoLint
$DoTest    = -not $NoTest
$DoFuzz    = (-not $NoFuzz) -and (-not $Quick)
$DoDogfood = -not $NoDogfood
$DoDemoGif = (-not $NoDemoGif) -and (-not $Quick)
$DoPublish = -not $NoPublish


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Configuration (mirrors cicd/config.bash - keep the two in step)

## Repo root = the parent of this script's cicd/ dir. Everything runs from there.
$Root    = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$AppName = "gitsby"
$ExeName = "gitsby"

## Stage 1: lint. Every first-party shell file. shellcheck is gating; there is
## deliberately no formatter stage - bash here is hand-formatted on purpose.
$ShellLintGlob = @(
    "bin/gitsby"
    "install*.bash"
    "cicd/*.bash"
    "cicd/utility/*.bash"
    "cicd/utility/n8git_backup-and-publish"
    "cicd/utility/include/*.bash"
)
## Report-only (findings warn, never gate). Empty since the bin/gitsby refactor.
$ShellLintWarnGlob = @()
$MdLintGlob        = @("*.md", "project/*.md", "project/design_docs/*.md")
$PyLintFile        = @("cicd/utility/gen-demo-gif.py")
$PsLintGlob        = @("bin/gitsby.ps1", "install*.ps1", "cicd/*.ps1")

## Stages 2 and 3: the bash harnesses, run under Git Bash.
$TestScript = "cicd/test.bash"
$FuzzScript = "cicd/fuzz.bash"

## Full run transcript (gitignored). Its own dir so the two pipelines' rotations
## can't prune each other's logs.
$LogDir = "cicd/artifacts/lint-win"

## Stage 4: dogfood. A script project's release build is the script itself, so
## copy it over the first existing dir below - the stable path you launch by
## hand. No elevation fallback: an unwritable dest is a warning, not an
## unattended privilege escalation.
$DogfoodBashSrc  = "bin/gitsby"
$DogfoodBashDest = @(
    "C:\opt\0-0\common\exec\synced\util\wsl\bash"
    (Join-Path $env:USERPROFILE "synced\0-0\common\exec\util\wsl\bash")
)
$DogfoodPwshSrc  = "bin/gitsby.ps1"
$DogfoodPwshDest = @(
    "C:\opt\0-0\common\exec\synced\util\0_crossplatform"
    (Join-Path $env:USERPROFILE "synced\0-0\common\exec\util\0_crossplatform")
)

## Stage 5: demo gif. Compare only - see the header for why Windows never lands
## a render.
$DemoGifScenario = "cicd/demo-scenario.toml"
$DemoGifScript   = "cicd/utility/gen-demo-gif.py"
$DemoGifOut      = "assets/demo.gif"

## Sourced through bash to rotate the run logs, the same helper cicd.bash uses.
$GfsRotate = "cicd/utility/include/gfs-rotate.bash"

## Publish commit message: -Message wins, then an auto stamp when unattended.
## Interactive runs capture it at the preflight prompt; still empty at commit
## time means let git open its editor.
$PublishMsg = ""
if     ($Message)    { $PublishMsg = $Message }
elseif ($Unattended) { $PublishMsg = "$AppName CI/CD $Stamp" }


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Output helpers (mirror cicd.bash: fEcho / fEcho_Clean / fSection)

$script:WasLastEchoBlank = $false
$script:Transcribing     = $false
$script:RunLogPath       = ""
$script:RunLogUnix       = ""
$script:Letterbox        = "•" * 74

function fEcho_Clean {
    param([string]$Msg = "")
    if ($Msg) { Write-Host $Msg; $script:WasLastEchoBlank = $false }
    elseif (-not $script:WasLastEchoBlank) { Write-Host ""; $script:WasLastEchoBlank = $true }
}
function fEcho    { param([string]$Msg = ""); if ($Msg) { fEcho_Clean "[ $Msg ]" } else { fEcho_Clean } }
function fSection { param([Parameter(Mandatory)][string]$Msg); fEcho_Clean; fEcho_Clean $script:Letterbox; fEcho $Msg }
function fNote    { param([Parameter(Mandatory)][string]$Msg); fEcho_Clean $Msg }
function fWarn    { param([Parameter(Mandatory)][string]$Msg); fEcho "WARNING: $Msg" }
function fDie     { param([Parameter(Mandatory)][string]$Msg); fEcho "FAILED: $Msg"; exit 1 }


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Functions

## Git Bash, specifically. A bare 'bash' on PATH is usually the WSL launcher in
## System32, which sees the repo at /mnt/c and can't run these harnesses against
## the Windows pwsh they shim out to. Resolve the real thing, or nothing.
function Resolve-BashExe {
    $candidate = [System.Collections.Generic.List[string]]::new()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        ## <git>/cmd/git.exe -> <git>/bin/bash.exe
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        $candidate.Add((Join-Path $gitRoot "bin\bash.exe"))
    }
    $candidate.Add("$env:ProgramFiles\Git\bin\bash.exe")
    $candidate.Add("${env:ProgramFiles(x86)}\Git\bin\bash.exe")
    $candidate.Add("$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
    foreach ($path in $candidate) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    }
    ## Last resort: whatever is on PATH, unless it's the WSL launcher.
    $onPath = Get-Command bash -ErrorAction SilentlyContinue
    if ($onPath -and $onPath.Source -notlike "$env:SystemRoot\*") { return $onPath.Source }
    return $null
}

## Single-quote a string for a bash command line.
function ConvertTo-BashLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return "'" + $Text.Replace("'", "'\''") + "'"
}

## Run a command line under Git Bash, from the repo root. Output goes straight to
## the console; the caller reads $LASTEXITCODE.
function Invoke-Bash {
    param([Parameter(Mandatory)][string]$Command)
    & $script:BashExe -c "cd $script:RootLiteral && $Command"
}

## Run one of the bash harnesses, with transcription suspended around it.
## PowerShell transcribes a child's output line by line, and measured against
## test.bash that costs about 3.5x (17.5 checks/minute becomes 5). The suites are
## long enough on Windows already, so bash tees into the same run log instead and
## nothing is lost. Relaying the output itself is free - only transcribing isn't.
function Invoke-BashHarness {
    param([Parameter(Mandatory)][string]$Script)

    $wasTranscribing = $script:Transcribing
    if ($wasTranscribing) {
        Stop-Transcript *> $null
        $script:Transcribing = $false
    }

    ## Two traps in one line. pipefail, or the pipe reports tee's exit status and
    ## every failing suite reads as a pass. And Out-Host, because a native command's
    ## stdout is this function's OUTPUT - without it the caller's `-ne 0` compares
    ## the whole suite transcript instead of the exit code, and a clean run reports
    ## as failed.
    Invoke-Bash "set -o pipefail; bash $(ConvertTo-BashLiteral $Script) 2>&1 | tee -a $(ConvertTo-BashLiteral $script:RunLogUnix)" | Out-Host
    $harnessExit = $LASTEXITCODE

    if ($wasTranscribing) {
        try {
            Start-Transcript -LiteralPath $script:RunLogPath -Append *> $null
            $script:Transcribing = $true
        } catch {
            fWarn "the run log stops here ($($_.Exception.Message))"
        }
    }
    return $harnessExit
}

## Expand the configured globs to repo-relative, forward-slashed paths. Mirrors
## the engine's nullglob loop: a glob matching nothing contributes nothing.
function Expand-GlobList {
    param([string[]]$Glob = @())
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $Glob) {
        $item = @(Get-ChildItem -Path (Join-Path $Root $pattern) -File -ErrorAction SilentlyContinue |
            Sort-Object -Property FullName)
        foreach ($file in $item) {
            $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            if (-not $found.Contains($relative)) { $found.Add($relative) }
        }
    }
    return $found.ToArray()
}

## A working python, as file + leading args. The Store stub in WindowsApps is on
## PATH and answers nothing, so every candidate has to prove itself by printing a
## version before it counts.
function Resolve-PythonCommand {
    foreach ($spec in @(@("python3"), @("python"), @("py", "-3"))) {
        $exe = Get-Command $spec[0] -ErrorAction SilentlyContinue
        if (-not $exe) { continue }
        $lead = @($spec | Select-Object -Skip 1)
        & $exe.Source @lead --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ File = $exe.Source; Lead = $lead }
        }
    }
    return $null
}

## markdownlint, however it happens to be installed. $null when it isn't.
function Resolve-MarkdownLintCommand {
    foreach ($name in @("markdownlint", "markdownlint.cmd")) {
        $exe = Get-Command $name -ErrorAction SilentlyContinue
        if ($exe) { return [pscustomobject]@{ File = $exe.Source; Lead = @() } }
    }
    $npx = Get-Command npx -ErrorAction SilentlyContinue
    if ($npx) {
        & $npx.Source --no-install markdownlint --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ File = $npx.Source; Lead = @("--no-install", "markdownlint") }
        }
    }
    return $null
}

## Stage 0. Refuses only on a real divergence; every other answer is ordinary.
function Invoke-SyncStage {
    git rev-parse --abbrev-ref '@{u}' *> $null
    if ($LASTEXITCODE -ne 0) {
        ## No upstream is an ordinary state for a brand-new branch, not a reason to stop.
        fNote "no upstream for this branch - nothing to sync"; return
    }
    git fetch --quiet *> $null
    if ($LASTEXITCODE -ne 0) {
        ## Offline is the other ordinary state. Warn and build what is here.
        fWarn "can't reach origin - building without refreshing"; return
    }
    ## Left is behind, right is ahead: what origin has that we don't, and the reverse.
    $counts = (git rev-list --left-right --count '@{u}...HEAD' 2>$null) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $counts.Count -lt 2) { fWarn "can't compare against origin - building as-is"; return }
    $behind = [int]$counts[0]; $ahead = [int]$counts[1]
    if     ($behind -eq 0) { fNote "up to date with origin (${ahead} to publish)" }
    elseif ($ahead -gt 0)  { fDie "diverged from origin: ${ahead} local, ${behind} remote. Reconcile before building." }
    else {
        ## Only behind, so this can only be a fast-forward. --autostash carries a dirty
        ## tree over it rather than refusing, and puts it back afterward.
        fNote "fast-forwarding ${behind} commit(s) from origin"
        git merge --ff-only --autostash '@{u}' | Out-Host
        if ($LASTEXITCODE -ne 0) { fDie "fast-forward from origin failed" }
    }
}

## Stage 1. shellcheck gates; the extras gate only when their tool is present.
function Invoke-LintStage {
    param([string[]]$ShellFile, [string[]]$ShellWarnFile)

    if (-not $ShellFile.Count) { fDie "no shell files matched the lint globs" }
    foreach ($file in $ShellFile) {
        & $script:BashExe -n ((Join-Path $Root $file).Replace('\', '/'))
        if ($LASTEXITCODE -ne 0) { fDie "syntax error: $file" }
    }
    fEcho "OK: bash -n ($($ShellFile.Count) file(s))"

    if (-not (Get-Command shellcheck -ErrorAction SilentlyContinue)) { fDie "shellcheck not installed" }
    & shellcheck @ShellFile
    if ($LASTEXITCODE -ne 0) { fDie "shellcheck findings" }
    fEcho "OK: shellcheck clean"

    ## Legacy files: report findings without gating.
    foreach ($file in $ShellWarnFile) {
        & $script:BashExe -n ((Join-Path $Root $file).Replace('\', '/'))
        if ($LASTEXITCODE -ne 0) { fDie "syntax error: $file" }
        $finding = @(& shellcheck --format=gcc $file 2>$null)
        if ($finding.Count) { fWarn "$($finding.Count) shellcheck finding(s) in legacy $file (report-only until the refactor)" }
        else                { fEcho "OK: legacy $file clean" }
    }

    $mdFile = @(Expand-GlobList -Glob $MdLintGlob)
    if ($mdFile.Count) {
        $md = Resolve-MarkdownLintCommand
        if ($md) {
            $lead = $md.Lead
            & $md.File @lead @mdFile
            if ($LASTEXITCODE -ne 0) { fDie "markdownlint findings" }
            fEcho "OK: markdownlint clean ($($mdFile.Count) file(s))"
        } else {
            fWarn "markdownlint skipped (not installed: npm install -g markdownlint-cli)"
        }
    }

    $pyFile = @($PyLintFile | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) })
    if ($pyFile.Count) {
        $py = Resolve-PythonCommand
        if ($py) {
            $lead = $py.Lead
            & $py.File @lead -m py_compile @pyFile
            if ($LASTEXITCODE -ne 0) { fDie "py_compile findings" }
            Remove-Item -LiteralPath (Join-Path $Root "cicd\utility\__pycache__") -Recurse -Force -ErrorAction SilentlyContinue
            fEcho "OK: py_compile ($($pyFile.Count) file(s))"
        } else {
            fWarn "py_compile skipped (no working python found)"
        }
    }

    ## PSScriptAnalyzer runs in-process here - we already are pwsh, so the extra
    ## interpreter the bash engine has to spawn buys nothing.
    $psFile = @(Expand-GlobList -Glob $PsLintGlob)
    if ($psFile.Count) {
        if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
            $total = 0
            foreach ($file in $psFile) {
                $finding = @(Invoke-ScriptAnalyzer -Path (Join-Path $Root $file) -Severity Error, Warning, Information)
                if ($finding.Count) {
                    $finding | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
                    $total += $finding.Count
                }
            }
            if ($total) { fDie "PSScriptAnalyzer findings ($total)" }
            fEcho "OK: PSScriptAnalyzer clean ($($psFile.Count) file(s))"
        } else {
            fWarn "PSScriptAnalyzer skipped (module not installed: Install-Module PSScriptAnalyzer)"
        }
    }
}

## Stage 4. Copy the script over its fixed name in the first dest that exists.
function Invoke-DogfoodStage {
    $did = $false

    if ($DogfoodBashDest.Count) {
        $dest = @($DogfoodBashDest | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) | Select-Object -First 1
        if ($dest) {
            Copy-Item -LiteralPath (Join-Path $Root $DogfoodBashSrc) -Destination (Join-Path $dest $ExeName) -Force
            fEcho "OK: installed (bash) -> $(Join-Path $dest $ExeName)"
            $did = $true
        } else {
            fWarn "no bash dogfood dest exists ($($DogfoodBashDest -join ', ')); skipping"
        }
    }

    if ($DogfoodPwshDest.Count) {
        $dest = @($DogfoodPwshDest | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) | Select-Object -First 1
        $leaf = Split-Path -Leaf $DogfoodPwshSrc
        if ($dest) {
            Copy-Item -LiteralPath (Join-Path $Root $DogfoodPwshSrc) -Destination (Join-Path $dest $leaf) -Force
            fEcho "OK: installed (pwsh) -> $(Join-Path $dest $leaf)"
            $did = $true
        } else {
            fWarn "no pwsh dogfood dest exists ($($DogfoodPwshDest -join ', ')); skipping"
        }
    }

    if (-not $did) { fNote "dogfood: nothing installed" }
}

## Stage 5. Render into a scratch file and compare. Never lands the result - see
## the header. Anything missing is a skip, and a failed render is a warning.
function Invoke-DemoGifStage {
    $scenario  = Join-Path $Root $DemoGifScenario
    $generator = Join-Path $Root $DemoGifScript
    $current   = Join-Path $Root $DemoGifOut
    if (-not (Test-Path -LiteralPath $scenario))  { fNote "no demo scenario ($DemoGifScenario)"; return }
    if (-not (Test-Path -LiteralPath $generator)) { fNote "no demo generator ($DemoGifScript)"; return }

    $py = Resolve-PythonCommand
    if (-not $py) { fWarn "demo gif skipped (no working python found)"; return }
    $lead = $py.Lead
    & $py.File @lead -c "import PIL" *> $null
    if ($LASTEXITCODE -ne 0) { fWarn "demo gif skipped (python has no Pillow: pip install pillow)"; return }
    Invoke-Bash "command -v fc-match >/dev/null 2>&1" *> $null
    if ($LASTEXITCODE -ne 0) {
        fWarn "demo gif skipped (the renderer picks its font through fc-match, which Windows has no equivalent of)"
        return
    }

    $scratch = Join-Path $Root "$LogDir/demo_$Stamp.gif"
    & $py.File @lead $DemoGifScript --scenario $DemoGifScenario --out $scratch --bin (Join-Path $Root $DogfoodBashSrc)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $scratch)) {
        Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
        fWarn "demo gif generation failed (continuing)"
        return
    }
    if ((Test-Path -LiteralPath $current) -and
        (Get-FileHash -LiteralPath $scratch -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash) {
        Remove-Item -LiteralPath $scratch -Force
        fEcho "OK: demo gif unchanged"
    } else {
        fWarn "demo gif differs from the committed copy - regenerate it on Linux (this render is at $scratch and was NOT landed)"
    }
}

## True when the working tree has tracked changes, staged or not.
function Test-GitDirty {
    & git diff --quiet
    if ($LASTEXITCODE -ne 0) { return $true }
    & git diff --cached --quiet
    return ($LASTEXITCODE -ne 0)
}

## True when the current branch has an upstream.
function Test-GitUpstream {
    & git rev-parse --abbrev-ref '@{u}' *> $null
    return ($LASTEXITCODE -eq 0)
}

## Run a git command, aborting the run if it fails.
function Invoke-Git {
    param([Parameter(Mandatory)][string]$What, [Parameter(Mandatory)][string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) { fDie "$What failed (exit $LASTEXITCODE): git $($GitArgs -join ' ')" }
}

## Stage 6. A native port of cicd/utility/n8git_backup-and-publish, minus the rar
## version archive: stash -> pull --ff-only -> pop -> add -> commit -> push. An
## empty $Msg means let git open its editor.
function Invoke-PublishStage {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Msg)

    $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
    fNote "branch: $branch"

    $didStash = $false
    if (Test-GitDirty) {
        fEcho_Clean "git stash push --include-untracked ..."
        $before = @(& git stash list).Count
        Invoke-Git "git stash" @("stash", "push", "--include-untracked", "-m", "auto-stash")
        $didStash = (@(& git stash list).Count -gt $before)
    }

    ## ff-only per the house rule: a divergent upstream stops here loudly instead
    ## of auto-merging behind the publish. A branch with no upstream has nothing
    ## to pull - the push below sets it on first publish.
    $hasUpstream = Test-GitUpstream
    if ($hasUpstream) {
        fEcho_Clean "git pull --ff-only ..."
        & git pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            ## The stash is still on the stack at this point, and a bare "pull
            ## failed" reads as though the tree was left as found. Say where the
            ## work went - stranding it silently is the one thing that turns a
            ## loud stop into a lost afternoon.
            if ($didStash) { fDie "git pull --ff-only failed; your changes are safe in 'git stash' (pop them once the branch is reconciled). Nothing was committed or pushed." }
            fDie "git pull --ff-only failed. Nothing was committed or pushed."
        }
    }

    ## A conflicted pop leaves markers in the tree and keeps the stash entry. Say
    ## what to do and stop, before anything gets staged, committed or pushed.
    if ($didStash) {
        fEcho_Clean "git stash pop ..."
        & git stash pop
        if ($LASTEXITCODE -ne 0) {
            fDie "stash pop conflicted after the pull. Resolve the conflicts, then 'git stash drop', and re-run. Nothing was committed or pushed."
        }
    }

    ## Never publish an unresolved merge: 'git add --all' would happily stage a
    ## conflict-marked file as resolved.
    if (@(& git ls-files --unmerged).Count) {
        fDie "unmerged paths present; refusing to stage or publish. Resolve them and re-run."
    }

    fEcho_Clean "git add --all ..."
    Invoke-Git "git add" @("add", "--all")

    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        fEcho_Clean "git commit ..."
        if ($Msg) {
            Invoke-Git "git commit" @("commit", "-m", $Msg)
            fEcho "OK: committed (`"$Msg`")"
        } else {
            & git commit
            if ($LASTEXITCODE -ne 0) { fDie "git commit failed or was aborted (empty message?)" }
            fEcho "OK: committed (via editor)"
        }
    } else {
        fNote "nothing to commit"
    }

    if (-not $hasUpstream) {
        fEcho_Clean "git push -u origin HEAD ..."
        Invoke-Git "git push" @("push", "-u", "origin", "HEAD")
        fEcho "OK: pushed $branch (upstream set)"
    } elseif (@(& git log '@{u}..' --oneline).Count) {
        fEcho_Clean "git push origin ..."
        Invoke-Git "git push" @("push", "origin")
        fEcho "OK: pushed $branch"
    } else {
        fNote "up to date with upstream; nothing to push"
    }
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Entry point

function Invoke-Main {
    Set-Location -LiteralPath $Root

    ## Git Bash carries the lint syntax check and both harnesses. Without it those
    ## stages can't run at all, so say so now rather than three stages in.
    $script:BashExe = Resolve-BashExe
    $script:RootLiteral = ConvertTo-BashLiteral ($Root.Replace('\', '/'))
    if (-not $script:BashExe -and ($DoLint -or $DoTest -or $DoFuzz)) {
        fDie "Git Bash not found (install Git for Windows), or rerun with -NoLint -NoTest -NoFuzz"
    }

    $shellFile     = @(Expand-GlobList -Glob $ShellLintGlob)
    $shellWarnFile = @(Expand-GlobList -Glob $ShellLintWarnGlob)
    $publishMsg    = $PublishMsg

    ## Preflight: the plan with resolved paths.
    $bashDest = @($DogfoodBashDest | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) | Select-Object -First 1
    $pwshDest = @($DogfoodPwshDest | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) | Select-Object -First 1
    $skipTag  = if ($Quick) { "(skipped -Quick)" } else { "(skipped)" }

    fEcho_Clean
    fEcho_Clean "$AppName Windows CI/CD"
    fEcho_Clean
    fEcho_Clean "Repo root ...........: $Root"
    fEcho_Clean "Git Bash ............: $(if ($script:BashExe) { $script:BashExe } else { '<not found>' })"
    if ($DoLint) {
        fEcho_Clean "Lint ................: shellcheck on $($shellFile.Count) shell file(s) + $($shellWarnFile.Count) legacy report-only  (+ markdownlint, py_compile, PSScriptAnalyzer if available)"
    } else {
        fEcho_Clean "Lint ................: (skipped)"
    }
    if     (-not $DoTest)                                             { fEcho_Clean "Tests ...............: (skipped)" }
    elseif (Test-Path -LiteralPath (Join-Path $Root $TestScript))     { fEcho_Clean "Tests ...............: $TestScript" }
    else                                                              { fEcho_Clean "Tests ...............: (no harness yet: $TestScript)" }
    if     (-not $DoFuzz)                                             { fEcho_Clean "Fuzz + security .....: $skipTag" }
    elseif (Test-Path -LiteralPath (Join-Path $Root $FuzzScript))     { fEcho_Clean "Fuzz + security .....: $FuzzScript" }
    else                                                              { fEcho_Clean "Fuzz + security .....: (no harness yet: $FuzzScript)" }
    if     (-not $DoDogfood)                                          { fEcho_Clean "Dogfood (bash) ......: (skipped)" }
    elseif ($bashDest)                                                { fEcho_Clean "Dogfood (bash) ......: overwrite $(Join-Path $bashDest $ExeName)" }
    else                                                              { fEcho_Clean "Dogfood (bash) ......: <none of: $($DogfoodBashDest -join ', ') exists - will skip>" }
    if     (-not $DoDogfood)                                          { fEcho_Clean "Dogfood (pwsh) ......: (skipped)" }
    elseif ($pwshDest)                                                { fEcho_Clean "Dogfood (pwsh) ......: overwrite $(Join-Path $pwshDest (Split-Path -Leaf $DogfoodPwshSrc))" }
    else                                                              { fEcho_Clean "Dogfood (pwsh) ......: <none of: $($DogfoodPwshDest -join ', ') exists - will skip>" }
    if     (-not $DoDemoGif)                                          { fEcho_Clean "Demo gif ............: $skipTag" }
    else                                                              { fEcho_Clean "Demo gif ............: compare only against $DemoGifOut (never regenerated on Windows)" }
    if     (-not $DoPublish)                                          { fEcho_Clean "Publish (last) ......: (disabled)" }
    elseif ($publishMsg)                                              { fEcho_Clean "Publish (last) ......: commit + push current branch (hands-off: `"$publishMsg`")" }
    else                                                              { fEcho_Clean "Publish (last) ......: commit + push current branch (will prompt for message; blank = editor)" }
    fEcho_Clean
    fEcho_Clean "Fail-fast: any error aborts before the next stage."
    fEcho_Clean

    ## Capture the commit message up front so the run finishes unattended. This is
    ## the natural place to bail on the common (publish) path - Ctrl+C aborts, and
    ## there is deliberately no separate "Proceed?" prompt.
    if (-not $Unattended -and $DoPublish -and -not $publishMsg) {
        $typed = Read-Host "Publish commit message (blank = editor; Ctrl+C aborts)"
        ## Read-Host bypasses the blank counter; reset it so the next section's
        ## leading blank isn't swallowed.
        $script:WasLastEchoBlank = $false
        if ($typed) { $publishMsg = $typed }
    }

    ## Transcribe the rest of the run so warnings from any stage can be reviewed
    ## after the fact. Rotate the prior (closed) logs first, through the same GFS
    ## helper cicd.bash uses.
    $logPath = Join-Path $Root $LogDir
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    if ($script:BashExe -and (Test-Path -LiteralPath (Join-Path $Root $GfsRotate))) {
        Invoke-Bash "source $(ConvertTo-BashLiteral $GfsRotate) && gfs_rotate $(ConvertTo-BashLiteral $LogDir) run log" *> $null
    }
    $script:RunLogPath = Join-Path $logPath "run_$Stamp.log"
    $script:RunLogUnix = "$LogDir/run_$Stamp.log"
    try {
        Start-Transcript -LiteralPath $script:RunLogPath | Out-Null
        $script:Transcribing = $true
    } catch {
        fWarn "no run log this time ($($_.Exception.Message))"
    }

    ## Stage 0: remote sync. The publish stage pulls too, but that is after everything
    ## has been built and tested - so a change merged upstream meanwhile would be pushed
    ## having been validated by nothing. Refreshing first means the rest of the run tests
    ## the tree that is actually going out. Publish keeps its own pull as the late guard.
    fSection "0/6  Remote sync"
    if (-not $DoSync) { fNote "remote sync skipped" }
    else { Invoke-SyncStage }

    ## Stage 1: lint. bash -n then shellcheck over every first-party shell file
    ## (gating - never an auto-formatter: bash is hand-formatted on purpose).
    fSection "1/6  Lint"
    if ($DoLint) { Invoke-LintStage -ShellFile $shellFile -ShellWarnFile $shellWarnFile }
    else         { fNote "lint skipped" }

    ## Stage 2: regression tests.
    fSection "2/6  Regression tests"
    if     (-not $DoTest)                                         { fNote "tests skipped" }
    elseif (Test-Path -LiteralPath (Join-Path $Root $TestScript)) {
        if ((Invoke-BashHarness -Script $TestScript) -ne 0) { fDie "regression tests" }
        fEcho "OK: tests passed"
        ## The behavioural suite runs the same checks once per build, so it passes on both while the
        ## two quietly disagree about the same input - which is what every port defect that reached
        ## users actually was. This asks the other question: do they ANSWER the same?
        if (Test-Path -LiteralPath (Join-Path $Root 'cicd/parity.bash')) {
            fEcho_Clean
            if ((Invoke-BashHarness -Script 'cicd/parity.bash') -ne 0) { fDie "builds disagree" }
            fEcho "OK: builds agree"
        }
    }
    else { fNote "no test harness ($TestScript)" }

    ## Stage 3: fuzz + security (adversarial input against our own parsing). Slow,
    ## so skipped under -Quick.
    fSection "3/6  Fuzz + security"
    if     (-not $DoFuzz)                                         { fNote "fuzz + security skipped$(if ($Quick) { ' (-Quick)' })" }
    elseif (Test-Path -LiteralPath (Join-Path $Root $FuzzScript)) {
        if ((Invoke-BashHarness -Script $FuzzScript) -ne 0) { fDie "fuzz + security" }
        fEcho "OK: fuzz + security passed"
    }
    else { fNote "no fuzz harness ($FuzzScript)" }

    ## Stage 4: dogfood.
    fSection "4/6  Dogfood"
    if ($DoDogfood) { Invoke-DogfoodStage }
    else            { fNote "dogfood skipped" }

    ## Stage 5: demo gif.
    fSection "5/6  Demo gif"
    if ($DoDemoGif) { Invoke-DemoGifStage }
    else            { fNote "demo gif skipped$(if ($Quick) { ' (-Quick)' })" }

    ## Stage 6: backup + publish.
    fSection "6/6  Backup + publish"
    if ($DoPublish) { Invoke-PublishStage -Msg $publishMsg }
    else            { fNote "publish disabled" }

    fSection "$AppName Windows CI/CD: done."
    fEcho_Clean
}

try {
    Invoke-Main
} finally {
    ## Guarded rather than try/catch'd: an unstarted transcript is the only
    ## reason Stop-Transcript would complain, and it is exactly what we track.
    if ($script:Transcribing) {
        $script:Transcribing = $false
        Stop-Transcript *> $null
    }
}


##	History:
##		- 2026-08-07 JC: Created. Windows-native port of cicd.bash - same six
##		  stages, native publish (no rar), demo gif compare-only.
