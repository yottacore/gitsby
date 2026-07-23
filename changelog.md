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

### Changed

- Renamed commands: `scompul`->`saveup`, `spush`->`sync`, `scommit`->`commit`, `spull`->`pull`, `mkbranch`->`newbr`, `chbranch`->`gobr`, `list`->`listbr`, `mtm`->`land`. The old names still work.
- `newbr`, `gobr`, and `land` now branch off / land on `dev` when the repo has one, else the default branch. `land` refuses to run from the default branch.

### Removed

### Other work
