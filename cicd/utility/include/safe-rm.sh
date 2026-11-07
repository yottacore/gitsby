#!/bin/sh

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

## fSafeRm PATH: safe-rm.bash's guard in POSIX sh, for stage 7's commands on a Mac or Unix box,
## whatever shell ssh lands in there. remote-tests.bash sends it ahead of the command that uses
## it, less these comments. The same checks: one absolute path, under a folder named tmp or
## under ${HOST_TEMP}/${APP_NAME}/, never HOST_TEMP itself nor a folder right under it, and not
## a link or through one. The caller sets HOST_TEMP to the box's temp root, resolved, and
## APP_NAME to the stage's folder under it. No realpath, and rm's -x where it has no
## --one-file-system, as in safe-rm.bash.

fSafeRm(){
	if [ "$#" -ne 1 ] || [ -z "${1}" ] || [ -z "${HOST_TEMP:-}" ] || [ -z "${APP_NAME:-}" ]; then
		printf 'safe-rm: refused, bad path or no HOST_TEMP and APP_NAME: "%s"\n' "${1:-}" >&2; return 1
	fi
	case "${1}" in *..*|*//*|*'
'*) printf 'safe-rm: refused, bad path: "%s"\n' "${1}" >&2; return 1 ;; esac
	__srP="${1%/}" __srOk=''
	case "${__srP}" in /tmp/?*|/*/tmp/?*|"${HOST_TEMP}/${APP_NAME}"/?*) __srOk=1 ;; esac
	case "${__srP}" in "${HOST_TEMP}"/*/*) ;; "${HOST_TEMP}"|"${HOST_TEMP}"/*) __srOk='' ;; esac
	if [ -z "${__srOk}" ]; then printf 'safe-rm: refused, not under a tmp folder, or a whole project temp folder: %s\n' "${__srP}" >&2; return 1; fi
	if [ -L "${__srP}" ]; then printf 'safe-rm: refused, a link: %s\n' "${__srP}" >&2; return 1; fi
	if [ ! -e "${__srP}" ]; then printf 'safe-rm: refused, not there: %s\n' "${__srP}" >&2; return 1; fi
	__srReal="$(cd -P -- "${__srP%/*}/" 2> /dev/null && pwd -P)" || { printf 'safe-rm: refused, not there: %s\n' "${__srP}" >&2; return 1; }
	if [ "${__srReal%/}/${__srP##*/}" != "${__srP}" ]; then printf 'safe-rm: refused, goes through a link: %s\n' "${__srP}" >&2; return 1; fi
	__srOneFs='--one-file-system'; rm --version > /dev/null 2>&1 || __srOneFs='-x'
	rm -r -f "${__srOneFs}" -- "${__srP}" && printf 'removed %s\n' "${__srP}"
}


##	History:
##		- 2026-11-06 JC: Created, from safe-rm.bash, for stage 7's old trees on the Mac and Unix boxes.
