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

func TestPullArgsFor(t *testing.T) { // [ErgA5KD]
	tests := []struct {
		upstream string
		extra    []string
		want     []string
	}{
		{"refs/remotes/origin/main", nil, []string{"merge", "--ff-only", "@{u}"}},
		{"refs/remotes/origin/feat/x", []string{"--autostash"}, []string{"merge", "--ff-only", "--autostash", "@{u}"}},
		{"refs/heads/main", nil, []string{"merge", "--ff-only", "@{u}"}},
		{"", []string{"--autostash"}, []string{"merge", "--ff-only", "--autostash", "@{u}"}},
		{"refs/remotes/up/main", nil, []string{"pull", "--ff-only"}},
		{"refs/remotes/origin2/main", []string{"--autostash"}, []string{"pull", "--ff-only", "--autostash"}},
	}
	for _, tc := range tests {
		if got := pullArgsFor(tc.upstream, tc.extra...); !slices.Equal(got, tc.want) {
			t.Errorf("pullArgsFor(%q, %q) = %q, want %q", tc.upstream, tc.extra, got, tc.want)
		}
	}
}
