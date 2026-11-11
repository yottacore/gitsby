#!/usr/bin/env bash

#  shellcheck enable=require-variable-braces  ## Every expansion braced: "${var}", not "$var".

##	Purpose:
##		Two backlog rules that review rounds kept leaking through, checked in cicd
##		stage 1 instead of by hand:
##		1. Every open code-review item (not ✅ ✋ 🚫, or in the new format not Done,
##		   Canceled, Moot, or Deferred) has an "Origin:" sub-bullet -
##		   the commit or round that introduced it, whether an earlier round saw it,
##		   and Confirmed (reproduced) or Plausible (read only).
##		2. A suite check removed on this branch, against the integration branch, is
##		   named on a backlog line the branch adds. Two decisions were reversed by
##		   deleting the check that encoded them, with nothing written down; this
##		   makes that a stop.
##		The checks are the ones test-id.bash finds, in the suites and spawn-count.bash.
##		A removed one is named by its ID as a word, or by its label as written, so a
##		label with a shell variable has to be quoted that way. A check that keeps its
##		ID under a new label was edited, not removed. Needs test-id.bash beside it.
##	Syntax:
##		backlog-check.bash [-q] [--base REF] [--backlog FILE]
##		  -q              print findings only
##		  --base REF      branch to diff the suites against (default: first of dev, main that exists)
##		  --backlog FILE  backlog to read (default: project/backlog.md at the repo root)
##	Exit: 0 clean, 1 findings, 2 cannot run (no backlog, not a git repo).
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
backlog="${root}/project/backlog.md"
base=""; quiet=0
suites=(cicd/test.bash cicd/parity.bash cicd/fuzz.bash cicd/utility/spawn-count.bash)
testIdCmd="${meDir}/test-id.bash"

fUsage(){ printf '%s\n' "$*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
	case "$1" in
		-q)        quiet=1 ;;
		--base)    base="${2:?--base needs a ref}"; shift ;;
		--backlog) backlog="${2:?--backlog needs a file}"; shift ;;
		-h|--help) grep -E '^##' "$0" | sed 's/^##\t\?//'; exit 0 ;;
		*)         fUsage "Unknown option: $1 (try --help)" ;;
	esac
	shift
done

fEcho_Clean(){ ((quiet)) || printf '%s\n' "$*"; }
[[ -r "${backlog}" ]] || fUsage "backlog-check: no backlog at ${backlog}"
git -C "${root}" rev-parse --git-dir >/dev/null 2>&1 || fUsage "backlog-check: ${root} is not a git repo"

findings=0

## 1. Open review items without an Origin line, in either format: an old emoji line at one tab, or
## a new top-level "- Code Review ..." item whose Status isn't closed. Each open item is listed,
## and again as missing with no Origin row.
reviewScan="$(awk '
	function flush() {
		if (cur != "" && open) { print "open " cur; if (!found) print "missing " cur }
		cur = ""; found = 0; open = 0; fmt = ""
	}
	/^#/ || /^- / { flush() }
	/^\t- / && fmt != "new" {
		flush()
		if (/Code Review [0-9]+[a-z]* (item|enhancement) [0-9]+:/ && !/(✅|✋|🚫)/) {
			cur = $0; sub(/:.*/, "", cur); sub(/^\t- [^ ]+ /, "", cur); fmt = "old"; open = 1
		}
	}
	/^- Code Review / { cur = $0; sub(/:.*/, "", cur); sub(/^- /, "", cur); fmt = "new"; open = 1 }
	fmt == "old" && /^\t\t- Origin:/ { found = 1 }
	fmt == "new" && /^\t- Origin:/   { found = 1 }
	fmt == "new" && /^\t- Status:/ {
		status = $0; sub(/^\t- Status:[ \t]*/, "", status)
		if (status ~ /^(Done|Canceled|Moot|Deferred)([^A-Za-z]|$)/) open = 0
	}
	END { flush() }
' "${backlog}")"
noOrigin="$(sed -n 's/^missing //p' <<< "${reviewScan}")"
openCount="$(grep -c '^open ' <<< "${reviewScan}" || true)"
if [[ -n "${noOrigin}" ]]; then
	echo "backlog-check: open review items with no 'Origin:' sub-bullet:"
	while IFS= read -r line; do echo "  ${line}"; done <<< "${noOrigin}"
	findings=1
else
	fEcho_Clean "backlog-check: Origin: present on every open review item (${openCount} listed)"
fi

## 2. Suite checks removed since the merge base. Compares the working tree, not HEAD,
## so it sees the branch as it is about to be committed.
if [[ -z "${base}" ]]; then
	for c in dev main; do
		if git -C "${root}" rev-parse --verify -q "refs/heads/${c}" >/dev/null; then base="${c}"; break; fi
	done
