#!/usr/bin/env bash

#  shellcheck disable=2034  ## 'variable appears unused.' Everything here is consumed by cicd.bash after sourcing.
#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		- Project-specific CI/CD settings for gitsby.
##		- The engine (cicd.bash) stays generic; everything project-specific lives here.
##		- To reuse the pipeline elsewhere, copy the cicd/ directory and edit this file.
##		- All paths are relative to the repo root; the engine cds there first.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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

## Build flags, in one place because four build sites have to agree on them.
##   -trimpath      keeps the build machine's directory names out of the binary.
##   -buildvcs=false keeps the repository's revision and dirty flag out of it. Without this
##                  the published assets carry whatever commit preceded the tag they claim -
##                  so nobody, including us, can rebuild them to the checksums we publish.
##   -buildid=      drops the last input-derived stamp, so identical source gives identical
##                  bytes on any machine with the same toolchain (pinned in go.mod).
##   -s -w          no symbol table, no DWARF: smaller is one of the two things that matter.
## CGO_ENABLED=0 goes with them, on the native build as well as the cross-builds, so every
## artifact the pipeline produces is the same kind of thing. GOAMD64=v1 sits beside it at each
## site. It's Go's default, so the bytes don't change, but a GOAMD64 left in the environment or
## in 'go env -w' would raise the CPU floor past the Core 2 Duo and Phenom II.
GO_BUILD_FLAGS=(-trimpath -buildvcs=false)
GO_LDFLAGS_COMMON="-s -w -buildid="
## The toolchain that builds the published assets. Two compiler versions produce different
## bytes from the same source, so reproducing a release means naming the one that cut it -
## and go.mod's 'go' line is a minimum, not a pin. Release builds only: a dev build should
## follow whatever is installed.
GO_RELEASE_TOOLCHAIN="go1.26.2"
## Stages 1-4 and the demo run in the image from cicd/container/Dockerfile unless this is 0
## or the run says --no-container. A box without a working docker runs them here, with a warning.
CICD_CONTAINER=1

## The versions the Go tools were at when this pipeline last gated a green run. Recorded,
## compared and warned about - never installed and never enforced. Which version passed
## something is worth knowing: a finding that appears out of nowhere on an unchanged tree
## is usually a tool that moved rather than code that did, and a machine two years behind
## reports clean for the opposite reason. Read with 'go version -m', which answers for any
## Go-built binary - the four of them spell '--version' four different ways, and one has no
## such flag at all. The toolchain itself is GO_RELEASE_TOOLCHAIN above.
GO_TOOL_VERSIONS=(
	"staticcheck=v0.7.0"
	"golangci-lint=v2.12.2"
	"govulncheck=v1.5.0"
	"goversioninfo=v1.5.0"
)
## The same, for the tools outside Go whose version can change a result: a lint finding, the
## demo gif's bytes, or a spawn count. Each spells its version its own way, so cicd.bash's
## fToolVersion knows how to ask every one of them.
TOOL_VERSIONS=(
	"shellcheck=0.11.0"
	"markdownlint=0.49.1"
	"PSScriptAnalyzer=1.25.0"
	"gifsicle=1.96"
	"Pillow=13.0.0"
	"strace=6.18"
	"git=2.51.0"
	"ruff=0.15.22"
	"pip-audit=2.10.1"
	"codeql=2.27.2"
)

## Half the cores, rounded up. The compiler takes all of them by default, in every build and
## in the eight-target release loop, which makes the machine unusable for the duration.
BUILD_JOBS=$(( ( $( nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2 ) + 1 ) / 2 ))

