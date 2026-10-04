// An answer the run already has, or can't use, is not asked for again. Each
// check puts a stand-in for the tool first on PATH and counts its calls.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// logCalls puts a shell stand-in for tool first on PATH. It logs each call, then
// runs body, which can hand the call on to the real tool. It returns the log.
func logCalls(t *testing.T, tool, body string) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("the stand-ins are shell scripts")
	}
	dir := t.TempDir()
	logFile := filepath.Join(dir, tool+".log")
	script := "#!/bin/sh\necho \"$*\" >> '" + logFile + "'\n" + body + "\n"
	if err := os.WriteFile(filepath.Join(dir, tool), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return logFile
}

// logGit is logCalls for git, handing every call on to the real one.
func logGit(t *testing.T) string {
	t.Helper()
	gitPath, err := exec.LookPath("git")
	if err != nil {
		t.Skip("no git")
	}
	return logCalls(t, "git", `exec '`+gitPath+`' "$@"`)
}

// callsTo counts the logged calls that contain what.
func callsTo(t *testing.T, logFile, what string) int {
	t.Helper()
	data, err := os.ReadFile(logFile)
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	n := 0
	for _, line := range strings.Split(string(data), "\n") {
		if line != "" && strings.Contains(line, what) {
			n++
		}
	}
	return n
}

func TestConvertibleAsksGhOnlyForSSH(t *testing.T) { // [Erl3JkJ]
	_, clone := gitTestRepo(t)
	t.Chdir(clone)
	ghLog := logCalls(t, "gh", "exit 1")
	runGit(t, clone, "remote", "set-url", "origin", "https://github.com/acme/proj.git")
	a := newApp(newPrinter())
	a.acct.name = "acme"
	if a.convertibleToHTTPS() {
		t.Error("an https origin was offered the move to https")
	}
	if n := callsTo(t, ghLog, ""); n != 0 {
		t.Errorf("gh was asked %d times about an https origin", n)
	}
	// The stand-in does answer, where the question means something.
	runGit(t, clone, "remote", "set-url", "origin", "git@github.com:acme/proj.git")
	a = newApp(newPrinter())
	a.acct.name = "acme"
	a.convertibleToHTTPS()
	if n := callsTo(t, ghLog, "git_protocol"); n != 1 {
		t.Errorf("gh was asked %d times for its protocol on an ssh origin, want 1", n)
	}
}

func TestEnterRepoSettlesTopLevel(t *testing.T) { // [Erl3JkX]
	origin, clone := gitTestRepo(t)
	gitLog := logGit(t)
	top, err := filepath.EvalSymlinks(clone)
	if err != nil {
		t.Fatal(err)
	}
	sub := filepath.Join(clone, "sub")
	if err := os.Mkdir(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Chdir(sub)
	a := newApp(newPrinter())
	a.cmd.name = "status"
	if err := a.enterRepo(); err != nil || !a.inRepo {
		t.Fatalf("enterRepo in a work tree: inRepo %v, %v", a.inRepo, err)
	}
	if got := a.contextDir(); got != top {
		t.Errorf("contextDir() = %q, want %q", got, top)
	}
	if n := callsTo(t, gitLog, "rev-parse"); n != 1 {
		t.Errorf("rev-parse ran %d times, want 1", n)
	}
	for _, tc := range []struct{ dir, want string }{
		{origin, "bare repository"},
		{filepath.Join(clone, ".git"), "'.git' directory"},
	} {
		t.Chdir(tc.dir)
		a := newApp(newPrinter())
		a.cmd.name = "status"
		if err := a.enterRepo(); err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("enterRepo in %s: %v, want %q", tc.dir, err, tc.want)
		}
	}
	// Outside a repo the folder is the context, and git is asked once there too.
	outside := t.TempDir()
	t.Chdir(outside)
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Truncate(gitLog, 0); err != nil {
		t.Fatal(err)
	}
	a = newApp(newPrinter())
	a.cmd.name = "whoami"
	if err := a.enterRepo(); err != nil || a.inRepo {
		t.Fatalf("enterRepo outside a repo: inRepo %v, %v", a.inRepo, err)
	}
	if got := a.contextDir(); got != wd {
		t.Errorf("outside a repo, contextDir() = %q, want %q", got, wd)
	}
	if n := callsTo(t, gitLog, "rev-parse"); n != 1 {
		t.Errorf("outside a repo, rev-parse ran %d times, want 1", n)
	}
}

func TestAccountTokenAsksGitConfigOnlyWhenNeeded(t *testing.T) { // [Erl3Jkl]
	_, clone := gitTestRepo(t)
	t.Chdir(clone)
	gitLog := logGit(t)
	tokenFile := filepath.Join(t.TempDir(), "acme.token")
	if err := os.WriteFile(tokenFile, []byte("tok_acme\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	// Not a GitHub host, so gh's own store is left out and the files are all there is.
	const host = "git.example.com"
	a := newApp(newPrinter())
	a.acct.name, a.acct.ghWho = "acme", "acme"
	a.cfg.values["account.acme.tokenfile"] = tokenFile
	for range 2 {
		if token, src, file := a.accountToken(host); token != "tok_acme" || src != tokenFromFile || file != tokenFile {
			t.Fatalf("accountToken = %q, %v, %q", token, src, file)
		}
	}
	if n := callsTo(t, gitLog, "gitsby.ghTokenFile"); n != 0 {
		t.Errorf("git config was asked %d times with the account's own file answering", n)
	}
	// With no file of its own, the account falls through to git config, once a run.
	a = newApp(newPrinter())
	a.acct.name, a.acct.ghWho = "acme", "acme"
	for range 2 {
		if token, _, _ := a.accountToken(host); token != "" {
			t.Fatalf("accountToken = %q with no token anywhere", token)
		}
	}
	if n := callsTo(t, gitLog, "gitsby.ghTokenFile"); n != 1 {
		t.Errorf("git config was asked %d times, want 1", n)
	}
}

func TestFetchReadsOriginHeadOnce(t *testing.T) { // [Erl3Jkz]
	_, clone := gitTestRepo(t)
	runGit(t, clone, "remote", "set-head", "origin", "main")
	t.Chdir(clone)
	gitLog := logGit(t)
	a := newApp(newPrinter())
	a.fetchRemote()
	if got := a.defaultBranch(); got != "main" {
		t.Errorf("defaultBranch() = %q, want main", got)
	}
	if n := callsTo(t, gitLog, "symbolic-ref"); n != 1 {
		t.Errorf("origin/HEAD was read %d times, want 1", n)
	}
}
