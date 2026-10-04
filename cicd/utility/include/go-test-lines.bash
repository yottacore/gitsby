#!/usr/bin/env bash
## fGoTestLines LOG MODULE_DIR: one line per top-level test in a 'go test -v' log, as
## "  ok: [<id>] TestName", with the ID from the end of that test's func line in MODULE_DIR.
##
## cicd.bash prints its own unit tests this way, and remote-tests.bash the ones it runs on other
## boxes. One copy, so the two can't drift apart.

fGoTestLines(){
	local ids=""
	ids="$(find "$2" -name '*_test.go' -type f -exec sed -nE 's#^func ((Test|Fuzz)[A-Za-z0-9_]*)\(.*// \[([0-9A-Za-z]+)\][[:space:]]*$#\1 \3#p' {} + 2>/dev/null || true)"
	## Subtests are indented in the log, so they don't match.
	IDS="${ids}" awk '
		BEGIN { n = split(ENVIRON["IDS"], l, "\n"); for (i = 1; i <= n; i++) { split(l[i], f, " "); id[f[1]] = "[" f[2] "] " } }
		/^--- (PASS|FAIL|SKIP): / { v = ($2 == "PASS:") ? "ok" : ($2 == "FAIL:") ? "FAIL" : "skip"; print "  " v ": " id[$3] $3 }' "$1"
}
