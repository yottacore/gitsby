#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		- Adversarial fuzz + injection-safety for gitsby's OWN input surface: the
##		  command slot, options, and branch/message/version/pr arguments. Not
##		  upstream git - just what a hostile or fat-fingered user can hand gitsby.
##		- Three invariants, checked per vector:
##		    1. No internal crash - no runtime error dump, exit stays a controlled 0/1.
##		    2. No shell/command injection - a canary side-effect never fires.
##		    3. Inputs that must be refused exit nonzero and leave the repo untouched.
##		- Run by cicd.bash stage 3 against the build from stage 2, or standalone after
##		  a 'go build' in src-go/. Hermetic: throwaway repos, no net.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}. On macOS, install one with 'brew install bash' and put it first on PATH." >&2; exit 1
fi
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-fuzz.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT

## Hermetic: no reliance on (or writes to) the user's git config, no prompts.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=fuzz GIT_AUTHOR_EMAIL=fuzz@fuzz
export GIT_COMMITTER_NAME=fuzz GIT_COMMITTER_EMAIL=fuzz@fuzz
export GIT_TERMINAL_PROMPT=0
## gitsby's own config decides which account a command acts as, so pin it the way test.bash does.
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"

## Pinning the config FILES is not isolation on its own: GIT_CONFIG_COUNT/KEY_n/VALUE_n outrank
## every one of them, and an inherited GH_TOKEN is what the fake gh reports back. Both arrive
## from an ordinary working terminal, and neither shows up as a failure you can act on.
fUnsetInheritedGitConfig(){
	local -i i=0
	for (( i = 0; i < ${GIT_CONFIG_COUNT:-0}; i++ )); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done
	unset GIT_CONFIG_COUNT
}
fUnsetInheritedGitConfig
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST GH_CONFIG_DIR GITSBY_ACCOUNT

## Output helpers, the same family as cicd.bash's: fEcho_Clean prints a line as given and
## collapses repeated blanks, and fUsage refuses the command line.
declare -i __wasLastEchoBlank=0
fEcho_Clean(){
	if [[ -n "${1:-}" ]]; then printf '%s\n' "$*"; __wasLastEchoBlank=0
	elif ((! __wasLastEchoBlank)); then echo; __wasLastEchoBlank=1; fi
}
fUsage(){ fEcho_Clean "$*" >&2; exit 2; }

## -q silences the per-check line and leaves the header, the failures and the total. The
## pipeline doesn't pass it, even on its own -q runs.
declare -i quiet=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		-h|--help)  fEcho_Clean "Usage: $(basename "${BASH_SOURCE[0]}") [-q|--quiet]"; exit 0 ;;
		*)          fUsage "unknown option: ${1} (try --help)" ;;
	esac
done

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); ((quiet)) || fEcho_Clean "  ok: $*"; }
fFail(){ fail=$((fail+1)); fEcho_Clean "  FAIL: $*"; }

declare -i isWindows=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) isWindows=1 ;; esac

## An internal-error dump from either implementation. A clean validation refusal
## ("gitsby: <msg>", exit 1) matches none of these; an uncaught bash error, a
## non-0/1 exit dump, or a pwsh StrictMode/runtime fault does. The arg parser's
## "Reverse call stack:" line is a deliberate refusal, not a crash, so it's out.
crashRe='unbound variable|: syntax error|bad substitution|command not found|integer expression expected|not a valid identifier|divide by zero|division by 0|bad array subscript|: line [0-9]+:|At line# |Command# \.\.\.|Err# \.\.\.|cannot be retrieved because it has not been set|Cannot index into a null|Attempted to divide by zero|Method invocation failed|Unable to find type'

__runOut=""; declare -i __runCode=0
## Run gitsby in a directory with the given args verbatim (no reshell of the
## vector), capturing merged output and exit code without tripping set -e.
fRun(){
	local -r dir="$1"; shift
	__runOut="$( { cd "${dir}" && "${gitsby}" "$@"; } </dev/null 2>&1 )" && __runCode=0 || __runCode=$?
}
fIsCrash(){ grep -qE "${crashRe}" <<< "${__runOut}" || ((__runCode >= 2)); }

## Must survive (accept or refuse - either is fine) without an internal crash.
fSurvive(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if fIsCrash; then fFail "${desc} (exit ${__runCode})"; else fOk "${desc}"; fi; }
## Must be ACCEPTED: exit 0, no crash. fSurvive can't say this - it passes on a flat refusal,
## so a valid option spelling that stopped being recognized would look fine.
fAccept(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if fIsCrash; then fFail "${desc}: crashed (exit ${__runCode})"
	elif ((__runCode != 0)); then fFail "${desc}: refused (exit ${__runCode}), should accept"
	else fOk "${desc}"; fi; }
