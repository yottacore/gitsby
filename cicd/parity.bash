#!/usr/bin/env bash

##	Purpose:
##		- Compares the two builds against each other, rather than each against a
##		  spec. cicd/test.bash asks "does this behave correctly?" once per
##		  implementation; this asks "do the two answer the SAME?" for one input.
##		- Aimed at the defect class the behavioural suite is blind to by
##		  construction: every port bug that has reached users here was a language
##		  mechanism differing - file encoding, parameter binding, return types,
##		  path resolution, string case - not a rule either build got wrong on
##		  purpose. A check written per implementation passes on both while they
##		  quietly disagree about the same input.
##		- Exits nonzero on any disagreement, so cicd aborts.
##	Syntax:
##		cicd/parity.bash
##	Notes:
##		- Skips itself where pwsh is absent: there is nothing to compare to.
##		- Output is normalized only for the program's own name ('gitsby' vs
##		  'gitsby.ps1') and for the option spellings the two builds document
##		  differently. Anything else that differs is a finding.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-parity.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
## The same directory in the spelling native Windows understands. A folder rule has to be written
## in a spelling BOTH builds can resolve, and an MSYS mount path such as '/tmp/...' is not one:
## only this shell knows its own mount table, and the PowerShell build must not need Git Bash to
## exist. 'account' marks a rule that resolves to no directory, which is what makes that visible
## rather than silent.
workNative="${work}"
command -v cygpath >/dev/null 2>&1 && workNative="$(cygpath -m "${work}")"
workBack="${workNative//\//\\}"

## Same hermeticity as the behavioural suite, and for the same reasons.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
export GITSBY_CONFIG="${work}/no-accounts.shcl"; : > "${GITSBY_CONFIG}"

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); echo "  ok: $*"; }
fBad(){  fail=$((fail+1)); echo "  DIFFER: $*"; }

bashBuild="${root}/bin/gitsby"
pwshBuild="${root}/bin/gitsby.ps1"

if ! command -v pwsh >/dev/null 2>&1; then
	echo "parity: pwsh not installed - nothing to compare against, skipping."
	exit 0
fi

fNormalize(){
	## Only the two things the builds are ENTITLED to differ on: the program's own name, and the
	## absolute path of whichever build produced the line. Everything else is left alone, because
	## everything else differing is the point of this file.
	## Every spelling of the work directory folds to one token: the two shells legitimately echo a
	## path the way their own runtime spells it, and that is not a parity finding.
	sed -e 's/gitsby\.ps1/gitsby/g' -e "s|${root}|<root>|g" \
		-e "s|${workBack}|<work>|gI" -e "s|${workNative}|<work>|gI" -e "s|${work}|<work>|g"
}

fRunBash(){ local -r d="${1}"; shift; ( cd "${d}" || exit 1; "${bashBuild}" "${@}" 2>&1 || true ) | fNormalize ;}
fRunPwsh(){ local -r d="${1}"; shift; ( cd "${d}" || exit 1; pwsh -NoProfile -File "${pwshBuild}" "${@}" 2>&1 || true ) | fNormalize ;}

fSame(){
	## One input, both builds, byte-identical answers after normalization.
	local -r label="${1}"; local -r dir="${2}"; shift 2
	local a="" b=""
	a="$(fRunBash "${dir}" "${@}")"
	b="$(fRunPwsh "${dir}" "${@}")"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		diff <(printf '%s\n' "${a}") <(printf '%s\n' "${b}") | sed 's/^/      /' | head -12
	fi
}

fSameField(){
	## One labelled line out of each build's output, compared. Used where the surrounding block
	## legitimately differs: each runtime echoes a path the way it spells one, and 'C:\x' against
	## '/c/x' is not a finding - what the two must agree on is what they RESOLVED from it.
	local -r label="${1}"; local -r pattern="${2}"; local -r dir="${3}"; shift 3
	local a="" b=""
	a="$(fRunBash "${dir}" "${@}" | grep -E "${pattern}" || true)"
	b="$(fRunPwsh "${dir}" "${@}" | grep -E "${pattern}" || true)"
	if [[ "${a}" == "${b}" ]]; then
		fOk "${label}"
	else
		fBad "${label}"
		printf '      bash: %s\n      pwsh: %s\n' "${a:-(no such line)}" "${b:-(no such line)}"
	fi
}

