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

var (
	prSub        = "" // "create" or "ok"; empty for the bare list and the numeric view
	prNum        = ""
	prTitle      = ""
	prHeadBranch = ""
)

var prNumRE = regexp.MustCompile(`^[0-9]+$`)

// sortPr validates pr's own arguments - before the repo gate, same as the
// scripts: a malformed pr call is wrong anywhere, in a repo or not.
func sortPr() {
	mustBeInPath("gh")
	switch strings.ToLower(cmdArg) {
	case "ok":
		prSub = "ok"
		prNum = cmdArg2
		if !prNumRE.MatchString(prNum) {
			throwUsage("Syntax: " + meName + " pr ok <number>")
		}
	case "create", "new":
		prSub = "create"
		prTitle = commitMessage // -m wins, same as everywhere else
		if prTitle == "" {
			prTitle = cmdArg2
		}
	case "":
	default:
		prNum = cmdArg
		if !prNumRE.MatchString(prNum) {
			throwUsage("Syntax: " + meName + " pr [create [title] | <number> | ok <number>]")
		}
	}
}

// prPreflight is everything the writers need settled before a plan is shown, so
// nothing can fail after it was confirmed.
func prPreflight() {
	prBranch := currentBranch()
	if prBranch == "" {
		throwUsage("Detached HEAD (no current branch); resolve that manually first.")
	}
	if prSub == "ok" {
		// 'pr ok <n>' can be run from anywhere, so ask gh which branch the PR
		// proposes. Fall back to the current one if gh can't say.
		prHeadBranch = runOut("gh", "pr", "view", prNum, "--json", "headRefName", "--jq", ".headRefName")
		if prHeadBranch == "" {
			prHeadBranch = prBranch
		}
		// gh merges what origin already has, then deletes the branch local and remote.
		// Work that never reached origin is outside the PR and outside the merge -
		// refuse, don't lose it.
		if runOut("git", "status", "--porcelain") != "" || isAhead() {
			if prBranch == prHeadBranch {
				throwUsage("'" + prBranch + "' has changes that aren't on origin, so PR #" + prNum + " can't include them. Run '" + meName + " sync' first.")
			}
			throwUsage("'" + prBranch + "' has changes that aren't on origin. Park them first: " + meName + " sync")
		}
		// Standing somewhere else doesn't make the PR's own branch safe: gh deletes it
		// with 'branch -D', so unpushed commits on it go too, and 'sync' can't reach it
		// from here.
		if prBranch != prHeadBranch && branchExistsLocal(prHeadBranch) {
			if !branchExistsRemote(prHeadBranch) {
				throwUsage("'" + prHeadBranch + "' is here but not on origin, so PR #" + prNum + " holds none of it - and it would be deleted. Push it first: git push -u origin " + prHeadBranch)
			}
			if branchHasUnpushed(prHeadBranch) {
				throwUsage("'" + prHeadBranch + "' has commits that never reached origin, so PR #" + prNum + " can't include them - and it would be deleted. Push them first: git push origin " + prHeadBranch)
			}
		}
		return
	}
	if prBranch == mergeTarget() || prBranch == defaultBranch() {
		throwUsage("'" + prBranch + "' is what pull requests merge into; there is nothing to propose. Start a branch first: " + meName + " br create <name>")
	}
	// No title given: the last commit subject is what the work is called already.
	if prTitle == "" {
		prTitle = runOut("git", "log", "-1", "--pretty=%s")
	}
	if prTitle == "" {
		throwUsage("No commits on '" + prBranch + "' yet; nothing to propose.")
	}
	// An open PR for this branch already is the answer to 'pr create' - say so
	// instead of letting gh error.
	if existingPr := runOut("gh", "pr", "list", "--head", prBranch, "--state", "open", "--json", "number", "--jq", ".[0].number // empty"); existingPr != "" {
		throwUsage("PR #" + existingPr + " is already open for '" + prBranch + "'. View it: " + meName + " pr " + existingPr)
	}
}

// cmdPrView: bare lists open PRs; a number views one plus its diff.
func cmdPrView() {
	if prNum == "" {
		runStep("gh", "pr", "list")
	} else {
		runStep("gh", "pr", "view", prNum)
		runStep("gh", "pr", "diff", prNum)
	}
}

func cmdPrCreate() {
	// GitHub can only diff what origin has, so park the work first - same as br merge
	// and release do.
	cmdPush()
	// Announced by hand rather than through runStep, like 'gh pr review' below:
	// runStep would print --head and --body too, which the preview doesn't, so the
	// two lines would disagree.
	prBase := branchTarget("")
	runStepAs("gh pr create --base "+prBase+" --title \""+prTitle+"\"", "gh pr create",
		"gh", "pr", "create", "--base", prBase, "--head", currentBranch(), "--title", prTitle, "--body", "")
}

func cmdPrAccept() {
	// Resolve both before gh deletes the branch out from under us, and off the PR's
	// own head branch (resolved up front) rather than the current one - they need not
	// be the same.
	prTargetBranch := branchTarget(prHeadBranch)
	wasHotfixPr := isHotfixBranch(prHeadBranch)
	echoClean("")
	echoStatus("gh pr review " + prNum + " --approve ...")
	// Best-effort: gh refuses to approve your own PR; merging is the part that matters.
	if !runInheritOK("gh", "pr", "review", prNum, "--approve") {
		echoStatus("Could not approve (own PR?); merging anyway.")
	}
	echoResetBlank()
	runStep("gh", "pr", "merge", prNum, "--merge", "--delete-branch")
	// gh deletes the PR's branch on the remote but leaves our origin/* copy behind,
	// so an upstream still looks present. Prune first; if ours is the branch that
	// just went away, pulling it can only fail - land on the merge target instead.
	fetchRemote()
	if !hasUpstream() {
		runStep("git", "checkout", prTargetBranch)
	}
	pullIfOnline()
	// Same rule as land: a hotfix that reached the default branch still owes dev a
	// merge.
	if wasHotfixPr {
		backMergeToDev()
	}
}
