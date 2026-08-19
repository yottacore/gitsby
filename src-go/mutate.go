// The writing half: the commit/pull/push core that update, sync and the branch
// commands compose their own recipes from, plus prune's executor. Every step
// re-asks the repo what state it is in, so a plan that sat at a prompt still
// skips whatever no longer applies.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strconv"
	"strings"
	"time"
)

// The stamp quiet mode falls back to when it has no message and no editor.
var serialDT = time.Now().Format("20060102-150405")

func cmdCommit() {
	// Never stage a conflicted tree. 'git add --all' marks a conflicted file
	// resolved, so the markers themselves would be committed, and then pushed by
	// sync. Ordinary use reaches this: a pull whose autostash reapply conflicts
	// still exits 0, so nothing upstream of here notices.
	if conflicted := runLines("git", "diff", "--name-only", "--diff-filter=U"); len(conflicted) > 0 {
		echoClean("")
		echoStatus("Unresolved conflicts; nothing was committed:")
		cappedLines(conflicted)
		throwUsage("Resolve those, then run '" + meName + " pullcom' again. Git also kept your pre-pull tree - see 'git stash list'.")
	}
	runStep("git", "add", "--all")
	switch {
	case runOut("git", "status", "--porcelain") == "":
		echoStatus("Nothing to commit.")
	case commitMessage != "":
		runStep("git", "commit", "-m", commitMessage)
	case quiet:
		runStep("git", "commit", "-m", meName+" "+serialDT) // quiet mode can't open an editor
	default:
		runStep("git", "commit")
	}
}

func cmdPull() {
	// --autostash instead of a manual stash push/pop: a failed pull (diverged,
	// offline) leaves the tree intact instead of stranding work in the stash.
	// Skipping beats failing when the remote is simply out of reach: update is the
	// only way to commit, so being offline must not turn a good commit into a
	// failed command. A reachable remote that can't fast-forward is a real problem
	// and still fails hard.
	switch {
	case !doFetch:
		echoStatus("Skipping the pull (--no-fetch).")
	case !remoteReachable:
		echoStatus("WARNING: remote unreachable; skipping the pull. Local changes still get committed.")
	case hasUpstream():
		runStep("git", "pull", "--ff-only", "--autostash")
	default:
		echoStatus("No upstream configured for this branch; nothing to pull.")
	}
}

// pullIfOnline is the pull inside a multi-step command. Same offline rule as
// cmdPull, quietly: --no-fetch and an unreachable remote both mean skip. Extra
// arguments go through to git pull.
func pullIfOnline(extra ...string) {
	if doFetch && remoteReachable && hasUpstream() {
		runStep("git", append([]string{"pull", "--ff-only"}, extra...)...)
	}
}

// pushIfOnline is the park push, for a command that still means something without
// it. The commands that exist to publish never get here - they are refused up
// front - so nothing reports success having sent nothing. Silence would read as
// published, hence the note, which names the branch: the command may move off it
// next (br switch, land), and a 'sync' from wherever you end up would publish
// that branch, not this one.
func pushIfOnline() {
	if !hasOrigin() {
		echoStatus("No 'origin' remote; nothing to push.")
		return
	}
	switch {
	case hasUpstream() && !isAhead():
		// True offline too: nothing local is ahead of the last-known origin.
		echoStatus("Nothing to push.")
	case isOffline():
		echoStatus("WARNING: remote unreachable; skipping the push. The work stays local on '" + currentBranch() + "' - '" + meName + " sync' from it publishes it.")
	case !hasUpstream():
		runStep("git", "push", "-u", "origin", "HEAD") // first publish of this branch
	default:
		runStep("git", "push")
	}
}

// requireOnline: cmd as typed, and what to do instead.
func requireOnline(cmd, instead string) {
	if isOffline() {
		throwUsage("Can't reach origin, and '" + cmd + "' has nothing left to do without it. " + instead)
	}
}

// publishBranch is a new branch's own first push, which is separate from the park
// push above it.
func publishBranch(branch string) {
	if !hasOrigin() {
		return
	}
	if isOffline() {
		echoStatus("WARNING: remote unreachable; '" + branch + "' is local only for now - '" + meName + " sync' publishes it.")
	} else {
		runStep("git", "push", "-u", "origin", branch)
	}
}

// cmdCommitPull pulls BEFORE committing. Committing first mints a local commit,
// so a remote that merely moved ahead is now diverged and --ff-only refuses -
// which is the everyday case, not an edge one. Pulling first fast-forwards (the
// dirty tree rides over on --autostash) and the commit lands on top, so history
// stays linear and --ff-only stays satisfiable.
func cmdCommitPull() {
	cmdPull()
	cmdCommit()
}

func cmdPush() {
	cmdCommitPull()
	pushIfOnline()
}

// cmdPrune deletes exactly what the plan listed - resolvePrune did all the
// deciding, up front.
func cmdPrune() {
	doneLocal, doneRemote := 0, 0
	reKept := map[string]bool{}
	for _, branch := range pruneLocal {
		// -D with our own gate, not -d. 'git branch -d' asks whether the branch is
		// contained in its upstream, or in HEAD when it has none - neither of which is
		// the question here, and the second one refuses a genuinely-merged local-only
		// branch from any other branch. Re-checked right now rather than trusting the
		// plan: the prompt may have sat a while.
		if !isMergedInto("refs/heads/"+branch, pruneTargetRefs) {
			echoStatus("'" + branch + "' is no longer contained in " + mergeTarget() + "; leaving it alone.")
			reKept[branch] = true
			continue
		}
		runStep("git", "branch", "-D", branch)
		doneLocal++
	}
	for _, branch := range pruneRemote {
		// "Leaving it alone" has to mean the remote copy too, or the message is a lie.
		if reKept[branch] {
			continue
		}
		// Non-fatal, same as br merge: someone else may have deleted it already.
		echoClean("")
		echoStatus("git push origin --delete " + branch + " ...")
		if runInheritOK("git", "push", "origin", "--delete", branch) {
			doneRemote++
		} else {
			echoStatus("WARNING: couldn't delete origin/" + branch + " (already gone?); continuing.")
		}
		echoResetBlank()
	}
	// Close with the count, so a wall of git output still ends in a plain answer.
	echoClean("")
	echoStatus("Pruned " + strconv.Itoa(doneLocal) + " local, " + strconv.Itoa(doneRemote) + " on origin.")
	if pruneCurrentMerged != "" {
		echoStatus("Kept '" + pruneCurrentMerged + "' - merged, but it's the current branch.")
	}
	if len(pruneKeep) > 0 {
		echoStatus("Kept " + strings.Join(pruneKeep, ", ") + " - not merged into " + mergeTarget() + " yet.")
	}
}
