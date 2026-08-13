<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Golang port

Gitsby moves from two scripted implementations to one compiled Go binary. This document covers the reasoning, the migration route, and what still needs working out.

<!-- TOC -->

- [Why](#why)
- [What the port fixes](#what-the-port-fixes)
- [What the port does not fix](#what-the-port-does-not-fix)
- [Why Go](#why-go)
- [Migration route](#migration-route)
- [Effects outside the program](#effects-outside-the-program)
- [Still to figure out](#still-to-figure-out)

<!-- /TOC -->

## Why

- The same logic is written twice. Each implementation is roughly 3,000 lines, and every change has to be made in both, then proven identical.

- Most of the test apparatus exists to police that duplication. The regression suite runs each check against both implementations, and `parity.bash` exists for no other reason.

- The recurring bug source is the porting itself, not the product. Argument binding, byte-order marks, path spelling, wildcard expansion and quoting have each produced real defects, and none of them are about git.

- One implementation removes the second copy, the parity suite, and half the regression checks.

## What the port fixes

- Every defect caused by a language artifact rather than by the problem being solved.

	- PowerShell argument binding: joined options, a bare `--` being unreachable, unknown options collecting silently, two switches sharing one parameter.

	- Byte-order marks breaking both the shebang and the documented one-liners.

	- Wildcard expansion of user values on the way to git.

	- Path spelling, where the same folder is written three ways depending on which shell asked.

- The injection surface largely goes away. Commands run through an argument list with no shell in between, so word splitting and expansion cannot occur. A good part of what the fuzz suite currently proves becomes structurally impossible instead.

- Windows stops needing Git Bash for the product itself.

## What the port does not fix

- Surprises in git and gh behavior survive the port untouched. Recent examples include:
	- A fast-forward pull reporting success after its stash reapply conflicted
	- Branch deletion checking containment against the wrong ref
	- Version sorting placing a candidate above the release it precedes
	- A branch deleted through the API leaving the local tracking ref alive.

- These are the more dangerous defects. One of them committed conflict markers and reported success.

- The port makes maintenance quieter. It does not make the tool safer on its own, and the regression suite remains the thing that does.

## Why Go

- Cross-compilation reaches macOS without a Mac. Pure Go builds for macOS from any host with no SDK. Rust needs the macOS SDK, which is the reason macOS is deferred in the sister project's build pipeline. For a tool whose main claim is installing anywhere, that difference decides it.

- The work is running a process, reading its text, deciding, and printing. That is well inside what Go is good at, and nowhere near what Rust is for.

- Executable size is not a significant factor here. Rust would produce a smaller file, but the difference is trivial for something downloaded once. And go is still pretty small.

- Neither language removes the process calls / shelling out. A git library would change behavior too much to be worth it, and gh has no library at all, so text parsing stays either way.

## Migration route

The regression suite already drives an implementation through a per-implementation shim. That makes the port incremental rather than a rewrite.

- Add a third leg to the suite for the Go binary, alongside the two existing ones.

- Build the port against the suite from the first commit. The existing checks are a complete description of the behavior, including all the git and gh handling that has been earned the hard way.

- Both scripted implementations stay in place and keep working throughout. Nothing has to be finished for the project to remain releasable.

- When the Go leg passes everything, the two scripted implementations and `parity.bash` are removed together.

This gives a continuous pass or fail signal, keeps the work abortable at any point, and avoids the usual failure mode of replacing working software with an unfinished copy.

## Effects outside the program

- The installers stay as shell and PowerShell scripts. They bootstrap before any binary exists, so they cannot be Go.

- `--arch` becomes real. It is currently accepted and documented as having no effect, because one script runs everywhere.

- Releases carry per-platform artifacts with a checksum each, instead of two script files.

- The lint stage adds Go tooling. Shellcheck and PSScriptAnalyzer still cover the pipeline and the installers, with Go tooling added for the product.

- The version stops being a line in the source and becomes a build-time value.

## Still to figure out

- Whether macOS builds need signing. The documented install path is a terminal download rather than a browser, so quarantine may not apply, but this needs testing on a real ARM macOS, rather than assuming or relying on my old x86_64 macbook or hackintosh VM.

- How much of the fuzz suite is still meaningful once there is no shell in the path, and what should replace the parts that are not.

- At what point to ditch hand-parsing .shcl, import real go module, and refactor .shcl to be fully hierarchical.

- Change to dogfood location.

- How long the scripted implementations stay in the repository after the Go leg passes, and whether either is worth keeping as a fallback. Probably just punting and moving to a "legacy" folder as with some sister projects is the way.

- Whether the release automation cuts the release before or after the build matrix runs, so a failed build never produces a half-published release.
