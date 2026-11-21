// The branch list is read once per run, so what moves a ref has to drop it: a
// step through the runners, and the fetch, which is not a step.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// gitTestRepo makes a bare origin with one commit on main and a clone of it, under
// a git that reads no config but its own. It returns both paths.
func gitTestRepo(t *testing.T) (origin, clone string) {
	t.Helper()
	if !inPath("git") {
		t.Skip("no git")
	}
	for _, name := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_SSH_COMMAND"} {
		t.Setenv(name, "")
		if err := os.Unsetenv(name); err != nil {
			t.Fatal(err)
		}
	}
	for name, value := range map[string]string{
		"GIT_CONFIG_GLOBAL": os.DevNull, "GIT_CONFIG_SYSTEM": os.DevNull, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "Ada", "GIT_AUTHOR_EMAIL": "ada@example.test",
		"GIT_COMMITTER_NAME": "Ada", "GIT_COMMITTER_EMAIL": "ada@example.test",
	} {
		t.Setenv(name, value)
	}
	root := t.TempDir()
	origin, clone = filepath.Join(root, "origin.git"), filepath.Join(root, "clone")
	runGit(t, root, "init", "-q", "--bare", "-b", "main", origin)
	runGit(t, root, "clone", "-q", origin, clone)
	runGit(t, clone, "commit", "-q", "--allow-empty", "-m", "first")
	runGit(t, clone, "push", "-q", "-u", "origin", "main")
	return origin, clone
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func TestBranchReadsFollowWrites(t *testing.T) { // [ddgbd]
	origin, clone := gitTestRepo(t)
	other := filepath.Join(filepath.Dir(clone), "other")
	runGit(t, filepath.Dir(clone), "clone", "-q", origin, other)
	t.Chdir(clone)
	p, _, _ := testPrinter()
	a := newApp(p)
	if a.branchExistsRemote("feat") || a.branchExistsLocal("side") {
		t.Fatal("found branches that don't exist yet")
	}
	runGit(t, other, "push", "-q", "origin", "HEAD:refs/heads/feat")
	// Nothing in this run moved a ref yet, so the first answer stands.
	if a.branchExistsRemote("feat") {
		t.Error("the branch list was asked again with nothing moved")
	}
	a.fetchRemote()
	if !a.branchExistsRemote("feat") {
		t.Error("after the fetch, origin's new branch is still missing")
	}
	if err := a.step("git", "branch", "side"); err != nil {
		t.Fatal(err)
	}
	if !a.branchExistsLocal("side") {
		t.Error("after a step made it, the local branch is still missing")
	}
}

// The pull step names the upstream as git shortens it, and the plan reads the same
// name for a branch it checks out later, from origin's copy when there is no local one.
func TestUpstreamNames(t *testing.T) { // [ddgbe]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "push", "-q", "origin", "HEAD:refs/heads/far")
	runGit(t, clone, "branch", "-q", "lone")
	t.Chdir(clone)
	a := newApp(newPrinter())
	tests := []struct {
		branch string
		want   upstreamRef
	}{
		{"main", upstreamRef{"refs/remotes/origin/main", "origin/main"}},
		{"far", upstreamRef{"refs/remotes/origin/far", "origin/far"}},
		{"lone", upstreamRef{}},
		{"nowhere", upstreamRef{}},
	}
	for _, tc := range tests {
		if got := a.upstreamOf(tc.branch); got != tc.want {
			t.Errorf("upstreamOf(%q) = %v, want %v", tc.branch, got, tc.want)
		}
	}
	if got := a.upstream(); got != tests[0].want {
		t.Errorf("upstream() = %v, want %v", got, tests[0].want)
	}
}