## Must refuse: nonzero exit, no crash.
fRefuse(){ local -r desc="$1"; local -r dir="$2"; shift 2; fRun "${dir}" "$@"
	if fIsCrash; then fFail "${desc}: crashed (exit ${__runCode})"
	elif ((__runCode == 0)); then fFail "${desc}: accepted, should refuse"
	else fOk "${desc}"; fi; }
## Commit a message and confirm it lands in the log verbatim - catches a shell
## glob-expanding a bare '*'/'?' message into filenames before git sees it.
fMsgLiteral(){ local -r desc="$1"; local -r dir="$2"; local -r msg="$3"
	echo "chg ${RANDOM}" > "${dir}/seed.txt"
	fRun "${dir}" -q update "${msg}"
	local rec; rec="$(cd "${dir}" && git log -1 --format=%s)"
	if fIsCrash;             then fFail "${desc}: crashed (exit ${__runCode})"
	elif [[ "${rec}" == "${msg}" ]]; then fOk "${desc}"
	else fFail "${desc}: recorded [${rec}], expected [${msg}]"; fi; }

## Confirm a PR title reaches gh verbatim - same class of bug as fMsgLiteral, on the
## other user-controlled value that gets handed to a native command.
## Clone into a glob-shaped directory name: the name must land verbatim, not expand
## against the cwd. Same bug class as fMsgLiteral, one slot deeper.
fDirLiteral(){ local -r desc="$1"; local -r dir="$2"; local -r url="$3"; local -r name="$4"
	rm -rf "${dir:?}/${name}"
	fRun "${dir}" -q repo clone "${url}" "${name}"
	if fIsCrash;                         then fFail "${desc}: crashed (exit ${__runCode})"
	elif [[ -d "${dir}/${name}/.git" ]]; then fOk "${desc}"
	else fFail "${desc}: no clone at [${name}]"; fi; }

fTitleLiteral(){ local -r desc="$1"; local -r dir="$2"; local -r title="$3"
	rm -f -- "${ghLog:?}"
	fRun "${dir}" -q pr create "${title}"
	local rec; rec="$(awk '/^--title$/{getline; print; exit}' "${ghLog}" 2>/dev/null || true)"
	if fIsCrash;                   then fFail "${desc}: crashed (exit ${__runCode})"
	elif [[ "${rec}" == "${title}" ]]; then fOk "${desc}"
	else fFail "${desc}: gh got [${rec}], expected [${title}]"; fi; }

## Fresh repo (bare origin + clone with one commit) under work/<name>.
fMakeRepo(){
	local -r dir="$1"
	git init --quiet --bare -b main "${dir}.git"
	git clone --quiet "${dir}.git" "${dir}" 2>/dev/null
	( cd "${dir}" && echo seed > seed.txt && git add --all \
		&& git commit --quiet -m seed && git push --quiet -u origin main )
}

## Vectors. None of these strings contain a crashRe keyword, so a vector echoed
## back in gitsby's output can't self-trip the crash check.
## The single quotes are the point: these must reach gitsby as literal text, not
## expand here - that's what proves gitsby keeps them inert.
# shellcheck disable=SC2016
{
## Commands are matched case-insensitively (forgiving by design), so 'STATUS' is a
## valid alias of 'status' and doesn't belong here.
badCommands=( frobnicate status2 '..' './x' '123' 'a b' '-' '--' 'commit extra junk' )
badOptions=( --bogus -x -qx '--no-fetch=1' '--=v' -Z )
## The noun grammar put a second word in play; it gets the same treatment as the first.
badSubcommands=( "${badCommands[@]}" 'creat' 'switchh' 'ok' 'list extra' )
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
	fEcho_Clean "fuzz: ${1} (${gitsby})"
	local -r base="${work}/$1"
	mkdir -p "${base}"

	## Deterministic gh on PATH: the pr vectors below must not depend on a real gh being
	## installed, and must never reach the network. Logs create-args one per line so the
	## title can be compared byte for byte.
	mkdir -p "${base}/bin"
	## No .cmd sibling here, unlike test.bash: on Windows that would route the stub through cmd.exe,
	## which splits an unquoted '&' or '>' in an argument - turning a vector this suite hands gitsby
	## into a real command, and reporting an injection that gitsby never had. The pwsh leg's gh
	## coverage is skipped on Windows instead (see below), which is the honest answer.
	cat > "${base}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$1 $2" in
	"pr list")   : ;;  ## no PR open for this branch
	"pr create") printf '%s\n' "$@" > "${FUZZ_GH_LOG}"; echo "https://example.invalid/pull/1" ;;
	*)           : ;;
