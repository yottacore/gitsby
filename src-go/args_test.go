// Argument parsing, on its own. None of it touches a repo, which is the point:
// the shapes that used to need a throwaway repo and a built binary to exercise
// are settled here in microseconds.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"slices"
	"strings"
	"testing"
)

func TestParseArgsPositionals(t *testing.T) { // [dbfqk]
	opt, cmd, help, err := parseArgs([]string{"repo", "clone", "https://x/y.git", "dir"})
	if err != nil || help != "" {
		t.Fatalf("err=%v help=%q", err, help)
	}
	if cmd.name != "repo" || cmd.arg != "clone" || cmd.arg2 != "https://x/y.git" || cmd.arg3 != "dir" {
		t.Errorf("positionals landed wrong: %+v", cmd)
	}
	if !opt.fetch || opt.visibility != "private" {
		t.Errorf("defaults not applied: %+v", opt)
	}
}

func TestParseArgsOptions(t *testing.T) { // [dbfqm]
	tests := []struct {
		name string
		argv []string
		want func(options) bool
	}{
		{"quiet long", []string{"-q"}, func(o options) bool { return o.quiet }},
		{"quiet as yes", []string{"--yes"}, func(o options) bool { return o.quiet }},
		{"no-fetch", []string{"--no-fetch"}, func(o options) bool { return !o.fetch }},
		{"nofetch", []string{"--nofetch"}, func(o options) bool { return !o.fetch }},
		{"public", []string{"--public"}, func(o options) bool { return o.visibility == "public" && o.sawPublic }},
		{"message split", []string{"-m", "hi there"}, func(o options) bool { return o.message == "hi there" }},
		{"message joined", []string{"--message=hi"}, func(o options) bool { return o.message == "hi" }},
		{"config joined keeps case", []string{"--config=/A/b"}, func(o options) bool { return o.configFile == "/A/b" && o.configGiven }},
		{"any-identity", []string{"--anyidentity"}, func(o options) bool { return o.anyIdentity }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			opt, _, _, err := parseArgs(tc.argv)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.want(opt) {
				t.Errorf("options not as expected: %+v", opt)
			}
		})
	}
}

