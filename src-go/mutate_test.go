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
// read it, so no push.default or push refspec can add another branch to it.
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
		{"upstream by another name", [][2]string{{"branch.feat.merge", "refs/heads/up"}}, "feat", []string{"push", "origin", "HEAD:refs/heads/up"}},
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
			got := a.pushArgs()
			for _, kv := range tc.config {
				runGit(t, clone, "config", "--unset", kv[0])
			}
			runGit(t, clone, "config", "branch.feat.merge", "refs/heads/feat")
			if !slices.Equal(got, tc.want) {
				t.Errorf("pushArgs() = %q, want %q", got, tc.want)
			}
		})
	}
}
