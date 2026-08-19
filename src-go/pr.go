// pr's argument shape, the read-only views, and the two writers. What a PR lands
// on - and whether it is a hotfix - are properties of the PR, not of the branch
// you happen to be standing on, so 'pr ok' asks gh rather than reading HEAD.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"strings"
)

// prRequest is which pull request this run is about, settled before any plan is
// shown.
type prRequest struct {
	sub        string // "create" or "ok"; empty for the bare list and the numeric view
	num        string
	title      string
	headBranch string
}

var prNumRE = regexp.MustCompile(`^[0-9]+$`)

// sortPr validates pr's own arguments - before the repo gate, same as the
// scripts: a malformed pr call is wrong anywhere, in a repo or not.
func (a *app) sortPr() error {
	if err := mustBeInPath("gh"); err != nil {
		return err
	}
	switch strings.ToLower(a.cmd.arg) {
	case "ok":
		a.pr.sub, a.pr.num = "ok", a.cmd.arg2
		if !prNumRE.MatchString(a.pr.num) {
			return usagef("Syntax: %s pr ok <number>", meName)
		}
	case "create", "new":
		a.pr.sub = "create"
		a.pr.title = a.opt.message // -m wins, same as everywhere else
		if a.pr.title == "" {
			a.pr.title = a.cmd.arg2
		}
	case "":
	default:
		a.pr.num = a.cmd.arg
		if !prNumRE.MatchString(a.pr.num) {
			return usagef("Syntax: %s pr [create [title] | <number> | ok <number>]", meName)
		}
	}
	return nil
}

// prPreflight is everything the writers need settled before a plan is shown, so
// nothing can fail after it was confirmed.
func (a *app) prPreflight() error {
	prBranch := a.currentBranch()
	if prBranch == "" {
		return usagef("Detached HEAD (no current branch); resolve that manually first.")
	}
	if a.pr.sub == "ok" {
		return a.prAcceptPreflight(prBranch)
	}
	if prBranch == a.mergeTarget() || prBranch == a.defaultBranch() {
		return usagef("'%s' is what pull requests merge into; there is nothing to propose. Start a branch first: %s br create <name>", prBranch, meName)
	}
	// No title given: the last commit subject is what the work is called already.
	if a.pr.title == "" {
		a.pr.title = runOut("git", "log", "-1", "--pretty=%s")
	}
	if a.pr.title == "" {
		return usagef("No commits on '%s' yet; nothing to propose.", prBranch)
	}
	// An open PR for this branch already is the answer to 'pr create' - say so
	// instead of letting gh error.
	if existing := runOut("gh", "pr", "list", "--head", prBranch, "--state", "open", "--json", "number", "--jq", ".[0].number // empty"); existing != "" {
		return usagef("PR #%s is already open for '%s'. View it: %s pr %s", existing, prBranch, meName, existing)
	}
	return nil
}

// prAcceptPreflight is 'pr ok <n>', which can be run from anywhere: ask gh which
// branch the PR proposes and whether it is still open. A gh that cannot answer
// used to fall back to the current branch, which made the plan confidently about
// the wrong thing and killed the run after it was confirmed - the exact shape
// preflight exists to prevent.
func (a *app) prAcceptPreflight(prBranch string) error {
	info, ok := runOutOK("gh", "pr", "view", a.pr.num, "--json", "headRefName,state", "--jq", ".headRefName, .state")
	fields := strings.Split(info, "\n")
	if !ok || len(fields) != 2 || fields[0] == "" {
		return usagef("Can't read PR #%s; check the number, and that gh can see this repo.", a.pr.num)
	}
	a.pr.headBranch = fields[0]
	if fields[1] != "OPEN" {
		return usagef("PR #%s is %s, not open; there is nothing to accept.", a.pr.num, strings.ToLower(fields[1]))
	}
	if err := refuseOptionShapedRefs(a.pr.headBranch); err != nil {
		return err
	}
	// gh merges what origin already has, then deletes the branch local and remote.
	// Work that never reached origin is outside the PR and outside the merge -
	// refuse, don't lose it.
	if runOut("git", "status", "--porcelain") != "" || isAhead() {
		if prBranch == a.pr.headBranch {
			return usagef("'%s' has changes that aren't on origin, so PR #%s can't include them. Run '%s sync' first.", prBranch, a.pr.num, meName)
		}
		return usagef("'%s' has changes that aren't on origin. Park them first: %s sync", prBranch, meName)
	}
	// Asked of the PR's own branch by name, wherever we are standing: gh deletes it
	// with 'branch -D' either way, and '@{u}' above answers nothing at all for a
	// branch that was pushed without -u - so standing on that one, the guard passed
	// and the commits went with the branch.
	if branchExistsLocal(a.pr.headBranch) {
		if !branchExistsRemote(a.pr.headBranch) {
			return usagef("'%s' is here but not on origin, so PR #%s holds none of it - and it would be deleted. Push it first: git push -u origin %s", a.pr.headBranch, a.pr.num, a.pr.headBranch)
		}
		if branchHasUnpushed(a.pr.headBranch) {
			return usagef("'%s' has commits that never reached origin, so PR #%s can't include them - and it would be deleted. Push them first: git push origin %s", a.pr.headBranch, a.pr.num, a.pr.headBranch)
		}
	}
	return nil
}

// cmdPrView: bare lists open PRs; a number views one plus its diff.
func (a *app) cmdPrView() error {
	if a.pr.num == "" {
		return a.step("gh", "pr", "list")
	}
	if err := a.step("gh", "pr", "view", a.pr.num); err != nil {
		return err
	}
	return a.step("gh", "pr", "diff", a.pr.num)
}

func (a *app) cmdPrCreate() error {
	// GitHub can only diff what origin has, so park the work first - same as br merge
	// and release do.
	if err := a.cmdPush(); err != nil {
		return err
	}
	// Announced by hand rather than through step, like 'gh pr review' below: step
	// would print --head and --body too, which the preview doesn't, so the two lines
	// would disagree.
	base := a.branchTarget("")
	return a.stepAs("gh pr create --base "+base+" --title \""+a.pr.title+"\"", "gh pr create",
		"gh", "pr", "create", "--base", base, "--head", a.currentBranch(), "--title", a.pr.title, "--body", "")
}

func (a *app) cmdPrAccept() error {
	// Resolve both before gh deletes the branch out from under us, and off the PR's
	// own head branch (resolved up front) rather than the current one - they need not
	// be the same.
	targetBranch := a.branchTarget(a.pr.headBranch)
	wasHotfixPr := a.isHotfixBranch(a.pr.headBranch)
	a.out.clean("")
	a.out.status("gh pr review " + a.pr.num + " --approve ...")
	// Best-effort: gh refuses to approve your own PR; merging is the part that matters.
	if !a.inheritOK("gh", "pr", "review", a.pr.num, "--approve") {
		a.out.status("Could not approve (own PR?); merging anyway.")
	}
	a.out.resetBlank()
	if err := a.step("gh", "pr", "merge", a.pr.num, "--merge", "--delete-branch"); err != nil {
		return err
	}
	// gh deletes the PR's branch on the remote but leaves our origin/* copy behind,
	// so an upstream still looks present. Prune first; if ours is the branch that
	// just went away, pulling it can only fail - land on the merge target instead.
	a.fetchRemote()
	if !a.hasUpstream() {
		if err := a.checkout(targetBranch); err != nil {
			return err
		}
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	// Same rule as merge: a hotfix that reached the default branch still owes dev a
	// merge.
	if wasHotfixPr {
		return a.backMergeToDev()
	}
	return nil
}
