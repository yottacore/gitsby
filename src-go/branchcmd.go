// The branch writers: create, hotfix, switch and land. Every one of them parks
// whatever is in the tree before it moves, so changing where you stand can't
// strand work - and land carries a hotfix on to dev, because the next release
// would otherwise undo it.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

// checkNewBranchName vets cmdArg for br create/hotfix. Git owns the rules for
// what a ref may be called, so ask git rather than keep a second copy of them.
func checkNewBranchName() {
	if !runOK("git", "check-ref-format", "--branch", cmdArg) {
		throwUsage("'" + cmdArg + "' is not a valid branch name.")
	}
	if branchExistsLocal(cmdArg) {
		throwUsage("Branch '" + cmdArg + "' already exists; use: " + meName + " br switch " + cmdArg)
	}
	if branchExistsRemote(cmdArg) {
		throwUsage("Branch '" + cmdArg + "' already exists on origin; use: " + meName + " br switch " + cmdArg)
	}
}

// cmdNewBranch is both 'br create' and 'br hotfix' - one recipe, different base.
// A hotfix comes off the default branch because it corrects what is already
// published; feature work still goes through dev. Branch-name validation already
// happened up front in main.
func cmdNewBranch(newBranch, baseBranch string) {
	if isProtectedBranch("") {
		// Don't commit WIP to main/dev; a dirty tree survives checkout -b, so carry it
		// to the new branch.
		if currentBranch() != baseBranch {
			runStep("git", "checkout", baseBranch)
		}
		pullIfOnline("--autostash")
	} else {
		cmdPush() // park current work safely first
		runStep("git", "checkout", baseBranch)
		pullIfOnline()
	}
	runStep("git", "checkout", "-b", newBranch)
	publishBranch(newBranch)
}

func cmdGoBranch(targetBranch string) {
	if targetBranch == "" {
		targetBranch = mergeTarget()
	}
	if currentBranch() == targetBranch {
		echoStatus("Already on '" + targetBranch + "'.")
		pullIfOnline()
		return
	}
	// The dirty-protected-branch refusal happens up front in main, before the plan
	// is shown.
	cmdPush()                                // park current work safely first
	runStep("git", "checkout", targetBranch) // auto-creates a tracking branch if it only exists on origin
	pullIfOnline()
}

// cmdLand merges the current branch into dev (or main/master) - backwards from
// 'git merge', but it saves a step.
func cmdLand() {
	workBranch := currentBranch()
	targetBranch := branchTarget(workBranch)
	if workBranch == targetBranch {
		throwUsage("Already on '" + targetBranch + "'. Run this from the branch to merge in: " + meName + " br switch <branch>, then " + meName + " br land")
	}
	if workBranch == defaultBranch() {
		throwUsage("'" + workBranch + "' is the default branch; landing it on '" + targetBranch + "' is backwards. To cut a release: " + meName + " release")
	}
	mergeMessage := commitMessage
	if mergeMessage == "" {
		mergeMessage = "Merge " + workBranch
	}
	wasHotfix := isHotfixBranch(workBranch)
	cmdPush()
	// After the push, not before: the warning reads the branch tip, and uncommitted
	// work only becomes part of it here. Checking first missed a hotfix whose bin/
	// edit was still in the working tree - the ordinary way of doing one.
	if wasHotfix {
		warnHotfixTouchedBin(workBranch, targetBranch)
	}
	runStep("git", "checkout", targetBranch)
	pullIfOnline()
	runStep("git", "merge", "--no-ff", workBranch, "-m", mergeMessage)
	// The merge must reach origin before the remote work branch goes away, or origin
	// loses its only ref to those commits. Publish an upstream-less target first.
	mergePublished := false
	switch {
	case !runOK("git", "remote", "get-url", "origin"):
	case isOffline():
		// A hotfix ends on dev after the back-merge, so a bare 'sync' from there would
		// publish dev and leave the default branch - the branch the hotfix exists to fix
		// - stale on origin. The switch's park push publishes dev on the way, so two
		// commands cover both.
		if wasHotfix {
			echoStatus("WARNING: remote unreachable; the merge to '" + targetBranch + "' is local only - once online, '" + meName + " br switch " + targetBranch + "' then '" + meName + " sync' publishes it.")
		} else {
			echoStatus("WARNING: remote unreachable; the merge to '" + targetBranch + "' is local only - '" + meName + " sync' publishes it.")
		}
	default:
		if hasUpstream() {
			runStep("git", "push")
		} else {
			runStep("git", "push", "-u", "origin", "HEAD")
		}
		mergePublished = true
	}
	runStep("git", "branch", "-d", workBranch)
	if branchExistsRemote(workBranch) {
		if !mergePublished {
			// The same rule as above, from the other side: with the merge still
			// unpublished, origin's copy of the branch is its only ref to those commits.
			echoStatus("Leaving origin's '" + workBranch + "' alone until the merge is pushed; '" + meName + " br prune' clears it later.")
		} else {
			// Non-fatal: someone (a PR merge, another clone) may have deleted it already.
			echoClean("")
			echoStatus("git push origin --delete " + workBranch + " ...")
			if !runInheritOK("git", "push", "origin", "--delete", workBranch) {
				echoStatus("WARNING: couldn't delete the remote branch (already gone?); continuing.")
			}
			echoResetBlank()
		}
	}
	pullIfOnline()
	// The hotfix now has to reach dev too, or the next release undoes it.
	if wasHotfix {
		backMergeToDev()
	}
}

