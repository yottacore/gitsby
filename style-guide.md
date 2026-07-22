<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Style guide

Canonical coding style for this project's Bash and PowerShell. For contribution process, see [contributing.md](contributing.md).

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Both languages](#both-languages)
	- [Naming](#naming)
	- [Comments and headers](#comments-and-headers)
- [Bash](#bash)
- [PowerShell](#powershell)

<!-- /TOC -->

## Both languages

### Naming

- Use meaningful names a human can read, search for, and replace: `upperBound`, not `ub`.

- Don't overcorrect. Short conventional names are fine where the meaning is clear.

- Single-letter variables are fine for loop counters and iterators (`for i in ...`), where that's idiomatic.

### Comments and headers

- Terse. Explain *why*, not *what*. Don't restate the next line of code.

- No decorative flair or banner dividers. (The one exception: full-width section-rule comments between major blocks, matching the existing ones.)

- The file header carries purpose, copyright, and license, in the existing format: `©` copyright line, license name and URL, SPDX identifier.

- Helper and utility scripts are usually MIT-licensed regardless of the project's license, and say so in their own header.

## Bash

- Target Bash 5. Prefer its idioms over portable-but-clunky workarounds.

- Must pass shellcheck. Per-file disables go at the top, each with a short reason (see the top of `bin/x9git`).

- Tabs for indentation, spaces for alignment.

- Reuse the script's existing output helpers (`fEcho`, `fEcho_Clean`). Don't add new echo/printf wrapper functions.

- Verify state before acting; make no assumptions about local or remote repo state. Every operation should be safe and idempotent.

## PowerShell

- Objects, not text. The pipeline passes .NET objects, not strings. Never parse command output as text when you can access properties. Filter, select, and sort on properties (`Where-Object`, `Select-Object`, `Sort-Object`, `Group-Object`); don't string-munge grep/sed/awk-style. This is the #1 rule; Bash habits break here.

- Use approved verbs (`Get-Verb`) for functions: Verb-Noun naming, PascalCase, singular noun (`Get-User`, not `Get-Users` or `Fetch-User`).

- Full cmdlet names and full parameter names in scripts (`Where-Object` not `?`, `-Property` not positional). Aliases and positional parameters are for the interactive prompt, not committed code.

- Advanced functions: `[CmdletBinding()]` and typed `param()` blocks. Declare parameter types; use `[Parameter(Mandatory)]`, validation attributes (`ValidateSet`, `ValidateNotNullOrEmpty`), and pipeline binding (`ValueFromPipeline`) with `begin`/`process`/`end` where relevant.

- `Set-StrictMode -Version Latest`, and deliberate `$ErrorActionPreference` handling. Prefer terminating errors for real failures: `-ErrorAction Stop` plus `try`/`catch`, and `throw` for your own errors. Don't silently swallow with `-ErrorAction SilentlyContinue` unless you then check `$?`/`$Error` and mean it.

- Output objects, don't `Write-Host`. Emit objects (or `[PSCustomObject]`) to the pipeline so callers can consume them. `Write-Host` is only for genuine console-only UI text. Use `Write-Verbose`/`Write-Warning`/`Write-Error` for diagnostics, gated by streams - not inline print debugging.

- Return rich data as `[PSCustomObject]` with named properties, not formatted strings. Keep formatting (`Format-Table`/`Format-List`) at the very end of a pipeline, display layer only. Never feed `Format-*` output into further logic.

- Comparison operators: `-eq -ne -lt -gt -match -contains` etc., not `<`, `>`, `==`. Remember `-eq` is case-insensitive by default (`-ceq` for case-sensitive). `$null` goes on the LEFT of `-eq` comparisons.

- Prefer the pipeline and cmdlets over manual loops when readable. Use `foreach ($x in $y) {}` for complex per-item logic. Avoid array `+=` in loops (O(n^2) recopy); use a `List[T]` or collect pipeline output.

- Quote deliberately: single quotes for literals, double quotes only when interpolating. Brace variables in strings when ambiguous: `"${name}"`.

- Comment-based help (`.SYNOPSIS`/`.PARAMETER`/`.EXAMPLE`) on functions and scripts.

- Cross-platform: target PowerShell 7+ (`pwsh`). Don't assume Windows-only cmdlets or paths. Use `Join-Path` and `$PSScriptRoot`, not hardcoded separators.

- Must pass PSScriptAnalyzer clean (settings, if any, live in `PSScriptAnalyzerSettings.psd1`).

- 4 spaces per indent (PowerShell convention; unlike the Bash side of this repo).
