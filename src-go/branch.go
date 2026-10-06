// Repo and branch readers: current/default branch, merge targets, the display
// forms. All read-only - a wrong answer here mislabels a line, never moves a ref.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"sort"
	"strconv"
	"strings"
)

func (a *app) currentBranch() string {
	return a.git.currentBranch.get(func() string { return runOut("git", "branch", "--show-current") })
}

// upstreamRef is a branch's upstream two ways. The full ref says whose it is; the
// short one is git's own unambiguous name for it, which the plan prints and the
// pull step runs.
type upstreamRef struct{ full, short string }

// upstream is the current branch's upstream, empty when it has none. One call
// for both forms, since rev-parse applies each option to the names after it.
func (a *app) upstream() upstreamRef {
	return a.git.upstream.get(func() upstreamRef {
		lines := runLines("git", "rev-parse", "--symbolic-full-name", "@{u}", "--abbrev-ref", "@{u}")
		if len(lines) != 2 {
			return upstreamRef{}
		}
		return upstreamRef{full: lines[0], short: lines[1]}
	})
}

func (a *app) hasUpstream() bool { return a.upstream().full != "" }

// branchRefs is every local branch with its upstream, and every branch origin
// has with git's short name for it. One for-each-ref answers all of the run's
// existence checks.
type branchRefs struct {
	local  map[string]upstreamRef
	origin map[string]string
}

func (a *app) branchRefs() branchRefs {
	return a.git.branches.get(func() branchRefs {
		refs := branchRefs{local: map[string]upstreamRef{}, origin: map[string]string{}}
		// A ref name can't hold a space, so an empty field still has its place.
		lines := runLines("git", "for-each-ref", "--format=%(refname) %(refname:short) %(upstream) %(upstream:short)", "refs/heads/", "refs/remotes/origin/")
		for _, line := range lines {
			fields := strings.Split(line, " ")
			if len(fields) != 4 {
				continue
			}
			if name, ok := strings.CutPrefix(fields[0], "refs/heads/"); ok {
				refs.local[name] = upstreamRef{full: fields[2], short: fields[3]}
			} else if name, ok := strings.CutPrefix(fields[0], "refs/remotes/origin/"); ok && name != "HEAD" {
				// origin/HEAD is a pointer at the default branch, not a branch. Counted as
				// one, 'br switch HEAD' passed the up-front check and parked work first.
				refs.origin[name] = fields[1]
			}
		}
		return refs
	})
}

func (a *app) branchExistsLocal(branch string) bool {
	_, ok := a.branchRefs().local[branch]
	return ok
}

func (a *app) branchExistsRemote(branch string) bool {
	_, ok := a.branchRefs().origin[branch]
	return ok
}

