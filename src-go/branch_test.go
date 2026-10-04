// The branch list is read once per run, so what moves a ref has to drop it: a
// step through the runners, and the fetch, which is not a step.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"path/filepath"
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

func TestBranchReadsFollowWrites(t *testing.T) { // [Erl1x2z]
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
func TestUpstreamNames(t *testing.T) { // [Erl1x3E]
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
