#!/usr/bin/env bash

#  shellcheck disable=2034  ## 'variable appears unused.' Everything here is consumed by cicd.bash after sourcing.

##	Purpose:
##		- Project-specific CI/CD settings for gitsby.
##		- The engine (cicd.bash) stays generic; everything project-specific lives here.
##		- To reuse the pipeline elsewhere, copy the cicd/ directory and edit this file.
##		- All paths are relative to the repo root; the engine cds there first.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## Only allow running 'sourced'.
declare -i isSourced_t6wqf=0; [[ "${BASH_SOURCE[0]}" == "${0}" ]] || isSourced_t6wqf=1
((isSourced_t6wqf)) || { echo -e "\nError in $(basename "${BASH_SOURCE[0]}"): This script is meant to be 'sourced' from within another script.\n"; exit 1; }


## Identity
APP_NAME="gitsby"
EXE_NAME="gitsby"

## Stage 1: lint. Every first-party shell file (globs, expanded by the engine).
## shellcheck is gating; there is deliberately NO formatter stage - bash is
## hand-formatted on purpose. Markdown is probe-gated (markdownlint if installed);
## the .py just gets a compile check.
SHELL_LINT_GLOBS=(
	"cicd/cicd.bash"
	"cicd/config.bash"
	"cicd/utility/lint-report.bash"
	"cicd/utility/git-auto-msg.bash"
	"cicd/utility/n8git_backup-and-publish"
	"cicd/utility/include/*.bash"
	"utility/*.bash"
)
## Report-only (findings warn, never gate): the pre-refactor legacy script. Move
## these up into SHELL_LINT_GLOBS as the refactor lands, so new code stays clean.
SHELL_LINT_WARN_GLOBS=(
	"bin/gitsby"
)
MD_LINT_GLOBS=(
	"*.md"
	"project/*.md"
)
PY_LINT_FILES=(
	"cicd/utility/gen-demo-gif.py"
)

## Stage 2: regression tests. The harness lands with the bin/gitsby refactor;
## until the file exists the engine reports the stage absent (not passing).
TEST_CMD=(cicd/test.bash)

## Stage 3: fuzz + security (adversarial input against gitsby's option/arg
## parsing and repo-state handling). Same lands-later policy; skipped by --quick.
FUZZ_CMD=(cicd/fuzz.bash)

## Full run output is tee'd here (gitignored) so warnings from any stage can be
## reviewed after the fact with utility/lint-report.bash. GFS-rotated: keeps ~30 -
## first + newest-per-hour/day/week/month/year + last 10 (GFS_KEEP_* to tune).
LINT_LOG_DIR="cicd/artifacts/lint"          # relative to repo root; created if missing (gitignored)

## Stage 4: dogfood. A script project's "release build" is the script itself:
## copy it over EXE_NAME in the first existing dir below (the stable path you
## launch by hand). The pwsh pair stays dormant until a PowerShell port exists.
DOGFOOD_BASH_SRC="bin/gitsby"
DOGFOOD_BASH_DESTS=(
	"${HOME}/synced/0-0/common/exec/util/linux/bash"
	"/usr/local/sbin"
)
DOGFOOD_PWSH_SRC=""                          # no pwsh port yet; set to its path when one lands
DOGFOOD_PWSH_DESTS=(
	"${HOME}/synced/0-0/common/exec/util/0_crossplatform"
	"/usr/local/sbin"
)

## Stage 5: demo gif. Types the scenario's commands into a fake terminal, runs
## each against the dogfooded script, renders the animated loop (640x360, 50fps,
## hard-cut loop boundary). Seeded, so an unchanged script + scenario reproduces
## the same file. Skipped by --quick / --no-demogif; self-skips until the
## scenario file exists (it lands after the bin/gitsby refactor).
DO_DEMOGIF=1
DEMOGIF_SCENARIO="cicd/demo-scenario.toml"
DEMOGIF_CMD=(cicd/utility/gen-demo-gif.py --scenario "${DEMOGIF_SCENARIO}")
DEMOGIF_OUT="assets/demo.gif"                # in-repo copy the README embeds
DEMOGIF_ARCHIVE_DIR="../private/demo/gif"    # out-of-tree originals, GFS-rotated

## Stage 6: backup + publish to git (runs from repo root). The engine always
## passes --quiet (it already gave the message prompt) and, when it has one,
## -m MESSAGE.
GIT_PUBLISH=(cicd/utility/n8git_backup-and-publish)

## Set a non-empty commit message to publish hands-off (suppresses the prompt and
## supplies the message so `git commit` won't open an editor). Left empty, publish
## prompts once at preflight unless -m/--message or -q is given (see cicd.bash).
PUBLISH_AUTO_MESSAGE=""


##	History:
##		- 2026-07-22 JC: Created.
