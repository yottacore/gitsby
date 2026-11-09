// The writing half: the commit/pull/push core that pullcom, sync and the branch
// commands compose their own recipes from, plus prune's executor. Every step
// re-asks the repo what state it is in, so a plan that sat at a prompt still
// skips whatever no longer applies.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"runtime"
	"strconv"
	"strings"
)

func (a *app) cmdCommit() error {
	// Never stage a conflicted tree. 'git add --all' marks a conflicted file
	// resolved, so the markers themselves would be committed, and then pushed by
	// sync. Ordinary use reaches this: a pull whose autostash reapply conflicts
	// still exits 0, so nothing upstream of here notices.
	if conflicted := runLines("git", "diff", "--name-only", "--diff-filter=U"); len(conflicted) > 0 {
		a.out.clean("")
		a.out.status("Unresolved conflicts; nothing was committed:")
		a.showLines(conflicted)
		if a.opt.staged { // nothing was stashed
			return usagef("Resolve those, then run '%s pullcom' again.", meName)
		}
		return usagef("Resolve those, then run '%s pullcom' again. Git also kept your pre-pull tree - see 'git stash list'.", meName)
	}
	if a.opt.staged {
		if runOK("git", "diff", "--cached", "--quiet") {
			a.out.status("Nothing staged, so nothing was committed.")
			return nil
		}
	} else {
		if err := a.step("git", "add", "--all"); err != nil {
			return err
		}
		if runOut("git", "status", "--porcelain") == "" {
			a.out.status("Nothing to commit.")
			return nil
		}
	}
	switch {
	case a.opt.message != "":
		return a.step("git", "commit", "-m", a.opt.message)
	case a.opt.quiet:
		return a.step("git", "commit", "-m", meName+" "+a.stamp) // quiet mode can't open an editor
	default:
		return a.step("git", "commit")
	}
}

func (a *app) cmdPull() error {
	// --autostash, so a failed pull leaves the tree as it was, not work in the stash.
	// Offline skips the pull, since pullcom is the only way to commit; --no-fetch skips
	// it too.
	switch {
	case !a.opt.fetch:
		a.out.status("Skipping the pull (--no-fetch).")
	case a.isOffline():
		a.out.status("WARNING: remote unreachable; skipping the pull. Local changes still get committed.")
	case a.hasUpstream():
		return a.step("git", a.pullArgs(a.autostash()...)...)
	default:
		a.out.status("No upstream configured for this branch; nothing to pull.")
	}
	return nil
}

// pullIfOnline is the pull inside a multi-step command. Same offline rule as
// cmdPull, quietly: --no-fetch and an unreachable remote both mean skip. Extra
// arguments go through to git.
func (a *app) pullIfOnline(extra ...string) error {
	if a.opt.fetch && !a.isOffline() && a.hasUpstream() {
		return a.step("git", a.pullArgs(extra...)...)
	}
	return nil
}

// pullArgs is the pull for a branch with an upstream. It merges what the command's fetch
// left, which the plan showed. An upstream on another remote still pulls.
func (a *app) pullArgs(extra ...string) []string {
	return pullArgsFor(a.upstream(), extra...)
}

// pullArgsFor names the upstream the way git shortens it, so the plan and the merge say
// the same branch. A local one starting with a dash goes by its full ref.
func pullArgsFor(upstream upstreamRef, extra ...string) []string {
	if upstream.full != "" && !strings.HasPrefix(upstream.full, "refs/remotes/origin/") && !strings.HasPrefix(upstream.full, "refs/heads/") {
		return append([]string{"pull", "--ff-only"}, extra...)
	}
	name := upstream.short
	switch {
	case upstream.full == "":
		name = "@{u}"
	case name == "" || strings.HasPrefix(name, "-"):
		name = upstream.full
	}
	args := append([]string{"merge", "--ff-only"}, extra...)
	return append(args, name)
}

// pushIfOnline is the park push, for a command that still means something without it.
// Offline gets a note naming the branch, since the command may move off it next.
func (a *app) pushIfOnline() error {
	if !a.hasOrigin() {
		a.out.status("No 'origin' remote; nothing to push.")
		return nil
	}
	switch {
	case a.hasUpstream() && !isAhead():
		// True offline too: nothing local is ahead of the last-known origin.
		a.out.status("Nothing to push.")
	case a.isOffline():
		a.out.status("WARNING: remote unreachable; skipping the push. The work stays local on '" + a.currentBranch() + "' - '" + meName + " sync' from it publishes it.")
	default:
		return a.step("git", a.pushArgs()...)
	}
	return nil
}

