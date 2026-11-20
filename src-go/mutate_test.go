// Which pull step a branch gets. The fetch at the start of a command covers
// origin only, so only an upstream there, or a local one, can skip the second
// round trip.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"cmp"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

func TestPullArgsFor(t *testing.T) { // [ddf65]
	tests := []struct {
		upstream upstreamRef
		extra    []string
		want     []string
	}{
		{upstreamRef{"refs/remotes/origin/main", "origin/main"}, nil, []string{"merge", "--ff-only", "origin/main"}},
		{upstreamRef{"refs/remotes/origin/feat/x", "origin/feat/x"}, []string{"--autostash"}, []string{"merge", "--ff-only", "--autostash", "origin/feat/x"}},
		{upstreamRef{"refs/remotes/origin/main", "remotes/origin/main"}, nil, []string{"merge", "--ff-only", "remotes/origin/main"}},
		{upstreamRef{"refs/heads/main", "main"}, nil, []string{"merge", "--ff-only", "main"}},
		{upstreamRef{"refs/heads/-x", "-x"}, nil, []string{"merge", "--ff-only", "refs/heads/-x"}},
		{upstreamRef{}, []string{"--autostash"}, []string{"merge", "--ff-only", "--autostash", "@{u}"}},
		{upstreamRef{"refs/remotes/up/main", "up/main"}, nil, []string{"pull", "--ff-only"}},
		{upstreamRef{"refs/remotes/origin2/main", "origin2/main"}, []string{"--autostash"}, []string{"pull", "--ff-only", "--autostash"}},
	}
	for _, tc := range tests {
		if got := pullArgsFor(tc.upstream, tc.extra...); !slices.Equal(got, tc.want) {
			t.Errorf("pullArgsFor(%v, %q) = %q, want %q", tc.upstream, tc.extra, got, tc.want)
		}
	}
}

