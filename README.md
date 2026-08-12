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

<!-- TOC ignore:true -->
# Gitsby

</div>

<table style="border: none; border-collapse: collapse;">
	<tr style="border: none; border-collapse: collapse;">
		<td style="border: none; border-collapse: collapse;"><img src="assets/logo.png" alt="Logo" width="128"/></td>
		<td style="border: none;">A simple, safe, opinionated Git wrapper for everyday work: nine commands instead of eighty-odd, and a workflow the tool enforces rather than a convention you're asked to remember.<br /><br />It also knows which of your GitHub accounts owns which folder, so work and personal repos stop needing SSH host aliases.</td>
	</tr>
</table>

<!-- Pin to the gif's native 960px. GitHub's max-width:100% still shrinks it on narrow columns; a % width would blow it up past native on wide ones. -->
<img src="assets/demo.gif" width="960" alt="Demo."/><br />
<sub><i>Like the smooth-scrolling terminal output and cursor? Take a look at <a href="https://github.com/jim-collier/silkterm">SilkTerm</a>!</i></sub>

<!--
	Demo video: https://www.youtube.com/watch?v=REPLACE_WITH_VIDEO_ID
	<img src="assets/demo.gif" width="960" alt="Demo."/>
-->

## Install

~~~bash
curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install.bash | bash
~~~

~~~pwsh
irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
~~~

