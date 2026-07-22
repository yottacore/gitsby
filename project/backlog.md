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

- ✅ Work on dev branch. Push releases to main.

	- ✅ `dev` branch created from `main` and pushed; feature branches now merge to `dev`, `main` is release-only.

- ✅ Create PRs rather than pushing directly (for this project).
	- Feature branches now go up as PRs to `dev` and land via merge commit; direct local merges retired.

- ✅ Delete stale branch from 2020.
	- `20201003-074416_jc_rewrite-in-golang` (abandoned golang rewrite) deleted from origin.

- 🛠️ CICD process (full spec in private notes):

	- ✅ `cicd.bash`: `-q|--quiet`, `-m|--msg|--message`, prompt for commit message when neither given (CTRL+C aborts); silkterm output style; `fEcho`/`fParseArgs` conventions.

	- ✅ Linting stage: shellcheck (+ markdownlint), no auto-format for Bash; output GFS-rotated to `cicd/artifacts/lint/`; zero-error goal.
		- Everything gates clean now, including `bin/gitsby` (the refactor cleared its ~80 legacy findings; report-only list emptied).

	- ✅ Regression tests; keep updated as features/bugs land.
		- `cicd/test.bash` landed with the refactor: 39 checks against throwaway repos (bare origin + two clones); covers every command plus failure guards.

	- 🛠️ Adversarial fuzz/security testing (our input surface + what we depend on).
		- Stage wired (`cicd/fuzz.bash`); same timing as the test harness.

	- ✅ Dogfood install stage: copy to first existing preferred dir (bash + pwsh lists).
		- pwsh leg dormant until a port exists.

	- 🛠️ Automated demo GIF (fake terminal, 640x360@50fps, `--quick` skips); copy `gen-demo-gif.py` from convert-base-v2; embed `assets/demo.gif` in README.
		- Generator + stage wired; scenario + README embed after the refactor, so it demos working commands.

- ✅ Refactor the bash script:
	- Rewritten 2142 -> ~620 lines on the current template generation (same one as `n8git_backup-and-publish`): strict mode, trap suite, arg parser, minified header trio.

	- ✅ Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- ✅ Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- ✅ Remove dead code.
		- Dropped the unused ~1400-line generic library (ping, symlink, editor pickers, sudo plumbing, glob-permutation engine, platform detection).

	- ✅ Refactor to maximize usefulness of idiomatic Bash 5 features.
		- Argument arrays instead of eval (which also retired the curly-quote message mangling), `[[ -v ]]`, parameter transforms, arithmetic conditionals.

- ✅ Make sure everything done with git:
	- Every command verifies state first and is idempotent: stash only if dirty (pop only what was pushed), pull only with an upstream, push only if ahead, commit only if changes; main/master detected from origin HEAD, not hardcoded. All covered by the regression tests.

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- ✅ Integrate these rules and ideals: `reference/git.txt` (in this repo), including:
	- Push hygiene (stash / pull --ff-only / stash apply / add / commit / push) is now the core of spull/scompul/spush; branch workflow lives in mkbranch/chbranch/mtm.
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

- ✅ Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.
	- All nine commands work and are regression-tested; scommit/scompul/spush/mtm take -m or a positional message, mkbranch/chbranch validate their branch argument.

- 🔘 Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.

	- 🔘 Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.

- 🔘 PowerShell port of gitsby (style guide already covers pwsh; dogfood pwsh leg activates when it lands).

### Done

#### Done - Initial requirements

#### Done - Bugs

#### Done - Features and enhancements

### Future and/or deferred

### Canceled
