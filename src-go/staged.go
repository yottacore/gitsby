// --staged: commit what is staged, and leave everything else where it is. Gitsby
// still stages nothing itself; the flag only stops 'git add --all' undoing a
// 'git add' that was already made. Nothing is stashed around a pull either, since
// git's autostash puts staged work back unstaged. So where git would refuse a
// step over the edits left in the tree, the run is refused before its plan.
// design.md, "--staged".

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"strconv"
	"strings"
)

// checkStagedFlag refuses --staged where the command would commit everything
// anyway. Ignoring it there would sweep in the very edits it was typed to keep out.
func checkStagedFlag(name string, opt options) error {
	if !opt.staged {
		return nil
	}
	switch name {
	case "pullcom", "sync", "br-create", "br-hotfix", "br-switch", "br-merge":
		return nil
	}
	return usagef("--staged works with pullcom, sync, br create, br hotfix, br switch and br merge.")
}

// treeSplit is the working tree as --staged sees it, with paths from the top of
// the repo. A file staged and then edited again is in both lists.
type treeSplit struct {
	staged []string // goes into the commit
	left   []string // stays in the tree: unstaged edits and untracked files
}

// parseStatusZ reads 'git status --porcelain -z --no-renames'. Without renames
// every record is two status letters, a space and one path.
func parseStatusZ(out string) treeSplit {
	var split treeSplit
	for _, rec := range strings.Split(out, "\x00") {
		if len(rec) < 4 || rec[2] != ' ' {
			continue
		}
		x, y, path := rec[0], rec[1], rec[3:]
		switch x {
		case '?':
			split.left = append(split.left, path)
		case '!':
		default:
			if x != ' ' {
				split.staged = append(split.staged, path)
			}
			if y != ' ' {
				split.left = append(split.left, path)
			}
		}
	}
	return split
}

// Every untracked file, not just its folder: a checkout or pull is refused over
// one file, and the plan lists them the same way.
func readTreeSplit() treeSplit {
	return parseStatusZ(runOut("git", "status", "--porcelain", "-z", "--no-renames", "--untracked-files=all"))
}

func pathSet(lists ...[]string) map[string]bool {
	set := map[string]bool{}
	for _, list := range lists {
		for _, path := range list {
			set[path] = true
		}
	}
	return set
}

// changedPaths is 'git diff --name-only' over args, with paths from the top.
func changedPaths(args ...string) []string {
	out := runOut("git", append([]string{"diff", "--name-only", "-z", "--no-renames"}, args...)...)
	var paths []string
	for _, path := range strings.Split(out, "\x00") {
		if path != "" {
			paths = append(paths, path)
		}
	}
	return paths
}

func pathsIn(paths []string, set map[string]bool) []string {
	var hit []string
	for _, path := range paths {
		if set[path] {
			hit = append(hit, path)
		}
	}
	return hit
}

// autostash is the pull's stash flag. Under --staged there is none: git reapplies
// its autostash without --index, so whatever was staged would come back unstaged
// and the commit after the pull would take nothing.
func (a *app) autostash() []string {
	if a.opt.staged {
		return nil
	}
	return []string{"--autostash"}
}

// stagedPreflight walks the steps of the command, in order, and refuses where git
// would stop on the edits --staged leaves in the tree. Up front, because the
// checkouts come after the commit and the push.
func (a *app) stagedPreflight() error {
	if !a.opt.staged {
		return nil
	}
	split := readTreeSplit()
	a.split = &split
	all, left := pathSet(split.staged, split.left), pathSet(split.left)
	current := a.currentBranch()
	switch a.cmd.name {
	case "pullcom", "sync":
		return a.stagedPullCheck(current, all)
	case "br-create", "br-hotfix":
		base := a.mergeTarget()
		if a.cmd.name == "br-hotfix" {
			base = a.defaultBranch()
		}
		if !a.isProtectedBranch("") {
			return a.stagedMoveCheck(base, all, left)
		}
		// Nothing is committed here, so all of it rides along, the staged part too.
		if current != base {
			if err := a.stagedCheckoutCheck(base, all, false); err != nil {
				return err
			}
		}
		return a.stagedPullCheck(base, all)
	case "br-switch":
		target := a.cmd.arg
		if target == "" {
			target = a.mergeTarget()
		}
		if current == target {
			return nil
		}
		return a.stagedMoveCheck(target, all, left)
	case "br-merge":
		if err := a.stagedMoveCheck(a.branchTarget(current), all, left); err != nil {
			return err
		}
		// The back-merge checks dev out too. What main holds by then is read as
		// the index, which is right unless the merge itself touches one of these.
		dev := a.mergeTarget()
		if a.isHotfixBranch("") && dev != a.defaultBranch() && (a.branchExistsLocal(dev) || a.branchExistsRemote(dev)) {
			if err := a.stagedCheckoutCheck(dev, left, true); err != nil {
				return err
			}
			return a.stagedPullCheck(dev, left)
		}
	}
	return nil
}

