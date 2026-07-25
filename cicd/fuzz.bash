#!/usr/bin/env bash

##	Purpose:
##		- Adversarial fuzz + injection-safety for gitsby's OWN input surface: the
##		  command slot, options, and branch/message/version/pr arguments. Not
##		  upstream git - just what a hostile or fat-fingered user can hand gitsby.
##		- Three invariants, checked per vector, per implementation (bash always,
##		  pwsh when installed):
##		    1. No internal crash - no bash/pwsh error dump, exit stays a controlled 0/1.
##		    2. No shell/command injection - a canary side-effect never fires.
##		    3. Inputs that must be refused exit nonzero and leave the repo untouched.
##		- Run by cicd.bash stage 3, or standalone. Hermetic: throwaway repos, no net.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-fuzz.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

## Hermetic: no reliance on (or writes to) the user's git config, no prompts.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=fuzz GIT_AUTHOR_EMAIL=fuzz@fuzz
export GIT_COMMITTER_NAME=fuzz GIT_COMMITTER_EMAIL=fuzz@fuzz
export GIT_TERMINAL_PROMPT=0

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); echo "  ok: $*"; }
fFail(){ fail=$((fail+1)); echo "  FAIL: $*"; }

## An internal-error dump from either implementation. A clean validation refusal
## ("gitsby: <msg>", exit 1) matches none of these; an uncaught bash error, a
## non-0/1 exit dump, or a pwsh StrictMode/runtime fault does. The arg parser's
## "Reverse call stack:" line is a deliberate refusal, not a crash, so it's out.
_crashRe='unbound variable|: syntax error|bad substitution|command not found|integer expression expected|not a valid identifier|divide by zero|division by 0|bad array subscript|: line [0-9]+:|At line# |Command# \.\.\.|Err# \.\.\.|cannot be retrieved because it has not been set|Cannot index into a null|Attempted to divide by zero|Method invocation failed|Unable to find type'

_out=""; declare -i _code=0
## Run gitsby in a directory with the given args verbatim (no reshell of the
## vector), capturing merged output and exit code without tripping set -e.
fRun(){
	local -r dir="$1"; shift
	_out="$( { cd "${dir}" && "${gitsby}" "$@"; } </dev/null 2>&1 )" && _code=0 || _code=$?
}
_isCrash(){ grep -qE "${_crashRe}" <<< "${_out}" || ((_code >= 2)); }

## Must survive (accept or refuse - either is fine) without an internal crash.
fSurvive(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if _isCrash; then fFail "${desc} (exit ${_code})"; else fOk "${desc}"; fi; }
## Must refuse: nonzero exit, no crash.
fRefuse(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if _isCrash; then fFail "${desc}: crashed (exit ${_code})"
	elif ((_code == 0)); then fFail "${desc}: accepted, should refuse"
	else fOk "${desc}"; fi; }

## Fresh repo (bare origin + clone with one commit) under work/<name>.
fMakeRepo(){
	local -r dir="$1"
	git init --quiet --bare -b main "${dir}.git"
	git clone --quiet "${dir}.git" "${dir}" 2>/dev/null
	( cd "${dir}" && echo seed > seed.txt && git add --all \
		&& git commit --quiet -m seed && git push --quiet -u origin main )
}

## Vectors. None of these strings contain a _crashRe keyword, so a vector echoed
## back in gitsby's output can't self-trip the crash check.
## The single quotes are the point: these must reach gitsby as literal text, not
## expand here - that's what proves gitsby keeps them inert.
# shellcheck disable=SC2016
{
## Commands are matched case-insensitively (forgiving by design), so 'STATUS' is a
## valid alias of 'status' and doesn't belong here.
badCommands=( frobnicate status2 '..' './x' '123' 'a b' '-' '--' 'commit extra junk' )
badOptions=( --bogus -x -qx '--no-fetch=1' '--=v' -Z )
inject=( '$(touch CANARY_A)' '`touch CANARY_B`' ';touch CANARY_C' '&& touch CANARY_D'
         '| touch CANARY_E' '> CANARY_F' '$(touch CANARY_G)tail' '../CANARY_H' )
badBranch=( "${inject[@]}" 'a..b' 'has space' '-leadingdash' 'tilde~x' 'caret^x'
            'colon:x' 'ends.lock' '/leading' 'trailing/' 'back\slash' '?' '*' )
## 'v1.2.3' (leading v stripped) and 'X.Y.Z.W' (matches the optional suffix) are
## valid on purpose, so they belong nowhere near this refuse list.
badVersion=( not.a.version 1 1.2 'v.1.2' '1.2.3-' '-1.0.0' '$(touch CANARY_V)' 'x y' )
badPr=( abc 3.5 '$(touch CANARY_P)' 'x' 'ok' 'ok abc' 'ok 1 2' )
}

