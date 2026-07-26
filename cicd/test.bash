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
	fAssert     "bare 'help' word works"       "${gitsby}" help
	fAssert     "bare 'version' word works"    "${gitsby}" version
	fAssert     "-y alias accepted"            bash -c "cd '${cloneA}' && '${gitsby}' -y status"
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
	fAssertNotOut "bad branch arg dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q newbr 'bad name'"

	## gobr: switch back and forth; bogus target rejected
	fAssert "gobr (default: main)"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr"
	fAssert "now on main"           bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == main ]]"
	fAssert "gobr feat"             bash -c "cd '${cloneA}' && '${gitsby}' -q gobr feat"
	fAssert "back on feat"          bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == feat ]]"
	fAssertFail "gobr nonexistent rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr nosuch"

	## gobr refuses to auto-commit WIP sitting on a protected branch, before showing a plan
	( cd "${cloneA}" && git checkout --quiet main && echo wip >> file2.txt )
	fAssertFail   "gobr from dirty main refuses"           bash -c "cd '${cloneA}' && '${gitsby}' -q gobr feat"
	fAssertNotOut "and dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q gobr feat"
	fAssert "wip left uncommitted on main"      bash -c "cd '${cloneA}' && ! git diff --quiet && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"
	## newbr carries that same tree instead, so its plan must not promise a commit on main
	fAssertNotOut "newbr from main previews no commit"  'git add --all'  bash -c "cd '${cloneA}' && '${gitsby}' -q newbr wipcarry"
	fAssert "wip carried to the new branch"  bash -c "cd '${cloneA}' && [[ \"\$(git branch --show-current)\" == wipcarry ]] && ! git diff --quiet"
	( cd "${cloneA}" && git checkout --quiet -- file2.txt && git checkout --quiet feat
	  git branch --quiet -D wipcarry && git push --quiet origin --delete wipcarry )

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
	fAssertFail   "release same version rejected"  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertNotOut "duplicate tag dies before the preview"  'Going to do'  bash -c "cd '${cloneA}' && '${gitsby}' -q release 1.2.3"
	fAssertFail "release bad version rejected"   bash -c "cd '${cloneA}' && '${gitsby}' -q release bogus"
	( cd "${cloneA}" && echo more > more.txt )
	fAssert "release with no version bumps patch"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.2.4 >/dev/null"

	## A candidate's own version is what comes next, and once it's cut the bump resumes from it
	( cd "${cloneA}" && git tag -a v1.3.0-rc1 -m rc1 && echo cand > cand.txt )
	fAssert "release after a candidate takes the candidate's version"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.3.0 >/dev/null"
	fAssert "it did not skip past to a later patch"                    bash -c "cd '${cloneA}' && ! git rev-parse -q --verify refs/tags/v1.3.1 >/dev/null"
	( cd "${cloneA}" && echo post > post.txt )
	fAssert "the next release bumps off the full version, not the candidate"  bash -c "cd '${cloneA}' && '${gitsby}' -q release && git rev-parse -q --verify refs/tags/v1.3.1 >/dev/null"

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

	## release with an upstream-less main: the branch must reach origin, not just the tag
	local fx3="${work}/$1-rel2"
	local o5="${fx3}/origin.git"; local c5="${fx3}/a"
	mkdir -p "${fx3}"
	git init --quiet --bare -b main "${o5}"
	git clone --quiet "${o5}" "${c5}" 2>/dev/null
	(
		cd "${c5}"
		echo one > f.txt; git add --all; git commit --quiet -m "initial"; git push --quiet -u origin main
		git checkout --quiet -b dev; git push --quiet -u origin dev
		echo d > d.txt; git add --all; git commit --quiet -m "dev work"; git push --quiet
		git branch --unset-upstream main  ## however it got lost, main now tracks nothing
	)
	fAssert "release with an upstream-less main runs"  bash -c "cd '${c5}' && '${gitsby}' -q release 9.0.0"
	fAssert "origin main advanced, not just the tag"   bash -c "cd '${o5}' && git ls-tree --name-only main | grep -qx d.txt"
	fAssert "tag reached origin too"                   bash -c "cd '${c5}' && git ls-remote --tags origin | grep -q 'refs/tags/v9.0.0'"

	## diverged pull with a dirty tree: fails, but work stays in the tree and out of the stash
	git clone --quiet "${o2}" "${c3}"
	( cd "${c3}" && git checkout --quiet dev && echo remote >> f.txt && git add --all && git commit --quiet -m "remote side" && git push --quiet )
	( cd "${c2}" && echo localc > localc.txt && git add --all && git commit --quiet -m "local side" && echo precious >> w.txt )
	fAssertFail "diverged pull fails"        bash -c "cd '${c2}' && '${gitsby}' -q pull"
	fAssert "dirty edit still in the tree"   bash -c "cd '${c2}' && grep -q precious w.txt"
	fAssert "nothing stranded in the stash"  bash -c "cd '${c2}' && [[ -z \"\$(git stash list)\" ]]"
	fAssertOut    "pull failure reads plainly"   'failed \(exit' bash -c "cd '${c2}' && '${gitsby}' -q pull"
	fAssertNotOut "no trap dump on git failure"  'Signal \.'     bash -c "cd '${c2}' && '${gitsby}' -q pull"

	## clone: derives the dir, checks out dev when the repo has one, no-op re-run, collision guards
	local cl="${work}/$1-clone"
	mkdir -p "${cl}"
	fAssert "clone runs"                bash -c "cd '${cl}' && '${gitsby}' -q clone '${origin}' cl1"
	fAssert "clone checked out dev"     bash -c "cd '${cl}/cl1' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert "clone again (already cloned) ok"  bash -c "cd '${cl}' && '${gitsby}' -q clone '${origin}' cl1"
	fAssert "clone derives dir from url"       bash -c "cd '${cl}' && '${gitsby}' -q clone '${origin}' && [[ -d origin/.git ]]"
	fAssertFail "clone into non-empty dir rejected"  bash -c "cd '${cl}' && mkdir -p other && touch other/x && '${gitsby}' -q clone '${origin}' other"
	fAssertFail "clone with no url rejected"         bash -c "cd '${cl}' && '${gitsby}' -q clone"
	## a repo without dev stays on the default branch; a pre-existing empty dir is fine; a clone of a different url is refused
	local o3="${cl}/nodev.git"
	git init --quiet --bare -b main "${o3}"
	git clone --quiet "${o3}" "${cl}/nodev-seed" 2>/dev/null
	( cd "${cl}/nodev-seed" && echo n > n.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main )
	fAssert "clone of a no-dev repo stays on default"  bash -c "cd '${cl}' && '${gitsby}' -q clone '${o3}' nd && [[ \"\$(cd nd && git branch --show-current)\" == main ]]"
	fAssert "clone into a pre-existing empty dir"      bash -c "cd '${cl}' && mkdir -p pre && '${gitsby}' -q clone '${origin}' pre && [[ -d pre/.git ]]"
	fAssertFail "clone over a different-url clone refused"  bash -c "cd '${cl}' && '${gitsby}' -q clone '${o3}' cl1"

	## connect: publish a local-only repo to a fresh empty remote; idempotent; guards
	local cn="${work}/$1-connect"
	mkdir -p "${cn}"
	git init --quiet --bare -b main "${cn}/remote.git"
	git init --quiet -b main "${cn}/proj"
	( cd "${cn}/proj" && echo hi > hi.txt && git add --all && git commit --quiet -m "init" )
	fAssert "connect pushes to an empty remote"  bash -c "cd '${cn}/proj' && '${gitsby}' -q connect '${cn}/remote.git'"
	fAssert "remote got the commit"              bash -c "cd '${cn}/remote.git' && git ls-tree --name-only main | grep -qx hi.txt"
	fAssert "connect set the upstream"           bash -c "cd '${cn}/proj' && git rev-parse --abbrev-ref '@{u}' >/dev/null"
	fAssert "connect again (nothing to do) ok"   bash -c "cd '${cn}/proj' && '${gitsby}' -q connect"
	fAssert "connect commits then pushes new work"  bash -c "cd '${cn}/proj' && echo more > more.txt && '${gitsby}' -q connect && cd '${cn}/remote.git' && git ls-tree --name-only main | grep -qx more.txt"
	fAssertFail "connect different url rejected"    bash -c "cd '${cn}/proj' && '${gitsby}' -q connect '${cn}/other.git'"

	## connect from a plain directory: init + commit + push in one
	git init --quiet --bare -b main "${cn}/remote2.git"
	mkdir -p "${cn}/plain"; echo data > "${cn}/plain/data.txt"
	fAssert "connect from a non-repo dir"  bash -c "cd '${cn}/plain' && '${gitsby}' -q connect '${cn}/remote2.git'"
	fAssert "plain dir now a pushed repo"  bash -c "cd '${cn}/plain' && [[ \"\$(git rev-parse main)\" == \"\$(git rev-parse origin/main)\" ]]"

	## connect refuses remotes with history, unreachable remotes, and empty dirs
	git init --quiet -b main "${cn}/proj2"
	( cd "${cn}/proj2" && echo x > x.txt && git add --all && git commit --quiet -m "x" )
	fAssertFail "connect to nonempty remote rejected"  bash -c "cd '${cn}/proj2' && '${gitsby}' -q connect '${cn}/remote2.git'"
	fAssertFail "connect to missing remote rejected"   bash -c "cd '${cn}/proj2' && '${gitsby}' -q connect '${cn}/nosuch.git'"
	fAssertFail "connect in an empty dir rejected"     bash -c "mkdir -p '${cn}/empty' && cd '${cn}/empty' && '${gitsby}' -q connect '${cn}/remote.git'"
	## an inited repo with no commit and no files is nothing to connect; a matching explicit url re-connects fine (push mode)
	git init --quiet -b main "${cn}/bare-repo"
	fAssertFail "connect an empty inited repo rejected"  bash -c "cd '${cn}/bare-repo' && '${gitsby}' -q connect '${cn}/remote.git'"
	fAssert "connect accepts a matching explicit url"    bash -c "cd '${cn}/proj' && '${gitsby}' -q connect '${cn}/remote.git'"

	## connect owner/name: the gh path, driven by a deterministic fake gh (no network). Covers repo
	## create (repo absent), remote-add (repo present but empty, https + ssh protocols), and the
	## refuse-nonempty guard. Add-mode github URLs are rewritten onto a local bare via insteadOf so
	## the push lands offline; create-mode wiring is done inside the stub.
	local gh="${work}/$1-gh"
	mkdir -p "${gh}/bin"
	cat > "${gh}/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