fSameExit(){
	## Same accept/reject verdict. Used where the two legitimately word a message differently but
	## must agree on whether the input is valid at all.
	local -r label="${1}"; local -r dir="${2}"; shift 2
	local -i ra=0 rb=0
	( cd "${dir}" && "${bashBuild}" "${@}" >/dev/null 2>&1 ) || ra=$?
	( cd "${dir}" && pwsh -NoProfile -File "${pwshBuild}" "${@}" >/dev/null 2>&1 ) || rb=$?
	## Only the verdict, not the code: the two runtimes number their own failures differently.
	if [[ $((ra == 0)) -eq $((rb == 0)) ]]; then fOk "${label}"; else fBad "${label} (bash exit ${ra}, pwsh exit ${rb})"; fi
}

echo
echo "[ gitsby parity: comparing the two builds against each other ]"
echo

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Path spelling. The folder rule is the feature most exposed to path handling, and this is where
## the builds diverged for real: one resolved a spelling through the filesystem and the other did
## not, so the same rule matched in one and not the other. Silently, which is the worst kind.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo "-- folder rules, however the path is spelled"
tree="${work}/tree"
mkdir -p "${tree}"
git init --quiet -b main "${tree}"
( cd "${tree}" && echo a > a.txt && git add --all && git commit --quiet -m init )

declare -a spellings=("${workNative}/tree")
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
	winPath="$( cd "${tree}" && pwd -W )"
	spellings+=("${winPath}")
	spellings+=("${winPath//\//\\}")
	spellings+=("${winPath,,}")
fi
for spelling in "${spellings[@]}"; do
	cat > "${work}/spell.shcl" <<-EOF
		account.s.path      = ${spelling}
		account.s.ghAccount = spellacct
	EOF
	fSameField "path spelled '${spelling}' resolves the same" '^Account' "${tree}" -q -NoFetch --config "${work}/spell.shcl" status
done

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Option binding. PowerShell's parameter binder is a whole mechanism the Bash build does not have,
## and it has produced three separate defects: options claimed out of a passthrough, a joined
## '-Config=FILE' binding nothing, and a bare '--' killing the process before any code ran.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- option forms"
fSame     "an unknown option is refused the same way"     "${tree}" -q --bogus status
fSame     "an option after the command is refused alike"  "${tree}" -q status --bogus
fSame     "too many positionals are counted alike"        "${tree}" -q br switch a b c
fSameExit "a spaced --config is accepted by both"         "${tree}" -q -NoFetch --config "${work}/no-accounts.shcl" status
fSameExit "an empty --config is refused by both"          "${tree}" -q -NoFetch --config "" status
fSameExit "a --config naming a directory is refused"      "${tree}" -q -NoFetch --config "${work}" status
fSameExit "a --config naming nothing there is refused"    "${tree}" -q -NoFetch --config "${work}/nope.shcl" status
fSameExit "-q and -y together are accepted by both"       "${tree}" -q -y -NoFetch status
fSameExit "-NoFetch before 'raw' is taken by both"        "${tree}" -q -NoFetch raw git rev-parse HEAD
fSameExit "a bad 'raw' tool is refused by both"           "${tree}" -q raw curl x

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## String case. Bash folds with '${x,,}' and PowerShell compares case-insensitively by default, so
## the two drift apart wherever one is applied and the other is assumed.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- string case"
cat > "${work}/case.shcl" <<-EOF
	account.mixed.path      = ${spellings[0]}
	account.mixed.ghAccount = caseacct
EOF
for name in mixed MIXED MiXeD; do
	## Exported around the call, not named only in the label: both builds have to SEE it. Written
	## the other way this loop ran three identical commands and compared them to each other, which
	## passes whatever either build does with the variable.
	export GITSBY_ACCOUNT="${name}"
	fSameField "GITSBY_ACCOUNT='${name}' resolves the same" '^Account' "${tree}" -q -NoFetch --config "${work}/case.shcl" status
	unset GITSBY_ACCOUNT
done

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## File encoding. A BOM is invisible in an editor and in 'Get-Content', and has broken both the
## documented one-liner installs and direct execution of the script. Bytes, not text.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
echo
echo "-- file encoding"
for f in "${root}/bin/gitsby" "${root}/bin/gitsby.ps1" "${root}/install.bash" "${root}/install.ps1" "${root}/install-dev.bash" "${root}/install-dev.ps1"; do
	[[ -f "${f}" ]] || continue
	if [[ "$(head -c 2 "${f}")" == "#!" ]]; then
		fOk "${f##*/} starts with a shebang, not a BOM"
	else
		fBad "${f##*/} does not start with '#!' - a BOM ahead of it breaks 'irm | iex' and direct execution"
	fi
done

echo
echo "parity passed: ${pass}, differed: ${fail}"
((fail == 0)) || exit 1

##	History:
##		- 20260812 JC: Created. Compares the two builds against each other rather than each against
##		  a spec, for the defect class the behavioural suite cannot see: every port bug that reached
##		  users was a language mechanism differing, not a rule either build got wrong.
