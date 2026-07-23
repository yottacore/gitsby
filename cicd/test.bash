#!/usr/bin/env bash

#  shellcheck disable=2317  ## 'Can't reach.' False hits on functions invoked indirectly.

##	Purpose:
##		- Regression tests for bin/gitsby (and bin/gitsby.ps1 when pwsh is
##		  installed - same suite, run once per implementation).
##		- Run by cicd.bash stage 2, or standalone.
##		- Builds throwaway repos (a bare 'origin' + two clones) under mktemp;
##		  never touches the real repo or network.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitsby-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

## Keep test commits hermetic (no reliance on the user's git config).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

declare -i pass=0 fail=0
fOk(){   pass=$((pass+1)); echo "  ok: $*"; }
fFail(){ fail=$((fail+1)); echo "  FAIL: $*"; }
## Assert the command succeeds / fails (output discarded; -q keeps gitsby promptless).
fAssert(){     local desc="$1"; shift; if   "$@" >/dev/null 2>&1; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertFail(){ local desc="$1"; shift; if ! "$@" >/dev/null 2>&1; then fOk "$desc"; else fFail "$desc"; fi; }

## Fixture: bare origin with an initial commit on main, plus two clones.
fMakeFixture(){
	local -r fixDir="$1"
	mkdir -p "${fixDir}"
	origin="${fixDir}/origin.git"; cloneA="${fixDir}/a"; cloneB="${fixDir}/b"
	git init --quiet --bare -b main "${origin}"
	git clone --quiet "${origin}" "${cloneA}" 2>/dev/null
	(
		cd "${cloneA}"
		echo one > file1.txt
		git add --all; git commit --quiet -m "initial"
		git push --quiet -u origin main
	)
	git clone --quiet "${origin}" "${cloneB}"
}

## The whole suite, against whatever ${gitsby} points at.
fRunSuite(){
	echo "suite: $1 (${gitsby})"

	## Help + bad input surface
	fAssert     "help exits 0"                 "${gitsby}" --help
	fAssert     "version exits 0"              "${gitsby}" -v
	fAssertFail "no args exits nonzero"        "${gitsby}"
	fAssertFail "unknown command rejected"     bash -c "cd '${cloneA}' && '${gitsby}' -q frobnicate"
	fAssertFail "unknown option rejected"      bash -c "cd '${cloneA}' && '${gitsby}' -q status --bogus"
	fAssertFail "outside a repo rejected"      bash -c "cd '${work}' && '${gitsby}' -q status"

	## Read-only commands
	fAssert "status runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssert "list runs"    bash -c "cd '${cloneA}' && '${gitsby}' -q list"

	## scommit: commits everything; idempotent when clean
	( cd "${cloneA}" && echo two > file2.txt )
	fAssert "scommit commits new file"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit 'add file2'"
	fAssert "worktree clean after scommit"      bash -c "cd '${cloneA}' && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "commit message recorded"           bash -c "cd '${cloneA}' && git log -1 --format=%s | grep -qx 'add file2'"
	fAssert "scommit again (nothing to do) ok"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit 'noop'"

	## spush: publishes; remote matches local
	fAssert "spush runs"           bash -c "cd '${cloneA}' && '${gitsby}' -q spush 'push file2'"
	fAssert "remote main matches"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## spull: remote moved ahead + local dirty -> stash, ff-only pull, pop
	(
		cd "${cloneB}"
		git pull --quiet --ff-only
		echo bee > fileB.txt
		git add --all; git commit --quiet -m "from B"
		git push --quiet
	)
	( cd "${cloneA}" && echo dirty >> file1.txt )
	fAssert "spull with dirty tree + remote ahead"  bash -c "cd '${cloneA}' && '${gitsby}' -q spull"
	fAssert "remote commit arrived"                 bash -c "cd '${cloneA}' && [[ -f fileB.txt ]]"
	fAssert "local dirty edit survived"             bash -c "cd '${cloneA}' && grep -q dirty file1.txt && ! git diff --quiet"
	fAssert "autostash fully popped"                bash -c "cd '${cloneA}' && [[ -z \"\$(git stash list)\" ]]"

	## mkbranch: parks work, branches off default, publishes with upstream
	fAssert "mkbranch feat"          bash -c "cd '${cloneA}' && '${gitsby}' -q mkbranch feat"
	fAssert "now on feat"            bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssert "feat has upstream"      bash -c "cd '${cloneA}' && git rev-parse --abbrev-ref 'feat@{u}' >/dev/null"
	fAssert "parked edit committed"  bash -c "cd '${cloneA}' && git diff --quiet && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssertFail "mkbranch existing name rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q mkbranch feat"
	fAssertFail "mkbranch bad name rejected"       bash -c "cd '${cloneA}' && '${gitsby}' -q mkbranch 'bad name'"
	fAssertFail "mkbranch no name rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q mkbranch"

	## chbranch: switch back and forth; bogus target rejected
	fAssert "chbranch (default: main)"  bash -c "cd '${cloneA}' && '${gitsby}' -q chbranch"
	fAssert "now on main"               bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "chbranch feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q chbranch feat"
	fAssert "back on feat"              bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssertFail "chbranch nonexistent rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q chbranch nosuch"

	## mtm: merge feat into main --no-ff, then delete it local + remote
	( cd "${cloneA}" && echo feat > feat.txt )
	fAssert "mtm merges feat into main"  bash -c "cd '${cloneA}' && '${gitsby}' -q mtm 'merge feat work'"
	fAssert "now on main after mtm"      bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "merge commit is --no-ff"    bash -c "cd '${cloneA}' && git log -1 --merges --format=%s | grep -qx 'merge feat work'"
	fAssert "feat deleted locally"       bash -c "cd '${cloneA}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "feat deleted on origin"     bash -c "cd '${origin}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "main pushed after mtm"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	fAssertFail "mtm from main rejected" bash -c "cd '${cloneA}' && '${gitsby}' -q mtm"

	## Detached HEAD guard
	fAssertFail "mutating command on detached HEAD rejected"  bash -c "cd '${cloneA}' && git checkout --quiet HEAD~0 --detach && '${gitsby}' -q scommit x"
	( cd "${cloneA}" && git checkout --quiet main )

	## Messages with quotes pass through unmangled (no eval, no curly-quote games)
	( cd "${cloneA}" && echo q > q.txt )
	fAssert "message with quotes survives"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit \"don't \\\"quote\\\" me\" && git log -1 --format=%s | grep -qx \"don't \\\"quote\\\" me\""
}

echo "gitsby regression tests (fixture: ${work})"

gitsby="${root}/bin/gitsby"
fMakeFixture "${work}/bash"
fRunSuite "bash"

## Same suite against the PowerShell port, when pwsh is available. The shim keeps
## ${gitsby} a plain single path so the bash -c interpolation above stays as-is.
if command -v pwsh >/dev/null 2>&1; then
	gitsby="${work}/gitsby-pwsh"
	printf '#!/usr/bin/env bash\nexec pwsh -NoProfile -File "%s" "$@"\n' "${root}/bin/gitsby.ps1" > "${gitsby}"
	chmod +x "${gitsby}"
	fMakeFixture "${work}/pwsh"
	fRunSuite "pwsh"
else
	echo "suite: pwsh skipped (pwsh not installed)"
fi

echo "passed: ${pass}, failed: ${fail}"
((fail == 0)) || exit 1


##	History:
##		- 20260722 JC: Created, alongside the bin/gitsby refactor.
##		- 20260722 JC: Run the suite per implementation; added the pwsh leg.
