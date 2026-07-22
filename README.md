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
# x9git

An "extreme" Git wrapper to speed and simplify Git workflow.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Summary](#summary)
- [General attributes](#general-attributes)
- ["Opinionated workflow": What are the opinions?](#opinionated-workflow-what-are-the-opinions)
- [Installation](#installation)
	- [Bash](#bash)
	- [PowerShell](#powershell)
- [Git notes and one-liners](#git-notes-and-one-liners)
- [Contributing](#contributing)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Summary

One reason Git is so complex, is because it's so flexible. It's so flexible because it supports a wide variety of workflows, team sizes, and very narrow/hard edge-cases of conflict resolution.

`x9git` vastly simplifies Git, by:

- Applying an opinionated workflow, and ignoring the myriad other ways of doing the same thing.

- By acknowledging that (arguably) some ≈90% of Git's complexity is devoted to to covering about ≈10% of use-cases, and ignoring most of them. (Not pretending they never happen, just not trying to be the tool to solve them.)

x9git and git are 100% compatible and interchangeable.

- *In fact in large projects, you'll still need raw `git` to resolve some sticky situations that `x9git` purposely doesn't try to tackle (in order to keep-it-simple and "do one thing well").*

100% compatible with GitHub and GitLab.


Arguably, about 90% of Git's complexity is due to covering a fringe about 10% of use-cases. If you buy that argument, then axiomatically, if you lop off that 10% of fringe use-cases, then Git becomes 90% easier to work with. This goes further, lopping off (very approximately) half of the functionality, and is about 95% easier to work with.

## General attributes

- Encourages an opinionated workflow.

- It doesn't cover fringe use-cases, which Git itself can cover while still using this for the more common stuff.

- It's goal-oriented, rather than task-driven. (Which sounds like hand-wavy doublespeak, but is accurate. The subcommands themselves illustrate how.)

To be clear, x9git is just shell script. There's not much "logic", it's more about exposing a set of goal-oriented commands, sanity-checking arguments and underlying filesystem, and then chaining together the appropriate git commands to accomplish that goal.

x9git and regular git are fully compatible. x9git does nothing that git can't do directly (with many more commands and guards).

Sub-objectives in the workflow of each x9git command:

1. Make few assumptions about underlying state, and

1. Do things in a safe way (if occasionally redundant and/or unnecessary), that is tolerant of unexpected or inconsistent states.

1. Be idempotent.

## "Opinionated workflow": What are the opinions?

There are many implicit opinions baked in. Here are the main ones:

- `git pull --ff-only` is safer than and preferable to `git pull --rebase`.

- `git push` only to a feature branch you created.

- Don't `push` to `dev`, `main`, or `master`; instead, create a pull request. Even if you otherwise have the rights to, and even for small personal projects. While pull requests are overkill for small personal projects, it is nevertheless good hygiene, and fosters good working habits and experience.

## Installation

First, decide on the Bash or PowerShell version, mainly gating on *nix vs Windows.

- *But both at the same time is OK too. The PowerShell version will work on Linux too. Either way, the open-source PowerShell v7 or greater must be installed. (Not the old PowerShell v5 that comes preinstalled with Windows.)*

Then, decide to install for your user account only, or system-wide. (But to avoid future confusion, not both on the same machine.)

### Bash

- User-only install

	~~~bash

	~~~

- System-wide install

	~~~bash
	cd /tmp

	wget https://raw.githubusercontent.com/jim-collier/x9git/main/x9git

	sudo cp x9git /usr/local/sbin/

	sudo chmod +x x9git
	~~~

### PowerShell

- User-only install

	~~~pwsh

	~~~

- System-wide install

	~~~pwsh
	~~~

## Git notes and one-liners

The document in this repo, "[Git notes and one-liners](https://github.com/jim-collier/x9git/blob/main/git_notes_and_oneliners.md)" covers some simplified versions of what the `x9git` does.

## Contributing

Contributions are welcome. Start with [contributing.md](contributing.md) for process, and [style-guide.md](style-guide.md) for coding style.

## Copyright and license

> Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br />
> Licensed under the [MIT License](https://mit-license.org/). No warranty.