## Test stub: deterministic gh, no network. Behavior driven by FAKE_GH_* env.
[[ -n "${FAKE_GH_LOG:-}" ]] && echo "$*" >> "${FAKE_GH_LOG}"
case "$1 $2" in
	"repo view")   case "${FAKE_GH_VIEW:-}" in notfound) exit 1 ;; empty) echo true ;; nonempty) echo false ;; esac ;;
	"config get")  echo "${FAKE_GH_PROTO:-https}" ;;
	"pr list")     echo "${FAKE_GH_EXISTING:-}" ;;  ## an already-open PR number for this branch, or nothing
	"pr create")   echo "https://github.com/me/proj/pull/${FAKE_GH_NEWPR:-1}" ;;
	"pr review")   : ;;  ## gitsby treats approval as best-effort; nothing to fake
	"pr merge")    ## Land the branch on the base, then drop it from the remote. Real gh does the delete
	               ## over the API, so the caller's origin/* copy survives it - restore the ref to match.
	               prBranch="$(git branch --show-current)"
	               prKeep="$(git rev-parse "refs/remotes/origin/${prBranch}")"
	               git push --quiet origin "HEAD:${FAKE_GH_BASE:-dev}"
	               git push --quiet origin --delete "${prBranch}"
	               git update-ref "refs/remotes/origin/${prBranch}" "${prKeep}" ;;
	"repo create") git init --quiet --bare -b main "${FAKE_GH_REMOTE}"
	               git remote add origin "${FAKE_GH_REMOTE}"
	               git push --quiet -u origin HEAD ;;
	*) echo "fake gh: unhandled: $*" >&2; exit 2 ;;
