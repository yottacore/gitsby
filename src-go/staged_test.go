// --staged on its own: the flag's reach, and reading the tree into what is
// committed and what stays.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"slices"
	"testing"
)

func TestParseArgsStaged(t *testing.T) { // [Err7CYL]
	for _, spelling := range []string{"--staged", "-staged", "--STAGED"} {
		opt, cmd, _, err := parseArgs([]string{"pullcom", spelling})
		if err != nil || !opt.staged || cmd.name != "pullcom" {
			t.Errorf("%s: staged=%v cmd=%q err=%v", spelling, opt.staged, cmd.name, err)
		}
	}
	if opt, _, _, _ := parseArgs([]string{"pullcom"}); opt.staged {
		t.Error("staged is on without the flag")
	}
}

// Every command that would commit the whole tree anyway refuses it, rather than
// sweeping in the edits it was typed to keep out.
// pr create and release refused it until 2026-10-05, and take it since.
func TestCheckStagedFlag(t *testing.T) { // [Err7CYY]
	staged := options{staged: true}
	for _, cmd := range []command{{name: "pullcom"}, {name: "sync"}, {name: "br-create"}, {name: "br-hotfix"}, {name: "br-switch"}, {name: "br-merge"},
		{name: "release"}, {name: "pr", arg: "create"}, {name: "pr", arg: "new"}, {name: "pr", arg: "Create"}} {
		if err := checkStagedFlag(cmd, staged); err != nil {
			t.Errorf("%s %s refused: %v", cmd.name, cmd.arg, err)
		}
	}
	for _, cmd := range []command{{name: "pr"}, {name: "pr", arg: "ok", arg2: "7"}, {name: "pr", arg: "7"}, {name: "repo-create"}, {name: "repo-connect"},
		{name: "status"}, {name: "br-prune"}, {name: "account-set"}} {
		if err := checkStagedFlag(cmd, staged); err == nil {
			t.Errorf("%s %s took --staged", cmd.name, cmd.arg)
		}
		if err := checkStagedFlag(cmd, options{}); err != nil {
			t.Errorf("%s %s refused with no --staged: %v", cmd.name, cmd.arg, err)
		}
	}
}

func TestParseStatusZ(t *testing.T) { // [Err7CYm]
	out := "M  staged.go\x00 M edited.go\x00MM both.go\x00A  added.go\x00AM added-then-edited.go\x00" +
		"D  gone.go\x00 D deleted-here.go\x00?? new dir/file name.txt\x00!! ignored.o\x00UU conflict.go\x00"
	split := parseStatusZ(out)
	wantStaged := []string{"staged.go", "both.go", "added.go", "added-then-edited.go", "gone.go", "conflict.go"}
	wantLeft := []string{"edited.go", "both.go", "added-then-edited.go", "deleted-here.go", "new dir/file name.txt", "conflict.go"}
	if !slices.Equal(split.staged, wantStaged) {
		t.Errorf("staged = %q, want %q", split.staged, wantStaged)
	}
	if !slices.Equal(split.left, wantLeft) {
		t.Errorf("left = %q, want %q", split.left, wantLeft)
	}
	if empty := parseStatusZ(""); len(empty.staged)+len(empty.left) != 0 {
		t.Errorf("a clean tree read as %+v", empty)
	}
}
