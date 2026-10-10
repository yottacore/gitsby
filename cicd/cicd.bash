#!/usr/bin/env bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'
#  shellcheck disable=2001  ## 'See if you can use ${variable//search/replace} instead.' Complains about good uses of sed.
#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes, use double quotes for that.' I know, and I often want an explicit '$'.
#  shellcheck disable=2034  ## 'variable appears unused.' Complains about valid use of variable indirection (e.g. later use of local -n var=$1)
#  shellcheck disable=2046  ## 'Quote to prevent word-splitting.' (OK for integers.)
#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2119  ## 'Use foo "$@" if function's $1 should mean script's $1.' Confusing and inapplicable.
#  shellcheck disable=2120  ## 'Foo references arguments, but none are ever passed.' Valid function argument overloading.
#  shellcheck disable=2128  ## 'Expanding an array without an index only gives the element in the index 0.' False hits on associative arrays.
#  shellcheck disable=2153  ## 'Possible misspelling.' False hits on vars assigned in the sourced config.bash.
#  shellcheck disable=2154  ## 'referenced but not assigned.' False hit on trap strings that assign the var they use (rc=$?).
#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary. For integers it's sometimes required to even come into existence for counters.
#  shellcheck disable=2162  ## 'read without -r will mangle backslashes.'
#  shellcheck disable=2178  ## 'Variable was used as an array but is now assigned a string.' False hits on associative arrays with e.g. 'local -n assocArray=$1'.
#  shellcheck disable=2181  ## 'Check exit code directly, not indirectly with $?.'
#  shellcheck disable=2317  ## 'Can't reach.' (I.e. an 'exit' is used for debugging - and makes an unusable visual mess.)
#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	- Purpose: Local CI/CD pipeline. Generic engine for a Go project;
##	  per-project settings live in config.bash.
##	- Stages (fail-fast, any error aborts before the next stage):
##	   0. remote sync (fast-forward from origin before anything is built or tested)
##	   1. lint (gofmt + go vet + staticcheck + golangci-lint, and shellcheck over the pipeline's own scripts)
##	   2. build + unit tests (go test) + regression tests (cicd/test.bash against the compiled binary)
##	   3. fuzz + security (cicd/fuzz.bash) + govulncheck + spawn counts; skipped under --quick
##	   4. backwards compatibility (cicd/parity.bash: this build vs the frozen v2.1.0 one)
##	   5. dogfood (cross-build every target and install each to its first existing dir)
##	   6. demo gif (fake-terminal render; skipped under --quick)
##	   7. Remote tests (cicd/remote-tests.bash, over ssh on the Mac, the Unix boxes and whichever Windows box is free; skipped under --quick)
##	   8. backup + publish to git (runs from repo root)
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -q, --quiet         quiet + unattended (no prompt); the publish step runs quiet too
##	   -y, --yes           unattended (no prompt) but not quiet
##	   -m, --message MSG   publish hands-off with this commit message (no editor)
##	       --msg MSG       alias for --message
##	   --no-sync           skip the remote sync stage
##	   --no-lint           skip the lint stage
##	   --no-test           skip the regression test stage
##	   --no-fuzz           skip the fuzz + security stage
##	   --no-parity         skip the backwards-compatibility comparison
##	   --no-dogfood        skip installing the build(s) locally
##	   --no-demogif        skip regenerating the demo gif
##	   --no-remote         skip the remote tests
##	   --no-publish        skip the git backup + publish stage
##	   --quick             skip the slow stages (fuzz, demo gif, remote tests)
##	   --container         run stages 1-4 in the pinned image from cicd/container/Dockerfile
##	   --gate              fast pre-push gate: every lint check and go test; no sync, build, suites, prompt or log
##	   --install-hook      install the git pre-push hook that runs --gate on each commit pushed to main
##	   -h, --help          show this help
##	- If neither -q/-y nor -m is given, the run prompts once for a commit message
##	  (blank = git editor; Ctrl+C aborts the whole run), then finishes unattended.
##	- Reuse: copy the cicd/ directory into another project and edit config.bash.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}. On macOS, install one with 'brew install bash' and put it first on PATH." >&2; exit 1
fi
set -Eeuo pipefail

## Find the repo root and load project config.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"   ## the git repo root (cicd/..)
export PATH="${HOME}/.local/bin:${PATH}"   ## user-prefix npm tools (markdownlint) win
source "${here}/config.bash"
source "${here}/utility/include/gfs-rotate.bash"       ## gfs_rotate() for the artifact dirs
source "${here}/utility/include/go-test-lines.bash"    ## fGoTestLines(), shared with remote-tests.bash
cd "${root}"
stamp="$(date +%Y%m%d-%H%M%S)"

## Output helpers: fEcho / fEcho_Clean, blank-collapsing.
## fEcho "msg" -> "[ msg ]" status line; fEcho_Clean "msg" -> plain line, and a
## bare call collapses repeated blanks. fSection draws the leading-blank + rule
## letterbox before a major stage header; fDie prints a fatal line and exits, and
## fUsage refuses the command line.
## printf, not 'echo -e': a commit message the user typed passes through here, and echo -e
## would animate any backslash escape or ANSI sequence in it. bin/gitsby does the same.
declare -i __wasLastEchoBlank=0
fEcho_ResetBlankCounter(){ __wasLastEchoBlank=0; }
fEcho_Clean(){
	if [[ -n "${1:-}" ]]; then printf '%s\n' "$*"; __wasLastEchoBlank=0
	elif ((! __wasLastEchoBlank)); then echo; __wasLastEchoBlank=1; fi
}
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force(){ fEcho_ResetBlankCounter; fEcho "$*"; }
__letterbox="••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"
fSection(){ fEcho_Clean; fEcho_Clean "${__letterbox}"; fEcho "$*"; [[ "${stagePause:-0}" == 0 ]] || sleep "${stagePause}"; }
fDie(){ { fEcho_Force "FAILED: $*"; } >&2; exit 1; }
fUsage(){ fEcho_Clean "$*" >&2; exit 2; }

## Parse options.
assumeYes=0; quiet=0; quick=0; doSync=1; doLint=1; doTest=1; doFuzz=1; doParity=1; doRemote=1; cliMessage=""
gate=0; installHook=0; stageOpts=(); container=0
while (($#)); do case "$1" in
	-q|--quiet)               quiet=1; assumeYes=1; shift ;;   ## quiet + unattended; publish runs quiet too
	-y|--yes)                 assumeYes=1; shift ;;
	--no-sync)                doSync=0; stageOpts+=("$1"); shift ;;
	--no-lint)                doLint=0; stageOpts+=("$1"); shift ;;
	--no-test)                doTest=0; stageOpts+=("$1"); shift ;;
	--no-fuzz)                doFuzz=0; stageOpts+=("$1"); shift ;;
	--no-parity)              doParity=0; stageOpts+=("$1"); shift ;;
	--no-dogfood)             DOGFOOD_TARGETS=(); stageOpts+=("$1"); shift ;;
	--no-demogif)             DO_DEMOGIF=0; stageOpts+=("$1"); shift ;;
	--no-remote)              doRemote=0; stageOpts+=("$1"); shift ;;
	--no-publish)             GIT_PUBLISH=(); stageOpts+=("$1"); shift ;;
	## Cross-building three platforms is the slow part of a run, not the fuzz and the gif -
	## so the flag whose job is skipping the slow parts has to skip that too. The native
	## target stays, since the dogfooded binary is what the next hand-run uses.
	--quick)                  quick=1; doFuzz=0; DO_DEMOGIF=0; doRemote=0; DOGFOOD_TARGETS=("${DOGFOOD_NATIVE_TARGET}"); stageOpts+=("$1"); shift ;;
	--message=*|--msg=*|-m=*) cliMessage="${1#*=}"; stageOpts+=("${1%%=*}"); shift ;;
	-m|--message|--msg)       cliMessage="${2-}"; stageOpts+=("$1"); shift; (($#)) && shift ;;
	## pre-push.bash looks for this arm's literal text to tell a commit that has a gate from
	## one cut before it existed, so keep the spelling.
	--gate)                   gate=1; assumeYes=1; shift ;;
	--install-hook)           installHook=1; shift ;;
	--container)              container=1; shift ;;
	-h|--help)                sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) fUsage "unknown option: ${1} (try --help)" ;;
