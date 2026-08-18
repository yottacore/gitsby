// Process running. Everything goes out as an argument list - no shell between, so
// word splitting and expansion cannot happen to user values on the way to a tool.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"os"
	"os/exec"
	"strings"
)

// runOut captures a command's stdout, trimmed. Any failure is simply no output -
// the callers all treat empty as "no answer", never as an error to report.
func runOut(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(out), "\r\n")
}

func mustBeInPath(name string) {
	if _, err := exec.LookPath(name); err != nil {
		throwUsage("Not found in path: " + name)
	}
}

// runHandover runs the tool with our stdio and leaves with its exit code - the
// portable stand-in for the scripts' exec, which cannot exist on Windows.
func runHandover(name string, args []string) {
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		throwUsage("Not found in path: " + name)
	}
	os.Exit(0)
}
