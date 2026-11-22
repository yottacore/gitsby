// Cutting a release: work out the version, refuse the ones that would strand a
// tag, then merge dev into the default branch, tag it, and push both. The version
// settles up front so the plan and the command can't disagree about it.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

// releasePlan is the version this run cuts, and whether we invented it - the
// guards below only speak for the invented ones. resume is a release already
// merged and tagged here whose push failed, so this run only sends it.
type releasePlan struct {
	tag    string
	bumped bool
	resume bool
}

// releaseVerRE is X.Y.Z, then a '-' or '.' and dot-separated parts, none of them
// empty. RELEASE_VERSION_RE in cicd/config.bash is the same, for release.bash, and
// test.bash holds the two together.
var (
	releaseVerRE = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$`)
	releaseTagRE = regexp.MustCompile(`^v?([0-9]+)(\.([0-9]+))?(\.([0-9]+))?(.*)$`)
)

// releaseVersionOK is a version git can also take as a tag, with or without the
// 'v'. Within the pattern's characters, the only name git refuses is one ending
// in ".lock", and a tag git refuses fails only after the release merge is made.
func releaseVersionOK(ver string) bool {
	return releaseVerRE.MatchString(ver) && !strings.HasSuffix(ver, ".lock")
}

// nextVersion is the version that follows a tag. A candidate's own version is
// what comes next: v2.0.0-rc1 -> v2.0.0, not v2.0.1 - promoting a candidate is a
// deliberate version rather than an invented one, and the bool says which. Short
// tags like v1.2 or v2020 pad out, and an unreadable one starts the numbering.
func nextVersion(latest string) (version string, bumped bool) {
	m := releaseTagRE.FindStringSubmatch(latest)
	if m == nil {
		return "0.1.0", true // first release ever, or an unreadable tag
	}
	major, minor := m[1], m[3]
	if minor == "" {
		minor = "0"
	}
	// m[5] already matched [0-9]+, so Atoi only fails on overflow - it answers
	// with the clamped max, which the bump below would wrap negative; 0 starts over.
	patch, err := strconv.Atoi(m[5])
	if err != nil {
		patch = 0
	}
	bumped = m[6] == ""
	if bumped {
		patch++
	}
	return major + "." + minor + "." + strconv.Itoa(patch), bumped
}

// resolveRelease settles the tag this run cuts, from the argument or from the
// latest tag in the repo.
func (a *app) resolveRelease() error {
	if ver := strings.TrimPrefix(a.cmd.arg, "v"); ver != "" {
		if !releaseVersionOK(ver) {
			return usageOf("release").refuse("'" + ver + "' is not a version.")
		}
		a.rel.tag = a.cmd.arg
		return nil
	}
	// newestReleaseTag weighs every tag itself; git's order only breaks its ties.
	tags := runLines("git", "-c", "versionsort.suffix=-", "tag", "--list", "v[0-9]*", "[0-9]*", "--sort=-v:refname")
	a.rel.tag, a.rel.bumped = nextReleaseTag(newestReleaseTag(tags))
	return nil
}

// nextReleaseTag is the tag after latest, spelled the same way, so a repo tagged
// without the 'v' goes on without it. The first tag gets the 'v'.
func nextReleaseTag(latest string) (tag string, bumped bool) {
	ver, bumped := nextVersion(latest)
	if latest != "" && !strings.HasPrefix(latest, "v") {
		return ver, bumped
	}
	return "v" + ver, bumped
}

// newestReleaseTag picks the tag to count on from tags git sorted newest first.
// A tag with no 'v' counts only as a whole X.Y.Z, so a date or a build number
// can't restart the numbering. Every tag goes through tagNewer rather than taking
// git's first: git ranks v3.0.0.rc1 above v3.0.0, and a versionsort.suffix of '.'
// would put v1.2 above v1.2.1. A tie keeps git's order, so rc.2 beats rc.1.
func newestReleaseTag(sorted []string) string {
	newest := ""
	for _, tag := range sorted {
		if !strings.HasPrefix(tag, "v") && !releaseVersionOK(tag) {
			continue
		}
		if newest == "" || tagNewer(tag, newest) {
			newest = tag
		}
	}
	return newest
}

// tagNewer: by number, then a full release over a candidate of the same number.
func tagNewer(tag, than string) bool {
	m, n := releaseTagRE.FindStringSubmatch(tag), releaseTagRE.FindStringSubmatch(than)
	if m == nil || n == nil {
		return n == nil && m != nil
	}
	for _, i := range []int{1, 3, 5} {
		// Atoi clamps on overflow, which still compares the right way.
		mi, _ := strconv.Atoi(m[i])
		ni, _ := strconv.Atoi(n[i])
		if mi != ni {
			return mi > ni
		}
	}
	return m[6] == "" && n[6] != ""
}

// releasePreflight refuses up front rather than mid-command: by the time
// cmdRelease runs it has already committed and pushed.
func (a *app) releasePreflight() error {
	ver := strings.TrimPrefix(a.rel.tag, "v")
	// After a failed push the next run finishes that release. A version worked out
	// here, a candidate's promotion included, would tag the same commit again and push
	// it, and the first tag would never go. A different version typed out is
	// deliberate, so it still cuts its own.
	typed := strings.TrimPrefix(a.cmd.arg, "v") != ""
	if pending, devOnly := a.unpushedRelease(); pending != "" && (!typed || strings.TrimPrefix(pending, "v") == ver) {
		head := "Release " + pending + " is tagged here but never reached origin"
		if devOnly {
			head = "Release " + pending + " is out, but 'dev' never reached origin"
		}
		// cmdRelease parks the current branch before the pushes. On the default
		// branch that commits past the tag and pushes it, then dev fast-forwards onto
		// it. Elsewhere the park stays off the release.
		if relMain := a.defaultBranch(); a.currentBranch() == relMain && a.commitPending() {
			return refusalBlock(head+", and '"+relMain+"' has uncommitted changes. Nothing was done.", [][]string{
				noteLines("Why", "Finishing it pushes '"+relMain+"' as it was tagged. Committing the changes first would put them on '"+relMain+"' past "+pending+"."),
				noteLines("Fix", "Set them aside with 'git stash --include-untracked', and run this again. Then put them back with 'git stash pop' on the branch they belong on."),
			}, nil)
		}
		a.rel = releasePlan{tag: pending, resume: true}
		a.out.status(head + "; finishing it.")
		return nil
	}
	// Either spelling, or 'release 1.2.3' in a repo tagged v1.2.3 cuts a second tag
	// for the same version.
	if have := runLines("git", "tag", "--list", "v"+ver, ver); len(have) > 0 {
		return usagef("Tag '%s' already exists.", have[0])
	}
	// An invented version on a target that gains nothing cuts a tag for no release, and
	// a re-run cuts another. Fails open.
	if !a.rel.bumped || a.parksIntoRelease() {
		return nil
	}
	// Full refs throughout, since git reads a tag of the same name ahead of a branch.
	relMain := a.defaultBranch()
	relTarget := "refs/heads/" + relMain
	if !a.branchExistsLocal(relMain) {
		relTarget = "refs/remotes/origin/" + relMain
	}
	// The local branch is what gets tagged and pushed, so it is what "nothing new"
	// is about. Stand down if origin has commits we don't: the pull would bring
	// them in.
	if a.branchExistsLocal(relMain) && a.branchExistsRemote(relMain) {
		if !runOK("git", "merge-base", "--is-ancestor", "refs/remotes/origin/"+relMain, relTarget) {
			return nil
		}
	}
	// Both copies of dev, since the release merges the local one after pulling
	// origin's. Work parked on dev was counted above, but from another branch a local
	// dev ahead of origin's is only seen here.
	if a.branchExistsRemote("dev") && !runOK("git", "merge-base", "--is-ancestor", "refs/remotes/origin/dev", relTarget) {
		return nil
	}
	if a.branchExistsLocal("dev") && !runOK("git", "merge-base", "--is-ancestor", "refs/heads/dev", relTarget) {
		return nil
	}
	if relExisting := runOut("git", "describe", "--exact-match", "--tags", relTarget); relExisting != "" {
		a.out.status("Nothing new to release since " + relExisting + ".")
		a.out.clean("  If that tag never reached origin, push it:")
		a.out.clean("    git push origin tag " + typedArg(relExisting, runtime.GOOS))
		a.out.clean("")
		return errDone
	}
	return nil
}

// parksIntoRelease: the current branch has work the release takes, in the tree or
// in commits origin doesn't have yet. cmdPush parks only the current branch, and
// cutRelease merges dev into the default branch, or tags the default branch alone,
// so work parked anywhere else stays out of the release.
func (a *app) parksIntoRelease() bool {
	if cur := a.currentBranch(); cur != a.mergeTarget() && cur != a.defaultBranch() {
		return false
	}
	return a.commitPending() || isAhead()
}

// unpushedRelease is the release tag on the tip of the local default branch while
// origin's copy is behind it or missing, or while it is level and only dev's push,
// the release's last, never went: a release cut here whose push failed. A default
// branch that went its own way from origin's isn't one, since its push would be
// refused anyway. devOnly is the level case.
func (a *app) unpushedRelease() (tag string, devOnly bool) {
	relMain := a.defaultBranch()
	if !a.branchExistsLocal(relMain) {
		return "", false
	}
	local := "refs/heads/" + relMain
	if a.branchExistsRemote(relMain) {
		// "<behind> <ahead>" of origin's copy.
		counts := strings.Fields(runOut("git", "rev-list", "--left-right", "--count", "refs/remotes/origin/"+relMain+"..."+local))
		if len(counts) != 2 || counts[0] != "0" {
			return "", false
		}
		if devOnly = counts[1] == "0"; devOnly && !a.devPushPending(local) {
			return "", false
		}
	}
	var tags []string
	for _, t := range runLines("git", "-c", "versionsort.suffix=-", "tag", "--list", "--points-at", local, "v[0-9]*", "[0-9]*", "--sort=-v:refname") {
		if releaseVersionOK(strings.TrimPrefix(t, "v")) {
			tags = append(tags, t)
		}
	}
	return newestReleaseTag(tags), devOnly
}

// devPushPending: dev here sits on the release, fast-forwarded to it, and origin's
// dev is behind it, so the release's last push failed. Read as work, dev's lead made
// a bare release cut a second tag on the same commit. A dev that moved on since, or
// one origin's went past, isn't one.
func (a *app) devPushPending(mainRef string) bool {
	if a.mergeTarget() != "dev" || !a.branchExistsLocal("dev") || !a.branchExistsRemote("dev") {
		return false
	}
	revs := runLines("git", "rev-parse", "refs/heads/dev", mainRef, "refs/remotes/origin/dev")
	if len(revs) != 3 || revs[0] != revs[1] || revs[2] == revs[0] {
		return false
	}
	return runOK("git", "merge-base", "--is-ancestor", "refs/remotes/origin/dev", "refs/heads/dev")
}

// cmdRelease merges dev into main/master --no-ff (if the repo has a dev), tags,
// and pushes both. A resumed release has the merge and the tag already.
func (a *app) cmdRelease() error {
	mainBranch := a.defaultBranch()
	// The same answer the plan read, so the run can't take a dev the plan never showed.
	devBranch := ""
	if a.mergeTarget() == "dev" {
		devBranch = "dev"
	}
	startBranch := a.currentBranch()
	if err := a.cmdPush(); err != nil { // park current work safely first
		return err
	}
	if a.rel.resume {
		if a.currentBranch() != mainBranch {
			if err := a.checkout(mainBranch); err != nil {
				return err
			}
		}
	} else if err := a.cutRelease(mainBranch, devBranch, startBranch); err != nil {
		return err
	}
	// The branch has to reach origin, not just the tag - otherwise origin gets the
	// commits as tag payload while its main still points at the old release. Same
	// trap as merge's.
	if a.hasOrigin() {
		if err := a.pushCurrent(); err != nil {
			return err
		}
		// 'tag' names refs/tags only, so a branch with the tag's name can't make the
		// push ambiguous.
		if err := a.step("git", "push", "origin", "tag", a.rel.tag); err != nil {
			return err
		}
	}
	// Fast-forward dev to include the release merge and tag, so dev isn't left a
	// commit behind. ff-only (not branch -f): if dev moved mid-release, skip rather
	// than discard work.
	if devBranch != "" {
		if !runOK("git", "merge-base", "--is-ancestor", "refs/heads/"+devBranch, "refs/heads/"+mainBranch) {
			a.out.status("WARNING: '" + devBranch + "' gained commits during the release; leaving it as-is.")
		} else {
			if err := a.checkout(devBranch); err != nil {
				return err
			}
			if err := a.step("git", "merge", "--ff-only", "refs/heads/"+mainBranch); err != nil {
				return err
			}
			if a.hasUpstream() {
				if err := a.pushCurrent(); err != nil {
					return err
				}
			}
		}
	}
	// Don't leave the user parked on main. previewRelease's last line follows this.
	if startBranch != "" && startBranch != a.currentBranch() && startBranch != mainBranch {
		return a.checkout(startBranch)
	}
	return nil
}

// cutRelease freshens dev, merges it into the default branch and tags the result,
// leaving the default branch checked out for the pushes.
func (a *app) cutRelease(mainBranch, devBranch, startBranch string) error {
	if devBranch != "" && a.currentBranch() != devBranch {
		// Freshen dev so the release has all of it.
		if err := a.checkout(devBranch); err != nil {
			return err
		}
		if err := a.pullIfOnline(); err != nil {
			return err
		}
	}
	if a.currentBranch() != mainBranch {
		if err := a.checkout(mainBranch); err != nil {
			return err
		}
	}
	if err := a.pullIfOnline(); err != nil {
		return err
	}
	if devBranch != "" {
		mergeMessage := a.opt.message
		if mergeMessage == "" {
			mergeMessage = "Release " + a.rel.tag
		}
		// By full ref: git merge reads a tag of the same name ahead of the branch.
		if err := a.step("git", "merge", "--no-ff", "refs/heads/"+devBranch, "-m", mergeMessage); err != nil {
			rerun := meName + " release"
			if a.cmd.arg != "" {
				rerun += " " + typedArg(a.cmd.arg, runtime.GOOS)
			}
			return a.backOutMerge(err, devBranch, mainBranch, startBranch,
				[]string{"git checkout " + typedArg(devBranch, runtime.GOOS), "git merge " + typedArg(mainBranch, runtime.GOOS)}, rerun)
		}
	}
	return a.step("git", "tag", "-a", a.rel.tag, "-m", a.rel.tag)
}