fi
if [[ -z "${base}" ]]; then
	fEcho_Clean "backlog-check: no integration branch found; removed-check test skipped"
else
	mergeBase="$(git -C "${root}" merge-base HEAD "${base}" 2>/dev/null || true)"
	if [[ -z "${mergeBase}" ]]; then
		fEcho_Clean "backlog-check: no merge base with ${base}; removed-check test skipped"
	else
		[[ -r "${testIdCmd}" ]] || fUsage "backlog-check: no test-id.bash beside this script, at ${testIdCmd}"
		## Each test as "<id> <label>", from the scan test-id.bash checks IDs with, so a check any
		## helper makes, anywhere on its line, counts. A suite gone from the tree has none left.
		before="$(bash "${testIdCmd}" --list --root "${root}" --rev "${mergeBase}" "${suites[@]}")" || fUsage "backlog-check: could not list the tests at ${base}"
		present=(); for s in "${suites[@]}"; do [[ -f "${root}/${s}" ]] && present+=("${s}"); done
		after=""
		if ((${#present[@]})); then after="$(bash "${testIdCmd}" --list --root "${root}" "${present[@]}")" || fUsage "backlog-check: could not list the tests"; fi
		## Only a line the branch adds can name a removal. One already there at the base, such as the
		## item that added the check, says nothing about why it went. A backlog git has no copy of
		## at the base is all new.
		backlogDir="$(cd -P -- "$(dirname -- "${backlog}")" && pwd -P)"; rootP="$(cd -P -- "${root}" && pwd -P)"
		baseBacklog=""
		if [[ "${backlogDir}/" == "${rootP}/"* ]]; then
			rel="${backlogDir#"${rootP}"}/${backlog##*/}"; rel="${rel#/}"
			baseBacklog="$(git -C "${root}" show "${mergeBase}:${rel}" 2>/dev/null || true)"
		fi
		## A check whose ID is still there was edited. So was one whose label came back under an ID
		## the base didn't have. The added lines name a removed check by its ID as a word, or by its label.
		mapfile -t scan < <(awk '
			(FILENAME == ARGV[1] || FILENAME == ARGV[2]) && $0 == "" { next }
			FILENAME == ARGV[1] { id = $1; lab = substr($0, length($1) + 2); ids[++nb] = id; labs[nb] = lab; if (id != "-") wasId[id] = 1; next }
			FILENAME == ARGV[2] { id = $1; lab = substr($0, length($1) + 2); if (id != "-") nowId[id] = 1; if (id == "-" || !(id in wasId)) newLab[lab] = 1; next }
			FILENAME == ARGV[3] { old[$0] = 1; next }
			!($0 in old) { text = text "\n" $0; t = $0; gsub(/[^0-9A-Za-z]+/, " ", t); k = split(t, w, " "); for (j = 1; j <= k; j++) named[w[j]] = 1 }
			END {
				n = 0
				for (i = 1; i <= nb; i++) {
					id = ids[i]; lab = labs[i]
					if ((id != "-" && id in nowId) || lab in newLab) continue
					n++
					if ((id != "-" && id in named) || (lab != "" && index(text, lab))) continue
					out = out (id == "-" ? lab : "[" id "] " lab) "\n"
				}
				printf "%d\n%s", n, out
			}' <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") <(printf '%s\n' "${baseBacklog}") "${backlog}")
		n="${scan[0]:-0}"; unnamed=""
		for line in "${scan[@]:1}"; do unnamed+="${line}"$'\n'; done
		if [[ -n "${unnamed}" ]]; then
			echo "backlog-check: suite checks removed since ${base} and not named on a backlog line this branch adds:"
			while IFS= read -r line; do [[ -n "${line}" ]] && echo "  \"${line}\""; done <<< "${unnamed}"
			echo "  Name each one in the backlog, by its ID, with the decision it encoded and why that changed."
			findings=1
		else
			fEcho_Clean "backlog-check: removed suite checks all named in the backlog (${n} removed since ${base})"
		fi
	fi
fi

exit "${findings}"


##	History:
##		- 20260910 JC: Created. The review-round audit found the refill came from
##		  deferred notes and silently deleted checks, not from fixes undoing fixes.
##		- 20260926 JC: Reads the test ID at the front of a label. A check whose ID or label is still there was edited, and the backlog can name a removed one by either.
##		- 20261004 JC: fEcho_Clean prints with printf. Every expansion braced, and shellcheck
##		  enforces it.
##		- 20261107 JC: Errors go through fUsage.
##		- 20261108 JC: gover retired, so the default base is dev.
##		- 20261111 JC: A removed check has to be named on a line the branch adds, not anywhere in the backlog. Checks are found by test-id.bash's scan, so every helper counts, at any place on its line, and spawn-count.bash's too.
