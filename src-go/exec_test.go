// Finding the tool 'raw' hands over to, without finding ourselves.

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