esac; done

## Both run a fixed thing, so a stage option beside either would read as taking effect when it
## cannot. Refused rather than ignored.
if ((gate && installHook)); then fUsage "--gate and --install-hook are separate runs; give one."; fi
if ((${#stageOpts[@]})); then
	if ((gate)); then
		fUsage "--gate runs a fixed set of checks and takes no stage options (got: ${stageOpts[*]})"
	elif ((installHook)); then
		fUsage "--install-hook installs the hook and takes no stage options (got: ${stageOpts[*]})"
	fi
fi
if ((container)) && ((gate || installHook)); then fUsage "--container goes with a full run, not --gate or --install-hook."; fi
if ((container)) && [[ -n "${GITSBY_CICD_IN_CONTAINER:-}" ]]; then fUsage "already in the container; --container would start another."; fi
if ((installHook)); then exec "${here}/utility/pre-push.bash" --install; fi

## Brief beat after each stage header so the cheap fast stages stay readable.
## Off for unattended runs (-q/-y) where nobody is watching.
stagePause=0.4; ((assumeYes)) && stagePause=0

## The same reasoning, passed on to the demo generator. Keyed on -q, not on unattended: -y is
## documented as unattended-but-not-quiet. The suites, parity and spawn counts never get it. One
## line per check is how a failure's neighbors get read, and -q runs are the usual ones.
declare -a harnessQuiet=(); ((quiet)) && harnessQuiet=("-q")

## What the plan and the stage lines say about a stage that --quick skipped.
skipNote="(skipped)"; quickNote=""
if ((quick)); then skipNote="(skipped --quick)"; quickNote=" (--quick)"; fi

## Publish commit message: -m wins, then config, then a default when unattended.
## Empty -> publish interactively (git commit opens an editor); when interactive
## we offer to capture a message at the preflight prompt below.
publishMsg=""
if   [[ -n "${cliMessage}" ]];              then publishMsg="${cliMessage}"
elif [[ -n "${PUBLISH_AUTO_MESSAGE:-}" ]]; then publishMsg="${PUBLISH_AUTO_MESSAGE}"
elif ((assumeYes));                       then publishMsg="${APP_NAME} CI/CD ${stamp}"
fi

trap 'rc=$?; printf "\n[ CICD ABORTED (exit %s) at line %s: %s ]\n" "${rc}" "${LINENO}" "${BASH_COMMAND}" >&2; exit "${rc}"' ERR

## Expand the configured shell-file globs once (nullglob, restored after).
shellFiles=(); shellWarnFiles=()
hadNullglob=0; shopt -q nullglob && hadNullglob=1; shopt -s nullglob
for g in "${SHELL_LINT_GLOBS[@]}"; do for f in ${g}; do [[ -f "${f}" ]] && shellFiles+=("${f}"); done; done
for g in "${SHELL_LINT_WARN_GLOBS[@]:-}"; do for f in ${g}; do [[ -f "${f}" ]] && shellWarnFiles+=("${f}"); done; done
((hadNullglob)) || shopt -u nullglob

## Stage 1's body and stage 2's unit tests, as functions so that --gate runs the same code a
## full run does. Two copies would drift, and the hook would pass what the pipeline stops.
## Where 'go install' puts a tool, in the order go resolves them. gen-winres looks the same way,
## so a tool one of them finds is not skipped by the other.
fGoToolPath(){ local found="" dir="" goPath=""
	found="$( command -v "$1" 2>/dev/null || true )"
	goPath="$(go env GOPATH 2>/dev/null || true)"
	for dir in "$(go env GOBIN 2>/dev/null || true)" "${goPath:+${goPath%%:*}/bin}"; do
		if [[ -z "${found}" && -n "${dir}" && -x "${dir}/$1" ]]; then found="${dir}/$1"; fi
	done
	echo "${found}"
}
## The version of each tool in TOOL_VERSIONS, however it spells it. Nothing when it is missing.
fToolVersion(){
	case "$1" in
		shellcheck)       shellcheck --version 2>/dev/null | awk '$1=="version:"{print $2}' ;;
		markdownlint)     markdownlint --version 2>/dev/null || npx --no-install markdownlint --version 2>/dev/null ;;
		## Stage 1's lint already asked, so pwsh need not start again.
		PSScriptAnalyzer) if [[ -n "${psaAsked:-}" ]]; then echo "${psaVersion}"; else pwsh -NoProfile -Command '$m = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1; if ($m) { $m.Version.ToString() }' 2>/dev/null; fi ;;
		gifsicle)         gifsicle --version 2>/dev/null | awk 'NR==1{print $NF}' ;;
		Pillow)           python3 -c 'import PIL; print(PIL.__version__)' 2>/dev/null ;;
		strace)           strace -V 2>/dev/null | awk 'NR==1{print $NF}' ;;
		git)              git --version 2>/dev/null | awk '{print $3}' ;;
	esac
}

