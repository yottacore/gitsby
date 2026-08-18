// The plan display. A static per-command recipe; the command functions do the
// real state checks at run time, which is what the '*' marks. 'commit' and 'pull'
// are not commands of their own - they stay here as the fragments the real ones
// compose their plans from.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

const pad = "    "

func preview(what string) {
	msgDisp := "git commit"
	if commitMessage != "" {
		msgDisp = `git commit -m "` + commitMessage + `"`
	}
	switch what {
	case "commit":
		echoClean(pad + "git add --all")
		echoClean(pad + msgDisp + " *")
	case "pull":
		echoClean(pad + "git pull --ff-only --autostash *")
	case "pullcom":
		preview("pull")
		preview("commit")
	case "sync":
		preview("pullcom")
		echoClean(pad + "git push (branch '" + currentBranch() + "') *")
	case "br-create":
		// From main/dev the dirty tree rides along to the new branch, so there's no
		// commit here.
		previewNewBranch(mergeTarget())
	case "br-hotfix":
		// Off the default branch, not dev: this corrects what is already published.
		previewNewBranch(defaultBranch())
	case "br-switch":
		// Already on the target: nothing is parked and no checkout happens, so the plan
		// must not promise an add/commit/push it will not do.
		target := cmdArg
		if target == "" {
			target = mergeTarget()
		}
		if currentBranch() != target {
			preview("sync")
			echoClean(pad + "git checkout " + target)
		}
		echoClean(pad + "git pull --ff-only *")
	case "br-merge":
		preview("sync")
		echoClean(pad + "git checkout " + branchTarget(""))
		echoClean(pad + "git pull --ff-only *")
		echoClean(pad + "git merge --no-ff " + currentBranch())
		echoClean(pad + "git push *")
		echoClean(pad + "git branch -d " + currentBranch())
		echoClean(pad + "git push origin --delete " + currentBranch() + " *")
		echoClean(pad + "git pull --ff-only *")
		// A hotfix owes dev the same change, or the next release undoes it.
		if isHotfixBranch("") {
			echoClean(pad + "git checkout " + mergeTarget())
			echoClean(pad + "git merge " + backMergeRef())
			echoClean(pad + "git push *")
		}
	case "br-prune":
		prunePreview()
	case "pr":
		if prSub == "create" {
			preview("sync")
			echoClean(pad + "gh pr create --base " + branchTarget("") + " --title \"" + prTitle + "\"")
		} else {
			echoClean(pad + "gh pr review " + prNum + " --approve *")
			echoClean(pad + "gh pr merge " + prNum + " --merge --delete-branch")
			echoClean(pad + "git checkout " + branchTarget(prHeadBranch) + " *")
			echoClean(pad + "git pull --ff-only *")
			if isHotfixBranch(prHeadBranch) {
				echoClean(pad + "git checkout " + mergeTarget())
				echoClean(pad + "git merge " + backMergeRef())
				echoClean(pad + "git push *")
			}
		}
	case "release":
		preview("sync")
		hasDev := mergeTarget() == "dev"
		if hasDev {
			echoClean(pad + "git checkout dev *")
			echoClean(pad + "git pull --ff-only *")
		}
		echoClean(pad + "git checkout " + defaultBranch() + " *")
		echoClean(pad + "git pull --ff-only *")
		if hasDev {
			echoClean(pad + "git merge --no-ff dev")
		}
		echoClean(pad + "git tag -a " + releaseTag)
		echoClean(pad + "git push *")
		echoClean(pad + "git push origin " + releaseTag + " *")
		if hasDev {
			echoClean(pad + "git checkout dev *")
			echoClean(pad + "git merge --ff-only " + defaultBranch() + " *")
			echoClean(pad + "git push *")
		}
		echoClean(pad + "git checkout " + currentBranch() + " *")
	case "repo-clone":
		echoClean(pad + "git clone " + maskUrl(cloneUrl) + " " + cloneDir)
		echoClean(pad + "git -C " + cloneDir + " checkout dev *")
	case "repo-url":
		echoClean(pad + "git remote set-url origin " + githubUrl(remoteTarget(runOut("git", "remote", "get-url", "origin")), cmdArg))
	case "account-apply":
		// Names every file and every condition, because this is the one command
		// that writes outside the repo you are standing in - into your own global
		// git config.
		applyDir := accountIncludeDir()
		for _, name := range accountNames() {
			echoClean(pad + "write " + applyDir + "/" + name + ".gitconfig")
		}
		for _, key := range accountManagedIncludes() {
			echoClean(pad + "git config --global --unset-all " + key)
		}
		for _, rule := range accountApplyPlan() {
			echoClean(pad + "git config --global --add " + rule.cond + " " + rule.target)
		}
	case "repo-create", "repo-connect":
		if !inRepo {
			echoClean(pad + "git init -b main")
		}
		preview("commit")
		switch connectMode {
		case "create":
			echoClean(pad + "gh repo create " + ghTarget + " --" + repoVisibility + " --source . --push --remote origin")
		case "add":
			echoClean(pad + "git remote add origin " + maskUrl(connectUrl))
			echoClean(pad + "git push -u origin HEAD")
		case "push":
			echoClean(pad + "git push -u origin HEAD *")
		}
	}
}

// previewNewBranch is br create and br hotfix - the same recipe off a different
// base.
func previewNewBranch(baseBranch string) {
	if isProtectedBranch("") {
		echoClean(pad + "git checkout " + baseBranch + " *")
		echoClean(pad + "git pull --ff-only --autostash *")
	} else {
		preview("sync")
		echoClean(pad + "git checkout " + baseBranch + " *")
		echoClean(pad + "git pull --ff-only *")
	}
	echoClean(pad + "git checkout -b " + cmdArg)
	echoClean(pad + "git push -u origin " + cmdArg + " *")
}