esac
GHEOF
	chmod +x "${base}/bin/gh"
	PATH="${base}/bin:${PATH}"; export PATH
	ghLog="${base}/gh.log"; export FUZZ_GH_LOG="${ghLog}"

	## Command slot: garbage first tokens are refused, never crash.
	local repo="${base}/cmd"; fMakeRepo "${repo}"
	local c
	for c in "${badCommands[@]}"; do fRefuse "[EkzQ7gG] command refused: '${c}'" "${repo}" -q "${c}"; done

	## Subcommand slot: garbage after a valid noun is refused the same way, and never reaches git.
	local sub
	for sub in "${badSubcommands[@]}"; do
		fRefuse "[El9QuEa] br subcommand refused: '${sub}'"   "${repo}" -q br   "${sub}"
		fRefuse "[El9QuEb] repo subcommand refused: '${sub}'" "${repo}" -q repo "${sub}"
	done

	## Options: unknown ones refused in either slot; valid combos accepted.
	local o
	for o in "${badOptions[@]}"; do
		fRefuse "[EkzQ7gH] option refused (slot 1): '${o}'" "${repo}" -q "${o}" status
		fRefuse "[EkzQ7gI] option refused (slot 2): '${o}'" "${repo}" -q status "${o}"
	done
	## -NoFetch is the spelling both ports take; bash also lowercases '--no-fetch', pwsh rejects it.
	fAccept "[EkzQ7gJ] valid combo -q -y status"          "${repo}" -q -y status
	fAccept "[EkzQ7gK] valid combo -q -NoFetch status"    "${repo}" -q -NoFetch status
	fAccept "[EkzQ7gL] valid combo -y -q br list"         "${repo}" -y -q br list
	[[ "$1" == "bash" ]] && fAccept "[EkzQ7gM] valid combo -q --no-fetch status"  "${repo}" -q --no-fetch status

	## Branch names: injection + malformed refs are refused before any action.
	local b
	for b in "${badBranch[@]}"; do
		fRefuse "[EkzQ7gN] br create refuses: '${b}'" "${repo}" -q br create "${b}"
		fRefuse "[EkzQ7gO] br switch refuses: '${b}'" "${repo}" -q br switch "${b}"
	done

	## br prune takes no argument at all, so that slot is a refusal - and an injection
	## vector parked there must die at the parser, well before anything is deleted.
	local p
	for p in "${inject[@]}"; do
		fRefuse "[El9kLkW] br prune refuses an argument: '${p}'" "${repo}" -q br prune "${p}"
	done
	fRefuse "[El9kLkX] br prune refuses a branch name"     "${repo}" -q br prune main
	fRefuse "[El9kLkY] internal br-prune token refused"    "${repo}" -q br-prune

	## Commit messages: anything goes in a message, but it stays inert data. Each
	## needs a real change to reach 'git commit'; unique content guarantees one.
	## 'update' is the command that commits - there is no bare 'commit' any more.
	local repo2="${base}/msg"; fMakeRepo "${repo2}"
	local -i i=0 m
	for m in "${!inject[@]}"; do
		echo "change ${i}" > "${repo2}/seed.txt"; i=$((i + 1))
		fSurvive "[EkzQ7gP] commit message inert: '${inject[m]}'" "${repo2}" -q update "${inject[m]}"
	done
	## ...and a bare-glob message must land verbatim, not expand to filenames. The
	## repo has files, so '*' and '*.txt' would glob if the message weren't literal.
	local gm
	for gm in '*' '*.txt' '?' 'v*'; do fMsgLiteral "[EkzUx6m] commit message verbatim: '${gm}'" "${repo2}" "${gm}"; done

	## Versions and PR numbers: malformed values refused (release fetches first,
	## which is local here; pr rejects before any network).
	local repo3="${base}/ver"; fMakeRepo "${repo3}"
	local v p
	for v in "${badVersion[@]}"; do fRefuse "[EkzQ7gQ] release refuses version: '${v}'" "${repo3}" -q release "${v}"; done
	for p in "${badPr[@]}";      do fRefuse "[EkzQ7gR] pr refuses: '${p}'"              "${repo3}" -q pr "${p}"; done

	## PR titles: free text like a commit message, and it must reach gh as data, not code.
	## Needs a branch that isn't the merge target, which is what 'pr create' proposes from.
	local repo4="${base}/prnew"; fMakeRepo "${repo4}"
	( cd "${repo4}" && git checkout --quiet -b dev && git push --quiet -u origin dev \
		&& git checkout --quiet -b feat && echo f > f.txt && git add --all && git commit --quiet -m feat )
	local t
	for t in "${inject[@]}"; do fSurvive "[El9Ej20] pr title inert: '${t}'" "${repo4}" -q pr create "${t}"; done
	## Reading what gh received needs the stub to actually run, which on Windows the PowerShell
	## build can't do - a shebang file is not something it can start, and the .cmd sibling that
	## would fix it re-parses these very arguments. Say so rather than pass on a stub that no-oped.
	if [[ "$1" == "bash" ]] || ((! isWindows)); then
		for t in '*' '*.txt' '?' 'v*'; do fTitleLiteral "[El9Ej21] pr title verbatim: '${t}'" "${repo4}" "${t}"; done
	else
		fEcho_Clean "  skipped: pr title verbatim (pwsh on Windows can't run the gh stub)"
	fi
	## Proposing from the merge target is nonsense whatever the title says.
	( cd "${repo4}" && git checkout --quiet dev )
	fRefuse "[El9Ej22] pr create refuses from the merge target" "${repo4}" -q pr create 'anything'
	( cd "${repo4}" && git checkout --quiet feat )

	## Clone url and directory are user values that reach native git. A junk url is refused
	## (none of these is cloneable); a glob-shaped directory has to stay literal.
	local u
	for u in "${inject[@]}"; do fRefuse "[El9QuEc] clone url refused: '${u}'" "${repo3}" -q repo clone "${u}"; done
	local cloneDir
	local -a cloneDirs=( '*' '?' 'v*' 'a b' )
	## Win32 forbids '*' and '?' in a path, so native git can't create such a work tree at all
	## ("could not create work tree dir '*': Invalid argument") - the invariant is unprovable
	## there rather than violated. MSYS mkdir happily makes one, which is what makes the first
	## guess wrong. A space is legal, so 'a b' stays.
	if ((isWindows)); then
		cloneDirs=( 'a b' )
		fEcho_Clean "  skipped: clone dir verbatim '*' '?' 'v*' (Win32 forbids those characters in a path)"
	fi
	for cloneDir in "${cloneDirs[@]}"; do fDirLiteral "[El9QuEd] clone dir verbatim: '${cloneDir}'" "${repo3}" "${repo3}.git" "${cloneDir}"; done

	## Long and odd input: must not crash. Branch is refused, message accepted.
	local long; long="$(printf 'x%.0s' {1..5000})"
	fRefuse  "[EkzQ7gS] long branch refused"  "${repo3}" -q br create "${long}"
	echo odd > "${repo2}/seed.txt"
	fSurvive "[EkzQ7gT] long message survives" "${repo2}" -q update "${long}"
	echo odd2 > "${repo2}/seed.txt"
	fSurvive "[EkzQ7gU] unicode/emoji message" "${repo2}" -q update $'café \u{1F600} ‮ rtl'

	## The new argument slots. 'raw' fronts exactly two tools, so anything else in that position is
	## refused rather than run - the one place a wrong answer would execute an arbitrary program.
	local rawTool
	for rawTool in "${badCommands[@]}" "${inject[@]}" 'rm' 'sh' 'GIT'; do
		fRefuse "[EmMuR5U] raw tool refused: '${rawTool}'" "${repo3}" -q raw "${rawTool}" --version
	done
	fRefuse "[EmMuR5V] raw with no tool refused" "${repo3}" -q raw
	## Deliberately NOT fuzzed: the arguments after 'git' or 'gh'. Reaching the tool verbatim is
	## the whole contract, so an injection vector there is gitsby doing its job, and the canary
	## would fire on a pass. What is checked above is that nothing but git and gh can be reached.

	## repo url takes one of two words and nothing else.
	local urlArg
	for urlArg in "${badSubcommands[@]}" "${inject[@]}" 'HTTPS ' 'https extra'; do
		fRefuse "[EmMuR5W] repo url arg refused: '${urlArg}'" "${repo3}" -q repo url "${urlArg}"
	done

	## account has two subcommands, and neither takes an argument.
	local acctSub
	for acctSub in "${badSubcommands[@]}" "${inject[@]}"; do
		fRefuse "[EmMuR5X] account subcommand refused: '${acctSub}'" "${repo3}" -q account "${acctSub}"
	done
	fRefuse "[EmMuR5Y] account list takes no argument"  "${repo3}" -q account list junk
	fRefuse "[EmMuR5Z] account apply takes no argument" "${repo3}" -q account apply junk

	## --config names a file. One that isn't there is refused; the value never reaches a shell.
	local cfg
	for cfg in "${inject[@]}" '/nonexistent/gitsby.shcl' ''; do
		fRefuse "[EmMuR5a] bad --config refused: '${cfg}'" "${repo3}" -q --config "${cfg}" status
	done

	## GITSBY_ACCOUNT reaches 'gh auth token --user' as a value. It must stay inert there, and an
	## account nobody holds a token for is simply not selected - never an error, never a canary.
	local acct
	for acct in "${inject[@]}" '-x' '--user root'; do
		GITSBY_ACCOUNT="${acct}" fSurvive "[EmMuR5b] GITSBY_ACCOUNT inert: '${acct}'" "${repo2}" -q --no-fetch status
	done
	unset GITSBY_ACCOUNT

	## 'path' is the same kind of VALUE. One that isn't absolute is listed as ignored rather than
	## matched, and junk matches nothing either way: nothing fires and nothing crashes.
	local pathCfg="${work}/path-fuzz.shcl" pathVal
	for pathVal in "${inject[@]}" '.' '..' './x' 'dev/work' '~' '~nobody/x' 'C:work' '\work'; do
		{ printf 'account.f.path = %s\n' "${pathVal}"; printf 'account.f.ghAccount = fuzzacct\n'; } > "${pathCfg}"
		fSurvive "[Ept2CIC] path inert: '${pathVal}'" "${repo2}" -q --no-fetch --config "${pathCfg}" status
		fSurvive "[Ept2CID] path inert in account: '${pathVal}'" "${repo2}" -q --no-fetch --config "${pathCfg}" account
	done

	## 'pathContains' is a config VALUE that reaches a native command twice over: it is compared
	## against the current path, and 'account apply' builds a git config key out of it. A rule that
	## matches nothing is the ordinary answer for junk, so what is asserted here is that nothing
	## fires and nothing crashes - never that it is refused.
	local segCfg="${work}/seg-fuzz.shcl" seg
	for seg in "${inject[@]}" '../..' '/' '**' '.'; do
		{ printf 'account.f.pathContains = %s\n' "${seg}"; printf 'account.f.ghAccount = fuzzacct\n'; } > "${segCfg}"
		fSurvive "[EmmNC1Q] pathContains inert: '${seg}'" "${repo2}" -q --no-fetch --config "${segCfg}" status
		fSurvive "[EmmNC1R] pathContains inert in account: '${seg}'" "${repo2}" -q --no-fetch --config "${segCfg}" account
	done

	## No-mutate: a refused command leaves HEAD and branch exactly as they were.
	local headBefore branchBefore
	headBefore="$(cd "${repo}" && git rev-parse HEAD)"
	branchBefore="$(cd "${repo}" && git branch --show-current)"
	fRun "${repo}" -q br create 'bad:name'   ## refused
	if [[ "$(cd "${repo}" && git rev-parse HEAD)" == "${headBefore}" \
		&& "$(cd "${repo}" && git branch --show-current)" == "${branchBefore}" ]]; then
		fOk "[EkzQ7gV] refused command left the repo unchanged"
	else
		fFail "[EkzQ7gV] refused command mutated the repo"
	fi
}