// stagedMoveCheck is the park and move every branch command shares: pull, commit
// the staged part, check the target out, and pull it.
func (a *app) stagedMoveCheck(target string, all, left map[string]bool) error {
	if err := a.stagedPullCheck(a.currentBranch(), all); err != nil {
		return err
	}
	if err := a.stagedCheckoutCheck(target, left, true); err != nil {
		return err
	}
	return a.stagedPullCheck(target, left)
}

// stagedPullCheck: a fast-forward with no stash is refused when it would change a
// file that has edits here. Only the merge of a fetched upstream can be read
// ahead; a pull from another remote is git's to refuse.
func (a *app) stagedPullCheck(branch string, dirty map[string]bool) error {
	if len(dirty) == 0 || !a.opt.fetch || a.isOffline() {
		return nil
	}
	up := a.upstreamOf(branch)
	if !strings.HasPrefix(up.full, "refs/remotes/origin/") && !strings.HasPrefix(up.full, "refs/heads/") {
		return nil
	}
	from := "HEAD"
	if branch != a.currentBranch() {
		// One with no local copy yet is checked out at origin's tip, so it has
		// nothing to pull.
		if !a.branchExistsLocal(branch) {
			return nil
		}
		from = "refs/heads/" + branch
	}
	hit := pathsIn(changedPaths(from+"..."+up.full), dirty)
	if len(hit) == 0 {
		return nil
	}
	pull := "git " + strings.Join(pullArgsFor(up), " ")
	return stagedRefusal(pull, "Those files changed on '"+up.short+"', and they have edits here. With --staged nothing is stashed around the pull, since git's stash puts staged work back unstaged:", hit,
		"Commit or stash those files with raw git, then run this again.")
}

// stagedCheckoutCheck: git refuses a checkout that would overwrite a file with
// edits. fromIndex reads the branch being left as the commit of the index, which
// is what it is once the staged part is committed. Otherwise it is HEAD, and the
// staged part rides along, as br create from main or dev carries it.
func (a *app) stagedCheckoutCheck(target string, dirty map[string]bool, fromIndex bool) error {
	if len(dirty) == 0 {
		return nil
	}
	ref := "refs/heads/" + target
	if !a.branchExistsLocal(target) {
		if !a.branchExistsRemote(target) {
			return nil
		}
		ref = "refs/remotes/origin/" + target
	}
	var changed []string
	if fromIndex {
		changed = changedPaths("--cached", ref)
	} else {
		changed = changedPaths("HEAD", ref)
	}
	hit := pathsIn(changed, dirty)
	if len(hit) == 0 {
		return nil
	}
	fix := "Commit or stash those files with raw git, then run this again."
	if fromIndex {
		fix = "Stage them too, so they are committed, or commit or stash them with raw git. Then run this again."
	}
	return stagedRefusal(a.checkoutDisp(target), "Those files are different on '"+target+"', and they have edits that --staged leaves in the tree:", hit, fix)
}

func stagedRefusal(step, why string, files []string, fix string) error {
	const most = 10
	whyLines := []string{why}
	for i, path := range files {
		if i == most {
			whyLines = append(whyLines, "  ... and "+strconv.Itoa(len(files)-most)+" more")
			break
		}
		whyLines = append(whyLines, "  "+path)
	}
	return refusalBlock("'"+step+"' would overwrite edits here, so git would refuse it.", [][]string{
		noteLines("Why", whyLines...),
		noteLines("Kept", "Nothing was done."),
		noteLines("Fix", fix),
	}, nil)
}

// previewSplit lists, under the commit step, what goes in and what stays.
func (a *app) previewSplit() {
	if a.split == nil {
		split := readTreeSplit()
		a.split = &split
	}
	if len(a.split.staged) == 0 {
		a.out.clean(pad + "  nothing is staged, so nothing is committed")
	} else {
		a.out.clean(pad + "  staged, so committed:")
		a.showLinesAt(pad+"    ", a.split.staged)
	}
	if len(a.split.left) > 0 {
		a.out.clean(pad + "  not staged, so left as is:")
		a.showLinesAt(pad+"    ", a.split.left)
	}
}
