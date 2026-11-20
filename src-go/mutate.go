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
	"bytes"
	"cmp"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
)

func (a *app) cmdCommit() error {
	// Never stage a conflicted tree. 'git add --all' marks a conflicted file
	// resolved, so the markers themselves would be committed, and then pushed by
	// sync. Ordinary use reaches this: a pull whose autostash reapply conflicts
	// still exits 0, so nothing upstream of here notices.
	if err := a.refuseConflicts("nothing was committed", a.rerunText()); err != nil {
		return err
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
		// The index, not status: a submodule with its own edits or untracked files
		// shows in status, but add stages nothing for it, and the commit would fail.
		if runOK("git", "diff", "--cached", "--quiet") {
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
	case a.goneUpstream() != "":
		a.out.status("'" + a.goneUpstream() + "' is gone; nothing to pull.")
	default:
		a.out.status("No upstream configured for this branch; nothing to pull.")
	}
	return nil
}

// opFiles are what git keeps in the git dir while an operation is stopped partway,
// in the order pendingOp checks them. The rebase goes first, so a merge or pick it
// stopped on is named as the rebase, which is what has to be finished or dropped.
// The sequencer outlives CHERRY_PICK_HEAD once a pick in a range is committed by
// hand, and its todo says which command it belongs to.
var opFiles = []string{"rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "sequencer", "BISECT_LOG"}

// stoppedOp is a git operation stopped partway: the command that started it, and the
// arguments that finish it and that drop it. A bisect has nothing to finish.
type stoppedOp struct {
	name, finish, drop string
}

// pendingOp names the operation git has stopped partway here, if any. paths line up
// with opFiles.
func pendingOp(paths []string) (stoppedOp, bool) {
	exists := func(p string) bool { _, err := os.Lstat(p); return err == nil }
	for i, p := range paths {
		if i >= len(opFiles) || !exists(p) {
			continue
		}
		switch opFiles[i] {
		case "rebase-apply":
			if exists(filepath.Join(p, "applying")) {
				return stoppedOp{"am", "--continue", "--abort"}, true
			}
			return stoppedOp{"rebase", "--continue", "--abort"}, true
		case "rebase-merge":
			return stoppedOp{"rebase", "--continue", "--abort"}, true
		case "MERGE_HEAD":
			return stoppedOp{"merge", "--continue", "--abort"}, true
		case "CHERRY_PICK_HEAD":
			return stoppedOp{"cherry-pick", "--continue", "--abort"}, true
		case "REVERT_HEAD":
			return stoppedOp{"revert", "--continue", "--abort"}, true
		case "sequencer":
			// No todo to read: take it as a cherry-pick, the usual one.
			todo, _ := os.ReadFile(filepath.Join(p, "todo"))
			if word, _, _ := strings.Cut(strings.TrimSpace(string(todo)), " "); word == "revert" {
				return stoppedOp{"revert", "--continue", "--abort"}, true
			}
			return stoppedOp{"cherry-pick", "--continue", "--abort"}, true
		case "BISECT_LOG":
			return stoppedOp{"bisect", "", "reset"}, true
		}
	}
	return stoppedOp{}, false
}

// refusePendingOp stops a command that commits, pulls, switches or merges while git
// has an operation stopped partway. Run over one, a commit takes the half-done work
// under gitsby's message, and a switch leaves the rest of a range for --continue to
// apply onto the next branch.
func (a *app) refusePendingOp() error {
	// The branch commands, pr and release; repo and account never commit onto history.
	if !a.inRepo || !a.cmd.mutating || !a.needsConfirmableBranch() {
		return nil
	}
	op, found := pendingOp(a.opPaths)
	if !found {
		return nil
	}
	why := "git stopped partway through it. A commit, pull or switch now would take in its half-done work, or leave the rest to land on another branch."
	fix := []string{"Finish it:", "  git " + op.name + " " + op.finish, "Or drop it:", "  git " + op.name + " " + op.drop}
	if op.finish == "" {
		why = "A switch or commit now moves HEAD off what it is testing, and 'git bisect reset' moves it back."
		fix = []string{"End it:", "  git " + op.name + " " + op.drop}
	}
	return refusalBlock("A 'git "+op.name+"' is in progress here.", [][]string{
		noteLines("Why", why),
		noteLines("Fix", append(fix, "Then run this again.")...),
	}, nil)
}

// refuseConflicts stops on any unmerged path, and names the stash git kept.
// stopped says what didn't happen, and rerun is the command to run once they're
// settled.
func (a *app) refuseConflicts(stopped, rerun string) error {
	conflicted := runLines("git", "diff", "--name-only", "--diff-filter=U")
	if len(conflicted) == 0 {
		return nil
	}
	a.out.clean("")
	a.out.status("Unresolved conflicts; " + stopped + ":")
	a.showLines(conflicted)
	if a.opt.staged { // nothing was stashed
		return usagef("Resolve those, then run '%s' again.", rerun)
	}
	return usagef("Resolve those, then run '%s' again. Git also kept your pre-pull tree - see 'git stash list'.", rerun)
}

// pullIfOnline is the pull inside a multi-step command. Same offline rule as
// cmdPull, quietly: --no-fetch and an unreachable remote both mean skip. Extra
// arguments go through to git.
func (a *app) pullIfOnline(extra ...string) error {
	if !a.opt.fetch || a.isOffline() || !a.hasUpstream() {
		return nil
	}
	if err := a.step("git", a.pullArgs(extra...)...); err != nil {
		return err
	}
	// An autostash reapply that conflicts still exits 0. With no commit after it to
	// catch that, br create went on to branch and push over the markers.
	if slices.Contains(extra, "--autostash") {
		return a.refuseConflicts("stopped after the pull", a.rerunText())
	}
	return nil
}

// rerunText is the command to run again once a stop is cleared: the one that was
// typed, with the branch, version or remote it was given, since without that it
// would do something else. --staged stays too, since a rerun without it commits
// the whole tree, edits left out on purpose included. A commit message, a PR title
// and the other options are left off. Every command that parks reaches cmdCommit's
// check, so naming pullcom there sent sync and the rest to a command that doesn't
// push or move.
func (a *app) rerunText() string {
	rerun := meName + " " + typedName(a.cmd)
	switch a.cmd.name {
	case "br-create", "br-hotfix", "br-switch", "release", "repo-create", "repo-connect":
		if a.cmd.arg != "" {
			rerun += " " + typedArg(a.cmd.arg, runtime.GOOS)
		}
	}
	if a.opt.staged {
		rerun += " --staged"
	}
	return rerun
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
		return a.pushCurrent()
	}
	return nil
}

// directPush: sync, or br switch's park push, is about to send your own commits
// straight to main, dev or the default branch. A merge left for sync doesn't count.
// design.md "--direct". br create and br hotfix carry the tree off a protected branch
// instead of pushing it, br merge refuses one, and release exists to push one.
// committed says commits are part of what goes, which need another way off the
// branch than a dirty tree does.
func (a *app) directPush() (push, committed bool) {
	switch a.cmd.name {
	case "sync":
	case "br-switch":
		// Only a move parks, and offline its push is skipped. A dirty protected tree
		// was refused before this.
		if a.currentBranch() == a.switchTarget() || a.isOffline() {
			return false, false
		}
	default:
		return false, false
	}
	if a.opt.direct || !a.hasOrigin() {
		return false, false
	}
	// Judged by where the push lands, not the branch's name: a branch made from
	// origin/main can push there.
	if target, ok := a.pushTarget(); !ok || !a.isProtectedBranch(target) {
		return false, false
	}
	if a.ownCommitsAhead() {
		return true, true
	}
	return a.commitPending(), false
}

// ownCommitsAhead: commits made on this branch that its upstream doesn't have. A
// merge isn't one.
func (a *app) ownCommitsAhead() bool {
	return a.hasUpstream() && runOut("git", "rev-list", "--first-parent", "--no-merges", "-n", "1", "@{u}..HEAD") != ""
}

// treeDirty: whether 'git add --all' has anything to take. A submodule's own edits
// and untracked files show in status but aren't this repo's to commit, so they
// don't count. A submodule moved to another commit still does. Untracked files are
// asked for by name, since status.showUntrackedFiles=no hides them from status but
// not from add.
func treeDirty() bool {
	return runOut("git", "status", "--porcelain", "--ignore-submodules=dirty", "--untracked-files=normal") != ""
}

// stagesTree: this run's commit step stages the whole tree with 'git add --all', the
// way dispatch reaches cmdCommit. br create and br hotfix off a protected branch
// carry the tree along instead, and --staged never stages.
func (a *app) stagesTree() bool {
	if !a.inRepo || a.opt.staged {
		return false
	}
	switch a.cmd.name {
	case "pullcom", "sync", "br-merge", "release", "repo-create", "repo-connect":
		return true
	case "br-switch":
		return a.currentBranch() != a.switchTarget()
	case "br-create", "br-hotfix":
		return !a.isProtectedBranch("")
	case "pr":
		return a.pr.sub == "create"
	}
	return false
}

// refuseSparseAdd: in a sparse checkout, 'git add --all' leaves out files outside
// it. A new one makes it exit 1 after staging the rest, so the run would stop after
// its pull with the index half staged. An edited tracked one is skipped without a
// word, so the run said Done with the edit left out. A dry run of the same add asks
// git itself, before the plan: the new files are in its error, and the skipped
// edits are what 'git diff' has that it doesn't list. git lists the new files
// whatever advice.updateSparsePath says, and LC_ALL=C keeps its words readable.
// Any other failure is left to the real add, since the dry run also fails when
// another git holds the index lock, and then lists nothing.
func (a *app) refuseSparseAdd() error {
	if !a.stagesTree() {
		return nil
	}
	cmd := toolCmd("git", "add", "--all", "--dry-run")
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	var paths []string
	if cmd.Run() != nil {
		if paths = sparseAddPaths(stderr.String()); len(paths) == 0 {
			return nil
		}
	}
	// Outside a sparse checkout add takes every edit, so there is nothing to compare.
	if runOut("git", "config", "--type=bool", "core.sparseCheckout") == "true" {
		paths = append(paths, skippedEdits(changedPaths("--ignore-submodules=dirty"), stdout.String())...)
	}
	if len(paths) == 0 {
		return nil
	}
	slices.Sort(paths)
	return refusalBlock("'git add --all' would leave out files outside the sparse checkout, or stop partway on them. Nothing was done.", [][]string{
		noteLines("File", slices.Compact(paths)...),
		noteLines("Fix", "Take their folders into the checkout with 'git sparse-checkout add <folder>', or move, delete or restore the files. Then run this again.", "Or stage what to commit yourself, and run this with --staged."),
	}, nil)
}

// skippedEdits: the edited tracked paths that a dry run of 'git add --all' doesn't
// list, from its "add 'path'" and "remove 'path'" lines under LC_ALL=C. Both name
// paths from the top of the repo.
func skippedEdits(edited []string, dryRun string) []string {
	taken := map[string]bool{}
	for _, line := range splitLines(dryRun) {
		for _, verb := range []string{"add '", "remove '"} {
			if path, ok := strings.CutPrefix(line, verb); ok && strings.HasSuffix(path, "'") {
				taken[strings.TrimSuffix(path, "'")] = true
			}
		}
	}
	var skipped []string
	for _, path := range edited {
		if !taken[path] {
			skipped = append(skipped, path)
		}
	}
	return skipped
}

// sparseAddPaths reads the paths out of what 'git add' says under LC_ALL=C: a lead
// that ends "updated in the index:", one path per line, then the hints if advice is on.
func sparseAddPaths(stderr string) []string {
	var paths []string
	in := false
	for _, line := range splitLines(stderr) {
		switch {
		case strings.HasSuffix(line, "updated in the index:"):
			in = true
		case !in:
		case line == "" || strings.HasPrefix(line, "hint:") || strings.HasPrefix(line, "warning:") || strings.HasPrefix(line, "error:") || strings.HasPrefix(line, "fatal:"):
			return paths
		default:
			paths = append(paths, line)
		}
	}
	return paths
}

// refuseDirectPush: nobody is there to read the warning, so -q refuses instead.
func (a *app) refuseDirectPush() error {
	if !a.opt.quiet {
		return nil
	}
	if push, committed := a.directPush(); push {
		if !a.isProtectedBranch("") {
			return usagef("%s Nothing was done. Re-run with --direct if that is intended, or publish it under its own name with %s first.", a.directPushText(), a.keepOffText(committed))
		}
		return usagef("%s Nothing was done. Re-run with --direct if that is intended, or move the work to a branch with %s.", a.directPushText(), a.keepOffText(committed))
	}
	return nil
}

// keepOffText is the way to move the work off the protected branch instead. br
// create takes a dirty tree along, but leaves commits behind on the branch, and
// the next push from there is refused again. So commits go with the tree to a new
// branch in git's own step, and the branch goes back to its upstream's tip. A
// branch that isn't protected itself, but tracks one, only has to stop tracking it.
func (a *app) keepOffText(committed bool) string {
	if !a.isProtectedBranch("") {
		return "'git branch --unset-upstream'"
	}
	if !committed {
		return "'" + meName + " br create <branch-name>'"
	}
	return "'git checkout -b <branch-name>', then 'git branch -f " + typedArg(a.currentBranch(), runtime.GOOS) + " " + typedArg(a.upstream().short, runtime.GOOS) + "'"
}

// directPushText names where the push lands, which for a branch tracking another
// one isn't the branch's own name.
func (a *app) directPushText() string {
	return "This pushes your work straight to '" + a.directTarget() + "'. But the recommended workflow is to push to a branch and merge one level higher through a pull request."
}

func (a *app) directTarget() string {
	target, _ := a.pushTarget()
	return target
}

// pushesGoneBranch is the gone upstream that a park push is about to put back,
// most often a branch deleted when its pull request merged. Empty when there's
// none. br merge deletes origin's copy again in the same run, and pr create needs
// the branch on origin, so neither asks.
func (a *app) pushesGoneBranch() string {
	switch a.cmd.name {
	case "br-merge", "pr":
		return ""
	case "release":
		// Parks from whatever branch it starts on, protected or not.
		if !a.hasOrigin() || a.isOffline() {
			return ""
		}
	default:
		if !a.parkPushes() {
			return ""
		}
	}
	return a.goneUpstream()
}

func (a *app) goneBranchText(gone string) string {
	return "'" + gone + "' is gone, most often because its pull request merged and the branch was deleted. This pushes '" + a.currentBranch() + "' back up."
}

// goneBranchLeave is the way off that leaves it gone: plain git to the branch the
// command was headed for, since the command itself would push it. Without its
// upstream setting, the push is an ordinary first publish, which asks nothing.
func (a *app) goneBranchLeave() string {
	target := a.branchTarget("")
	switch a.cmd.name {
	case "br-switch":
		target = a.switchTarget()
	case "br-create":
		target = a.mergeTarget()
	case "br-hotfix":
		target = a.defaultBranch()
	}
	return "'git switch " + typedArg(target, runtime.GOOS) + "'"
}

// refuseGoneBranch: the -q side of the warning above the prompt.
func (a *app) refuseGoneBranch() error {
	if !a.opt.quiet {
		return nil
	}
	if gone := a.pushesGoneBranch(); gone != "" {
		return usagef("%s Nothing was done. To leave it gone, run %s. To publish it again, run 'git branch --unset-upstream' first.", a.goneBranchText(gone), a.goneBranchLeave())
	}
	return nil
}

// pushArgs pushes the current branch and nothing else, named in full, since a bare
// push follows push.default and remote.<name>.push and can send every matching
// branch, or mirror. One with no upstream yet is a first publish: it goes up under
// its own name and tracks origin's copy from then on.
func (a *app) pushArgs() ([]string, error) {
	if !a.hasUpstream() {
		return []string{"push", "-u", "origin", "HEAD"}, nil
	}
	d := a.pushDest()
	if err := d.refusal(); err != nil {
		return nil, err
	}
	if strings.HasPrefix(d.remote, "-") {
		// git takes '--all' as a remote name.
		return []string{"push", "--", d.remote, "HEAD:" + d.ref}, nil
	}
	return []string{"push", d.remote, "HEAD:" + d.ref}, nil
}

// pushCurrent is the push of the branch HEAD is on.
func (a *app) pushCurrent() error {
	args, err := a.pushArgs()
	if err != nil {
		return err
	}
	return a.step("git", args...)
}

// pushDest is where a bare push would send the current branch: the push remote,
// which pushRemote or remote.pushDefault can set apart from the upstream's, and the
// ref that remote's push refspecs map it to. Past those, push.default decides only
// when the upstream on that same remote has another name, as for a branch made from
// origin/main. There simple, git's default, refuses rather than pick one, and
// refused says so. Where git has no one answer, as under push.default=nothing, it's
// the upstream, as for the pull.
type pushDest struct{ branch, remote, ref, refused string }

func (a *app) pushDest() pushDest {
	refs := a.branchRefs()
	branch := refs.head
	if branch == "" {
		branch = a.currentBranch()
	}
	p := refs.push[branch]
	d := pushDest{branch: branch, remote: cmp.Or(p.pushRemote, p.upRemote, "origin")}
	own := "refs/heads/" + branch
	switch {
	case p.pushRef != "":
		d.ref = p.pushRef
	case d.remote != p.upRemote || p.upRef == "" || p.upRef == own:
		// Another remote than the upstream's gets the branch under its own name, as
		// git does it.
		d.ref = own
	default:
		switch runOut("git", "config", "--get", "push.default") {
		case "current", "matching":
			d.ref = own
		case "upstream", "tracking", "nothing":
			d.ref = p.upRef
		default:
			d.refused = "'" + branch + "' tracks '" + a.upstream().short + "', a branch of another name, so under push.default=simple git won't push it."
		}
	}
	return d
}

// pushTarget is the branch a push of the current one lands on, and false where
// git would refuse the push. Without an upstream it's a first publish under its
// own name, which is asked last, since most pushes go there anyway.
func (a *app) pushTarget() (string, bool) {
	d := a.pushDest()
	if d.refused == "" && d.ref == "refs/heads/"+d.branch {
		return d.branch, true
	}
	if !a.hasUpstream() {
		return d.branch, true
	}
	if d.refused != "" {
		return "", false
	}
	return strings.TrimPrefix(d.ref, "refs/heads/"), true
}

// parkHead is the branch on origin the park push sends the current branch to.
// pr create opens its pull request from it, and br merge deletes it once merged.
// A branch can track one of another name, or push to another remote, so the
// current branch's name could be an older branch on origin, or none. Asked
// whether or not anything is left to push, since both need it either way.
func (a *app) parkHead(branch string) (string, error) {
	d := a.pushDest()
	if d.refused == "" && d.remote == "origin" && d.ref == "refs/heads/"+branch {
		return branch, nil
	}
	// Without an upstream the push is a first publish, to origin under its own name.
	if !a.hasUpstream() {
		return branch, nil
	}
	if err := d.refusal(); err != nil {
		return "", err
	}
	unset := "To publish it to origin under its own name, run 'git branch --unset-upstream' first."
	merge := a.cmd.name == "br-merge"
	head, isBranch := strings.CutPrefix(d.ref, "refs/heads/")
	switch {
	case d.remote != "origin" && merge:
		return "", usagef("'%s' pushes to the remote '%s', but br merge deletes the merged branch from origin, which wouldn't have the work. Nothing was done. %s", branch, d.remote, unset)
	case d.remote != "origin":
		return "", usagef("'%s' pushes to the remote '%s', but its pull request opens on origin, which wouldn't have the work. Nothing was done. %s", branch, d.remote, unset)
	case !isBranch && merge:
		return "", usagef("'%s' pushes to '%s' on origin, which isn't a branch br merge can delete once it's merged. Nothing was done.", branch, d.ref)
	case !isBranch:
		return "", usagef("'%s' pushes to '%s' on origin, which isn't a branch a pull request can name. Nothing was done.", branch, d.ref)
	case a.isProtectedBranch(head) && merge:
		return "", usagef("'%s' pushes to '%s', so br merge would delete origin's '%s' once it's merged. Nothing was done. %s", branch, head, head, unset)
	case a.isProtectedBranch(head):
		return "", usagef("'%s' pushes to '%s', so its pull request would propose '%s' itself. Nothing was done. %s", branch, head, head, unset)
	}
	return head, nil
}

// mergeHead is origin's copy of the branch br merge merges, the one its delete
// names. preflight refused where parkHead can't say.
func (a *app) mergeHead() string {
	if !a.hasOrigin() {
		return a.currentBranch()
	}
	head, err := a.parkHead(a.currentBranch())
	if err != nil {
		return a.currentBranch()
	}
	return head
}

// mergePushesOwn is the branch br merge, or pr ok's hotfix back-merge, is about to
// push with commits made on it directly, which sync there would ask about with
// --direct. The merge itself isn't one. Empty when there's none.
func (a *app) mergePushesOwn() string {
	var targets []string
	switch a.cmd.name {
	case "br-merge":
		targets = append(targets, a.branchTarget(""))
		if a.isHotfixBranch("") {
			targets = append(targets, a.mergeTarget()) // the back-merge
		}
	case "pr":
		if a.pr.sub == "ok" && a.isHotfixBranch(a.pr.headBranch) {
			targets = append(targets, a.mergeTarget())
		}
	}
	if len(targets) == 0 || !a.hasOrigin() || a.isOffline() {
		return ""
	}
	for _, target := range targets {
		if a.ownCommitsOn(target) {
			return target
		}
	}
	return ""
}

// ownCommitsOn is ownCommitsAhead for a branch HEAD isn't on. One without an
// upstream is a first publish, which sync doesn't ask about either. The tips come
// from branchRefs, so a branch level with origin's costs no call.
func (a *app) ownCommitsOn(branch string) bool {
	refs := a.branchRefs()
	up := refs.local[branch].full
	if up == "" {
		return false
	}
	if tip := refs.tip["refs/heads/"+branch]; tip != "" && tip == refs.tip[up] {
		return false
	}
	return runOut("git", "rev-list", "--first-parent", "--no-merges", "-n", "1", up+"..refs/heads/"+branch) != ""
}

func (a *app) ownPushText(target string) string {
	return "'" + target + "' has commits of its own that origin doesn't, and this pushes them straight to origin's '" + target + "' with the merge. But the recommended workflow is to push to a branch and merge one level higher through a pull request."
}

// ownPushOff keeps the commits as a branch of their own and puts the target back
// on its upstream, from where the run stands, since the target isn't checked out.
func (a *app) ownPushOff(target string) string {
	return "'git branch <branch-name> " + typedArg(target, runtime.GOOS) + "', then 'git branch -f " + typedArg(target, runtime.GOOS) + " " + typedArg(a.upstreamOf(target).short, runtime.GOOS) + "'"
}

// ownPushOn is the way to send them as meant. --direct stays sync's and br
// switch's, per 2026111910223293.
func (a *app) ownPushOn(target string) string {
	return "'" + meName + " br switch " + typedArg(target, runtime.GOOS) + "', then '" + meName + " sync --direct'"
}

// refuseMergePushesOwn: the -q side of the warning above the prompt.
func (a *app) refuseMergePushesOwn() error {
	if !a.opt.quiet {
		return nil
	}
	if target := a.mergePushesOwn(); target != "" {
		return usagef("%s Nothing was done. To keep them off '%s', move them to a branch with %s. To push them as they are first, run %s.", a.ownPushText(target), target, a.ownPushOff(target), a.ownPushOn(target))
	}
	return nil
}

// refusal: git would refuse the push, so say why before anything else fails on it.
func (d pushDest) refusal() error {
	if d.refused != "" {
		return usagef("%s Nothing was done. To publish it under its own name, run 'git branch --unset-upstream' first.", d.refused)
	}
	return nil
}

// parkPushes: this command's park push sends the current branch, the way the plan
// shows it. br create and br hotfix carry a protected branch's tree off instead.
func (a *app) parkPushes() bool {
	switch a.cmd.name {
	case "sync", "br-merge":
	case "br-switch":
		if a.currentBranch() == a.switchTarget() {
			return false
		}
	case "br-create", "br-hotfix":
		if a.isProtectedBranch("") {
			return false
		}
	case "pr":
		if a.pr.sub != "create" {
			return false
		}
	default:
		return false
	}
	return a.hasOrigin() && !a.isOffline()
}

// refuseParkPush: the park push would be refused by git, or would land on a
// protected branch from one that isn't, which only br switch and sync may do,
// with --direct. Asked only when something would go, since a branch made from
// origin/main and never touched has nothing to push. Before the plan, under -q
// or not, since neither can be answered at the prompt.
func (a *app) refuseParkPush() error {
	if !a.parkPushes() {
		return nil
	}
	target, ok := a.pushTarget()
	toProtected := ok && a.cmd.name != "sync" && a.cmd.name != "br-switch" && a.isProtectedBranch(target)
	if ok && !toProtected {
		return nil
	}
	// With no upstream it's a first publish, under its own name.
	if !a.hasUpstream() || (!isAhead() && !a.commitPending()) {
		return nil
	}
	if !ok {
		return a.pushDest().refusal()
	}
	return usagef("This pushes '%s' straight to '%s', the branch it tracks. Nothing was done. To publish it under its own name, run 'git branch --unset-upstream' first. To push it to '%s', run '%s sync --direct' first.", a.currentBranch(), target, target, meName)
}

// commitPending: whether the command's commit step has anything to take.
func (a *app) commitPending() bool {
	if a.opt.staged {
		return !runOK("git", "diff", "--cached", "--quiet")
	}
	return treeDirty()
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
