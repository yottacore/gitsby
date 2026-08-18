// Repo and branch readers: current/default branch, merge targets, the display
// forms. All read-only - a wrong answer here mislabels a line, never moves a ref.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strconv"
	"strings"
)

// Per-run constants, filled by main post-fetch so origin/HEAD is fresh.
var (
	defaultBranchCache = ""
	mergeTargetCache   = ""
)

func currentBranch() string { return runOut("git", "branch", "--show-current") }
func hasUpstream() bool     { return runOK("git", "rev-parse", "--abbrev-ref", "@{u}") }

// isAhead: -n 1 stops at the first commit - the count doesn't matter here.
func isAhead() bool { return runOut("git", "rev-list", "-n", "1", "@{u}..") != "" }

func branchExistsLocal(branch string) bool {
	return runOK("git", "show-ref", "--verify", "--quiet", "refs/heads/"+branch)
}
func branchExistsRemote(branch string) bool {
	return runOK("git", "show-ref", "--verify", "--quiet", "refs/remotes/origin/"+branch)
}

// branchHasUnpushed asks about a NAMED branch, not HEAD: ahead-ness of a branch
// you aren't standing on can't be asked with '@{u}'.
func branchHasUnpushed(branch string) bool {
	return runOut("git", "rev-list", "-n", "1", "refs/remotes/origin/"+branch+"..refs/heads/"+branch) != ""
}

// isProtectedBranch: main/master/dev - branches WIP should never be
// auto-committed to, or deleted. Empty means the current one.
func isProtectedBranch(branch string) bool {
	if branch == "" {
		branch = currentBranch()
	}
	if branch == defaultBranch() {
		return true
	}
	if branch == "main" || branch == "master" { // a leftover one isn't ours to touch either
		return true
	}
	return branch == "dev" && (branchExistsLocal("dev") || branchExistsRemote("dev"))
}

// isMergedInto: true when ref is already contained in any of the refs given.
func isMergedInto(ref string, into []string) bool {
	for _, target := range into {
		if !runOK("git", "rev-parse", "-q", "--verify", target) {
			continue
		}
		if runOK("git", "merge-base", "--is-ancestor", ref, target) {
			return true
		}
	}
	return false
}

// defaultBranch prefers origin's HEAD; falls back to whichever of main/master
// exists locally. A repo whose default is neither (git init -b trunk,
// init.defaultBranch) and that was never cloned has no origin/HEAD to read, so a
// sole local branch is the honest answer there. Guessing "main" at the end would
// name a branch that doesn't exist - the caller refuses instead.
func defaultBranch() string {
	if defaultBranchCache != "" {
		return defaultBranchCache
	}
	if originHead := runOut("git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"); originHead != "" {
		return strings.TrimPrefix(originHead, "origin/")
	}
	for _, name := range []string{"main", "master", "trunk"} {
		if branchExistsLocal(name) {
			return name
		}
	}
	// Nothing conventional to go on: a lone branch is the default by elimination.
	// A named one has to stay stable as feature branches come and go, which is why
	// the list above is checked first.
	locals := runLines("git", "for-each-ref", "--format=%(refname:short)", "refs/heads")
	if len(locals) == 1 {
		return locals[0]
	}
	// Unborn HEAD: nothing exists yet, so the name it will get is the honest answer.
	if len(locals) == 0 {
		if head := runOut("git", "symbolic-ref", "--quiet", "--short", "HEAD"); head != "" {
			return head
		}
		return "main"
	}
	return ""
}

// mergeTarget: feature branches come off of - and land on - dev when the repo
// has one; else the default branch.
func mergeTarget() string {
	if mergeTargetCache != "" {
		return mergeTargetCache
	}
	if branchExistsLocal("dev") || branchExistsRemote("dev") {
		return "dev"
	}
	return defaultBranch()
}

// isHotfixBranch: a hotfix corrects what is already published, so it targets the
// default branch instead of dev. The 'hotfix/' prefix is the marker: it lives in
// the ref name, so it survives a clone and is visible in a branch listing.
func isHotfixBranch(branch string) bool {
	if branch == "" {
		branch = currentBranch()
	}
	return strings.HasPrefix(branch, "hotfix/")
}

// branchTarget is where THIS branch lands, which is not always where new feature
// branches come from - a hotfix lands on the default branch.
func branchTarget(branch string) string {
	if branch == "" {
		branch = currentBranch()
	}
	if isHotfixBranch(branch) {
		return defaultBranch()
	}
	return mergeTarget()
}

// branchDisp: "base :: branch" for work branches; a bare name for main/master/dev,
// which are off nothing. The base is where the branch LANDS - for anything gitsby
// made that's also where it came from, and git records no fork point to read, so
// the land target is the honest answer either way.
func branchDisp(branch string) string {
	if branch == "" {
		branch = currentBranch()
	}
	if branch == "" {
		return ""
	}
	if isProtectedBranch(branch) {
		return branch
	}
	if base := branchTarget(branch); base != "" {
		return base + " :: " + branch
	}
	return branch
}

// branchSync gives ahead/behind for the branch line; empty when in sync, so a
// quiet line means "nothing pending".
func branchSync() string {
	if !hasUpstream() {
		return "(no upstream)"
	}
	behind, ahead := 0, 0
	if counts := strings.Fields(runOut("git", "rev-list", "--left-right", "--count", "@{u}...HEAD")); len(counts) == 2 {
		behind, _ = strconv.Atoi(counts[0])
		ahead, _ = strconv.Atoi(counts[1])
	}
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

var maskUrlRE = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]+@(.*)$`)

// maskUrl hides userinfo in displayed URLs (https://user:token@host ->
// https://***@host); a credentialed origin would otherwise echo the token on
// every run.
func maskUrl(url string) string {
	if m := maskUrlRE.FindStringSubmatch(url); m != nil {
		return m[1] + "***@" + m[2]
	}
	return url
}