// git shortens a ref as far as it stays unambiguous, so a tag sharing the short
// name made origin's default read as "remotes/origin/main", and an unborn one as
// "heads/main". The name comes from the full ref, whatever tags exist.
func TestDefaultBranchBesideSameNamedTag(t *testing.T) { // [ddgbx]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "remote", "set-head", "origin", "main")
	runGit(t, clone, "tag", "origin/main")
	t.Chdir(clone)
	if got := newApp(newPrinter()).defaultBranch(); got != "main" {
		t.Errorf("defaultBranch() beside tag origin/main = %q, want main", got)
	}

	unborn := filepath.Join(t.TempDir(), "unborn")
	runGit(t, filepath.Dir(unborn), "init", "-q", "-b", "trunkish", unborn)
	hash := exec.Command("git", "hash-object", "-w", "--stdin")
	hash.Dir = unborn
	blob, err := hash.Output()
	if err != nil {
		t.Fatal(err)
	}
	runGit(t, unborn, "tag", "trunkish", strings.TrimSpace(string(blob)))
	t.Chdir(unborn)
	if got := newApp(newPrinter()).defaultBranch(); got != "trunkish" {
		t.Errorf("unborn defaultBranch() beside tag trunkish = %q, want trunkish", got)
	}
}

// After '--' a br switch target can start with a dash, and 'git checkout -f' would
// run as the option. One that exists is refused like any other dash-led branch, and
// one that doesn't isn't offered as a br create line.
func TestSwitchTargetWithLeadingDash(t *testing.T) { // [df520]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "update-ref", "refs/heads/-f", "HEAD")
	runGit(t, clone, "push", "-q", "origin", "HEAD:refs/heads/-far")
	runGit(t, clone, "fetch", "-q")
	runGit(t, clone, "checkout", "-q", "-b", "work")
	t.Chdir(clone)
	for target, want := range map[string]string{
		"-f":   "reads it as an option",
		"-far": "reads it as an option",
		"-no":  "can't start with a dash",
		"main": "",
	} {
		_, cmd, _, err := parseArgs([]string{"br", "switch", "--", target})
		if err == nil {
			cmd, err = collapseCommand(cmd)
		}
		if err != nil {
			t.Fatalf("%q: parse: %v", target, err)
		}
		a := newApp(newPrinter())
		a.cmd = cmd
		err = a.preflightBranch()
		switch {
		case want == "" && err != nil:
			t.Errorf("%q: refused: %v", target, err)
		case want != "" && (err == nil || !strings.Contains(err.Error(), want)):
			t.Errorf("%q: got %v, want %q", target, err, want)
		case want != "" && strings.Contains(err.Error(), "br create"):
			t.Errorf("%q: suggests a br create line: %v", target, err)
		}
	}
}

// Before the first commit, br create and br hotfix off the branch HEAD names would
// only rename it, then fail the push. They refuse up front, unless the base is
// another branch that exists.
func TestUnbornBase(t *testing.T) { // [dfhjw]
	seeded, _ := gitTestRepo(t)
	root := t.TempDir()
	empty := filepath.Join(root, "empty.git")
	runGit(t, root, "init", "-q", "--bare", "-b", "main", empty)
	withDev := filepath.Join(root, "dev.git")
	runGit(t, root, "clone", "-q", "--bare", seeded, withDev)
	runGit(t, withDev, "branch", "dev", "main")
	tests := []struct {
		name, origin string
		args         []string
		want         string
	}{
		{"no origin", "", []string{"br", "create", "nb"}, "Make the first commit with: gitsby pullcom"},
		{"empty origin", empty, []string{"br", "create", "nb"}, "Publish the first commit with: gitsby repo connect"},
		{"hotfix, empty origin", empty, []string{"br", "hotfix", "hb"}, "nothing to start 'hotfix/hb' from"},
		{"origin has main", seeded, []string{"br", "hotfix", "hb"}, "no commits here yet, so there is nothing to start 'hotfix/hb' from. Origin has one"},
		{"origin has dev", withDev, []string{"br", "create", "nb"}, ""},
	}
	for i, tt := range tests {
		repo := filepath.Join(root, fmt.Sprint("r", i))
		runGit(t, root, "init", "-q", "-b", "main", repo)
		if tt.origin != "" {
			runGit(t, repo, "remote", "add", "origin", tt.origin)
			runGit(t, repo, "fetch", "-q", "origin")
		}
		t.Chdir(repo)
		_, cmd, _, err := parseArgs(tt.args)
		if err == nil {
			cmd, err = collapseCommand(cmd)
		}
		if err != nil {
			t.Fatalf("%s: parse: %v", tt.name, err)
		}
		a := newApp(newPrinter())
		a.cmd = cmd
		err = a.preflightBranch()
		switch {
		case tt.want == "" && err != nil:
			t.Errorf("%s: refused: %v", tt.name, err)
		case tt.want != "" && (err == nil || !strings.Contains(err.Error(), tt.want)):
			t.Errorf("%s: got %v, want %q", tt.name, err, tt.want)
		}
	}
}