// localBranchNames in refname order, the order for-each-ref lists them in.
func (a *app) localBranchNames() []string {
	local := a.branchRefs().local
	names := make([]string, 0, len(local))
	for name := range local {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// upstreamOf is upstream for any branch. One with no local copy yet is checked
// out tracking origin's, so that is its upstream.
func (a *app) upstreamOf(branch string) upstreamRef {
	if branch == a.currentBranch() {
		return a.upstream()
	}
	refs := a.branchRefs()
	if up, ok := refs.local[branch]; ok {
		return up
	}
	if short, ok := refs.origin[branch]; ok {
		return upstreamRef{full: "refs/remotes/origin/" + branch, short: short}
	}
	return upstreamRef{}
}

// aheadBehind: both directions against the upstream, in the one call that answers
// for both - the branch line and the incoming list were each asking git separately
// for the same number.
func (a *app) aheadBehind() (ahead, behind int) {
	counts := a.git.aheadBehind.get(func() [2]int {
		fields := strings.Fields(runOut("git", "rev-list", "--left-right", "--count", "@{u}...HEAD"))
		if len(fields) != 2 {
			return [2]int{}
		}
		// rev-list's count format is fixed, so a non-number can only mean a git this
		// code has never met; 0 keeps the status line a status line.
		behind, _ := strconv.Atoi(fields[0])
		ahead, _ := strconv.Atoi(fields[1])
		return [2]int{ahead, behind}
	})
	return counts[0], counts[1]
}

// isAhead: -n 1 stops at the first commit - the count doesn't matter here.
func isAhead() bool { return runOut("git", "rev-list", "-n", "1", "@{u}..") != "" }

// branchHasUnpushed asks about a NAMED branch, not HEAD: ahead-ness of a branch
// you aren't standing on can't be asked with '@{u}'.
func branchHasUnpushed(branch string) bool {
	return runOut("git", "rev-list", "-n", "1", "refs/remotes/origin/"+branch+"..refs/heads/"+branch) != ""
}

// refuseOptionShapedRefs stops a branch whose name starts with a dash before it
// reaches git in the leading argument position of a checkout, a merge or a branch
// delete, where git reads it as flags instead. Not typeable here - the parser
// takes a leading dash as an option of ours - so it can only have arrived from a
// repo we cloned, and 'git checkout' has no separator that would rescue it.
func refuseOptionShapedRefs(names ...string) error {
	for _, name := range names {
		if strings.HasPrefix(name, "-") {
			return usagef("Branch '%s' starts with a dash, so git reads it as an option rather than a name. Rename it with raw git first.", name)
		}
	}
	return nil
}

// checkoutArgs is how a branch actually gets checked out. git's DWIM creates a
// tracking branch from a remote copy only when exactly one remote has it; with two
// it refuses to guess, and the up-front existence check never notices because it
// only ever looks at origin. So name origin, and let the plan say the same thing
// the command will run. By full ref, since a tag named 'origin/<branch>' makes the
// short name ambiguous and git then refuses the checkout.
func (a *app) checkoutArgs(branch string) []string {
	if branch != "" && !a.branchExistsLocal(branch) && a.branchExistsRemote(branch) {
		return []string{"checkout", "-b", branch, "--track", "refs/remotes/origin/" + branch}
	}
	return []string{"checkout", branch}
}

func (a *app) checkoutDisp(branch string) string {
	return "git " + strings.Join(a.checkoutArgs(branch), " ")
}

func (a *app) checkout(branch string) error { return a.step("git", a.checkoutArgs(branch)...) }

// isProtectedBranch: main/master/dev - branches WIP should never be
// auto-committed to, or deleted. Empty means the current one.
func (a *app) isProtectedBranch(branch string) bool {
	if branch == "" {
		branch = a.currentBranch()
	}
	if branch == a.defaultBranch() {
		return true
	}
	if branch == "main" || branch == "master" { // a leftover one isn't ours to touch either
		return true
	}
	return branch == "dev" && (a.branchExistsLocal("dev") || a.branchExistsRemote("dev"))
}

// defaultBranch prefers origin's HEAD; falls back to whichever of main/master
// exists locally. A repo whose default is neither (git init -b trunk,
// init.defaultBranch) and that was never cloned has no origin/HEAD to read, so a
// sole local branch is the honest answer there. Guessing "main" at the end would
// name a branch that doesn't exist - the caller refuses instead.
func (a *app) defaultBranch() string {
	return a.git.defaultBranch.get(a.resolveDefaultBranch)
}

// originHead is origin/HEAD's target as a full ref, "" when there is none. The
// fetch reads it to decide whether to heal it, and the default branch comes from
// the same answer. Never --short: git lengthens that to 'remotes/origin/main'
// when a tag is named 'origin/main'.
func (a *app) originHead() string {
	return a.git.originHead.get(func() string {
		return runOut("git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
	})
}

func (a *app) resolveDefaultBranch() string {
	if branch, ok := strings.CutPrefix(a.originHead(), "refs/remotes/origin/"); ok && branch != "" {
		return branch
	}
	for _, name := range []string{"main", "master", "trunk"} {
		if a.branchExistsLocal(name) {
			return name
		}
	}
	// Nothing conventional to go on: a lone branch is the default by elimination.
	// A named one has to stay stable as feature branches come and go, which is why
	// the list above is checked first.
	locals := a.localBranchNames()
	if len(locals) == 1 {
		return locals[0]
	}
	// Unborn HEAD: nothing exists yet, so the name it will get is the honest answer.
	if len(locals) == 0 {
		if head, ok := strings.CutPrefix(runOut("git", "symbolic-ref", "--quiet", "HEAD"), "refs/heads/"); ok && head != "" {
			return head
		}
		return "main"
	}
	return ""
}

// mergeTarget: feature branches come off of - and land on - dev when the repo
// has one; else the default branch.
func (a *app) mergeTarget() string {
	return a.git.mergeTarget.get(func() string {
		if a.branchExistsLocal("dev") || a.branchExistsRemote("dev") {
			return "dev"
		}
		return a.defaultBranch()
	})
}

// isHotfixBranch: a hotfix corrects what is already published, so it targets the
// default branch instead of dev. The 'hotfix/' prefix is the marker: it lives in
// the ref name, so it survives a clone and is visible in a branch listing.
func (a *app) isHotfixBranch(branch string) bool {
	if branch == "" {
		branch = a.currentBranch()
	}
	return strings.HasPrefix(branch, "hotfix/")
}

// branchTarget is where THIS branch lands, which is not always where new feature
// branches come from - a hotfix lands on the default branch.
func (a *app) branchTarget(branch string) string {
	if branch == "" {
		branch = a.currentBranch()
	}
	if a.isHotfixBranch(branch) {
		return a.defaultBranch()
	}
	return a.mergeTarget()
}

// branchDisp: "base :: branch" for work branches; a bare name for main/master/dev,
// which are off nothing. The base is where the branch LANDS - for anything gitsby
// made that's also where it came from, and git records no fork point to read, so
// the land target is the honest answer either way.
func (a *app) branchDisp(branch string) string {
	if branch == "" {
		branch = a.currentBranch()
	}
	if branch == "" {
		return ""
	}
	if a.isProtectedBranch(branch) {
		return branch
	}
	if base := a.branchTarget(branch); base != "" {
		return base + " :: " + branch
	}
	return branch
}

// branchSync gives ahead/behind for the branch line; empty when in sync, so a
// quiet line means "nothing pending".
func (a *app) branchSync() string {
	if !a.hasUpstream() {
		return "(no upstream)"
	}
	ahead, behind := a.aheadBehind()
	out := ""
	if ahead > 0 {
		out = "ahead " + strconv.Itoa(ahead)
	}
	if behind > 0 {
		if out != "" {
			out += ", "
		}
		out += "behind " + strconv.Itoa(behind)
	}
	if out != "" {
		return "[" + out + "]"
	}
	return ""
}

// commitIdentity: what actually gets stamped on commits (config or GIT_AUTHOR_*) -
// and shown to everyone on the remote.
func commitIdentity() string {
	ident := runOut("git", "var", "GIT_AUTHOR_IDENT")
	// Drop the trailing "timestamp timezone".
	if i := strings.LastIndex(ident, " "); i >= 0 {
		if j := strings.LastIndex(ident[:i], " "); j >= 0 {
			ident = ident[:j]
		}
	}
	if ident == "" {
		return "(unset)"
	}
	return ident
}

var maskURLRE = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]+@(.*)$`)

// maskURL hides userinfo in displayed URLs (https://user:token@host ->
// https://***@host); a credentialed origin would otherwise echo the token on
// every run.
func maskURL(url string) string {
	if m := maskURLRE.FindStringSubmatch(url); m != nil {
		return m[1] + "***@" + m[2]
	}
	return url
}
