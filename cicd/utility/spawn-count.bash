#!/usr/bin/env bash

##	Purpose:
##		- Counts the processes gitsby spawns per command, and fails when a count grows.
##		- This is the profiling step, and it is deliberately not a sampling profiler: the
##		  program spends its whole life blocked waiting on git, so a flamegraph is a flat
##		  wall of Execve and Wait with no self-time in it and no leaders. What costs
##		  anything here is how many times we fork git, so that is what gets measured.
##		- Each command runs against a pristine throwaway repo with its own bare origin.
##		  The work tree AND the origin are restored between runs: prune deletes branches
##		  on both sides, and leaving either behind makes the next command's count a
##		  different question.
##		- Some commands run again in a folder an account's rule covers, with a fake gh
##		  and ssh, and on a pty with no -q, the way someone at a terminal runs them.
##		  Those are the paths that ask gh and ssh who you are.
##		- Each command has an expected count, written beside it below. Its limit is
##		  that plus 2, or a tenth again, whichever is larger. A count over the limit
##		  fails, --record or not. A fix that lowers a count lowers the number too.
##		- Baseline is the newest previous run in the artifact dir, GFS-rotated like the
##		  lint logs. No baseline yet means the first run records one and passes.
##	Syntax:
##		cicd/utility/spawn-count.bash [-q|--quiet] [--record]
##		  --record   Write the counts even when they rose against the baseline (accept a
##		             deliberate rise). It does not lift a limit.
##	Requires:
##		- strace. Linux only; the step self-skips anywhere else, which is the same
##		  treatment every other probe-gated tool gets.
##		- script, from util-linux, for the pty runs. Without it those are skipped and say so.
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
root="$(cd "${here}/.." && pwd)"; root="$(cd "${root}/.." && pwd)"
# shellcheck source=/dev/null
source "${root}/cicd/config.bash"
# shellcheck source=/dev/null
source "${here}/include/gfs-rotate.bash"

declare -i quiet=0 record=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet) quiet=1; shift ;;
		--record)   record=1; shift ;;
		-h|--help)  sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
		*)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

fEcho_Clean(){ echo "$*"; }

command -v strace >/dev/null 2>&1 || { echo "  spawn counts skipped (no strace)"; exit 0; }
exe="${root}/${GO_MODULE_DIR}/${EXE_NAME}"
[[ -x "${exe}" ]] || { echo "no build at ${GO_MODULE_DIR}/${EXE_NAME} - run cicd.bash stage 2, or 'go build' there" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-spawn.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT

## Hermetic, for the same reasons the suites are: an inherited config decides which account a
## command acts as, and that changes how many processes it starts. HOME and the two other
## places gitsby looks for its config are emptied or moved, so a measure that drops the pin
## still can't read the real user's accounts.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=spawn GIT_AUTHOR_EMAIL=spawn@test
export GIT_COMMITTER_NAME=spawn GIT_COMMITTER_EMAIL=spawn@test
noAccounts="${work}/no-accounts.shcl"; : > "${noAccounts}"
export GITSBY_CONFIG="${noAccounts}"
mkdir -p "${work}/home"
export HOME="${work}/home" XDG_CONFIG_HOME="" APPDATA=""
for ((i = 0; i < ${GIT_CONFIG_COUNT:-0}; i++)); do unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"; done
unset GIT_CONFIG_COUNT
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST GH_CONFIG_DIR GITSBY_ACCOUNT GIT_SSH_COMMAND GIT_SSH

## Nothing here reaches the network. The account folders' origins name github.com, so a fake gh
## and ssh answer what gitsby asks, and a proxy on a closed port fails anything that still tries
## https. The fakes run under this bash by full path: '#!/usr/bin/env bash' would add env's own
## exec and one failed one per PATH entry ahead of bash, and those would be counted as ours.
mkdir -p "${work}/bin"
cat > "${work}/bin/gh" <<EOF
#!${BASH}
## gh holds no account, so a token comes from the account's file; 'api user' answers for the
## token gitsby exported, or for gh's own login without one.
case "\$1 \$2" in
	"api user")   if [[ -n "\${GH_TOKEN:-}" ]]; then echo "\${GH_TOKEN#tok_}"; else echo ghuser; fi ;;
	"auth token") exit 1 ;;
	"config get") case " \$* " in *" user "*) echo ghuser ;; *) echo https ;; esac ;;
	*)            echo "fake gh: unhandled: \$*" >&2; exit 2 ;;
