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

##	- Purpose: Local CI/CD pipeline. Generic engine for a Bash-script project;
##	  per-project settings live in config.bash.
##	- Stages (fail-fast, any error aborts before the next stage):
##	   1. lint (bash -n + shellcheck gating; markdownlint + py_compile + PSScriptAnalyzer if available)
##	   2. regression tests (cicd/test.bash, once it exists)
##	   3. fuzz + security (cicd/fuzz.bash, once it exists; skipped under --quick)
##	   4. dogfood (install the script(s) to the first existing preferred dir)
##	   5. demo gif (fake-terminal render; skipped under --quick)
##	   6. backup + publish to git (runs from repo root)
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -q, --quiet         quiet + unattended (no prompt); the publish step runs quiet too
##	   -y, --yes           unattended (no prompt) but not quiet
##	   -m, --message MSG   publish hands-off with this commit message (no editor)
##	       --msg MSG       alias for --message
##	   --no-lint           skip the lint stage
##	   --no-test           skip the regression test stage
##	   --no-fuzz           skip the fuzz + security stage
##	   --no-dogfood        skip installing the script(s) locally
##	   --no-demogif        skip regenerating the demo gif
##	   --no-publish        skip the git backup + publish stage
##	   --quick             skip the slow stages (fuzz, demo gif)
##	   -h, --help          show this help
##	- If neither -q/-y nor -m is given, the run prompts once for a commit message
##	  (blank = git editor; Ctrl+C aborts the whole run), then finishes unattended.
##	- Reuse: copy the cicd/ directory into another project and edit config.bash.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

## Find the repo root and load project config.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"   ## the git repo root (cicd/..)
export PATH="${HOME}/.local/bin:${PATH}"   ## user-prefix npm tools (markdownlint) win
source "${here}/config.bash"
source "${here}/utility/include/gfs-rotate.bash"       ## gfs_rotate() for the artifact dirs
cd "${root}"
stamp="$(date +%Y%m%d-%H%M%S)"

