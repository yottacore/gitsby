<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Git help

Command strings for common git tasks

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [General notes](#general-notes)
	- [Stash](#stash)
- [Commands for common tasks](#commands-for-common-tasks)
	- [Basics using main or master](#basics-using-main-or-master)
		- [Clone a project and start programming with it, using aliases in ~/.ssh/config](#clone-a-project-and-start-programming-with-it-using-aliases-in-sshconfig)
		- [Reconnect to a project after renaming it remotely](#reconnect-to-a-project-after-renaming-it-remotely)
	- [Regular use](#regular-use)
		- [Refresh local with changes from upstream](#refresh-local-with-changes-from-upstream)
		- [Push local changes to upstream](#push-local-changes-to-upstream)
	- [Read-only inspection](#read-only-inspection)
		- [Show what SSH keys and username git thinks you're using](#show-what-ssh-keys-and-username-git-thinks-youre-using)
		- [Show diff between local state and upstream](#show-diff-between-local-state-and-upstream)
	- [Branches](#branches)
		- [Check out an existing branch and start using it, while preserving local changes](#check-out-an-existing-branch-and-start-using-it-while-preserving-local-changes)
		- [Create a new branch and sync it to GitHub](#create-a-new-branch-and-sync-it-to-github)
		- [Merge current local feature branch to main, and return to main](#merge-current-local-feature-branch-to-main-and-return-to-main)
	- [Maintenance](#maintenance)
		- [Remove a file from git AND locally](#remove-a-file-from-git-and-locally)
- [References](#references)

<!-- /TOC -->

## General notes

### Stash

`git stash apply` leaves the current stash on the stash. `git stash pop` does the same thing as apply, but removes the last stash. `--include-untracked` includes untracked, which could make the stash grow large. The stash is local.

Care is needed with `stash apply` or `stash pop`, because if the a `git stash push` didn't succeed, then a corresponding `apply` or `pop` may use a stale set.

## Commands for common tasks

### Basics using main or master

#### Clone a project and start programming with it, using aliases in ~/.ssh/config

~~~bash
gitProj="REMOTE_REPO_NAME"
gitUser="YOUR_GIT_USER_NAME"
[[ -n "${gitProj}"  &&  -n "${gitUser}" ]]  &&  git clone "git@github_${gitUser}:${gitUser}/${gitProj}.git"  &&  cd "${gitProj}"  &&  echo  &&  git remote -v  &&  echo  &&  git config user.name  &&  git config user.email  &&  echo
~~~

#### Reconnect to a project after renaming it remotely

~~~bash
gitProj="REMOTE_REPO_NAME"
gitUser="YOUR_GIT_USER_NAME"
[[ -n "${gitProj}"  &&  -n "${gitUser}" ]]  &&  git remote set-url origin "git@github_${gitUser}:${gitUser}/${gitProj}.git"  &&  echo -e "\ngit will be using this contact info:" ; git config user.name ; git config user.email; echo -e "\ngit remote info:" ; git remote -v; echo -e "\nSSH login test:" ; ssh -T git@github.com; echo  &&  git status  &&  echo
~~~

### Regular use

#### Refresh local with changes from upstream

~~~bash
preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0)); git pull --ff-only; ((didStash)) && git stash pop; echo && git status && echo
~~~

#### Push local changes to upstream

~~~bash
n8git_backup-and-publish
~~~

or

~~~bash
preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0)); git pull --rebase; ((didStash)) && git stash pop; git add --all && (git diff --cached --quiet || git commit) && git push -u origin HEAD; echo && git status && echo
~~~

### Read-only inspection

#### Show what SSH keys and username git thinks you're using

~~~bash
echo -e "\ngit will be using this contact info:" ; git config user.name ; git config user.email; echo -e "\ngit remote info:" ; git remote -v; echo -e "\nSSH login test:" ; ssh -T git@github.com; echo  &&  git status  &&  echo
~~~

#### Show diff between local state and upstream

~~~bash
git fetch && echo && git status  &&  { echo; git diff HEAD @{u} | less -FRX; echo; }
~~~

### Branches

#### Check out an existing branch and start using it, while preserving local changes

~~~bash
gitProj="feature/1-refactor-from-static-template-to-dynamic-library"
[[ -n "${gitProj}" ]]  &&  { preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0));  git fetch origin  &&  git checkout "${gitProj}"  &&  { ((didStash)) && git stash pop || true; }  &&  echo  &&  git status  &&  echo ; }
~~~

#### Create a new branch and sync it to GitHub

~~~bash
branchName="feature/YOUR_BRANCH_NAME"
[[ -n "${branchName}" ]]  &&  { preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0));  git pull --ff-only  &&  git checkout -b "${branchName}"  &&  { ((didStash)) && git stash pop || true; }  &&  git push -u origin "${branchName}"  &&  echo  &&  git branch -vv  &&  echo  &&  git status  &&  echo ; }
~~~

#### Merge current local feature branch to main, and return to main

~~~bash
branchName="feature/1-refactor-from-static-template-to-dynamic-library"

## Commit local changes and sync with upstream
preCount=$(git stash list | wc -l); git stash push --include-untracked -m "auto-stash"; postCount=$(git stash list | wc -l); didStash=$((postCount > preCount ? 1 : 0)); git pull --rebase; ((didStash)) && git stash pop; git add --all && (git diff --cached --quiet || git commit) && git push -u origin HEAD; echo && git status && echo

## Merge to main (assumes clean working tree — run preceding block first)
[[ -n "${branchName}" ]]  &&  git checkout main  &&  git pull --ff-only origin main  &&  git checkout "${branchName}"  &&  git merge main  &&  git checkout main  &&  git merge --no-ff "${branchName}"  &&  git push origin main  &&  echo  &&  git branch -vv  &&  echo  &&  git status  &&  echo
~~~

### Maintenance

#### Remove a file from git AND locally

~~~bash
fileToDelete="FILE_TO_DELETE"
[[ -n "${fileToDelete}"  &&  -e "${fileToDelete}" ]]  &&  git rm --cached -r "${fileToDelete}"  &&  git commit -m "Remove '${fileToDelete}' from tracking."  &&  git push  &&  trash "${fileToDelete}"
~~~

## References

- [x9git project](https://github.com/jim-collier/x9git/tree/main)
- [x9git reference](https://github.com/jim-collier/x9git/blob/main/reference/git.txt)
