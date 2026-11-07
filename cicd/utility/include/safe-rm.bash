#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

## fSafeRm PATH: the one way a pipeline script removes a folder. One absolute path, under a folder
## named tmp or under the run's own ${HOST_TEMP}/<app>/, and not through a link. HOST_TEMP is the
## caller's, resolved once at its start, since a temp folder can sit behind a link (macOS's
## /var). Uses the caller's APP_NAME. A copy of the box-wide guard, since a clone or another box
## has none. No realpath: BSD's has no -e, and older macOS has none at all.

## BSD rm spells --one-file-system -x.
__safeRmOneFs='--one-file-system'; rm --version >/dev/null 2>&1 || __safeRmOneFs='-x'

## Never HOST_TEMP itself, nor a project's whole folder right under it, where other runs keep theirs.
fSafeRm_Takes(){
	[[ "${1}" =~ ^/(.+/)?tmp/[^/]+(/[^/]+)*$ || "${1}" == "${HOST_TEMP:?}/${APP_NAME:?}"/?* ]] || return 1
	[[ "${1}" != "${HOST_TEMP}" && ( "${1}" != "${HOST_TEMP}"/* || "${1#"${HOST_TEMP}"/}" == */* ) ]]
}

fSafeRm(){
	local p="${1:-}" real=''
	if [[ "${#}" -ne 1 || -z "${p}" || "${p}" == *..* || "${p}" == *//* || "${p}" == *$'\n'* ]]; then
		printf 'safe-rm: refused, bad path: "%s"\n' "${p}" >&2; return 1
	fi
	p="${p%/}"
	if ! fSafeRm_Takes "${p}"; then
		printf 'safe-rm: refused, not under a tmp folder, or a whole project temp folder: %s\n' "${p}" >&2; return 1
	fi
	if [[ -L "${p}" ]]; then printf 'safe-rm: refused, a link: %s\n' "${p}" >&2; return 1; fi
	if [[ ! -e "${p}" ]]; then printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; fi
	real="$(cd -P -- "${p%/*}/" 2> /dev/null && pwd -P)" || { printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; }
	if [[ "${real%/}/${p##*/}" != "${p}" ]]; then printf 'safe-rm: refused, goes through a link: %s\n' "${p}" >&2; return 1; fi
	rm -r -f "${__safeRmOneFs}" -- "${p}" && printf 'removed %s\n' "${p}"
}

## fSafeRm_Under PARENT PATH...: the guard for a folder outside any temp root, such as a module
## cache in a volume. Each PATH is strictly under PARENT, which has no link in it, and neither
## PATH nor anything between is a link. All or none: one refused, nothing goes. Made writable
## first, since go leaves what it extracts read-only. Quiet on success.
fSafeRm_Under(){
	local parent="${1:-}" p cur rel
	shift || true
	parent="${parent%/}"
	if [[ "${parent}" != /?* || "${parent}" == *..* || "${parent}" == *//* || "${parent}" == *$'\n'* || ! -d "${parent}" ]] \
		|| [[ "$(cd -P -- "${parent}" 2> /dev/null && pwd -P)" != "${parent}" ]]; then
		printf 'safe-rm: refused, bad parent or one through a link: "%s"\n' "${parent}" >&2; return 1
	fi
	(($#)) || return 0
	for p in "$@"; do
		if [[ "${p}" != "${parent}"/?* || "${p}" == *..* || "${p}" == *//* || "${p}" == *$'\n'* || "${p}" == */ ]]; then
			printf 'safe-rm: refused, not under %s: "%s"\n' "${parent}" "${p}" >&2; return 1
		fi
		cur="${parent}"; rel="${p#"${parent}"/}/"
		while [[ -n "${rel}" ]]; do
			cur+="/${rel%%/*}"; rel="${rel#*/}"
			if [[ -L "${cur}" ]]; then printf 'safe-rm: refused, a link or through one: %s\n' "${p}" >&2; return 1; fi
		done
	done
	chmod -R u+w -- "$@" 2> /dev/null || true
	rm -r -f "${__safeRmOneFs}" -- "$@"
}

## The same, for a path that may not be there yet. Quiet on success.
fSafeRm_IfThere(){ if [[ -e "${1:-}" || -L "${1:-}" ]]; then fSafeRm "${1:-}" >/dev/null; fi ;}

## For a script that may run outside cicd.bash: HOST_TEMP resolved and exported.
fSafeRm_Init(){
	HOST_TEMP="$(cd -P -- "${HOST_TEMP:-${TMPDIR:-/tmp}}" 2> /dev/null && pwd -P)" || { printf 'safe-rm: no temp folder at %s\n' "${HOST_TEMP:-${TMPDIR:-/tmp}}" >&2; return 1; }
	export HOST_TEMP
}

## After fSafeRm_Init, the folder a script's mktemp goes in. TMPDIR, resolved, unless the guard
## wouldn't take what's made there, as on macOS, and then ${HOST_TEMP}/<app>. Under cicd.bash,
## TMPDIR is the run's folder.
fSafeRm_Tmp(){
	local t
	t="$(cd -P -- "${TMPDIR:-/tmp}" 2> /dev/null && pwd -P)" || { printf 'safe-rm: no temp folder at %s\n' "${TMPDIR:-/tmp}" >&2; return 1; }
	t="${t%/}"
	if ! fSafeRm_Takes "${t}/x"; then t="${HOST_TEMP%/}/${APP_NAME:?}"; mkdir -p -- "${t}" || return 1; fi
	printf '%s\n' "${t}"
}


##	History:
##		- 2026-10-25 JC: Created, from the shared safe removal guard.
##		- 2026-11-06 JC: No realpath, and rm's -x where it has no --one-file-system, so the harnesses can use it on the Mac and BSD boxes. fSafeRm_IfThere, fSafeRm_Init and fSafeRm_Tmp for the harnesses and utilities. Refuses HOST_TEMP and a project's whole folder under it, as the shared guard has since 2026-10-28.
##		- 2026-11-06 JC: fSafeRm_Under, for the Go module cache in the cache volume.