fEcho_Clean "gitsby fuzz + security (fixtures: ${work})"

## One implementation. The shim keeps ${gitsby} a single path, so the argument passing
## above is unchanged.
goBin="${root}/src-go/gitsby"; [[ -x "${goBin}" ]] || goBin="${goBin}.exe"
[[ -x "${goBin}" ]] || { fEcho_Clean "no build at src-go/gitsby - run 'go build' there, or cicd.bash stage 2" >&2; exit 1; }
gitsby="${work}/gitsby-go"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${goBin}" > "${gitsby}"
chmod +x "${gitsby}"
fRunFuzz "go"

## The credential helper. gitsby writes it as a git config value, and git hands that value to a
## SHELL when a push needs credentials - so anything interpolated into it is a command, not a
## string. The login that goes in there can come from GITSBY_ACCOUNT, from a git config key, or
## from the config file, and none of those is a place to accept shell. Driven with a real
## 'git credential fill', because the string is inert until git actually runs it: reading the
## config value back proves nothing about what happens when it is invoked.
fCredentialHelperVectors(){
	local -r ch="${work}/credhelper"
	mkdir -p "${ch}"
	git init --quiet -b main "${ch}/proj"
	(
		cd "${ch}/proj" || exit 1
		echo a > a.txt && git add --all && git commit --quiet -m init
		git remote add origin https://github.com/acme/proj.git
	)
	echo tok_fuzz > "${ch}/token"; chmod 600 "${ch}/token" 2>/dev/null || true
	local vector=""
	## Single quotes throughout: these are the literal text of an attack, not something to expand.
	# shellcheck disable=SC2016
	for vector in '; touch '"${ch}"'/CANARY-ghaccount; echo x' \
	              '`touch '"${ch}"'/CANARY-backtick`' \
	              '$(touch '"${ch}"'/CANARY-subshell)' \
	              '" ; touch '"${ch}"'/CANARY-quote ; "' ; do
		cat > "${ch}/v.shcl" <<-EOF
			account.v.path      = ${ch}/proj
			account.v.ghAccount = ${vector}
			account.v.tokenFile = ${ch}/token
		EOF
		## 'credential fill' makes git invoke the helper for real.
		( cd "${ch}/proj" && printf 'protocol=https\nhost=github.com\n\n' | \
			"${gitsby}" -q -NoFetch --config "${ch}/v.shcl" raw git credential fill ) >/dev/null 2>&1 || true
	done
	## GIT_CONFIG_COUNT is the one environment value gitsby reads and numbers its own
	## config entries on from, so a junk count must be refused rather than treated as
	## zero and numbered over the caller's entries - and a count carrying a command
	## substitution must stay text, never be evaluated. Driven on the same path that
	## actually adds config (the credential helper), which is where the count is read.
	local badCount="" why=""
	# shellcheck disable=SC2016
	for badCount in 'x[$(touch '"${ch}"'/CANARY-count)]' '-1' '1e3'; do
		GIT_CONFIG_COUNT="${badCount}" fRun "${ch}/proj" -q -NoFetch --config "${ch}/v.shcl" raw git credential fill
		why=""
		if fIsCrash; then why="crashed (exit ${__runCode})"; elif ((__runCode == 0)); then why="accepted"; fi
		if [[ -z "${why}" ]]; then fOk "[Ervo5Ng] junk GIT_CONFIG_COUNT refused: '${badCount}'"
		else fFail "[Ervo5Ng] junk GIT_CONFIG_COUNT '${badCount}': ${why}"; fi
	done

	## The helper git holds must carry no login text at all - the name is read from the
	## environment when it runs, the same way the token is.
	local helper=""
	helper="$( cd "${ch}/proj" && "${gitsby}" -q -NoFetch --config "${ch}/v.shcl" raw git config --get credential.https://github.com.helper 2>/dev/null )"
	# shellcheck disable=SC2016  ## matching the literal variable reference, not its value
	if [[ "${helper}" == *'${GITSBY_HOST_USER}'* && "${helper}" != *touch* ]]; then
		fOk "[EnSFBNI] the credential helper reads its username from the environment"
	else
		fFail "[EnSFBNI] the credential helper carries interpolated text: ${helper}"
	fi
}
fCredentialHelperVectors

