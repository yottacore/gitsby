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

// The plan's push line names where the step sends it: the remote when it isn't
// origin, and the branch when it isn't the current one's name. Checked against the
// step's own arguments, so the two can't drift. An empty want is a push git would
// refuse, which names only the branch, since nothing goes.
func TestPlannedPushDisp(t *testing.T) { // [dfk0y]
	origin, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	runGit(t, clone, "push", "-q", "origin", "feat:up")
	runGit(t, clone, "remote", "add", "fork", origin)
	runGit(t, clone, "fetch", "-q", "fork")
	runGit(t, clone, "branch", "-q", "lone")
	t.Chdir(clone)
	tests := []struct {
		name   string
		config [][2]string
		branch string
		want   string
	}{
		{"plain", nil, "feat", "git push (branch 'feat') *"},
		{"no upstream", nil, "lone", "git push (branch 'lone') *"},
		{"no upstream, push remote", [][2]string{{"remote.pushDefault", "fork"}}, "lone", "git push (branch 'lone') *"},
		{"push remote", [][2]string{{"branch.feat.pushRemote", "fork"}}, "feat", "git push (branch 'feat', to 'feat' on 'fork') *"},
		{"upstream on another remote", [][2]string{{"branch.feat.remote", "fork"}}, "feat", "git push (branch 'feat', to 'feat' on 'fork') *"},
		{"upstream by another name, upstream", [][2]string{{"branch.feat.merge", "refs/heads/up"}, {"push.default", "upstream"}}, "feat", "git push (branch 'feat', to 'up') *"},
		{"upstream by another name, simple", [][2]string{{"branch.feat.merge", "refs/heads/up"}}, "feat", ""},
		{"refspec that renames", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/heads/other"}}, "feat", "git push (branch 'feat', to 'other') *"},
		{"refspec to a ref that isn't a branch", [][2]string{{"remote.origin.push", "refs/heads/feat:refs/for/main"}}, "feat", "git push (branch 'feat', to 'refs/for/main') *"},
		{"push remote and a renaming refspec", [][2]string{{"branch.feat.pushRemote", "fork"}, {"remote.fork.push", "refs/heads/feat:refs/heads/other"}}, "feat", "git push (branch 'feat', to 'other' on 'fork') *"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runGit(t, clone, "checkout", "-q", tc.branch)
			for _, kv := range tc.config {
				runGit(t, clone, "config", kv[0], kv[1])
			}
			a := newApp(newPrinter())
			p := a.currentPush("park")
			args, err := a.pushArgs()
			for _, kv := range tc.config {
				runGit(t, clone, "config", "--unset", kv[0])
			}
			runGit(t, clone, "config", "branch.feat.remote", "origin")
			runGit(t, clone, "config", "branch.feat.merge", "refs/heads/feat")
			if tc.want == "" {
				// preflight refused what it could, so the step's refusal comes after a
				// commit, a merge or a tag.
				if err == nil || strings.Contains(err.Error(), "Nothing was done") || p.disp() != "git push (branch 'feat') *" {
					t.Errorf("disp() = %q, pushArgs() = %q, %v, want a refusal that doesn't say nothing was done", p.disp(), args, err)
				}
				return
			}
			if got := p.disp(); got != tc.want || err != nil {
				t.Errorf("disp() = %q, %v, want %q", got, err, tc.want)
			}
			// What the step sends, read off its arguments.
			remote, target := "origin", tc.branch
			if !slices.Contains(args, "-u") {
				remote, target = args[len(args)-2], strings.TrimPrefix(strings.TrimPrefix(args[len(args)-1], "HEAD:"), "refs/heads/")
			}
			named := ""
			switch {
			case remote != "origin":
				named = ", to '" + target + "' on '" + remote + "'"
			case target != tc.branch:
				named = ", to '" + target + "'"
			}
			if p.disp() != "git push (branch '"+tc.branch+"'"+named+") *" {
				t.Errorf("disp() = %q, but the step is git %q", p.disp(), args)
			}
		})
	}
}