fStageLint(){
	local f g hadNullglob n mdFiles psFiles psList psScript psRc psOut q pyCache toolDrift toolSpec toolName toolWant toolPath toolHave unformatted winresStatus
	((${#shellFiles[@]})) || fDie "no shell files matched SHELL_LINT_GLOBS"
	for f in "${shellFiles[@]}"; do
		bash -n "${f}" || fDie "syntax error: ${f}"
	done
	fEcho "OK: bash -n (${#shellFiles[@]} file(s))"
	shellcheck --version >/dev/null 2>&1 || fDie "shellcheck not installed"
	shellcheck "${shellFiles[@]}"
	fEcho "OK: shellcheck clean"
	## Legacy files: report findings without gating (the refactor retires this list).
	if ((${#shellWarnFiles[@]})); then
		for f in "${shellWarnFiles[@]}"; do
			bash -n "${f}" || fDie "syntax error: ${f}"
			n="$(shellcheck "${f}" 2>/dev/null | grep -c "^In " || true)"
			if ((n)); then fEcho "WARNING: ${n} shellcheck finding(s) in legacy ${f} (report-only until the refactor)"
			else fEcho "OK: legacy ${f} clean"; fi
		done
	fi
	if ((${#MD_LINT_GLOBS[@]})); then
		mdFiles=()
		hadNullglob=0; shopt -q nullglob && hadNullglob=1; shopt -s nullglob
		for g in "${MD_LINT_GLOBS[@]}"; do for f in ${g}; do [[ -f "${f}" ]] && mdFiles+=("${f}"); done; done
		((hadNullglob)) || shopt -u nullglob
		if command -v markdownlint >/dev/null 2>&1; then
			markdownlint "${mdFiles[@]}"
			fEcho "OK: markdownlint clean (${#mdFiles[@]} file(s))"
		elif npx --no-install markdownlint --version >/dev/null 2>&1; then
			npx --no-install markdownlint "${mdFiles[@]}"
			fEcho "OK: markdownlint clean (${#mdFiles[@]} file(s))"
		else
			fEcho "WARNING: markdownlint skipped (not installed: npm install -g markdownlint-cli)"
		fi
	fi
	if [[ -n "${PY_LINT_FILES+x}" ]] && ((${#PY_LINT_FILES[@]})); then
		## At the head of an && list a failure neither stopped the run nor fired the trap. The
		## cache goes to a folder of our own, since py_compile writes one beside each file.
		pyCache="$(mktemp -d)"
		if ! PYTHONPYCACHEPREFIX="${pyCache}" python3 -m py_compile "${PY_LINT_FILES[@]}"; then
			rm -rf -- "${pyCache:?}"
			fDie "py_compile"
		fi
		rm -rf -- "${pyCache:?}"
		fEcho "OK: py_compile (${#PY_LINT_FILES[@]} file(s))"
	fi
	if [[ -n "${PS_LINT_GLOBS+x}" ]] && ((${#PS_LINT_GLOBS[@]})); then
		psFiles=()
		hadNullglob=0; shopt -q nullglob && hadNullglob=1; shopt -s nullglob
		for g in "${PS_LINT_GLOBS[@]}"; do for f in ${g}; do [[ -f "${f}" ]] && psFiles+=("${f}"); done; done
		((hadNullglob)) || shopt -u nullglob
		if ((${#psFiles[@]})); then
			## One pwsh for every file, the module probe and its version: each start costs about a
			## second. A file that fails to parse is reported from ParseFile and not analyzed, so
			## a Severity filter in the settings can't hide it. Exit 3 is a missing module.
			psList=""; q="'"
			for f in "${psFiles[@]}"; do psList+="${psList:+,}${q}${f//${q}/${q}${q}}${q}"; done
			psScript="\$ErrorActionPreference = 'Stop'; \$m = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1; if (-not \$m) { exit 3 }; 'PSScriptAnalyzer-version ' + \$m.Version; \$bad = 0"
			psScript+="; foreach (\$f in @(${psList})) { \$parseErrors = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path \$PWD \$f), [ref]\$null, [ref]\$parseErrors)"
			psScript+="; if (\$parseErrors) { \$bad++; \$parseErrors | Select-Object @{Name='ScriptName'; Expression={\$f}}, @{Name='Line'; Expression={\$_.Extent.StartLineNumber}}, ErrorId, Message | Format-Table -AutoSize | Out-String -Width 200 | Write-Host; continue }"
			psScript+="; \$r = Invoke-ScriptAnalyzer -Path \$f -Settings ${q}${PS_LINT_SETTINGS//${q}/${q}${q}}${q}; if (\$r) { \$bad++; \$r | Format-Table -AutoSize | Out-String -Width 200 | Write-Host } }; exit [int](\$bad -gt 0)"
			psRc=0
			if ! command -v pwsh >/dev/null 2>&1; then psRc=3
			else
				[[ -f "${PS_LINT_SETTINGS}" ]] || fDie "PSScriptAnalyzer settings not found: ${PS_LINT_SETTINGS}"
				psOut="$(pwsh -NoProfile -NonInteractive -Command "${psScript}" </dev/null)" || psRc=$?
				psaVersion="$(sed -n 's/^PSScriptAnalyzer-version //p' <<< "${psOut}")"; psaAsked=1
				[[ -z "${psOut}" ]] || sed '/^PSScriptAnalyzer-version /d' <<< "${psOut}"
			fi
			case "${psRc}" in
				0) fEcho "OK: PSScriptAnalyzer clean, 5.1-compatible (${#psFiles[@]} file(s))" ;;
				3) fEcho "WARNING: PSScriptAnalyzer skipped (pwsh + PSScriptAnalyzer module not both installed)" ;;
				*) fDie "PSScriptAnalyzer findings, listed above" ;;
			esac
		fi
	fi
	## gofmt is the arbiter of format, vet gates, staticcheck gates when installed.
	## Keyed off the module, not a glob - the tools walk it themselves. A missing
	## toolchain is fatal now rather than a warning: it is what builds the product.
	command -v go >/dev/null 2>&1 || fDie "go toolchain not installed - nothing in this pipeline can run without it"
	## Which version of each tool is about to gate this run. A tool that moved on its own is
	## the usual reason a finding appears - or stops appearing - on a tree nobody touched.
	## Warned about only: this pipeline installs nothing, and a version skew is a thing to
	## know rather than a reason to refuse to build.
	## A tool that is missing altogether is warned about by the step that needs it.
	toolDrift=()
	for toolSpec in "${GO_TOOL_VERSIONS[@]}"; do
		toolName="${toolSpec%%=*}"; toolWant="${toolSpec#*=}"
		toolPath="$(fGoToolPath "${toolName}")"
		[[ -n "${toolPath}" ]] || continue
		toolHave="$( go version -m "${toolPath}" 2>/dev/null | awk '$1=="mod"{print $3; exit}' || true )"
		[[ "${toolHave}" == "${toolWant}" ]] || toolDrift+=( "${toolName} ${toolHave:-unknown} (recorded ${toolWant})" )
	done
	for toolSpec in "${TOOL_VERSIONS[@]}"; do
		toolName="${toolSpec%%=*}"; toolWant="${toolSpec#*=}"
		toolHave="$(fToolVersion "${toolName}" || true)"
		[[ -z "${toolHave}" || "${toolHave}" == "${toolWant}" ]] || toolDrift+=( "${toolName} ${toolHave} (recorded ${toolWant})" )
	done
	((${#toolDrift[@]} == 0)) || fEcho "WARNING: tool versions differ from the recorded set: ${toolDrift[*]}"
	unformatted="$(cd "${root}/${GO_MODULE_DIR}" && gofmt -l .)"
	[[ -z "${unformatted}" ]] || fDie "gofmt wants to reformat: ${unformatted}"
	## Same core budget as the builds: BUILD_JOBS caps the go tool's workers, and
	## GOMAXPROCS caps the analysis threads inside each one.
	(cd "${root}/${GO_MODULE_DIR}" && GOMAXPROCS="${BUILD_JOBS}" go vet -p "${BUILD_JOBS}" ./...) || fDie "go vet findings"
	fEcho "OK: gofmt + go vet clean"
	if command -v staticcheck >/dev/null 2>&1; then
		(cd "${root}/${GO_MODULE_DIR}" && GOMAXPROCS="${BUILD_JOBS}" staticcheck ./...) || fDie "staticcheck findings"
		fEcho "OK: staticcheck clean"
	else
		fEcho "WARNING: staticcheck skipped (not installed: go install honnef.co/go/tools/cmd/staticcheck@latest)"
	fi
	## The rest of the set - dropped errors, shadowed builtins, naming - configured in
	## src-go/.golangci.yml. Gates when installed, like staticcheck above.
	if command -v golangci-lint >/dev/null 2>&1; then
		(cd "${root}/${GO_MODULE_DIR}" && golangci-lint run --concurrency "${BUILD_JOBS}" ./...) || fDie "golangci-lint findings"
		fEcho "OK: golangci-lint clean"
	else
		fEcho "WARNING: golangci-lint skipped (not installed: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest)"
	fi
	## The committed Windows resource, against what the newest tag would generate. It is linked
	## into published bytes, so an edited icon or description that nobody regenerated would ship
	## silently. Probe-gated like the two above.
	winresStatus=0
	"${WINRES_CMD[@]}" --check -q || winresStatus=$?
	case "${winresStatus}" in
		0) fEcho "OK: windows resource current" ;;
		3) fEcho "WARNING: windows resource check skipped (not installed: go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.5.0)" ;;
		*) fDie "windows resource is stale" ;;
	esac
	## Two backlog rules the review rounds kept leaking through: every open review item
	## names where it came from, and a suite check removed on this branch is named in the
	## backlog. Both were broken by hand before, and neither showed anywhere.
	"${BACKLOG_CHECK_CMD[@]}" -q || fDie "backlog check failed (see above)"
	fEcho "OK: backlog check"
}
fUnitTests(){
	local log="" rc=0
	log="$(mktemp "${TMPDIR:-/tmp}/gitsby-gotest.XXXXXX")"
	## -race costs little on a tree with no goroutines and pays the day one appears. -v is for
	## the line per test below; the rest of what it prints is shown only when something failed.
	(cd "${root}/${GO_MODULE_DIR}" && GOMAXPROCS="${BUILD_JOBS}" go test -race -p "${BUILD_JOBS}" -v ./...) >"${log}" 2>&1 || rc=$?
	fGoTestLines "${log}" "${root}/${GO_MODULE_DIR}"
	if ((rc)); then
		grep -vE '^ *(=== (RUN|PAUSE|CONT|NAME)|--- (PASS|SKIP))' "${log}" || true
		rm -f -- "${log:?}"
		fDie "go test failures"
	fi
	rm -f -- "${log:?}"
	fEcho "OK: go test"
}

## Dogfood destinations, resolved once. Per target, the first configured dir that exists and
## is writable; empty means the stage will skip that target with a warning. The dest array is
## found by name (DOGFOOD_DESTS_<GOOS>_<GOARCH>, upper-cased), so adding a target is a config
## edit and nothing here.
case "${OSTYPE:-}" in
	linux*)          hostGoos="linux"   ;;
	darwin*)         hostGoos="darwin"  ;;
	msys*|cygwin*)   hostGoos="windows" ;;
	freebsd*)        hostGoos="freebsd" ;;
	*)               hostGoos=""        ;;
esac
declare -A dogfoodDest=() dogfoodAll=()
for t in "${DOGFOOD_TARGETS[@]:-}"; do
	[[ -n "${t}" ]] || continue
	destVar="DOGFOOD_DESTS_${t^^}"; destVar="${destVar//\//_}"
	declare -n _dests="${destVar}"
	destCands=("${_dests[@]:-}")
	## The fallback belongs to whichever target this box could actually run.
	if [[ -n "${DOGFOOD_FALLBACK_DIR:-}" && "${t%%/*}" == "${hostGoos}" ]]; then destCands+=("${DOGFOOD_FALLBACK_DIR}"); fi
	foundDest=""; for cand in "${destCands[@]:-}"; do [[ -d "${cand}" && -w "${cand}" ]] && { foundDest="${cand}"; break; }; done
	dogfoodDest["${t}"]="${foundDest}"
	dogfoodAll["${t}"]="${destCands[*]:-}"
	unset -n _dests
done

## Display helpers for the plan block: 'linux/amd64' -> 'linux', and the dotted leader that
## lines every value up on the same column as the fixed labels below.
fPlanOS(){ case "${1%%/*}" in darwin) echo macos ;; *) echo "${1%%/*}" ;; esac ;}
fPlanLine(){ local -r dots="........................"; local -i n=$(( 20 - ${#1} )); ((n < 0)) && n=0; fEcho_Clean "${1} ${dots:0:n}: ${2}" ;}

## --gate: what the pre-push hook runs against the commit being pushed. The stages it leaves
## out are the slow ones, and the ones that change something: a fetch, a build, an install, a push.
if ((gate)); then
	fEcho_Clean
	fEcho_Clean "${APP_NAME} gate: every lint check, then the unit tests"
	fEcho_Clean "Repo root ...........: ${root}"
	fSection "Gate 1/2  Lint"
	fStageLint
	fSection "Gate 2/2  Unit tests"
	fUnitTests
	fSection "${APP_NAME} gate: passed."
	fEcho_Clean
	exit 0
fi

## --container: the image's versions come from config.bash, and its tag hashes the recipe plus
## those, so a bumped version can't run on the old image.
if ((container)); then
	command -v docker >/dev/null 2>&1 || fDie "--container needs docker"
	containerRecipe="${here}/container/Dockerfile"
	[[ -f "${containerRecipe}" ]] || fDie "missing ${containerRecipe}"
	containerArgs=(--build-arg "VER_go=${GO_RELEASE_TOOLCHAIN#go}")
	for toolSpec in "${GO_TOOL_VERSIONS[@]}" "${TOOL_VERSIONS[@]}"; do
		toolName="${toolSpec%%=*}"; toolName="VER_${toolName//-/_}"
		grep -qxF "ARG ${toolName}" "${containerRecipe}" || fDie "config.bash pins ${toolSpec%%=*}, and the container recipe has no ARG ${toolName} for it"
		containerArgs+=(--build-arg "${toolName}=${toolSpec#*=}")
	done
	containerImage="${APP_NAME}-cicd:$( { cat "${containerRecipe}"; printf '%s\n' "${containerArgs[@]}"; } | git hash-object --stdin | cut -c1-12 )"
	## The same stages as here, minus everything that needs this box.
	containerRun=(-y --no-sync --no-dogfood --no-demogif --no-remote --no-publish)
	((quiet))    && containerRun[0]=-q
	((doLint))   || containerRun+=(--no-lint)
	((doTest))   || containerRun+=(--no-test)
	((doFuzz))   || containerRun+=(--no-fuzz)
	((doParity)) || containerRun+=(--no-parity)
fi

## Preflight: show the plan with resolved paths, then confirm.

fEcho_Clean
fEcho_Clean "${APP_NAME} local CI/CD"
fEcho_Clean
fEcho_Clean "Repo root ...........: ${root}"
if ((container)); then
	fEcho_Clean "Container ...........: stages 1-4 in ${containerImage}"
fi
if ((doLint)); then
	fEcho_Clean "Lint ................: gofmt + go vet + staticcheck, shellcheck on ${#shellFiles[@]} shell file(s)  (+ golangci-lint, markdownlint, py_compile, PSScriptAnalyzer, windows resource if available)"
else
	fEcho_Clean "Lint ................: (skipped)"
fi
if ((doTest)) && [[ -f "${TEST_CMD[0]:-}" ]]; then
	fEcho_Clean "Tests ...............: ${TEST_CMD[*]}"
elif ((doTest)); then
	fEcho_Clean "Tests ...............: (no harness yet: ${TEST_CMD[0]:-cicd/test.bash})"
else
	fEcho_Clean "Tests ...............: (skipped)"
fi
if ((doTest)); then
	fEcho_Clean "Go build ............: ${GO_MODULE_DIR} -> ${GO_MODULE_DIR}/${EXE_NAME} (the suite's subject)"
fi
if ((doFuzz)) && [[ -f "${FUZZ_CMD[0]:-}" ]]; then
	fEcho_Clean "Fuzz + security .....: ${FUZZ_CMD[*]}"
elif ((doFuzz)); then
	fEcho_Clean "Fuzz + security .....: (no harness yet: ${FUZZ_CMD[0]:-cicd/fuzz.bash})"
else
	fEcho_Clean "Fuzz + security .....: ${skipNote}"
fi
if ((! doParity)); then
	fEcho_Clean "Compatibility .......: (skipped)"
elif [[ -f "${PARITY_CMD[0]:-}" ]]; then
	fEcho_Clean "Compatibility .......: ${PARITY_CMD[*]} (this build vs legacy/bin)"
else
	fEcho_Clean "Compatibility .......: (no comparison harness: ${PARITY_CMD[0]:-cicd/parity.bash})"
fi
if ((${#DOGFOOD_TARGETS[@]})); then
	for t in "${DOGFOOD_TARGETS[@]}"; do
		exe="${EXE_NAME}"; [[ "${t}" == windows/* ]] && exe="${EXE_NAME}.exe"
		if [[ -n "${dogfoodDest[${t}]}" ]]; then fPlanLine "Dogfood ($(fPlanOS "${t}"))" "build ${t} -> ${dogfoodDest[${t}]}/${exe}"
		else fPlanLine "Dogfood ($(fPlanOS "${t}"))" "<none of: ${dogfoodAll[${t}]} exists - will skip>"; fi
	done
else
	fEcho_Clean "Dogfood .............: (disabled)"
fi
if ((DO_DEMOGIF)) && [[ -f "${DEMOGIF_SCENARIO}" ]]; then
	fEcho_Clean "Demo gif ............: ${DEMOGIF_CMD[*]} -> ${DEMOGIF_OUT}"
elif ((DO_DEMOGIF)); then
	fEcho_Clean "Demo gif ............: (no scenario yet: ${DEMOGIF_SCENARIO})"
else
	fEcho_Clean "Demo gif ............: ${skipNote}"
fi
if ((doRemote)) && [[ -f "${REMOTE_TEST_CMD[0]:-}" ]]; then
	fEcho_Clean "Remote tests ........: ${REMOTE_TEST_CMD[*]} (${REMOTE_MAC_HOSTS[*]%%:*} ${REMOTE_UNIX_HOSTS[*]%%:*}; first free of ${REMOTE_WINDOWS_HOSTS[*]%%:*})"
elif ((doRemote)); then
	fEcho_Clean "Remote tests ........: (no harness yet: ${REMOTE_TEST_CMD[0]:-cicd/remote-tests.bash})"
else
	fEcho_Clean "Remote tests ........: ${skipNote}"
fi
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "Publish (last) ......: (disabled)"
elif [[ -n "${publishMsg}" ]]; then
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (hands-off: \"${publishMsg}\")"
else
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (will prompt for message; blank = editor)"
fi
fEcho_Clean
fEcho_Clean "Fail-fast: any error aborts before the next stage."
fEcho_Clean

if ((! assumeYes)); then
	## Capture the commit message up front so the run can finish unattended. This
	## is the natural place to bail on the common (publish) path - Ctrl+C here
	## aborts; there is no separate "Proceed? [y/N]" (removed to cut friction).
	if ((${#GIT_PUBLISH[@]})) && [[ -z "${publishMsg}" ]]; then
		read -r -p "Publish commit message (blank = editor; Ctrl+C aborts): " typedMessage
		fEcho_ResetBlankCounter
		[[ -n "${typedMessage}" ]] && publishMsg="${typedMessage}"
	fi
fi

## Tee the rest of the run (all stages) to a gitignored log so warnings from any
## stage can be reviewed after the fact. Rotate the prior (closed) logs first.
## Inside the container the outer run's log already has all of it.
if [[ -n "${LINT_LOG_DIR:-}" && -z "${GITSBY_CICD_IN_CONTAINER:-}" ]] && mkdir -p "${root}/${LINT_LOG_DIR}" 2>/dev/null; then
	gfs_rotate "${root}/${LINT_LOG_DIR}" run log >/dev/null 2>&1 || true
	exec > >(tee "${root}/${LINT_LOG_DIR}/run_${stamp}.log") 2>&1
	## Wait for tee to drain on exit, else the shell prompt returns mid-flush and
	## the last output lands after it (looks like the prompt "came back").
	teePid=$!
	trap 'exec 1>&- 2>&-; wait "${teePid}" 2>/dev/null' EXIT
fi

## Stage 0: remote sync. The publish stage pulls too, but that is after everything
## has been built and tested - so a change merged upstream meanwhile would be pushed
## having been validated by nothing. Refreshing first means the rest of the run tests
## the tree that is actually going out. Publish keeps its own pull as the late guard.
fSection "0/8  Remote sync"
if ((! doSync)); then
	fEcho_Clean "remote sync skipped"
elif ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
	## No upstream is an ordinary state for a brand-new branch, not a reason to stop.
	fEcho_Clean "no upstream for this branch - nothing to sync"
elif ! git fetch --quiet 2>/dev/null; then
	## Offline is the other ordinary state. Warn and build what is here.
	fEcho_Clean "WARNING: can't reach origin - building without refreshing"
else
	## Left is behind, right is ahead: what origin has that we don't, and the reverse.
	counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo "0	0")"
	behind="${counts%%[[:space:]]*}"; ahead="${counts##*[[:space:]]}"
	if   ((behind == 0)); then fEcho_Clean "up to date with origin (${ahead} to publish)"
	elif ((ahead > 0));   then fDie "diverged from origin: ${ahead} local, ${behind} remote. Reconcile before building."
	else
		## Only behind, so this can only be a fast-forward. --autostash carries a dirty
		## tree over it rather than refusing, and puts it back afterward.
		fEcho_Clean "fast-forwarding ${behind} commit(s) from origin"
		git merge --ff-only --autostash '@{u}' || fDie "fast-forward from origin failed"
	fi
fi

## Version stamped into every build this run. Dev builds carry what describe says; a
## release injects the clean one. Read after the sync, which can move HEAD. -dirty
## because a run that publishes builds source whose commit stage 8 hasn't made yet.
goVersion="$(git describe --tags --always --dirty --match 'v*' 2>/dev/null || echo 0.0.0)"
## Build number, as minutes since 2000 in Crockford base32 - the binary does the encoding,
## this only hands it the seconds. Taken from the commit rather than the clock so the same
## source builds to the same bytes; a wall-clock stamp would mean nobody, including us,
## could ever rebuild a published asset to its published checksum.
goBuildEpoch="$(git log -1 --format=%ct 2>/dev/null || echo 0)"

## --container: stages 1-4 run in the pinned image, against this same tree. It is mounted at
## the same path, so paths in the output and a worktree's .git file still resolve. The Go
## caches live in a named volume, or every run would download and build from nothing.
if ((container)); then
	fSection "Container"
	if docker image inspect "${containerImage}" >/dev/null 2>&1; then
		fEcho_Clean "image ${containerImage}"
	else
		fEcho_Clean "building ${containerImage}"
		docker build -q -t "${containerImage}" "${containerArgs[@]}" "${here}/container" >/dev/null || fDie "image build failed"
		## The one it replaces is close to 2 GB nobody runs again.
		while IFS= read -r oldImage; do
			if [[ -z "${oldImage}" || "${oldImage}" == "${containerImage}" ]]; then continue; fi
			if docker rmi "${oldImage}" >/dev/null 2>&1; then fEcho_Clean "removed ${oldImage}"
			else fEcho_Clean "kept ${oldImage} (in use)"; fi
		done < <(docker image ls "${containerImage%%:*}" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
	fi
	containerMounts=(-v "${root}:${root}" -v "${APP_NAME}-cicd-cache:/cache" --tmpfs "/tmp:rw,exec,mode=1777")
	gitCommon="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
	if [[ -n "${gitCommon}" && "${gitCommon}" != "${root}/"* ]]; then containerMounts+=(-v "${gitCommon}:${gitCommon}"); fi
	fEcho_Clean "runs cicd.bash ${containerRun[*]}"
	docker run --rm --init --user "$(id -u):$(id -g)" "${containerMounts[@]}" -w "${root}" \
		"${containerImage}" bash "${root}/cicd/cicd.bash" "${containerRun[@]}" \
		|| fDie "the run in the container failed (above)"
	fEcho "OK: stages 1-4 in the container"
	doLint=0; doTest=0; doFuzz=0; doParity=0; ranWhere="ran in the container"
fi

## Stage 1: lint. gofmt/vet/staticcheck over the module, then bash -n and shellcheck
## over the pipeline's own scripts and the installer (gating - never an auto-formatter:
## those are hand-formatted on purpose). markdownlint, py_compile and PSScriptAnalyzer
## are probe-gated extras.
fSection "1/8  Lint"
if ((! doLint)); then
	fEcho_Clean "lint ${ranWhere:-skipped}"
else
	fStageLint
fi

## Stage 2: build, then the regression suite against what was just built. The build is
## the native one; the cross-builds happen at dogfood, where they have somewhere to go.
## Dev builds carry the describe version; release builds inject the clean one.
fSection "2/8  Build + regression tests"
if ((! doTest)); then
	fEcho_Clean "build + tests ${ranWhere:-skipped}"
else
	(cd "${root}/${GO_MODULE_DIR}" && CGO_ENABLED=0 \
		go build "${GO_BUILD_FLAGS[@]}" -p "${BUILD_JOBS}" -ldflags "${GO_LDFLAGS_COMMON} -X main.version=${goVersion#v} -X main.buildEpoch=${goBuildEpoch}" -o "${EXE_NAME}" .) \
		|| fDie "go build failed"
	fEcho "OK: go build (v${goVersion#v})"
	## The unit tests come before the suite below: they answer in milliseconds and
	## cover the parsing and matching the suite can only reach through a built binary.
	fUnitTests
	if [[ -f "${TEST_CMD[0]:-}" ]]; then
		"${TEST_CMD[@]}"
		fEcho "OK: tests passed"
	else
		fEcho_Clean "no test harness (${TEST_CMD[0]:-cicd/test.bash})"
	fi
fi

## Stage 3: fuzz + security (adversarial input against our parsing, plus checks
## of what we shell out to). Slow, so skipped under --quick. Same lands-later
## policy as the tests.
fSection "3/8  Fuzz + security"
if ((! doFuzz)); then
	fEcho_Clean "fuzz + security ${ranWhere:-skipped${quickNote}}"
elif [[ -f "${FUZZ_CMD[0]:-}" ]]; then
	"${FUZZ_CMD[@]}"
	fEcho "OK: fuzz + security passed"
else
	fEcho_Clean "no fuzz harness (${FUZZ_CMD[0]:-cicd/fuzz.bash})"
fi
## Coverage-guided fuzzing of the pure parsers, briefly. Their seed corpus already ran
## with 'go test' in stage 2; this hunts a little past it each run. One target per
## invocation is go's rule, and a crasher lands in src-go/testdata/fuzz/ as evidence.
if ((doFuzz)); then
	for fuzzTarget in $(cd "${root}/${GO_MODULE_DIR}" && go test -list 'Fuzz.*' . 2>/dev/null | grep '^Fuzz' || true); do
		(cd "${root}/${GO_MODULE_DIR}" && GOMAXPROCS="${BUILD_JOBS}" go test -run '^$' -fuzz "^${fuzzTarget}\$" -fuzztime 5s -parallel "${BUILD_JOBS}" . >/dev/null) \
			|| fDie "fuzzing found a crasher in ${fuzzTarget} (reproducer under ${GO_MODULE_DIR}/testdata/fuzz/)"
		## The test ID sits at the end of the func line, as '// [<id>]'.
		fuzzId="$(sed -n "s|^func ${fuzzTarget}(.*// \(\[[0-9A-Za-z]*\]\)[[:space:]]*\$|\1 |p" "${root}/${GO_MODULE_DIR}"/*_test.go 2>/dev/null || true)"
		fEcho_Clean "  ok: ${fuzzId}${fuzzTarget}"
	done
	fEcho "OK: native fuzz targets"
fi
## With no third-party dependencies the standard library is the only library code there is
## to check - and it is linked into every binary we publish. Probe-gated like staticcheck;
## it runs even under --quick, because it is a lookup rather than a workload.
if [[ -n "${ranWhere:-}" ]]; then
	:
elif command -v govulncheck >/dev/null 2>&1; then
	(cd "${root}/${GO_MODULE_DIR}" && govulncheck ./...) || fDie "govulncheck findings"
	fEcho "OK: govulncheck clean"
else
	fEcho "WARNING: govulncheck skipped (not installed: go install golang.org/x/vuln/cmd/govulncheck@latest)"
fi
## The profiling half, and deliberately not a sampling profile: this program is blocked on
## git for effectively all of its wall clock, so a flamegraph has no leaders in it. What
## costs anything is how often we fork git, and that is what regresses silently.
if ((doFuzz)) && [[ -f "${SPAWN_COUNT_CMD[0]:-}" ]]; then
	"${SPAWN_COUNT_CMD[@]}" || fDie "spawn counts regressed"
	fEcho "OK: spawn counts"
fi

## Stage 4: backwards compatibility. The behavioral suite asks "is this correct?" of one
## build at a time, so it passes while this build and the frozen one quietly disagree about
## the same input - which is what every port defect that reached users actually was. This
## asks the other question: do they ANSWER the same? Self-skips once legacy/ is gone.
fSection "4/8  Backwards compatibility"
if ((! doParity)); then
	fEcho_Clean "compatibility comparison ${ranWhere:-skipped}"
elif [[ -f "${PARITY_CMD[0]:-}" ]]; then
	"${PARITY_CMD[@]}"
	fEcho "OK: this build answers as the frozen one does"
else
	fEcho_Clean "no comparison harness (${PARITY_CMD[0]:-cicd/parity.bash})"
fi

## Stage 5: dogfood. Cross-build each configured target and copy it to the first existing,
## writable dir in that target's list. No sudo fallback on purpose - an unwritable dest is a
## warning, not an unattended privilege escalation. A cross-build failure is fatal: it means
## the tree stopped being portable, which is worth finding here rather than at a release.
fSection "5/8  Dogfood"
## Builds target $1 (goos/goarch) to the file $2. Stage 7 builds the Mac one this way too, so
## the Mac tests run against the same build dogfood installs.
fCrossBuild(){
	local target="$1" out="$2" arch part
	local -a arches parts=()
	## darwin/universal is both Mac CPUs, built apart and joined.
	arches=("${target##*/}"); [[ "${target}" == darwin/universal ]] && arches=(amd64 arm64)
	for arch in "${arches[@]}"; do
		part="${out}"; ((${#arches[@]} == 1)) || part="${out}-${arch}"
		(cd "${root}/${GO_MODULE_DIR}" && CGO_ENABLED=0 GOOS="${target%%/*}" GOARCH="${arch}" \
			go build "${GO_BUILD_FLAGS[@]}" -p "${BUILD_JOBS}" -ldflags "${GO_LDFLAGS_COMMON} -X main.version=${goVersion#v} -X main.buildEpoch=${goBuildEpoch}" -o "${part}" .) \
			|| fDie "go build failed for ${target%%/*}/${arch}"
		parts+=("${part}")
	done
	if ((${#parts[@]} > 1)); then
		"${root}/cicd/utility/macho-universal.bash" "${out}" "${parts[@]}" || fDie "could not join the ${target} builds"
		rm -f -- "${parts[@]}"
	fi
}
dogfoodDone=0
if ((! ${#DOGFOOD_TARGETS[@]})); then
	fEcho_Clean "dogfood disabled"
else
	for t in "${DOGFOOD_TARGETS[@]}"; do
		exe="${EXE_NAME}"; [[ "${t}" == windows/* ]] && exe="${EXE_NAME}.exe"
		if [[ -z "${dogfoodDest[${t}]}" ]]; then
			fEcho "WARNING: no ${t} dogfood dest exists/writable (${dogfoodAll[${t}]}); skipping"
			continue
		fi
		## Built into the module dir under the target's own name, so the native binary the
		## suite just ran against is not overwritten by a build that cannot run here.
		out="${root}/${GO_MODULE_DIR}/${EXE_NAME}-${t//\//-}"
		fCrossBuild "${t}" "${out}"
		cp -f "${out}" "${dogfoodDest[${t}]}/${exe}"
		chmod +x "${dogfoodDest[${t}]}/${exe}"
		rm -f -- "${out:?}"
		fEcho "OK: installed (${t}) -> ${dogfoodDest[${t}]}/${exe}"
		dogfoodDone=1
	done
fi
((dogfoodDone)) || fEcho_Clean "dogfood: nothing installed"

## Stage 6: demo gif. Types the scenario into a fake terminal, runs each command
## against a build of its own, stamped with the newest release, renders the
## animated loop. A failure is a warning, never a stop. When the render differs
## from the committed copy, a timestamped original is kept (GFS-pruned) out of
## tree, then landed in-repo.
fSection "6/8  Demo gif"
if ((! DO_DEMOGIF)); then
	fEcho_Clean "demo gif skipped${quickNote}"
elif [[ ! -f "${DEMOGIF_SCENARIO}" ]]; then
	fEcho_Clean "no demo scenario (${DEMOGIF_SCENARIO})"
else
	demogifOut="${root}/${DEMOGIF_OUT}"
	demogifTmp="${demogifOut}.new"
	mkdir -p "$(dirname "${demogifOut}")"
	## Every command prints a banner naming its build, and a build stamped with the commit put a
	## new one on camera at every commit, so the whole gif was replaced on every run. The demo's
	## own build carries the newest release instead - the version and build number that release's
	## published binary prints - so the gif changes only when what it shows does.
	demoVersion="0.0.0"; demoBuildEpoch=""
	demoTags="$(git -c versionsort.suffix=- tag --sort=-v:refname --list 'v*' 2>/dev/null || true)"
	demoTag="${demoTags%%$'\n'*}"
	if [[ "${demoTag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([A-Za-z0-9.-]+)?$ ]]; then
		demoVersion="${demoTag#v}"
		demoBuildEpoch="$(git log -1 --format=%ct "${demoTag}^{commit}" 2>/dev/null || true)"
	elif [[ -n "${demoTag}" ]]; then
		fEcho "WARNING: the newest v* tag '${demoTag}' is not a version, so the demo build is stamped 0.0.0"
	fi
	demogifBin="${root}/${GO_MODULE_DIR}/${EXE_NAME}-demo"
	if ! (cd "${root}/${GO_MODULE_DIR}" && CGO_ENABLED=0 \
		go build "${GO_BUILD_FLAGS[@]}" -p "${BUILD_JOBS}" -ldflags "${GO_LDFLAGS_COMMON} -X main.version=${demoVersion} -X main.buildEpoch=${demoBuildEpoch}" -o "${demogifBin}" .); then
		fEcho "WARNING: demo build failed, so no demo gif was rendered (continuing)"
	elif (cd "${root}" && python3 "${DEMOGIF_CMD[@]}" ${harnessQuiet[@]+"${harnessQuiet[@]}"} --out "${demogifTmp}" --bin "${demogifBin}"); then
		if [[ -n "${DEMOGIF_OPT_CMD[*]:-}" ]] && command -v "${DEMOGIF_OPT_CMD[0]}" >/dev/null 2>&1; then
			demogifWas=$(stat -c%s "${demogifTmp}")
			if "${DEMOGIF_OPT_CMD[@]}" "${demogifTmp}" -o "${demogifTmp}.opt" 2>/dev/null; then
				mv -f "${demogifTmp}.opt" "${demogifTmp}"
				fEcho_Clean "optimized: $((demogifWas / 1024)) -> $(( $(stat -c%s "${demogifTmp}") / 1024 )) KiB"
			else
				rm -f -- "${demogifTmp:?}.opt"
				fEcho_Clean "${DEMOGIF_OPT_CMD[0]}: failed, keeping the raw render"
			fi
		fi
		if [[ -f "${demogifOut}" ]] && cmp -s "${demogifTmp}" "${demogifOut}"; then
			rm -f -- "${demogifTmp:?}"
			fEcho "OK: demo gif unchanged"
		else
			## Keep the new original out of tree (GFS-pruned), then land it in the repo.
			mkdir -p "${DEMOGIF_ARCHIVE_DIR}"
			cp -f "${demogifTmp}" "${DEMOGIF_ARCHIVE_DIR}/demo_${stamp}.gif"
			gfs_rotate "${DEMOGIF_ARCHIVE_DIR}" demo gif >/dev/null 2>&1 || true
			mv -f "${demogifTmp}" "${demogifOut}"
			fEcho "OK: demo gif regenerated"
		fi
	else
		rm -f -- "${demogifTmp:?}"
		fEcho "WARNING: demo gif generation failed (continuing)"
	fi
	rm -f -- "${demogifBin:?}"
fi

## Stage 7: the Go tests on a Mac, a Windows box and the other Unix boxes, and the regression
## suite on the Mac and the Unix boxes against the build for each. The Linux arm64 box also runs
## the windows/arm64 Go tests under Wine. Nothing else runs the tests on
## those platforms, and Windows-only breaks went unnoticed for weeks before this. A box that is off, unreachable or taken by someone else
## is skipped with a note rather than waited for. Slow, so skipped under --quick.
fSection "7/8  Remote tests"
if ((! doRemote)); then
	fEcho_Clean "Remote tests skipped${quickNote}"
elif [[ ! -f "${REMOTE_TEST_CMD[0]:-}" ]]; then
	fEcho_Clean "no remote test harness (${REMOTE_TEST_CMD[0]:-cicd/remote-tests.bash})"
else
	remoteBin="${root}/${GO_MODULE_DIR}/${EXE_NAME}-darwin-universal"
	fCrossBuild darwin/universal "${remoteBin}"
	remoteArgs=(--mac-bin "${remoteBin}"); remoteBins=("${remoteBin}")
	mapfile -t remoteTargets < <(printf '%s\n' "${REMOTE_UNIX_TARGETS[@]}" | sort -u)
	for t in "${remoteTargets[@]}"; do
		[[ -n "${t}" ]] || continue
		remoteBins+=("${root}/${GO_MODULE_DIR}/${EXE_NAME}-${t/\//-}")
		fCrossBuild "${t}" "${remoteBins[-1]}"
		remoteArgs+=(--bin "${t}" "${remoteBins[-1]}")
	done
	remoteRc=0
	"${REMOTE_TEST_CMD[@]}" "${remoteArgs[@]}" || remoteRc=$?
	rm -f -- "${remoteBins[@]}"
	((remoteRc == 0)) || fDie "Remote tests failed (see above)"
	fEcho "OK: Remote tests"
fi

## Stage 8: backup + publish.
fSection "8/8  Backup + publish"
## Always run the publisher quiet: cicd already gave the initial prompt, so skip
## its redundant continue-prompt. With no message it still lets git open the editor.
pubFlags=(--quiet)
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "publish disabled"
elif [[ -n "${publishMsg}" ]]; then
	## Hands-off: the publisher fills the empty commit message from -m so `git
	## commit` won't open an editor.
	fEcho_Clean "hands-off publish (commit message: \"${publishMsg}\")"
	"${GIT_PUBLISH[@]}" "${pubFlags[@]}" -m "${publishMsg}"
	fEcho "OK: published"
else
	"${GIT_PUBLISH[@]}" "${pubFlags[@]}"
	fEcho "OK: published"
fi

fSection "${APP_NAME} CI/CD: done."
fEcho_Clean


##	History:
##		- 2026-07-22 JC: Created. Generic engine + config.bash for a Bash-script project, adapted from the sister pipeline; lint/tests/fuzz/dogfood/demo-gif/publish stages, -q/-m/--quick flags, tee'd run log.
##		- 2026-08-17 JC: Stage 2 builds the go port before the tests, so the suite's go leg runs against this tree; dev builds carry the git-describe version via -ldflags. A missing toolchain warns and lets the leg skip itself.
##		- 2026-08-17 JC: Stage 1 lints the go tree: gofmt (list mode, gating) and go vet, plus staticcheck when installed. Keyed off src-go existing rather than globs, so there is nothing to mirror in the Windows settings yet.
##		- 2026-08-18 JC: Go-specific, seven stages. The go toolchain is required rather than probed, the build gates, and the PowerShell lint block is gone with the scripts. Backwards compatibility became its own stage instead of a tail on the tests, and dogfood cross-builds every configured target rather than copying one script.
##		- 2026-08-19 JC: PSScriptAnalyzer is back in stage 1, probe-gated as before. The installer for Windows is the one piece of PowerShell that still ships, and it was going out unlinted.
##		- 2026-08-19 JC: golangci-lint joins stage 1 and go test joins stage 2, both alongside what was already there. The unit tests cover the parsing and matching that previously needed a built binary and a throwaway repo to reach.
##		- 2026-08-19 JC: PSScriptAnalyzer also checks the installer against Windows PowerShell 5.1 syntax. The installer supports 5.1 now, and nothing gated that.
##		- 2026-08-19 JC: Stage 1 checks the committed Windows resource against the newest tag. The .exe carries an icon and version details now, and the resource that gives it them is a checked-in file that nothing else would notice going stale.
##		- 2026-08-19 JC: --quick narrows dogfood to the native target, which is the slow part it was supposed to be skipping. Every build site shares one set of flags (-buildvcs=false above all, without which the published assets can never be rebuilt to their published checksums) and half the cores. Stage 3 gained govulncheck and the spawn counts; the three harnesses take -q from the engine.
##		- 2026-08-21 JC: The harnesses get -q only when the run is quiet, since -y is unattended but not quiet. go vet, staticcheck and golangci-lint keep to the build's core budget, go test runs with -race, and stage 3 fuzzes the pure parsers for a few seconds each.
##		- 2026-08-26 JC: Every build carries a build number taken from the commit date. Dogfood falls back to ~/.local/bin, for the target this box can run, when no shared dir exists.
##		- 2026-09-10 JC: Stage 1 runs backlog-check.bash: open review items carry an Origin line, and a suite check removed on the branch has to be named in the backlog. Two decisions had been reversed by deleting the check that encoded them, with nothing written down.
##		- 2026-09-14 JC: --gate runs every lint check and the unit tests and nothing else, for the pre-push hook that --install-hook puts in place. Stage 1 and the unit tests became functions, so the gate and a full run share one copy of each.
##		- 2026-09-14 JC: The demo gif renders from a build of its own, stamped with the newest release rather than the commit, and -q reaches its generator. The banner every command prints had put a new version on camera at every commit, so the gif was replaced on nearly every run.
##		- 2026-09-15 JC: A failed py_compile stops the run. At the head of an && list it neither stopped the run nor fired the trap.
##		- 2026-09-15 JC: The build version is read after the remote sync, and says -dirty for uncommitted source. Read at startup, it could name the commit before a fast-forward, and a publishing run's builds named the commit before the one holding their source.
##		- 2026-09-26 JC: The regression and fuzz suites print a line per check under -q too, and each native fuzz target gets one.
##		- 2026-09-26 JC: Parity and spawn counts print a line per check under -q too.
##		- 2026-09-27 JC: Each native fuzz target's line carries its test ID.
##		- 2026-09-27 JC: The Go unit tests print a line per test, with its test ID. Their full output shows only on a failure.
##		- 2026-09-28 JC: The tool version check covers six tools outside Go, and finds a Go tool where go install put it when that is not on PATH.
##		- 2026-10-03 JC: macOS dogfood is a universal binary, both Mac CPUs built and joined, so Intel Macs can run it too.
##		- 2026-10-03 JC: PowerShell lint is one pwsh for every file, with its rules in PSScriptAnalyzerSettings.psd1. A file that fails to parse fails the lint on its own.
##		- 2026-10-04 JC: Stage 7 runs the Go tests on a Mac and a Windows box, and the regression suite on the Mac against the universal build, through cicd/remote-tests.bash. A box that is off or taken is skipped, not waited for. Full runs only. Publish is stage 8.
##		- 2026-10-04 JC: Stage 7 also builds for each Unix box's target in config.bash, FreeBSD amd64 and Linux arm64 to start, and hands those builds to the harness.
##		- 2026-10-04 JC: Variables are camelCase, and the output helpers keep their state in two-underscore globals. The helpers come before the option loop, so a bad option goes through fUsage too. Every expansion braced, and shellcheck enforces it.
##		- 2026-10-10 JC: --container runs stages 1-4 in an image built from cicd/container/Dockerfile, with the versions config.bash pins. A pinned tool the recipe doesn't take stops the run. The tool version check knows git.