esac
EOF
cat > "${work}/bin/ssh" <<EOF
#!${BASH}
for arg in "\$@"; do
	case "\${arg}" in
		-G) printf 'user git\nhostname github.com\n'; exit 0 ;;
		-T) echo "Hi acme! You've successfully authenticated, but GitHub does not provide shell access."; exit 1 ;;
	esac
done
exit 255
EOF
chmod +x "${work}/bin/gh" "${work}/bin/ssh"
export PATH="${work}/bin:${PATH}"
export HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 all_proxy=http://127.0.0.1:9
unset NO_PROXY no_proxy

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The world: a bare origin and a clone, with a merged branch and an unmerged one, so prune
## has something to survey and merge has something to leave alone.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
pristine="${work}/pristine"
mkdir -p "${pristine}"
git init --quiet --bare -b main "${pristine}/origin.git"
git clone --quiet "${pristine}/origin.git" "${pristine}/repo" 2>/dev/null
(
	cd "${pristine}/repo"
	echo one > file.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
	git checkout --quiet -b dev && git push --quiet -u origin dev
	git checkout --quiet -b landed && echo two >> file.txt && git add --all && git commit --quiet -m landed
	git push --quiet -u origin landed
	git checkout --quiet dev && git merge --quiet --no-ff landed -m merge && git push --quiet
	git checkout --quiet -b open-work && echo three >> file.txt && git add --all && git commit --quiet -m wip
	git push --quiet -u origin open-work
	git checkout --quiet dev
)

## Two copies of that clone whose origin is on github.com, one over ssh and one over https, each
## covered by an account's folder rule. The Account line prints only for an account picked like
## that, never for one guessed from the remote's owner, so this is the path a configured user
## takes. The token comes from a file, since the fake gh holds none: that is the case that reads
## gh's own login before the token is exported, and asks who the token belongs to after. A
## changed file gives status a list to print. Three logins, so the listing asks gh about each.
cp -a "${pristine}/repo" "${pristine}/acct-ssh"
cp -a "${pristine}/repo" "${pristine}/acct-https"
git -C "${pristine}/acct-ssh"   remote set-url origin git@github.com:acme/proj.git
git -C "${pristine}/acct-https" remote set-url origin https://github.com/beta/proj.git
echo four >> "${pristine}/acct-ssh/file.txt"
echo four >> "${pristine}/acct-https/file.txt"
printf 'tok_acme\n' > "${work}/home/acme.token"
printf 'tok_beta\n' > "${work}/home/beta.token"
chmod 600 "${work}/home/acme.token" "${work}/home/beta.token"
accounts="${work}/accounts.shcl"
cat > "${accounts}" <<EOF
account: acme
	path: ${work}/live/acct-ssh
	ghaccount: acme
	tokenfile: ${work}/home/acme.token
	email: acme@example.com
account: beta
	path: ${work}/live/acct-https
	ghaccount: beta
	tokenfile: ${work}/home/beta.token
	email: beta@example.com
account: gamma
	ghaccount: gamma
	sshkey: ${work}/home/id_gamma
	email: gamma@example.com
EOF

fRestore(){
	rm -rf -- "${work:?}/live"
	mkdir -p "${work}/live"
	cp -a "${pristine}/." "${work}/live/"
}

