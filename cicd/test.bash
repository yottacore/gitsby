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
	fAssert "listbr runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q listbr"
	fAssert "old alias 'list' still works"  bash -c "cd '${cloneA}' && '${gitsby}' -q list"

	## commit: commits everything; idempotent when clean
	( cd "${cloneA}" && echo two > file2.txt )
	fAssert "commit commits new file"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'add file2'"
	fAssert "worktree clean after commit"      bash -c "cd '${cloneA}' && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "commit message recorded"          bash -c "cd '${cloneA}' && git log -1 --format=%s | grep -qx 'add file2'"
	fAssert "commit again (nothing to do) ok"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'noop'"
	( cd "${cloneA}" && echo alias > alias.txt )
	fAssert "old alias 'scommit' still works"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit 'via alias'"

	## sync: publishes; remote matches local
	fAssert "sync runs"            bash -c "cd '${cloneA}' && '${gitsby}' -q sync 'push file2'"
	fAssert "remote main matches"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## pull: remote moved ahead + local dirty -> stash, ff-only pull, pop
	(
		cd "${cloneB}"
		git pull --quiet --ff-only
		echo bee > fileB.txt
		git add --all; git commit --quiet -m "from B"
		git push --quiet
	)
	( cd "${cloneA}" && echo dirty >> file1.txt )
	fAssert "pull with dirty tree + remote ahead"  bash -c "cd '${cloneA}' && '${gitsby}' -q pull"
	fAssert "remote commit arrived"                bash -c "cd '${cloneA}' && [[ -f fileB.txt ]]"
	fAssert "local dirty edit survived"            bash -c "cd '${cloneA}' && grep -q dirty file1.txt && ! git diff --quiet"
	fAssert "autostash fully popped"               bash -c "cd '${cloneA}' && [[ -z \"\$(git stash list)\" ]]"

	## newbr: parks work, branches off default, publishes with upstream
	fAssert "newbr feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q newbr feat"
	fAssert "now on feat"            bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssert "feat has upstream"      bash -c "cd '${cloneA}' && git rev-parse --abbrev-ref 'feat@{u}' >/dev/null"
	fAssert "parked edit committed"  bash -c "cd '${cloneA}' && git diff --quiet && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssertFail "newbr existing name rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q newbr feat"
	fAssertFail "newbr bad name rejected"       bash -c "cd '${cloneA}' && '${gitsby}' -q newbr 'bad name'"
	fAssertFail "newbr no name rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q newbr"

	## gobr: switch back and forth; bogus target rejected
	fAssert "gobr (default: main)"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr"
	fAssert "now on main"           bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "gobr feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q gobr feat"
	fAssert "back on feat"          bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssertFail "gobr nonexistent rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr nosuch"

	## land: merge feat into main --no-ff, then delete it local + remote
	( cd "${cloneA}" && echo feat > feat.txt )
	fAssert "land merges feat into main"  bash -c "cd '${cloneA}' && '${gitsby}' -q land 'merge feat work'"
	fAssert "now on main after land"      bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "merge commit is --no-ff"     bash -c "cd '${cloneA}' && git log -1 --merges --format=%s | grep -qx 'merge feat work'"
	fAssert "feat deleted locally"        bash -c "cd '${cloneA}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "feat deleted on origin"      bash -c "cd '${origin}' && ! git show-ref --verify --quiet refs/heads/feat"
	fAssert "main pushed after land"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	fAssertFail "land from main rejected" bash -c "cd '${cloneA}' && '${gitsby}' -q land"

	## dev-aware targeting: with a dev branch, newbr bases off dev and land merges to dev
	( cd "${cloneA}" && git checkout --quiet -b dev && git push --quiet -u origin dev )
	fAssert "newbr feat2 bases off dev"   bash -c "cd '${cloneA}' && '${gitsby}' -q newbr feat2 && [[ \"\$(git merge-base feat2 dev)\" == \"\$(git rev-parse dev)\" ]]"
	( cd "${cloneA}" && echo feat2 > feat2.txt )
	fAssert "land merges feat2 into dev"  bash -c "cd '${cloneA}' && '${gitsby}' -q land 'merge feat2 work'"
	fAssert "now on dev after land"       bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "feat2 landed on dev not main"  bash -c "cd '${cloneA}' && [[ -f feat2.txt ]] && ! git ls-tree --name-only main | grep -qx feat2.txt"
	fAssert "gobr with no arg goes to dev"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr main && '${gitsby}' -q gobr && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssertFail "land from dev rejected"    bash -c "cd '${cloneA}' && '${gitsby}' -q land"
	fAssertFail "land from main rejected (dev repo)"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr main && '${gitsby}' -q land; rc=\$?; git checkout --quiet dev; exit \$rc"

	## release: merge dev into main, tag, push; then auto-bump patch on the next one
	fAssert "release 1.2.3 runs"        bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssert "tag v1.2.3 on main"        bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse v1.2.3^{commit})\" == \"\$(git rev-parse main)\" ]]"
	fAssert "release merged dev to main"  bash -c "cd '${cloneA}' && git ls-tree --name-only main | grep -qx feat2.txt"
	fAssert "main pushed with tag"      bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]] && git ls-remote --tags origin | grep -q 'refs/tags/v1.2.3'"
	fAssert "back on dev after release"  bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssertFail "release same version rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertFail "release bad version rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q release bogus"
	( cd "${cloneA}" && echo more > more.txt )
	fAssert "release with no version bumps patch"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.2.4 >/dev/null"

	## Detached HEAD guard
	fAssertFail "mutating command on detached HEAD rejected"  bash -c "cd '${cloneA}' && git checkout --quiet HEAD~0 --detach && '${gitsby}' -q commit x"
	( cd "${cloneA}" && git checkout --quiet dev )

	## Messages with quotes pass through unmangled (no eval, no curly-quote games)
	( cd "${cloneA}" && echo q > q.txt )
	fAssert "message with quotes survives"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit \"don't \\\"quote\\\" me\" && git log -1 --format=%s | grep -qx \"don't \\\"quote\\\" me\""

	## pr needs gh; syntax errors surface without it doing anything
	fAssertFail "pr with bad number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr bogus"
	fAssertFail "pr ok with no number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr ok"
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