// A single-branch or shallow clone fetches only one branch, so a missing origin/dev
// says nothing about origin. fetchSees reads the fetch refspecs git itself uses.
func TestFetchSees(t *testing.T) { // [dfh89]
	_, clone := gitTestRepo(t)
	t.Chdir(clone)
	tests := []struct {
		name    string
		specs   []string
		sees    map[string]bool
		seesAll bool
	}{
		{"clone default", []string{"+refs/heads/*:refs/remotes/origin/*"}, map[string]bool{"dev": true, "a/b": true}, true},
		{"single branch", []string{"+refs/heads/main:refs/remotes/origin/main"}, map[string]bool{"main": true, "dev": false}, false},
		{"set-branches main dev", []string{"+refs/heads/main:refs/remotes/origin/main", "+refs/heads/dev:refs/remotes/origin/dev"}, map[string]bool{"dev": true, "feat": false}, false},
		{"a negative refspec", []string{"+refs/heads/*:refs/remotes/origin/*", "^refs/heads/dev"}, map[string]bool{"dev": false, "feat": true}, true},
		{"a negative pattern", []string{"+refs/heads/*:refs/remotes/origin/*", "^refs/heads/tmp/*"}, map[string]bool{"tmp/x": false, "tmpx": true}, true},
		{"a pattern with a prefix", []string{"+refs/heads/feat/*:refs/remotes/origin/feat/*"}, map[string]bool{"feat/x": true, "feat": false, "dev": false}, false},
		{"mapped elsewhere", []string{"+refs/heads/*:refs/remotes/other/*"}, map[string]bool{"dev": false}, false},
		{"a mirror", []string{"+refs/*:refs/*"}, map[string]bool{"dev": false}, false},
		{"a short source", []string{"dev:refs/remotes/origin/dev"}, map[string]bool{"dev": true}, false},
		{"no refspec", nil, map[string]bool{"main": false}, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// --unset-all exits 5 with nothing to unset.
			_ = exec.Command("git", "-C", clone, "config", "--unset-all", "remote.origin.fetch").Run()
			for _, spec := range tc.specs {
				runGit(t, clone, "config", "--add", "remote.origin.fetch", spec)
			}
			a := newApp(newPrinter())
			for branch, want := range tc.sees {
				if got := a.fetchSees(branch); got != want {
					t.Errorf("fetchSees(%q) = %v, want %v", branch, got, want)
				}
			}
			if got := a.fetchSeesAll(); got != tc.seesAll {
				t.Errorf("fetchSeesAll() = %v, want %v", got, tc.seesAll)
			}
		})
	}
}