hasPty=0
if command -v script >/dev/null 2>&1 && script -qec true /dev/null </dev/null >/dev/null 2>&1; then hasPty=1; fi

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The measurement. -f follows the children, so a git that forks its own helper is counted
## where it happens; execve is the event that costs, since that is a new program image.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The label starts with the test ID, which is printed but kept out of the baseline file, so
## an older baseline still matches. Then the expected count, how it runs, and the folder:
##   pipe  stdout to /dev/null, the way the pipeline and a script see it
##   tty   on a pty with stdin at end of input, which is a terminal to gitsby
## A folder starting 'acct' runs with the accounts file, and any other with the empty one.
## Room for a git version that adds or drops a helper of its own: two more processes, or a
## tenth again, whichever is larger. A real regression costs more than that.
fHeadroom(){ local n=$(( $1 / 10 )); (( n < 2 )) && n=2; echo "${n}"; }
declare -a ids=() labels=() counts=() expects=() limits=() skipped=()
fMeasure(){
	local label="${1#\[*\] }" id="${1%%\] *}]" expect="$2" how="$3" folder="$4"; shift 4
	local config="${noAccounts}" traceFile="${work}/trace.out" n=0 skip=""
	[[ "${folder}" == acct* ]] && config="${accounts}"
	fRestore
	: > "${traceFile}"
	if [[ "${how}" == tty ]] && ((! hasPty)); then
		skip="no pty"
	elif [[ "${how}" == tty ]]; then
		local traced=""
		printf -v traced '%q ' strace -f -e trace=execve -o "${traceFile}" "${exe}" "$@"
		## TERM is set so tput has an answer to give; the count is the same either way.
		( cd "${work}/live/${folder}" && GITSBY_CONFIG="${config}" TERM=xterm SHELL="${BASH}" script -qec "${traced}" /dev/null </dev/null ) >/dev/null 2>&1 || true
	else
		( cd "${work}/live/${folder}" && GITSBY_CONFIG="${config}" strace -f -e trace=execve -o "${traceFile}" "${exe}" "$@" ) >/dev/null 2>&1 || true
	fi
	[[ -n "${skip}" ]] || n="$(grep -c 'execve(' "${traceFile}" 2>/dev/null || true)"
	ids+=("${id}")
	labels+=("${label}")
	counts+=("${n}")
	expects+=("${expect}")
	limits+=("$(( expect + $(fHeadroom "${expect}") ))")
	skipped+=("${skip}")
}

## Expected counts are today's. --no-fetch on all but two: a fetch's cost is
## mostly git's own (upload-pack, a maintenance run), and a github.com origin can't be fetched
## here at all. The two with a fetch run against the local origin, restored before each. pullcom
## is one of them because its pull step only runs after a fetch, and that step used to ask
## origin a second time.
((quiet)) || fEcho_Clean "spawn counts (${exe})"
fMeasure "[EnQTUO0] status"                              14 pipe repo        -q --no-fetch status
fMeasure "[EnberSa] whoami"                               9 pipe repo        -q --no-fetch whoami
fMeasure "[EnQTUe8] br list"                              9 pipe repo        -q --no-fetch br list
fMeasure "[EnQTUuG] account list"                         9 pipe repo        -q --no-fetch account list
fMeasure "[EnQTVAO] repo url"                             8 pipe repo        -q --no-fetch repo url
fMeasure "[EnQTVQW] pullcom"                             25 pipe repo        -q --no-fetch pullcom "spawn count"
fMeasure "[ErgAQyw] pullcom with a fetch"                 32 pipe repo        -q pullcom "spawn count"
fMeasure "[EnQTVge] br switch"                           33 pipe repo        -q --no-fetch br switch main
fMeasure "[EnQTVwm] br prune"                            39 pipe repo        -q --no-fetch br prune
fMeasure "[Erg2KIz] status with a fetch"                 21 tty  repo        status
fMeasure "[Erg2KJr] status in an account folder"         25 tty  acct-ssh    --no-fetch status
fMeasure "[Erg2KKj] whoami in an account folder"         19 tty  acct-ssh    --no-fetch whoami
fMeasure "[Erg2KLb] account list with accounts"          14 tty  acct-ssh    --no-fetch account list
fMeasure "[Erg2KMS] status in an https account folder"   21 tty  acct-https  --no-fetch status

##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Each count against its limit, then against the newest previous run; then record this one.
##•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
countDir="${root}/${SPAWN_COUNT_DIR}"
mkdir -p "${countDir}"
baseline=""
for f in "${countDir}"/spawn_*.tsv; do [[ -f "${f}" ]] && baseline="${f}"; done

