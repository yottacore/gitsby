// Repo and branch readers: current/default branch, merge targets, the display
// forms. All read-only - a wrong answer here mislabels a line, never moves a ref.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"runtime"
	"slices"
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

// goneUpstream is the current branch's upstream on a remote when it's still set
// but its ref is gone, as once a fetch prunes a branch origin deleted. rev-parse
// reads that as no upstream at all, so the next push is a first publish that puts
// the branch back. for-each-ref still names it.
func (a *app) goneUpstream() string {
	if a.hasUpstream() {
		return ""
	}
	if up := a.branchRefs().local[a.currentBranch()]; strings.HasPrefix(up.full, "refs/remotes/") {
		return up.short
	}
	return ""
}

// branchRefs is every local branch with its upstream, and every branch origin
// has with git's short name for it. One for-each-ref answers all of the run's
// existence checks, and where each local branch's push and upstream go.
type branchRefs struct {
	local  map[string]upstreamRef
	origin map[string]string
	push   map[string]pushRefs
	head   string            // the branch checked out, so a push needs no second call to name it
	held   map[string]string // a branch checked out in another worktree, to that worktree's path
	tip    map[string]string // each ref, by its full name, to its commit
}

// pushRefs is what git reads to place a branch's push: the push remote and the
// ref its push refspecs map the branch to, and the upstream's remote and ref.
type pushRefs struct{ pushRemote, pushRef, upRemote, upRef string }