// The branch commands refuse in a narrowed clone where origin's dev, or its
// default branch, can't be seen, and run where it can.
func TestRefuseNarrowFetch(t *testing.T) { // [dfh8a]
	origin, clone := gitTestRepo(t)
	runGit(t, clone, "push", "-q", "origin", "HEAD:refs/heads/dev")
	root := filepath.Dir(clone)
	single := filepath.Join(root, "single")
	runGit(t, root, "clone", "-q", "--single-branch", "-b", "main", origin, single)
	devOnly := filepath.Join(root, "devonly")
	runGit(t, root, "clone", "-q", "--single-branch", "-b", "dev", origin, devOnly)
	tests := []struct{ name, dir, cmd, sub, want string }{
		{"full clone", clone, "br-merge", "", ""},
		{"single-branch br merge", single, "br-merge", "", "whether origin has a 'dev'"},
		{"single-branch br create", single, "br-create", "", "whether origin has a 'dev'"},
		{"single-branch br hotfix", single, "br-hotfix", "", "whether origin has a 'dev'"},
		{"single-branch br switch", single, "br-switch", "", "whether origin has a 'dev'"},
		{"single-branch br prune", single, "br-prune", "", "whether origin has a 'dev'"},
		{"single-branch release", single, "release", "", "whether origin has a 'dev'"},
		{"single-branch pr create", single, "pr", "create", "whether origin has a 'dev'"},
		{"single-branch pr ok", single, "pr", "ok", "whether origin has a 'dev'"},
		{"single-branch pr view only reads", single, "pr", "", ""},
		{"single-branch sync pushes only its branch", single, "sync", "", ""},
		{"single-branch pullcom", single, "pullcom", "", ""},
		{"dev only, no default branch to read", devOnly, "br-merge", "", "which branch is origin's default"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Chdir(tc.dir)
			a := newApp(newPrinter())
			a.cmd.name, a.pr.sub = tc.cmd, tc.sub
			err := a.refuseNarrowFetch()
			switch {
			case tc.want == "" && err != nil:
				t.Errorf("refused: %v", err)
			case tc.want != "" && (err == nil || !strings.Contains(err.Error(), tc.want) || !strings.Contains(err.Error(), "git remote set-branches origin")):
				t.Errorf("got %v, want %q and the set-branches fix", err, tc.want)
			}
		})
	}
	// Once dev is fetched too, only a new branch outside the fetch is refused.
	runGit(t, single, "remote", "set-branches", "--add", "origin", "dev")
	runGit(t, single, "fetch", "-q", "origin")
	t.Chdir(single)
	a := newApp(newPrinter())
	a.cmd.name = "br-create"
	if err := a.refuseNarrowFetch(); err != nil {
		t.Errorf("with dev fetched: refused: %v", err)
	}
	if err := a.checkNewBranchName("feat"); err == nil || !strings.Contains(err.Error(), "whether origin has a 'feat'") {
		t.Errorf("checkNewBranchName(feat) = %v, want the narrowed-fetch refusal", err)
	}
	a.cmd.name, a.cmd.arg = "br-switch", "feat"
	if err := a.preflightBranch(); err == nil || !strings.Contains(err.Error(), "whether origin has a 'feat'") {
		t.Errorf("br switch feat = %v, want the narrowed-fetch refusal", err)
	}
}

// git won't check out a branch another worktree has. Every command that checks
// one out asks before the plan, and the branch checked out here doesn't count.
func TestRefuseHeldBranch(t *testing.T) { // [dfh8b]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "branch", "-q", "dev")
	runGit(t, clone, "push", "-q", "-u", "origin", "dev")
	runGit(t, clone, "checkout", "-q", "dev")
	linked := filepath.Join(filepath.Dir(clone), "linked")
	runGit(t, clone, "worktree", "add", "-q", "-b", "w", linked, "dev")
	runGit(t, linked, "branch", "-q", "hotfix/h", "main")
	// pr ok moves off a branch that tracks the PR's own, or that tracks nothing.
	runGit(t, linked, "push", "-q", "-u", "origin", "w")
	runGit(t, linked, "branch", "-q", "solo", "w")
	// t.Chdir keeps the folder it left open until its test ends, and Windows
	// won't rename an open folder, so linked's cases get their own subtest.
	t.Run("from the linked worktree", func(t *testing.T) {
		t.Chdir(linked)
		tests := []struct{ name, branch, cmd, sub, arg, head, want string }{
			{"br merge", "w", "br-merge", "", "", "", "dev"},
			{"br switch", "w", "br-switch", "", "", "", "dev"},
			{"br switch to main", "w", "br-switch", "", "main", "", ""},
			{"br create", "w", "br-create", "", "next", "", "dev"},
			{"br hotfix", "w", "br-hotfix", "", "hotfix/x", "", ""},
			{"release", "w", "release", "", "", "", "dev"},
			{"pr ok of this branch", "w", "pr", "ok", "", "w", "dev"},
			{"pr ok of another branch", "w", "pr", "ok", "", "other", ""},
			{"pr ok from a branch with no upstream", "solo", "pr", "ok", "", "other", "dev"},
			{"pr create checks nothing out", "w", "pr", "create", "", "", ""},
			{"sync checks nothing out", "w", "sync", "", "", "", ""},
			{"a hotfix's back-merge", "hotfix/h", "br-merge", "", "", "", "dev"},
		}
		for _, tc := range tests {
			t.Run(tc.name, func(t *testing.T) {
				runGit(t, linked, "checkout", "-q", tc.branch)
				a := newApp(newPrinter())
				a.cmd.name, a.cmd.arg, a.pr.sub, a.pr.headBranch = tc.cmd, tc.arg, tc.sub, tc.head
				err := a.refuseHeldBranch()
				switch {
				case tc.want == "" && err != nil:
					t.Errorf("refused: %v", err)
				case tc.want != "" && (err == nil || !strings.Contains(err.Error(), "'"+tc.want+"' is checked out in another worktree")):
					t.Errorf("got %v, want %q named", err, tc.want)
				}
			})
		}
	})
	// From the main worktree, dev is its own, and w is the one held.
	runGit(t, linked, "checkout", "-q", "w")
	t.Chdir(clone)
	a := newApp(newPrinter())
	a.cmd.name, a.cmd.arg = "br-switch", "w"
	if err := a.refuseHeldBranch(); err == nil || !strings.Contains(err.Error(), "'w' is checked out") {
		t.Errorf("br switch w from the main worktree = %v, want w named", err)
	}
	a = newApp(newPrinter())
	a.cmd.name = "release"
	if err := a.refuseHeldBranch(); err != nil {
		t.Errorf("release on dev in the main worktree: refused: %v", err)
	}
	// A worktree folder deleted by hand still holds its branch, and prune frees it.
	if err := os.Rename(linked, linked+"-moved"); err != nil {
		t.Fatal(err)
	}
	a = newApp(newPrinter())
	a.cmd.name, a.cmd.arg = "br-switch", "w"
	if err := a.refuseHeldBranch(); err == nil || !strings.Contains(err.Error(), "git worktree prune") {
		t.Errorf("br switch w with its worktree folder gone = %v, want 'git worktree prune'", err)
	}
	runGit(t, clone, "worktree", "prune")
	a = newApp(newPrinter())
	a.cmd.name, a.cmd.arg = "br-switch", "w"
	if err := a.refuseHeldBranch(); err != nil {
		t.Errorf("br switch w after the prune: refused: %v", err)
	}
}

