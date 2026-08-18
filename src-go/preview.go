// The plan display. A static per-command recipe; the command functions do the
// real state checks at run time, which is what the '*' marks. 'commit' and 'pull'
// are not commands of their own - they stay here as the fragments the real ones
// compose their plans from.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

const pad = "    "

func preview(what string) {
	msgDisp := "git commit"
	if commitMessage != "" {
		msgDisp = `git commit -m "` + commitMessage + `"`
	}
	switch what {
	case "commit":
		echoClean(pad + "git add --all")
		echoClean(pad + msgDisp + " *")
	case "pull":
		echoClean(pad + "git pull --ff-only --autostash *")
	case "update":
		preview("pull")
		preview("commit")
	case "sync":
		preview("update")
		echoClean(pad + "git push (branch '" + currentBranch() + "') *")
	case "br-create":
		// From main/dev the dirty tree rides along to the new branch, so there's no
		// commit here.
		previewNewBranch(mergeTarget())
	case "br-hotfix":
		// Off the default branch, not dev: this corrects what is already published.
		previewNewBranch(defaultBranch())
	case "br-switch":
		// Already on the target: nothing is parked and no checkout happens, so the plan
		// must not promise an add/commit/push it will not do.
		target := cmdArg
		if target == "" {
			target = mergeTarget()
		}
		if currentBranch() != target {
			preview("sync")
			echoClean(pad + "git checkout " + target)
		}
		echoClean(pad + "git pull --ff-only *")
	case "br-land":
		preview("sync")
		echoClean(pad + "git checkout " + branchTarget(""))
		echoClean(pad + "git pull --ff-only *")
		echoClean(pad + "git merge --no-ff " + currentBranch())
		echoClean(pad + "git push *")
		echoClean(pad + "git branch -d " + currentBranch())
		echoClean(pad + "git push origin --delete " + currentBranch() + " *")
		echoClean(pad + "git pull --ff-only *")
		// A hotfix owes dev the same change, or the next release undoes it.
		if isHotfixBranch("") {
			echoClean(pad + "git checkout " + mergeTarget())
			echoClean(pad + "git merge " + backMergeRef())
			echoClean(pad + "git push *")
		}
	case "br-prune":
		prunePreview()
	}
	// The recipes for the pr, release, repo and account writers land with those
	// commands.
}

// previewNewBranch is br create and br hotfix - the same recipe off a different
// base.
func previewNewBranch(baseBranch string) {
	if isProtectedBranch("") {
		echoClean(pad + "git checkout " + baseBranch + " *")
		echoClean(pad + "git pull --ff-only --autostash *")
	} else {
		preview("sync")
		echoClean(pad + "git checkout " + baseBranch + " *")
		echoClean(pad + "git pull --ff-only *")
	}
	echoClean(pad + "git checkout -b " + cmdArg)
	echoClean(pad + "git push -u origin " + cmdArg + " *")
}