// The push names the branch and where it goes, read the way a bare push would
// read it, so no push.default or push refspec can add another branch to it. A nil
// want is a push git would refuse.
func TestPushArgs(t *testing.T) { // [df52f]
	origin, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	runGit(t, clone, "push", "-q", "origin", "feat:up")
	runGit(t, clone, "remote", "add", "fork", origin)
	runGit(t, clone, "remote", "add", "--", "--all", origin)
	runGit(t, clone, "branch", "-q", "lone")
	t.Chdir(clone)
	tests := []struct {
		name   string
		config [][2]string
		branch string
		want   []string
	}{
		{"plain", nil, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		{"matching", [][2]string{{"push.default", "matching"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		{"nothing", [][2]string{{"push.default", "nothing"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		{"refspec for every branch", [][2]string{{"remote.origin.push", "+refs/*:refs/*"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		{"refspec that renames", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/heads/other"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/other"}},
		{"refspec for another branch", [][2]string{{"remote.origin.push", "refs/heads/main:refs/heads/main"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		// A branch made from origin/main tracks it. simple, git's default, refuses
		// that push rather than send it to the upstream.
		{"upstream by another name", [][2]string{{"branch.feat.merge", "refs/heads/up"}}, "feat", nil},
		{"upstream by another name, simple", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "simple"}}, "feat", nil},
		{"upstream by another name, upstream", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "upstream"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/up"}},
		{"upstream by another name, tracking", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "tracking"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/up"}},
		{"upstream by another name, nothing", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "nothing"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/up"}},
		{"upstream by another name, current", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "current"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		{"upstream by another name, matching", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "matching"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/feat"}},
		{"upstream by another name, push remote", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"branch.feat.pushRemote", "fork"}}, "feat", []string{"push", "fork", "HEAD:refs/heads/feat"}},
		{"upstream by another name, refspec", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"remote.origin.push", "refs/heads/feat:refs/heads/other"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/other"}},
		{"push remote", [][2]string{{"branch.feat.pushRemote", "fork"}}, "feat", []string{"push", "fork", "HEAD:refs/heads/feat"}},
		{"push remote that reads as an option", [][2]string{{"remote.pushDefault", "--all"}}, "feat", []string{"push", "--", "--all", "HEAD:refs/heads/feat"}},
		{"no upstream", nil, "lone", []string{"push", "-u", "origin", "HEAD"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runGit(t, clone, "checkout", "-q", tc.branch)
			for _, kv := range tc.config {
				runGit(t, clone, "config", kv[0], kv[1])
			}
			a := newApp(newPrinter())
			got, err := a.pushArgs()
			for _, kv := range tc.config {
				runGit(t, clone, "config", "--unset", kv[0])
			}
			runGit(t, clone, "config", "branch.feat.merge", "refs/heads/feat")
			if !slices.Equal(got, tc.want) || (err != nil) != (tc.want == nil) {
				t.Errorf("pushArgs() = %q, %v, want %q", got, err, tc.want)
			}
		})
	}
}

// pr create names the branch on origin its park push sends the work to, and refuses
// where that isn't one, since the PR opens on origin. An empty want is a refusal.
func TestPrCreateHead(t *testing.T) { // [dfh76]
	origin, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	runGit(t, clone, "push", "-q", "origin", "feat:up")
	runGit(t, clone, "remote", "add", "second", origin)
	runGit(t, clone, "fetch", "-q", "second")
	runGit(t, clone, "branch", "-q", "lone")
	t.Chdir(clone)
	tests := []struct {
		name   string
		config [][2]string
		branch string
		want   string
	}{
		{"plain", nil, "feat", "feat"},
		{"no upstream", nil, "lone", "lone"},
		{"upstream by another name", [][2]string{{"branch.feat.merge", "refs/heads/up"}}, "feat", ""},
		{"upstream by another name, upstream", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "upstream"}}, "feat", "up"},
		{"upstream by another name, current", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "current"}}, "feat", "feat"},
		{"refspec that renames", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/heads/other"}}, "feat", "other"},
		{"refspec to a ref that isn't a branch", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/for/main"}}, "feat", ""},
		{"tracks main, upstream", [][2]string{{"branch.feat.merge", "refs/heads/main"}, {"push.default", "upstream"}}, "feat", ""},
		{"upstream on another remote", [][2]string{{"branch.feat.remote", "second"}}, "feat", ""},
		{"push remote", [][2]string{{"branch.feat.pushRemote", "second"}}, "feat", ""},
		{"push default", [][2]string{{"remote.pushDefault", "second"}}, "feat", ""},
		{"push remote, no upstream", [][2]string{{"remote.pushDefault", "second"}}, "lone", "lone"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runGit(t, clone, "checkout", "-q", tc.branch)
			for _, kv := range tc.config {
				runGit(t, clone, "config", kv[0], kv[1])
			}
			a := newApp(newPrinter())
			got, err := a.prCreateHead(tc.branch)
			for _, kv := range tc.config {
				runGit(t, clone, "config", "--unset", kv[0])
			}
			runGit(t, clone, "config", "branch.feat.remote", "origin")
			runGit(t, clone, "config", "branch.feat.merge", "refs/heads/feat")
			if got != tc.want || (err != nil) != (tc.want == "") {
				t.Errorf("prCreateHead() = %q, %v, want %q", got, err, tc.want)
			}
		})
	}
}

// br merge deletes origin's copy of what it merged, which is where the park push
// went. A head on dev would have it delete dev.
func TestMergeHead(t *testing.T) { // [dfhg7]
	origin, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	runGit(t, clone, "push", "-q", "origin", "feat:up", "feat:dev")
	runGit(t, clone, "remote", "add", "second", origin)
	runGit(t, clone, "fetch", "-q", "second")
	t.Chdir(clone)
	tests := []struct {
		name    string
		config  [][2]string
		want    string
		refusal string
	}{
		{"plain", nil, "feat", ""},
		{"upstream by another name", [][2]string{{"branch.feat.merge", "refs/heads/up"}}, "", "push.default=simple"},
		{"upstream by another name, upstream", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "upstream"}}, "up", ""},
		{"refspec that renames", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/heads/other"}}, "other", ""},
		{"refspec to a ref that isn't a branch", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/for/main"}}, "", "br merge can delete"},
		{"tracks dev, upstream", [][2]string{{"branch.feat.merge", "refs/heads/dev"}, {"push.default", "upstream"}}, "", "delete origin's 'dev'"},
		{"upstream on another remote", [][2]string{{"branch.feat.remote", "second"}}, "", "remote 'second'"},
		{"push remote", [][2]string{{"branch.feat.pushRemote", "second"}}, "", "remote 'second'"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			for _, kv := range tc.config {
				runGit(t, clone, "config", kv[0], kv[1])
			}
			a := newApp(newPrinter())
			a.cmd.name = "br-merge"
			got, err := a.parkHead("feat")
			head := a.mergeHead()
			for _, kv := range tc.config {
				runGit(t, clone, "config", "--unset", kv[0])
			}
			runGit(t, clone, "config", "branch.feat.remote", "origin")
			runGit(t, clone, "config", "branch.feat.merge", "refs/heads/feat")
			if got != tc.want || (err != nil) != (tc.refusal != "") || (err != nil && !strings.Contains(err.Error(), tc.refusal)) {
				t.Errorf("parkHead() = %q, %v, want %q, %q", got, err, tc.want, tc.refusal)
			}
			if want := cmp.Or(tc.want, "feat"); head != want {
				t.Errorf("mergeHead() = %q, want %q", head, want)
			}
		})
	}
}

// Commits made on the branch br merge pushes, the target or the hotfix back-merge's
// dev, are what sync there asks --direct for. A merge isn't one, and neither is a
// target with no upstream, which goes up as a first publish.
func TestMergePushesOwn(t *testing.T) { // [dfhg8]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "dev")
	runGit(t, clone, "push", "-q", "-u", "origin", "dev")
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "checkout", "-q", "-b", "hotfix/x", "main")
	t.Chdir(clone)
	onDev := func(args ...string) {
		runGit(t, clone, "checkout", "-q", "dev")
		runGit(t, clone, args...)
		runGit(t, clone, "checkout", "-q", "feat")
	}
	check := func(name, branch, cmd, sub, head, want string) {
		t.Run(name, func(t *testing.T) {
			runGit(t, clone, "checkout", "-q", branch)
			a := newApp(newPrinter())
			a.cmd.name = cmd
			a.pr.sub, a.pr.headBranch = sub, head
			if got := a.mergePushesOwn(); got != want {
				t.Errorf("mergePushesOwn() = %q, want %q", got, want)
			}
		})
	}
	check("level", "feat", "br-merge", "", "", "")
	check("level, pr ok of a hotfix", "feat", "pr", "ok", "hotfix/x", "")
	onDev("commit", "-q", "--allow-empty", "-m", "direct")
	check("own commit", "feat", "br-merge", "", "", "dev")
	check("own commit, back-merge", "hotfix/x", "br-merge", "", "", "dev")
	check("own commit, pr ok of a hotfix", "feat", "pr", "ok", "hotfix/x", "dev")
	check("own commit, pr ok of a feature", "feat", "pr", "ok", "feat", "")
	check("own commit, sync", "feat", "sync", "", "", "")
	onDev("reset", "-q", "--hard", "origin/dev")
	runGit(t, clone, "checkout", "-q", "-b", "side", "dev")
	runGit(t, clone, "commit", "-q", "--allow-empty", "-m", "side")
	onDev("merge", "-q", "--no-ff", "side", "-m", "merge side")
	check("merge only", "feat", "br-merge", "", "", "")
	onDev("branch", "-q", "--unset-upstream")
	onDev("commit", "-q", "--allow-empty", "-m", "unpublished")
	check("no upstream", "feat", "br-merge", "", "", "")
}

// A branch origin deleted, once a fetch prunes its ref, still has its upstream set,
// and git reads that as none. A park push would publish it again under the old
// name, so it has to be seen as gone rather than as never pushed.
func TestGoneUpstream(t *testing.T) { // [dfgxm]
	origin, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	runGit(t, clone, "branch", "-q", "lone")
	runGit(t, clone, "branch", "-q", "--track", "local", "lone")
	t.Chdir(clone)
	tests := []struct {
		name, branch, cmd, wantGone, wantPush string
	}{
		{"upstream still there", "feat", "sync", "", ""},
		{"never pushed", "lone", "sync", "", ""},
		{"local upstream", "local", "sync", "", ""},
	}
	check := func(tc struct{ name, branch, cmd, wantGone, wantPush string }) {
		t.Run(tc.name, func(t *testing.T) {
			runGit(t, clone, "checkout", "-q", tc.branch)
			a := newApp(newPrinter())
			a.cmd.name = tc.cmd
			if got := a.goneUpstream(); got != tc.wantGone {
				t.Errorf("goneUpstream() = %q, want %q", got, tc.wantGone)
			}
			if got := a.pushesGoneBranch(); got != tc.wantPush {
				t.Errorf("pushesGoneBranch() = %q, want %q", got, tc.wantPush)
			}
		})
	}
	for _, tc := range tests {
		check(tc)
	}
	runGit(t, origin, "branch", "-q", "-D", "feat")
	runGit(t, clone, "fetch", "-q", "--prune", "origin")
	runGit(t, clone, "branch", "-q", "-D", "lone")
	for _, tc := range []struct{ name, branch, cmd, wantGone, wantPush string }{
		{"deleted on origin", "feat", "sync", "origin/feat", "origin/feat"},
		{"deleted on origin, br switch parks it", "feat", "br-switch", "origin/feat", "origin/feat"},
		{"deleted on origin, pr create needs it there", "feat", "pr", "origin/feat", ""},
		{"deleted on origin, br create parks it", "feat", "br-create", "origin/feat", "origin/feat"},
		{"deleted on origin, br hotfix parks it", "feat", "br-hotfix", "origin/feat", "origin/feat"},
		{"deleted on origin, release parks it", "feat", "release", "origin/feat", "origin/feat"},
		{"deleted on origin, br merge deletes it again", "feat", "br-merge", "origin/feat", ""},
		{"local upstream deleted", "local", "sync", "", ""},
	} {
		check(tc)
	}
}

// status.showUntrackedFiles=no hides untracked files from status, but not from
// 'git add --all', so a check that read status let them be committed and pushed.
func TestTreeDirtyUntrackedHidden(t *testing.T) { // [dfh4g]
	_, clone := gitTestRepo(t)
	t.Chdir(clone)
	if err := os.WriteFile(filepath.Join(clone, "new.txt"), []byte("n\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{"no", "false", "normal", "all"} {
		runGit(t, clone, "config", "status.showUntrackedFiles", value)
		a := newApp(newPrinter())
		if !treeDirty() || !a.commitPending() {
			t.Errorf("status.showUntrackedFiles=%s: treeDirty() = %v, commitPending() = %v, want both true", value, treeDirty(), a.commitPending())
		}
	}
}

// Every git status a check or the plan reads says which untracked files it wants,
// so the user's status.showUntrackedFiles can't hide one that add will take.
func TestStatusNamesUntracked(t *testing.T) { // [dfh4h]
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) < 10 {
		t.Fatalf("found %d sources: %v", len(files), err)
	}
	call := regexp.MustCompile(`"git",\s*"status"`)
	found := 0
	for _, file := range files {
		if strings.HasSuffix(file, "_test.go") {
			continue
		}
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for i, line := range strings.Split(string(src), "\n") {
			if !call.MatchString(line) {
				continue
			}
			found++
			if !strings.Contains(line, `"--untracked-files=`) {
				t.Errorf("%s:%d runs git status without --untracked-files: %s", file, i+1, strings.TrimSpace(line))
			}
		}
	}
	if found < 4 {
		t.Errorf("found %d git status calls, want at least 4; the pattern no longer matches the source", found)
	}
}

// A stopped am, pick, revert, merge, rebase or bisect was finished under gitsby's
// message, or left for its --continue to apply onto the branch gitsby switched to.
// Each state is made by real git, and named before anything else runs.
func TestPendingOpNamed(t *testing.T) { // [dfh53]
	write := func(dir, name, body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	// src holds 2 commits, the first clashing with work's.
	stopped := func() string {
		_, clone := gitTestRepo(t)
		write(clone, "f.txt", "base\n")
		runGit(t, clone, "add", "f.txt")
		runGit(t, clone, "commit", "-q", "-m", "base")
		runGit(t, clone, "checkout", "-q", "-b", "src")
		write(clone, "f.txt", "src\n")
		runGit(t, clone, "commit", "-q", "-am", "c1")
		write(clone, "g.txt", "g\n")
		runGit(t, clone, "add", "g.txt")
		runGit(t, clone, "commit", "-q", "-m", "c2")
		runGit(t, clone, "checkout", "-q", "-b", "work", "src~2")
		write(clone, "f.txt", "work\n")
		runGit(t, clone, "commit", "-q", "-am", "w")
		return clone
	}
	mayFail := func(dir string, args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		_ = cmd.Run() // the stop is the point
	}
	resolve := func(dir string) {
		write(dir, "f.txt", "x\n")
		runGit(t, dir, "add", "f.txt")
	}
	cases := []struct {
		state, want string
		setup       func(dir string)
	}{
		{"nothing stopped", "", func(string) {}},
		{"resolved merge", "merge", func(d string) { mayFail(d, "merge", "src"); resolve(d) }},
		{"stopped am", "am", func(d string) {
			runGit(t, d, "format-patch", "-q", "-o", "../p", "src~2..src")
			mayFail(d, "am", "../p/0001-c1.patch", "../p/0002-c2.patch")
		}},
		{"resolved am -3", "am", func(d string) {
			runGit(t, d, "format-patch", "-q", "-o", "../p", "src~2..src")
			mayFail(d, "am", "-3", "../p/0001-c1.patch", "../p/0002-c2.patch")
			resolve(d)
		}},
		{"resolved range pick", "cherry-pick", func(d string) { mayFail(d, "cherry-pick", "src~2..src"); resolve(d) }},
		{"range pick, pick 1 committed by hand", "cherry-pick", func(d string) {
			mayFail(d, "cherry-pick", "src~2..src")
			resolve(d)
			runGit(t, d, "commit", "-q", "-m", "pick1")
		}},
		{"range revert, revert 1 committed by hand", "revert", func(d string) {
			runGit(t, d, "checkout", "-q", "-b", "rv", "src")
			write(d, "f.txt", "y\n")
			runGit(t, d, "commit", "-q", "-am", "y")
			mayFail(d, "revert", "--no-edit", "src~1", "src")
			resolve(d)
			runGit(t, d, "commit", "-q", "-m", "rv1")
		}},
		{"rebase", "rebase", func(d string) { mayFail(d, "rebase", "src") }},
		{"apply rebase", "rebase", func(d string) { mayFail(d, "rebase", "--apply", "src") }},
		{"bisect without checkout", "bisect", func(d string) { runGit(t, d, "bisect", "start", "--no-checkout", "work", "src~2") }},
	}
	for _, tc := range cases {
		dir := stopped()
		tc.setup(dir)
		// From a subfolder, where rev-parse answers with relative paths.
		sub := filepath.Join(dir, "sub")
		if err := os.MkdirAll(sub, 0o700); err != nil {
			t.Fatal(err)
		}
		t.Chdir(sub)
		a := newApp(newPrinter())
		a.cmd = command{name: "pullcom", mutating: true}
		if err := a.enterRepo(); err != nil || !a.inRepo || len(a.opPaths) != len(opFiles) {
			t.Fatalf("%s: enterRepo: inRepo %v, %d op paths, %v", tc.state, a.inRepo, len(a.opPaths), err)
		}
		op, found := pendingOp(a.opPaths)
		if op.name != tc.want || found != (tc.want != "") {
			t.Errorf("%s: pendingOp = %q, %v, want %q", tc.state, op.name, found, tc.want)
		}
		err := a.refusePendingOp()
		switch {
		case tc.want == "" && err != nil:
			t.Errorf("%s: refused: %v", tc.state, err)
		case tc.want != "" && (err == nil || !strings.Contains(err.Error(), "A 'git "+tc.want+"' is in progress here.")):
			t.Errorf("%s: refusePendingOp = %v, want it to name git %s", tc.state, err, tc.want)
		}
		// Reading the state is how you see what to do about it.
		a.cmd = command{name: "status"}
		if err := a.refusePendingOp(); err != nil {
			t.Errorf("%s: status refused: %v", tc.state, err)
		}
	}
}
