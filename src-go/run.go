// Process running. Everything goes out as an argument list - no shell between, so
// word splitting and expansion cannot happen to user values on the way to a tool.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
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

// runOK is the exit-code question: did it succeed at all.
func runOK(name string, args ...string) bool {
	return exec.Command(name, args...).Run() == nil
}

// runLines is runOut split into lines, empties dropped.
func runLines(name string, args ...string) []string {
	var lines []string
	for _, line := range strings.Split(runOut(name, args...), "\n") {
		if line = strings.TrimRight(line, "\r"); line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

// runInherit streams a command straight to our stdio and carries on regardless -
// for listings whose output IS the point and whose failure has nothing to add.
func runInherit(name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	_ = cmd.Run()
}

// runInheritOK is runInherit that still answers whether it worked - for the steps
// whose failure is survivable but worth a word (a remote branch somebody else
// already deleted).
func runInheritOK(name string, args ...string) bool {
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run() == nil
}

// runStep announces and runs a command verbatim, with our stdio - the scripts'
// fRun. A failing command gets a plain one-line report; the trap dump stays
// reserved for unexpected errors. Display copy is masked per argument, so a
// credentialed URL never prints its token in the announcement or the failure.
func runStep(name string, args ...string) {
	disp := maskUrl(name)
	for _, arg := range args {
		disp += " " + maskUrl(arg)
	}
	echoClean("")
	echoStatus(disp + " ...")
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		rc := 1
		if ee, ok := err.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		}
		echoClean("")
		fmt.Fprintln(os.Stderr, meName+": '"+disp+"' failed (exit "+strconv.Itoa(rc)+").")
		echoCleanForce("")
		os.Exit(1)
	}
	echoResetBlank()
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
