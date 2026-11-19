// Which pull step a branch gets. The fetch at the start of a command covers
// origin only, so only an upstream there, or a local one, can skip the second
// round trip.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"slices"
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

// A branch origin deleted, once a fetch prunes its ref, still has its upstream set,
// and git reads that as none. sync and br switch's park push would publish it again
// under the old name, so they have to see it as gone rather than as never pushed.
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
		{"local upstream deleted", "local", "sync", "", ""},
	} {
		check(tc)
	}
}
