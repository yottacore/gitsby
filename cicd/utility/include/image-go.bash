#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

## fImageGo DIR OUT_DIR [NAME=value]... ARG...: 'go ARG...' in DIR, with those variables set.
## OUT_DIR is where its -o file goes.
##
## With GITSBY_CICD_IMAGE set, go is the image's, so a build copied into place or sent to another
## box comes from the same toolchain as the checks. cicd.bash sets it once the image is there, and
## stage 7 hands it on to remote-tests.bash. Without it, go is this box's. The tree and OUT_DIR
## are mounted at their own paths, and the Go caches are the named volume the full run uses.
## The container gets the caller's BUILD_JOBS as its quota, and go runs niced in there, since
## the caller's nice stops at the docker client. Uses the caller's root and APP_NAME. The
## container is labeled and named for the run's folder, GITSBY_CICD_RUN, so cicd.bash can remove
## what a stopped run left.

fImageGo(){
	local dir="$1" outDir="$2" name="" n=0
	local -a vars=() dockerVars=() mounts=() rmOpt=(--rm)
	shift 2
	while (($#)) && [[ "$1" =~ ^[A-Z_][A-Z0-9_]*= ]]; do vars+=("$1"); dockerVars+=(-e "$1"); shift; done
	if [[ -z "${GITSBY_CICD_IMAGE:-}" ]]; then
		(cd "${dir}" && env ${vars[@]+"${vars[@]}"} go "$@")
		return
	fi
	mounts=(-v "${root:?}:${root}" -v "${APP_NAME:?}-cicd-cache:/cache" --tmpfs "/tmp:rw,exec,mode=1777")
	[[ "${outDir}" == "${root}" || "${outDir}" == "${root}/"* ]] || mounts+=(-v "${outDir}:${outDir}")
	## A release builds its tag from an export outside the tree.
	[[ "${dir}" == "${root}" || "${dir}" == "${root}/"* || "${dir}" == "${outDir}" || "${dir}" == "${outDir}/"* ]] || mounts+=(-v "${dir}:${dir}")
	## cicd.bash --keep-temp sets it, and lists what it kept by the run label.
	[[ -z "${GITSBY_CICD_KEEP_TEMP:-}" ]] || rmOpt=()
	## Kept containers hold their names, and stage 7's harness builds under the same run.
	while :; do
		n=$((n + 1)); name="${APP_NAME}-${GITSBY_CICD_RUN:-run}-go-${1:-}-${n}"
		[[ -n "$(docker ps -aq --filter "name=^/${name}\$" 2>/dev/null || true)" ]] || break
	done
	docker run ${rmOpt[@]+"${rmOpt[@]}"} --init --name "${name}" --label "dev.project=${APP_NAME}" --label "dev.run=${GITSBY_CICD_RUN:-}" \
		--cpus "${BUILD_JOBS:-1}" --cpu-shares 256 \
		--user "$(id -u):$(id -g)" "${mounts[@]}" ${dockerVars[@]+"${dockerVars[@]}"} -w "${dir}" \
		"${GITSBY_CICD_IMAGE}" nice -n 19 go "$@" &
	## So the caller's INT or TERM trap runs at once, and not when the build ends.
	wait "$!"
}

## fImageRecipe: the pinned image's tag in containerImage, and its build args in containerArgs.
## The versions come from config.bash, and the tag hashes the recipe plus those, so a bumped
## version can't run on the old image. Uses the caller's here, APP_NAME and fDie.
fImageRecipe(){
	local recipe="${here:?}/container/Dockerfile" toolSpec toolName
	[[ -f "${recipe}" ]] || fDie "missing ${recipe}"
	containerArgs=(--build-arg "VER_go=${GO_RELEASE_TOOLCHAIN#go}")
	for toolSpec in "${GO_TOOL_VERSIONS[@]}" "${TOOL_VERSIONS[@]}"; do
		toolName="${toolSpec%%=*}"; toolName="VER_${toolName//-/_}"
		grep -qxF "ARG ${toolName}" "${recipe}" || fDie "config.bash pins ${toolSpec%%=*}, and the container recipe has no ARG ${toolName} for it"
		containerArgs+=(--build-arg "${toolName}=${toolSpec#*=}")
	done
	containerArgs+=(--build-arg "CODEQL_SHA256=${CODEQL_SHA256}" --build-arg "CODEQL_PY_SHA256=${CODEQL_PY_SHA256}")
	## In the tag's hash, so an image from before the labels is built again with them.
	containerArgs+=(--label "dev.project=${APP_NAME}")
	## The Python tools' lock is the other file the recipe copies in.
	containerImage="${APP_NAME}-cicd:$( { cat "${recipe}" "${here}/container/requirements.txt"; printf '%s\n' "${containerArgs[@]}"; } | git hash-object --stdin | cut -c1-12 )"
}

## fImageBuild RUN: builds the image fImageRecipe named when it isn't there yet, and makes the Go
## cache volume, both labeled for the run's folder RUN.
fImageBuild(){
	local run="$1"
	if docker image inspect "${containerImage:?}" >/dev/null 2>&1; then
		fEcho_Clean "image ${containerImage}"
	else
		## The one it replaces goes at the end of a cicd.bash run that passes on this one.
		fEcho_Clean "building ${containerImage}"
		docker build -q -t "${containerImage}" "${containerArgs[@]}" --label "dev.run=${run}" "${here}/container" >/dev/null || fDie "image build failed"
	fi
	## Made here rather than by the first run that mounts it, so it carries the labels.
	if ! docker volume inspect "${APP_NAME}-cicd-cache" >/dev/null 2>&1; then
		docker volume create --label "dev.project=${APP_NAME}" --label "dev.run=${run}" "${APP_NAME}-cicd-cache" >/dev/null || fDie "can't make the ${APP_NAME}-cicd-cache volume"
	fi
}


##	History:
##		- 2026-10-25 JC: Created. Dogfood's and stage 7's builds come from the image's Go, where the run uses the image.
##		- 2026-10-25 JC: The container takes the caller's core budget as its quota, at a low weight, and go runs niced in it.
##		- 2026-10-25 JC: GITSBY_CICD_KEEP_TEMP keeps the container after the build.
##		- 2026-10-25 JC: Labeled dev.project and dev.run, and named for the run's folder.
##		- 2026-10-25 JC: fImageRecipe and fImageBuild, moved here from cicd.bash so release.bash builds with the same image. A build folder outside the tree is mounted too.
