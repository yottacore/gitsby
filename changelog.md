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

## v2.0.0-beta1

### Notes

### Added

- `pr` command: list open pull requests, view one with its diff, or accept one (approve + merge + branch delete), via `gh`.
- `release` command: merge dev into main `--no-ff` (when the repo has a dev branch), tag, and push. With no version given, bumps the patch of the latest `v*` tag.
- Pre-flight display, before the confirmation prompt on every mutating command (and on `status`): the SSH identity a push or fetch will present (host aliases resolved to the real host, user, and key), the author that will be stamped on commits, ahead/behind counts, and the files a pull would bring in.

### Changed

- Renamed commands: `scompul`->`update`, `spush`->`sync`, `scommit`->`commit`, `spull`->`pull`, `mkbranch`->`newbr`, `chbranch`->`gobr`, `list`->`listbr`, `mtm`->`land`. The old names still work (as does the interim name `saveup`).
- `release` now fast-forwards dev to main afterward, so dev includes the release merge and tag. If dev gained commits mid-release, the fast-forward is skipped with a warning instead of discarding anything.
- Output starts and ends with a blank line, for breathing room between shell prompts.
- Status now shows a compact one-line-per-file change list instead of `git status`'s long form, truncated to the terminal width and capped so a large working tree can't scroll the prompt out of view.
- `newbr`, `gobr`, and `land` now branch off / land on `dev` when the repo has one, else the default branch. `land` refuses to run from the default branch.

### Removed

### Other work