## Stage 1: lint. Go first (gofmt is the arbiter of format, vet and staticcheck gate),
## then every first-party shell file (globs, expanded by the engine). shellcheck is
## gating; there is deliberately NO bash formatter stage - the pipeline's own scripts are
## hand-formatted on purpose. Markdown is probe-gated (markdownlint if installed); the Python
## files get a compile check and ruff's leak rules. legacy/ is deliberately absent from every glob: it is frozen,
## so a newer shellcheck finding there is noise nobody is allowed to fix.
SHELL_LINT_GLOBS=(
	"install.bash"
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
	"cicd/utility/codeql-findings.py"
)
## ruff over the same files, these rules only: lru_cache on a method (B019), open() with no
## 'with' (SIM115), and a mutable default argument (B006). Probe-gated.
PY_LINT_RULES=(B019 SIM115 B006)
## Stage 3: pip-audit over the third-party libraries those files import, as installed. Skipped
## by --quick and --no-fuzz, like govulncheck. The leak checks' CodeQL reads their installed source too.
PY_AUDIT_DISTS=(Pillow fonttools pycairo PyGObject)
## Advisories against the upstream versions of the Debian builds the demo runs on. Debian's
## builds carry security patches past those versions, so each one names the Debian build
## that fixed it: backlog 2026101905585018. Pillow is the upstream wheel, so it needs none.
## A new advisory fails the run.
PIP_AUDIT_IGNORE=(
	## fontTools 4.57.0-1+deb13u1
	CVE-2025-66034   # fixed in 4.57.0-1+deb13u1
)
## PowerShell (probe-gated: needs pwsh + the PSScriptAnalyzer module). Back after the
## scripted build was frozen: the installer is the one piece of PowerShell that still
## ships, because it is the only shell every Windows box already has. run-latest.ps1 is a
## dev helper, but first-party all the same.
PS_LINT_GLOBS=(
	"install.ps1"
	"cicd/utility/run-latest.ps1"
)
## Its rules, in the file editors find on their own.
PS_LINT_SETTINGS="PSScriptAnalyzerSettings.psd1"

## Stage 1: the committed Windows resource (icon + version details), checked rather than built.
## It is linked into the .exe files we publish checksums for, so it lives in the tree the same
## way the source does - see the script's header for why it can't be generated at build time.
## Probe-gated on goversioninfo; release.bash regenerates it with the version bump.
WINRES_CMD=(cicd/utility/gen-winres.bash)

## Stage 1: backlog rules. Open review items carry an "Origin:" line, and a suite check
## removed on the branch is named in the backlog. See the script's header for why.
BACKLOG_CHECK_CMD=(cicd/utility/backlog-check.bash)

## Stage 2: build + regression tests. The suite runs against the compiled binary and gates.
## Skipped by --quick, which keeps only the build and go test here.
TEST_CMD=(cicd/test.bash)

## Stage 3: fuzz + security (adversarial input against gitsby's own command/option/
## arg surface, with an injection canary). Runs under --quick too; the native fuzz
## targets and govulncheck don't.
FUZZ_CMD=(cicd/fuzz.bash)

## Stage 4: backwards compatibility. Same input to the Go build and to the frozen v2.1.0
## script under legacy/, answers compared byte for byte wherever the two still claim to be
## the same command. Self-skips when legacy/ is gone.
PARITY_CMD=(cicd/parity.bash)

## Full run output is tee'd here (gitignored) so warnings from any stage can be
## reviewed after the fact with utility/lint-report.bash. GFS-rotated: keeps ~30 -
## first + newest-per-hour/day/week/month/year + last 10 (GFS_KEEP_* to tune).
LINT_LOG_DIR="cicd/artifacts/lint"          # relative to repo root; created if missing (gitignored)

## Stage 3: spawn counts. One row per command, GFS-rotated the same way; the newest previous
## run is the baseline the next one is compared against.
SPAWN_COUNT_DIR="cicd/artifacts/spawn"      # relative to repo root; created if missing (gitignored)
SPAWN_COUNT_CMD=(cicd/utility/spawn-count.bash)

## Where a kept build is archived, for bisecting a behavior change against an older one.
KEEP_BUILD_DIR="cicd/artifacts/builds"      # relative to repo root; created if missing (gitignored)