Per-user by default, and it shows you the plan before it does anything. You need Git, plus either bash 4.4+ or PowerShell 7+. [More installation options](#installation-options).

## A typical day

~~~bash
## Day zero: get the repo
gitsby repo clone git@github.com:my-github-user/my-project.git

## Or to publish work that only exists locally
gitsby repo create my-github-user/my-project

## Branch off dev (or main), publish it
gitsby br create Feature1

## ...Do work...

## Commit + pull; do this all day long
gitsby update "wip"

## Also push, when ready to share to the upstream branch
gitsby sync

## Merge into dev (--no-ff), push, delete the branch
gitsby br land "Add Feature1"
~~~

Every mutating command fetches first, shows you the repo state and the exact git commands it is about to run, and asks before touching anything.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Install](#install)
- [A typical day](#a-typical-day)
- [What it is](#what-it-is)
- [Commands](#commands)
- [Multiple GitHub accounts](#multiple-github-accounts)
- [Compatibility](#compatibility)
- [Installation options](#installation-options)
- [How to develop](#how-to-develop)
- [Contributing](#contributing)
- [Legal stuff](#legal-stuff)

<!-- /TOC -->

## What it is

Git has more than eighty porcelain commands, because it supports every workflow, every team size, and every hard edge-case of conflict resolution. That flexibility is the whole reason it's complex.

Gitsby has 9 - or 22 counting subcommands. It gets there three ways:

- By applying one opinionated workflow and ignoring the myriad other ways of doing the same thing.

- By accepting that arguably 90% of Git's complexity covers about 10% of use-cases, and purposely leaving those alone. Not pretending they never happen - just not trying to be the tool that solves them when they do.

- By orienting commands around *goals* ("what do I want to happen with these changes?") rather than around administrative tasks. So Gitsby commands don't map 1:1 onto Git commands; they line up with what you were actually trying to do, which is usually several Git commands and a decision or two in between.

Gitsby does nothing a skilled Git user can't do directly - just with far fewer chances to make one of the expensive mistakes.

Every command aims to be safe (never risk losing work, yours or anyone's), idempotent, tolerant of a previous command having been half-finished, and forgiving - run any of them at any time, and if it doesn't make sense it won't damage anything.

The full list of opinions, and how the workflow lines up against GitFlow, GitHub Flow, GitLab Flow, and trunk-based development, is in [workflows.md](workflows.md).

## Commands

What you reach for daily is a one-word command. Everything else is grouped under a noun, so the whole set is discoverable from a handful of starting points. `repository` and `branch` spell out if you prefer them.

| Command              | Args          | What it does
| :--                  | :--           | :--
| `update`             | `[msg]`       | Pull updates, then commit all local changes. Do frequently!
| `sync`               | `[msg]`       | Pull, commit, and push. Do infrequently.
| `status`             |               | Fetch and show current status.
| `release`            | `[ver]`       | Cut a release: merge `dev` into `main`, tag, push. No version: the next one after the latest tag.
| `br`                 |               | Fetch and list branches (`br list` is the same thing).
| `br create`          | `<branch>`    | Create a new branch off `dev`/`main`. Uncommitted work on `dev`/`main` comes along; on another branch it is parked there first.
| `br hotfix`          | `<name>`      | Branch off the default branch as `hotfix/<name>`, to correct what's already published. Landing it carries the change back to `dev`.
| `br switch`          | `[branch]`    | Switch to a branch (parks current work first). No arg: back to `dev`/`main`.
| `br land`            | `[msg]`       | Merge the current branch into `dev`/`main` (`--no-ff`), push, delete it local + remote.
| `br prune`           |               | Delete branches already merged into `dev`/`main`, local + remote. Unmerged ones, and the branch you're on, are kept.
| `repo clone`         | `<url> [dir]` | Clone a repo you don't have yet (checks out `dev` if it has one). Re-run is a no-op.
| `repo create`        | `<owner/name>`| `git init` if needed, commit, then create the GitHub repo via [gh](https://github.com/cli/cli) and push to it (`--public`/`--private`; private by default).
| `repo connect`       | `[target]`    | Publish local work to a remote that already exists and is empty: `git init` if needed, commit, push. Takes a URL or `owner/name`.
| `repo url`           | `[https\|ssh]` | Show how `origin` authenticates, or switch it between the two. Nothing else about the repo changes.
| `pr`                 |               | Lists PRs via [gh](https://github.com/cli/cli).
| `pr <#>`             |               | View a PR plus its diff.
| `pr create`          | `[title]`     | Push the current branch and open a PR against `dev`/`main` (no title: the last commit subject).
| `pr ok`              | `<#>`         | Approve and merge a PR.
| `account`            |               | Show your configured GitHub accounts, and which one this folder uses (`account list` is the same thing).
| `account apply`      |               | Teach plain `git` the same folder rules, so `git` outside Gitsby behaves identically.
| `raw git`            | `<args ...>`  | Run `git` as the account this folder belongs to. Everything after `git` is git's, verbatim.
| `raw gh`             | `<args ...>`  | The same, for `gh`.

There is deliberately no bare `commit` and no bare `pull`. Committing without sharing is how work quietly diverges, and pulling without committing is the one thing the rest of the tool never does.

`br create`, `br switch`, `br land`, and `pr create` all deal with your work first. `update` is the one command for both, and it pulls *before* it commits so your work lands on top of everyone else's and history stays linear.

Options: `-m MSG` (commit/merge message, or give it positionally), `-q`/`-y` (assume yes; no prompts), `--public`/`--private` (visibility for `repo create`; private by default), `--no-fetch` (skip the fetch and the pull), `--any-identity`, `--config FILE` (read accounts from somewhere other than the usual place), `-h`, `-v`.

The PowerShell version takes the same options in PowerShell form: `-Message MSG`, `-Quiet`/`-y`, `-Public`/`-Private`, `-NoFetch`, `-AnyIdentity`, `-Config FILE`, `-Help`, `-Version`. Commands and arguments are spelled identically in both.

When the fetch finds the remote out of reach, the commands that mean something locally still work. `update` commits, `br create` and `br switch` and `br land` do their branch work, and each says what it skipped and that `sync` will publish it later. The commands that exist to publish - `sync`, `pr create`, `pr ok`, `release` - refuse up front and say what to do instead, rather than failing halfway through or reporting success having sent nothing.

`repo create` and `repo connect` list the files they are about to publish before asking, since that is the one command that hands a whole directory over for the first time. The list is what `git add --all` will actually add, `.gitignore` and all - so a stray `.env` is visible while you can still say no.

## Multiple GitHub accounts

Most people with two GitHub accounts also have a folder for each: one tree for work, one for everything else. Gitsby takes that literally. Say which account owns which folder, once, and every command run anywhere under that folder acts as that account - `git` and `gh` alike.

~~~ini
# ~/.config/gitsby/config.shcl

account.work.path       = ~/dev/work
account.work.ghAccount  = my-work-login
account.work.email      = ada@work.example

account.personal.path       = ~/dev/personal
account.personal.ghAccount  = my-personal-login
account.personal.email      = ada@home.example
~~~

Over HTTPS each account authenticates with its own token - the one `gh` already stores - so a second account costs one `gh auth login` and three lines of config, with no SSH keys and no `~/.ssh/config` host aliases baked into remote URLs. `gitsby account apply` writes the same rules into your global git config as ordinary `includeIf` blocks, so plain `git` agrees with Gitsby even when Gitsby isn't involved. `gitsby raw git ...` runs any git command as the folder's account, so existing scripts become account-correct by prefixing rather than rewriting.

Nothing here is required. With no configuration Gitsby uses whichever account `gh` is logged in as, exactly as it always did. A single-account machine never notices the feature exists.

Full detail, including SSH keys, token files, and how Gitsby checks that `gh` and `git` agree about who you are: [accounts.md](accounts.md).

## Compatibility

- Gitsby, [Git](https://git-scm.com/), [gh](https://github.com/cli/cli), [Lazygit](https://github.com/jesseduffield/lazygit), and [Tig](https://github.com/jonas/tig) are all compatible, interchangeable, and can be intermixed on the same project at any time without interference. That makes trying Gitsby cheap - you don't need to commit to anything. (No pun intended.)

	> Note: [GitButler](https://gitbutler.com/) is *not* interchangeable with these. While a great tool and a cool idea, it manages its own metadata - that inherently doesn't mix well with other git-based tools that move `HEAD` or rewrite history. It's worth a look, but give it a dedicated trial on a small personal repo rather than mixing it in.

- Gitsby works with any Git remote, GitHub and GitLab included. The exceptions go through [gh](https://github.com/cli/cli) and are therefore GitHub-only: the `pr` commands, `repo create`, and `repo connect` when you give it an `owner/name` instead of a URL.

- What you need: Git, plus either bash 4.4 or newer (for `gitsby`) or PowerShell 7 or newer (for `gitsby.ps1`). The two builds are interchangeable - same commands, same results - so on a machine without bash, the PowerShell one is a complete substitute.

	- Linux: bash is already new enough on anything current.

	- macOS: stock `/bin/bash` is 3.2 from 2007. `brew install bash` or `sudo port install bash` puts a current one alongside it rather than over it, so the new one has to come first on your `PATH`.

	- BSD ships no bash at all, but it's trivially easy to remedy: `pkg install bash` on FreeBSD, `pkg_add bash` on OpenBSD.

	- Windows: use the PowerShell build, or the Bash one under WSL.

	Gitsby tells you which of these applies if it can't run, rather than failing with a shell error.

- Your default branch can be called anything. Gitsby asks the remote what it is, and falls back to `main`, `master`, or `trunk` locally - or to your only branch, in a repo that has just one. If it genuinely can't tell, it says so and stops instead of guessing, and `git remote set-head origin --auto` is usually the one-line fix.

## Installation options

There are no distribution packages yet - nothing on apt, dnf, Homebrew, or winget. The install scripts are the supported route, and either one shows exactly what it will do and asks before doing it.

By default they take the latest full release and verify the download against that release's `SHA256SUMS`. Asking for anything else - `--release dev`, or a branch or tag by name - pulls straight from the tree instead, and skips verification.

| Bash | PowerShell | Effect |
| --- | --- | --- |
| `--release dev\|stable` | `-Release dev\|stable` | Which build: the latest release (the default), or the tip of `dev`. |
| `--target user\|system` | `-Target user\|system` | Install for you (the default) or for everyone. `~/.local/bin` -> `/usr/local/bin` (*nix); system needs `sudo` or an elevated shell. |
| `--arch x64\|amd64\|arm64` | `-Arch x64\|amd64\|arm64` | Accepted so the command line matches other installers. It has no effect here - gitsby is a script, so one file runs on every architecture. |
| `-r`, `--ref REF` | `-Ref REF` | A specific branch, tag, or commit. Skips checksum verification. |
| `-y`, `--yes` | `-Yes` | Skip the confirmation prompt (for scripted installs). |
| `-h`, `--help` | `-?` | Show usage and exit. |

`-s`/`--system` and `-System` still work, and mean the same as `--target system`.

System-wide, and the no-`curl` case:

~~~bash
curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install.bash | bash -s -- --target system
~~~

~~~pwsh
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -Target system
~~~

No `curl`? Swap in `wget -qO-` for `curl -fsSL`.

Or skip the installer entirely - grab the script, make it executable, put it on your PATH:

~~~bash
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/bin/gitsby -o ~/.local/bin/gitsby && chmod +x ~/.local/bin/gitsby
~~~

~~~pwsh
$dest = if ($IsWindows) { "$env:LOCALAPPDATA\Programs\gitsby" } else { "$HOME/.local/bin" }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
irm https://raw.githubusercontent.com/jim-collier/gitsby/main/bin/gitsby.ps1 -OutFile "$dest/gitsby.ps1"
~~~

For reference, the installers use: `~/.local/bin` (user) or `/usr/local/bin` (system) on *nix; `%LOCALAPPDATA%\Programs\gitsby` (user) or `%ProgramFiles%\gitsby` (system) on Windows.

## How to develop

One-liner dev setup: clones the repo into `./gitsby`, checks out the `dev` branch, and checks (optionally installs) the dev tooling.

~~~bash
curl -fsSL https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.bash | bash
~~~

~~~pwsh
irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1 | iex
~~~

Once it's cloned, `cicd/cicd.bash` is the local pipeline and the one command to know. It fast-forwards from origin first, so everything after it tests the tree that is actually going out, then runs the lint stage, the regression tests, the fuzz vectors, a dogfood install, a demo gif rebuild, and a commit and push at the end. Run it before opening a PR. Any stage whose tooling isn't installed reports itself absent and is skipped, so a missing `pwsh` or `gifsicle` won't stop the rest.

~~~bash
cicd/cicd.bash --quick          # skips fuzz and the demo gif; what you want while iterating
cicd/cicd.bash                  # everything, and it prompts once for a commit message
cicd/cicd.bash -y -m "message"  # unattended
~~~

Full prerequisites and process: [contributing.md](contributing.md). Coding style: [style-guide.md](style-guide.md). There's also "[Git notes and one-liners](git_notes_and_oneliners.md)", covering simplified versions of what Gitsby does - useful when you want the raw commands.

## Contributing

Given that you may be using this for mission-critical work (as I do), Gitsby aims to be bulletproof, unsurprising, and useful, in that order. It is currently simple enough that the first two are attainable, and they're believed met now - through manual QA, an automated suite that runs every check against both implementations, and near-daily use.

Given how it's written, even if a feature fails its design, it should in theory still never compromise your work.

But if you find something that doesn't work as advertised, or behaves in a way you find surprising even if as-designed, please file an issue. Contributions are welcome too - start with [contributing.md](contributing.md).

## Legal stuff

> Copyright © 2014-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)<br />
> Licensed under the [MIT License](https://mit-license.org/)<br />
> SPDX-License-Identifier: `MIT`.<br />
> No warranty.<br />
> Gitsby™ is a [trademark](trademark.md) of Jim Collier.
