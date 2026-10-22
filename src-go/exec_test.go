// Finding the tools gitsby runs, without finding ourselves.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// A gh that is this binary, by link, comes before the real one on PATH and is
// passed over. So is a relative entry, which LookPath would never run.
func TestLookToolSkipsSelf(t *testing.T) { // [EtMXfI7]
	if runtime.GOOS == "windows" {
		t.Skip("needs symlinks and the exec bit")
	}
	exe, err := os.Executable()
	if err != nil {
		t.Skip("can't name the test binary:", err)
	}
	root := t.TempDir()
	link, realDir, rel := filepath.Join(root, "link"), filepath.Join(root, "realDir"), "relbin"
	for _, dir := range []string{link, realDir, filepath.Join(root, rel)} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(exe, filepath.Join(link, "gh")); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{realDir, filepath.Join(root, rel)} {
		if err := os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(root)
	sep := string(os.PathListSeparator)
	t.Setenv("PATH", rel+sep+link+sep+realDir)

	found, ours := lookTool("gh")
	if found != filepath.Join(realDir, "gh") || !slices.Equal(ours, []string{filepath.Join(link, "gh")}) {
		t.Errorf("found %q, ours %q", found, ours)
	}

	t.Setenv("PATH", link+sep+link+string(filepath.Separator))
	found, ours = lookTool("gh")
	if found != "" || len(ours) != 1 {
		t.Errorf("only ourselves on PATH: found %q, ours %q", found, ours)
	}
}

// A 'raw' that would start what a 'raw' above it already started, same tool file,
// arguments and folder, refuses before running anything, and names the tool.
// The variable is read as the run found it.
func TestRawRefusesInsideRaw(t *testing.T) { // [EtMXfJm]
	dir := t.TempDir()
	gh := filepath.Join(dir, "gh")
	if runtime.GOOS == "windows" {
		gh += ".exe"
	}
	// Never this test binary, so a regression that runs it can't start us again.
	if err := os.WriteFile(gh, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	args := []string{"auth", "status"}
	above, err := rawNest("", "gh", gh, args)
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv(rawActiveVar, above)
	a := newApp(newPrinter())
	err = a.cmdPassthrough("gh", args)
	if err == nil || !strings.Contains(err.Error(), "Looping") || !strings.Contains(err.Error(), gh) || !strings.Contains(err.Error(), rawActiveVar) {
		t.Errorf("got %v", err)
	}
}

// The chain refuses only a repeat, or anything started while 'raw' was only
// checking a tool. Other arguments, another folder or another tool file nest, as
// a hook calling 'raw git' under 'raw git commit' does.
func TestRawNestChain(t *testing.T) { // [EtOGJ79]
	t.Chdir(t.TempDir())
	chain, err := rawNest("", "git", "/bin/git", []string{"commit", "-m", "x"})
	if err != nil || len(strings.Fields(chain)) != 1 {
		t.Fatalf("first: %q, %v", chain, err)
	}
	if _, err := rawNest(chain, "git", "/bin/git", []string{"commit", "-m", "x"}); err == nil || !strings.Contains(err.Error(), "'/bin/git'") {
		t.Errorf("a repeat ran: %v", err)
	}
	// Joined differently, the same words are other arguments.
	for _, args := range [][]string{{"status"}, {"commit-m", "x"}, {"commit", "-mx"}} {
		if next, err := rawNest(chain, "git", "/bin/git", args); err != nil || len(strings.Fields(next)) != 2 {
			t.Errorf("%q refused: %q, %v", args, next, err)
		}
	}
	if _, err := rawNest(chain, "git", "/usr/local/bin/git", []string{"commit", "-m", "x"}); err != nil {
		t.Errorf("another git refused: %v", err)
	}
	if _, err := rawNest(chain+" "+rawProbing, "gh", "/bin/gh", []string{"api", "user"}); err == nil || !strings.Contains(err.Error(), "only checking") {
		t.Errorf("a raw from a probe ran: %v", err)
	}
	t.Chdir(t.TempDir())
	if _, err := rawNest(chain, "git", "/bin/git", []string{"commit", "-m", "x"}); err != nil {
		t.Errorf("another folder refused: %v", err)
	}
}

// A loop with new arguments each time stops at rawDepthMax, and says how deep.
func TestRawNestDepth(t *testing.T) { // [EtOGJ7M]
	chain := ""
	for n := range rawDepthMax {
		var err error
		if chain, err = rawNest(chain, "gh", "/bin/gh", []string{strconv.Itoa(n)}); err != nil {
			t.Fatalf("refused at %d: %v", n+1, err)
		}
	}
	_, err := rawNest(chain, "gh", "/bin/gh", []string{"last"})
	if err == nil || !strings.Contains(err.Error(), strconv.Itoa(rawDepthMax+1)+" deep") {
		t.Errorf("got %v", err)
	}
}

// Every spawn takes the same lookup: a gh that is this binary is refused rather
// than run (never Run here, since a regression would start this test binary again), the real one runs by full path under its own name, and a name with a
// path in it is left alone.
func TestToolCmdSkipsSelf(t *testing.T) { // [EtMclJC]
	if runtime.GOOS == "windows" {
		t.Skip("needs symlinks and the exec bit")
	}
	exe, err := os.Executable()
	if err != nil {
		t.Skip("can't name the test binary:", err)
	}
	root := t.TempDir()
	link, realDir := filepath.Join(root, "link"), filepath.Join(root, "realDir")
	for _, dir := range []string{link, realDir} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(exe, filepath.Join(link, "gh")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(realDir, "gh"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	t.Setenv("PATH", link)
	cmd := toolCmd("gh", "auth", "status")
	if cmd.Err == nil || !strings.Contains(cmd.Err.Error(), "is "+meName+" itself") {
		t.Errorf("only ourselves on PATH: Err %v", cmd.Err)
	}
	if inPath("gh") || mustBeInPath("gh") == nil || shadowed("tea", "gh") == nil {
		t.Error("a gh that is us counts as installed")
	}

	t.Setenv("PATH", link+string(os.PathListSeparator)+realDir)
	cmd = toolCmd("gh", "auth", "status")
	if cmd.Err != nil || cmd.Path != filepath.Join(realDir, "gh") || cmd.Args[0] != "gh" {
		t.Errorf("got Err %v, Path %q, argv[0] %q", cmd.Err, cmd.Path, cmd.Args[0])
	}

	given := filepath.Join(link, "gh")
	if cmd = toolCmd(given); cmd.Path != given || cmd.Err != nil {
		t.Errorf("a path was looked up: Path %q, Err %v", cmd.Path, cmd.Err)
	}
}

// No spawn outside exec.go, so none can skip toolCmd's lookup. A new call site
// running a tool by bare name is how 2026102111572785 came back after raw's fix.
func TestOneSpawnSite(t *testing.T) { // [EtMctyX]
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) < 10 {
		t.Fatalf("found %d sources: %v", len(files), err)
	}
	for _, file := range files {
		if file == "exec.go" || strings.HasSuffix(file, "_test.go") {
			continue
		}
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for _, call := range []string{"exec.Command(", "exec.CommandContext(", "exec.LookPath(", "os.StartProcess(", "syscall.Exec("} {
			if strings.Contains(string(src), call) {
				t.Errorf("%s calls %s; use toolCmd or findTool in exec.go", file, call)
			}
		}
	}
}
