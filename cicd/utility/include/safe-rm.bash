#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

## fSafeRm PATH: the one way a pipeline script removes a folder. One absolute path, under a folder
## named tmp or under the run's own ${HOST_TEMP}/<app>/, and not through a link. HOST_TEMP is the
## caller's, resolved with realpath once at its start, since a temp folder can sit behind a link
## (macOS's /var). Uses the caller's APP_NAME. A copy of the box-wide guard, since a clone or
## another box has none.

fSafeRm(){
	local p="${1:-}" real='' own="${HOST_TEMP:?}/${APP_NAME:?}"
	if [[ "${#}" -ne 1 || -z "${p}" || "${p}" == *..* || "${p}" == *//* || "${p}" == *$'\n'* ]]; then
		printf 'safe-rm: refused, bad path: "%s"\n' "${p}" >&2; return 1
	fi
	p="${p%/}"
	if ! [[ "${p}" =~ ^/(.+/)?tmp/[^/]+(/[^/]+)*$ || "${p}" == "${own}"/?* ]]; then
		printf 'safe-rm: refused, not under a tmp folder: %s\n' "${p}" >&2; return 1
	fi
	if [[ -L "${p}" ]]; then printf 'safe-rm: refused, a link: %s\n' "${p}" >&2; return 1; fi
	real="$(realpath -e -- "${p}" 2> /dev/null)" || { printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; }
	if [[ "${real}" != "${p}" ]]; then printf 'safe-rm: refused, goes through a link: %s\n' "${p}" >&2; return 1; fi
	rm -rf --one-file-system -- "${p}" && printf 'removed %s\n' "${p}"
}


##	History:
##		- 2026-10-25 JC: Created, from the shared safe removal guard.
