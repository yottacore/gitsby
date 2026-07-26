<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

[![!#/bin/bash](https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE.svg?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Latest release](https://img.shields.io/github/v/release/jim-collier/gitsby?include_prereleases&label=release)](https://github.com/jim-collier/gitsby/releases/latest)
![Lifecycle: Stable](https://img.shields.io/badge/Lifecycle-Stable-brightgreen)
![Support](https://img.shields.io/badge/Support-Maintained-brightgreen)
![Status: Passing](https://img.shields.io/badge/Status-Passing-brightgreen)

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

</div>

<table style="border: none; border-collapse: collapse;">
	<tr style="border: none; border-collapse: collapse;">
		<td style="border: none; border-collapse: collapse;"><img src="assets/logo.png" alt="Logo" width="128"/></td>
		<td style="border: none;">A simple, safe, and opinionated Git wrapper to speed up everyday Git workflow. Unlimited safe project scaling.<br /><br />It's so simple and safe, because it does quite a bit of heavy-lifting for you.</td>
	</tr>
</table>

<img src="assets/demo.gif" alt="Demo."/>

<!--
	Demo video: https://www.youtube.com/watch?v=REPLACE_WITH_VIDEO_ID
	<img src="assets/demo.gif" width="90%" alt="Demo."/>
-->

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Summary](#summary)
- [General attributes](#general-attributes)
- ["Opinionated workflow": What are the opinions?](#opinionated-workflow-what-are-the-opinions)
- [Why](#why)
- [Commands](#commands)
- [Installation](#installation)
	- [Bash](#bash)
	- [PowerShell](#powershell)
	- [Direct](#direct)
- [How to develop](#how-to-develop)
- [Git notes and one-liners](#git-notes-and-one-liners)
- [Contributing](#contributing)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Summary

If you're reading this, you probably know how to use Git.

You probably also understand that it's complex, mostly because it's so flexible. It's so flexible because it supports a wide variety of workflows, team sizes, and the necessary subcommands to do anything/everything - including very narrow/hard edge-cases of conflict resolution.

Git has about 82 porcelain commands.

Gitsby has 13.

> *Granted, this comparison doesn't hit super hard, when only about 1/5th of git users interact with bare `git` on a daily basis - as it's integrated into IDEs, CI/CD pipelines, AI coding agents, etc.*

Gitsby shrinks Git's command set by:

- Applying an "opinionated" workflow, and ignoring the myriad other ways of doing the same thing.

- By acknowledging that (arguably) some 90% of Git's complexity is devoted to covering about 10% of edge use-cases, and purposely ignoring most of them. (That is to say, not pretending they never happen - just not trying to be the tool to solve them if and when they arise.)

- Commands are oriented around *goals* (e.g. "what do I want to happen with these changes?"), rather than a series of *administrative tasks*.

	- It's a subtle but important distinction.

	- And it means that Gitsby commands don't map 1:1 with Git commands - but do line up with many common real-world "best practice" use cases of Git (as series of multiple commands at a time with brief human decisions made in between them).

👉 Gitsby, [Git](https://git-scm.com/), [gh](https://github.com/cli/cli), [Lazygit](https://github.com/jesseduffield/lazygit), and [Tig](https://github.com/jonas/tig) are all compatible, interchangeable, and can be intermixed on the same project at any time without interference.

- *In fact in large projects, you may still need to use bare Git (and/or some other wrapper) to resolve some sticky situations that Gitsby purposely doesn't try to tackle, in order to keep-it-simple and "do one thing well".*

👉 Gitsby is 100% compatible with GitHub and GitLab.

> Note: [GitButler](https://gitbutler.com/) is *not* fully interchangeable with Git, Gitsby, gh, LazyGit, and/or Tig. While a great tool and a cool idea, it manages its own metadata - that inherently doesn't mix well with other git-based tools that moves `HEAD` or rewrites history.

## General attributes

- Encourages and partially enforces an "opinionated" workflow. (More on what that means below, because it has become an overloaded word.)

- It doesn't cover fringe use-cases, which Git itself can cover while still using this for the more common stuff.

- It's goal-oriented, rather than task-driven. (The subcommands themselves illustrate what this means.)

To be clear, gitsby is just shell script. (Two scripts actually, with the same syntax and results.) It exposes a set of goal-oriented commands, then sanity-checking arguments and underlying filesystem, and chains the appropriate git commands together to accomplish that goal.

Gitsby does nothing that Git can't do directly by a skilled and experienced user - just with far fewer opportunities for common human mistakes.

Sub-objectives in the workflow of each gitsby command:

1. Don't make assumptions about the underlying repo state.

1. Be safe - if occasionally redundant and/or unnecessary. Never risk losing work - yours locally, or others in the remote.

1. Be idempotent.

1. Be tolerant - of previous commands having been only half-finished, and other potential weirdness.

1. Be forgiving - any sub-command can be run at any time, and if it doesn't make sense, it won't screw anything up.

## "Opinionated workflow": What are the opinions?

The "opinions" are mostly informed by industry and conventional best-practices, learned over millions upon millions of collective human programmer-hours. There is no reinvention of any wheels - it's just an exposed interface that places gentle guardrails and sanity checks around a way of working with Git that has proven to more easily scale and minimize trouble.

There are many implicit opinions baked in. Here are the main ones:

- `git pull --ff-only` is safer than and preferable to `git pull --rebase`.

- Merges are always `--no-ff`, so the fact that a branch existed stays visible in history.

- `git push` only to a feature branch you created.

- Don't `push` to `dev`, `main`, or `master`; instead, create a Pull Request. Even if you otherwise have the rights to, and even for small personal "toy" projects.

	While PRs are overkill for small personal projects, it is nevertheless good hygiene, does not add much extra effort, and reinforces good working habits at a reflexive level.

- Pushed history is permanent. No rebase, no amend, no force-push, no rewriting.

- Feature branches are short-lived: branch off, do the work, land it, delete it (local and remote).

- If the repo has a `dev` branch, feature branches come off of - and land back on - `dev`. `main` is then release-only: a `dev` -> `main` merge is a release cut, with a tag.

- Commit the whole working tree (`git add --all`), every time. The staging area is not a workspace; partial staging is one of those fringe cases left to raw `git`.

- Commit and pull frequently (`update`); push less often (`sync`).

- Uncommitted work should never block anything. A pull auto-stashes around itself, `br create` carries uncommitted work onto the new branch, and a branch switch parks current work first (commit, pull, push - though never auto-committed onto `main`/`dev`), so nothing is ever stranded or lost.

- Every branch tracks a same-named branch on `origin`, from the moment it's created.

- One remote, and it's named `origin`. (Multi-remote setups are another fringe case left to raw `git`.)

- Releases are annotated semver tags (`vX.Y.Z`). If no version is given, bump the patch.

- Look before you leap: fetch first, show the current state and the exact commands about to run, and ask before doing anything that mutates.

## Why

Many years ago, I grew tired of my development team of expert git users (and myself) making repeated, costly mistakes with the tool. Not from incompetence, malice, recklessness, or carelessness - but because git is so powerful that the exact order of operations for tough edge-cases can be both hard to remember, and not inherently obvious.

Many of those tough edge-cases arose in the first place, precisely because our git workflow wasn't enforced at an automation level.

(I'm sure this is all sounding too familiar for veteran developers.)

I surveyed the git tools and wrappers available at the time and concluded they were also "too flexible" - none enforced an opinionated (enough) workflow based on well-established industry best practices.

So I wrote x9git, the v1 forerunner of gitsby.

For years, it worked and was extremely useful. But it wasn't comprehensive enough - bare git was still needed on a regular basis. Also, the version that worked well, while open-sourced and committed to a company repo, never made it into this "permanent home" repo when I created it a couple of years later. That first commit had some broken features I punted on and commented out.

Now, years later, this v2 release - renamed gitsby - finally fulfills the original vision: with a small but comprehensive end-to-end set of bulletproof commands.

## Commands

What you reach for daily is one word. Everything else is grouped under a noun, so the whole set is discoverable from three starting points. `repository` and `branch` spell out if you prefer them.

| Command              | Args          | What it does
| :--                  | :--           | :--
| `update`             | `[msg]`       | Pull updates, then commit all local changes. Do frequently!
| `sync`               | `[msg]`       | Pull, commit, and push. Do infrequently.
| `status`             |               | Fetch and show current status.
| `release`            | `[ver]`       | Cut a release: merge `dev` into `main`, tag, push. No version: bump the patch.
| `br`                 |               | Fetch and list branches (`br list` is the same thing).
| `br create`          | `<branch>`    | Create a new branch off `dev`/`main` (carries current uncommitted work to it).
| `br switch`          | `[branch]`    | Switch to a branch (parks current work first). No arg: back to `dev`/`main`.
| `br land`            | `[msg]`       | Merge the current branch into `dev`/`main` (`--no-ff`), push, delete it local + remote.
| `repo clone`         | `<url> [dir]` | Clone a repo you don't have yet (checks out `dev` if it has one). Re-run is a no-op.
| `repo create`        | `<owner/name>`| Create the GitHub repo via [gh](https://github.com/cli/cli), then `git init` if needed, commit, and push (`--public`/`--private`; private by default).
| `repo connect`       | `[target]`    | Publish local work to a remote that already exists and is empty: `git init` if needed, commit, push. Takes a URL or `owner/name`.
| `pr`                 |               | Lists PRs via [gh](https://github.com/cli/cli).
| `pr <#>`             |               | View a PR plus its diff.
| `pr create`          | `[title]`     | Push the current branch and open a PR against `dev`/`main` (no title: the last commit subject).
| `pr ok`              | `<#>`         | Approve and merge a PR.

There is deliberately no bare `commit` and no bare `pull`. Committing without sharing is how work quietly diverges, and pulling without committing is the one thing the rest of the tool never does - `br create`, `br switch`, `br land` and `pr create` all park your work first. `update` is the one command for both, and it pulls *before* it commits so your work lands on top of everyone else's and history stays linear.

Options: `-m MSG` (commit/merge message, or give it positionally), `-q`/`-y` (assume yes; no prompts), `--no-fetch` (work offline: skip the fetch and the pull), `-h`, `-v`.

A typical day:

~~~text
gitsby repo clone git@github.com:you/proj.git   # day zero: get the repo
                             # (or: gitsby repo create you/proj - publish work that only exists locally)
gitsby br create featx       # branch off dev (or main), publish it
...hack hack hack...
gitsby update "wip"          # commit + pull; do this all day long
gitsby sync                  # also push, when ready to share
gitsby br land "add featx"   # merge into dev (--no-ff), push, delete the branch
~~~

Every mutating command fetches first, shows the repo state (including who you'd act as on the remote) and the exact git commands it's about to run, and asks before touching anything. `pr` and `release` close the loop: review/accept the pull request, then cut a tagged release from `dev`.

## Installation

First, decide on the Bash or PowerShell version, mainly gating on *nix vs Windows.

- *But both at the same time is OK too. The PowerShell version will work on Linux too. Either way, the open-source PowerShell v7 or greater must be installed. (Not the old PowerShell v5 that comes preinstalled with Windows.)*

Then, decide to install for your user account only, or system-wide. (But to avoid future confusion, not both on the same machine.)

Either way, the installer shows exactly what it will do and asks before doing it (add `-y`/`-Yes` to skip the prompt, e.g. for scripted installs).

With no `--ref`/`-Ref`, the installers take the latest full release, and verify the download against that release's `SHA256SUMS` when one is published. Naming a branch, tag, or pre-release with `--ref`/`-Ref` pulls straight from the tree instead, and skips verification.

Both installers take the same options (Bash / PowerShell forms):

| Bash | PowerShell | Effect |
| --- | --- | --- |
| `-s`, `--system` | `-System` | Install for all users instead of just you. `~/.local/bin` -> `/usr/local/bin` (*nix); needs `sudo` / an elevated shell. |
| `-y`, `--yes` | `-Yes` | Skip the confirmation prompt (for scripted installs). |
| `-r`, `--ref REF` | `-Ref REF` | Install a specific branch, tag, or commit instead of the latest release. Skips checksum verification. |
| `-h`, `--help` | `-?` | Show usage and exit. |

With no options, both do a per-user install of the latest release, after showing the plan and asking.

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

- User-only install

	~~~pwsh
	irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
	~~~

- System-wide install (run from an elevated / sudo PowerShell)

	~~~pwsh
	& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System
	~~~

### Direct

No installer: grab the script itself, make it executable, and put it on your PATH.

~~~bash
curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/bin/gitsby -o ~/.local/bin/gitsby && chmod +x ~/.local/bin/gitsby
~~~

~~~pwsh
irm https://raw.githubusercontent.com/jim-collier/gitsby/main/bin/gitsby.ps1 -OutFile "$HOME/.local/bin/gitsby.ps1"
~~~

For reference, the installers use: `~/.local/bin` (user) or `/usr/local/bin` (system) on *nix; `%LOCALAPPDATA%\Programs\gitsby` (user) or `%ProgramFiles%\gitsby` (system) on Windows.

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

The document in this repo, "[Git notes and one-liners](https://github.com/jim-collier/gitsby/blob/main/git_notes_and_oneliners.md)" covers some simplified versions of what Gitsby does. They differ slightly in some areas (mostly due to being limited to one-liners), but Gitsby is the canonical source of truth.

## Contributing

Given that you may be using this for mission-critical work (as I do), Gitsby must be absolutely, 100%:

- Bulletproof and bug-free

- Unsurprising

- Useful

It is currently simple enough, that the first two objectives are attainable. (And believed to be now, as verified through manual QA, exhaustive automated testing, and near-daily use.)

Given how it's written, even if a feature fails its design, it should in theory still never compromise your work.

But if you find something that doesn't work as advertised, and/or behaves in a way you find "surprising" (even if as-designed), please let us know! File an issue.

Contributions are also welcome. Start with [contributing.md](contributing.md) for process, and [style-guide.md](style-guide.md) for coding style.

## Copyright and license

> Copyright © 2014-2026 Jim Collier (ID: 1cv◂‡Vᛦ)<br />
> Licensed under the [MIT License](https://mit-license.org/). No warranty.