// Every mutating command that pushes the branch it stands on lists that push in
// plannedPushes, which the guards before the plan read. One left out commits and
// then has git refuse the push, as release and repo connect did. noPush is the
// rest, so a new command fails here until it's put on one side.
func TestPlannedPushesEveryCommand(t *testing.T) { // [dfk0z]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "feat")
	runGit(t, clone, "push", "-q", "-u", "origin", "feat")
	t.Chdir(clone)
	want := map[string]string{"sync": "park", "br-switch": "park", "br-create": "park", "br-hotfix": "park", "br-merge": "park", "pr create": "park", "release": "park", "repo-create": "connect", "repo-connect": "connect"}
	noPush := map[string]bool{"pullcom": true, "br-prune": true, "pr ok": true, "repo-clone": true, "repo-url": true, "account-apply": true, "account-set": true, "account-unset": true}
	seen := map[string]bool{}
	for _, u := range usages {
		if u.cmd == "raw" {
			continue
		}
		var cmd command
		settled := false
		for _, tail := range [][]string{nil, {"ssh"}, {"x", "y"}, {"x", "y", "z"}} {
			opt, got, _, err := parseArgs(append(strings.Fields(u.cmd), tail...))
			if err == nil {
				if got, err = collapseCommand(got); err == nil {
					got, err = sortCommand(got, &opt)
				}
			}
			if err == nil && (!settled || got.mutating) {
				cmd, settled = got, true
			}
			if settled && cmd.mutating {
				break
			}
		}
		if !settled || !cmd.mutating {
			continue
		}
		key := cmd.name
		a := newApp(newPrinter())
		a.cmd = cmd
		if cmd.name == "pr" {
			a.pr.sub = strings.Fields(u.cmd)[1]
			key += " " + a.pr.sub
		}
		if seen[key] {
			continue
		}
		seen[key] = true
		if err := a.enterRepo(); err != nil {
			t.Fatal(err)
		}
		// repo create and connect settle this after preflight. An origin already set
		// is the push case.
		a.tgt.connectMode = "push"
		var kinds []string
		for _, p := range a.plannedPushes() {
			kinds = append(kinds, p.kind)
		}
		switch {
		case want[key] != "" && !slices.Equal(kinds, []string{want[key]}):
			t.Errorf("%s: plannedPushes kinds = %q, want %q", key, kinds, want[key])
		case want[key] == "" && !noPush[key]:
			t.Errorf("%s: a mutating command in neither list; say whether it pushes the current branch", key)
		case want[key] == "" && len(kinds) > 0:
			t.Errorf("%s: plannedPushes kinds = %q, want none", key, kinds)
		}
	}
	for key := range want {
		if !seen[key] {
			t.Errorf("%s: no longer settles from usages", key)
		}
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
		if !a.treeDirty() || !a.commitPending() {
			t.Errorf("status.showUntrackedFiles=%s: treeDirty() = %v, commitPending() = %v, want both true", value, a.treeDirty(), a.commitPending())
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
	call := regexp.MustCompile(`"git",\s*("-c",\s*"[^"]*",\s*)*"status"`)
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

// diff.relative cut every git diff to the folder gitsby ran from, and a textconv
// driver whose output didn't change hid a staged edit from --quiet. So from sub/ an
// autostash conflict outside it went unseen and its markers were committed, and an
// edit staged outside it was "Nothing to commit".
func TestDiffReadsIgnoreDiffConfig(t *testing.T) { // [dfjwf]
	_, clone := gitTestRepo(t)
	write := func(name, body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(clone, name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(filepath.Join(clone, "sub"), 0o750); err != nil {
		t.Fatal(err)
	}
	write("f.txt", "base\n")
	write("sub/s.txt", "s\n")
	runGit(t, clone, "add", "f.txt", "sub/s.txt")
	runGit(t, clone, "commit", "-q", "-m", "base")
	runGit(t, clone, "config", "diff.relative", "true")
	runGit(t, clone, "config", "diff.same.textconv", "echo same <")
	write(".git/info/attributes", "f.txt diff=same\n")
	t.Chdir(filepath.Join(clone, "sub"))

	write("f.txt", "staged\n")
	runGit(t, clone, "add", "f.txt")
	a := newApp(newPrinter())
	a.opt.staged = true
	if !indexDiffers() || !a.commitPending() {
		t.Errorf("an edit staged outside sub/: indexDiffers() = %v, commitPending() = %v, want both true", indexDiffers(), a.commitPending())
	}
	if got := changedPaths("--cached", "HEAD"); !slices.Contains(got, "f.txt") {
		t.Errorf("changedPaths(--cached HEAD) = %q, want f.txt in it", got)
	}
	if got := changedPaths("HEAD"); !slices.Contains(got, "f.txt") {
		t.Errorf("changedPaths(HEAD) = %q, want f.txt in it", got)
	}

	// A real conflict on f.txt, outside the folder this runs from.
	runGit(t, clone, "commit", "-q", "-m", "ours")
	runGit(t, clone, "checkout", "-q", "-b", "other", "HEAD~1")
	write("f.txt", "theirs\n")
	runGit(t, clone, "commit", "-q", "-am", "theirs")
	runGit(t, clone, "checkout", "-q", "main")
	merge := exec.Command("git", "merge", "-q", "other")
	merge.Dir = clone
	if merge.Run() == nil {
		t.Fatal("the merge didn't conflict")
	}
	a = newApp(newPrinter())
	if err := a.refuseConflicts("nothing was committed", "gitsby sync"); err == nil {
		t.Error("refuseConflicts saw no conflict outside sub/")
	}
}

// diff.ignoreSubmodules=all hid a submodule moved to another commit from git diff,
// though 'git add --all' stages it and git commit takes it, so the commit step said
// "Nothing to commit." and left it staged.
func TestDiffReadsSeeSubmoduleMove(t *testing.T) { // [dfjwh]
	origin, clone := gitTestRepo(t)
	child := filepath.Join(filepath.Dir(origin), "child")
	runGit(t, filepath.Dir(origin), "init", "-q", "-b", "main", child)
	runGit(t, child, "commit", "-q", "--allow-empty", "-m", "c1")
	runGit(t, clone, "-c", "protocol.file.allow=always", "submodule", "-q", "add", child, "child")
	runGit(t, clone, "commit", "-q", "-m", "add child")
	runGit(t, filepath.Join(clone, "child"), "commit", "-q", "--allow-empty", "-m", "c2")
	runGit(t, clone, "config", "diff.ignoreSubmodules", "all")
	runGit(t, clone, "add", "child")
	t.Chdir(clone)
	if !indexDiffers() {
		t.Error("indexDiffers() = false with the submodule's move staged")
	}
	if got := changedPaths("--cached", "HEAD"); !slices.Contains(got, "child") {
		t.Errorf("changedPaths(--cached HEAD) = %q, want child in it", got)
	}
	// The sparse check's own --ignore-submodules=dirty still wins over the helper's.
	if err := os.WriteFile(filepath.Join(clone, "child", "dirt.txt"), []byte("d\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	runGit(t, clone, "reset", "-q")
	runGit(t, filepath.Join(clone, "child"), "reset", "-q", "--hard", "HEAD~1")
	if got := changedPaths("--ignore-submodules=dirty"); len(got) != 0 {
		t.Errorf("changedPaths(--ignore-submodules=dirty) = %q with only untracked files in the submodule, want none", got)
	}
}

// Every git diff read in src-go goes through diffArgs, so no new one can come back
// blind to the conflict or the edit [dfjwf] makes.
func TestDiffReadsUseDiffArgs(t *testing.T) { // [dfjwg]
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) < 10 {
		t.Fatalf("found %d sources: %v", len(files), err)
	}
	call := regexp.MustCompile(`("git",\s*|\[\]string\{)"diff"`)
	helper, found := 0, 0
	for _, file := range files {
		if strings.HasSuffix(file, "_test.go") {
			continue
		}
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for i, line := range strings.Split(string(src), "\n") {
			if strings.Contains(line, "diffArgs(") && !strings.Contains(line, "func diffArgs(") {
				found++
			}
			if !call.MatchString(line) {
				continue
			}
			if strings.Contains(line, `"diff", "--no-relative", "--no-textconv", "--no-ext-diff", "--ignore-submodules=none"`) {
				helper++
				continue
			}
			t.Errorf("%s:%d runs git diff without diffArgs: %s", file, i+1, strings.TrimSpace(line))
		}
	}
	if helper != 1 {
		t.Errorf("found %d diffArgs bodies, want 1", helper)
	}
	if found < 5 {
		t.Errorf("found %d diffArgs calls, want at least 5; the pattern no longer matches the source", found)
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

// Every mutating command refuses over a stopped operation, but for the few named
// as never committing, pulling, switching or merging here. repo create and connect
// commit the tree first, and finished a resolved merge or am under gitsby's message.
func TestPendingOpEveryCommitter(t *testing.T) { // [dfjzg]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "checkout", "-q", "-b", "side")
	if err := os.WriteFile(filepath.Join(clone, "f.txt"), []byte("side\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	runGit(t, clone, "add", "f.txt")
	runGit(t, clone, "commit", "-q", "-m", "side")
	runGit(t, clone, "checkout", "-q", "main")
	runGit(t, clone, "merge", "-q", "--no-ff", "--no-commit", "side")
	t.Chdir(clone)
	seen := map[string]bool{}
	for _, u := range usages {
		if u.cmd == "raw" {
			continue // handed to the tool before any of this runs
		}
		// The fewest words each takes, and with a transport repo url mutates.
		var cmd command
		settled := false
		for _, tail := range [][]string{nil, {"ssh"}, {"x", "y"}, {"x", "y", "z"}} {
			opt, got, _, err := parseArgs(append(strings.Fields(u.cmd), tail...))
			if err == nil {
				if got, err = collapseCommand(got); err == nil {
					got, err = sortCommand(got, &opt)
				}
			}
			if err == nil && (!settled || got.mutating) {
				cmd, settled = got, true
			}
			if settled && cmd.mutating {
				break
			}
		}
		if !settled {
			t.Fatalf("%s: no argument list settles", u.cmd)
		}
		if !cmd.mutating || seen[cmd.name+" "+cmd.arg] {
			continue
		}
		seen[cmd.name+" "+cmd.arg] = true
		a := newApp(newPrinter())
		a.cmd = cmd
		if err := a.enterRepo(); err != nil {
			t.Fatal(err)
		}
		err := a.refusePendingOp()
		switch {
		case pendingOpFree(cmd.name) && err != nil:
			t.Errorf("%s: refused: %v", u.cmd, err)
		case !pendingOpFree(cmd.name) && (err == nil || !strings.Contains(err.Error(), "A 'git merge' is in progress here.")):
			t.Errorf("%s: refusePendingOp = %v, want the merge named", u.cmd, err)
		}
	}
	for _, name := range []string{"repo-create", "repo-connect", "pullcom", "br-switch", "release"} {
		if pendingOpFree(name) {
			t.Errorf("%s passes over a stopped operation", name)
		}
	}
	if len(seen) < 15 {
		t.Errorf("checked %d mutating commands, want at least 15; usages no longer settles them", len(seen))
	}
}

// A stop's advice names the command that ran, and reads back as that command, for
// every one that commits or pulls. --staged stays, since a rerun without it commits
// the whole tree. cmdCommit used to name pullcom for all of them,
// which commits but doesn't push, switch or open the PR.
func TestRerunNamesTheCommand(t *testing.T) { // [dfhh2]
	settle := func(argv ...string) (command, options) {
		t.Helper()
		opt, cmd, _, err := parseArgs(argv)
		if err == nil {
			cmd, err = collapseCommand(cmd)
		}
		if err == nil {
			cmd, err = sortCommand(cmd, &opt)
		}
		if err != nil {
			t.Fatalf("%v: %v", argv, err)
		}
		return cmd, opt
	}
	for _, tc := range []struct {
		argv []string
		want string
	}{
		{[]string{"pullcom", "msg1"}, "pullcom"},
		{[]string{"update", "-m", "msg1"}, "pullcom"},
		{[]string{"sync", "msg1"}, "sync"},
		{[]string{"sync", "--staged"}, "sync --staged"},
		{[]string{"pullcom", "--staged", "-m", "msg1"}, "pullcom --staged"},
		{[]string{"br", "switch", "feat1", "--staged"}, "br switch feat1 --staged"},
		{[]string{"pr", "create", "--staged", "title1"}, "pr create --staged"},
		{[]string{"release", "--staged", "v1.2.3"}, "release v1.2.3 --staged"},
		{[]string{"br", "create", "feat1"}, "br create feat1"},
		{[]string{"branch", "new", "feat1"}, "br create feat1"},
		{[]string{"br", "hotfix", "hotfix/fix1"}, "br hotfix hotfix/fix1"},
		{[]string{"br", "switch", "feat1"}, "br switch feat1"},
		{[]string{"br", "go"}, "br switch"},
		{[]string{"br", "merge", "msg1"}, "br merge"},
		{[]string{"br", "land", "-m", "msg1"}, "br merge"},
		{[]string{"pr", "create", "title1"}, "pr create"},
		{[]string{"pr", "new", "-m", "title1"}, "pr create"},
		{[]string{"release", "v1.2.3"}, "release v1.2.3"},
		{[]string{"release"}, "release"},
		{[]string{"repo", "connect", "o/n"}, "repo connect o/n"},
		{[]string{"repo", "create", "o/n"}, "repo create o/n"},
	} {
		cmd, opt := settle(tc.argv...)
		got := (&app{cmd: cmd, opt: opt}).rerunText()
		if got != meName+" "+tc.want {
			t.Errorf("%v: rerun is %q, want %q", tc.argv, got, meName+" "+tc.want)
			continue
		}
		back, backOpt := settle(strings.Fields(got)[1:]...)
		if back.name != cmd.name || backOpt.staged != opt.staged || (cmd.name != "pullcom" && cmd.name != "sync" && cmd.name != "br-merge" && back.arg != cmd.arg) {
			t.Errorf("%v: %q reads back as %+v, not %+v", tc.argv, got, back, cmd)
		}
		if strings.Contains(got, "msg1") || strings.Contains(got, "title1") {
			t.Errorf("%v: %q carries the message", tc.argv, got)
		}
	}
}

// git's lead, as git 2.51 writes it under LC_ALL=C, with the advice on and off.
func TestSparseAddPaths(t *testing.T) { // [dfhkc]
	lead := "The following paths and/or pathspecs matched paths that exist\noutside of your sparse-checkout definition, so will not be\nupdated in the index:\n"
	cases := []struct {
		stderr string
		want   []string
	}{
		{lead + "out/new.txt\nout/sub dir/b.txt\nhint: If you intend to update such entries, try one of the following:\nhint: * Use the --sparse option.\n", []string{"out/new.txt", "out/sub dir/b.txt"}},
		{lead + "out/new.txt\n", []string{"out/new.txt"}},
		{"warning: adding embedded git repository: sub\n" + lead + "out/a.txt\r\n", []string{"out/a.txt"}},
		{"fatal: Unable to create '/r/.git/index.lock': File exists.\n", nil},
		{"", nil},
	}
	for _, c := range cases {
		if got := sparseAddPaths(c.stderr); !slices.Equal(got, c.want) {
			t.Errorf("sparseAddPaths(%q) = %q, want %q", c.stderr, got, c.want)
		}
	}
}

// A dry run's add and remove lines are what it takes, quotes and spaces in a path
// included. Anything else 'git diff' had is left out.
func TestSkippedEdits(t *testing.T) { // [dfhkn]
	dry := "add 'in/a.txt'\nremove 'in/gone.txt'\r\nadd 'in/it's here.txt'\n"
	got := skippedEdits([]string{"in/a.txt", "in/gone.txt", "in/it's here.txt", "out/o.txt"}, dry)
	if want := []string{"out/o.txt"}; !slices.Equal(got, want) {
		t.Errorf("skippedEdits = %q, want %q", got, want)
	}
	if got := skippedEdits(nil, dry); got != nil {
		t.Errorf("skippedEdits with no edits = %q, want none", got)
	}
}
