#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

## fImageGo DIR OUT_DIR [NAME=value]... ARG...: 'go ARG...' in DIR, with those variables set.
## OUT_DIR is where its -o file goes.
##
## With GITSBY_CICD_IMAGE set, go is the image's, so a build copied into place or sent to another
## box comes from the same toolchain as the checks. cicd.bash sets it once the image is there, and
## stage 7 hands it on to remote-tests.bash. Without it, go is this box's. The tree and OUT_DIR
## are mounted at their own paths, and the Go caches are the named volume the full run uses.
## Uses the caller's root and APP_NAME.

fImageGo(){
	local dir="$1" outDir="$2"
	local -a vars=() dockerVars=() mounts=()
	shift 2
	while (($#)) && [[ "$1" =~ ^[A-Z_][A-Z0-9_]*= ]]; do vars+=("$1"); dockerVars+=(-e "$1"); shift; done
	if [[ -z "${GITSBY_CICD_IMAGE:-}" ]]; then
		(cd "${dir}" && env ${vars[@]+"${vars[@]}"} go "$@")
		return
	fi
	mounts=(-v "${root:?}:${root}" -v "${APP_NAME:?}-cicd-cache:/cache" --tmpfs "/tmp:rw,exec,mode=1777")
	[[ "${outDir}" == "${root}" || "${outDir}" == "${root}/"* ]] || mounts+=(-v "${outDir}:${outDir}")
	docker run --rm --init --label "${APP_NAME}.cicd.run=${GITSBY_CICD_RUN:-}" --label "${APP_NAME}.cicd.tree=${root}" \
		--user "$(id -u):$(id -g)" "${mounts[@]}" ${dockerVars[@]+"${dockerVars[@]}"} -w "${dir}" \
		"${GITSBY_CICD_IMAGE}" go "$@"
}


##	History:
##		- 2026-10-25 JC: Created. Dogfood's and stage 7's builds come from the image's Go, where the run uses the image.