## Argument injection into git. A folder name, a ref, or anything else user-controlled that
## reaches git as a leading argument must not be read as an option. 'repo clone' derives the
## work-tree name from the URL's last path part, so a URL whose tail is option-shaped puts that
## option in git's argument list unless gitsby separates it with '--'. A local clone runs the
## value of '--upload-pack' through a shell, which is what makes the attempt observable here.
fCloneArgInjection(){
	if ((isWindows)); then
		fEcho_Clean "  skipped: clone dir arg injection (path characters Win32 forbids)"
		return
	fi
	local -r dir="${work}/clonearg"
	mkdir -p "${dir}"
	## The bare repo's own folder name is the option string. The canary is a bare name, so the
	## command it is smuggled into would create it in whatever directory the clone runs from.
	# shellcheck disable=SC2016
	local -r evil='--upload-pack=touch CANARY-clonearg;git-upload-pack'
	git init --quiet --bare -b main "${dir}/${evil}.git"
	( git init --quiet -b main "${dir}/seed" && cd "${dir}/seed" \
		&& echo s > s.txt && git add --all && git commit --quiet -m s \
		&& git push --quiet "${dir}/${evil}.git" main ) >/dev/null 2>&1
	fRun "${dir}" -q repo clone "file://${dir}/${evil}.git"
	local why=""
	if fIsCrash; then why="crashed (exit ${__runCode})"
	elif [[ -e "${dir}/CANARY-clonearg" ]]; then why="it reached git as an option"; fi
	if [[ -z "${why}" ]]; then fOk "[Ervo5NU] a derived clone directory cannot reach git as an option"
	else fFail "[Ervo5NU] derived clone directory: ${why}"; fi
}
fCloneArgInjection

