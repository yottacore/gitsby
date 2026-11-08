#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		Takes every module version a go.sum doesn't name out of a Go module cache, from the
##		download cache and the extracted trees both. Also kept: golang.org/toolchain for
##		go.mod's toolchain line, or its go line where it has none, and the checksum db's
##		cache. cicd.bash runs it in the image on the gitsby-cicd-cache volume, once a run
##		passed and no other run's container is up. Not for a box's own module cache, which
##		every Go project on it shares.
##	Syntax:
##		go-modcache-prune.bash MODCACHE GO_MOD GO_SUM
##		  MODCACHE  the module cache, an absolute path with no link in it
##	Output: how many module versions went, on a line of its own.
##	Exit: 0 done, or nothing to do, 1 refused or failed, 2 bad usage.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}." >&2; exit 1
fi
set -Eeuo pipefail

fDie(){ printf 'go-modcache-prune: %s\n' "$*" >&2; exit 1 ;}

(($# == 3)) || { printf 'Usage: go-modcache-prune.bash MODCACHE GO_MOD GO_SUM\n' >&2; exit 2; }
modCache="${1%/}"; goMod="$2"; goSum="$3"
[[ -f "${goMod}" && -f "${goSum}" ]] || fDie "no go.mod or go.sum at ${goMod} and ${goSum}"
[[ "${modCache}" == /?* && "${modCache}" != *..* && "${modCache}" != *//* && "${modCache}" != *$'\n'* ]] || fDie "refused, bad path: ${modCache}"
## A cache that was never filled has nothing to prune.
[[ -d "${modCache}/cache/download" ]] || { echo 0; exit 0; }
[[ "$(cd -P -- "${modCache}" && pwd -P)" == "${modCache}" ]] || fDie "refused, goes through a link: ${modCache}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/include/safe-rm.bash"   ## fSafeRm_Under()

## "<path>@<version>" for each module version go.sum names, its /go.mod-only ones too, spelled
## as the cache spells them: a capital is "!" and the lower case letter.
declare -A keep=()
while IFS= read -r line; do keep["${line}"]=1; done < <(awk '
	function esc(s,   o, c, i) { o = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); o = o (c ~ /[A-Z]/ ? "!" tolower(c) : c) }; return o }
	NF >= 2 { v = $2; sub(/\/go\.mod$/, "", v); print esc($1) "@" esc(v) }' "${goSum}")
toolchain="$(awk '$1 == "toolchain" { t = $2 } $1 == "go" { g = "go" $2 } END { print (t != "" ? t : g) }' "${goMod}")"

fKept(){
	[[ -n "${keep["$1"]:-}" ]] && return 0
	[[ -n "${toolchain}" && "$1" == "golang.org/toolchain@v0.0.1-${toolchain}."* ]]
}

declare -A gone=() parents=() dlParents=()
declare -a doomed=()

## The extracted trees, "<path>@<version>", and the marker beside one still being written.
while IFS= read -r -d '' p; do
	rel="${p#"${modCache}"/}"; key="${rel%.partial}"
	fKept "${key}" && continue
	doomed+=("${p}"); gone["${key}"]=1
	[[ "${rel}" != */* ]] || parents["${rel%/*}"]=1
done < <(find "${modCache}" -path "${modCache}/cache" -prune -o -name '*@*' -prune -print0)

## The download cache, one @v folder per module. A version is all of its files, whatever the
## suffix. A folder with none left goes whole, its list too.
while IFS= read -r -d '' at; do
	mod="${at#"${modCache}/cache/download/"}"; mod="${mod%/@v}"
	nKept=0; drop=()
	for f in "${at}"/*; do
		[[ -e "${f}" ]] || continue
		base="${f##*/}"
		[[ "${base}" != list && "${base}" != list.lock ]] || continue
		key="${mod}@${base%.*}"
		if fKept "${key}"; then nKept=$((nKept + 1)); else drop+=("${f}"); gone["${key}"]=1; fi
	done
	if ((nKept == 0)); then
		doomed+=("${at}"); dlParents["${mod}"]=1
	else
		doomed+=(${drop[@]+"${drop[@]}"})
	fi
done < <(find "${modCache}/cache/download" -path "${modCache}/cache/download/sumdb" -prune -o -type d -name '@v' -prune -print0)

if ((${#doomed[@]})); then
	fSafeRm_Under "${modCache}" "${doomed[@]}" || fDie "couldn't remove them all"
	## The folders above that are empty now, no higher than the cache's own two.
	if ((${#parents[@]})); then (cd "${modCache}" && rmdir -p -- "${!parents[@]}" 2>/dev/null) || true; fi
	if ((${#dlParents[@]})); then (cd "${modCache}/cache/download" && rmdir -p -- "${!dlParents[@]}" 2>/dev/null) || true; fi
fi
echo "${#gone[@]}"


##	History:
##		- 2026-11-06 JC: Created.
