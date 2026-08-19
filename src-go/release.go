// Cutting a release: work out the version, refuse the ones that would strand a
// tag, then merge dev into the default branch, tag it, and push both. The version
// settles up front so the plan and the command can't disagree about it.

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

var (
	releaseTag    = ""
	releaseBumped = false // set when we invented the version rather than being told it
)

var (
	releaseVerRE = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$`)
	releaseTagRE = regexp.MustCompile(`^v?([0-9]+)(\.([0-9]+))?(\.([0-9]+))?(.*)$`)
)

// resolveRelease settles releaseTag, and records whether the version was ours or
// the caller's - the guards below only speak for the invented ones.
func resolveRelease() {
	ver := strings.TrimPrefix(cmdArg, "v")
	if ver != "" {
		if !releaseVerRE.MatchString(ver) {
			throwUsage("'" + ver + "' is not a version (want X.Y.Z, optional -suffix). Syntax: " + meName + " release [version]")
		}
		releaseTag = "v" + ver
		return
	}
	ver = "0.1.0" // first release ever, or an unreadable tag
	releaseBumped = true
	latest := ""
	// versionsort.suffix=- ranks v2.0.0 above its own v2.0.0-rc1; the default sort
	// inverts them.
	if tags := runLines("git", "-c", "versionsort.suffix=-", "tag", "--list", "v[0-9]*", "--sort=-v:refname"); len(tags) > 0 {
		latest = tags[0]
	}
	if m := releaseTagRE.FindStringSubmatch(latest); m != nil {
		maj := m[1]
		min := m[3] // pad short tags like v1.2 or v2020
		if min == "" {
			min = "0"
		}
		pat, _ := strconv.Atoi(m[5])
		// A candidate's own version is what comes next: v2.0.0-rc1 -> v2.0.0, not
		// v2.0.1. Promoting a candidate is a deliberate version, not an invented one.
		if m[6] != "" {
			releaseBumped = false
		} else {
			pat++
		}
		ver = maj + "." + min + "." + strconv.Itoa(pat)
	}
	releaseTag = "v" + ver
}

// releasePreflight refuses up front rather than mid-command: by the time
// cmdRelease runs it has already committed and pushed.
func releasePreflight() {
	if runOK("git", "rev-parse", "-q", "--verify", "refs/tags/"+releaseTag) {
		throwUsage("Tag '" + releaseTag + "' already exists.")
	}
	// An invented version on a target that would gain nothing cuts a tag for no
	// release, and the natural re-run after a failed push cuts a second one on the
	// same commit - so the first is stranded forever. A version you typed, and
	// promoting a candidate, are deliberate and stay allowed. Fails open: if we
	// can't tell, the release goes ahead. 'release' parks first, so uncommitted work
	// or unpushed commits ARE something to release even when the branches currently
	// look level - the guard only speaks for a settled repo.
	if !releaseBumped || runOut("git", "status", "--porcelain") != "" || isAhead() {
		return
	}
	relMain := defaultBranch()
	relTarget := relMain
	if !branchExistsLocal(relMain) {
		relTarget = "origin/" + relMain
	}
	// The local branch is what gets tagged and pushed, so it is what "nothing new"
	// is about. Stand down if origin holds commits we don't: the pull would bring
	// them in.
	if relTarget == relMain && branchExistsRemote(relMain) {
		if !runOK("git", "merge-base", "--is-ancestor", "origin/"+relMain, relMain) {
			return
		}
	}
	relSource := ""
	if branchExistsRemote("dev") {
		relSource = "origin/dev"
	} else if branchExistsLocal("dev") {
		relSource = "dev"
	}
	if relSource != "" && !runOK("git", "merge-base", "--is-ancestor", relSource, relTarget) {
		return
	}
	if relExisting := runOut("git", "describe", "--exact-match", "--tags", relTarget); relExisting != "" {
		throwUsage("Nothing new to release since " + relExisting + ". If that tag never reached origin, push it: git push origin " + relExisting)
	}
}

// cmdRelease merges dev into main/master --no-ff (if the repo has a dev), tags,
// and pushes both.
func cmdRelease() {
	mainBranch := defaultBranch()
	devBranch := ""
	if branchExistsLocal("dev") || branchExistsRemote("dev") {
		devBranch = "dev"
	}
	startBranch := currentBranch()
	cmdPush() // park current work safely first
	if devBranch != "" && currentBranch() != devBranch {
		runStep("git", "checkout", devBranch) // freshen dev so the release has all of it
		pullIfOnline()
	}
	if currentBranch() != mainBranch {
		runStep("git", "checkout", mainBranch)
	}
	pullIfOnline()
	if devBranch != "" {
		mergeMessage := commitMessage
		if mergeMessage == "" {
			mergeMessage = "Release " + releaseTag
		}
		runStep("git", "merge", "--no-ff", devBranch, "-m", mergeMessage)
	}
	runStep("git", "tag", "-a", releaseTag, "-m", releaseTag)
	// The branch has to reach origin, not just the tag - otherwise origin gets the
	// commits as tag payload while its main still points at the old release. Same
	// trap as land's.
	if hasOrigin() {
		if hasUpstream() {
			runStep("git", "push")
		} else {
			runStep("git", "push", "-u", "origin", "HEAD")
		}
		runStep("git", "push", "origin", releaseTag)
	}
	// Fast-forward dev to include the release merge and tag, so dev isn't left a
	// commit behind. ff-only (not branch -f): if dev moved mid-release, skip rather
	// than discard work.
	if devBranch != "" {
		if runOK("git", "merge-base", "--is-ancestor", devBranch, mainBranch) {
			runStep("git", "checkout", devBranch)
			runStep("git", "merge", "--ff-only", mainBranch)
			if hasUpstream() {
				runStep("git", "push")
			}
		} else {
			echoStatus("WARNING: '" + devBranch + "' gained commits during the release; leaving it as-is.")
		}
	}
	// Don't leave the user parked on main.
	if startBranch != "" && startBranch != currentBranch() && startBranch != mainBranch {
		runStep("git", "checkout", startBranch)
	}
}