// directPush: sync is about to send your own commits straight to main, dev or the
// default branch. A merge left for sync doesn't count. design.md "--direct".
func (a *app) directPush() bool {
	if a.cmd.name != "sync" || a.opt.direct || !a.hasOrigin() || !a.isProtectedBranch("") {
		return false
	}
	if a.hasUpstream() && runOut("git", "rev-list", "--first-parent", "--no-merges", "-n", "1", "@{u}..HEAD") != "" {
		return true
	}
	if a.opt.staged {
		return !runOK("git", "diff", "--cached", "--quiet")
	}
	return runOut("git", "status", "--porcelain") != ""
}

func (a *app) directPushText() string {
	return "This pushes your work straight to '" + a.currentBranch() + "'. But the recommended workflow is to push to a branch and merge one level higher through a pull request."
}

// pushArgs pushes the current branch. One with no upstream yet is a first publish:
// it goes up under its own name and tracks origin's copy from then on.
func (a *app) pushArgs() []string {
	if !a.hasUpstream() {
		return []string{"push", "-u", "origin", "HEAD"}
	}
	return []string{"push"}
}

// pushesToRemote: whether this command sends anything to origin, since the identity
// check costs an ssh probe. Named by exception, so a new mutating command is covered.
func (a *app) pushesToRemote() bool {
	switch a.cmd.name {
	case "pullcom", "repo-clone", "repo-url", "account-apply", "account-set", "account-unset":
		return false
	}
	return a.cmd.mutating
}

// requireOnline: cmd as typed, and what to do instead.
func (a *app) requireOnline(cmd, instead string) error {
	if a.isOffline() {
		return usagef("Can't reach origin, and '%s' has nothing left to do without it. %s", cmd, instead)
	}
	return nil
}

// publishBranch is a new branch's own first push, which is separate from the park
// push above it. It runs right after the checkout, so HEAD is the branch, and a tag
// with the branch's name can't make the push ambiguous the way the name would.
func (a *app) publishBranch(branch string) error {
	if !a.hasOrigin() {
		return nil
	}
	if a.isOffline() {
		a.out.status("WARNING: remote unreachable; '" + branch + "' is local only for now - '" + meName + " sync' publishes it.")
		return nil
	}
	return a.step("git", "push", "-u", "origin", "HEAD")
}

// cmdCommitPull pulls before committing, so a remote that moved ahead fast-forwards and
// the commit goes on top. Committing first would leave it diverged for --ff-only.
func (a *app) cmdCommitPull() error {
	if err := a.cmdPull(); err != nil {
		return err
	}
	return a.cmdCommit()
}

func (a *app) cmdPush() error {
	if err := a.cmdCommitPull(); err != nil {
		return err
	}
	return a.pushIfOnline()
}

// cmdPrune deletes exactly what the plan listed - resolvePrune did all the
// deciding, up front.
func (a *app) cmdPrune() error {
	doneLocal := 0
	heldBack := map[string]bool{}
	// -D with our own gate, since -d asks about the upstream or HEAD. Re-checked now, as
	// the prompt may have sat, by one 'for-each-ref --merged' per target. A branch gone
	// since reads as not merged.
	stillMerged := map[string]bool{}
	unconfirmed := func() bool {
		for _, branch := range a.prune.local {
			if !stillMerged[branch] {
				return true
			}
		}
		return false
	}
	for _, ref := range a.prune.targetRefs {
		// Later refs are asked only while a candidate is still unconfirmed, so the
		// common case - everything merged through the first ref - costs one call.
		if !unconfirmed() {
			break
		}
		for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:lstrip=2)", "--merged", ref, "refs/heads/") {
			stillMerged[branch] = true
		}
	}
	for _, branch := range a.prune.local {
		if !stillMerged[branch] {
			a.out.status("'" + branch + "' is no longer contained in " + a.mergeTarget() + "; leaving it alone.")
			heldBack[branch] = true
		}
	}
	// "Leaving it alone" has to mean the remote copy too, or the message is a lie.
	remoteLeft := func() []string {
		var branches []string
		for _, branch := range a.prune.remote {
			if !heldBack[branch] {
				branches = append(branches, branch)
			}
		}
		return branches
	}
	// Origin is asked before anything is deleted here, so a copy origin has moved
	// keeps its local branch too. Prune finds its candidates among local branches,
	// and a second run can't look again at one that is already gone.
	var onOrigin map[string]string
	asked := false
	if remote := remoteLeft(); len(remote) > 0 && !a.isOffline() {
		onOrigin, asked = a.askOriginHeads()
		if asked {
			_, changed, _ := sortRemoteDeletes(remote, a.prune.remoteTip, onOrigin)
			for _, branch := range changed {
				heldBack[branch] = true
			}
			if len(changed) > 0 {
				again := "again"
				if !a.opt.fetch {
					again = "without --no-fetch"
				}
				a.out.status("WARNING: origin's copies of " + strings.Join(changed, ", ") + " have changed since this clone last fetched; kept them here and on origin - '" + meName + " br prune' " + again + " takes a fresh look.")
			}
		}
	}
	var deleteLocal []string
	for _, branch := range a.prune.local {
		if !heldBack[branch] {
			deleteLocal = append(deleteLocal, branch)
		}
	}
	// One call, not one per branch. Each fork of git costs a process and takes its own
	// helpers with it, and this is the command most likely to be handed eight branches at
	// once - which was two thirds of everything it spawned.
	if len(deleteLocal) > 0 {
		a.out.clean("")
		a.out.status("git branch -D " + strings.Join(deleteLocal, " ") + " ...")
		// Non-fatal, the same way the remote half below is. git deletes the branches it
		// can and exits nonzero for the rest - one checked out in another worktree, most
		// often - and returning that ended the run with those deletions already done,
		// origin untouched, and no count printed at all.
		if a.inheritOK("git", append([]string{"branch", "-D"}, deleteLocal...)...) {
			doneLocal = len(deleteLocal)
		} else {
			var stillHere []string
			for _, branch := range deleteLocal {
				if a.branchExistsLocal(branch) {
					stillHere = append(stillHere, branch)
					// Its remote copy stays too: deleting that would leave a branch here
					// with nothing on origin behind it.
					heldBack[branch] = true
				} else {
					doneLocal++
				}
			}
			if len(stillHere) > 0 {
				a.out.status("WARNING: couldn't delete " + strings.Join(stillHere, ", ") + " here (checked out in another worktree?); continuing.")
			}
		}
		a.out.resetBlank()
	}
	doneRemote := a.pruneRemote(remoteLeft(), onOrigin, asked)
	// Close with the count, so a wall of git output still ends in a plain answer.
	a.out.clean("")
	a.out.status("Pruned " + strconv.Itoa(doneLocal) + " local, " + strconv.Itoa(doneRemote) + " on origin.")
	if a.prune.currentMerged != "" {
		a.out.status("Kept '" + a.prune.currentMerged + "' - merged, but it's the current branch.")
	}
	if len(a.prune.keep) > 0 {
		a.out.status("Kept " + strings.Join(a.prune.keep, ", ") + " - not merged into " + a.mergeTarget() + " yet.")
	}
	return nil
}

