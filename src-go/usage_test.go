// The command table: every placeholder defined where it appears, and nothing
// defined that the syntax doesn't show.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
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
