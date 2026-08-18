// Output helpers. The blank-line counter is what keeps the section rhythm: repeated
// blanks collapse to one, so callers can ask for breathing room without coordinating.

// Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
// Licensed under The MIT License (MIT). Full text at:
//	https://mit-license.org/
// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"
)

var quiet = false // -q/--quiet/-y: no prompts, no banner

var wasLastEchoBlank = false

func echoResetBlank() { wasLastEchoBlank = false }

// echoClean prints a plain line; an empty one only lands when the previous line
// was not already blank.
func echoClean(s string) {
	if s != "" {
		fmt.Println(s)
		wasLastEchoBlank = false
	} else if !wasLastEchoBlank {
		fmt.Println()
		wasLastEchoBlank = true
	}
}

func echoCleanForce(s string) {
	echoResetBlank()
	echoClean(s)
}

// echoStatus prints a bracketed status line - the scripts' fEcho.
func echoStatus(s string) {
	if s != "" {
		echoClean("[ " + s + " ]")
	} else {
		echoClean("")
	}
}

// throwUsage reports an expected validation error and exits. Blank lines wrap the
// message on stdout while the message itself goes to stderr, matching the scripts.
func throwUsage(msg string) {
	if msg == "" {
		msg = "An error occurred."
	}
	echoClean("")
	fmt.Fprintln(os.Stderr, meName+": "+msg)
	echoCleanForce("")
	// The scripts' exit trap resets the blank counter and prints once more on the
	// way out, so an error ends with two blanks where success ends with one.
	echoCleanForce("")
	os.Exit(1)
}
