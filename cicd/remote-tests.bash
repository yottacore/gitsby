#!/usr/bin/env bash

##	Purpose:
##		- Runs the tests on a Mac and a Windows box over ssh. cicd.bash stage 7 runs it on a
##		  full run, or run it alone.
##		- Mac: the Go tests, cross-built for it, then test.bash against the universal build.
##		  Both run in a copy of this tree, git dir included, in the stage's own folder under
##		  the box's home, replaced each run. The suite reads the history and builds offline, so
##		  the box fetches the Go modules first.
##		- Other Unix boxes, such as FreeBSD and Linux arm64: the same as the Mac, as each box's
##		  test user, against the build given for its target. test.bash runs only where the box
##		  has the tools it needs, and the Go tests run either way.
##		- Windows: the Go tests, cross-built, in a folder under %TEMP% made for the run and
##		  removed after it. There is no bash on those boxes to run the suite with.
##		- Each box is taken through the host lock for the length of its run, and only if it is
##		  free right now. A box that is off, unreachable or taken by someone else is skipped
##		  with a note, and so is the whole stage when there is no lock script. Every Mac and
##		  Unix box in the list runs; of the Windows boxes, the first free one does.
##		- The boxes, the lock and the paths are in config.bash, under stage 7.
##	Syntax:
##		cicd/remote-tests.bash [--mac-bin FILE] [--bin GOOS/GOARCH FILE]...
##		  --mac-bin FILE  the universal build test.bash runs against on the Mac. Without it the
##		                  Mac runs the Go tests only.
##		  --bin T FILE    the same for the Unix boxes whose target is T, such as freebsd/amd64.
##		  (--held is how the script calls itself under the lock, and is not for use by hand.)
##	Exit: 0 nothing failed, skipped boxes included; 1 a test failed, or a box could not be set
##	      up for one; 2 bad usage.
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
# shellcheck source=/dev/null
source "${here}/config.bash"
# shellcheck source=/dev/null
source "${here}/utility/include/go-test-lines.bash"

macBin=""; held=()
declare -A unixBin=()
while (($#)); do case "$1" in
	--mac-bin) [[ -n "${2:-}" ]] || { echo "--mac-bin needs a file" >&2; exit 2; }; macBin="$2"; shift 2 ;;
	--bin)     [[ "${2:-}" == */* && -n "${3:-}" ]] || { echo "--bin needs a target like freebsd/amd64, then a file" >&2; exit 2; }
	           [[ -f "$3" ]] || { echo "--bin: no such file: $3" >&2; exit 2; }
	           unixBin["$2"]="$3"; shift 3 ;;
	--held)    (($# >= 4)) || { echo "--held needs a kind, a lock name and an ssh name" >&2; exit 2; }; held=("$2" "$3" "$4"); shift 4 ;;
	-h|--help) sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*)         echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done
[[ -z "${macBin}" || -f "${macBin}" ]] || { echo "--mac-bin: no such file: ${macBin}" >&2; exit 2; }
for spec in "${REMOTE_UNIX_HOSTS[@]}"; do
	[[ "${REMOTE_UNIX_TARGETS[${spec%%:*}]:-}" == */* ]] || { echo "config.bash: REMOTE_UNIX_TARGETS has no target like freebsd/amd64 for ${spec%%:*}" >&2; exit 2; }
done

fEcho_Clean(){ printf '%s\n' "$*"; }