// A value we are already waiting for wins over the option test - there is no
// other way to write a commit message that starts with a dash.
func TestParseArgsMessageMayLookLikeAnOption(t *testing.T) { // [dbfqn]
	opt, cmd, _, err := parseArgs([]string{"pullcom", "-m", "-Wall added"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if opt.message != "-Wall added" {
		t.Errorf("message = %q", opt.message)
	}
	if cmd.name != "pullcom" {
		t.Errorf("command = %q", cmd.name)
	}
}

func TestParseArgsRefusals(t *testing.T) { // [dbfqp]
	for _, argv := range [][]string{
		{"--offline"},
		{"--nonsense"},
		{"-m"},
		{"a", "b", "c", "d", "e", "f"},
	} {
		if _, _, _, err := parseArgs(argv); err == nil {
			t.Errorf("%v was accepted", argv)
		}
	}
}

// The tokenizer takes five positionals for 'account set <name> <key> <value>'
// alone. Every other command has to keep rejecting the fifth, which is now
// sortCommand's job rather than the tokenizer's - and the tail that does it was
// only ever checking the fourth.
func TestSortCommandRefusesFifthPositional(t *testing.T) { // [dbhgc]
	_, cmd, _, err := parseArgs([]string{"repo", "clone", "url", "dir", "extra"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	cmd, err = collapseCommand(cmd)
	if err != nil {
		t.Fatalf("collapse: %v", err)
	}
	opt := defaultOptions()
	if _, err := sortCommand(cmd, &opt); err == nil {
		t.Error("a fifth positional was accepted on 'repo clone'")
	}
}

// 'account set' is the one command that keeps all three of its shifted
// positionals, and the tail that rejects a third must not eat its value.
func TestSortCommandAccountSet(t *testing.T) { // [dbhgd]
	_, cmd, _, err := parseArgs([]string{"account", "set", "work", "host", "gitea.com"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	cmd, err = collapseCommand(cmd)
	if err != nil {
		t.Fatalf("collapse: %v", err)
	}
	opt := defaultOptions()
	got, err := sortCommand(cmd, &opt)
	if err != nil {
		t.Fatalf("sort: %v", err)
	}
	if got.name != "account-set" || got.arg != "work" || got.arg2 != "host" || got.arg3 != "gitea.com" {
		t.Errorf("got %q %q/%q/%q", got.name, got.arg, got.arg2, got.arg3)
	}
	if !got.mutating {
		t.Error("account set must be a mutating command")
	}
}

// Two words exactly: without the key it prints the syntax, and a value after it is
// refused, since the command removes every line of the key and not just one.
func TestSortCommandAccountUnset(t *testing.T) { // [dd83n]
	for _, tc := range []struct {
		argv []string
		want string
	}{
		{[]string{"account", "unset", "work", "host"}, ""},
		{[]string{"acct", "unset", "work"}, "Syntax: " + meName + " account unset"},
		{[]string{"account", "unset", "work", "path", "/srv/w"}, "(got '/srv/w' too)"},
	} {
		_, cmd, _, err := parseArgs(tc.argv)
		if err == nil {
			cmd, err = collapseCommand(cmd)
		}
		if err == nil {
			opt := defaultOptions()
			cmd, err = sortCommand(cmd, &opt)
		}
		switch {
		case tc.want == "" && (err != nil || cmd.name != "account-unset" || !cmd.mutating):
			t.Errorf("%v: name %q, mutating %v, err %v", tc.argv, cmd.name, cmd.mutating, err)
		case tc.want != "" && (err == nil || !strings.Contains(err.Error(), tc.want)):
			t.Errorf("%v: err = %v, want %q", tc.argv, err, tc.want)
		}
	}
}

func TestParseArgsHelpFromAnyPosition(t *testing.T) { // [dbfqq]
	for _, argv := range [][]string{{"--help"}, {"br", "create", "--help"}, {"-h"}} {
		if _, _, help, err := parseArgs(argv); help != "help" || err != nil {
			t.Errorf("%v: help=%q err=%v", argv, help, err)
		}
	}
}

// The information options answer from any position, as help does. A message value
// is still a message, and -v stays first-word only.
func TestParseArgsInfoFromAnyPosition(t *testing.T) { // [dd811]
	for _, tc := range []struct {
		argv []string
		want string
	}{
		{[]string{"br", "create", "x", "--version"}, "version"},
		{[]string{"status", "--about"}, "about"},
		{[]string{"sync", "--donate"}, "donate"},
		{[]string{"sync", "-m", "--about"}, ""},
	} {
		if _, _, info, err := parseArgs(tc.argv); info != tc.want || err != nil {
			t.Errorf("%v: info=%q err=%v, want %q", tc.argv, info, err, tc.want)
		}
	}
	if _, _, _, err := parseArgs([]string{"sync", "-v"}); err == nil {
		t.Error("-v after a command must be refused, not read as --version")
	}
}

func TestCollapseCommand(t *testing.T) { // [dbfqr]
	tests := []struct {
		argv []string
		want string
	}{
		{[]string{"br", "list"}, "br-list"},
		{[]string{"br"}, "br-list"},
		{[]string{"branch", "land"}, "br-merge"},
		{[]string{"br", "merge"}, "br-merge"},
		{[]string{"br", "clean"}, "br-prune"},
		{[]string{"account"}, "account-list"},
		{[]string{"acct", "apply"}, "account-apply"},
		{[]string{"repository", "new"}, "repo-create"},
		{[]string{"update"}, "pullcom"},
		{[]string{"pullc"}, "pullcom"},
		{[]string{"PULL"}, "pullcom"},
		{[]string{"whoami"}, "whoami"},
		{[]string{"who"}, "whoami"},
		{[]string{"identity"}, "whoami"},
		{[]string{"status"}, "status"},
	}
	for _, tc := range tests {
		t.Run(tc.want+"/"+tc.argv[0], func(t *testing.T) {
			_, cmd, _, err := parseArgs(tc.argv)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			got, err := collapseCommand(cmd)
			if err != nil {
				t.Fatalf("collapse: %v", err)
			}
			if got.name != tc.want {
				t.Errorf("got %q, want %q", got.name, tc.want)
			}
		})
	}
}

// The internal tokens have a hyphen precisely so they cannot be typed.
func TestCollapseCommandRefusesInternalTokens(t *testing.T) { // [dbfqs]
	for _, name := range []string{"br-merge", "repo-clone", "account-apply"} {
		if _, err := collapseCommand(command{name: name}); err == nil {
			t.Errorf("%q was accepted as typed", name)
		}
	}
}

// The noun shift is what makes 'br list extra' complain about the extra rather
// than about 'list'.
func TestSortCommandShiftedPositionals(t *testing.T) { // [dbfqt]
	_, cmd, _, err := parseArgs([]string{"br", "list", "extra"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	cmd, err = collapseCommand(cmd)
	if err != nil {
		t.Fatalf("collapse: %v", err)
	}
	opt := defaultOptions()
	if _, err := sortCommand(cmd, &opt); err == nil {
		t.Error("'br list extra' was accepted")
	}
}

func TestSortCommandMutating(t *testing.T) { // [dbfqv]
	tests := []struct {
		argv     []string
		mutating bool
	}{
		{[]string{"status"}, false},
		{[]string{"whoami"}, false},
		{[]string{"br", "list"}, false},
		{[]string{"account", "list"}, false},
		{[]string{"repo", "url"}, false},
		{[]string{"repo", "url", "https"}, true},
		{[]string{"pr"}, false},
		{[]string{"pr", "7"}, false},
		{[]string{"pr", "create"}, true},
		{[]string{"pr", "ok", "7"}, true},
		{[]string{"pullcom"}, true},
		{[]string{"br", "prune"}, true},
		{[]string{"account", "apply"}, true},
	}
	for _, tc := range tests {
		t.Run(tc.argv[0]+"/"+joinArgs(tc.argv[1:]), func(t *testing.T) {
			opt, cmd, _, err := parseArgs(tc.argv)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			if cmd, err = collapseCommand(cmd); err != nil {
				t.Fatalf("collapse: %v", err)
			}
			cmd, err = sortCommand(cmd, &opt)
			if err != nil {
				t.Fatalf("sort: %v", err)
			}
			if cmd.mutating != tc.mutating {
				t.Errorf("mutating = %v, want %v", cmd.mutating, tc.mutating)
			}
		})
	}
}

// A bare positional is the commit message when no -m was given, and -m wins when
// both are.
func TestSortCommandPositionalMessage(t *testing.T) { // [dbfqw]
	opt, cmd, _, err := parseArgs([]string{"pullcom", "typed here"})
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if cmd, err = collapseCommand(cmd); err != nil {
		t.Fatalf("collapse: %v", err)
	}
	if _, err := sortCommand(cmd, &opt); err != nil {
		t.Fatalf("sort: %v", err)
	}
	if opt.message != "typed here" {
		t.Errorf("message = %q", opt.message)
	}

	if opt, cmd, _, err = parseArgs([]string{"pullcom", "positional", "-m", "flag"}); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if cmd, err = collapseCommand(cmd); err != nil {
		t.Fatalf("collapse: %v", err)
	}
	if _, err := sortCommand(cmd, &opt); err != nil {
		t.Fatalf("sort: %v", err)
	}
	if opt.message != "flag" {
		t.Errorf("-m did not win: %q", opt.message)
	}
}

func TestScanPassthrough(t *testing.T) { // [dbfqx]
	tests := []struct {
		name     string
		argv     []string
		tool     string
		args     []string
		wantErr  bool
		wantQuie bool
	}{
		{name: "plain", argv: []string{"raw", "git", "status", "-s"}, tool: "git", args: []string{"status", "-s"}},
		{name: "gh", argv: []string{"raw", "gh", "pr", "list"}, tool: "gh", args: []string{"pr", "list"}},
		{name: "our options first", argv: []string{"-q", "raw", "git", "log"}, tool: "git", args: []string{"log"}, wantQuie: true},
		{name: "tool's own -q is the tool's", argv: []string{"raw", "git", "commit", "-q"}, tool: "git", args: []string{"commit", "-q"}},
		{name: "no raw at all", argv: []string{"status"}},
		{name: "option after raw is ours arriving late", argv: []string{"raw", "-q", "git"}, wantErr: true},
		{name: "unknown tool", argv: []string{"raw", "svn"}, wantErr: true},
		{name: "raw with nothing after it", argv: []string{"raw"}, wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			opt := defaultOptions()
			tool, args, err := scanPassthrough(tc.argv, &opt)
			if (err != nil) != tc.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tc.wantErr)
			}
			if tc.wantErr {
				return
			}
			if tool != tc.tool {
				t.Errorf("tool = %q, want %q", tool, tc.tool)
			}
			if joinArgs(args) != joinArgs(tc.args) {
				t.Errorf("args = %v, want %v", args, tc.args)
			}
			if opt.quiet != tc.wantQuie {
				t.Errorf("quiet = %v, want %v", opt.quiet, tc.wantQuie)
			}
		})
	}
}

func joinArgs(args []string) string {
	out := ""
	for _, a := range args {
		out += a + "\x00"
	}
	return out
}

func TestBorrowedNameRefusesRawToolNames(t *testing.T) { // [debe6]
	for _, name := range append(slices.Clone(rawTools), "tea-cli") {
		for _, argv0 := range []string{name, "/usr/local/bin/" + name, strings.ToUpper(name) + ".exe"} {
			err := borrowedName(argv0)
			if err == nil || !strings.Contains(err.Error(), "'gitsby raw "+name+"'") {
				t.Errorf("borrowedName(%q) = %v, want a refusal naming 'gitsby raw %s'", argv0, err, name)
			}
		}
	}
	// Any other name is fine, release asset names included.
	for _, argv0 := range []string{"gitsby", "./gitsby", "gitsby.exe", "gitsby-linux-amd64", "gitsby-windows-arm64.exe", "gitsby.test", "ghx", "git-gitsby"} {
		if err := borrowedName(argv0); err != nil {
			t.Errorf("borrowedName(%q) = %v, want nil", argv0, err)
		}
	}
}

// An option a command doesn't read is refused, never dropped. The ones that mean
// something everywhere stay valid everywhere, raw included.
func TestOptionsOnlyWhereRead(t *testing.T) { // [df4e9]
	settle := func(argv ...string) error {
		opt, cmd, _, err := parseArgs(argv)
		if err != nil {
			return err
		}
		if cmd, err = collapseCommand(cmd); err != nil {
			return err
		}
		if cmd, err = sortCommand(cmd, &opt); err != nil {
			return err
		}
		return checkOptionsUsed(typedName(cmd), opt)
	}
	for _, argv := range [][]string{
		{"status", "-m", "x"}, {"status", "--public"}, {"pullcom", "--direct"}, {"pullcom", "--private"},
		{"repo", "connect", "--public"}, {"br", "prune", "-m", "x"}, {"pr", "ok", "7", "-m", "x"}, {"pr", "--message=x"},
		{"whoami", "--staged"}, {"account", "--direct"},
	} {
		if err := settle(argv...); err == nil {
			t.Errorf("%v: took an option it doesn't read", argv)
		}
	}
	for _, argv := range [][]string{
		{"sync", "--direct"}, {"repo", "create", "o/n", "--public"}, {"repo", "connect", "-m", "x"}, {"pr", "create", "-m", "t"},
		{"release", "-m", "x"}, {"br", "switch", "-m", "x"}, {"-q", "-NoFetch", "--any-identity", "--config", "f", "account"},
		{"--no-fetch", "repo", "clone", "u"}, {"status", "-y"},
	} {
		if err := settle(argv...); err != nil {
			t.Errorf("%v: refused: %v", argv, err)
		}
	}
}

// Both parsers read one table. Every spelling goes before raw, and only the
// options with no command list get through to the tool.
func TestRawTakesTheSameOptions(t *testing.T) { // [df4ea]
	for _, spec := range optSpecs {
		for _, s := range spec.spellings {
			argv := []string{"--" + s}
			if spec.value {
				argv = append(argv, "v")
			}
			opt := defaultOptions()
			tool, _, err := scanPassthrough(append(argv, "raw", "git", "status"), &opt)
			switch {
			case spec.cmds == nil && (err != nil || tool != "git"):
				t.Errorf("--%s before raw: tool=%q err=%v", s, tool, err)
			case spec.cmds != nil && err == nil:
				t.Errorf("--%s before raw was taken and dropped", s)
			}
			if _, _, _, err := parseArgs(append(argv, "status")); err != nil {
				t.Errorf("--%s: main parser refused it: %v", s, err)
			}
		}
	}
}

// pr settles its verb with the other nouns: 'list' is the bare form, and a word
// that is neither a verb nor a number is refused as one, by name.
func TestCollapsePr(t *testing.T) { // [df4em]
	for in, want := range map[string]string{"": "", "list": "", "LIST": "", "create": "create", "new": "create", "ok": "ok", "42": "42"} {
		cmd, err := collapseCommand(command{name: "pr", arg: in})
		if err != nil || cmd.name != "pr" || cmd.arg != want {
			t.Errorf("pr %q: name=%q arg=%q err=%v, want arg %q", in, cmd.name, cmd.arg, err, want)
		}
	}
	for _, in := range []string{"foo", "view", "4x"} {
		_, err := collapseCommand(command{name: "pr", arg: in})
		if err == nil || !strings.Contains(err.Error(), "Unknown 'pr' subcommand '"+in+"'") {
			t.Errorf("pr %q: err=%v", in, err)
		}
	}
}

// '--' ends gitsby's options, as POSIX and git have it. Before it a '--' was a
// positional, so 'pullcom --' committed with the message '--'.
func TestDoubleDashEndsOptions(t *testing.T) { // [df4eq]
	opt, cmd, _, err := parseArgs([]string{"-q", "pullcom", "--", "-v bump"})
	if err != nil || cmd.name != "pullcom" || cmd.arg != "-v bump" || !opt.quiet {
		t.Errorf("pullcom -- '-v bump': cmd=%+v err=%v", cmd, err)
	}
	if _, cmd, _, err = parseArgs([]string{"pullcom", "--"}); err != nil || cmd.arg != "" {
		t.Errorf("pullcom --: arg=%q err=%v", cmd.arg, err)
	}
	if _, cmd, _, err = parseArgs([]string{"pullcom", "--", "--"}); err != nil || cmd.arg != "--" {
		t.Errorf("pullcom -- --: arg=%q err=%v", cmd.arg, err)
	}
	if opt, _, _, err = parseArgs([]string{"-m", "--", "pullcom"}); err != nil || opt.message != "--" {
		t.Errorf("-m --: the value wins, got %q err=%v", opt.message, err)
	}
	opt = defaultOptions()
	tool, args, err := scanPassthrough([]string{"-q", "--", "raw", "git", "log", "--", "x"}, &opt)
	if err != nil || tool != "git" || joinArgs(args) != joinArgs([]string{"log", "--", "x"}) {
		t.Errorf("-- raw git log -- x: tool=%q args=%v err=%v", tool, args, err)
	}
}