## A ref name that is also a revision or a non-branch must be refused before any work is parked.
## origin/HEAD is a symbolic ref at the default branch, not a branch, so 'br switch HEAD' passed
## the up-front existence check, committed and pushed the working tree to park it, then failed at
## 'git checkout -b HEAD'. The invariant under test is the no-mutate one, on the branch writers.
fSwitchUntouched(){
	local -r repo="${work}/switchref"
	fMakeRepo "${repo}"
	( cd "${repo}" && git checkout --quiet -b feat && echo f > f.txt \
		&& git add --all && git commit --quiet -m feat && git push --quiet -u origin feat ) >/dev/null 2>&1
	## Uncommitted work that 'park then move' would publish if the switch got that far.
	echo dirty > "${repo}/f.txt"
	local headBefore remoteBefore
	headBefore="$(cd "${repo}" && git rev-parse HEAD)"
	remoteBefore="$(cd "${repo}" && git rev-parse origin/feat)"
	fRun "${repo}" -q br switch HEAD
	local headAfter remoteAfter
	headAfter="$(cd "${repo}" && git rev-parse HEAD)"
	remoteAfter="$(cd "${repo}" && git rev-parse origin/feat)"
	local why=""
	if fIsCrash; then why="crashed (exit ${__runCode})"
	elif ((__runCode == 0)); then why="accepted, should refuse"
	elif [[ "${headAfter}" != "${headBefore}" || "${remoteAfter}" != "${remoteBefore}" ]]; then why="changed the repo before refusing"; fi
	if [[ -z "${why}" ]]; then fOk "[Ervo5NW] br switch HEAD refuses and leaves the repo untouched"
	else fFail "[Ervo5NW] br switch HEAD: ${why}"; fi
}
fSwitchUntouched

