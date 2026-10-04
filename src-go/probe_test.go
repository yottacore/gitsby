// Round trips asked ahead. Each answer has to come back to the line that reads it,
// as it stood when it was asked, and one nobody reads must not outlive the run.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// fakeTool puts a shell script called name first on PATH.
func fakeTool(t *testing.T, name, body string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("the fakes are shell scripts")
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func TestGhLoginAskedAheadAnswersForItsOwnToken(t *testing.T) { // [ErkSC3h]
	fakeTool(t, "gh", `echo "${GH_TOKEN#tok_}"`)
	t.Setenv("GH_TOKEN", "tok_first")
	a := newApp(newPrinter())
	defer a.endProbes()
	a.askGhLoginAhead()
	t.Setenv("GH_TOKEN", "tok_later")
	if got := a.ghLogin(); got != "first" {
		t.Errorf("ghLogin() = %q, want first: the token exported when it was asked", got)
	}
	if a.gh.loginAhead != nil {
		t.Error("the answer was read but is still pending")
	}
	a.askGhLoginAhead()
	if a.gh.loginAhead != nil {
		t.Error("asked again for an answer already known")
	}
}

func TestSSHLoginAskedAheadIsReadBack(t *testing.T) { // [ErkSC3v]
	fakeTool(t, "ssh", `echo "Hi bob! You've successfully authenticated."; exit 1`)
	t.Setenv("GIT_SSH_COMMAND", "ssh")
	a := newApp(newPrinter())
	defer a.endProbes()
	url := "git@github.com:a/b.git"
	a.askSSHLoginAhead(url)
	a.askSSHLoginAhead(url)
	if len(a.gh.sshAhead) != 1 {
		t.Fatalf("%d probes pending for one remote, want 1", len(a.gh.sshAhead))
	}
	if got := a.sshLogin(url); got != "bob" {
		t.Errorf("sshLogin() = %q, want bob", got)
	}
	if len(a.gh.sshAhead) != 0 {
		t.Error("the answer was read but is still pending")
	}
	if got := a.gh.sshLogins[url]; got != "bob" {
		t.Errorf("cached answer = %q, want bob", got)
	}
}

func TestEndProbesKillsAProbeNobodyRead(t *testing.T) { // [ErkSC48]
	fakeTool(t, "ssh", "exec sleep 30")
	t.Setenv("GIT_SSH_COMMAND", "ssh")
	a := newApp(newPrinter())
	url := "git@github.com:a/b.git"
	a.askSSHLoginAhead(url)
	pending := a.gh.sshAhead[url]
	started := time.Now()
	a.endProbes()
	if got := pending.wait(); got != "?" {
		t.Errorf("killed probe answered %q, want ?", got)
	}
	if waited := time.Since(started); waited > 10*time.Second {
		t.Errorf("the probe ran on for %v after the run ended", waited)
	}
}

func TestAskGhTokensAsksEachLoginOnce(t *testing.T) { // [ErkTEpz]
	asked := filepath.Join(t.TempDir(), "asked")
	fakeTool(t, "gh", `echo "$4" >> '`+asked+`'; case "$4" in two) echo tok_two ;; *) exit 1 ;; esac`)
	a := newApp(newPrinter())
	a.askGhTokens([]string{"one", "two", "one", "", "three"})
	for who, want := range map[string]string{"one": "", "two": "tok_two", "three": ""} {
		if got, known := a.gh.tokens[who]; !known || got != want {
			t.Errorf("token for %s = %q (known %v), want %q", who, got, known, want)
		}
	}
	if got := a.ghTokenFor("two"); got != "tok_two" {
		t.Errorf("ghTokenFor(two) = %q, want tok_two", got)
	}
	raw, err := os.ReadFile(asked)
	if err != nil {
		t.Fatal(err)
	}
	if lines := strings.Fields(string(raw)); len(lines) != 3 {
		t.Errorf("gh asked %d times (%v), want once per login", len(lines), lines)
	}
}
