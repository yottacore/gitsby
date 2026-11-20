// Batch files on PATH: cmd reads a batch file's command line again, so gitsby
// never runs one.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Each batch file on PATH is passed over for the next program, in any case of
// extension, and the refusal names them when nothing else is there. A path given
// to toolCmd that is, or PATHEXT makes, a batch file is refused too.
func TestLookToolSkipsBatch(t *testing.T) { // [dfhmj]
	batDir, cmdDir, exeDir := t.TempDir(), t.TempDir(), t.TempDir()
	bat, cmd, exe := filepath.Join(batDir, "gbtool.BAT"), filepath.Join(cmdDir, "gbtool.cmd"), filepath.Join(exeDir, "gbtool.exe")
	// Never run, so a stub does.
	for _, file := range []string{bat, cmd, exe} {
		if err := os.WriteFile(file, []byte("@echo off\r\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	sep := string(os.PathListSeparator)
	t.Setenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")

	t.Setenv("PATH", batDir+sep+cmdDir+sep+exeDir)
	hit := lookTool("gbtool")
	if !strings.EqualFold(hit.path, exe) || len(hit.batch) != 2 || !strings.EqualFold(hit.batch[0], bat) || !strings.EqualFold(hit.batch[1], cmd) {
		t.Errorf("got %q, passed over %q", hit.path, hit.batch)
	}
	if c := toolCmd("gbtool", "x"); c.Err != nil || !strings.EqualFold(c.Path, exe) {
		t.Errorf("toolCmd: Err %v, Path %q", c.Err, c.Path)
	}

	t.Setenv("PATH", batDir+sep+cmdDir)
	err := mustBeInPath("gbtool")
	if err == nil || !strings.Contains(err.Error(), "are batch files") || inPath("gbtool") || shadowed("gbtool") == nil {
		t.Errorf("only batch files on PATH: %v", err)
	}
	if c := toolCmd("gbtool", "x"); c.Err == nil {
		t.Errorf("toolCmd took %q", c.Path)
	}

	for _, given := range []string{bat, filepath.Join(cmdDir, "gbtool")} {
		if c := toolCmd(given); c.Err == nil || !strings.Contains(c.Err.Error(), "is a batch file") {
			t.Errorf("%s: Err %v", given, c.Err)
		}
	}
	if c := toolCmd(exe); c.Err != nil {
		t.Errorf("an exe path: %v", c.Err)
	}
}

// The path a user runs: a batch file first on PATH, given an argument with & and
// one with %NAME%, as a branch name can be. cmd would run what follows the & and
// expand the name, so neither may reach it.
func TestToolCmdRunsNoBatch(t *testing.T) { // [dfhmk]
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "gbtool.bat"), []byte("@echo off\r\necho got %1 %2\r\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GBTOOLMARK", "INJECTED")
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	// No space in the first, or Go's quotes would hide the & from cmd.
	out, err := toolCmd("gbtool", "x&echo.AMPRAN", "%GBTOOLMARK%").CombinedOutput()
	if err == nil || strings.Contains(string(out), "AMPRAN") || strings.Contains(string(out), "INJECTED") {
		t.Errorf("ran the batch file: err %v, output %q", err, out)
	}
}