## A config 'sshkey' becomes GIT_SSH_COMMAND, which git hands to a shell - so a key path carrying
## a shell character would be re-parsed there and run. The value is dropped on load; proven by a
## real command that would use the key, with a fake ssh on PATH so nothing reaches the network.
## The canary is inside the key value: it fires only if the shell ever sees the string, which it
## does not when the value is dropped and git execs ssh directly.
fSshKeyInert(){
	local -r dir="${work}/sshkey"
	mkdir -p "${dir}/bin"
	git init --quiet -b main "${dir}/proj" >/dev/null 2>&1
	( cd "${dir}/proj" && git commit --quiet --allow-empty -m init \
		&& git remote add origin ssh://git@example.invalid/acme/proj.git ) >/dev/null 2>&1
	printf '#!/usr/bin/env bash\nexit 1\n' > "${dir}/bin/ssh"; chmod +x "${dir}/bin/ssh"
	## Each value is an absolute path (so the "must be absolute" rule doesn't drop it first)
	## carrying a shell metacharacter. A '#' can't appear - the config format reads it as a
	## comment - so a redirect and a substitution carry the canary instead, each firing whatever
	## trails them on the reconstructed command line.
	local key="" why=""
	# shellcheck disable=SC2016
	for key in "${dir}/k;>${dir}/CANARY-sshkey" "${dir}/k\$(touch ${dir}/CANARY-sshkey)" "${dir}/k\`touch ${dir}/CANARY-sshkey\`"; do
		printf 'account.s.path = %s\naccount.s.sshKey = %s\n' "${dir}/proj" "${key}" > "${dir}/s.shcl"
		## ls-remote against an unreachable host exits nonzero by design, so the exit code says
		## nothing here - only the canary does, and a gitsby-internal crash would still show in
		## the output pattern.
		PATH="${dir}/bin:${PATH}" fRun "${dir}/proj" -q -NoFetch --config "${dir}/s.shcl" raw git ls-remote origin
		why=""
		if grep -qE "${crashRe}" <<< "${__runOut}"; then why="crashed"
		elif [[ -e "${dir}/CANARY-sshkey" ]]; then why="reached ssh"; fi
		if [[ -z "${why}" ]]; then fOk "[Ervo5Nd] shell-bearing sshKey never reaches ssh: '${key}'"
		else fFail "[Ervo5Nd] shell-bearing sshKey '${key}': ${why}"; fi
	done
}
fSshKeyInert

## 'account apply' turns folder rules and account values into a git config file and the includeIf
## keys that pull it in. It writes them with 'git config', so git's own writer quotes a value - what
## gitsby owns is escaping the glob characters git itself reads in a gitdir pattern, and dropping a
## shell-bearing host or user before either becomes a credential key.
fAccountApplyVectors(){
	local -r dir="${work}/apply"
	mkdir -p "${dir}/covered"
	git init --quiet -b main "${dir}/covered" >/dev/null 2>&1
	: > "${dir}/global"
	# shellcheck disable=SC2016
	cat > "${dir}/a.shcl" <<EOF
account.a.path         = ${dir}/covered
account.a.pathContains = d*e
account.a.host         = a;touch ${dir}/CANARY-apply
account.a.user         = a b
account.a.name         = n\$(touch ${dir}/CANARY-apply)
EOF
	GIT_CONFIG_GLOBAL="${dir}/global" fRun "${dir}" -q --config "${dir}/a.shcl" account apply
	local why=""
	if fIsCrash; then why="crashed (exit ${__runCode})"
	elif ! grep -qF 'd\*e' <<< "${__runOut}"; then why="left a glob character unescaped"; fi
	if [[ -z "${why}" ]]; then fOk "[Ervo5NY] account apply escapes glob characters in a folder rule"
	else fFail "[Ervo5NY] account apply folder rule: ${why}"; fi
	## The shell-bearing host and the spaced user must not appear in any fragment.
	local hit=""
	hit="$(grep -rlF -e 'a;touch' -e 'a b' "${dir}/accounts" 2>/dev/null || true)"
	if [[ -z "${hit}" ]]; then fOk "[Ervo5Nb] account apply drops a shell-bearing host and a spaced user"
	else fFail "[Ervo5Nb] a shell-bearing host or spaced user reached an account fragment"; fi
}
fAccountApplyVectors

## The security assertion: no vector ever caused a side-effect to run.
if [[ -z "$(find "${work}" -name 'CANARY*' -print -quit)" ]]; then
	fOk "[EkzQ7gW] no injection canary fired"
else
	fFail "[EkzQ7gW] injection canary fired: $(find "${work}" -name 'CANARY*')"
fi

fEcho_Clean "passed: ${pass}, failed: ${fail}"
((fail == 0)) || exit 1


##	History:
##		- 20260724 JC: Created. Adversarial fuzz of the command/option/arg surface
##			with an injection canary, run per implementation like the test harness.
##		- 20260726 JC: Vectors for the noun+verb subcommand slot, and for the clone url and directory.
##		- 20260808 JC: Vectors for the 'raw' tool slot, the 'repo url' argument, the 'account' subcommand, '--config' and GITSBY_ACCOUNT. What follows 'raw git' or 'raw gh' is deliberately not fuzzed - reaching the tool verbatim is the contract, so a vector there would fire the canary on a pass.
##		- 20260810 JC: The glob-shaped clone directories are skipped on Windows. Win32 forbids those characters in a path, so native git cannot create such a work tree at all and the invariant is unprovable there rather than violated - MSYS mkdir happily makes one, which is what makes the first guess wrong.
##		- 20260812 JC: Vectors for the "pathContains" config value. It is compared against the current path and becomes a git config key in "account apply", so it reaches a native command twice; junk there must stay inert rather than be refused, since a rule matching nothing is the ordinary answer.
##		- 20260813 JC: Same environment isolation the behavioral suite grew, plus the gitsby config file this one had never pinned at all.
##		- 20260818 JC: One leg, the compiled build. The scripted ones moved to legacy/ and are no longer a fuzz target - nothing new can reach them.
##		- 20260914 JC: Vectors for the "path" config value, beside pathContains: the injection set plus relative, dot, tilde and drive-relative spellings. One that isn't absolute is listed as ignored, and nothing fires or crashes either way. 269 -> 301.
##		- 20260926 JC: Every check carries a test ID at the front of its label.
##		- 20260926 JC: The pipeline no longer passes -q, so every check prints a line.
##		- 20261004 JC: Prints through fEcho_Clean, like the other pipeline scripts. Variables are camelCase, and fRun hands back its output in two-underscore globals. Every expansion braced, and shellcheck enforces it.
##		- 20261006 JC: Reworked for the no-shell Go build. The surviving vectors stay as regression guards against a shell slipping back into the path, and the suite now drives the places a value still reaches a real tool: a clone directory derived from a URL tail that is option-shaped (argument injection into git), a ref that is also a revision ('br switch HEAD', which parked work before refusing), a shell-bearing 'sshkey' through a real ssh, 'account apply' escaping glob characters in a folder rule and dropping a shell-bearing host or user, and a junk GIT_CONFIG_COUNT on the credential path. 301 -> 311. Two product bugs fixed alongside (clone '--', origin/HEAD not a branch).
