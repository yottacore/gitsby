// The command table: every placeholder defined where it appears, and nothing
// defined that the syntax doesn't show.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// '[list]' is a word typed as it is, not a placeholder.
var placeholderRE = regexp.MustCompile(`<[^<>]+>|\[[^<>\[\]]+\]`)

func TestUsagesDefineTheirPlaceholders(t *testing.T) { // [df4ef]
	for _, u := range usages {
		if u.help == "" || u.group == "" {
			t.Errorf("%s: no help line or group", u.syntax())
		}
		if u.lines != nil {
			if !strings.Contains(strings.Join(u.lines(), "\n"), "Syntax: "+meName+" "+u.syntax()+"\n") {
				t.Errorf("%s: its own block doesn't open with its syntax", u.syntax())
			}
			continue
		}
		var names []string
		for _, d := range u.defs {
			names = append(names, d.name)
		}
		var used []string
		for _, p := range placeholderRE.FindAllString(u.args, -1) {
			if p == "[list]" {
				continue
			}
			used = append(used, p)
			if !slices.Contains(names, p) {
				t.Errorf("%s: %s isn't defined", u.syntax(), p)
			}
		}
		for _, n := range names {
			if !slices.Contains(used, n) {
				t.Errorf("%s: defines %s, which its syntax doesn't show", u.syntax(), n)
			}
		}
	}
}

// A noun's block lists each verb's placeholders once, with the verbs optional
// where the noun works bare.
func TestNounRefusal(t *testing.T) { // [df4eg]
	for noun, want := range map[string]string{
		"repo": "Syntax: " + meName + " repo <clone <url> [directory] | create <owner/name> | connect [<url> | <owner/name>] | url [https|ssh]>",
		"pr":   "Syntax: " + meName + " pr [list | <number> | create [title] | ok <number>]",
	} {
		got := nounRefusal(noun).Error()
		if !strings.HasPrefix(got, want+"\n") {
			t.Errorf("%s: got %q", noun, got)
		}
		if strings.Count(got, "\n  <url> ") > 1 {
			t.Errorf("%s: <url> defined twice", noun)
		}
	}
}

// Every command answers '<command> --help' with its own block, opening on its own
// syntax. A noun alone gets the noun's block, and anything unknown the whole screen.
func TestHelpForEveryCommand(t *testing.T) { // [df4f1]
	nouns := map[string]bool{"br": true, "account": true, "pr": true}
	for _, u := range usages {
		words := strings.Fields(u.cmd)
		switch {
		case u.cmd == "pr" && u.args == "<number>":
			words = []string{"pr", "7"}
		case nouns[u.cmd]:
			continue
		}
		block := helpFor(append(words, "--help"))
		if len(block) == 0 || block[0] != "Syntax: "+meName+" "+u.syntax() {
			t.Errorf("%v --help: got %q", words, block)
			continue
		}
		if last := block[len(block)-1]; !strings.HasPrefix(last, "  Options: -q, --no-fetch") {
			t.Errorf("%v --help: no options line, got %q", words, last)
		}
	}
	for argv, want := range map[string]string{
		"br create --help":     "Options: -q, --no-fetch, --any-identity, --config, --staged, -m.",
		"-q update -h":         "Syntax: " + meName + " pullcom [message]",
		"repo --help":          "Syntax: " + meName + " repo <clone",
		"branch -h":            "Syntax: " + meName + " br [",
		"sync --direct --help": "--direct",
	} {
		if got := strings.Join(helpFor(strings.Fields(argv)), "\n"); !strings.Contains(got, want) {
			t.Errorf("%s: want %q in %q", argv, want, got)
		}
	}
	for _, argv := range []string{"--help", "-q -h", "nosuch --help"} {
		if got := helpFor(strings.Fields(argv)); got != nil {
			t.Errorf("%s: want the whole screen, got %q", argv, got)
		}
	}
}

// A placeholder written into another message is spelled the way the table spells
// it, and never with a '|' a pasted line would hand the shell.
func TestInlinePlaceholders(t *testing.T) { // [df4f8]
	files, _ := filepath.Glob("*.go")
	bad := regexp.MustCompile(`<url \||connect <url> \||<new branch|\[msg\]|\[ver\]|\[dir\]|<o/n>`)
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") {
			continue
		}
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		for i, line := range strings.Split(string(src), "\n") {
			if bad.MatchString(line) {
				t.Errorf("%s:%d: %s", f, i+1, strings.TrimSpace(line))
			}
		}
	}
}
