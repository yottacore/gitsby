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

func (a *app) preview(what string) {
	switch what {
	case "commit":
		msgDisp := "git commit"
		if a.opt.message != "" {
			msgDisp = `git commit -m "` + a.opt.message + `"`
		}
		a.out.clean(pad + "git add --all")
		a.out.clean(pad + msgDisp + " *")
	case "pull":
		a.out.clean(pad + "git pull --ff-only --autostash *")
	case "pullcom":
		a.preview("pull")
		a.preview("commit")
	case "sync":
		a.preview("pullcom")
		a.out.clean(pad + "git push (branch '" + a.currentBranch() + "') *")
	case "br-create":
		// From main/dev the dirty tree rides along to the new branch, so there's no
		// commit here.
		a.previewNewBranch(a.mergeTarget())
	case "br-hotfix":
		// Off the default branch, not dev: this corrects what is already published.
		a.previewNewBranch(a.defaultBranch())
	case "br-switch":
		// Already on the target: nothing is parked and no checkout happens, so the plan
		// must not promise an add/commit/push it will not do.
		target := a.cmd.arg
		if target == "" {
			target = a.mergeTarget()
		}
		if a.currentBranch() != target {
			a.preview("sync")
			a.out.clean(pad + "git checkout " + target)
		}
		a.out.clean(pad + "git pull --ff-only *")
	case "br-merge":
		a.preview("sync")
		a.out.clean(pad + "git checkout " + a.branchTarget(""))
		a.out.clean(pad + "git pull --ff-only *")
		a.out.clean(pad + "git merge --no-ff " + a.currentBranch())
		a.out.clean(pad + "git push *")
		a.out.clean(pad + "git branch -d " + a.currentBranch())
		a.out.clean(pad + "git push origin --delete " + a.currentBranch() + " *")
		a.out.clean(pad + "git pull --ff-only *")
		// A hotfix owes dev the same change, or the next release undoes it.
		if a.isHotfixBranch("") {
			a.previewBackMerge()
		}
	case "br-prune":
		a.prunePreview()
	case "pr":
		a.previewPr()
	case "release":
		a.previewRelease()
	case "repo-clone":
		a.out.clean(pad + "git clone " + maskURL(a.tgt.cloneURL) + " " + a.tgt.cloneDir)
		a.out.clean(pad + "git -C " + a.tgt.cloneDir + " checkout dev *")
	case "repo-url":
		a.out.clean(pad + "git remote set-url origin " + githubURL(remoteTarget(a.originURL()), a.cmd.arg))
	case "account-apply":
		// Names every file and every condition, because this is the one command
		// that writes outside the repo you are standing in - into your own global
		// git config.
		applyDir := a.cfg.includeDir()
		for _, name := range a.cfg.accountNames() {
			a.out.clean(pad + "write " + applyDir + "/" + name + ".gitconfig")
		}
		for _, key := range a.cfg.accountManagedIncludes() {
			a.out.clean(pad + "git config --global --unset-all " + key)
		}
		for _, rule := range a.cfg.accountApplyPlan() {
			a.out.clean(pad + "git config --global --add " + rule.cond + " " + rule.target)
		}
	case "repo-create", "repo-connect":
		if !a.inRepo {
			a.out.clean(pad + "git init -b main")
		}
		a.preview("commit")
		switch a.tgt.connectMode {
		case "create":
			a.out.clean(pad + "gh repo create " + a.tgt.ghTarget + " --" + a.opt.visibility + " --source . --push --remote origin")
		case "add":
			a.out.clean(pad + "git remote add origin " + maskURL(a.tgt.connectURL))
			a.out.clean(pad + "git push -u origin HEAD")
		case "push":
			a.out.clean(pad + "git push -u origin HEAD *")
		}
	}
}

// previewNewBranch is br create and br hotfix - the same recipe off a different
// base.
func (a *app) previewNewBranch(baseBranch string) {
	if a.isProtectedBranch("") {
		a.out.clean(pad + "git checkout " + baseBranch + " *")
		a.out.clean(pad + "git pull --ff-only --autostash *")
	} else {
		a.preview("sync")
		a.out.clean(pad + "git checkout " + baseBranch + " *")
		a.out.clean(pad + "git pull --ff-only *")
	}
	a.out.clean(pad + "git checkout -b " + a.cmd.arg)
	a.out.clean(pad + "git push -u origin " + a.cmd.arg + " *")
}

// previewBackMerge is the tail every hotfix path shares: dev has to receive what
// landed on the default branch.
func (a *app) previewBackMerge() {
	a.out.clean(pad + "git checkout " + a.mergeTarget())
	a.out.clean(pad + "git merge " + a.backMergeRef())
	a.out.clean(pad + "git push *")
}

func (a *app) previewPr() {
	if a.pr.sub == "create" {
		a.preview("sync")
		a.out.clean(pad + "gh pr create --base " + a.branchTarget("") + " --title \"" + a.pr.title + "\"")
		return
	}
	a.out.clean(pad + "gh pr review " + a.pr.num + " --approve *")
	a.out.clean(pad + "gh pr merge " + a.pr.num + " --merge --delete-branch")
	a.out.clean(pad + "git checkout " + a.branchTarget(a.pr.headBranch) + " *")
	a.out.clean(pad + "git pull --ff-only *")
	if a.isHotfixBranch(a.pr.headBranch) {
		a.previewBackMerge()
	}
}

func (a *app) previewRelease() {
	a.preview("sync")
	hasDev := a.mergeTarget() == "dev"
	if hasDev {
		a.out.clean(pad + "git checkout dev *")
		a.out.clean(pad + "git pull --ff-only *")
	}
	a.out.clean(pad + "git checkout " + a.defaultBranch() + " *")
	a.out.clean(pad + "git pull --ff-only *")
	if hasDev {
		a.out.clean(pad + "git merge --no-ff dev")
	}
	a.out.clean(pad + "git tag -a " + a.rel.tag)
	a.out.clean(pad + "git push *")
	a.out.clean(pad + "git push origin " + a.rel.tag + " *")
	if hasDev {
		a.out.clean(pad + "git checkout dev *")
		a.out.clean(pad + "git merge --ff-only " + a.defaultBranch() + " *")
		a.out.clean(pad + "git push *")
	}
	a.out.clean(pad + "git checkout " + a.currentBranch() + " *")
}