## The leak checks: the soak test's rounds (N, then N more, compared), and where each run's heap
## profiles go, one folder per run.
LEAKCHECK_SOAK_ROUNDS=30
LEAKCHECK_DIR="cicd/artifacts/leakcheck"    # relative to repo root; created if missing (gitignored)
## They also run CodeQL, from the Go and Python bundles of the version in TOOL_VERSIONS:
## the CLI and its query packs, checked against these sums when the image is built. It's in the
## image and nowhere else. Each language gets its security and quality suite. Go's runs once for
## each OS in RELEASE_TARGETS, since the extractor sees one OS's files at a time. Python's runs
## once, over PY_LINT_FILES and the installed source of PY_AUDIT_DISTS. Third-party code goes
## under vendor/, where only Go's security, correctness and reliability findings count, and only
## Python's security ones (cicd/utility/codeql-findings.py).
CODEQL_SHA256="0cfb942cd33fb71d3a3b84dad626ef8895ea3f1ceb097bc8cdb7d4493f032ae9"
CODEQL_PY_SHA256="b0dce01b3aa8d14cfbac8a653eb1921fb71514695fc33b79f0e0e2eb81467350"
CODEQL_SUITE="codeql/go-queries:codeql-suites/go-security-and-quality.qls"
CODEQL_PY_SUITE="codeql/python-queries:codeql-suites/python-security-and-quality.qls"
## Findings set aside, as "rule path", each with its backlog item. One that stops being reported
## fails the run, so this list can't outlive what it covers.
CODEQL_IGNORE=(
	## shcl 2.0.0, the old writer the tests use to make old-format files. Won't fix: it's frozen,
	## and only the tests run it. Backlog 2026101906343987.
	"go/incorrect-integer-conversion vendor/github.com/jim-collier/shcl/source/go/v2/shcl.go"
	"go/unhandled-writable-file-close vendor/github.com/jim-collier/shcl/source/go/v2/shcl.go"
	## A wide regex character range in fontTools' XML module. Not reachable: the demo never loads
	## that module. Backlog 2026101907065426.
	"py/overly-large-range vendor/fontTools/misc/etree.py"
)

## Stage 5: dogfood. Build each target and copy it to the first existing, writable dir in
## that target's list. Cross-building is free here - the module is pure Go with no cgo -
## so every target is built every run rather than on a cadence. Destination arrays are found
## by name: DOGFOOD_DESTS_<GOOS>_<GOARCH>, upper-cased.
DOGFOOD_TARGETS=(
	"linux/amd64"
	"windows/amd64"
	"darwin/universal"
)
DOGFOOD_DESTS_LINUX_AMD64=(
	"${HOME}/synced/0-0/common/exec/util/linux/bin"
)
## Two spellings of one share: the path as this box mounts it, and the path Windows mounts
## it at. Whichever exists is the one running. cli, not gui - gitsby is a terminal program.
DOGFOOD_DESTS_WINDOWS_AMD64=(
	"${HOME}/synced/0-0/common/exec/util/mswin/cli/by-self/win64"
	"C:/opt/0-0/common/exec/synced/util/mswin/cli/by-self/win64"
)
## One macOS slot, and Macs of both CPUs read it, so the target is a universal binary:
## amd64 and arm64 built apart, then joined by cicd/utility/macho-universal.bash. The share
## mounts at the same spelling from Linux and from macOS, so one entry covers both.
DOGFOOD_DESTS_DARWIN_UNIVERSAL=(
	"${HOME}/synced/0-0/common/exec/util/macos/bin"
)

## Last resort when none of the shared dirs above exist - the same dir install.bash uses by
## default. Only appended to the target that matches the box doing the build: a .exe has no
## business in a Linux ~/.local/bin, and it would match there every time.
DOGFOOD_FALLBACK_DIR="${HOME}/.local/bin"

## Release assets (cicd/release.bash). Every platform the module cross-builds to, which is
## every platform Go targets - the tree is pure Go with no cgo, so nothing here needs an
## SDK or a machine of its own. Published as gitsby-<goos>-<goarch>, with .exe on Windows,
## alongside a SHA256SUMS over the set. macOS is one universal file for both CPUs, joined the
## way dogfood joins it, so the installers take the same file on any Mac.
RELEASE_TARGETS=(
	"linux/amd64"
	"linux/arm64"
	"windows/amd64"
	"windows/arm64"
	"darwin/universal"
	"freebsd/amd64"
	"freebsd/arm64"
)

