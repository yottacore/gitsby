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

- 🔘 Work on dev branch. Push releases to main.

- 🔘 Create PRs rather than pushing directly (for this project).

- 🔘 Refactor the bash script:

	- 🔘 Use newer, easier-to-maintain Bash template/boilerplate/common functions. (E.g. from sister project silkterm.) But even those examples need to be cleaner (don't change anything outside of repo.)

	- 🔘 Modernize function and variable naming convention. Be descriptive with names, but not too long. Use of one-letter variables in small loop structures is OK.

	- 🔘 Remove dead code.

	- 🔘 Refactor to maximize usefulness of idiomatic Bash 5 features.

- 🔘 Make sure everything done with git:

	- Is done safely. E.g. before stashing, verify safely in a robust way that makes no assumptions, that there is anything to pull. `n8git_backup-and-publish` has examples.

	- Never make assumptions about the local and/or repo state. Verify first for every command, whatever is relevant for the command.

	- Everything must be idempotent.

- 🔘 Integrate these rules and ideals: https://github.com/x9-testlab/x9git/blob/main/reference/git.txt, including:
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

- 🔘 Get original commands and options working. At some point some just kind of broke (pre-git), and were never fixed.

- 🔘 Create a release-install script per platform (`bash` and \[`pwsh` or `cmd`\]), runnable via a single `curl`/`wget` (etc.) and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort. Update README.md with one-liner for both local and system-level installs.

	- 🔘 Do the same thing for a dev-branch install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort. Update README.md with one-liner for both local and system-level installs.

### Misc to-do

### Bugs

### Features and enhancements

### Done

#### Done - Initial requirements

#### Done - Bugs

#### Done - Features and enhancements

### Future and/or deferred

### Canceled
