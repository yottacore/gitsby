#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		- Mints the ID a new test carries, and checks that every test has one.
##		- An ID is the whole minutes from 2000-01-01 UTC to when the test was written,
##		  in lowercase Crockford base 32 (0-9, a-z less i, l, o, u). Five characters
##		  until 2063, and IDs of one length sort by age in a plain byte sort. A minute
##		  another test already has goes to the next free one.
##		- A suite check carries it at the front of its label, as "[<id>] label". A
##		  pass/fail pair written out by hand is one check, so its fOk and fFail
##		  (fBad in parity) share one. A Go test carries it on its func line, as a
##		  trailing "// [<id>]". A spawn-count measure carries it like a suite check.
##		- A check inside a loop is one test, so every pass of the loop reports the
##		  same ID.
##	Syntax:
##		test-id.bash [--at DATE] [-n COUNT] [--root DIR]
##		test-id.bash --check [-q] [--root DIR]
##		test-id.bash --list [--root DIR] WHAT...
##		  --at DATE   mint for DATE instead of now, in any form 'date -d' reads
##		  -n COUNT    mint COUNT IDs, each the next free minute after the last
##		  --check     fail on a test with no ID, or an ID used twice
##		  --list      print "<id> <label>" for each test in WHAT, once each: a suite script's
##		              path from the repo root, 'go' for the Go tests and fuzz targets, or
##		              'gofuzz' for the fuzz targets alone
##		  -q          print findings only
##		  --root DIR  tree to check (default: the repo this script sits in)
##	Exit: 0 clean, 1 findings, 2 bad usage.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	printf '%s\n' "${0##*/}: needs bash 4.4 or newer, and this is bash ${BASH_VERSION}. On macOS, install one with 'brew install bash' and put it first on PATH." >&2; exit 1
fi
set -Eeuo pipefail

meDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${meDir}/../.." && pwd)"
at=""; check=0; quiet=0; list=0; listWhat=(); count=1
suites=(cicd/test.bash cicd/fuzz.bash cicd/parity.bash cicd/utility/spawn-count.bash)
while [[ $# -gt 0 ]]; do
	case "$1" in
		--at)      at="${2:?--at needs a date}"; shift ;;
		--check)   check=1 ;;
		--list)    list=1 ;;
		-q)        quiet=1 ;;
		-n)        count="${2:?-n needs a count}"; shift ;;
		--root)    root="${2:?--root needs a directory}"; shift ;;
		-h|--help) grep -E '^##' "$0" | sed 's/^##\t\?//'; exit 0 ;;
		-*)        echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
		*)         ((list)) || { echo "Unknown option: $1 (try --help)" >&2; exit 2; }; listWhat+=("$1") ;;
	esac
	shift
done

fBase32(){
	local -i n="$1"
	local -r digits='0123456789abcdefghjkmnpqrstvwxyz'
	local out=""
	while ((n > 0)); do out="${digits:n % 32:1}${out}"; n=$((n / 32)); done
	printf '%s\n' "${out:-0}"
}