declare -i regressed=0 overLimit=0 underLimit=0
## One line per command, whatever it did, so a -q-less run shows each count and its verdict.
if [[ -z "${baseline}" ]]; then
	((quiet)) || fEcho_Clean "  (no baseline yet - recording this run as one)"
else
	((quiet)) || fEcho_Clean "  baseline: $(basename "${baseline}")"
fi
for ((i = 0; i < ${#labels[@]}; i++)); do
	if [[ -n "${skipped[i]}" ]]; then
		((quiet)) || fEcho_Clean "  skipped    ${ids[i]} ${labels[i]} (${skipped[i]})"
		continue
	fi
	if (( counts[i] > limits[i] )); then
		fEcho_Clean "  OVER LIMIT ${ids[i]} ${labels[i]}: ${counts[i]}, limit ${limits[i]} (expected ${expects[i]})"
		overLimit=1
		continue
	fi
	(( counts[i] < expects[i] )) && underLimit=$((underLimit + 1))
	was=""
	[[ -z "${baseline}" ]] || was="$(awk -F'\t' -v k="${labels[i]}" '$1==k{print $2}' "${baseline}" || true)"
	[[ -n "${was}" ]] || { ((quiet)) || fEcho_Clean "  NEW        ${ids[i]} ${labels[i]}: ${counts[i]}"; continue; }
	## Arithmetic on text from a file runs any $(...) in an array subscript, so only digits go on.
	[[ "${was}" =~ ^[0-9]+$ ]] || { echo "spawn-count: $(basename "${baseline}") has '${was}' for ${labels[i]}, which isn't a count. Fix or delete that file." >&2; exit 1; }
	if (( counts[i] > was + $(fHeadroom "${was}") )); then
		fEcho_Clean "  REGRESSED  ${ids[i]} ${labels[i]}: ${was} -> ${counts[i]}"
		regressed=1
	elif (( counts[i] < was )); then
		((quiet)) || fEcho_Clean "  improved   ${ids[i]} ${labels[i]}: ${was} -> ${counts[i]}, expected ${expects[i]}"
	else
		((quiet)) || fEcho_Clean "  ok         ${ids[i]} ${labels[i]}: ${counts[i]}"
	fi
done
((quiet)) || ((underLimit == 0)) || fEcho_Clean "  ${underLimit} under their expected count; lower those numbers in ${BASH_SOURCE[0]##*/} to keep the gain."

if ((overLimit)); then
	echo "spawn counts went over their limits; nothing recorded." >&2
	echo "  A deliberate rise raises the expected count beside the command in ${BASH_SOURCE[0]##*/}." >&2
	exit 1
fi
if ((regressed)) && ((! record)); then
	echo "spawn counts regressed against $(basename "${baseline}"); nothing recorded." >&2
	echo "  Re-run with --record to accept the new counts as the baseline." >&2
	exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out="${countDir}/spawn_${stamp}.tsv"
: > "${out}"
for ((i = 0; i < ${#labels[@]}; i++)); do
	[[ -n "${skipped[i]}" ]] || printf '%s\t%s\n' "${labels[i]}" "${counts[i]}" >> "${out}"
done
gfs_rotate "${countDir}" spawn tsv >/dev/null 2>&1 || true
((quiet)) || fEcho_Clean "  recorded $(basename "${out}")"


##	History:
##		- 20260819 JC: Created. The profiling step, as spawn counting rather than as a sampling
##		  profile: this program is blocked on git for effectively all of its wall clock, so a
##		  flamegraph has no leaders in it. Each command is measured against a restored fixture,
##		  origin included - prune deletes on both sides, and a leftover makes the next count a
##		  different question.
##		- 20260926 JC: One line per command with its verdict, ok included, in place of the bare counts. The pipeline no longer passes -q.
##		- 20260927 JC: Each command carries a test ID, printed on its line.
##		- 20261003 JC: A limit per command that fails at any rise, --record or not. An account folder with a fake gh and ssh, a pty run with no -q, and a status that fetches, for status, whoami and the account listing.
##		- 20261003 JC: pullcom with a fetch, so the pull step is counted.
##		- 20261003 JC: The number beside each command is the expected count, and its limit adds the same headroom the baseline compare allows, so a git update that starts one more helper doesn't fail the gate.
