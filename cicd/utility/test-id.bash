#!/usr/bin/env bash

##	Purpose:
##		- Mints the ID a new test carries, and checks that every test has one.
##		- An ID is the milliseconds from 2000-01-01 UTC to when the test was written,
##		  in base 62 (0-9, A-Z, a-z). Seven characters until 2111, and IDs of one
##		  length sort by age in a plain byte sort.
##		- A suite check carries it at the front of its label, as "[<id>] label". A
##		  pass/fail pair written out by hand is one check, so its fOk and fFail
##		  (fBad in parity) share one. A Go test carries it on its func line, as a
##		  trailing "// [<id>]". A spawn-count measure carries it like a suite check.
##		- A check inside a loop is one test, so every pass of the loop reports the
##		  same ID.
##	Syntax:
##		test-id.bash [--at DATE]
##		test-id.bash --check [-q] [--root DIR]
##		  --at DATE   mint for DATE instead of now, in any form 'date -d' reads
##		  --check     fail on a test with no ID, or an ID used twice
##		  -q          print findings only
##		  --root DIR  tree to check (default: the repo this script sits in)
##	Exit: 0 clean, 1 findings, 2 bad usage.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

meDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${meDir}/../.." && pwd)"
at=""; check=0; quiet=0
suites=(cicd/test.bash cicd/fuzz.bash cicd/parity.bash cicd/utility/spawn-count.bash)
while [[ $# -gt 0 ]]; do
	case "$1" in
		--at)      at="${2:?--at needs a date}"; shift ;;
		--check)   check=1 ;;
		-q)        quiet=1 ;;
		--root)    root="${2:?--root needs a directory}"; shift ;;
		-h|--help) grep -E '^##' "$0" | sed 's/^##\t\?//'; exit 0 ;;
		*)         echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
	shift
done

fBase62(){
	local -i n="$1"
	local -r digits='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
	local out=""
	while ((n > 0)); do out="${digits:n % 62:1}${out}"; n=$((n / 62)); done
	printf '%s\n' "${out:-0}"
}

if ((! check)); then
	ms=""
	## Now from the shell rather than date, whose %N is GNU-only. BSD date prints it literally.
	if [[ -n "${at}" ]]; then ms="$(date -u -d "${at}" +%s%3N)" || exit 2
	else ms="${EPOCHREALTIME//[!0-9]/}"; ms="${ms:0:${#ms}-3}"; fi
	## Checked before the arithmetic: a bad number there aborts this whole block, and the
	## script would carry on into --check.
	if [[ ! "${ms}" =~ ^[0-9]+$ ]] || ((10#${ms} < 946684800000)); then echo "test-id: ${at} is before 2000" >&2; exit 2; fi
	ms=$((10#${ms} - 946684800000))
	fBase62 "${ms}"
	exit 0
fi

## One line per test: "<id or -> <kind> <file>:<line>". Kind is ok or fail for the two halves
## of a hand-written pair, and check for everything else. A label that is only the caller's
## $desc or $label is a helper passing one through, not a test of its own.
fSites(){
	local f
	for f in "${suites[@]}"; do
		[[ -f "${root}/${f}" ]] || continue
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
					id = "-"
					if (match(s, /^\[[0-9A-Za-z]+\] /)) id = substr(s, 2, RLENGTH - 3)
					print id, kind, ENVIRON["FILE"] ":" NR
				}
			}' "${root}/${f}"
	done
	if [[ -d "${root}/src-go" ]]; then
		while IFS= read -r f; do
			awk -v file="${f#"${root}/"}" '
				/^func (Test|Fuzz)[A-Za-z0-9_]*\(/ {
					id = "-"
					if (match($0, /\/\/ \[[0-9A-Za-z]+\][[:space:]]*$/)) { id = substr($0, RSTART + 4); sub(/\].*/, "", id) }
					print id, "check", file ":" NR
				}' "${f}"
		done < <(find "${root}/src-go" -name '*_test.go' -type f | LC_ALL=C sort)
	fi
}

sites="$(fSites)"
if [[ -z "${sites}" ]]; then echo "test-id: found no tests under ${root}"; exit 1; fi
findings=""
missing="$(awk '$1 == "-" { print "  " $3 }' <<< "${sites}")"
if [[ -n "${missing}" ]]; then findings+="test-id: tests with no ID (mint one with cicd/utility/test-id.bash):"$'\n'"${missing}"$'\n'; fi
badForm="$(awk '$1 != "-" && $1 !~ /^[0-9A-Za-z]{7}$/ { print "  " $3 ": [" $1 "]" }' <<< "${sites}")"
if [[ -n "${badForm}" ]]; then findings+="test-id: IDs that are not seven base-62 characters:"$'\n'"${badForm}"$'\n'; fi
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
