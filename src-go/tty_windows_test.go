// The console's width comes from the console itself, with no tput.

// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
)

// Under ssh the test's own stdout is a pipe, so the console is opened by name.
// PowerShell's RawUI reads the same window by its own path, as a second opinion.
func TestTerminalWidthAsksTheConsole(t *testing.T) { // [dfng4]
	conout, err := os.OpenFile("CONOUT$", os.O_RDWR, 0)
	if err != nil {
		t.Skipf("no console here: %v", err)
	}
	t.Cleanup(func() { _ = conout.Close() }) // nothing written; nothing to lose on close
	if !isTTY(conout) {
		t.Skip("CONOUT$ isn't a console here")
	}
	cols := termCols(conout)
	if cols <= 0 {
		t.Fatalf("termCols(CONOUT$) = %d, want the window width", cols)
	}
	t.Logf("console is %d columns", cols)
	if pipe, err := os.CreateTemp(t.TempDir(), "out"); err == nil {
		if n := termCols(pipe); n != 0 {
			t.Errorf("termCols(a file) = %d, want 0", n)
		}
		_ = pipe.Close() // only read for its handle
	}
	if out, err := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", "$Host.UI.RawUI.WindowSize.Width").Output(); err == nil {
		if ps, err := strconv.Atoi(strings.TrimSpace(string(out))); err == nil && ps > 0 && ps != cols {
			t.Errorf("termCols(CONOUT$) = %d, PowerShell says %d", cols, ps)
		}
	}
	want := cols
	if want < 40 {
		want = 100
	}
	stdout := os.Stdout
	os.Stdout = conout
	got := newApp(newPrinter()).terminalWidth()
	os.Stdout = stdout
	if got != want {
		t.Errorf("terminalWidth() = %d with a %d-column console, want %d", got, cols, want)
	}
}