// prune passes over a locked worktree, so for one whose folder is gone the refusal
// names unlocking it first. An unlocked one with its folder gone still gets prune alone.
func TestRefuseHeldBranchLocked(t *testing.T) { // [dfkyp]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "branch", "-q", "dev")
	locked := filepath.Join(filepath.Dir(clone), "locked")
	plain := filepath.Join(filepath.Dir(clone), "plain")
	runGit(t, clone, "worktree", "add", "-q", locked, "dev")
	runGit(t, clone, "worktree", "add", "-q", "-b", "w", plain, "dev")
	runGit(t, clone, "worktree", "lock", locked)
	for _, dir := range []string{locked, plain} {
		if err := os.Rename(dir, dir+"-moved"); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(clone)
	ask := func(branch string) error {
		t.Helper()
		a := newApp(newPrinter())
		a.cmd = command{name: "br-switch", arg: branch, mutating: true}
		if err := a.enterRepo(); err != nil || a.worktreesDir == "" {
			t.Fatalf("enterRepo: worktreesDir %q, %v", a.worktreesDir, err)
		}
		return a.refuseHeldBranch()
	}
	if err := ask("dev"); err == nil || !strings.Contains(err.Error(), "git worktree unlock") {
		t.Errorf("br switch dev with its locked worktree's folder gone = %v, want 'git worktree unlock'", err)
	}
	if err := ask("w"); err == nil || strings.Contains(err.Error(), "unlock") || !strings.Contains(err.Error(), "git worktree prune") {
		t.Errorf("br switch w with its unlocked worktree's folder gone = %v, want prune alone", err)
	}
	runGit(t, clone, "worktree", "prune")
	if err := ask("dev"); err == nil {
		t.Error("br switch dev after a prune that skips the locked worktree: not refused")
	}
	runGit(t, clone, "worktree", "unlock", locked)
	runGit(t, clone, "worktree", "prune")
	if err := ask("dev"); err != nil {
		t.Errorf("br switch dev after unlock and prune: refused: %v", err)
	}
}

// git won't check out a branch another worktree is rebasing or bisecting either,
// though HEAD is detached there and %(worktreepath) doesn't name it. Each state is
// made by real git, read through enterRepo as a run reads it.
func TestRefuseBusyBranch(t *testing.T) { // [dfjzf]
	_, clone := gitTestRepo(t)
	commit := func(dir, body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, "f.txt"), []byte(body+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		runGit(t, dir, "add", "f.txt")
		runGit(t, dir, "commit", "-q", "-m", body)
	}
	mayFail := func(dir string, args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		_ = cmd.Run() // the stop is the point
	}
	runGit(t, clone, "checkout", "-q", "-b", "side")
	commit(clone, "side")
	runGit(t, clone, "checkout", "-q", "-b", "dev", "main")
	commit(clone, "d1")
	commit(clone, "d2")
	runGit(t, clone, "checkout", "-q", "main")
	linked := filepath.Join(filepath.Dir(clone), "linked")
	runGit(t, clone, "worktree", "add", "-q", linked, "dev")
	realLinked, _ := filepath.EvalSymlinks(linked)
	realClone, _ := filepath.EvalSymlinks(clone)
	sub := filepath.Join(clone, "sub")
	if err := os.MkdirAll(sub, 0o700); err != nil {
		t.Fatal(err)
	}
	// Each ask is a subtest, so its t.Chdir lets go of the folder it left when
	// the ask is done. Windows won't rename an open folder, as below.
	ask := func(from, branch string) (err error) {
		t.Helper()
		t.Run(filepath.Base(from), func(t *testing.T) {
			t.Chdir(from)
			a := newApp(newPrinter())
			a.cmd = command{name: "br-switch", arg: branch, mutating: true}
			if err := a.enterRepo(); err != nil || a.worktreesDir == "" {
				t.Fatalf("enterRepo from %s: worktreesDir %q, %v", from, a.worktreesDir, err)
			}
			err = a.refuseHeldBranch()
		})
		return err
	}
	want := func(state string, err error, what, folder string) {
		t.Helper()
		switch {
		case what == "" && err != nil:
			t.Errorf("%s: refused: %v", state, err)
		case what != "" && (err == nil || !strings.Contains(err.Error(), "'dev' is "+what+" in another worktree") || !strings.Contains(err.Error(), nativePath(folder))):
			t.Errorf("%s: got %v, want dev named as %s in %s", state, err, what, folder)
		}
	}
	mayFail(linked, "rebase", "side")
	want("rebase in a linked worktree", ask(clone, "dev"), "being rebased", realLinked)
	want("the same, from a subfolder", ask(sub, "dev"), "being rebased", realLinked)
	want("another branch", ask(clone, "side"), "", "")
	runGit(t, linked, "rebase", "--abort")
	runGit(t, linked, "checkout", "-q", "--detach")
	want("nothing stopped, dev free", ask(clone, "dev"), "", "")
	runGit(t, linked, "checkout", "-q", "dev")
	mayFail(linked, "rebase", "--apply", "side")
	want("apply rebase", ask(clone, "dev"), "being rebased", realLinked)
	runGit(t, linked, "rebase", "--abort")
	runGit(t, linked, "bisect", "start", "dev", "main")
	want("bisect", ask(clone, "dev"), "being bisected", realLinked)
	runGit(t, linked, "bisect", "reset")
	// An am holds no branch, so git checks dev out and so does gitsby.
	runGit(t, linked, "checkout", "-q", "--detach")
	runGit(t, linked, "format-patch", "-q", "-o", "../p", "main..side")
	mayFail(linked, "am", "../p/0001-side.patch")
	want("am in a linked worktree", ask(clone, "dev"), "", "")
	runGit(t, linked, "am", "--abort")
	// The main worktree rebasing dev, asked from the linked one.
	runGit(t, clone, "checkout", "-q", "dev")
	mayFail(clone, "rebase", "side")
	want("rebase in the main worktree", ask(linked, "dev"), "being rebased", realClone)
	runGit(t, clone, "rebase", "--abort")
	runGit(t, clone, "checkout", "-q", "main")
	// A worktree folder deleted by hand mid-rebase still holds dev, and prune frees it.
	runGit(t, linked, "checkout", "-q", "dev")
	mayFail(linked, "rebase", "side")
	if err := os.Rename(linked, linked+"-moved"); err != nil {
		t.Fatal(err)
	}
	if err := ask(clone, "dev"); err == nil || !strings.Contains(err.Error(), "git worktree prune") {
		t.Errorf("rebasing worktree's folder gone = %v, want 'git worktree prune'", err)
	}
	runGit(t, clone, "worktree", "prune")
	want("after the prune", ask(clone, "dev"), "", "")
}
