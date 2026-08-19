#!/usr/bin/env bash

#  shellcheck disable=2034  ## 'variable appears unused.' Everything here is consumed by cicd.bash after sourcing.

##	Purpose:
##		- Project-specific CI/CD settings for gitsby.
##		- The engine (cicd.bash) stays generic; everything project-specific lives here.
##		- To reuse the pipeline elsewhere, copy the cicd/ directory and edit this file.
##		- All paths are relative to the repo root; the engine cds there first.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## Only allow running 'sourced'.
declare -i isSourced_t6wqf=0; [[ "${BASH_SOURCE[0]}" == "${0}" ]] || isSourced_t6wqf=1
((isSourced_t6wqf)) || { echo -e "\nError in $(basename "${BASH_SOURCE[0]}"): This script is meant to be 'sourced' from within another script.\n"; exit 1; }


## Identity
APP_NAME="gitsby"
EXE_NAME="gitsby"

## The Go module. Everything the pipeline builds and tests comes from here; the frozen
## script builds under legacy/ are reference only and no stage touches them except parity.
GO_MODULE_DIR="src-go"

## Stage 1: lint. Go first (gofmt is the arbiter of format, vet and staticcheck gate),
## then every first-party shell file (globs, expanded by the engine). shellcheck is
## gating; there is deliberately NO bash formatter stage - the pipeline's own scripts are
## hand-formatted on purpose. Markdown is probe-gated (markdownlint if installed); the .py
## just gets a compile check. legacy/ is deliberately absent from every glob: it is frozen,
## so a newer shellcheck finding there is noise nobody is allowed to fix.
SHELL_LINT_GLOBS=(
	"cicd/*.bash"
	"cicd/utility/*.bash"
	"cicd/utility/n8git_backup-and-publish"
	"cicd/utility/include/*.bash"
	"cicd/utility/demo/*.bash"
)
## Report-only (findings warn, never gate). Empty since the bin/gitsby refactor.
SHELL_LINT_WARN_GLOBS=()
MD_LINT_GLOBS=(
	"*.md"
	"legacy/*.md"
	"project/*.md"
	"project/design_docs/*.md"
)
PY_LINT_FILES=(
	"cicd/utility/demo/gen-demo-gif.py"
)

## Stage 2: build + regression tests. The suite runs against the compiled binary and gates.
TEST_CMD=(cicd/test.bash)

## Stage 3: fuzz + security (adversarial input against gitsby's own command/option/
## arg surface, with an injection canary). Skipped by --quick.
FUZZ_CMD=(cicd/fuzz.bash)

## Stage 3b: backwards compatibility. Same input to the Go build and to the frozen v2.1.0
## script under legacy/, answers compared byte for byte wherever the two still claim to be
## the same command. Skipped by --quick; self-skips when legacy/ is gone.
PARITY_CMD=(cicd/parity.bash)

## Full run output is tee'd here (gitignored) so warnings from any stage can be
## reviewed after the fact with utility/lint-report.bash. GFS-rotated: keeps ~30 -
## first + newest-per-hour/day/week/month/year + last 10 (GFS_KEEP_* to tune).
LINT_LOG_DIR="cicd/artifacts/lint"          # relative to repo root; created if missing (gitignored)

## Stage 4: dogfood. Build each target and copy it to the first existing, writable dir in
## that target's list. Cross-building is free here - the module is pure stdlib with no cgo -
## so every target is built every run rather than on a cadence. Destination arrays are found
## by name: DOGFOOD_DESTS_<GOOS>_<GOARCH>, upper-cased.
DOGFOOD_TARGETS=(
	"linux/amd64"
	"windows/amd64"
	"darwin/arm64"
)
DOGFOOD_DESTS_LINUX_AMD64=(
	"${HOME}/synced/0-0/common/exec/util/linux/bin"
	"/usr/local/sbin"
)
## Two spellings of one share: the path as this box mounts it, and the path Windows mounts
## it at. Whichever exists is the one running.
DOGFOOD_DESTS_WINDOWS_AMD64=(
	"${HOME}/synced/0-0/common/exec/util/mswin/cli/by-self/win64"
	"C:/opt/0-0/common/exec/synced/util/mswin/cli/by-self/win64"
)
## One macOS slot, so one target: arm64. A universal binary would need lipo, which only
## exists on a Mac, and there is no second destination to justify it.
DOGFOOD_DESTS_DARWIN_ARM64=(
	"${HOME}/synced/0-0/common/exec/util/macos/bin"
	"/Users/collierjr/synced/0-0/common/exec/util/macos/bin"
)

## Release assets (cicd/release.bash). Every platform the module cross-builds to, which is
## every platform Go targets - the tree is pure stdlib with no cgo, so nothing here needs an
## SDK or a machine of its own. Published as gitsby-<goos>-<goarch>, with .exe on Windows,
## alongside a SHA256SUMS over the set.
RELEASE_TARGETS=(
	"linux/amd64"
	"linux/arm64"
	"windows/amd64"
	"windows/arm64"
	"darwin/amd64"
	"darwin/arm64"
)

## Stage 5: demo gif. Types the scenario's command into a fake terminal, runs it
## against the dogfooded binary (in a throwaway anonymized repo the scenario
## builds), renders the 960x540 animated loop (hard-cut boundary). Seeded + pinned
## commit dates, so an unchanged binary + scenario reproduces the same file byte
## for byte (the optimizer below is deterministic too, though its version counts).
## Skipped by --quick / --no-demogif; self-skips if the scenario is absent.
DO_DEMOGIF=1
DEMOGIF_SCENARIO="cicd/utility/demo/demo-scenario.toml"
DEMOGIF_CMD=(cicd/utility/demo/gen-demo-gif.py --scenario "${DEMOGIF_SCENARIO}")
DEMOGIF_OUT="assets/demo.gif"                # in-repo copy the README embeds
DEMOGIF_ARCHIVE_DIR="../private/demo/gif"    # out-of-tree originals, GFS-rotated
## Lossless squeeze, when the tool is around; skipped silently if not. Worth
## about 9% - the renderer already crops each frame to what changed, so most of
## the win is banked. Stays before the compare, so the committed file is the
## optimized one. Lossy modes buy almost nothing on a 35-colour text demo.
DEMOGIF_OPT_CMD=(gifsicle -O3)

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
##		- 2026-08-18 JC: Go-specific. The scripts moved to legacy/ and left the lint globs with them; dogfood builds three targets instead of copying one script; parity became a stage, comparing the Go build against the frozen one.