// pruneRemote deletes br prune's remote half and says how many went. Each delete is
// leased on the value cmdPrune got from origin. asked false: origin couldn't be asked.
func (a *app) pruneRemote(branches []string, onOrigin map[string]string, asked bool) int {
	if len(branches) == 0 {
		return 0
	}
	// Same rule br merge keeps: nothing goes out while origin is unreachable, or the
	// count at the end reads as if it had finished.
	if !asked {
		a.pruneHeldOffline(branches)
		return 0
	}
	// A copy origin moved was held back with its local branch, so none is left here.
	send, _, gone := sortRemoteDeletes(branches, a.prune.remoteTip, onOrigin)
	// Not a warning: gone is what was asked for. Left out of the push, since one delete of a
	// missing ref makes git send none of them.
	if len(gone) > 0 {
		a.out.status("Already gone from origin: " + strings.Join(gone, ", ") + ".")
	}
	done := 0
	var stillThere []string
	for _, batch := range leaseDeleteBatches(send, a.prune.remoteTip, leasePushBudget) {
		a.out.clean("")
		a.out.status("git push --force-with-lease origin --delete " + strings.Join(batch.branches, " ") + " ...")
		if a.inheritOK("git", batch.args...) {
			done += len(batch.branches)
		} else {
			// Non-fatal, same as br merge. A leased delete is decided per ref, so count what
			// went rather than writing the batch off: a delete that went through takes the
			// remote-tracking ref with it, which is a local lookup.
			for _, branch := range batch.branches {
				if a.branchExistsRemote(branch) {
					stillThere = append(stillThere, branch)
				} else {
					done++
				}
			}
		}
		a.out.resetBlank()
	}
	if len(stillThere) > 0 {
		a.out.status("WARNING: couldn't delete " + strings.Join(stillThere, ", ") + " on origin; continuing.")
	}
	return done
}

// pruneHeldOffline is the one wording for origin's copies held back because origin
// can't be reached, whether the fetch found that or the delete-time ask did. The
// local branches are gone by then, so another prune would find nothing to look at.
// It names the deletes themselves instead, leased on what was checked.
func (a *app) pruneHeldOffline(branches []string) {
	a.out.status("WARNING: remote unreachable; left origin's copies of " + strings.Join(branches, ", ") + " alone.")
	a.out.clean("  Once origin can be reached, these delete them. Each one stops if that branch has moved:")
	for _, branch := range branches {
		a.out.clean(planPad + leaseDeleteLine(branch, a.prune.remoteTip[branch], runtime.GOOS))
	}
}