## Stage 6: demo gif. Types the scenario's command into a fake terminal, runs it
## against a build of its own, stamped with the newest release rather than the commit
## (in a throwaway anonymized repo the scenario builds), renders the 960x540 animated
## loop (hard-cut boundary). Seeded, with pinned commit dates and that fixed stamp, so
## a commit that changes nothing the demo prints reproduces the same file byte for
## byte (the optimizer below is deterministic too, though its version counts).
## Skipped by --quick / --no-demogif; self-skips if the scenario is absent.
DO_DEMOGIF=1
DEMOGIF_SCENARIO="cicd/utility/demo/demo-scenario.toml"
DEMOGIF_CMD=(cicd/utility/demo/gen-demo-gif.py --scenario "${DEMOGIF_SCENARIO}")
DEMOGIF_OUT="assets/demo.gif"                # in-repo copy the README embeds
DEMOGIF_ARCHIVE_DIR="../private/demo/gif"    # out-of-tree originals, GFS-rotated
## The tools in TOOL_VERSIONS that shape the gif's bytes. A render that differs from the committed
## gif, made where one of them isn't at its recorded version, is warned about and not kept, since
## the difference may be the tool's. The image always has the recorded ones.
DEMOGIF_TOOLS=(Pillow gifsicle)
## Lossless squeeze, when the tool is around; skipped silently if not. Worth
## about 9% - the renderer already crops each frame to what changed, so most of
## the win is banked. Stays before the compare, so the committed file is the
## optimized one. Lossy modes buy almost nothing on a 35-color text demo.
DEMOGIF_OPT_CMD=(gifsicle -O3)

## Stage 7: Remote tests, over ssh. Each box is taken through a host lock shared with
## other projects, only while its run lasts and only if free right now. The lock is a script
## outside the repo; the first file matching REMOTE_LOCK_GLOB is it, and with none the stage
## is skipped. The boxes are this machine's, so on anyone else's that is what happens. A VM goes
## through the VM state helper beside the lock, which wakes it and puts it back as it was found.
REMOTE_TEST_CMD=(cicd/remote-tests.bash)
REMOTE_LOCK_GLOB="${HOME}/synced/0-0/common/exec/util/linux/bash/*_windows-host-lock.bash"
## Each entry is the name the lock knows a box by, then optionally a colon and the ssh names it
## answers to, tried in order.
## Every Mac in the list runs; of the Windows boxes, the first free one does. b29w goes first,
## since it spares this box, and nothing here needs vm925w's GPU.
REMOTE_MAC_HOSTS=("b26" "vmKt6m:vmkt6m")
REMOTE_WINDOWS_HOSTS=("b29w" "vm925w")
## Both Macs are Intel. /bin/bash there is 3.2, below the suite's floor, so the suite runs under
## Homebrew's, which is not on the PATH an ssh command gets. vmKt6m runs as a test user who is
## not an admin, with nothing but the system on PATH, which b26 doesn't cover.
REMOTE_MAC_GOARCH="amd64"
REMOTE_MAC_BASH="/usr/local/bin/bash"
## A Mac without one of these, or without REMOTE_MAC_BASH, runs the Go tests only.
REMOTE_MAC_NEEDS=(git go)
## The stage's own folder under each Mac's and Unix box's temp root (HOST_TEMP, else TMPDIR, else
## /tmp), holding the copy of the tree the suite runs in.
REMOTE_MAC_DIR="gitsby/remote-tests"
## Other Unix boxes, run the way the Mac is, each as its test user: the Go tests built for its
## target, then test.bash against the build cicd.bash makes for that target, where the box has
## every tool in REMOTE_UNIX_NEEDS. Every box in the list runs. The lock knows both by name.
REMOTE_UNIX_HOSTS=("vmFreeBSD:bsdtest@vmFreeBSD" "vmDebARM64:tester@vmDebARM64")
declare -gA REMOTE_UNIX_TARGETS=([vmFreeBSD]="freebsd/amd64" [vmDebARM64]="linux/arm64")
## go for the suite's own builds; an older one fetches the toolchain go.mod names.
REMOTE_UNIX_NEEDS=(bash git go)
REMOTE_UNIX_DIR="gitsby/remote-tests"
## Unix boxes that also run the Go tests built for a Windows target, under Wine, after their own.
## Wine is not Windows, so this adds to the Windows box's run, and doesn't replace it. A box
## without wine skips it with a note. vmDebARM64 needs arm64.nobti on its kernel line for this.
declare -gA REMOTE_UNIX_WINE=([vmDebARM64]="windows/arm64")