esac
GHEOF
	chmod +x "${gh}/bin/gh"
	local ghp="${gh}/bin:${PATH}"

	## create: repo doesn't exist yet -> gitsby inits + commits, the stub creates and pushes
	mkdir -p "${gh}/create"; echo c > "${gh}/create/c.txt"
	fAssert "connect owner/name creates a missing repo"  bash -c "cd '${gh}/create' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/created.git' FAKE_GH_LOG='${gh}/create.log' '${gitsby}' -q connect me/proj"
	fAssert "created repo got the commit"                bash -c "cd '${gh}/created.git' && git ls-tree --name-only main | grep -qx c.txt"
	fAssert "create defaulted to a private repo"         bash -c "grep -q -- '--private' '${gh}/create.log'"
	mkdir -p "${gh}/pub"; echo p > "${gh}/pub/p.txt"
	if [[ "$1" == "bash" ]]; then  ## visibility flag spelled per implementation
		fAssert "connect --public creates a public repo"  bash -c "cd '${gh}/pub' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/pub.git' FAKE_GH_LOG='${gh}/pub.log' '${gitsby}' -q --public connect me/proj && grep -q -- '--public' '${gh}/pub.log'"
	else
		fAssert "connect -Public creates a public repo"   bash -c "cd '${gh}/pub' && PATH='${ghp}' FAKE_GH_VIEW=notfound FAKE_GH_REMOTE='${gh}/pub.git' FAKE_GH_LOG='${gh}/pub.log' '${gitsby}' -q -Public connect me/proj && grep -q -- '--public' '${gh}/pub.log'"
	fi

	## add: repo exists but is empty -> gitsby builds the URL from git_protocol and pushes to it
	git init --quiet --bare -b main "${gh}/backing-https.git"
	printf '[url "%s"]\n\tinsteadOf = https://github.com/me/proj.git\n' "${gh}/backing-https.git" > "${gh}/gc-https"
	mkdir -p "${gh}/add-https"; ( cd "${gh}/add-https" && git init --quiet -b main && echo h > h.txt && git add --all && git commit --quiet -m init )
	fAssert "connect owner/name adds an https remote to an empty repo"  bash -c "cd '${gh}/add-https' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=https GIT_CONFIG_GLOBAL='${gh}/gc-https' '${gitsby}' -q connect me/proj"
	fAssert "https url recorded as origin"  bash -c "cd '${gh}/add-https' && [[ \"\$(git remote get-url origin)\" == 'https://github.com/me/proj.git' ]]"
	fAssert "empty repo received the push"  bash -c "cd '${gh}/backing-https.git' && git ls-tree --name-only main | grep -qx h.txt"
	git init --quiet --bare -b main "${gh}/backing-ssh.git"
	printf '[url "%s"]\n\tinsteadOf = git@github.com:me/proj.git\n' "${gh}/backing-ssh.git" > "${gh}/gc-ssh"
	mkdir -p "${gh}/add-ssh"; ( cd "${gh}/add-ssh" && git init --quiet -b main && echo s > s.txt && git add --all && git commit --quiet -m init )
	fAssert "ssh protocol builds an scp-style origin url"  bash -c "cd '${gh}/add-ssh' && PATH='${ghp}' FAKE_GH_VIEW=empty FAKE_GH_PROTO=ssh GIT_CONFIG_GLOBAL='${gh}/gc-ssh' '${gitsby}' -q connect me/proj && [[ \"\$(git remote get-url origin)\" == 'git@github.com:me/proj.git' ]]"

	## reject: repo already has commits
	mkdir -p "${gh}/reject"; ( cd "${gh}/reject" && git init --quiet -b main && echo r > r.txt && git add --all && git commit --quiet -m init )
	fAssertFail "connect owner/name refuses a nonempty repo"  bash -c "cd '${gh}/reject' && PATH='${ghp}' FAKE_GH_VIEW=nonempty '${gitsby}' -q connect me/proj"

	## pr ok run from the PR's own branch: gh deletes the branch on the remote but leaves our
	## origin/* copy, so the upstream still looks alive and pulling it can only fail.
	mkdir -p "${gh}/prok"
	git init --quiet --bare -b main "${gh}/prok/origin.git"
	local prc="${gh}/prok/c"
	git clone --quiet "${gh}/prok/origin.git" "${prc}" 2>/dev/null
	(
		cd "${prc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b prfeat && echo work > work.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin prfeat
	)
	fAssertOut "pr ok plans the branch switch"  'git checkout dev'  bash -c "cd '${prc}' && PATH='${ghp}' FAKE_GH_BASE=dev '${gitsby}' -q pr ok 7"
	fAssert    "pr ok landed on the merge target"  bash -c "cd '${prc}' && [[ \"\$(git branch --show-current)\" == dev ]]"
	fAssert    "pr ok pulled the merged work"      bash -c "cd '${prc}' && git ls-tree --name-only dev | grep -qx work.txt"
	fAssert    "the merged branch is gone from origin"  bash -c "cd '${prc}' && ! git ls-remote --heads origin prfeat | grep -q prfeat"

	## pr new: parks the work, then opens the PR against the merge target. Same fake gh.
	mkdir -p "${gh}/prnew"
	git init --quiet --bare -b main "${gh}/prnew/origin.git"
	local pnc="${gh}/prnew/c"
	git clone --quiet "${gh}/prnew/origin.git" "${pnc}" 2>/dev/null
	(
		cd "${pnc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b pnfeat && echo work > work.txt && git add --all && git commit --quiet -m "Teach it to retry"
	)
	fAssertFail "pr new refuses from the merge target"  bash -c "cd '${pnc}' && git checkout --quiet dev && PATH='${ghp}' '${gitsby}' -q pr new 'nope'"
	fAssertFail "pr new refuses an already-open PR"     bash -c "cd '${pnc}' && git checkout --quiet pnfeat && PATH='${ghp}' FAKE_GH_EXISTING=99 '${gitsby}' -q pr new"
	fAssert     "pr new opens the PR"                   bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prnew.log' '${gitsby}' -q pr new"
	fAssert     "pr new pushed the branch first"        bash -c "cd '${pnc}' && git ls-remote --heads origin pnfeat | grep -q pnfeat"
	fAssert     "pr new based the PR on the merge target"  bash -c "grep -q -- '--base dev' '${gh}/prnew.log'"
	fAssert     "pr new titled it from the last commit" bash -c "grep -q -- '--title Teach it to retry' '${gh}/prnew.log'"
	## An explicit title wins over the commit subject.
	(
		cd "${pnc}" || exit 1
		git checkout --quiet -b pnfeat2 && echo more > more.txt && git add --all && git commit --quiet -m "Commit subject"
	)
	fAssert "pr new takes an explicit title"  bash -c "cd '${pnc}' && PATH='${ghp}' FAKE_GH_LOG='${gh}/prnew2.log' '${gitsby}' -q pr new 'Explicit title' && grep -q -- '--title Explicit title' '${gh}/prnew2.log'"

	## pr ok refuses to merge while work is still only local: gh merges what origin has, then
	## deletes the branch, so anything unpushed would be outside both the PR and the merge.
	mkdir -p "${gh}/prguard"
	git init --quiet --bare -b main "${gh}/prguard/origin.git"
	local pgc="${gh}/prguard/c"
	git clone --quiet "${gh}/prguard/origin.git" "${pgc}" 2>/dev/null
	(
		cd "${pgc}" || exit 1
		echo base > base.txt && git add --all && git commit --quiet -m init && git push --quiet -u origin main
		git checkout --quiet -b dev && git push --quiet -u origin dev
		git checkout --quiet -b pgfeat && echo w > w.txt && git add --all && git commit --quiet -m work
		git push --quiet -u origin pgfeat
	)
	fAssertFail "pr ok refuses a dirty tree"  bash -c "cd '${pgc}' && echo dirt > dirt.txt && PATH='${ghp}' '${gitsby}' -q pr ok 7"
	fAssert     "pr ok left the dirty work alone"  bash -c "cd '${pgc}' && [[ -f dirt.txt ]] && [[ \"\$(git branch --show-current)\" == pgfeat ]]"
	fAssertFail "pr ok refuses unpushed commits"  bash -c "cd '${pgc}' && rm -f dirt.txt && echo u > u.txt && git add --all && git commit --quiet -m unpushed && PATH='${ghp}' '${gitsby}' -q pr ok 7"
	fAssert     "pr ok kept the unpushed commit"  bash -c "cd '${pgc}' && git log -1 --pretty=%s | grep -qx unpushed"
	fAssert     "pr ok proceeds once synced"  bash -c "cd '${pgc}' && git push --quiet && PATH='${ghp}' FAKE_GH_BASE=dev '${gitsby}' -q pr ok 7"

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
##		- 20260724 JC: clone and connect checks (dev checkout, no-op re-runs, plain-dir connect, nonempty/missing-remote and collision guards).
##		- 20260724 JC: exhaustive clone/connect coverage - no-dev/empty-dir/different-url clone edges, empty-repo + matching-url connect, and the gh owner/name paths (create, add https/ssh, nonempty-refuse) via a hermetic fake gh.
##		- 20260725 JC: Release-candidate version checks, and pr ok from the merged branch - the fake gh grew a pr merge that restores the stale origin ref, since that is what makes the real failure reproduce.