## No prompt can be answered here, a dead box must not hang the run, and a box that drops
## mid-run must not either.
sshOpts=(-o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
## The first line each remote command prints. The Mac's shell startup file prints on every ssh
## command, which no ssh option turns off, and it breaks rsync and scp the same way.
mark="@@gitsby-remote-tests@@"
## Proves the folder on the Mac is this stage's before anything in it is removed.
ownMark=".gitsby-remote-tests"

## Runs the command $2 on $1, printing only what follows the marker it must echo first. The
## rest of the arguments go to ssh before the host. Returns ssh's status, which is the
## command's own, or 255 when the connection failed.
fRemote(){
	local host="$1" cmd="$2"
	shift 2
	# shellcheck disable=SC2029  ## built here on purpose; the remote parts are escaped.
	if ssh "${sshOpts[@]}" "$@" "${host}" "${cmd}" | tr -d '\r' | sed -u "0,/^${mark}[[:space:]]*\$/d"; then return 0; fi
	return "${PIPESTATUS[0]}"
}

## The lock name of a host entry, and its ssh names, comma separated.
fLockName(){ echo "${1%%:*}" ;}
fSshNames(){ if [[ "$1" == *:* ]]; then echo "${1#*:}"; else echo "$1"; fi ;}

## The first ssh name of the entry $1 that answers, or nothing.
fReachable(){
	local name
	local -a names
	IFS=, read -ra names <<< "$(fSshNames "$1")"
	for name in "${names[@]}"; do
		if ssh "${sshOpts[@]}" -n "${name}" exit 0 >/dev/null 2>&1; then echo "${name}"; return 0; fi
	done
	return 0
}

## The Go tests built for $1/$2 into the file $3.
fBuildTests(){
	(cd "${root}/${GO_MODULE_DIR}" && CGO_ENABLED=0 GOOS="$1" GOARCH="$2" GOMAXPROCS="${BUILD_JOBS}" go test -c -p "${BUILD_JOBS}" -o "$3" .)
}

## NUL-separated paths in, the ones that exist out. A tracked file deleted in the tree is still
## listed by git, and tar would stop on it.
fExisting(){
	local f
	while IFS= read -r -d '' f; do
		if [[ -e "${root}/${f}" || -L "${root}/${f}" ]]; then printf '%s\0' "${f}"; fi
	done
}

## Prints "test result" lines for a run that failed: what go test printed, less the passes.
fGoTestFailures(){ grep -vE '^ *(=== (RUN|PAUSE|CONT|NAME)|--- (PASS|SKIP))' "$1" || true ;}

fResult(){ echo "$2" > "${work}/result-$1" ;}

## A target's name in file names: freebsd/amd64 -> freebsd-amd64.
fTag(){ echo "${1/\//-}" ;}

## Under the lock: the Mac or other Unix box $2, reached as $3, by the kind $1. Both get a copy
## of the tree in the stage's folder under the box's home, run the Go tests built for them there,
## then test.bash against the build given for them.
fRunPosix(){
	local kind="$1" lockName="$2" sshName="$3" rc=0 failed=0 dir log="${work}/gotest-$2.log" bashDir
	local target tarFile hasBin binName suiteCmd missing="" fetch="go mod download"
	if [[ "${kind}" == mac ]]; then
		target="darwin/${REMOTE_MAC_GOARCH}" tarFile="${work}/mac.tar" hasBin="${work}/mac-has-bin" binName="the universal build"
		printf -v dir '%q' "${REMOTE_MAC_DIR}"
		## Homebrew's bash first, so the scripts the suite starts by their shebang get it too.
		printf -v bashDir '%q' "$(dirname "${REMOTE_MAC_BASH}")"
		suiteCmd="PATH=${bashDir}:\"\$PATH\" ${REMOTE_MAC_BASH} cicd/test.bash"
	else
		target="${REMOTE_UNIX_TARGETS[${lockName}]}"
		tarFile="${work}/unix-$(fTag "${target}").tar" hasBin="${work}/has-bin-$(fTag "${target}")" binName="the ${target} build"
		printf -v dir '%q' "${REMOTE_UNIX_DIR}"
		suiteCmd="bash cicd/test.bash"
		## Only the suite needs these, so a box without them still runs the Go tests.
		missing="$(fRemote "${sshName}" "echo ${mark}; for t in ${REMOTE_UNIX_NEEDS[*]}; do command -v \"\$t\" >/dev/null 2>&1 || printf '%s ' \"\$t\"; done" -n)" || rc=$?
		if ((rc)); then fEcho_Clean "  skip: ${lockName}, lost the connection while looking for its tools"; fResult "${lockName}" lost; return 0; fi
		read -r missing <<< "${missing}"
		if [[ -n "${missing}" || ! -f "${hasBin}" ]]; then fetch=":"; fi
	fi
	fEcho_Clean "  ${lockName}: copying the tree to ~/${dir}/tree"
	## The marker is checked again right before the removal, and a folder without it is not
	## this stage's to touch.
	fRemote "${sshName}" "echo ${mark}
		set -e
		d=\"\$HOME/${dir}\"
		if [ -e \"\$d\" ] && [ ! -f \"\$d/${ownMark}\" ]; then echo \"\$d is not this stage's folder, so it was left alone\" >&2; exit 3; fi
		mkdir -p \"\$d\"
		: > \"\$d/${ownMark}\"
		if [ -f \"\$d/${ownMark}\" ]; then rm -rf \"\$d/tree\"; fi
		tar -xf - -C \"\$d\"
		cd \"\$d/tree/${GO_MODULE_DIR}\"
		${fetch}" < "${tarFile}" || rc=$?
	if ((rc == 255)); then fEcho_Clean "  skip: ${lockName}, lost the connection while copying the tree"; fResult "${lockName}" lost; return 0; fi
	if ((rc)); then fEcho_Clean "  FAIL: ${lockName}, could not copy the tree or fetch the Go modules (exit ${rc})"; fResult "${lockName}" fail; return 0; fi

	fEcho_Clean "  ${lockName}: go test (${target})"
	rc=0
	fRemote "${sshName}" "echo ${mark}; cd \"\$HOME/${dir}/tree/${GO_MODULE_DIR}\" && ./${EXE_NAME}-test -test.v" -n >"${log}" 2>&1 || rc=$?
	if ((rc == 255)); then fEcho_Clean "  skip: ${lockName}, lost the connection during go test"; fResult "${lockName}" lost; return 0; fi
	fGoTestLines "${log}" "${root}/${GO_MODULE_DIR}"
	if ((rc)); then fGoTestFailures "${log}"; fEcho_Clean "  FAIL: ${lockName} go test"; failed=1; fi

	if [[ ! -f "${hasBin}" ]]; then
		if [[ "${kind}" == mac ]]; then fEcho_Clean "  skip: test.bash on ${lockName}, since no universal build was given (--mac-bin)"
		else fEcho_Clean "  skip: test.bash on ${lockName}, since no ${target} build was given (--bin)"; fi
	elif [[ -n "${missing}" ]]; then
		fEcho_Clean "  skip: test.bash on ${lockName}, which lacks: ${missing}"
	else
		fEcho_Clean "  ${lockName}: test.bash against ${binName}"
		rc=0
		fRemote "${sshName}" "echo ${mark}; cd \"\$HOME/${dir}/tree\" && ${suiteCmd}" -n || rc=$?
		if ((rc == 255)); then fEcho_Clean "  skip: ${lockName}, lost the connection during test.bash"; fResult "${lockName}" lost; return 0; fi
		if ((rc)); then fEcho_Clean "  FAIL: ${lockName} test.bash"; failed=1; fi
	fi
	if ((failed)); then fResult "${lockName}" fail; else fResult "${lockName}" pass; fi
}

## Under the lock: the Windows box $1, reached as $2. The commands are cmd's, which is where
## ssh lands there.
fRunWindows(){
	local lockName="$1" sshName="$2" rc=0 log="${work}/gotest-$1.log" setupLog="${work}/setup-$1.log" dir
	dir="%TEMP%\\test_gitsby_$(date +%Y%m%d-%H%M%S%2N)"
	fEcho_Clean "  ${lockName}: copying the Go tests to ${dir}"
	## "made" says mkdir made the folder, so it is this run's to remove whatever fails after.
	fRemote "${sshName}" "echo ${mark}& mkdir \"${dir}\" && echo made&& %SystemRoot%\\System32\\tar.exe -xf - -C \"${dir}\"" < "${work}/win.tar" >"${setupLog}" 2>&1 || rc=$?
	if ((rc == 0)); then
		fEcho_Clean "  ${lockName}: go test (windows/amd64)"
		fRemote "${sshName}" "echo ${mark}& cd /d \"${dir}\\${GO_MODULE_DIR}\" && ${EXE_NAME}-test.exe -test.v" -n >"${log}" 2>&1 || rc=$?
	fi
	if grep -qx made "${setupLog}"; then
		fRemote "${sshName}" "echo ${mark}& cd /d \"%TEMP%\" && rmdir /s /q \"${dir}\"" -n >/dev/null 2>&1 || true
	fi
	if ((rc == 255)); then fEcho_Clean "  skip: ${lockName}, lost the connection"; fResult "${lockName}" lost; return 0; fi
	if [[ ! -s "${log}" ]]; then
		grep -vx made "${setupLog}" || true
		fEcho_Clean "  FAIL: ${lockName}, could not copy the Go tests (exit ${rc})"; fResult "${lockName}" fail; return 0
	fi
	fGoTestLines "${log}" "${root}/${GO_MODULE_DIR}"
	if ((rc)); then
		fGoTestFailures "${log}"
		fEcho_Clean "  FAIL: ${lockName} go test (exit ${rc})"
		fResult "${lockName}" fail
	else
		fResult "${lockName}" pass
	fi
}

## The second half of a run: this script again, started by the lock's wrap once it holds the box.
if ((${#held[@]})); then
	work="${REMOTE_TESTS_WORK:?--held runs only under the lock, started by this script}"
	if [[ -n "${REMOTE_TESTS_ERR_FD:-}" ]]; then exec 2>&"${REMOTE_TESTS_ERR_FD}"; fi
	: > "${work}/started-${held[1]}"
	case "${held[0]}" in
		mac|unix) fRunPosix "${held[0]}" "${held[1]}" "${held[2]}" ;;
		windows)  fRunWindows "${held[1]}" "${held[2]}" ;;
		*)        echo "--held: unknown kind '${held[0]}'" >&2; exit 2 ;;
	esac
	exit 0
fi

lock=""
mapfile -t lockFound < <(compgen -G "${REMOTE_LOCK_GLOB}" || true)
for f in "${lockFound[@]}"; do
	if [[ -x "${f}" ]]; then lock="${f}"; break; fi
done
if [[ -z "${lock}" ]]; then
	fEcho_Clean "  skip: every box, since there is no host lock script (${REMOTE_LOCK_GLOB})"
	exit 0
fi
## The lock reads its settings from variables named after its own file. It keeps two host
## lists, and hands out only the Windows one for 'any' and 'all', so a Mac or Unix box goes in
## the other.
## That one starts from the lock's own, so its status still lists the rest while this runs. An
## older lock has no other list and refuses those by name, which skips each with that note.
## A caller with a session id is taken to be the whole session, and one that misses keeps its
## place in line for minutes, holding the box back from others, so the lock is asked as a
## plain process, whose place goes when it exits.
lockVar="${lock##*/}"; lockVar="${lockVar%%_*}"; lockVar="${lockVar^^}"
declare -a winNames=()
for spec in "${REMOTE_WINDOWS_HOSTS[@]}"; do winNames+=("$(fLockName "${spec}")"); done
lockWin="${winNames[*]}"
lockOther=" $(env "${lockVar}_WINDOWS_HOSTS=${lockWin}" "${lock}" hosts 2>/dev/null || true) "
for name in "${winNames[@]}"; do lockOther="${lockOther// ${name} / }"; done
for spec in "${REMOTE_MAC_HOSTS[@]}" "${REMOTE_UNIX_HOSTS[@]}"; do
	name="$(fLockName "${spec}")"
	[[ "${lockOther}" == *" ${name} "* ]] || lockOther+="${name} "
done
read -r lockOther <<< "${lockOther}"
fLock(){ env -u "${lockVar}_CODE_SESSION_ID" -u "${lockVar}_PID" "${lockVar}_WINDOWS_HOSTS=${lockWin}" "${lockVar}_OTHER_HOSTS=${lockOther}" "${lock}" "$@" ;}

work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-remote.XXXXXX")"
trap 'rm -rf -- "${work:?}"' EXIT

declare -a macRun=() unixRun=() winRun=()
declare -A unixTargets=()
for spec in "${REMOTE_MAC_HOSTS[@]}"; do
	name="$(fReachable "${spec}")"
	if [[ -n "${name}" ]]; then macRun+=("$(fLockName "${spec}") ${name}")
	else fEcho_Clean "  skip: $(fLockName "${spec}"), not reachable over ssh (tried $(fSshNames "${spec}"))"; fi
done
for spec in "${REMOTE_UNIX_HOSTS[@]}"; do
	name="$(fReachable "${spec}")"
	if [[ -n "${name}" ]]; then
		unixRun+=("$(fLockName "${spec}") ${name}")
		unixTargets["${REMOTE_UNIX_TARGETS[$(fLockName "${spec}")]}"]=1
	else fEcho_Clean "  skip: $(fLockName "${spec}"), not reachable over ssh (tried $(fSshNames "${spec}"))"; fi
done
for spec in "${REMOTE_WINDOWS_HOSTS[@]}"; do
	name="$(fReachable "${spec}")"
	if [[ -n "${name}" ]]; then winRun+=("$(fLockName "${spec}") ${name}")
	else fEcho_Clean "  skip: $(fLockName "${spec}"), not reachable over ssh (tried $(fSshNames "${spec}"))"; fi
done

## Built before any box is taken, so none is held while this compiles.
if ((${#macRun[@]})); then
	mkdir -p "${work}/mac/tree/${GO_MODULE_DIR}"
	fBuildTests darwin "${REMOTE_MAC_GOARCH}" "${work}/mac/tree/${GO_MODULE_DIR}/${EXE_NAME}-test" \
		|| { fEcho_Clean "  FAIL: the Go tests do not build for darwin/${REMOTE_MAC_GOARCH}"; exit 1; }
	if [[ -n "${macBin}" ]]; then
		cp -f -- "${macBin}" "${work}/mac/tree/${GO_MODULE_DIR}/${EXE_NAME}"
		chmod +x "${work}/mac/tree/${GO_MODULE_DIR}/${EXE_NAME}"
		: > "${work}/mac-has-bin"
	fi
fi
for target in "${!unixTargets[@]}"; do
	tag="$(fTag "${target}")"
	mkdir -p "${work}/unix-${tag}/tree/${GO_MODULE_DIR}"
	fBuildTests "${target%%/*}" "${target##*/}" "${work}/unix-${tag}/tree/${GO_MODULE_DIR}/${EXE_NAME}-test" \
		|| { fEcho_Clean "  FAIL: the Go tests do not build for ${target}"; exit 1; }
	if [[ -n "${unixBin[${target}]:-}" ]]; then
		cp -f -- "${unixBin[${target}]}" "${work}/unix-${tag}/tree/${GO_MODULE_DIR}/${EXE_NAME}"
		chmod +x "${work}/unix-${tag}/tree/${GO_MODULE_DIR}/${EXE_NAME}"
		: > "${work}/has-bin-${tag}"
	fi
done
if ((${#macRun[@]} + ${#unixRun[@]})); then
	## The tree as it stands, tracked files and new ones not ignored, which is what the
	## pipeline tests here. Then the git dir. In a linked worktree that is the main one's, with
	## this worktree's HEAD and index laid over it. The pre-push gate's snapshot is a whole
	## second tree, and nothing on the boxes uses it. Each box's builds go on a copy of that.
	(cd "${root}" && git ls-files -z -co --exclude-standard) | fExisting > "${work}/tree.files"
	tar -cf "${work}/tree.tar" -C "${root}" --null -T "${work}/tree.files" --transform 's,^,tree/,S'
	gitDir="$(cd "${root}" && cd "$(git rev-parse --git-dir)" && pwd -P)"
	gitCommon="$(cd "${root}" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
	tar -rf "${work}/tree.tar" -C "${gitCommon}" --exclude='./gitsby-gate*' --exclude=./worktrees --transform 's,^\.,tree/.git,S' .
	if [[ "${gitDir}" != "${gitCommon}" ]]; then
		mkdir -p "${work}/linked/tree/.git"
		cp -f -- "${gitDir}/HEAD" "${gitDir}/index" "${work}/linked/tree/.git/"
		tar -rf "${work}/tree.tar" -C "${work}/linked" tree/.git
	fi
	if ((${#macRun[@]})); then
		cp -f -- "${work}/tree.tar" "${work}/mac.tar"
		tar -rf "${work}/mac.tar" -C "${work}/mac" "tree/${GO_MODULE_DIR}"
	fi
	for target in "${!unixTargets[@]}"; do
		tag="$(fTag "${target}")"
		cp -f -- "${work}/tree.tar" "${work}/unix-${tag}.tar"
		tar -rf "${work}/unix-${tag}.tar" -C "${work}/unix-${tag}" "tree/${GO_MODULE_DIR}"
	done
	rm -f -- "${work:?}/tree.tar"
fi
if ((${#winRun[@]})); then
	mkdir -p "${work}/win/${GO_MODULE_DIR}"
	fBuildTests windows amd64 "${work}/win/${GO_MODULE_DIR}/${EXE_NAME}-test.exe" \
		|| { fEcho_Clean "  FAIL: the Go tests do not build for windows/amd64"; exit 1; }
	## Some tests read the module's own source and testdata from where they run.
	(cd "${root}" && git ls-files -z -co --exclude-standard -- "${GO_MODULE_DIR}") | fExisting > "${work}/win.files"
	tar -cf "${work}/win.tar" -C "${root}" --null -T "${work}/win.files"
	tar -rf "${work}/win.tar" -C "${work}/win" "${GO_MODULE_DIR}/${EXE_NAME}-test.exe"
fi

## Runs the kind $1 on the box $2, reached as $3, under the lock, and prints why when the lock
## would not have it. True when the box ran, whatever the result.
exec {errFd}>&2
fUnderLock(){
	local kind="$1" lockName="$2" sshName="$3" rc=0 errFile="${work}/lock-$2.err" why=""
	REMOTE_TESTS_WORK="${work}" REMOTE_TESTS_ERR_FD="${errFd}" \
		fLock wrap "${lockName}" --wait 0 --why "gitsby: ${kind} tests" -- "${here}/${BASH_SOURCE[0]##*/}" --held "${kind}" "${lockName}" "${sshName}" 2>"${errFile}" || rc=$?
	if [[ -e "${work}/started-${lockName}" ]]; then
		[[ -e "${work}/result-${lockName}" ]] || { fEcho_Clean "  FAIL: ${lockName}, the run ended early (exit ${rc})"; fResult "${lockName}" fail; }
		[[ "$(< "${work}/result-${lockName}")" != lost ]]
		return
	fi
	case "${rc}" in
		3)  why="$(sed -n 's/^still queued: .* is held by /held by /p' "${errFile}" | head -n 1)"
		    fEcho_Clean "  skip: ${lockName}, ${why:-taken by another session}" ;;
		75) fEcho_Clean "  skip: ${lockName}, the lock's state is busy" ;;
		*)  fEcho_Clean "  skip: ${lockName}, the lock would not take it (exit ${rc}): $(head -n 1 "${errFile}")" ;;
	esac
	return 1
}

for entry in "${macRun[@]}"; do fUnderLock mac "${entry% *}" "${entry#* }" || true; done
for entry in "${unixRun[@]}"; do fUnderLock unix "${entry% *}" "${entry#* }" || true; done
for entry in "${winRun[@]}"; do
	if fUnderLock windows "${entry% *}" "${entry#* }"; then break; fi
done
exec {errFd}>&-

shopt -s nullglob
failed=(); passed=()
for f in "${work}"/result-*; do
	case "$(< "${f}")" in
		pass) passed+=("${f##*/result-}") ;;
		fail) failed+=("${f##*/result-}") ;;
	esac
done
shopt -u nullglob
if ((${#failed[@]})); then
	fEcho_Clean "  passed on: ${passed[*]:-none}; failed on: ${failed[*]}"
	exit 1
fi
fEcho_Clean "  passed on: ${passed[*]:-none}"


##	History:
##		- 2026-10-04 JC: Created. The Go tests on a Mac and a Windows box, and test.bash on the Mac against the universal build, each box taken through the host lock and skipped when it is off or taken.
##		- 2026-10-04 JC: The same run as the Mac's on other Unix boxes, FreeBSD amd64 and Linux arm64 to start, each as its test user. test.bash there only where the box has the tools for it.