## The whole fuzz suite against whatever ${gitsby} points at.
fRunFuzz(){
	echo "fuzz: $1 (${gitsby})"
	local -r base="${work}/$1"
	mkdir -p "${base}"

	## Command slot: garbage first tokens are refused, never crash.
	local repo="${base}/cmd"; fMakeRepo "${repo}"
	local c
	for c in "${badCommands[@]}"; do fRefuse "command refused: '${c}'" "${repo}" -q "${c}"; done

	## Options: unknown ones refused in either slot; valid combos accepted.
	local o
	for o in "${badOptions[@]}"; do
		fRefuse "option refused (slot 1): '${o}'" "${repo}" -q "${o}" status
		fRefuse "option refused (slot 2): '${o}'" "${repo}" -q status "${o}"
	done
	fSurvive "valid combo -q -y status"        "${repo}" -q -y status
	fSurvive "valid combo -q --no-fetch status" "${repo}" -q --no-fetch status
	fSurvive "valid combo -y -q listbr"        "${repo}" -y -q listbr

	## Branch names: injection + malformed refs are refused before any action.
	local b
	for b in "${badBranch[@]}"; do
		fRefuse "newbr refuses: '${b}'" "${repo}" -q newbr "${b}"
		fRefuse "gobr refuses: '${b}'"  "${repo}" -q gobr  "${b}"
	done

	## Commit messages: anything goes in a message, but it stays inert data. Each
	## needs a real change to reach 'git commit'; unique content guarantees one.
	local repo2="${base}/msg"; fMakeRepo "${repo2}"
	local -i i=0 m
	for m in "${!inject[@]}"; do
		echo "change ${i}" > "${repo2}/seed.txt"; i=$((i + 1))
		fSurvive "commit message inert: '${inject[m]}'" "${repo2}" -q commit "${inject[m]}"
	done

	## Versions and PR numbers: malformed values refused (release fetches first,
	## which is local here; pr rejects before any network).
	local repo3="${base}/ver"; fMakeRepo "${repo3}"
	local v p
	for v in "${badVersion[@]}"; do fRefuse "release refuses version: '${v}'" "${repo3}" -q release "${v}"; done
	for p in "${badPr[@]}";      do fRefuse "pr refuses: '${p}'"              "${repo3}" -q pr "${p}"; done

	## Long and odd input: must not crash. Branch is refused, message accepted.
	local long; long="$(printf 'x%.0s' {1..5000})"
	fRefuse  "long branch refused"  "${repo3}" -q newbr "${long}"
	echo odd > "${repo2}/seed.txt"
	fSurvive "long message survives" "${repo2}" -q commit "${long}"
	echo odd2 > "${repo2}/seed.txt"
	fSurvive "unicode/emoji message" "${repo2}" -q commit $'café \u{1F600} ‮ rtl'

	## No-mutate: a refused command leaves HEAD and branch exactly as they were.
	local before_head before_branch
	before_head="$(cd "${repo}" && git rev-parse HEAD)"
	before_branch="$(cd "${repo}" && git branch --show-current)"
	fRun "${repo}" -q newbr 'bad:name'   ## refused
	if [[ "$(cd "${repo}" && git rev-parse HEAD)" == "${before_head}" \
		&& "$(cd "${repo}" && git branch --show-current)" == "${before_branch}" ]]; then
		fOk "refused command left the repo unchanged"
	else
		fFail "refused command mutated the repo"
	fi
}

echo "gitsby fuzz + security (fixtures: ${work})"

gitsby="${root}/bin/gitsby"
fRunFuzz "bash"

## Same suite against the PowerShell port when pwsh is present. The shim keeps
## ${gitsby} a single path, so the argument passing above is unchanged.
if command -v pwsh >/dev/null 2>&1; then
	gitsby="${work}/gitsby-pwsh"
	printf '#!/usr/bin/env bash\nexec pwsh -NoProfile -File "%s" "$@"\n' "${root}/bin/gitsby.ps1" > "${gitsby}"
	chmod +x "${gitsby}"
	fRunFuzz "pwsh"
else
	echo "fuzz: pwsh skipped (pwsh not installed)"
fi

## The security assertion: no vector ever caused a side-effect to run.
if [[ -z "$(find "${work}" -name 'CANARY*' -print -quit)" ]]; then
	fOk "no injection canary fired"
else
	fFail "injection canary fired: $(find "${work}" -name 'CANARY*')"
fi

echo "passed: ${pass}, failed: ${fail}"
((fail == 0)) || exit 1


##	History:
##		- 20260724 JC: Created. Adversarial fuzz of the command/option/arg surface
##			with an injection canary, run per implementation like the test harness.
