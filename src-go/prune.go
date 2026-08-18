// br prune's survey and plan. All read-only: the survey decides, the plan shows
// every branch by name, and the deleting half lands with the other writers.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import "strings"

var (
	pruneTargetRefs    []string
	pruneLocal         []string
	pruneRemote        []string
	pruneKeep          []string
	pruneCurrentMerged = ""
)

// resolvePrune sorts local branches into what's already landed and what isn't.
// Ancestry is an exact test here only because gitsby always lands with a real
// merge commit - a squash- or rebase-landed branch never looks contained, and is
// kept rather than guessed at.
func resolvePrune() {
	target := mergeTarget()
	targetRemoteRef := "refs/remotes/origin/" + target
	if branchExistsLocal(target) {
		pruneTargetRefs = append(pruneTargetRefs, "refs/heads/"+target)
	}
	if branchExistsRemote(target) {
		pruneTargetRefs = append(pruneTargetRefs, targetRemoteRef)
	}
	current := currentBranch()
	// Ask once per target ref, not once per branch: 'for-each-ref --merged' answers
	// "which branches are contained in this ref" for all of them in a single call.
	// The delete-time per-branch re-check stays with the deleting half, deliberately:
	// the confirmation prompt can sit a while, and that one is the safety net rather
	// than the survey.
	mergedLocal := map[string]bool{}
	for _, ref := range pruneTargetRefs {
		for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "--merged", ref, "refs/heads/") {
			mergedLocal[branch] = true
		}
	}
	mergedRemote := map[string]bool{}
	if runOK("git", "rev-parse", "-q", "--verify", targetRemoteRef) {
		for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "--merged", targetRemoteRef, "refs/remotes/origin/") {
			mergedRemote[branch] = true
		}
	}
	for _, branch := range runLines("git", "for-each-ref", "--format=%(refname:short)", "refs/heads/") {
		// The branch we're standing on can't be deleted, and protected ones never are.
		// But if it WOULD have qualified, say so - otherwise it just vanishes from
		// every list.
		if branch == current {
			if !isProtectedBranch(branch) && mergedLocal[branch] {
				pruneCurrentMerged = branch
			}
			continue
		}
		if isProtectedBranch(branch) {
			continue
		}
		if mergedLocal[branch] {
			pruneLocal = append(pruneLocal, branch)
			// The remote copy goes only when origin has the merge too: a landing that
			// hasn't been pushed yet leaves origin holding the only ref to that work.
			if branchExistsRemote(branch) && mergedRemote["origin/"+branch] {
				pruneRemote = append(pruneRemote, branch)
			}
		} else {
			pruneKeep = append(pruneKeep, branch)
		}
	}
}

// pruneNothingToDo says WHY the plan is empty - "no branch is merged" would be a
// lie when the merged one is the branch we're standing on.
func pruneNothingToDo() {
	if pruneCurrentMerged != "" {
		echoStatus("Nothing to prune from here.")
		echoClean("  Current branch '" + pruneCurrentMerged + "' is merged, but you're on it; switch off it to prune it.")
	} else {
		echoStatus("Nothing to prune; no branch is fully merged into '" + mergeTarget() + "' yet.")
	}
	if len(pruneKeep) > 0 {
		echoClean("  Keeping (not merged yet): " + strings.Join(pruneKeep, ", "))
	}
	echoClean("")
}

// prunePreview is br prune's slice of the plan display.
func prunePreview() {
	const pad = "    "
	// -D is what runs, so -D is what the plan says. The line above it is the reason
	// that's safe: gitsby checks containment itself, against the branch that matters.
	echoClean(pad + "(each verified contained in " + mergeTarget() + ", and re-checked at delete time)")
	for _, branch := range pruneLocal {
		echoClean(pad + "git branch -D " + branch)
	}
	for _, branch := range pruneRemote {
		echoClean(pad + "git push origin --delete " + branch)
	}
	if pruneCurrentMerged != "" {
		echoClean(pad + "Keeping '" + pruneCurrentMerged + "' - merged, but it's the current branch.")
	}
	if len(pruneKeep) > 0 {
		echoClean(pad + "Keeping (not merged yet): " + strings.Join(pruneKeep, ", "))
	}
}