## Stage 8: backup + publish to git (runs from repo root). The engine always
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
##		- 2026-08-19 JC: WINRES_CMD: the Windows resource check joins stage 1, and release.bash regenerates the resource with the version bump.
##		- 2026-08-19 JC: GO_TOOL_VERSIONS: the lint and audit tools ran at whatever version the box had, so a finding could appear or vanish with no change to the tree. Recorded and compared in stage 1, as a warning.
##		- 2026-08-26 JC: DOGFOOD_FALLBACK_DIR, for a box that has none of the shared dirs. It only applies to the target that box can run. The macOS share is one entry for both platforms.
##		- 2026-09-10 JC: BACKLOG_CHECK_CMD joins stage 1.
##		- 2026-09-14 JC: The demo gif renders from a build stamped with the newest release, so it changes only when what it shows does.
##		- 2026-09-15 JC: run-latest.ps1 joins the PowerShell lint.
##		- 2026-08-19 JC: The installer is back at the repo root, so its two files are linted again - the root install.bash under shellcheck, install.ps1 under a restored PSScriptAnalyzer glob. FreeBSD joins the release matrix, since it cross-builds for free and the installer would otherwise have nothing to offer a BSD.
##		- 2026-09-10 JC: BACKLOG_CHECK_CMD joins stage 1.
##		- 2026-09-14 JC: The demo comment names the build the demo really runs.
##		- 2026-09-28 JC: TOOL_VERSIONS records the six tools outside Go that shape a result. The parity comment no longer says --quick skips it.
##		- 2026-10-03 JC: macOS dogfood is one universal binary, so Intel Macs can run it too.
##		- 2026-10-03 JC: PS_LINT_SETTINGS: the PowerShell lint rules moved out of cicd.bash into a settings file.
##		- 2026-10-03 JC: The macOS release is one universal binary, in place of one per CPU.
##		- 2026-10-04 JC: Stage 7 runs the tests on a Mac and a Windows box. Publish is stage 8.
##		- 2026-10-04 JC: Stage 7 also runs them on a FreeBSD amd64 and a Linux arm64 box.
##		- 2026-10-04 JC: Every expansion braced, and shellcheck enforces it. The settings stay upper case.
##		- 2026-10-05 JC: REMOTE_UNIX_WINE: the Linux arm64 box also runs the windows/arm64 Go tests under Wine.
##		- 2026-10-10 JC: TOOL_VERSIONS records git, since an older one spawns more on a fetch. Every pinned tool is also what the --container image installs.
##		- 2026-10-10 JC: CICD_CONTAINER: the container is the default.
##		- 2026-10-18 JC: DOGFOOD_NATIVE_TARGET is gone. --quick dogfoods every target now, since each cross-build takes seconds.
##		- 2026-10-19 JC: PY_LINT_RULES, PY_AUDIT_DISTS and PIP_AUDIT_IGNORE: ruff's leak rules over the demo script, and pip-audit over what it imports. LEAKCHECK_*: the --leakcheck soak test. TOOL_VERSIONS records ruff and pip-audit.
##		- 2026-10-19 JC: --leakcheck runs CodeQL too, from a pinned bundle in the image, with CODEQL_IGNORE for findings set aside. TOOL_VERSIONS records it.
##		- 2026-10-19 JC: Notes the GOAMD64=v1 pin beside CGO_ENABLED=0.
##		- 2026-10-19 JC: Pillow 12.3.0, from the upstream wheel, and only fontTools is left on PIP_AUDIT_IGNORE. CodeQL's Python suite runs too, with its own bundle sum. DEMOGIF_TOOLS names the tools a demo render has to match.
##		- 2026-10-21 JC: Pillow 13.0.0, which fixes the advisories against 12.3.0. --no-fuzz skips pip-audit too.
##		- 2026-10-25 JC: Stage 7 tries b29w before vm925w, adds vmKt6m beside b26, and keeps each box's copy of the tree under its temp root. REMOTE_MAC_NEEDS.