## Parse options.
assume_yes=0; quiet=0; quick=0; do_lint=1; do_test=1; do_fuzz=1; cli_message=""
while (($#)); do case "$1" in
	-q|--quiet)               quiet=1; assume_yes=1; shift ;;   ## quiet + unattended; publish runs quiet too
	-y|--yes)                 assume_yes=1; shift ;;
	--no-lint)                do_lint=0; shift ;;
	--no-test)                do_test=0; shift ;;
	--no-fuzz)                do_fuzz=0; shift ;;
	--no-dogfood)             DOGFOOD_BASH_DESTS=(); DOGFOOD_PWSH_DESTS=(); shift ;;
	--no-demogif)             DO_DEMOGIF=0; shift ;;
	--no-publish)             GIT_PUBLISH=(); shift ;;
	--quick)                  quick=1; do_fuzz=0; DO_DEMOGIF=0; shift ;;
	--message=*|--msg=*|-m=*) cli_message="${1#*=}"; shift ;;
	-m|--message|--msg)       cli_message="${2-}"; shift; (($#)) && shift ;;
	-h|--help)                sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done

## Brief beat after each stage header so the cheap fast stages stay readable.
## Off for unattended runs (-q/-y) where nobody is watching.
stage_pause=0.4; ((assume_yes)) && stage_pause=0

## Publish commit message: -m wins, then config, then a default when unattended.
## Empty -> publish interactively (git commit opens an editor); when interactive
## we offer to capture a message at the preflight prompt below.
publish_msg=""
if   [[ -n "$cli_message" ]];              then publish_msg="$cli_message"
elif [[ -n "${PUBLISH_AUTO_MESSAGE:-}" ]]; then publish_msg="$PUBLISH_AUTO_MESSAGE"
elif ((assume_yes));                       then publish_msg="${APP_NAME} CI/CD ${stamp}"
fi

## Output helpers: fEcho / fEcho_Clean, blank-collapsing.
## fEcho "msg" -> "[ msg ]" status line; fEcho_Clean "msg" -> plain line, and a
## bare call collapses repeated blanks. fSection draws the leading-blank + rule
## letterbox before a major stage header; fDie prints a fatal line and exits.
declare -i _wasLastEchoBlank=0
fEcho_ResetBlankCounter(){ _wasLastEchoBlank=0; }
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force(){ fEcho_ResetBlankCounter; fEcho "$*"; }
_letterbox="••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"
fSection(){ fEcho_Clean; fEcho_Clean "${_letterbox}"; fEcho "$*"; [[ "${stage_pause:-0}" == 0 ]] || sleep "${stage_pause}"; }
fDie(){ { fEcho_Force "FAILED: $*"; } >&2; exit 1; }
trap 'rc=$?; printf "\n[ CICD ABORTED (exit %s) at line %s: %s ]\n" "$rc" "$LINENO" "$BASH_COMMAND" >&2; exit $rc' ERR

## Expand the configured shell-file globs once (nullglob, restored after).
shell_files=(); shell_warn_files=()
_ng=0; shopt -q nullglob && _ng=1; shopt -s nullglob
for g in "${SHELL_LINT_GLOBS[@]}"; do for f in $g; do [[ -f "$f" ]] && shell_files+=("$f"); done; done
for g in "${SHELL_LINT_WARN_GLOBS[@]:-}"; do for f in $g; do [[ -f "$f" ]] && shell_warn_files+=("$f"); done; done
((_ng)) || shopt -u nullglob

## Preflight: show the plan with resolved paths, then confirm.
bash_dest=""; for d in "${DOGFOOD_BASH_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { bash_dest="$d"; break; }; done
pwsh_dest=""; for d in "${DOGFOOD_PWSH_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { pwsh_dest="$d"; break; }; done

fEcho_Clean
fEcho_Clean "${APP_NAME} local CI/CD"
fEcho_Clean
fEcho_Clean "Repo root ...........: ${root}"
if ((do_lint)); then
	fEcho_Clean "Lint ................: shellcheck on ${#shell_files[@]} shell file(s) + ${#shell_warn_files[@]} legacy report-only  (+ markdownlint, py_compile, PSScriptAnalyzer if available)"
else
	fEcho_Clean "Lint ................: (skipped)"
fi
if ((do_test)) && [[ -f "${TEST_CMD[0]:-}" ]]; then
	fEcho_Clean "Tests ...............: ${TEST_CMD[*]}"
elif ((do_test)); then
	fEcho_Clean "Tests ...............: (no harness yet: ${TEST_CMD[0]:-cicd/test.bash})"
else
	fEcho_Clean "Tests ...............: (skipped)"
fi
if ((do_fuzz)) && [[ -f "${FUZZ_CMD[0]:-}" ]]; then
	fEcho_Clean "Fuzz + security .....: ${FUZZ_CMD[*]}"
elif ((do_fuzz)); then
	fEcho_Clean "Fuzz + security .....: (no harness yet: ${FUZZ_CMD[0]:-cicd/fuzz.bash})"
else
	fEcho_Clean "Fuzz + security .....: $( ((quick)) && echo '(skipped --quick)' || echo '(skipped)')"
fi
if ((${#DOGFOOD_BASH_DESTS[@]})); then
	if [[ -n "$bash_dest" ]]; then fEcho_Clean "Dogfood (bash) ......: overwrite ${bash_dest}/${EXE_NAME}"
	else fEcho_Clean "Dogfood (bash) ......: <none of: ${DOGFOOD_BASH_DESTS[*]} exists - will skip>"; fi
else
	fEcho_Clean "Dogfood (bash) ......: (disabled)"
fi
if [[ -n "${DOGFOOD_PWSH_SRC:-}" ]]; then
	if [[ -n "$pwsh_dest" ]]; then fEcho_Clean "Dogfood (pwsh) ......: overwrite ${pwsh_dest}/$(basename "${DOGFOOD_PWSH_SRC}")"
	else fEcho_Clean "Dogfood (pwsh) ......: <none of: ${DOGFOOD_PWSH_DESTS[*]} exists - will skip>"; fi
else
	fEcho_Clean "Dogfood (pwsh) ......: (no pwsh port yet)"
fi
if ((DO_DEMOGIF)) && [[ -f "${DEMOGIF_SCENARIO}" ]]; then
	fEcho_Clean "Demo gif ............: ${DEMOGIF_CMD[*]} -> ${DEMOGIF_OUT}"
elif ((DO_DEMOGIF)); then
	fEcho_Clean "Demo gif ............: (no scenario yet: ${DEMOGIF_SCENARIO})"
else
	fEcho_Clean "Demo gif ............: $( ((quick)) && echo '(skipped --quick)' || echo '(skipped)')"
fi
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "Publish (last) ......: (disabled)"
elif [[ -n "$publish_msg" ]]; then
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (hands-off: \"${publish_msg}\")"
else
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (will prompt for message; blank = editor)"
fi
fEcho_Clean
fEcho_Clean "Fail-fast: any error aborts before the next stage."
fEcho_Clean

if ((! assume_yes)); then
	## Capture the commit message up front so the run can finish unattended. This
	## is the natural place to bail on the common (publish) path - Ctrl+C here
	## aborts; there is no separate "Proceed? [y/N]" (removed to cut friction).
	if ((${#GIT_PUBLISH[@]})) && [[ -z "$publish_msg" ]]; then
		read -r -p "Publish commit message (blank = editor; Ctrl+C aborts): " m
		fEcho_ResetBlankCounter
		[[ -n "$m" ]] && publish_msg="$m"
	fi
fi

## Tee the rest of the run (all stages) to a gitignored log so warnings from any
## stage can be reviewed after the fact. Rotate the prior (closed) logs first.
if [[ -n "${LINT_LOG_DIR:-}" ]] && mkdir -p "${root}/${LINT_LOG_DIR}" 2>/dev/null; then
	gfs_rotate "${root}/${LINT_LOG_DIR}" run log >/dev/null 2>&1 || true
	exec > >(tee "${root}/${LINT_LOG_DIR}/run_${stamp}.log") 2>&1
	## Wait for tee to drain on exit, else the shell prompt returns mid-flush and
	## the last output lands after it (looks like the prompt "came back").
	tee_pid=$!
	trap 'exec 1>&- 2>&-; wait "${tee_pid}" 2>/dev/null' EXIT
fi

## Stage 1: lint. bash -n then shellcheck over every first-party shell file
## (gating - never an auto-formatter: bash is hand-formatted on purpose).
## markdownlint and py_compile are probe-gated extras.
fSection "1/6  Lint"
if ((! do_lint)); then
	fEcho_Clean "lint skipped"
else
	((${#shell_files[@]})) || fDie "no shell files matched SHELL_LINT_GLOBS"
	for f in "${shell_files[@]}"; do
		bash -n "$f" || fDie "syntax error: $f"
	done
	fEcho "OK: bash -n (${#shell_files[@]} file(s))"
	shellcheck --version >/dev/null 2>&1 || fDie "shellcheck not installed"
	shellcheck "${shell_files[@]}"
	fEcho "OK: shellcheck clean"
	## Legacy files: report findings without gating (the refactor retires this list).
	if ((${#shell_warn_files[@]})); then
		for f in "${shell_warn_files[@]}"; do
			bash -n "$f" || fDie "syntax error: $f"
			n="$(shellcheck "$f" 2>/dev/null | grep -c "^In " || true)"
			if ((n)); then fEcho "WARNING: ${n} shellcheck finding(s) in legacy ${f} (report-only until the refactor)"
			else fEcho "OK: legacy ${f} clean"; fi
		done
	fi
	if ((${#MD_LINT_GLOBS[@]})); then
		md_files=()
		_ng=0; shopt -q nullglob && _ng=1; shopt -s nullglob
		for g in "${MD_LINT_GLOBS[@]}"; do for f in $g; do [[ -f "$f" ]] && md_files+=("$f"); done; done
		((_ng)) || shopt -u nullglob
		if command -v markdownlint >/dev/null 2>&1; then
			markdownlint "${md_files[@]}"
			fEcho "OK: markdownlint clean (${#md_files[@]} file(s))"
		elif npx --no-install markdownlint --version >/dev/null 2>&1; then
			npx --no-install markdownlint "${md_files[@]}"
			fEcho "OK: markdownlint clean (${#md_files[@]} file(s))"
		else
			fEcho "WARNING: markdownlint skipped (not installed: npm install -g markdownlint-cli)"
		fi
	fi
	if [[ -n "${PY_LINT_FILES+x}" ]] && ((${#PY_LINT_FILES[@]})); then
		python3 -m py_compile "${PY_LINT_FILES[@]}" && rm -rf "${root}/cicd/utility/__pycache__"
		fEcho "OK: py_compile (${#PY_LINT_FILES[@]} file(s))"
	fi
	if [[ -n "${PS_LINT_GLOBS+x}" ]] && ((${#PS_LINT_GLOBS[@]})); then
		ps_files=()
		_ng=0; shopt -q nullglob && _ng=1; shopt -s nullglob
		for g in "${PS_LINT_GLOBS[@]}"; do for f in $g; do [[ -f "$f" ]] && ps_files+=("$f"); done; done
		((_ng)) || shopt -u nullglob
		if ((${#ps_files[@]})); then
			if pwsh -NoProfile -Command "Get-Command Invoke-ScriptAnalyzer" >/dev/null 2>&1; then
				for f in "${ps_files[@]}"; do
					pwsh -NoProfile -Command "\$r = Invoke-ScriptAnalyzer -Path '${f}' -Severity Error,Warning,Information; \$r | Format-Table -AutoSize | Out-String -Width 200 | Write-Host; exit @(\$r).Count" || fDie "PSScriptAnalyzer findings in ${f}"
				done
				fEcho "OK: PSScriptAnalyzer clean (${#ps_files[@]} file(s))"
			else
				fEcho "WARNING: PSScriptAnalyzer skipped (pwsh + PSScriptAnalyzer module not both installed)"
			fi
		fi
	fi
fi

## Stage 2: regression tests. The harness lands with the bin/gitsby refactor;
## until then this stage reports itself absent rather than pretending to pass.
fSection "2/6  Regression tests"
if ((! do_test)); then
	fEcho_Clean "tests skipped"
elif [[ -f "${TEST_CMD[0]:-}" ]]; then
	"${TEST_CMD[@]}"
	fEcho "OK: tests passed"
else
	fEcho_Clean "no test harness yet (${TEST_CMD[0]:-cicd/test.bash} - lands with the bin/gitsby refactor)"
fi

## Stage 3: fuzz + security (adversarial input against our parsing, plus checks
## of what we shell out to). Slow, so skipped under --quick. Same lands-later
## policy as the tests.
fSection "3/6  Fuzz + security"
if ((! do_fuzz)); then
	fEcho_Clean "fuzz + security skipped$( ((quick)) && echo ' (--quick)')"
elif [[ -f "${FUZZ_CMD[0]:-}" ]]; then
	"${FUZZ_CMD[@]}"
	fEcho "OK: fuzz + security passed"
else
	fEcho_Clean "no fuzz harness (${FUZZ_CMD[0]:-cicd/fuzz.bash})"
fi

## Stage 4: dogfood. A script project's "release build" is the script itself;
## copy it over the first existing preferred dir. No sudo fallback on purpose -
## an unwritable dest is a warning, not an unattended privilege escalation.
fSection "4/6  Dogfood"
df_did=0
if ((${#DOGFOOD_BASH_DESTS[@]})); then
	if [[ -n "$bash_dest" ]]; then
		cp -f "${DOGFOOD_BASH_SRC}" "${bash_dest}/${EXE_NAME}"
		chmod +x "${bash_dest}/${EXE_NAME}"
		fEcho "OK: installed (bash) -> ${bash_dest}/${EXE_NAME}"
		df_did=1
	else
		fEcho "WARNING: no bash dogfood dest exists/writable (${DOGFOOD_BASH_DESTS[*]}); skipping"
	fi
fi
if [[ -n "${DOGFOOD_PWSH_SRC:-}" ]]; then
	if [[ -n "$pwsh_dest" ]]; then
		cp -f "${DOGFOOD_PWSH_SRC}" "${pwsh_dest}/"
		fEcho "OK: installed (pwsh) -> ${pwsh_dest}/$(basename "${DOGFOOD_PWSH_SRC}")"
		df_did=1
	else
		fEcho "WARNING: no pwsh dogfood dest exists/writable (${DOGFOOD_PWSH_DESTS[*]}); skipping"
	fi
else
	fEcho_Clean "pwsh: no port yet"
fi
((df_did)) || fEcho_Clean "dogfood: nothing installed"

## Stage 5: demo gif. Types the scenario into a fake terminal, runs each command
## against the dogfooded script, renders the animated loop. A failure is a
## warning, never a stop. When the render differs from the committed copy, a
## timestamped original is kept (GFS-pruned) out of tree, then landed in-repo.
fSection "5/6  Demo gif"
if ((! DO_DEMOGIF)); then
	fEcho_Clean "demo gif skipped$( ((quick)) && echo ' (--quick)')"
elif [[ ! -f "${DEMOGIF_SCENARIO}" ]]; then
	fEcho_Clean "no demo scenario (${DEMOGIF_SCENARIO})"
else
	demogif_out="${root}/${DEMOGIF_OUT}"
	demogif_tmp="${demogif_out}.new"
	mkdir -p "$(dirname "${demogif_out}")"
	if (cd "${root}" && python3 "${DEMOGIF_CMD[@]}" --out "${demogif_tmp}" --bin "${root}/${DOGFOOD_BASH_SRC}"); then
		if [[ -n "${DEMOGIF_OPT_CMD[*]:-}" ]] && command -v "${DEMOGIF_OPT_CMD[0]}" >/dev/null 2>&1; then
			demogif_was=$(stat -c%s "${demogif_tmp}")
			if "${DEMOGIF_OPT_CMD[@]}" "${demogif_tmp}" -o "${demogif_tmp}.opt" 2>/dev/null; then
				mv -f "${demogif_tmp}.opt" "${demogif_tmp}"
				fEcho_Clean "optimized: $((demogif_was / 1024)) -> $(( $(stat -c%s "${demogif_tmp}") / 1024 )) KiB"
			else
				rm -f "${demogif_tmp}.opt"
				fEcho_Clean "${DEMOGIF_OPT_CMD[0]}: failed, keeping the raw render"
			fi
		fi
		if [[ -f "${demogif_out}" ]] && cmp -s "${demogif_tmp}" "${demogif_out}"; then
			rm -f "${demogif_tmp}"
			fEcho "OK: demo gif unchanged"
		else
			## Keep the new original out of tree (GFS-pruned), then land it in the repo.
			mkdir -p "${DEMOGIF_ARCHIVE_DIR}"
			cp -f "${demogif_tmp}" "${DEMOGIF_ARCHIVE_DIR}/demo_${stamp}.gif"
			gfs_rotate "${DEMOGIF_ARCHIVE_DIR}" demo gif >/dev/null 2>&1 || true
			mv -f "${demogif_tmp}" "${demogif_out}"
			fEcho "OK: demo gif regenerated"
		fi
	else
		rm -f "${demogif_tmp}"
		fEcho "WARNING: demo gif generation failed (continuing)"
	fi
fi

## Stage 6: backup + publish.
fSection "6/6  Backup + publish"
## Always run the publisher quiet: cicd already gave the initial prompt, so skip
## its redundant continue-prompt. With no message it still lets git open the editor.
pub_flags=(--quiet)
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "publish disabled"
elif [[ -n "$publish_msg" ]]; then
	## Hands-off: the publisher fills the empty commit message from -m so `git
	## commit` won't open an editor.
	fEcho_Clean "hands-off publish (commit message: \"${publish_msg}\")"
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}" -m "${publish_msg}"
	fEcho "OK: published"
else
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}"
	fEcho "OK: published"
fi

fSection "${APP_NAME} CI/CD: done."
fEcho_Clean


##	History:
##		- 2026-07-22 JC: Created. Generic engine + config.bash for a Bash-script project, adapted from the sister pipeline; lint/tests/fuzz/dogfood/demo-gif/publish stages, -q/-m/--quick flags, tee'd run log.
