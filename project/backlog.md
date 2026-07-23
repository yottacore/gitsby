<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Requirements

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Misc to-do](#misc-to-do)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Initial requirements](#done---initial-requirements)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Backlog

### Misc to-do

### Bugs

### Features and enhancements

- 🛠️ CICD process (full spec in private notes):

	- ✅ `cicd.bash`: `-q|--quiet`, `-m|--msg|--message`, prompt for commit message when neither given (CTRL+C aborts); silkterm output style; `fEcho`/`fParseArgs` conventions.

	- ✅ Linting stage: shellcheck (+ markdownlint), no auto-format for Bash; output GFS-rotated to `cicd/artifacts/lint/`; zero-error goal.
		- Everything gates clean now, including `bin/gitsby` (the refactor cleared its ~80 legacy findings; report-only list emptied). PSScriptAnalyzer gates the three `.ps1` files.

	- ✅ Dogfood install stage: copy to first existing preferred dir (bash + pwsh lists).
		- Both legs live since the pwsh port landed.

	- ✅ Regression tests; keep updated as features/bugs land.
		- `cicd/test.bash`: throwaway repos (bare origin + two clones), every command plus failure guards, run once per implementation - 140 checks.

	- 🛠️ Adversarial fuzz/security testing (our input surface + what we depend on).
		- Stage wired (`cicd/fuzz.bash`); same timing as the test harness.

	- 🛠️ Automated demo GIF (fake terminal, 640x360@50fps, `--quick` skips); copy `gen-demo-gif.py` from convert-base-v2; embed `assets/demo.gif` in README.
		- Generator + stage wired; scenario + README embed after the refactor, so it demos working commands.

- 🔘 Add a PowerShell badge to README.md.

- 🛠️ A Bash >=3.2 script, and/or cross-platform PowerShell v7 script, that users can run as a one-liner from their shell - to download the latest stable or dev release, verify checksum, and install the executable. Idempotent; states its plan and asks before touching anything. Uses nice output, blank line at the start and end of script, and one blank line between major sections of output. Add something like this to README.md, under an "Installation" header, "Direct" subheader. (The primary install should be an installer.) Include the commands, and the install locations.

	- Mostly covered by the shipped installers (see the release-install item under Done). Still open: checksum verification of the download, and a README "Installation" -> "Direct" subsection listing the commands next to the install locations below.

	- `--arch` doesn't apply - gitsby is a script, not a compiled binary. `--release dev|stable` is spelled `--ref`, and `--target user|system` is spelled `--system` (default user).

	- Bash installer (Linux, BSD, macOS, WSL)

		~~~bash
		bash <(curl -fsSL https://raw.githubusercontent.com/USER/PROJECT/main/install.bash)  [--release dev|stable]  [--target user|system]  [--arch x64|amd64|arm64]
		~~~

	- PowerShell installer (Windows, Linux, macOS)

		~~~powershell
		& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/USER/PROJECT/main/install.ps1')))  [-Release dev|stable]  [-Target user|system]  [-Arch x64|amd64|arm64]
		~~~

	- Installation locations for CLI programs (in this example, a program that has multiple files and a symlinked executable):

		| OS      | System multi-file path  | ￩ Single exe or symlink        | (or) User install path              | ￩ Single exe or symlink
		| :---    | :---                    | :---                           | :---                                | :---
		| Linux   | /opt/PROG/              | /usr/local/bin/PROG            | ~/.local/share/PROG/                | ~/.local/bin/PROG
		| BSD     | /usr/local/PROG/        | /usr/local/bin/PROG            | ~/.local/share/PROG/                | ~/.local/bin/PROG
		| Windows | C:\Program Files\PROG\  | *Add install dir to `%PATH%`*  | %LOCALAPPDATA%\Programs\PROG\       | *Add install dir to `%PATH%`*
		| macOS   | /opt/PROG/              | /usr/local/bin/PROG            | ~/Library/Application Support/PROG/ | ~/.local/bin/PROG

	- Installation locations for GUI packages (in this example, a program that has multiple files and a symlinked executable):

		| OS      | System multi-file path  | ￩ Launcher                                                    | (or) User install path        | ￩ Launcher
		| :---    | :---                    | :---                                                          | :---                          | :---
		| Linux   | /opt/PROG/              | /usr/local/share/applications/PROG.desktop                    | ~/.local/share/PROG/          | ~/.local/share/applications/PROG.desktop
		| BSD     | /usr/local/PROG/        | /usr/local/share/applications/PROG.desktop                    | ~/.local/share/PROG/          | ~/.local/share/applications/PROG.desktop
		| Windows | C:\Program Files\PROG\  | %ProgramData%\Microsoft\Windows\Start Menu\Programs\PROG.lnk  | %LOCALAPPDATA%\Programs\PROG\ | %APPDATA%\Microsoft\Windows\Start Menu\Programs\PROG.lnk
		| macOS   | /Applications/PROG.app/ | *The .app bundle is the launcher*                             | ~/Applications/PROG.app/      | *.app bundle*

### Done

#### Done - Initial requirements

#### Done - Bugs

#### Done - Features and enhancements

- ✅ Rename `saveup` to `update`.
	- Done in both implementations; `saveup` stays as a hidden alias like the other old names. Docs and changelog swept.

- ✅ Script output starts and ends with a blank line (breathing room between prompt text).
	- Trailing blanks already existed on every exit path; added the leading one (both implementations). Error paths were already blank-wrapped.

- ✅ After `release` merges dev to main, bring dev up to include the release merge and tag.
	- Done via `git merge --ff-only main` on dev (then push), not `git branch -f dev main`: same result normally, but if dev gained commits mid-release it skips with a warning instead of discarding work. Previews updated; tests cover it.

- ✅ 'git_notes_and_oneliners.md': Move the current commands under a "Bash" section, and add a "PowerShell" section below it, with pwsh v7 parity versions of the same one-liners.
	- Two mirrored sections, same task headings in the same order, so the two are easy to compare side by side.
	- The PowerShell section opens with the three gotchas that bite when translating from Bash: `&&`/`||` need pwsh 7, `@{u}` has to be quoted, and staged-change tests read `$LASTEXITCODE`.
	- Every pwsh one-liner was run against throwaway repos, not just eyeballed. Two spots deviate on purpose: no `less` (git pages its own diff), and `Remove-Item` deletes outright since there is no cross-platform `trash`.
	- Also swapped the stale sister-tool reference in the Bash "push local changes" one-liner for `gitsby saveup`.

- ✅ All potentially destructive or conflict-producing commands - or anything that will reveal a user identity on the remote - should:
	- Show what's going to change (including a list of changed files, piped through an internal equivalent of `... | less -FX` if necessary)
	- git status without line-breaks, and SSH connection info. And a prompt to continue. All with standard 1 blank line where appropriate.
	- Every mutating command already previewed its plan and prompted; this added the identity and change detail. `status` shows the same block.
	- SSH line resolves the remote URL through `ssh -G`, so a `~/.ssh/config` host alias shows the real host, user, and key it will use - the point being to catch acting as the wrong account before you push. Author line shows what git will actually stamp on the commit.
	- Changes list one file per line (short form), truncated to the terminal width and capped at 25 with an "and N more" tail - the `less -FX` idea without depending on a pager. Incoming section lists what a pull would change, and the branch line carries ahead/behind.

- ✅ Better command names; dev-aware merging; PR and release commands (both implementations).
	- Renames: scompul->saveup, spush->sync, scommit->commit, spull->pull, mkbranch->newbr, chbranch->gobr, list->listbr, mtm->land. Old names still work as hidden aliases.
	- newbr/gobr/land now branch off / land on dev when the repo has one, else main/master. land refuses to run from the default branch.
	- New: pr (bare = list, n = view + diff, ok n = approve + merge, via gh), release (merge dev into main --no-ff, tag, push; no version = patch bump on the latest v* tag).

- ✅ PowerShell port of gitsby (style guide already covers pwsh; dogfood pwsh leg activates when it lands).
	- `bin/gitsby.ps1`: same commands, checks, and flow as the bash version. Regression suite now runs once per implementation (78 checks total); PSScriptAnalyzer joined the lint stage (gates all three .ps1 files); dogfood pwsh leg live. Not in a release yet - README says to use `-Ref dev` until one is cut.

- ✅ Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.
	- `install.bash` + `install.ps1` at repo root; plan-then-confirm, `--system`/`-y`/`--ref`; README Installation one-liners filled in (user + system, curl and wget). Resolves the latest release tag, prefers a release asset, falls back to the tagged tree. The 2022-era releases predate the `bin/` layout so the release path activates for real once a v2 release is cut (`--ref main`/`--ref dev` works today); the pwsh installer says the port hasn't shipped and points at the bash one until then.

	- ✅ Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.
		- `install-dev.bash` + `install-dev.ps1`: clone, check out `dev`, check tooling (offers package-manager install where one is found), verify, print next steps. Documented in README "How to develop" + contributing.md "Your First Code Contribution". Bash installers run on macOS stock bash 3.2.

- ✅ Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.
	- All commands work and are regression-tested; the commit/save/sync/land family takes -m or a positional message, newbr/gobr validate their branch argument.

- ✅ Integrate these rules and ideals: `reference/git.txt` (in this repo), including:
	- Push hygiene (stash / pull --ff-only / stash apply / add / commit / push) is now the core of pull/saveup/sync; branch workflow lives in newbr/gobr/land.
	- Work on feature branches
	- PRs to merge to develop
	- Commit frequently
	- Pull frequently, push infrequently
	- Push hygene:

		~~~bash
		git stash
		git pull --ff-only
		git stash apply
		git add .
		git commit -m ""
		git push
		~~~

- ✅ Make sure everything done with git:
	- Every command verifies state first and is idempotent: stash only if dirty (pop only what was pushed), pull only with an upstream, push only if ahead, commit only if changes; main/master detected from origin HEAD, not hardcoded. All covered by the regression tests.

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- ✅ Refactor the bash script:
	- Rewritten 2142 -> ~620 lines on the current template generation (same one as `n8git_backup-and-publish`): strict mode, trap suite, arg parser, minified header trio.

	- ✅ Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- ✅ Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- ✅ Remove dead code.
		- Dropped the unused ~1400-line generic library (ping, symlink, editor pickers, sudo plumbing, glob-permutation engine, platform detection).

	- ✅ Refactor to maximize usefulness of idiomatic Bash 5 features.
		- Argument arrays instead of eval (which also retired the curly-quote message mangling), `[[ -v ]]`, parameter transforms, arithmetic conditionals.

- ✅ Work on dev branch. Push releases to main.

	- ✅ `dev` branch created from `main` and pushed; feature branches now merge to `dev`, `main` is release-only.

- ✅ Create PRs rather than pushing directly (for this project).
	- Feature branches now go up as PRs to `dev` and land via merge commit; direct local merges retired.

- ✅ Delete stale branch from 2020.
	- `20201003-074416_jc_rewrite-in-golang` (abandoned golang rewrite) deleted from origin.

### Future and/or deferred

### Canceled