func (a *app) branchRefs() branchRefs {
	return a.git.branches.get(func() branchRefs {
		refs := branchRefs{local: map[string]upstreamRef{}, origin: map[string]string{}, push: map[string]pushRefs{}, held: map[string]string{}, tip: map[string]string{}}
		// NUL apart, since a remote can be a URL, which may hold a space. An empty
		// field still has its place.
		lines := runLines("git", "for-each-ref", "--format=%(refname)%00%(refname:short)%00%(upstream)%00%(upstream:short)%00%(push:remotename)%00%(push:remoteref)%00%(upstream:remotename)%00%(upstream:remoteref)%00%(HEAD)%00%(worktreepath)%00%(objectname)", "refs/heads/", "refs/remotes/origin/")
		for _, line := range lines {
			fields := strings.Split(line, "\x00")
			if len(fields) != 11 {
				continue
			}
			refs.tip[fields[0]] = fields[10]
			if name, ok := strings.CutPrefix(fields[0], "refs/heads/"); ok {
				refs.local[name] = upstreamRef{full: fields[2], short: fields[3]}
				refs.push[name] = pushRefs{pushRemote: fields[4], pushRef: fields[5], upRemote: fields[6], upRef: fields[7]}
				if fields[8] == "*" {
					refs.head = name
				} else if fields[9] != "" {
					refs.held[name] = fields[9]
				}
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

// fetchSees: whether origin's fetch refspecs bring its branch into
// refs/remotes/origin, so that no origin/<branch> here means origin has none. A
// single-branch or shallow clone fetches only the one branch. Read only once some
// branch a run needs is missing from origin's refs here.
func (a *app) fetchSees(branch string) bool {
	seen := false
	for _, spec := range a.originFetch() {
		if neg, ok := strings.CutPrefix(spec, "^"); ok {
			if _, ok := refspecMap(neg, neg, "refs/heads/"+branch); ok {
				return false
			}
			continue
		}
		src, dst, ok := strings.Cut(strings.TrimPrefix(spec, "+"), ":")
		if !ok {
			continue
		}
		if to, ok := refspecMap(src, dst, "refs/heads/"+branch); ok && to == "refs/remotes/origin/"+branch {
			seen = true
		}
	}
	return seen
}

// fetchSeesAll: origin's fetch brings in every branch it has, a negative refspec
// aside, which fetchSees answers for by name.
func (a *app) fetchSeesAll() bool {
	for _, spec := range a.originFetch() {
		if strings.TrimPrefix(spec, "+") == "refs/heads/*:refs/remotes/origin/*" {
			return true
		}
	}
	return false
}

func (a *app) originFetch() []string {
	return a.git.originFetch.get(func() []string { return runLines("git", "config", "--get-all", "remote.origin.fetch") })
}

// refspecMap is where one side of a refspec maps ref to, git's way: a '*' on each
// side stands for the same text, slashes included, and a source without one
// names a single ref, in full or by its branch name.
func refspecMap(src, dst, ref string) (string, bool) {
	before, after, glob := strings.Cut(src, "*")
	if !glob {
		if src == ref || "refs/heads/"+src == ref {
			return dst, true
		}
		return "", false
	}
	if len(ref) < len(before)+len(after) || !strings.HasPrefix(ref, before) || !strings.HasSuffix(ref, after) {
		return "", false
	}
	return strings.Replace(dst, "*", ref[len(before):len(ref)-len(after)], 1), true
}

// refuseNarrowFetch: with only some of origin's branches fetched, a missing
// origin/dev doesn't mean origin has none, and the branch commands would take the
// default branch for the merge target. A new branch the fetch doesn't cover
// would read as gone after its first push. So these refuse rather than guess.
// sync and pullcom only push the branch they're on, and run as before.
func (a *app) refuseNarrowFetch() error {
	switch a.cmd.name {
	case "br-create", "br-hotfix", "br-switch", "br-merge", "br-prune", "release":
	case "pr":
		if a.pr.sub == "" {
			return nil
		}
	default:
		return nil
	}
	if !a.hasOrigin() {
		return nil
	}
	switch {
	case !a.branchExistsLocal("dev") && !a.branchExistsRemote("dev") && !a.fetchSees("dev"):
		return narrowFetchRefusal("whether origin has a 'dev'")
	case a.originHead() == "" && !slices.Contains(defaultNames, a.defaultBranch()) && !a.fetchSeesAll():
		// The default branch was then the only local one, which in a clone of dev
		// alone is dev.
		return narrowFetchRefusal("which branch is origin's default")
	}
	return nil
}

func narrowFetchRefusal(what string) error {
	return refusalBlock("This clone fetches only some of origin's branches, so it can't tell "+what+". Nothing was done.", [][]string{
		noteLines("Fix", "Fetch all of them first:", "  git remote set-branches origin "+typedArg("*", runtime.GOOS), "  git fetch origin"),
	}, nil)
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

// refuseOptionShapedRefs stops a branch named with a leading dash, which comes from a
// clone or raw git, before git reads it as flags where there's no separator.
func refuseOptionShapedRefs(names ...string) error {
	for _, name := range names {
		if strings.HasPrefix(name, "-") {
			return usagef("Branch '%s' starts with a dash, so git reads it as an option rather than a name. Rename it with raw git first.", name)
		}
	}
	return nil
}

// checkoutArgs names origin by full ref, since git's DWIM refuses with 2 remotes holding
// the branch, and a tag named 'origin/<branch>' makes the short name ambiguous.
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

// defaultBranch prefers origin's HEAD, then main or master, then a sole local branch.
// Nothing past that, so the caller refuses rather than guessing.
func (a *app) defaultBranch() string {
	return a.git.defaultBranch.get(a.resolveDefaultBranch)
}

// defaultBranchDisp is the default branch for a listing, or why there isn't one.
func (a *app) defaultBranchDisp() string {
	if dflt := a.defaultBranch(); dflt != "" {
		return dflt
	}
	return "(unknown - no origin/HEAD, no main, master, or trunk, and more than one local branch)"
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

// defaultNames are taken for the default branch, in this order, when origin
// doesn't say.
var defaultNames = []string{"main", "master", "trunk"}

func (a *app) resolveDefaultBranch() string {
	if branch, ok := strings.CutPrefix(a.originHead(), "refs/remotes/origin/"); ok && branch != "" {
		return branch
	}
	for _, name := range defaultNames {
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
	// Unborn HEAD: nothing exists yet, so the name it will get is the true answer.
	if len(locals) == 0 {
		if head, ok := strings.CutPrefix(runOut("git", "symbolic-ref", "--quiet", "HEAD"), "refs/heads/"); ok && head != "" {
			return head
		}
		return "main"
	}
	return ""
}

// switchTarget is where br switch goes: the branch named, or the merge target.
func (a *app) switchTarget() string {
	if a.cmd.arg != "" {
		return a.cmd.arg
	}
	return a.mergeTarget()
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

// branchTarget is where THIS branch merges into, which is not always where new feature
// branches come from - a hotfix merges into the default branch.
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
// which are off nothing. The base is where the branch MERGES - for anything gitsby
// made that's also where it came from, and git records no fork point to read, so
// the merge target is the true answer either way.
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
		if gone := a.goneUpstream(); gone != "" {
			return "(" + gone + " gone)"
		}
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

// (?s), since a value read back from .git/config can hold a newline, and a '.'
// that stops there leaves the whole URL unmatched, token and all. The userinfo
// runs to the last '@' before the path, since a password can hold one.
var maskURLRE = regexp.MustCompile(`(?s)^([A-Za-z][A-Za-z0-9+.-]*://)[^/]+@(.*)$`)

// maskURL hides userinfo in displayed URLs (https://user:token@host ->
// https://***@host); a credentialed origin would otherwise echo the token on
// every run.
func maskURL(url string) string {
	if m := maskURLRE.FindStringSubmatch(url); m != nil {
		return m[1] + "***@" + m[2]
	}
	return url
}