if ((check && list)); then echo "test-id: --check and --list are separate runs; give one." >&2; exit 2; fi
if ((list && ! ${#listWhat[@]})); then echo "test-id: --list needs a suite, 'go' or 'gofuzz'" >&2; exit 2; fi

## One line per test: "<id or -> <kind> <file>:<line>", then a tab and its label. Kind is ok or
## fail for the two halves of a hand-written pair, and check for everything else. A label that
## is only the caller's $desc or $label is a helper passing one through, not a test of its own.
## Takes what --list does, or with nothing, every suite and the Go tests.
fSites(){
	local f goPat=""
	local -a what=("$@")
	((${#what[@]})) || what=("${suites[@]}" go)
	for f in "${what[@]}"; do
		case "${f}" in
			go)     goPat='^func (Test|Fuzz)[A-Za-z0-9_]*[(]' ;;
			gofuzz) goPat='^func Fuzz[A-Za-z0-9_]*[(]' ;;
			*)      goPat="" ;;
		esac
		if [[ -n "${goPat}" ]]; then
			[[ -d "${root}/src-go" ]] || continue
			while IFS= read -r f; do
				awk -v file="${f#"${root}/"}" -v pat="${goPat}" '
					$0 ~ pat {
						id = "-"
						if (match($0, /\/\/ \[[0-9A-Za-z]+\][[:space:]]*$/)) { id = substr($0, RSTART + 4); sub(/\].*/, "", id) }
						name = substr($0, 6); sub(/\(.*/, "", name)
						print id, "check", file ":" NR "\t" name
					}' "${f}"
			done < <(find "${root}/src-go" -name '*_test.go' -type f | LC_ALL=C sort)
			continue
		fi
		f="${f#"${root}/"}"
		[[ -f "${root}/${f}" ]] || { ((! list)) || { echo "test-id: no suite at ${f}" >&2; return 2; }; continue; }
		FILE="${f}" awk '
			/^[[:space:]]*#/ { next }
			{
				s = $0
				while (match(s, /(^|[^A-Za-z0-9_])(fAssert[A-Za-z]*|fOk|fFail|fBad|fSurvive|fAccept|fRefuse|fMsgLiteral|fDirLiteral|fTitleLiteral|fSame[A-Za-z]*|fMeasure)[[:space:]]+"/)) {
					call = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
					if (s ~ /^\$\{?(desc|label)([^A-Za-z0-9_]|$)/) continue
					## spawn-count calls it only at the start of a line; elsewhere it is text about one.
					if (call ~ /fMeasure/ && $0 !~ /^fMeasure[[:space:]]/) continue
					kind = "check"
					if (call ~ /fOk[[:space:]]/) kind = "ok"
					else if (call ~ /(fFail|fBad)[[:space:]]/) kind = "fail"
					id = "-"; label = s
					if (match(s, /^\[[0-9A-Za-z]+\] /)) { id = substr(s, 2, RLENGTH - 3); label = substr(s, RLENGTH + 1) }
					## Up to the closing quote, a backslashed one aside.
					if (match(label, /^([^"\\]|\\.)*/)) label = substr(label, 1, RLENGTH)
					print id, kind, ENVIRON["FILE"] ":" NR "\t" label
				}
			}' "${root}/${f}"
	done
}

if ((! check && ! list)); then
	[[ "${count}" =~ ^[1-9][0-9]*$ ]] || { echo "test-id: -n takes a count of 1 or more" >&2; exit 2; }
	sec=""
	## Now from the shell rather than date, whose %N is GNU-only. BSD date prints it literally.
	if [[ -n "${at}" ]]; then sec="$(date -u -d "${at}" +%s)" || exit 2
	else sec="${EPOCHREALTIME%[.,]*}"; fi
	## Checked before the arithmetic: a bad number there aborts this whole block, and the
	## script would carry on into --check.
	if [[ ! "${sec}" =~ ^[0-9]+$ ]] || ((10#${sec} < 946684800)); then echo "test-id: ${at} is before 2000" >&2; exit 2; fi
	declare -A taken=()
	while read -r id _; do [[ "${id}" == "-" ]] || taken["${id}"]=1; done < <(fSites)
	min=$(( (10#${sec} - 946684800) / 60 ))
	for ((i = 0; i < count; i++)); do
		id="$(fBase32 "${min}")"
		while [[ -n "${taken[${id}]:-}" ]]; do min=$((min + 1)); id="$(fBase32 "${min}")"; done
		taken["${id}"]=1
		printf '%s\n' "${id}"
	done
	exit 0
fi

## Each test once, in the order its file has them. An fOk and its fFail are one.
if ((list)); then
	sites="$(fSites "${listWhat[@]}")" || exit 2
	[[ -z "${sites}" ]] || awk -F '\t' '{ split($1, a, " "); if (!seen[a[1]]++ || a[1] == "-") print a[1] " " $2 }' <<< "${sites}"
	exit 0
fi

sites="$(fSites)"
if [[ -z "${sites}" ]]; then echo "test-id: found no tests under ${root}"; exit 1; fi
findings=""
missing="$(awk '$1 == "-" { print "  " $3 }' <<< "${sites}")"
if [[ -n "${missing}" ]]; then findings+="test-id: tests with no ID (mint one with cicd/utility/test-id.bash):"$'\n'"${missing}"$'\n'; fi
badForm="$(awk '$1 != "-" && $1 !~ /^[0-9abcdefghjkmnpqrstvwxyz]{5}$/ { print "  " $3 ": [" $1 "]" }' <<< "${sites}")"
if [[ -n "${badForm}" ]]; then findings+="test-id: IDs that are not five lowercase Crockford base-32 characters:"$'\n'"${badForm}"$'\n'; fi
## An ID may appear twice only as an fOk and the fFail right after it, in the same file.
dupes="$(awk '$1 != "-" { n[$1]++; k[$1] = k[$1] " " $2; w[$1] = w[$1] " " $3 }
	END {
		for (id in n) {
			if (n[id] == 1) continue
			if (n[id] == 2 && k[id] == " ok fail") {
				split(w[id], a, " "); split(a[1], p, ":"); split(a[2], q, ":")
				if (p[1] == q[1] && q[2] - p[2] >= 0 && q[2] - p[2] <= 3) continue
			}
			print "  " id ":" w[id]
		}
	}' <<< "${sites}" | LC_ALL=C sort)"
if [[ -n "${dupes}" ]]; then findings+="test-id: IDs used by more than one test:"$'\n'"${dupes}"$'\n'; fi

if [[ -n "${findings}" ]]; then printf '%s' "${findings}"; exit 1; fi
((quiet)) || echo "test-id: every test has its own ID ($(awk '{ print $1 }' <<< "${sites}" | LC_ALL=C sort -u | grep -c .) tests)"
exit 0


##	History:
##		- 20260926 JC: Created. Every suite check and Go test got an ID dated from when it was written.
##		- 20260927 JC: spawn-count's measures are tests too.
##		- 20261001 JC: The current time comes from EPOCHREALTIME, so minting works with BSD date. '--at' still needs GNU date.
##		- 20261004 JC: Every expansion braced, and shellcheck enforces it.
##		- 20261025 JC: --list prints each test's ID and label for the suites named, so cicd.bash --list can say what a run would check.
##		- 20261026 JC: IDs are minutes since 2000 in Crockford base 32, and every old one was converted from the time it held. A taken minute goes to the next free one. -n mints several.
