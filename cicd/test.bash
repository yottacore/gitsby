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
## Assert the command's output matches an extended regex (for the pre-flight display).
## Capture rather than pipe: 'grep -q' would close the pipe early and pipefail would call that a failure.
fAssertOut(){  local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if grep -qE "$pat" <<< "${out}"; then fOk "$desc"; else fFail "$desc"; fi; }
fAssertNotOut(){ local desc="$1"; local pat="$2"; shift 2; local out=""; out="$("$@" 2>&1 || true)"
	if ! grep -qE "$pat" <<< "${out}"; then fOk "$desc"; else fFail "$desc"; fi; }

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

	## Pre-flight display: who we act as, and a compact list of what changes
	fAssertOut "status names the commit author"  'Author \.+:'            bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "clean worktree says so"          '\(working tree clean\)' bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	( cd "${cloneA}" && echo probe > probe.txt )
	fAssertOut "changed file listed"             '\?\? probe\.txt'        bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "mutating command previews first" 'Going to do'            bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'probe'"
	( cd "${cloneA}" && git reset --quiet --hard HEAD~1 )

	## commit: commits everything; idempotent when clean
	( cd "${cloneA}" && echo two > file2.txt )
	fAssert "commit commits new file"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'add file2'"
	fAssert "worktree clean after commit"      bash -c "cd '${cloneA}' && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "commit message recorded"          bash -c "cd '${cloneA}' && git log -1 --format=%s | grep -qx 'add file2'"
	fAssert "commit again (nothing to do) ok"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'noop'"
	( cd "${cloneA}" && echo alias > alias.txt )
	fAssert "old alias 'scommit' still works"  bash -c "cd '${cloneA}' && '${gitsby}' -q scommit 'via alias'"

	## update: commit + pull in one; old name still works
	( cd "${cloneA}" && echo upd > upd.txt )
	fAssert "update commits and pulls"        bash -c "cd '${cloneA}' && '${gitsby}' -q update 'add upd'"
	fAssert "worktree clean after update"     bash -c "cd '${cloneA}' && [[ -z \"\$(git status --porcelain)\" ]]"
	fAssert "old alias 'saveup' still works"  bash -c "cd '${cloneA}' && '${gitsby}' -q saveup"

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
	fAssertOut "behind count on the branch line"  'behind 1'   bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "incoming changes previewed"       'Incoming'   bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssertOut "incoming file named"              'fileB\.txt' bash -c "cd '${cloneA}' && '${gitsby}' -q status"
	fAssert "pull with dirty tree + remote ahead"  bash -c "cd '${cloneA}' && '${gitsby}' -q pull"
	fAssert "remote commit arrived"                bash -c "cd '${cloneA}' && [[ -f fileB.txt ]]"
	fAssert "local dirty edit survived"            bash -c "cd '${cloneA}' && grep -q dirty file1.txt && ! git diff --quiet"
	fAssert "autostash fully popped"               bash -c "cd '${cloneA}' && [[ -z \"\$(git stash list)\" ]]"

	## newbr: branches off default, publishes with upstream; dirty work on the
	## protected base is carried to the new branch, never committed to the base
	fAssert "newbr feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q newbr feat"
	fAssert "now on feat"            bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssert "feat has upstream"      bash -c "cd '${cloneA}' && git rev-parse --abbrev-ref 'feat@{u}' >/dev/null"
	fAssert "dirty edit carried uncommitted"  bash -c "cd '${cloneA}' && grep -q dirty file1.txt && ! git diff --quiet"
	fAssert "no WIP commit on main"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]] && ! git show main:file1.txt | grep -q dirty"
	( cd "${cloneA}" && git add --all && git commit --quiet -m "carried" )
	fAssertFail "newbr existing name rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q newbr feat"
	fAssertFail "newbr bad name rejected"       bash -c "cd '${cloneA}' && '${gitsby}' -q newbr 'bad name'"
	fAssertFail "newbr no name rejected"        bash -c "cd '${cloneA}' && '${gitsby}' -q newbr"

	## gobr: switch back and forth; bogus target rejected
	fAssert "gobr (default: main)"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr"
	fAssert "now on main"           bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "gobr feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q gobr feat"
	fAssert "back on feat"          bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssertFail "gobr nonexistent rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr nosuch"

	## gobr refuses to auto-commit WIP sitting on a protected branch
	( cd "${cloneA}" && git checkout --quiet main && echo wip >> file2.txt )
	fAssertFail "gobr from dirty main refuses"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr feat"
	fAssert "wip left uncommitted on main"      bash -c "cd '${cloneA}' && ! git diff --quiet && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	( cd "${cloneA}" && git checkout --quiet -- file2.txt && git checkout --quiet feat )

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
	fAssert "dev fast-forwarded to the release"  bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse dev)\" == \"\$(git rev-parse main)\" ]]"
	fAssert "dev pushed after release"           bash -c "cd '${cloneA}' && [[ \"\$(git rev-parse dev)\" == \"\$(git rev-parse origin/dev)\" ]]"
	fAssertFail "release same version rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertFail "release bad version rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q release bogus"
	( cd "${cloneA}" && echo more > more.txt )
	fAssert "release with no version bumps patch"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.2.4 >/dev/null"

	## release started from a feature branch returns there; slash branch names work
	fAssert "newbr relfeat"  bash -c "cd '${cloneA}' && '${gitsby}' -q newbr relfeat"
	( cd "${cloneA}" && echo rel > rel.txt )
	fAssert "release from a feature branch runs"  bash -c "cd '${cloneA}' && '${gitsby}' -q release"
	fAssert "returns to the feature branch"       bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == relfeat ]]"
	fAssert "newbr with a slash name"  bash -c "cd '${cloneA}' && '${gitsby}' -q newbr feat/x && [[ \"\$(git branch --show-current)\" == feat/x ]]"
	fAssert "gobr back to dev"         bash -c "cd '${cloneA}' && '${gitsby}' -q gobr && [[ \"\$(git branch --show-current)\" == dev ]]"

	## Detached HEAD guard
	fAssertFail "mutating command on detached HEAD rejected"  bash -c "cd '${cloneA}' && git checkout --quiet HEAD~0 --detach && '${gitsby}' -q commit x"
	( cd "${cloneA}" && git checkout --quiet dev )

	## Messages with quotes pass through unmangled (no eval, no curly-quote games)
	( cd "${cloneA}" && echo q > q.txt )
	fAssert "message with quotes survives"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit \"don't \\\"quote\\\" me\" && git log -1 --format=%s | grep -qx \"don't \\\"quote\\\" me\""

	## Message handling: -m and -m= forms; option-like words stay words; extra bare word rejected
	( cd "${cloneA}" && echo m1 > m1.txt )
	fAssert "commit -m flag form"     bash -c "cd '${cloneA}' && '${gitsby}' -q commit -m 'via -m flag' && git log -1 --format=%s | grep -qx 'via -m flag'"
	if [[ "$1" == "bash" ]]; then  ## -m=MSG is bash-only; pwsh binding has no -param=value form
		( cd "${cloneA}" && echo m2 > m2.txt )
		fAssert "commit -m= joined form"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit -m='via -m= flag' && git log -1 --format=%s | grep -qx 'via -m= flag'"
	fi
	( cd "${cloneA}" && echo m3 > m3.txt )
	fAssert "message containing -v commits"           bash -c "cd '${cloneA}' && '${gitsby}' -q commit 'add -v flag' && git log -1 --format=%s | grep -qx 'add -v flag'"
	fAssertFail "unquoted two-word message rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q commit Fixed bug"

	## Non-tty: mutating commands fail closed without -q; read-only ones just go quiet
	( cd "${cloneA}" && echo nt > nt.txt )
	fAssertFail "mutating without -q and no tty refuses"  bash -c "cd '${cloneA}' && '${gitsby}' commit ntmsg < /dev/null"
	fAssert "file left uncommitted"                       bash -c "cd '${cloneA}' && git status --porcelain | grep -q nt.txt"
	fAssert "read-only without -q still runs non-tty"     bash -c "cd '${cloneA}' && '${gitsby}' status < /dev/null"
	( cd "${cloneA}" && "${gitsby}" -q commit "nt cleanup" >/dev/null 2>&1 )

	## Credentialed remote URLs display masked (-NoFetch keeps it off the network; also lowercases to bash --nofetch)
	( cd "${cloneA}" && git remote set-url origin 'https://user:sekrit@127.0.0.1:1/x.git' )
	fAssertNotOut "no-fetch skips the fetch"           '\[ git fetch' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertOut    "remote URL masks credentials"       '\*\*\*@127\.0\.0\.1' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	fAssertNotOut "credential itself never shown"      'sekrit' bash -c "cd '${cloneA}' && '${gitsby}' -q -NoFetch status"
	( cd "${cloneA}" && git remote set-url origin "${origin}" )

	## pr needs gh; syntax errors surface without it doing anything
	fAssertFail "pr with bad number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr bogus"
	fAssertFail "pr ok with no number rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q pr ok"

	## land with an upstream-less target: the merge must reach origin before the remote work branch dies
	local fx2="${work}/$1-land2"
	local o2="${fx2}/origin.git"; local c2="${fx2}/a"; local c3="${fx2}/b"
	mkdir -p "${fx2}"
	git init --quiet --bare -b main "${o2}"
	git clone --quiet "${o2}" "${c2}" 2>/dev/null
	(
		cd "${c2}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev  ## local-only dev: no upstream
		git checkout --quiet -b feat9; git push --quiet -u origin feat9
		echo work > w.txt; git add --all; git commit --quiet -m "work"; git push --quiet
	)
	fAssert "land with upstream-less dev runs"      bash -c "cd '${c2}' && '${gitsby}' -q land 'merge feat9'"
	fAssert "merge reached origin (dev published)"  bash -c "cd '${o2}' && git show-ref --verify --quiet refs/heads/dev && git ls-tree --name-only dev | grep -qx w.txt"
	fAssert "feat9 deleted on origin after publish" bash -c "cd '${o2}' && ! git show-ref --verify --quiet refs/heads/feat9"

	## diverged pull with a dirty tree: fails, but work stays in the tree and out of the stash
	git clone --quiet "${o2}" "${c3}"
	( cd "${c3}" && git checkout --quiet dev && echo remote >> f.txt && git add --all && git commit --quiet -m "remote side" && git push --quiet )
	( cd "${c2}" && echo localc > localc.txt && git add --all && git commit --quiet -m "local side" && echo precious >> w.txt )
	fAssertFail "diverged pull fails"        bash -c "cd '${c2}' && '${gitsby}' -q pull"
	fAssert "dirty edit still in the tree"   bash -c "cd '${c2}' && grep -q precious w.txt"
	fAssert "nothing stranded in the stash"  bash -c "cd '${c2}' && [[ -z \"\$(git stash list)\" ]]"
	fAssertOut    "pull failure reads plainly"   'failed \(exit' bash -c "cd '${c2}' && '${gitsby}' -q pull"
	fAssertNotOut "no trap dump on git failure"  'Signal \.'     bash -c "cd '${c2}' && '${gitsby}' -q pull"

	## no-remote repo: everything still works locally
	local nr="${work}/$1-noremote"
	git init --quiet -b main "${nr}"
	( cd "${nr}" && echo a > a.txt && git add --all && git commit --quiet -m "initial" )
	fAssert "sync with no remote"   bash -c "cd '${nr}' && '${gitsby}' -q sync 'msg'"
	fAssert "newbr with no remote"  bash -c "cd '${nr}' && '${gitsby}' -q newbr nb && [[ \"\$(git branch --show-current)\" == nb ]]"
	( cd "${nr}" && echo b > b.txt )
	fAssert "land with no remote"   bash -c "cd '${nr}' && '${gitsby}' -q land 'merge nb'"
	fAssert "landed on main"        bash -c "cd '${nr}' && [[ \"\$(git branch --show-current)\" == main ]] && [[ -f b.txt ]]"
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
##		- 20260723 JC: Checks for the update command (and its old name), and for dev fast-forwarding after a release.
