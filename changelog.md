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

## v2.0.0 - 2026-07-25

### Notes

- First release since 2022, and a rewrite rather than an update.
- Most commands were renamed. The old names all still work, so existing habits and scripts keep running.
- Gitsby now ships in two languages, Bash and PowerShell, with the same commands and the same behavior in each.

### Added

- PowerShell version, `bin/gitsby.ps1`, for Windows and anywhere else PowerShell 7 runs.
- Installers for both versions, `install.bash` and `install.ps1`, run straight from a shell one-liner. Each shows its plan and asks first, installs for you or system-wide, and checks the download against the release checksums.
- Setup scripts for contributors, `install-dev.bash` and `install-dev.ps1`: clone the repo, switch to `dev`, and check the tooling.
- `clone` command: get a repo you don't have yet. Derives the directory from the URL, checks out `dev` when the repo has one, and re-running it is a no-op.
- `connect` command: publish work that only exists locally. Initializes the repo if needed, commits, and pushes - to an existing empty remote by URL, or creates the GitHub repo via `gh` for an `owner/name` target (`--public`/`--private`; private by default). Refuses remotes that already have history, and won't change an existing origin.
- `pr` command: list open pull requests, view one with its diff, or accept one (approve + merge + branch delete), via `gh`.
- `release` command: merge dev into main `--no-ff` (when the repo has a dev branch), tag, and push. With no version given, bumps the patch of the latest `v*` tag.
- Pre-flight display, before the confirmation prompt on every mutating command (and on `status`): the SSH identity a push or fetch will present (host aliases resolved to the real host, user, and key), the author that will be stamped on commits, ahead/behind counts, and the files a pull would bring in.
- `--no-fetch` to skip the fetch that every command starts with, for working offline.
- `-y`/`--yes` as an alias for `-q`, and `help`/`version` as bare words.
- A PowerShell section in `git_notes_and_oneliners.md`, mirroring the Bash one task for task.

### Changed

- Renamed commands: `scompul`->`update`, `spush`->`sync`, `scommit`->`commit`, `spull`->`pull`, `mkbranch`->`newbr`, `chbranch`->`gobr`, `list`->`listbr`, `mtm`->`land`. The old names still work (as does the interim name `saveup`).
- `newbr`, `gobr`, and `land` now branch off / land on `dev` when the repo has one, else the default branch. `land` refuses to run from the default branch.
- `pull` no longer risks stranding your work. A pull that can't fast-forward leaves the working tree exactly as it found it.
- `newbr` carries uncommitted work onto the new branch instead of committing it to `main`/`dev` first. `gobr` refuses and says what to do instead.
- `land` publishes an unpushed target branch before deleting the branch it merged, so the work always reaches the remote first.
- `release` now fast-forwards dev to main afterward, so dev includes the release merge and tag. If dev gained commits mid-release, the fast-forward is skipped with a warning instead of discarding anything.
- Mutating commands refuse to run without a terminal unless you pass `-q`/`-y`, so a piped or scheduled run can't silently confirm itself.
- Remote URLs with an embedded password or token print masked.
- Status now shows a compact one-line-per-file change list instead of `git status`'s long form, truncated to the terminal width and capped so a large working tree can't scroll the prompt out of view.
- Output starts and ends with a blank line, for breathing room between shell prompts.
- Errors read as plain one-line messages instead of a script dump.

### Removed

- The old command names are no longer listed in help. They still work.

### Other work

- Both versions carry a regression suite and a fuzz suite, run before anything is published.
- The demo at the top of the README is generated from a scripted session against a throwaway repo, so it can't drift from what the tool actually does.
