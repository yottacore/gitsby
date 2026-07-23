<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

[![!#/bin/bash](https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Support](https://img.shields.io/badge/Support-Maintained-brightgreen)
![Status: Passing](https://img.shields.io/badge/Status-Passing-brightgreen)

</div>
<!--
[![!#/bin/bash](https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![made-with-python](https://img.shields.io/badge/Made%20with-Python-1f425f.svg)](https://www.python.org/)
[![made-with-rust](https://img.shields.io/badge/Made%20with-Rust-1f425f.svg)](https://www.rust-lang.org/)
![Go](https://img.shields.io/badge/Go-00ADD8?logo=go&logoColor=white)
![Made with](https://img.shields.io/badge/Made%20with-C%2B%2B-brightgreen?style=plastic)
![Made with](https://img.shields.io/badge/Made%20with-Unreal%20Engine-critical?style=plastic)
[![made-with-javascript](https://img.shields.io/badge/Made%20with-JavaScript-1f425f.svg)](https://www.javascript.com)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)
[![License: GPL v2+](https://img.shields.io/badge/License-GPLv2%2B-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)
![Lifecycle: Alpha](https://img.shields.io/badge/Lifecycle-Alpha-orange)
![Lifecycle: Beta](https://img.shields.io/badge/Lifecycle-Beta-yellow)
![Lifecycle: RC](https://img.shields.io/badge/Lifecycle-RC-blue)
![Lifecycle: Stable](https://img.shields.io/badge/Lifecycle-Stable-brightgreen)
![Lifecycle: Deprecated](https://img.shields.io/badge/Lifecycle-Deprecated-red)
![Status: Deprecated](https://img.shields.io/badge/Status-Deprecated-orange)
![Status: Archived](https://img.shields.io/badge/Status-Archived-lightgrey)
![Lifecycle: EOL](https://img.shields.io/badge/Lifecycle-EOL-lightgrey)
![Coverage](https://img.shields.io/badge/Coverage-25%25-red)
![Coverage](https://img.shields.io/badge/Coverage-50%25-orange)
![Coverage](https://img.shields.io/badge/Coverage-75%25-yellow)
![Coverage](https://img.shields.io/badge/Coverage-90%25-brightgreen)
![Status: Passing](https://img.shields.io/badge/Status-Passing-brightgreen)
![Status: Failing](https://img.shields.io/badge/Status-Failing-red)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/jim-collier?logo=GitHub%20Sponsors&style=social)](https://github.com/sponsors/jim-collier)
-->

<!-- TOC ignore:true -->
# The Great Gitsby

An opinionated Git wrapper to speed and simplify Git workflow.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Summary](#summary)
- [General attributes](#general-attributes)
- ["Opinionated workflow": What are the opinions?](#opinionated-workflow-what-are-the-opinions)
- [Installation](#installation)
	- [Bash](#bash)
	- [PowerShell](#powershell)
- [How to develop](#how-to-develop)
- [Git notes and one-liners](#git-notes-and-one-liners)
- [Contributing](#contributing)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Summary

If you're reading this, you probably know how to use Git. You probably also understand that it's complex, mostly because it's so flexible.

Git is so flexible because it supports a wide variety of workflows, team sizes, and very narrow/hard edge-cases of conflict resolution.

Gitsby vastly simplifies Git, by:

- Applying an "opinionated" workflow, and ignoring the myriad other ways of doing the same thing.

- By acknowledging that (arguably) some ≈90% of Git's complexity is devoted to to covering about ≈10% of edge use-cases, and purposely ignoring most of them. (That is to say, not pretending they never happen - just not trying to be the tool to solve them if and when they arise.)

Gitsby and Git are 100% compatible and interchangeable.

- *In fact in large projects, you'll still need raw `git` to resolve some sticky situations that `gitsby` purposely doesn't try to tackle (in order to keep-it-simple and "do one thing well").*

100% compatible with GitHub and GitLab.

## General attributes

- Encourages an opinionated workflow. (More on what that means below, because it has besome an overloaded word.)

- It doesn't cover fringe use-cases, which Git itself can cover while still using this for the more common stuff.

- It's goal-oriented, rather than task-driven. (Which sounds like hand-wavy doublespeak, but is accurate. The subcommands themselves illustrate how.)

To be clear, gitsby is just shell script. (Two scripts actually, with the same syntax and results.) There's not much "logic", it's more about exposing a set of goal-oriented commands, sanity-checking arguments and underlying filesystem, and then chaining together the appropriate git commands to accomplish that goal.

Gitsby does nothing that git can't do directly, with many more commands and guards.

Sub-objectives in the workflow of each gitsby command:

1. Don't make assumptions - about the underlying repo state.

1. Be safe - if occasionally redundant and/or unnecessary. Never risk losing work - yours locally, or others in the remote.

1. Be idempotent.

1. Be tolerant - of previous commands having been only half-finished, and other potential weirdness.

1. Be forgiving - any sub-command can be run at any time, and if it doesn't make sense, it won't screw anything up.

## "Opinionated workflow": What are the opinions?

The "opinions" are mostly informed by industry and conventional best-practices, learned over millions upon millions of programmer-hours. There is no reinvention of any wheels - it's just an exposed interface that places gentle guardrails and sanity checks around a way of working with Git that has proven to more easily scale and minimize trouble.

There are many implicit opinions baked in. Here are the main ones:

- `git pull --ff-only` is safer than and preferable to `git pull --rebase`.

- Merges are always `--no-ff`, so the fact that a branch existed stays visible in history.

- `git push` only to a feature branch you created.

- Don't `push` to `dev`, `main`, or `master`; instead, create a Pull Request. Even if you otherwise have the rights to, and even for small personal projects.

	While PRs are overkill for small personal projects, it is nevertheless good hygiene, does not add much extra effort, and reinforces good working habits.

- Pushed history is permanent. No rebase, no amend, no force-push, no rewriting.

- Feature branches are short-lived: branch off, do the work, land it, delete it (local and remote).

- If the repo has a `dev` branch, feature branches come off of - and land back on - `dev`. `main` is then release-only: a `dev` -> `main` merge is a release cut, with a tag.

- Commit the whole working tree (`git add --all`), every time. The staging area is not a workspace; partial staging is one of those fringe cases left to raw `git`.

- Commit and pull frequently (`saveup`); push less often (`sync`).

- Uncommitted work should never block anything. A pull auto-stashes around itself (untracked files included), and a branch switch parks current work first - commit, pull, push - so nothing is ever stranded or lost.

- Every branch tracks a same-named branch on `origin`, from the moment it's created.

- One remote, and it's named `origin`. (Multi-remote setups are another fringe case left to raw `git`.)

- Releases are annotated semver tags (`vX.Y.Z`). If no version is given, bump the patch.

- Look before you leap: fetch first, show the current state and the exact commands about to run, and ask before doing anything that mutates.

## Installation

First, decide on the Bash or PowerShell version, mainly gating on *nix vs Windows.

- *But both at the same time is OK too. The PowerShell version will work on Linux too. Either way, the open-source PowerShell v7 or greater must be installed. (Not the old PowerShell v5 that comes preinstalled with Windows.)*

Then, decide to install for your user account only, or system-wide. (But to avoid future confusion, not both on the same machine.)

Either way, the installer shows exactly what it will do and asks before doing it (add `-y`/`-Yes` to skip the prompt, e.g. for scripted installs).

### Bash

- User-only install (to `~/.local/bin`)

	~~~bash
	curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install.bash | bash
	~~~

- System-wide install (to `/usr/local/bin`, uses `sudo`)

	~~~bash
	curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install.bash | bash -s -- --system
	~~~

- No `curl`? Swap in `wget -qO-` for `curl -fsSL`. To install from a branch instead of the latest release, append `--ref dev` (or `--ref main`).

### PowerShell

*The PowerShell port is new and not in a release yet. Until one is cut, install it from the dev branch by adding `-Ref dev` to the scriptblock form below.*

- User-only install

	~~~pwsh
	irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
	~~~

- System-wide install (run from an elevated / sudo PowerShell)

	~~~pwsh
	& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System
	~~~

## How to develop

One-liner dev setup: clones the repo into `./gitsby`, checks out the `dev` branch, and checks (optionally installs) the dev tooling. Details in [contributing.md](contributing.md).

- Linux / macOS

	~~~bash
	curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.bash | bash
	~~~

- Windows (PowerShell 7+)

	~~~pwsh
	irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1 | iex
	~~~

## Git notes and one-liners

The document in this repo, "[Git notes and one-liners](https://github.com/jim-collier/gitsby/blob/main/git_notes_and_oneliners.md)" covers some simplified versions of what Gitsby does. They differ slightly in some areas (mostly due to being limited to one-liners), but Gitsby is the cononical source of truth.

## Contributing

Contributions are welcome. Start with [contributing.md](contributing.md) for process, and [style-guide.md](style-guide.md) for coding style.

## Copyright and license

> Copyright © 2014-2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br />
> Licensed under the [MIT License](https://mit-license.org/). No warranty.