// backMergeRef is what the back-merge actually merges. 'pr ok' lands the hotfix on
// the server, so the LOCAL default branch never sees it and merging that is a
// silent no-op; the fetched remote-tracking ref is the one holding it. After 'br
// land' the two are the same commit, so this is right either way - and it falls
// back to the local branch when there's no remote at all. Offline flips it back:
// land's push was skipped, so origin's copy is the stale one, and merging it would
// carry the hotfix nowhere. ('pr ok' can't run offline at all.)
func backMergeRef() string {
	mainBranch := defaultBranch()
	if !isOffline() && runOK("git", "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+mainBranch) {
		return "origin/" + mainBranch
	}
	return mainBranch
}

// backMergeToDev: after a hotfix lands on the default branch, dev has to receive
// it. Skipping this is how the next release conflicts on the same file, or quietly
// reinstates the text the hotfix replaced. A conflict here is raw-git territory:
// abort so the tree is left clean, and say so plainly.
func backMergeToDev() {
	mainBranch := defaultBranch()
	devBranch := mergeTarget()
	if devBranch == mainBranch { // no dev in this repo: nothing to carry back
		return
	}
	if !branchExistsLocal(devBranch) && !branchExistsRemote(devBranch) {
		return
	}
	mergeRef := backMergeRef()
	echoClean("")
	runStep("git", "checkout", devBranch)
	pullIfOnline()
	echoStatus("git merge " + mergeRef + " ...")
	if runInheritOK("git", "merge", mergeRef, "-m", "Merge "+mainBranch) {
		echoResetBlank()
		pushIfOnline()
	} else {
		_ = runOK("git", "merge", "--abort")
		echoResetBlank()
		echoStatus("WARNING: '" + mainBranch + "' would not merge cleanly into '" + devBranch + "'; left '" + devBranch + "' untouched.")
		echoClean("  The hotfix landed on '" + mainBranch + "' - that part is done.")
		echoClean("  Carry it across by hand: git checkout " + devBranch + " && git merge " + mergeRef)
	}
}

// warnHotfixTouchedBin: a hotfix that changes shipped code leaves the default
// branch carrying something no tag contains, so the latest release's assets stop
// matching it. Documentation does not.
func warnHotfixTouchedBin(workBranch, targetBranch string) {
	if runOut("git", "diff", "--name-only", targetBranch+"..."+workBranch, "--", "bin/") == "" {
		return
	}
	echoClean("")
	echoStatus("NOTE: this hotfix changes shipped code, not just documentation.")
	echoClean("  '" + targetBranch + "' will carry code that no tag contains, so the latest release's")
	echoClean("  downloads no longer match it. Cut a patch release when you're ready: " + meName + " release")
}
