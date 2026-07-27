# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## vNEXT - DATE

### Notes

### Added

### Changed

### Removed

### Other work
-->

## v2.0.0 - 2026-07-26

### Notes

- First release since 2022, and a rewrite rather than an update.
- Commands were reorganized, and the pre-2.0 names are gone. The tool is also invoked by a new name, so nothing that worked before was silently changed underneath you.

- Gitsby now ships in two languages, Bash (for *nix, Darwin, and WSL) and PowerShell (for any platform that PowerShell v7 runs on including Linux, macOS, and Windows); with the same commands and the same behavior in each.

### Added

- PowerShell version, `bin/gitsby.ps1`, for Windows and anywhere else PowerShell 7 runs.
- Installers for both versions, `install.bash` and `install.ps1`, run straight from a shell one-liner. Each shows its plan and asks first, installs for you or system-wide, and checks the download against the release checksums.
- Setup scripts for contributors, `install-dev.bash` and `install-dev.ps1`: clone the repo, switch to `dev`, and check the tooling.
- `repo clone` command: get a repo you don't have yet. Derives the directory from the URL, checks out `dev` when the repo has one, and re-running it is a no-op.
- `repo create` command: make the GitHub repo and publish to it in one step. Takes an `owner/name` target, creates it via `gh` (`--public`/`--private`; private by default), then initializes, commits, and pushes.
- `repo connect` command: publish local-only work to a remote that already exists and is empty, by URL or `owner/name`. Initializes the repo if needed, commits, and pushes. Refuses remotes that already have history, remotes that don't exist yet (that's `repo create`), and won't change an existing origin.
- `pr` command: open a pull request (`pr create`), list open ones, view one with its diff, or accept one (approve + merge + branch delete), via `gh`. `pr create` pushes the current branch first, targets `dev` when the repo has one, and titles the PR from the last commit subject unless you give a title.
- `release` command: merge dev into main `--no-ff` (when the repo has a dev branch), tag, and push. With no version given, bumps the patch of the latest `v*` tag.
- `br hotfix` command: branch off the default branch as `hotfix/<name>`, to correct what is already published without waiting for a release. Landing it merges to the default branch and then carries the change back into `dev`, so the next release can't undo it. Warns if the branch touched `bin/`, since shipped code on the default branch no longer matches the latest release.
- `br prune` command: delete every branch already merged into `dev`/`main`, local copy and remote copy both. Branches that aren't merged yet are listed and left alone, and there is no flag to override that. `br land` and `pr ok` clean up after themselves, but nothing cleaned up after a PR merged from the web UI, or after a branch you walked away from.
- GitHub account shown in the pre-flight for every `gh`-backed command, since `gh` acts as its own token's account rather than the one your SSH key authenticates as. Commands that write through `gh` compare the two: a confirmed mismatch warns interactively and is refused unattended, and `--any-identity`/`-AnyIdentity` proceeds anyway.
- Pre-flight display, before the confirmation prompt on every mutating command (and on `status`): the SSH identity a push or fetch will present (host aliases resolved to the real host, user, and key), the author that will be stamped on commits, ahead/behind counts, and the files a pull would bring in.
- `--no-fetch` to skip the fetch that every command starts with, for working offline.
- `-y`/`--yes` as an alias for `-q`, and `help`/`version` as bare words.
- A PowerShell section in `git_notes_and_oneliners.md`, mirroring the Bash one task for task.

### Changed

- Commands you reach for daily stay one word: `update`, `sync`, `status`, `release`. The rest are grouped under a noun - `repo clone` / `repo create` / `repo connect`, `br` / `br create` / `br switch` / `br land`, and `pr` / `pr create` / `pr <n>` / `pr ok <n>`. `repository` and `branch` spell out if you prefer.
- The pre-2.0 command names (`scompul`, `spush`, `scommit`, `spull`, `mkbranch`, `chbranch`, `list`, `mtm`) were removed rather than aliased. Not all of them worked, and 2.0 is a clean break under a new tool name.
- `br create`, `br switch`, and `br land` branch off / land on `dev` when the repo has one, else the default branch. `br land` refuses to run from the default branch.
- Pulling no longer risks stranding your work. A pull that can't fast-forward leaves the working tree exactly as it found it.
- `br create` carries uncommitted work onto the new branch instead of committing it to `main`/`dev` first. `br switch` refuses and says what to do instead.
- `br land` publishes an unpushed target branch before deleting the branch it merged, so the work always reaches the remote first.
- `release` now fast-forwards dev to main afterward, so dev includes the release merge and tag. If dev gained commits mid-release, the fast-forward is skipped with a warning instead of discarding anything.
- `pr ok` refuses when the current branch has uncommitted changes or commits that never reached the remote. Merging deletes the branch, and anything only local would be outside both the pull request and the merge.
- `update` and `sync` now pull *before* they commit. Committing first created a local commit, so any remote that had moved ahead was diverged and the fast-forward-only pull refused - the everyday case. Pulling first fast-forwards and your work lands on top, keeping history linear.
- `--no-fetch` now means offline: it skips the pull as well as the pre-command fetch, in every command that pulls. A remote that can't be reached warns and skips the pull instead of failing, so being offline never turns a good commit into a failed command.
- Mutating commands refuse to run without a terminal unless you pass `-q`/`-y`, so a piped or scheduled run can't silently confirm itself.
- Remote URLs with an embedded password or token print masked.
- Status now shows a compact one-line-per-file change list instead of `git status`'s long form, truncated to the terminal width and capped so a large working tree can't scroll the prompt out of view.
- Output starts and ends with a blank line, for breathing room between shell prompts.
- Errors read as plain one-line messages instead of a script dump.

### Removed

- Every pre-2.0 command name. See the reorganization note above.
- The bare `commit` and `pull` commands. Both were ways around the workflow the tool exists to enforce: `commit` alone leaves work committed but unshared, and `pull` alone was the only place gitsby let you take upstream changes without parking your own. `update` does both, in the right order.

### Other work

- Both versions carry a regression suite and a fuzz suite, run before anything is published.
- The demo at the top of the README is generated from a scripted session against a throwaway repo, so it can't drift from what the tool actually does.
