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

// forgetRepoState drops every answer read once and remembered. Called by each of
// the runners below that actually runs something at the user's behest, rather
// than by each writer by hand: a step we announce is exactly the thing that can
// invalidate them, and a future one gets this for free instead of having to
// remember. The plain readers don't call it - they are what fills the caches.
func forgetRepoState() {
	originUrlKnown = false
	coreSshCommandKnown = false
	currentBranchKnown = false
	hasUpstreamKnown = false
	aheadBehindKnown = false
	contextDirKnown = false
}

// runOut captures a command's stdout, trimmed. Any failure is simply no output -
// most callers treat empty as "no answer", never as an error to report.
func runOut(name string, args ...string) string {
	out, _ := runOutOK(name, args...)
	return out
}

// runOutOK is runOut that also says whether the command worked, for the few
// callers that must tell "the tool failed" apart from "the answer is nothing".
// gh in particular exits nonzero for a repo that isn't there and for a network
// that is down, and stating the first when it was the second sends you off to
// create something that already exists.
func runOutOK(name string, args ...string) (string, bool) {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return "", false
	}
	return strings.TrimRight(string(out), "\r\n"), true
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
	forgetRepoState()
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	_ = cmd.Run()
}

// runInheritRC is runInherit that reports the exit code, for the callers that
// print it. A tool that never started counts as a plain failure - the PATH check
// upstream is what catches a missing one.
func runInheritRC(name string, args ...string) int {
	forgetRepoState()
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	err := cmd.Run()
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	return 1
}

// runInheritOK is runInherit that still answers whether it worked - for the steps
// whose failure is survivable but worth a word (a remote branch somebody else
// already deleted).
func runInheritOK(name string, args ...string) bool {
	return runInheritRC(name, args...) == 0
}

// runStep announces and runs a command verbatim, with our stdio - the scripts'
// fRun. A failing command gets a plain one-line report; the trap dump stays
// reserved for unexpected errors. Display copy is masked per argument, so a
// credentialed URL never prints its token in the announcement or the failure.
func runStep(name string, args ...string) {
	forgetRepoState()
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

// runStepAs announces one thing and runs another, for the gh calls whose real
// argument list carries flags the plan never showed - echoing it verbatim would
// contradict the preview. The failure line names the command, not the arguments.
func runStepAs(announce, label, name string, args ...string) {
	echoClean("")
	echoStatus(announce + " ...")
	if rc := runInheritRC(name, args...); rc != 0 {
		echoClean("")
		fmt.Fprintln(os.Stderr, meName+": '"+label+"' failed (exit "+strconv.Itoa(rc)+").")
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
