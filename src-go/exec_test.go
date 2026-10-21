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

// A 'raw' started while one is already handing over refuses before it looks
// for anything, and says which variable stopped it.
func TestRawRefusesInsideRaw(t *testing.T) { // [EtMXfJm]
	t.Setenv(rawActiveVar, "/somewhere/gh")
	t.Setenv("PATH", "")
	a := newApp(newPrinter())
	err := a.cmdPassthrough("gh", []string{"auth", "status"})
	if err == nil || !strings.Contains(err.Error(), rawActiveVar) || !strings.Contains(err.Error(), "/somewhere/gh") {
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
